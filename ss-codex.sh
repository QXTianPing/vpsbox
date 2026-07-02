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

install_self_command() {
    local src
    src="${BASH_SOURCE[0]:-$0}"

    mkdir -p "$(dirname "$CMD_PATH")"

    case "$src" in
        /dev/fd/*|/proc/*)
            if command -v curl >/dev/null 2>&1; then
                curl -fsSL "$SCRIPT_URL" -o "$CMD_PATH" 2>/dev/null || {
                    warn "管理命令安装失败，可重新运行安装命令。"
                    return 0
                }
                install_command_alias
                return 0
            fi
            warn "未找到 curl，暂时无法安装 sscodex 管理命令。"
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

    echo "$host"
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

    read -r -p "请输入节点域名或 IP：" input_host
    domain="$(normalize_host "$input_host")"
    if [ -z "$domain" ]; then
        err "节点域名或 IP 不能为空。"
        return 1
    fi

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
    info "正在更新 sing-box..."
    bash <(curl -fsSL https://sing-box.app/install.sh)

    if node_exists; then
        setup_service
        service_restart
    fi

    info "更新完成：$(singbox_version)"
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

uninstall_all() {
    echo "此操作会卸载 sing-box，并删除所有节点配置。"
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
 当前节点：$(node_state)
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
10) 更新 sing-box
11) 卸载 sing-box，并删除所有节点配置
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
            10) update_singbox; pause ;;
            11) uninstall_all; pause ;;
            0) exit 0 ;;
            *) warn "无效选项：$opt"; pause ;;
        esac
    done
}

need_root
detect_os
install_self_command
main_loop
