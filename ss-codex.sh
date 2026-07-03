#!/usr/bin/env bash
set -euo pipefail

APP_NAME="SS Codex"
SCRIPT_URL="https://raw.githubusercontent.com/QXTianPing/ss-codex/main/ss-codex.sh"
CMD_PATH="/usr/local/bin/sscodex"
CONFIG_DIR="/etc/sing-box"
CONFIG_PATH="$CONFIG_DIR/config.json"
STATE_FILE="$CONFIG_DIR/ss-codex.env"
URI_FILE="$CONFIG_DIR/ss-codex-uri.txt"
BBR_CONF="/etc/sysctl.d/99-ss-codex-bbr.conf"
SERVICE_NAME="sing-box"
METHOD="2022-blake3-aes-128-gcm"
PORT_MIN=10000
PORT_MAX=60000

info() { echo -e "\033[1;34m[INFO]\033[0m $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $*"; }
err()  { echo -e "\033[1;31m[ERR]\033[0m $*" >&2; }

pause() {
    echo ""
    read -r -p "按回车返回主菜单..." _
}

need_root() {
    if [ "$(id -u)" != "0" ]; then
        err "请使用 root 用户运行。"
        exit 1
    fi
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
    ln -sf "$CMD_PATH" /usr/bin/sscodex 2>/dev/null || true
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

download_sscodex_script() {
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

    if ! curl -fsSL "$SCRIPT_URL" -o "$tmp"; then
        rm -f "$tmp"
        err "下载失败，请检查网络或 GitHub raw 地址。"
        return 1
    fi

    if ! bash -n "$tmp"; then
        rm -f "$tmp"
        err "下载到的脚本未通过语法检查，已保留当前版本。"
        return 1
    fi

    chmod 755 "$tmp" 2>/dev/null || true
    mv -f "$tmp" "$dest"
}

install_self_command() {
    local src
    src="${BASH_SOURCE[0]:-$0}"

    mkdir -p "$(dirname "$CMD_PATH")"

    case "$src" in
        /dev/fd/*|/proc/*)
            if download_sscodex_script "$CMD_PATH"; then
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
    mkdir -p "$CONFIG_DIR"
    chmod 700 "$CONFIG_DIR" 2>/dev/null || true
}

install_deps() {
    detect_os

    case "$OS" in
        alpine)
            apk update
            apk add --no-cache bash curl ca-certificates openssl jq iproute2 coreutils
            ;;
        debian)
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -y
            apt-get install -y curl ca-certificates openssl jq iproute2 coreutils
            ;;
        redhat)
            if command -v dnf >/dev/null 2>&1; then
                dnf install -y curl ca-certificates openssl jq iproute coreutils
            else
                yum install -y curl ca-certificates openssl jq iproute coreutils
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
    install_deps
    detect_os

    case "$OS" in
        alpine)
            apk add --repository=http://dl-cdn.alpinelinux.org/alpine/edge/community sing-box
            ;;
        *)
            ensure_curl || exit 1
            bash <(curl -fsSL https://sing-box.app/install.sh)
            ;;
    esac

    if ! singbox_installed; then
        err "sing-box 安装失败，请检查网络或手动安装。"
        exit 1
    fi

    info "sing-box 安装完成：$(singbox_version)"
}

service_start() {
    if is_systemd; then
        systemctl start "$SERVICE_NAME"
    elif [ "$OS" = "alpine" ] && command -v rc-service >/dev/null 2>&1; then
        rc-service "$SERVICE_NAME" start
    else
        err "未检测到 systemd/OpenRC，无法管理服务。"
        return 1
    fi
}

service_stop() {
    if is_systemd; then
        systemctl stop "$SERVICE_NAME"
    elif [ "$OS" = "alpine" ] && command -v rc-service >/dev/null 2>&1; then
        rc-service "$SERVICE_NAME" stop
    else
        err "未检测到 systemd/OpenRC，无法管理服务。"
        return 1
    fi
}

service_restart() {
    if is_systemd; then
        systemctl restart "$SERVICE_NAME"
    elif [ "$OS" = "alpine" ] && command -v rc-service >/dev/null 2>&1; then
        rc-service "$SERVICE_NAME" restart
    else
        err "未检测到 systemd/OpenRC，无法管理服务。"
        return 1
    fi
}

service_enable() {
    if is_systemd; then
        systemctl enable "$SERVICE_NAME" >/dev/null 2>&1 || true
    elif [ "$OS" = "alpine" ] && command -v rc-update >/dev/null 2>&1; then
        rc-update add "$SERVICE_NAME" default >/dev/null 2>&1 || true
    fi
}

service_disable() {
    if is_systemd; then
        systemctl disable "$SERVICE_NAME" >/dev/null 2>&1 || true
    elif [ "$OS" = "alpine" ] && command -v rc-update >/dev/null 2>&1; then
        rc-update del "$SERVICE_NAME" default >/dev/null 2>&1 || true
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
    local recvq
    local sendq
    local local_addr
    local peer_addr
    local proc_info
    local addr
    local port
    local proto_upper
    local proc_name

    public_file="$(mktemp)"
    local_file="$(mktemp)"
    suggest_file="$(mktemp)"

    while read -r proto state recvq sendq local_addr peer_addr proc_info; do
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
    [ -f "$STATE_FILE" ] && [ -f "$CONFIG_PATH" ]
}

load_state() {
    if [ -f "$STATE_FILE" ]; then
        # shellcheck disable=SC1090
        . "$STATE_FILE"
    fi
}

save_state() {
    local domain="$1"
    local name="$2"
    local port="$3"
    local password="$4"

    secure_config_dir
    {
        printf 'DOMAIN=%q\n' "$domain"
        printf 'NAME=%q\n' "$name"
        printf 'PORT=%q\n' "$port"
        printf 'PASSWORD=%q\n' "$password"
        printf 'METHOD=%q\n' "$METHOD"
    } > "$STATE_FILE"
    chmod 600 "$STATE_FILE" 2>/dev/null || true
}

normalize_host() {
    local host="$1"
    local no_colons
    local colon_count

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
    encoded="$(url_encode_userinfo "${METHOD:-$METHOD}:${PASSWORD:-}")"
    echo "ss://${encoded}@${host}:${PORT:-0}#${NAME:-ss}"
}

write_uri_file() {
    secure_config_dir
    generate_link > "$URI_FILE"
    chmod 600 "$URI_FILE" 2>/dev/null || true
}

port_in_use() {
    local port="$1"
    ss -tuln 2>/dev/null | awk '{print $5}' | grep -Eq "[:.]${port}$"
}

random_port() {
    local port
    local i
    for i in $(seq 1 100); do
        port="$(shuf -i "${PORT_MIN}-${PORT_MAX}" -n 1 2>/dev/null || echo $((RANDOM % (PORT_MAX - PORT_MIN + 1) + PORT_MIN)))"
        if ! port_in_use "$port"; then
            echo "$port"
            return 0
        fi
    done
    echo $((RANDOM % (PORT_MAX - PORT_MIN + 1) + PORT_MIN))
}

random_password() {
    if singbox_installed; then
        sing-box generate rand --base64 16 2>/dev/null | tr -d '\n\r' && return 0
    fi

    openssl rand -base64 16 2>/dev/null | tr -d '\n\r' && return 0
    head -c 16 /dev/urandom | base64 | tr -d '\n\r'
}

write_config() {
    local port="$1"
    local password="$2"

    secure_config_dir
    if [ -f "$CONFIG_PATH" ]; then
        cp "$CONFIG_PATH" "${CONFIG_PATH}.bak" 2>/dev/null || true
        chmod 600 "${CONFIG_PATH}.bak" 2>/dev/null || true
    fi

    cat > "$CONFIG_PATH" <<EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "shadowsocks",
      "tag": "ss-codex-in",
      "listen": "0.0.0.0",
      "listen_port": $port,
      "method": "$METHOD",
      "password": "$password"
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ]
}
EOF
    chmod 600 "$CONFIG_PATH" 2>/dev/null || true

    sing-box check -c "$CONFIG_PATH" >/dev/null
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
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        service_enable
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
        chmod +x /etc/init.d/sing-box
        service_enable
    else
        err "未检测到 systemd/OpenRC，无法创建服务。"
        exit 1
    fi
}

create_or_rebuild_node() {
    if node_exists; then
        warn "检测到已有节点。"
        read -r -p "是否覆盖重建？(y/N): " confirm
        [[ "$confirm" =~ ^[Yy]$ ]] || { info "已取消。"; return 0; }
    fi

    install_singbox_if_missing

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
        break
    done

    default_name="$(default_name_for_host "$domain")"
    read -r -p "请输入节点名称，留空默认 ${default_name}：" input_name
    name="$(sanitize_name "${input_name:-$default_name}")"

    info "正在自动选择端口..."
    port="$(random_port)"
    info "自动选择端口：$port"

    info "正在自动生成随机强密码..."
    password="$(random_password)"

    info "加密方式：$METHOD"
    info "正在写入配置..."
    write_config "$port" "$password"

    save_state "$domain" "$name" "$port" "$password"
    write_uri_file

    setup_service
    info "正在启动 sing-box 服务..."
    service_restart

    info "创建完成。可在主菜单选择 2 查看节点链接。"
}

view_node_link() {
    if ! node_exists; then
        warn "当前没有已创建的节点。"
        return 0
    fi

    load_state
    write_uri_file

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
    if ! node_exists; then
        warn "当前没有已创建的节点。"
        return 0
    fi

    read -r -p "确认删除当前 SS 节点？sing-box 服务将停止。(y/N): " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { info "已取消。"; return 0; }

    service_stop 2>/dev/null || true
    rm -f "$CONFIG_PATH" "$STATE_FILE" "$URI_FILE"
    info "当前节点已删除，sing-box 服务已停止。"
}

update_singbox() {
    install_deps
    ensure_curl || return 1
    info "正在更新 sing-box..."
    bash <(curl -fsSL https://sing-box.app/install.sh)

    if node_exists; then
        setup_service
        service_restart
    fi

    info "更新完成：$(singbox_version)"
}

update_sscodex() {
    info "正在下载最新 sscodex 脚本..."
    download_sscodex_script "$CMD_PATH" || return 1
    install_command_alias

    info "sscodex 已覆盖更新。"
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
    [ "$qdisc" = "fq" ] && echo "已启用" || echo "未启用"
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
    if ! fail2ban_installed; then
        echo "未启用"
        return
    fi

    if fail2ban-client status sshd >/dev/null 2>&1; then
        echo "已启用"
    else
        echo "未启用"
    fi
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

ipv4_dns_lines() {
    if print_ipv4_dns_from_resolvectl; then
        return 0
    fi

    if print_ipv4_dns_from_resolv_conf; then
        return 0
    fi

    echo " 未检测到 IPv4 DNS"
}

enable_bbr_fq() {
    cat > "$BBR_CONF" <<EOF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
    sysctl --system
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
            if ! apt update || ! apt install -y fail2ban || ! systemctl enable --now fail2ban; then
                warn "Fail2ban 安装或启动未完全成功，将尝试写入最小 SSH 配置后重启。"
            fi
            ;;
        alpine)
            if ! apk update || ! apk add --no-cache fail2ban; then
                err "Fail2ban 安装失败。"
                return 1
            fi
            if command -v rc-update >/dev/null 2>&1; then
                rc-update add fail2ban default >/dev/null 2>&1 || true
            fi
            if command -v rc-service >/dev/null 2>&1; then
                rc-service fail2ban start || true
            fi
            ;;
        redhat)
            if command -v dnf >/dev/null 2>&1; then
                dnf install -y fail2ban || { err "Fail2ban 安装失败。"; return 1; }
            else
                yum install -y fail2ban || { err "Fail2ban 安装失败。"; return 1; }
            fi
            if is_systemd; then
                systemctl enable --now fail2ban || true
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

    info "等待 Fail2ban 服务启动 3 秒..."
    sleep 3

    if [ "$(fail2ban_service_state)" = "运行中" ] && [ "$(fail2ban_sshd_state)" = "已启用" ]; then
        info "Fail2ban 已安装，SSH 防护已启用。"
        return 0
    fi

    warn "Fail2ban 已安装，但 SSH 防护未正常启用，正在写入最小 SSH 配置..."
    mkdir -p /etc/fail2ban/jail.d
    cat > /etc/fail2ban/jail.d/sshd.local <<'EOF'
[sshd]
enabled = true
port = 22
backend = systemd
EOF

    if is_systemd; then
        systemctl restart fail2ban || { err "Fail2ban 重启失败，请执行 journalctl -u fail2ban -n 50 --no-pager 查看原因。"; return 1; }
    elif [ "$OS" = "alpine" ] && command -v rc-service >/dev/null 2>&1; then
        rc-service fail2ban restart || { err "Fail2ban 重启失败。"; return 1; }
    fi

    info "等待 Fail2ban 服务重启 3 秒..."
    sleep 3

    info "Fail2ban 状态：$(fail2ban_service_state)"
    info "SSH 防护：$(fail2ban_sshd_state)"
}

uninstall_all() {
    echo "此操作会卸载 SS Codex、sing-box，并删除所有节点配置。"
    read -r -p "确认继续？请输入 YES：" confirm
    [ "$confirm" = "YES" ] || { info "已取消。"; return 0; }

    info "正在停止并禁用服务..."
    service_stop 2>/dev/null || true
    service_disable 2>/dev/null || true

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

    info "正在清理文件..."
    rm -rf "$CONFIG_DIR"
    rm -f /usr/bin/sing-box /usr/local/bin/sing-box
    rm -f "$CMD_PATH" /usr/bin/sscodex
    rm -f /usr/local/bin/sb /usr/bin/sb
    rm -f /var/log/sing-box*

    info "卸载完成。"
    info "sscodex 命令已删除，当前菜单即将退出。"
    exit 0
}

start_service_action() {
    if ! node_exists; then
        warn "当前没有节点配置，请先创建节点。"
        return 0
    fi
    install_singbox_if_missing
    setup_service
    service_start
    info "sing-box 服务已启动。"
}

restart_service_action() {
    if ! node_exists; then
        warn "当前没有节点配置，请先创建节点。"
        return 0
    fi
    install_singbox_if_missing
    setup_service
    service_restart
    info "sing-box 服务已重启。"
}

singbox_install_state() {
    singbox_installed && echo "已安装" || echo "未安装"
}

node_state() {
    node_exists && echo "已创建" || echo "未创建"
}

show_menu() {
    clear 2>/dev/null || true
    cat <<EOF
========================================
 SS Codex 一键节点管理
========================================
 提示：输入 sscodex 打开管理面板
----------------------------------------
 sing-box：$(singbox_install_state)
 状态：$(service_status_short)
 版本：$(singbox_version)
 BBR：$(bbr_state)
 fq：$(fq_state)
 Fail2ban：$(fail2ban_install_state)
 Fail2ban 状态：$(fail2ban_service_state)
 SSH 防护：$(fail2ban_sshd_state)
 当前节点：$(node_state)
 IPv4 DNS：
$(ipv4_dns_lines)
----------------------------------------
 1) 创建/重建 SS 2022 节点
 2) 查看节点链接
 3) 删除当前节点
----------------------------------------
 4) 启动 sing-box 服务
 5) 停止 sing-box 服务
 6) 重启 sing-box 服务
 7) 查看 sing-box 状态
 8) 查看 sing-box 日志
----------------------------------------
 9) 一键开启 BBR + fq
10) 安装 Fail2ban
11) 更新 sing-box
12) 更新 sscodex 脚本
13) 卸载 SS Codex
14) 查看端口与安全组建议
 0) 退出
========================================
EOF
}

main_loop() {
    while true; do
        show_menu
        read -r -p "请输入选项: " opt
        echo ""

        case "$opt" in
            1) create_or_rebuild_node; pause ;;
            2) view_node_link; pause ;;
            3) delete_node; pause ;;
            4) start_service_action; pause ;;
            5) service_stop && info "sing-box 服务已停止。"; pause ;;
            6) restart_service_action; pause ;;
            7) show_service_status; pause ;;
            8) show_logs ;;
            9) enable_bbr_fq; pause ;;
            10) install_fail2ban; pause ;;
            11) update_singbox; pause ;;
            12) update_sscodex; pause ;;
            13) uninstall_all; pause ;;
            14) show_ports_security_group; pause ;;
            0) exit 0 ;;
            *) warn "无效选项：$opt"; pause ;;
        esac
    done
}

need_root
detect_os
install_self_command
main_loop
