#!/usr/bin/env bash
set -euo pipefail
umask 077

APP_NAME="VPSBox"
VPSBOX_VERSION="v1.0.0"
SCRIPT_URL="https://raw.githubusercontent.com/QXTianPing/vpsbox/main/vpsbox.sh"
SINGBOX_RELEASE_VERSION="1.13.14"
NEXTTRACE_RELEASE_VERSION="1.7.1"
CMD_PATH="/usr/local/bin/vpsbox"
CONFIG_DIR="/etc/sing-box"
CONFIG_PATH="$CONFIG_DIR/config.json"
STATE_FILE="$CONFIG_DIR/vpsbox.env"
URI_FILE="$CONFIG_DIR/vpsbox-uri.txt"
BBR_CONF="/etc/sysctl.d/99-vpsbox-bbr.conf"
JOURNALD_VPSBOX_CONF="/etc/systemd/journald.conf.d/99-vpsbox.conf"
VPSBOX_STATE_DIR="/etc/vpsbox"
CHANGE_MANIFEST="$VPSBOX_STATE_DIR/changes.env"
CHANGE_BACKUP_DIR="$VPSBOX_STATE_DIR/backups"
GAI_CONF="/etc/gai.conf"
NTP_SOURCES_BEGIN="# BEGIN VPSBOX NTP SOURCES"
NTP_SOURCES_END="# END VPSBOX NTP SOURCES"
HOSTNAME_BEGIN="# BEGIN VPSBOX HOSTNAME"
HOSTNAME_END="# END VPSBOX HOSTNAME"
SSHD_MAIN_CONF="/etc/ssh/sshd_config"
SSHD_CONFIG_DIR="/etc/ssh/sshd_config.d"
SSHD_VPSBOX_PORT_CONF="$SSHD_CONFIG_DIR/00-vpsbox-ssh-port.conf"
SSHD_VPSBOX_HARDENING_CONF="$SSHD_CONFIG_DIR/01-vpsbox-ssh-hardening.conf"
SSH_TARGET_PORT="23333"
FAIL2BAN_CONFIG_DIR="/etc/fail2ban/jail.d"
FAIL2BAN_VPSBOX_SSHD_CONF="$FAIL2BAN_CONFIG_DIR/99-vpsbox-sshd.local"
RUNTIME_DIR="/run/vpsbox"
LOCK_FILE="$RUNTIME_DIR/vpsbox.lock"
LOCK_DIR="$RUNTIME_DIR/lockdir"
LOCK_USING_FLOCK=0
LOCK_USING_DIR=0
SERVICE_NAME="sing-box"
METHOD="2022-blake3-aes-128-gcm"
PORT_MIN=10000
PORT_MAX=60000
TRACE_NAMES=(
    "北京电信" "北京联通" "北京移动"
    "上海电信" "上海联通" "上海移动"
    "广州电信" "广州联通" "广州移动"
)
TRACE_IPS=(
    "219.141.140.10" "202.106.195.68" "221.179.155.161"
    "101.95.120.109" "210.22.70.3" "183.192.160.3"
    "58.60.188.222" "210.21.196.6" "120.196.165.24"
)
TRACE_MAX_JOBS=3
REMOTE_VERSION=""
UPDATE_AVAILABLE=0

info() { echo -e "\033[1;34m[INFO]\033[0m $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $*"; }
err()  { echo -e "\033[1;31m[ERR]\033[0m $*" >&2; }

confirm_default_yes() {
    local prompt="$1" answer
    while true; do
        read -r -p "$prompt (Y/n): " answer || return 1
        case "$answer" in
            ""|Y|y) return 0 ;;
            N|n) return 1 ;;
            *) warn "请输入 y 或 n；直接回车默认 y。" ;;
        esac
    done
}

retry() {
    local max="$1"
    local delay="$2"
    local attempt=1
    local status=0

    shift 2

    while [ "$attempt" -le "$max" ]; do
        if "$@"; then
            return 0
        else
            status=$?
        fi

        if [ "$attempt" -ge "$max" ]; then
            err "命令重试 ${max} 次后仍失败：$*"
            return "$status"
        fi

        warn "命令失败，${delay} 秒后重试（${attempt}/${max}）：$*"
        sleep "$delay"
        attempt=$((attempt + 1))
    done
}

pause() {
    echo ""
    read -r -p "按回车返回主菜单..." _ || exit 0
}

run_menu_action() {
    local status
    if "$@"; then
        return 0
    else
        status=$?
    fi
    warn "操作未完成（退出码：$status），已保留当前菜单。"
    return 0
}

need_root() {
    if [ "$(id -u)" != "0" ]; then
        err "请使用 root 用户运行。"
        exit 1
    fi
}

prepare_runtime_dir() {
    if [ -L "$RUNTIME_DIR" ]; then
        err "$RUNTIME_DIR 是符号链接，已拒绝使用。"
        exit 1
    fi

    if ! mkdir -p "$RUNTIME_DIR"; then
        err "无法创建运行目录：$RUNTIME_DIR"
        exit 1
    fi

    chown root:root "$RUNTIME_DIR" 2>/dev/null || true
    chmod 700 "$RUNTIME_DIR" 2>/dev/null || true
}

is_pid() {
    [[ "${1:-}" =~ ^[0-9]+$ ]]
}

process_alive() {
    local pid="$1"

    is_pid "$pid" && kill -0 "$pid" 2>/dev/null
}

lock_metadata_value() {
    local path="$1" key="$2"
    [ -f "$path" ] || return 1
    awk -F= -v key="$key" '$1 == key { print $2; exit }' "$path" 2>/dev/null
}

process_start_ticks() {
    local pid="$1" stat
    stat="$(cat "/proc/$pid/stat" 2>/dev/null)" || return 1
    stat="${stat##*) }"
    printf '%s\n' "$stat" | awk '{print $20}'
}

process_stdin_tty() {
    local pid="$1" tty
    tty="$(readlink "/proc/$pid/fd/0" 2>/dev/null || true)"
    case "$tty" in
        /dev/pts/*|/dev/tty*) [ -c "$tty" ] && printf '%s\n' "$tty" ;;
    esac
}

lock_owner_matches() {
    local path="$1" pid="$2" recorded_start recorded_boot current_start current_boot
    process_alive "$pid" || return 1
    recorded_start="$(lock_metadata_value "$path" start_ticks || true)"
    recorded_boot="$(lock_metadata_value "$path" boot_id || true)"
    current_start="$(process_start_ticks "$pid" || true)"
    current_boot="$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || true)"
    [ -n "$recorded_start" ] && [ "$recorded_start" = "$current_start" ] &&
        [ -n "$recorded_boot" ] && [ "$recorded_boot" = "$current_boot" ]
}

old_menu_lost_terminal() {
    local path="$1" pid="$2"
    lock_owner_matches "$path" "$pid" || return 1
    [ -z "$(process_stdin_tty "$pid")" ]
}

terminate_orphaned_vpsbox_menu() {
    local pid="$1" i
    warn "检测到失去终端的旧 vpsbox 菜单（PID $pid），正在自动回收锁。"
    kill -TERM "$pid" 2>/dev/null || return 1
    for i in 1 2 3 4 5; do
        process_alive "$pid" || return 0
        sleep 1
    done
    kill -KILL "$pid" 2>/dev/null || return 1
    sleep 1
    ! process_alive "$pid"
}

cleanup_vpsbox_lock() {
    if [ "$LOCK_USING_FLOCK" = "1" ]; then
        flock -u 200 2>/dev/null || true
        exec 200>&-
        LOCK_USING_FLOCK=0
        if [ -f "$LOCK_FILE" ] && [ ! -L "$LOCK_FILE" ]; then
            : > "$LOCK_FILE"
        fi
    fi
    if [ "$LOCK_USING_DIR" = "1" ] && [ -d "$LOCK_DIR" ] && [ ! -L "$LOCK_DIR" ]; then
        rm -rf "$LOCK_DIR"
        LOCK_USING_DIR=0
    fi
}

install_lock_cleanup_traps() {
    trap cleanup_vpsbox_lock EXIT
    trap 'exit 0' HUP INT TERM QUIT
}

lock_pid_from_file() {
    local path="$1"
    local pid=""

    [ -f "$path" ] || return 1
    pid="$(awk -F= '$1 == "pid" { print $2; exit }' "$path" 2>/dev/null || true)"
    if is_pid "$pid"; then
        printf '%s\n' "$pid"
        return 0
    fi
    return 1
}

find_running_vpsbox_pid() {
    ps -eo pid=,args= 2>/dev/null |
        awk -v self="$$" -v cmd="$CMD_PATH" '
            $1 != self && index($0, cmd) { print $1; exit }
        '
}

show_process_summary() {
    local pid="$1"

    if process_alive "$pid"; then
        ps -p "$pid" -o pid=,tty=,etime=,cmd= 2>/dev/null || true
    fi
}

terminate_old_vpsbox_menu() {
    local pid="${1:-}"
    local confirm
    local i

    if ! is_pid "$pid"; then
        pid="$(find_running_vpsbox_pid || true)"
    fi

    if ! process_alive "$pid"; then
        return 1
    fi

    warn "检测到旧 vpsbox 菜单仍在运行："
    show_process_summary "$pid"
    echo ""
    read -r -p "输入 YES 结束旧菜单并继续，其他任意输入取消: " confirm
    if [ "$confirm" != "YES" ]; then
        err "检测到另一个 vpsbox 正在运行，请先退出旧菜单。"
        exit 1
    fi

    kill "$pid" 2>/dev/null || true
    for i in 1 2 3 4 5; do
        process_alive "$pid" || return 0
        sleep 1
    done

    warn "旧菜单未正常退出，正在强制结束。"
    kill -KILL "$pid" 2>/dev/null || true
    sleep 1
    process_alive "$pid" && return 1 || return 0
}

write_flock_metadata() {
    : > "$LOCK_FILE"
    {
        printf 'pid=%s\n' "$$"
        printf 'start_ticks=%s\n' "$(process_start_ticks "$$" || true)"
        printf 'boot_id=%s\n' "$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || true)"
        printf 'tty=%s\n' "$(process_stdin_tty "$$" || true)"
        printf 'started=%s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')"
    } >&200
}

write_lockdir_metadata() {
    {
        printf 'pid=%s\n' "$$"
        printf 'start_ticks=%s\n' "$(process_start_ticks "$$" || true)"
        printf 'boot_id=%s\n' "$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || true)"
        printf 'tty=%s\n' "$(process_stdin_tty "$$" || true)"
        printf 'started=%s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')"
    } > "$LOCK_DIR/pid"
}

acquire_lock() {
    local old_pid=""

    prepare_runtime_dir

    if command -v flock >/dev/null 2>&1; then
        exec 200>"$LOCK_FILE"
        if flock -n 200; then
            LOCK_USING_FLOCK=1
            write_flock_metadata
            install_lock_cleanup_traps
            return 0
        fi

        old_pid="$(lock_pid_from_file "$LOCK_FILE" || true)"
        if old_menu_lost_terminal "$LOCK_FILE" "$old_pid" && terminate_orphaned_vpsbox_menu "$old_pid"; then
            if flock -n 200; then
                LOCK_USING_FLOCK=1
                write_flock_metadata
                install_lock_cleanup_traps
                return 0
            fi
        fi
        if terminate_old_vpsbox_menu "$old_pid"; then
            if flock -n 200; then
                LOCK_USING_FLOCK=1
                write_flock_metadata
                install_lock_cleanup_traps
                return 0
            fi
            err "旧菜单已处理，但锁仍被占用，请稍后重试。"
            exit 1
        fi

        err "检测到另一个 vpsbox 正在运行，请先退出旧菜单。"
        exit 1
    fi

    if mkdir "$LOCK_DIR" 2>/dev/null; then
        write_lockdir_metadata
        LOCK_USING_DIR=1
        install_lock_cleanup_traps
        return 0
    fi

    old_pid="$(lock_pid_from_file "$LOCK_DIR/pid" || true)"
    [ -z "$old_pid" ] && old_pid="$(find_running_vpsbox_pid || true)"
    if ! process_alive "$old_pid"; then
        warn "检测到残留 vpsbox 锁，正在清理。"
        rm -rf "$LOCK_DIR"
        if mkdir "$LOCK_DIR" 2>/dev/null; then
            write_lockdir_metadata
            LOCK_USING_DIR=1
            install_lock_cleanup_traps
            return 0
        fi
    elif old_menu_lost_terminal "$LOCK_DIR/pid" "$old_pid" && terminate_orphaned_vpsbox_menu "$old_pid"; then
        rm -rf "$LOCK_DIR"
        if mkdir "$LOCK_DIR" 2>/dev/null; then
            write_lockdir_metadata
            LOCK_USING_DIR=1
            install_lock_cleanup_traps
            return 0
        fi
    elif terminate_old_vpsbox_menu "$old_pid"; then
        rm -rf "$LOCK_DIR"
        if mkdir "$LOCK_DIR" 2>/dev/null; then
            write_lockdir_metadata
            LOCK_USING_DIR=1
            install_lock_cleanup_traps
            return 0
        fi
    fi

    if ! mkdir "$LOCK_DIR" 2>/dev/null; then
        err "检测到另一个 vpsbox 正在运行，请先退出旧菜单。"
        exit 1
    fi
    write_lockdir_metadata
    LOCK_USING_DIR=1
    install_lock_cleanup_traps
}

detect_os() {
    OS="unknown"
    OS_ID=""
    OS_ID_LIKE=""

    if [ -f /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        OS_ID="${ID:-}"
        OS_ID_LIKE="${ID_LIKE:-}"
    fi

    if echo "$OS_ID $OS_ID_LIKE" | grep -qi "alpine"; then
        OS="alpine"
    elif echo "$OS_ID $OS_ID_LIKE" | grep -Eqi "debian|ubuntu"; then
        OS="debian"
    elif echo "$OS_ID $OS_ID_LIKE" | grep -Eqi "centos|rhel|fedora|rocky|almalinux"; then
        OS="redhat"
    fi
}

is_systemd() {
    command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]
}

install_command_alias() {
    chmod 755 "$CMD_PATH" 2>/dev/null || true
    ln -sf "$CMD_PATH" /usr/bin/vpsbox 2>/dev/null || true
}

ensure_curl() {
    if command -v curl >/dev/null 2>&1; then
        return 0
    fi

    info "未检测到 curl，正在安装依赖..."
    install_deps

    if command -v curl >/dev/null 2>&1; then
        return 0
    fi

    err "未找到 curl，无法继续。"
    return 1
}

download_vpsbox_script() {
    local dest="$1"
    local tmp

    ensure_curl || return 1

    mkdir -p "$(dirname "$dest")"
    if command -v mktemp >/dev/null 2>&1; then
        tmp="$(mktemp "${dest}.tmp.XXXXXX")"
    else
        tmp="${dest}.tmp.$$"
        : > "$tmp"
    fi

    if ! retry 3 2 curl -fsSL "$SCRIPT_URL" -o "$tmp"; then
        rm -f "$tmp"
        err "下载失败，请检查网络或 GitHub raw 地址。"
        return 1
    fi

    if ! bash -n "$tmp"; then
        rm -f "$tmp"
        err "下载到的脚本未通过语法检查，已保留当前版本。"
        return 1
    fi

    if ! grep -Eq '^VPSBOX_VERSION="v[0-9]+([.][0-9]+){2}"$' "$tmp"; then
        rm -f "$tmp"
        err "下载到的脚本缺少有效版本号，已保留当前版本。"
        return 1
    fi

    chmod 755 "$tmp" 2>/dev/null || true
    mv -f "$tmp" "$dest"
}

version_is_newer() {
    local candidate="${1#v}"
    local current="${2#v}"
    local candidate_part
    local current_part
    local i
    local -a candidate_parts
    local -a current_parts

    IFS=. read -r -a candidate_parts <<< "$candidate"
    IFS=. read -r -a current_parts <<< "$current"

    for i in 0 1 2; do
        candidate_part="${candidate_parts[$i]:-0}"
        current_part="${current_parts[$i]:-0}"
        [[ "$candidate_part" =~ ^[0-9]+$ ]] || return 1
        [[ "$current_part" =~ ^[0-9]+$ ]] || return 1
        if ((10#$candidate_part > 10#$current_part)); then
            return 0
        fi
        if ((10#$candidate_part < 10#$current_part)); then
            return 1
        fi
    done

    return 1
}

check_vpsbox_update_on_start() {
    local src
    local current_path
    local installed_path
    local tmp
    local remote_version

    [ -t 0 ] && [ -t 1 ] || return 0
    command -v curl >/dev/null 2>&1 || return 0

    src="${BASH_SOURCE[0]:-$0}"
    current_path="$(readlink -f "$src" 2>/dev/null || printf '%s\n' "$src")"
    installed_path="$(readlink -f "$CMD_PATH" 2>/dev/null || printf '%s\n' "$CMD_PATH")"
    [ "$current_path" = "$installed_path" ] || return 0
    [ -f "$CMD_PATH" ] || return 0

    tmp="$(mktemp "$RUNTIME_DIR/update-check.XXXXXX")" || return 0
    if ! curl -fsSL --connect-timeout 3 --max-time 8 "$SCRIPT_URL" -o "$tmp" >/dev/null 2>&1; then
        rm -f "$tmp"
        return 0
    fi

    remote_version="$(sed -n 's/^VPSBOX_VERSION="\([^"]*\)"$/\1/p' "$tmp" | head -n 1)"
    rm -f "$tmp"
    [[ "$remote_version" =~ ^v[0-9]+([.][0-9]+){2}$ ]] || return 0

    REMOTE_VERSION="$remote_version"
    if version_is_newer "$REMOTE_VERSION" "$VPSBOX_VERSION"; then
        UPDATE_AVAILABLE=1
    fi
}

vpsbox_update_notice() {
    if [ "$UPDATE_AVAILABLE" -eq 1 ]; then
        printf ' 新版本：%s（请使用菜单 8 手动更新）\n' "$REMOTE_VERSION"
    fi
}

github_release_asset() {
    local repo="$1" tag="$2" asset="$3" api url digest

    ensure_curl || return 1
    command -v jq >/dev/null 2>&1 || { err "未找到 jq，无法校验 GitHub Release 资产。"; return 1; }
    api="https://api.github.com/repos/$repo/releases/tags/$tag"
    if ! api="$(curl -fsSL --connect-timeout 8 --max-time 30 "$api")"; then
        err "无法读取 $repo 的 Release 元数据：$tag"
        return 1
    fi
    url="$(printf '%s' "$api" | jq -r --arg asset "$asset" '.assets[] | select(.name == $asset) | .browser_download_url' | head -n 1)"
    digest="$(printf '%s' "$api" | jq -r --arg asset "$asset" '.assets[] | select(.name == $asset) | .digest' | head -n 1)"
    [[ "$url" =~ ^https://github.com/ ]] || { err "未找到 Release 资产：$asset"; return 1; }
    [[ "$digest" =~ ^sha256:[0-9a-f]{64}$ ]] || { err "Release 未提供有效 SHA256：$asset"; return 1; }
    printf '%s\n%s\n' "$url" "$digest"
}

download_verified_github_asset() {
    local repo="$1" tag="$2" asset="$3" dest="$4"
    local metadata url digest actual

    metadata="$(github_release_asset "$repo" "$tag" "$asset")" || return 1
    url="$(printf '%s\n' "$metadata" | sed -n '1p')"
    digest="$(printf '%s\n' "$metadata" | sed -n '2p')"
    if ! retry 3 2 curl -fL --connect-timeout 8 --max-time 180 "$url" -o "$dest"; then
        rm -f "$dest"
        return 1
    fi
    actual="sha256:$(sha256sum "$dest" | awk '{print $1}')"
    if [ "$actual" != "$digest" ]; then
        rm -f "$dest"
        err "SHA256 校验失败：$asset"
        return 1
    fi
}

run_singbox_installer() {
    local version="${1:-$SINGBOX_RELEASE_VERSION}"
    local arch suffix asset tmp_dir tmp

    [[ "$version" =~ ^[0-9]+([.][0-9]+){2}$ ]] || { err "sing-box 版本格式无效：$version"; return 1; }

    detect_os
    case "$OS" in
        debian) arch="$(dpkg --print-architecture)"; suffix="deb" ;;
        alpine) arch="$(apk --print-arch)"; suffix="apk" ;;
        redhat) arch="$(uname -m)"; suffix="rpm" ;;
        *) err "当前系统不支持 sing-box 固定 Release 安装。"; return 1 ;;
    esac
    asset="sing-box_${version}_linux_${arch}.${suffix}"
    tmp_dir="$(mktemp -d /tmp/vpsbox-sing-box-release.XXXXXX)" || return 1
    tmp="$tmp_dir/$asset"
    info "正在下载并校验 sing-box v$version（$asset）..."
    if ! download_verified_github_asset "SagerNet/sing-box" "v$version" "$asset" "$tmp"; then
        rm -rf "$tmp_dir"
        return 1
    fi
    case "$OS" in
        debian) dpkg -i "$tmp" || { rm -rf "$tmp_dir"; return 1; } ;;
        alpine) apk add --allow-untrusted "$tmp" || { rm -rf "$tmp_dir"; return 1; } ;;
        redhat)
            if command -v dnf >/dev/null 2>&1; then dnf install -y "$tmp"; else yum install -y "$tmp"; fi || { rm -rf "$tmp_dir"; return 1; }
            ;;
    esac
    rm -rf "$tmp_dir"
    return 0
}

install_self_command() {
    local src
    src="${BASH_SOURCE[0]:-$0}"

    mkdir -p "$(dirname "$CMD_PATH")"

    case "$src" in
        /dev/fd/*|/proc/*)
            if download_vpsbox_script "$CMD_PATH"; then
                install_command_alias
                return 0
            fi
            warn "管理命令安装失败，可重新运行安装命令。"
            return 0
            ;;
    esac

    [ -f "$src" ] || return 0

    if [ "$(readlink -f "$src" 2>/dev/null || echo "$src")" != "$CMD_PATH" ]; then
        cp "$src" "$CMD_PATH" 2>/dev/null || true
        install_command_alias
    else
        install_command_alias
    fi
}

secure_config_dir() {
    local path

    if [ -L "$CONFIG_DIR" ]; then
        err "$CONFIG_DIR 是符号链接，已拒绝使用。"
        return 1
    fi

    mkdir -p "$CONFIG_DIR" || return 1
    chown root:root "$CONFIG_DIR" || return 1
    chmod 700 "$CONFIG_DIR" || return 1

    for path in "$CONFIG_PATH" "$STATE_FILE" "$URI_FILE" "${CONFIG_PATH}.bak"; do
        if [ -L "$path" ]; then
            err "$path 是符号链接，已拒绝使用。"
            return 1
        fi
    done
}

ensure_change_store() {
    [ ! -L "$VPSBOX_STATE_DIR" ] && [ ! -L "$CHANGE_BACKUP_DIR" ] && [ ! -L "$CHANGE_MANIFEST" ] || {
        err "VPSBox 变更清单路径包含符号链接，已拒绝使用。"
        return 1
    }
    mkdir -p "$CHANGE_BACKUP_DIR" || return 1
    chown root:root "$VPSBOX_STATE_DIR" "$CHANGE_BACKUP_DIR" || return 1
    chmod 700 "$VPSBOX_STATE_DIR" "$CHANGE_BACKUP_DIR" || return 1
    [ -e "$CHANGE_MANIFEST" ] || : > "$CHANGE_MANIFEST"
    chown root:root "$CHANGE_MANIFEST" && chmod 600 "$CHANGE_MANIFEST"
}

manifest_value() {
    local key="$1"
    ensure_change_store || return 1
    awk -F= -v key="$key" '$1 == key && $2 ~ /^[A-Za-z0-9_.:-]+$/ { value=$2 } END { if (value != "") print value; else exit 1 }' "$CHANGE_MANIFEST"
}

manifest_set() {
    local key="$1" value="$2" tmp
    [[ "$key" =~ ^[A-Z0-9_]+$ && "$value" =~ ^[A-Za-z0-9_.:-]+$ ]] || return 1
    ensure_change_store || return 1
    tmp="$(mktemp "$VPSBOX_STATE_DIR/.changes.XXXXXX")" || return 1
    awk -F= -v key="$key" '$1 != key { print }' "$CHANGE_MANIFEST" > "$tmp"
    printf '%s=%s\n' "$key" "$value" >> "$tmp"
    chown root:root "$tmp" && chmod 600 "$tmp" && mv -f "$tmp" "$CHANGE_MANIFEST"
}

manifest_set_once() {
    local key="$1" value="$2"
    [ -n "$(manifest_value "$key" 2>/dev/null || true)" ] || manifest_set "$key" "$value"
}

manifest_remove() {
    local key="$1" tmp
    [[ "$key" =~ ^[A-Z0-9_]+$ ]] || return 1
    ensure_change_store || return 1
    tmp="$(mktemp "$VPSBOX_STATE_DIR/.changes.XXXXXX")" || return 1
    awk -F= -v key="$key" '$1 != key { print }' "$CHANGE_MANIFEST" > "$tmp"
    chown root:root "$tmp" && chmod 600 "$tmp" && mv -f "$tmp" "$CHANGE_MANIFEST"
}

backup_change_file_once() {
    local name="$1" target="$2" state
    [[ "$name" =~ ^[A-Z0-9_]+$ ]] || return 1
    state="$(manifest_value "BACKUP_$name" 2>/dev/null || true)"
    [ -n "$state" ] && return 0
    if [ -e "$target" ]; then
        [ ! -L "$target" ] || { err "备份目标是符号链接，已拒绝：$target"; return 1; }
        cp -a "$target" "$CHANGE_BACKUP_DIR/$name" || return 1
        manifest_set "BACKUP_$name" file
    else
        manifest_set "BACKUP_$name" absent
    fi
}

mark_change_applied() {
    manifest_set "APPLIED_$1" 1
}

restore_change_file() {
    local name="$1" target="$2" state
    state="$(manifest_value "BACKUP_$name" 2>/dev/null || true)"
    case "$state" in
        file) cp -a "$CHANGE_BACKUP_DIR/$name" "$target" ;;
        absent) rm -f "$target" ;;
        *) warn "没有 $name 的可恢复备份。"; return 1 ;;
    esac
}

clear_change_tracking() {
    local name="$1"
    rm -f "$CHANGE_BACKUP_DIR/$name"
    manifest_remove "BACKUP_$name"
    manifest_remove "APPLIED_$name"
}

install_deps() {
    detect_os

    case "$OS" in
        alpine)
            retry 3 2 apk update
            retry 3 2 apk add --no-cache bash curl ca-certificates openssl jq iproute2 coreutils
            ;;
        debian)
            export DEBIAN_FRONTEND=noninteractive
            retry 3 2 apt-get update -y
            retry 3 2 apt-get install -y curl ca-certificates openssl jq iproute2 coreutils
            ;;
        redhat)
            if command -v dnf >/dev/null 2>&1; then
                retry 3 2 dnf install -y curl ca-certificates openssl jq iproute coreutils
            else
                retry 3 2 yum install -y curl ca-certificates openssl jq iproute coreutils
            fi
            ;;
        *)
            warn "未识别系统类型，跳过自动安装依赖。"
            ;;
    esac
}

singbox_installed() {
    command -v sing-box >/dev/null 2>&1
}

singbox_version() {
    if singbox_installed; then
        sing-box version 2>/dev/null | head -n1 | sed 's/^sing-box version //'
    else
        echo "-"
    fi
}

install_singbox_if_missing() {
    if singbox_installed; then
        return 0
    fi

    info "未检测到 sing-box，开始自动安装..."
    install_deps || return 1
    detect_os

    # 使用固定官方 Release 包与 GitHub 提供的 SHA256，不混用 Alpine edge/community。
    run_singbox_installer || return 1

    if ! singbox_installed; then
        err "sing-box 安装失败，请检查网络或手动安装。"
        return 1
    fi

    info "sing-box 安装完成：$(singbox_version)"
}

service_start() {
    if is_systemd; then
        retry 3 2 systemctl start "$SERVICE_NAME"
    elif [ "$OS" = "alpine" ] && command -v rc-service >/dev/null 2>&1; then
        retry 3 2 rc-service "$SERVICE_NAME" start
    else
        err "未检测到 systemd/OpenRC，无法管理服务。"
        return 1
    fi
}

service_stop() {
    if is_systemd; then
        retry 3 2 systemctl stop "$SERVICE_NAME"
    elif [ "$OS" = "alpine" ] && command -v rc-service >/dev/null 2>&1; then
        retry 3 2 rc-service "$SERVICE_NAME" stop
    else
        err "未检测到 systemd/OpenRC，无法管理服务。"
        return 1
    fi
}

service_enable() {
    if is_systemd; then
        systemctl enable "$SERVICE_NAME" >/dev/null 2>&1
    elif [ "$OS" = "alpine" ] && command -v rc-update >/dev/null 2>&1; then
        rc-update add "$SERVICE_NAME" default >/dev/null 2>&1
    else
        return 1
    fi
}

service_is_enabled() {
    if is_systemd; then
        systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null
    elif [ "$OS" = "alpine" ]; then
        [ -e "/etc/runlevels/default/$SERVICE_NAME" ] || [ -L "/etc/runlevels/default/$SERVICE_NAME" ]
    else
        return 1
    fi
}

service_disable() {
    if is_systemd; then
        systemctl disable "$SERVICE_NAME" >/dev/null 2>&1
    elif [ "$OS" = "alpine" ] && command -v rc-update >/dev/null 2>&1; then
        rc-update del "$SERVICE_NAME" default >/dev/null 2>&1
    else
        return 1
    fi
}

service_status_short() {
    if ! singbox_installed; then
        echo "未运行"
        return
    fi

    if is_systemd; then
        if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
            echo "运行中"
        else
            echo "未运行"
        fi
    elif [ "$OS" = "alpine" ] && command -v rc-service >/dev/null 2>&1; then
        if rc-service "$SERVICE_NAME" status >/dev/null 2>&1; then
            echo "运行中"
        else
            echo "未运行"
        fi
    else
        echo "未知"
    fi
}

service_is_running() {
    [ "$(service_status_short)" = "运行中" ]
}

singbox_config_pids() {
    local proc pid exe
    local -a args

    for proc in /proc/[0-9]*; do
        [ -r "$proc/cmdline" ] || continue
        pid="${proc##*/}"
        [ "$pid" != "$$" ] || continue
        exe="$(readlink "$proc/exe" 2>/dev/null || true)"
        [ "${exe##*/}" = "sing-box" ] || continue
        mapfile -d '' -t args < "$proc/cmdline" 2>/dev/null || true
        [ "${#args[@]}" -ge 4 ] || continue
        if [ "${args[1]}" = "run" ] && [ "${args[2]}" = "-c" ] && [ "${args[3]}" = "$CONFIG_PATH" ]; then
            printf '%s\n' "$pid"
        fi
    done
}

stop_singbox_config_processes() {
    local pids pid i

    pids="$(singbox_config_pids)"
    [ -n "$pids" ] || return 0
    warn "检测到使用 $CONFIG_PATH 的残留 sing-box 进程，正在停止：$(echo "$pids" | tr '\n' ' ')"
    while read -r pid; do
        [ -n "$pid" ] && kill -TERM "$pid" 2>/dev/null || true
    done <<< "$pids"
    for i in 1 2 3 4 5; do
        [ -z "$(singbox_config_pids)" ] && return 0
        sleep 1
    done
    pids="$(singbox_config_pids)"
    while read -r pid; do
        [ -n "$pid" ] && kill -KILL "$pid" 2>/dev/null || true
    done <<< "$pids"
    sleep 1
    [ -z "$(singbox_config_pids)" ]
}

restart_singbox_cleanly() {
    service_stop 2>/dev/null || true
    stop_singbox_config_processes || {
        err "旧 sing-box 进程无法停止，已拒绝启动新实例。"
        return 1
    }
    service_start
}

show_service_status() {
    if is_systemd; then
        systemctl status "$SERVICE_NAME" --no-pager || true
    elif [ "$OS" = "alpine" ] && command -v rc-service >/dev/null 2>&1; then
        rc-service "$SERVICE_NAME" status || true
    else
        warn "未检测到 systemd/OpenRC。"
    fi
}

show_logs() {
    if is_systemd; then
        journalctl -u "$SERVICE_NAME" -f
    elif [ "$OS" = "alpine" ]; then
        tail -f /var/log/sing-box.log /var/log/sing-box.err 2>/dev/null || true
    else
        warn "未检测到可用日志方式。"
    fi
}

is_loopback_listen_addr() {
    local addr="$1"

    case "$addr" in
        127.*|::1|localhost|ip6-localhost)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

show_ports_security_group() {
    if ! command -v ss >/dev/null 2>&1; then
        err "未找到 ss 命令，无法查看端口。"
        return 1
    fi

    local public_file
    local local_file
    local suggest_file
    local proto
    local state
    local local_addr
    local proc_info
    local addr
    local port
    local proto_upper
    local proc_name

    public_file="$(mktemp)"
    local_file="$(mktemp)"
    suggest_file="$(mktemp)"

    while read -r proto state _recvq _sendq local_addr _peer_addr proc_info; do
        case "$state" in
            LISTEN|UNCONN) ;;
            *) continue ;;
        esac

        port="${local_addr##*:}"
        [[ "$port" =~ ^[0-9]+$ ]] || continue

        addr="${local_addr%:*}"
        addr="${addr#\[}"
        addr="${addr%\]}"

        proto_upper="${proto^^}"
        proc_name="-"
        if [[ "${proc_info:-}" =~ \"([^\"]+)\" ]]; then
            proc_name="${BASH_REMATCH[1]}"
        fi

        if is_loopback_listen_addr "$addr"; then
            printf '%-5s %-8s %s\n' "$proto_upper" "$port" "$proc_name" >> "$local_file"
        else
            printf '%-5s %-8s %s\n' "$proto_upper" "$port" "$proc_name" >> "$public_file"
            printf '%s %s\n' "$proto_upper" "$port" >> "$suggest_file"
        fi
    done < <(ss -H -tulpn 2>/dev/null || true)

    cat <<EOF
========================================
 端口与安全组建议
========================================
公网监听，需要安全组放行：
EOF
    if [ -s "$public_file" ]; then
        sort -u "$public_file"
    else
        echo "无"
    fi

    cat <<EOF

本机监听，无需安全组放行：
EOF
    if [ -s "$local_file" ]; then
        sort -u "$local_file"
    else
        echo "无"
    fi

    cat <<EOF

建议入站放行：
EOF
    if [ -s "$suggest_file" ]; then
        sort -u -k1,1 -k2,2n "$suggest_file"
    else
        echo "无"
    fi

    cat <<EOF
ICMP 可选

建议出站：
ALL
========================================
EOF

    rm -f "$public_file" "$local_file" "$suggest_file"
}

node_exists() {
    [ -f "$CONFIG_PATH" ] && [ ! -L "$CONFIG_PATH" ] && load_state >/dev/null 2>&1
}

state_file_is_secure() {
    local owner
    local mode

    [ -f "$STATE_FILE" ] || return 1
    [ ! -L "$STATE_FILE" ] || return 1
    owner="$(stat -c '%u' "$STATE_FILE" 2>/dev/null)" || return 1
    mode="$(stat -c '%a' "$STATE_FILE" 2>/dev/null)" || return 1
    [ "$owner" = "0" ] || return 1
    [[ "$mode" =~ ^[0-7]{3,4}$ ]] || return 1
    (( (8#$mode & 8#022) == 0 ))
}

load_state() {
    local key
    local value
    local domain=""
    local name=""
    local port=""
    local password=""
    local method=""
    local protocol="shadowsocks"
    local uuid=""
    local flow=""
    local reality_server_name=""
    local reality_public_key=""
    local reality_short_id=""
    local fingerprint=""
    local seen_keys=""

    state_file_is_secure || return 1

    while IFS='=' read -r key value; do
        case "$key" in
            ""|'#'*) continue ;;
            DOMAIN|NAME|PORT|PASSWORD|METHOD|PROTOCOL|UUID|FLOW|REALITY_SERVER_NAME|REALITY_PUBLIC_KEY|REALITY_SHORT_ID|FINGERPRINT)
                case " $seen_keys " in
                    *" $key "*) return 1 ;;
                esac
                seen_keys="$seen_keys $key"
                ;;
            *) return 1 ;;
        esac
        case "$key" in
            DOMAIN) domain="$value" ;;
            NAME) name="$value" ;;
            PORT) port="$value" ;;
            PASSWORD) password="$value" ;;
            METHOD) method="$value" ;;
            PROTOCOL) protocol="$value" ;;
            UUID) uuid="$value" ;;
            FLOW) flow="$value" ;;
            REALITY_SERVER_NAME) reality_server_name="$value" ;;
            REALITY_PUBLIC_KEY) reality_public_key="$value" ;;
            REALITY_SHORT_ID) reality_short_id="$value" ;;
            FINGERPRINT) fingerprint="$value" ;;
        esac
    done < "$STATE_FILE"

    is_valid_node_host "$domain" || return 1
    [ -n "$name" ] && [ "$(sanitize_name "$name")" = "$name" ] || return 1
    [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ] || return 1
    case "$protocol" in
        shadowsocks)
            [[ "$password" =~ ^[A-Za-z0-9_+/=-]+$ ]] || return 1
            [ "$method" = "$METHOD" ] || return 1
            ;;
        vless-reality)
            [[ "$uuid" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]] || return 1
            [ "$flow" = "xtls-rprx-vision" ] || return 1
            is_domain_name "$reality_server_name" || return 1
            [[ "$reality_public_key" =~ ^[A-Za-z0-9_-]{40,60}$ ]] || return 1
            [[ "$reality_short_id" =~ ^[0-9A-Fa-f]{16}$ ]] || return 1
            [ "$fingerprint" = "chrome" ] || return 1
            ;;
        *) return 1 ;;
    esac

    DOMAIN="$domain"
    NAME="$name"
    PORT="$port"
    PASSWORD="$password"
    METHOD="$method"
    PROTOCOL="$protocol"
    UUID="$uuid"
    FLOW="$flow"
    REALITY_SERVER_NAME="$reality_server_name"
    REALITY_PUBLIC_KEY="$reality_public_key"
    REALITY_SHORT_ID="$reality_short_id"
    FINGERPRINT="$fingerprint"
}

save_state() {
    local domain="$1"
    local name="$2"
    local port="$3"
    local password="$4"

    secure_config_dir || return 1
    {
        printf 'PROTOCOL=shadowsocks\n'
        printf 'DOMAIN=%s\n' "$domain"
        printf 'NAME=%s\n' "$name"
        printf 'PORT=%s\n' "$port"
        printf 'PASSWORD=%s\n' "$password"
        printf 'METHOD=%s\n' "$METHOD"
    } > "$STATE_FILE"
    chown root:root "$STATE_FILE" || return 1
    chmod 600 "$STATE_FILE" || return 1
}

save_vless_reality_state() {
    local domain="$1" name="$2" port="$3" uuid="$4" server_name="$5" public_key="$6" short_id="$7"

    secure_config_dir || return 1
    {
        printf 'PROTOCOL=vless-reality\n'
        printf 'DOMAIN=%s\n' "$domain"
        printf 'NAME=%s\n' "$name"
        printf 'PORT=%s\n' "$port"
        printf 'UUID=%s\n' "$uuid"
        printf 'FLOW=xtls-rprx-vision\n'
        printf 'REALITY_SERVER_NAME=%s\n' "$server_name"
        printf 'REALITY_PUBLIC_KEY=%s\n' "$public_key"
        printf 'REALITY_SHORT_ID=%s\n' "$short_id"
        printf 'FINGERPRINT=chrome\n'
    } > "$STATE_FILE"
    chown root:root "$STATE_FILE" || return 1
    chmod 600 "$STATE_FILE" || return 1
}

normalize_host() {
    local host="$1"
    local no_colons
    local colon_count

    host="$(sanitize_paste_input "$host")"
    host="$(echo "$host" | tr -d '[:space:]')"
    host="${host#http://}"
    host="${host#https://}"
    host="${host%%/*}"
    host="${host%%\?*}"
    host="${host%%#*}"

    if [[ "$host" == \[*\]* ]]; then
        host="${host#\[}"
        host="${host%%\]*}"
    else
        no_colons="${host//:/}"
        colon_count=$((${#host} - ${#no_colons}))
        if [ "$colon_count" -eq 1 ] && [[ "${host##*:}" =~ ^[0-9]+$ ]]; then
            host="${host%:*}"
        fi
    fi

    host="${host%.}"
    echo "$host"
}

sanitize_paste_input() {
    local value="$1"

    value="${value//$'\033[200~'/}"
    value="${value//$'\033[201~'/}"
    value="$(printf '%s' "$value" | LC_ALL=C tr -d '\000-\037\177')"
    value="${value#\[200~}"
    value="${value%\[201~}"
    printf '%s' "$value"
}

is_ipv4_address() {
    local ip="$1"
    local IFS=.
    local -a parts
    local part

    [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    read -r -a parts <<< "$ip"
    [ "${#parts[@]}" -eq 4 ] || return 1

    for part in "${parts[@]}"; do
        [[ "$part" =~ ^[0-9]+$ ]] || return 1
        ((10#$part <= 255)) || return 1
    done
}

is_ipv6_address_basic() {
    local ip="$1"
    local no_colons
    local colon_count
    local without_double
    local double_count
    local check_ip
    local maybe_v4
    local rest
    local chunk

    [[ "$ip" == *:* ]] || return 1
    [[ "$ip" =~ ^[0-9A-Fa-f:.]+$ ]] || return 1
    [[ "$ip" != *:::* ]] || return 1
    [[ "$ip" != :[^:]* ]] || return 1
    [[ "$ip" != *[^:]: ]] || return 1

    without_double="${ip//::/}"
    double_count=$(((${#ip} - ${#without_double}) / 2))
    [ "$double_count" -le 1 ] || return 1

    maybe_v4="${ip##*:}"
    check_ip="$ip"
    if [[ "$maybe_v4" == *.* ]]; then
        is_ipv4_address "$maybe_v4" || return 1
        check_ip="${ip%:*}:0"
    fi

    no_colons="${check_ip//:/}"
    colon_count=$((${#check_ip} - ${#no_colons}))
    [ "$colon_count" -ge 2 ] || return 1
    [ "$colon_count" -le 7 ] || return 1
    if [[ "$check_ip" != *::* ]] && [ "$colon_count" -ne 7 ]; then
        return 1
    fi

    rest="$check_ip"
    while [[ "$rest" == *:* ]]; do
        chunk="${rest%%:*}"
        if [ -n "$chunk" ] && [[ ! "$chunk" =~ ^[0-9A-Fa-f]{1,4}$ ]]; then
            return 1
        fi
        rest="${rest#*:}"
    done
    [ -z "$rest" ] || [[ "$rest" =~ ^[0-9A-Fa-f]{1,4}$ ]]
}

is_ip_address() {
    local host="$1"

    if command -v python3 >/dev/null 2>&1; then
        python3 - "$host" <<'PY' >/dev/null 2>&1
import ipaddress
import sys

try:
    ipaddress.ip_address(sys.argv[1])
except ValueError:
    sys.exit(1)
PY
        return $?
    fi

    is_ipv4_address "$host" || is_ipv6_address_basic "$host"
}

is_domain_name() {
    local domain="$1"
    local IFS=.
    local -a labels
    local label
    local last

    [ "${#domain}" -ge 4 ] || return 1
    [ "${#domain}" -le 253 ] || return 1
    [[ "$domain" == *.* ]] || return 1
    [[ "$domain" =~ ^[A-Za-z0-9.-]+$ ]] || return 1
    [[ "$domain" != *..* ]] || return 1

    read -r -a labels <<< "$domain"
    [ "${#labels[@]}" -ge 2 ] || return 1

    for label in "${labels[@]}"; do
        [ -n "$label" ] || return 1
        [ "${#label}" -le 63 ] || return 1
        [[ "$label" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$ ]] || return 1
    done

    last="${labels[${#labels[@]}-1]}"
    [ "${#last}" -ge 2 ] || return 1
    [[ "$last" =~ [A-Za-z] ]]
}

is_valid_node_host() {
    local host="$1"
    is_ip_address "$host" || is_domain_name "$host"
}

is_repeated_node_host() {
    local host="${1,,}"
    local length="${#1}"
    local half

    [ "$length" -ge 8 ] || return 1
    ((length % 2 == 0)) || return 1
    half=$((length / 2))
    [ "${host:0:half}" = "${host:half:half}" ]
}

uri_host() {
    local host="$1"
    if [[ "$host" == *:* && "$host" != \[*\] ]]; then
        echo "[$host]"
    else
        echo "$host"
    fi
}

sanitize_name() {
    local raw="$1"
    local cleaned
    cleaned="$(printf "%s" "$raw" | sed 's/[^A-Za-z0-9._-]/-/g')"
    cleaned="$(printf "%s" "$cleaned" | sed 's/--*/-/g; s/^-//; s/-$//')"
    [ -n "$cleaned" ] && echo "$cleaned" || echo "ss"
}

default_name_for_host() {
    local host="$1"
    local first="${host%%.*}"
    first="$(sanitize_name "$first")"
    echo "ss-$first"
}

url_encode_userinfo() {
    printf "%s" "$1" \
        | sed -e 's/%/%25/g' \
              -e 's/:/%3A/g' \
              -e 's/+/%2B/g' \
              -e 's/\//%2F/g' \
              -e 's/=/%3D/g'
}

generate_link() {
    load_state
    local host
    local encoded
    host="$(uri_host "${DOMAIN:-}")"
    case "${PROTOCOL:-shadowsocks}" in
        shadowsocks)
            encoded="$(url_encode_userinfo "${METHOD:-$METHOD}:${PASSWORD:-}")"
            echo "ss://${encoded}@${host}:${PORT:-0}#${NAME:-ss}"
            ;;
        vless-reality)
            echo "vless://${UUID}@${host}:${PORT}?encryption=none&flow=${FLOW}&security=reality&sni=${REALITY_SERVER_NAME}&fp=${FINGERPRINT}&pbk=${REALITY_PUBLIC_KEY}&sid=${REALITY_SHORT_ID}&type=tcp#${NAME}"
            ;;
        *) return 1 ;;
    esac
}

write_uri_file() {
    secure_config_dir || return 1
    generate_link > "$URI_FILE"
    chown root:root "$URI_FILE" || return 1
    chmod 600 "$URI_FILE" || return 1
}

backup_node_files() {
    local backup_dir="$1"
    mkdir -p "$backup_dir" || return 1

    if [ -f "$CONFIG_PATH" ]; then cp -a "$CONFIG_PATH" "$backup_dir/config.json" || return 1; fi
    if [ -f "$STATE_FILE" ]; then cp -a "$STATE_FILE" "$backup_dir/state.env" || return 1; fi
    if [ -f "$URI_FILE" ]; then cp -a "$URI_FILE" "$backup_dir/node-uri.txt" || return 1; fi
    if [ -f /etc/systemd/system/sing-box.service ]; then cp -a /etc/systemd/system/sing-box.service "$backup_dir/sing-box.service" || return 1; fi
    if [ -f /etc/init.d/sing-box ]; then cp -a /etc/init.d/sing-box "$backup_dir/openrc-sing-box" || return 1; fi

    if service_is_running; then
        echo "1" > "$backup_dir/service-running"
    else
        echo "0" > "$backup_dir/service-running"
    fi
    if service_is_enabled; then
        echo "1" > "$backup_dir/service-enabled"
    else
        echo "0" > "$backup_dir/service-enabled"
    fi
}

restore_node_files() {
    local backup_dir="$1"
    local was_running="0"
    local was_enabled="0"

    [ -f "$backup_dir/service-running" ] && was_running="$(cat "$backup_dir/service-running")"
    [ -f "$backup_dir/service-enabled" ] && was_enabled="$(cat "$backup_dir/service-enabled")"

    warn "创建失败，正在恢复旧配置..."
    service_stop 2>/dev/null || true
    stop_singbox_config_processes 2>/dev/null || true

    rm -f "$CONFIG_PATH" "$STATE_FILE" "$URI_FILE"
    [ -f "$backup_dir/config.json" ] && cp -a "$backup_dir/config.json" "$CONFIG_PATH"
    [ -f "$backup_dir/state.env" ] && cp -a "$backup_dir/state.env" "$STATE_FILE"
    [ -f "$backup_dir/node-uri.txt" ] && cp -a "$backup_dir/node-uri.txt" "$URI_FILE"

    if is_systemd; then
        if [ -f "$backup_dir/sing-box.service" ]; then
            cp -a "$backup_dir/sing-box.service" /etc/systemd/system/sing-box.service
        else
            rm -f /etc/systemd/system/sing-box.service
        fi
        systemctl daemon-reload 2>/dev/null || true
    fi

    if [ "$OS" = "alpine" ]; then
        if [ -f "$backup_dir/openrc-sing-box" ]; then
            cp -a "$backup_dir/openrc-sing-box" /etc/init.d/sing-box
        else
            rm -f /etc/init.d/sing-box
        fi
    fi

    if [ "$was_enabled" = "1" ]; then
        service_enable 2>/dev/null || warn "旧配置已恢复，但 sing-box 开机启动状态恢复失败。"
    else
        service_disable 2>/dev/null || true
    fi

    if [ "$was_running" = "1" ] && [ -f "$CONFIG_PATH" ] && singbox_installed; then
        if restart_singbox_cleanly 2>/dev/null; then
            info "旧配置与运行状态已恢复。"
        else
            warn "旧配置已恢复，但 sing-box 运行状态恢复失败，请手动检查服务。"
        fi
    else
        info "已恢复到创建前状态。"
    fi

    rm -rf "$backup_dir"
}

cleanup_node_backup() {
    local backup_dir="$1"
    rm -rf "$backup_dir"
}

port_in_use() {
    local port="$1"
    ss -tuln 2>/dev/null | awk '{print $5}' | grep -Eq "[:.]${port}$"
}

wait_for_port_listener() {
    local port="$1" i
    for i in 1 2 3 4 5; do
        port_in_use "$port" && return 0
        sleep 1
    done
    return 1
}

ipv6_listen_available() {
    [ -r /proc/net/if_inet6 ] || return 1
    [ -s /proc/net/if_inet6 ] || return 1

    if [ -r /proc/sys/net/ipv6/conf/all/disable_ipv6 ] &&
        [ "$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null)" = "1" ]; then
        return 1
    fi
}

ipv6_bindv6only_value() {
    local value

    value="$(sysctl -n net.ipv6.bindv6only 2>/dev/null || cat /proc/sys/net/ipv6/bindv6only 2>/dev/null || echo 0)"
    case "$value" in
        1) echo "1" ;;
        *) echo "0" ;;
    esac
}

listen_mode() {
    if ipv6_listen_available; then
        if [ "$(ipv6_bindv6only_value)" = "1" ]; then
            echo "dual"
        else
            echo "ipv6"
        fi
    else
        echo "ipv4"
    fi
}

random_port() {
    local port
    local i
    for i in $(seq 1 100); do
        port="$(shuf -i "${PORT_MIN}-${PORT_MAX}" -n 1 2>/dev/null || echo $((RANDOM % (PORT_MAX - PORT_MIN + 1) + PORT_MIN)))"
        if ! port_in_use "$port" && ! port_is_effective_ssh_port "$port"; then
            echo "$port"
            return 0
        fi
    done
    err "连续 100 次未找到可用随机端口。"
    return 1
}

is_valid_port() {
    [[ "${1:-}" =~ ^[0-9]+$ ]] && [ "$1" -ge 1 ] && [ "$1" -le 65535 ]
}

port_is_effective_ssh_port() {
    local port="$1" ports
    ports="$(ssh_effective_ports_csv 2>/dev/null || true)"
    case ",$ports," in
        *",$port,"*) return 0 ;;
        *) return 1 ;;
    esac
}

choose_node_port() {
    local existing_port="${1:-}" input confirm

    while true; do
        if [ -n "$existing_port" ]; then
            printf '请输入节点端口（留空自动随机；当前端口 %s 可保留）: ' "$existing_port" >&2
        else
            printf '请输入节点端口（1-65535，留空自动随机）: ' >&2
        fi
        read -r input || return 1
        if [ -z "$input" ]; then
            random_port
            return $?
        fi
        if ! is_valid_port "$input"; then
            err "端口必须是 1-65535 的整数。"
            continue
        fi
        if port_is_effective_ssh_port "$input"; then
            err "端口 $input 是当前 SSH 生效端口，不能用于节点。"
            continue
        fi
        if [ "$input" != "$existing_port" ] && port_in_use "$input"; then
            err "端口 $input 已被占用，请更换。"
            continue
        fi
        if [ "$input" -lt 1024 ]; then
            read -r -p "端口 $input 属于特权端口，确认使用？请输入 YES：" confirm
            [ "$confirm" = "YES" ] || continue
        fi
        printf '%s\n' "$input"
        return 0
    done
}

random_password() {
    if singbox_installed; then
        sing-box generate rand --base64 16 2>/dev/null | tr -d '\n\r' && return 0
    fi

    openssl rand -base64 16 2>/dev/null | tr -d '\n\r' && return 0
    head -c 16 /dev/urandom | base64 | tr -d '\n\r'
}

write_shadowsocks_inbound_json() {
    local tag="$1"
    local listen="$2"
    local port="$3"
    local password="$4"
    local suffix="${5:-}"

    cat <<EOF
    {
      "type": "shadowsocks",
      "tag": "$tag",
      "listen": "$listen",
      "listen_port": $port,
      "method": "$METHOD",
      "password": "$password"
    }$suffix
EOF
}

write_config() {
    local port="$1"
    local password="$2"
    local mode

    secure_config_dir || return 1
    if [ -f "$CONFIG_PATH" ]; then
        cp "$CONFIG_PATH" "${CONFIG_PATH}.bak" || return 1
        chown root:root "${CONFIG_PATH}.bak" || return 1
        chmod 600 "${CONFIG_PATH}.bak" || return 1
    fi

    mode="$(listen_mode)"

    case "$mode" in
        ipv6)
            info "监听地址：::（IPv4/IPv6 双栈）"
            ;;
        dual)
            info "监听地址：0.0.0.0 + ::（系统启用了 IPv6-only 监听）"
            ;;
        *)
            info "监听地址：0.0.0.0"
            ;;
    esac

    cat > "$CONFIG_PATH" <<EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
EOF
    case "$mode" in
        ipv6)
            write_shadowsocks_inbound_json "vpsbox-in" "::" "$port" "$password" >> "$CONFIG_PATH"
            ;;
        dual)
            write_shadowsocks_inbound_json "vpsbox-in-ipv4" "0.0.0.0" "$port" "$password" "," >> "$CONFIG_PATH"
            write_shadowsocks_inbound_json "vpsbox-in-ipv6" "::" "$port" "$password" >> "$CONFIG_PATH"
            ;;
        *)
            write_shadowsocks_inbound_json "vpsbox-in" "0.0.0.0" "$port" "$password" >> "$CONFIG_PATH"
            ;;
    esac

    cat >> "$CONFIG_PATH" <<EOF
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ]
}
EOF
    chown root:root "$CONFIG_PATH" || return 1
    chmod 600 "$CONFIG_PATH" || return 1

    sing-box check -c "$CONFIG_PATH" >/dev/null
}

write_vless_reality_inbound_json() {
    local tag="$1" listen="$2" port="$3" uuid="$4" server_name="$5" private_key="$6" short_id="$7" suffix="${8:-}"

    cat <<EOF
    {
      "type": "vless",
      "tag": "$tag",
      "listen": "$listen",
      "listen_port": $port,
      "users": [
        {
          "name": "vpsbox",
          "uuid": "$uuid",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "$server_name",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "$server_name",
            "server_port": 443
          },
          "private_key": "$private_key",
          "short_id": ["$short_id"]
        }
      }
    }$suffix
EOF
}

write_vless_reality_config() {
    local port="$1" uuid="$2" server_name="$3" private_key="$4" short_id="$5" mode

    secure_config_dir || return 1
    if [ -f "$CONFIG_PATH" ]; then
        cp "$CONFIG_PATH" "${CONFIG_PATH}.bak" || return 1
        chown root:root "${CONFIG_PATH}.bak" || return 1
        chmod 600 "${CONFIG_PATH}.bak" || return 1
    fi
    mode="$(listen_mode)"
    case "$mode" in
        ipv6) info "监听地址：::（IPv4/IPv6 双栈）" ;;
        dual) info "监听地址：0.0.0.0 + ::（系统启用了 IPv6-only 监听）" ;;
        *) info "监听地址：0.0.0.0" ;;
    esac

    cat > "$CONFIG_PATH" <<EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
EOF
    case "$mode" in
        ipv6) write_vless_reality_inbound_json "vpsbox-vless-reality-in" "::" "$port" "$uuid" "$server_name" "$private_key" "$short_id" >> "$CONFIG_PATH" ;;
        dual)
            write_vless_reality_inbound_json "vpsbox-vless-reality-in-ipv4" "0.0.0.0" "$port" "$uuid" "$server_name" "$private_key" "$short_id" "," >> "$CONFIG_PATH"
            write_vless_reality_inbound_json "vpsbox-vless-reality-in-ipv6" "::" "$port" "$uuid" "$server_name" "$private_key" "$short_id" >> "$CONFIG_PATH"
            ;;
        *) write_vless_reality_inbound_json "vpsbox-vless-reality-in" "0.0.0.0" "$port" "$uuid" "$server_name" "$private_key" "$short_id" >> "$CONFIG_PATH" ;;
    esac
    cat >> "$CONFIG_PATH" <<EOF
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ]
}
EOF
    chown root:root "$CONFIG_PATH" || return 1
    chmod 600 "$CONFIG_PATH" || return 1
    sing-box check -c "$CONFIG_PATH" >/dev/null
}

generate_reality_keypair() {
    local output private_key public_key
    output="$(sing-box generate reality-keypair 2>/dev/null)" || return 1
    private_key="$(printf '%s\n' "$output" | awk -F': *' '/^PrivateKey:/ {print $2; exit}')"
    public_key="$(printf '%s\n' "$output" | awk -F': *' '/^PublicKey:/ {print $2; exit}')"
    [[ "$private_key" =~ ^[A-Za-z0-9_-]{40,60}$ ]] || return 1
    [[ "$public_key" =~ ^[A-Za-z0-9_-]{40,60}$ ]] || return 1
    printf '%s\n%s\n' "$private_key" "$public_key"
}

check_reality_server() {
    local server_name="$1"
    is_domain_name "$server_name" || return 1
    resolve_host_ips "$server_name" | grep -q . || return 1
    if command -v openssl >/dev/null 2>&1; then
        timeout 12 openssl s_client -connect "${server_name}:443" -servername "$server_name" </dev/null >/dev/null 2>&1 || return 1
    fi
}

setup_service() {
    local bin
    bin="$(command -v sing-box)"

    if is_systemd; then
        cat > /etc/systemd/system/sing-box.service <<EOF
[Unit]
Description=Sing-box Proxy Server
Documentation=https://sing-box.sagernet.org
After=network.target nss-lookup.target
Wants=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$CONFIG_DIR
ExecStart=$bin run -c $CONFIG_PATH
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=10s
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
        retry 3 2 systemctl daemon-reload || return 1
        service_enable || return 1
        return 0
    elif [ "$OS" = "alpine" ] && command -v rc-service >/dev/null 2>&1; then
        cat > /etc/init.d/sing-box <<EOF
#!/sbin/openrc-run
name="sing-box"
description="Sing-box Proxy Server"
command="$bin"
command_args="run -c $CONFIG_PATH"
command_background="yes"
pidfile="/run/sing-box.pid"
output_log="/var/log/sing-box.log"
error_log="/var/log/sing-box.err"
supervisor=supervise-daemon
supervise_daemon_args="--respawn-max 0 --respawn-delay 5"

depend() {
    need net
}
EOF
        chmod +x /etc/init.d/sing-box || return 1
        service_enable || return 1
        return 0
    else
        err "未检测到 systemd/OpenRC，无法创建服务。"
        return 1
    fi
}

create_or_rebuild_node() {
    local backup_dir
    local existing_port=""
    backup_dir="$(mktemp -d /tmp/vpsbox-node-backup.XXXXXX)" || return 1
    if ! backup_node_files "$backup_dir"; then
        cleanup_node_backup "$backup_dir"
        err "备份当前节点失败，已取消重建。"
        return 1
    fi

    if node_exists; then
        existing_port="$PORT"
        warn "检测到已有节点。"
        read -r -p "是否覆盖重建？(y/N): " confirm
        [[ "$confirm" =~ ^[Yy]$ ]] || { cleanup_node_backup "$backup_dir"; info "已取消。"; return 0; }
    fi

    if ! install_singbox_if_missing; then
        cleanup_node_backup "$backup_dir"
        err "sing-box 安装失败，未创建新节点。"
        return 1
    fi

    local input_host
    local domain
    local default_name
    local input_name
    local name
    local port
    local password

    while true; do
        read -r -p "请输入节点域名或 IP：" input_host
        domain="$(normalize_host "$input_host")"
        if [ -z "$domain" ]; then
            err "节点域名或 IP 不能为空，请重新输入。"
            continue
        fi
        if ! is_valid_node_host "$domain"; then
            err "格式不正确，请输入类似 sb.637892.xyz、1.2.3.4 或 2001:db8::1。"
            continue
        fi
        if is_repeated_node_host "$domain"; then
            err "检测到节点地址可能被重复粘贴：$domain"
            err "请只输入一次域名或 IP。"
            continue
        fi
        info "已识别节点连接地址：$domain"
        break
    done

    default_name="$(default_name_for_host "$domain")"
    while true; do
        read -r -p "请输入节点名称，留空默认 ${default_name}：" input_name
        input_name="$(sanitize_paste_input "$input_name")"
        if [ -n "$input_name" ] && [[ "${input_name,,}" == "${domain,,}"* ]]; then
            err "检测到节点名称包含连接地址前缀，可能是粘贴残留：$input_name"
            err "请重新输入节点名称。"
            continue
        fi
        name="$(sanitize_name "${input_name:-$default_name}")"
        info "已识别节点名称：$name"
        break
    done

    if ! port="$(choose_node_port "$existing_port")"; then
        cleanup_node_backup "$backup_dir"
        err "节点端口选择失败，未创建新节点。"
        return 1
    fi
    info "节点端口：$port"

    cat <<EOF
----------------------------------------
 请确认节点信息
 协议：SS 2022
 连接地址：$domain
 连接端口：$port
 节点名称：$name
----------------------------------------
EOF
    if ! confirm_default_yes "确认无误并创建？"; then
        cleanup_node_backup "$backup_dir"
        info "已取消，未修改当前节点。"
        return 0
    fi

    info "正在自动生成随机强密码..."
    password="$(random_password)"

    info "加密方式：$METHOD"
    info "正在写入配置..."
    if ! write_config "$port" "$password"; then
        restore_node_files "$backup_dir"
        err "配置检查失败，未创建新节点。"
        return 1
    fi

    if ! save_state "$domain" "$name" "$port" "$password"; then
        restore_node_files "$backup_dir"
        err "状态文件写入失败，未创建新节点。"
        return 1
    fi

    if ! write_uri_file; then
        restore_node_files "$backup_dir"
        err "节点链接写入失败，未创建新节点。"
        return 1
    fi

    if ! setup_service; then
        restore_node_files "$backup_dir"
        err "服务配置失败，未创建新节点。"
        return 1
    fi
    info "正在启动 sing-box 服务..."
    if ! restart_singbox_cleanly; then
        restore_node_files "$backup_dir"
        err "sing-box 启动失败，未创建新节点。"
        return 1
    fi
    if ! service_is_running || ! wait_for_port_listener "$port"; then
        restore_node_files "$backup_dir"
        err "sing-box 未保持运行或节点端口未监听，未创建新节点。"
        return 1
    fi

    cleanup_node_backup "$backup_dir"

    info "创建完成，节点链接如下："
    view_node_link
}

create_vless_reality_node() {
    local backup_dir existing_port="" confirm input_host domain default_name input_name name port
    local input_sni server_name uuid short_id private_key public_key
    local -a keypair

    backup_dir="$(mktemp -d /tmp/vpsbox-node-backup.XXXXXX)" || return 1
    if ! backup_node_files "$backup_dir"; then
        cleanup_node_backup "$backup_dir"
        err "备份当前节点失败，已取消重建。"
        return 1
    fi

    if node_exists; then
        existing_port="$PORT"
        warn "检测到已有 ${PROTOCOL:-shadowsocks} 节点。"
        read -r -p "创建 VLESS Reality 将替换当前节点，是否继续？(y/N): " confirm
        [[ "$confirm" =~ ^[Yy]$ ]] || { cleanup_node_backup "$backup_dir"; info "已取消。"; return 0; }
    fi

    if ! install_singbox_if_missing; then
        cleanup_node_backup "$backup_dir"
        err "sing-box 安装失败，未创建新节点。"
        return 1
    fi

    while true; do
        read -r -p "请输入节点连接地址（域名或 IP）：" input_host
        domain="$(normalize_host "$input_host")"
        if ! is_valid_node_host "$domain"; then
            err "格式不正确，请输入类似 sb.example.com、1.2.3.4 或 2001:db8::1。"
            continue
        fi
        if is_repeated_node_host "$domain"; then
            err "检测到节点地址可能被重复粘贴：$domain"
            err "请只输入一次域名或 IP。"
            continue
        fi
        info "已识别节点连接地址：$domain"
        break
    done

    default_name="$(default_name_for_host "$domain")"
    default_name="vless-${default_name#ss-}"
    while true; do
        read -r -p "请输入节点名称，留空默认 ${default_name}：" input_name
        input_name="$(sanitize_paste_input "$input_name")"
        if [ -n "$input_name" ] && [[ "${input_name,,}" == "${domain,,}"* ]]; then
            err "检测到节点名称包含连接地址前缀，可能是粘贴残留：$input_name"
            err "请重新输入节点名称。"
            continue
        fi
        name="$(sanitize_name "${input_name:-$default_name}")"
        info "已识别节点名称：$name"
        break
    done

    while true; do
        read -r -p "请输入 Reality 目标域名/SNI：" input_sni
        server_name="$(normalize_host "$input_sni")"
        if ! is_domain_name "$server_name"; then
            err "Reality 目标必须是有效域名，不能使用 IP 地址。"
            continue
        fi
        info "正在检查 Reality 目标的 DNS 与 TLS 443 可达性..."
        if ! check_reality_server "$server_name"; then
            err "目标域名无法解析或 TLS 443 不可达，请更换。"
            continue
        fi
        break
    done

    if ! port="$(choose_node_port "$existing_port")"; then
        cleanup_node_backup "$backup_dir"
        err "节点端口选择失败，未创建新节点。"
        return 1
    fi
    info "节点端口：$port"

    cat <<EOF
----------------------------------------
 请确认节点信息
 协议：VLESS Reality
 连接地址：$domain
 连接端口：$port
 Reality 目标：${server_name}:443
 节点名称：$name
----------------------------------------
EOF
    if ! confirm_default_yes "确认无误并创建？"; then
        cleanup_node_backup "$backup_dir"
        info "已取消，未修改当前节点。"
        return 0
    fi

    uuid="$(sing-box generate uuid 2>/dev/null | tr -d '\r\n')"
    if [[ ! "$uuid" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]]; then
        cleanup_node_backup "$backup_dir"
        err "UUID 生成失败，未创建新节点。"
        return 1
    fi
    mapfile -t keypair < <(generate_reality_keypair) || true
    if [ "${#keypair[@]}" -ne 2 ]; then
        cleanup_node_backup "$backup_dir"
        err "Reality 密钥生成失败，未创建新节点。"
        return 1
    fi
    private_key="${keypair[0]}"
    public_key="${keypair[1]}"
    short_id="$(sing-box generate rand 8 --hex 2>/dev/null | tr -d '\r\n')"
    if [[ ! "$short_id" =~ ^[0-9A-Fa-f]{16}$ ]]; then
        cleanup_node_backup "$backup_dir"
        err "Reality Short ID 生成失败，未创建新节点。"
        return 1
    fi

    info "正在写入 VLESS Reality 配置..."
    if ! write_vless_reality_config "$port" "$uuid" "$server_name" "$private_key" "$short_id"; then
        restore_node_files "$backup_dir"
        err "配置检查失败，未创建新节点。"
        return 1
    fi
    if ! save_vless_reality_state "$domain" "$name" "$port" "$uuid" "$server_name" "$public_key" "$short_id"; then
        restore_node_files "$backup_dir"
        err "状态文件写入失败，未创建新节点。"
        return 1
    fi
    if ! write_uri_file || ! setup_service; then
        restore_node_files "$backup_dir"
        err "节点链接或服务配置失败，未创建新节点。"
        return 1
    fi
    info "正在启动 sing-box 服务..."
    if ! restart_singbox_cleanly || ! service_is_running || ! wait_for_port_listener "$port"; then
        restore_node_files "$backup_dir"
        err "sing-box 未保持运行或节点端口未监听，未创建新节点。"
        return 1
    fi
    cleanup_node_backup "$backup_dir"
    info "创建完成，节点链接如下："
    view_node_link
}

view_node_link() {
    if ! node_exists; then
        warn "当前没有已创建的节点。"
        return 0
    fi

    load_state
    write_uri_file

    if [ "$PROTOCOL" = "vless-reality" ]; then
        cat <<EOF
========================================
 当前 VLESS Reality 节点
========================================
 节点地址：${DOMAIN}:${PORT}
 Reality SNI：${REALITY_SERVER_NAME}
 流控：${FLOW}
----------------------------------------
 链接：
 $(cat "$URI_FILE")
========================================
EOF
        return 0
    fi

    cat <<EOF
========================================
 当前 SS 节点
========================================
 节点地址：${DOMAIN}:${PORT}
 加密方式：${METHOD}
 密码：${PASSWORD}
----------------------------------------
 链接：
 $(cat "$URI_FILE")
========================================
EOF
}

delete_node() {
    local node_port

    if ! node_exists; then
        warn "当前没有已创建的节点。"
        return 0
    fi
    load_state || {
        err "节点状态文件不安全或内容无效，已拒绝删除。"
        return 1
    }
    node_port="$PORT"

    read -r -p "确认删除当前 ${PROTOCOL:-shadowsocks} 节点？sing-box 服务将停止。(y/N): " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { info "已取消。"; return 0; }

    service_stop 2>/dev/null || warn "服务管理器未能正常停止 sing-box，将继续检查 VPSBox 配置对应的进程。"
    if ! stop_singbox_config_processes; then
        err "残留 sing-box 进程无法停止，已保留节点配置。"
        return 1
    fi
    sleep 1
    if service_is_running; then
        err "sing-box 服务仍在运行，已保留节点配置。"
        return 1
    fi
    if port_in_use "$node_port"; then
        err "节点端口 $node_port 仍在监听，已保留节点配置。"
        return 1
    fi
    if ! service_disable; then
        warn "无法禁用 sing-box 开机启动，请手动检查服务状态。"
    fi
    rm -f "$CONFIG_PATH" "$STATE_FILE" "$URI_FILE"
    info "当前节点已删除，sing-box 服务已停止并尝试禁用开机启动。"
}

update_singbox() {
    local binary_path backup_dir backup_binary old_version
    local was_active=0 was_enabled=0

    if ! singbox_installed; then
        warn "当前未安装 sing-box，已取消更新。"
        info "如需安装 sing-box，请先创建节点或启动服务。"
        return 0
    fi

    binary_path="$(command -v sing-box)"
    old_version="$(singbox_version)"
    [[ "$old_version" =~ ^[0-9]+([.][0-9]+){2}$ ]] || { err "无法识别当前 sing-box 版本，已取消更新。"; return 1; }
    backup_dir="$(mktemp -d /tmp/vpsbox-sing-box-update.XXXXXX)" || return 1
    backup_binary="$backup_dir/sing-box"
    cp -a "$binary_path" "$backup_binary" || { rm -rf "$backup_dir"; err "备份当前 sing-box 二进制失败，已取消更新。"; return 1; }

    if service_is_running; then
        was_active=1
    fi
    if is_systemd && systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null; then
        was_enabled=1
    fi

    install_deps || return 1
    info "正在更新 sing-box..."
    if ! run_singbox_installer; then
        rm -rf "$backup_dir"
        return 1
    fi

    if node_exists; then
        if ! sing-box check -c "$CONFIG_PATH" >/dev/null; then
            err "当前节点配置未通过新版 sing-box 检查，正在恢复旧二进制。"
            if ! run_singbox_installer "$old_version"; then
                cp -a "$backup_binary" "$binary_path" || err "恢复旧二进制失败：$backup_binary"
            fi
            rm -rf "$backup_dir"
            return 1
        fi
        if ! setup_service || ! restart_singbox_cleanly || ! service_is_running; then
            err "新版 sing-box 未能正常启动，正在恢复旧二进制。"
            service_stop 2>/dev/null || true
            if ! run_singbox_installer "$old_version" && ! cp -a "$backup_binary" "$binary_path"; then
                err "恢复旧版 sing-box 失败：$backup_binary"
                rm -rf "$backup_dir"
                return 1
            fi
            if [ "$was_enabled" -eq 1 ]; then service_enable || true; else service_disable || true; fi
            if [ "$was_active" -eq 1 ] && ! service_start; then
                err "旧版 sing-box 已恢复，但服务未能重新启动。"
                rm -rf "$backup_dir"
                return 1
            fi
            rm -rf "$backup_dir"
            return 1
        fi
    fi

    rm -rf "$backup_dir"
    info "更新完成：$(singbox_version)"
}

update_vpsbox() {
    local backup="${CMD_PATH}.previous"

    info "正在下载最新 vpsbox 脚本..."
    if [ -f "$CMD_PATH" ]; then
        cp -a "$CMD_PATH" "$backup" || {
            err "备份当前 vpsbox 脚本失败，已取消更新。"
            return 1
        }
        chmod 700 "$backup" || return 1
    fi

    download_vpsbox_script "$CMD_PATH" || return 1
    install_command_alias

    info "vpsbox 已更新；旧版本备份：$backup"
    info "正在重新打开新版管理面板..."
    exec "$CMD_PATH"
}

bbr_state() {
    local cc
    cc="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "")"
    [ "$cc" = "bbr" ] && echo "已启用" || echo "未启用"
}

fq_state() {
    local qdisc
    qdisc="$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "")"
    if [ "$qdisc" = "fq" ]; then
        echo "已启用"
    elif [ -n "$qdisc" ]; then
        echo "未启用（当前：$qdisc）"
    else
        echo "未启用"
    fi
}

ipv4_priority_state() {
    if [ -f "$GAI_CONF" ] &&
        grep -Eq '^[[:space:]]*precedence[[:space:]]+::ffff:0:0/96[[:space:]]+100([[:space:]]|$)' "$GAI_CONF"; then
        echo "已启用"
    else
        echo "未启用"
    fi
}

fail2ban_installed() {
    command -v fail2ban-client >/dev/null 2>&1
}

fail2ban_install_state() {
    fail2ban_installed && echo "已安装" || echo "未安装"
}

fail2ban_service_state() {
    if ! fail2ban_installed; then
        echo "未运行"
        return
    fi

    if is_systemd; then
        if systemctl is-active --quiet fail2ban 2>/dev/null; then
            echo "运行中"
        else
            echo "未运行"
        fi
    elif [ "$OS" = "alpine" ] && command -v rc-service >/dev/null 2>&1; then
        if rc-service fail2ban status >/dev/null 2>&1; then
            echo "运行中"
        else
            echo "未运行"
        fi
    else
        echo "未知"
    fi
}

fail2ban_sshd_state() {
    local configured_ports
    local effective_ports

    if ! fail2ban_installed; then
        echo "未启用"
        return
    fi

    if ! fail2ban-client status sshd >/dev/null 2>&1; then
        echo "未启用"
        return
    fi

    configured_ports="$(awk -F= '/^[[:space:]]*port[[:space:]]*=/ {
        value=$2
        gsub(/[[:space:]]/, "", value)
        print value
        exit
    }' "$FAIL2BAN_VPSBOX_SSHD_CONF" 2>/dev/null || true)"
    effective_ports="$(ssh_effective_ports_csv || true)"
    if [ -n "$effective_ports" ] && [ "$configured_ports" = "$effective_ports" ]; then
        echo "已启用"
    else
        echo "端口未同步"
    fi
}

chrony_service_name() {
    detect_os
    case "$OS" in
        debian) echo "chrony" ;;
        redhat) echo "chronyd" ;;
        *) echo "chrony" ;;
    esac
}

chrony_conf_path() {
    detect_os
    case "$OS" in
        redhat) echo "/etc/chrony.conf" ;;
        *) echo "/etc/chrony/chrony.conf" ;;
    esac
}

ntp_sync_state() {
    local svc

    if ! is_systemd; then
        echo "不支持"
        return
    fi

    svc="$(chrony_service_name)"
    if ! command -v chronyc >/dev/null 2>&1 &&
        ! systemctl list-unit-files "${svc}.service" 2>/dev/null | grep -q "^${svc}\\.service"; then
        echo "未安装"
        return
    fi

    if ! systemctl is-active --quiet "$svc" 2>/dev/null; then
        echo "未运行"
        return
    fi

    if command -v chronyc >/dev/null 2>&1 &&
        chronyc tracking 2>/dev/null | grep -Eq '^Leap status[[:space:]]*:[[:space:]]*Normal'; then
        echo "已同步"
    else
        echo "运行中"
    fi
}

remove_vpsbox_ntp_block() {
    local file="$1"

    [ -f "$file" ] || return 0
    sed -i "/^# BEGIN VPSBOX NTP SOURCES$/,/^# END VPSBOX NTP SOURCES$/d" "$file"
}

write_chrony_sources() {
    local conf
    local source_file="/etc/chrony/sources.d/vpsbox.sources"

    conf="$(chrony_conf_path)"
    if [ ! -f "$conf" ]; then
        err "未找到 chrony 配置文件：$conf"
        return 1
    fi

    if grep -Eq '^[[:space:]]*sourcedir[[:space:]]+/etc/chrony/sources\.d([[:space:]]|$)' "$conf"; then
        mkdir -p /etc/chrony/sources.d
        cat > "$source_file" <<EOF
pool time.cloudflare.com iburst maxsources 4
pool pool.ntp.org iburst maxsources 4
EOF
        remove_vpsbox_ntp_block "$conf"
        info "已写入 NTP 源：$source_file"
    else
        remove_vpsbox_ntp_block "$conf"
        cat >> "$conf" <<EOF

$NTP_SOURCES_BEGIN
pool time.cloudflare.com iburst maxsources 4
pool pool.ntp.org iburst maxsources 4
$NTP_SOURCES_END
EOF
        rm -f "$source_file" 2>/dev/null || true
        info "已写入 NTP 源：$conf"
    fi
}

show_chrony_permission_hint() {
    local svc="$1"
    local logs

    logs="$(journalctl -u "$svc" -n 30 --no-pager 2>/dev/null || true)"
    if echo "$logs" | grep -Eqi 'adjtimex|Operation not permitted'; then
        warn "检测到 chrony 无权限调整系统时间。"
        warn "当前可能是 LXC/OpenVZ 容器 VPS，实例内无法自行校时，请依赖宿主机 NTP 或联系服务商。"
    else
        warn "chrony 未正常启动，可执行以下命令查看原因："
        warn "journalctl -u $svc -n 50 --no-pager"
    fi
}

enable_ntp_sync() {
    local svc
    local active_state
    local enabled_state
    local sources_output
    local tracking_output
    local conf source_file backup_dir
    local chrony_was_active=0 chrony_was_enabled=0
    local timesyncd_exists=0 timesyncd_was_active=0 timesyncd_was_enabled=0

    detect_os
    if ! is_systemd; then
        err "未检测到 systemd，无法自动配置 chrony。"
        return 1
    fi

    info "正在安装 chrony..."
    case "$OS" in
        debian)
            export DEBIAN_FRONTEND=noninteractive
            retry 3 2 apt-get update -y || return 1
            if ! retry 3 2 apt-get install -y chrony; then
                show_chrony_permission_hint "$(chrony_service_name)"
                return 1
            fi
            ;;
        redhat)
            if command -v dnf >/dev/null 2>&1; then
                if ! retry 3 2 dnf install -y chrony; then
                    show_chrony_permission_hint "$(chrony_service_name)"
                    return 1
                fi
            else
                if ! retry 3 2 yum install -y chrony; then
                    show_chrony_permission_hint "$(chrony_service_name)"
                    return 1
                fi
            fi
            ;;
        alpine)
            err "Alpine 暂不支持自动配置 chrony，请手动使用 apk/rc-service 配置。"
            return 1
            ;;
        *)
            err "未识别系统类型，无法自动配置 chrony。"
            return 1
            ;;
    esac

    svc="$(chrony_service_name)"
    conf="$(chrony_conf_path)"
    source_file="/etc/chrony/sources.d/vpsbox.sources"
    backup_change_file_once NTP_CONF "$conf" || { err "记录 chrony 原配置失败，已取消修改。"; return 1; }
    backup_change_file_once NTP_SOURCES "$source_file" || { err "记录 NTP 源原配置失败，已取消修改。"; return 1; }
    backup_dir="$(mktemp -d /tmp/vpsbox-chrony.XXXXXX)" || return 1
    cp -a "$conf" "$backup_dir/chrony.conf" || { rm -rf "$backup_dir"; err "备份 chrony 配置失败，已取消。"; return 1; }
    if [ -e "$source_file" ] || [ -L "$source_file" ]; then
        cp -a "$source_file" "$backup_dir/vpsbox.sources" || { rm -rf "$backup_dir"; err "备份 NTP 源配置失败，已取消。"; return 1; }
        : > "$backup_dir/source-existed"
    fi
    if systemctl is-active --quiet "$svc" 2>/dev/null; then chrony_was_active=1; fi
    if systemctl is-enabled --quiet "$svc" 2>/dev/null; then chrony_was_enabled=1; fi
    if systemctl list-unit-files systemd-timesyncd.service 2>/dev/null | grep -q '^systemd-timesyncd\.service'; then
        timesyncd_exists=1
        if systemctl is-active --quiet systemd-timesyncd 2>/dev/null; then timesyncd_was_active=1; fi
        if systemctl is-enabled --quiet systemd-timesyncd 2>/dev/null; then timesyncd_was_enabled=1; fi
    fi
    manifest_set_once NTP_CHRONY_ACTIVE "$([ "$chrony_was_active" -eq 1 ] && echo active || echo inactive)" || return 1
    manifest_set_once NTP_CHRONY_ENABLED "$([ "$chrony_was_enabled" -eq 1 ] && echo enabled || echo disabled)" || return 1
    manifest_set_once NTP_TIMESYNCD_ACTIVE "$([ "$timesyncd_was_active" -eq 1 ] && echo active || echo inactive)" || return 1
    manifest_set_once NTP_TIMESYNCD_ENABLED "$([ "$timesyncd_was_enabled" -eq 1 ] && echo enabled || echo disabled)" || return 1
    info "chrony 服务名：$svc"

    systemctl stop "$svc" 2>/dev/null || true
    if ! write_chrony_sources; then
        cp -a "$backup_dir/chrony.conf" "$conf"
        if [ -f "$backup_dir/source-existed" ]; then cp -a "$backup_dir/vpsbox.sources" "$source_file"; else rm -f "$source_file"; fi
        [ "$chrony_was_active" -eq 1 ] && systemctl start "$svc" 2>/dev/null || true
        rm -rf "$backup_dir"
        return 1
    fi

    info "正在启用 chrony 并设置开机自启..."
    if ! systemctl enable --now "$svc"; then
        err "chrony 启动失败，正在恢复原 NTP 配置。"
        systemctl stop "$svc" 2>/dev/null || true
        cp -a "$backup_dir/chrony.conf" "$conf"
        if [ -f "$backup_dir/source-existed" ]; then cp -a "$backup_dir/vpsbox.sources" "$source_file"; else rm -f "$source_file"; fi
        if [ "$chrony_was_enabled" -eq 1 ]; then systemctl enable "$svc" 2>/dev/null || true; else systemctl disable "$svc" 2>/dev/null || true; fi
        [ "$chrony_was_active" -eq 1 ] && systemctl start "$svc" 2>/dev/null || true
        rm -rf "$backup_dir"
        show_chrony_permission_hint "$svc"
        return 1
    fi

    sleep 2
    if ! systemctl is-active --quiet "$svc" 2>/dev/null; then
        err "chrony 未保持运行，正在恢复原 NTP 配置。"
        systemctl stop "$svc" 2>/dev/null || true
        cp -a "$backup_dir/chrony.conf" "$conf"
        if [ -f "$backup_dir/source-existed" ]; then cp -a "$backup_dir/vpsbox.sources" "$source_file"; else rm -f "$source_file"; fi
        if [ "$chrony_was_enabled" -eq 1 ]; then systemctl enable "$svc" 2>/dev/null || true; else systemctl disable "$svc" 2>/dev/null || true; fi
        [ "$chrony_was_active" -eq 1 ] && systemctl start "$svc" 2>/dev/null || true
        rm -rf "$backup_dir"
        show_chrony_permission_hint "$svc"
        return 1
    fi

    if [ "$timesyncd_exists" -eq 1 ]; then
        info "chrony 已确认运行，正在停用 systemd-timesyncd，避免多个 NTP 客户端并存..."
        if ! systemctl disable --now systemd-timesyncd; then
            warn "无法停用 systemd-timesyncd；为避免多个 NTP 客户端并存，正在回滚 chrony 配置。"
            systemctl stop "$svc" 2>/dev/null || true
            cp -a "$backup_dir/chrony.conf" "$conf"
            if [ -f "$backup_dir/source-existed" ]; then cp -a "$backup_dir/vpsbox.sources" "$source_file"; else rm -f "$source_file"; fi
            if [ "$chrony_was_enabled" -eq 1 ]; then systemctl enable "$svc" 2>/dev/null || true; else systemctl disable "$svc" 2>/dev/null || true; fi
            [ "$chrony_was_active" -eq 1 ] && systemctl start "$svc" 2>/dev/null || true
            if [ "$timesyncd_was_enabled" -eq 1 ]; then systemctl enable systemd-timesyncd 2>/dev/null || true; fi
            [ "$timesyncd_was_active" -eq 1 ] && systemctl start systemd-timesyncd 2>/dev/null || true
            rm -rf "$backup_dir"
            return 1
        fi
    fi
    rm -rf "$backup_dir"
    mark_change_applied NTP_CONF || return 1

    enabled_state="$(systemctl is-enabled "$svc" 2>/dev/null || echo "unknown")"
    active_state="$(systemctl is-active "$svc" 2>/dev/null || echo "unknown")"
    info "chrony 开机自启：$enabled_state"
    info "chrony 运行状态：$active_state"

    echo ""
    info "NTP 时间源："
    if ! sources_output="$(chronyc sources -v 2>/dev/null)"; then
        sleep 1
        sources_output="$(chronyc sources -v 2>/dev/null || true)"
    fi
    if [ -n "$sources_output" ]; then
        printf '%s\n' "$sources_output"
    else
        warn "无法读取 chrony 时间源。"
    fi

    echo ""
    info "同步状态："
    tracking_output="$(chronyc tracking 2>/dev/null || true)"
    if [ -n "$tracking_output" ]; then
        printf '%s\n' "$tracking_output"
        if echo "$tracking_output" | grep -Eq '^Leap status[[:space:]]*:[[:space:]]*Normal'; then
            info "NTP 时间同步已启用。"
        else
            warn "chrony 已运行，首次同步可能需要几分钟。"
        fi
    else
        warn "无法读取 chrony 同步状态。"
    fi

    echo ""
    info "系统时间关键状态："
    timedatectl show -p Timezone -p NTP -p NTPSynchronized -p TimeUSec 2>/dev/null || true
    warn "如确认需要立即校准，可手动执行：chronyc makestep"
}

print_ipv4_dns_from_resolvectl() {
    command -v resolvectl >/dev/null 2>&1 || return 1

    local found=1
    local seen=" "
    local line
    local token
    local ip

    while IFS= read -r line; do
        line="${line#*:}"
        for token in $line; do
            ip="${token%%%*}"
            ip="${ip%#*}"
            if is_ipv4_address "$ip"; then
                case "$seen" in
                    *" $ip "*) ;;
                    *)
                        printf ' nameserver %s\n' "$ip"
                        seen="${seen}${ip} "
                        found=0
                        ;;
                esac
            fi
        done
    done < <(resolvectl dns 2>/dev/null)

    return "$found"
}

print_ipv4_dns_from_resolv_conf() {
    [ -r /etc/resolv.conf ] || return 1

    local found=1
    local seen=" "
    local keyword
    local ip

    while read -r keyword ip _; do
        [ "$keyword" = "nameserver" ] || continue
        if is_ipv4_address "$ip"; then
            case "$seen" in
                *" $ip "*) ;;
                *)
                    printf ' nameserver %s\n' "$ip"
                    seen="${seen}${ip} "
                    found=0
                    ;;
            esac
        fi
    done < /etc/resolv.conf

    return "$found"
}

resolv_conf_managed_by_systemd_resolved() {
    [ -L /etc/resolv.conf ] || return 1

    local target
    target="$(readlink /etc/resolv.conf 2>/dev/null || true)"

    case "$target" in
        *systemd/resolve*)
            command -v systemctl >/dev/null 2>&1 || return 1
            systemctl list-unit-files systemd-resolved.service 2>/dev/null |
                grep -q '^systemd-resolved\.service' || return 1
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

ipv4_dns_lines() {
    if resolv_conf_managed_by_systemd_resolved; then
        if print_ipv4_dns_from_resolvectl; then
            return 0
        fi
        if print_ipv4_dns_from_resolv_conf; then
            return 0
        fi
        echo " 未检测到 IPv4 DNS"
        return
    fi

    if print_ipv4_dns_from_resolv_conf; then
        return 0
    fi

    if print_ipv4_dns_from_resolvectl; then
        return 0
    fi

    echo " 未检测到 IPv4 DNS"
}

dns_values_line() {
    local dns1="$1"
    local dns2="${2:-}"

    if [ -n "$dns2" ]; then
        printf '%s %s\n' "$dns1" "$dns2"
    else
        printf '%s\n' "$dns1"
    fi
}

verify_dns_resolution() {
    if command -v getent >/dev/null 2>&1; then
        if command -v timeout >/dev/null 2>&1; then
            timeout 8 getent ahosts example.com 2>/dev/null | grep -Eq '^[0-9A-Fa-f:.]+'
        else
            getent ahosts example.com 2>/dev/null | grep -Eq '^[0-9A-Fa-f:.]+'
        fi
        return $?
    fi
    if command -v resolvectl >/dev/null 2>&1; then
        if command -v timeout >/dev/null 2>&1; then
            timeout 8 resolvectl query example.com >/dev/null 2>&1
        else
            resolvectl query example.com >/dev/null 2>&1
        fi
        return $?
    fi
    return 2
}

write_resolv_conf_dns() {
    local dns1="$1"
    local dns2="${2:-}"
    local backup
    local created_resolv="0"
    local verify_status
    local tmp

    backup_change_file_once DNS_RESOLV /etc/resolv.conf || { err "记录 DNS 原配置失败，已取消修改。"; return 1; }
    backup="/etc/resolv.conf.vpsbox.bak.$(date +%Y%m%d%H%M%S)"
    if [ -e /etc/resolv.conf ]; then
        if ! cp -a /etc/resolv.conf "$backup"; then
            err "备份 /etc/resolv.conf 失败，已取消 DNS 修改。"
            return 1
        fi
    else
        created_resolv="1"
    fi

    tmp="$(mktemp /etc/.resolv.conf.vpsbox.XXXXXX)" || return 1
    if ! {
        printf 'nameserver %s\n' "$dns1"
        [ -n "$dns2" ] && printf 'nameserver %s\n' "$dns2"
        [ -r /etc/resolv.conf ] && awk '$1 != "nameserver" { print }' /etc/resolv.conf
    } > "$tmp"; then
        rm -f "$tmp"
        err "生成新的 /etc/resolv.conf 失败。"
        return 1
    fi

    chown root:root "$tmp" || { rm -f "$tmp"; return 1; }
    chmod 644 "$tmp" || { rm -f "$tmp"; return 1; }
    if ! mv -f "$tmp" /etc/resolv.conf; then
        rm -f "$tmp"
        err "原子替换 /etc/resolv.conf 失败。"
        return 1
    fi

    if verify_dns_resolution; then
        info "DNS 解析验证通过。"
    else
        verify_status=$?
        if [ "$verify_status" -eq 2 ]; then
            warn "未找到 getent/resolvectl，无法自动验证 DNS 解析。"
        else
            err "DNS 解析验证失败，正在恢复原配置。"
            if [ -e "$backup" ]; then
                cp -a "$backup" /etc/resolv.conf || warn "恢复 DNS 备份失败：$backup"
            elif [ "$created_resolv" = "1" ]; then
                rm -f /etc/resolv.conf
            fi
            return 1
        fi
    fi

    mark_change_applied DNS_RESOLV || return 1
    [ -e "$backup" ] && info "原配置备份：$backup"
}

rollback_systemd_resolved_dns() {
    local conf_file="$1"
    local backup="$2"
    local created_conf="$3"

    if [ -n "$backup" ] && [ -e "$backup" ]; then
        if cp "$backup" "$conf_file" 2>/dev/null; then
            warn "已恢复 systemd-resolved DNS 备份：$backup"
        else
            warn "恢复 systemd-resolved DNS 备份失败，请手动检查：$backup"
        fi
    elif [ "$created_conf" = "1" ]; then
        rm -f "$conf_file"
        warn "已删除新建的 systemd-resolved DNS 配置：$conf_file"
    else
        warn "未找到可恢复的 systemd-resolved DNS 备份，请手动检查：$conf_file"
    fi
}

write_systemd_resolved_dns() {
    local dns1="$1"
    local dns2="${2:-}"
    local conf_dir="/etc/systemd/resolved.conf.d"
    local conf_file="$conf_dir/vpsbox.conf"
    local backup=""
    local created_conf="0"
    local tmp
    local verify_status

    [ ! -L "$conf_file" ] || {
        err "$conf_file 是符号链接，已拒绝覆盖。"
        return 1
    }

    mkdir -p "$conf_dir" || return 1
    backup_change_file_once DNS_RESOLVED "$conf_file" || { err "记录 DNS 原配置失败，已取消修改。"; return 1; }
    if [ -e "$conf_file" ]; then
        backup="${conf_file}.bak.$(date +%Y%m%d%H%M%S)"
        if ! cp -a "$conf_file" "$backup"; then
            err "备份 $conf_file 失败，已取消 DNS 修改。"
            return 1
        fi
    else
        created_conf="1"
    fi

    tmp="$(mktemp "$conf_dir/.vpsbox.conf.XXXXXX")" || return 1
    if ! cat > "$tmp" <<EOF
[Resolve]
DNS=$(dns_values_line "$dns1" "$dns2")
Domains=~.
EOF
    then
        rm -f "$tmp"
        err "写入 $conf_file 失败。"
        return 1
    fi
    chmod 644 "$tmp" || { rm -f "$tmp"; return 1; }
    mv -f "$tmp" "$conf_file" || { rm -f "$tmp"; return 1; }

    info "检测到 systemd-resolved，已写入：$conf_file"
    warn "Domains=~. 会让 systemd-resolved 将全局 DNS 查询交给上述服务器。"
    info "正在重启 systemd-resolved 以应用 DNS，不会重启 VPS..."
    if ! retry 3 2 systemctl restart systemd-resolved; then
        err "重启 systemd-resolved 失败，请检查 systemctl status systemd-resolved --no-pager。"
        rollback_systemd_resolved_dns "$conf_file" "$backup" "$created_conf"
        retry 2 2 systemctl restart systemd-resolved >/dev/null 2>&1 || true
        return 1
    fi

    resolvectl flush-caches >/dev/null 2>&1 || true
    if verify_dns_resolution; then
        info "DNS 解析验证通过。"
    else
        verify_status=$?
        if [ "$verify_status" -eq 2 ]; then
            warn "未找到可用命令，无法自动验证 DNS 解析。"
        else
            err "DNS 解析验证失败，正在恢复 systemd-resolved 配置。"
            rollback_systemd_resolved_dns "$conf_file" "$backup" "$created_conf"
            retry 2 2 systemctl restart systemd-resolved >/dev/null 2>&1 || true
            return 1
        fi
    fi
    mark_change_applied DNS_RESOLVED || return 1
    [ -n "$backup" ] && [ -e "$backup" ] && info "原配置备份：$backup"
}

apply_ipv4_dns() {
    local dns1="$1"
    local dns2="${2:-}"

    if resolv_conf_managed_by_systemd_resolved; then
        write_systemd_resolved_dns "$dns1" "$dns2"
        return $?
    fi

    if [ -L /etc/resolv.conf ]; then
        warn "/etc/resolv.conf 是未知符号链接，DNS 可能由系统网络服务管理。"
        warn "为避免破坏 NetworkManager、DHCP 或 cloud-init 管理的 DNS，已拒绝直接覆盖。"
        return 2
    fi

    write_resolv_conf_dns "$dns1" "$dns2"
}

change_ipv4_dns() {
    local choice
    local dns1=""
    local dns2=""
    local apply_status

    cat <<EOF
========================================
 修改系统 IPv4 DNS
========================================
当前 IPv4 DNS：
$(ipv4_dns_lines)
----------------------------------------
 1) 使用默认 DNS：1.1.1.1 + 8.8.8.8
 2) 自定义 IPv4 DNS
 0) 取消
========================================
EOF

    read -r -p "请输入选项: " choice
    case "$choice" in
        1)
            dns1="1.1.1.1"
            dns2="8.8.8.8"
            ;;
        2)
            while true; do
                read -r -p "请输入 DNS1 IPv4 地址: " dns1
                if is_ipv4_address "$dns1"; then
                    break
                fi
                err "DNS1 格式不正确，请输入 IPv4 地址，例如 1.1.1.1。"
            done

            while true; do
                read -r -p "请输入 DNS2 IPv4 地址，留空跳过: " dns2
                [ -z "$dns2" ] && break
                if is_ipv4_address "$dns2"; then
                    break
                fi
                err "DNS2 格式不正确，请输入 IPv4 地址，例如 8.8.8.8。"
            done
            ;;
        0)
            info "已取消。"
            return 0
            ;;
        *)
            warn "无效选项。"
            return 1
            ;;
    esac

    if apply_ipv4_dns "$dns1" "$dns2"; then
        :
    else
        apply_status=$?
        [ "$apply_status" -eq 2 ] && return 0
        return "$apply_status"
    fi

    info "IPv4 DNS 已更新："
    ipv4_dns_lines
}

enable_ipv4_priority() {
    local backup=""

    info "正在启用系统 IPv4 优先，不会禁用 IPv6。"
    backup_change_file_once GAI_CONF "$GAI_CONF" || { err "记录 IPv4 优先原配置失败，已取消修改。"; return 1; }

    if [ -s "$GAI_CONF" ]; then
        backup="${GAI_CONF}.bak.$(date +%F-%H%M%S)"
        if ! cp -a "$GAI_CONF" "$backup"; then
            err "备份 $GAI_CONF 失败，已取消修改。"
            return 1
        fi
    fi

    if ! touch "$GAI_CONF"; then
        err "无法创建或写入 $GAI_CONF。"
        return 1
    fi

    if ! sed -i '/^[#[:space:]]*precedence[[:space:]]\+::ffff:0:0\/96[[:space:]]\+/d' "$GAI_CONF"; then
        err "清理旧 IPv4 优先配置失败。"
        return 1
    fi

    if ! printf '%s\n' 'precedence ::ffff:0:0/96 100' >> "$GAI_CONF"; then
        err "写入 IPv4 优先配置失败。"
        return 1
    fi

    info "已写入：precedence ::ffff:0:0/96 100"
    mark_change_applied GAI_CONF || return 1
    [ -n "$backup" ] && info "原配置备份：$backup"
    info "当前 IPv4 优先：$(ipv4_priority_state)"
    info "可用 curl ip.sb 或 curl -v ip.sb 验证默认出口。"
}

sshd_binary() {
    local bin

    bin="$(command -v sshd 2>/dev/null || true)"
    if [ -n "$bin" ]; then
        printf '%s\n' "$bin"
    elif [ -x /usr/sbin/sshd ]; then
        printf '%s\n' "/usr/sbin/sshd"
    else
        return 1
    fi
}

sshd_effective_config() {
    local bin

    bin="$(sshd_binary)" || return 1
    "$bin" -T 2>/dev/null
}

sshd_effective_values() {
    local key="$1"

    sshd_effective_config | awk -v key="$key" '$1 == key {
        $1 = ""
        sub(/^ /, "")
        print
    }' || true
}

sshd_effective_value() {
    local key="$1"
    local value

    value="$(sshd_effective_values "$key" | head -n 1 || true)"
    [ -n "$value" ] && printf '%s\n' "$value" || printf '%s\n' "未知"
}

sshd_effective_value_list() {
    local key="$1"
    local values

    values="$(sshd_effective_values "$key" | awk 'BEGIN { sep = "" } { printf "%s%s", sep, $0; sep = ", " } END { printf "\n" }' || true)"
    [ -n "$values" ] && printf '%s\n' "$values" || printf '%s\n' "未知"
}

ssh_effective_ports_csv() {
    local ports

    ports="$(sshd_effective_values port | awk '/^[0-9]+$/ && $1 >= 1 && $1 <= 65535' | sort -n -u | paste -sd, -)"
    [ -n "$ports" ] || return 1
    printf '%s\n' "$ports"
}

ssh_port_state() {
    sshd_effective_value_list port
}

ssh_effective_value_equals() {
    local key="$1"
    local expected="$2"

    [ "$(sshd_effective_value "$key")" = "$expected" ]
}

ssh_effective_ports_match_target() {
    local ports

    ports="$(sshd_effective_values port | sort -n | awk 'BEGIN { sep = "" } { printf "%s%s", sep, $0; sep = " " } END { printf "\n" }' || true)"
    [ "$ports" = "$SSH_TARGET_PORT" ]
}

ssh_basic_hardening_effective() {
    ssh_effective_value_equals logingracetime 60 &&
        ssh_effective_value_equals strictmodes yes &&
        ssh_effective_value_equals pubkeyauthentication yes &&
        ssh_effective_value_equals permitemptypasswords no &&
        ssh_effective_value_equals usepam yes &&
        ssh_effective_value_equals usedns no
}

ssh_vpsbox_settings_effective() {
    ssh_effective_ports_match_target && ssh_basic_hardening_effective
}

ssh_hardening_state() {
    if ! sshd_binary >/dev/null 2>&1; then
        echo "无法检测"
    elif ssh_basic_hardening_effective; then
        echo "已配置"
    else
        echo "未配置"
    fi
}

ensure_sshd_dropin_include() {
    local tmp

    if grep -Eq '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/\*\.conf([[:space:]]|$)' "$SSHD_MAIN_CONF" 2>/dev/null; then
        return 0
    fi

    tmp="$(mktemp)" || return 1
    {
        echo "Include /etc/ssh/sshd_config.d/*.conf"
        cat "$SSHD_MAIN_CONF"
    } > "$tmp" || { rm -f "$tmp"; return 1; }
    install -m 644 "$tmp" "$SSHD_MAIN_CONF" || { rm -f "$tmp"; return 1; }
    rm -f "$tmp"
}

backup_ssh_file() {
    local path="$1"
    local suffix="$2"

    if [ -e "$path" ]; then
        cp -a "$path" "${path}.vpsbox.bak.${suffix}" || return 1
        printf '%s\n' "${path}.vpsbox.bak.${suffix}"
    fi
}

restore_ssh_config_backup() {
    local main_backup="$1"
    local dropin_path="$2"
    local dropin_backup="$3"

    if [ -n "$main_backup" ] && [ -e "$main_backup" ]; then
        cp -a "$main_backup" "$SSHD_MAIN_CONF" || warn "恢复 $SSHD_MAIN_CONF 失败。"
    fi
    if [ -n "$dropin_backup" ] && [ -e "$dropin_backup" ]; then
        cp -a "$dropin_backup" "$dropin_path" || warn "恢复 $dropin_path 失败。"
    else
        rm -f "$dropin_path" || warn "删除 $dropin_path 失败。"
    fi
}

comment_main_ssh_port_directives() {
    local tmp

    tmp="$(mktemp)" || return 1
    awk '
        /^[[:space:]]*Port[[:space:]]+/ {
            print "# VPSBox disabled: " $0
            next
        }
        { print }
    ' "$SSHD_MAIN_CONF" > "$tmp" || { rm -f "$tmp"; return 1; }
    install -m 644 "$tmp" "$SSHD_MAIN_CONF" || { rm -f "$tmp"; return 1; }
    rm -f "$tmp"
}

write_vpsbox_ssh_port_config() {
    local tmp

    mkdir -p "$SSHD_CONFIG_DIR" || return 1
    tmp="$(mktemp)" || return 1
    cat > "$tmp" <<EOF || { rm -f "$tmp"; return 1; }
# Managed by VPSBox
Port $SSH_TARGET_PORT
EOF
    install -m 644 "$tmp" "$SSHD_VPSBOX_PORT_CONF" || { rm -f "$tmp"; return 1; }
    rm -f "$tmp"
}

write_vpsbox_ssh_hardening_config() {
    local tmp

    mkdir -p "$SSHD_CONFIG_DIR" || return 1
    tmp="$(mktemp)" || return 1
    cat > "$tmp" <<'EOF' || { rm -f "$tmp"; return 1; }
# Managed by VPSBox
LoginGraceTime 1m
StrictModes yes
PubkeyAuthentication yes
PermitEmptyPasswords no
UsePAM yes
UseDNS no
EOF
    install -m 644 "$tmp" "$SSHD_VPSBOX_HARDENING_CONF" || { rm -f "$tmp"; return 1; }
    rm -f "$tmp"
}

validate_ssh_port_effective_config() {
    local bin

    bin="$(sshd_binary)" || { err "未找到 sshd，无法检查 SSH 配置。"; return 1; }

    if ! "$bin" -t; then
        err "sshd -t 检查未通过。"
        return 1
    fi

    if ! ssh_effective_ports_match_target; then
        err "SSH 当前生效端口不是 $SSH_TARGET_PORT，当前为：$(ssh_port_state)"
        warn "可能还有其他 SSH 配置文件也写了 Port，请先检查 /etc/ssh/sshd_config 和 /etc/ssh/sshd_config.d/。"
        return 1
    fi
}

validate_ssh_hardening_effective_config() {
    local bin

    bin="$(sshd_binary)" || { err "未找到 sshd，无法检查 SSH 配置。"; return 1; }

    if ! "$bin" -t; then
        err "sshd -t 检查未通过。"
        return 1
    fi

    if ! ssh_basic_hardening_effective; then
        err "SSH 基础加固项未全部生效。"
        return 1
    fi
}

restart_ssh_service() {
    if is_systemd; then
        retry 3 2 systemctl restart ssh || retry 3 2 systemctl restart sshd
    elif command -v service >/dev/null 2>&1; then
        retry 3 2 service ssh restart || retry 3 2 service sshd restart
    else
        err "未找到可用的 SSH 服务重启方式。"
        return 1
    fi
}

ssh_listener_on_port() {
    local port="$1"

    command -v ss >/dev/null 2>&1 || return 1
    if ss -H -tlnp 2>/dev/null | awk -v port="$port" '
        $4 ~ (":" port "$") && $0 ~ /"sshd"/ { found=1 }
        END { exit(found ? 0 : 1) }
    '; then
        return 0
    fi

    if is_systemd && systemctl is-active --quiet ssh.socket 2>/dev/null; then
        ss -H -tln 2>/dev/null | awk -v port="$port" '
            $4 ~ (":" port "$") { found=1 }
            END { exit(found ? 0 : 1) }
        '
        return $?
    fi
    return 1
}

wait_for_ssh_listener() {
    local port="$1"
    local i

    for i in 1 2 3 4 5; do
        ssh_listener_on_port "$port" && return 0
        sleep 1
    done
    return 1
}

warn_ssh_access_controls() {
    if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q '^Status: active'; then
        ufw status 2>/dev/null | grep -Eq "^${SSH_TARGET_PORT}/tcp[[:space:]]+ALLOW" ||
            warn "UFW 正在运行，但未确认已放行 TCP $SSH_TARGET_PORT。"
    fi
    if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
        firewall-cmd --quiet --query-port="${SSH_TARGET_PORT}/tcp" >/dev/null 2>&1 ||
            warn "firewalld 正在运行，但未确认已放行 TCP $SSH_TARGET_PORT。"
    fi
    if command -v getenforce >/dev/null 2>&1 && [ "$(getenforce 2>/dev/null)" = "Enforcing" ]; then
        if command -v semanage >/dev/null 2>&1; then
            semanage port -l 2>/dev/null | awk '$1 == "ssh_port_t" { print $3 }' |
                tr ',' '\n' | grep -Eq "(^|[[:space:]])${SSH_TARGET_PORT}($|[[:space:]])" ||
                warn "SELinux 为 Enforcing，未确认 ssh_port_t 包含端口 $SSH_TARGET_PORT。"
        else
            warn "SELinux 为 Enforcing，但未安装 semanage，无法验证 SSH 新端口策略。"
        fi
    fi
}

sync_fail2ban_sshd_port() {
    local backup=""
    local backend="auto"
    local ports
    local tmp

    if ! fail2ban_installed; then
        return 0
    fi

    mkdir -p "$FAIL2BAN_CONFIG_DIR" || return 1
    backup_change_file_once FAIL2BAN_SSHD "$FAIL2BAN_VPSBOX_SSHD_CONF" || return 1
    ports="$(ssh_effective_ports_csv)" || {
        err "无法读取 SSH 当前生效端口，已取消同步 Fail2ban。"
        return 1
    }
    is_systemd && backend="systemd"

    if [ -e "$FAIL2BAN_VPSBOX_SSHD_CONF" ]; then
        backup="${FAIL2BAN_VPSBOX_SSHD_CONF}.bak.$(date +%Y%m%d%H%M%S)"
        cp -a "$FAIL2BAN_VPSBOX_SSHD_CONF" "$backup" || return 1
    fi

    tmp="$(mktemp "$FAIL2BAN_CONFIG_DIR/.vpsbox-sshd.XXXXXX")" || return 1
    cat > "$tmp" <<EOF
[sshd]
enabled = true
port = $ports
backend = $backend
EOF
    chmod 644 "$tmp" || { rm -f "$tmp"; return 1; }

    mv -f "$tmp" "$FAIL2BAN_VPSBOX_SSHD_CONF" || return 1
    if ! fail2ban-client -t -c /etc/fail2ban >/dev/null 2>&1; then
        if [ -n "$backup" ]; then
            cp -a "$backup" "$FAIL2BAN_VPSBOX_SSHD_CONF" || true
        else
            rm -f "$FAIL2BAN_VPSBOX_SSHD_CONF"
        fi
        err "Fail2ban 配置预检失败，已恢复现有 SSH 防护配置。"
        return 1
    fi

    if is_systemd; then
        if ! retry 3 2 systemctl restart fail2ban; then
            if [ -n "$backup" ]; then
                cp -a "$backup" "$FAIL2BAN_VPSBOX_SSHD_CONF" || true
            else
                rm -f "$FAIL2BAN_VPSBOX_SSHD_CONF"
            fi
            systemctl restart fail2ban >/dev/null 2>&1 || true
            return 1
        fi
    elif command -v rc-service >/dev/null 2>&1; then
        if [ "$(fail2ban_service_state)" = "运行中" ]; then
            retry 3 2 rc-service fail2ban restart || {
                if [ -n "$backup" ]; then
                    cp -a "$backup" "$FAIL2BAN_VPSBOX_SSHD_CONF" || true
                else
                    rm -f "$FAIL2BAN_VPSBOX_SSHD_CONF"
                fi
                rc-service fail2ban restart >/dev/null 2>&1 || true
                return 1
            }
        elif ! retry 3 2 rc-service fail2ban start; then
            if [ -n "$backup" ]; then
                cp -a "$backup" "$FAIL2BAN_VPSBOX_SSHD_CONF" || true
            else
                rm -f "$FAIL2BAN_VPSBOX_SSHD_CONF"
            fi
            rc-service fail2ban start >/dev/null 2>&1 || true
            return 1
        fi
    else
        err "未找到 Fail2ban 服务重启方式。"
        return 1
    fi

    rm -f "$FAIL2BAN_CONFIG_DIR/99-vpsbox-sshd-port.local"
    fail2ban-client status sshd >/dev/null 2>&1 || return 1
    mark_change_applied FAIL2BAN_SSHD || return 1
}

apply_ssh_port_change() {
    local confirm
    local suffix
    local main_backup=""
    local dropin_backup=""

    if ! sshd_binary >/dev/null 2>&1; then
        err "未找到 sshd，无法修改 SSH 配置。"
        return 1
    fi

    if [ ! -f "$SSHD_MAIN_CONF" ]; then
        err "未找到 SSH 主配置：$SSHD_MAIN_CONF"
        return 1
    fi

    if ssh_effective_ports_match_target; then
        info "SSH 端口已经是 $SSH_TARGET_PORT，无需重复修改。"
        read -r -p "仍要重新写入并重启 SSH？[y/N]: " confirm
        case "$confirm" in
            y|Y|yes|YES) ;;
            *) info "已取消重复修改。"; return 0 ;;
        esac
    fi

    read -r -p "确认已在商家安全组放行 TCP $SSH_TARGET_PORT？输入 YES 继续: " confirm
    if [ "$confirm" != "YES" ]; then
        info "已取消，未修改 SSH 配置。"
        return 0
    fi

    backup_change_file_once SSHD_MAIN "$SSHD_MAIN_CONF" || return 1
    backup_change_file_once SSHD_PORT "$SSHD_VPSBOX_PORT_CONF" || return 1
    backup_change_file_once SSHD_HARDENING "$SSHD_VPSBOX_HARDENING_CONF" || return 1
    manifest_set_once SSH_PORTS "$(ssh_effective_ports_csv)" || return 1

    suffix="$(date +%F-%H%M%S)"
    if ! main_backup="$(backup_ssh_file "$SSHD_MAIN_CONF" "$suffix")"; then
        err "备份 $SSHD_MAIN_CONF 失败，已取消修改。"
        return 1
    fi
    if ! dropin_backup="$(backup_ssh_file "$SSHD_VPSBOX_PORT_CONF" "$suffix")"; then
        err "备份 $SSHD_VPSBOX_PORT_CONF 失败，已取消修改。"
        return 1
    fi

    if ! write_vpsbox_ssh_port_config || ! ensure_sshd_dropin_include || ! comment_main_ssh_port_directives; then
        err "写入 SSH 端口配置失败，正在回滚。"
        restore_ssh_config_backup "$main_backup" "$SSHD_VPSBOX_PORT_CONF" "$dropin_backup"
        return 1
    fi

    if ! validate_ssh_port_effective_config; then
        err "SSH 端口配置验证失败，正在回滚。"
        restore_ssh_config_backup "$main_backup" "$SSHD_VPSBOX_PORT_CONF" "$dropin_backup"
        return 1
    fi

    if ! restart_ssh_service; then
        err "SSH 服务重启失败，正在回滚配置并尝试恢复服务。"
        restore_ssh_config_backup "$main_backup" "$SSHD_VPSBOX_PORT_CONF" "$dropin_backup"
        restart_ssh_service >/dev/null 2>&1 || true
        return 1
    fi

    if ! wait_for_ssh_listener "$SSH_TARGET_PORT"; then
        err "SSH 重启后未检测到 sshd 监听端口 $SSH_TARGET_PORT，正在回滚。"
        restore_ssh_config_backup "$main_backup" "$SSHD_VPSBOX_PORT_CONF" "$dropin_backup"
        restart_ssh_service >/dev/null 2>&1 || true
        return 1
    fi

    warn_ssh_access_controls

    if sync_fail2ban_sshd_port; then
        fail2ban_installed && info "Fail2ban sshd 端口已同步为 $SSH_TARGET_PORT。"
    else
        warn "Fail2ban sshd 端口同步失败，请稍后检查 fail2ban-client status sshd。"
    fi

    mark_change_applied SSH_CONFIG || return 1

    info "SSH 端口已修改为 $SSH_TARGET_PORT。"
    [ -n "$main_backup" ] && info "主配置备份：$main_backup"
    [ -n "$dropin_backup" ] && info "vpsbox SSH 端口配置备份：$dropin_backup"
    warn "不要关闭当前 SSH 窗口。"
    warn "请另开一个新窗口测试：ssh -p $SSH_TARGET_PORT root@你的服务器IP"
    warn "确认新端口可以登录后，再去商家安全组关闭 TCP 22。"
}

apply_ssh_basic_hardening() {
    local confirm
    local suffix
    local main_backup=""
    local dropin_backup=""

    if ! sshd_binary >/dev/null 2>&1; then
        err "未找到 sshd，无法修改 SSH 配置。"
        return 1
    fi

    if [ ! -f "$SSHD_MAIN_CONF" ]; then
        err "未找到 SSH 主配置：$SSHD_MAIN_CONF"
        return 1
    fi

    if ssh_basic_hardening_effective; then
        info "SSH 基础加固已经生效，无需重复应用。"
        read -r -p "仍要重新写入并重启 SSH？[y/N]: " confirm
        case "$confirm" in
            y|Y|yes|YES) ;;
            *) info "已取消重复应用。"; return 0 ;;
        esac
    fi

    read -r -p "确认应用 SSH 基础加固并重启 SSH？[y/N]: " confirm
    case "$confirm" in
        y|Y|yes|YES) ;;
        *) info "已取消，未修改 SSH 配置。"; return 0 ;;
    esac

    backup_change_file_once SSHD_MAIN "$SSHD_MAIN_CONF" || return 1
    backup_change_file_once SSHD_PORT "$SSHD_VPSBOX_PORT_CONF" || return 1
    backup_change_file_once SSHD_HARDENING "$SSHD_VPSBOX_HARDENING_CONF" || return 1
    manifest_set_once SSH_PORTS "$(ssh_effective_ports_csv)" || return 1

    suffix="$(date +%F-%H%M%S)"
    if ! main_backup="$(backup_ssh_file "$SSHD_MAIN_CONF" "$suffix")"; then
        err "备份 $SSHD_MAIN_CONF 失败，已取消修改。"
        return 1
    fi
    if ! dropin_backup="$(backup_ssh_file "$SSHD_VPSBOX_HARDENING_CONF" "$suffix")"; then
        err "备份 $SSHD_VPSBOX_HARDENING_CONF 失败，已取消修改。"
        return 1
    fi

    if ! write_vpsbox_ssh_hardening_config || ! ensure_sshd_dropin_include; then
        err "写入 SSH 基础加固配置失败，正在回滚。"
        restore_ssh_config_backup "$main_backup" "$SSHD_VPSBOX_HARDENING_CONF" "$dropin_backup"
        return 1
    fi

    if ! validate_ssh_hardening_effective_config; then
        err "SSH 基础加固配置验证失败，正在回滚。"
        restore_ssh_config_backup "$main_backup" "$SSHD_VPSBOX_HARDENING_CONF" "$dropin_backup"
        return 1
    fi

    if ! restart_ssh_service; then
        err "SSH 服务重启失败，正在回滚配置并尝试恢复服务。"
        restore_ssh_config_backup "$main_backup" "$SSHD_VPSBOX_HARDENING_CONF" "$dropin_backup"
        restart_ssh_service >/dev/null 2>&1 || true
        return 1
    fi

    mark_change_applied SSH_CONFIG || return 1

    info "SSH 基础加固已应用。"
    [ -n "$main_backup" ] && info "主配置备份：$main_backup"
    [ -n "$dropin_backup" ] && info "vpsbox SSH 加固配置备份：$dropin_backup"
    warn "当前 SSH 连接通常不会断开，建议另开一个新窗口测试 SSH 登录。"
}

show_current_ssh_config() {
    local port
    local login_grace
    local strict_modes
    local pubkey_auth
    local empty_passwords
    local use_pam
    local use_dns

    if ! sshd_binary >/dev/null 2>&1; then
        err "未找到 sshd，无法查看 SSH 当前生效配置。"
        return 1
    fi

    port="$(ssh_port_state)"
    login_grace="$(sshd_effective_value logingracetime)"
    strict_modes="$(sshd_effective_value strictmodes)"
    pubkey_auth="$(sshd_effective_value pubkeyauthentication)"
    empty_passwords="$(sshd_effective_value permitemptypasswords)"
    use_pam="$(sshd_effective_value usepam)"
    use_dns="$(sshd_effective_value usedns)"

    cat <<EOF
========================================
 SSH 当前生效配置
========================================
1. Port
   当前值：$port
   作用：SSH 实际监听端口。

2. LoginGraceTime
   当前值：$login_grace
   作用：登录认证最多等待时间，超时断开。

3. StrictModes
   当前值：$strict_modes
   作用：检查用户目录和 ~/.ssh 权限，权限不安全会拒绝登录。

4. PubkeyAuthentication
   当前值：$pubkey_auth
   作用：是否允许 SSH 密钥登录。

5. PermitEmptyPasswords
   当前值：$empty_passwords
   作用：是否禁止空密码账号登录；no 表示禁止空密码登录。

6. UsePAM
   当前值：$use_pam
   作用：是否使用 Debian PAM 登录/会话流程。

7. UseDNS
   当前值：$use_dns
   作用：是否进行 DNS 反向解析；no 通常可减少登录卡顿。
----------------------------------------
监听状态：
EOF

    if command -v ss >/dev/null 2>&1; then
        ss -H -tlnp 2>/dev/null | awk '/sshd/ { print " " $0 }' || true
    else
        echo " 未找到 ss 命令，无法查看监听状态。"
    fi

cat <<EOF
----------------------------------------
配置来源：
 端口配置：$SSHD_VPSBOX_PORT_CONF $([ -f "$SSHD_VPSBOX_PORT_CONF" ] && echo "存在" || echo "不存在")
 加固配置：$SSHD_VPSBOX_HARDENING_CONF $([ -f "$SSHD_VPSBOX_HARDENING_CONF" ] && echo "存在" || echo "不存在")
========================================
EOF
}

restore_vpsbox_ssh_config() {
    local confirm tmp original_ports original_port name path

    [ "$(manifest_value APPLIED_SSH_CONFIG 2>/dev/null || true)" = "1" ] || {
        warn "没有已记录的 VPSBox SSH 配置可恢复。"
        return 0
    }
    original_ports="$(manifest_value SSH_PORTS 2>/dev/null || true)"
    original_port="${original_ports%%,*}"
    echo "将恢复 SSH 主配置及 VPSBox 端口/加固 drop-in。"
    echo "预期恢复端口：${original_ports:-未知}；当前连接可能断开。"
    read -r -p "请确认已有控制台或备用连接。输入 YES 执行 SSH 恢复：" confirm
    [ "$confirm" = "YES" ] || { info "已取消 SSH 恢复。"; return 0; }

    tmp="$(mktemp -d /tmp/vpsbox-ssh-restore.XXXXXX)" || return 1
    for name in main port hardening; do
        case "$name" in
            main) path="$SSHD_MAIN_CONF" ;;
            port) path="$SSHD_VPSBOX_PORT_CONF" ;;
            hardening) path="$SSHD_VPSBOX_HARDENING_CONF" ;;
        esac
        if [ -e "$path" ]; then cp -a "$path" "$tmp/$name"; else : > "$tmp/$name.absent"; fi
    done
    if ! restore_change_file SSHD_MAIN "$SSHD_MAIN_CONF" || ! restore_change_file SSHD_PORT "$SSHD_VPSBOX_PORT_CONF" || ! restore_change_file SSHD_HARDENING "$SSHD_VPSBOX_HARDENING_CONF" || ! "$(sshd_binary)" -t; then
        err "SSH 恢复配置校验失败，正在回滚当前配置。"
        [ -f "$tmp/main" ] && cp -a "$tmp/main" "$SSHD_MAIN_CONF"
        if [ -f "$tmp/port" ]; then cp -a "$tmp/port" "$SSHD_VPSBOX_PORT_CONF"; else rm -f "$SSHD_VPSBOX_PORT_CONF"; fi
        if [ -f "$tmp/hardening" ]; then cp -a "$tmp/hardening" "$SSHD_VPSBOX_HARDENING_CONF"; else rm -f "$SSHD_VPSBOX_HARDENING_CONF"; fi
        rm -rf "$tmp"
        return 1
    fi
    if ! restart_ssh_service || { [ -n "$original_port" ] && ! wait_for_ssh_listener "$original_port"; }; then
        err "SSH 服务未能在原端口恢复监听，正在回滚当前配置。"
        [ -f "$tmp/main" ] && cp -a "$tmp/main" "$SSHD_MAIN_CONF"
        if [ -f "$tmp/port" ]; then cp -a "$tmp/port" "$SSHD_VPSBOX_PORT_CONF"; else rm -f "$SSHD_VPSBOX_PORT_CONF"; fi
        if [ -f "$tmp/hardening" ]; then cp -a "$tmp/hardening" "$SSHD_VPSBOX_HARDENING_CONF"; else rm -f "$SSHD_VPSBOX_HARDENING_CONF"; fi
        restart_ssh_service >/dev/null 2>&1 || true
        rm -rf "$tmp"
        return 1
    fi
    rm -rf "$tmp"
    clear_change_tracking SSHD_MAIN; clear_change_tracking SSHD_PORT; clear_change_tracking SSHD_HARDENING
    manifest_remove APPLIED_SSH_CONFIG; manifest_remove SSH_PORTS
    sync_fail2ban_sshd_port || warn "SSH 已恢复，但 Fail2ban 端口同步失败，请手动检查。"
    info "SSH 配置已恢复，请立即用新窗口验证原端口连接。"
}

ssh_port_change_menu() {
    local opt

    while true; do
        clear 2>/dev/null || true
        cat <<EOF
========================================
 修改 SSH 端口
========================================
 当前 SSH 端口：$(ssh_port_state)
 目标 SSH 端口：$SSH_TARGET_PORT
----------------------------------------
将写入：
$SSHD_VPSBOX_PORT_CONF

1. Port $SSH_TARGET_PORT
   修改 SSH 监听端口，减少 22 端口扫描噪音。
   请先在商家安全组放行 TCP $SSH_TARGET_PORT。
----------------------------------------
 1) 应用 SSH 端口修改
 2) 恢复 VPSBox SSH 配置（高风险）
 0) 返回
========================================
EOF
        read -r -p "请输入选项: " opt || exit 0
        echo ""

        case "$opt" in
            1) run_menu_action apply_ssh_port_change; pause ;;
            2) run_menu_action restore_vpsbox_ssh_config; pause ;;
            0) return 0 ;;
            *) warn "无效选项：$opt"; pause ;;
        esac
    done
}

ssh_basic_hardening_menu() {
    local opt

    while true; do
        clear 2>/dev/null || true
        cat <<EOF
========================================
 SSH 基础加固
========================================
 加固配置：$(ssh_hardening_state)
----------------------------------------
将写入：
$SSHD_VPSBOX_HARDENING_CONF

1. LoginGraceTime 1m
   登录认证最多等待 1 分钟，超时断开。

2. StrictModes yes
   检查用户目录和 ~/.ssh 权限，权限不安全会拒绝登录。

3. PubkeyAuthentication yes
   允许 SSH 密钥登录；没有密钥也不影响密码登录。

4. PermitEmptyPasswords no
   禁止空密码账号通过 SSH 登录。

5. UsePAM yes
   保持 Debian 默认 PAM 登录/会话流程。

 6. UseDNS no
   登录时不做反向 DNS 查询，减少登录卡顿。
----------------------------------------
 1) 应用 SSH 基础加固
 0) 返回
========================================
EOF
        read -r -p "请输入选项: " opt || exit 0
        echo ""

        case "$opt" in
            1) run_menu_action apply_ssh_basic_hardening; pause ;;
            0) return 0 ;;
            *) warn "无效选项：$opt"; pause ;;
        esac
    done
}

update_system_packages() {
    detect_os
    if [ "$OS" != "debian" ]; then
        err "系统更新当前仅支持 Debian/Ubuntu。"
        case "$OS" in
            alpine) warn "Alpine 可手动执行：apk update && apk upgrade" ;;
            redhat) warn "RedHat 系可手动执行：dnf upgrade -y 或 yum update -y" ;;
            *) warn "未识别系统类型，已取消。" ;;
        esac
        return 1
    fi

    cat <<EOF
即将执行系统更新：
apt update && apt upgrade -y && apt autoremove -y
EOF
    read -r -p "确认继续？[y/N]: " confirm
    case "$confirm" in
        y|Y|yes|YES) ;;
        *) info "已取消系统更新。"; return 0 ;;
    esac

    export DEBIAN_FRONTEND=noninteractive
    retry 3 2 apt update
    retry 3 2 apt upgrade -y
    retry 3 2 apt autoremove -y

    if [ "$(reboot_required_state)" = "需要" ]; then
        warn "系统更新完成，检测到需要重启 VPS。"
    else
        info "系统更新完成，当前不需要重启。"
    fi
}

enable_bbr_fq() {
    local old_cc old_fq tmp backup_dir
    local had_old_conf=0

    old_cc="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || true)"
    old_fq="$(sysctl -n net.core.default_qdisc 2>/dev/null || true)"
    backup_change_file_once BBR_CONF "$BBR_CONF" || { err "记录 BBR 原配置失败，已取消修改。"; return 1; }
    manifest_set BBR_CC "${old_cc:-unknown}" || return 1
    manifest_set BBR_FQ "${old_fq:-unknown}" || return 1
    backup_dir="$(mktemp -d /tmp/vpsbox-bbr.XXXXXX)" || return 1
    if [ -e "$BBR_CONF" ] || [ -L "$BBR_CONF" ]; then
        [ ! -L "$BBR_CONF" ] || { rm -rf "$backup_dir"; err "$BBR_CONF 是符号链接，已拒绝覆盖。"; return 1; }
        cp -a "$BBR_CONF" "$backup_dir/99-vpsbox-bbr.conf" || { rm -rf "$backup_dir"; err "备份 BBR 配置失败。"; return 1; }
        had_old_conf=1
    fi
    tmp="$(mktemp /etc/sysctl.d/.vpsbox-bbr.XXXXXX)" || { rm -rf "$backup_dir"; return 1; }
    cat > "$tmp" <<EOF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF

    if ! modprobe tcp_bbr >/dev/null 2>&1 || ! modprobe sch_fq >/dev/null 2>&1; then
        rm -f "$tmp"; rm -rf "$backup_dir"
        err "内核不支持 tcp_bbr 或 sch_fq，未写入持久化配置。"
        return 1
    fi
    if ! sysctl -p "$tmp" >/dev/null 2>&1 || [ "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || true)" != "bbr" ] || [ "$(sysctl -n net.core.default_qdisc 2>/dev/null || true)" != "fq" ]; then
        [ -n "$old_cc" ] && sysctl -w "net.ipv4.tcp_congestion_control=$old_cc" >/dev/null 2>&1 || true
        [ -n "$old_fq" ] && sysctl -w "net.core.default_qdisc=$old_fq" >/dev/null 2>&1 || true
        rm -f "$tmp"; rm -rf "$backup_dir"
        err "BBR + fq 未能同时生效，已恢复运行时内核参数，未写入持久化配置。"
        return 1
    fi

    if ! chown root:root "$tmp" || ! chmod 644 "$tmp" || ! mv -f "$tmp" "$BBR_CONF"; then
        [ -n "$old_cc" ] && sysctl -w "net.ipv4.tcp_congestion_control=$old_cc" >/dev/null 2>&1 || true
        [ -n "$old_fq" ] && sysctl -w "net.core.default_qdisc=$old_fq" >/dev/null 2>&1 || true
        if [ "$had_old_conf" -eq 1 ]; then cp -a "$backup_dir/99-vpsbox-bbr.conf" "$BBR_CONF"; else rm -f "$BBR_CONF"; fi
        rm -f "$tmp"; rm -rf "$backup_dir"
        err "保存 BBR 配置失败，已回滚。"
        return 1
    fi
    rm -rf "$backup_dir"
    mark_change_applied BBR_CONF || return 1

    echo ""
    info "当前 BBR：$(bbr_state)"
    info "当前 fq：$(fq_state)"
}

install_fail2ban() {
    info "正在安装 Fail2ban..."

    detect_os
    case "$OS" in
        debian)
            export DEBIAN_FRONTEND=noninteractive
            if ! retry 3 2 apt update ||
                ! retry 3 2 apt install -y fail2ban ||
                ! retry 3 2 systemctl enable --now fail2ban; then
                warn "Fail2ban 安装或启动未完全成功，将尝试写入最小 SSH 配置后重启。"
            fi
            ;;
        alpine)
            if ! retry 3 2 apk update || ! retry 3 2 apk add --no-cache fail2ban; then
                err "Fail2ban 安装失败。"
                return 1
            fi
            if command -v rc-update >/dev/null 2>&1; then
                rc-update add fail2ban default >/dev/null 2>&1 || true
            fi
            if command -v rc-service >/dev/null 2>&1; then
                retry 3 2 rc-service fail2ban start || true
            fi
            ;;
        redhat)
            if command -v dnf >/dev/null 2>&1; then
                retry 3 2 dnf install -y fail2ban || { err "Fail2ban 安装失败。"; return 1; }
            else
                retry 3 2 yum install -y fail2ban || { err "Fail2ban 安装失败。"; return 1; }
            fi
            if is_systemd; then
                retry 3 2 systemctl enable --now fail2ban || true
            fi
            ;;
        *)
            err "未识别系统类型，无法自动安装 Fail2ban。"
            return 1
            ;;
    esac

    if ! fail2ban_installed; then
        err "Fail2ban 未安装成功，请检查软件源或网络。"
        return 1
    fi

    if is_systemd; then
        systemctl enable fail2ban >/dev/null 2>&1 || {
            err "无法设置 Fail2ban 开机自启。"
            return 1
        }
    elif [ "$OS" = "alpine" ] && command -v rc-service >/dev/null 2>&1; then
        rc-update add fail2ban default >/dev/null 2>&1 || {
            err "无法设置 Fail2ban 开机自启。"
            return 1
        }
    fi

    info "正在按 SSH 当前生效端口配置 Fail2ban..."
    sync_fail2ban_sshd_port || {
        err "Fail2ban SSH 配置或重启失败。"
        return 1
    }

    if [ "$(fail2ban_service_state)" != "运行中" ] || [ "$(fail2ban_sshd_state)" != "已启用" ]; then
        err "Fail2ban 未达到预期状态，请检查服务日志和 SSH 端口配置。"
        return 1
    fi

    info "Fail2ban 已安装，SSH 防护已启用，端口：$(ssh_effective_ports_csv)"
}

check_table_header() {
    cat <<'EOF'
----------------------------------------
 状态   | 项目             | 结果
--------+------------------+------------
EOF
}

check_table_footer() {
    cat <<'EOF'
--------+------------------+------------
EOF
}

display_width() {
    local text="$1"
    local i ch width=0

    for ((i = 0; i < ${#text}; i++)); do
        ch="${text:i:1}"
        case "$ch" in
            [[:ascii:]]) width=$((width + 1)) ;;
            *) width=$((width + 2)) ;;
        esac
    done

    printf '%s' "$width"
}

pad_right_display() {
    local text="$1"
    local target_width="$2"
    local width
    local padding

    width="$(display_width "$text")"
    padding=$((target_width - width))
    [ "$padding" -lt 0 ] && padding=0

    printf '%s' "$text"
    printf '%*s' "$padding" ''
}

check_row() {
    printf ' %-6s | ' "$1"
    pad_right_display "$2" 16
    printf ' | %s\n' "${3:-}"
}

check_ok() {
    check_row "OK" "$1" "${2:-}"
}

check_warn() {
    check_row "WARN" "$1" "${2:-}"
}

check_fail() {
    check_row "FAIL" "$1" "${2:-}"
}

public_ipv4() {
    command -v curl >/dev/null 2>&1 || return 1
    curl -4fsS --max-time 5 https://api.ipify.org 2>/dev/null
}

resolve_host_ips() {
    local host="$1"

    command -v getent >/dev/null 2>&1 || return 1
    getent ahosts "$host" 2>/dev/null | awk '{print $1}' | sort -u | head -n 5
}

run_self_check() {
    detect_os
    local has_node="0"
    local max_use
    local max_file
    local state

    max_use="$(journald_conf_value SystemMaxUse || echo "未配置")"
    max_file="$(journald_conf_value SystemMaxFileSize || echo "未配置")"

    cat <<EOF
========================================
 一键自检
========================================
EOF
    check_table_header

    if [ "$(id -u)" = "0" ]; then
        check_ok "运行用户" "root"
    else
        check_fail "运行用户" "不是 root"
    fi

    if [ -x "$CMD_PATH" ]; then
        check_ok "vpsbox 命令" "$CMD_PATH"
    else
        check_warn "vpsbox 命令" "未安装到 $CMD_PATH"
    fi

    if singbox_installed; then
        check_ok "sing-box" "$(singbox_version)"
    else
        check_warn "sing-box" "未安装"
    fi

    if [ -f "$STATE_FILE" ] && ! load_state; then
        check_fail "节点状态" "文件不安全或内容无效"
    elif node_exists; then
        load_state
        has_node="1"
        check_ok "当前节点" "${PROTOCOL:-shadowsocks} ${DOMAIN:-未知}:${PORT:-未知}"
        if [ "${PROTOCOL:-}" = "vless-reality" ]; then
            check_ok "Reality SNI" "${REALITY_SERVER_NAME:-未知}"
        fi
    else
        check_warn "当前节点" "未创建"
    fi

    if [ -f "$CONFIG_PATH" ]; then
        if singbox_installed && sing-box check -c "$CONFIG_PATH" >/dev/null 2>&1; then
            check_ok "配置语法" "通过"
        elif singbox_installed; then
            check_fail "配置语法" "未通过"
        else
            check_warn "配置语法" "sing-box 未安装，无法检查"
        fi
    else
        check_warn "配置文件" "不存在"
    fi

    state="$(service_status_short)"
    if [ "$state" = "运行中" ]; then
        check_ok "服务状态" "$state"
    elif [ "$has_node" = "1" ]; then
        check_fail "服务状态" "$state"
    else
        check_warn "服务状态" "$state"
    fi

    if [ "$has_node" = "1" ] && [ -n "${PORT:-}" ]; then
        if port_in_use "$PORT"; then
            check_ok "端口监听" "$PORT 正在监听"
        else
            check_warn "端口监听" "$PORT 未监听"
        fi
    fi

    if [ "$has_node" = "1" ] && [ -n "${DOMAIN:-}" ]; then
        if is_ip_address "$DOMAIN"; then
            check_ok "节点地址" "$DOMAIN"
        elif is_valid_node_host "$DOMAIN"; then
            local ips
            ips="$(resolve_host_ips "$DOMAIN" | tr '\n' ' ')"
            if [ -n "$ips" ]; then
                check_ok "域名解析" "$ips"
            else
                check_warn "域名解析" "未解析到 IP"
            fi
        else
            check_fail "节点地址" "格式不正确：$DOMAIN"
        fi
    fi

    if [ -s "$URI_FILE" ]; then
        check_ok "节点链接" "$URI_FILE"
    else
        check_warn "节点链接" "未生成"
    fi

    local ip
    ip="$(public_ipv4 || true)"
    if [ -n "$ip" ] && is_ipv4_address "$ip"; then
        check_ok "公网 IPv4" "$ip"
    else
        check_warn "公网 IPv4" "获取失败"
    fi

    check_ok "系统时间" "$(date '+%Y-%m-%d %H:%M:%S %Z')"
    state="$(ntp_sync_state)"
    if [ "$state" = "已同步" ]; then
        check_ok "NTP 同步" "$state"
    else
        check_warn "NTP 同步" "$state"
    fi
    check_ok "运行时间" "$(uptime -p 2>/dev/null || echo "无法检测")"
    state="$(bbr_state)"
    if [ "$state" = "已启用" ]; then check_ok "BBR" "$state"; else check_warn "BBR" "$state"; fi
    state="$(fq_state)"
    if [ "$state" = "已启用" ]; then check_ok "fq" "$state"; else check_warn "fq" "$state"; fi
    state="$(ipv4_priority_state)"
    if [ "$state" = "已启用" ]; then check_ok "IPv4 优先" "$state"; else check_warn "IPv4 优先" "$state"; fi
    if ssh_effective_ports_match_target; then
        check_ok "SSH 端口" "$(ssh_port_state)"
    else
        check_warn "SSH 端口" "$(ssh_port_state)"
    fi
    if ssh_basic_hardening_effective; then
        check_ok "SSH 基础加固" "$(ssh_hardening_state)"
    else
        check_warn "SSH 基础加固" "$(ssh_hardening_state)"
    fi
    state="$(fail2ban_install_state)"
    if [ "$state" = "已安装" ]; then check_ok "Fail2ban" "$state"; else check_warn "Fail2ban" "$state"; fi
    state="$(fail2ban_service_state)"
    if [ "$state" = "运行中" ]; then check_ok "Fail2ban 状态" "$state"; else check_warn "Fail2ban 状态" "$state"; fi
    state="$(fail2ban_sshd_state)"
    if [ "$state" = "已启用" ]; then check_ok "SSH 防护" "$state"; else check_warn "SSH 防护" "$state"; fi

    if [ "$(reboot_required_state)" = "需要" ]; then
        check_warn "系统重启" "需要重启"
    else
        check_ok "系统重启" "不需要重启"
    fi
    state="$(journal_disk_usage)"
    if [ "$state" = "无法检测" ]; then check_warn "日志占用" "$state"; else check_ok "日志占用" "$state"; fi
    state="$(journald_limit_state)"
    if [ "$state" = "已配置" ]; then
        check_ok "日志限制" "$state"
        check_ok "日志最大占用" "$max_use"
        check_ok "单个日志最大" "$max_file"
    else
        check_warn "日志限制" "$state"
        check_warn "日志最大占用" "$max_use"
        check_warn "单个日志最大" "$max_file"
    fi

    check_table_footer

    show_ports_security_group || true
}

nexttrace_installed() {
    command -v nexttrace >/dev/null 2>&1
}

ensure_nexttrace() {
    local arch asset tmp

    if nexttrace_installed; then
        return 0
    fi

    warn "未检测到 nexttrace。"
    read -r -p "是否自动安装 nexttrace？(y/N): " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { info "已取消。"; return 1; }

    install_deps || return 1

    case "$(uname -m)" in
        x86_64) arch="amd64" ;;
        aarch64) arch="arm64" ;;
        armv7l|armv7) arch="armv7" ;;
        i?86) arch="386" ;;
        *) err "不支持的 nexttrace 架构：$(uname -m)"; return 1 ;;
    esac
    asset="nexttrace_linux_$arch"
    tmp="$(mktemp "/tmp/$asset.XXXXXX")" || return 1
    info "正在下载并校验 nexttrace v$NEXTTRACE_RELEASE_VERSION（$asset）..."
    if ! download_verified_github_asset "nxtrace/NTrace-core" "v$NEXTTRACE_RELEASE_VERSION" "$asset" "$tmp"; then
        rm -f "$tmp"
        return 1
    fi
    if ! install -o root -g root -m 755 "$tmp" /usr/local/bin/nexttrace; then
        rm -f "$tmp"
        err "安装 nexttrace 二进制失败。"
        return 1
    fi
    rm -f "$tmp"

    if nexttrace_installed; then
        info "nexttrace 安装完成。"
        return 0
    fi

    err "未找到 nexttrace 命令，安装可能未成功。"
    return 1
}

trace_has() {
    local output="$1"
    local pattern="$2"
    printf '%s\n' "$output" | grep -Eiq "$pattern"
}

detect_trace_line() {
    local output="$1"
    local has_4134=0
    local has_4809=0

    trace_has "$output" 'AS[[:space:]]*4134|AS4134|202\.97\.' && has_4134=1
    trace_has "$output" 'AS[[:space:]]*4809|AS4809|59\.43\.' && has_4809=1

    if trace_has "$output" 'AS[[:space:]]*23764|AS23764|69\.194\.|203\.22\.'; then
        echo "CTGNET|AS23764"
    elif [ "$has_4134" = "1" ] && [ "$has_4809" = "1" ]; then
        echo "CN2 GT|AS4134/AS4809"
    elif [ "$has_4809" = "1" ]; then
        echo "CN2 GIA|AS4809"
    elif [ "$has_4134" = "1" ]; then
        echo "163|AS4134"
    elif trace_has "$output" 'AS[[:space:]]*9929|AS9929|218\.105\.|210\.51\.'; then
        echo "9929|AS9929"
    elif trace_has "$output" 'AS[[:space:]]*4837|AS4837|219\.158\.'; then
        echo "4837|AS4837"
    elif trace_has "$output" 'AS[[:space:]]*58807|AS58807|223\.120\.(16|17|19|130|131|140|141)\.'; then
        echo "CMIN2|AS58807"
    elif trace_has "$output" 'AS[[:space:]]*58453|AS58453|AS[[:space:]]*9808|AS9808|223\.(118|119|120|121)\.'; then
        echo "CMI|AS58453"
    else
        echo "未识别|-"
    fi
}

run_nexttrace_target() {
    local ip="$1"

    if command -v timeout >/dev/null 2>&1; then
        timeout 30 nexttrace -n -P -C "$ip" 2>&1
    else
        nexttrace -n -P -C "$ip" 2>&1
    fi
}

check_route_target() {
    local name="$1"
    local ip="$2"
    local result_file="$3"
    local output
    local detected
    local result
    local asn

    if output="$(run_nexttrace_target "$ip")"; then
        detected="$(detect_trace_line "$output")"
        result="${detected%%|*}"
        asn="${detected#*|}"
    else
        result="检测失败"
        asn="-"
    fi

    printf '%-10s %-15s %-10s %s\n' "$name" "$ip" "$result" "$asn" > "$result_file"
}

show_backtrace_routes() {
    ensure_nexttrace || return 1

    local i
    local name
    local ip
    local tmp_dir
    local result_file

    tmp_dir="$(mktemp -d /tmp/vpsbox-trace.XXXXXX)"
    trap 'rm -rf "$tmp_dir"' RETURN

    cat <<EOF
========================================
 三网回程检测
========================================
正在分批检测 ${#TRACE_NAMES[@]} 个目标，每批最多 ${TRACE_MAX_JOBS} 个，每个最多 30 秒，请稍等...
----------------------------------------
线路      目标 IP          判断       关键 ASN
EOF

    local job_count=0
    for i in "${!TRACE_NAMES[@]}"; do
        name="${TRACE_NAMES[$i]}"
        ip="${TRACE_IPS[$i]}"
        check_route_target "$name" "$ip" "$tmp_dir/$i" &
        job_count=$((job_count + 1))
        if [ "$job_count" -ge "$TRACE_MAX_JOBS" ]; then
            wait
            job_count=0
        fi
    done

    wait

    for i in "${!TRACE_NAMES[@]}"; do
        result_file="$tmp_dir/$i"
        if [ -s "$result_file" ]; then
            cat "$result_file"
        else
            printf '%-10s %-15s %-10s %s\n' "${TRACE_NAMES[$i]}" "${TRACE_IPS[$i]}" "检测失败" "-"
        fi
    done

    rm -rf "$tmp_dir"
    trap - RETURN

    cat <<EOF
========================================
提示：回程判断仅供参考，完整路径可用 nexttrace 手动确认。
EOF
}

uninstall_singbox_and_nodes() {
    info "正在停止并禁用 sing-box 服务..."
    if service_is_running && ! service_stop; then
        err "sing-box 服务停止失败，已取消删除。"
        return 1
    fi
    sleep 1
    if service_is_running; then
        err "sing-box 服务仍在运行，已取消删除。"
        return 1
    fi
    service_disable 2>/dev/null || warn "无法禁用 sing-box 开机启动，将继续卸载已停止的服务。"

    if is_systemd; then
        rm -f /etc/systemd/system/sing-box.service
        systemctl daemon-reload 2>/dev/null || true
        systemctl reset-failed sing-box 2>/dev/null || true
    fi

    if [ "$OS" = "alpine" ]; then
        rm -f /etc/init.d/sing-box
        apk del sing-box 2>/dev/null || true
    elif [ "$OS" = "debian" ]; then
        apt-get purge -y sing-box >/dev/null 2>&1 || true
    elif [ "$OS" = "redhat" ]; then
        if command -v dnf >/dev/null 2>&1; then
            dnf remove -y sing-box >/dev/null 2>&1 || true
        else
            yum remove -y sing-box >/dev/null 2>&1 || true
        fi
    fi

    info "正在删除 sing-box 和节点配置..."
    rm -rf "$CONFIG_DIR"
    rm -f /usr/bin/sing-box /usr/local/bin/sing-box
    rm -f /var/log/sing-box*
    hash -r

    if singbox_installed; then
        err "仍检测到 sing-box 命令，卸载未完全完成：$(command -v sing-box)"
        return 1
    fi

    info "sing-box 和节点配置已删除。"
}

uninstall_all() {
    local confirm
    local remove_singbox

    echo "此操作会卸载 VPSBox 管理命令。"
    echo "默认不会删除 sing-box，也不会删除节点配置。"
    echo "可在确认后恢复 VPSBox 已记录的 DNS、BBR、Fail2ban、NTP、journald 与 IPv4 优先设置。"
    read -r -p "确认卸载 VPSBox？请输入 YES：" confirm
    [ "$confirm" = "YES" ] || { info "已取消。"; return 0; }

    read -r -p "是否同时删除 sing-box 和所有节点配置？请输入 YES 确认：" remove_singbox
    if [ "$remove_singbox" = "YES" ]; then
        uninstall_singbox_and_nodes || {
            err "sing-box 卸载未完成，已保留 VPSBox 管理命令便于重试。"
            return 1
        }
    else
        info "已保留 sing-box 和节点配置。"
    fi

    info "正在删除 VPSBox 命令..."
    rm -f "$CMD_PATH" /usr/bin/vpsbox

    info "卸载完成。"
    info "vpsbox 命令已删除，当前菜单即将退出。"
    exit 0
}

is_valid_hostname_value() {
    local value="$1"
    [ -n "$value" ] && [ "${#value}" -le 253 ] || return 1
    [[ "$value" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]] || return 1
    local label
    IFS='.' read -ra labels <<< "$value"
    for label in "${labels[@]}"; do
        [ -n "$label" ] && [ "${#label}" -le 63 ] || return 1
        [[ "$label" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$ ]] || return 1
    done
}

hostname_current_value() {
    hostnamectl --static 2>/dev/null || hostname 2>/dev/null
}

set_system_hostname() {
    local value="$1"
    if command -v hostnamectl >/dev/null 2>&1; then
        hostnamectl set-hostname "$value"
    else
        hostname "$value"
    fi
}

change_system_hostname() {
    local old new tmp
    old="$(hostname_current_value)"
    echo "当前主机名：$old"
    read -r -p "请输入新主机名（留空取消）: " new
    [ -n "$new" ] || { info "已取消。"; return 0; }
    is_valid_hostname_value "$new" || { err "主机名格式不正确。"; return 1; }
    [ "$new" != "$old" ] || { info "新旧主机名相同。"; return 0; }
    backup_change_file_once HOSTNAME_FILE /etc/hostname || return 1
    backup_change_file_once HOSTS_FILE /etc/hosts || return 1

    tmp="$(mktemp /etc/.hostname.vpsbox.XXXXXX)" || return 1
    printf '%s\n' "$new" > "$tmp"
    if ! chown root:root "$tmp" || ! chmod 644 "$tmp" || ! mv -f "$tmp" /etc/hostname || ! set_system_hostname "$new"; then
        rm -f "$tmp"
        restore_change_file HOSTNAME_FILE /etc/hostname || true
        set_system_hostname "$old" 2>/dev/null || true
        err "主机名修改失败，已尝试恢复原主机名。"
        return 1
    fi

    tmp="$(mktemp /etc/.hosts.vpsbox.XXXXXX)" || {
        restore_change_file HOSTNAME_FILE /etc/hostname || true
        set_system_hostname "$old" 2>/dev/null || true
        return 1
    }
    awk -v begin="$HOSTNAME_BEGIN" -v end="$HOSTNAME_END" '
        $0 == begin { skip=1; next }
        $0 == end { skip=0; next }
        !skip { print }
    ' /etc/hosts > "$tmp"
    {
        printf '%s\n' "$HOSTNAME_BEGIN"
        printf '127.0.1.1 %s\n' "$new"
        printf '%s\n' "$HOSTNAME_END"
    } >> "$tmp"
    if ! chown root:root "$tmp" || ! chmod 644 "$tmp" || ! mv -f "$tmp" /etc/hosts; then
        rm -f "$tmp"
        restore_change_file HOSTNAME_FILE /etc/hostname || true
        restore_change_file HOSTS_FILE /etc/hosts || true
        set_system_hostname "$old" 2>/dev/null || true
        err "更新 /etc/hosts 失败，已恢复原配置。"
        return 1
    fi
    manifest_set HOSTNAME_VALUE "$old" || return 1
    mark_change_applied HOSTNAME || return 1
    info "主机名已修改为：$new"
}

cleanup_size_for() {
    local path="$1"
    [ -d "$path" ] || { echo 0; return; }
    du -sb "$path" 2>/dev/null | awk '{print $1}'
}

cleanup_preview() {
    local path size
    for path in /var/cache/apt /var/cache/dnf /var/cache/yum /var/cache/apk /tmp /var/tmp "$CHANGE_BACKUP_DIR"; do
        [ -d "$path" ] || continue
        size="$(cleanup_size_for "$path")"
        printf '%-30s %s bytes\n' "$path" "$size"
    done
    command -v journalctl >/dev/null 2>&1 && journalctl --disk-usage 2>/dev/null || true
}

cleanup_old_temp_files() {
    local path="$1"
    [ -d "$path" ] || return 0
    find "$path" -xdev -maxdepth 1 -type f -user root -name 'vpsbox-*' -mtime +7 -print -delete 2>/dev/null || true
}

cleanup_orphaned_change_backups() {
    local backup name state
    [ -d "$CHANGE_BACKUP_DIR" ] || return 0
    for backup in "$CHANGE_BACKUP_DIR"/*; do
        [ -f "$backup" ] || continue
        name="${backup##*/}"
        [[ "$name" =~ ^[A-Z0-9_]+$ ]] || continue
        state="$(manifest_value "BACKUP_$name" 2>/dev/null || true)"
        [ "$state" = "file" ] && continue
        if find "$backup" -xdev -type f -mtime +30 -print -delete 2>/dev/null; then
            info "已清理未引用的 VPSBox 备份：$name"
        fi
    done
}

cleanup_system_garbage() {
    local confirm journal_confirm
    echo "将扫描并清理：包管理器缓存、超过 7 天的 VPSBox 临时文件、未引用的 VPSBox 过期备份。"
    echo "不会清理节点配置、用户主目录、Docker 数据卷或数据库。"
    cleanup_preview
    read -r -p "确认执行垃圾清理？请输入 YES：" confirm
    [ "$confirm" = "YES" ] || { info "已取消清理。"; return 0; }

    if command -v apt-get >/dev/null 2>&1; then apt-get clean || warn "APT 缓存清理失败。"; fi
    if command -v dnf >/dev/null 2>&1; then dnf clean all || warn "DNF 缓存清理失败。"; fi
    if command -v yum >/dev/null 2>&1; then yum clean all || warn "YUM 缓存清理失败。"; fi
    if command -v apk >/dev/null 2>&1; then apk cache clean || warn "APK 缓存清理失败。"; fi
    cleanup_old_temp_files /tmp
    cleanup_old_temp_files /var/tmp
    cleanup_orphaned_change_backups || warn "VPSBox 未引用备份清理不完整。"
    if command -v journalctl >/dev/null 2>&1; then
        read -r -p "是否清理超过 30 天的 systemd 日志？请输入 YES，其他输入跳过：" journal_confirm
        if [ "$journal_confirm" = "YES" ]; then
            journalctl --vacuum-time=30d || warn "systemd 历史日志清理失败。"
        else
            info "已跳过 systemd 历史日志清理。"
        fi
    fi
    info "垃圾清理完成，当前占用："
    cleanup_preview
}

show_vpsbox_changes() {
    local name found=0
    echo "VPSBox 已记录的系统变更："
    for name in HOSTNAME DNS_RESOLV DNS_RESOLVED BBR_CONF GAI_CONF FAIL2BAN_SSHD NTP_CONF JOURNALD_CONF; do
        if [ "$(manifest_value "APPLIED_$name" 2>/dev/null || true)" = "1" ]; then
            printf ' - %s：可恢复\n' "$name"
            found=1
        fi
    done
    [ "$found" -eq 1 ] || echo " - 无"
    echo "SSH 配置不会由此功能自动恢复，请保持当前连接并手动核验后处理。"
}

restore_vpsbox_system_changes() {
    local confirm cc fq chrony timesyncd old failed=0

    show_vpsbox_changes
    read -r -p "恢复上述 VPSBox 已记录的系统设置？请输入 YES：" confirm
    [ "$confirm" = "YES" ] || { info "已取消恢复。"; return 0; }

    if [ "$(manifest_value APPLIED_HOSTNAME 2>/dev/null || true)" = "1" ]; then
        restore_change_file HOSTNAME_FILE /etc/hostname || failed=1
        restore_change_file HOSTS_FILE /etc/hosts || failed=1
        old="$(manifest_value HOSTNAME_VALUE 2>/dev/null || true)"
        [ -n "$old" ] && set_system_hostname "$old" 2>/dev/null || failed=1
    fi

    if [ "$(manifest_value APPLIED_DNS_RESOLV 2>/dev/null || true)" = "1" ] && ! restore_change_file DNS_RESOLV /etc/resolv.conf; then failed=1; fi
    if [ "$(manifest_value APPLIED_DNS_RESOLVED 2>/dev/null || true)" = "1" ] && ! restore_change_file DNS_RESOLVED /etc/systemd/resolved.conf.d/vpsbox.conf; then failed=1; fi
    if resolv_conf_managed_by_systemd_resolved && ! systemctl restart systemd-resolved; then failed=1; fi

    if [ "$(manifest_value APPLIED_BBR_CONF 2>/dev/null || true)" = "1" ]; then
        restore_change_file BBR_CONF "$BBR_CONF" || failed=1
        cc="$(manifest_value BBR_CC 2>/dev/null || true)"; fq="$(manifest_value BBR_FQ 2>/dev/null || true)"
        if [ -n "$cc" ] && [ "$cc" != "unknown" ]; then sysctl -w "net.ipv4.tcp_congestion_control=$cc" >/dev/null 2>&1 || failed=1; fi
        if [ -n "$fq" ] && [ "$fq" != "unknown" ]; then sysctl -w "net.core.default_qdisc=$fq" >/dev/null 2>&1 || failed=1; fi
    fi
    if [ "$(manifest_value APPLIED_GAI_CONF 2>/dev/null || true)" = "1" ] && ! restore_change_file GAI_CONF "$GAI_CONF"; then failed=1; fi
    if [ "$(manifest_value APPLIED_FAIL2BAN_SSHD 2>/dev/null || true)" = "1" ]; then
        restore_change_file FAIL2BAN_SSHD "$FAIL2BAN_VPSBOX_SSHD_CONF" || failed=1
        if fail2ban_installed; then
            if is_systemd; then
                systemctl restart fail2ban && systemctl is-active --quiet fail2ban || failed=1
            elif [ "$OS" = "alpine" ] && command -v rc-service >/dev/null 2>&1; then
                rc-service fail2ban restart && rc-service fail2ban status >/dev/null || failed=1
            else
                failed=1
            fi
        fi
    fi
    if [ "$(manifest_value APPLIED_JOURNALD_CONF 2>/dev/null || true)" = "1" ]; then
        restore_change_file JOURNALD_CONF "$JOURNALD_VPSBOX_CONF" || failed=1
        is_systemd && systemctl restart systemd-journald && systemctl is-active --quiet systemd-journald || failed=1
    fi
    if [ "$(manifest_value APPLIED_NTP_CONF 2>/dev/null || true)" = "1" ]; then
        is_systemd || { err "当前环境无法恢复 systemd 管理的 NTP 状态。"; failed=1; }
        chrony="$(chrony_service_name)"
        systemctl stop "$chrony" || failed=1
        restore_change_file NTP_CONF "$(chrony_conf_path)" || failed=1
        restore_change_file NTP_SOURCES /etc/chrony/sources.d/vpsbox.sources || failed=1
        if [ "$(manifest_value NTP_CHRONY_ENABLED 2>/dev/null || true)" = "enabled" ]; then systemctl enable "$chrony" || failed=1; else systemctl disable "$chrony" || failed=1; fi
        if [ "$(manifest_value NTP_CHRONY_ACTIVE 2>/dev/null || true)" = "active" ]; then systemctl start "$chrony" || failed=1; else systemctl stop "$chrony" || failed=1; fi
        timesyncd="$(manifest_value NTP_TIMESYNCD_ENABLED 2>/dev/null || true)"
        if [ "$timesyncd" = "enabled" ]; then systemctl enable systemd-timesyncd || failed=1; else systemctl disable systemd-timesyncd || failed=1; fi
        if [ "$(manifest_value NTP_TIMESYNCD_ACTIVE 2>/dev/null || true)" = "active" ]; then systemctl start systemd-timesyncd || failed=1; else systemctl stop systemd-timesyncd || failed=1; fi
    fi
    if [ "$failed" -eq 1 ]; then
        err "部分文件恢复失败；已保留变更清单和备份，请修复权限或路径后重试。"
        return 1
    fi
    if [ "$(manifest_value APPLIED_HOSTNAME 2>/dev/null || true)" = "1" ]; then
        clear_change_tracking HOSTNAME_FILE || failed=1
        clear_change_tracking HOSTS_FILE || failed=1
        manifest_remove APPLIED_HOSTNAME || failed=1
        manifest_remove HOSTNAME_VALUE || failed=1
    fi
    if [ "$(manifest_value APPLIED_BBR_CONF 2>/dev/null || true)" = "1" ]; then
        clear_change_tracking BBR_CONF || failed=1
        manifest_remove BBR_CC || failed=1
        manifest_remove BBR_FQ || failed=1
    fi
    if [ "$(manifest_value APPLIED_NTP_CONF 2>/dev/null || true)" = "1" ]; then
        clear_change_tracking NTP_CONF || failed=1
        clear_change_tracking NTP_SOURCES || failed=1
        manifest_remove NTP_CHRONY_ACTIVE || failed=1
        manifest_remove NTP_CHRONY_ENABLED || failed=1
        manifest_remove NTP_TIMESYNCD_ACTIVE || failed=1
        manifest_remove NTP_TIMESYNCD_ENABLED || failed=1
    fi
    for name in DNS_RESOLV DNS_RESOLVED GAI_CONF FAIL2BAN_SSHD JOURNALD_CONF; do
        if [ "$(manifest_value "APPLIED_$name" 2>/dev/null || true)" = "1" ]; then
            clear_change_tracking "$name" || failed=1
        fi
    done
    if [ "$failed" -eq 1 ]; then
        err "恢复已完成部分步骤，但清单或备份清理失败，已保留剩余状态供人工核验。"
        return 1
    fi
    info "已恢复已记录项目；请使用自检和对应服务状态确认结果。"
}

start_service_action() {
    if ! node_exists; then
        warn "当前没有节点配置，请先创建节点。"
        return 0
    fi
    install_singbox_if_missing || return 1
    setup_service || return 1
    service_start || return 1
    info "sing-box 服务已启动。"
}

restart_service_action() {
    if ! node_exists; then
        warn "当前没有节点配置，请先创建节点。"
        return 0
    fi
    install_singbox_if_missing || return 1
    setup_service || return 1
    restart_singbox_cleanly || return 1
    info "sing-box 服务已重启。"
}

stop_service_action() {
    service_stop || return 1
    info "sing-box 服务已停止。"
}

singbox_install_state() {
    singbox_installed && echo "已安装" || echo "未安装"
}

node_state() {
    if node_exists; then
        load_state
        case "$PROTOCOL" in
            vless-reality) echo "VLESS Reality" ;;
            *) echo "SS 2022" ;;
        esac
    else
        echo "未创建"
    fi
}

node_address() {
    if ! node_exists; then
        echo "-"
        return
    fi

    load_state
    if [ -n "${DOMAIN:-}" ] && [ -n "${PORT:-}" ]; then
        echo "${DOMAIN}:${PORT}"
    else
        echo "-"
    fi
}

reboot_required_state() {
    if [ -f /var/run/reboot-required ] || [ -f /run/reboot-required ]; then
        echo "需要"
    else
        echo "不需要"
    fi
}

journal_disk_usage() {
    if command -v journalctl >/dev/null 2>&1; then
        journalctl --disk-usage 2>/dev/null | sed -E 's/^Archived and active journals take up //; s/\.$//'
    else
        echo "无法检测"
    fi
}

journald_conf_value() {
    local key="$1"
    local value

    if command -v systemd-analyze >/dev/null 2>&1; then
        value="$(systemd-analyze cat-config systemd/journald.conf 2>/dev/null | awk -F= -v key="$key" '$0 ~ "^[[:space:]]*" key "=" { value=$2 } END { print value }' || true)"
    else
        value="$(grep -E "^[[:space:]]*$key=" "$JOURNALD_VPSBOX_CONF" /etc/systemd/journald.conf 2>/dev/null | tail -n 1 | cut -d= -f2- || true)"
    fi
    [ -n "$value" ] || return 1
    printf '%s\n' "$value"
}

journald_limit_state() {
    local max_use
    local max_file

    max_use="$(journald_conf_value SystemMaxUse || true)"
    max_file="$(journald_conf_value SystemMaxFileSize || true)"

    if [ "$max_use" = "500M" ] && [ "$max_file" = "50M" ]; then
        echo "已配置"
    else
        echo "未配置"
    fi
}

limit_systemd_journal() {
    local conf_dir backup_dir tmp had_old=0 confirm

    if ! is_systemd; then
        err "未检测到 systemd，无法配置 systemd-journald。"
        return 1
    fi

    if ! command -v journalctl >/dev/null 2>&1; then
        err "未找到 journalctl，无法清理 systemd 日志。"
        return 1
    fi

    conf_dir="$(dirname "$JOURNALD_VPSBOX_CONF")"
    if [ -L "$conf_dir" ] || [ -L "$JOURNALD_VPSBOX_CONF" ]; then
        err "journald 配置路径包含符号链接，已拒绝修改。"
        return 1
    fi
    mkdir -p "$conf_dir" || return 1
    backup_change_file_once JOURNALD_CONF "$JOURNALD_VPSBOX_CONF" || { err "记录 journald 原配置失败，已取消修改。"; return 1; }
    backup_dir="$(mktemp -d /tmp/vpsbox-journald.XXXXXX)" || return 1
    if [ -e "$JOURNALD_VPSBOX_CONF" ]; then
        cp -a "$JOURNALD_VPSBOX_CONF" "$backup_dir/99-vpsbox.conf" || { rm -rf "$backup_dir"; err "备份 journald 配置失败。"; return 1; }
        had_old=1
    fi
    tmp="$(mktemp "$conf_dir/.99-vpsbox.XXXXXX")" || { rm -rf "$backup_dir"; return 1; }
    cat > "$tmp" <<EOF
[Journal]
SystemMaxUse=500M
SystemMaxFileSize=50M
EOF
    if ! chown root:root "$tmp" || ! chmod 644 "$tmp" || ! mv -f "$tmp" "$JOURNALD_VPSBOX_CONF"; then
        rm -f "$tmp"
        rm -rf "$backup_dir"
        err "写入 journald 配置失败。"
        return 1
    fi

    if ! systemctl restart systemd-journald || ! systemctl is-active --quiet systemd-journald || [ "$(journald_conf_value SystemMaxUse || true)" != "500M" ] || [ "$(journald_conf_value SystemMaxFileSize || true)" != "50M" ]; then
        err "journald 配置未生效，正在恢复原配置。"
        if [ "$had_old" -eq 1 ]; then cp -a "$backup_dir/99-vpsbox.conf" "$JOURNALD_VPSBOX_CONF"; else rm -f "$JOURNALD_VPSBOX_CONF"; fi
        systemctl restart systemd-journald 2>/dev/null || true
        rm -rf "$backup_dir"
        return 1
    fi
    rm -rf "$backup_dir"
    mark_change_applied JOURNALD_CONF || return 1
    info "systemd 日志限制已设置。"
    info "当前日志占用：$(journal_disk_usage)"
    info "总大小：500M"
    info "单文件：50M"
    read -r -p "是否立即清理历史日志至 500M？此操作不可恢复。请输入 YES 确认：" confirm
    if [ "$confirm" = "YES" ]; then
        retry 3 2 journalctl --vacuum-size=500M
        info "清理完成，当前日志占用：$(journal_disk_usage)"
    else
        info "已跳过清理历史日志；新限制会在后续日志轮转中生效。"
    fi
}

show_menu() {
    clear 2>/dev/null || true
    cat <<EOF
========================================
 $APP_NAME
========================================
 版本：$VPSBOX_VERSION
 提示：输入 vpsbox 打开管理面板
$(vpsbox_update_notice)
----------------------------------------
 sing-box：$(singbox_install_state)
 sing-box 状态：$(service_status_short)
 sing-box 版本：$(singbox_version)
 当前节点：$(node_state)
 节点地址：$(node_address)
----------------------------------------
 IPv4 DNS：
$(ipv4_dns_lines)
----------------------------------------
 1) 节点管理
 2) sing-box 管理
 3) 系统优化
 4) 一键自检
 5) 查看三网回程
----------------------------------------
 8) 更新 vpsbox 脚本
 9) 卸载 VPSBox
 0) 退出
========================================
EOF
}

node_menu() {
    local opt

    while true; do
        clear 2>/dev/null || true
        cat <<EOF
========================================
 节点管理
========================================
 当前节点：$(node_state)
 节点地址：$(node_address)
----------------------------------------
 1) 创建/重建 SS 2022 节点
 2) 创建/重建 VLESS Reality 节点
 3) 查看节点链接
 4) 删除当前节点
 0) 返回主菜单
========================================
EOF
        read -r -p "请输入选项: " opt || exit 0
        echo ""

        case "$opt" in
            1) run_menu_action create_or_rebuild_node; pause ;;
            2) run_menu_action create_vless_reality_node; pause ;;
            3) run_menu_action view_node_link; pause ;;
            4) run_menu_action delete_node; pause ;;
            0) return 0 ;;
            *) warn "无效选项：$opt"; pause ;;
        esac
    done
}

singbox_menu() {
    local opt

    while true; do
        clear 2>/dev/null || true
        cat <<EOF
========================================
 sing-box 管理
========================================
 sing-box：$(singbox_install_state)
 sing-box 状态：$(service_status_short)
 sing-box 版本：$(singbox_version)
----------------------------------------
 1) 启动 sing-box 服务
 2) 停止 sing-box 服务
 3) 重启 sing-box 服务
 4) 更新 sing-box
 0) 返回主菜单
========================================
EOF
        read -r -p "请输入选项: " opt || exit 0
        echo ""

        case "$opt" in
            1) run_menu_action start_service_action; pause ;;
            2) run_menu_action stop_service_action; pause ;;
            3) run_menu_action restart_service_action; pause ;;
            4) run_menu_action update_singbox; pause ;;
            0) return 0 ;;
            *) warn "无效选项：$opt"; pause ;;
        esac
    done
}

system_menu() {
    local opt

    while true; do
        clear 2>/dev/null || true
        cat <<EOF
========================================
 系统优化
========================================
 BBR：$(bbr_state)
 fq：$(fq_state)
 IPv4 优先：$(ipv4_priority_state)
 SSH 端口：$(ssh_port_state)
 SSH 加固：$(ssh_hardening_state)
 Fail2ban：$(fail2ban_service_state)
 SSH 防护：$(fail2ban_sshd_state)
 NTP 同步：$(ntp_sync_state)
 系统重启：$(reboot_required_state)
----------------------------------------
 1) 系统更新
 2) 一键开启 BBR + fq
 3) 安装 Fail2ban
 4) 限制 systemd 日志大小
 5) 修改系统 IPv4 DNS
 6) 启用系统 IPv4 优先
 7) 修改 SSH 端口
 8) SSH 基础加固
 9) 查看 SSH 当前生效配置
 10) 开启 NTP 时间同步
 11) 查看/恢复 VPSBox 系统改动
 12) 垃圾清理
 13) 修改主机名
 0) 返回主菜单
========================================
EOF
        read -r -p "请输入选项: " opt || exit 0
        echo ""

        case "$opt" in
            1) run_menu_action update_system_packages; pause ;;
            2) run_menu_action enable_bbr_fq; pause ;;
            3) run_menu_action install_fail2ban; pause ;;
            4) run_menu_action limit_systemd_journal; pause ;;
            5) run_menu_action change_ipv4_dns; pause ;;
            6) run_menu_action enable_ipv4_priority; pause ;;
            7) ssh_port_change_menu ;;
            8) ssh_basic_hardening_menu ;;
            9) run_menu_action show_current_ssh_config; pause ;;
            10) run_menu_action enable_ntp_sync; pause ;;
            11) run_menu_action restore_vpsbox_system_changes; pause ;;
            12) run_menu_action cleanup_system_garbage; pause ;;
            13) run_menu_action change_system_hostname; pause ;;
            0) return 0 ;;
            *) warn "无效选项：$opt"; pause ;;
        esac
    done
}

main_loop() {
    while true; do
        show_menu
        read -r -p "请输入选项: " opt || exit 0
        echo ""

        case "$opt" in
            1) run_menu_action node_menu ;;
            2) run_menu_action singbox_menu ;;
            3) run_menu_action system_menu ;;
            4) run_menu_action run_self_check; pause ;;
            5) run_menu_action show_backtrace_routes; pause ;;
            8) update_vpsbox; pause ;;
            9) uninstall_all; pause ;;
            0) exit 0 ;;
            *) warn "无效选项：$opt"; pause ;;
        esac
    done
}

need_root
detect_os
acquire_lock
install_self_command
check_vpsbox_update_on_start
main_loop
