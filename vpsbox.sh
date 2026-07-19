#!/usr/bin/env bash
set -euo pipefail
umask 077

APP_NAME="vpsbox"
VPSBOX_VERSION="v1.0.34"
# 只从当前仓库下载可执行脚本；旧地址仅用于识别本地 v1.0.23 及更早备份，绝不联网获取。
SCRIPT_URL="https://raw.githubusercontent.com/TianPingXi/vpsbox/main/vpsbox.sh"
LEGACY_SCRIPT_URL="https://raw.githubusercontent.com/QXTianPing/vpsbox/main/vpsbox.sh"
SINGBOX_RELEASE_VERSION="1.13.14"
NEXTTRACE_RELEASE_VERSION="1.7.1"
DEFAULT_REALITY_SERVER_NAME="addons.mozilla.org"
CMD_PATH="/usr/local/bin/vpsbox"
CONFIG_DIR="/etc/sing-box"
# sing-box 软件包可能生成默认 config.json；vpsbox 节点只使用 vpsbox.d 独立配置。
URI_FILE="$CONFIG_DIR/vpsbox-uri.txt"
NODE_CONFIG_DIR="$CONFIG_DIR/vpsbox.d"
SS_CONFIG_PATH="$NODE_CONFIG_DIR/10-ss.json"
VLESS_CONFIG_PATH="$NODE_CONFIG_DIR/20-vless-reality.json"
SS_STATE_FILE="$CONFIG_DIR/vpsbox-ss.env"
VLESS_STATE_FILE="$CONFIG_DIR/vpsbox-vless.env"
SS_URI_FILE="$CONFIG_DIR/vpsbox-ss-uri.txt"
VLESS_URI_FILE="$CONFIG_DIR/vpsbox-vless-uri.txt"
BBR_CONF="/etc/sysctl.d/99-vpsbox-bbr.conf"
JOURNALD_VPSBOX_CONF="/etc/systemd/journald.conf.d/99-vpsbox.conf"
VPSBOX_STATE_DIR="/etc/vpsbox"
CHANGE_MANIFEST="$VPSBOX_STATE_DIR/changes.env"
CHANGE_BACKUP_DIR="$VPSBOX_STATE_DIR/backups"
NODE_TRANSACTION_DIR="$VPSBOX_STATE_DIR/node-transaction"
NODE_TRANSACTION_BACKUP="$NODE_TRANSACTION_DIR/backup"
NODE_TRANSACTION_STAGE="$NODE_TRANSACTION_DIR/stage"
SINGBOX_UPDATE_TRANSACTION_DIR="$VPSBOX_STATE_DIR/singbox-update"
SINGBOX_UPDATE_TRANSACTION_STATE="$SINGBOX_UPDATE_TRANSACTION_DIR/state"
GAI_CONF="/etc/gai.conf"
RESOLV_CONF="/etc/resolv.conf"
NTP_SOURCES_BEGIN="# BEGIN VPSBOX NTP SOURCES"
NTP_SOURCES_END="# END VPSBOX NTP SOURCES"
CHRONY_SOURCE_FILE="/etc/chrony/sources.d/vpsbox.sources"
HOSTNAME_BEGIN="# BEGIN VPSBOX HOSTNAME"
HOSTNAME_END="# END VPSBOX HOSTNAME"
HOSTNAME_PATH="/etc/hostname"
HOSTS_PATH="/etc/hosts"
SSHD_MAIN_CONF="/etc/ssh/sshd_config"
SSHD_CONFIG_DIR="/etc/ssh/sshd_config.d"
SSHD_VPSBOX_PORT_CONF="$SSHD_CONFIG_DIR/00-vpsbox-ssh-port.conf"
SSHD_VPSBOX_HARDENING_CONF="$SSHD_CONFIG_DIR/01-vpsbox-ssh-hardening.conf"
SSH_TARGET_PORT="23333"
FAIL2BAN_CONFIG_DIR="/etc/fail2ban/jail.d"
FAIL2BAN_VPSBOX_SSHD_CONF="$FAIL2BAN_CONFIG_DIR/99-vpsbox-sshd.local"
FIREWALL_CONFIG="$VPSBOX_STATE_DIR/firewall.nft"
FIREWALL_STATE_FILE="$VPSBOX_STATE_DIR/firewall.env"
FIREWALL_SYSTEMD_UNIT="/etc/systemd/system/vpsbox-firewall.service"
FIREWALL_OPENRC_SERVICE="/etc/init.d/vpsbox-firewall"
FIREWALL_SERVICE_NAME="vpsbox-firewall"
FIREWALL_ROLLBACK_SECONDS=90
FIREWALL_ROLLBACK_DIR="$VPSBOX_STATE_DIR/firewall-rollbacks"
PACKAGE_CONNECT_TIMEOUT=15
PACKAGE_UPDATE_TIMEOUT=120
PACKAGE_INSTALL_TIMEOUT=600
SYSTEM_UPGRADE_TIMEOUT=7200
VPSBOX_UPDATE_STARTUP_TIMEOUT=60
PACKAGE_KILL_GRACE=10
PACKAGE_RETRY_MAX=2
PACKAGE_RETRY_DELAY=2
ACTIVE_BOUNDED_PID=""
ACTIVE_BOUNDED_START=""
ACTIVE_BOUNDED_TIMER_PID=""
ACTIVE_BOUNDED_MARKER=""
RUNTIME_DIR="/run/vpsbox"
LOCK_FILE="$RUNTIME_DIR/vpsbox.lock"
LOCK_DIR="$RUNTIME_DIR/lockdir"
LOCK_RECLAIM_DIR="$RUNTIME_DIR/lockdir-reclaim"
LOCK_USING_FLOCK=0
LOCK_USING_DIR=0
ACTIVE_NODE_BACKUP=""
ACTIVE_NODE_TRANSACTION_MUTATED=0
ACTIVE_FIREWALL_TRANSITION_DIR=""
ACTIVE_SSH_FIREWALL_TRANSITION=0
ACTIVE_FIREWALL_ROLLBACK_DIR=""
ACTIVE_TRACE_TMP=""
ACTIVE_UNAPPLIED_SSH_TRACKING=0
ACTIVE_FAIL2BAN_TEST_IP=""
ACTIVE_FAIL2BAN_TEST_BACKENDS=""
ACTIVE_SINGBOX_UPDATE_BINARY=""
ACTIVE_SINGBOX_UPDATE_BACKUP=""
ACTIVE_SINGBOX_UPDATE_DIR=""
ACTIVE_SINGBOX_UPDATE_PACKAGE=""
ACTIVE_SINGBOX_UPDATE_OLD_VERSION=""
ACTIVE_SINGBOX_UPDATE_WAS_ENABLED=0
ACTIVE_SINGBOX_UPDATE_WAS_ACTIVE=0
ACTIVE_SINGBOX_UPDATE_MUTATED=0
ACTIVE_SINGBOX_UPDATE_ROLLING_BACK=0
SERVICE_NAME="sing-box"
SS_METHOD="2022-blake3-aes-128-gcm"
METHOD="$SS_METHOD"
PORT_MIN=10000
PORT_MAX=60000
TRACE_NAMES=(
    "北京电信" "北京联通" "北京移动"
    "上海电信" "上海联通" "上海移动"
    "广东电信" "广东联通" "广东移动"
    "安徽电信" "安徽联通" "安徽移动"
    "江苏电信" "江苏联通" "江苏移动"
)
TRACE_IPS=(
    "106.37.68.13" "221.222.185.232" "211.136.25.153"
    "101.226.101.195" "112.64.235.107" "117.185.117.117"
    "183.47.102.91" "157.148.63.62" "211.139.145.129"
    "117.68.18.76" "112.132.39.144" "39.145.24.107"
    "117.62.242.159" "112.80.130.226" "36.155.213.87"
)
TRACE_REGIONS=("北京" "上海" "广东" "安徽" "江苏")
TRACE_ISPS=("电信" "联通" "移动")
TRACE_SIZE_SMALL=64
TRACE_SIZE_LARGE=1400
TRACE_SIZE_QUERIES=3
REMOTE_VERSION=""
UPDATE_AVAILABLE=0
PENDING_VPSBOX_UPDATE_BACKUP="${VPSBOX_UPDATE_BACKUP:-}"
PENDING_VPSBOX_UPDATE_READY_FILE="${VPSBOX_UPDATE_READY_FILE:-}"
VPSBOX_UPDATE_STARTUP_CONFIRMED=0
VPSBOX_UPDATE_WATCHDOG_PID=""
VPSBOX_UPDATE_WATCHDOG_DIR=""
FW_EXTRA_TCP=""
FW_EXTRA_UDP=""
FW_SSH_PORTS=""
FW_NODE_TCP=""
FW_NODE_UDP=""
FW_PUBLIC_TCP=""
FW_PUBLIC_UDP=""
FW_OTHER_PUBLIC_TCP=""
FW_OTHER_PUBLIC_UDP=""
FW_DOCKER_TCP=""
FW_DOCKER_UDP=""
FW_DOCKER_PUBLIC_TCP=""
FW_DOCKER_PUBLIC_UDP=""
FW_DOCKER_PUBLIC4_TCP=""
FW_DOCKER_PUBLIC4_UDP=""
FW_DOCKER_PUBLIC6_TCP=""
FW_DOCKER_PUBLIC6_UDP=""
FW_DOCKER_PROXY4_TCP=""
FW_DOCKER_PROXY4_UDP=""
FW_DOCKER_PROXY6_TCP=""
FW_DOCKER_PROXY6_UDP=""
FW_DOCKER_BRIDGES=""
FW_DOCKER_DAEMON_PID=""
FW_DOCKER_DAEMON_START_TICKS=""
FW_DOCKER_HOST_NETWORK=0
FW_DOCKER_DYNAMIC_PORT=0
FW_DOCKER_DIRECT_NETWORK=0
FW_DOCKER_CUSTOM_BRIDGE=0
FW_ALLOWED_TCP=""
FW_ALLOWED_UDP=""

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

run_bounded_in_new_session() {
    local limit="$1" marker pid start="" timer status marker_state i

    shift
    marker="$(mktemp /tmp/vpsbox-command-timeout.XXXXXX)" || return 1
    printf '%s\n' pending > "$marker"
    # 后台命令必须关闭菜单锁描述符；否则父菜单被 SIGKILL 后，子进程会继续占用 flock。
    setsid "$@" 200>&- &
    pid=$!

    for i in {1..50}; do
        if ! process_alive "$pid" || process_is_zombie "$pid"; then
            if wait "$pid"; then status=0; else status=$?; fi
            if [ "$status" -ne 0 ] && bounded_session_has_processes "$pid"; then
                terminate_bounded_session "$pid" 1
            fi
            rm -f -- "$marker"
            return "$status"
        fi
        start="$(process_start_ticks "$pid" || true)"
        if [[ "$start" =~ ^[0-9]+$ ]] && bounded_process_group_matches "$pid" "$start"; then
            break
        fi
        start=""
        sleep 0.02
    done
    if [ -z "$start" ]; then
        kill -TERM "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
        rm -f -- "$marker"
        err "无法为命令建立独立进程组，已取消执行：$1"
        return 125
    fi

    ACTIVE_BOUNDED_PID="$pid"
    ACTIVE_BOUNDED_START="$start"
    ACTIVE_BOUNDED_MARKER="$marker"
    (
        sleep "$limit"
        if bounded_process_group_matches "$pid" "$start"; then
            printf '%s\n' timeout > "$marker"
            terminate_bounded_session "$pid" "$PACKAGE_KILL_GRACE"
        fi
    ) 200>&- &
    timer=$!
    ACTIVE_BOUNDED_TIMER_PID="$timer"

    if wait "$pid"; then status=0; else status=$?; fi
    marker_state="$(cat "$marker" 2>/dev/null || true)"
    if [ "$marker_state" = "timeout" ]; then
        wait "$timer" 2>/dev/null || true
        status=124
    else
        kill -TERM "$timer" 2>/dev/null || true
        wait "$timer" 2>/dev/null || true
        if [ "$status" -ne 0 ] && bounded_session_has_processes "$pid"; then
            terminate_bounded_session "$pid" 1
        fi
    fi

    ACTIVE_BOUNDED_PID=""
    ACTIVE_BOUNDED_START=""
    ACTIVE_BOUNDED_TIMER_PID=""
    ACTIVE_BOUNDED_MARKER=""
    rm -f -- "$marker"
    return "$status"
}

run_bounded_with_timeout() {
    local limit="$1" status

    shift
    if timeout -k 1 1 true 200>&- >/dev/null 2>&1; then
        if timeout -k "$PACKAGE_KILL_GRACE" "$limit" "$@" 200>&-; then return 0; else status=$?; fi
    else
        # 兼容 BusyBox 1.35 之前不支持 timeout -k 的版本；旧 Alpine 仍可能使用该实现，
        # 因此保留普通 timeout 回退。两条 timeout 路径都必须关闭 FD 200，避免旧系统
        # 在父菜单异常退出后由包管理子进程继续占用 vpsbox 菜单锁。
        warn "当前 timeout 不支持强制终止延迟，使用兼容模式。"
        if timeout "$limit" "$@" 200>&-; then return 0; else status=$?; fi
    fi
    return "$status"
}

run_bounded_command() {
    local limit="$1" status

    shift
    [[ "$limit" =~ ^[1-9][0-9]*$ ]] && [ "$#" -gt 0 ] || return 2
    if command -v setsid >/dev/null 2>&1; then
        if run_bounded_in_new_session "$limit" "$@"; then return 0; else status=$?; fi
    elif command -v timeout >/dev/null 2>&1; then
        if run_bounded_with_timeout "$limit" "$@"; then return 0; else status=$?; fi
    else
        err "缺少 setsid/timeout，已拒绝执行无时限命令：$1"
        return 127
    fi
    case "$status" in
        124|137|143)
            err "命令执行超时或被强制终止（上限 ${limit} 秒）：$1"
            ;;
    esac
    return "$status"
}

retry_bounded_command() {
    local max="$1" delay="$2" limit="$3"
    local attempt=1 status=0

    shift 3
    while [ "$attempt" -le "$max" ]; do
        if run_bounded_command "$limit" "$@"; then
            return 0
        else
            status=$?
        fi
        case "$status" in
            124|125|126|127|137|143) return "$status" ;;
        esac
        if [ "$attempt" -ge "$max" ]; then
            err "命令重试 ${max} 次后仍失败：$*"
            return "$status"
        fi
        warn "命令失败，${delay} 秒后重试（${attempt}/${max}）：$*"
        sleep "$delay"
        attempt=$((attempt + 1))
    done
}

apt_get_bounded() {
    local limit="$1"

    shift
    retry_bounded_command "$PACKAGE_RETRY_MAX" "$PACKAGE_RETRY_DELAY" "$limit" \
        apt-get \
        -o "Acquire::Retries=1" \
        -o "Acquire::http::Timeout=$PACKAGE_CONNECT_TIMEOUT" \
        -o "Acquire::https::Timeout=$PACKAGE_CONNECT_TIMEOUT" \
        -o "Dpkg::Lock::Timeout=$PACKAGE_CONNECT_TIMEOUT" \
        "$@"
}

apk_bounded() {
    local limit="$1"

    shift
    retry_bounded_command "$PACKAGE_RETRY_MAX" "$PACKAGE_RETRY_DELAY" "$limit" apk "$@"
}

dnf_bounded() {
    local limit="$1"

    shift
    retry_bounded_command "$PACKAGE_RETRY_MAX" "$PACKAGE_RETRY_DELAY" "$limit" \
        dnf --setopt="timeout=$PACKAGE_CONNECT_TIMEOUT" --setopt="retries=1" "$@"
}

yum_bounded() {
    local limit="$1"

    shift
    retry_bounded_command "$PACKAGE_RETRY_MAX" "$PACKAGE_RETRY_DELAY" "$limit" \
        yum --setopt="timeout=$PACKAGE_CONNECT_TIMEOUT" --setopt="retries=1" "$@"
}

pause() {
    echo ""
    read -r -p "按回车返回当前菜单..." _ || exit 0
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

    if ! chown root:root "$RUNTIME_DIR" 2>/dev/null ||
        ! chmod 700 "$RUNTIME_DIR" 2>/dev/null; then
        err "无法保护运行目录：$RUNTIME_DIR"
        exit 1
    fi
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

process_is_zombie() {
    local pid="$1" stat

    stat="$(cat "/proc/$pid/stat" 2>/dev/null)" || return 1
    stat="${stat##*) }"
    [ "${stat%% *}" = "Z" ]
}

process_group_session_ids() {
    local pid="$1" stat _state _ppid pgrp session

    stat="$(cat "/proc/$pid/stat" 2>/dev/null)" || return 1
    stat="${stat##*) }"
    read -r _state _ppid pgrp session _ <<< "$stat"
    [[ "$pgrp" =~ ^[0-9]+$ && "$session" =~ ^[0-9]+$ ]] || return 1
    printf '%s %s\n' "$pgrp" "$session"
}

bounded_process_group_identity_matches() {
    local pid="$1" expected_start="$2" ids

    process_alive "$pid" || return 1
    [ "$(process_start_ticks "$pid" 2>/dev/null || true)" = "$expected_start" ] || return 1
    ids="$(process_group_session_ids "$pid" || true)"
    [ "$ids" = "$pid $pid" ]
}

bounded_process_group_matches() {
    local pid="$1" expected_start="$2"

    bounded_process_group_identity_matches "$pid" "$expected_start" || return 1
    ! process_is_zombie "$pid"
}

bounded_session_has_processes() {
    local session="$1" stat_path stat _state _ppid _pgrp sid

    for stat_path in /proc/[0-9]*/stat; do
        [ -r "$stat_path" ] || continue
        stat="$(cat "$stat_path" 2>/dev/null || true)"
        [ -n "$stat" ] || continue
        stat="${stat##*) }"
        read -r _state _ppid _pgrp sid _ <<< "$stat"
        [ "$sid" = "$session" ] && return 0
    done
    return 1
}

bounded_session_signal() {
    local session="$1" signal="$2" stat_path stat _state _ppid _pgrp sid pid leader_matches=0

    case "$signal" in TERM|KILL) ;; *) return 2 ;; esac
    # 会话成员只能由该命令派生；先通知子进程，最后通知会话 leader。
    for stat_path in /proc/[0-9]*/stat; do
        [ -r "$stat_path" ] || continue
        pid="${stat_path#/proc/}"
        pid="${pid%/stat}"
        [ "$pid" != "$$" ] && [ "$pid" -gt 1 ] || continue
        stat="$(cat "$stat_path" 2>/dev/null || true)"
        [ -n "$stat" ] || continue
        stat="${stat##*) }"
        read -r _state _ppid _pgrp sid _ <<< "$stat"
        [ "$sid" = "$session" ] || continue
        if [ "$pid" = "$session" ]; then
            leader_matches=1
            continue
        fi
        kill "-$signal" "$pid" 2>/dev/null || true
    done
    if [ "$leader_matches" -eq 1 ]; then
        kill "-$signal" "$session" 2>/dev/null || true
    fi
}

terminate_bounded_session() {
    local session="$1" grace="$2" i loops

    bounded_session_signal "$session" TERM
    loops=$((grace * 10))
    [ "$loops" -gt 0 ] || loops=1
    for ((i = 0; i < loops; i++)); do
        bounded_session_has_processes "$session" || return 0
        sleep 0.1
    done
    if bounded_session_has_processes "$session"; then
        bounded_session_signal "$session" KILL
    fi
}

cleanup_active_bounded_command() {
    local pid="${ACTIVE_BOUNDED_PID:-}" start="${ACTIVE_BOUNDED_START:-}"
    local timer="${ACTIVE_BOUNDED_TIMER_PID:-}" marker="${ACTIVE_BOUNDED_MARKER:-}"

    ACTIVE_BOUNDED_PID=""
    ACTIVE_BOUNDED_START=""
    ACTIVE_BOUNDED_TIMER_PID=""
    ACTIVE_BOUNDED_MARKER=""
    if is_pid "$timer"; then
        kill -TERM "$timer" 2>/dev/null || true
        wait "$timer" 2>/dev/null || true
    fi
    if is_pid "$pid" && [[ "$start" =~ ^[0-9]+$ ]] &&
        { bounded_process_group_identity_matches "$pid" "$start" ||
            { ! process_alive "$pid" && bounded_session_has_processes "$pid"; }; }; then
        terminate_bounded_session "$pid" 1
        wait "$pid" 2>/dev/null || true
    fi
    if [[ "$marker" == /tmp/vpsbox-command-timeout.* ]] && [ -f "$marker" ] && [ ! -L "$marker" ]; then
        rm -f -- "$marker"
    fi
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
        if [ -f "$LOCK_FILE" ] && [ ! -L "$LOCK_FILE" ]; then
            : > "$LOCK_FILE"
        fi
        flock -u 200 2>/dev/null || true
        exec 200>&-
        LOCK_USING_FLOCK=0
    fi
    if [ "$LOCK_USING_DIR" = "1" ] && [ -d "$LOCK_DIR" ] && [ ! -L "$LOCK_DIR" ]; then
        rm -rf "$LOCK_DIR"
        LOCK_USING_DIR=0
    fi
}

cleanup_active_trace_tmp() {
    local tmp_dir="${ACTIVE_TRACE_TMP:-}"

    ACTIVE_TRACE_TMP=""
    if [[ "$tmp_dir" == /tmp/vpsbox-trace.* ]] && [ -d "$tmp_dir" ] && [ ! -L "$tmp_dir" ]; then
        rm -rf -- "$tmp_dir"
    fi
}

cleanup_vpsbox_runtime() {
    local backup="${ACTIVE_NODE_BACKUP:-}"
    local firewall_rollback="${ACTIVE_FIREWALL_ROLLBACK_DIR:-}"
    if declare -F cleanup_active_bounded_command >/dev/null 2>&1; then
        cleanup_active_bounded_command
    fi
    if declare -F rollback_active_singbox_update >/dev/null 2>&1; then
        rollback_active_singbox_update ||
            warn "sing-box 更新被中断，旧版本或原服务状态未能完整恢复；更新备份已保留。"
    fi
    if [ "$backup" = "$NODE_TRANSACTION_DIR" ] && [ -d "$backup" ]; then
        if declare -F rollback_active_node_transaction >/dev/null 2>&1; then
            rollback_active_node_transaction ||
                warn "节点操作被中断，自动恢复未完成；事务备份已保留：$NODE_TRANSACTION_DIR"
        elif declare -F restore_node_files >/dev/null 2>&1; then
            ACTIVE_NODE_BACKUP=""
            restore_node_files "$NODE_TRANSACTION_BACKUP" ||
                warn "节点操作被中断，自动恢复未完成；事务备份已保留：$NODE_TRANSACTION_DIR"
        fi
    fi
    if [ "${ACTIVE_SSH_FIREWALL_TRANSITION:-0}" = "1" ] &&
        declare -F ssh_firewall_transition_reconcile >/dev/null 2>&1; then
        ssh_firewall_transition_reconcile ||
            warn "SSH 端口切换被中断，无法自动对账；临时放行规则已保留，请重新进入防火墙菜单更新。"
    fi
    if [ "${ACTIVE_SSH_FIREWALL_TRANSITION:-0}" != "1" ] &&
        declare -F firewall_abort_port_transition >/dev/null 2>&1; then
        firewall_abort_port_transition ||
            warn "端口切换被中断，防火墙临时规则恢复失败，请重新进入防火墙菜单更新。"
    fi
    if declare -F firewall_rollback_dir_valid >/dev/null 2>&1 &&
        firewall_rollback_dir_valid "$firewall_rollback" &&
        [ -d "$firewall_rollback" ] && [ ! -L "$firewall_rollback" ] &&
        declare -F firewall_restore_snapshot_now >/dev/null 2>&1; then
        if [ -e "$firewall_rollback/completed" ]; then
            ACTIVE_FIREWALL_ROLLBACK_DIR=""
            if declare -F firewall_cleanup_finished_rollback >/dev/null 2>&1; then
                firewall_cleanup_finished_rollback "$firewall_rollback" ||
                    warn "防火墙规则已提交，但回滚进程清理尚未完成：$firewall_rollback"
            else
                rm -rf "$firewall_rollback"
            fi
        elif [ "$(cat "$firewall_rollback/decision" 2>/dev/null || true)" = "commit" ]; then
            firewall_restore_snapshot_now "$firewall_rollback" 1 ||
                warn "防火墙操作被中断，自动恢复失败；快照已保留：$firewall_rollback"
        else
            firewall_restore_snapshot_now "$firewall_rollback" 0 ||
                warn "防火墙操作被中断，自动恢复失败；快照已保留：$firewall_rollback"
        fi
    fi
    if declare -F cleanup_active_fail2ban_test >/dev/null 2>&1; then
        cleanup_active_fail2ban_test ||
            warn "Fail2ban 测试地址自动解封失败，请按错误提示手动清理。"
    fi
    if [ "${ACTIVE_UNAPPLIED_SSH_TRACKING:-0}" = "1" ] &&
        declare -F cleanup_unapplied_ssh_tracking >/dev/null 2>&1; then
        cleanup_unapplied_ssh_tracking 0 ||
            warn "SSH 首次事务被中断，未能完整清理尚未应用的恢复基线。"
    fi
    cleanup_active_trace_tmp
    cleanup_vpsbox_lock
    if declare -F rollback_pending_vpsbox_update >/dev/null 2>&1; then
        rollback_pending_vpsbox_update ||
            warn "新版 vpsbox 启动失败，旧版脚本未能自动恢复，请检查 ${CMD_PATH}.previous。"
    fi
}

install_lock_cleanup_traps() {
    trap cleanup_vpsbox_runtime EXIT
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM
    trap 'exit 131' QUIT
}

lock_pid_from_file() {
    local path="$1"
    local pid=""

    [ -f "$path" ] || return 1
    # 兼容早期版本仅写入 pid/started 的锁元数据。升级后可能仍遇到旧锁文件，
    # 但缺少 start_ticks/boot_id 时不能防止 PID 复用，因此只读取 PID 并进入人工确认路径。
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

wait_for_lockdir_metadata() {
    local i

    # mkdir 是原子的，但创建者在写入 pid 元数据前存在极短窗口；等待后再判断残留，
    # 避免没有 flock 的系统上两个并发菜单互相删除刚创建的有效锁。
    for i in {1..10}; do
        [ -s "$LOCK_DIR/pid" ] && return 0
        [ -d "$LOCK_DIR" ] && [ ! -L "$LOCK_DIR" ] || return 1
        sleep 0.1
    done
    [ -s "$LOCK_DIR/pid" ]
}

lockdir_reclaim_owner_matches() {
    local path="$LOCK_RECLAIM_DIR/owner" pid start boot

    [ -f "$path" ] && [ ! -L "$path" ] || return 1
    pid="$(awk -F= '$1 == "pid" { print $2; exit }' "$path" 2>/dev/null || true)"
    start="$(awk -F= '$1 == "start_ticks" { print $2; exit }' "$path" 2>/dev/null || true)"
    boot="$(awk -F= '$1 == "boot_id" { print $2; exit }' "$path" 2>/dev/null || true)"
    is_pid "$pid" && [[ "$start" =~ ^[0-9]+$ ]] && [ -n "$boot" ] || return 1
    process_alive "$pid" &&
        [ "$(process_start_ticks "$pid" 2>/dev/null || true)" = "$start" ] &&
        [ "$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || true)" = "$boot" ]
}

lockdir_reclaim_owned_by_self() {
    local pid self_pid="$BASHPID"

    pid="$(awk -F= '$1 == "pid" { print $2; exit }' "$LOCK_RECLAIM_DIR/owner" 2>/dev/null || true)"
    [ "$pid" = "$self_pid" ] && lockdir_reclaim_owner_matches
}

write_lockdir_reclaim_metadata() {
    local self_pid="$BASHPID" tmp="${LOCK_RECLAIM_DIR}.owner.$BASHPID"

    rm -f -- "$tmp"
    if ! {
        printf 'pid=%s\n' "$self_pid"
        printf 'start_ticks=%s\n' "$(process_start_ticks "$self_pid" || true)"
        printf 'boot_id=%s\n' "$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || true)"
    } > "$tmp" ||
        ! chmod 600 "$tmp" ||
        ! mv -f -- "$tmp" "$LOCK_RECLAIM_DIR/owner"; then
        rm -f -- "$tmp"
        return 1
    fi
}

acquire_lockdir_reclaim_guard() {
    local i

    for i in {1..30}; do
        if mkdir "$LOCK_RECLAIM_DIR" 2>/dev/null; then
            if write_lockdir_reclaim_metadata; then
                return 0
            fi
            rm -rf -- "$LOCK_RECLAIM_DIR"
            return 1
        fi
        if [ -L "$LOCK_RECLAIM_DIR" ] ||
            { [ -e "$LOCK_RECLAIM_DIR" ] && [ ! -d "$LOCK_RECLAIM_DIR" ]; }; then
            return 1
        fi
        # 创建者写 owner 前有极短窗口；先等待，再只回收已确认没有存活持有者的目录。
        if [ ! -s "$LOCK_RECLAIM_DIR/owner" ]; then
            sleep 0.1
            continue
        fi
        lockdir_reclaim_owner_matches || {
            rm -rf -- "$LOCK_RECLAIM_DIR"
            continue
        }
        sleep 0.1
    done
    # 创建者若在写 owner 前被 SIGKILL，会留下空回收目录。rmdir 只会删除空目录；
    # 若另一个存活创建者已写入元数据则原子失败，不会误删有效保护。
    if [ -d "$LOCK_RECLAIM_DIR" ] && [ ! -L "$LOCK_RECLAIM_DIR" ] &&
        [ ! -e "$LOCK_RECLAIM_DIR/owner" ] &&
        rmdir -- "$LOCK_RECLAIM_DIR" 2>/dev/null &&
        mkdir "$LOCK_RECLAIM_DIR" 2>/dev/null; then
        if write_lockdir_reclaim_metadata; then
            return 0
        fi
        rm -rf -- "$LOCK_RECLAIM_DIR"
    fi
    return 1
}

release_lockdir_reclaim_guard() {
    if lockdir_reclaim_owned_by_self; then
        rm -f -- "$LOCK_RECLAIM_DIR/owner"
        rmdir -- "$LOCK_RECLAIM_DIR" 2>/dev/null || true
    fi
}

activate_lockdir_lock() {
    write_lockdir_metadata || {
        rm -rf -- "$LOCK_DIR"
        return 1
    }
    LOCK_USING_DIR=1
    install_lock_cleanup_traps
}

acquire_lock() {
    local old_pid=""
    local reclaim_guard=0

    prepare_runtime_dir

    if command -v flock >/dev/null 2>&1; then
        [ ! -L "$LOCK_FILE" ] || { err "$LOCK_FILE 是符号链接，已拒绝使用。"; exit 1; }
        exec 200<>"$LOCK_FILE"
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

    if [ -L "$LOCK_DIR" ] || { [ -e "$LOCK_DIR" ] && [ ! -d "$LOCK_DIR" ]; }; then
        err "$LOCK_DIR 不是安全的锁目录，已拒绝使用。"
        exit 1
    fi

    acquire_lockdir_reclaim_guard || {
        err "无法取得 vpsbox 锁回收保护，请稍后重试。"
        exit 1
    }
    reclaim_guard=1
    # 无 flock 时，首次创建和残留锁回收都必须在同一保护内完成，避免锁目录已创建、
    # 元数据尚未写入时被并发进程误判为残留锁。
    if mkdir "$LOCK_DIR" 2>/dev/null; then
        activate_lockdir_lock || {
            release_lockdir_reclaim_guard
            err "vpsbox 锁元数据写入失败。"
            exit 1
        }
        release_lockdir_reclaim_guard
        return
    fi
    if [ -L "$LOCK_DIR" ] || { [ -e "$LOCK_DIR" ] && [ ! -d "$LOCK_DIR" ]; }; then
        release_lockdir_reclaim_guard
        err "$LOCK_DIR 不是安全的锁目录，已拒绝使用。"
        exit 1
    fi

    wait_for_lockdir_metadata || true
    old_pid="$(lock_pid_from_file "$LOCK_DIR/pid" || true)"
    [ -z "$old_pid" ] && old_pid="$(find_running_vpsbox_pid || true)"
    if ! process_alive "$old_pid"; then
        warn "检测到残留 vpsbox 锁，正在清理。"
        rm -rf -- "$LOCK_DIR"
    elif old_menu_lost_terminal "$LOCK_DIR/pid" "$old_pid" && terminate_orphaned_vpsbox_menu "$old_pid"; then
        rm -rf -- "$LOCK_DIR"
    elif terminate_old_vpsbox_menu "$old_pid"; then
        rm -rf -- "$LOCK_DIR"
    else
        release_lockdir_reclaim_guard
        err "检测到另一个 vpsbox 正在运行，请先退出旧菜单。"
        exit 1
    fi

    if ! mkdir "$LOCK_DIR" 2>/dev/null; then
        release_lockdir_reclaim_guard
        err "检测到另一个 vpsbox 正在运行，请先退出旧菜单。"
        exit 1
    fi
    activate_lockdir_lock || {
        release_lockdir_reclaim_guard
        err "vpsbox 锁元数据写入失败。"
        exit 1
    }
    [ "$reclaim_guard" = "1" ] && release_lockdir_reclaim_guard
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

install_root_file_atomically() {
    local source="$1" target="$2" mode="${3:-644}"
    local parent tmp

    [ -f "$source" ] && [ ! -L "$source" ] || return 1
    [[ "$mode" =~ ^[0-7]{3,4}$ ]] || return 1
    [ ! -L "$target" ] || return 1
    parent="$(dirname "$target")"
    [ -d "$parent" ] && [ ! -L "$parent" ] || return 1
    command -v mktemp >/dev/null 2>&1 || return 1
    tmp="$(mktemp "$parent/.vpsbox-publish.XXXXXX")" || return 1
    if ! cp -- "$source" "$tmp" ||
        ! chown root:root "$tmp" ||
        ! chmod "$mode" "$tmp" ||
        ! mv -f -- "$tmp" "$target"; then
        rm -f -- "$tmp"
        return 1
    fi
}

restore_root_file_snapshot() {
    local snapshot="$1" target="$2" was_present="$3"
    local mode

    if [ "$was_present" = "1" ]; then
        [ -f "$snapshot" ] && [ ! -L "$snapshot" ] || return 1
        mode="$(stat -c '%a' "$snapshot" 2>/dev/null)" || return 1
        install_root_file_atomically "$snapshot" "$target" "$mode"
    else
        [ ! -L "$target" ] || return 1
        if [ -e "$target" ] && [ ! -f "$target" ]; then
            return 1
        fi
        rm -f -- "$target"
    fi
}

install_command_alias() {
    if [ ! -f "$CMD_PATH" ] || [ -L "$CMD_PATH" ]; then
        err "管理命令文件不存在或不安全：$CMD_PATH"
        return 1
    fi
    chmod 755 "$CMD_PATH" || {
        err "无法设置管理命令权限：$CMD_PATH"
        return 1
    }
    ln -sf "$CMD_PATH" /usr/bin/vpsbox || {
        err "无法创建命令入口：/usr/bin/vpsbox"
        return 1
    }
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

vpsbox_script_identity_valid() {
    local script="$1"

    [ -f "$script" ] && [ ! -L "$script" ] || return 1
    grep -Fqx 'APP_NAME="vpsbox"' "$script" || return 1
    if ! grep -Fqx "SCRIPT_URL=\"$LEGACY_SCRIPT_URL\"" "$script" &&
        ! grep -Fqx "SCRIPT_URL=\"$SCRIPT_URL\"" "$script"; then
        return 1
    fi
    grep -Fqx 'vpsbox_main() {' "$script" || return 1
    grep -Fqx 'if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then' "$script" || return 1
    grep -Fqx '    vpsbox_main "$@"' "$script" || return 1
}

fetch_vpsbox_script_once() {
    local dest="$1" connect_timeout="$2" max_time="$3"

    rm -f -- "$dest"
    if curl -fsSL --connect-timeout "$connect_timeout" --max-time "$max_time" \
        "$SCRIPT_URL" -o "$dest"; then
        return 0
    fi
    rm -f -- "$dest"
    return 1
}

download_vpsbox_script() {
    local dest="$1"
    local require_newer="${2:-0}"
    local tmp
    local downloaded_version

    ensure_curl || return 1

    mkdir -p "$(dirname "$dest")" || return 1
    command -v mktemp >/dev/null 2>&1 || {
        err "未找到 mktemp，无法安全创建下载临时文件。"
        return 1
    }
    tmp="$(mktemp "${dest}.tmp.XXXXXX")" || return 1

    if ! retry 3 2 fetch_vpsbox_script_once "$tmp" 8 180; then
        rm -f "$tmp"
        err "GitHub Raw 下载失败，请检查网络后重试。"
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
    if ! vpsbox_script_identity_valid "$tmp"; then
        rm -f "$tmp"
        err "下载到的脚本缺少 vpsbox 项目标识或必要入口，已保留当前版本。"
        return 1
    fi
    downloaded_version="$(sed -n 's/^VPSBOX_VERSION="\([^"]*\)"$/\1/p' "$tmp" | head -n 1)"
    if [ "$require_newer" = "1" ]; then
        case "$(version_relation "$downloaded_version" "$VPSBOX_VERSION")" in
            newer) ;;
            same)
                rm -f "$tmp"
                return 2
                ;;
            older)
                rm -f "$tmp"
                warn "远程版本 $downloaded_version 低于当前版本 $VPSBOX_VERSION，已拒绝降级。"
                return 3
                ;;
            *)
                rm -f "$tmp"
                err "无法比较远程版本 $downloaded_version 与当前版本 $VPSBOX_VERSION。"
                return 1
                ;;
        esac
    fi

    chmod 755 "$tmp" || { rm -f "$tmp"; return 1; }
    mv -f "$tmp" "$dest" || { rm -f "$tmp"; return 1; }
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

version_relation() {
    local candidate="$1"
    local current="$2"

    [[ "$candidate" =~ ^v?[0-9]+([.][0-9]+){2}$ ]] || return 1
    [[ "$current" =~ ^v?[0-9]+([.][0-9]+){2}$ ]] || return 1

    if version_is_newer "$candidate" "$current"; then
        printf '%s\n' newer
    elif version_is_newer "$current" "$candidate"; then
        printf '%s\n' older
    else
        printf '%s\n' same
    fi
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
    if ! fetch_vpsbox_script_once "$tmp" 3 8 >/dev/null 2>&1; then
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

auto_update_vpsbox_on_start() {
    [ "$UPDATE_AVAILABLE" -eq 1 ] || return 0

    info "发现新版本 $REMOTE_VERSION，正在自动更新..."
    if update_vpsbox; then
        return 0
    fi

    warn "自动更新失败，继续使用当前版本；可稍后使用菜单 00 重试。"
    return 0
}

vpsbox_update_notice() {
    if [ "$UPDATE_AVAILABLE" -eq 1 ]; then
        printf ' 新版本：%s（自动更新失败，请使用菜单 00 重试）\n' "$REMOTE_VERSION"
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
        debian)
            run_bounded_command "$PACKAGE_INSTALL_TIMEOUT" \
                env DEBIAN_FRONTEND=noninteractive \
                dpkg --force-confdef --force-confold --install "$tmp" ||
                { rm -rf "$tmp_dir"; return 1; }
            ;;
        alpine) apk_bounded "$PACKAGE_INSTALL_TIMEOUT" add --allow-untrusted "$tmp" || { rm -rf "$tmp_dir"; return 1; } ;;
        redhat)
            if command -v dnf >/dev/null 2>&1; then
                dnf_bounded "$PACKAGE_INSTALL_TIMEOUT" install -y "$tmp"
            else
                yum_bounded "$PACKAGE_INSTALL_TIMEOUT" install -y "$tmp"
            fi || { rm -rf "$tmp_dir"; return 1; }
            ;;
    esac
    rm -rf "$tmp_dir"
    return 0
}

singbox_binary_is_package_managed() {
    local binary_path="$1" owner

    binary_path="$(readlink -f -- "$binary_path" 2>/dev/null || printf '%s' "$binary_path")"
    detect_os
    case "$OS" in
        debian)
            command -v dpkg-query >/dev/null 2>&1 || return 1
            owner="$(dpkg-query -S "$binary_path" 2>/dev/null | awk -F: 'NR == 1 { print $1 }')"
            [[ "$owner" =~ ^sing-box(:[^:]+)?$ ]]
            ;;
        alpine)
            command -v apk >/dev/null 2>&1 || return 1
            apk info --who-owns "$binary_path" 2>/dev/null | grep -Eq ' owned by sing-box-[^[:space:]]+$'
            ;;
        redhat)
            command -v rpm >/dev/null 2>&1 || return 1
            [ "$(rpm -qf --queryformat '%{NAME}\n' "$binary_path" 2>/dev/null || true)" = "sing-box" ]
            ;;
        *) return 1 ;;
    esac
}

prepare_singbox_rollback_package() {
    local version="$1" backup_dir="$2"
    local arch suffix asset package

    [[ "$version" =~ ^[0-9]+([.][0-9]+){2}$ ]] || return 1
    detect_os
    case "$OS" in
        debian) arch="$(dpkg --print-architecture)"; suffix="deb" ;;
        alpine) arch="$(apk --print-arch)"; suffix="apk" ;;
        redhat) arch="$(uname -m)"; suffix="rpm" ;;
        *) return 1 ;;
    esac
    asset="sing-box_${version}_linux_${arch}.${suffix}"
    package="$backup_dir/$asset"
    download_verified_github_asset "SagerNet/sing-box" "v$version" "$asset" "$package" || return 1
    printf '%s\n' "$package"
}

install_singbox_package_file() {
    local package="$1"

    [ -f "$package" ] && [ ! -L "$package" ] || return 1
    detect_os
    case "$OS" in
        debian)
            run_bounded_command "$PACKAGE_INSTALL_TIMEOUT" \
                env DEBIAN_FRONTEND=noninteractive \
                dpkg --force-confdef --force-confold --install "$package"
            ;;
        alpine)
            apk_bounded "$PACKAGE_INSTALL_TIMEOUT" add --allow-untrusted "$package"
            ;;
        redhat)
            run_bounded_command "$PACKAGE_INSTALL_TIMEOUT" \
                rpm -Uvh --oldpackage --replacepkgs "$package"
            ;;
        *) return 1 ;;
    esac
}

install_self_command() {
    local src
    src="${1:-${BASH_SOURCE[0]:-$0}}"

    mkdir -p "$(dirname "$CMD_PATH")" || { err "无法创建管理命令目录。"; return 1; }

    case "$src" in
        /dev/fd/*|/proc/*)
            if download_vpsbox_script "$CMD_PATH"; then
                install_command_alias || return 1
                return 0
            fi
            err "管理命令安装失败，请检查网络后重新运行安装命令。"
            return 1
            ;;
    esac

    [ -f "$src" ] && [ ! -L "$src" ] ||
        { err "找不到当前 vpsbox 脚本，或脚本路径不安全：$src"; return 1; }

    if [ "$(readlink -f "$src" 2>/dev/null || echo "$src")" != "$CMD_PATH" ]; then
        if ! install_root_file_atomically "$src" "$CMD_PATH" 755; then
            err "无法安装管理命令到 $CMD_PATH。"
            return 1
        fi
        install_command_alias || return 1
    else
        install_command_alias || return 1
    fi
}

secure_config_dir() {
    local path

    if [ -L "$CONFIG_DIR" ] || [ -L "$NODE_CONFIG_DIR" ]; then
        err "$CONFIG_DIR 是符号链接，已拒绝使用。"
        return 1
    fi

    mkdir -p "$CONFIG_DIR" || return 1
    chown root:root "$CONFIG_DIR" || return 1
    chmod 700 "$CONFIG_DIR" || return 1
    if [ -d "$NODE_CONFIG_DIR" ]; then
        chown root:root "$NODE_CONFIG_DIR" || return 1
        chmod 700 "$NODE_CONFIG_DIR" || return 1
    fi

    for path in "$URI_FILE" "$SS_CONFIG_PATH" "$VLESS_CONFIG_PATH" \
        "$SS_STATE_FILE" "$VLESS_STATE_FILE" "$SS_URI_FILE" "$VLESS_URI_FILE"; do
        if [ -L "$path" ]; then
            err "$path 是符号链接，已拒绝使用。"
            return 1
        fi
    done
}

secure_node_config_dir() {
    secure_config_dir || return 1
    mkdir -p "$NODE_CONFIG_DIR" || return 1
    chown root:root "$NODE_CONFIG_DIR" || return 1
    chmod 700 "$NODE_CONFIG_DIR"
}

ensure_change_store() {
    [ ! -L "$VPSBOX_STATE_DIR" ] && [ ! -L "$CHANGE_BACKUP_DIR" ] && [ ! -L "$CHANGE_MANIFEST" ] || {
        err "vpsbox 变更清单路径包含符号链接，已拒绝使用。"
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
    # 值始终是单行 token；额外允许逗号保存已规范化的 SSH 多端口 CSV。
    awk -F= -v key="$key" '$1 == key && $2 ~ /^[A-Za-z0-9_.:,-]+$/ { value=$2 } END { if (value != "") print value; else exit 1 }' "$CHANGE_MANIFEST"
}

manifest_set() {
    local key="$1" value="$2" tmp
    [[ "$key" =~ ^[A-Z0-9_]+$ && "$value" =~ ^[A-Za-z0-9_.:,-]+$ ]] || return 1
    ensure_change_store || return 1
    tmp="$(mktemp "$VPSBOX_STATE_DIR/.changes.XXXXXX")" || return 1
    if ! awk -F= -v key="$key" '$1 != key { print }' "$CHANGE_MANIFEST" > "$tmp" ||
        ! printf '%s=%s\n' "$key" "$value" >> "$tmp" ||
        ! chown root:root "$tmp" ||
        ! chmod 600 "$tmp" ||
        ! mv -f -- "$tmp" "$CHANGE_MANIFEST"; then
        rm -f -- "$tmp"
        return 1
    fi
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
    if ! awk -F= -v key="$key" '$1 != key { print }' "$CHANGE_MANIFEST" > "$tmp" ||
        ! chown root:root "$tmp" ||
        ! chmod 600 "$tmp" ||
        ! mv -f -- "$tmp" "$CHANGE_MANIFEST"; then
        rm -f -- "$tmp"
        return 1
    fi
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
    local name="$1"

    manifest_set "APPLIED_$name" 1 || return 1
    manifest_remove "PENDING_$name"
}

begin_change_transaction() {
    manifest_set "PENDING_$1" 1
}

change_restore_state() {
    local name="$1"

    if [ "$(manifest_value "PENDING_$name" 2>/dev/null || true)" = "1" ]; then
        printf '%s\n' pending
    # 兼容 v1.0.26 及更早版本的变更清单：旧版本只记录 APPLIED，没有 PENDING。
    elif [ "$(manifest_value "APPLIED_$name" 2>/dev/null || true)" = "1" ]; then
        printf '%s\n' applied
    else
        printf '%s\n' none
    fi
}

change_needs_restore() {
    [ "$(change_restore_state "$1")" != none ]
}

restore_change_file() {
    local name="$1" target="$2" state backup tmp parent
    state="$(manifest_value "BACKUP_$name" 2>/dev/null || true)"
    case "$state" in
        file)
            backup="$CHANGE_BACKUP_DIR/$name"
            [ -f "$backup" ] && [ ! -L "$backup" ] || {
                err "$name 的备份文件无效，已拒绝恢复。"
                return 1
            }
            parent="$(dirname "$target")"
            [ -d "$parent" ] && [ ! -L "$parent" ] || {
                err "恢复目标目录无效或为符号链接：$parent"
                return 1
            }
            tmp="$(mktemp "$parent/.vpsbox-restore.XXXXXX")" || return 1
            if ! cp -a "$backup" "$tmp"; then
                rm -f -- "$tmp"
                return 1
            fi
            # 目标后来可能被系统组件改成符号链接；删除链接本身，避免覆盖其指向文件。
            if [ -L "$target" ] && ! rm -f -- "$target"; then
                rm -f -- "$tmp"
                return 1
            fi
            if { [ -e "$target" ] && [ ! -f "$target" ]; } ||
                ! mv -f -- "$tmp" "$target"; then
                rm -f -- "$tmp"
                return 1
            fi
            ;;
        absent)
            if [ -L "$target" ] || [ -f "$target" ]; then
                rm -f -- "$target"
            elif [ -e "$target" ]; then
                err "恢复目标不是普通文件，已拒绝删除：$target"
                return 1
            fi
            ;;
        *) warn "没有 $name 的可恢复备份。"; return 1 ;;
    esac
}

clear_change_tracking() {
    local name="$1" failed=0

    rm -f "$CHANGE_BACKUP_DIR/$name" || failed=1
    manifest_remove "BACKUP_$name" || failed=1
    manifest_remove "APPLIED_$name" || failed=1
    manifest_remove "PENDING_$name" || failed=1
    return "$failed"
}

install_deps() {
    detect_os

    case "$OS" in
        alpine)
            apk_bounded "$PACKAGE_UPDATE_TIMEOUT" update || return 1
            apk_bounded "$PACKAGE_INSTALL_TIMEOUT" add --no-cache bash curl ca-certificates openssl jq iproute2 coreutils || return 1
            ;;
        debian)
            export DEBIAN_FRONTEND=noninteractive
            apt_get_bounded "$PACKAGE_UPDATE_TIMEOUT" update -y || return 1
            apt_get_bounded "$PACKAGE_INSTALL_TIMEOUT" install -y curl ca-certificates openssl jq iproute2 coreutils || return 1
            ;;
        redhat)
            if command -v dnf >/dev/null 2>&1; then
                dnf_bounded "$PACKAGE_INSTALL_TIMEOUT" install -y curl ca-certificates openssl jq iproute coreutils || return 1
            else
                yum_bounded "$PACKAGE_INSTALL_TIMEOUT" install -y curl ca-certificates openssl jq iproute coreutils || return 1
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

singbox_package_installed() {
    case "$OS" in
        alpine)
            command -v apk >/dev/null 2>&1 && apk info -e sing-box >/dev/null 2>&1
            ;;
        debian)
            command -v dpkg-query >/dev/null 2>&1 &&
                [ "$(dpkg-query -W -f='${Status}' sing-box 2>/dev/null || true)" = "install ok installed" ]
            ;;
        redhat)
            command -v rpm >/dev/null 2>&1 && rpm -q sing-box >/dev/null 2>&1
            ;;
        *) return 1 ;;
    esac
}

singbox_artifacts_present() {
    singbox_installed || singbox_package_installed ||
        [ -e "$CONFIG_DIR" ] ||
        [ -e /etc/systemd/system/sing-box.service ] ||
        [ -e /usr/lib/systemd/system/sing-box.service ] ||
        [ -e /lib/systemd/system/sing-box.service ] ||
        [ -e /etc/init.d/sing-box ] ||
        [ -e /usr/bin/sing-box ] ||
        [ -e /usr/local/bin/sing-box ] ||
        pgrep -x sing-box >/dev/null 2>&1
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

install_singbox_for_node_transaction() {
    if ! singbox_installed; then
        # 首次安装会写入二进制和服务文件，必须先把节点事务标记为已修改，
        # 这样安装中断后下次启动会恢复安装前的服务状态，而不是丢弃事务。
        mark_node_transaction_mutated || return 1
    fi
    install_singbox_if_missing
}

refuse_service_mutation_in_test() {
    if [ "${VPSBOX_TEST_MODE:-0}" = "1" ]; then
        err "测试模式禁止调用真实服务管理命令：$1"
        return 1
    fi
}

run_openrc_service() {
    # OpenRC 可能通过 supervise-daemon 启动长期进程；明确关闭菜单 flock，
    # 防止守护进程继承 FD 200 后让已退出的 vpsbox 看起来仍持有锁。
    rc-service "$@" 200>&-
}

service_start() {
    refuse_service_mutation_in_test service_start || return 1
    if is_systemd; then
        retry 3 2 systemctl start "$SERVICE_NAME"
    elif [ "$OS" = "alpine" ] && command -v rc-service >/dev/null 2>&1; then
        retry 3 2 run_openrc_service "$SERVICE_NAME" start
    else
        err "未检测到 systemd/OpenRC，无法管理服务。"
        return 1
    fi
}

service_stop() {
    refuse_service_mutation_in_test service_stop || return 1
    if is_systemd; then
        retry 3 2 systemctl stop "$SERVICE_NAME"
    elif [ "$OS" = "alpine" ] && command -v rc-service >/dev/null 2>&1; then
        retry 3 2 run_openrc_service "$SERVICE_NAME" stop
    else
        err "未检测到 systemd/OpenRC，无法管理服务。"
        return 1
    fi
}

service_enable() {
    refuse_service_mutation_in_test service_enable || return 1
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
    refuse_service_mutation_in_test service_disable || return 1
    if is_systemd; then
        systemctl disable "$SERVICE_NAME" >/dev/null 2>&1
    elif [ "$OS" = "alpine" ] && command -v rc-update >/dev/null 2>&1; then
        rc-update del "$SERVICE_NAME" default >/dev/null 2>&1
    else
        return 1
    fi
}

service_manager_is_active() {
    if is_systemd; then
        systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null
    elif [ "$OS" = "alpine" ] && command -v rc-service >/dev/null 2>&1; then
        run_openrc_service "$SERVICE_NAME" status >/dev/null 2>&1
    else
        return 1
    fi
}

service_is_running() {
    singbox_installed && service_manager_is_active && [ -n "$(singbox_config_pids)" ]
}

service_status_short() {
    if ! singbox_installed; then
        echo "未运行"
    elif service_is_running; then
        echo "运行中"
    elif is_systemd || { [ "$OS" = "alpine" ] && command -v rc-service >/dev/null 2>&1; }; then
        echo "未运行"
    else
        echo "未知"
    fi
}

singbox_config_pids() {
    local proc pid exe
    local -a args

    for proc in /proc/[0-9]*; do
        [ -r "$proc/cmdline" ] || continue
        pid="${proc##*/}"
        [ "$pid" != "$$" ] || continue
        exe="$(readlink "$proc/exe" 2>/dev/null || true)"
        # Linux 会给仍在运行但磁盘文件已被升级/删除的程序追加 " (deleted)"；
        # 只剥离该精确后缀，并继续核对可执行文件名及完整配置参数，避免扩大进程匹配范围。
        case "$exe" in
            *' (deleted)') exe="${exe% (deleted)}" ;;
        esac
        [ "${exe##*/}" = "sing-box" ] || continue
        mapfile -d '' -t args < "$proc/cmdline" 2>/dev/null || true
        [ "${#args[@]}" -ge 4 ] || continue
        if [ "${args[1]}" = "run" ] &&
            [ "${args[2]}" = "-C" ] && [ "${args[3]}" = "$NODE_CONFIG_DIR" ]; then
            printf '%s\n' "$pid"
        fi
    done
}

stop_singbox_config_processes() {
    local pids pid i

    refuse_service_mutation_in_test stop_singbox_config_processes || return 1
    pids="$(singbox_config_pids)"
    [ -n "$pids" ] || return 0
    warn "检测到使用 vpsbox 节点配置的残留 sing-box 进程，正在停止：$(echo "$pids" | tr '\n' ' ')"
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
    local stop_failed=0

    service_stop 2>/dev/null || stop_failed=1
    stop_singbox_config_processes || {
        err "旧 sing-box 进程无法停止，已拒绝启动新实例。"
        return 1
    }
    if [ "$stop_failed" -eq 1 ] && service_manager_is_active; then
        err "服务管理器未能停止旧 sing-box，已拒绝启动新实例。"
        return 1
    fi
    service_start || return 1
    service_is_running
}

restore_singbox_service_state() {
    local was_enabled="$1" was_active="$2"

    if [ "$was_enabled" = "1" ]; then
        service_enable || return 1
        service_is_enabled || return 1
    else
        if ! service_disable && service_is_enabled; then
            return 1
        fi
        service_is_enabled && return 1
    fi
    if [ "$was_active" = "1" ]; then
        restart_singbox_cleanly && service_is_running
    else
        if ! service_stop && service_manager_is_active; then
            return 1
        fi
        stop_singbox_config_processes || return 1
        ! service_manager_is_active && [ -z "$(singbox_config_pids)" ]
    fi
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

    addr="${addr,,}"
    case "$addr" in
        127.*|::1|0:0:0:0:0:0:0:1|::ffff:127.*|::ffff:7f*|0:0:0:0:0:ffff:7f*|localhost|ip6-localhost)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

ipv4_listen_addr_is_public() {
    local addr="$1" first second third fourth octet

    [[ "$addr" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    IFS='.' read -r first second third fourth <<< "$addr"
    for octet in "$first" "$second" "$third" "$fourth"; do
        (( 10#$octet <= 255 )) || return 1
    done
    first=$((10#$first))
    second=$((10#$second))
    third=$((10#$third))
    fourth=$((10#$fourth))

    # IANA special-purpose, private, shared, loopback, link-local, documentation,
    # benchmark, multicast and reserved ranges are not public listener addresses.
    (( first == 0 || first == 10 || first == 127 || first >= 224 )) && return 1
    (( first == 100 && second >= 64 && second <= 127 )) && return 1
    (( first == 169 && second == 254 )) && return 1
    (( first == 172 && second >= 16 && second <= 31 )) && return 1
    (( first == 192 && second == 0 && third == 0 && fourth != 9 && fourth != 10 )) && return 1
    (( first == 192 && second == 0 && third == 2 )) && return 1
    (( first == 192 && second == 88 && third == 99 )) && return 1
    (( first == 192 && second == 168 )) && return 1
    (( first == 198 && (second == 18 || second == 19) )) && return 1
    (( first == 198 && second == 51 && third == 100 )) && return 1
    (( first == 203 && second == 0 && third == 113 )) && return 1
    return 0
}

ipv6_expand_hextets() {
    local addr="${1,,}" left right part missing
    local -a left_parts=() right_parts=() parts=()

    [[ "$addr" == *:* ]] && [[ "$addr" != *.* ]] || return 1
    if [[ "$addr" == *::* ]]; then
        [ "${addr#*::}" = "${addr##*::}" ] || return 1
        left="${addr%%::*}"
        right="${addr#*::}"
        [ -z "$left" ] || IFS=':' read -r -a left_parts <<< "$left"
        [ -z "$right" ] || IFS=':' read -r -a right_parts <<< "$right"
        missing=$((8 - ${#left_parts[@]} - ${#right_parts[@]}))
        [ "$missing" -ge 1 ] || return 1
        parts=("${left_parts[@]}")
        while [ "$missing" -gt 0 ]; do
            parts+=(0)
            missing=$((missing - 1))
        done
        parts+=("${right_parts[@]}")
    else
        IFS=':' read -r -a parts <<< "$addr"
        [ "${#parts[@]}" -eq 8 ] || return 1
    fi
    [ "${#parts[@]}" -eq 8 ] || return 1
    for part in "${parts[@]}"; do
        [[ "$part" =~ ^[0-9a-f]{1,4}$ ]] || return 1
        printf '%u ' "$((16#$part))"
    done
    printf '\n'
}

ipv6_listen_addr_is_public() {
    local addr="${1,,}" embedded expanded
    local h0 h1 h2 h3 h4 h5 h6 h7

    addr="${addr%%%*}"
    case "$addr" in
        ::ffff:*.*.*.*)
            embedded="${addr##*::ffff:}"
            ipv4_listen_addr_is_public "$embedded"
            return $?
            ;;
    esac

    expanded="$(ipv6_expand_hextets "$addr")" || return 1
    read -r h0 h1 h2 h3 h4 h5 h6 h7 <<< "$expanded"
    if [ "$h0" -eq 0 ] && [ "$h1" -eq 0 ] && [ "$h2" -eq 0 ] &&
        [ "$h3" -eq 0 ] && [ "$h4" -eq 0 ]; then
        if [ "$h5" -eq 0 ] && [ "$h6" -eq 0 ] &&
            { [ "$h7" -eq 0 ] || [ "$h7" -eq 1 ]; }; then
            return 1
        fi
        if [ "$h5" -eq 65535 ]; then
            embedded="$((h6 >> 8)).$((h6 & 255)).$((h7 >> 8)).$((h7 & 255))"
            ipv4_listen_addr_is_public "$embedded"
            return $?
        fi
    fi

    # 精确按 IANA 前缀判断，避免用字符串通配把 /64、/48 或 /20 扩大成 /16。
    (( h0 == 0x0100 && h1 == 0 && h2 == 0 && (h3 == 0 || h3 == 1) )) && return 1
    (( (h0 & 0xfe00) == 0xfc00 )) && return 1
    (( (h0 & 0xffc0) == 0xfe80 || (h0 & 0xffc0) == 0xfec0 )) && return 1
    (( (h0 & 0xff00) == 0xff00 )) && return 1
    (( h0 == 0x2001 && h1 == 0x0002 && h2 == 0 )) && return 1
    (( h0 == 0x2001 && (h1 & 0xfff0) == 0x0010 )) && return 1
    (( h0 == 0x2001 && (h1 & 0xfff0) == 0x0020 )) && return 1
    (( h0 == 0x2001 && h1 == 0x0db8 )) && return 1
    (( h0 == 0x2002 )) && return 1
    (( h0 == 0x3fff && (h1 & 0xf000) == 0 )) && return 1
    (( h0 == 0x5f00 )) && return 1
    return 0
}

is_public_listen_addr() {
    local addr="${1,,}"

    addr="${addr#[}"
    addr="${addr/\]/}"
    is_wildcard_listen_addr "$addr" && return 0
    is_loopback_listen_addr "$addr" && return 1
    if [[ "$addr" == *:* ]]; then
        ipv6_listen_addr_is_public "$addr"
    else
        ipv4_listen_addr_is_public "$addr"
    fi
}

is_dhcp_client_listener() {
    local protocol="$1" port="$2"

    [ "$protocol" = "udp" ] && { [ "$port" = "68" ] || [ "$port" = "546" ]; }
}

collect_listening_sockets() {
    local output proto protocol state local_addr addr port proc_info proc_name scope
    local _recvq _sendq _peer_addr

    command -v ss >/dev/null 2>&1 || {
        err "未找到 ss 命令，无法读取监听端口。"
        return 1
    }
    output="$(ss -H -tulpn 2>/dev/null)" || {
        err "无法读取系统监听端口。"
        return 1
    }

    while read -r proto state _recvq _sendq local_addr _peer_addr proc_info; do
        case "${proto,,}:$state" in
            tcp*:LISTEN) protocol="tcp" ;;
            udp*:UNCONN) protocol="udp" ;;
            *) continue ;;
        esac

        port="${local_addr##*:}"
        port="$(normalize_port_decimal "$port" 2>/dev/null)" || continue
        addr="${local_addr%:*}"
        addr="${addr#\[}"
        addr="${addr/\]/}"

        proc_name="-"
        if [[ "${proc_info:-}" =~ \"([^\"]+)\" ]]; then
            proc_name="${BASH_REMATCH[1]}"
        fi

        if is_dhcp_client_listener "$protocol" "$port"; then
            scope="system"
        elif is_loopback_listen_addr "$addr"; then
            scope="local"
        elif is_public_listen_addr "$addr"; then
            scope="public"
        else
            scope="nonpublic"
        fi
        printf '%s|%s|%s|%s|%s\n' "$scope" "$protocol" "$port" "$addr" "$proc_name"
    done <<< "$output"
}

show_ports_security_group() {
    local public_file local_file suggest_file records
    local scope protocol port _addr proc_name proto_upper

    public_file="$(mktemp)"
    local_file="$(mktemp)"
    suggest_file="$(mktemp)"
    records="$(collect_listening_sockets)" || {
        rm -f "$public_file" "$local_file" "$suggest_file"
        return 1
    }

    while IFS='|' read -r scope protocol port _addr proc_name; do
        [ -n "$scope" ] || continue
        proto_upper="${protocol^^}"
        if [ "$scope" = "public" ]; then
            printf '%-5s %-8s %s\n' "$proto_upper" "$port" "$proc_name" >> "$public_file"
            printf '%s %s\n' "$proto_upper" "$port" >> "$suggest_file"
        else
            printf '%-5s %-8s %s\n' "$proto_upper" "$port" "$proc_name" >> "$local_file"
        fi
    done <<< "$records"

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

本机或非公网监听，无需安全组放行：
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

node_config_path() {
    case "$1" in
        ss) printf '%s\n' "$SS_CONFIG_PATH" ;;
        vless) printf '%s\n' "$VLESS_CONFIG_PATH" ;;
        *) return 2 ;;
    esac
}

node_state_path() {
    case "$1" in
        ss) printf '%s\n' "$SS_STATE_FILE" ;;
        vless) printf '%s\n' "$VLESS_STATE_FILE" ;;
        *) return 2 ;;
    esac
}

node_uri_path() {
    case "$1" in
        ss) printf '%s\n' "$SS_URI_FILE" ;;
        vless) printf '%s\n' "$VLESS_URI_FILE" ;;
        *) return 2 ;;
    esac
}

node_protocol_display_name() {
    case "$1" in
        ss) printf '%s\n' "Shadowsocks" ;;
        vless) printf '%s\n' "VLESS Reality" ;;
        *) return 2 ;;
    esac
}

node_file_is_secure() {
    local file="$1"
    local owner group mode

    [ -f "$file" ] && [ ! -L "$file" ] || return 1
    owner="$(stat -c '%u' "$file" 2>/dev/null)" || return 1
    group="$(stat -c '%g' "$file" 2>/dev/null)" || return 1
    mode="$(stat -c '%a' "$file" 2>/dev/null)" || return 1
    [ "$owner" = "0" ] && [ "$group" = "0" ] && [ "$mode" = "600" ]
}

node_dir_is_secure() {
    local dir="$1"
    local owner group mode

    [ -d "$dir" ] && [ ! -L "$dir" ] || return 1
    owner="$(stat -c '%u' "$dir" 2>/dev/null)" || return 1
    group="$(stat -c '%g' "$dir" 2>/dev/null)" || return 1
    mode="$(stat -c '%a' "$dir" 2>/dev/null)" || return 1
    [ "$owner" = "0" ] && [ "$group" = "0" ] && [ "$mode" = "700" ]
}

load_state_file() {
    local file="$1"
    local expected_protocol="$2"
    local key
    local value
    local domain=""
    local name=""
    local port=""
    local password=""
    local method=""
    local protocol=""
    local uuid=""
    local flow=""
    local reality_server_name=""
    local reality_private_key=""
    local reality_public_key=""
    local reality_short_id=""
    local fingerprint=""
    local config_id=""
    local seen_keys=""

    node_file_is_secure "$file" || return 1
    while IFS='=' read -r key value; do
        case "$key" in
            ""|'#'*) continue ;;
            DOMAIN|NAME|PORT|PASSWORD|METHOD|PROTOCOL|UUID|FLOW|REALITY_SERVER_NAME|REALITY_PRIVATE_KEY|REALITY_PUBLIC_KEY|REALITY_SHORT_ID|FINGERPRINT|CONFIG_ID)
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
            REALITY_PRIVATE_KEY) reality_private_key="$value" ;;
            REALITY_PUBLIC_KEY) reality_public_key="$value" ;;
            REALITY_SHORT_ID) reality_short_id="$value" ;;
            FINGERPRINT) fingerprint="$value" ;;
            CONFIG_ID) config_id="$value" ;;
        esac
    done < "$file"

    is_valid_node_host "$domain" || return 1
    [ -n "$name" ] && [ "$(sanitize_name "$name")" = "$name" ] || return 1
    [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ] || return 1
    [ "$protocol" = "$expected_protocol" ] || return 1
    [[ "$config_id" =~ ^[0-9a-f]{24}$ ]] || return 1
    case "$protocol" in
        shadowsocks)
            [[ "$password" =~ ^[A-Za-z0-9_+/=-]+$ ]] || return 1
            [ "$method" = "$SS_METHOD" ] || return 1
            ;;
        vless-reality)
            [[ "$uuid" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]] || return 1
            [ "$flow" = "xtls-rprx-vision" ] || return 1
            is_domain_name "$reality_server_name" || return 1
            [[ "$reality_private_key" =~ ^[A-Za-z0-9_-]{40,60}$ ]] || return 1
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
    REALITY_PRIVATE_KEY="$reality_private_key"
    REALITY_PUBLIC_KEY="$reality_public_key"
    REALITY_SHORT_ID="$reality_short_id"
    FINGERPRINT="$fingerprint"
    CONFIG_ID="$config_id"
}

node_config_matches_loaded_state() {
    local protocol="$1"
    local config="$2"

    command -v jq >/dev/null 2>&1 || return 1
    node_file_is_secure "$config" || return 1
    case "$protocol" in
        ss)
            jq -e \
                --argjson port "$PORT" \
                --arg method "$METHOD" \
                --arg password "$PASSWORD" \
                --arg config_id "$CONFIG_ID" '
                (.inbounds | type == "array" and length > 0) and
                all(.inbounds[];
                    .type == "shadowsocks" and
                    .listen_port == $port and
                    .method == $method and
                    .password == $password and
                    (.tag | type == "string" and contains($config_id))
                ) and
                ((.outbounds | type == "array" and length > 0) and
                 all(.outbounds[]; .tag | type == "string" and contains($config_id)))
            ' "$config" >/dev/null 2>&1
            ;;
        vless)
            jq -e \
                --argjson port "$PORT" \
                --arg uuid "$UUID" \
                --arg flow "$FLOW" \
                --arg server_name "$REALITY_SERVER_NAME" \
                --arg private_key "${REALITY_PRIVATE_KEY:-}" \
                --arg short_id "$REALITY_SHORT_ID" \
                --arg config_id "$CONFIG_ID" '
                (.inbounds | type == "array" and length > 0) and
                all(.inbounds[];
                    .type == "vless" and
                    .listen_port == $port and
                    any(.users[]?; .uuid == $uuid and .flow == $flow) and
                    .tls.enabled == true and
                    .tls.server_name == $server_name and
                    .tls.reality.enabled == true and
                    .tls.reality.handshake.server == $server_name and
                    .tls.reality.private_key == $private_key and
                    any(.tls.reality.short_id[]?; . == $short_id) and
                    (.tag | type == "string" and contains($config_id))
                ) and
                ((.outbounds | type == "array" and length > 0) and
                 all(.outbounds[]; .tag | type == "string" and contains($config_id)))
            ' "$config" >/dev/null 2>&1
            ;;
        *) return 2 ;;
    esac
}

node_uri_matches_loaded_state() {
    local uri="$1"
    local expected

    [ -e "$uri" ] || return 0
    node_file_is_secure "$uri" || return 1
    expected="$(generate_link_from_loaded_state)" || return 1
    [ "$(wc -l < "$uri")" -eq 1 ] && [ "$(cat "$uri")" = "$expected" ]
}

validate_protocol_node_artifacts() {
    local protocol="$1"
    local config="${2:-}"
    local state="${3:-}"
    local uri="${4:-}"
    local expected

    [ -n "$config" ] || config="$(node_config_path "$protocol")" || return 2
    [ -n "$state" ] || state="$(node_state_path "$protocol")" || return 2
    [ -n "$uri" ] || uri="$(node_uri_path "$protocol")" || return 2
    case "$protocol" in
        ss) expected=shadowsocks ;;
        vless) expected=vless-reality ;;
        *) return 2 ;;
    esac
    node_file_is_secure "$state" || return 1
    load_state_file "$state" "$expected" || return 1
    node_config_matches_loaded_state "$protocol" "$config" || return 1
    node_uri_matches_loaded_state "$uri"
}

protocol_node_exists() {
    local protocol="$1" config state

    config="$(node_config_path "$protocol")" || return 2
    state="$(node_state_path "$protocol")" || return 2
    case "$protocol" in
        ss|vless) ;;
        *) return 2 ;;
    esac
    [ -f "$config" ] && [ ! -L "$config" ] &&
        [ -f "$state" ] && [ ! -L "$state" ] &&
        validate_protocol_node_artifacts "$protocol" "$config" "$state" "$(node_uri_path "$protocol")" >/dev/null 2>&1
}

protocol_visible_exists() {
    protocol_node_exists "$1"
}

load_protocol_state() {
    local protocol="$1" state expected

    state="$(node_state_path "$protocol")" || return 2
    case "$protocol" in
        ss) expected=shadowsocks ;;
        vless) expected=vless-reality ;;
        *) return 2 ;;
    esac
    protocol_node_exists "$protocol" || return 1
    load_state_file "$state" "$expected"
}

node_exists() {
    protocol_node_exists ss || protocol_node_exists vless
}

node_artifacts_present() {
    [ -e "$URI_FILE" ] || [ -e "$NODE_CONFIG_DIR" ] ||
        [ -e "$SS_STATE_FILE" ] || [ -e "$VLESS_STATE_FILE" ] ||
        [ -e "$SS_URI_FILE" ] || [ -e "$VLESS_URI_FILE" ]
}

node_config_dir_contents_valid() {
    local path entries

    [ -e "$NODE_CONFIG_DIR" ] || return 0
    node_dir_is_secure "$NODE_CONFIG_DIR" || return 1
    entries="$(find "$NODE_CONFIG_DIR" -mindepth 1 -maxdepth 1 -print 2>/dev/null)" || return 1
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        case "$path" in
            "$SS_CONFIG_PATH"|"$VLESS_CONFIG_PATH") ;;
            *) return 1 ;;
        esac
        node_file_is_secure "$path" || return 1
    done <<< "$entries"
}

aggregate_uri_matches_nodes() {
    local protocol expected="" link

    [ -e "$URI_FILE" ] || return 0
    node_file_is_secure "$URI_FILE" || return 1
    for protocol in ss vless; do
        protocol_node_exists "$protocol" || continue
        link="$(generate_protocol_link "$protocol")" || return 1
        [ -n "$expected" ] && expected="${expected}"$'\n'
        expected="${expected}${link}"
    done
    [ -n "$expected" ] && [ "$(cat "$URI_FILE")" = "$expected" ]
}

require_valid_node_state_if_present() {
    local has_core=0 protocol label config state uri
    local path

    for path in "$URI_FILE" "$NODE_CONFIG_DIR" "$SS_CONFIG_PATH" "$VLESS_CONFIG_PATH" \
        "$SS_STATE_FILE" "$VLESS_STATE_FILE" "$SS_URI_FILE" "$VLESS_URI_FILE"; do
        if [ -L "$path" ]; then
            err "检测到节点路径为符号链接，已拒绝继续：$path"
            return 1
        fi
    done
    node_config_dir_contents_valid || {
        err "节点配置目录包含未知、残缺或不安全的文件：$NODE_CONFIG_DIR"
        return 1
    }

    for protocol in ss vless; do
        label="$(node_protocol_display_name "$protocol")" || return 1
        config="$(node_config_path "$protocol")" || return 1
        state="$(node_state_path "$protocol")" || return 1
        uri="$(node_uri_path "$protocol")" || return 1
        if [ -e "$config" ] || [ -e "$state" ]; then
            [ -f "$config" ] && [ -f "$state" ] &&
                validate_protocol_node_artifacts "$protocol" "$config" "$state" "$uri" || {
                err "检测到 $label 节点配置残缺、不安全或内容无效。"
                err "请检查 $config 与 $state。"
                return 1
            }
            has_core=1
        fi
        if [ -e "$uri" ] && ! protocol_node_exists "$protocol"; then
            err "检测到没有对应节点状态的孤立链接文件：$uri"
            return 1
        fi
    done

    if [ "$has_core" -eq 0 ] &&
        { [ -e "$URI_FILE" ] || [ -e "$SS_URI_FILE" ] || [ -e "$VLESS_URI_FILE" ]; }; then
        err "检测到孤立的节点链接文件，已拒绝继续以免误判节点状态。"
        return 1
    fi
    if [ "$has_core" -eq 1 ] && ! aggregate_uri_matches_nodes; then
        err "检测到汇总节点链接与独立节点状态不一致：$URI_FILE"
        return 1
    fi
}

commit_node_state_file() {
    local tmp="$1"
    local dest="$2"

    if ! chown root:root "$tmp" ||
        ! chmod 600 "$tmp" ||
        ! mv -f -- "$tmp" "$dest"; then
        rm -f -- "$tmp"
        return 1
    fi
}

save_state() {
    local domain="$1"
    local name="$2"
    local port="$3"
    local password="$4"
    local config_id="$5"
    local dest="${6:-$SS_STATE_FILE}"
    local tmp

    [[ "$config_id" =~ ^[0-9a-f]{24}$ ]] || return 1
    secure_config_dir || return 1
    tmp="$(mktemp "$CONFIG_DIR/.vpsbox-ss-state.XXXXXX")" || return 1
    if ! {
        printf 'PROTOCOL=shadowsocks\n' &&
            printf 'CONFIG_ID=%s\n' "$config_id" &&
            printf 'DOMAIN=%s\n' "$domain" &&
            printf 'NAME=%s\n' "$name" &&
            printf 'PORT=%s\n' "$port" &&
            printf 'PASSWORD=%s\n' "$password" &&
            printf 'METHOD=%s\n' "$SS_METHOD"
    } > "$tmp"; then
        rm -f -- "$tmp"
        return 1
    fi
    commit_node_state_file "$tmp" "$dest"
}

save_vless_reality_state() {
    local domain="$1" name="$2" port="$3" uuid="$4" server_name="$5"
    local private_key="$6" public_key="$7" short_id="$8"
    local config_id="$9"
    local dest="${10:-$VLESS_STATE_FILE}"
    local tmp

    [[ "$config_id" =~ ^[0-9a-f]{24}$ ]] || return 1
    secure_config_dir || return 1
    tmp="$(mktemp "$CONFIG_DIR/.vpsbox-vless-state.XXXXXX")" || return 1
    if ! {
        printf 'PROTOCOL=vless-reality\n' &&
            printf 'CONFIG_ID=%s\n' "$config_id" &&
            printf 'DOMAIN=%s\n' "$domain" &&
            printf 'NAME=%s\n' "$name" &&
            printf 'PORT=%s\n' "$port" &&
            printf 'UUID=%s\n' "$uuid" &&
            printf 'FLOW=xtls-rprx-vision\n' &&
            printf 'REALITY_SERVER_NAME=%s\n' "$server_name" &&
            printf 'REALITY_PRIVATE_KEY=%s\n' "$private_key" &&
            printf 'REALITY_PUBLIC_KEY=%s\n' "$public_key" &&
            printf 'REALITY_SHORT_ID=%s\n' "$short_id" &&
            printf 'FINGERPRINT=chrome\n'
    } > "$tmp"; then
        rm -f -- "$tmp"
        return 1
    fi
    commit_node_state_file "$tmp" "$dest"
}

normalize_host() {
    local host="$1"
    local no_colons
    local colon_count

    host="$(sanitize_paste_input "$host")"
    host="$(printf '%s' "$host" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
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
        [ "${#part}" -eq 1 ] || [[ "$part" != 0* ]] || return 1
        ((10#$part <= 255)) || return 1
    done
}

is_ipv6_address_basic() {
    local ip="$1"
    local check_ip
    local maybe_v4
    local left right
    local side segment
    local units=0
    local -a chunks

    [[ "$ip" == *:* ]] || return 1
    [[ "$ip" =~ ^[0-9A-Fa-f:.]+$ ]] || return 1
    [[ "$ip" != *:::* ]] || return 1
    [[ "$ip" != :[^:]* ]] || return 1
    [[ "$ip" != *[^:]: ]] || return 1

    check_ip="$ip"
    if [[ "$check_ip" == *.* ]]; then
        maybe_v4="${check_ip##*:}"
        is_ipv4_address "$maybe_v4" || return 1
        check_ip="${check_ip%"$maybe_v4"}0:0"
    fi

    if [[ "$check_ip" == *::* ]]; then
        right="${check_ip#*::}"
        [[ "$right" != *::* ]] || return 1
        left="${check_ip%%::*}"
        for side in "$left" "$right"; do
            [ -n "$side" ] || continue
            IFS=: read -r -a chunks <<< "$side"
            for segment in "${chunks[@]}"; do
                [[ "$segment" =~ ^[0-9A-Fa-f]{1,4}$ ]] || return 1
                units=$((units + 1))
            done
        done
        # "::" 必须压缩至少一个 16 位段；七个显式段加边缘压缩仍是合法地址。
        [ "$units" -lt 8 ]
    else
        IFS=: read -r -a chunks <<< "$check_ip"
        [ "${#chunks[@]}" -eq 8 ] || return 1
        for segment in "${chunks[@]}"; do
            if [[ ! "$segment" =~ ^[0-9A-Fa-f]{1,4}$ ]]; then
                return 1
            fi
        done
        return 0
    fi
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

node_ipv4_is_assigned_locally() {
    local address="$1"

    command -v ip >/dev/null 2>&1 || return 1
    ip -4 -o addr show scope global 2>/dev/null \
        | awk -v target="$address" '{ split($4, parts, "/"); if (parts[1] == target) found = 1 } END { exit !found }'
}

prompt_node_host() {
    local result_var="$1"
    local prompt="$2"
    local input_host host

    [[ "$result_var" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || return 1

    while true; do
        read -r -p "$prompt" input_host || return 1
        host="$(normalize_host "$input_host")"

        if [ -z "$host" ]; then
            info "正在自动检测 VPS 公网 IPv4..."
            host="$(normalize_host "$(public_ipv4 || true)")"
            if ! is_ipv4_address "$host"; then
                warn "公网 IPv4 自动检测失败，请手动输入节点连接地址。"
                continue
            fi

            info "自动检测到公网 IPv4：$host"
            if ! confirm_default_yes "确认使用该公网 IPv4？"; then
                info "请手动输入节点连接地址。"
                continue
            fi
            if command -v ip >/dev/null 2>&1 && ! node_ipv4_is_assigned_locally "$host"; then
                warn "该公网 IPv4 未直接配置在本机，当前 VPS 可能使用 NAT。"
                warn "请确认公网映射地址正确，并将后续节点端口映射到相同端口。"
            fi
        elif ! is_valid_node_host "$host"; then
            err "格式不正确，请输入类似 sb.example.com、1.2.3.4 或 2001:db8::1。"
            continue
        fi

        if is_repeated_node_host "$host"; then
            err "检测到节点地址可能被重复粘贴：$host"
            err "请只输入一次域名或 IP。"
            continue
        fi

        printf -v "$result_var" '%s' "$host"
        info "已识别节点连接地址：$host"
        return 0
    done
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

generate_link_from_loaded_state() {
    local host
    local encoded

    host="$(uri_host "${DOMAIN:-}")" || return 1
    case "${PROTOCOL:-shadowsocks}" in
        shadowsocks)
            encoded="$(url_encode_userinfo "${METHOD:-$SS_METHOD}:${PASSWORD:-}")" || return 1
            printf 'ss://%s@%s:%s#%s\n' "$encoded" "$host" "${PORT:-0}" "${NAME:-ss}"
            ;;
        vless-reality)
            printf 'vless://%s@%s:%s?encryption=none&flow=%s&security=reality&sni=%s&fp=%s&pbk=%s&sid=%s&type=tcp#%s\n' \
                "$UUID" "$host" "$PORT" "$FLOW" "$REALITY_SERVER_NAME" "$FINGERPRINT" \
                "$REALITY_PUBLIC_KEY" "$REALITY_SHORT_ID" "$NAME"
            ;;
        *) return 1 ;;
    esac
}

generate_protocol_link() {
    load_protocol_state "$1" || return 1
    generate_link_from_loaded_state
}

secure_uri_build_files() {
    local build_dir="$1"
    local path

    for path in "$build_dir"/*.txt; do
        [ -f "$path" ] || continue
        chown root:root "$path" && chmod 600 "$path" || return 1
    done
}

build_current_uri_files() {
    local build_dir="$1"
    local aggregate="$build_dir/${URI_FILE##*/}"
    local protocol dest tmp
    local has_node=0

    mkdir -p "$build_dir" || return 1
    : > "$aggregate" || return 1
    for protocol in ss vless; do
        dest="$(node_uri_path "$protocol")" || return 1
        tmp="$build_dir/${dest##*/}"
        if protocol_node_exists "$protocol"; then
            generate_protocol_link "$protocol" > "$tmp" || return 1
            cat "$tmp" >> "$aggregate" || return 1
            has_node=1
        fi
    done
    if [ "$has_node" -eq 0 ]; then
        rm -f -- "$aggregate" || return 1
    fi
    secure_uri_build_files "$build_dir"
}

restore_uri_file_group() {
    local backup_dir="$1"
    local dest backup

    for dest in "$URI_FILE" "$SS_URI_FILE" "$VLESS_URI_FILE"; do
        rm -f -- "$dest" || return 1
        backup="$backup_dir/${dest##*/}"
        if [ -f "$backup" ]; then
            cp -a -- "$backup" "$dest" || return 1
        fi
    done
}

publish_uri_file_group() {
    local build_dir="$1"
    local rollback_dir tmp_dir dest source tmp failed=0

    rollback_dir="$(mktemp -d "$CONFIG_DIR/.vpsbox-uri-rollback.XXXXXX")" || return 1
    tmp_dir="$(mktemp -d "$CONFIG_DIR/.vpsbox-uri-publish.XXXXXX")" || {
        rm -rf -- "$rollback_dir"
        return 1
    }
    for dest in "$URI_FILE" "$SS_URI_FILE" "$VLESS_URI_FILE"; do
        [ ! -L "$dest" ] || {
            rm -rf -- "$rollback_dir" "$tmp_dir"
            return 1
        }
        if [ -f "$dest" ]; then
            cp -a -- "$dest" "$rollback_dir/${dest##*/}" || {
                rm -rf -- "$rollback_dir" "$tmp_dir"
                return 1
            }
        fi
        source="$build_dir/${dest##*/}"
        if [ -f "$source" ]; then
            tmp="$tmp_dir/${dest##*/}"
            cp -- "$source" "$tmp" &&
                chown root:root "$tmp" &&
                chmod 600 "$tmp" || {
                rm -rf -- "$rollback_dir" "$tmp_dir"
                return 1
            }
        fi
    done
    for dest in "$URI_FILE" "$SS_URI_FILE" "$VLESS_URI_FILE"; do
        tmp="$tmp_dir/${dest##*/}"
        if [ -f "$tmp" ]; then
            mv -f -- "$tmp" "$dest" || { failed=1; break; }
        else
            rm -f -- "$dest" || { failed=1; break; }
        fi
    done
    if [ "$failed" -ne 0 ]; then
        if ! restore_uri_file_group "$rollback_dir"; then
            err "节点链接文件组更新失败，旧链接组也未能完整恢复。"
        fi
        rm -rf -- "$rollback_dir" "$tmp_dir"
        return 1
    fi
    rm -rf -- "$rollback_dir" "$tmp_dir"
}

write_uri_files() {
    local build_dir

    secure_config_dir || return 1
    build_dir="$(mktemp -d "$CONFIG_DIR/.vpsbox-uri-build.XXXXXX")" || return 1
    if ! build_current_uri_files "$build_dir" ||
        ! publish_uri_file_group "$build_dir"; then
        rm -rf -- "$build_dir"
        return 1
    fi
    rm -rf -- "$build_dir"
}

backup_node_files() {
    local backup_dir="$1"
    local manifest="$backup_dir/manifest"

    command -v sha256sum >/dev/null 2>&1 || {
        err "缺少 sha256sum，无法建立可校验的节点事务备份。"
        return 1
    }
    mkdir -p "$backup_dir" || return 1
    : > "$manifest" || return 1
    printf 'version|1\n' >> "$manifest" || return 1

    backup_node_file_with_manifest "$URI_FILE" "$backup_dir/node-uri.txt" \
        node-uri.txt "$manifest" || return 1

    if [ -d "$NODE_CONFIG_DIR" ] && [ ! -L "$NODE_CONFIG_DIR" ]; then
        cp -a "$NODE_CONFIG_DIR" "$backup_dir/vpsbox.d" || return 1
        printf 'dir|vpsbox.d|present|-\n' >> "$manifest" || return 1
        backup_node_copied_file_with_manifest \
            "$backup_dir/vpsbox.d/${SS_CONFIG_PATH##*/}" \
            "vpsbox.d/${SS_CONFIG_PATH##*/}" "$manifest" || return 1
        backup_node_copied_file_with_manifest \
            "$backup_dir/vpsbox.d/${VLESS_CONFIG_PATH##*/}" \
            "vpsbox.d/${VLESS_CONFIG_PATH##*/}" "$manifest" || return 1
    elif [ ! -e "$NODE_CONFIG_DIR" ] && [ ! -L "$NODE_CONFIG_DIR" ]; then
        printf 'dir|vpsbox.d|absent|-\n' >> "$manifest" || return 1
        printf 'file|vpsbox.d/%s|absent|-\n' "${SS_CONFIG_PATH##*/}" >> "$manifest" || return 1
        printf 'file|vpsbox.d/%s|absent|-\n' "${VLESS_CONFIG_PATH##*/}" >> "$manifest" || return 1
    else
        return 1
    fi

    backup_node_file_with_manifest "$SS_STATE_FILE" "$backup_dir/ss-state.env" \
        ss-state.env "$manifest" || return 1
    backup_node_file_with_manifest "$VLESS_STATE_FILE" "$backup_dir/vless-state.env" \
        vless-state.env "$manifest" || return 1
    backup_node_file_with_manifest "$SS_URI_FILE" "$backup_dir/ss-uri.txt" \
        ss-uri.txt "$manifest" || return 1
    backup_node_file_with_manifest "$VLESS_URI_FILE" "$backup_dir/vless-uri.txt" \
        vless-uri.txt "$manifest" || return 1
    backup_node_file_with_manifest /etc/systemd/system/sing-box.service \
        "$backup_dir/sing-box.service" sing-box.service "$manifest" || return 1
    backup_node_file_with_manifest /etc/init.d/sing-box \
        "$backup_dir/openrc-sing-box" openrc-sing-box "$manifest" || return 1

    if service_is_running; then
        printf '1\n' > "$backup_dir/service-running" || return 1
    else
        printf '0\n' > "$backup_dir/service-running" || return 1
    fi
    if service_is_enabled; then
        printf '1\n' > "$backup_dir/service-enabled" || return 1
    else
        printf '0\n' > "$backup_dir/service-enabled" || return 1
    fi
    chown root:root "$backup_dir/service-running" "$backup_dir/service-enabled" "$manifest" ||
        return 1
    chmod 600 "$backup_dir/service-running" "$backup_dir/service-enabled" "$manifest" ||
        return 1
    backup_node_copied_file_with_manifest "$backup_dir/service-running" \
        service-running "$manifest" || return 1
    backup_node_copied_file_with_manifest "$backup_dir/service-enabled" \
        service-enabled "$manifest" || return 1
}

backup_node_file_with_manifest() {
    local source="$1" backup="$2" name="$3" manifest="$4"
    local digest

    if [ -f "$source" ] && [ ! -L "$source" ]; then
        cp -a -- "$source" "$backup" || return 1
        digest="$(sha256sum "$backup" | awk '{print $1}')" || return 1
        [[ "$digest" =~ ^[0-9a-f]{64}$ ]] || return 1
        printf 'file|%s|present|%s\n' "$name" "$digest" >> "$manifest"
    elif [ ! -e "$source" ] && [ ! -L "$source" ]; then
        printf 'file|%s|absent|-\n' "$name" >> "$manifest"
    else
        return 1
    fi
}

backup_node_copied_file_with_manifest() {
    local backup="$1" name="$2" manifest="$3"
    local digest

    if [ -f "$backup" ] && [ ! -L "$backup" ]; then
        digest="$(sha256sum "$backup" | awk '{print $1}')" || return 1
        [[ "$digest" =~ ^[0-9a-f]{64}$ ]] || return 1
        printf 'file|%s|present|%s\n' "$name" "$digest" >> "$manifest"
    elif [ ! -e "$backup" ] && [ ! -L "$backup" ]; then
        printf 'file|%s|absent|-\n' "$name" >> "$manifest"
    else
        return 1
    fi
}

node_backup_file_is_safe() {
    local file="$1" owner group mode

    [ -f "$file" ] && [ ! -L "$file" ] || return 1
    if [ "${VPSBOX_TEST_MODE:-0}" = "1" ]; then
        return 0
    fi
    owner="$(stat -c '%u' "$file" 2>/dev/null)" || return 1
    group="$(stat -c '%g' "$file" 2>/dev/null)" || return 1
    mode="$(stat -c '%a' "$file" 2>/dev/null)" || return 1
    [[ "$mode" =~ ^[0-7]{3,4}$ ]] || return 1
    [ "$owner" = "0" ] && [ "$group" = "0" ] &&
        [ $((8#$mode & 8#022)) -eq 0 ]
}

node_backup_manifest_entry() {
    local manifest="$1" name="$2"

    awk -F'|' -v name="$name" '
        $2 == name { line=$0; count++ }
        END {
            if (count == 1) print line
            else exit 1
        }
    ' "$manifest"
}

validate_node_backup_file_entry() {
    local manifest="$1" name="$2" path="$3"
    local line kind entry_name state digest actual

    line="$(node_backup_manifest_entry "$manifest" "$name")" || return 1
    IFS='|' read -r kind entry_name state digest <<< "$line"
    [ "$kind" = "file" ] && [ "$entry_name" = "$name" ] || return 1
    case "$state" in
        present)
            [[ "$digest" =~ ^[0-9a-f]{64}$ ]] || return 1
            node_backup_file_is_safe "$path" || return 1
            actual="$(sha256sum "$path" | awk '{print $1}')" || return 1
            [ "$actual" = "$digest" ]
            ;;
        absent)
            [ "$digest" = "-" ] && [ ! -e "$path" ] && [ ! -L "$path" ]
            ;;
        *) return 1 ;;
    esac
}

node_backup_entry_is_present() {
    local manifest="$1" name="$2" line kind entry_name state digest

    line="$(node_backup_manifest_entry "$manifest" "$name")" || return 2
    IFS='|' read -r kind entry_name state digest <<< "$line"
    [ "$entry_name" = "$name" ] || return 2
    case "$state" in
        present) return 0 ;;
        absent) return 1 ;;
        *) return 2 ;;
    esac
}

validate_node_transaction_backup() {
    local backup_dir="$1"
    local manifest="$backup_dir/manifest"
    local config_dir="$backup_dir/vpsbox.d"
    local ss_config="$config_dir/${SS_CONFIG_PATH##*/}"
    local vless_config="$config_dir/${VLESS_CONFIG_PATH##*/}"
    local line kind name state digest expected="" link protocol path
    local config_dir_present=0 config_count=0 entry_status
    local -a entries=(
        node-uri.txt vpsbox.d "vpsbox.d/${SS_CONFIG_PATH##*/}"
        "vpsbox.d/${VLESS_CONFIG_PATH##*/}" ss-state.env vless-state.env
        ss-uri.txt vless-uri.txt sing-box.service openrc-sing-box
        service-running service-enabled
    )

    command -v sha256sum >/dev/null 2>&1 || return 1
    [ -d "$backup_dir" ] && [ ! -L "$backup_dir" ] || return 1
    node_backup_file_is_safe "$manifest" || return 1
    [ "$(sed -n '1p' "$manifest")" = "version|1" ] || return 1
    [ "$(wc -l < "$manifest")" -eq 13 ] || return 1
    for name in "${entries[@]}"; do
        node_backup_manifest_entry "$manifest" "$name" >/dev/null || return 1
    done

    line="$(node_backup_manifest_entry "$manifest" vpsbox.d)" || return 1
    IFS='|' read -r kind name state digest <<< "$line"
    [ "$kind" = "dir" ] && [ "$name" = "vpsbox.d" ] && [ "$digest" = "-" ] || return 1
    case "$state" in
        present)
            [ -d "$config_dir" ] && [ ! -L "$config_dir" ] || return 1
            config_dir_present=1
            ;;
        absent)
            [ ! -e "$config_dir" ] && [ ! -L "$config_dir" ] || return 1
            ;;
        *) return 1 ;;
    esac

    validate_node_backup_file_entry "$manifest" node-uri.txt "$backup_dir/node-uri.txt" || return 1
    validate_node_backup_file_entry "$manifest" "vpsbox.d/${SS_CONFIG_PATH##*/}" "$ss_config" || return 1
    validate_node_backup_file_entry "$manifest" "vpsbox.d/${VLESS_CONFIG_PATH##*/}" "$vless_config" || return 1
    validate_node_backup_file_entry "$manifest" ss-state.env "$backup_dir/ss-state.env" || return 1
    validate_node_backup_file_entry "$manifest" vless-state.env "$backup_dir/vless-state.env" || return 1
    validate_node_backup_file_entry "$manifest" ss-uri.txt "$backup_dir/ss-uri.txt" || return 1
    validate_node_backup_file_entry "$manifest" vless-uri.txt "$backup_dir/vless-uri.txt" || return 1
    validate_node_backup_file_entry "$manifest" sing-box.service "$backup_dir/sing-box.service" || return 1
    validate_node_backup_file_entry "$manifest" openrc-sing-box "$backup_dir/openrc-sing-box" || return 1
    validate_node_backup_file_entry "$manifest" service-running "$backup_dir/service-running" || return 1
    validate_node_backup_file_entry "$manifest" service-enabled "$backup_dir/service-enabled" || return 1

    grep -Eq '^[01]$' "$backup_dir/service-running" || return 1
    grep -Eq '^[01]$' "$backup_dir/service-enabled" || return 1

    if node_backup_entry_is_present "$manifest" "vpsbox.d/${SS_CONFIG_PATH##*/}"; then
        node_backup_entry_is_present "$manifest" ss-state.env || return 1
        validate_protocol_node_artifacts ss "$ss_config" "$backup_dir/ss-state.env" \
            "$backup_dir/ss-uri.txt" || return 1
        config_count=$((config_count + 1))
    else
        entry_status=$?
        [ "$entry_status" -eq 1 ] || return 1
        if node_backup_entry_is_present "$manifest" ss-state.env; then
            return 1
        else
            entry_status=$?
            [ "$entry_status" -eq 1 ] || return 1
        fi
    fi
    if node_backup_entry_is_present "$manifest" "vpsbox.d/${VLESS_CONFIG_PATH##*/}"; then
        node_backup_entry_is_present "$manifest" vless-state.env || return 1
        validate_protocol_node_artifacts vless "$vless_config" "$backup_dir/vless-state.env" \
            "$backup_dir/vless-uri.txt" || return 1
        config_count=$((config_count + 1))
    else
        entry_status=$?
        [ "$entry_status" -eq 1 ] || return 1
        if node_backup_entry_is_present "$manifest" vless-state.env; then
            return 1
        else
            entry_status=$?
            [ "$entry_status" -eq 1 ] || return 1
        fi
    fi
    if [ "$config_count" -gt 0 ]; then
        [ "$config_dir_present" -eq 1 ] || return 1
        while IFS= read -r path; do
            [ -n "$path" ] || continue
            case "$path" in
                "$ss_config"|"$vless_config") ;;
                *) return 1 ;;
            esac
        done < <(find "$config_dir" -mindepth 1 -maxdepth 1 -print 2>/dev/null)
        command -v sing-box >/dev/null 2>&1 || return 1
        sing-box check -C "$config_dir" >/dev/null || return 1
    elif [ "$config_dir_present" -eq 1 ]; then
        [ -z "$(find "$config_dir" -mindepth 1 -maxdepth 1 -print 2>/dev/null)" ] || return 1
    fi

    if node_backup_entry_is_present "$manifest" node-uri.txt; then
        for protocol in ss vless; do
            case "$protocol" in
                ss)
                    if node_backup_entry_is_present "$manifest" ss-state.env; then
                        :
                    else
                        entry_status=$?
                        [ "$entry_status" -eq 1 ] || return 1
                        continue
                    fi
                    load_state_file "$backup_dir/ss-state.env" shadowsocks || return 1
                    ;;
                vless)
                    if node_backup_entry_is_present "$manifest" vless-state.env; then
                        :
                    else
                        entry_status=$?
                        [ "$entry_status" -eq 1 ] || return 1
                        continue
                    fi
                    load_state_file "$backup_dir/vless-state.env" vless-reality || return 1
                    ;;
            esac
            link="$(generate_link_from_loaded_state)" || return 1
            [ -n "$expected" ] && expected="${expected}"$'\n'
            expected="${expected}${link}"
        done
        [ -n "$expected" ] && [ "$(cat "$backup_dir/node-uri.txt")" = "$expected" ] || return 1
    else
        [ "$?" -eq 1 ] || return 1
    fi
}

sync_node_transaction_store() {
    [ "${VPSBOX_TEST_MODE:-0}" != "1" ] || return 0
    command -v sync >/dev/null 2>&1 || return 1
    sync
}

node_transaction_dir_valid() {
    [ "${1:-}" = "$NODE_TRANSACTION_DIR" ] &&
        [ "$NODE_TRANSACTION_DIR" = "$VPSBOX_STATE_DIR/node-transaction" ]
}

remove_node_transaction_dir() {
    local transaction_dir="${1:-$NODE_TRANSACTION_DIR}"

    node_transaction_dir_valid "$transaction_dir" || {
        err "节点事务目录异常，已拒绝递归清理：$transaction_dir"
        return 1
    }
    [ ! -L "$transaction_dir" ] || {
        err "节点事务目录是符号链接，已拒绝清理：$transaction_dir"
        return 1
    }
    rm -rf -- "$transaction_dir"
}

prepare_node_transaction_store() {
    [ ! -L "$VPSBOX_STATE_DIR" ] && [ ! -L "$NODE_TRANSACTION_DIR" ] || {
        err "节点事务路径包含符号链接，已拒绝使用。"
        return 1
    }
    mkdir -p "$VPSBOX_STATE_DIR" || return 1
    chown root:root "$VPSBOX_STATE_DIR" || return 1
    chmod 700 "$VPSBOX_STATE_DIR"
}

begin_node_transaction() {
    prepare_node_transaction_store || return 1
    if [ -e "$NODE_TRANSACTION_DIR/pending" ]; then
        err "检测到尚未恢复的节点事务，已拒绝开始新操作：$NODE_TRANSACTION_DIR"
        return 1
    fi
    if [ -e "$NODE_TRANSACTION_DIR/committed" ]; then
        node_file_is_secure "$NODE_TRANSACTION_DIR/committed" || {
            err "节点事务 committed 标记不安全，已拒绝开始新操作。"
            return 1
        }
        remove_node_transaction_dir || return 1
    elif [ -e "$NODE_TRANSACTION_DIR" ]; then
        # pending 标记只会在完整备份后写入；没有标记说明尚未修改节点文件。
        remove_node_transaction_dir || return 1
    fi
    mkdir -p "$NODE_TRANSACTION_BACKUP" "$NODE_TRANSACTION_STAGE" || {
        remove_node_transaction_dir || true
        return 1
    }
    chown root:root "$NODE_TRANSACTION_DIR" "$NODE_TRANSACTION_BACKUP" "$NODE_TRANSACTION_STAGE" || {
        remove_node_transaction_dir || true
        return 1
    }
    chmod 700 "$NODE_TRANSACTION_DIR" "$NODE_TRANSACTION_BACKUP" "$NODE_TRANSACTION_STAGE" || {
        remove_node_transaction_dir || true
        return 1
    }
    if ! backup_node_files "$NODE_TRANSACTION_BACKUP"; then
        remove_node_transaction_dir || true
        return 1
    fi
    if ! validate_node_transaction_backup "$NODE_TRANSACTION_BACKUP" ||
        ! sync_node_transaction_store; then
        remove_node_transaction_dir || true
        err "节点事务备份未通过完整性或持久化检查。"
        return 1
    fi
    : > "$NODE_TRANSACTION_DIR/pending" || {
        remove_node_transaction_dir || true
        return 1
    }
    chown root:root "$NODE_TRANSACTION_DIR/pending" &&
        chmod 600 "$NODE_TRANSACTION_DIR/pending" || {
        remove_node_transaction_dir || true
        return 1
    }
    sync_node_transaction_store || {
        remove_node_transaction_dir || true
        return 1
    }
    ACTIVE_NODE_BACKUP="$NODE_TRANSACTION_DIR"
    ACTIVE_NODE_TRANSACTION_MUTATED=0
}

mark_node_transaction_mutated() {
    [ "${ACTIVE_NODE_BACKUP:-}" = "$NODE_TRANSACTION_DIR" ] || return 1
    [ -f "$NODE_TRANSACTION_DIR/pending" ] && [ ! -L "$NODE_TRANSACTION_DIR/pending" ] ||
        return 1
    : > "$NODE_TRANSACTION_DIR/mutated" || return 1
    chown root:root "$NODE_TRANSACTION_DIR/mutated" &&
        chmod 600 "$NODE_TRANSACTION_DIR/mutated" || return 1
    sync_node_transaction_store || return 1
    ACTIVE_NODE_TRANSACTION_MUTATED=1
}

cancel_unmodified_node_transaction() {
    local transaction_dir="${ACTIVE_NODE_BACKUP:-}"

    [ -n "$transaction_dir" ] || return 0
    node_transaction_dir_valid "$transaction_dir" || return 1
    [ "${ACTIVE_NODE_TRANSACTION_MUTATED:-0}" = "0" ] || return 1
    [ ! -e "$transaction_dir/mutated" ] || return 1
    ACTIVE_NODE_BACKUP=""
    ACTIVE_NODE_TRANSACTION_MUTATED=0
    remove_node_transaction_dir "$transaction_dir"
}

commit_node_transaction() {
    [ "${ACTIVE_NODE_BACKUP:-}" = "$NODE_TRANSACTION_DIR" ] || return 1
    [ -f "$NODE_TRANSACTION_DIR/pending" ] && [ ! -L "$NODE_TRANSACTION_DIR/pending" ] || return 1
    : > "$NODE_TRANSACTION_DIR/committed" || return 1
    chown root:root "$NODE_TRANSACTION_DIR/committed" &&
        chmod 600 "$NODE_TRANSACTION_DIR/committed" || return 1
    sync_node_transaction_store || return 1
    rm -f -- "$NODE_TRANSACTION_DIR/pending" || return 1
    sync_node_transaction_store || return 1
    ACTIVE_NODE_BACKUP=""
    ACTIVE_NODE_TRANSACTION_MUTATED=0
    remove_node_transaction_dir || {
        warn "节点事务已提交，但临时目录未能清理：$NODE_TRANSACTION_DIR"
        return 0
    }
}

restore_node_files() {
    local backup_dir="$1"
    local was_running="0"
    local was_enabled="0"
    local failed=0

    if ! validate_node_transaction_backup "$backup_dir"; then
        err "节点事务备份不完整、不可解析或哈希不匹配，已拒绝覆盖现有节点文件。"
        err "事务备份已保留：$backup_dir"
        return 1
    fi
    was_running="$(cat "$backup_dir/service-running")" || return 1
    was_enabled="$(cat "$backup_dir/service-enabled")" || return 1

    warn "操作未完成，正在恢复操作前的节点配置..."
    service_stop 2>/dev/null || true
    stop_singbox_config_processes 2>/dev/null || true
    if service_manager_is_active || [ -n "$(singbox_config_pids)" ]; then
        err "sing-box 服务或残留进程未能停止，已拒绝覆盖节点文件。"
        err "事务备份已保留：$backup_dir"
        return 1
    fi

    [ "$NODE_CONFIG_DIR" = "$CONFIG_DIR/vpsbox.d" ] || {
        err "节点配置目录异常，已拒绝递归恢复：$NODE_CONFIG_DIR"
        return 1
    }
    rm -rf -- "$NODE_CONFIG_DIR" || failed=1
    rm -f "$URI_FILE" \
        "$SS_STATE_FILE" "$VLESS_STATE_FILE" "$SS_URI_FILE" "$VLESS_URI_FILE" || failed=1
    if [ -f "$backup_dir/node-uri.txt" ]; then cp -a "$backup_dir/node-uri.txt" "$URI_FILE" || failed=1; fi
    if [ -d "$backup_dir/vpsbox.d" ]; then cp -a "$backup_dir/vpsbox.d" "$NODE_CONFIG_DIR" || failed=1; fi
    if [ -f "$backup_dir/ss-state.env" ]; then cp -a "$backup_dir/ss-state.env" "$SS_STATE_FILE" || failed=1; fi
    if [ -f "$backup_dir/vless-state.env" ]; then cp -a "$backup_dir/vless-state.env" "$VLESS_STATE_FILE" || failed=1; fi
    if [ -f "$backup_dir/ss-uri.txt" ]; then cp -a "$backup_dir/ss-uri.txt" "$SS_URI_FILE" || failed=1; fi
    if [ -f "$backup_dir/vless-uri.txt" ]; then cp -a "$backup_dir/vless-uri.txt" "$VLESS_URI_FILE" || failed=1; fi

    if is_systemd; then
        if [ -f "$backup_dir/sing-box.service" ]; then
            cp -a "$backup_dir/sing-box.service" /etc/systemd/system/sing-box.service || failed=1
        else
            rm -f /etc/systemd/system/sing-box.service || failed=1
        fi
        systemctl daemon-reload 2>/dev/null || failed=1
    fi

    if [ "$OS" = "alpine" ]; then
        if [ -f "$backup_dir/openrc-sing-box" ]; then
            cp -a "$backup_dir/openrc-sing-box" /etc/init.d/sing-box || failed=1
        else
            rm -f /etc/init.d/sing-box || failed=1
        fi
    fi

    restore_singbox_service_state "$was_enabled" "$was_running" 2>/dev/null || failed=1

    if [ "$failed" -ne 0 ]; then
        err "操作前的节点配置恢复不完整，备份已保留：$backup_dir"
        return 1
    fi
    info "已恢复到创建前状态。"
}

rollback_node_files_transaction() {
    local transaction_dir="${ACTIVE_NODE_BACKUP:-}"

    [ -n "$transaction_dir" ] || return 0
    node_transaction_dir_valid "$transaction_dir" || return 1
    [ -f "$transaction_dir/pending" ] || return 1
    if [ "${ACTIVE_NODE_TRANSACTION_MUTATED:-0}" = "0" ] &&
        [ ! -e "$transaction_dir/mutated" ]; then
        cancel_unmodified_node_transaction
        return $?
    fi
    if ! restore_node_files "$transaction_dir/backup"; then
        return 1
    fi
    ACTIVE_NODE_BACKUP=""
    ACTIVE_NODE_TRANSACTION_MUTATED=0
    remove_node_transaction_dir "$transaction_dir"
}

rollback_active_node_transaction() {
    local transaction_dir="${ACTIVE_NODE_BACKUP:-}"
    local failed=0 had_firewall_transition=0

    [ -n "$transaction_dir" ] || return 0
    node_transaction_dir_valid "$transaction_dir" || return 1
    if [ "${ACTIVE_NODE_TRANSACTION_MUTATED:-0}" = "0" ] &&
        [ ! -e "$transaction_dir/mutated" ]; then
        cancel_unmodified_node_transaction
        return $?
    fi
    [ -n "${ACTIVE_FIREWALL_TRANSITION_DIR:-}" ] && had_firewall_transition=1
    if ! restore_node_files "$transaction_dir/backup"; then
        ACTIVE_NODE_BACKUP=""
        ACTIVE_NODE_TRANSACTION_MUTATED=0
        return 1
    fi
    if [ "$had_firewall_transition" -eq 1 ] &&
        declare -F firewall_abort_port_transition >/dev/null 2>&1; then
        firewall_abort_port_transition || {
            warn "节点已回滚，但主机防火墙临时规则恢复失败，请手动更新。"
            failed=1
        }
    elif declare -F firewall_refresh_if_enabled >/dev/null 2>&1; then
        firewall_refresh_if_enabled || {
            warn "节点已回滚，但主机防火墙端口重新同步失败，请手动更新。"
            failed=1
        }
    fi
    ACTIVE_NODE_BACKUP=""
    ACTIVE_NODE_TRANSACTION_MUTATED=0
    if [ "$failed" -ne 0 ]; then
        err "节点文件已恢复，但事务未完整结束；备份已保留：$transaction_dir"
        return 1
    fi
    remove_node_transaction_dir "$transaction_dir"
}

recover_pending_node_transaction() {
    local had_pending=0

    [ -e "$NODE_TRANSACTION_DIR" ] || return 0
    prepare_node_transaction_store || return 1
    node_transaction_dir_valid "$NODE_TRANSACTION_DIR" || return 1
    [ -d "$NODE_TRANSACTION_DIR" ] && [ ! -L "$NODE_TRANSACTION_DIR" ] || {
        err "节点事务目录不安全，已拒绝启动：$NODE_TRANSACTION_DIR"
        return 1
    }
    if [ -f "$NODE_TRANSACTION_DIR/committed" ]; then
        node_file_is_secure "$NODE_TRANSACTION_DIR/committed" || {
            err "节点事务 committed 标记不安全，已拒绝自动处理。"
            return 1
        }
        remove_node_transaction_dir
        return
    fi
    if [ -f "$NODE_TRANSACTION_DIR/pending" ]; then
        node_file_is_secure "$NODE_TRANSACTION_DIR/pending" || {
            err "节点事务 pending 标记不安全，已拒绝自动恢复。"
            return 1
        }
        had_pending=1
    fi
    if [ "$had_pending" -eq 0 ]; then
        # 没有 pending 表示上次只创建了未完成备份，尚未开始修改节点。
        remove_node_transaction_dir
        return
    fi
    if [ ! -e "$NODE_TRANSACTION_DIR/mutated" ]; then
        # pending 已持久化但还没有首次真实修改时，硬中断只需丢弃备份。
        remove_node_transaction_dir
        return
    fi
    node_file_is_secure "$NODE_TRANSACTION_DIR/mutated" || {
        err "节点事务 mutated 标记不安全，已拒绝自动恢复。"
        return 1
    }
    [ -d "$NODE_TRANSACTION_BACKUP" ] && [ ! -L "$NODE_TRANSACTION_BACKUP" ] || {
        err "待恢复节点事务缺少可信备份，已拒绝启动。"
        return 1
    }
    warn "检测到上次未提交的节点事务，正在优先恢复..."
    ACTIVE_NODE_BACKUP="$NODE_TRANSACTION_DIR"
    ACTIVE_NODE_TRANSACTION_MUTATED=1
    if ! restore_node_files "$NODE_TRANSACTION_BACKUP"; then
        ACTIVE_NODE_BACKUP=""
        ACTIVE_NODE_TRANSACTION_MUTATED=0
        err "未提交节点事务恢复失败，备份已保留；修复前禁止继续覆盖节点文件。"
        return 1
    fi
    if declare -F firewall_refresh_if_enabled >/dev/null 2>&1 &&
        ! firewall_refresh_if_enabled; then
        ACTIVE_NODE_BACKUP=""
        ACTIVE_NODE_TRANSACTION_MUTATED=0
        err "原节点已恢复，但主机防火墙同步失败；事务备份已保留。"
        return 1
    fi
    ACTIVE_NODE_BACKUP=""
    ACTIVE_NODE_TRANSACTION_MUTATED=0
    remove_node_transaction_dir || return 1
    info "未提交节点事务已完整恢复。"
}

port_in_use_tcp() {
    local port="$1" output

    command -v ss >/dev/null 2>&1 || return 2
    output="$(ss -H -ltn 2>/dev/null)" || return 2
    printf '%s\n' "$output" |
        awk -v port="$port" '$4 ~ ("[:.]" port "$") { found=1 } END { exit !found }'
}

port_in_use_udp() {
    local port="$1" output

    command -v ss >/dev/null 2>&1 || return 2
    output="$(ss -H -lun 2>/dev/null)" || return 2
    printf '%s\n' "$output" |
        awk -v port="$port" '$4 ~ ("[:.]" port "$") { found=1 } END { exit !found }'
}

port_in_use_for_protocols() {
    local port="$1" protocols="${2:-both}"
    local tcp_status udp_status

    case "$protocols" in
        tcp) port_in_use_tcp "$port" ;;
        udp) port_in_use_udp "$port" ;;
        both)
            if port_in_use_tcp "$port"; then
                tcp_status=0
            else
                tcp_status=$?
            fi
            if port_in_use_udp "$port"; then
                udp_status=0
            else
                udp_status=$?
            fi
            if [ "$tcp_status" -eq 0 ] || [ "$udp_status" -eq 0 ]; then
                return 0
            fi
            if [ "$tcp_status" -gt 1 ] || [ "$udp_status" -gt 1 ]; then
                return 2
            fi
            return 1
            ;;
        *) return 2 ;;
    esac
}

port_in_use() {
    port_in_use_for_protocols "$1" both
}

port_conflicts_with_existing_node() {
    local port="$1" desired="$2" existing="$3"

    [ "$desired" = "$existing" ] && return 1
    port_in_use_for_protocols "$port" "$desired"
}

port_listener_ready() {
    local port="$1" protocols="${2:-both}"

    case "$protocols" in
        tcp) port_in_use_tcp "$port" ;;
        udp) port_in_use_udp "$port" ;;
        both) port_in_use_tcp "$port" && port_in_use_udp "$port" ;;
        *) return 2 ;;
    esac
}

wait_for_port_listener() {
    local port="$1" protocols="${2:-both}" i
    for i in 1 2 3 4 5; do
        port_listener_ready "$port" "$protocols" && return 0
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
    local port docker_ports protocols="${2:-both}" reserved_node_ports="${3:-}"
    local i status

    command -v ss >/dev/null 2>&1 || {
        err "缺少 ss，无法可靠检查节点端口占用。"
        return 1
    }
    if ! ssh_effective_ports_csv >/dev/null 2>&1; then
        err "无法读取 SSH 当前生效端口，已取消随机端口选择。"
        return 1
    fi
    if [ "$#" -ge 1 ]; then
        docker_ports="$1"
    else
        docker_ports="$(docker_reserved_ports_csv "$protocols")" || {
            err "无法可靠读取 Docker 已发布端口，已取消随机端口选择。"
            return 1
        }
    fi
    for i in $(seq 1 100); do
        port="$(shuf -i "${PORT_MIN}-${PORT_MAX}" -n 1 2>/dev/null || echo $((RANDOM % (PORT_MAX - PORT_MIN + 1) + PORT_MIN)))"
        if port_in_use_for_protocols "$port" "$protocols"; then
            continue
        else
            status=$?
            [ "$status" -eq 1 ] || {
                err "无法检查端口 $port 的监听状态，已取消随机端口选择。"
                return 1
            }
        fi
        if port_is_effective_ssh_port "$port"; then
            continue
        else
            status=$?
            [ "$status" -eq 1 ] || {
                err "无法读取 SSH 当前生效端口，已取消随机端口选择。"
                return 1
            }
        fi
        if ! csv_contains_port "$docker_ports" "$port" &&
            ! csv_contains_port "$reserved_node_ports" "$port"; then
            echo "$port"
            return 0
        fi
    done
    err "连续 100 次未找到可用随机端口。"
    return 1
}

random_trace_source_port() {
    local port i status

    command -v ss >/dev/null 2>&1 || {
        err "缺少 ss，无法可靠选择 TCP 探测源端口。"
        return 1
    }

    # 探测源端口不是入站服务端口，不应依赖 Docker daemon 的保留端口清单。
    for i in $(seq 1 100); do
        port="$(shuf -i "${PORT_MIN}-${PORT_MAX}" -n 1 2>/dev/null || echo $((RANDOM % (PORT_MAX - PORT_MIN + 1) + PORT_MIN)))"
        if port_in_use_tcp "$port"; then
            continue
        else
            status=$?
            if [ "$status" -eq 1 ]; then
                echo "$port"
                return 0
            fi
            err "无法检查 TCP 端口 $port，已取消探测源端口选择。"
            return 1
        fi
    done
    err "连续 100 次未找到可用的 TCP 探测源端口。"
    return 1
}

normalize_port_decimal() {
    local port="${1:-}" normalized

    [[ "$port" =~ ^[0-9]+$ ]] || return 1
    normalized="${port#"${port%%[!0]*}"}"
    [ -n "$normalized" ] || normalized=0
    [ "${#normalized}" -le 5 ] || return 1
    [ "$normalized" -ge 1 ] && [ "$normalized" -le 65535 ] || return 1
    printf '%s\n' "$normalized"
}

is_valid_port() {
    local normalized

    normalized="$(normalize_port_decimal "${1:-}")" || return 1
    # 交互输入使用规范十进制，避免 00080 进入 JSON、状态文件或 nftables 后产生不同表示。
    [ "$normalized" = "$1" ]
}

port_is_effective_ssh_port() {
    local port="$1" ports

    ports="$(ssh_effective_ports_csv 2>/dev/null)" || return 2
    case ",$ports," in
        *",$port,"*) return 0 ;;
        *) return 1 ;;
    esac
}

choose_node_port() {
    local existing_port="${1:-}" protocols="${2:-both}" existing_protocols="${3:-}"
    local reserved_node_ports="${4:-}"
    local input confirm docker_ports managed_pids status

    command -v ss >/dev/null 2>&1 || {
        err "缺少 ss，无法可靠检查节点端口占用。"
        return 1
    }
    ssh_effective_ports_csv >/dev/null 2>&1 || {
        err "无法读取 SSH 当前生效端口，已取消节点端口选择。"
        return 1
    }

    docker_ports="$(docker_reserved_ports_for_port_choice "$protocols")" || {
        err "无法可靠读取 Docker 已发布端口，已取消节点端口选择。"
        return 1
    }

    while true; do
        if [ -n "$existing_port" ]; then
            printf '请输入节点端口（留空自动随机；当前端口 %s 可保留）: ' "$existing_port" >&2
        else
            printf '请输入节点端口（1-65535，留空自动随机）: ' >&2
        fi
        read -r input || return 1
        if [ -z "$input" ]; then
            random_port "$docker_ports" "$protocols" "$reserved_node_ports"
            return $?
        fi
        if ! is_valid_port "$input"; then
            err "端口必须是 1-65535 的整数。"
            continue
        fi
        if port_is_effective_ssh_port "$input"; then
            err "端口 $input 是当前 SSH 生效端口，不能用于节点。"
            continue
        else
            status=$?
            if [ "$status" -ne 1 ]; then
                err "无法读取 SSH 当前生效端口，已取消节点端口选择。"
                return 1
            fi
        fi
        if csv_contains_port "$reserved_node_ports" "$input"; then
            err "端口 $input 已被另一个节点使用，请更换。"
            continue
        fi
        managed_pids="$(singbox_config_pids || true)"
        status=1
        if [ "$input" = "$existing_port" ] && [ -n "$managed_pids" ]; then
            if port_conflicts_with_existing_node "$input" "$protocols" "$existing_protocols"; then
                status=0
            else
                status=$?
            fi
        elif port_in_use_for_protocols "$input" "$protocols"; then
            status=0
        else
            status=$?
        fi
        case "$status" in
            0)
                err "端口 $input 已被占用，请更换。"
                continue
                ;;
            1) ;;
            *)
                err "无法检查端口 $input 的监听状态，已取消节点端口选择。"
                return 1
                ;;
        esac
        if csv_contains_port "$docker_ports" "$input"; then
            err "端口 $input 已被 Docker 发布规则占用，请更换。"
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

configured_node_ports_csv() {
    local exclude_protocol="${1:-}" protocol result=""

    for protocol in ss vless; do
        [ "$protocol" != "$exclude_protocol" ] || continue
        if load_protocol_state "$protocol" >/dev/null 2>&1; then
            result="$(csv_add_port "$result" "$PORT")" || return 1
        fi
    done
    printf '%s\n' "$result"
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
      "method": "$SS_METHOD",
      "password": "$password"
    }$suffix
EOF
}

write_config() {
    local port="$1"
    local password="$2"
    local config_id="$3"
    local dest="${4:-$SS_CONFIG_PATH}"
    local mode tmp

    [[ "$config_id" =~ ^[0-9a-f]{24}$ ]] || return 1
    if [ "$dest" = "$SS_CONFIG_PATH" ]; then
        secure_node_config_dir || return 1
    else
        secure_config_dir || return 1
        [ -d "${dest%/*}" ] && [ ! -L "${dest%/*}" ] || return 1
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

    tmp="$(mktemp "$CONFIG_DIR/.10-ss.XXXXXX")" || return 1
    cat > "$tmp" <<EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
EOF
    case "$mode" in
        ipv6)
            write_shadowsocks_inbound_json "vpsbox-${config_id}-ss-in" "::" "$port" "$password" >> "$tmp"
            ;;
        dual)
            write_shadowsocks_inbound_json "vpsbox-${config_id}-ss-in-ipv4" "0.0.0.0" "$port" "$password" "," >> "$tmp"
            write_shadowsocks_inbound_json "vpsbox-${config_id}-ss-in-ipv6" "::" "$port" "$password" >> "$tmp"
            ;;
        *)
            write_shadowsocks_inbound_json "vpsbox-${config_id}-ss-in" "0.0.0.0" "$port" "$password" >> "$tmp"
            ;;
    esac

    cat >> "$tmp" <<EOF
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct-${config_id}-ss"
    }
  ]
}
EOF
    if ! chown root:root "$tmp" ||
        ! chmod 600 "$tmp" ||
        ! sing-box check -c "$tmp" >/dev/null ||
        ! mv -f -- "$tmp" "$dest"; then
        rm -f -- "$tmp"
        return 1
    fi
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
    local port="$1" uuid="$2" server_name="$3" private_key="$4" short_id="$5"
    local config_id="$6" dest="${7:-$VLESS_CONFIG_PATH}" mode tmp

    [[ "$config_id" =~ ^[0-9a-f]{24}$ ]] || return 1
    if [ "$dest" = "$VLESS_CONFIG_PATH" ]; then
        secure_node_config_dir || return 1
    else
        secure_config_dir || return 1
        [ -d "${dest%/*}" ] && [ ! -L "${dest%/*}" ] || return 1
    fi
    mode="$(listen_mode)"
    case "$mode" in
        ipv6) info "监听地址：::（IPv4/IPv6 双栈）" ;;
        dual) info "监听地址：0.0.0.0 + ::（系统启用了 IPv6-only 监听）" ;;
        *) info "监听地址：0.0.0.0" ;;
    esac

    tmp="$(mktemp "$CONFIG_DIR/.20-vless-reality.XXXXXX")" || return 1
    cat > "$tmp" <<EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
EOF
    case "$mode" in
        ipv6) write_vless_reality_inbound_json "vpsbox-${config_id}-vless-reality-in" "::" "$port" "$uuid" "$server_name" "$private_key" "$short_id" >> "$tmp" ;;
        dual)
            write_vless_reality_inbound_json "vpsbox-${config_id}-vless-reality-in-ipv4" "0.0.0.0" "$port" "$uuid" "$server_name" "$private_key" "$short_id" "," >> "$tmp"
            write_vless_reality_inbound_json "vpsbox-${config_id}-vless-reality-in-ipv6" "::" "$port" "$uuid" "$server_name" "$private_key" "$short_id" >> "$tmp"
            ;;
        *) write_vless_reality_inbound_json "vpsbox-${config_id}-vless-reality-in" "0.0.0.0" "$port" "$uuid" "$server_name" "$private_key" "$short_id" >> "$tmp" ;;
    esac
    cat >> "$tmp" <<EOF
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct-${config_id}-vless"
    }
  ]
}
EOF
    if ! chown root:root "$tmp" ||
        ! chmod 600 "$tmp" ||
        ! sing-box check -c "$tmp" >/dev/null ||
        ! mv -f -- "$tmp" "$dest"; then
        rm -f -- "$tmp"
        return 1
    fi
}

generate_node_config_id() {
    local config_id

    config_id="$(sing-box generate rand 12 --hex 2>/dev/null | tr -d '\r\n')" || return 1
    [[ "$config_id" =~ ^[0-9a-f]{24}$ ]] || return 1
    printf '%s\n' "$config_id"
}

prepare_node_stage() {
    [ "${ACTIVE_NODE_BACKUP:-}" = "$NODE_TRANSACTION_DIR" ] || return 1
    [ "$NODE_TRANSACTION_STAGE" = "$NODE_TRANSACTION_DIR/stage" ] || return 1
    rm -rf -- "$NODE_TRANSACTION_STAGE" || return 1
    mkdir -p "$NODE_TRANSACTION_STAGE/configs" \
        "$NODE_TRANSACTION_STAGE/states" "$NODE_TRANSACTION_STAGE/uris" || return 1
    chown -R root:root "$NODE_TRANSACTION_STAGE" || return 1
    chmod 700 "$NODE_TRANSACTION_STAGE" "$NODE_TRANSACTION_STAGE/configs" \
        "$NODE_TRANSACTION_STAGE/states" "$NODE_TRANSACTION_STAGE/uris"
}

stage_sibling_node_config() {
    local target_protocol="$1"
    local protocol source

    for protocol in ss vless; do
        [ "$protocol" != "$target_protocol" ] || continue
        if protocol_node_exists "$protocol"; then
            source="$(node_config_path "$protocol")" || return 1
            cp -- "$source" "$NODE_TRANSACTION_STAGE/configs/${source##*/}" || return 1
            chown root:root "$NODE_TRANSACTION_STAGE/configs/${source##*/}" &&
                chmod 600 "$NODE_TRANSACTION_STAGE/configs/${source##*/}" || return 1
        fi
    done
}

build_staged_uri_files() {
    local target_protocol="$1"
    local target_state="$2"
    local uri_dir="$NODE_TRANSACTION_STAGE/uris"
    local aggregate="$uri_dir/${URI_FILE##*/}"
    local protocol state expected dest

    : > "$aggregate" || return 1
    for protocol in ss vless; do
        dest="$(node_uri_path "$protocol")" || return 1
        if [ "$protocol" = "$target_protocol" ]; then
            state="$target_state"
            case "$protocol" in
                ss) expected=shadowsocks ;;
                vless) expected=vless-reality ;;
                *) return 2 ;;
            esac
            load_state_file "$state" "$expected" || return 1
            generate_link_from_loaded_state > "$uri_dir/${dest##*/}" || return 1
        elif protocol_node_exists "$protocol"; then
            generate_protocol_link "$protocol" > "$uri_dir/${dest##*/}" || return 1
        else
            continue
        fi
        cat "$uri_dir/${dest##*/}" >> "$aggregate" || return 1
    done
    secure_uri_build_files "$uri_dir"
}

validate_staged_node() {
    local protocol="$1"
    local config state uri final_path

    final_path="$(node_config_path "$protocol")" || return 1
    config="$NODE_TRANSACTION_STAGE/configs/${final_path##*/}"
    final_path="$(node_state_path "$protocol")" || return 1
    state="$NODE_TRANSACTION_STAGE/states/${final_path##*/}"
    final_path="$(node_uri_path "$protocol")" || return 1
    uri="$NODE_TRANSACTION_STAGE/uris/${final_path##*/}"
    validate_protocol_node_artifacts "$protocol" "$config" "$state" "$uri" || return 1
    sing-box check -C "$NODE_TRANSACTION_STAGE/configs" >/dev/null
}

publish_staged_node_file() {
    local source="$1"
    local dest="$2"
    local tmp

    [ -f "$source" ] && [ ! -L "$source" ] || return 1
    tmp="$(mktemp "${dest}.publish.XXXXXX")" || return 1
    if ! cp -- "$source" "$tmp" ||
        ! chown root:root "$tmp" ||
        ! chmod 600 "$tmp" ||
        ! mv -f -- "$tmp" "$dest"; then
        rm -f -- "$tmp"
        return 1
    fi
}

publish_staged_node() {
    local protocol="$1"
    local config state

    config="$(node_config_path "$protocol")" || return 1
    state="$(node_state_path "$protocol")" || return 1
    prepare_node_layout_for_write || return 1
    publish_staged_node_file \
        "$NODE_TRANSACTION_STAGE/configs/${config##*/}" "$config" || return 1
    publish_staged_node_file \
        "$NODE_TRANSACTION_STAGE/states/${state##*/}" "$state" || return 1
    publish_uri_file_group "$NODE_TRANSACTION_STAGE/uris" || return 1
    require_valid_node_state_if_present
}

check_node_config_set() {
    [ -d "$NODE_CONFIG_DIR" ] && [ ! -L "$NODE_CONFIG_DIR" ] || return 1
    { [ -f "$SS_CONFIG_PATH" ] || [ -f "$VLESS_CONFIG_PATH" ]; } || return 1
    node_config_dir_contents_valid || return 1
    sing-box check -C "$NODE_CONFIG_DIR" >/dev/null
}

check_active_node_config() {
    require_valid_node_state_if_present || return 1
    node_exists || return 1
    check_node_config_set
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
    command -v openssl >/dev/null 2>&1 || {
        err "未找到 openssl，无法验证 Reality 目标的 TLS 443。"
        return 1
    }
    run_bounded_command 12 openssl s_client \
        -connect "${server_name}:443" -servername "$server_name" \
        </dev/null >/dev/null 2>&1
}

render_singbox_systemd_service() {
    local bin="$1"

    require_valid_node_state_if_present || return 1
    node_exists || return 1

    cat <<EOF
[Unit]
Description=Sing-box Proxy Server
Documentation=https://sing-box.sagernet.org
After=network.target nss-lookup.target
Wants=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$CONFIG_DIR
ExecStart=$bin run -C $NODE_CONFIG_DIR
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
}

render_singbox_openrc_service() {
    local bin="$1"

    require_valid_node_state_if_present || return 1
    node_exists || return 1

    cat <<EOF
#!/sbin/openrc-run
name="sing-box"
description="Sing-box Proxy Server"
command="$bin"
command_args="run -C $NODE_CONFIG_DIR"
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
}

singbox_service_definition_is_current() {
    local bin

    bin="$(command -v sing-box 2>/dev/null)" || return 1
    if is_systemd; then
        [ -f /etc/systemd/system/sing-box.service ] &&
            [ ! -L /etc/systemd/system/sing-box.service ] || return 1
        render_singbox_systemd_service "$bin" |
            cmp -s - /etc/systemd/system/sing-box.service
    elif [ "$OS" = "alpine" ] && command -v rc-service >/dev/null 2>&1; then
        [ -f /etc/init.d/sing-box ] && [ ! -L /etc/init.d/sing-box ] || return 1
        render_singbox_openrc_service "$bin" | cmp -s - /etc/init.d/sing-box
    else
        return 1
    fi
}

setup_service() {
    local bin
    bin="$(command -v sing-box)"

    if is_systemd; then
        [ ! -L /etc/systemd/system/sing-box.service ] || { err "sing-box systemd 服务文件是符号链接，已拒绝覆盖。"; return 1; }
        render_singbox_systemd_service "$bin" > /etc/systemd/system/sing-box.service || return 1
        retry 3 2 systemctl daemon-reload || return 1
        service_enable || return 1
        return 0
    elif [ "$OS" = "alpine" ] && command -v rc-service >/dev/null 2>&1; then
        [ ! -L /etc/init.d/sing-box ] || { err "sing-box OpenRC 服务文件是符号链接，已拒绝覆盖。"; return 1; }
        render_singbox_openrc_service "$bin" > /etc/init.d/sing-box || return 1
        chmod +x /etc/init.d/sing-box || return 1
        service_enable || return 1
        return 0
    else
        err "未检测到 systemd/OpenRC，无法创建服务。"
        return 1
    fi
}

prepare_node_layout_for_write() {
    # vpsbox 服务只加载 vpsbox.d；软件包或用户自己的 config.json 不参与节点布局。
    secure_node_config_dir
}

verify_all_node_runtime() {
    local protocol protocols

    service_is_running || return 1
    for protocol in vless ss; do
        protocol_visible_exists "$protocol" || continue
        load_protocol_state "$protocol" || return 1
        if [ "$protocol" = "vless" ]; then
            [ -n "${REALITY_PRIVATE_KEY:-}" ] || return 1
            protocols=tcp
        else
            protocols=both
        fi
        wait_for_port_listener "$PORT" "$protocols" || return 1
    done
}

create_or_rebuild_node() {
    local confirm domain default_name input_name name port password config_id
    local staged_config staged_state
    local existing_port="" existing_protocols="" sibling_ports=""

    require_valid_node_state_if_present || return 1
    if protocol_visible_exists ss; then
        load_protocol_state ss || return 1
        existing_port="$PORT"
        existing_protocols=both
        warn "检测到已有 Shadowsocks 节点。"
        if ! read -r -p "是否覆盖重建 Shadowsocks 节点？(y/N): " confirm; then
            info "输入已结束，已取消。"
            return 1
        fi
        [[ "$confirm" =~ ^[Yy]$ ]] || { info "已取消。"; return 0; }
    fi

    sibling_ports="$(configured_node_ports_csv ss)" || {
        err "无法读取 VLESS Reality 节点端口，未创建 Shadowsocks 节点。"
        return 1
    }

    if ! prompt_node_host domain "请输入节点域名或 IP（留空自动检测公网 IPv4）："; then
        info "输入已结束，已取消。"
        return 1
    fi
    default_name="$(default_name_for_host "$domain")"
    while true; do
        read -r -p "请输入节点名称，留空默认 ${default_name}：" input_name ||
            { info "输入已结束，已取消。"; return 1; }
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
    if ! port="$(choose_node_port "$existing_port" both "$existing_protocols" "$sibling_ports")"; then
        err "节点端口选择失败，未创建 Shadowsocks 节点。"
        return 1
    fi
    info "节点端口：$port"

    cat <<EOF
----------------------------------------
 请确认节点信息
 协议：Shadowsocks
 连接地址：$domain
 连接端口：$port
 节点名称：$name
----------------------------------------
EOF
    if ! confirm_default_yes "确认无误并创建？"; then
        info "已取消，未修改现有节点。"
        return 0
    fi

    # 最终确认前不创建事务、不停止服务，也不刷新防火墙；pending 写入后才允许首次修改。
    if ! begin_node_transaction; then
        err "无法创建受保护的节点事务，未修改 Shadowsocks 节点。"
        return 1
    fi
    if ! install_singbox_for_node_transaction; then
        rollback_node_files_transaction || true
        err "sing-box 安装失败，未创建 Shadowsocks 节点。"
        return 1
    fi
    info "正在自动生成随机强密码..."
    if ! password="$(random_password)" || [ -z "$password" ]; then
        rollback_node_files_transaction || true
        err "随机强密码生成失败，未创建 Shadowsocks 节点。"
        return 1
    fi

    config_id="$(generate_node_config_id)" || {
        rollback_node_files_transaction || true
        err "节点配置标识生成失败，未创建 Shadowsocks 节点。"
        return 1
    }
    staged_config="$NODE_TRANSACTION_STAGE/configs/${SS_CONFIG_PATH##*/}"
    staged_state="$NODE_TRANSACTION_STAGE/states/${SS_STATE_FILE##*/}"
    if ! prepare_node_stage ||
        ! stage_sibling_node_config ss ||
        ! write_config "$port" "$password" "$config_id" "$staged_config" ||
        ! save_state "$domain" "$name" "$port" "$password" "$config_id" "$staged_state" ||
        ! build_staged_uri_files ss "$staged_state" ||
        ! validate_staged_node ss; then
        rollback_node_files_transaction || true
        err "Shadowsocks 配置、状态或链接预生成校验失败，未修改现有节点。"
        return 1
    fi
    if ! mark_node_transaction_mutated ||
        ! firewall_prepare_port_transition "$port" "$port"; then
        rollback_active_node_transaction || true
        err "主机防火墙无法临时放行新节点端口，未创建 Shadowsocks 节点。"
        return 1
    fi
    info "加密方式：$SS_METHOD"
    info "正在写入 Shadowsocks 配置..."
    if ! publish_staged_node ss ||
        ! check_node_config_set ||
        ! setup_service; then
        rollback_active_node_transaction || true
        err "Shadowsocks 配置、状态、链接或服务写入失败，已恢复创建前状态。"
        return 1
    fi
    info "正在启动 sing-box 服务..."
    if ! restart_singbox_cleanly || ! verify_all_node_runtime; then
        rollback_active_node_transaction || true
        err "sing-box 未保持运行或节点端口未完整监听，已恢复创建前状态。"
        return 1
    fi
    if ! firewall_complete_port_transition; then
        rollback_active_node_transaction || true
        err "主机防火墙未能同步节点端口，已恢复创建前状态。"
        return 1
    fi

    if ! commit_node_transaction; then
        rollback_active_node_transaction || true
        err "节点事务提交失败，已尝试恢复创建前状态。"
        return 1
    fi
    info "Shadowsocks 节点创建完成，当前节点链接如下："
    view_node_link || {
        err "节点已创建并运行，但链接显示失败，请稍后使用查看节点链接功能重试。"
        return 1
    }
}

create_vless_reality_node() {
    local confirm domain default_name input_name name port input_sni server_name
    local uuid short_id private_key public_key config_id staged_config staged_state
    local existing_port="" existing_protocols="" reality_check_deferred=0
    local sibling_ports=""
    local -a keypair

    require_valid_node_state_if_present || return 1
    if protocol_visible_exists vless; then
        load_protocol_state vless || return 1
        existing_port="$PORT"
        existing_protocols=tcp
        warn "检测到已有 VLESS Reality 节点。"
        if ! read -r -p "是否覆盖重建 VLESS Reality 节点？(y/N): " confirm; then
            info "输入已结束，已取消。"
            return 1
        fi
        [[ "$confirm" =~ ^[Yy]$ ]] || { info "已取消。"; return 0; }
    fi

    sibling_ports="$(configured_node_ports_csv vless)" || {
        err "无法读取 Shadowsocks 节点端口，未创建 VLESS Reality 节点。"
        return 1
    }

    if ! prompt_node_host domain "请输入节点连接地址（域名或 IP，留空自动检测公网 IPv4）："; then
        info "输入已结束，已取消。"
        return 1
    fi
    default_name="$(default_name_for_host "$domain")"
    default_name="vless-${default_name#ss-}"
    while true; do
        read -r -p "请输入节点名称，留空默认 ${default_name}：" input_name ||
            { info "输入已结束，已取消。"; return 1; }
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
        read -r -p "请输入 Reality 目标域名/SNI（留空默认 ${DEFAULT_REALITY_SERVER_NAME}）：" input_sni ||
            { info "输入已结束，已取消。"; return 1; }
        server_name="$(normalize_host "${input_sni:-$DEFAULT_REALITY_SERVER_NAME}")"
        if ! is_domain_name "$server_name"; then
            err "Reality 目标必须是有效域名，不能使用 IP 地址。"
            continue
        fi
        if command -v openssl >/dev/null 2>&1; then
            info "正在检查 Reality 目标的 DNS 与 TLS 443 可达性..."
            if ! check_reality_server "$server_name"; then
                err "目标域名无法解析或 TLS 443 不可达，请更换。"
                continue
            fi
        else
            reality_check_deferred=1
            info "将在最终确认并补齐依赖后检查 Reality 目标。"
        fi
        break
    done
    if ! port="$(choose_node_port "$existing_port" tcp "$existing_protocols" "$sibling_ports")"; then
        err "节点端口选择失败，未创建 VLESS Reality 节点。"
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
        info "已取消，未修改现有节点。"
        return 0
    fi

    if ! begin_node_transaction; then
        err "无法创建受保护的节点事务，未修改 VLESS Reality 节点。"
        return 1
    fi
    if ! install_singbox_for_node_transaction; then
        rollback_node_files_transaction || true
        err "sing-box 安装失败，未创建 VLESS Reality 节点。"
        return 1
    fi
    if [ "$reality_check_deferred" -eq 1 ]; then
        info "正在检查 Reality 目标的 DNS 与 TLS 443 可达性..."
    fi
    if ! check_reality_server "$server_name"; then
        rollback_node_files_transaction || true
        err "目标域名无法解析或 TLS 443 不可达，未创建 VLESS Reality 节点。"
        return 1
    fi
    uuid="$(sing-box generate uuid 2>/dev/null | tr -d '\r\n')"
    if [[ ! "$uuid" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]]; then
        rollback_node_files_transaction || true
        err "UUID 生成失败，未创建 VLESS Reality 节点。"
        return 1
    fi
    mapfile -t keypair < <(generate_reality_keypair) || true
    if [ "${#keypair[@]}" -ne 2 ]; then
        rollback_node_files_transaction || true
        err "Reality 密钥生成失败，未创建 VLESS Reality 节点。"
        return 1
    fi
    private_key="${keypair[0]}"
    public_key="${keypair[1]}"
    short_id="$(sing-box generate rand 8 --hex 2>/dev/null | tr -d '\r\n')"
    if [[ ! "$short_id" =~ ^[0-9A-Fa-f]{16}$ ]]; then
        rollback_node_files_transaction || true
        err "Reality Short ID 生成失败，未创建 VLESS Reality 节点。"
        return 1
    fi

    config_id="$(generate_node_config_id)" || {
        rollback_node_files_transaction || true
        err "节点配置标识生成失败，未创建 VLESS Reality 节点。"
        return 1
    }
    staged_config="$NODE_TRANSACTION_STAGE/configs/${VLESS_CONFIG_PATH##*/}"
    staged_state="$NODE_TRANSACTION_STAGE/states/${VLESS_STATE_FILE##*/}"
    if ! prepare_node_stage ||
        ! stage_sibling_node_config vless ||
        ! write_vless_reality_config \
            "$port" "$uuid" "$server_name" "$private_key" "$short_id" \
            "$config_id" "$staged_config" ||
        ! save_vless_reality_state \
            "$domain" "$name" "$port" "$uuid" "$server_name" \
            "$private_key" "$public_key" "$short_id" "$config_id" "$staged_state" ||
        ! build_staged_uri_files vless "$staged_state" ||
        ! validate_staged_node vless; then
        rollback_node_files_transaction || true
        err "VLESS Reality 配置、状态或链接预生成校验失败，未修改现有节点。"
        return 1
    fi
    if ! mark_node_transaction_mutated ||
        ! firewall_prepare_port_transition "$port" ""; then
        rollback_active_node_transaction || true
        err "主机防火墙无法临时放行新节点端口，未创建 VLESS Reality 节点。"
        return 1
    fi
    info "正在写入 VLESS Reality 配置..."
    if ! publish_staged_node vless ||
        ! check_node_config_set ||
        ! setup_service; then
        rollback_active_node_transaction || true
        err "VLESS Reality 配置、状态、链接或服务写入失败，已恢复创建前状态。"
        return 1
    fi
    info "正在启动 sing-box 服务..."
    if ! restart_singbox_cleanly || ! verify_all_node_runtime; then
        rollback_active_node_transaction || true
        err "sing-box 未保持运行或节点端口未完整监听，已恢复创建前状态。"
        return 1
    fi
    if ! firewall_complete_port_transition; then
        rollback_active_node_transaction || true
        err "主机防火墙未能同步节点端口，已恢复创建前状态。"
        return 1
    fi

    if ! commit_node_transaction; then
        rollback_active_node_transaction || true
        err "节点事务提交失败，已尝试恢复创建前状态。"
        return 1
    fi
    info "VLESS Reality 节点创建完成，当前节点链接如下："
    view_node_link || {
        err "节点已创建并运行，但链接显示失败，请稍后使用查看节点链接功能重试。"
        return 1
    }
}

view_node_link() {
    local protocol label uri displayed=0

    require_valid_node_state_if_present || return 1
    node_exists || { warn "当前没有已创建的节点。"; return 0; }
    write_uri_files || {
        err "节点链接生成或写入失败。"
        return 1
    }

    for protocol in vless ss; do
        protocol_visible_exists "$protocol" || continue
        label="$(node_protocol_display_name "$protocol")" || return 1
        load_protocol_state "$protocol" || {
            err "$label 节点状态读取失败，无法显示链接。"
            return 1
        }
        uri="$(generate_link_from_loaded_state)" || {
            err "$label 节点链接生成失败。"
            return 1
        }
        if [ "$protocol" = "vless" ]; then
            cat <<EOF
========================================
 VLESS Reality 节点
========================================
 节点地址：${DOMAIN}:${PORT}
 Reality SNI：${REALITY_SERVER_NAME}
 流控：${FLOW}
----------------------------------------
 链接：
 $uri
========================================
EOF
        else
            cat <<EOF
========================================
 Shadowsocks 节点
========================================
 节点地址：${DOMAIN}:${PORT}
 加密方式：${METHOD}
 密码：${PASSWORD}
----------------------------------------
 链接：
 $uri
========================================
EOF
        fi
        displayed=1
    done
    [ "$displayed" -eq 1 ]
}

delete_node_protocol() {
    local protocol="$1" label config state uri node_port node_protocols
    local confirm port_status

    case "$protocol" in
        vless) label="VLESS Reality"; node_protocols=tcp ;;
        ss) label="Shadowsocks"; node_protocols=both ;;
        *) return 2 ;;
    esac
    require_valid_node_state_if_present || return 1
    if ! protocol_visible_exists "$protocol"; then
        warn "当前没有已创建的 $label 节点。"
        return 0
    fi
    load_protocol_state "$protocol" || {
        err "$label 节点状态不安全或内容无效，已拒绝删除。"
        return 1
    }
    node_port="$PORT"
    if ! read -r -p "确认删除 $label 节点？(y/N): " confirm; then
        info "输入已结束，已取消。"
        return 1
    fi
    [[ "$confirm" =~ ^[Yy]$ ]] || { info "已取消。"; return 0; }

    if ! begin_node_transaction; then
        err "备份当前节点失败，已取消删除。"
        return 1
    fi
    if ! mark_node_transaction_mutated ||
        ! firewall_prepare_port_transition "" ""; then
        rollback_active_node_transaction || true
        err "主机防火墙无法开始节点删除事务，已取消删除。"
        return 1
    fi

    service_stop 2>/dev/null ||
        warn "服务管理器未能正常停止 sing-box，将继续检查 vpsbox 配置对应的进程。"
    if ! stop_singbox_config_processes; then
        rollback_active_node_transaction || true
        err "残留 sing-box 进程无法停止，已保留节点配置。"
        return 1
    fi
    sleep 1
    if service_manager_is_active || [ -n "$(singbox_config_pids)" ]; then
        rollback_active_node_transaction || true
        err "sing-box 服务仍在运行，已保留节点配置。"
        return 1
    fi
    if port_in_use_for_protocols "$node_port" "$node_protocols"; then
        rollback_active_node_transaction || true
        err "节点端口 $node_port 仍被其他进程监听，已保留节点配置。"
        return 1
    else
        port_status=$?
        if [ "$port_status" -ne 1 ]; then
            rollback_active_node_transaction || true
            err "无法确认节点端口 $node_port 是否已释放，已保留节点配置。"
            return 1
        fi
    fi

    config="$(node_config_path "$protocol")" || return 1
    state="$(node_state_path "$protocol")" || return 1
    uri="$(node_uri_path "$protocol")" || return 1
    rm -f -- "$config" "$state" "$uri" || {
        rollback_active_node_transaction || true
        err "$label 节点文件删除失败，已尝试恢复。"
        return 1
    }
    write_uri_files || {
        rollback_active_node_transaction || true
        err "剩余节点链接更新失败，已尝试恢复。"
        return 1
    }

    if node_exists; then
        if ! check_node_config_set ||
            ! setup_service ||
            ! restart_singbox_cleanly ||
            ! verify_all_node_runtime; then
            rollback_active_node_transaction || true
            err "剩余节点恢复运行失败，已恢复删除前状态。"
            return 1
        fi
    else
        if ! service_disable || service_is_enabled; then
            rollback_active_node_transaction || true
            err "无法禁用 sing-box 开机启动，已恢复删除前状态。"
            return 1
        fi
        [ "$NODE_CONFIG_DIR" = "$CONFIG_DIR/vpsbox.d" ] &&
            rmdir "$NODE_CONFIG_DIR" 2>/dev/null || true
    fi
    if ! firewall_complete_port_transition; then
        rollback_active_node_transaction || true
        err "主机防火墙端口同步失败，已恢复删除前状态。"
        return 1
    fi

    if ! commit_node_transaction; then
        rollback_active_node_transaction || true
        err "节点删除事务提交失败，已尝试恢复删除前状态。"
        return 1
    fi
    if node_exists; then
        info "$label 节点已删除，其他节点继续运行。"
    else
        info "$label 节点已删除，sing-box 服务已停止并禁用开机启动。"
    fi
}

delete_vless_reality_node() {
    delete_node_protocol vless
}

delete_node() {
    delete_node_protocol ss
}

singbox_binary_version_at() {
    local binary="$1"

    [ -x "$binary" ] && [ ! -L "$binary" ] || return 1
    "$binary" version 2>/dev/null | head -n1 | sed 's/^sing-box version //'
}

restore_singbox_binary_atomically() {
    local backup_binary="$1" binary_path="$2" old_version="$3"
    local parent tmp restored_version

    [ -f "$backup_binary" ] && [ ! -L "$backup_binary" ] || return 1
    parent="$(dirname "$binary_path")"
    [ -d "$parent" ] && [ ! -L "$parent" ] || return 1
    tmp="$(mktemp "$parent/.sing-box-vpsbox-restore.XXXXXX")" || return 1
    if ! cp -a -- "$backup_binary" "$tmp"; then
        rm -f -- "$tmp"
        return 1
    fi
    restored_version="$(singbox_binary_version_at "$tmp" 2>/dev/null || true)"
    if [ -n "$old_version" ] && [ "$restored_version" != "$old_version" ]; then
        rm -f -- "$tmp"
        return 1
    fi
    if ! mv -f -- "$tmp" "$binary_path"; then
        rm -f -- "$tmp"
        return 1
    fi
}

singbox_update_transaction_dir_valid() {
    [ "${1:-}" = "$SINGBOX_UPDATE_TRANSACTION_DIR" ] &&
        [ "$SINGBOX_UPDATE_TRANSACTION_DIR" = "$VPSBOX_STATE_DIR/singbox-update" ]
}

remove_singbox_update_transaction_dir() {
    local dir="${1:-$SINGBOX_UPDATE_TRANSACTION_DIR}"

    singbox_update_transaction_dir_valid "$dir" || return 1
    [ ! -L "$dir" ] || return 1
    rm -rf -- "$dir"
}

singbox_update_state_value() {
    local key="$1"

    [ -f "$SINGBOX_UPDATE_TRANSACTION_STATE" ] &&
        [ ! -L "$SINGBOX_UPDATE_TRANSACTION_STATE" ] || return 1
    awk -F= -v key="$key" '$1 == key { print substr($0, index($0, "=") + 1); found=1; exit }
        END { if (!found) exit 1 }' "$SINGBOX_UPDATE_TRANSACTION_STATE"
}

singbox_update_transaction_valid() {
    local binary_path old_version was_enabled was_active package_name
    local binary_hash package_hash current_hash mode

    singbox_update_transaction_dir_valid "$SINGBOX_UPDATE_TRANSACTION_DIR" || return 1
    [ -d "$SINGBOX_UPDATE_TRANSACTION_DIR" ] &&
        [ ! -L "$SINGBOX_UPDATE_TRANSACTION_DIR" ] || return 1
    [ -f "$SINGBOX_UPDATE_TRANSACTION_DIR/pending" ] &&
        [ ! -L "$SINGBOX_UPDATE_TRANSACTION_DIR/pending" ] || return 1
    [ -f "$SINGBOX_UPDATE_TRANSACTION_DIR/old-binary" ] &&
        [ ! -L "$SINGBOX_UPDATE_TRANSACTION_DIR/old-binary" ] || return 1
    mode="$(stat -c '%a' "$SINGBOX_UPDATE_TRANSACTION_DIR" 2>/dev/null || true)"
    [ "$mode" = "700" ] || return 1
    mode="$(stat -c '%a' "$SINGBOX_UPDATE_TRANSACTION_STATE" 2>/dev/null || true)"
    [ "$mode" = "600" ] || return 1
    if [ "${VPSBOX_TEST_MODE:-0}" != "1" ]; then
        [ "$(stat -c '%U:%G' "$SINGBOX_UPDATE_TRANSACTION_DIR" "$SINGBOX_UPDATE_TRANSACTION_STATE" \
            "$SINGBOX_UPDATE_TRANSACTION_DIR/pending" "$SINGBOX_UPDATE_TRANSACTION_DIR/old-binary" \
            2>/dev/null | sort -u)" = "root:root" ] || return 1
    fi
    mode="$(stat -c '%a' "$SINGBOX_UPDATE_TRANSACTION_DIR/pending" 2>/dev/null || true)"
    [ "$mode" = "600" ] || return 1
    mode="$(stat -c '%a' "$SINGBOX_UPDATE_TRANSACTION_DIR/old-binary" 2>/dev/null || true)"
    [ "$mode" = "755" ] || return 1

    [ "$(singbox_update_state_value version 2>/dev/null || true)" = "1" ] || return 1
    binary_path="$(singbox_update_state_value binary_path 2>/dev/null || true)"
    old_version="$(singbox_update_state_value old_version 2>/dev/null || true)"
    was_enabled="$(singbox_update_state_value was_enabled 2>/dev/null || true)"
    was_active="$(singbox_update_state_value was_active 2>/dev/null || true)"
    package_name="$(singbox_update_state_value package_name 2>/dev/null || true)"
    binary_hash="$(singbox_update_state_value binary_sha256 2>/dev/null || true)"
    package_hash="$(singbox_update_state_value package_sha256 2>/dev/null || true)"
    if [ "${VPSBOX_TEST_MODE:-0}" = "1" ]; then
        [[ "$binary_path" == /tmp/vpsbox-test.*/sing-box ||
            "$binary_path" == /tmp/vpsbox-test.*/*/sing-box ]] || return 1
    else
        case "$binary_path" in
            /usr/bin/sing-box|/usr/local/bin/sing-box) ;;
            *) return 1 ;;
        esac
    fi
    [[ "$old_version" =~ ^[0-9]+([.][0-9]+){2}$ ]] || return 1
    [[ "$was_enabled" =~ ^[01]$ && "$was_active" =~ ^[01]$ ]] || return 1
    [[ "$binary_hash" =~ ^[0-9a-f]{64}$ ]] || return 1
    current_hash="$(sha256sum "$SINGBOX_UPDATE_TRANSACTION_DIR/old-binary" 2>/dev/null | awk '{print $1}')"
    [ "$current_hash" = "$binary_hash" ] || return 1
    [ "$(singbox_binary_version_at "$SINGBOX_UPDATE_TRANSACTION_DIR/old-binary" 2>/dev/null || true)" = "$old_version" ] ||
        return 1
    case "$package_name" in
        rollback-package.deb|rollback-package.apk|rollback-package.rpm)
            [ -f "$SINGBOX_UPDATE_TRANSACTION_DIR/$package_name" ] &&
                [ ! -L "$SINGBOX_UPDATE_TRANSACTION_DIR/$package_name" ] || return 1
            if [ "${VPSBOX_TEST_MODE:-0}" != "1" ]; then
                [ "$(stat -c '%U:%G %a' "$SINGBOX_UPDATE_TRANSACTION_DIR/$package_name" 2>/dev/null || true)" = "root:root 600" ] ||
                    return 1
            else
                [ "$(stat -c '%a' "$SINGBOX_UPDATE_TRANSACTION_DIR/$package_name" 2>/dev/null || true)" = "600" ] ||
                    return 1
            fi
            [[ "$package_hash" =~ ^[0-9a-f]{64}$ ]] || return 1
            current_hash="$(sha256sum "$SINGBOX_UPDATE_TRANSACTION_DIR/$package_name" 2>/dev/null | awk '{print $1}')"
            [ "$current_hash" = "$package_hash" ]
            ;;
        none)
            [ "$package_hash" = "none" ]
            ;;
        *) return 1 ;;
    esac
}

persist_singbox_update_transaction() {
    local binary_path="$1" backup_binary="$2" rollback_package="$3" old_version="$4"
    local was_enabled="$5" was_active="$6" package_name package_hash="none"
    local binary_hash tmp_dir

    command -v sha256sum >/dev/null 2>&1 || return 1
    [ ! -L "$VPSBOX_STATE_DIR" ] && [ ! -L "$SINGBOX_UPDATE_TRANSACTION_DIR" ] || return 1
    mkdir -p "$VPSBOX_STATE_DIR" || return 1
    if [ "${VPSBOX_TEST_MODE:-0}" != "1" ]; then
        chown root:root "$VPSBOX_STATE_DIR" || return 1
    fi
    chmod 700 "$VPSBOX_STATE_DIR" || return 1
    if [ -e "$SINGBOX_UPDATE_TRANSACTION_DIR" ]; then
        [ ! -e "$SINGBOX_UPDATE_TRANSACTION_DIR/pending" ] || return 1
        remove_singbox_update_transaction_dir || return 1
    fi
    tmp_dir="$(mktemp -d "$VPSBOX_STATE_DIR/.singbox-update.XXXXXX")" || return 1
    chmod 700 "$tmp_dir" || { rm -rf -- "$tmp_dir"; return 1; }
    if ! cp -a -- "$backup_binary" "$tmp_dir/old-binary" ||
        ! chmod 755 "$tmp_dir/old-binary"; then
        rm -rf -- "$tmp_dir"
        return 1
    fi
    binary_hash="$(sha256sum "$tmp_dir/old-binary" | awk '{print $1}')"
    if [ -n "$rollback_package" ]; then
        case "$rollback_package" in
            *.deb) package_name="rollback-package.deb" ;;
            *.apk) package_name="rollback-package.apk" ;;
            *.rpm) package_name="rollback-package.rpm" ;;
            *) rm -rf -- "$tmp_dir"; return 1 ;;
        esac
        if ! cp -a -- "$rollback_package" "$tmp_dir/$package_name" ||
            ! chmod 600 "$tmp_dir/$package_name"; then
            rm -rf -- "$tmp_dir"
            return 1
        fi
        package_hash="$(sha256sum "$tmp_dir/$package_name" | awk '{print $1}')"
    else
        package_name=none
    fi
    if ! {
        printf 'version=1\n'
        printf 'binary_path=%s\n' "$binary_path"
        printf 'old_version=%s\n' "$old_version"
        printf 'was_enabled=%s\n' "$was_enabled"
        printf 'was_active=%s\n' "$was_active"
        printf 'package_name=%s\n' "$package_name"
        printf 'binary_sha256=%s\n' "$binary_hash"
        printf 'package_sha256=%s\n' "$package_hash"
    } > "$tmp_dir/state" ||
        ! chmod 600 "$tmp_dir/state" ||
        ! : > "$tmp_dir/pending" ||
        ! chmod 600 "$tmp_dir/pending" ||
        ! mv -- "$tmp_dir" "$SINGBOX_UPDATE_TRANSACTION_DIR"; then
        rm -rf -- "$tmp_dir"
        return 1
    fi
    if ! sync_node_transaction_store || ! singbox_update_transaction_valid; then
        remove_singbox_update_transaction_dir || true
        return 1
    fi
}

restore_singbox_update_backup() {
    local binary_path="$1" backup_binary="$2" backup_dir="$3"
    local was_enabled="$4" was_active="$5"
    local rollback_package="${6:-}" old_version="${7:-}"
    local failed=0 package_restored=0 binary_ready=0 service_ready=1

    if ! service_stop 2>/dev/null && service_manager_is_active; then
        err "更新后的 sing-box 服务无法停止，已拒绝在运行中覆盖二进制。"
        failed=1
    fi
    if ! stop_singbox_config_processes 2>/dev/null; then
        err "更新后的 sing-box 进程无法停止，已拒绝在运行中覆盖二进制。"
        failed=1
    fi
    if [ "$failed" -ne 0 ]; then
        warn "sing-box 更新备份已保留：$backup_dir"
        return 1
    fi
    if [ -n "$rollback_package" ] && [ -n "$old_version" ]; then
        if install_singbox_package_file "$rollback_package" &&
            [ "$(singbox_version)" = "$old_version" ]; then
            package_restored=1
            binary_ready=1
        else
            err "旧 sing-box 软件包恢复失败，正在尝试恢复二进制副本。"
            failed=1
        fi
    fi
    if [ "$package_restored" -eq 0 ]; then
        if restore_singbox_binary_atomically "$backup_binary" "$binary_path" "$old_version"; then
            binary_ready=1
        else
            err "旧 sing-box 二进制恢复失败：$backup_binary"
            failed=1
        fi
    fi
    hash -r
    if [ "$binary_ready" -eq 1 ] && node_exists && ! setup_service; then
        err "旧 sing-box 服务配置恢复失败。"
        failed=1
        service_ready=0
    fi
    if [ "$binary_ready" -eq 1 ] && [ "$service_ready" -eq 1 ] &&
        ! restore_singbox_service_state "$was_enabled" "$was_active"; then
        err "旧 sing-box 二进制已恢复，但原服务状态恢复失败。"
        failed=1
    fi

    if [ "$failed" -ne 0 ]; then
        # 更新失败时保留本地二进制备份，避免包管理器处于异常状态后失去最后恢复副本。
        warn "sing-box 更新备份已保留：$backup_dir"
        return 1
    fi
    return 0
}

recover_pending_singbox_update() {
    local binary_path old_version was_enabled was_active package_name rollback_package=""

    [ -e "$SINGBOX_UPDATE_TRANSACTION_DIR" ] || return 0
    [ -d "$SINGBOX_UPDATE_TRANSACTION_DIR" ] &&
        [ ! -L "$SINGBOX_UPDATE_TRANSACTION_DIR" ] || {
            err "sing-box 更新事务路径不安全，已拒绝自动处理。"
            return 1
        }
    if [ ! -e "$SINGBOX_UPDATE_TRANSACTION_DIR/pending" ]; then
        remove_singbox_update_transaction_dir || return 1
        return 0
    fi
    singbox_update_transaction_valid || {
        err "sing-box 更新恢复记录未通过完整性检查，已保留：$SINGBOX_UPDATE_TRANSACTION_DIR"
        return 1
    }
    binary_path="$(singbox_update_state_value binary_path)"
    old_version="$(singbox_update_state_value old_version)"
    was_enabled="$(singbox_update_state_value was_enabled)"
    was_active="$(singbox_update_state_value was_active)"
    package_name="$(singbox_update_state_value package_name)"
    [ "$package_name" = "none" ] ||
        rollback_package="$SINGBOX_UPDATE_TRANSACTION_DIR/$package_name"

    warn "检测到上次未完成的 sing-box 更新，正在恢复旧版本。"
    if ! restore_singbox_update_backup \
        "$binary_path" "$SINGBOX_UPDATE_TRANSACTION_DIR/old-binary" \
        "$SINGBOX_UPDATE_TRANSACTION_DIR" "$was_enabled" "$was_active" \
        "$rollback_package" "$old_version"; then
        err "sing-box 旧版本未能完整恢复，事务记录已保留：$SINGBOX_UPDATE_TRANSACTION_DIR"
        return 1
    fi
    [ "$(singbox_version)" = "$old_version" ] || {
        err "sing-box 恢复后的版本不符，事务记录已保留：$SINGBOX_UPDATE_TRANSACTION_DIR"
        return 1
    }
    remove_singbox_update_transaction_dir || return 1
    info "上次中断的 sing-box 更新已恢复到 v$old_version。"
}

begin_singbox_update_transaction() {
    ACTIVE_SINGBOX_UPDATE_BINARY="$1"
    ACTIVE_SINGBOX_UPDATE_BACKUP="$2"
    ACTIVE_SINGBOX_UPDATE_DIR="$3"
    ACTIVE_SINGBOX_UPDATE_PACKAGE="${6:-}"
    ACTIVE_SINGBOX_UPDATE_OLD_VERSION="${7:-}"
    ACTIVE_SINGBOX_UPDATE_WAS_ENABLED="$4"
    ACTIVE_SINGBOX_UPDATE_WAS_ACTIVE="$5"
    ACTIVE_SINGBOX_UPDATE_MUTATED=0
}

cancel_unmodified_singbox_update_transaction() {
    local backup_dir="${ACTIVE_SINGBOX_UPDATE_DIR:-}"

    ACTIVE_SINGBOX_UPDATE_BINARY=""
    ACTIVE_SINGBOX_UPDATE_BACKUP=""
    ACTIVE_SINGBOX_UPDATE_DIR=""
    ACTIVE_SINGBOX_UPDATE_PACKAGE=""
    ACTIVE_SINGBOX_UPDATE_OLD_VERSION=""
    ACTIVE_SINGBOX_UPDATE_WAS_ENABLED=0
    ACTIVE_SINGBOX_UPDATE_WAS_ACTIVE=0
    ACTIVE_SINGBOX_UPDATE_MUTATED=0
    if { [[ "$backup_dir" == /tmp/vpsbox-sing-box-update.* ]] ||
        singbox_update_transaction_dir_valid "$backup_dir" ||
        [ "${VPSBOX_TEST_MODE:-0}" = "1" ]; } &&
        [ -d "$backup_dir" ] && [ ! -L "$backup_dir" ]; then
        if singbox_update_transaction_dir_valid "$backup_dir"; then
            remove_singbox_update_transaction_dir
        else
            rm -rf -- "$backup_dir"
        fi
    fi
}

rollback_active_singbox_update() {
    local binary_path backup_binary backup_dir rollback_package old_version
    local was_enabled was_active mutated result=0

    [ "${ACTIVE_SINGBOX_UPDATE_ROLLING_BACK:-0}" = "0" ] || return 0
    backup_dir="${ACTIVE_SINGBOX_UPDATE_DIR:-}"
    [ -n "$backup_dir" ] || return 0
    binary_path="$ACTIVE_SINGBOX_UPDATE_BINARY"
    backup_binary="$ACTIVE_SINGBOX_UPDATE_BACKUP"
    rollback_package="$ACTIVE_SINGBOX_UPDATE_PACKAGE"
    old_version="$ACTIVE_SINGBOX_UPDATE_OLD_VERSION"
    was_enabled="$ACTIVE_SINGBOX_UPDATE_WAS_ENABLED"
    was_active="$ACTIVE_SINGBOX_UPDATE_WAS_ACTIVE"
    mutated="$ACTIVE_SINGBOX_UPDATE_MUTATED"
    ACTIVE_SINGBOX_UPDATE_ROLLING_BACK=1

    # 先清空全局事务，防止恢复命令再次收到信号时重复进入同一回滚。
    ACTIVE_SINGBOX_UPDATE_BINARY=""
    ACTIVE_SINGBOX_UPDATE_BACKUP=""
    ACTIVE_SINGBOX_UPDATE_DIR=""
    ACTIVE_SINGBOX_UPDATE_PACKAGE=""
    ACTIVE_SINGBOX_UPDATE_OLD_VERSION=""
    ACTIVE_SINGBOX_UPDATE_WAS_ENABLED=0
    ACTIVE_SINGBOX_UPDATE_WAS_ACTIVE=0
    ACTIVE_SINGBOX_UPDATE_MUTATED=0
    if [ "$mutated" = "1" ]; then
        restore_singbox_update_backup \
            "$binary_path" "$backup_binary" "$backup_dir" "$was_enabled" "$was_active" \
            "$rollback_package" "$old_version" || result=1
        if [ "$result" -eq 0 ] && singbox_update_transaction_dir_valid "$backup_dir"; then
            remove_singbox_update_transaction_dir || result=1
        fi
    elif { [[ "$backup_dir" == /tmp/vpsbox-sing-box-update.* ]] ||
        singbox_update_transaction_dir_valid "$backup_dir" ||
        [ "${VPSBOX_TEST_MODE:-0}" = "1" ]; } &&
        [ -d "$backup_dir" ] && [ ! -L "$backup_dir" ]; then
        if singbox_update_transaction_dir_valid "$backup_dir"; then
            remove_singbox_update_transaction_dir || result=1
        else
            rm -rf -- "$backup_dir" || result=1
        fi
    else
        result=1
    fi
    ACTIVE_SINGBOX_UPDATE_ROLLING_BACK=0
    return "$result"
}

commit_singbox_update_transaction() {
    local backup_dir="${ACTIVE_SINGBOX_UPDATE_DIR:-}"

    ACTIVE_SINGBOX_UPDATE_BINARY=""
    ACTIVE_SINGBOX_UPDATE_BACKUP=""
    ACTIVE_SINGBOX_UPDATE_DIR=""
    ACTIVE_SINGBOX_UPDATE_PACKAGE=""
    ACTIVE_SINGBOX_UPDATE_OLD_VERSION=""
    ACTIVE_SINGBOX_UPDATE_WAS_ENABLED=0
    ACTIVE_SINGBOX_UPDATE_WAS_ACTIVE=0
    ACTIVE_SINGBOX_UPDATE_MUTATED=0
    { [[ "$backup_dir" == /tmp/vpsbox-sing-box-update.* ]] ||
        singbox_update_transaction_dir_valid "$backup_dir" ||
        [ "${VPSBOX_TEST_MODE:-0}" = "1" ]; } &&
        [ -d "$backup_dir" ] && [ ! -L "$backup_dir" ] || return 1
    if singbox_update_transaction_dir_valid "$backup_dir"; then
        remove_singbox_update_transaction_dir
    else
        rm -rf -- "$backup_dir"
    fi
}

update_singbox() {
    local binary_path backup_dir backup_binary rollback_package old_version
    local relation new_version
    local was_active=0 was_enabled=0 had_nodes=0

    if ! singbox_installed; then
        warn "当前未安装 sing-box，已取消更新。"
        info "如需安装 sing-box，请先创建节点或启动服务。"
        return 0
    fi
    if node_artifacts_present; then
        require_valid_node_state_if_present || {
            err "节点配置完整性未通过，已拒绝更新 sing-box。"
            return 1
        }
        node_exists && check_node_config_set || {
            err "节点配置未通过当前 sing-box 检查，已拒绝更新。"
            return 1
        }
        had_nodes=1
    fi

    binary_path="$(command -v sing-box)"
    old_version="$(singbox_version)"
    [[ "$old_version" =~ ^[0-9]+([.][0-9]+){2}$ ]] || { err "无法识别当前 sing-box 版本，已取消更新。"; return 1; }
    relation="$(version_relation "$SINGBOX_RELEASE_VERSION" "$old_version")" || {
        err "无法比较 sing-box 版本，已取消更新。"
        return 1
    }
    case "$relation" in
        same)
            info "sing-box 当前已是受管版本 v$SINGBOX_RELEASE_VERSION，无需更新。"
            return 0
            ;;
        older)
            warn "当前 sing-box v$old_version 高于受管版本 v$SINGBOX_RELEASE_VERSION，已拒绝隐式降级。"
            return 0
            ;;
        newer) ;;
    esac
    if ! singbox_binary_is_package_managed "$binary_path"; then
        err "当前 sing-box 不是由系统 sing-box 软件包管理，已拒绝自动更新。"
        info "请先用原安装方式更新或卸载，再由 vpsbox 安装受管版本。"
        return 1
    fi
    backup_dir="$(mktemp -d /tmp/vpsbox-sing-box-update.XXXXXX)" || return 1
    backup_binary="$backup_dir/sing-box"
    cp -a "$binary_path" "$backup_binary" || { rm -rf "$backup_dir"; err "备份当前 sing-box 二进制失败，已取消更新。"; return 1; }

    if service_is_running; then
        was_active=1
    fi
    if service_is_enabled; then
        was_enabled=1
    fi
    begin_singbox_update_transaction \
        "$binary_path" "$backup_binary" "$backup_dir" "$was_enabled" "$was_active"

    if ! install_deps; then
        cancel_unmodified_singbox_update_transaction
        err "更新依赖准备失败；sing-box 二进制和服务状态均未修改。"
        return 1
    fi
    rollback_package="$(prepare_singbox_rollback_package "$old_version" "$backup_dir")" || {
        cancel_unmodified_singbox_update_transaction
        err "无法下载并校验旧版 sing-box 回滚包，已取消更新。"
        return 1
    }
    ACTIVE_SINGBOX_UPDATE_PACKAGE="$rollback_package"
    ACTIVE_SINGBOX_UPDATE_OLD_VERSION="$old_version"
    if ! persist_singbox_update_transaction \
        "$binary_path" "$backup_binary" "$rollback_package" "$old_version" \
        "$was_enabled" "$was_active"; then
        cancel_unmodified_singbox_update_transaction
        err "无法持久化 sing-box 更新回滚记录，已取消更新。"
        return 1
    fi
    rm -rf -- "$backup_dir"
    backup_dir="$SINGBOX_UPDATE_TRANSACTION_DIR"
    backup_binary="$backup_dir/old-binary"
    rollback_package="$backup_dir/$(singbox_update_state_value package_name)"
    ACTIVE_SINGBOX_UPDATE_DIR="$backup_dir"
    ACTIVE_SINGBOX_UPDATE_BACKUP="$backup_binary"
    ACTIVE_SINGBOX_UPDATE_PACKAGE="$rollback_package"
    info "正在更新 sing-box..."
    ACTIVE_SINGBOX_UPDATE_MUTATED=1
    if ! run_singbox_installer; then
        err "sing-box 安装过程失败，正在恢复旧二进制和原服务状态。"
        rollback_active_singbox_update || true
        return 1
    fi

    new_version="$(singbox_version)"
    if [ "$new_version" != "$SINGBOX_RELEASE_VERSION" ]; then
        err "安装后的 sing-box 版本异常（当前：$new_version），正在恢复旧版本。"
        rollback_active_singbox_update || true
        return 1
    fi

    if [ "$had_nodes" -eq 1 ]; then
        if ! check_node_config_set; then
            err "当前节点配置未通过新版 sing-box 检查，正在恢复旧二进制。"
            rollback_active_singbox_update || true
            return 1
        fi
        if ! setup_service || ! restore_singbox_service_state "$was_enabled" "$was_active"; then
            err "新版 sing-box 未能恢复原服务状态，正在恢复旧二进制。"
            rollback_active_singbox_update || true
            return 1
        fi
    elif ! restore_singbox_service_state "$was_enabled" "$was_active"; then
        err "新版 sing-box 未能恢复原服务状态，正在恢复旧二进制。"
        rollback_active_singbox_update || true
        return 1
    fi

    commit_singbox_update_transaction || {
        err "sing-box 已更新，但临时备份清理失败：$backup_dir"
        return 1
    }
    info "更新完成：$(singbox_version)"
}

restore_previous_vpsbox() {
    local backup="$1"
    local tmp

    [ -f "$backup" ] && [ ! -L "$backup" ] || {
        err "未找到可用的旧版备份：$backup"
        return 1
    }
    if ! bash -n "$backup" >/dev/null 2>&1 ||
        ! vpsbox_script_identity_valid "$backup"; then
        err "旧版备份未通过语法或项目身份检查：$backup"
        return 1
    fi
    tmp="$(mktemp "$(dirname "$CMD_PATH")/.vpsbox-restore.XXXXXX")" || return 1
    if ! cp -a -- "$backup" "$tmp" ||
        ! chmod 755 "$tmp" ||
        ! mv -f -- "$tmp" "$CMD_PATH"; then
        rm -f -- "$tmp"
        err "旧版 vpsbox 恢复失败，备份仍保留在：$backup"
        return 1
    fi
    install_command_alias || return 1
    info "已从 $backup 恢复旧版 vpsbox。"
}

vpsbox_update_ready_path_valid() {
    local ready="$1" dir

    [ -n "$ready" ] || return 1
    dir="${ready%/ready}"
    [ "$ready" = "$dir/ready" ] || return 1
    [[ "$dir" == "$RUNTIME_DIR"/update-startup.* ]] || return 1
    [ -d "$dir" ] && [ ! -L "$dir" ] && [ ! -L "$ready" ]
}

mark_vpsbox_update_ready() {
    local ready="$1" dir tmp

    vpsbox_update_ready_path_valid "$ready" || return 1
    dir="${ready%/ready}"
    tmp="$(mktemp "$dir/.ready.XXXXXX")" || return 1
    if ! printf '%s\n' "$$" > "$tmp" ||
        ! chmod 600 "$tmp" ||
        ! mv -f -- "$tmp" "$ready"; then
        rm -f -- "$tmp"
        return 1
    fi
}

start_vpsbox_update_watchdog() {
    local backup="$1" dir ready owner_pid owner_start

    # v1.0.22 起由旧进程先启动独立 watchdog，再 exec 新脚本。这样即使候选脚本
    # 在解析完毕后、进入 vpsbox_main 之前顶层退出，也能依据 PID 启动时间恢复 .previous。
    [ "$backup" = "${CMD_PATH}.previous" ] || return 1
    if [ ! -f "$backup" ] || [ -L "$backup" ] ||
        ! bash -n "$backup" >/dev/null 2>&1 ||
        ! vpsbox_script_identity_valid "$backup"; then
        return 1
    fi
    [ -d "$RUNTIME_DIR" ] && [ ! -L "$RUNTIME_DIR" ] || return 1
    dir="$(mktemp -d "$RUNTIME_DIR/update-startup.XXXXXX")" || return 1
    chmod 700 "$dir" || { rm -rf -- "$dir"; return 1; }
    ready="$dir/ready"
    owner_pid="$$"
    owner_start="$(process_start_ticks "$owner_pid" 2>/dev/null || true)"
    [[ "$owner_start" =~ ^[0-9]+$ ]] || { rm -rf -- "$dir"; return 1; }

    (
        local elapsed=0 current_start i

        trap - EXIT HUP INT TERM QUIT
        while [ "$elapsed" -lt "$VPSBOX_UPDATE_STARTUP_TIMEOUT" ]; do
            if [ -f "$ready" ] && [ ! -L "$ready" ]; then
                rm -rf -- "$dir"
                exit 0
            fi
            current_start="$(process_start_ticks "$owner_pid" 2>/dev/null || true)"
            [ "$current_start" = "$owner_start" ] || break
            sleep 1
            elapsed=$((elapsed + 1))
        done

        if [ -f "$ready" ] && [ ! -L "$ready" ]; then
            rm -rf -- "$dir"
            exit 0
        fi
        current_start="$(process_start_ticks "$owner_pid" 2>/dev/null || true)"
        if [ "$current_start" = "$owner_start" ]; then
            kill -TERM "$owner_pid" 2>/dev/null || true
            for i in 1 2 3 4 5; do
                sleep 1
                current_start="$(process_start_ticks "$owner_pid" 2>/dev/null || true)"
                [ "$current_start" = "$owner_start" ] || break
            done
            [ "$current_start" != "$owner_start" ] ||
                kill -KILL "$owner_pid" 2>/dev/null || true
        fi
        if [ -f "$ready" ] && [ ! -L "$ready" ]; then
            rm -rf -- "$dir"
            exit 0
        fi
        if restore_previous_vpsbox "$backup"; then
            if [ -w /dev/tty ]; then
                printf '\n[WARN] 新版 vpsbox 未完成启动，已自动恢复旧版。\n' >/dev/tty 2>/dev/null || true
            fi
            rm -rf -- "$dir"
        else
            printf '%s\n' "restore_failed=1" > "$dir/restore-failed" 2>/dev/null || true
            if [ -w /dev/tty ]; then
                printf '\n[ERR] 新版 vpsbox 启动失败，且旧版自动恢复失败：%s\n' "$backup" >/dev/tty 2>/dev/null || true
            fi
        fi
    ) 200>&- </dev/null >>"$dir/watchdog.log" 2>&1 &
    VPSBOX_UPDATE_WATCHDOG_PID=$!
    VPSBOX_UPDATE_WATCHDOG_DIR="$dir"
}

rollback_pending_vpsbox_update() {
    local backup="${PENDING_VPSBOX_UPDATE_BACKUP:-}"
    local ready="${PENDING_VPSBOX_UPDATE_READY_FILE:-}"

    [ -n "$backup$ready" ] || return 0
    [ "${VPSBOX_UPDATE_STARTUP_CONFIRMED:-0}" != "1" ] || return 0
    PENDING_VPSBOX_UPDATE_BACKUP=""
    PENDING_VPSBOX_UPDATE_READY_FILE=""
    unset VPSBOX_UPDATE_BACKUP || true
    unset VPSBOX_UPDATE_READY_FILE || true

    # 兼容旧版本遗留的 .previous：旧备份本身不能证明本次启动来自更新，
    # 因此没有一次性更新握手变量时绝不自动回退，避免普通启动误用陈旧备份。
    [ "$backup" = "${CMD_PATH}.previous" ] || {
        err "拒绝使用非预期的 vpsbox 更新备份路径：$backup"
        return 1
    }
    vpsbox_update_ready_path_valid "$ready" || {
        err "拒绝使用无效的 vpsbox 更新握手路径：$ready"
        return 1
    }
    err "新版 vpsbox 未完成首次界面启动，正在恢复旧版脚本。"
    if restore_previous_vpsbox "$backup"; then
        mark_vpsbox_update_ready "$ready" || true
        return 0
    fi
    return 1
}

confirm_pending_vpsbox_update() {
    local ready="${PENDING_VPSBOX_UPDATE_READY_FILE:-}"

    [ -n "${PENDING_VPSBOX_UPDATE_BACKUP:-}$ready" ] || return 0
    if ! mark_vpsbox_update_ready "$ready"; then
        err "无法确认新版 vpsbox 启动状态，已触发安全回滚。"
        return 1
    fi
    VPSBOX_UPDATE_STARTUP_CONFIRMED=1
    PENDING_VPSBOX_UPDATE_BACKUP=""
    PENDING_VPSBOX_UPDATE_READY_FILE=""
    unset VPSBOX_UPDATE_BACKUP || true
    unset VPSBOX_UPDATE_READY_FILE || true
}

update_vpsbox() {
    local backup="${CMD_PATH}.previous"
    local candidate
    local status

    info "正在下载最新 vpsbox 脚本..."
    mkdir -p "$(dirname "$CMD_PATH")" || return 1
    candidate="$(mktemp "$(dirname "$CMD_PATH")/.vpsbox-update.XXXXXX")" || return 1
    if download_vpsbox_script "$candidate" 1; then
        :
    else
        status=$?
        rm -f "$candidate"
        REMOTE_VERSION=""
        UPDATE_AVAILABLE=0
        case "$status" in
            2)
                info "当前已是最新版，无需更新。"
                return 0
                ;;
            3) return 0 ;;
            *) return "$status" ;;
        esac
    fi

    if [ -f "$CMD_PATH" ]; then
        cp -a "$CMD_PATH" "$backup" || {
            rm -f "$candidate"
            err "备份当前 vpsbox 脚本失败，已取消更新。"
            return 1
        }
        chmod 700 "$backup" || { rm -f "$candidate"; return 1; }
    fi
    if ! mv -f "$candidate" "$CMD_PATH"; then
        rm -f "$candidate"
        err "替换 vpsbox 脚本失败，正在从备份恢复。"
        [ ! -f "$backup" ] || restore_previous_vpsbox "$backup" || true
        return 1
    fi
    if ! install_command_alias; then
        err "新版 vpsbox 管理命令入口安装失败，正在恢复旧版脚本。"
        if [ -f "$backup" ] && restore_previous_vpsbox "$backup"; then
            warn "已恢复更新前的 vpsbox 脚本。"
        else
            err "自动恢复失败；请使用备份手动恢复：$backup"
        fi
        return 1
    fi

    info "vpsbox 已更新；旧版本备份：$backup"
    info "正在重新打开新版管理面板..."
    cleanup_vpsbox_lock
    reexec_updated_vpsbox "$backup" || {
        status=$?
        err "无法重新打开新版管理面板，正在恢复旧版脚本。"
        if ! restore_previous_vpsbox "$backup"; then
            err "自动恢复失败；请使用备份手动恢复：$backup"
        fi
        acquire_lock || true
        return "$status"
    }
}

reexec_updated_vpsbox() {
    local backup="$1" ready status watchdog_pid

    start_vpsbox_update_watchdog "$backup" || {
        err "无法启动新版 vpsbox 启动监护，已取消切换。"
        return 1
    }
    ready="$VPSBOX_UPDATE_WATCHDOG_DIR/ready"
    watchdog_pid="$VPSBOX_UPDATE_WATCHDOG_PID"
    VPSBOX_UPDATE_BACKUP="$backup" VPSBOX_UPDATE_READY_FILE="$ready" exec "$CMD_PATH"
    status=$?
    mark_vpsbox_update_ready "$ready" || true
    wait "$watchdog_pid" 2>/dev/null || true
    VPSBOX_UPDATE_WATCHDOG_PID=""
    VPSBOX_UPDATE_WATCHDOG_DIR=""
    return "$status"
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

bbr_fq_summary_state() {
    local bbr fq

    bbr="$(bbr_state)"
    fq="$(fq_state)"
    if [ "$bbr" = "已启用" ] && [ "$fq" = "已启用" ]; then
        echo "已开启"
    else
        printf 'BBR %s / fq %s\n' "$bbr" "$fq"
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

fail2ban_service_is_enabled() {
    if is_systemd; then
        systemctl is-enabled --quiet fail2ban 2>/dev/null
    elif [ "$OS" = "alpine" ]; then
        [ -e /etc/runlevels/default/fail2ban ] || [ -L /etc/runlevels/default/fail2ban ]
    else
        return 1
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

render_fail2ban_sshd_config() {
    local ports="$1" backend="$2"

    cat <<EOF
[sshd]
enabled = true
port = $ports
backend = $backend
EOF
}

fail2ban_sshd_configuration_healthy() {
    local backend="auto" ports

    fail2ban_installed || return 1
    [ "$(fail2ban_service_state)" = "运行中" ] || return 1
    fail2ban_service_is_enabled || return 1
    [ -f "$FAIL2BAN_VPSBOX_SSHD_CONF" ] &&
        [ ! -L "$FAIL2BAN_VPSBOX_SSHD_CONF" ] || return 1
    ports="$(ssh_effective_ports_csv)" || return 1
    is_systemd && backend="systemd"
    render_fail2ban_sshd_config "$ports" "$backend" |
        cmp -s - "$FAIL2BAN_VPSBOX_SSHD_CONF" || return 1
    fail2ban-client -t -c /etc/fail2ban >/dev/null 2>&1 || return 1
    fail2ban-client status sshd >/dev/null 2>&1
}

fail2ban_action_names() {
    local output header

    output="$(fail2ban-client get sshd actions 2>/dev/null)" || return 1
    header="${output%%$'\n'*}"
    [[ "$header" == "The jail sshd has the following actions:" ]] || return 1
    printf '%s\n' "$output" |
        sed '1d' |
        tr ',' '\n' |
        sed 's/^[[:space:]]*//; s/[[:space:]]*$//; /^$/d'
}

fail2ban_single_action_line() {
    local line

    line="$(printf '%s\n' "$1" |
        sed 's/^[[:space:]]*//; s/[[:space:]]*$//; /^$/d')"
    [ -n "$line" ] && [[ "$line" != *$'\n'* ]] || return 1
    printf '%s\n' "$line"
}

fail2ban_action_executable() {
    local line="$1" executable

    read -r executable _ <<< "$line"
    executable="${executable#\"}"
    executable="${executable%\"}"
    printf '%s\n' "$executable"
}

fail2ban_simple_action_is_safe() {
    local actionban="$1"

    [[ "$actionban" != *';'* ]] &&
        [[ "$actionban" != *'|'* ]] &&
        [[ "$actionban" != *'&'* ]] &&
        [[ "$actionban" != *'`'* ]] &&
        [[ "$actionban" != *'$('* ]]
}

fail2ban_ipset_action_backend() {
    local actionban="$1" safe left right executable

    [[ "$actionban" == *'<ip>'* ]] || return 1
    [[ "$actionban" != *';'* ]] || return 1
    [[ "$actionban" != *'&'* ]] || return 1
    [[ "$actionban" != *'`'* ]] || return 1
    [[ "$actionban" != *'$('* ]] || return 1
    safe="${actionban//||/}"
    [[ "$safe" != *'|'* ]] || return 1

    if [[ "$actionban" == *'||'* ]]; then
        left="$(fail2ban_single_action_line "${actionban%%||*}")" || return 1
        right="${actionban#*||}"
        [[ "$right" != *'||'* ]] || return 1
        right="$(fail2ban_single_action_line "$right")" || return 1
        executable="$(fail2ban_action_executable "$left")"
        case "$executable" in ipset|*/ipset|'<ipset>') ;; *) return 1 ;; esac
        executable="$(fail2ban_action_executable "$right")"
        case "$executable" in ipset|*/ipset|'<ipset>') ;; *) return 1 ;; esac
        [[ " $left " == *' --test '* && " $right " == *' --add '* ]] || return 1
    else
        left="$(fail2ban_single_action_line "$actionban")" || return 1
        executable="$(fail2ban_action_executable "$left")"
        case "$executable" in ipset|*/ipset|'<ipset>') ;; *) return 1 ;; esac
        [[ " $left " == *' add '* ]] || return 1
    fi
    printf '%s\n' ipset
}

fail2ban_ufw_action_backend() {
    local actionban="$1" safe line executable after_and
    local saw_if=0 saw_then=0 saw_else=0 saw_fi=0 ufw_commands=0

    [[ "$actionban" == *'<ip>'* ]] || return 1
    [[ "$actionban" != *';'* ]] || return 1
    [[ "$actionban" != *'|'* ]] || return 1
    [[ "$actionban" != *'`'* ]] || return 1
    [[ "$actionban" != *'$('* ]] || return 1
    safe="${actionban//&&/}"
    [[ "$safe" != *'&'* ]] || return 1

    while IFS= read -r line; do
        line="$(printf '%s\n' "$line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
        [ -n "$line" ] || continue
        case "$line" in
            if\ \[\ -n\ *' ] && '* )
                [ "$saw_if" -eq 0 ] || return 1
                after_and="${line#* ] && }"
                executable="$(fail2ban_action_executable "$after_and")"
                case "$executable" in ufw|*/ufw|'<ufw>') ;; *) return 1 ;; esac
                [[ " $after_and " == *' app info '* ]] || return 1
                saw_if=1
                ;;
            then) saw_then=$((saw_then + 1)) ;;
            else) saw_else=$((saw_else + 1)) ;;
            fi) saw_fi=$((saw_fi + 1)) ;;
            *)
                executable="$(fail2ban_action_executable "$line")"
                case "$executable" in ufw|*/ufw|'<ufw>') ;; *) return 1 ;; esac
                [[ " $line " == *' from <ip> '* ]] || return 1
                ufw_commands=$((ufw_commands + 1))
                ;;
        esac
    done <<< "$actionban"
    [ "$saw_if" -eq 1 ] && [ "$saw_then" -eq 1 ] &&
        [ "$saw_else" -eq 1 ] && [ "$saw_fi" -eq 1 ] &&
        [ "$ufw_commands" -eq 2 ] || return 1
    printf '%s\n' ufw
}

fail2ban_action_backend() {
    local action="$1" actionban="$2" line executable

    [[ "$actionban" == *'<ip>'* ]] || return 1
    case "$action" in
        nftables|nftables-multiport|nftables-allports)
            fail2ban_simple_action_is_safe "$actionban" || return 1
            line="$(fail2ban_single_action_line "$actionban")" || return 1
            executable="$(fail2ban_action_executable "$line")"
            case "$executable" in nft|*/nft|'<nft>'|'<nftables>') ;; *) return 1 ;; esac
            [[ " $line " == *' add element '* ]] || return 1
            printf '%s\n' nftables
            ;;
        iptables|iptables-multiport|iptables-allports)
            fail2ban_simple_action_is_safe "$actionban" || return 1
            line="$(fail2ban_single_action_line "$actionban")" || return 1
            executable="$(fail2ban_action_executable "$line")"
            case "$executable" in iptables|*/iptables|'<iptables>') ;; *) return 1 ;; esac
            [[ " $line " == *' -I '* && " $line " == *' -s <ip> '* ]] || return 1
            printf '%s\n' iptables
            ;;
        iptables-ipset|iptables-ipset-*)
            fail2ban_ipset_action_backend "$actionban"
            ;;
        ipset)
            fail2ban_ipset_action_backend "$actionban"
            ;;
        ufw)
            fail2ban_ufw_action_backend "$actionban"
            ;;
        firewallcmd-new|firewallcmd-multiport|firewallcmd-allports|firewallcmd-ipset)
            fail2ban_simple_action_is_safe "$actionban" || return 1
            line="$(fail2ban_single_action_line "$actionban")" || return 1
            executable="$(fail2ban_action_executable "$line")"
            case "$executable" in
                firewall-cmd|*/firewall-cmd|'<firewall-cmd>')
                    if [[ " $line " == *' --direct --add-rule '* && " $line " == *' -s <ip> '* ]] ||
                        [[ " $line " == *' --add-entry=<ip> '* ]]; then
                        printf '%s\n' firewalld
                    else
                        return 1
                    fi
                    ;;
                ipset|*/ipset|'<ipset>')
                    [[ " $line " == *' add '* ]] || return 1
                    printf '%s\n' ipset
                    ;;
                *) return 1 ;;
            esac
            ;;
        *) return 1 ;;
    esac
}

fail2ban_effective_firewall_backends() {
    local actions action actionban backend backends=""

    actions="$(fail2ban_action_names)" || {
        err "无法读取 Fail2ban sshd jail 的动作列表，已取消真实封禁验证。"
        return 1
    }
    [ -n "$actions" ] || {
        err "Fail2ban sshd jail 没有可验证的封禁动作。"
        return 1
    }

    while IFS= read -r action; do
        [ -n "$action" ] || continue
        actionban="$(fail2ban-client get sshd action "$action" actionban 2>/dev/null)" || {
            err "无法读取 Fail2ban 动作 $action 的实际封禁命令。"
            return 1
        }
        [ -n "$actionban" ] || {
            err "Fail2ban 动作 $action 没有实际封禁命令。"
            return 1
        }
        backend="$(fail2ban_action_backend "$action" "$actionban")" || {
            err "Fail2ban 动作 $action 不是受支持的纯防火墙封禁命令；为避免通知或外部副作用，未执行测试封禁。"
            return 1
        }
        if ! grep -qxF "$backend" <<< "$backends"; then
            backends+="${backends:+$'\n'}$backend"
        fi
    done <<< "$actions"

    [ -n "$backends" ] || return 1
    printf '%s\n' "$backends"
}

fail2ban_backend_dump() {
    local backend="$1" ipsets ipset_name

    case "$backend" in
        nftables)
            command -v nft >/dev/null 2>&1 || return 1
            nft list ruleset 2>/dev/null
            ;;
        iptables)
            command -v iptables-save >/dev/null 2>&1 || return 1
            iptables-save 2>/dev/null
            ;;
        ipset)
            command -v ipset >/dev/null 2>&1 || return 1
            ipset save 2>/dev/null
            ;;
        ufw)
            command -v ufw >/dev/null 2>&1 || return 1
            ufw show raw 2>/dev/null
            ;;
        firewalld)
            command -v firewall-cmd >/dev/null 2>&1 || return 1
            firewall-cmd --direct --get-all-rules 2>/dev/null || return 1
            firewall-cmd --list-all-zones 2>/dev/null || return 1
            ipsets="$(firewall-cmd --get-ipsets 2>/dev/null)" || return 1
            for ipset_name in $ipsets; do
                firewall-cmd --ipset="$ipset_name" --get-entries 2>/dev/null || return 1
            done
            ;;
        *) return 1 ;;
    esac
}

fail2ban_backends_readable() {
    local backends="$1" backend

    while IFS= read -r backend; do
        [ -n "$backend" ] || continue
        if ! fail2ban_backend_dump "$backend" >/dev/null; then
            err "无法读取 Fail2ban 的 $backend 防火墙后端；请检查对应命令与运行状态。"
            return 1
        fi
    done <<< "$backends"
}

fail2ban_ipv4_in_text() {
    local ip="$1"
    local text="${2:-}"
    local escaped

    is_ipv4_address "$ip" || return 1
    escaped="${ip//./\\.}"
    grep -Eq "(^|[^0-9.])${escaped}(/32)?([^0-9./]|$)" <<< "$text"
}

fail2ban_jail_has_ip() {
    local ip="$1" output

    output="$(fail2ban-client get sshd banip 2>/dev/null)" || return 2
    fail2ban_ipv4_in_text "$ip" "$output"
}

fail2ban_backend_has_ip() {
    local backend="$1" ip="$2" output

    output="$(fail2ban_backend_dump "$backend")" || return 2
    fail2ban_ipv4_in_text "$ip" "$output"
}

fail2ban_test_state_present() {
    local ip="$1" backends="$2" backend status

    if fail2ban_jail_has_ip "$ip"; then
        :
    else
        status=$?
        [ "$status" -eq 1 ] && return 1
        return 2
    fi
    while IFS= read -r backend; do
        [ -n "$backend" ] || continue
        if fail2ban_backend_has_ip "$backend" "$ip"; then
            :
        else
            status=$?
            [ "$status" -eq 1 ] && return 1
            return 2
        fi
    done <<< "$backends"
    return 0
}

fail2ban_test_state_absent() {
    local ip="$1" backends="$2" backend status

    if fail2ban_jail_has_ip "$ip"; then
        return 1
    else
        status=$?
        [ "$status" -eq 1 ] || return 2
    fi
    while IFS= read -r backend; do
        [ -n "$backend" ] || continue
        if fail2ban_backend_has_ip "$backend" "$ip"; then
            return 1
        else
            status=$?
            [ "$status" -eq 1 ] || return 2
        fi
    done <<< "$backends"
    return 0
}

fail2ban_test_client_ipv4() {
    local ip=""

    if [ -n "${SSH_CONNECTION:-}" ]; then
        ip="${SSH_CONNECTION%% *}"
    elif [ -n "${SSH_CLIENT:-}" ]; then
        ip="${SSH_CLIENT%% *}"
    fi
    is_ipv4_address "$ip" && printf '%s\n' "$ip"
}

fail2ban_local_ipv4_text() {
    if command -v ip >/dev/null 2>&1; then
        ip -o -4 addr show 2>/dev/null
    elif command -v hostname >/dev/null 2>&1; then
        hostname -I 2>/dev/null
    else
        return 1
    fi
}

fail2ban_select_test_ip() {
    local backends="$1" client_ip local_ipv4 candidate status
    local -a candidates=(
        "192.0.2.254" "198.51.100.254" "203.0.113.254"
        "192.0.2.253" "198.51.100.253" "203.0.113.253"
    )

    client_ip="$(fail2ban_test_client_ipv4 || true)"
    local_ipv4="$(fail2ban_local_ipv4_text)" || return 1
    for candidate in "${candidates[@]}"; do
        [ "$candidate" = "$client_ip" ] && continue
        fail2ban_ipv4_in_text "$candidate" "$local_ipv4" && continue
        if fail2ban_test_state_absent "$candidate" "$backends"; then
            printf '%s\n' "$candidate"
            return 0
        else
            status=$?
            [ "$status" -eq 1 ] && continue
            return 1
        fi
    done
    return 1
}

cleanup_active_fail2ban_test() {
    local ip="${ACTIVE_FAIL2BAN_TEST_IP:-}"
    local backends="${ACTIVE_FAIL2BAN_TEST_BACKENDS:-}"
    local attempt

    [ -n "$ip" ] || return 0
    for attempt in 1 2 3 4 5; do
        fail2ban-client set sshd unbanip "$ip" >/dev/null 2>&1 || true
        if fail2ban_test_state_absent "$ip" "$backends"; then
            ACTIVE_FAIL2BAN_TEST_IP=""
            ACTIVE_FAIL2BAN_TEST_BACKENDS=""
            return 0
        fi
        [ "$attempt" -lt 5 ] && sleep 1
    done

    err "Fail2ban 测试地址 $ip 未能自动完全解封。"
    err "请保持当前 SSH 会话并执行：fail2ban-client set sshd unbanip $ip"
    return 1
}

verify_fail2ban_real_ban() {
    local backends test_ip attempt present=0

    if [ -n "${ACTIVE_FAIL2BAN_TEST_IP:-}" ] && ! cleanup_active_fail2ban_test; then
        err "上一次 Fail2ban 测试地址仍未清理，已拒绝开始新的验证。"
        return 2
    fi
    backends="$(fail2ban_effective_firewall_backends)" || return 1
    fail2ban_backends_readable "$backends" || return 1
    test_ip="$(fail2ban_select_test_ip "$backends")" || {
        err "无法选出未被占用的 TEST-NET IPv4 测试地址。"
        return 1
    }

    ACTIVE_FAIL2BAN_TEST_IP="$test_ip"
    ACTIVE_FAIL2BAN_TEST_BACKENDS="$backends"
    info "正在验证 Fail2ban sshd jail 与实际防火墙封禁链路..."
    if ! fail2ban-client set sshd banip "$test_ip" >/dev/null 2>&1; then
        err "Fail2ban 测试封禁命令执行失败。"
        if cleanup_active_fail2ban_test; then
            return 1
        fi
        return 2
    fi
    for attempt in 1 2 3 4 5; do
        if fail2ban_test_state_present "$test_ip" "$backends"; then
            present=1
            break
        fi
        [ "$attempt" -lt 5 ] && sleep 1
    done
    if [ "$present" -ne 1 ]; then
        err "测试地址未同时出现在 sshd jail 与实际防火墙后端。"
        if cleanup_active_fail2ban_test; then
            return 1
        fi
        return 2
    fi
    if ! cleanup_active_fail2ban_test; then
        return 2
    fi

    info "Fail2ban 真实封禁、后端落地与解封清理验证通过。"
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
    local source_file="$CHRONY_SOURCE_FILE"

    conf="$(chrony_conf_path)"
    if [ ! -f "$conf" ]; then
        err "未找到 chrony 配置文件：$conf"
        return 1
    fi

    if grep -Eq '^[[:space:]]*sourcedir[[:space:]]+/etc/chrony/sources\.d([[:space:]]|$)' "$conf"; then
        mkdir -p /etc/chrony/sources.d || return 1
        if ! cat > "$source_file" <<EOF
pool time.cloudflare.com iburst maxsources 4
pool pool.ntp.org iburst maxsources 4
EOF
        then
            return 1
        fi
        remove_vpsbox_ntp_block "$conf" || return 1
        info "已写入 NTP 源：$source_file"
    else
        remove_vpsbox_ntp_block "$conf" || return 1
        if ! cat >> "$conf" <<EOF

$NTP_SOURCES_BEGIN
pool time.cloudflare.com iburst maxsources 4
pool pool.ntp.org iburst maxsources 4
$NTP_SOURCES_END
EOF
        then
            return 1
        fi
        rm -f "$source_file" || return 1
        info "已写入 NTP 源：$conf"
    fi
}

chrony_expected_sources() {
    cat <<EOF
pool time.cloudflare.com iburst maxsources 4
pool pool.ntp.org iburst maxsources 4
EOF
}

chrony_sources_are_current() {
    local conf source_file="$CHRONY_SOURCE_FILE"
    local expected actual begin_count end_count

    conf="$(chrony_conf_path)"
    [ -f "$conf" ] && [ ! -L "$conf" ] || return 1
    expected="$(chrony_expected_sources)"
    if grep -Eq '^[[:space:]]*sourcedir[[:space:]]+/etc/chrony/sources\.d([[:space:]]|$)' "$conf"; then
        [ -f "$source_file" ] && [ ! -L "$source_file" ] || return 1
        actual="$(cat "$source_file")"
        [ "$actual" = "$expected" ] || return 1
        ! grep -Fq "$NTP_SOURCES_BEGIN" "$conf" &&
            ! grep -Fq "$NTP_SOURCES_END" "$conf"
        return
    fi

    [ ! -e "$source_file" ] && [ ! -L "$source_file" ] || return 1
    begin_count="$(grep -Fxc "$NTP_SOURCES_BEGIN" "$conf" 2>/dev/null || true)"
    end_count="$(grep -Fxc "$NTP_SOURCES_END" "$conf" 2>/dev/null || true)"
    [ "$begin_count" = "1" ] && [ "$end_count" = "1" ] || return 1
    actual="$(sed -n "/^${NTP_SOURCES_BEGIN}$/,/^${NTP_SOURCES_END}$/p" "$conf")"
    [ "$actual" = "$NTP_SOURCES_BEGIN
$expected
$NTP_SOURCES_END" ]
}

ntp_service_state_is_healthy() {
    local svc="$1"

    systemctl is-enabled --quiet "$svc" 2>/dev/null &&
        systemctl is-active --quiet "$svc" 2>/dev/null || return 1
    if systemd_unit_exists systemd-timesyncd.service; then
        ! systemctl is-enabled --quiet systemd-timesyncd 2>/dev/null &&
            ! systemctl is-active --quiet systemd-timesyncd 2>/dev/null || return 1
    fi
}

repair_ntp_service_state() {
    local svc="$1" failed=0 timesyncd_unit="absent"
    local chrony_enabled="disabled" chrony_active="inactive"
    local timesyncd_enabled="disabled" timesyncd_active="inactive"

    info "NTP 配置已存在，正在轻量修复服务状态..."
    systemctl is-enabled --quiet "$svc" 2>/dev/null && chrony_enabled="enabled"
    systemctl is-active --quiet "$svc" 2>/dev/null && chrony_active="active"
    if systemd_unit_exists systemd-timesyncd.service; then
        timesyncd_unit="present"
        systemctl is-enabled --quiet systemd-timesyncd 2>/dev/null &&
            timesyncd_enabled="enabled"
        systemctl is-active --quiet systemd-timesyncd 2>/dev/null &&
            timesyncd_active="active"
    fi

    systemctl enable "$svc" >/dev/null 2>&1 || failed=1
    if [ "$failed" -eq 0 ] && ! systemctl is-active --quiet "$svc" 2>/dev/null; then
        retry 3 2 systemctl start "$svc" || failed=1
    fi
    if [ "$failed" -eq 0 ] && [ "$timesyncd_unit" = "present" ] &&
        { systemctl is-enabled --quiet systemd-timesyncd 2>/dev/null ||
            systemctl is-active --quiet systemd-timesyncd 2>/dev/null; }; then
        systemctl disable --now systemd-timesyncd >/dev/null 2>&1 || failed=1
    fi
    if [ "$failed" -eq 0 ] && ntp_service_state_is_healthy "$svc"; then
        return 0
    fi

    warn "NTP 服务状态轻量修复失败，正在恢复修改前状态。"
    restore_ntp_unit_state "$svc" present "$chrony_enabled" "$chrony_active" || true
    restore_ntp_unit_state systemd-timesyncd "$timesyncd_unit" \
        "$timesyncd_enabled" "$timesyncd_active" || true
    return 1
}

show_ntp_runtime_details() {
    local svc="$1" enabled_state active_state sources_output tracking_output

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
            warn "chrony 已运行，首次同步可能需要几分钟；当前配置不会重复改写。"
        fi
    else
        warn "无法读取 chrony 同步状态。"
    fi

    echo ""
    info "系统时间关键状态："
    timedatectl show -p Timezone -p NTP -p NTPSynchronized -p TimeUSec 2>/dev/null || true
    warn "如确认需要立即校准，可手动执行：chronyc makestep"
}

systemd_unit_exists() {
    local unit="$1"

    systemctl list-unit-files "$unit" 2>/dev/null | grep -q "^${unit//./\\.}"
}

ntp_package_installed() {
    local package="$1"

    case "$OS" in
        debian)
            dpkg-query -W -f='${Status}\n' "$package" 2>/dev/null |
                grep -qx 'install ok installed'
            ;;
        redhat)
            rpm -q "$package" >/dev/null 2>&1
            ;;
        *)
            return 1
            ;;
    esac
}

restore_ntp_packages_to_state() {
    local chrony_state="$1" timesyncd_state="${2:-}" failed=0

    case "$chrony_state" in installed|absent) ;; *) return 1 ;; esac
    case "$OS" in
        debian)
            case "$timesyncd_state" in installed|absent) ;; *) return 1 ;; esac
            export DEBIAN_FRONTEND=noninteractive
            if [ "$chrony_state" = "absent" ]; then
                if ntp_package_installed chrony &&
                    ! apt_get_bounded "$PACKAGE_INSTALL_TIMEOUT" purge -y chrony; then
                    failed=1
                fi
                if [ "$timesyncd_state" = "installed" ]; then
                    ntp_package_installed systemd-timesyncd ||
                        apt_get_bounded "$PACKAGE_INSTALL_TIMEOUT" install -y systemd-timesyncd ||
                        failed=1
                elif ntp_package_installed systemd-timesyncd &&
                    ! apt_get_bounded "$PACKAGE_INSTALL_TIMEOUT" purge -y systemd-timesyncd; then
                    failed=1
                fi
            else
                ntp_package_installed chrony ||
                    apt_get_bounded "$PACKAGE_INSTALL_TIMEOUT" install -y chrony ||
                    failed=1
                if [ "$timesyncd_state" = "absent" ] &&
                    ntp_package_installed systemd-timesyncd &&
                    ! apt_get_bounded "$PACKAGE_INSTALL_TIMEOUT" purge -y systemd-timesyncd; then
                    failed=1
                fi
            fi
            ;;
        redhat)
            if [ "$chrony_state" = "installed" ] && ! ntp_package_installed chrony; then
                if command -v dnf >/dev/null 2>&1; then
                    dnf_bounded "$PACKAGE_INSTALL_TIMEOUT" install -y chrony || failed=1
                else
                    yum_bounded "$PACKAGE_INSTALL_TIMEOUT" install -y chrony || failed=1
                fi
            elif [ "$chrony_state" = "absent" ] && ntp_package_installed chrony; then
                if command -v dnf >/dev/null 2>&1; then
                    dnf_bounded "$PACKAGE_INSTALL_TIMEOUT" remove -y chrony || failed=1
                else
                    yum_bounded "$PACKAGE_INSTALL_TIMEOUT" remove -y chrony || failed=1
                fi
            fi
            ;;
        *)
            return 1
            ;;
    esac
    return "$failed"
}

restore_ntp_unit_state() {
    local unit="$1" existed="$2" enabled="$3" active="$4"

    if [ "$existed" = "absent" ]; then
        if systemd_unit_exists "${unit}.service"; then
            systemctl disable --now "$unit" >/dev/null 2>&1 || return 1
        fi
        return 0
    fi
    [ "$existed" = "present" ] || return 1
    systemd_unit_exists "${unit}.service" || return 1
    if [ "$enabled" = "enabled" ]; then
        systemctl enable "$unit" >/dev/null || return 1
    else
        systemctl disable "$unit" >/dev/null || return 1
    fi
    if [ "$active" = "active" ]; then
        systemctl start "$unit" >/dev/null || return 1
    else
        systemctl stop "$unit" >/dev/null || return 1
    fi
}

restore_ntp_snapshot_file() {
    local snapshot_dir="$1" name="$2" target="$3"

    if [ -f "$snapshot_dir/$name.present" ]; then
        [ -f "$snapshot_dir/$name" ] && [ ! -L "$snapshot_dir/$name" ] || return 1
        if [ -L "$target" ]; then
            rm -f -- "$target" || return 1
        elif [ -e "$target" ] && [ ! -f "$target" ]; then
            return 1
        fi
        cp -a "$snapshot_dir/$name" "$target"
    elif [ -f "$snapshot_dir/$name.absent" ]; then
        if [ -L "$target" ] || [ -f "$target" ]; then
            rm -f -- "$target"
        elif [ -e "$target" ]; then
            return 1
        fi
    else
        return 1
    fi
}

cleanup_ntp_snapshot() {
    local snapshot_dir="$1"

    [[ "$snapshot_dir" == /tmp/vpsbox-chrony.* ]] &&
        [ -d "$snapshot_dir" ] && [ ! -L "$snapshot_dir" ] || return 1
    rm -rf -- "$snapshot_dir"
}

rollback_ntp_runtime_state() {
    local snapshot_dir="$1" conf="$2" source_file="$3" svc="$4"
    local chrony_package="$5" timesyncd_package="$6"
    local chrony_unit="$7" chrony_enabled="$8" chrony_active="$9"
    local timesyncd_unit="${10}" timesyncd_enabled="${11}" timesyncd_active="${12}"
    local failed=0

    systemctl stop "$svc" >/dev/null 2>&1 || true
    restore_ntp_packages_to_state "$chrony_package" "$timesyncd_package" || failed=1
    restore_ntp_snapshot_file "$snapshot_dir" conf "$conf" || failed=1
    restore_ntp_snapshot_file "$snapshot_dir" sources "$source_file" || failed=1
    restore_ntp_unit_state "$svc" "$chrony_unit" "$chrony_enabled" "$chrony_active" ||
        failed=1
    restore_ntp_unit_state systemd-timesyncd "$timesyncd_unit" \
        "$timesyncd_enabled" "$timesyncd_active" || failed=1
    return "$failed"
}

clear_ntp_change_tracking() {
    local key failed=0

    clear_change_tracking NTP_CONF || failed=1
    clear_change_tracking NTP_SOURCES || failed=1
    for key in NTP_CHRONY_ACTIVE NTP_CHRONY_ENABLED NTP_CHRONY_PACKAGE \
        NTP_CHRONY_UNIT NTP_TIMESYNCD_ACTIVE NTP_TIMESYNCD_ENABLED \
        NTP_TIMESYNCD_PACKAGE NTP_TIMESYNCD_UNIT; do
        manifest_remove "$key" || failed=1
    done
    return "$failed"
}

settle_failed_ntp_change() {
    local snapshot_dir="$1" conf="$2" source_file="$3" svc="$4"
    local chrony_package="$5" timesyncd_package="$6"
    local chrony_unit="$7" chrony_enabled="$8" chrony_active="$9"
    local timesyncd_unit="${10}" timesyncd_enabled="${11}" timesyncd_active="${12}"
    local applied_before="${13}"

    if ! rollback_ntp_runtime_state "$snapshot_dir" "$conf" "$source_file" "$svc" \
        "$chrony_package" "$timesyncd_package" \
        "$chrony_unit" "$chrony_enabled" "$chrony_active" \
        "$timesyncd_unit" "$timesyncd_enabled" "$timesyncd_active"; then
        err "NTP 原状态未能完整恢复；恢复记录与临时快照已保留：$snapshot_dir"
        return 1
    fi
    cleanup_ntp_snapshot "$snapshot_dir" ||
        warn "NTP 已回滚，但临时快照清理失败：$snapshot_dir"
    if [ "$applied_before" != "1" ] && ! clear_ntp_change_tracking; then
        warn "NTP 已回滚，但变更清单清理失败；恢复菜单仍会保留该项目。"
        return 1
    fi
}

restore_recorded_ntp_change() {
    local svc chrony_package timesyncd_package chrony_unit timesyncd_unit
    local chrony_enabled chrony_active timesyncd_enabled timesyncd_active failed=0

    detect_os
    is_systemd || return 1
    svc="$(chrony_service_name)"
    chrony_package="$(manifest_value NTP_CHRONY_PACKAGE 2>/dev/null || true)"
    timesyncd_package="$(manifest_value NTP_TIMESYNCD_PACKAGE 2>/dev/null || true)"
    chrony_unit="$(manifest_value NTP_CHRONY_UNIT 2>/dev/null || true)"
    timesyncd_unit="$(manifest_value NTP_TIMESYNCD_UNIT 2>/dev/null || true)"
    chrony_enabled="$(manifest_value NTP_CHRONY_ENABLED 2>/dev/null || true)"
    chrony_active="$(manifest_value NTP_CHRONY_ACTIVE 2>/dev/null || true)"
    timesyncd_enabled="$(manifest_value NTP_TIMESYNCD_ENABLED 2>/dev/null || true)"
    timesyncd_active="$(manifest_value NTP_TIMESYNCD_ACTIVE 2>/dev/null || true)"

    systemctl stop "$svc" >/dev/null 2>&1 || true
    if [ -n "$chrony_package" ]; then
        restore_ntp_packages_to_state "$chrony_package" "$timesyncd_package" ||
            failed=1
    else
        # 兼容 v1.0.21 及更早的 NTP 清单：旧记录没有原包状态。
        # 为避免猜测后卸载用户原有软件，只恢复可确认的文件和现存 unit 状态。
        warn "旧版 NTP 恢复记录缺少包状态，将保留当前已安装的软件包。"
    fi
    restore_change_file NTP_CONF "$(chrony_conf_path)" || failed=1
    restore_change_file NTP_SOURCES "$CHRONY_SOURCE_FILE" || failed=1

    if [ -n "$chrony_unit" ]; then
        restore_ntp_unit_state "$svc" "$chrony_unit" "$chrony_enabled" "$chrony_active" ||
            failed=1
        restore_ntp_unit_state systemd-timesyncd "$timesyncd_unit" \
            "$timesyncd_enabled" "$timesyncd_active" || failed=1
    else
        # 旧版只记录 active/enabled；unit 已不存在时无法安全重建，不能伪报恢复成功。
        if systemd_unit_exists "${svc}.service"; then
            restore_ntp_unit_state "$svc" present "$chrony_enabled" "$chrony_active" ||
                failed=1
        elif [ "$chrony_enabled" = "enabled" ] || [ "$chrony_active" = "active" ]; then
            failed=1
        fi
        if systemd_unit_exists systemd-timesyncd.service; then
            restore_ntp_unit_state systemd-timesyncd present \
                "$timesyncd_enabled" "$timesyncd_active" || failed=1
        elif [ "$timesyncd_enabled" = "enabled" ] || [ "$timesyncd_active" = "active" ]; then
            failed=1
        fi
    fi
    return "$failed"
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
    local conf source_file backup_dir
    local chrony_package="absent" timesyncd_package="absent"
    local chrony_unit="absent" timesyncd_unit="absent"
    local chrony_active="inactive" chrony_enabled="disabled"
    local timesyncd_active="inactive" timesyncd_enabled="disabled"
    local applied_before=0

    detect_os
    if ! is_systemd; then
        if [ "$OS" = "alpine" ]; then
            err "Alpine/OpenRC 当前不适用此功能；vpsbox 不会自动修改 chrony。"
        else
            err "未检测到 systemd，无法自动配置 chrony。"
        fi
        return 1
    fi

    svc="$(chrony_service_name)"
    conf="$(chrony_conf_path)"
    source_file="$CHRONY_SOURCE_FILE"
    if ntp_package_installed chrony &&
        systemd_unit_exists "${svc}.service" &&
        chrony_sources_are_current; then
        if ntp_service_state_is_healthy "$svc"; then
            info "NTP 配置与 chrony 服务已正常，无需重复安装或改写。"
        elif ! repair_ntp_service_state "$svc"; then
            err "NTP 配置正确，但 chrony 服务状态修复失败。"
            show_chrony_permission_hint "$svc"
            return 1
        fi
        show_ntp_runtime_details "$svc"
        return 0
    fi

    ntp_package_installed chrony && chrony_package="installed"
    if [ "$OS" = "debian" ] && ntp_package_installed systemd-timesyncd; then
        timesyncd_package="installed"
    fi
    if systemd_unit_exists "${svc}.service"; then
        chrony_unit="present"
        systemctl is-active --quiet "$svc" 2>/dev/null && chrony_active="active"
        systemctl is-enabled --quiet "$svc" 2>/dev/null && chrony_enabled="enabled"
    fi
    if systemd_unit_exists systemd-timesyncd.service; then
        timesyncd_unit="present"
        systemctl is-active --quiet systemd-timesyncd 2>/dev/null &&
            timesyncd_active="active"
        systemctl is-enabled --quiet systemd-timesyncd 2>/dev/null &&
            timesyncd_enabled="enabled"
    fi

    backup_change_file_once NTP_CONF "$conf" ||
        { err "记录 chrony 原配置失败，已取消修改。"; return 1; }
    backup_change_file_once NTP_SOURCES "$source_file" ||
        { err "记录 NTP 源原配置失败，已取消修改。"; return 1; }
    [ "$(manifest_value APPLIED_NTP_CONF 2>/dev/null || true)" = "1" ] &&
        applied_before=1
    if [ "$applied_before" -eq 0 ]; then
        manifest_set_once NTP_CHRONY_ACTIVE "$chrony_active" || return 1
        manifest_set_once NTP_CHRONY_ENABLED "$chrony_enabled" || return 1
        manifest_set_once NTP_CHRONY_PACKAGE "$chrony_package" || return 1
        manifest_set_once NTP_CHRONY_UNIT "$chrony_unit" || return 1
        manifest_set_once NTP_TIMESYNCD_ACTIVE "$timesyncd_active" || return 1
        manifest_set_once NTP_TIMESYNCD_ENABLED "$timesyncd_enabled" || return 1
        manifest_set_once NTP_TIMESYNCD_PACKAGE "$timesyncd_package" || return 1
        manifest_set_once NTP_TIMESYNCD_UNIT "$timesyncd_unit" || return 1
        mark_change_applied NTP_CONF || {
            clear_ntp_change_tracking || true
            err "无法记录 NTP 事务，已取消修改。"
            return 1
        }
    else
        # 兼容 v1.0.21 及更早已记录的 NTP 变更：旧清单没有包与 unit 字段，
        # 不能用当前（修改后）状态反推原状态，因此这里绝不补写猜测值。
        :
    fi

    backup_dir="$(mktemp -d /tmp/vpsbox-chrony.XXXXXX)" || return 1
    if [ -f "$conf" ] && [ ! -L "$conf" ]; then
        cp -a "$conf" "$backup_dir/conf" &&
            : > "$backup_dir/conf.present" || {
            cleanup_ntp_snapshot "$backup_dir" || true
            return 1
        }
    elif [ ! -e "$conf" ] && [ ! -L "$conf" ]; then
        : > "$backup_dir/conf.absent"
    else
        cleanup_ntp_snapshot "$backup_dir" || true
        err "chrony 配置不是普通文件，已拒绝修改：$conf"
        return 1
    fi
    if [ -f "$source_file" ] && [ ! -L "$source_file" ]; then
        cp -a "$source_file" "$backup_dir/sources" &&
            : > "$backup_dir/sources.present" || {
            cleanup_ntp_snapshot "$backup_dir" || true
            return 1
        }
    elif [ ! -e "$source_file" ] && [ ! -L "$source_file" ]; then
        : > "$backup_dir/sources.absent"
    else
        cleanup_ntp_snapshot "$backup_dir" || true
        err "NTP 源配置不是普通文件，已拒绝修改：$source_file"
        return 1
    fi

    info "正在安装 chrony..."
    case "$OS" in
        debian)
            export DEBIAN_FRONTEND=noninteractive
            if ! apt_get_bounded "$PACKAGE_UPDATE_TIMEOUT" update ||
                ! apt_get_bounded "$PACKAGE_INSTALL_TIMEOUT" install -y chrony; then
                settle_failed_ntp_change "$backup_dir" "$conf" "$source_file" "$svc" \
                    "$chrony_package" "$timesyncd_package" \
                    "$chrony_unit" "$chrony_enabled" "$chrony_active" \
                    "$timesyncd_unit" "$timesyncd_enabled" "$timesyncd_active" \
                    "$applied_before" || true
                return 1
            fi
            ;;
        redhat)
            if command -v dnf >/dev/null 2>&1; then
                dnf_bounded "$PACKAGE_INSTALL_TIMEOUT" install -y chrony
            else
                yum_bounded "$PACKAGE_INSTALL_TIMEOUT" install -y chrony
            fi || {
                settle_failed_ntp_change "$backup_dir" "$conf" "$source_file" "$svc" \
                    "$chrony_package" "$timesyncd_package" \
                    "$chrony_unit" "$chrony_enabled" "$chrony_active" \
                    "$timesyncd_unit" "$timesyncd_enabled" "$timesyncd_active" \
                    "$applied_before" || true
                return 1
            }
            ;;
        *)
            settle_failed_ntp_change "$backup_dir" "$conf" "$source_file" "$svc" \
                "$chrony_package" "$timesyncd_package" \
                "$chrony_unit" "$chrony_enabled" "$chrony_active" \
                "$timesyncd_unit" "$timesyncd_enabled" "$timesyncd_active" \
                "$applied_before" || true
            err "未识别系统类型，无法自动配置 chrony。"
            return 1
            ;;
    esac

    if [ ! -f "$conf" ] || [ -L "$conf" ]; then
        err "chrony 安装后未生成有效配置，正在恢复原 NTP 状态。"
        settle_failed_ntp_change "$backup_dir" "$conf" "$source_file" "$svc" \
            "$chrony_package" "$timesyncd_package" \
            "$chrony_unit" "$chrony_enabled" "$chrony_active" \
            "$timesyncd_unit" "$timesyncd_enabled" "$timesyncd_active" \
            "$applied_before" || true
        return 1
    fi
    info "chrony 服务名：$svc"

    systemctl stop "$svc" 2>/dev/null || true
    if ! write_chrony_sources; then
        settle_failed_ntp_change "$backup_dir" "$conf" "$source_file" "$svc" \
            "$chrony_package" "$timesyncd_package" \
            "$chrony_unit" "$chrony_enabled" "$chrony_active" \
            "$timesyncd_unit" "$timesyncd_enabled" "$timesyncd_active" \
            "$applied_before" || true
        return 1
    fi

    info "正在启用 chrony 并设置开机自启..."
    if ! systemctl enable --now "$svc"; then
        err "chrony 启动失败，正在恢复原 NTP 配置。"
        settle_failed_ntp_change "$backup_dir" "$conf" "$source_file" "$svc" \
            "$chrony_package" "$timesyncd_package" \
            "$chrony_unit" "$chrony_enabled" "$chrony_active" \
            "$timesyncd_unit" "$timesyncd_enabled" "$timesyncd_active" \
            "$applied_before" || true
        show_chrony_permission_hint "$svc"
        return 1
    fi

    sleep 2
    if ! systemctl is-active --quiet "$svc" 2>/dev/null; then
        err "chrony 未保持运行，正在恢复原 NTP 配置。"
        settle_failed_ntp_change "$backup_dir" "$conf" "$source_file" "$svc" \
            "$chrony_package" "$timesyncd_package" \
            "$chrony_unit" "$chrony_enabled" "$chrony_active" \
            "$timesyncd_unit" "$timesyncd_enabled" "$timesyncd_active" \
            "$applied_before" || true
        show_chrony_permission_hint "$svc"
        return 1
    fi

    if systemd_unit_exists systemd-timesyncd.service; then
        info "chrony 已确认运行，正在停用 systemd-timesyncd，避免多个 NTP 客户端并存..."
        if ! systemctl disable --now systemd-timesyncd; then
            warn "无法停用 systemd-timesyncd；为避免多个 NTP 客户端并存，正在回滚 chrony 配置。"
            settle_failed_ntp_change "$backup_dir" "$conf" "$source_file" "$svc" \
                "$chrony_package" "$timesyncd_package" \
                "$chrony_unit" "$chrony_enabled" "$chrony_active" \
                "$timesyncd_unit" "$timesyncd_enabled" "$timesyncd_active" \
                "$applied_before" || true
            return 1
        fi
    fi
    cleanup_ntp_snapshot "$backup_dir" ||
        warn "NTP 配置已生效，但临时快照清理失败：$backup_dir"

    show_ntp_runtime_details "$svc"
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
    [ -r "$RESOLV_CONF" ] || return 1

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
    done < "$RESOLV_CONF"

    return "$found"
}

resolv_conf_managed_by_systemd_resolved() {
    [ -L "$RESOLV_CONF" ] || return 1

    local target
    target="$(readlink "$RESOLV_CONF" 2>/dev/null || true)"

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
    local output

    if command -v getent >/dev/null 2>&1; then
        output="$(run_bounded_command 8 getent ahosts example.com 2>/dev/null)" || return 1
        grep -Eq '^[0-9A-Fa-f:.]+' <<< "$output"
        return
    fi
    if command -v resolvectl >/dev/null 2>&1; then
        run_bounded_command 8 resolvectl query example.com >/dev/null 2>&1
        return
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

    backup_change_file_once DNS_RESOLV "$RESOLV_CONF" || { err "记录 DNS 原配置失败，已取消修改。"; return 1; }
    backup="${RESOLV_CONF}.vpsbox.bak.$(date +%Y%m%d%H%M%S)"
    if [ -e "$RESOLV_CONF" ]; then
        if ! cp -a "$RESOLV_CONF" "$backup"; then
            err "备份 $RESOLV_CONF 失败，已取消 DNS 修改。"
            return 1
        fi
    else
        created_resolv="1"
    fi
    begin_change_transaction DNS_RESOLV || { err "记录 DNS 修改事务失败，已取消修改。"; return 1; }

    tmp="$(mktemp "$(dirname "$RESOLV_CONF")/.resolv.conf.vpsbox.XXXXXX")" || return 1
    if ! {
        printf 'nameserver %s\n' "$dns1"
        if [ -n "$dns2" ]; then
            printf 'nameserver %s\n' "$dns2"
        fi
        if [ -r "$RESOLV_CONF" ]; then
            awk '$1 != "nameserver" { print }' "$RESOLV_CONF"
        fi
        :
    } > "$tmp"; then
        rm -f "$tmp"
        err "生成新的 $RESOLV_CONF 失败。"
        return 1
    fi

    chown root:root "$tmp" || { rm -f "$tmp"; return 1; }
    chmod 644 "$tmp" || { rm -f "$tmp"; return 1; }
    if ! mv -f "$tmp" "$RESOLV_CONF"; then
        rm -f "$tmp"
        err "原子替换 $RESOLV_CONF 失败。"
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
                cp -a "$backup" "$RESOLV_CONF" || warn "恢复 DNS 备份失败：$backup"
            elif [ "$created_resolv" = "1" ]; then
                rm -f "$RESOLV_CONF"
            fi
            return 1
        fi
    fi

    mark_change_applied DNS_RESOLV || return 1
    if [ -e "$backup" ]; then
        info "原配置备份：$backup"
    fi
    return 0
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
    begin_change_transaction DNS_RESOLVED || { err "记录 DNS 修改事务失败，已取消修改。"; return 1; }

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
    if [ -n "$backup" ] && [ -e "$backup" ]; then
        info "原配置备份：$backup"
    fi
    return 0
}

apply_ipv4_dns() {
    local dns1="$1"
    local dns2="${2:-}"

    if resolv_conf_managed_by_systemd_resolved; then
        write_systemd_resolved_dns "$dns1" "$dns2"
        return $?
    fi

    if [ -L "$RESOLV_CONF" ]; then
        warn "$RESOLV_CONF 是未知符号链接，DNS 可能由系统网络服务管理。"
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
 修改 IPv4 DNS
========================================
当前 IPv4 DNS：
$(ipv4_dns_lines)
----------------------------------------
 [1] 使用默认 DNS：1.1.1.1 + 8.8.8.8
 [2] 自定义 IPv4 DNS
 [0] 取消
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
    local parent tmp

    info "正在开启 IPv4 优先，不会禁用 IPv6。"
    if [ "$(ipv4_priority_state)" = "已启用" ]; then
        info "IPv4 优先已开启，无需重复修改。"
        return 0
    fi
    [ ! -L "$GAI_CONF" ] || { err "$GAI_CONF 是符号链接，已拒绝修改。"; return 1; }
    backup_change_file_once GAI_CONF "$GAI_CONF" || { err "记录 IPv4 优先原配置失败，已取消修改。"; return 1; }
    begin_change_transaction GAI_CONF || { err "记录 IPv4 优先事务失败，已取消修改。"; return 1; }

    parent="$(dirname "$GAI_CONF")"
    [ -d "$parent" ] && [ ! -L "$parent" ] || {
        err "IPv4 优先配置目录无效或为符号链接：$parent"
        return 1
    }
    tmp="$(mktemp "$parent/.gai.conf.vpsbox.XXXXXX")" || return 1
    if [ -f "$GAI_CONF" ]; then
        cp -a -- "$GAI_CONF" "$tmp" || { rm -f -- "$tmp"; return 1; }
    else
        chmod 644 "$tmp" || { rm -f -- "$tmp"; return 1; }
    fi

    if ! sed -i '/^[#[:space:]]*precedence[[:space:]]\+::ffff:0:0\/96[[:space:]]\+/d' "$tmp"; then
        rm -f -- "$tmp"
        err "清理旧 IPv4 优先配置失败。"
        return 1
    fi

    if ! printf '%s\n' 'precedence ::ffff:0:0/96 100' >> "$tmp"; then
        rm -f -- "$tmp"
        err "写入 IPv4 优先配置失败。"
        return 1
    fi
    if ! chown root:root "$tmp" || ! mv -f -- "$tmp" "$GAI_CONF"; then
        rm -f -- "$tmp"
        err "原子替换 IPv4 优先配置失败。"
        return 1
    fi

    info "已写入：precedence ::ffff:0:0/96 100"
    mark_change_applied GAI_CONF || return 1
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
    }'
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

    ports="$(ssh_effective_ports_csv)" || return 1
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

sshd_main_has_active_port_directive() {
    grep -Eq '^[[:space:]]*Port[[:space:]]+[0-9]+' "$SSHD_MAIN_CONF" 2>/dev/null
}

sshd_dropin_include_available() {
    sshd_vpsbox_port_include_available &&
        sshd_vpsbox_hardening_include_available
}

sshd_vpsbox_port_include_available() {
    sshd_main_has_dropin_wildcard ||
        sshd_main_includes_path "$SSHD_VPSBOX_PORT_CONF"
}

sshd_vpsbox_hardening_include_available() {
    sshd_main_has_dropin_wildcard ||
        sshd_main_includes_path "$SSHD_VPSBOX_HARDENING_CONF"
}

sshd_main_has_dropin_wildcard() {
    awk '
        tolower($1) == "include" {
            for (i = 2; i <= NF; i++) {
                if ($i ~ /sshd_config[.]d\/[*][.]conf$/) found = 1
            }
        }
        END { exit !found }
    ' "$SSHD_MAIN_CONF" 2>/dev/null
}

sshd_main_includes_path() {
    local expected="$1"

    awk -v expected="$expected" '
        tolower($1) == "include" {
            for (i = 2; i <= NF; i++) {
                if ($i == expected) found = 1
            }
        }
        END { exit !found }
    ' "$SSHD_MAIN_CONF" 2>/dev/null
}

install_ssh_config_atomically() {
    install_root_file_atomically "$@"
}

ensure_sshd_dropin_include() {
    local tmp
    local -a managed_includes=()

    sshd_dropin_include_available && return 0
    mkdir -p "$SSHD_CONFIG_DIR" || return 1
    tmp="$(mktemp)" || return 1
    sshd_main_includes_path "$SSHD_VPSBOX_PORT_CONF" ||
        managed_includes+=("$SSHD_VPSBOX_PORT_CONF")
    sshd_main_includes_path "$SSHD_VPSBOX_HARDENING_CONF" ||
        managed_includes+=("$SSHD_VPSBOX_HARDENING_CONF")
    [ "${#managed_includes[@]}" -gt 0 ] || {
        rm -f "$tmp"
        return 1
    }

    # OpenSSH 对多数全局指令采用首个匹配值，因此 Include 必须位于主配置前部。
    # 主配置原本没有通配 Include 时只引入 vpsbox 自己的两个文件，避免顺带
    # 激活目录中由云镜像或管理员留下的其他休眠 drop-in。
    {
        printf 'Include'
        printf ' %s' "${managed_includes[@]}"
        printf '\n'
        cat "$SSHD_MAIN_CONF"
    } > "$tmp" || { rm -f "$tmp"; return 1; }

    if ! install_ssh_config_atomically "$tmp" "$SSHD_MAIN_CONF" 644; then
        rm -f "$tmp"
        return 1
    fi
    rm -f "$tmp"
    sshd_dropin_include_available
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
    local failed=0 mode

    if [ -n "$main_backup" ] && [ -e "$main_backup" ]; then
        mode="$(stat -c '%a' "$main_backup" 2>/dev/null || true)"
        install_ssh_config_atomically "$main_backup" "$SSHD_MAIN_CONF" "$mode" || {
            warn "恢复 $SSHD_MAIN_CONF 失败。"
            failed=1
        }
    fi
    if [ -n "$dropin_backup" ] && [ -e "$dropin_backup" ]; then
        mode="$(stat -c '%a' "$dropin_backup" 2>/dev/null || true)"
        install_ssh_config_atomically "$dropin_backup" "$dropin_path" "$mode" || {
            warn "恢复 $dropin_path 失败。"
            failed=1
        }
    else
        rm -f "$dropin_path" || {
            warn "删除 $dropin_path 失败。"
            failed=1
        }
    fi
    return "$failed"
}

set_main_ssh_port_directives() {
    local tmp

    tmp="$(mktemp)" || return 1
    awk -v port="$SSH_TARGET_PORT" '
        /^[[:space:]]*Port[[:space:]]+/ {
            print "Port " port
            changed=1
            next
        }
        { print }
        END {
            if (!changed) print "Port " port
        }
    ' "$SSHD_MAIN_CONF" > "$tmp" || { rm -f "$tmp"; return 1; }
    install_ssh_config_atomically "$tmp" "$SSHD_MAIN_CONF" 644 ||
        { rm -f "$tmp"; return 1; }
    rm -f "$tmp"
}

write_vpsbox_ssh_port_config() {
    local tmp

    mkdir -p "$SSHD_CONFIG_DIR" || return 1
    tmp="$(mktemp)" || return 1
    cat > "$tmp" <<EOF || { rm -f "$tmp"; return 1; }
# Managed by vpsbox
Port $SSH_TARGET_PORT
EOF
    install_ssh_config_atomically "$tmp" "$SSHD_VPSBOX_PORT_CONF" 644 ||
        { rm -f "$tmp"; return 1; }
    rm -f "$tmp"
}

write_vpsbox_ssh_hardening_config() {
    local tmp

    mkdir -p "$SSHD_CONFIG_DIR" || return 1
    tmp="$(mktemp)" || return 1
    cat > "$tmp" <<'EOF' || { rm -f "$tmp"; return 1; }
# Managed by vpsbox
LoginGraceTime 1m
StrictModes yes
PubkeyAuthentication yes
PermitEmptyPasswords no
UsePAM yes
UseDNS no
EOF
    install_ssh_config_atomically "$tmp" "$SSHD_VPSBOX_HARDENING_CONF" 644 ||
        { rm -f "$tmp"; return 1; }
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
    local port="$1" socket_ports

    command -v ss >/dev/null 2>&1 || return 1
    if ss -H -tlnp 2>/dev/null | awk -v port="$port" '
        $4 ~ (":" port "$") && $0 ~ /"sshd"/ { found=1 }
        END { exit(found ? 0 : 1) }
    '; then
        return 0
    fi

    if ssh_socket_activation_active; then
        socket_ports="$(ssh_socket_activation_ports_csv)" || return 1
        csv_contains_port "$socket_ports" "$port" || return 1
        ss -H -tln 2>/dev/null | awk -v port="$port" '
            $4 ~ (":" port "$") { found=1 }
            END { exit(found ? 0 : 1) }
        '
        return $?
    fi
    return 1
}

ssh_effective_ports_listening() {
    local ports port
    local IFS=,

    ports="$(ssh_effective_ports_csv)" || return 1
    for port in $ports; do
        ssh_listener_on_port "$port" || return 1
    done
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

wait_for_any_ssh_listener_csv() {
    local ports="$1" port
    local IFS=,

    for port in $ports; do
        wait_for_ssh_listener "$port" && return 0
    done
    return 1
}

ssh_connection_server_port() {
    local client_ip client_port server_ip server_port extra

    [ -n "${SSH_CONNECTION:-}" ] || return 1
    read -r client_ip client_port server_ip server_port extra <<< "$SSH_CONNECTION"
    [ -n "$client_ip" ] && [ -n "$client_port" ] && [ -n "$server_ip" ] &&
        [ -z "${extra:-}" ] && is_valid_port "$server_port" || return 1
    printf '%s\n' "$server_port"
}

ssh_socket_activation_ports_csv() {
    local unit output ports="" parsed active=0

    is_systemd || return 1
    for unit in ssh.socket sshd.socket; do
        systemctl is-active --quiet "$unit" 2>/dev/null || continue
        active=1
        output="$(systemctl show "$unit" --property=Listen --value 2>/dev/null)" || return 1
        parsed="$(printf '%s\n' "$output" | awk '
            {
                for (i = 1; i < NF; i++) {
                    token = $i
                    sub(/^Listen=/, "", token)
                    if ($(i + 1) != "(Stream)") continue
                    if (token ~ /^[0-9]+$/ ||
                        token ~ /^\[[^][]+\]:[0-9]+$/ ||
                        token ~ /^[*A-Za-z0-9_.-]+:[0-9]+$/) {
                        sub(/^.*:/, "", token)
                        print token
                    }
                }
            }
        ')" || return 1
        [ -n "$parsed" ] || return 1
        ports="$(merge_port_csv "$ports" "$(printf '%s\n' "$parsed" | paste -sd, -)")" || return 1
    done
    [ "$active" -eq 1 ] && [ -n "$ports" ] || return 1
    printf '%s\n' "$ports"
}

ssh_listening_ports_csv() {
    local output ports socket_ports connection_port

    command -v ss >/dev/null 2>&1 || return 1
    output="$(ss -H -tlnp 2>/dev/null)" || return 1
    ports="$(printf '%s\n' "$output" | awk '
        /"sshd"/ {
            address=$4
            sub(/^.*:/, "", address)
            if (address ~ /^[0-9]+$/) print address
        }
    ' | paste -sd, -)" || return 1
    connection_port="$(ssh_connection_server_port 2>/dev/null || true)"
    if ssh_socket_activation_active; then
        socket_ports="$(ssh_socket_activation_ports_csv)" || return 1
    else
        socket_ports=""
    fi
    ports="$(merge_port_csv "$ports" "$socket_ports" "$connection_port")" || return 1
    [ -n "$ports" ] || return 1
    printf '%s\n' "$ports"
}

ssh_firewall_transition_begin() {
    local tcp_ports="$1"

    [ "${ACTIVE_SSH_FIREWALL_TRANSITION:-0}" = "0" ] || {
        err "已有未完成的 SSH 防火墙端口切换。"
        return 1
    }
    ACTIVE_SSH_FIREWALL_TRANSITION=1
    if ! firewall_prepare_port_transition "$tcp_ports" ""; then
        ACTIVE_SSH_FIREWALL_TRANSITION=0
        return 1
    fi
}

ssh_firewall_transition_abort() {
    # SSH 的事务前防火墙快照可能早已落后于 sshd；按配置与实际监听并集重算更安全。
    ssh_firewall_transition_reconcile
}

ssh_firewall_transition_finish() {
    firewall_complete_port_transition || return 1
    ACTIVE_SSH_FIREWALL_TRANSITION=0
}

ssh_firewall_transition_reconcile() {
    local configured_ports listening_ports safe_ports transition_dir

    [ "${ACTIVE_SSH_FIREWALL_TRANSITION:-0}" = "1" ] || return 0
    configured_ports="$(ssh_effective_ports_csv 2>/dev/null || true)"
    listening_ports="$(ssh_listening_ports_csv 2>/dev/null || true)"
    safe_ports="$(merge_port_csv "$configured_ports" "$listening_ports")" || return 1
    [ -n "$safe_ports" ] || return 1
    firewall_sync_active_config "$safe_ports" "" 1 || return 1
    transition_dir="${ACTIVE_FIREWALL_TRANSITION_DIR:-}"
    if [ -n "$transition_dir" ]; then
        firewall_discard_port_transition || return 1
    fi
    ACTIVE_SSH_FIREWALL_TRANSITION=0
}

firewall_settle_pending_port_transition() {
    if [ -n "${ACTIVE_NODE_BACKUP:-}" ]; then
        warn "检测到未完成的节点端口事务，正在先恢复节点与防火墙状态。"
        rollback_active_node_transaction || return 1
    fi
    if [ "${ACTIVE_SSH_FIREWALL_TRANSITION:-0}" = "1" ]; then
        warn "检测到未完成的 SSH 端口事务，正在保留配置端口与实际监听端口的安全并集。"
        ssh_firewall_transition_reconcile || {
            err "SSH 端口事务无法安全对账，已拒绝继续修改主机防火墙。"
            return 1
        }
    elif [ -n "${ACTIVE_FIREWALL_TRANSITION_DIR:-}" ]; then
        warn "检测到未完成的端口事务，正在恢复事务前的防火墙配置。"
        firewall_abort_port_transition || {
            err "未完成的端口事务无法恢复，已拒绝继续修改主机防火墙。"
            return 1
        }
    fi
    [ -z "${ACTIVE_NODE_BACKUP:-}" ] &&
        [ "${ACTIVE_SSH_FIREWALL_TRANSITION:-0}" = "0" ] &&
        [ -z "${ACTIVE_FIREWALL_TRANSITION_DIR:-}" ]
}

ssh_socket_activation_active() {
    is_systemd && { systemctl is-active --quiet ssh.socket 2>/dev/null || systemctl is-active --quiet sshd.socket 2>/dev/null; }
}

ssh_socket_activation_enabled_or_active() {
    local unit

    is_systemd || return 1
    for unit in ssh.socket sshd.socket; do
        if systemctl is-active --quiet "$unit" 2>/dev/null ||
            systemctl is-enabled --quiet "$unit" 2>/dev/null; then
            return 0
        fi
    done
    return 1
}

choose_ssh_target_port() {
    local input confirm docker_ports status

    command -v ss >/dev/null 2>&1 || {
        err "缺少 ss，无法可靠检查 SSH 端口占用。"
        return 1
    }
    ssh_effective_ports_csv >/dev/null 2>&1 || {
        err "无法读取 SSH 当前生效端口，已取消修改。"
        return 1
    }

    docker_ports="$(docker_reserved_ports_for_port_choice tcp)" || {
        err "无法可靠读取 Docker 已发布端口，已取消 SSH 端口选择。"
        return 1
    }

    while true; do
        read -r -p "请输入新 SSH 端口（1-65535，留空默认 23333）: " input || return 1
        input="${input:-23333}"
        is_valid_port "$input" || { err "端口必须是 1-65535 的整数。"; continue; }
        if port_is_effective_ssh_port "$input"; then
            status=0
        else
            status=$?
            if [ "$status" -ne 1 ]; then
                err "无法读取 SSH 当前生效端口，已取消修改。"
                return 1
            fi
            if port_in_use_tcp "$input"; then
                err "端口 $input 已被占用，请更换。"
                continue
            else
                status=$?
                if [ "$status" -ne 1 ]; then
                    err "无法检查端口 $input 的监听状态，已取消修改。"
                    return 1
                fi
            fi
        fi
        if [ "$status" -ne 0 ] && csv_contains_port "$docker_ports" "$input"; then
            err "端口 $input 已被 Docker 发布规则占用，请更换。"
            continue
        fi
        if [ "$input" -lt 1024 ]; then
            read -r -p "端口 $input 属于特权端口，输入 YES 确认使用: " confirm
            [ "$confirm" = "YES" ] || continue
        fi
        printf '%s\n' "$input"
        return 0
    done
}

clear_ssh_change_tracking() {
    local failed=0

    clear_change_tracking SSHD_MAIN || failed=1
    clear_change_tracking SSHD_PORT || failed=1
    clear_change_tracking SSHD_HARDENING || failed=1
    manifest_remove APPLIED_SSH_CONFIG || failed=1
    manifest_remove SSH_PORTS || failed=1
    return "$failed"
}

cleanup_unapplied_ssh_tracking() {
    local applied_before="$1"

    if [ "$applied_before" = "1" ]; then
        ACTIVE_UNAPPLIED_SSH_TRACKING=0
        return 0
    fi
    if clear_ssh_change_tracking; then
        ACTIVE_UNAPPLIED_SSH_TRACKING=0
        return 0
    fi
    ACTIVE_UNAPPLIED_SSH_TRACKING=1
    return 1
}

ssh_unapplied_tracking_present() {
    local key

    [ "$(manifest_value APPLIED_SSH_CONFIG 2>/dev/null || true)" != "1" ] || return 1
    for key in BACKUP_SSHD_MAIN BACKUP_SSHD_PORT BACKUP_SSHD_HARDENING SSH_PORTS; do
        manifest_value "$key" >/dev/null 2>&1 && return 0
    done
    [ -e "$CHANGE_BACKUP_DIR/SSHD_MAIN" ] || [ -L "$CHANGE_BACKUP_DIR/SSHD_MAIN" ] ||
        [ -e "$CHANGE_BACKUP_DIR/SSHD_PORT" ] || [ -L "$CHANGE_BACKUP_DIR/SSHD_PORT" ] ||
        [ -e "$CHANGE_BACKUP_DIR/SSHD_HARDENING" ] || [ -L "$CHANGE_BACKUP_DIR/SSHD_HARDENING" ]
}

settle_stale_unapplied_ssh_tracking() {
    if [ "${ACTIVE_UNAPPLIED_SSH_TRACKING:-0}" != "1" ] &&
        ! ssh_unapplied_tracking_present; then
        return 0
    fi
    # v1.0.22 起 SSH 配置只会在 APPLIED_SSH_CONFIG 成功落盘后写入；
    # 因此无 APPLIED 标记的残留仅是中断的首次基线，可安全清理后重新采集。
    if cleanup_unapplied_ssh_tracking 0; then
        return 0
    fi
    err "检测到未应用且无法清理的 SSH 恢复基线，已拒绝继续修改。"
    return 1
}

rollback_ssh_port_change() {
    local main_backup="$1" dropin_backup="$2" original_ports="$3"
    local applied_before="${4:-1}" bin

    if ! restore_ssh_config_backup "$main_backup" "$SSHD_VPSBOX_PORT_CONF" "$dropin_backup"; then
        err "SSH 配置文件回滚失败，请通过控制台恢复。"
        ssh_firewall_transition_reconcile ||
            warn "无法自动对账 SSH 端口；临时防火墙规则已保留，请勿关闭当前连接。"
        return 1
    fi
    bin="$(sshd_binary)" || { err "SSH 回滚后未找到 sshd，请通过控制台恢复。"; return 1; }
    if ! "$bin" -t; then
        err "SSH 回滚后的配置校验失败，请通过控制台恢复。"
        ssh_firewall_transition_reconcile ||
            warn "无法自动对账 SSH 端口；临时防火墙规则已保留，请勿关闭当前连接。"
        return 1
    fi
    if ! restart_ssh_service; then
        err "SSH 回滚后服务无法重启，请通过控制台恢复。"
        ssh_firewall_transition_reconcile ||
            warn "无法自动对账 SSH 端口；临时防火墙规则已保留，请勿关闭当前连接。"
        return 1
    fi
    if [ -n "$original_ports" ] && ! wait_for_any_ssh_listener_csv "$original_ports"; then
        err "SSH 回滚后未恢复原端口监听（$original_ports），请通过控制台恢复。"
        ssh_firewall_transition_reconcile ||
            warn "无法自动对账 SSH 端口；临时防火墙规则已保留，请勿关闭当前连接。"
        return 1
    fi
    if declare -F ssh_firewall_transition_abort >/dev/null 2>&1 && ! ssh_firewall_transition_abort; then
        err "SSH 已回滚，但主机防火墙未能恢复修改前的端口规则。"
        return 1
    fi
    if [ "$applied_before" != "1" ]; then
        # 首次 SSH 事务失败时必须同时清掉备份基线和端口记录；若此前已成功应用过，
        # 则保留旧版本也会读取的 BACKUP_SSHD_* / SSH_PORTS，供恢复菜单继续回退。
        if ! clear_ssh_change_tracking; then
            err "SSH 已回滚，但无法清理首次事务记录；恢复菜单仍会保留该项目。"
            return 1
        fi
    fi
    return 0
}

rollback_ssh_hardening_change() {
    local main_backup="$1" dropin_backup="$2" applied_before="$3"
    local restart_required="${4:-0}"
    local expected_ports="${5:-}"

    restore_ssh_config_backup "$main_backup" "$SSHD_VPSBOX_HARDENING_CONF" "$dropin_backup" ||
        return 1
    if [ "$restart_required" = "1" ] && ! restart_ssh_service; then
        return 1
    fi
    if [ "$restart_required" = "1" ] && [ -n "$expected_ports" ] &&
        ! wait_for_any_ssh_listener_csv "$expected_ports"; then
        return 1
    fi
    if [ "$applied_before" != "1" ]; then
        # 与端口修改共用同一份旧版恢复基线，首次加固失败也不能留下过期备份。
        clear_ssh_change_tracking || return 1
    fi
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

restore_fail2ban_sshd_config_file() {
    local backup="$1"
    local mode

    if [ -n "$backup" ]; then
        [ -f "$backup" ] && [ ! -L "$backup" ] || return 1
        mode="$(stat -c '%a' "$backup" 2>/dev/null)" || return 1
        install_root_file_atomically "$backup" "$FAIL2BAN_VPSBOX_SSHD_CONF" "$mode"
    else
        [ ! -L "$FAIL2BAN_VPSBOX_SSHD_CONF" ] || return 1
        if [ -e "$FAIL2BAN_VPSBOX_SSHD_CONF" ] &&
            [ ! -f "$FAIL2BAN_VPSBOX_SSHD_CONF" ]; then
            return 1
        fi
        rm -f -- "$FAIL2BAN_VPSBOX_SSHD_CONF"
    fi
}

restore_fail2ban_sshd_sync_state() {
    local backup="$1" was_running="$2"

    restore_fail2ban_sshd_config_file "$backup" || return 1
    fail2ban-client -t -c /etc/fail2ban >/dev/null 2>&1 || return 1

    if is_systemd; then
        if [ "$was_running" -eq 1 ]; then
            retry 3 1 systemctl restart fail2ban >/dev/null
        else
            retry 3 1 systemctl stop fail2ban >/dev/null
        fi
    elif command -v rc-service >/dev/null 2>&1; then
        if [ "$was_running" -eq 1 ]; then
            retry 3 1 rc-service fail2ban restart >/dev/null
        else
            retry 3 1 rc-service fail2ban stop >/dev/null
        fi
    else
        return 1
    fi
}

fail2ban_sync_failure_with_rollback() {
    local reason="$1" backup="$2" was_running="$3"

    if restore_fail2ban_sshd_sync_state "$backup" "$was_running"; then
        err "$reason，已恢复同步前的配置与服务状态。"
    else
        err "$reason，且同步前状态未能完整恢复，请检查服务与配置。"
    fi
    return 1
}

restore_fail2ban_runtime_after_sync() {
    local was_running="$1"

    [ "$was_running" -eq 0 ] || return 0
    if is_systemd; then
        retry 3 1 systemctl stop fail2ban >/dev/null || return 1
    elif command -v rc-service >/dev/null 2>&1; then
        retry 3 1 rc-service fail2ban stop >/dev/null || return 1
    else
        return 1
    fi
    [ "$(fail2ban_service_state)" != "运行中" ]
}

prune_fail2ban_sshd_backups() {
    local backup nullglob_was_set=0
    local -a backups

    shopt -q nullglob && nullglob_was_set=1
    shopt -s nullglob
    backups=("${FAIL2BAN_VPSBOX_SSHD_CONF}.bak."*)
    [ "$nullglob_was_set" -eq 1 ] || shopt -u nullglob
    while [ "${#backups[@]}" -gt 5 ]; do
        backup="${backups[0]}"
        [ -f "$backup" ] && [ ! -L "$backup" ] || return 1
        rm -f -- "$backup" || return 1
        backups=("${backups[@]:1}")
    done
}

sync_fail2ban_sshd_port() {
    local backup=""
    local backend="auto"
    local ports
    local service_action
    local tmp
    local was_running=0

    if ! fail2ban_installed; then
        return 0
    fi
    if fail2ban_sshd_configuration_healthy; then
        info "Fail2ban SSH 防护配置已是当前状态，无需重复同步。"
        return 0
    fi
    [ "$(fail2ban_service_state)" = "运行中" ] && was_running=1
    manifest_set_once FAIL2BAN_ACTIVE "$([ "$was_running" -eq 1 ] && echo active || echo inactive)" || return 1
    if fail2ban_service_is_enabled; then
        manifest_set_once FAIL2BAN_ENABLED enabled || return 1
    else
        manifest_set_once FAIL2BAN_ENABLED disabled || return 1
    fi

    mkdir -p "$FAIL2BAN_CONFIG_DIR" || return 1
    if [ -L "$FAIL2BAN_VPSBOX_SSHD_CONF" ] ||
        { [ -e "$FAIL2BAN_VPSBOX_SSHD_CONF" ] && [ ! -f "$FAIL2BAN_VPSBOX_SSHD_CONF" ]; }; then
        err "Fail2ban SSH 防护配置路径不安全，已拒绝修改：$FAIL2BAN_VPSBOX_SSHD_CONF"
        return 1
    fi
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
    begin_change_transaction FAIL2BAN_SSHD || { err "记录 Fail2ban 修改事务失败，已取消修改。"; return 1; }

    tmp="$(mktemp "$FAIL2BAN_CONFIG_DIR/.vpsbox-sshd.XXXXXX")" || return 1
    render_fail2ban_sshd_config "$ports" "$backend" > "$tmp" || {
        rm -f "$tmp"
        return 1
    }
    chmod 644 "$tmp" || { rm -f "$tmp"; return 1; }

    if ! mv -f "$tmp" "$FAIL2BAN_VPSBOX_SSHD_CONF"; then
        rm -f -- "$tmp"
        return 1
    fi
    if ! fail2ban-client -t -c /etc/fail2ban >/dev/null 2>&1; then
        fail2ban_sync_failure_with_rollback "Fail2ban 配置预检失败" "$backup" "$was_running" || true
        return 1
    fi

    if is_systemd; then
        if [ "$was_running" -eq 1 ]; then
            service_action="restart"
        else
            service_action="start"
        fi
        if ! retry 3 2 systemctl "$service_action" fail2ban; then
            fail2ban_sync_failure_with_rollback \
                "Fail2ban 服务启动或重启失败" "$backup" "$was_running" || true
            return 1
        fi
    elif command -v rc-service >/dev/null 2>&1; then
        if [ "$was_running" -eq 1 ]; then
            service_action="restart"
        else
            service_action="start"
        fi
        if ! retry 3 2 rc-service fail2ban "$service_action"; then
            fail2ban_sync_failure_with_rollback \
                "Fail2ban 服务启动或重启失败" "$backup" "$was_running" || true
            return 1
        fi
    else
        fail2ban_sync_failure_with_rollback \
            "未找到 Fail2ban 服务启动或重启方式" "$backup" "$was_running" || true
        return 1
    fi

    if ! retry 5 1 fail2ban-client status sshd >/dev/null 2>&1; then
        fail2ban_sync_failure_with_rollback \
            "Fail2ban 服务已启动，但 sshd jail 未在预期时间内就绪" \
            "$backup" "$was_running" || true
        return 1
    fi
    if verify_fail2ban_real_ban; then
        :
    else
        service_action=$?
        if [ "$service_action" -eq 2 ] || [ -n "${ACTIVE_FAIL2BAN_TEST_IP:-}" ]; then
            err "Fail2ban 真实封禁验证失败，且测试地址仍有残留；为保留解封能力，暂不回滚当前 jail。"
        elif restore_fail2ban_sshd_sync_state "$backup" "$was_running"; then
            err "Fail2ban 真实封禁验证失败，已恢复同步前的配置与服务状态。"
        else
            err "Fail2ban 真实封禁验证失败，且同步前状态未能完整恢复，请检查服务与配置。"
        fi
        return 1
    fi
    if ! restore_fail2ban_runtime_after_sync "$was_running"; then
        err "Fail2ban 配置验证通过，但无法恢复同步前的停止状态。"
        return 1
    fi
    if ! mark_change_applied FAIL2BAN_SSHD; then
        fail2ban_sync_failure_with_rollback \
            "Fail2ban 防护已验证，但无法记录已应用状态" "$backup" "$was_running" || true
        return 1
    fi
    # 旧版本曾使用该文件名；新文件按字典序后加载并已验证生效，因此旧文件清理失败
    # 只保留为兼容残留，不应把已成功应用的防护状态误报为失败。
    rm -f "$FAIL2BAN_CONFIG_DIR/99-vpsbox-sshd-port.local" ||
        warn "旧版 Fail2ban SSH 端口配置未能清理，可稍后手动删除。"
    prune_fail2ban_sshd_backups || warn "Fail2ban 历史备份清理不完整，最多保留 5 份的策略未完全执行。"
}

apply_ssh_port_change() {
    local confirm new_port original_ports retired_ports write_action
    local suffix
    local main_backup=""
    local dropin_backup=""
    local ssh_change_was_applied=0
    local vpsbox_firewall_active=0

    if ! sshd_binary >/dev/null 2>&1; then
        err "未找到 sshd，无法修改 SSH 配置。"
        return 1
    fi

    if [ ! -f "$SSHD_MAIN_CONF" ]; then
        err "未找到 SSH 主配置：$SSHD_MAIN_CONF"
        return 1
    fi

    if ssh_socket_activation_enabled_or_active; then
        err "检测到 SSH socket activation 正在运行或已启用；为避免重启后端口错配，当前不自动修改。"
        err "请先通过控制台处理 ssh.socket/sshd.socket，或关闭 socket activation 后重试。"
        return 1
    fi
    settle_stale_unapplied_ssh_tracking || return 1

    new_port="$(choose_ssh_target_port)" || { info "已取消。"; return 0; }
    SSH_TARGET_PORT="$new_port"

    if ssh_effective_ports_match_target; then
        info "SSH 端口已经是 $SSH_TARGET_PORT，无需重复修改。"
        read -r -p "仍要重新写入并重启 SSH？[y/N]: " confirm
        case "$confirm" in
            y|Y|yes|YES) ;;
            *) info "已取消重复修改。"; return 0 ;;
        esac
    fi

    if firewall_runtime_enabled; then
        vpsbox_firewall_active=1
        read -r -p "vpsbox 防火墙将自动临时放行 TCP $SSH_TARGET_PORT；如厂商另有安全组，请先在厂商面板放行。输入 YES 继续: " confirm
    else
        read -r -p "确认已在商家安全组或其他外部防火墙放行 TCP $SSH_TARGET_PORT？输入 YES 继续: " confirm
    fi
    if [ "$confirm" != "YES" ]; then
        info "已取消，未修改 SSH 配置。"
        return 0
    fi

    [ "$(manifest_value APPLIED_SSH_CONFIG 2>/dev/null || true)" = "1" ] &&
        ssh_change_was_applied=1
    [ "$ssh_change_was_applied" = "1" ] || ACTIVE_UNAPPLIED_SSH_TRACKING=1
    if ! backup_change_file_once SSHD_MAIN "$SSHD_MAIN_CONF" ||
        ! backup_change_file_once SSHD_PORT "$SSHD_VPSBOX_PORT_CONF" ||
        ! backup_change_file_once SSHD_HARDENING "$SSHD_VPSBOX_HARDENING_CONF"; then
        cleanup_unapplied_ssh_tracking "$ssh_change_was_applied" ||
            warn "SSH 尚未修改，但首次恢复基线清理不完整。"
        return 1
    fi
    original_ports="$(ssh_effective_ports_csv)" || {
        cleanup_unapplied_ssh_tracking "$ssh_change_was_applied" ||
            warn "SSH 尚未修改，但首次恢复基线清理不完整。"
        err "无法读取 SSH 当前生效端口，已取消修改。"
        return 1
    }
    retired_ports="$(csv_remove_port "$original_ports" "$SSH_TARGET_PORT")" || {
        cleanup_unapplied_ssh_tracking "$ssh_change_was_applied" ||
            warn "SSH 尚未修改，但首次恢复基线清理不完整。"
        err "无法计算 SSH 旧端口，已取消修改。"
        return 1
    }
    if ! manifest_set_once SSH_PORTS "$original_ports"; then
        cleanup_unapplied_ssh_tracking "$ssh_change_was_applied" ||
            warn "SSH 尚未修改，但首次恢复基线清理不完整。"
        return 1
    fi

    suffix="$(date +%F-%H%M%S)"
    if ! main_backup="$(backup_ssh_file "$SSHD_MAIN_CONF" "$suffix")"; then
        cleanup_unapplied_ssh_tracking "$ssh_change_was_applied" ||
            warn "SSH 尚未修改，但首次恢复基线清理不完整。"
        err "备份 $SSHD_MAIN_CONF 失败，已取消修改。"
        return 1
    fi
    if ! dropin_backup="$(backup_ssh_file "$SSHD_VPSBOX_PORT_CONF" "$suffix")"; then
        cleanup_unapplied_ssh_tracking "$ssh_change_was_applied" ||
            warn "SSH 尚未修改，但首次恢复基线清理不完整。"
        err "备份 $SSHD_VPSBOX_PORT_CONF 失败，已取消修改。"
        return 1
    fi
    if ! ssh_firewall_transition_begin "$SSH_TARGET_PORT"; then
        cleanup_unapplied_ssh_tracking "$ssh_change_was_applied" ||
            warn "SSH 尚未修改，但首次恢复基线清理不完整。"
        err "主机防火墙无法临时放行 SSH 新端口，已取消修改。"
        return 1
    fi
    # 在首次写入 SSH 配置前可靠落盘；若 Ctrl+C 发生在写入、校验或重启期间，
    # 恢复菜单仍能识别并恢复原配置，不会留下“已修改但未记录”的状态。
    if ! mark_change_applied SSH_CONFIG; then
        ssh_firewall_transition_abort || true
        cleanup_unapplied_ssh_tracking "$ssh_change_was_applied" ||
            warn "SSH 尚未修改，但首次恢复基线清理不完整。"
        err "无法记录 SSH 配置事务，已取消修改。"
        return 1
    fi
    ACTIVE_UNAPPLIED_SSH_TRACKING=0

    if { [ -e "$SSHD_VPSBOX_PORT_CONF" ] && sshd_vpsbox_port_include_available; } || { ! sshd_main_has_active_port_directive && sshd_vpsbox_port_include_available; }; then
        write_action="vpsbox drop-in"
        write_vpsbox_ssh_port_config || {
            err "写入 SSH drop-in 失败，正在回滚。"
            rollback_ssh_port_change "$main_backup" "$dropin_backup" "$original_ports" "$ssh_change_was_applied" || true
            return 1
        }
    else
        write_action="主配置"
        set_main_ssh_port_directives || {
            err "写入 SSH 主配置失败，正在回滚。"
            rollback_ssh_port_change "$main_backup" "$dropin_backup" "$original_ports" "$ssh_change_was_applied" || true
            return 1
        }
    fi

    if ! validate_ssh_port_effective_config; then
        err "SSH 端口配置验证失败，正在回滚。"
        rollback_ssh_port_change "$main_backup" "$dropin_backup" "$original_ports" "$ssh_change_was_applied" || true
        return 1
    fi

    if ! restart_ssh_service; then
        err "SSH 服务重启失败，正在回滚配置。"
        rollback_ssh_port_change "$main_backup" "$dropin_backup" "$original_ports" "$ssh_change_was_applied" || true
        return 1
    fi

    if ! wait_for_ssh_listener "$SSH_TARGET_PORT"; then
        err "SSH 重启后未检测到 sshd 监听端口 $SSH_TARGET_PORT，正在回滚。"
        rollback_ssh_port_change "$main_backup" "$dropin_backup" "$original_ports" "$ssh_change_was_applied" || true
        return 1
    fi
    if ! ssh_firewall_transition_finish; then
        err "主机防火墙无法同步 SSH 新端口，正在回滚配置。"
        rollback_ssh_port_change "$main_backup" "$dropin_backup" "$original_ports" "$ssh_change_was_applied" || true
        return 1
    fi

    info "SSH 配置写入位置：$write_action"

    warn_ssh_access_controls

    if sync_fail2ban_sshd_port; then
        fail2ban_installed && info "Fail2ban sshd 端口已同步为 $SSH_TARGET_PORT。"
    else
        warn "Fail2ban sshd 端口同步失败，请稍后检查 fail2ban-client status sshd。"
    fi

    info "SSH 端口已修改为 $SSH_TARGET_PORT。"
    [ -n "$main_backup" ] && info "主配置备份：$main_backup"
    [ -n "$dropin_backup" ] && info "vpsbox SSH 端口配置备份：$dropin_backup"
    warn "不要关闭当前 SSH 窗口。"
    warn "请另开一个新窗口测试：ssh -p $SSH_TARGET_PORT root@你的服务器IP"
    if [ -n "$retired_ports" ]; then
        if [ "$vpsbox_firewall_active" -eq 1 ]; then
            warn "确认新端口可以登录后，请在新 SSH 会话再次更新 vpsbox 防火墙，以移除可能因旧会话暂时保留的端口（$retired_ports）。"
            warn "如果厂商安全组仍放行旧端口（$retired_ports），届时也可在厂商面板关闭。"
        else
            warn "确认新端口可以登录后，再在商家安全组或其他外部防火墙关闭旧端口（$retired_ports）。"
        fi
    fi
}

ssh_port_change_firewall_hint() {
    if firewall_runtime_enabled; then
        echo "vpsbox 防火墙运行中，新端口将自动临时放行并同步。"
        echo "如厂商另有安全组，仍需先在厂商面板放行新端口。"
    else
        echo "请先在商家安全组或其他外部防火墙放行即将输入的 TCP 端口。"
    fi
}

apply_ssh_basic_hardening() {
    local confirm
    local suffix
    local main_backup=""
    local dropin_backup=""
    local original_ports
    local ssh_change_was_applied=0

    if ! sshd_binary >/dev/null 2>&1; then
        err "未找到 sshd，无法修改 SSH 配置。"
        return 1
    fi

    if [ ! -f "$SSHD_MAIN_CONF" ]; then
        err "未找到 SSH 主配置：$SSHD_MAIN_CONF"
        return 1
    fi
    settle_stale_unapplied_ssh_tracking || return 1

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

    [ "$(manifest_value APPLIED_SSH_CONFIG 2>/dev/null || true)" = "1" ] &&
        ssh_change_was_applied=1
    [ "$ssh_change_was_applied" = "1" ] || ACTIVE_UNAPPLIED_SSH_TRACKING=1
    if ! backup_change_file_once SSHD_MAIN "$SSHD_MAIN_CONF" ||
        ! backup_change_file_once SSHD_PORT "$SSHD_VPSBOX_PORT_CONF" ||
        ! backup_change_file_once SSHD_HARDENING "$SSHD_VPSBOX_HARDENING_CONF"; then
        cleanup_unapplied_ssh_tracking "$ssh_change_was_applied" ||
            warn "SSH 尚未修改，但首次恢复基线清理不完整。"
        return 1
    fi
    original_ports="$(ssh_effective_ports_csv)" || {
        cleanup_unapplied_ssh_tracking "$ssh_change_was_applied" ||
            warn "SSH 尚未修改，但首次恢复基线清理不完整。"
        err "无法读取 SSH 当前生效端口，已取消加固。"
        return 1
    }
    if ! manifest_set_once SSH_PORTS "$original_ports"; then
        cleanup_unapplied_ssh_tracking "$ssh_change_was_applied" ||
            warn "SSH 尚未修改，但首次恢复基线清理不完整。"
        return 1
    fi

    suffix="$(date +%F-%H%M%S)"
    if ! main_backup="$(backup_ssh_file "$SSHD_MAIN_CONF" "$suffix")"; then
        cleanup_unapplied_ssh_tracking "$ssh_change_was_applied" ||
            warn "SSH 尚未修改，但首次恢复基线清理不完整。"
        err "备份 $SSHD_MAIN_CONF 失败，已取消修改。"
        return 1
    fi
    if ! dropin_backup="$(backup_ssh_file "$SSHD_VPSBOX_HARDENING_CONF" "$suffix")"; then
        cleanup_unapplied_ssh_tracking "$ssh_change_was_applied" ||
            warn "SSH 尚未修改，但首次恢复基线清理不完整。"
        err "备份 $SSHD_VPSBOX_HARDENING_CONF 失败，已取消修改。"
        return 1
    fi
    # 与端口修改使用同一恢复标记，确保交互中断后仍可从恢复菜单回到原配置。
    mark_change_applied SSH_CONFIG || {
        cleanup_unapplied_ssh_tracking "$ssh_change_was_applied" ||
            warn "SSH 尚未修改，但首次恢复基线清理不完整。"
        err "无法记录 SSH 配置事务，已取消修改。"
        return 1
    }
    ACTIVE_UNAPPLIED_SSH_TRACKING=0

    if ! write_vpsbox_ssh_hardening_config || ! ensure_sshd_dropin_include; then
        err "写入 SSH 基础加固配置失败，正在回滚。"
        rollback_ssh_hardening_change "$main_backup" "$dropin_backup" "$ssh_change_was_applied" 0 "$original_ports" ||
            warn "SSH 配置未能完整回滚，恢复标记已保留。"
        return 1
    fi

    if ! validate_ssh_hardening_effective_config; then
        err "SSH 基础加固配置验证失败，正在回滚。"
        rollback_ssh_hardening_change "$main_backup" "$dropin_backup" "$ssh_change_was_applied" 0 "$original_ports" ||
            warn "SSH 配置未能完整回滚，恢复标记已保留。"
        return 1
    fi

    if ! restart_ssh_service; then
        err "SSH 服务重启失败，正在回滚配置并尝试恢复服务。"
        rollback_ssh_hardening_change "$main_backup" "$dropin_backup" "$ssh_change_was_applied" 1 "$original_ports" ||
            warn "SSH 配置或服务未能完整回滚，恢复标记已保留。"
        return 1
    fi

    if ! wait_for_any_ssh_listener_csv "$original_ports"; then
        err "SSH 服务重启后未恢复原端口监听（$original_ports），正在回滚配置并尝试恢复服务。"
        rollback_ssh_hardening_change "$main_backup" "$dropin_backup" "$ssh_change_was_applied" 1 "$original_ports" ||
            warn "SSH 配置或服务未能完整回滚，恢复标记已保留。"
        return 1
    fi

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
        err "未找到 sshd，无法查看 SSH 生效配置。"
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
 SSH 生效配置
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

ssh_restore_snapshot_root() {
    printf '%s\n' "$VPSBOX_STATE_DIR/ssh-restore-snapshots"
}

ssh_restore_snapshot_path_allowed() {
    local snapshot_dir="$1" root parent base

    root="$(ssh_restore_snapshot_root)"
    parent="$(dirname -- "$snapshot_dir")"
    base="${snapshot_dir##*/}"
    if [ "$parent" = "$root" ]; then
        [[ "$base" == restore.* || "$base" == .building.* ]]
    elif [ "$parent" = /tmp ]; then
        [[ "$base" == vpsbox-ssh-restore.* ]]
    else
        return 1
    fi
}

remove_ssh_restore_snapshot() {
    local snapshot_dir="$1"

    ssh_restore_snapshot_path_allowed "$snapshot_dir" &&
        [ -d "$snapshot_dir" ] && [ ! -L "$snapshot_dir" ] || return 1
    rm -rf -- "$snapshot_dir"
}

ssh_restore_snapshot_path_is_secure() {
    local path="$1" expected_mode="$2" owner group mode

    [ ! -L "$path" ] || return 1
    [ "${VPSBOX_TEST_MODE:-0}" = "1" ] && return 0
    owner="$(stat -c '%u' "$path" 2>/dev/null)" || return 1
    group="$(stat -c '%g' "$path" 2>/dev/null)" || return 1
    mode="$(stat -c '%a' "$path" 2>/dev/null)" || return 1
    [ "$owner" = "0" ] && [ "$group" = "0" ] && [ "$mode" = "$expected_mode" ]
}

ssh_restore_snapshot_manifest_entry() {
    local manifest="$1" name="$2"

    awk -F'|' -v name="$name" '
        $1 == name { line=$0; count++ }
        END {
            if (count == 1) print line
            else exit 1
        }
    ' "$manifest"
}

ssh_restore_snapshot_dir_valid() {
    local snapshot_dir="$1" root manifest name entry state mode digest path actual

    ssh_restore_snapshot_path_allowed "$snapshot_dir" &&
        [ -d "$snapshot_dir" ] && [ ! -L "$snapshot_dir" ] || return 1
    root="$(ssh_restore_snapshot_root)"
    if [[ "$snapshot_dir" == /tmp/vpsbox-ssh-restore.* ]]; then
        # 兼容 v1.0.32 及更早版本在 /tmp 创建、且没有完整性清单的 SSH 恢复快照。
        ssh_restore_snapshot_path_is_secure "$snapshot_dir" 700 || return 1
        for name in main port hardening; do
            if [ -f "$snapshot_dir/$name" ] && [ ! -L "$snapshot_dir/$name" ] &&
                [ ! -e "$snapshot_dir/$name.absent" ] && [ ! -L "$snapshot_dir/$name.absent" ]; then
                if [ "${VPSBOX_TEST_MODE:-0}" != "1" ]; then
                    mode="$(stat -c '%a' "$snapshot_dir/$name" 2>/dev/null)" || return 1
                    [[ "$mode" =~ ^[0-7]{3,4}$ ]] &&
                        [ $((8#$mode & 8#022)) -eq 0 ] || return 1
                fi
            elif [ -f "$snapshot_dir/$name.absent" ] && [ ! -L "$snapshot_dir/$name.absent" ] &&
                [ ! -e "$snapshot_dir/$name" ] && [ ! -L "$snapshot_dir/$name" ]; then
                :
            else
                return 1
            fi
        done
        return 0
    fi
    [[ "$snapshot_dir" == "$root"/restore.* ]] || return 1
    [ -d "$root" ] && [ ! -L "$root" ] &&
        ssh_restore_snapshot_path_is_secure "$root" 700 || return 1
    ssh_restore_snapshot_path_is_secure "$snapshot_dir" 700 || return 1
    manifest="$snapshot_dir/manifest"
    [ -f "$manifest" ] && [ ! -L "$manifest" ] &&
        ssh_restore_snapshot_path_is_secure "$manifest" 600 || return 1
    [ "$(awk 'END { print NR + 0 }' "$manifest")" = "3" ] || return 1
    for name in main port hardening; do
        entry="$(ssh_restore_snapshot_manifest_entry "$manifest" "$name")" || return 1
        IFS='|' read -r _ state mode digest <<< "$entry"
        case "$state" in
            file)
                [[ "$mode" =~ ^[0-7]{3,4}$ ]] &&
                    [ $((8#$mode & 8#022)) -eq 0 ] ||
                    return 1
                path="$snapshot_dir/$name"
                [ -f "$path" ] && [ ! -L "$path" ] &&
                    [ ! -e "$snapshot_dir/$name.absent" ] &&
                    ssh_restore_snapshot_path_is_secure "$path" 600 || return 1
                ;;
            absent)
                [ "$mode" = "-" ] || return 1
                path="$snapshot_dir/$name.absent"
                [ -f "$path" ] && [ ! -L "$path" ] &&
                    [ ! -e "$snapshot_dir/$name" ] &&
                    ssh_restore_snapshot_path_is_secure "$path" 600 || return 1
                ;;
            *) return 1 ;;
        esac
        [[ "$digest" =~ ^[0-9a-f]{64}$ ]] || return 1
        actual="$(sha256sum "$path" 2>/dev/null | awk '{print $1}')" || return 1
        [ "$actual" = "$digest" ] || return 1
    done
}

create_ssh_restore_snapshot() {
    local output_var="$1" root build final suffix manifest name path mode digest

    command -v sha256sum >/dev/null 2>&1 || return 1
    ensure_change_store || return 1
    root="$(ssh_restore_snapshot_root)"
    [ ! -L "$root" ] || return 1
    mkdir -p "$root" || return 1
    chown root:root "$root" || return 1
    chmod 700 "$root" || return 1
    build="$(mktemp -d "$root/.building.XXXXXX")" || return 1
    chown root:root "$build" && chmod 700 "$build" || {
        remove_ssh_restore_snapshot "$build" || true
        return 1
    }
    manifest="$build/manifest"
    for name in main port hardening; do
        case "$name" in
            main) path="$SSHD_MAIN_CONF" ;;
            port) path="$SSHD_VPSBOX_PORT_CONF" ;;
            hardening) path="$SSHD_VPSBOX_HARDENING_CONF" ;;
        esac
        if [ -f "$path" ] && [ ! -L "$path" ]; then
            mode="$(stat -c '%a' "$path" 2>/dev/null)" &&
                [[ "$mode" =~ ^[0-7]{3,4}$ ]] &&
                [ $((8#$mode & 8#022)) -eq 0 ] &&
                cp -- "$path" "$build/$name" &&
                chown root:root "$build/$name" &&
                chmod 600 "$build/$name" || {
                remove_ssh_restore_snapshot "$build" || true
                return 1
            }
            digest="$(sha256sum "$build/$name" | awk '{print $1}')" || {
                remove_ssh_restore_snapshot "$build" || true
                return 1
            }
            printf '%s|file|%s|%s\n' "$name" "$mode" "$digest" >> "$manifest" || {
                remove_ssh_restore_snapshot "$build" || true
                return 1
            }
        elif [ ! -e "$path" ] && [ ! -L "$path" ]; then
            : > "$build/$name.absent" &&
                chown root:root "$build/$name.absent" &&
                chmod 600 "$build/$name.absent" || {
                remove_ssh_restore_snapshot "$build" || true
                return 1
            }
            digest="$(sha256sum "$build/$name.absent" | awk '{print $1}')" || {
                remove_ssh_restore_snapshot "$build" || true
                return 1
            }
            printf '%s|absent|-|%s\n' "$name" "$digest" >> "$manifest" || {
                remove_ssh_restore_snapshot "$build" || true
                return 1
            }
        else
            remove_ssh_restore_snapshot "$build" || true
            return 1
        fi
    done
    chown root:root "$manifest" && chmod 600 "$manifest" || {
        remove_ssh_restore_snapshot "$build" || true
        return 1
    }
    suffix="${build##*.building.}"
    final="$root/restore.$suffix"
    [ ! -e "$final" ] && mv -- "$build" "$final" || {
        remove_ssh_restore_snapshot "$build" || true
        return 1
    }
    ssh_restore_snapshot_dir_valid "$final" || {
        remove_ssh_restore_snapshot "$final" || true
        return 1
    }
    printf -v "$output_var" '%s' "$final"
}

restore_ssh_runtime_snapshot() {
    local snapshot_dir="$1" expected_ports="$2" name path bin entry mode

    ssh_restore_snapshot_dir_valid "$snapshot_dir" || return 1
    for name in main port hardening; do
        case "$name" in
            main) path="$SSHD_MAIN_CONF" ;;
            port) path="$SSHD_VPSBOX_PORT_CONF" ;;
            hardening) path="$SSHD_VPSBOX_HARDENING_CONF" ;;
        esac
        if [ -f "$snapshot_dir/$name" ]; then
            if [[ "$snapshot_dir" == /tmp/vpsbox-ssh-restore.* ]]; then
                mode="$(stat -c '%a' "$snapshot_dir/$name" 2>/dev/null)" || return 1
            else
                entry="$(ssh_restore_snapshot_manifest_entry "$snapshot_dir/manifest" "$name")" ||
                    return 1
                IFS='|' read -r _ _ mode _ <<< "$entry"
            fi
            install_ssh_config_atomically "$snapshot_dir/$name" "$path" "$mode" || return 1
        elif [ -f "$snapshot_dir/$name.absent" ]; then
            rm -f "$path" || return 1
        else
            return 1
        fi
    done
    bin="$(sshd_binary)" || return 1
    "$bin" -t || return 1
    restart_ssh_service || return 1
    [ -z "$expected_ports" ] || wait_for_any_ssh_listener_csv "$expected_ports"
}

settle_failed_ssh_restore() {
    local snapshot_dir="$1" expected_ports="$2"

    if restore_ssh_runtime_snapshot "$snapshot_dir" "$expected_ports"; then
        if ssh_firewall_transition_abort; then
            return 0
        fi
        warn "SSH 配置与监听已回滚，但防火墙快照未能直接恢复，正在安全对账。"
    else
        warn "SSH 运行状态未完整回滚，正在保留配置端口与实际监听端口的安全并集。"
    fi
    if ssh_firewall_transition_reconcile; then
        warn "已按 SSH 配置端口与实际监听端口的并集保留防火墙放行。"
        return 0
    fi
    warn "无法自动对账 SSH 端口；临时防火墙规则已保留，请勿关闭当前连接。"
    return 1
}

restore_vpsbox_ssh_config() {
    local confirm tmp original_ports current_ports transition_ports

    [ "$(manifest_value APPLIED_SSH_CONFIG 2>/dev/null || true)" = "1" ] || {
        warn "没有已记录的 vpsbox SSH 配置可恢复。"
        return 0
    }
    original_ports="$(manifest_value SSH_PORTS 2>/dev/null || true)"
    original_ports="$(normalize_port_csv "$original_ports")" || {
        err "记录的 SSH 原端口无效，已拒绝自动恢复。"
        return 1
    }
    [ -n "$original_ports" ] || {
        err "未记录可恢复的 SSH 原端口，已拒绝自动恢复。"
        return 1
    }
    # 恢复入口必须在当前 sshd_config 已损坏时仍可使用，因此安全端口取自
    # 实际监听和当前 SSH 连接，不再依赖 sshd -T 成功。
    current_ports="$(ssh_listening_ports_csv 2>/dev/null || true)"
    current_ports="$(merge_port_csv "$current_ports" "$(ssh_connection_server_port 2>/dev/null || true)")" ||
        return 1
    transition_ports="$(merge_port_csv "$original_ports" "$current_ports")" || return 1
    [ -n "$transition_ports" ] || {
        err "无法确定待恢复或当前连接使用的 SSH 安全端口，已拒绝自动恢复。"
        return 1
    }
    echo "将恢复 SSH 主配置及 vpsbox 端口/加固 drop-in。"
    echo "预期恢复端口：${original_ports:-未知}；当前连接可能断开。"
    read -r -p "请确认已有控制台或备用连接。输入 YES 执行 SSH 恢复：" confirm
    [ "$confirm" = "YES" ] || { info "已取消 SSH 恢复。"; return 0; }
    if ! ssh_firewall_transition_begin "$transition_ports"; then
        err "主机防火墙无法临时放行待恢复的 SSH 端口，已取消恢复。"
        return 1
    fi

    if ! create_ssh_restore_snapshot tmp; then
        ssh_firewall_transition_abort || true
        err "无法创建可校验的 SSH 恢复前快照，已取消恢复。"
        return 1
    fi
    if ! restore_change_file SSHD_MAIN "$SSHD_MAIN_CONF" || ! restore_change_file SSHD_PORT "$SSHD_VPSBOX_PORT_CONF" || ! restore_change_file SSHD_HARDENING "$SSHD_VPSBOX_HARDENING_CONF" || ! "$(sshd_binary)" -t; then
        err "SSH 恢复配置校验失败，正在回滚当前配置。"
        if settle_failed_ssh_restore "$tmp" "$current_ports"; then
            remove_ssh_restore_snapshot "$tmp" ||
                warn "SSH 已回滚，但恢复前快照未能清理：$tmp"
        else
            err "SSH 自动回滚未完成，已保留本次恢复前快照：$tmp"
        fi
        return 1
    fi
    if ! restart_ssh_service || ! wait_for_any_ssh_listener_csv "$original_ports"; then
        err "SSH 服务未能在原端口恢复监听，正在回滚当前配置。"
        if settle_failed_ssh_restore "$tmp" "$current_ports"; then
            remove_ssh_restore_snapshot "$tmp" ||
                warn "SSH 已回滚，但恢复前快照未能清理：$tmp"
        else
            err "SSH 自动回滚未完成，已保留本次恢复前快照：$tmp"
        fi
        return 1
    fi
    if ! ssh_firewall_transition_finish; then
        err "主机防火墙无法同步恢复后的 SSH 端口，正在回滚当前配置。"
        if settle_failed_ssh_restore "$tmp" "$current_ports"; then
            remove_ssh_restore_snapshot "$tmp" ||
                warn "SSH 已回滚，但恢复前快照未能清理：$tmp"
        else
            err "SSH 自动回滚未完成，已保留本次恢复前快照：$tmp"
        fi
        return 1
    fi
    remove_ssh_restore_snapshot "$tmp" ||
        warn "SSH 已恢复，但恢复前快照未能清理：$tmp"
    if ! clear_ssh_change_tracking; then
        err "SSH 配置已恢复，但变更清单清理失败；已保留剩余记录供人工核验。"
        return 1
    fi
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
 新端口：创建时输入，留空默认 23333
----------------------------------------
将根据当前 SSH 配置，最小化修改主配置或 vpsbox drop-in。
$(ssh_port_change_firewall_hint)
----------------------------------------
 [1] 应用 SSH 端口修改
 [2] 恢复 vpsbox SSH 配置（高风险）
----------------------------------------
 [0] 返回系统优化
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
 [1] 应用 SSH 基础加固
----------------------------------------
 [0] 返回系统优化
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
    local confirm

    detect_os
    case "$OS" in
        debian)
            cat <<EOF
即将执行系统更新：
apt update && apt upgrade -y && apt autoremove -y
EOF
            ;;
        alpine)
            cat <<EOF
即将执行系统更新：
apk update && apk upgrade
EOF
            ;;
        redhat)
            err "系统更新当前不自动支持 RedHat 系。"
            warn "可手动执行：dnf upgrade -y 或 yum update -y"
            return 1
            ;;
        *)
            err "未识别系统类型，已取消系统更新。"
            return 1
            ;;
    esac

    read -r -p "确认继续？[y/N]: " confirm || return 1
    case "$confirm" in
        y|Y|yes|YES) ;;
        *) info "已取消系统更新。"; return 0 ;;
    esac

    case "$OS" in
        debian)
            export DEBIAN_FRONTEND=noninteractive
            apt_get_bounded "$PACKAGE_UPDATE_TIMEOUT" update || {
                err "APT 软件包索引更新失败，已停止后续步骤。"
                return 1
            }
            apt_get_bounded "$SYSTEM_UPGRADE_TIMEOUT" upgrade -y || {
                err "APT 软件包升级失败，已停止后续步骤。"
                return 1
            }
            apt_get_bounded "$SYSTEM_UPGRADE_TIMEOUT" autoremove -y || {
                err "APT 自动清理失败。"
                return 1
            }
            ;;
        alpine)
            apk_bounded "$PACKAGE_UPDATE_TIMEOUT" update || {
                err "APK 软件包索引更新失败，已停止后续步骤。"
                return 1
            }
            apk_bounded "$SYSTEM_UPGRADE_TIMEOUT" upgrade || {
                err "APK 软件包升级失败。"
                return 1
            }
            ;;
    esac

    if [ "$(reboot_required_state)" = "需要" ]; then
        warn "系统更新完成，检测到需要重启 VPS。"
    else
        info "系统更新完成，当前不需要重启。"
    fi
}

render_bbr_fq_config() {
    cat <<EOF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
}

bbr_fq_persistent_config_is_current() {
    [ -f "$BBR_CONF" ] && [ ! -L "$BBR_CONF" ] || return 1
    render_bbr_fq_config | cmp -s - "$BBR_CONF"
}

bbr_fq_runtime_is_current() {
    [ "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || true)" = "bbr" ] &&
        [ "$(sysctl -n net.core.default_qdisc 2>/dev/null || true)" = "fq" ]
}

repair_bbr_fq_runtime() {
    local old_cc old_fq

    old_cc="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || true)"
    old_fq="$(sysctl -n net.core.default_qdisc 2>/dev/null || true)"
    if ! modprobe tcp_bbr >/dev/null 2>&1 ||
        ! modprobe sch_fq >/dev/null 2>&1 ||
        ! sysctl -p "$BBR_CONF" >/dev/null 2>&1 ||
        ! bbr_fq_runtime_is_current; then
        [ -n "$old_cc" ] && sysctl -w "net.ipv4.tcp_congestion_control=$old_cc" >/dev/null 2>&1 || true
        [ -n "$old_fq" ] && sysctl -w "net.core.default_qdisc=$old_fq" >/dev/null 2>&1 || true
        return 1
    fi
}

enable_bbr_fq() {
    local old_cc old_fq tmp

    if bbr_fq_persistent_config_is_current; then
        if bbr_fq_runtime_is_current; then
            info "BBR + fq 配置和运行状态已正确，无需重复应用。"
            return 0
        fi
        info "BBR + fq 持久化配置已存在，正在轻量修复运行参数..."
        if ! repair_bbr_fq_runtime; then
            err "BBR + fq 运行参数修复失败，已恢复修改前的运行参数。"
            return 1
        fi
        info "当前 BBR：$(bbr_state)"
        info "当前 fq：$(fq_state)"
        return 0
    fi

    old_cc="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || true)"
    old_fq="$(sysctl -n net.core.default_qdisc 2>/dev/null || true)"
    backup_change_file_once BBR_CONF "$BBR_CONF" || { err "记录 BBR 原配置失败，已取消修改。"; return 1; }
    manifest_set_once BBR_CC "${old_cc:-unknown}" || return 1
    manifest_set_once BBR_FQ "${old_fq:-unknown}" || return 1
    if [ -e "$BBR_CONF" ] || [ -L "$BBR_CONF" ]; then
        [ ! -L "$BBR_CONF" ] || { err "$BBR_CONF 是符号链接，已拒绝覆盖。"; return 1; }
    fi
    begin_change_transaction BBR_CONF || { err "记录 BBR 修改事务失败，已取消修改。"; return 1; }
    tmp="$(mktemp /etc/sysctl.d/.vpsbox-bbr.XXXXXX)" || return 1
    render_bbr_fq_config > "$tmp" || {
        rm -f "$tmp"
        return 1
    }

    if ! modprobe tcp_bbr >/dev/null 2>&1 || ! modprobe sch_fq >/dev/null 2>&1; then
        rm -f "$tmp"
        err "内核不支持 tcp_bbr 或 sch_fq，未写入持久化配置。"
        return 1
    fi
    if ! sysctl -p "$tmp" >/dev/null 2>&1 || [ "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || true)" != "bbr" ] || [ "$(sysctl -n net.core.default_qdisc 2>/dev/null || true)" != "fq" ]; then
        [ -n "$old_cc" ] && sysctl -w "net.ipv4.tcp_congestion_control=$old_cc" >/dev/null 2>&1 || true
        [ -n "$old_fq" ] && sysctl -w "net.core.default_qdisc=$old_fq" >/dev/null 2>&1 || true
        rm -f "$tmp"
        err "BBR + fq 未能同时生效，已恢复运行时内核参数，未写入持久化配置。"
        return 1
    fi

    if ! chown root:root "$tmp" || ! chmod 644 "$tmp" || ! mv -f "$tmp" "$BBR_CONF"; then
        [ -n "$old_cc" ] && sysctl -w "net.ipv4.tcp_congestion_control=$old_cc" >/dev/null 2>&1 || true
        [ -n "$old_fq" ] && sysctl -w "net.core.default_qdisc=$old_fq" >/dev/null 2>&1 || true
        rm -f "$tmp"
        err "保存 BBR 配置失败；原持久化配置未被替换，运行时参数已尝试恢复。"
        return 1
    fi
    mark_change_applied BBR_CONF || return 1

    echo ""
    info "当前 BBR：$(bbr_state)"
    info "当前 fq：$(fq_state)"
}

ensure_fail2ban_service_running() {
    if is_systemd; then
        systemctl enable fail2ban >/dev/null 2>&1 || return 1
        if [ "$(fail2ban_service_state)" != "运行中" ]; then
            retry 3 2 systemctl start fail2ban || return 1
        fi
    elif [ "$OS" = "alpine" ] && command -v rc-service >/dev/null 2>&1; then
        command -v rc-update >/dev/null 2>&1 || return 1
        rc-update add fail2ban default >/dev/null 2>&1 || return 1
        if [ "$(fail2ban_service_state)" != "运行中" ]; then
            retry 3 2 rc-service fail2ban start || return 1
        fi
    else
        return 1
    fi
}

install_fail2ban() {
    detect_os
    if fail2ban_sshd_configuration_healthy; then
        info "Fail2ban SSH 防护已正常运行，无需重复安装或配置。"
        return 0
    fi

    if ! fail2ban_installed; then
        info "正在安装 Fail2ban..."
        case "$OS" in
            debian)
                export DEBIAN_FRONTEND=noninteractive
                if ! apt_get_bounded "$PACKAGE_UPDATE_TIMEOUT" update ||
                    ! apt_get_bounded "$PACKAGE_INSTALL_TIMEOUT" install -y fail2ban; then
                    warn "Fail2ban 安装未完全成功，将检查最终安装状态。"
                fi
                ;;
            alpine)
                if ! apk_bounded "$PACKAGE_UPDATE_TIMEOUT" update ||
                    ! apk_bounded "$PACKAGE_INSTALL_TIMEOUT" add --no-cache fail2ban; then
                    err "Fail2ban 安装失败。"
                    return 1
                fi
                ;;
            redhat)
                if command -v dnf >/dev/null 2>&1; then
                    dnf_bounded "$PACKAGE_INSTALL_TIMEOUT" install -y fail2ban || { err "Fail2ban 安装失败。"; return 1; }
                else
                    yum_bounded "$PACKAGE_INSTALL_TIMEOUT" install -y fail2ban || { err "Fail2ban 安装失败。"; return 1; }
                fi
                ;;
            *)
                err "未识别系统类型，无法自动安装 Fail2ban。"
                return 1
                ;;
        esac
    else
        info "Fail2ban 已安装，正在检查服务与 SSH 防护配置..."
    fi

    if ! fail2ban_installed; then
        err "Fail2ban 未安装成功，请检查软件源或网络。"
        return 1
    fi

    ensure_fail2ban_service_running || {
        err "无法启动 Fail2ban 或设置开机自启。"
        return 1
    }

    info "正在按 SSH 当前生效端口配置 Fail2ban..."
    sync_fail2ban_sshd_port || {
        err "Fail2ban SSH 配置或重启失败。"
        return 1
    }

    if ! fail2ban_service_is_enabled ||
        [ "$(fail2ban_service_state)" != "运行中" ] ||
        [ "$(fail2ban_sshd_state)" != "已启用" ]; then
        err "Fail2ban 未达到预期状态，请检查服务日志和 SSH 端口配置。"
        return 1
    fi

    info "Fail2ban 已安装，SSH 防护已启用，端口：$(ssh_effective_ports_csv)"
}

normalize_port_csv() {
    local input="${1:-}" item
    local -a items normalized_items=()

    [ -n "$input" ] || return 0
    IFS=',' read -ra items <<< "$input"
    for item in "${items[@]}"; do
        item="$(normalize_port_decimal "$item")" || return 1
        normalized_items+=("$item")
    done
    # 旧状态文件可能保存过带前导零的端口；读取时统一迁移成 nftables 使用的十进制形式。
    printf '%s\n' "${normalized_items[@]}" | sort -n -u | paste -sd, -
}

csv_contains_port() {
    local csv="${1:-}" port="$2"
    case ",$csv," in
        *",$port,"*) return 0 ;;
        *) return 1 ;;
    esac
}

csv_add_port() {
    local csv="${1:-}" port="$2"
    if [ -n "$csv" ]; then
        normalize_port_csv "$csv,$port"
    else
        normalize_port_csv "$port"
    fi
}

csv_remove_port() {
    local csv="${1:-}" port="$2" item
    local result=""
    local -a items

    [ -n "$csv" ] || return 0
    IFS=',' read -ra items <<< "$csv"
    for item in "${items[@]}"; do
        [ "$item" = "$port" ] && continue
        if [ -n "$result" ]; then result="$result,$item"; else result="$item"; fi
    done
    normalize_port_csv "$result"
}

merge_port_csv() {
    local result="" csv
    for csv in "$@"; do
        [ -n "$csv" ] || continue
        if [ -n "$result" ]; then result="$result,$csv"; else result="$csv"; fi
    done
    normalize_port_csv "$result"
}

subtract_port_csv() {
    local result="${1:-}" excluded="${2:-}" port
    local IFS=,

    result="$(normalize_port_csv "$result")" || return 1
    excluded="$(normalize_port_csv "$excluded")" || return 1
    [ -n "$excluded" ] || { printf '%s\n' "$result"; return 0; }
    for port in $excluded; do
        result="$(csv_remove_port "$result" "$port")" || return 1
    done
    printf '%s\n' "$result"
}

port_csv_is_subset() {
    local required="${1:-}" available="${2:-}" port
    local IFS=,

    [ -n "$required" ] || return 0
    for port in $required; do
        csv_contains_port "$available" "$port" || return 1
    done
}

firewall_write_ssh_safe_snapshot() {
    local source="$1" dest="$2" ssh_ports="$3" existing_tcp formatted tmp

    [ -f "$source" ] && [ ! -L "$source" ] || return 1
    ssh_ports="$(normalize_port_csv "$ssh_ports")" || return 1
    [ -n "$ssh_ports" ] || return 1
    existing_tcp="$(awk '
        /^[[:space:]]*chain[[:space:]]+input[[:space:]]*\{/ { in_input=1; next }
        in_input && /^[[:space:]]*\}/ { exit }
        in_input && $0 !~ /meta nfproto/ { print }
    ' "$source" | firewall_ports_from_nft_chain tcp)" || return 1
    if port_csv_is_subset "$ssh_ports" "$existing_tcp"; then
        [ "$source" = "$dest" ] || cp -a "$source" "$dest"
        return $?
    fi

    formatted="$(printf '%s' "$ssh_ports" | sed 's/,/, /g')"
    tmp="$(mktemp "$(dirname "$dest")/.firewall-ssh-safe.XXXXXX")" || return 1
    if ! awk -v ports="$formatted" '
        /^[[:space:]]*chain[[:space:]]+input[[:space:]]*\{/ { in_input=1 }
        in_input && /^[[:space:]]*\}/ {
            print "        tcp dport { " ports " } accept"
            inserted=1
            in_input=0
        }
        { print }
        END { if (!inserted) exit 1 }
    ' "$source" > "$tmp"; then
        rm -f "$tmp"
        return 1
    fi
    chmod 600 "$tmp" || { rm -f "$tmp"; return 1; }
    mv -f "$tmp" "$dest"
}

firewall_state_file_is_secure() {
    local owner mode

    [ -f "$FIREWALL_STATE_FILE" ] && [ ! -L "$FIREWALL_STATE_FILE" ] || return 1
    owner="$(stat -c '%u' "$FIREWALL_STATE_FILE" 2>/dev/null)" || return 1
    mode="$(stat -c '%a' "$FIREWALL_STATE_FILE" 2>/dev/null)" || return 1
    [ "$owner" = "0" ] || return 1
    [[ "$mode" =~ ^[0-7]{3,4}$ ]] || return 1
    (( (8#$mode & 8#077) == 0 ))
}

firewall_managed_file_is_secure() {
    local path="$1" owner mode
    [ -f "$path" ] && [ ! -L "$path" ] || return 1
    owner="$(stat -c '%u' "$path" 2>/dev/null)" || return 1
    mode="$(stat -c '%a' "$path" 2>/dev/null)" || return 1
    [ "$owner" = "0" ] || return 1
    [[ "$mode" =~ ^[0-7]{3,4}$ ]] || return 1
    (( (8#$mode & 8#077) == 0 ))
}

firewall_load_state() {
    local key value tcp="" udp=""

    FW_EXTRA_TCP=""
    FW_EXTRA_UDP=""
    [ -e "$FIREWALL_STATE_FILE" ] || return 0
    firewall_state_file_is_secure || {
        err "防火墙状态文件不安全，已拒绝读取：$FIREWALL_STATE_FILE"
        return 1
    }

    while IFS='=' read -r key value || [ -n "$key" ]; do
        case "$key" in
            EXTRA_TCP_PORTS) tcp="$value" ;;
            EXTRA_UDP_PORTS) udp="$value" ;;
            "") ;;
            *)
                err "防火墙状态文件包含未知字段：$key"
                return 1
                ;;
        esac
    done < "$FIREWALL_STATE_FILE"

    [[ "$tcp" =~ ^$|^[0-9]+(,[0-9]+)*$ ]] || return 1
    [[ "$udp" =~ ^$|^[0-9]+(,[0-9]+)*$ ]] || return 1
    FW_EXTRA_TCP="$(normalize_port_csv "$tcp")" || return 1
    FW_EXTRA_UDP="$(normalize_port_csv "$udp")" || return 1
}

firewall_write_state_file() {
    local dest="$1"
    {
        printf 'EXTRA_TCP_PORTS=%s\n' "$FW_EXTRA_TCP"
        printf 'EXTRA_UDP_PORTS=%s\n' "$FW_EXTRA_UDP"
    } > "$dest"
}

firewall_install_managed_file() {
    local source="$1" target="$2" mode="$3" target_dir tmp

    [ ! -L "$target" ] || {
        err "目标文件是符号链接，已拒绝覆盖：$target"
        return 1
    }
    target_dir="$(dirname "$target")"
    mkdir -p "$target_dir" || return 1
    tmp="$(mktemp "$target_dir/.vpsbox-firewall.XXXXXX")" || return 1
    if ! cp "$source" "$tmp" ||
        ! chown root:root "$tmp" ||
        ! chmod "$mode" "$tmp" ||
        ! mv -f "$tmp" "$target"; then
        rm -f "$tmp"
        return 1
    fi
}

firewall_runtime_enabled() {
    command -v nft >/dev/null 2>&1 &&
        nft list table inet vpsbox >/dev/null 2>&1 &&
        nft list chain inet vpsbox input >/dev/null 2>&1
}

firewall_persistence_enabled() {
    if is_systemd; then
        systemctl is-enabled --quiet "$FIREWALL_SERVICE_NAME" 2>/dev/null
    elif [ "$OS" = "alpine" ]; then
        [ -e "/etc/runlevels/default/$FIREWALL_SERVICE_NAME" ] ||
            [ -L "/etc/runlevels/default/$FIREWALL_SERVICE_NAME" ]
    else
        return 1
    fi
}

firewall_service_active() {
    if is_systemd; then
        systemctl is-active --quiet "$FIREWALL_SERVICE_NAME" 2>/dev/null
    elif [ "$OS" = "alpine" ] && command -v rc-service >/dev/null 2>&1; then
        rc-service "$FIREWALL_SERVICE_NAME" status >/dev/null 2>&1
    else
        return 1
    fi
}

firewall_control_plane_present() {
    firewall_runtime_enabled ||
        [ -e "$FIREWALL_CONFIG" ] ||
        [ -e "$FIREWALL_SYSTEMD_UNIT" ] ||
        [ -e "$FIREWALL_OPENRC_SERVICE" ] ||
        firewall_persistence_enabled ||
        firewall_service_active
}

firewall_artifacts_present() {
    firewall_control_plane_present || [ -e "$FIREWALL_STATE_FILE" ]
}

firewall_install_state() {
    command -v nft >/dev/null 2>&1 && echo "已安装" || echo "未安装"
}

firewall_runtime_state() {
    if firewall_runtime_enabled; then
        echo "运行中"
    elif [ -f "$FIREWALL_CONFIG" ]; then
        echo "配置存在但未运行"
    elif [ -e "$FIREWALL_SYSTEMD_UNIT" ] ||
        [ -e "$FIREWALL_OPENRC_SERVICE" ] ||
        firewall_persistence_enabled || firewall_service_active; then
        echo "状态不完整"
    else
        echo "未启用"
    fi
}

firewall_persistence_state() {
    firewall_persistence_enabled && echo "已启用" || echo "未启用"
}

firewall_native_service_enabled() {
    if is_systemd; then
        systemctl is-enabled --quiet nftables 2>/dev/null ||
            systemctl is-active --quiet nftables 2>/dev/null
    elif [ "$OS" = "alpine" ]; then
        [ -e /etc/runlevels/default/nftables ] ||
            [ -L /etc/runlevels/default/nftables ] ||
            { command -v rc-service >/dev/null 2>&1 && rc-service nftables status >/dev/null 2>&1; }
    else
        return 1
    fi
}

firewall_openrc_service_enabled() {
    local service="$1" runlevels_dir="${2:-/etc/runlevels}" entry

    [ -n "$service" ] && [ -d "$runlevels_dir" ] || return 1
    for entry in "$runlevels_dir"/*/"$service"; do
        [ -e "$entry" ] || [ -L "$entry" ] || continue
        return 0
    done
    return 1
}

firewall_firewalld_enabled_or_active() {
    if is_systemd; then
        systemctl is-active --quiet firewalld 2>/dev/null ||
            systemctl is-enabled --quiet firewalld 2>/dev/null
    elif [ "$OS" = "alpine" ]; then
        { command -v rc-service >/dev/null 2>&1 &&
            rc-service firewalld status >/dev/null 2>&1; } ||
            firewall_openrc_service_enabled firewalld
    else
        return 1
    fi
}

firewall_check_conflicts() {
    if command -v ufw >/dev/null 2>&1 &&
        ufw status 2>/dev/null | grep -Eqi '^Status:[[:space:]]*active'; then
        err "检测到 UFW 正在运行。为避免规则链冲突，请先停用 UFW 后再启用主机防火墙。"
        return 1
    fi
    if firewall_firewalld_enabled_or_active; then
        err "检测到 firewalld 已启用或正在运行。为避免重启后出现规则链冲突，请先停用 firewalld。"
        return 1
    fi
    if firewall_native_service_enabled; then
        err "检测到系统 nftables 服务已启用或正在运行。"
        err "vpsbox 不会覆盖现有 /etc/nftables.conf；请先迁移或停用原服务。"
        return 1
    fi
    if command -v nft >/dev/null 2>&1 &&
        nft list table inet vpsbox >/dev/null 2>&1 &&
        { [ ! -f "$FIREWALL_CONFIG" ] || [ ! -f "$FIREWALL_STATE_FILE" ]; }; then
        err "检测到非完整 vpsbox 状态的 inet vpsbox 表，已拒绝覆盖。"
        return 1
    fi
}

ensure_nftables() {
    if command -v nft >/dev/null 2>&1 &&
        command -v jq >/dev/null 2>&1 &&
        command -v ss >/dev/null 2>&1 &&
        command -v timeout >/dev/null 2>&1; then
        return 0
    fi
    detect_os
    info "正在安装主机防火墙所需的 nftables、jq、iproute2 与 coreutils..."
    case "$OS" in
        debian)
            export DEBIAN_FRONTEND=noninteractive
            apt_get_bounded "$PACKAGE_UPDATE_TIMEOUT" update -y || return 1
            apt_get_bounded "$PACKAGE_INSTALL_TIMEOUT" install -y nftables jq iproute2 coreutils || return 1
            ;;
        alpine)
            apk_bounded "$PACKAGE_UPDATE_TIMEOUT" update || return 1
            apk_bounded "$PACKAGE_INSTALL_TIMEOUT" add --no-cache nftables jq iproute2 coreutils || return 1
            ;;
        *)
            err "主机防火墙目前仅支持 Debian/Ubuntu 与 Alpine。"
            return 1
            ;;
    esac
    command -v nft >/dev/null 2>&1 &&
        command -v jq >/dev/null 2>&1 &&
        command -v ss >/dev/null 2>&1 &&
        command -v timeout >/dev/null 2>&1 || {
            err "主机防火墙依赖安装后仍不完整。"
            return 1
        }
}

is_valid_interface_name() {
    local name="${1:-}"
    [ -n "$name" ] && [ "${#name}" -le 15 ] &&
        [[ "$name" =~ ^[A-Za-z0-9_.:-]+$ ]]
}

normalize_interface_csv() {
    local input="${1:-}" item
    local -a items

    [ -n "$input" ] || return 0
    IFS=',' read -ra items <<< "$input"
    for item in "${items[@]}"; do
        is_valid_interface_name "$item" || return 1
    done
    printf '%s\n' "${items[@]}" | sort -u | paste -sd, -
}

interface_csv_add() {
    local csv="${1:-}" name="$2"
    if [ -n "$csv" ]; then
        normalize_interface_csv "$csv,$name"
    else
        normalize_interface_csv "$name"
    fi
}

firewall_docker_available() {
    command -v docker >/dev/null 2>&1 &&
        docker_with_timeout info >/dev/null 2>&1
}

docker_with_timeout() {
    command -v docker >/dev/null 2>&1 && command -v timeout >/dev/null 2>&1 || return 1
    timeout 15 docker "$@"
}

docker_daemon_process_present() {
    local comm_file comm_name

    for comm_file in /proc/[0-9]*/comm; do
        [ -r "$comm_file" ] || continue
        read -r comm_name < "$comm_file" || continue
        [ "$comm_name" = "dockerd" ] && return 0
    done
    return 1
}

docker_single_daemon_pid() {
    local comm_file comm_name pid="" count=0

    for comm_file in /proc/[0-9]*/comm; do
        [ -r "$comm_file" ] || continue
        read -r comm_name < "$comm_file" || continue
        [ "$comm_name" = "dockerd" ] || continue
        pid="${comm_file%/comm}"
        pid="${pid##*/}"
        count=$((count + 1))
    done
    [ "$count" -eq 1 ] || return 1
    printf '%s\n' "$pid"
}

firewall_docker_config_has_unsafe_mode() {
    local config_file="$1"

    jq -e '
        (.["allow-direct-routing"] == true) or
        (.iptables == false) or
        (.ip6tables == false) or
        ([.["default-network-opts"] // {} | .. | objects | to_entries[]? |
            select(
                (
                    ((.key | endswith("gateway_mode_ipv4")) or (.key | endswith("gateway_mode_ipv6"))) and
                    ((.value == "routed") or (.value == "nat-unprotected"))
                ) or
                ((.key | endswith("trusted_host_interfaces")) and ((.value // "") != ""))
            )
        ] | length > 0)
    ' "$config_file" >/dev/null 2>&1
}

docker_go_bool_value() {
    local value="${1,,}"

    case "$value" in
        1|t|true) printf '%s\n' true ;;
        0|f|false) printf '%s\n' false ;;
        *) return 1 ;;
    esac
}

timestamp_strictly_after() {
    local candidate="$1" reference="$2"

    [[ "$candidate" =~ ^[0-9]+$ ]] && [[ "$reference" =~ ^[0-9]+$ ]] &&
        [ "$candidate" -gt "$reference" ]
}

firewall_validate_docker_daemon_mode() {
    local comm_file comm_name cmdline_file="" config_file="/etc/docker/daemon.json"
    local config_view config_parent arg value parsed_bool i daemon_found=0 config_explicit=0
    local daemon_pid="" clock_ticks boot_epoch start_ticks daemon_start_epoch config_mtime config_ctime
    local -a daemon_argv

    for comm_file in /proc/[0-9]*/comm; do
        [ -r "$comm_file" ] || continue
        read -r comm_name < "$comm_file" || continue
        [ "$comm_name" = "dockerd" ] || continue
        cmdline_file="${comm_file%/comm}/cmdline"
        [ -r "$cmdline_file" ] || continue
        [ "$daemon_found" -eq 0 ] || {
            err "检测到多个 dockerd 进程，无法确认当前 socket 对应的 daemon 参数。"
            return 1
        }
        mapfile -d '' -t daemon_argv < "$cmdline_file"
        daemon_pid="${comm_file%/comm}"
        daemon_pid="${daemon_pid##*/}"
        daemon_found=1
    done
    [ "$daemon_found" -eq 1 ] || {
        err "无法确认本机 dockerd 进程参数，已拒绝更新防火墙。"
        return 1
    }

    for ((i = 0; i < ${#daemon_argv[@]}; i++)); do
        arg="${daemon_argv[$i]}"
        case "$arg" in
            --config-file=*) config_file="${arg#*=}"; config_explicit=1 ;;
            --config-file)
                i=$((i + 1))
                [ "$i" -lt "${#daemon_argv[@]}" ] || {
                    err "dockerd --config-file 缺少路径。"
                    return 1
                }
                config_file="${daemon_argv[$i]}"
                config_explicit=1
                ;;
            --allow-direct-routing)
                err "检测到 Docker direct routing，已拒绝更新防火墙。"
                return 1
                ;;
            --allow-direct-routing=*)
                value="${arg#*=}"
                parsed_bool="$(docker_go_bool_value "$value")" || {
                    err "dockerd 返回了无法识别的 allow-direct-routing 布尔值：$value"
                    return 1
                }
                if [ "$parsed_bool" = "true" ]; then
                    err "检测到 Docker direct routing，已拒绝更新防火墙。"
                    return 1
                fi
                ;;
            --iptables=*|--ip6tables=*)
                value="${arg#*=}"
                parsed_bool="$(docker_go_bool_value "$value")" || {
                    err "dockerd 返回了无法识别的防火墙布尔值：$value"
                    return 1
                }
                if [ "$parsed_bool" = "false" ]; then
                    err "检测到 Docker 已关闭 iptables/ip6tables 管理，无法可靠守卫发布端口。"
                    return 1
                fi
                ;;
            --default-network-opt=*)
                value="${arg#*=}"
                case "$value" in
                    *gateway_mode_ipv4=routed*|*gateway_mode_ipv6=routed*|\
                    *gateway_mode_ipv4=nat-unprotected*|*gateway_mode_ipv6=nat-unprotected*|\
                    *trusted_host_interfaces=*)
                        err "dockerd 默认网络参数启用了直连/非保护模式，已拒绝更新防火墙。"
                        return 1
                        ;;
                esac
                ;;
            --default-network-opt)
                i=$((i + 1))
                [ "$i" -lt "${#daemon_argv[@]}" ] || {
                    err "dockerd --default-network-opt 缺少参数。"
                    return 1
                }
                value="${daemon_argv[$i]}"
                case "$value" in
                    *gateway_mode_ipv4=routed*|*gateway_mode_ipv6=routed*|\
                    *gateway_mode_ipv4=nat-unprotected*|*gateway_mode_ipv6=nat-unprotected*|\
                    *trusted_host_interfaces=*)
                        err "dockerd 默认网络参数启用了直连/非保护模式，已拒绝更新防火墙。"
                        return 1
                        ;;
                esac
                ;;
        esac
    done

    case "$config_file" in
        /*) ;;
        *)
            err "dockerd 配置文件不是绝对路径，无法安全检查：$config_file"
            return 1
            ;;
    esac
    start_ticks="$(awk '{ print $22; exit }' "/proc/$daemon_pid/stat" 2>/dev/null || true)"
    [[ "$start_ticks" =~ ^[0-9]+$ ]] || {
        err "无法读取 dockerd 进程启动标识，已拒绝更新防火墙。"
        return 1
    }
    FW_DOCKER_DAEMON_PID="$daemon_pid"
    FW_DOCKER_DAEMON_START_TICKS="$start_ticks"
    clock_ticks="$(getconf CLK_TCK 2>/dev/null)" || clock_ticks=""
    [[ "$clock_ticks" =~ ^[1-9][0-9]*$ ]] || clock_ticks=100
    boot_epoch="$(awk '$1 == "btime" { print $2; exit }' /proc/stat 2>/dev/null)"
    if ! [[ "$boot_epoch" =~ ^[0-9]+$ ]]; then
        err "无法确认 dockerd 启动时间，已拒绝根据磁盘配置更新防火墙。"
        return 1
    fi
    daemon_start_epoch=$((boot_epoch + start_ticks / clock_ticks))

    config_view="/proc/$daemon_pid/root$config_file"
    if [ ! -e "$config_view" ]; then
        if [ "$config_explicit" -eq 1 ]; then
            err "dockerd 显式配置文件在当前 daemon 视图中不存在：$config_file"
            return 1
        fi
        config_parent="${config_view%/*}"
        if [ -e "$config_parent" ]; then
            [ -d "$config_parent" ] && [ ! -L "$config_parent" ] || {
                err "dockerd 默认配置目录状态异常，无法确认启动时配置：${config_file%/*}"
                return 1
            }
            config_mtime="$(stat -c '%Y' "$config_parent" 2>/dev/null)" || return 1
            config_ctime="$(stat -c '%Z' "$config_parent" 2>/dev/null)" || return 1
            # /proc 的 btime 与 stat 时间只有秒级；同一秒无法证明目录变更晚于 daemon，
            # 仅在时间戳严格更晚时拒绝，避免刚启动 Docker 时产生同秒误报。
            if timestamp_strictly_after "$config_mtime" "$daemon_start_epoch" ||
                timestamp_strictly_after "$config_ctime" "$daemon_start_epoch"; then
                err "dockerd 默认配置文件当前不存在，但配置目录在 daemon 启动后发生过变化。"
                err "无法排除配置已被删除；请重启 Docker 后再更新 vpsbox 防火墙。"
                return 1
            fi
        fi
        return 0
    fi
    [ ! -L "$config_view" ] || {
        err "dockerd 配置文件是符号链接，无法确认运行时加载的文件版本：$config_file"
        return 1
    }
    command -v jq >/dev/null 2>&1 || {
        err "dockerd 使用了配置文件，但缺少 jq，无法安全检查：$config_file"
        return 1
    }
    [ -r "$config_view" ] && [ -f "$config_view" ] || {
        err "无法安全读取 dockerd 配置文件：$config_file"
        return 1
    }
    config_mtime="$(stat -c '%Y' "$config_view" 2>/dev/null)" || return 1
    config_ctime="$(stat -c '%Z' "$config_view" 2>/dev/null)" || return 1
    if ! [[ "$config_mtime" =~ ^[0-9]+$ ]] || ! [[ "$config_ctime" =~ ^[0-9]+$ ]]; then
        err "无法确认 dockerd 配置文件时间，已拒绝更新防火墙。"
        return 1
    fi
    # 同秒时间戳在现有内核接口精度下无法排序，只有严格晚于启动秒才视为未加载变更。
    if timestamp_strictly_after "$config_mtime" "$daemon_start_epoch" ||
        timestamp_strictly_after "$config_ctime" "$daemon_start_epoch"; then
        err "dockerd 配置文件在 daemon 启动后发生过变化，当前运行态可能尚未加载。"
        err "请重启 Docker 并确认容器正常后，再更新 vpsbox 防火墙。"
        return 1
    fi
    jq empty "$config_view" >/dev/null 2>&1 || {
        err "dockerd 配置文件不是有效 JSON：$config_file"
        return 1
    }
    if firewall_docker_config_has_unsafe_mode "$config_view"; then
        err "dockerd 配置启用了 direct routing、非保护网关或关闭了防火墙管理。"
        return 1
    fi
}

firewall_docker_daemon_identity_unchanged() {
    local expected_pid="${FW_DOCKER_DAEMON_PID:-}" expected_ticks="${FW_DOCKER_DAEMON_START_TICKS:-}"
    local comm_file comm_name pid="" count=0 current_ticks

    [[ "$expected_pid" =~ ^[0-9]+$ ]] && [[ "$expected_ticks" =~ ^[0-9]+$ ]] || return 1
    for comm_file in /proc/[0-9]*/comm; do
        [ -r "$comm_file" ] || continue
        read -r comm_name < "$comm_file" || continue
        [ "$comm_name" = "dockerd" ] || continue
        pid="${comm_file%/comm}"
        pid="${pid##*/}"
        count=$((count + 1))
    done
    [ "$count" -eq 1 ] && [ "$pid" = "$expected_pid" ] || return 1
    current_ticks="$(awk '{ print $22; exit }' "/proc/$pid/stat" 2>/dev/null)" || return 1
    [ "$current_ticks" = "$expected_ticks" ]
}

is_wildcard_listen_addr() {
    local addr="${1,,}"

    case "$addr" in
        ""|'*'|0.0.0.0|::|0:0:0:0:0:0:0:0) return 0 ;;
        *) return 1 ;;
    esac
}

firewall_record_docker_public_binding() {
    local protocol="$1" host_ip="${2,,}" port="$3"

    is_valid_port "$port" || return 1
    is_loopback_listen_addr "$host_ip" && return 0
    case "$host_ip" in
        "")
            err "Docker 发布地址尚未确定，已拒绝把端口 $port 视为公网端口。"
            return 1
            ;;
        0.0.0.0|'*')
            case "$protocol" in
                tcp) FW_DOCKER_PUBLIC4_TCP="$(csv_add_port "$FW_DOCKER_PUBLIC4_TCP" "$port")" ;;
                udp) FW_DOCKER_PUBLIC4_UDP="$(csv_add_port "$FW_DOCKER_PUBLIC4_UDP" "$port")" ;;
                *) return 1 ;;
            esac
            ;;
        ::|0:0:0:0:0:0:0:0)
            case "$protocol" in
                tcp) FW_DOCKER_PUBLIC6_TCP="$(csv_add_port "$FW_DOCKER_PUBLIC6_TCP" "$port")" ;;
                udp) FW_DOCKER_PUBLIC6_UDP="$(csv_add_port "$FW_DOCKER_PUBLIC6_UDP" "$port")" ;;
                *) return 1 ;;
            esac
            ;;
        *)
            err "Docker 发布到特定非回环地址 $host_ip:$port，当前无法保留地址级访问边界。"
            err "请改用通配地址/回环地址，或关闭 vpsbox 防火墙后自行管理规则。"
            return 1
            ;;
    esac
    FW_DOCKER_PUBLIC_TCP="$(merge_port_csv "$FW_DOCKER_PUBLIC4_TCP" "$FW_DOCKER_PUBLIC6_TCP")" || return 1
    FW_DOCKER_PUBLIC_UDP="$(merge_port_csv "$FW_DOCKER_PUBLIC4_UDP" "$FW_DOCKER_PUBLIC6_UDP")" || return 1
}

firewall_detect_docker_proxy_ports() {
    local family output mapping protocol listen_address host port

    FW_DOCKER_PROXY4_TCP=""
    FW_DOCKER_PROXY4_UDP=""
    FW_DOCKER_PROXY6_TCP=""
    FW_DOCKER_PROXY6_UDP=""
    command -v ss >/dev/null 2>&1 || {
        err "缺少 ss，无法检查 docker-proxy 监听。"
        return 1
    }
    for family in 4 6; do
        output="$(ss -H "-$family" -lntup 2>/dev/null)" || {
            err "无法读取 IPv$family docker-proxy 监听状态。"
            return 1
        }
        while IFS='|' read -r protocol listen_address; do
            [ -n "$protocol" ] || continue
            port="${listen_address##*:}"
            host="${listen_address%:*}"
            host="${host#[}"
            host="${host%]}"
            is_valid_port "$port" || {
                err "docker-proxy 返回了无效监听端口：$listen_address"
                return 1
            }
            is_loopback_listen_addr "$host" && continue
            is_wildcard_listen_addr "$host" || {
                err "docker-proxy 监听特定地址 $listen_address，无法用端口级规则保持地址边界。"
                return 1
            }
            case "$protocol:$family" in
                tcp:4)
                    csv_contains_port "$FW_DOCKER_PUBLIC4_TCP" "$port" || return 1
                    FW_DOCKER_PROXY4_TCP="$(csv_add_port "$FW_DOCKER_PROXY4_TCP" "$port")"
                    ;;
                udp:4)
                    csv_contains_port "$FW_DOCKER_PUBLIC4_UDP" "$port" || return 1
                    FW_DOCKER_PROXY4_UDP="$(csv_add_port "$FW_DOCKER_PROXY4_UDP" "$port")"
                    ;;
                tcp:6)
                    csv_contains_port "$FW_DOCKER_PUBLIC6_TCP" "$port" || return 1
                    FW_DOCKER_PROXY6_TCP="$(csv_add_port "$FW_DOCKER_PROXY6_TCP" "$port")"
                    ;;
                udp:6)
                    csv_contains_port "$FW_DOCKER_PUBLIC6_UDP" "$port" || return 1
                    FW_DOCKER_PROXY6_UDP="$(csv_add_port "$FW_DOCKER_PROXY6_UDP" "$port")"
                    ;;
            esac
        done < <(printf '%s\n' "$output" | awk '/docker-proxy/ {
            address=$5
            if ($1 == "tcp" || $1 == "udp") print $1 "|" address
        }')
    done
}

firewall_detect_docker_ports() {
    local container mode mapping container_port protocol binding host_ip host_port remainder
    local network_id network_name network_driver bridge_name swarm_state
    local docker_host context endpoint effective_endpoint security_options container_list network_list
    local bindings running publish_all port_mappings network_data gateway_v4 gateway_v6 trusted_interfaces
    local container_dynamic
    local connected_count

    FW_DOCKER_TCP=""
    FW_DOCKER_UDP=""
    FW_DOCKER_PUBLIC_TCP=""
    FW_DOCKER_PUBLIC_UDP=""
    FW_DOCKER_PUBLIC4_TCP=""
    FW_DOCKER_PUBLIC4_UDP=""
    FW_DOCKER_PUBLIC6_TCP=""
    FW_DOCKER_PUBLIC6_UDP=""
    FW_DOCKER_PROXY4_TCP=""
    FW_DOCKER_PROXY4_UDP=""
    FW_DOCKER_PROXY6_TCP=""
    FW_DOCKER_PROXY6_UDP=""
    FW_DOCKER_BRIDGES=""
    FW_DOCKER_DAEMON_PID=""
    FW_DOCKER_DAEMON_START_TICKS=""
    FW_DOCKER_HOST_NETWORK=0
    FW_DOCKER_DYNAMIC_PORT=0
    FW_DOCKER_DIRECT_NETWORK=0
    FW_DOCKER_CUSTOM_BRIDGE=0

    if ! command -v docker >/dev/null 2>&1; then
        docker_daemon_process_present || return 0
        err "检测到 dockerd 进程但缺少 docker CLI，无法可靠检查发布端口。"
        return 1
    fi

    docker_host="${DOCKER_HOST:-}"
    case "$docker_host" in
        ""|unix:///*) ;;
        *)
            err "检测到远程 DOCKER_HOST，已拒绝用远端容器信息配置本机防火墙。"
            return 1
            ;;
    esac
    context="$(docker_with_timeout context show 2>/dev/null)" || {
        err "无法确认 Docker 当前 context，已拒绝更新防火墙。"
        return 1
    }
    endpoint="$(docker_with_timeout context inspect --format '{{.Endpoints.docker.Host}}' "$context" 2>/dev/null)" || {
        err "无法读取 Docker context 连接地址，已拒绝更新防火墙。"
        return 1
    }
    effective_endpoint="${docker_host:-$endpoint}"
    case "$effective_endpoint" in
        unix:///var/run/docker.sock|unix:///run/docker.sock) ;;
        *)
            err "Docker 当前连接不是受支持的本机 rootful socket：$effective_endpoint"
            return 1
            ;;
    esac

    if ! firewall_docker_available; then
        err "检测到 Docker 命令，但无法连接 Docker daemon。"
        err "请先启动 Docker 或移除无效客户端，再更新主机防火墙。"
        return 1
    fi

    security_options="$(docker_with_timeout info --format '{{json .SecurityOptions}}' 2>/dev/null)" || {
        err "无法读取 Docker 安全模式，已拒绝更新防火墙。"
        return 1
    }
    if [[ "$security_options" == *rootless* ]]; then
        err "检测到 rootless Docker；当前防火墙仅支持本机 rootful Docker。"
        return 1
    fi

    swarm_state="$(docker_with_timeout info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null)" || {
        err "无法读取 Docker Swarm 状态，已拒绝更新防火墙。"
        return 1
    }
    if [ "$swarm_state" != "inactive" ]; then
        err "Docker Swarm 状态不是 inactive（当前：$swarm_state），已拒绝更新防火墙。"
        return 1
    fi

    firewall_validate_docker_daemon_mode || return 1

    container_list="$(docker_with_timeout ps -aq 2>/dev/null)" || {
        err "Docker 容器枚举失败，已拒绝生成不完整的防火墙规则。"
        return 1
    }

    while IFS= read -r container; do
        [ -n "$container" ] || continue
        container_dynamic=0
        mode="$(docker_with_timeout inspect --format '{{.HostConfig.NetworkMode}}' "$container" 2>/dev/null)" || {
            err "无法读取 Docker 容器网络模式：$container"
            return 1
        }
        if [ "$mode" = "host" ]; then
            FW_DOCKER_HOST_NETWORK=1
            continue
        fi
        publish_all="$(docker_with_timeout inspect --format '{{.HostConfig.PublishAllPorts}}' "$container" 2>/dev/null)" || {
            err "无法读取 Docker 容器随机发布设置：$container"
            return 1
        }
        case "$publish_all" in
            true) container_dynamic=1 ;;
            false) ;;
            *)
                err "Docker 返回了无效的随机发布状态：$publish_all"
                return 1
                ;;
        esac
        bindings="$(docker_with_timeout inspect --format \
            '{{range $port, $bindings := .HostConfig.PortBindings}}{{range $bindings}}{{printf "%s|%s|%s\n" $port .HostIp .HostPort}}{{end}}{{end}}' \
            "$container" 2>/dev/null)" || {
            err "无法读取 Docker 容器端口映射：$container"
            return 1
        }
        while IFS= read -r mapping; do
            [ -n "$mapping" ] || continue
            container_port="${mapping%%|*}"
            remainder="${mapping#*|}"
            host_ip="${remainder%%|*}"
            host_port="${remainder##*|}"
            protocol="${container_port##*/}"
            if [ -z "$host_port" ] || [ "$host_port" = "0" ]; then
                container_dynamic=1
                continue
            fi
            is_valid_port "$host_port" || {
                err "Docker 返回了无效宿主机端口：$host_port"
                return 1
            }
            case "$protocol" in
                tcp)
                    FW_DOCKER_TCP="$(csv_add_port "$FW_DOCKER_TCP" "$host_port")"
                    [ -n "$host_ip" ] || container_dynamic=1
                    ;;
                udp)
                    FW_DOCKER_UDP="$(csv_add_port "$FW_DOCKER_UDP" "$host_port")"
                    [ -n "$host_ip" ] || container_dynamic=1
                    ;;
                *)
                    err "检测到不受支持的 Docker 发布协议：$protocol"
                    return 1
                    ;;
            esac
            if [ -n "$host_ip" ]; then
                firewall_record_docker_public_binding "$protocol" "$host_ip" "$host_port" || return 1
            fi
        done <<< "$bindings"

        running="$(docker_with_timeout inspect --format '{{.State.Running}}' "$container" 2>/dev/null)" || {
            err "无法读取 Docker 容器运行状态：$container"
            return 1
        }
        if [ "$running" != "true" ]; then
            [ "$container_dynamic" = "0" ] || FW_DOCKER_DYNAMIC_PORT=1
            continue
        fi
        port_mappings="$(docker_with_timeout port "$container" 2>/dev/null)" || {
            err "无法读取运行中 Docker 容器的实际发布端口：$container"
            return 1
        }
        [ -z "$port_mappings" ] || container_dynamic=0
        while IFS= read -r mapping; do
            [ -n "$mapping" ] || continue
            container_port="${mapping%% -> *}"
            protocol="${container_port##*/}"
            binding="${mapping#* -> }"
            host_port="${binding##*:}"
            host_ip="${binding%:*}"
            host_ip="${host_ip#[}"
            host_ip="${host_ip%]}"
            is_valid_port "$host_port" || {
                err "Docker 返回了无效运行端口：$host_port"
                return 1
            }
            case "$protocol" in
                tcp)
                    FW_DOCKER_TCP="$(csv_add_port "$FW_DOCKER_TCP" "$host_port")"
                    firewall_record_docker_public_binding tcp "$host_ip" "$host_port" || return 1
                    ;;
                udp)
                    FW_DOCKER_UDP="$(csv_add_port "$FW_DOCKER_UDP" "$host_port")"
                    firewall_record_docker_public_binding udp "$host_ip" "$host_port" || return 1
                    ;;
                *)
                    err "检测到不受支持的 Docker 运行协议：$protocol"
                    return 1
                    ;;
            esac
        done <<< "$port_mappings"
        [ "$container_dynamic" = "0" ] || FW_DOCKER_DYNAMIC_PORT=1
    done <<< "$container_list"

    network_list="$(docker_with_timeout network ls --format '{{.ID}}|{{.Name}}|{{.Driver}}' 2>/dev/null)" || {
        err "Docker 网络枚举失败，已拒绝生成不完整的防火墙规则。"
        return 1
    }
    while IFS='|' read -r network_id network_name network_driver; do
        [ -n "$network_id" ] || continue
        network_data="$(docker_with_timeout network inspect --format \
            '{{index .Options "com.docker.network.bridge.name"}}|{{index .Options "com.docker.network.bridge.gateway_mode_ipv4"}}|{{index .Options "com.docker.network.bridge.gateway_mode_ipv6"}}|{{index .Options "com.docker.network.bridge.trusted_host_interfaces"}}|{{len .Containers}}' \
            "$network_id" 2>/dev/null)" || {
            err "无法读取 Docker 网络配置：$network_name"
            return 1
        }
        IFS='|' read -r bridge_name gateway_v4 gateway_v6 trusted_interfaces connected_count <<< "$network_data"
        case "$network_driver" in
            bridge)
                case "$gateway_v4,$gateway_v6" in
                    *routed*|*nat-unprotected*)
                        err "Docker 网络 $network_name 使用 $gateway_v4/$gateway_v6 直连模式，已拒绝更新。"
                        return 1
                        ;;
                esac
                if [ -n "$trusted_interfaces" ] && [ "$trusted_interfaces" != "<no value>" ]; then
                    err "Docker 网络 $network_name 允许可信接口直连，已拒绝更新。"
                    return 1
                fi
                if [ -z "$bridge_name" ] || [ "$bridge_name" = "<no value>" ]; then
                    if [ "$network_name" = "bridge" ]; then
                        bridge_name="docker0"
                    else
                        bridge_name="br-${network_id:0:12}"
                    fi
                fi
                is_valid_interface_name "$bridge_name" || {
                    err "Docker 返回了无效 bridge 接口名：$bridge_name"
                    return 1
                }
                [ -d "/sys/class/net/$bridge_name/bridge" ] || {
                    err "Docker 返回的接口不是可用 Linux bridge：$bridge_name"
                    return 1
                }
                case "$bridge_name" in
                    docker0|br-*) ;;
                    *) FW_DOCKER_CUSTOM_BRIDGE=1 ;;
                esac
                FW_DOCKER_BRIDGES="$(interface_csv_add "$FW_DOCKER_BRIDGES" "$bridge_name")"
                ;;
            host|none|null) ;;
            *)
                if [[ "$connected_count" =~ ^[1-9][0-9]*$ ]]; then
                    FW_DOCKER_DIRECT_NETWORK=1
                    err "Docker 网络 $network_name 使用 $network_driver 且连接了容器，当前无法安全接管。"
                    return 1
                fi
                ;;
        esac
    done <<< "$network_list"

    firewall_detect_docker_proxy_ports || {
        err "docker-proxy 监听与 Docker 发布端口不一致，已拒绝更新防火墙。"
        return 1
    }
    firewall_docker_daemon_identity_unchanged || {
        err "Docker daemon 在检查期间发生变化，已拒绝使用可能不一致的端口结果。"
        return 1
    }

}

docker_reserved_ports_csv() {
    local protocols="${1:-both}"
    local docker_host context endpoint effective_endpoint container container_list
    local bindings mapping host_port binding_protocol running port_mappings swarm_state control_available
    local service service_list published_ports port reserved=""
    local daemon_pid daemon_start_ticks current_pid current_start_ticks

    case "$protocols" in
        tcp|udp|both) ;;
        *) return 2 ;;
    esac

    if ! command -v docker >/dev/null 2>&1; then
        docker_daemon_process_present || return 0
        err "检测到 dockerd 进程但缺少 docker CLI，无法可靠检查保留端口。"
        return 1
    fi
    docker_host="${DOCKER_HOST:-}"
    case "$docker_host" in
        ""|unix:///*) ;;
        *)
            err "检测到远程 DOCKER_HOST，无法据此判断本机 Docker 保留端口。"
            return 1
            ;;
    esac
    context="$(docker_with_timeout context show 2>/dev/null)" || return 1
    endpoint="$(docker_with_timeout context inspect --format '{{.Endpoints.docker.Host}}' "$context" 2>/dev/null)" || return 1
    effective_endpoint="${docker_host:-$endpoint}"
    case "$effective_endpoint" in
        unix:///*) ;;
        *)
            err "Docker 当前连接不是本机 Unix socket，无法可靠检查保留端口。"
            return 1
            ;;
    esac
    docker_with_timeout info >/dev/null 2>&1 || {
        err "检测到 Docker 命令，但无法连接本机 Docker daemon。"
        return 1
    }
    daemon_pid="$(docker_single_daemon_pid)" || {
        err "无法确认唯一的本机 dockerd 进程，已拒绝使用不完整的保留端口结果。"
        return 1
    }
    daemon_start_ticks="$(awk '{ print $22; exit }' "/proc/$daemon_pid/stat" 2>/dev/null || true)"
    [[ "$daemon_start_ticks" =~ ^[0-9]+$ ]] || return 1

    container_list="$(docker_with_timeout ps -aq 2>/dev/null)" || return 1
    while IFS= read -r container; do
        [ -n "$container" ] || continue
        bindings="$(docker_with_timeout inspect --format \
            '{{range $port, $bindings := .HostConfig.PortBindings}}{{range $bindings}}{{printf "%s|%s|%s\n" $port .HostIp .HostPort}}{{end}}{{end}}' \
            "$container" 2>/dev/null)" || return 1
        while IFS= read -r mapping; do
            [ -n "$mapping" ] || continue
            binding_protocol="${mapping%%|*}"
            binding_protocol="${binding_protocol##*/}"
            case "$binding_protocol" in
                tcp|udp) ;;
                *) continue ;;
            esac
            host_port="${mapping##*|}"
            [ -z "$host_port" ] || [ "$host_port" = "0" ] || {
                is_valid_port "$host_port" || return 1
                if [ "$protocols" = "both" ] || [ "$protocols" = "$binding_protocol" ]; then
                    reserved="$(csv_add_port "$reserved" "$host_port")" || return 1
                fi
            }
        done <<< "$bindings"

        running="$(docker_with_timeout inspect --format '{{.State.Running}}' "$container" 2>/dev/null)" || return 1
        [ "$running" = "true" ] || continue
        port_mappings="$(docker_with_timeout port "$container" 2>/dev/null)" || return 1
        while IFS= read -r mapping; do
            [ -n "$mapping" ] || continue
            binding_protocol="${mapping%% ->*}"
            binding_protocol="${binding_protocol##*/}"
            case "$binding_protocol" in
                tcp|udp) ;;
                *) continue ;;
            esac
            host_port="${mapping##*:}"
            is_valid_port "$host_port" || return 1
            if [ "$protocols" = "both" ] || [ "$protocols" = "$binding_protocol" ]; then
                reserved="$(csv_add_port "$reserved" "$host_port")" || return 1
            fi
        done <<< "$port_mappings"
    done <<< "$container_list"

    swarm_state="$(docker_with_timeout info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null)" || return 1
    if [ "$swarm_state" != "inactive" ]; then
        [ "$swarm_state" = "active" ] || {
            err "Docker Swarm 状态为 $swarm_state，无法可靠枚举保留端口。"
            return 1
        }
        control_available="$(docker_with_timeout info --format '{{.Swarm.ControlAvailable}}' 2>/dev/null)" || return 1
        [ "$control_available" = "true" ] || {
            err "当前 Swarm 节点不是 manager，无法可靠枚举服务发布端口。"
            return 1
        }
        service_list="$(docker_with_timeout service ls -q 2>/dev/null)" || return 1
        while IFS= read -r service; do
            [ -n "$service" ] || continue
            published_ports="$(docker_with_timeout service inspect --format \
                '{{range .Endpoint.Spec.Ports}}{{printf "%d|%s\n" .PublishedPort .Protocol}}{{end}}' \
                "$service" 2>/dev/null)" || return 1
            while IFS='|' read -r port binding_protocol; do
                [ -n "$port" ] || continue
                case "$binding_protocol" in
                    tcp|udp) ;;
                    *) continue ;;
                esac
                is_valid_port "$port" || return 1
                if [ "$protocols" = "both" ] || [ "$protocols" = "$binding_protocol" ]; then
                    reserved="$(csv_add_port "$reserved" "$port")" || return 1
                fi
            done <<< "$published_ports"
        done <<< "$service_list"
    fi
    current_pid="$(docker_single_daemon_pid)" || return 1
    current_start_ticks="$(awk '{ print $22; exit }' "/proc/$current_pid/stat" 2>/dev/null || true)"
    [ "$current_pid" = "$daemon_pid" ] && [ "$current_start_ticks" = "$daemon_start_ticks" ] || {
        err "Docker daemon 在端口枚举期间发生变化，已拒绝使用结果。"
        return 1
    }
    printf '%s\n' "$reserved"
}

docker_reserved_ports_for_port_choice() {
    local protocols="${1:-both}" result

    if result="$(docker_reserved_ports_csv "$protocols")"; then
        printf '%s\n' "$result"
        return 0
    fi
    if firewall_control_plane_present; then
        [ -z "$result" ] || printf '%s\n' "$result" >&2
        return 1
    fi
    warn "无法可靠读取 Docker 已发布端口；当前未启用 vpsbox 防火墙，本次仅检查系统实际监听端口。Docker 恢复后请确认没有端口冲突。" >&2
    printf '\n'
}

firewall_detect_public_listeners() {
    local records scope protocol port _addr _proc_name

    FW_PUBLIC_TCP=""
    FW_PUBLIC_UDP=""
    records="$(collect_listening_sockets)" || return 1
    while IFS='|' read -r scope protocol port _addr _proc_name; do
        [ "$scope" = "public" ] || continue
        case "$protocol" in
            tcp) FW_PUBLIC_TCP="$(csv_add_port "$FW_PUBLIC_TCP" "$port")" || return 1 ;;
            udp) FW_PUBLIC_UDP="$(csv_add_port "$FW_PUBLIC_UDP" "$port")" || return 1 ;;
        esac
    done <<< "$records"
}

firewall_detect_allowed_ports() {
    local ssh_configured_ports ssh_listening_ports known_tcp known_udp protocol label

    ssh_configured_ports="$(ssh_effective_ports_csv 2>/dev/null || true)"
    [ -n "$ssh_configured_ports" ] || {
        err "无法读取 SSH 当前实际生效端口，已拒绝启用防火墙。"
        return 1
    }
    ssh_listening_ports="$(ssh_listening_ports_csv 2>/dev/null)" || {
        err "无法可靠读取 SSH 实际监听端口，已拒绝更新防火墙。"
        return 1
    }
    FW_SSH_PORTS="$(merge_port_csv "$ssh_configured_ports" "$ssh_listening_ports")" || return 1

    FW_NODE_TCP=""
    FW_NODE_UDP=""
    require_valid_node_state_if_present || return 1
    for protocol in vless ss; do
        protocol_visible_exists "$protocol" || continue
        label="$(node_protocol_display_name "$protocol")" || return 1
        load_protocol_state "$protocol" || return 1
        is_valid_port "${PORT:-}" || {
            err "$label 节点端口无效，已拒绝生成防火墙规则。"
            return 1
        }
        FW_NODE_TCP="$(csv_add_port "$FW_NODE_TCP" "$PORT")" || return 1
        if [ "$protocol" = "ss" ]; then
            FW_NODE_UDP="$(csv_add_port "$FW_NODE_UDP" "$PORT")" || return 1
        fi
    done

    firewall_detect_docker_ports || return 1
    firewall_detect_public_listeners || return 1
    known_tcp="$(merge_port_csv "$FW_SSH_PORTS" "$FW_NODE_TCP" "$FW_DOCKER_PUBLIC_TCP" "$FW_EXTRA_TCP")" || return 1
    known_udp="$(merge_port_csv "$FW_NODE_UDP" "$FW_DOCKER_PUBLIC_UDP" "$FW_EXTRA_UDP")" || return 1
    FW_OTHER_PUBLIC_TCP="$(subtract_port_csv "$FW_PUBLIC_TCP" "$known_tcp")" || return 1
    FW_OTHER_PUBLIC_UDP="$(subtract_port_csv "$FW_PUBLIC_UDP" "$known_udp")" || return 1
    FW_ALLOWED_TCP="$(merge_port_csv "$FW_SSH_PORTS" "$FW_NODE_TCP" "$FW_PUBLIC_TCP" "$FW_EXTRA_TCP")" || return 1
    FW_ALLOWED_UDP="$(merge_port_csv "$FW_NODE_UDP" "$FW_PUBLIC_UDP" "$FW_EXTRA_UDP")" || return 1
}

firewall_write_config() {
    local dest="$1" tcp_ports udp_ports
    local docker4_tcp docker4_udp docker6_tcp docker6_udp
    local docker_bridges docker_bridge_elements extra_tcp extra_udp
    local proxy4_tcp proxy4_udp proxy6_tcp proxy6_udp

    tcp_ports="$(printf '%s' "$FW_ALLOWED_TCP" | sed 's/,/, /g')"
    udp_ports="$(printf '%s' "$FW_ALLOWED_UDP" | sed 's/,/, /g')"
    docker4_tcp="$(normalize_port_csv "$FW_DOCKER_PUBLIC4_TCP")" || return 1
    docker4_udp="$(normalize_port_csv "$FW_DOCKER_PUBLIC4_UDP")" || return 1
    docker6_tcp="$(normalize_port_csv "$FW_DOCKER_PUBLIC6_TCP")" || return 1
    docker6_udp="$(normalize_port_csv "$FW_DOCKER_PUBLIC6_UDP")" || return 1
    extra_tcp="$(normalize_port_csv "$FW_EXTRA_TCP")" || return 1
    extra_udp="$(normalize_port_csv "$FW_EXTRA_UDP")" || return 1
    docker_bridges="$(normalize_interface_csv "$FW_DOCKER_BRIDGES")" || return 1
    if [ -n "$docker4_tcp$docker4_udp$docker6_tcp$docker6_udp" ] && [ -z "$docker_bridges" ]; then
        err "检测到 Docker 公开端口，但没有可验证的 Docker bridge。"
        return 1
    fi
    if [ -n "$docker_bridges" ]; then
        docker_bridge_elements="$(printf '%s\n' "$docker_bridges" | awk -F, '{
            for (i = 1; i <= NF; i++) printf "%s\"%s\"", (i == 1 ? "" : ", "), $i
        }')"
    else
        docker_bridge_elements=""
    fi
    proxy4_tcp="$(printf '%s' "$FW_DOCKER_PROXY4_TCP" | sed 's/,/, /g')"
    proxy4_udp="$(printf '%s' "$FW_DOCKER_PROXY4_UDP" | sed 's/,/, /g')"
    proxy6_tcp="$(printf '%s' "$FW_DOCKER_PROXY6_TCP" | sed 's/,/, /g')"
    proxy6_udp="$(printf '%s' "$FW_DOCKER_PROXY6_UDP" | sed 's/,/, /g')"
    cat > "$dest" <<'EOF'
# Managed by vpsbox. Replace only the dedicated table; never flush the global ruleset.
delete table inet vpsbox

table inet vpsbox {
EOF
    if [ -n "$docker_bridge_elements" ]; then
        printf '    set docker_bridge_ifaces {\n        type ifname\n        elements = { %s }\n    }\n\n' \
            "$docker_bridge_elements" >> "$dest"
    fi
    if [ -n "$docker4_tcp" ]; then
        printf '    set docker4_tcp_ports {\n        type inet_service\n        elements = { %s }\n    }\n\n' \
            "$(printf '%s' "$docker4_tcp" | sed 's/,/, /g')" >> "$dest"
    fi
    if [ -n "$docker4_udp" ]; then
        printf '    set docker4_udp_ports {\n        type inet_service\n        elements = { %s }\n    }\n\n' \
            "$(printf '%s' "$docker4_udp" | sed 's/,/, /g')" >> "$dest"
    fi
    if [ -n "$docker6_tcp" ]; then
        printf '    set docker6_tcp_ports {\n        type inet_service\n        elements = { %s }\n    }\n\n' \
            "$(printf '%s' "$docker6_tcp" | sed 's/,/, /g')" >> "$dest"
    fi
    if [ -n "$docker6_udp" ]; then
        printf '    set docker6_udp_ports {\n        type inet_service\n        elements = { %s }\n    }\n\n' \
            "$(printf '%s' "$docker6_udp" | sed 's/,/, /g')" >> "$dest"
    fi
    if [ -n "$extra_tcp" ]; then
        printf '    set extra_tcp_dnat_ports {\n        type inet_service\n        elements = { %s }\n    }\n\n' \
            "$(printf '%s' "$extra_tcp" | sed 's/,/, /g')" >> "$dest"
    fi
    if [ -n "$extra_udp" ]; then
        printf '    set extra_udp_dnat_ports {\n        type inet_service\n        elements = { %s }\n    }\n\n' \
            "$(printf '%s' "$extra_udp" | sed 's/,/, /g')" >> "$dest"
    fi

    cat >> "$dest" <<'EOF'
    chain input {
        type filter hook input priority filter; policy drop;

        ct state invalid drop
        ct state established,related accept
        iifname "lo" accept

        ip protocol icmp accept
        meta l4proto ipv6-icmp accept

        meta nfproto ipv4 udp sport 67 udp dport 68 accept
        meta nfproto ipv6 udp sport 547 udp dport 546 accept
EOF
    [ -n "$tcp_ports" ] && printf '        tcp dport { %s } accept\n' "$tcp_ports" >> "$dest"
    [ -n "$udp_ports" ] && printf '        udp dport { %s } accept\n' "$udp_ports" >> "$dest"
    [ -n "$proxy4_tcp" ] && printf '        meta nfproto ipv4 tcp dport { %s } accept\n' "$proxy4_tcp" >> "$dest"
    [ -n "$proxy4_udp" ] && printf '        meta nfproto ipv4 udp dport { %s } accept\n' "$proxy4_udp" >> "$dest"
    [ -n "$proxy6_tcp" ] && printf '        meta nfproto ipv6 tcp dport { %s } accept\n' "$proxy6_tcp" >> "$dest"
    [ -n "$proxy6_udp" ] && printf '        meta nfproto ipv6 udp dport { %s } accept\n' "$proxy6_udp" >> "$dest"
    cat >> "$dest" <<'EOF'
    }
EOF
    cat >> "$dest" <<'EOF'

    chain docker_port_guard {
EOF
    if [ -n "$extra_tcp" ]; then
        printf '        meta l4proto tcp ct original proto-dst @extra_tcp_dnat_ports accept\n' >> "$dest"
    fi
    if [ -n "$docker4_tcp" ]; then
        printf '        meta nfproto ipv4 meta l4proto tcp oifname @docker_bridge_ifaces ct original proto-dst @docker4_tcp_ports accept\n' >> "$dest"
    fi
    if [ -n "$docker6_tcp" ]; then
        printf '        meta nfproto ipv6 meta l4proto tcp oifname @docker_bridge_ifaces ct original proto-dst @docker6_tcp_ports accept\n' >> "$dest"
    fi
    printf '        meta l4proto tcp drop\n' >> "$dest"
    if [ -n "$extra_udp" ]; then
        printf '        meta l4proto udp ct original proto-dst @extra_udp_dnat_ports accept\n' >> "$dest"
    fi
    if [ -n "$docker4_udp" ]; then
        printf '        meta nfproto ipv4 meta l4proto udp oifname @docker_bridge_ifaces ct original proto-dst @docker4_udp_ports accept\n' >> "$dest"
    fi
    if [ -n "$docker6_udp" ]; then
        printf '        meta nfproto ipv6 meta l4proto udp oifname @docker_bridge_ifaces ct original proto-dst @docker6_udp_ports accept\n' >> "$dest"
    fi
    printf '        meta l4proto udp drop\n' >> "$dest"
    printf '        drop\n' >> "$dest"
    cat >> "$dest" <<'EOF'
    }

    chain docker_forward {
        type filter hook forward priority -1; policy accept;

        ct state established,related accept
EOF
    if [ -n "$docker_bridge_elements" ]; then
        printf '        iifname @docker_bridge_ifaces accept\n' >> "$dest"
    fi
    printf '        ct direction original ct status dnat jump docker_port_guard\n' >> "$dest"
    if [ -n "$docker_bridge_elements" ]; then
        printf '        oifname @docker_bridge_ifaces drop\n' >> "$dest"
    fi
    cat >> "$dest" <<'EOF'
    }
EOF
    cat >> "$dest" <<'EOF'
}
EOF
}

firewall_write_service_definition() {
    local dest="$1" nft_path
    nft_path="$(command -v nft)" || return 1

    if is_systemd; then
        cat > "$dest" <<EOF
[Unit]
Description=vpsbox host firewall
DefaultDependencies=no
Wants=network-pre.target
Before=network-pre.target shutdown.target
Conflicts=shutdown.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStartPre=-$nft_path add table inet vpsbox
ExecStart=$nft_path -f $FIREWALL_CONFIG
ExecStop=-$nft_path delete table inet vpsbox

[Install]
WantedBy=sysinit.target
EOF
    elif [ "$OS" = "alpine" ] && command -v rc-update >/dev/null 2>&1; then
        cat > "$dest" <<EOF
#!/sbin/openrc-run
description="vpsbox host firewall"

depend() {
    need localmount
    before net
}

start() {
    ebegin "Loading vpsbox host firewall"
    $nft_path add table inet vpsbox >/dev/null 2>&1 || true
    $nft_path -f $FIREWALL_CONFIG
    eend \$?
}

stop() {
    ebegin "Removing vpsbox host firewall"
    $nft_path delete table inet vpsbox >/dev/null 2>&1 || true
    eend 0
}
EOF
    else
        err "未检测到受支持的 systemd/OpenRC 服务管理器。"
        return 1
    fi
}

firewall_snapshot_file() {
    local dir="$1" name="$2" path="$3"
    if [ -e "$path" ]; then
        [ ! -L "$path" ] || return 1
        cp -a "$path" "$dir/$name" || return 1
        : > "$dir/$name.present"
    fi
}

firewall_prepare_rollback_store() {
    [ ! -L "$VPSBOX_STATE_DIR" ] && [ ! -L "$FIREWALL_ROLLBACK_DIR" ] || {
        err "防火墙回滚目录包含符号链接，已拒绝使用。"
        return 1
    }
    mkdir -p "$FIREWALL_ROLLBACK_DIR" || return 1
    chown root:root "$FIREWALL_ROLLBACK_DIR" || return 1
    chmod 700 "$FIREWALL_ROLLBACK_DIR" || return 1
}

firewall_rollback_dir_valid() {
    local dir="${1:-}"

    case "$dir" in
        "$FIREWALL_ROLLBACK_DIR"/firewall-rollback.*) ;;
        # 兼容 v1.0.25 及更早版本在 /run/vpsbox 中留下、尚未完成的回滚快照。
        "$RUNTIME_DIR"/firewall-rollback.*) ;;
        *) return 1 ;;
    esac
    [ -d "$dir" ] && [ ! -L "$dir" ]
}

firewall_watchdog_cmdline_matches() {
    local dir="$1" pid="$2"
    local -a args=()

    firewall_rollback_dir_valid "$dir" || return 1
    is_pid "$pid" && [ "$pid" -gt 1 ] && [ "$pid" -ne "$$" ] || return 1
    process_alive "$pid" || return 1
    process_is_zombie "$pid" && return 1
    [ -r "/proc/$pid/cmdline" ] || return 1
    mapfile -d '' -t args < "/proc/$pid/cmdline" 2>/dev/null || true
    [ "${#args[@]}" -eq 2 ] || return 1
    case "${args[0]}" in
        sh|*/sh) ;;
        *) return 1 ;;
    esac
    [ "${args[1]}" = "$dir/rollback.sh" ]
}

firewall_watchdog_process_matches() {
    local dir="$1" pid="$2" expected_start="$3"

    firewall_watchdog_cmdline_matches "$dir" "$pid" || return 1
    [ "$(process_start_ticks "$pid" 2>/dev/null || true)" = "$expected_start" ]
}

firewall_watchdog_identity_matches() {
    local dir="$1" pid="$2"
    local path recorded_pid recorded_start recorded_boot current_start current_boot

    firewall_rollback_dir_valid "$dir" || return 2
    is_pid "$pid" && [ "$pid" -gt 1 ] && [ "$pid" -ne "$$" ] || return 2
    for path in "$dir/watchdog.pid" "$dir/watchdog.start" "$dir/watchdog.boot"; do
        [ -f "$path" ] && [ ! -L "$path" ] || return 2
    done
    IFS= read -r recorded_pid < "$dir/watchdog.pid" || return 2
    IFS= read -r recorded_start < "$dir/watchdog.start" || return 2
    IFS= read -r recorded_boot < "$dir/watchdog.boot" || return 2
    [ "$recorded_pid" = "$pid" ] && [[ "$recorded_start" =~ ^[0-9]+$ ]] &&
        [ -n "$recorded_boot" ] || return 2

    process_alive "$pid" || return 1
    process_is_zombie "$pid" && return 1
    current_start="$(process_start_ticks "$pid" || true)"
    current_boot="$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || true)"
    [ -n "$current_start" ] && [ "$recorded_start" = "$current_start" ] || return 1
    [ -n "$current_boot" ] && [ "$recorded_boot" = "$current_boot" ] || return 1
    firewall_watchdog_cmdline_matches "$dir" "$pid" || return 1
}

firewall_sleep_process_matches() {
    local pid="$1" expected_start="$2"
    local -a args=()

    process_alive "$pid" || return 1
    process_is_zombie "$pid" && return 1
    [ "$(process_start_ticks "$pid" 2>/dev/null || true)" = "$expected_start" ] || return 1
    [ -r "/proc/$pid/cmdline" ] || return 1
    mapfile -d '' -t args < "/proc/$pid/cmdline" 2>/dev/null || true
    [ "${#args[@]}" -eq 2 ] || return 1
    case "${args[0]}" in
        sleep|*/sleep) ;;
        *) return 1 ;;
    esac
    # 兼容 v1.0.16-v1.0.18 的一次性 sleep 90：脚本升级后仍需能终止旧快照留下的等待进程。
    # 当前 watchdog 使用 sleep 1 轮询；这里只接受两种精确参数，避免误杀其他 sleep。
    [ "${args[1]}" = "1" ] || [ "${args[1]}" = "$FIREWALL_ROLLBACK_SECONDS" ]
}

firewall_watchdog_sleep_records() {
    local parent="$1" child start children

    children="$(cat "/proc/$parent/task/$parent/children" 2>/dev/null || true)"
    for child in $children; do
        is_pid "$child" || continue
        start="$(process_start_ticks "$child" 2>/dev/null || true)"
        [[ "$start" =~ ^[0-9]+$ ]] || continue
        firewall_sleep_process_matches "$child" "$start" || continue
        printf '%s:%s\n' "$child" "$start"
    done
}

firewall_stop_recorded_sleeps() {
    local records="$1" record pid start i failed=0

    for record in $records; do
        pid="${record%%:*}"
        start="${record#*:}"
        firewall_sleep_process_matches "$pid" "$start" || continue
        kill -TERM "$pid" 2>/dev/null || true
        for i in {1..10}; do
            firewall_sleep_process_matches "$pid" "$start" || break
            sleep 0.1
        done
        if firewall_sleep_process_matches "$pid" "$start"; then
            kill -KILL "$pid" 2>/dev/null || true
        fi
        for i in {1..10}; do
            firewall_sleep_process_matches "$pid" "$start" || break
            sleep 0.1
        done
        firewall_sleep_process_matches "$pid" "$start" && failed=1
    done
    [ "$failed" -eq 0 ]
}

firewall_forget_watchdog_metadata() {
    local dir="$1"

    rm -f "$dir/watchdog.pid" "$dir/watchdog.start" "$dir/watchdog.boot"
}

firewall_wait_watchdog_exit() {
    local pid="$1" i

    for i in {1..20}; do
        if ! process_alive "$pid" || process_is_zombie "$pid"; then
            wait "$pid" 2>/dev/null || true
            return 0
        fi
        sleep 0.1
    done
    return 1
}

firewall_stop_verified_watchdog() {
    local dir="$1" pid="$2" start="$3" status sleep_records

    firewall_watchdog_process_matches "$dir" "$pid" "$start" || return 0
    sleep_records="$(firewall_watchdog_sleep_records "$pid")"
    if firewall_wait_watchdog_exit "$pid"; then
        firewall_stop_recorded_sleeps "$sleep_records"
        return $?
    fi

    firewall_stop_recorded_sleeps "$sleep_records" || status=1
    if firewall_wait_watchdog_exit "$pid"; then
        return "${status:-0}"
    fi
    firewall_watchdog_process_matches "$dir" "$pid" "$start" || return "${status:-0}"

    kill -TERM "$pid" 2>/dev/null || true
    if firewall_wait_watchdog_exit "$pid"; then
        return "${status:-0}"
    fi
    firewall_watchdog_process_matches "$dir" "$pid" "$start" || return "${status:-0}"

    kill -KILL "$pid" 2>/dev/null || true
    if firewall_wait_watchdog_exit "$pid"; then
        return "${status:-0}"
    fi
    return 1
}

firewall_find_watchdog_pids() {
    local dir="$1" proc pid

    for proc in /proc/[0-9]*; do
        [ -d "$proc" ] || continue
        pid="${proc##*/}"
        firewall_watchdog_cmdline_matches "$dir" "$pid" || continue
        printf '%s\n' "$pid"
    done
}

firewall_stop_rollback_watchdog() {
    local dir="$1" path pid start found_pid

    firewall_rollback_dir_valid "$dir" || return 1
    for path in "$dir/watchdog.pid" "$dir/watchdog.start" "$dir/watchdog.boot"; do
        [ ! -e "$path" ] || { [ -f "$path" ] && [ ! -L "$path" ]; } || {
            warn "防火墙回滚进程元数据路径不安全，已保留快照：$dir"
            return 1
        }
    done
    if [ -e "$dir/watchdog.pid" ]; then
        IFS= read -r pid < "$dir/watchdog.pid" || pid=""
        if is_pid "$pid" && [ "$pid" -gt 1 ] && [ "$pid" -ne "$$" ]; then
            # 兼容 v1.0.16-v1.0.18 仅写 watchdog.pid 的快照：升级后旧快照仍可能待回滚。
            # 缺少身份字段时必须再核对精确脚本命令行，避免 PID 复用导致误杀；该分支也处理当前版本分步落盘中断。
            if [ -e "$dir/watchdog.start" ] && [ -e "$dir/watchdog.boot" ]; then
                if firewall_watchdog_identity_matches "$dir" "$pid"; then
                    start="$(process_start_ticks "$pid")"
                fi
            fi
            if [ -z "${start:-}" ] && firewall_watchdog_cmdline_matches "$dir" "$pid"; then
                start="$(process_start_ticks "$pid" 2>/dev/null || true)"
            fi
            if [[ "${start:-}" =~ ^[0-9]+$ ]]; then
                firewall_stop_verified_watchdog "$dir" "$pid" "$start" || {
                    warn "防火墙回滚进程未能退出，快照已保留：$dir"
                    return 1
                }
            elif process_is_zombie "$pid"; then
                wait "$pid" 2>/dev/null || true
            fi
        else
            warn "防火墙回滚进程 PID 元数据无效，将按脚本路径安全扫描：$dir"
        fi
    fi

    # 兼容旧快照的空 PID、陈旧 PID，以及当前版本在元数据落盘前中断的情况。
    # PID 文件仅作快速定位，最终只扫描精确 rollback.sh 命令行，既能收敛遗留 watchdog 又避免误杀。
    while IFS= read -r found_pid; do
        [ -n "$found_pid" ] || continue
        start="$(process_start_ticks "$found_pid" 2>/dev/null || true)"
        [[ "$start" =~ ^[0-9]+$ ]] || continue
        firewall_stop_verified_watchdog "$dir" "$found_pid" "$start" || {
            warn "防火墙回滚进程未能退出，快照已保留：$dir"
            return 1
        }
    done < <(firewall_find_watchdog_pids "$dir")
    firewall_forget_watchdog_metadata "$dir"
    return 0
}

firewall_cleanup_finished_rollback() {
    local dir="$1"

    firewall_rollback_dir_valid "$dir" || return 1
    [ -e "$dir/completed" ] || [ -e "$dir/rolled-back" ] || return 1
    firewall_stop_rollback_watchdog "$dir" || return 1
    [ "${ACTIVE_FIREWALL_ROLLBACK_DIR:-}" = "$dir" ] && ACTIVE_FIREWALL_ROLLBACK_DIR=""
    rm -rf -- "$dir"
}

firewall_recover_pending_rollbacks() {
    local dir decision owner root

    prepare_runtime_dir
    firewall_prepare_rollback_store || return 1
    for root in "$FIREWALL_ROLLBACK_DIR" "$RUNTIME_DIR"; do
        for dir in "$root"/.firewall-rollback-build.*; do
            [ -e "$dir" ] || continue
            if [ ! -d "$dir" ] || [ -L "$dir" ]; then
                err "检测到不安全的防火墙回滚构建目录：$dir"
                return 1
            fi
            rm -rf "$dir" || return 1
        done
    done
    for root in "$FIREWALL_ROLLBACK_DIR" "$RUNTIME_DIR"; do
        for dir in "$root"/firewall-rollback.*; do
            [ -e "$dir" ] || continue
            if [ ! -d "$dir" ] || [ -L "$dir" ]; then
                err "检测到不安全的防火墙回滚目录：$dir"
                return 1
            fi
            if [ -e "$dir/completed" ] || [ -e "$dir/rolled-back" ]; then
                if ! firewall_cleanup_finished_rollback "$dir"; then
                    err "已完成的防火墙快照清理失败，已拒绝开始新的防火墙操作：$dir"
                    return 1
                fi
                continue
            fi
            decision="$(cat "$dir/decision" 2>/dev/null || true)"
            owner=0
            [ "$decision" = "commit" ] && owner=1
            warn "检测到未完成的防火墙操作，正在先恢复快照：$dir"
            if ! firewall_restore_snapshot_now "$dir" "$owner"; then
                err "旧防火墙快照尚未恢复，已拒绝开始新的防火墙操作。"
                return 1
            fi
        done
    done
}

firewall_create_rollback_snapshot() {
    local output_var="$1" ssh_ports="$2" dir build_dir final_dir suffix nft_path

    if [ -n "${ACTIVE_FIREWALL_ROLLBACK_DIR:-}" ]; then
        err "已有未完成的防火墙回滚快照，已拒绝创建新快照。"
        return 1
    fi
    firewall_prepare_rollback_store || return 1
    for dir in "$FIREWALL_ROLLBACK_DIR"/firewall-rollback.*; do
        [ -d "$dir" ] || continue
        err "检测到尚未处理的防火墙回滚目录：$dir"
        return 1
    done

    build_dir="$(mktemp -d "$FIREWALL_ROLLBACK_DIR/.firewall-rollback-build.XXXXXX")" || return 1
    suffix="${build_dir##*.firewall-rollback-build.}"
    final_dir="$FIREWALL_ROLLBACK_DIR/firewall-rollback.$suffix"
    if [ -e "$final_dir" ] || [ -L "$final_dir" ]; then
        rm -rf "$build_dir"
        err "防火墙回滚目录发生冲突，已拒绝继续。"
        return 1
    fi
    nft_path="$(command -v nft)" || { rm -rf "$build_dir"; return 1; }
    firewall_snapshot_file "$build_dir" config "$FIREWALL_CONFIG" &&
        firewall_snapshot_file "$build_dir" state "$FIREWALL_STATE_FILE" &&
        firewall_snapshot_file "$build_dir" systemd-unit "$FIREWALL_SYSTEMD_UNIT" &&
        firewall_snapshot_file "$build_dir" openrc-service "$FIREWALL_OPENRC_SERVICE" || {
            rm -rf "$build_dir"
            return 1
        }
    if firewall_runtime_enabled; then
        nft list table inet vpsbox > "$build_dir/table.nft" || { rm -rf "$build_dir"; return 1; }
        : > "$build_dir/table.present"
    fi
    if [ -e "$build_dir/config.present" ] &&
        ! firewall_write_ssh_safe_snapshot "$build_dir/config" "$build_dir/config" "$ssh_ports"; then
        rm -rf "$build_dir"
        return 1
    fi
    if [ -e "$build_dir/table.present" ] &&
        ! firewall_write_ssh_safe_snapshot "$build_dir/table.nft" "$build_dir/table.nft" "$ssh_ports"; then
        rm -rf "$build_dir"
        return 1
    fi
    firewall_persistence_enabled && : > "$build_dir/service.enabled"
    firewall_service_active && : > "$build_dir/service.active"

    printf '%s\n' commit > "$build_dir/commit.token" || { rm -rf "$build_dir"; return 1; }
    printf '%s\n' rollback > "$build_dir/rollback.token" || { rm -rf "$build_dir"; return 1; }

    if ! cat > "$build_dir/rollback.sh" <<EOF
#!/bin/sh
set -u
dir='$final_dir'
nft='$nft_path'
failed=0
mode="\${1:-}"
sleep_pid=''

stop_watchdog_wait() {
    if [ -n "\$sleep_pid" ]; then
        kill -TERM "\$sleep_pid" 2>/dev/null || true
        wait "\$sleep_pid" 2>/dev/null || true
    fi
    exit 0
}

restore_lock_process_start() {
    awk '{ print \$22 }' "/proc/\$1/stat" 2>/dev/null
}

restore_lock_metadata_value() {
    metadata_file="\$1"
    metadata_key="\$2"
    awk -F= -v key="\$metadata_key" '\$1 == key { print substr(\$0, length(key) + 2); exit }' \
        "\$metadata_file" 2>/dev/null
}

restore_lock_metadata_ready() {
    lock_dir="\$dir/restore.lock"
    [ -s "\$lock_dir/owner" ] ||
        { [ -s "\$lock_dir/pid" ] && [ -s "\$lock_dir/start" ] && [ -s "\$lock_dir/boot" ]; }
}

restore_lock_owner_matches() {
    lock_dir="\$dir/restore.lock"
    [ -d "\$lock_dir" ] && [ ! -L "\$lock_dir" ] || return 1
    if [ -s "\$lock_dir/owner" ] && [ ! -L "\$lock_dir/owner" ]; then
        lock_pid="\$(restore_lock_metadata_value "\$lock_dir/owner" pid)" || return 1
        lock_start="\$(restore_lock_metadata_value "\$lock_dir/owner" start)" || return 1
        lock_boot="\$(restore_lock_metadata_value "\$lock_dir/owner" boot)" || return 1
    else
        # 兼容 v1.0.32 及更早版本生成的 pid/start/boot 三文件锁。
        lock_pid="\$(cat "\$lock_dir/pid" 2>/dev/null)" || return 1
        lock_start="\$(cat "\$lock_dir/start" 2>/dev/null)" || return 1
        lock_boot="\$(cat "\$lock_dir/boot" 2>/dev/null)" || return 1
    fi
    case "\$lock_pid:\$lock_start" in
        *[!0-9:]*|:*|*:) return 1 ;;
    esac
    kill -0 "\$lock_pid" 2>/dev/null || return 1
    [ "\$(restore_lock_process_start "\$lock_pid")" = "\$lock_start" ] &&
        [ "\$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)" = "\$lock_boot" ]
}

cleanup_restore_lock() {
    lock_dir="\$dir/restore.lock"
    rm -f "\$lock_dir/owner" "\$lock_dir/pid" "\$lock_dir/start" "\$lock_dir/boot" \
        "\$dir/.restore.lock.owner.\$\$"
    rmdir "\$lock_dir" >/dev/null 2>&1 || true
}

acquire_restore_lock() {
    lock_dir="\$dir/restore.lock"
    if ! mkdir "\$lock_dir" 2>/dev/null; then
        [ -d "\$lock_dir" ] && [ ! -L "\$lock_dir" ] || return 1
        lock_wait=0
        while [ "\$lock_wait" -lt 30 ] && ! restore_lock_metadata_ready; do
            sleep 0.1
            lock_wait=\$((lock_wait + 1))
        done
        restore_lock_owner_matches && return 2
        # 旧回滚进程被 SIGKILL 后可能遗留 restore.lock。只有持有者身份已失效，
        # 且目录中仅含 vpsbox 元数据时才回收，避免覆盖仍在执行的恢复。
        rm -f "\$lock_dir/owner" "\$lock_dir/pid" "\$lock_dir/start" "\$lock_dir/boot"
        rmdir "\$lock_dir" 2>/dev/null || return 1
        mkdir "\$lock_dir" 2>/dev/null || return 1
    fi
    lock_start="\$(restore_lock_process_start "\$\$")"
    lock_boot="\$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)"
    case "\$lock_start" in ''|*[!0-9]*) cleanup_restore_lock; return 1 ;; esac
    [ -n "\$lock_boot" ] || { cleanup_restore_lock; return 1; }
    owner_tmp="\$dir/.restore.lock.owner.\$\$"
    {
        printf 'pid=%s\n' "\$\$"
        printf 'start=%s\n' "\$lock_start"
        printf 'boot=%s\n' "\$lock_boot"
    } > "\$owner_tmp" &&
        chmod 600 "\$owner_tmp" &&
        mv -f "\$owner_tmp" "\$lock_dir/owner" || {
        cleanup_restore_lock
        return 1
    }
}

if [ "\$mode" != "--now" ] && [ "\$mode" != "--commit-owner" ]; then
    trap stop_watchdog_wait HUP INT TERM
    waited=0
    while [ "\$waited" -lt "$FIREWALL_ROLLBACK_SECONDS" ]; do
        [ -d "\$dir" ] || exit 0
        [ ! -e "\$dir/completed" ] || exit 0
        [ ! -e "\$dir/rolled-back" ] || exit 0
        sleep 1 &
        sleep_pid=\$!
        wait "\$sleep_pid" || exit 0
        sleep_pid=''
        waited=\$((waited + 1))
    done
    trap - HUP INT TERM
fi
[ -d "\$dir" ] || exit 0
[ ! -e "\$dir/completed" ] || exit 0
[ ! -e "\$dir/rolled-back" ] || exit 0

if [ "\$mode" = "--commit-owner" ]; then
    [ "\$(cat "\$dir/decision" 2>/dev/null)" = "commit" ] || exit 1
else
    if ! ln "\$dir/rollback.token" "\$dir/decision" 2>/dev/null; then
        case "\$(cat "\$dir/decision" 2>/dev/null)" in
            commit) exit 0 ;;
            rollback) ;;
            *) exit 1 ;;
        esac
    fi
fi

if acquire_restore_lock; then
    :
else
    restore_lock_status=\$?
    [ "\$restore_lock_status" -eq 2 ] && exit 0
    : > "\$dir/rollback-failed"
    exit 1
fi
trap cleanup_restore_lock EXIT
trap 'exit 1' HUP INT TERM
[ ! -e "\$dir/completed" ] || exit 0
[ ! -e "\$dir/rolled-back" ] || exit 0
rm -f "\$dir/rollback-failed"
: > "\$dir/restoring"

run_limited() {
    if command -v timeout >/dev/null 2>&1; then
        timeout 20 "\$@"
    else
        "\$@"
    fi
}

restore_file() {
    name="\$1"
    target="\$2"
    if [ -e "\$dir/\$name.present" ]; then
        cp -a "\$dir/\$name" "\$target" || return 1
    else
        rm -f "\$target" || return 1
    fi
}

restore_file config '$FIREWALL_CONFIG' || failed=1
restore_file state '$FIREWALL_STATE_FILE' || failed=1
restore_file systemd-unit '$FIREWALL_SYSTEMD_UNIT' || failed=1
restore_file openrc-service '$FIREWALL_OPENRC_SERVICE' || failed=1

if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
    run_limited systemctl daemon-reload || failed=1
    if [ -e "\$dir/service.enabled" ]; then
        run_limited systemctl enable '$FIREWALL_SERVICE_NAME' || failed=1
        systemctl is-enabled --quiet '$FIREWALL_SERVICE_NAME' 2>/dev/null || failed=1
    else
        run_limited systemctl disable '$FIREWALL_SERVICE_NAME' >/dev/null 2>&1 || true
        systemctl is-enabled --quiet '$FIREWALL_SERVICE_NAME' 2>/dev/null && failed=1
    fi
    if [ -e "\$dir/service.active" ]; then
        run_limited systemctl restart '$FIREWALL_SERVICE_NAME' || failed=1
        systemctl is-active --quiet '$FIREWALL_SERVICE_NAME' 2>/dev/null || failed=1
    else
        run_limited systemctl stop '$FIREWALL_SERVICE_NAME' >/dev/null 2>&1 || true
        systemctl is-active --quiet '$FIREWALL_SERVICE_NAME' 2>/dev/null && failed=1
    fi
elif command -v rc-update >/dev/null 2>&1; then
    if [ -e "\$dir/service.enabled" ]; then
        run_limited rc-update add '$FIREWALL_SERVICE_NAME' default || failed=1
        [ -e '/etc/runlevels/default/$FIREWALL_SERVICE_NAME' ] || failed=1
    else
        run_limited rc-update del '$FIREWALL_SERVICE_NAME' default >/dev/null 2>&1 || true
        [ ! -e '/etc/runlevels/default/$FIREWALL_SERVICE_NAME' ] || failed=1
    fi
    if [ -e "\$dir/service.active" ]; then
        run_limited rc-service '$FIREWALL_SERVICE_NAME' restart || failed=1
        rc-service '$FIREWALL_SERVICE_NAME' status >/dev/null 2>&1 || failed=1
    else
        run_limited rc-service '$FIREWALL_SERVICE_NAME' stop >/dev/null 2>&1 || true
        rc-service '$FIREWALL_SERVICE_NAME' status >/dev/null 2>&1 && failed=1
    fi
else
    failed=1
fi

"\$nft" delete table inet vpsbox >/dev/null 2>&1 || true
if [ -e "\$dir/table.present" ]; then
    "\$nft" -f "\$dir/table.nft" || failed=1
    "\$nft" list table inet vpsbox >/dev/null 2>&1 || failed=1
elif "\$nft" list table inet vpsbox >/dev/null 2>&1; then
    failed=1
fi

if [ "\$failed" -eq 0 ]; then
    rm -f "\$dir/restoring"
    : > "\$dir/rolled-back"
    exit 0
fi
: > "\$dir/rollback-failed"
exit 1
EOF
    then
        rm -rf "$build_dir"
        return 1
    fi
    chmod 700 "$build_dir/rollback.sh" || { rm -rf "$build_dir"; return 1; }
    sh -n "$build_dir/rollback.sh" || { rm -rf "$build_dir"; return 1; }

    # 仅完整快照使用正式前缀；中断时隐藏构建目录不会被当作待恢复操作。
    ACTIVE_FIREWALL_ROLLBACK_DIR="$final_dir"
    if ! mv "$build_dir" "$final_dir"; then
        ACTIVE_FIREWALL_ROLLBACK_DIR=""
        rm -rf "$build_dir"
        return 1
    fi
    printf -v "$output_var" '%s' "$final_dir"
}

firewall_start_rollback_watchdog() {
    local dir="$1" pid start boot
    firewall_rollback_dir_valid "$dir" || return 1
    : > "$dir/armed"
    # watchdog 必须独立于菜单存活以执行超时回滚，但不能继承菜单的 flock FD 200。
    nohup sh "$dir/rollback.sh" >> "$dir/rollback.log" 2>&1 200>&- &
    pid=$!
    start="$(process_start_ticks "$pid" || true)"
    boot="$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || true)"
    if ! process_alive "$pid" || ! [[ "$start" =~ ^[0-9]+$ ]] || [ -z "$boot" ] ||
        ! printf '%s\n' "$pid" > "$dir/watchdog.pid" ||
        ! printf '%s\n' "$start" > "$dir/watchdog.start" ||
        ! printf '%s\n' "$boot" > "$dir/watchdog.boot"; then
        kill -TERM "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
        firewall_forget_watchdog_metadata "$dir"
        return 1
    fi
}

firewall_restore_snapshot_now() {
    local dir="$1" commit_owner="${2:-0}" i mode="--now"

    if ! firewall_rollback_dir_valid "$dir"; then
        return 1
    fi
    if [ -e "$dir/completed" ]; then
        [ "${ACTIVE_FIREWALL_ROLLBACK_DIR:-}" = "$dir" ] && ACTIVE_FIREWALL_ROLLBACK_DIR=""
        firewall_cleanup_finished_rollback "$dir" ||
            warn "防火墙操作已提交，但回滚进程清理尚未完成：$dir"
        return 0
    fi
    [ -x "$dir/rollback.sh" ] || return 1
    [ "$commit_owner" = "1" ] && mode="--commit-owner"
    sh "$dir/rollback.sh" "$mode" >> "$dir/rollback.log" 2>&1 || true
    for i in {1..90}; do
        if [ -e "$dir/rolled-back" ]; then
            [ "${ACTIVE_FIREWALL_ROLLBACK_DIR:-}" = "$dir" ] && ACTIVE_FIREWALL_ROLLBACK_DIR=""
            firewall_cleanup_finished_rollback "$dir" ||
                warn "防火墙快照已恢复，但回滚进程清理尚未完成：$dir"
            return 0
        fi
        [ -e "$dir/rollback-failed" ] && {
            err "防火墙自动恢复失败，快照保留在：$dir"
            return 1
        }
        sleep 1
    done
    err "防火墙恢复结果无法确认，快照保留在：$dir"
    return 1
}

firewall_begin_commit() {
    local dir="$1"
    firewall_rollback_dir_valid "$dir" || return 1
    : > "$dir/committing" || return 1
    if ! ln "$dir/commit.token" "$dir/decision" 2>/dev/null; then
        rm -f "$dir/committing"
        return 1
    fi
}

firewall_finish_commit() {
    local dir="$1"

    firewall_rollback_dir_valid "$dir" || return 1
    [ "$(cat "$dir/decision" 2>/dev/null || true)" = "commit" ] || return 1
    : > "$dir/completed" || return 1
    ACTIVE_FIREWALL_ROLLBACK_DIR=""
    firewall_cleanup_finished_rollback "$dir" ||
        warn "防火墙规则已提交，但回滚进程清理尚未完成：$dir"
    return 0
}

firewall_apply_config_file() {
    local config="$1" table_existed=0

    firewall_runtime_enabled && table_existed=1
    if [ "$table_existed" -eq 0 ]; then
        nft add table inet vpsbox || return 1
    fi
    if ! nft -c -f "$config"; then
        [ "$table_existed" -eq 1 ] || nft delete table inet vpsbox >/dev/null 2>&1 || true
        return 1
    fi
    if ! nft -f "$config"; then
        [ "$table_existed" -eq 1 ] || nft delete table inet vpsbox >/dev/null 2>&1 || true
        return 1
    fi
}

firewall_enable_persistence() {
    command -v timeout >/dev/null 2>&1 || {
        err "缺少 timeout 命令，无法为防火墙持久化设置执行上限。"
        return 1
    }
    if is_systemd; then
        timeout 20 systemctl daemon-reload &&
            timeout 20 systemctl enable --now "$FIREWALL_SERVICE_NAME"
    elif [ "$OS" = "alpine" ] && command -v rc-update >/dev/null 2>&1; then
        timeout 20 rc-update add "$FIREWALL_SERVICE_NAME" default >/dev/null &&
            { timeout 20 rc-service "$FIREWALL_SERVICE_NAME" restart >/dev/null 2>&1 ||
                timeout 20 rc-service "$FIREWALL_SERVICE_NAME" start; }
    else
        return 1
    fi
}

firewall_show_port_summary() {
    cat <<EOF
----------------------------------------
 即将应用主机防火墙
 SSH TCP：${FW_SSH_PORTS:--}
 节点 TCP：${FW_NODE_TCP:--}
 节点 UDP：${FW_NODE_UDP:--}
 Docker TCP：${FW_DOCKER_PUBLIC_TCP:--}
 Docker UDP：${FW_DOCKER_PUBLIC_UDP:--}
 其他公网 TCP：${FW_OTHER_PUBLIC_TCP:--}
 其他公网 UDP：${FW_OTHER_PUBLIC_UDP:--}
 额外 TCP：${FW_EXTRA_TCP:--}
 额外 UDP：${FW_EXTRA_UDP:--}
 默认入站策略：拒绝
 出站：不创建规则
 Docker 转发：仅检查已发布端口，不限制容器出站
----------------------------------------
EOF
    if [ "$FW_DOCKER_HOST_NETWORK" = "1" ]; then
        warn "检测到 host 网络模式容器；当前公网监听已自动纳入，未启动服务请通过额外端口提前放行。"
    fi
    if [ "$FW_DOCKER_DYNAMIC_PORT" = "1" ]; then
        warn "检测到尚未确定的 Docker 随机发布端口；容器启动后请重新更新防火墙。"
    fi
    if [ "$FW_DOCKER_DIRECT_NETWORK" = "1" ]; then
        warn "检测到 Docker 直连网络；该模式不会由当前端口守卫自动放行。"
    fi
    if [ "$FW_DOCKER_CUSTOM_BRIDGE" = "1" ]; then
        warn "检测到自定义 Docker bridge 接口名；新增或变更该网络后必须重新更新防火墙。"
    fi
}

firewall_apply_desired_state() {
    local work_dir rollback_dir answer service_file service_target service_mode

    firewall_settle_pending_port_transition || return 1
    detect_os
    case "$OS" in
        debian|alpine) ;;
        *) err "主机防火墙目前仅支持 Debian/Ubuntu 与 Alpine。"; return 1 ;;
    esac
    firewall_recover_pending_rollbacks || return 1
    firewall_check_conflicts || return 1
    ensure_nftables || return 1
    firewall_check_conflicts || return 1
    firewall_detect_allowed_ports || return 1

    firewall_show_port_summary
    read -r -p "确认应用以上规则？请输入 YES：" answer || return 1
    [ "$answer" = "YES" ] || { info "已取消，未修改防火墙。"; return 0; }

    # 用户确认期间 ssh.socket、sshd、Docker 或公网监听可能变化；落盘前重新取一次实时状态。
    firewall_detect_allowed_ports || {
        err "确认后端口状态发生异常，未修改防火墙。"
        return 1
    }

    ensure_change_store || return 1
    work_dir="$(mktemp -d "$RUNTIME_DIR/firewall-work.XXXXXX")" || return 1
    firewall_write_state_file "$work_dir/firewall.env" || { rm -rf "$work_dir"; return 1; }
    firewall_write_config "$work_dir/firewall.nft" || { rm -rf "$work_dir"; return 1; }
    if is_systemd; then
        service_file="$work_dir/vpsbox-firewall.service"
        service_target="$FIREWALL_SYSTEMD_UNIT"
        service_mode=644
    else
        service_file="$work_dir/vpsbox-firewall"
        service_target="$FIREWALL_OPENRC_SERVICE"
        service_mode=755
    fi
    firewall_write_service_definition "$service_file" || { rm -rf "$work_dir"; return 1; }

    if ! firewall_create_rollback_snapshot rollback_dir "$FW_SSH_PORTS"; then
        rm -rf "$work_dir"
        err "无法创建防火墙回滚快照。"
        return 1
    fi
    if ! firewall_start_rollback_watchdog "$rollback_dir"; then
        err "无法启动自动回滚保护，正在恢复原状态。"
        if ! firewall_restore_snapshot_now "$rollback_dir"; then
            err "原状态恢复失败，必须先处理保留的回滚快照。"
        fi
        rm -rf "$work_dir"
        return 1
    fi
    # SSH 二次确认前只修改内核运行态，不覆盖开机配置。若此时异常重启，
    # 系统仍按原有持久配置启动；持久快照会在下次进入防火墙功能时继续恢复/清理。
    if ! firewall_apply_config_file "$work_dir/firewall.nft"; then
        err "防火墙临时配置校验或应用失败，正在恢复原状态。"
        if ! firewall_restore_snapshot_now "$rollback_dir"; then
            err "原状态恢复失败，必须先处理保留的回滚快照。"
        fi
        rm -rf "$work_dir"
        return 1
    fi

    info "规则已临时应用，$FIREWALL_ROLLBACK_SECONDS 秒内未确认将自动恢复。"
    warn "请保持当前 SSH 会话，并立即另开一个 SSH 窗口测试登录。"
    read -r -p "确认新 SSH 会话可以登录后，输入 YES 保存规则：" answer || answer=""
    if [ "$answer" != "YES" ]; then
        warn "未收到有效确认，正在恢复应用前的防火墙状态。"
        if ! firewall_restore_snapshot_now "$rollback_dir"; then
            err "原状态恢复失败，必须先处理保留的回滚快照。"
        fi
        rm -rf "$work_dir"
        return 1
    fi

    if ! firewall_begin_commit "$rollback_dir"; then
        err "确认前规则已经开始自动恢复，本次设置未保存。"
        if ! firewall_restore_snapshot_now "$rollback_dir"; then
            err "自动恢复尚未完成，已保留回滚快照。"
        fi
        rm -rf "$work_dir"
        return 1
    fi
    if ! firewall_install_managed_file "$work_dir/firewall.env" "$FIREWALL_STATE_FILE" 600 ||
        ! firewall_install_managed_file "$work_dir/firewall.nft" "$FIREWALL_CONFIG" 600 ||
        ! firewall_install_managed_file "$service_file" "$service_target" "$service_mode" ||
        ! firewall_enable_persistence ||
        ! firewall_runtime_enabled ||
        ! firewall_persistence_enabled ||
        ! firewall_service_active; then
        err "防火墙持久化验证失败，正在恢复应用前状态。"
        if ! firewall_restore_snapshot_now "$rollback_dir" 1; then
            err "原状态恢复失败，必须先处理保留的回滚快照。"
        fi
        rm -rf "$work_dir"
        return 1
    fi
    if ! firewall_finish_commit "$rollback_dir"; then
        err "防火墙提交状态写入失败，正在恢复应用前状态。"
        if ! firewall_restore_snapshot_now "$rollback_dir" 1; then
            err "原状态恢复失败，必须先处理保留的回滚快照。"
        fi
        rm -rf "$work_dir"
        return 1
    fi
    rm -rf "$work_dir"
    info "主机防火墙已启用并设置为开机自动加载。"
}

firewall_sync_active_config() {
    local temporary_tcp="${1:-}" temporary_udp="${2:-}" quiet="${3:-0}"
    local tmp backup

    firewall_recover_pending_rollbacks || return 1

    if [ ! -f "$FIREWALL_CONFIG" ]; then
        if firewall_runtime_enabled ||
            [ -e "$FIREWALL_SYSTEMD_UNIT" ] ||
            [ -e "$FIREWALL_OPENRC_SERVICE" ] ||
            firewall_persistence_enabled ||
            firewall_service_active; then
            err "主机防火墙运行状态不完整且配置文件缺失，请先在防火墙菜单关闭或修复。"
            return 1
        fi
        return 0
    fi
    [ -f "$FIREWALL_STATE_FILE" ] || {
        err "主机防火墙配置不完整，请先在防火墙菜单执行更新或关闭。"
        return 1
    }
    firewall_runtime_enabled || {
        err "主机防火墙配置存在但规则表未运行，无法同步端口。"
        return 1
    }
    firewall_load_state || return 1
    firewall_detect_allowed_ports || return 1
    FW_ALLOWED_TCP="$(merge_port_csv "$FW_ALLOWED_TCP" "$temporary_tcp")" || return 1
    FW_ALLOWED_UDP="$(merge_port_csv "$FW_ALLOWED_UDP" "$temporary_udp")" || return 1
    tmp="$(mktemp "$RUNTIME_DIR/firewall-refresh.XXXXXX")" || return 1
    backup="$(mktemp "$RUNTIME_DIR/firewall-config-backup.XXXXXX")" || { rm -f "$tmp"; return 1; }
    cp "$FIREWALL_CONFIG" "$backup" || { rm -f "$tmp" "$backup"; return 1; }
    if ! firewall_write_config "$tmp" ||
        ! nft -c -f "$tmp" ||
        ! firewall_install_managed_file "$tmp" "$FIREWALL_CONFIG" 600 ||
        ! nft -f "$FIREWALL_CONFIG"; then
        firewall_install_managed_file "$backup" "$FIREWALL_CONFIG" 600 || true
        rm -f "$tmp" "$backup"
        return 1
    fi
    rm -f "$tmp" "$backup"
    [ "$quiet" = "1" ] || info "主机防火墙已同步当前 SSH、节点、Docker 和公网监听端口。"
}

firewall_prepare_port_transition() {
    local tcp_ports="${1:-}" udp_ports="${2:-}" transition_dir
    local ssh_configured_ports ssh_listening_ports ssh_safe_ports

    if [ -n "${ACTIVE_FIREWALL_TRANSITION_DIR:-}" ]; then
        err "已有未完成的防火墙端口切换，已拒绝开始新的切换。"
        return 1
    fi
    if [ ! -f "$FIREWALL_CONFIG" ]; then
        firewall_sync_active_config "$tcp_ports" "$udp_ports" 1
        return $?
    fi

    prepare_runtime_dir
    transition_dir="$(mktemp -d "$RUNTIME_DIR/firewall-transition.XXXXXX")" || return 1
    ssh_configured_ports="$(ssh_effective_ports_csv 2>/dev/null)" || {
        rm -rf "$transition_dir"
        return 1
    }
    ssh_listening_ports="$(ssh_listening_ports_csv 2>/dev/null)" || {
        rm -rf "$transition_dir"
        return 1
    }
    ssh_safe_ports="$(merge_port_csv "$ssh_configured_ports" "$ssh_listening_ports")" || {
        rm -rf "$transition_dir"
        return 1
    }
    # 事务前文件可能落后于 sshd；快照只增补安全 SSH 端口，不提前收窄其他服务。
    if ! firewall_write_ssh_safe_snapshot \
        "$FIREWALL_CONFIG" "$transition_dir/firewall.nft" "$ssh_safe_ports"; then
        rm -rf "$transition_dir"
        return 1
    fi
    ACTIVE_FIREWALL_TRANSITION_DIR="$transition_dir"
    if ! firewall_sync_active_config "$tcp_ports" "$udp_ports" 1; then
        firewall_abort_port_transition || true
        return 1
    fi
}

firewall_abort_port_transition() {
    local transition_dir="${ACTIVE_FIREWALL_TRANSITION_DIR:-}"

    [ -n "$transition_dir" ] || return 0
    if [[ "$transition_dir" != "$RUNTIME_DIR"/firewall-transition.* ]] ||
        [ ! -d "$transition_dir" ] || [ -L "$transition_dir" ] ||
        [ ! -f "$transition_dir/firewall.nft" ]; then
        err "防火墙端口切换备份无效，已拒绝自动恢复：$transition_dir"
        return 1
    fi
    if ! firewall_install_managed_file "$transition_dir/firewall.nft" "$FIREWALL_CONFIG" 600 ||
        ! firewall_apply_config_file "$FIREWALL_CONFIG"; then
        err "防火墙端口切换恢复失败，备份已保留：$transition_dir"
        return 1
    fi
    ACTIVE_FIREWALL_TRANSITION_DIR=""
    rm -rf "$transition_dir"
}

firewall_discard_port_transition() {
    local transition_dir="${ACTIVE_FIREWALL_TRANSITION_DIR:-}"

    [ -n "$transition_dir" ] || return 0
    if [[ "$transition_dir" != "$RUNTIME_DIR"/firewall-transition.* ]] ||
        [ ! -d "$transition_dir" ] || [ -L "$transition_dir" ]; then
        err "防火墙端口切换目录无效，已拒绝清理：$transition_dir"
        return 1
    fi
    ACTIVE_FIREWALL_TRANSITION_DIR=""
    rm -rf "$transition_dir"
}

firewall_complete_port_transition() {
    local transition_dir="${ACTIVE_FIREWALL_TRANSITION_DIR:-}"

    firewall_sync_active_config "" "" 0 || return 1
    [ -n "$transition_dir" ] || return 0
    if [[ "$transition_dir" != "$RUNTIME_DIR"/firewall-transition.* ]] ||
        [ ! -d "$transition_dir" ] || [ -L "$transition_dir" ]; then
        err "防火墙端口切换目录无效，无法完成清理：$transition_dir"
        return 1
    fi
    firewall_discard_port_transition
}

firewall_refresh_if_enabled() {
    firewall_sync_active_config "" "" 0
}

firewall_ports_from_nft_chain() {
    local protocol="$1"

    awk -v protocol="$protocol" '
        {
            line=$0
            if (index(line, protocol " sport ") > 0) next
            marker=protocol " dport "
            start=index(line, marker)
            if (start == 0) next
            tail=substr(line, start + length(marker))
            stop=index(tail, " accept")
            if (stop == 0) next
            values=substr(tail, 1, stop - 1)
            gsub(/[{},]/, " ", values)
            count=split(values, parts, /[[:space:]]+/)
            for (i=1; i<=count; i++) {
                if (parts[i] ~ /^[0-9]+$/) print parts[i]
            }
        }
    ' | sort -n -u | paste -sd, -
}

firewall_live_port_set_matches() {
    local set_name="$1" expected="$2" set_rules live_body live_set

    if [ -n "$expected" ]; then
        expected="$(normalize_port_csv "$expected")" || return 1
        set_rules="$(nft -nn list set inet vpsbox "$set_name" 2>/dev/null)" || return 1
        live_body="$(printf '%s\n' "$set_rules" | firewall_set_body_lines "$set_name")" || return 1
        live_set="$(printf '%s\n' "$live_body" | firewall_discrete_port_set_values)" || return 1
        [ "$live_set" = "$expected" ]
    else
        ! nft list set inet vpsbox "$set_name" >/dev/null 2>&1
    fi
}

firewall_live_interface_set_matches() {
    local set_name="$1" expected="$2" set_rules live_body live_set

    if [ -n "$expected" ]; then
        expected="$(normalize_interface_csv "$expected")" || return 1
        set_rules="$(nft -nn list set inet vpsbox "$set_name" 2>/dev/null)" || return 1
        live_body="$(printf '%s\n' "$set_rules" | firewall_set_body_lines "$set_name")" || return 1
        live_set="$(printf '%s\n' "$live_body" | firewall_discrete_interface_set_values)" || return 1
        [ "$live_set" = "$expected" ]
    else
        ! nft list set inet vpsbox "$set_name" >/dev/null 2>&1
    fi
}

firewall_set_body_lines() {
    local set_name="$1"

    awk -v target="$set_name" '
        $1 == "set" && $2 == target && $3 == "{" { inside=1; next }
        inside && /^[[:space:]]*}[[:space:]]*$/ { exit }
        inside {
            line=$0
            sub(/^[[:space:]]*/, "", line)
            sub(/[[:space:]]*;?[[:space:]]*$/, "", line)
            gsub(/[[:space:]]+/, " ", line)
            if (line != "") print line
        }
    '
}

firewall_discrete_port_set_values() {
    awk '
        NR == 1 { if ($0 != "type inet_service") exit 1; next }
        { text = text (text == "" ? "" : " ") $0 }
        END {
            gsub(/[[:space:]]+/, " ", text)
            if (text !~ /^elements = \{ [0-9]+(, [0-9]+)* \}$/) exit 1
            sub(/^elements = \{ /, "", text)
            sub(/ \}$/, "", text)
            count=split(text, values, /, /)
            for (i=1; i<=count; i++) print values[i]
        }
    ' | sort -n -u | paste -sd, -
}

firewall_discrete_interface_set_values() {
    awk '
        NR == 1 { if ($0 != "type ifname") exit 1; next }
        { text = text (text == "" ? "" : " ") $0 }
        END {
            gsub(/[[:space:]]+/, " ", text)
            if (text !~ /^elements = \{ "[A-Za-z0-9_.:-]+"(, "[A-Za-z0-9_.:-]+")* \}$/) exit 1
            sub(/^elements = \{ /, "", text)
            sub(/ \}$/, "", text)
            count=split(text, values, /, /)
            for (i=1; i<=count; i++) {
                sub(/^"/, "", values[i])
                sub(/"$/, "", values[i])
                print values[i]
            }
        }
    ' | sort -u | paste -sd, -
}

firewall_nft_port_expression() {
    local csv

    csv="$(normalize_port_csv "${1:-}")" || return 1
    [ -n "$csv" ] || return 1
    if [[ "$csv" == *,* ]]; then
        printf '{ %s }\n' "$(printf '%s' "$csv" | sed 's/,/, /g')"
    else
        printf '%s\n' "$csv"
    fi
}

firewall_chain_rule_lines() {
    local chain="$1"

    awk -v target="$chain" '
        $1 == "chain" && $2 == target && $3 == "{" { inside=1; next }
        inside && /^[[:space:]]*}[[:space:]]*$/ { exit }
        inside {
            line=$0
            sub(/^[[:space:]]*/, "", line)
            sub(/[[:space:]]*$/, "", line)
            gsub(/[[:space:]]+/, " ", line)
            if (line == "" || line ~ /^type filter hook /) next
            print line
        }
    '
}

firewall_expected_input_rule_lines() {
    local expression

    printf '%s\n' \
        'ct state 0x1 drop' \
        'ct state 0x2,0x4 accept' \
        'iifname "lo" accept' \
        'ip protocol 1 accept' \
        'meta l4proto 58 accept' \
        'meta nfproto 2 udp sport 67 udp dport 68 accept' \
        'meta nfproto 10 udp sport 547 udp dport 546 accept'
    if [ -n "$FW_ALLOWED_TCP" ]; then
        expression="$(firewall_nft_port_expression "$FW_ALLOWED_TCP")" || return 1
        printf 'tcp dport %s accept\n' "$expression"
    fi
    if [ -n "$FW_ALLOWED_UDP" ]; then
        expression="$(firewall_nft_port_expression "$FW_ALLOWED_UDP")" || return 1
        printf 'udp dport %s accept\n' "$expression"
    fi
    if [ -n "$FW_DOCKER_PROXY4_TCP" ]; then
        expression="$(firewall_nft_port_expression "$FW_DOCKER_PROXY4_TCP")" || return 1
        printf 'meta nfproto 2 tcp dport %s accept\n' "$expression"
    fi
    if [ -n "$FW_DOCKER_PROXY4_UDP" ]; then
        expression="$(firewall_nft_port_expression "$FW_DOCKER_PROXY4_UDP")" || return 1
        printf 'meta nfproto 2 udp dport %s accept\n' "$expression"
    fi
    if [ -n "$FW_DOCKER_PROXY6_TCP" ]; then
        expression="$(firewall_nft_port_expression "$FW_DOCKER_PROXY6_TCP")" || return 1
        printf 'meta nfproto 10 tcp dport %s accept\n' "$expression"
    fi
    if [ -n "$FW_DOCKER_PROXY6_UDP" ]; then
        expression="$(firewall_nft_port_expression "$FW_DOCKER_PROXY6_UDP")" || return 1
        printf 'meta nfproto 10 udp dport %s accept\n' "$expression"
    fi
}

firewall_expected_guard_rule_lines() {
    [ -z "$FW_EXTRA_TCP" ] || printf '%s\n' \
        'meta l4proto 6 ct original proto-dst @extra_tcp_dnat_ports accept'
    [ -z "$FW_DOCKER_PUBLIC4_TCP" ] || printf '%s\n' \
        'meta nfproto 2 meta l4proto 6 oifname @docker_bridge_ifaces ct original proto-dst @docker4_tcp_ports accept'
    [ -z "$FW_DOCKER_PUBLIC6_TCP" ] || printf '%s\n' \
        'meta nfproto 10 meta l4proto 6 oifname @docker_bridge_ifaces ct original proto-dst @docker6_tcp_ports accept'
    printf '%s\n' 'meta l4proto 6 drop'
    [ -z "$FW_EXTRA_UDP" ] || printf '%s\n' \
        'meta l4proto 17 ct original proto-dst @extra_udp_dnat_ports accept'
    [ -z "$FW_DOCKER_PUBLIC4_UDP" ] || printf '%s\n' \
        'meta nfproto 2 meta l4proto 17 oifname @docker_bridge_ifaces ct original proto-dst @docker4_udp_ports accept'
    [ -z "$FW_DOCKER_PUBLIC6_UDP" ] || printf '%s\n' \
        'meta nfproto 10 meta l4proto 17 oifname @docker_bridge_ifaces ct original proto-dst @docker6_udp_ports accept'
    printf '%s\n' 'meta l4proto 17 drop' 'drop'
}

firewall_expected_forward_rule_lines() {
    printf '%s\n' 'ct state 0x2,0x4 accept'
    [ -z "$FW_DOCKER_BRIDGES" ] || printf '%s\n' 'iifname @docker_bridge_ifaces accept'
    printf '%s\n' 'ct direction 0 ct status 0x20 jump docker_port_guard'
    [ -z "$FW_DOCKER_BRIDGES" ] || printf '%s\n' 'oifname @docker_bridge_ifaces drop'
}

firewall_expected_set_names() {
    [ -z "$FW_DOCKER_BRIDGES" ] || printf '%s\n' docker_bridge_ifaces
    [ -z "$FW_DOCKER_PUBLIC4_TCP" ] || printf '%s\n' docker4_tcp_ports
    [ -z "$FW_DOCKER_PUBLIC4_UDP" ] || printf '%s\n' docker4_udp_ports
    [ -z "$FW_DOCKER_PUBLIC6_TCP" ] || printf '%s\n' docker6_tcp_ports
    [ -z "$FW_DOCKER_PUBLIC6_UDP" ] || printf '%s\n' docker6_udp_ports
    [ -z "$FW_EXTRA_TCP" ] || printf '%s\n' extra_tcp_dnat_ports
    [ -z "$FW_EXTRA_UDP" ] || printf '%s\n' extra_udp_dnat_ports
}

firewall_table_object_names() {
    local object_type="$1"

    awk -v object_type="$object_type" '
        $1 == object_type && $3 == "{" { print $2 }
    ' | sort -u | paste -sd, -
}

firewall_live_config_matches_expected() {
    local table_rules input_rules live_tcp live_udp guard_rules forward_rules
    local live_rule_lines expected_rule_lines
    local live_chain_names live_set_names expected_set_names
    local expected_input_tcp expected_input_udp
    local expected_docker4_tcp expected_docker4_udp expected_docker6_tcp expected_docker6_udp
    local expected_docker_bridges

    firewall_runtime_enabled || return 1
    table_rules="$(nft -nn list table inet vpsbox 2>/dev/null)" || return 1
    live_chain_names="$(printf '%s\n' "$table_rules" | firewall_table_object_names chain)" || return 1
    [ "$live_chain_names" = "docker_forward,docker_port_guard,input" ] || return 1
    live_set_names="$(printf '%s\n' "$table_rules" | firewall_table_object_names set)" || return 1
    expected_set_names="$(firewall_expected_set_names | sort -u | paste -sd, -)" || return 1
    [ "$live_set_names" = "$expected_set_names" ] || return 1
    if printf '%s\n' "$table_rules" |
        grep -Eq '^[[:space:]]*(map|flowtable|counter|quota|limit|synproxy)[[:space:]]+[^[:space:]]+[[:space:]]*\{'; then
        return 1
    fi
    input_rules="$(nft -nn list chain inet vpsbox input 2>/dev/null)" || return 1
    printf '%s\n' "$input_rules" |
        grep -Eq 'hook input priority (filter|0); policy drop;' || return 1
    live_rule_lines="$(printf '%s\n' "$input_rules" | firewall_chain_rule_lines input)" || return 1
    expected_rule_lines="$(firewall_expected_input_rule_lines)" || return 1
    [ "$live_rule_lines" = "$expected_rule_lines" ] || return 1
    live_tcp="$(printf '%s\n' "$input_rules" | firewall_ports_from_nft_chain tcp)" || return 1
    live_udp="$(printf '%s\n' "$input_rules" | firewall_ports_from_nft_chain udp)" || return 1
    expected_input_tcp="$(merge_port_csv "$FW_ALLOWED_TCP" "$FW_DOCKER_PROXY4_TCP" "$FW_DOCKER_PROXY6_TCP")" || return 1
    expected_input_udp="$(merge_port_csv "$FW_ALLOWED_UDP" "$FW_DOCKER_PROXY4_UDP" "$FW_DOCKER_PROXY6_UDP")" || return 1
    [ "$live_tcp" = "$expected_input_tcp" ] || return 1
    [ "$live_udp" = "$expected_input_udp" ] || return 1
    guard_rules="$(nft -nn list chain inet vpsbox docker_port_guard 2>/dev/null)" || return 1
    forward_rules="$(nft -nn list chain inet vpsbox docker_forward 2>/dev/null)" || return 1
    live_rule_lines="$(printf '%s\n' "$guard_rules" | firewall_chain_rule_lines docker_port_guard)" || return 1
    expected_rule_lines="$(firewall_expected_guard_rule_lines)" || return 1
    [ "$live_rule_lines" = "$expected_rule_lines" ] || return 1
    live_rule_lines="$(printf '%s\n' "$forward_rules" | firewall_chain_rule_lines docker_forward)" || return 1
    expected_rule_lines="$(firewall_expected_forward_rule_lines)" || return 1
    [ "$live_rule_lines" = "$expected_rule_lines" ] || return 1
    printf '%s\n' "$forward_rules" |
        grep -Eq 'hook forward priority (-1|filter[[:space:]]*-[[:space:]]*1); policy accept;' || return 1
    if nft list chain inet vpsbox output >/dev/null 2>&1; then return 1; fi

    expected_docker4_tcp="$(normalize_port_csv "$FW_DOCKER_PUBLIC4_TCP")" || return 1
    expected_docker4_udp="$(normalize_port_csv "$FW_DOCKER_PUBLIC4_UDP")" || return 1
    expected_docker6_tcp="$(normalize_port_csv "$FW_DOCKER_PUBLIC6_TCP")" || return 1
    expected_docker6_udp="$(normalize_port_csv "$FW_DOCKER_PUBLIC6_UDP")" || return 1
    expected_docker_bridges="$(normalize_interface_csv "$FW_DOCKER_BRIDGES")" || return 1
    if [ -n "$expected_docker4_tcp$expected_docker4_udp$expected_docker6_tcp$expected_docker6_udp" ] &&
        [ -z "$expected_docker_bridges" ]; then return 1; fi
    firewall_live_port_set_matches docker4_tcp_ports "$expected_docker4_tcp" || return 1
    firewall_live_port_set_matches docker4_udp_ports "$expected_docker4_udp" || return 1
    firewall_live_port_set_matches docker6_tcp_ports "$expected_docker6_tcp" || return 1
    firewall_live_port_set_matches docker6_udp_ports "$expected_docker6_udp" || return 1
    firewall_live_port_set_matches extra_tcp_dnat_ports "$FW_EXTRA_TCP" || return 1
    firewall_live_port_set_matches extra_udp_dnat_ports "$FW_EXTRA_UDP" || return 1
    firewall_live_interface_set_matches docker_bridge_ifaces "$expected_docker_bridges" || return 1
    ! nft list set inet vpsbox docker_tcp_ports >/dev/null 2>&1 || return 1
    ! nft list set inet vpsbox docker_udp_ports >/dev/null 2>&1 || return 1
}

firewall_config_direct_ports() {
    local source="$1" protocol="$2"

    [ -f "$source" ] && [ ! -L "$source" ] || return 1
    case "$protocol" in tcp|udp) ;; *) return 2 ;; esac
    awk '
        /^[[:space:]]*chain[[:space:]]+input[[:space:]]*\{/ { in_input=1; next }
        in_input && /^[[:space:]]*\}/ { exit }
        in_input && $0 !~ /meta nfproto/ { print }
    ' "$source" | firewall_ports_from_nft_chain "$protocol"
}

firewall_config_port_set_matches() {
    local source="$1" set_name="$2" expected="$3" body actual count

    count="$(grep -Ec "^[[:space:]]*set[[:space:]]+${set_name}[[:space:]]*\\{" "$source" || true)"
    if [ -z "$expected" ]; then
        [ "$count" -eq 0 ]
        return
    fi
    [ "$count" -eq 1 ] || return 1
    expected="$(normalize_port_csv "$expected")" || return 1
    body="$(firewall_set_body_lines "$set_name" < "$source")" || return 1
    actual="$(printf '%s\n' "$body" | firewall_discrete_port_set_values)" || return 1
    [ "$actual" = "$expected" ]
}

firewall_config_additive_shape_valid() {
    local source="$1" old_tcp="$2" old_udp="$3"
    local direct_tcp direct_udp count expected_rule

    [ -f "$source" ] && [ ! -L "$source" ] || return 1
    grep -Fqx '# Managed by vpsbox. Replace only the dedicated table; never flush the global ruleset.' "$source" || return 1
    [ "$(grep -Ec '^[[:space:]]*table[[:space:]]+inet[[:space:]]+vpsbox[[:space:]]*\{' "$source" || true)" -eq 1 ] || return 1
    for count in input docker_port_guard docker_forward; do
        [ "$(grep -Ec "^[[:space:]]*chain[[:space:]]+${count}[[:space:]]*\\{" "$source" || true)" -eq 1 ] || return 1
    done
    ! grep -Eq '^[[:space:]]*chain[[:space:]]+output[[:space:]]*\{' "$source" || return 1
    [ "$(grep -Ec '^[[:space:]]*tcp[[:space:]]+dport[[:space:]]+\{[^}]+\}[[:space:]]+accept[[:space:]]*$' "$source" || true)" -eq 1 ] || return 1
    [ "$(grep -Ec '^[[:space:]]*udp[[:space:]]+dport[[:space:]]+\{[^}]+\}[[:space:]]+accept[[:space:]]*$' "$source" || true)" -le 1 ] || return 1

    direct_tcp="$(firewall_config_direct_ports "$source" tcp)" || return 1
    direct_udp="$(firewall_config_direct_ports "$source" udp)" || return 1
    [ -n "$direct_tcp" ] || return 1
    port_csv_is_subset "$old_tcp" "$direct_tcp" || return 1
    port_csv_is_subset "$old_udp" "$direct_udp" || return 1
    firewall_config_port_set_matches "$source" extra_tcp_dnat_ports "$old_tcp" || return 1
    firewall_config_port_set_matches "$source" extra_udp_dnat_ports "$old_udp" || return 1

    expected_rule='        meta l4proto tcp ct original proto-dst @extra_tcp_dnat_ports accept'
    count="$(grep -Fxc "$expected_rule" "$source" || true)"
    if [ -n "$old_tcp" ]; then [ "$count" -eq 1 ] || return 1; else [ "$count" -eq 0 ] || return 1; fi
    expected_rule='        meta l4proto udp ct original proto-dst @extra_udp_dnat_ports accept'
    count="$(grep -Fxc "$expected_rule" "$source" || true)"
    if [ -n "$old_udp" ]; then [ "$count" -eq 1 ] || return 1; else [ "$count" -eq 0 ] || return 1; fi
}

firewall_replace_input_direct_ports() {
    local source="$1" dest="$2" protocol="$3" ports="$4" formatted

    ports="$(normalize_port_csv "$ports")" || return 1
    [ -n "$ports" ] || return 1
    formatted="$(printf '%s' "$ports" | sed 's/,/, /g')"
    awk -v protocol="$protocol" -v formatted="$formatted" '
        function emit_rule() {
            print "        " protocol " dport { " formatted " } accept"
            inserted=1
        }
        /^[[:space:]]*chain[[:space:]]+input[[:space:]]*\{/ {
            in_input=1
            print
            next
        }
        in_input {
            target="^[[:space:]]*" protocol "[[:space:]]+dport[[:space:]]+\\{[^}]+\\}[[:space:]]+accept[[:space:]]*$"
            if ($0 ~ target) {
                seen++
                if (!inserted) emit_rule()
                next
            }
            if (!inserted && protocol == "tcp" && $0 ~ /^[[:space:]]*udp[[:space:]]+dport[[:space:]]+/) emit_rule()
            if (!inserted && $0 ~ /^[[:space:]]*meta[[:space:]]+nfproto.*(tcp|udp)[[:space:]]+dport[[:space:]]+/) emit_rule()
            if (!inserted && $0 ~ /^[[:space:]]*}[[:space:]]*$/) emit_rule()
            if ($0 ~ /^[[:space:]]*}[[:space:]]*$/) in_input=0
        }
        { print }
        END { if (!inserted || seen > 1) exit 1 }
    ' "$source" > "$dest"
}

firewall_replace_extra_port_set() {
    local source="$1" dest="$2" set_name="$3" ports="$4" anchor="$5" formatted

    ports="$(normalize_port_csv "$ports")" || return 1
    [ -n "$ports" ] || return 1
    formatted="$(printf '%s' "$ports" | sed 's/,/, /g')"
    awk -v target="$set_name" -v formatted="$formatted" -v anchor="$anchor" '
        function emit_set() {
            print "    set " target " {"
            print "        type inet_service"
            print "        elements = { " formatted " }"
            print "    }"
            print ""
            inserted=1
        }
        skipping {
            if ($0 ~ /^[[:space:]]*}[[:space:]]*$/) skipping=0
            next
        }
        $1 == "set" && $2 == target && $3 == "{" {
            seen++
            if (!inserted) emit_set()
            skipping=1
            next
        }
        !inserted && anchor != "" && $1 == "set" && $2 == anchor && $3 == "{" { emit_set() }
        !inserted && $1 == "chain" && $2 == "input" && $3 == "{" { emit_set() }
        { print }
        END { if (!inserted || skipping || seen > 1) exit 1 }
    ' "$source" > "$dest"
}

firewall_ensure_extra_guard_rule() {
    local source="$1" dest="$2" protocol="$3" rule count

    rule="        meta l4proto $protocol ct original proto-dst @extra_${protocol}_dnat_ports accept"
    count="$(grep -Fxc "$rule" "$source" || true)"
    if [ "$count" -eq 1 ]; then
        cp "$source" "$dest"
        return
    fi
    [ "$count" -eq 0 ] || return 1
    awk -v protocol="$protocol" -v rule="$rule" '
        /^[[:space:]]*chain[[:space:]]+docker_port_guard[[:space:]]*\{/ {
            in_guard=1
            print
            if (protocol == "tcp") { print rule; inserted=1 }
            next
        }
        in_guard && protocol == "udp" && $0 ~ /^[[:space:]]*meta[[:space:]]+l4proto[[:space:]]+tcp[[:space:]]+drop[[:space:]]*$/ {
            print
            print rule
            inserted=1
            next
        }
        in_guard && $0 ~ /^[[:space:]]*}[[:space:]]*$/ { in_guard=0 }
        { print }
        END { if (!inserted) exit 1 }
    ' "$source" > "$dest"
}

firewall_build_config_with_added_ports() {
    local source="$1" dest="$2" protocols="$3"
    local work_dir current next protocol direct desired set_name anchor

    case "$protocols" in tcp|udp|both) ;; *) return 2 ;; esac
    work_dir="$(mktemp -d "$(dirname "$dest")/.firewall-add-build.XXXXXX")" || return 1
    current="$work_dir/current.nft"
    cp "$source" "$current" || { rm -rf "$work_dir"; return 1; }
    for protocol in tcp udp; do
        [ "$protocols" = "both" ] || [ "$protocols" = "$protocol" ] || continue
        if [ "$protocol" = "tcp" ]; then
            desired="$FW_EXTRA_TCP"
            set_name=extra_tcp_dnat_ports
            anchor=extra_udp_dnat_ports
        else
            desired="$FW_EXTRA_UDP"
            set_name=extra_udp_dnat_ports
            anchor=""
        fi
        direct="$(firewall_config_direct_ports "$current" "$protocol")" || { rm -rf "$work_dir"; return 1; }
        direct="$(merge_port_csv "$direct" "$desired")" || { rm -rf "$work_dir"; return 1; }
        next="$work_dir/input-$protocol.nft"
        firewall_replace_input_direct_ports "$current" "$next" "$protocol" "$direct" || { rm -rf "$work_dir"; return 1; }
        current="$next"
        next="$work_dir/set-$protocol.nft"
        firewall_replace_extra_port_set "$current" "$next" "$set_name" "$desired" "$anchor" || { rm -rf "$work_dir"; return 1; }
        current="$next"
        next="$work_dir/guard-$protocol.nft"
        firewall_ensure_extra_guard_rule "$current" "$next" "$protocol" || { rm -rf "$work_dir"; return 1; }
        current="$next"
    done
    cp "$current" "$dest" || { rm -rf "$work_dir"; return 1; }
    rm -rf "$work_dir"
}

firewall_check_config_file() {
    local config="$1" table_existed=0 status=0

    command -v nft >/dev/null 2>&1 || return 1
    nft list table inet vpsbox >/dev/null 2>&1 && table_existed=1
    if [ "$table_existed" -eq 0 ] && ! nft add table inet vpsbox; then
        return 1
    fi
    nft -c -f "$config" >/dev/null 2>&1 || status=1
    [ "$table_existed" -eq 1 ] || nft delete table inet vpsbox >/dev/null 2>&1 || true
    return "$status"
}

firewall_live_added_ports_match() {
    local protocols="$1" port="$2" input_ports

    case "$protocols" in tcp|udp|both) ;; *) return 2 ;; esac
    if [ "$protocols" = "tcp" ] || [ "$protocols" = "both" ]; then
        input_ports="$(nft -nn list chain inet vpsbox input 2>/dev/null | firewall_ports_from_nft_chain tcp)" || return 1
        csv_contains_port "$input_ports" "$port" || return 1
        firewall_live_port_set_matches extra_tcp_dnat_ports "$FW_EXTRA_TCP" || return 1
    fi
    if [ "$protocols" = "udp" ] || [ "$protocols" = "both" ]; then
        input_ports="$(nft -nn list chain inet vpsbox input 2>/dev/null | firewall_ports_from_nft_chain udp)" || return 1
        csv_contains_port "$input_ports" "$port" || return 1
        firewall_live_port_set_matches extra_udp_dnat_ports "$FW_EXTRA_UDP" || return 1
    fi
}

firewall_restore_additive_snapshot() {
    local rollback_dir="$1" commit_owner="${2:-0}"

    if ! firewall_restore_snapshot_now "$rollback_dir" "$commit_owner"; then
        err "新增端口失败且旧防火墙状态未能自动恢复，快照保留在：$rollback_dir"
        return 1
    fi
}

firewall_apply_added_ports() {
    local protocols="$1" port="$2" old_tcp="$3" old_udp="$4"
    local work_dir rollback_dir old_direct_tcp was_runtime=0 committed=0 persist_failed=0
    local new_config new_state

    case "$protocols" in tcp|udp|both) ;; *) return 2 ;; esac
    firewall_recover_pending_rollbacks || return 1
    firewall_runtime_enabled && was_runtime=1
    firewall_managed_file_is_secure "$FIREWALL_CONFIG" || {
        err "当前防火墙配置不是安全的 vpsbox 受管文件；请使用 [1] 一键开启/更新防火墙。"
        return 1
    }
    firewall_state_file_is_secure || {
        err "当前防火墙状态文件不可用；请使用 [1] 一键开启/更新防火墙。"
        return 1
    }
    if ! firewall_config_additive_shape_valid "$FIREWALL_CONFIG" "$old_tcp" "$old_udp"; then
        err "当前防火墙规则结构无法安全执行增量更新；请使用 [1] 一键开启/更新防火墙。"
        return 1
    fi

    prepare_runtime_dir || return 1
    work_dir="$(mktemp -d "$RUNTIME_DIR/firewall-add.XXXXXX")" || return 1
    new_config="$work_dir/firewall.nft"
    new_state="$work_dir/firewall.env"
    if ! firewall_build_config_with_added_ports "$FIREWALL_CONFIG" "$new_config" "$protocols" ||
        ! firewall_write_state_file "$new_state" ||
        ! firewall_check_config_file "$new_config"; then
        rm -rf "$work_dir"
        err "无法生成或校验新增端口后的防火墙配置。"
        return 1
    fi
    old_direct_tcp="$(firewall_config_direct_ports "$FIREWALL_CONFIG" tcp)" || {
        rm -rf "$work_dir"
        return 1
    }
    if ! firewall_create_rollback_snapshot rollback_dir "$old_direct_tcp"; then
        rm -rf "$work_dir"
        err "无法创建新增端口的防火墙回滚快照。"
        return 1
    fi

    if [ "$was_runtime" -eq 1 ]; then
        if ! firewall_apply_config_file "$new_config" ||
            ! firewall_live_added_ports_match "$protocols" "$port"; then
            err "新增端口的运行规则验证失败，正在恢复旧状态。"
            firewall_restore_additive_snapshot "$rollback_dir" || true
            rm -rf "$work_dir"
            return 1
        fi
    fi
    if ! firewall_begin_commit "$rollback_dir"; then
        err "新增端口提交前回滚快照状态异常，正在恢复旧状态。"
        firewall_restore_additive_snapshot "$rollback_dir" || true
        rm -rf "$work_dir"
        return 1
    fi
    committed=1
    if ! firewall_install_managed_file "$new_config" "$FIREWALL_CONFIG" 600; then
        persist_failed=1
    elif ! firewall_install_managed_file "$new_state" "$FIREWALL_STATE_FILE" 600; then
        persist_failed=1
    elif [ "$was_runtime" -eq 1 ] && ! firewall_live_added_ports_match "$protocols" "$port"; then
        persist_failed=1
    fi
    if [ "$persist_failed" -ne 0 ]; then
        err "新增端口的持久化验证失败，正在恢复旧状态。"
        firewall_restore_additive_snapshot "$rollback_dir" "$committed" || true
        rm -rf "$work_dir"
        return 1
    fi
    if ! firewall_finish_commit "$rollback_dir"; then
        err "新增端口提交收尾失败，正在恢复旧状态。"
        firewall_restore_additive_snapshot "$rollback_dir" "$committed" || true
        rm -rf "$work_dir"
        return 1
    fi
    rm -rf "$work_dir"
    if [ "$was_runtime" -eq 1 ]; then
        info "已轻量放行 $protocols 端口：$port"
    else
        info "额外端口已保存；防火墙下次启动时会自动放行：$port"
    fi
}

firewall_config_matches_expected() {
    local tmp status=0
    [ -f "$FIREWALL_CONFIG" ] && [ -f "$FIREWALL_STATE_FILE" ] || return 1
    firewall_load_state || return 1
    firewall_detect_allowed_ports || return 1
    tmp="$(mktemp "$RUNTIME_DIR/firewall-check.XXXXXX")" || return 1
    firewall_write_config "$tmp" || status=1
    if [ "$status" -eq 0 ] && ! cmp -s "$tmp" "$FIREWALL_CONFIG"; then status=1; fi
    if [ "$status" -eq 0 ] && ! nft -c -f "$FIREWALL_CONFIG" >/dev/null 2>&1; then status=1; fi
    if [ "$status" -eq 0 ] && ! firewall_live_config_matches_expected; then status=1; fi
    rm -f "$tmp"
    [ "$status" -eq 0 ]
}

firewall_view_rules() {
    firewall_load_state || return 1
    firewall_detect_allowed_ports || return 1
    cat <<EOF
========================================
 当前放行端口
========================================
 来源       协议       端口
----------------------------------------
 SSH        TCP        ${FW_SSH_PORTS:--}
 节点       TCP        ${FW_NODE_TCP:--}
 节点       UDP        ${FW_NODE_UDP:--}
 Docker     TCP        ${FW_DOCKER_PUBLIC_TCP:--}
 Docker     UDP        ${FW_DOCKER_PUBLIC_UDP:--}
 其他公网   TCP        ${FW_OTHER_PUBLIC_TCP:--}
 其他公网   UDP        ${FW_OTHER_PUBLIC_UDP:--}
 额外端口   TCP        ${FW_EXTRA_TCP:--}
 额外端口   UDP        ${FW_EXTRA_UDP:--}
----------------------------------------
 防火墙：$(firewall_runtime_state)
 开机加载：$(firewall_persistence_state)
 出站规则：不创建
========================================
EOF
    echo "说明：这里只显示 VPS 内部规则；NAT 端口映射和商家安全组需单独设置。"
}

firewall_save_inactive_state() {
    local tmp
    ensure_change_store || return 1
    tmp="$(mktemp "$RUNTIME_DIR/firewall-state.XXXXXX")" || return 1
    firewall_write_state_file "$tmp" &&
        firewall_install_managed_file "$tmp" "$FIREWALL_STATE_FILE" 600 || {
            rm -f "$tmp"
            return 1
        }
    rm -f "$tmp"
}

firewall_commit_port_state() {
    if firewall_control_plane_present; then
        firewall_apply_desired_state
    else
        firewall_save_inactive_state
        info "额外端口已保存；启用主机防火墙时会自动使用。"
    fi
}

firewall_prompt_port() {
    local port
    read -r -p "请输入端口（1-65535）：" port || return 1
    is_valid_port "$port" || {
        err "端口必须是 1-65535 的整数。"
        return 1
    }
    printf '%s\n' "$port"
}

firewall_add_extra_port() {
    local protocol="$1" port old_tcp old_udp
    firewall_settle_pending_port_transition || return 1
    firewall_load_state || return 1
    port="$(firewall_prompt_port)" || return 1
    old_tcp="$FW_EXTRA_TCP"
    old_udp="$FW_EXTRA_UDP"
    case "$protocol" in
        tcp)
            csv_contains_port "$FW_EXTRA_TCP" "$port" && { info "额外 TCP 已放行端口：$port"; return 0; }
            FW_EXTRA_TCP="$(csv_add_port "$FW_EXTRA_TCP" "$port")"
            ;;
        udp)
            csv_contains_port "$FW_EXTRA_UDP" "$port" && { info "额外 UDP 已放行端口：$port"; return 0; }
            FW_EXTRA_UDP="$(csv_add_port "$FW_EXTRA_UDP" "$port")"
            ;;
        both)
            if csv_contains_port "$FW_EXTRA_TCP" "$port" && csv_contains_port "$FW_EXTRA_UDP" "$port"; then
                info "额外 TCP/UDP 已放行端口：$port"
                return 0
            fi
            FW_EXTRA_TCP="$(csv_add_port "$FW_EXTRA_TCP" "$port")"
            FW_EXTRA_UDP="$(csv_add_port "$FW_EXTRA_UDP" "$port")"
            ;;
        *) return 1 ;;
    esac
    if firewall_control_plane_present; then
        firewall_apply_added_ports "$protocol" "$port" "$old_tcp" "$old_udp"
    else
        firewall_save_inactive_state || return 1
        info "额外端口已保存；启用主机防火墙时会自动使用。"
    fi
}

firewall_remove_extra_port() {
    local protocol="$1" port
    firewall_settle_pending_port_transition || return 1
    firewall_load_state || return 1
    port="$(firewall_prompt_port)" || return 1
    case "$protocol" in
        tcp)
            csv_contains_port "$FW_EXTRA_TCP" "$port" || { warn "额外 TCP 列表中没有端口 $port。"; return 0; }
            FW_EXTRA_TCP="$(csv_remove_port "$FW_EXTRA_TCP" "$port")"
            ;;
        udp)
            csv_contains_port "$FW_EXTRA_UDP" "$port" || { warn "额外 UDP 列表中没有端口 $port。"; return 0; }
            FW_EXTRA_UDP="$(csv_remove_port "$FW_EXTRA_UDP" "$port")"
            ;;
        *) return 1 ;;
    esac
    firewall_commit_port_state
}

firewall_clear_extra_ports() {
    local answer
    firewall_settle_pending_port_transition || return 1
    firewall_load_state || return 1
    read -r -p "清空所有额外 TCP/UDP 放行端口？请输入 YES：" answer || return 1
    [ "$answer" = "YES" ] || { info "已取消。"; return 0; }
    FW_EXTRA_TCP=""
    FW_EXTRA_UDP=""
    firewall_commit_port_state
}

firewall_extra_ports_menu() {
    local opt
    while true; do
        firewall_load_state || return 1
        clear 2>/dev/null || true
        cat <<EOF
========================================
 额外放行端口
========================================
 TCP：${FW_EXTRA_TCP:--}
 UDP：${FW_EXTRA_UDP:--}
----------------------------------------
 [1] 添加 TCP 端口
 [2] 添加 UDP 端口
 [3] 同时添加 TCP/UDP 端口
 [4] 删除 TCP 端口
 [5] 删除 UDP 端口
 [6] 清空额外端口
----------------------------------------
 [0] 返回主机防火墙
========================================
EOF
        read -r -p "请输入选项: " opt || return 0
        echo ""
        case "$opt" in
            1) run_menu_action firewall_add_extra_port tcp; pause ;;
            2) run_menu_action firewall_add_extra_port udp; pause ;;
            3) run_menu_action firewall_add_extra_port both; pause ;;
            4) run_menu_action firewall_remove_extra_port tcp; pause ;;
            5) run_menu_action firewall_remove_extra_port udp; pause ;;
            6) run_menu_action firewall_clear_extra_ports; pause ;;
            0) return 0 ;;
            *) warn "无效选项：$opt"; pause ;;
        esac
    done
}

firewall_disable_internal() {
    local failed=0

    firewall_settle_pending_port_transition || return 1
    firewall_recover_pending_rollbacks || return 1
    if firewall_control_plane_present && ! command -v nft >/dev/null 2>&1; then
        err "缺少 nft 命令，无法确认并删除当前 vpsbox 规则表。"
        return 1
    fi
    if is_systemd; then
        systemctl disable --now "$FIREWALL_SERVICE_NAME" >/dev/null 2>&1 || true
        systemctl is-active --quiet "$FIREWALL_SERVICE_NAME" 2>/dev/null && failed=1
        systemctl is-enabled --quiet "$FIREWALL_SERVICE_NAME" 2>/dev/null && failed=1
    elif [ "$OS" = "alpine" ]; then
        rc-service "$FIREWALL_SERVICE_NAME" stop >/dev/null 2>&1 || true
        rc-update del "$FIREWALL_SERVICE_NAME" default >/dev/null 2>&1 || true
        rc-service "$FIREWALL_SERVICE_NAME" status >/dev/null 2>&1 && failed=1
        { [ -e "/etc/runlevels/default/$FIREWALL_SERVICE_NAME" ] ||
            [ -L "/etc/runlevels/default/$FIREWALL_SERVICE_NAME" ]; } && failed=1
    fi
    if command -v nft >/dev/null 2>&1; then
        nft delete table inet vpsbox >/dev/null 2>&1 || true
        nft list table inet vpsbox >/dev/null 2>&1 && failed=1
    fi
    [ "$failed" -eq 0 ] || {
        err "无法完整停止防火墙服务或删除 inet vpsbox 规则表，已保留管理文件便于重试。"
        return 1
    }
    if ! rm -f "$FIREWALL_CONFIG" "$FIREWALL_STATE_FILE" \
        "$FIREWALL_SYSTEMD_UNIT" "$FIREWALL_OPENRC_SERVICE"; then
        err "防火墙已停止，但管理文件删除失败。"
        return 1
    fi
    is_systemd && systemctl daemon-reload >/dev/null 2>&1 || true
    info "vpsbox 主机防火墙已关闭；其他程序的规则未被修改。"
}

firewall_disable() {
    local answer
    firewall_recover_pending_rollbacks || return 1
    if ! firewall_artifacts_present; then
        info "主机防火墙未启用，无需关闭。"
        return 0
    fi
    read -r -p "关闭后将不再由 vpsbox 限制入站连接，输入 YES 确认：" answer || return 1
    [ "$answer" = "YES" ] || { info "已取消。"; return 0; }
    firewall_disable_internal
}

firewall_menu() {
    local opt ssh_ports node_tcp node_udp docker_tcp docker_udp public_tcp public_udp protocol
    local ssh_known node_tcp_known node_udp_known docker_tcp_known docker_udp_known known_tcp known_udp

    firewall_settle_pending_port_transition || return 1
    while true; do
        firewall_load_state || return 1
        ssh_ports="$(ssh_effective_ports_csv 2>/dev/null || echo "-")"
        node_tcp="-"
        node_udp="-"
        for protocol in vless ss; do
            if load_protocol_state "$protocol" >/dev/null 2>&1; then
                [ "$node_tcp" = "-" ] && node_tcp=""
                node_tcp="$(csv_add_port "$node_tcp" "$PORT")"
                if [ "$protocol" = "ss" ]; then
                    [ "$node_udp" = "-" ] && node_udp=""
                    node_udp="$(csv_add_port "$node_udp" "$PORT")"
                fi
            fi
        done
        node_tcp="${node_tcp:--}"
        node_udp="${node_udp:--}"
        docker_tcp="-"
        docker_udp="-"
        if firewall_docker_available; then
            if firewall_detect_docker_ports; then
                docker_tcp="${FW_DOCKER_PUBLIC_TCP:--}"
                docker_udp="${FW_DOCKER_PUBLIC_UDP:--}"
            fi
        elif command -v docker >/dev/null 2>&1; then
            docker_tcp="daemon 不可用"
            docker_udp="daemon 不可用"
        fi
        public_tcp="-"
        public_udp="-"
        if firewall_detect_public_listeners 2>/dev/null; then
            ssh_known="$(normalize_port_csv "$ssh_ports" 2>/dev/null || true)"
            node_tcp_known="$(normalize_port_csv "$node_tcp" 2>/dev/null || true)"
            node_udp_known="$(normalize_port_csv "$node_udp" 2>/dev/null || true)"
            docker_tcp_known="$(normalize_port_csv "$docker_tcp" 2>/dev/null || true)"
            docker_udp_known="$(normalize_port_csv "$docker_udp" 2>/dev/null || true)"
            known_tcp="$(merge_port_csv "$ssh_known" "$node_tcp_known" "$docker_tcp_known" "$FW_EXTRA_TCP")"
            known_udp="$(merge_port_csv "$node_udp_known" "$docker_udp_known" "$FW_EXTRA_UDP")"
            public_tcp="$(subtract_port_csv "$FW_PUBLIC_TCP" "$known_tcp")"
            public_udp="$(subtract_port_csv "$FW_PUBLIC_UDP" "$known_udp")"
            public_tcp="${public_tcp:--}"
            public_udp="${public_udp:--}"
        fi

        clear 2>/dev/null || true
        cat <<EOF
========================================
 主机防火墙
========================================
 nftables：$(firewall_install_state)
 防火墙：$(firewall_runtime_state)
 开机加载：$(firewall_persistence_state)
----------------------------------------
 SSH TCP：$ssh_ports
 节点 TCP：$node_tcp
 节点 UDP：$node_udp
 Docker TCP：$docker_tcp
 Docker UDP：$docker_udp
 其他公网 TCP：$public_tcp
 其他公网 UDP：$public_udp
 额外 TCP：${FW_EXTRA_TCP:--}
 额外 UDP：${FW_EXTRA_UDP:--}
 默认入站：拒绝未放行的连接
 出站规则：不创建
----------------------------------------
 [1] 一键开启/更新防火墙
 [2] 查看当前放行端口
 [3] 管理额外放行端口
 [4] 关闭并移除 vpsbox 防火墙
----------------------------------------
 [0] 返回主菜单
========================================
EOF
        read -r -p "请输入选项: " opt || return 0
        echo ""
        case "$opt" in
            1) run_menu_action firewall_apply_desired_state; pause ;;
            2) run_menu_action firewall_view_rules; pause ;;
            3) firewall_extra_ports_menu ;;
            4) run_menu_action firewall_disable; pause ;;
            0) return 0 ;;
            *) warn "无效选项：$opt"; pause ;;
        esac
    done
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

check_info() {
    check_row "INFO" "$1" "${2:-}"
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
    local output

    command -v getent >/dev/null 2>&1 || return 1
    output="$(run_bounded_command 12 getent ahosts "$host" 2>/dev/null)" || return 1
    printf '%s\n' "$output" | awk '{print $1}' | sort -u | head -n 5
}

run_self_check() {
    detect_os
    local has_node="0"
    local node_integrity_failed="0"
    local max_use
    local max_file
    local state node_protocols protocol label ips

    max_use="$(journald_conf_value SystemMaxUse || echo "未配置")"
    max_file="$(journald_conf_value SystemMaxFileSize || echo "未配置")"

    cat <<EOF
========================================
 一键检测
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

    if node_artifacts_present && ! require_valid_node_state_if_present >/dev/null 2>&1; then
        node_integrity_failed="1"
        check_fail "配置完整性" "未通过"
    fi
    for protocol in vless ss; do
        load_protocol_state "$protocol" >/dev/null 2>&1 || continue
        has_node="1"
        [ "$protocol" = "vless" ] && label="VLESS Reality" || label="Shadowsocks"
        check_ok "$label 节点" "${DOMAIN:-未知}:${PORT:-未知}"
        if [ "$protocol" = "vless" ]; then
            check_ok "Reality SNI" "${REALITY_SERVER_NAME:-未知}"
            node_protocols=tcp
        else
            node_protocols=both
        fi
        if port_listener_ready "$PORT" "$node_protocols"; then
            check_ok "$label 监听" "$PORT 正在监听"
        else
            check_warn "$label 监听" "$PORT 未监听"
        fi
        if is_ip_address "$DOMAIN"; then
            check_ok "$label 地址" "$DOMAIN"
        elif is_valid_node_host "$DOMAIN"; then
            ips="$(resolve_host_ips "$DOMAIN" | tr '\n' ' ')"
            if [ -n "$ips" ]; then
                check_ok "$label 解析" "$ips"
            else
                check_warn "$label 解析" "未解析到 IP"
            fi
        else
            check_fail "$label 地址" "格式不正确：$DOMAIN"
        fi
    done
    if [ "$has_node" != "1" ] && [ "$node_integrity_failed" != "1" ]; then
        check_warn "节点" "未创建"
    fi

    if [ "$node_integrity_failed" = "1" ]; then
        check_fail "配置语法" "配置完整性未通过"
    elif [ "$has_node" = "1" ] && singbox_installed; then
        if check_active_node_config >/dev/null 2>&1; then
            check_ok "配置语法" "通过"
        else
            check_fail "配置语法" "未通过"
        fi
    elif [ "$has_node" = "1" ]; then
        check_warn "配置语法" "sing-box 未安装，无法检查"
    elif ! node_artifacts_present; then
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

    if [ "$has_node" = "1" ] && [ -s "$URI_FILE" ]; then
        check_ok "节点链接" "$URI_FILE"
    elif [ "$has_node" = "1" ]; then
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
    if ssh_effective_ports_listening; then
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

    if ! firewall_control_plane_present; then
        if [ -e "$FIREWALL_STATE_FILE" ]; then
            check_info "主机防火墙" "未启用，已保存额外端口"
        else
            check_info "主机防火墙" "未启用（如已使用厂商安全组可忽略）"
        fi
    elif ! firewall_managed_file_is_secure "$FIREWALL_CONFIG" ||
        ! firewall_state_file_is_secure; then
        check_fail "主机防火墙" "配置文件不完整或不安全"
    elif ! firewall_runtime_enabled; then
        check_fail "主机防火墙" "配置存在但规则未运行"
    else
        check_ok "主机防火墙" "运行中"
        if firewall_persistence_enabled && firewall_service_active; then
            check_ok "防火墙自启" "已启用"
        else
            check_fail "防火墙自启" "未正常启用"
        fi
        if firewall_config_matches_expected >/dev/null 2>&1; then
            check_ok "防火墙端口" "与 SSH/节点/Docker/公网监听状态一致"
        else
            check_fail "防火墙端口" "配置已过期，请执行防火墙更新"
        fi
    fi

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
    local arch asset tmp confirm

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

trace_has_asn() {
    local output="$1"
    local asn="$2"

    printf '%s\n' "$output" | grep -Eiq "(^|[^[:alnum:]_])AS[[:space:]]*${asn}([^[:alnum:]_]|$)"
}

trace_hop_count() {
    local output="$1"
    local prefix="$2"

    printf '%s\n' "$output" | awk -v prefix="$prefix" '
        {
            line = $0
            sub(/^[[:space:]]*/, "", line)
            hop = line
            sub(/[[:space:]].*$/, "", hop)
            if (hop ~ /^[0-9]+$/ && index($0, prefix) > 0) seen[hop] = 1
        }
        END {
            count = 0
            for (hop in seen) count++
            print count
        }
    '
}

trace_output_has_hop() {
    trace_has "$1" '^[[:space:]]*[0-9]+[[:space:]].*([0-9]{1,3}\.){3}[0-9]{1,3}'
}

validate_trace_targets() {
    local i
    local expected=$(( ${#TRACE_REGIONS[@]} * ${#TRACE_ISPS[@]} ))

    if [ "${#TRACE_NAMES[@]}" -ne "$expected" ] || [ "${#TRACE_IPS[@]}" -ne "$expected" ]; then
        err "三网回程目标配置数量不一致。"
        return 1
    fi
    for i in "${!TRACE_IPS[@]}"; do
        if ! is_ipv4_address "${TRACE_IPS[$i]}"; then
            err "三网回程目标 IP 无效：${TRACE_NAMES[$i]} (${TRACE_IPS[$i]})"
            return 1
        fi
    done
}

detect_trace_line() {
    local output="$1"
    local has_4134=0
    local has_4809=0
    local count_20297=0
    local count_5943=0

    (trace_has_asn "$output" 4134 || trace_has "$output" '202\.97\.') && has_4134=1
    (trace_has_asn "$output" 4809 || trace_has "$output" '59\.43\.') && has_4809=1
    count_20297="$(trace_hop_count "$output" '202.97.')"
    count_5943="$(trace_hop_count "$output" '59.43.')"

    if trace_has_asn "$output" 23764 || trace_has "$output" '69\.194\.|203\.22\.'; then
        echo "CTGNet|AS23764"
    elif trace_has_asn "$output" 10099; then
        echo "10099|AS10099"
    elif trace_has_asn "$output" 58807 || trace_has "$output" '223\.120\.(1(2[89]|[3-9][0-9])|2([0-4][0-9]|5[0-5]))\.'; then
        echo "CMIN2|AS58807"
    elif trace_has_asn "$output" 9929 || trace_has "$output" '218\.105\.|210\.51\.'; then
        echo "9929|AS9929"
    elif [ "$has_4134" = "1" ] && [ "$has_4809" = "1" ] && [ "$count_20297" -gt 1 ]; then
        echo "CN2 GT|AS4134/AS4809"
    elif [ "$has_4809" = "1" ] && [ "$count_5943" -gt 0 ]; then
        echo "CN2 GIA|AS4809"
    elif [ "$has_4809" = "1" ]; then
        echo "CN2待确认|AS4809"
    elif [ "$has_4134" = "1" ]; then
        echo "163|AS4134"
    elif trace_has_asn "$output" 4837 || trace_has "$output" '219\.158\.'; then
        echo "4837|AS4837"
    elif trace_has_asn "$output" 58453 || trace_has "$output" '223\.(118|119|121)\.|223\.120\.(0|[1-9][0-9]|1[01][0-9]|12[0-7])\.'; then
        echo "CMI|AS58453"
    elif trace_has_asn "$output" 9808 || trace_has "$output" '221\.(176|183)\.'; then
        echo "CMNET|AS9808"
    elif trace_has_asn "$output" 3356; then
        echo "Lumen|AS3356"
    else
        echo "Hidden|-"
    fi
}

nexttrace_supports_size_compare() {
    local help flag
    local -a missing=()

    help="$(nexttrace --help 2>&1 || true)"
    if [ -z "$help" ]; then
        err "无法读取 nexttrace 参数列表。"
        return 1
    fi

    for flag in --psize --source-port --parallel-requests --queries; do
        grep -Fq -e "$flag" <<< "$help" || missing+=("$flag")
    done
    if [ "${#missing[@]}" -gt 0 ]; then
        err "当前 nexttrace 不支持大小包对比所需参数：${missing[*]}"
        err "请更新 nexttrace 后重试；vpsbox 不会覆盖已有的外部安装。"
        return 1
    fi
    return 0
}

run_nexttrace_sized_target() {
    local ip="$1"
    local source_port="$2"
    local packet_size="$3"
    local -a args=(
        -n -P -C -T -p 80
        --source-port "$source_port"
        --parallel-requests 1
        --queries "$TRACE_SIZE_QUERIES"
        --psize "$packet_size"
        "$ip"
    )

    run_bounded_command 30 nexttrace "${args[@]}" 2>&1
}

trace_asn_path_file() {
    local output_file="$1"

    awk '
        {
            line = $0
            sub(/^[[:space:]]*/, "", line)
            hop = line
            sub(/[[:space:]].*$/, "", hop)
            if (hop !~ /^[0-9]+$/) next

            while (match(line, /AS[[:space:]]*[0-9]+/)) {
                asn = substr(line, RSTART, RLENGTH)
                gsub(/[^0-9]/, "", asn)
                if (asn != "" && asn != "0" && asn != last) {
                    if (path != "") path = path ">"
                    path = path asn
                    last = asn
                }
                line = substr(line, RSTART + RLENGTH)
            }
        }
        END { print path }
    ' "$output_file"
}

trace_file_has_hop() {
    grep -Eq '^[[:space:]]*[0-9]+[[:space:]].*([0-9]{1,3}\.){3}[0-9]{1,3}' "$1"
}

trace_asn_label() {
    case "$1" in
        4134) printf '163' ;;
        4809) printf 'CN2' ;;
        23764) printf 'CTGNet' ;;
        10099) printf '10099' ;;
        9929) printf '9929' ;;
        4837) printf '4837' ;;
        58807) printf 'CMIN2' ;;
        58453) printf 'CMI' ;;
        9808) printf 'CMNET' ;;
        3356) printf 'Lumen' ;;
        *) printf 'AS%s' "$1" ;;
    esac
}

trace_asn_path_display() {
    local path="$1"
    local asn label output="" last_label=""
    local -a asns=()

    if [ -z "$path" ]; then
        printf '-'
        return 0
    fi

    IFS='>' read -r -a asns <<< "$path"
    for asn in "${asns[@]}"; do
        [ -n "$asn" ] || continue
        label="$(trace_asn_label "$asn")"
        [ "$label" = "$last_label" ] && continue
        if [ -n "$output" ]; then
            output+=" → "
        fi
        output+="$label"
        last_label="$label"
    done
    printf '%s' "${output:--}"
}

capture_size_trace() {
    local ip="$1"
    local source_port="$2"
    local packet_size="$3"
    local output_file="$4"
    local path

    if ! : > "$output_file"; then
        err "无法创建大小包探测临时文件：$output_file"
        return 1
    fi
    if ! run_nexttrace_sized_target "$ip" "$source_port" "$packet_size" > "$output_file"; then
        :
    fi

    if ! trace_file_has_hop "$output_file"; then
        printf 'fail|\n'
        return 0
    fi

    path="$(trace_asn_path_file "$output_file")"
    if [ -n "$path" ]; then
        printf 'ok|%s\n' "$path"
    else
        printf 'no-asn|\n'
    fi
}

size_trace_path_display() {
    local state="$1"
    local path="$2"

    case "$state" in
        ok) trace_asn_path_display "$path" ;;
        no-asn) printf '无 ASN' ;;
        *) printf '失败' ;;
    esac
}

write_route_result_from_trace_file() {
    local name="$1"
    local ip="$2"
    local output_file="$3"
    local result_file="$4"
    local output detected result asn

    if [ ! -f "$output_file" ]; then
        err "三网回程探测输出不存在：$output_file"
        return 1
    fi

    output="$(<"$output_file")"
    detected="$(detect_trace_line "$output")"
    result="${detected%%|*}"
    asn="${detected#*|}"
    if [ "$result" = "Hidden" ] && ! trace_output_has_hop "$output"; then
        result="Fail"
        asn="-"
    fi

    printf '%s|%s|%s|%s\n' "$name" "$ip" "$result" "$asn" > "$result_file"
}

check_combined_route_target() {
    local name="$1"
    local ip="$2"
    local source_port="$3"
    local file_prefix="$4"
    local route_result_file="$5"
    local size_result_file="$6"
    local small1 large1 small2 large2
    local small1_state large1_state small2_state="" large2_state=""
    local small1_path large1_path small2_path="" large2_path=""
    local small_display large_display status

    small1="$(capture_size_trace "$ip" "$source_port" "$TRACE_SIZE_SMALL" "${file_prefix}.small1")" || return 1
    small1_state="${small1%%|*}"
    small1_path="${small1#*|}"
    write_route_result_from_trace_file "$name" "$ip" "${file_prefix}.small1" "$route_result_file" || return 1

    large1="$(capture_size_trace "$ip" "$source_port" "$TRACE_SIZE_LARGE" "${file_prefix}.large1")" || return 1
    large1_state="${large1%%|*}"
    large1_path="${large1#*|}"

    if [ "$small1_state" = "fail" ] || [ "$large1_state" = "fail" ]; then
        status="Fail"
    elif [ "$small1_state" != "ok" ] || [ "$large1_state" != "ok" ]; then
        status="Unknown"
    elif [ "$small1_path" = "$large1_path" ]; then
        status="Same"
    else
        printf '          首轮路径不同，正在执行 %s B → %s B 复测...\n' "$TRACE_SIZE_LARGE" "$TRACE_SIZE_SMALL"
        large2="$(capture_size_trace "$ip" "$source_port" "$TRACE_SIZE_LARGE" "${file_prefix}.large2")" || return 1
        large2_state="${large2%%|*}"
        large2_path="${large2#*|}"

        small2="$(capture_size_trace "$ip" "$source_port" "$TRACE_SIZE_SMALL" "${file_prefix}.small2")" || return 1
        small2_state="${small2%%|*}"
        small2_path="${small2#*|}"

        if [ "$small2_state" != "ok" ] || [ "$large2_state" != "ok" ]; then
            status="Unknown"
        elif [ "$small1_path" = "$small2_path" ] && [ "$large1_path" = "$large2_path" ] && [ "$small1_path" != "$large1_path" ]; then
            status="Split"
        else
            status="Fluctuation"
        fi
    fi

    small_display="$(size_trace_path_display "$small1_state" "$small1_path")"
    large_display="$(size_trace_path_display "$large1_state" "$large1_path")"
    printf '%s|%s|%s|%s\n' "$name" "$small_display" "$large_display" "$status" > "$size_result_file"
}

size_trace_status_label() {
    case "$1" in
        Same) printf '未发现差异' ;;
        Split) printf '疑似大小包分流' ;;
        Fluctuation) printf '路由波动' ;;
        Unknown) printf '无法判断' ;;
        *) printf '探测失败' ;;
    esac
}

show_size_trace_summary() {
    local tmp_dir="$1"
    local i name small_path large_path status
    local same=0 split=0 fluctuation=0 unknown=0 failed=0
    local abnormal=0
    local -a names=() small_paths=() large_paths=() statuses=()

    for i in "${!TRACE_NAMES[@]}"; do
        if [ -s "$tmp_dir/size.$i" ]; then
            IFS='|' read -r name small_path large_path status < "$tmp_dir/size.$i" || true
        else
            name="${TRACE_NAMES[$i]}"
            small_path="失败"
            large_path="失败"
            status="Fail"
        fi
        names[i]="$name"
        small_paths[i]="$small_path"
        large_paths[i]="$large_path"
        statuses[i]="$status"
        case "$status" in
            Same) same=$((same + 1)) ;;
            Split) split=$((split + 1)) ;;
            Fluctuation) fluctuation=$((fluctuation + 1)) ;;
            Unknown) unknown=$((unknown + 1)) ;;
            *) failed=$((failed + 1)) ;;
        esac
        [ "$status" = "Same" ] || abnormal=$((abnormal + 1))
    done

    cat <<EOF
========================================
 大小包路由对比
========================================
方式：TCP 80　小包：${TRACE_SIZE_SMALL} B　大包：${TRACE_SIZE_LARGE} B
结果：一致 $same | 疑似分流 $split | 波动 $fluctuation | 无法判断 $unknown | 失败 $failed
EOF
    if [ "$abnormal" -eq 0 ]; then
        printf '%d 个目标未发现大小包路径差异。\n' "${#TRACE_NAMES[@]}"
        return 0
    fi

    cat <<'EOF'
------------------------------------------------------------------------
差异/异常详情：
目标       | 小包路径 | 大包路径 | 结果
EOF
    for i in "${!TRACE_NAMES[@]}"; do
        [ "${statuses[$i]}" = "Same" ] && continue
        printf ' %-10s | %s | %s | %s\n' \
            "${names[$i]}" "${small_paths[$i]}" "${large_paths[$i]}" "$(size_trace_status_label "${statuses[$i]}")"
    done
}

format_trace_cell() {
    local result="$1"

    case "$result" in
        CN2待确认) printf '%s%*s' "$result" 5 "" ;;
        *) printf '%-14s' "$result" ;;
    esac
}

format_trace_region() {
    printf ' %s    ' "$1"
}

show_backtrace_matrix() {
    local tmp_dir="$1"
    local i result_file name ip result asn region isp
    local identified=0 hidden=0 failed=0 total="${#TRACE_NAMES[@]}"
    local report_time
    local -a issues=()
    local -A results=()

    report_time="$(date '+%Y-%m-%d %H:%M:%S %Z')"

    for i in "${!TRACE_NAMES[@]}"; do
        result_file="$tmp_dir/$i"
        if [ -s "$result_file" ]; then
            IFS='|' read -r name ip result asn < "$result_file" || true
        else
            name="${TRACE_NAMES[$i]}"
            ip="${TRACE_IPS[$i]}"
            result="Fail"
            asn="-"
        fi
        results["$name"]="$result"
        case "$result" in
            Hidden) hidden=$((hidden + 1)); issues+=("$name|$ip|Hidden") ;;
            Fail) failed=$((failed + 1)); issues+=("$name|$ip|Fail") ;;
            *) identified=$((identified + 1)) ;;
        esac
    done

    cat <<EOF
 报告时间：$report_time
 方式：TCP 80　包大小：${TRACE_SIZE_SMALL} B　目标：$total　并发：1
--------------------------------------------------------
 地区    电信          联通          移动
EOF

    for region in "${TRACE_REGIONS[@]}"; do
        format_trace_region "$region"
        for isp in "${TRACE_ISPS[@]}"; do
            name="${region}${isp}"
            format_trace_cell "${results["$name"]:-Fail}"
        done
        printf '\n'
    done

    printf '\n--------------------------------------------------------\n'
    printf ' 结果：目标 %d | 已识别 %d | Hidden %d | Fail %d\n' "$total" "$identified" "$hidden" "$failed"
    if [ "${#issues[@]}" -gt 0 ]; then
        printf '\n 未识别/失败：\n'
        for i in "${issues[@]}"; do
            IFS='|' read -r name ip result <<< "$i"
            printf ' %-8s %-15s %s\n' "$name" "$ip" "$result"
        done
    fi
}

show_backtrace_routes() {
    validate_trace_targets || return 1
    ensure_nexttrace || return 1
    nexttrace_supports_size_compare || return 1

    local i name ip tmp_dir source_port
    local total="${#TRACE_NAMES[@]}"

    # 固定源端口并严格串行，避免五元组变化或并发 TCP 探测造成路径误判。
    source_port="$(random_trace_source_port)" || return 1
    tmp_dir="$(mktemp -d /tmp/vpsbox-trace.XXXXXX)" || { err "无法创建回程检测临时目录。"; return 1; }
    [[ "$tmp_dir" == /tmp/vpsbox-trace.* ]] || { err "回程检测临时目录路径异常。"; return 1; }
    ACTIVE_TRACE_TMP="$tmp_dir"
    trap 'cleanup_active_trace_tmp' RETURN

    cat <<EOF
========================================
 三网回程与大小包路由对比
========================================
模式：TCP 80
包大小：${TRACE_SIZE_SMALL} B / ${TRACE_SIZE_LARGE} B
策略：严格串行，首轮不同的目标自动反向复测
目标：$total 个，每次探测最多 30 秒，请稍等...
EOF

    for i in "${!TRACE_NAMES[@]}"; do
        name="${TRACE_NAMES[$i]}"
        ip="${TRACE_IPS[$i]}"
        printf '[%d/%d] %s：%s B → %s B\n' \
            "$((i + 1))" "$total" "$name" "$TRACE_SIZE_SMALL" "$TRACE_SIZE_LARGE"
        if ! check_combined_route_target \
            "$name" "$ip" "$source_port" "$tmp_dir/probe.$i" "$tmp_dir/$i" "$tmp_dir/size.$i"; then
            err "$name 的三网回程与大小包检测未完成。"
            return 1
        fi
    done

    cat <<EOF

========================================
 三网回程（TCP 80，${TRACE_SIZE_SMALL} B）
========================================
EOF
    show_backtrace_matrix "$tmp_dir"

    printf '\n'
    show_size_trace_summary "$tmp_dir"

    cleanup_active_trace_tmp
    trap - RETURN

    cat <<'EOF'
========================================
提示：线路判断仅供参考；CN2 GT/GIA 以完整路径的 ASN 与跳数为准，可用 nexttrace 手动复核。
大小包结果只表示路由是否与探测包大小相关，不能单独证明线路存在人为欺骗。
EOF
}

uninstall_singbox_and_nodes() {
    local failed=0

    info "正在停止并禁用 sing-box 服务..."
    service_stop 2>/dev/null || warn "服务管理器未能正常停止 sing-box，将继续检查 vpsbox 配置对应的进程。"
    if ! stop_singbox_config_processes; then
        err "残留 sing-box 进程无法停止，已取消删除。"
        return 1
    fi
    sleep 1
    if service_is_running; then
        err "sing-box 服务仍在运行，已取消删除。"
        return 1
    fi
    service_disable 2>/dev/null ||
        warn "无法通过服务管理器禁用 sing-box，将继续清理并在最后复核。"

    if is_systemd; then
        rm -f /etc/systemd/system/sing-box.service \
            /etc/systemd/system/multi-user.target.wants/sing-box.service \
            /usr/lib/systemd/system/sing-box.service \
            /lib/systemd/system/sing-box.service || failed=1
        systemctl daemon-reload 2>/dev/null || failed=1
        systemctl reset-failed sing-box 2>/dev/null || true
    fi

    if [ "$OS" = "alpine" ]; then
        rm -f /etc/init.d/sing-box /etc/runlevels/default/sing-box || failed=1
        if singbox_package_installed &&
            ! apk_bounded "$PACKAGE_INSTALL_TIMEOUT" del sing-box; then failed=1; fi
    elif [ "$OS" = "debian" ]; then
        if singbox_package_installed &&
            ! apt_get_bounded "$PACKAGE_INSTALL_TIMEOUT" purge -y sing-box; then failed=1; fi
    elif [ "$OS" = "redhat" ]; then
        if singbox_package_installed; then
            if command -v dnf >/dev/null 2>&1; then
                dnf_bounded "$PACKAGE_INSTALL_TIMEOUT" remove -y sing-box || failed=1
            else
                yum_bounded "$PACKAGE_INSTALL_TIMEOUT" remove -y sing-box || failed=1
            fi
        fi
    fi

    info "正在删除 sing-box 和节点配置..."
    [ "$CONFIG_DIR" = "/etc/sing-box" ] || {
        err "sing-box 配置目录异常，已拒绝递归删除：$CONFIG_DIR"
        return 1
    }
    rm -rf -- "$CONFIG_DIR" || failed=1
    rm -f /usr/bin/sing-box /usr/local/bin/sing-box || failed=1
    rm -f /var/log/sing-box* || failed=1
    hash -r

    if service_is_running || service_is_enabled || singbox_artifacts_present; then
        err "仍检测到 sing-box 的进程、软件包、服务或配置残留。"
        failed=1
    fi
    if [ "$failed" -ne 0 ]; then
        err "sing-box 卸载未完整通过验收，已保留 vpsbox 管理命令便于重试。"
        return 1
    fi

    info "sing-box 和节点配置已删除。"
}

uninstall_all() {
    local confirm
    local remove_singbox
    local remove_firewall

    echo "此操作会卸载 vpsbox 管理命令。"
    echo "默认不会删除 sing-box，也不会删除节点配置。"
    echo "如有已记录的系统设置，卸载前可选择恢复。"
    read -r -p "确认卸载 vpsbox？请输入 YES：" confirm
    [ "$confirm" = "YES" ] || { info "已取消。"; return 0; }

    offer_restore_recorded_changes_before_uninstall || {
        err "系统设置恢复未完成，已取消卸载并保留 vpsbox 管理命令。"
        return 1
    }

    if firewall_artifacts_present; then
        echo "检测到由 vpsbox 管理的主机防火墙。"
        read -r -p "卸载前必须关闭并移除该防火墙，输入 YES 继续：" remove_firewall
        if [ "$remove_firewall" != "YES" ]; then
            info "已取消卸载，主机防火墙和 vpsbox 命令均已保留。"
            return 0
        fi
        firewall_disable_internal || {
            err "主机防火墙未能完整移除，已取消卸载 vpsbox。"
            return 1
        }
    fi

    if ! singbox_artifacts_present; then
        info "未安装 sing-box，无需删除节点配置。"
    else
        read -r -p "是否同时删除 sing-box 和所有节点配置？请输入 YES 确认：" remove_singbox
        if [ "$remove_singbox" = "YES" ]; then
            uninstall_singbox_and_nodes || {
                err "sing-box 卸载未完成，已保留 vpsbox 管理命令便于重试。"
                return 1
            }
        else
            info "已保留 sing-box 和节点配置。"
        fi
    fi

    info "正在删除 vpsbox 命令..."
    if ! rm -f "$CMD_PATH" /usr/bin/vpsbox ||
        [ -e "$CMD_PATH" ] || [ -L "$CMD_PATH" ] ||
        [ -e /usr/bin/vpsbox ] || [ -L /usr/bin/vpsbox ]; then
        err "vpsbox 管理命令删除失败，请检查 $CMD_PATH 与 /usr/bin/vpsbox。"
        return 1
    fi

    info "卸载完成。"
    info "vpsbox 命令已删除，当前菜单即将退出。"
    exit 0
}

is_valid_hostname_value() {
    local value="$1"
    [ -n "$value" ] && [ "${#value}" -le 64 ] || return 1
    [[ "$value" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]] || return 1
    local label
    IFS='.' read -ra labels <<< "$value"
    for label in "${labels[@]}"; do
        [ -n "$label" ] && [ "${#label}" -le 63 ] || return 1
        [[ "$label" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$ ]] || return 1
    done
}

hostname_current_value() {
    if is_systemd && command -v hostnamectl >/dev/null 2>&1; then
        hostnamectl --static 2>/dev/null || hostname 2>/dev/null
    else
        hostname 2>/dev/null
    fi
}

set_system_hostname() {
    local value="$1"
    if is_systemd && command -v hostnamectl >/dev/null 2>&1; then
        hostnamectl set-hostname "$value"
    else
        hostname "$value"
    fi
}

hostname_hosts_markers_valid() {
    local begin_count end_count begin_line end_line

    [ -f "$HOSTS_PATH" ] && [ ! -L "$HOSTS_PATH" ] || return 1
    begin_count="$(grep -Fxc "$HOSTNAME_BEGIN" "$HOSTS_PATH" 2>/dev/null || true)"
    end_count="$(grep -Fxc "$HOSTNAME_END" "$HOSTS_PATH" 2>/dev/null || true)"
    if [ "$begin_count" = "0" ] && [ "$end_count" = "0" ]; then
        return 0
    fi
    [ "$begin_count" = "1" ] && [ "$end_count" = "1" ] || return 1
    begin_line="$(grep -Fnx "$HOSTNAME_BEGIN" "$HOSTS_PATH" | cut -d: -f1)"
    end_line="$(grep -Fnx "$HOSTNAME_END" "$HOSTS_PATH" | cut -d: -f1)"
    [ "$begin_line" -lt "$end_line" ]
}

hostname_short_name() {
    printf '%s\n' "${1%%.*}"
}

hostname_snapshot_file() {
    local dir="$1" name="$2" target="$3"

    [ ! -L "$target" ] || return 1
    if [ -e "$target" ]; then
        [ -f "$target" ] || return 1
        cp -a -- "$target" "$dir/$name" || return 1
        : > "$dir/$name.present"
    else
        : > "$dir/$name.absent"
    fi
}

create_hostname_operation_snapshot() {
    local output_var="$1" current_hostname="$2" dir

    dir="$(mktemp -d /tmp/vpsbox-hostname.XXXXXX)" || return 1
    chmod 700 "$dir" || { rm -rf -- "$dir"; return 1; }
    if ! hostname_snapshot_file "$dir" hostname "$HOSTNAME_PATH" ||
        ! hostname_snapshot_file "$dir" hosts "$HOSTS_PATH" ||
        ! printf '%s\n' "$current_hostname" > "$dir/runtime-hostname" ||
        ! chmod 600 "$dir/runtime-hostname"; then
        rm -rf -- "$dir"
        return 1
    fi
    printf -v "$output_var" '%s' "$dir"
}

restore_hostname_snapshot_file() {
    local dir="$1" name="$2" target="$3" parent tmp

    if [ -e "$dir/$name.present" ]; then
        [ -f "$dir/$name" ] && [ ! -L "$dir/$name" ] || return 1
        parent="$(dirname "$target")"
        [ -d "$parent" ] && [ ! -L "$parent" ] || return 1
        tmp="$(mktemp "$parent/.vpsbox-hostname-restore.XXXXXX")" || return 1
        if ! cp -a -- "$dir/$name" "$tmp" ||
            { [ -L "$target" ] && ! rm -f -- "$target"; } ||
            ! mv -f -- "$tmp" "$target"; then
            rm -f -- "$tmp"
            return 1
        fi
    elif [ -e "$dir/$name.absent" ]; then
        rm -f -- "$target"
    else
        return 1
    fi
}

hostname_operation_snapshot_valid() {
    local dir="$1" runtime

    { [[ "$dir" == /tmp/vpsbox-hostname.* ]] ||
        [ "${VPSBOX_TEST_MODE:-0}" = "1" ]; } &&
        [ -d "$dir" ] && [ ! -L "$dir" ] || return 1
    [ -f "$dir/runtime-hostname" ] && [ ! -L "$dir/runtime-hostname" ] || return 1
    runtime="$(cat "$dir/runtime-hostname" 2>/dev/null || true)"
    is_valid_hostname_value "$runtime" || return 1
    { [ -e "$dir/hostname.present" ] && [ ! -e "$dir/hostname.absent" ]; } ||
        { [ -e "$dir/hostname.absent" ] && [ ! -e "$dir/hostname.present" ]; } || return 1
    { [ -e "$dir/hosts.present" ] && [ ! -e "$dir/hosts.absent" ]; } ||
        { [ -e "$dir/hosts.absent" ] && [ ! -e "$dir/hosts.present" ]; } || return 1
}

rollback_hostname_change() {
    local snapshot="$1" original failed=0

    hostname_operation_snapshot_valid "$snapshot" || return 1
    original="$(cat "$snapshot/runtime-hostname")"
    restore_hostname_snapshot_file "$snapshot" hostname "$HOSTNAME_PATH" || failed=1
    restore_hostname_snapshot_file "$snapshot" hosts "$HOSTS_PATH" || failed=1
    set_system_hostname "$original" >/dev/null 2>&1 || failed=1
    [ "$(hostname_current_value 2>/dev/null || true)" = "$original" ] || failed=1
    if [ "$failed" -eq 0 ]; then
        manifest_remove PENDING_HOSTNAME || failed=1
    fi
    if [ "$failed" -eq 0 ]; then
        rm -rf -- "$snapshot"
        return 0
    fi
    warn "本次主机名操作恢复未完成，临时快照已保留：$snapshot"
    return 1
}

change_system_hostname() {
    local old new short_name hosts_entry tmp operation_snapshot=""
    old="$(hostname_current_value)"
    echo "当前主机名：$old"
    read -r -p "请输入新主机名（留空取消）: " new
    new="$(sanitize_paste_input "$new")"
    [ -n "$new" ] || { info "已取消。"; return 0; }
    is_valid_hostname_value "$new" || { err "主机名格式不正确：仅允许字母、数字、点和连字符，长度不超过 64。"; return 1; }
    [ "$new" != "$old" ] || { info "新旧主机名相同。"; return 0; }
    [ ! -L "$HOSTNAME_PATH" ] || { err "$HOSTNAME_PATH 是符号链接，已拒绝修改。"; return 1; }
    hostname_hosts_markers_valid || { err "$HOSTS_PATH 是符号链接或 vpsbox 主机名标记异常，已拒绝修改。"; return 1; }
    backup_change_file_once HOSTNAME_FILE "$HOSTNAME_PATH" || return 1
    backup_change_file_once HOSTS_FILE "$HOSTS_PATH" || return 1
    manifest_set_once HOSTNAME_VALUE "$old" || return 1
    begin_change_transaction HOSTNAME || { err "记录主机名修改事务失败，已取消修改。"; return 1; }
    if ! create_hostname_operation_snapshot operation_snapshot "$old"; then
        manifest_remove PENDING_HOSTNAME || true
        err "无法创建本次主机名操作快照，已取消修改。"
        return 1
    fi
    short_name="$(hostname_short_name "$new")"
    hosts_entry="127.0.1.1 $new"
    [ "$short_name" = "$new" ] || hosts_entry+=" $short_name"

    tmp="$(mktemp "$(dirname "$HOSTNAME_PATH")/.hostname.vpsbox.XXXXXX")" || {
        rollback_hostname_change "$operation_snapshot" || true
        return 1
    }
    printf '%s\n' "$new" > "$tmp"
    if ! chown root:root "$tmp" || ! chmod 644 "$tmp" || ! mv -f "$tmp" "$HOSTNAME_PATH" || ! set_system_hostname "$new"; then
        rm -f "$tmp"
        rollback_hostname_change "$operation_snapshot" || true
        err "主机名修改失败，已尝试恢复原主机名。"
        return 1
    fi

    tmp="$(mktemp "$(dirname "$HOSTS_PATH")/.hosts.vpsbox.XXXXXX")" || {
        rollback_hostname_change "$operation_snapshot" || true
        return 1
    }
    if ! awk -v begin="$HOSTNAME_BEGIN" -v end="$HOSTNAME_END" '
        $0 == begin { skip=1; next }
        $0 == end { skip=0; next }
        !skip { print }
    ' "$HOSTS_PATH" > "$tmp"; then
        rm -f "$tmp"
        rollback_hostname_change "$operation_snapshot" || true
        err "读取 $HOSTS_PATH 失败，已恢复原配置。"
        return 1
    fi
    {
        printf '%s\n' "$HOSTNAME_BEGIN"
        printf '%s\n' "$hosts_entry"
        printf '%s\n' "$HOSTNAME_END"
    } >> "$tmp"
    if ! chown root:root "$tmp" || ! chmod 644 "$tmp" || ! mv -f "$tmp" "$HOSTS_PATH"; then
        rm -f "$tmp"
        rollback_hostname_change "$operation_snapshot" || true
        err "更新 $HOSTS_PATH 失败，已恢复原配置。"
        return 1
    fi
    if [ "$(tr -d '\r\n' <"$HOSTNAME_PATH")" != "$new" ] || [ "$(hostname_current_value)" != "$new" ] || ! grep -Fqx "$hosts_entry" "$HOSTS_PATH"; then
        rollback_hostname_change "$operation_snapshot" || true
        err "主机名验证失败，已恢复原配置。"
        return 1
    fi
    if ! mark_change_applied HOSTNAME; then
        rollback_hostname_change "$operation_snapshot" || true
        err "无法记录主机名变更，已恢复原配置。"
        return 1
    fi
    rm -rf -- "$operation_snapshot"
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

cleanup_old_temp_dirs() {
    local base="$1" path

    case "$base" in
        /tmp|/var/tmp) ;;
        *) return 1 ;;
    esac
    [ -d "$base" ] && [ ! -L "$base" ] || return 0
    while IFS= read -r -d '' path; do
        [ -d "$path" ] && [ ! -L "$path" ] || continue
        case "$path" in
            "${ACTIVE_NODE_BACKUP:-}"|"${ACTIVE_TRACE_TMP:-}") continue ;;
        esac
        # 兼容 v1.0.32 及更早版本的 /tmp SSH 恢复快照：它可能是失败后仅存的
        # 重试依据，因此不再由垃圾清理自动删除。
        case "$path" in
            "$base"/vpsbox-node-backup.*|\
            "$base"/vpsbox-sing-box-release.*|\
            "$base"/vpsbox-sing-box-update.*|\
            "$base"/vpsbox-chrony.*|\
            "$base"/vpsbox-bbr.*|\
            "$base"/vpsbox-trace.*|\
            "$base"/vpsbox-journald.*)
                rm -rf -- "$path" || warn "清理遗留临时目录失败：$path"
                ;;
        esac
    done < <(
        find "$base" -xdev -mindepth 1 -maxdepth 1 -type d -user root -mtime +7 \
            \( -name 'vpsbox-node-backup.*' \
            -o -name 'vpsbox-sing-box-release.*' \
            -o -name 'vpsbox-sing-box-update.*' \
            -o -name 'vpsbox-chrony.*' \
            -o -name 'vpsbox-bbr.*' \
            -o -name 'vpsbox-trace.*' \
            -o -name 'vpsbox-journald.*' \) \
            -print0 2>/dev/null
    )
}

cleanup_orphaned_change_backups() {
    local backup name state old_file
    [ -d "$CHANGE_BACKUP_DIR" ] || return 0
    for backup in "$CHANGE_BACKUP_DIR"/*; do
        [ -f "$backup" ] || continue
        name="${backup##*/}"
        [[ "$name" =~ ^[A-Z0-9_]+$ ]] || continue
        state="$(manifest_value "BACKUP_$name" 2>/dev/null || true)"
        [ "$state" = "file" ] && continue
        old_file="$(find "$backup" -xdev -type f -mtime +30 -print -quit 2>/dev/null || true)"
        [ -n "$old_file" ] || continue
        if find "$backup" -xdev -type f -mtime +30 -delete 2>/dev/null; then
            info "已清理未引用的 vpsbox 备份：$name"
        else
            warn "清理未引用的 vpsbox 备份失败：$name"
            return 1
        fi
    done
}

cleanup_system_garbage() {
    local confirm journal_confirm
    echo "将扫描并清理：包管理器缓存、超过 7 天的 vpsbox 临时文件、未引用的 vpsbox 过期备份。"
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
    cleanup_old_temp_dirs /tmp
    cleanup_old_temp_dirs /var/tmp
    cleanup_orphaned_change_backups || warn "vpsbox 未引用备份清理不完整。"
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
    local name state found=0
    echo "vpsbox 已记录的系统变更："
    for name in HOSTNAME DNS_RESOLV DNS_RESOLVED BBR_CONF GAI_CONF FAIL2BAN_SSHD NTP_CONF JOURNALD_CONF; do
        state="$(change_restore_state "$name")"
        case "$state" in
            pending) printf ' - %s：未完成，可恢复\n' "$name"; found=1 ;;
            applied) printf ' - %s：可恢复\n' "$name"; found=1 ;;
        esac
    done
    [ "$found" -eq 1 ] || echo " - 无"
    echo "SSH 配置不会由此功能自动恢复，请保持当前连接并手动核验后处理。"
}

recorded_system_changes_present() {
    local name

    for name in HOSTNAME DNS_RESOLV DNS_RESOLVED BBR_CONF GAI_CONF FAIL2BAN_SSHD NTP_CONF JOURNALD_CONF; do
        change_needs_restore "$name" && return 0
    done
    return 1
}

offer_restore_recorded_changes_before_uninstall() {
    local confirm

    recorded_system_changes_present || return 0
    echo "检测到 vpsbox 已记录且可恢复的系统设置："
    show_vpsbox_changes
    if ! read -r -p "是否在卸载前恢复上述系统设置？请输入 YES 恢复，其他输入保留现状：" confirm; then
        err "未能读取恢复选择，已取消卸载。"
        return 1
    fi
    if [ "$confirm" = "YES" ]; then
        restore_vpsbox_system_changes 1
    else
        info "已保留当前系统设置。"
    fi
}

restore_vpsbox_system_changes() {
    local skip_confirmation="${1:-0}"
    local confirm cc fq old failed=0
    local fail2ban_active fail2ban_enabled

    if [ "$skip_confirmation" != "1" ]; then
        show_vpsbox_changes
        read -r -p "恢复上述 vpsbox 已记录的系统设置？请输入 YES：" confirm
        [ "$confirm" = "YES" ] || { info "已取消恢复。"; return 0; }
    fi

    if change_needs_restore HOSTNAME; then
        restore_change_file HOSTNAME_FILE "$HOSTNAME_PATH" || failed=1
        restore_change_file HOSTS_FILE "$HOSTS_PATH" || failed=1
        old="$(manifest_value HOSTNAME_VALUE 2>/dev/null || true)"
        [ -n "$old" ] && set_system_hostname "$old" 2>/dev/null || failed=1
    fi

    if change_needs_restore DNS_RESOLV && ! restore_change_file DNS_RESOLV "$RESOLV_CONF"; then failed=1; fi
    if change_needs_restore DNS_RESOLVED && ! restore_change_file DNS_RESOLVED /etc/systemd/resolved.conf.d/vpsbox.conf; then failed=1; fi
    if resolv_conf_managed_by_systemd_resolved && ! systemctl restart systemd-resolved; then failed=1; fi

    if change_needs_restore BBR_CONF; then
        restore_change_file BBR_CONF "$BBR_CONF" || failed=1
        cc="$(manifest_value BBR_CC 2>/dev/null || true)"; fq="$(manifest_value BBR_FQ 2>/dev/null || true)"
        if [ -n "$cc" ] && [ "$cc" != "unknown" ]; then sysctl -w "net.ipv4.tcp_congestion_control=$cc" >/dev/null 2>&1 || failed=1; fi
        if [ -n "$fq" ] && [ "$fq" != "unknown" ]; then sysctl -w "net.core.default_qdisc=$fq" >/dev/null 2>&1 || failed=1; fi
    fi
    if change_needs_restore GAI_CONF && ! restore_change_file GAI_CONF "$GAI_CONF"; then failed=1; fi
    if change_needs_restore FAIL2BAN_SSHD; then
        restore_change_file FAIL2BAN_SSHD "$FAIL2BAN_VPSBOX_SSHD_CONF" || failed=1
        if fail2ban_installed; then
            fail2ban-client -t -c /etc/fail2ban >/dev/null 2>&1 || failed=1
            fail2ban_active="$(manifest_value FAIL2BAN_ACTIVE 2>/dev/null || true)"
            fail2ban_enabled="$(manifest_value FAIL2BAN_ENABLED 2>/dev/null || true)"
            # 兼容 v1.0.0-v1.0.1 已记录 Fail2ban 配置但尚未记录服务状态的清单：
            # 缺失状态时不猜测启用关系，仅在服务当前仍运行时重启以加载恢复后的配置。
            if is_systemd; then
                if [ "$fail2ban_enabled" = "enabled" ]; then systemctl enable fail2ban || failed=1; elif [ "$fail2ban_enabled" = "disabled" ]; then systemctl disable fail2ban || failed=1; fi
                if [ "$fail2ban_active" = "active" ]; then systemctl restart fail2ban || failed=1; elif [ "$fail2ban_active" = "inactive" ]; then systemctl stop fail2ban || failed=1; elif systemctl is-active --quiet fail2ban; then systemctl restart fail2ban || failed=1; fi
            elif [ "$OS" = "alpine" ] && command -v rc-service >/dev/null 2>&1; then
                if [ "$fail2ban_enabled" = "enabled" ]; then rc-update add fail2ban default || failed=1; elif [ "$fail2ban_enabled" = "disabled" ]; then rc-update del fail2ban default || failed=1; fi
                if [ "$fail2ban_active" = "active" ]; then rc-service fail2ban restart || failed=1; elif [ "$fail2ban_active" = "inactive" ]; then rc-service fail2ban stop || failed=1; elif rc-service fail2ban status >/dev/null 2>&1; then rc-service fail2ban restart || failed=1; fi
            fi
        fi
    fi
    if change_needs_restore JOURNALD_CONF; then
        restore_change_file JOURNALD_CONF "$JOURNALD_VPSBOX_CONF" || failed=1
        is_systemd && systemctl restart systemd-journald && systemctl is-active --quiet systemd-journald || failed=1
    fi
    if change_needs_restore NTP_CONF; then
        if ! restore_recorded_ntp_change; then
            err "当前环境无法恢复 systemd 管理的 NTP 状态。"
            failed=1
        fi
    fi
    if [ "$failed" -eq 1 ]; then
        err "部分文件恢复失败；已保留变更清单和备份，请修复权限或路径后重试。"
        return 1
    fi
    if change_needs_restore HOSTNAME; then
        clear_change_tracking HOSTNAME_FILE || failed=1
        clear_change_tracking HOSTS_FILE || failed=1
        manifest_remove APPLIED_HOSTNAME || failed=1
        manifest_remove PENDING_HOSTNAME || failed=1
        manifest_remove HOSTNAME_VALUE || failed=1
    fi
    if change_needs_restore BBR_CONF; then
        clear_change_tracking BBR_CONF || failed=1
        manifest_remove BBR_CC || failed=1
        manifest_remove BBR_FQ || failed=1
    fi
    if change_needs_restore NTP_CONF; then
        clear_ntp_change_tracking || failed=1
    fi
    for name in DNS_RESOLV DNS_RESOLVED GAI_CONF FAIL2BAN_SSHD JOURNALD_CONF; do
        if change_needs_restore "$name"; then
            clear_change_tracking "$name" || failed=1
        fi
    done
    manifest_remove FAIL2BAN_ACTIVE || failed=1
    manifest_remove FAIL2BAN_ENABLED || failed=1
    if [ "$failed" -eq 1 ]; then
        err "恢复已完成部分步骤，但清单或备份清理失败，已保留剩余状态供人工核验。"
        return 1
    fi
    info "已恢复已记录项目；请使用自检和对应服务状态确认结果。"
}

verify_current_node_runtime() {
    verify_all_node_runtime
}

start_service_action() {
    require_valid_node_state_if_present || return 1
    if ! node_exists; then
        warn "当前没有节点配置，请先创建节点。"
        return 0
    fi

    if service_is_running &&
        verify_current_node_runtime &&
        singbox_service_definition_is_current; then
        if ! service_is_enabled; then
            service_enable || {
                err "sing-box 正在运行，但设置开机自启失败。"
                return 1
            }
        fi
        info "sing-box 服务已在运行，无需重复启动。"
        return 0
    fi

    install_singbox_if_missing || return 1
    if singbox_service_definition_is_current &&
        ! service_manager_is_active &&
        [ -z "$(singbox_config_pids)" ]; then
        service_is_enabled || service_enable || return 1
        service_start || return 1
    else
        setup_service || return 1
        restart_singbox_cleanly || return 1
    fi
    if ! verify_current_node_runtime; then
        err "sing-box 未保持运行或节点端口未按协议完整监听。"
        return 1
    fi
    info "sing-box 服务已启动。"
}

restart_service_action() {
    require_valid_node_state_if_present || return 1
    if ! node_exists; then
        warn "当前没有节点配置，请先创建节点。"
        return 0
    fi
    install_singbox_if_missing || return 1
    setup_service || return 1
    restart_singbox_cleanly || return 1
    if ! verify_current_node_runtime; then
        err "sing-box 未保持运行或节点端口未按协议完整监听。"
        return 1
    fi
    info "sing-box 服务已重启。"
}

stop_service_action() {
    local failed=0

    service_stop || failed=1
    stop_singbox_config_processes || failed=1
    if service_manager_is_active || [ -n "$(singbox_config_pids)" ]; then
        err "sing-box 服务或当前配置对应的残留进程仍在运行。"
        return 1
    fi
    if [ "$failed" -ne 0 ]; then
        err "sing-box 已停止，但服务管理命令执行失败，请检查服务定义。"
        return 1
    fi
    info "sing-box 服务已停止。"
}

singbox_summary_line() {
    local version status

    if ! singbox_installed; then
        echo " sing-box：未安装"
        return 0
    fi
    version="$(singbox_version)"
    [ -n "$version" ] && [ "$version" != "-" ] || version="版本未知"
    status="$(service_status_short)"
    printf ' sing-box：%s %s\n' "$version" "$status"
}

node_state() {
    local states=""

    protocol_visible_exists vless && states="VLESS Reality"
    if protocol_visible_exists ss; then
        [ -n "$states" ] && states="$states + Shadowsocks" || states="Shadowsocks"
    fi
    printf '%s\n' "${states:-未创建}"
}

node_address() {
    local protocol addresses=""

    for protocol in vless ss; do
        if load_protocol_state "$protocol" >/dev/null 2>&1; then
            [ -n "$addresses" ] && addresses="$addresses, "
            addresses="${addresses}${DOMAIN}:${PORT}"
        fi
    done
    printf '%s\n' "${addresses:--}"
}

node_summary() {
    local protocol label

    if node_artifacts_present &&
        ! require_valid_node_state_if_present >/dev/null 2>&1; then
        printf '%s\n 节点状态：异常，请进入节点管理检查\n' '----------------------------------------'
        return 0
    fi
    for protocol in vless ss; do
        load_protocol_state "$protocol" >/dev/null 2>&1 || continue
        [ "$protocol" = "vless" ] && label="VLESS Reality" || label="Shadowsocks"
        printf '%s\n' '----------------------------------------'
        printf ' %s 节点\n 状态：已创建\n 名称：%s\n 地址：%s\n 端口：%s\n' \
            "$label" "$NAME" "$DOMAIN" "$PORT"
    done
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

    if [ "$(journald_limit_state)" = "已配置" ] &&
        systemctl is-active --quiet systemd-journald 2>/dev/null; then
        info "systemd 日志限制已正确生效，无需重复写入或重启服务。"
        info "当前日志占用：$(journal_disk_usage)"
        info "总大小：500M"
        info "单文件：50M"
        return 0
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
    begin_change_transaction JOURNALD_CONF || { rm -rf "$backup_dir"; err "记录 journald 修改事务失败，已取消修改。"; return 1; }
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
        if restore_root_file_snapshot \
            "$backup_dir/99-vpsbox.conf" "$JOURNALD_VPSBOX_CONF" "$had_old" &&
            systemctl restart systemd-journald >/dev/null 2>&1; then
            rm -rf "$backup_dir"
            err "journald 配置未生效，已恢复修改前的配置与服务。"
        else
            err "journald 配置未生效，且未能完整恢复；恢复菜单中的原始基线仍保留。"
            warn "本次临时备份保留在：$backup_dir"
        fi
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
        if retry 3 2 journalctl --vacuum-size=500M; then
            info "清理完成，当前日志占用：$(journal_disk_usage)"
        else
            err "历史日志清理失败，日志大小限制仍已生效。"
            return 1
        fi
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
$(singbox_summary_line)
$(node_summary)
----------------------------------------
 IPv4 DNS：
$(ipv4_dns_lines)
----------------------------------------
 [1] 节点管理
 [2] sing-box 管理
 [3] 系统优化
 [4] 主机防火墙
 [5] 一键检测
 [6] 三网回程测试
 [7] 第三方脚本
----------------------------------------
 [00] 更新 vpsbox
 [88] 卸载 vpsbox
 [0] 退出
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
$(singbox_summary_line)
$(node_summary)
----------------------------------------
 [1] 创建/重建 VLESS Reality 节点（推荐）
 [2] 创建/重建 Shadowsocks 节点
 [3] 查看节点链接
 [4] 删除 VLESS Reality 节点
 [5] 删除 Shadowsocks 节点
----------------------------------------
 [0] 返回主菜单
========================================
EOF
        read -r -p "请输入选项: " opt || exit 0
        echo ""

        case "$opt" in
            1) run_menu_action create_vless_reality_node; pause ;;
            2) run_menu_action create_or_rebuild_node; pause ;;
            3) run_menu_action view_node_link; pause ;;
            4) run_menu_action delete_vless_reality_node; pause ;;
            5) run_menu_action delete_node; pause ;;
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
$(singbox_summary_line)
----------------------------------------
 [1] 启动服务
 [2] 停止服务
 [3] 重启服务
 [4] 更新 sing-box
----------------------------------------
 [0] 返回主菜单
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
    local opt ntp_label journal_label

    while true; do
        detect_os
        ntp_label="开启 NTP 时间同步"
        journal_label="限制 journald 日志大小"
        if [ "$OS" = "alpine" ]; then
            ntp_label+="（Alpine/OpenRC 不适用）"
            journal_label+="（Alpine/OpenRC 不适用）"
        fi
        clear 2>/dev/null || true
        cat <<EOF
========================================
 系统优化
========================================
 BBR + fq：$(bbr_fq_summary_state)
 IPv4 优先：$(ipv4_priority_state)
 SSH：端口 $(ssh_port_state) / 加固$(ssh_hardening_state)
 Fail2ban：$(fail2ban_service_state) / SSH 防护$(fail2ban_sshd_state)
 NTP：$(ntp_sync_state)
 系统重启：$(reboot_required_state)
----------------------------------------
 基础
 [1] 系统更新
 [2] 垃圾清理
 [3] 修改主机名
 [4] $ntp_label

 网络
 [5] 修改 IPv4 DNS
 [6] 开启 IPv4 优先
 [7] 开启 BBR + fq

 SSH 安全
 [8] 修改 SSH 端口
 [9] SSH 基础加固
 [10] 查看 SSH 生效配置
 [11] 安装 Fail2ban

 维护
 [12] $journal_label
 [13] 查看/恢复 vpsbox 系统改动
----------------------------------------
 [0] 返回主菜单
========================================
EOF
        read -r -p "请输入选项: " opt || exit 0
        echo ""

        case "$opt" in
            1) run_menu_action update_system_packages; pause ;;
            2) run_menu_action cleanup_system_garbage; pause ;;
            3) run_menu_action change_system_hostname; pause ;;
            4) run_menu_action enable_ntp_sync; pause ;;
            5) run_menu_action change_ipv4_dns; pause ;;
            6) run_menu_action enable_ipv4_priority; pause ;;
            7) run_menu_action enable_bbr_fq; pause ;;
            8) ssh_port_change_menu ;;
            9) ssh_basic_hardening_menu ;;
            10) run_menu_action show_current_ssh_config; pause ;;
            11) run_menu_action install_fail2ban; pause ;;
            12) run_menu_action limit_systemd_journal; pause ;;
            13) run_menu_action restore_vpsbox_system_changes; pause ;;
            0) return 0 ;;
            *) warn "无效选项：$opt"; pause ;;
        esac
    done
}

show_ip_quality_script_info() {
    clear 2>/dev/null || true
    cat <<'EOF'
========================================
 IP 质量体检脚本
========================================
 项目地址：
 https://github.com/xykt/ScriptMenu

 上游命令：
 bash <(curl -Ls https://Check.Place) -I

 说明：vpsbox 仅提供第三方脚本链接和命令提示，
 不会自动执行。
========================================
EOF
}

show_network_quality_script_info() {
    clear 2>/dev/null || true
    cat <<'EOF'
========================================
 网络质量体检脚本
========================================
 项目地址：
 https://github.com/xykt/ScriptMenu

 上游命令：
 bash <(curl -Ls https://Check.Place) -N

 说明：vpsbox 仅提供第三方脚本链接和命令提示，
 不会自动执行。
========================================
EOF
}

show_tcp_quality_script_info() {
    clear 2>/dev/null || true
    cat <<'EOF'
========================================
 TCP 质量检测脚本
========================================
 项目地址：
 https://github.com/ibsgss/TcpQuality

 上游命令：
 bash <(curl -fsSL https://raw.githubusercontent.com/ibsgss/TcpQuality/main/runTcpQuality.sh)

 说明：vpsbox 仅提供第三方脚本链接和命令提示，
 不会自动执行。
========================================
EOF
}

show_node_quality_script_info() {
    clear 2>/dev/null || true
    cat <<'EOF'
========================================
 VPS 综合质量测试脚本
========================================
 项目地址：
 https://github.com/LloydAsp/NodeQuality

 上游命令：
 bash <(curl -sL https://run.NodeQuality.com)

 说明：vpsbox 仅提供第三方脚本链接和命令提示，
 不会自动执行。
========================================
EOF
}

show_reinstall_script_info() {
    clear 2>/dev/null || true
    cat <<'EOF'
========================================
 一键 VPS 系统重装脚本
========================================
 项目地址：
 https://github.com/bin456789/reinstall

 上游命令（安装 Debian 13）：
 curl -fL https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh -o reinstall.sh && bash reinstall.sh debian 13

 警告：执行重装会清除整个系统盘的数据。
 vpsbox 仅提供第三方脚本链接和命令提示，
 不会自动执行。
========================================
EOF
}

other_scripts_menu() {
    local opt

    while true; do
        clear 2>/dev/null || true
        cat <<'EOF'
========================================
 第三方脚本
========================================
 [1] IP 质量体检脚本（xykt）
 [2] 网络质量体检脚本（xykt）
 [3] TCP 质量检测脚本（ibsgss）
 [4] VPS 综合质量测试脚本（LloydAsp）
 [5] 一键 VPS 系统重装脚本（bin456789）
----------------------------------------
 [0] 返回主菜单
========================================
EOF
        read -r -p "请输入选项: " opt || exit 0
        echo ""

        case "$opt" in
            1)
                show_ip_quality_script_info
                exit 0
                ;;
            2)
                show_network_quality_script_info
                exit 0
                ;;
            3)
                show_tcp_quality_script_info
                exit 0
                ;;
            4)
                show_node_quality_script_info
                exit 0
                ;;
            5)
                show_reinstall_script_info
                exit 0
                ;;
            0) return 0 ;;
            *) warn "无效选项：$opt"; pause ;;
        esac
    done
}

main_loop() {
    while true; do
        show_menu
        # 只有新版已完成初始化并成功渲染首个菜单，才确认本次自更新启动成功。
        # v1.0.21 及更早版本不会传递握手变量，因此普通启动不会误用陈旧 .previous。
        confirm_pending_vpsbox_update
        read -r -p "请输入选项: " opt || exit 0
        echo ""

        case "$opt" in
            1) run_menu_action node_menu ;;
            2) run_menu_action singbox_menu ;;
            3) run_menu_action system_menu ;;
            4) run_menu_action firewall_menu ;;
            5) run_menu_action run_self_check; pause ;;
            6) run_menu_action show_backtrace_routes; pause ;;
            7) run_menu_action other_scripts_menu ;;
            00) run_menu_action update_vpsbox; pause ;;
            88) uninstall_all; pause ;;
            0) exit 0 ;;
            *) warn "无效选项：$opt"; pause ;;
        esac
    done
}

vpsbox_main() {
    if [ -n "${PENDING_VPSBOX_UPDATE_BACKUP:-}${PENDING_VPSBOX_UPDATE_READY_FILE:-}" ]; then
        # 更新后的新进程可能在取得菜单锁前失败，必须提前安装 EXIT 回滚处理。
        trap cleanup_vpsbox_runtime EXIT
    fi
    need_root
    detect_os
    acquire_lock
    recover_pending_singbox_update || {
        err "sing-box 更新事务未能恢复，已停止启动 vpsbox，避免丢失旧二进制。"
        return 1
    }
    recover_pending_node_transaction || {
        err "节点事务未能恢复，已停止启动 vpsbox，避免覆盖现有节点。"
        return 1
    }
    install_self_command
    if [ -z "${PENDING_VPSBOX_UPDATE_BACKUP:-}${PENDING_VPSBOX_UPDATE_READY_FILE:-}" ]; then
        check_vpsbox_update_on_start
        auto_update_vpsbox_on_start
    fi
    main_loop
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    vpsbox_main "$@"
fi
