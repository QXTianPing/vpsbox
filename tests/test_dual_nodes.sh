#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=tests/test_helper.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/test_helper.sh"

# shellcheck source=../vpsbox.sh
source "$REPO_DIR/vpsbox.sh"

# 双节点夹具只验证配置与事务，不访问软件源安装宿主机依赖。
node_dependencies_available() { return 0; }
missing_node_commands() { printf '\n'; }

mkdir -p "$TEST_TMP/bin"
cat > "$TEST_TMP/bin/sing-box" <<'EOF'
#!/bin/sh
case "${1:-}" in
    version) printf 'sing-box version 1.13.14\n' ;;
    check) exit 0 ;;
    *) exit 0 ;;
esac
EOF
chmod 755 "$TEST_TMP/bin/sing-box"
PATH="$TEST_TMP/bin:$PATH"
export PATH

# Windows 挂载上的 WSL 测试目录不允许普通测试用户 chown root；节点权限本身由既有回归覆盖。
chown() { return 0; }
node_file_is_secure() {
    [ -f "$1" ] && [ ! -L "$1" ]
}
node_dir_is_secure() {
    [ -d "$1" ] && [ ! -L "$1" ]
}
# Git for Windows 不附带 jq；该环境只用精确字段回退继续跑交互/事务测试。
# Debian 验收存在 jq 时会直接执行生产实现和完整 JSON 语义校验。
if ! command -v jq >/dev/null 2>&1; then
    node_config_matches_loaded_state() {
        local protocol="$1" config="$2"

        case "$protocol" in
            ss)
                grep -Fq '"type": "shadowsocks"' "$config" &&
                    grep -Fq "\"listen_port\": $PORT" "$config" &&
                    grep -Fq "\"method\": \"$METHOD\"" "$config" &&
                    grep -Fq "\"password\": \"$PASSWORD\"" "$config" || return 1
                ;;
            vless)
                grep -Fq '"type": "vless"' "$config" &&
                    grep -Fq "\"listen_port\": $PORT" "$config" &&
                    grep -Fq "\"uuid\": \"$UUID\"" "$config" &&
                    grep -Fq "\"flow\": \"$FLOW\"" "$config" &&
                    grep -Fq "\"server_name\": \"$REALITY_SERVER_NAME\"" "$config" &&
                    grep -Fq "\"private_key\": \"$REALITY_PRIVATE_KEY\"" "$config" &&
                    grep -Fq "\"$REALITY_SHORT_ID\"" "$config" || return 1
                ;;
            *) return 2 ;;
        esac
        grep -Fq "$CONFIG_ID" "$config"
    }
fi

cleanup() {
    rm -rf -- "$TEST_TMP"
}
trap cleanup EXIT

set_node_paths() {
    CONFIG_DIR="$1"
    URI_FILE="$CONFIG_DIR/vpsbox-uri.txt"
    NODE_CONFIG_DIR="$CONFIG_DIR/vpsbox.d"
    SS_CONFIG_PATH="$NODE_CONFIG_DIR/10-ss.json"
    VLESS_CONFIG_PATH="$NODE_CONFIG_DIR/20-vless-reality.json"
    SS_STATE_FILE="$CONFIG_DIR/vpsbox-ss.env"
    VLESS_STATE_FILE="$CONFIG_DIR/vpsbox-vless.env"
    SS_URI_FILE="$CONFIG_DIR/vpsbox-ss-uri.txt"
    VLESS_URI_FILE="$CONFIG_DIR/vpsbox-vless-uri.txt"
    VPSBOX_STATE_DIR="$CONFIG_DIR/vpsbox-state"
    NODE_TRANSACTION_DIR="$VPSBOX_STATE_DIR/node-transaction"
    NODE_TRANSACTION_BACKUP="$NODE_TRANSACTION_DIR/backup"
    # shellcheck disable=SC2034 # 被被测的节点事务函数动态读取。
    NODE_TRANSACTION_STAGE="$NODE_TRANSACTION_DIR/stage"
    ACTIVE_NODE_BACKUP=""
}

write_ss_state_fixture() {
    local file="$1" port="${2:-20001}" config_id="${3:-111111111111111111111111}"
    cat > "$file" <<EOF
PROTOCOL=shadowsocks
CONFIG_ID=$config_id
DOMAIN=ss.example.com
NAME=ss-node
PORT=$port
PASSWORD=QUFBQUFBQUFBQUFBQUFBQQ==
METHOD=$SS_METHOD
EOF
    chmod 600 "$file"
}

write_vless_state_fixture() {
    local file="$1" port="${2:-20002}" config_id="${3:-222222222222222222222222}"
    cat > "$file" <<EOF
PROTOCOL=vless-reality
CONFIG_ID=$config_id
DOMAIN=vless.example.com
NAME=vless-node
PORT=$port
UUID=11111111-2222-4333-8444-555555555555
FLOW=xtls-rprx-vision
REALITY_SERVER_NAME=addons.mozilla.org
REALITY_PRIVATE_KEY=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
REALITY_PUBLIC_KEY=BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB
REALITY_SHORT_ID=0123456789abcdef
FINGERPRINT=chrome
EOF
    chmod 600 "$file"
}

write_ss_config_fixture() {
    local file="$1" port="${2:-20001}" config_id="${3:-111111111111111111111111}"
    cat > "$file" <<EOF
{
  "inbounds": [{
    "type": "shadowsocks",
    "tag": "vpsbox-${config_id}-ss-in",
    "listen": "0.0.0.0",
    "listen_port": $port,
    "method": "$SS_METHOD",
    "password": "QUFBQUFBQUFBQUFBQUFBQQ=="
  }],
  "outbounds": [{"type": "direct", "tag": "direct-${config_id}-ss"}]
}
EOF
    chmod 600 "$file"
}

write_vless_config_fixture() {
    local file="$1" port="${2:-20002}" config_id="${3:-222222222222222222222222}"
    cat > "$file" <<EOF
{
  "inbounds": [{
    "type": "vless",
    "tag": "vpsbox-${config_id}-vless-reality-in",
    "listen": "0.0.0.0",
    "listen_port": $port,
    "users": [{
      "name": "vpsbox",
      "uuid": "11111111-2222-4333-8444-555555555555",
      "flow": "xtls-rprx-vision"
    }],
    "tls": {
      "enabled": true,
      "server_name": "addons.mozilla.org",
      "reality": {
        "enabled": true,
        "handshake": {"server": "addons.mozilla.org", "server_port": 443},
        "private_key": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "short_id": ["0123456789abcdef"]
      }
    }
  }],
  "outbounds": [{"type": "direct", "tag": "direct-${config_id}-vless"}]
}
EOF
    chmod 600 "$file"
}

test_complete_configs_merge_with_unique_tags() {
    (
        local vless_before
        set_node_paths "$TEST_TMP/config-pair"
        listen_mode() { printf '%s\n' ipv4; }
        sing-box() {
            [ "${1:-}" = check ] || return 1
            return 0
        }

        write_vless_reality_config \
            20002 11111111-2222-4333-8444-555555555555 addons.mozilla.org \
            AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA 0123456789abcdef \
            222222222222222222222222
        write_vless_state_fixture "$VLESS_STATE_FILE"
        vless_before="$(cat "$VLESS_CONFIG_PATH")"
        write_config 20001 QUFBQUFBQUFBQUFBQUFBQQ== 111111111111111111111111
        write_ss_state_fixture "$SS_STATE_FILE"
        check_node_config_set

        assert_file_contains "$SS_CONFIG_PATH" '"type": "shadowsocks"'
        assert_file_contains "$SS_CONFIG_PATH" '"tag": "direct-111111111111111111111111-ss"'
        assert_file_contains "$VLESS_CONFIG_PATH" '"type": "vless"'
        assert_file_contains "$VLESS_CONFIG_PATH" '"tag": "direct-222222222222222222222222-vless"'
        assert_file_not_contains "$SS_CONFIG_PATH" '"tag": "direct"'
        assert_file_not_contains "$VLESS_CONFIG_PATH" '"tag": "direct"'
        assert_eq "$vless_before" "$(cat "$VLESS_CONFIG_PATH")" \
            "创建 Shadowsocks 时不得改写既有 VLESS Reality 完整配置"
    )
}

test_create_shadowsocks_preserves_vless_node() {
    (
        local vless_config_before vless_state_before
        set_node_paths "$TEST_TMP/create-shadowsocks"
        mkdir -p "$NODE_CONFIG_DIR"
        write_vless_config_fixture "$VLESS_CONFIG_PATH"
        write_vless_state_fixture "$VLESS_STATE_FILE" 20002
        write_uri_files
        vless_config_before="$(cat "$VLESS_CONFIG_PATH")"
        vless_state_before="$(cat "$VLESS_STATE_FILE")"

        service_is_running() { return 1; }
        service_is_enabled() { return 1; }
        install_singbox_if_missing() { return 0; }
        prompt_node_host() { printf -v "$1" '%s' ss.example.com; }
        choose_node_port() { printf '%s\n' 20001; }
        confirm_default_yes() { return 0; }
        random_password() { printf '%s\n' QUFBQUFBQUFBQUFBQUFBQQ==; }
        listen_mode() { printf '%s\n' ipv4; }
        sing-box() {
            case "${1:-} ${2:-} ${3:-} ${4:-}" in
                "generate rand 12 --hex") printf '%s\n' 111111111111111111111111 ;;
                "check "*) return 0 ;;
                *) return 1 ;;
            esac
        }
        firewall_prepare_port_transition() { return 0; }
        setup_service() { return 0; }
        restart_singbox_cleanly() { return 0; }
        verify_all_node_runtime() { return 0; }
        firewall_complete_port_transition() { return 0; }
        view_node_link() { return 0; }

        create_or_rebuild_node <<< $'\n' >/dev/null

        protocol_node_exists ss ||
            fail "创建后的 Shadowsocks 节点应可独立读取"
        assert_eq "$vless_config_before" "$(cat "$VLESS_CONFIG_PATH")" \
            "创建 Shadowsocks 时不得改写 VLESS Reality 配置"
        assert_eq "$vless_state_before" "$(cat "$VLESS_STATE_FILE")" \
            "创建 Shadowsocks 时不得改写 VLESS Reality 状态"
    )
}

test_create_vless_preserves_shadowsocks_node() {
    (
        local ss_config_before ss_state_before
        set_node_paths "$TEST_TMP/create-vless"
        mkdir -p "$NODE_CONFIG_DIR"
        write_ss_config_fixture "$SS_CONFIG_PATH"
        write_ss_state_fixture "$SS_STATE_FILE" 20001
        write_uri_files
        ss_config_before="$(cat "$SS_CONFIG_PATH")"
        ss_state_before="$(cat "$SS_STATE_FILE")"

        service_is_running() { return 1; }
        service_is_enabled() { return 1; }
        install_singbox_if_missing() { return 0; }
        prompt_node_host() { printf -v "$1" '%s' vless.example.com; }
        check_reality_server() { return 0; }
        choose_node_port() { printf '%s\n' 20002; }
        confirm_default_yes() { return 0; }
        listen_mode() { printf '%s\n' ipv4; }
        sing-box() {
            case "${1:-} ${2:-} ${3:-} ${4:-}" in
                "generate uuid  ") printf '%s\n' 11111111-2222-4333-8444-555555555555 ;;
                "generate rand 8 --hex") printf '%s\n' 0123456789abcdef ;;
                "generate rand 12 --hex") printf '%s\n' 222222222222222222222222 ;;
                "check "*) return 0 ;;
                *) return 1 ;;
            esac
        }
        generate_reality_keypair() {
            printf '%s\n%s\n' \
                AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA \
                BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB
        }
        firewall_prepare_port_transition() { return 0; }
        setup_service() { return 0; }
        restart_singbox_cleanly() { return 0; }
        verify_all_node_runtime() { return 0; }
        firewall_complete_port_transition() { return 0; }
        view_node_link() { return 0; }

        create_vless_reality_node <<< $'\n\n' >/dev/null

        protocol_node_exists vless ||
            fail "创建后的 VLESS Reality 节点应可独立读取"
        assert_eq "$ss_config_before" "$(cat "$SS_CONFIG_PATH")" \
            "创建 VLESS Reality 时不得改写 Shadowsocks 配置"
        assert_eq "$ss_state_before" "$(cat "$SS_STATE_FILE")" \
            "创建 VLESS Reality 时不得改写 Shadowsocks 状态"
    )
}

test_independent_states_and_links_are_aggregated() {
    (
        set_node_paths "$TEST_TMP/state-links"
        mkdir -p "$NODE_CONFIG_DIR"
        write_ss_config_fixture "$SS_CONFIG_PATH"
        write_vless_config_fixture "$VLESS_CONFIG_PATH"
        write_ss_state_fixture "$SS_STATE_FILE"
        write_vless_state_fixture "$VLESS_STATE_FILE"

        write_uri_files

        assert_file_contains "$SS_URI_FILE" '^ss://'
        assert_file_contains "$VLESS_URI_FILE" '^vless://'
        [ "$(wc -l < "$URI_FILE")" -eq 2 ] || fail "汇总链接文件应包含两个节点"
        [ "$(sed -n '1p' "$URI_FILE")" = "$(cat "$SS_URI_FILE")" ] ||
            fail "汇总链接第一行应为 Shadowsocks"
        [ "$(sed -n '2p' "$URI_FILE")" = "$(cat "$VLESS_URI_FILE")" ] ||
            fail "汇总链接第二行应为 VLESS Reality"
    )
}

test_service_definition_uses_independent_config_directory() {
    (
        set_node_paths "$TEST_TMP/service-mode"
        mkdir -p "$NODE_CONFIG_DIR"
        write_ss_config_fixture "$SS_CONFIG_PATH"
        write_ss_state_fixture "$SS_STATE_FILE"
        write_uri_files
        render_singbox_systemd_service /usr/bin/sing-box > "$TEST_TMP/sing-box.service"
        assert_file_contains "$TEST_TMP/sing-box.service" "ExecStart=/usr/bin/sing-box run -C $NODE_CONFIG_DIR"
        assert_file_not_contains "$TEST_TMP/sing-box.service" ' run -c '
    )
}

test_orphan_protocol_uri_is_rejected() {
    (
        set_node_paths "$TEST_TMP/orphan-uri"
        mkdir -p "$NODE_CONFIG_DIR"
        printf 'stale\n' > "$SS_URI_FILE"

        if require_valid_node_state_if_present > "$TEST_TMP/orphan-uri.out" 2>&1; then
            fail "没有 Shadowsocks 配置和状态时不得接受孤立链接文件"
        fi
        assert_file_contains "$TEST_TMP/orphan-uri.out" '孤立链接文件'
    )
}

test_stopped_sibling_port_is_rejected() {
    (
        local output="$TEST_TMP/sibling-port.out"
        docker_reserved_ports_for_port_choice() { printf '\n'; }
        ssh_effective_ports_csv() { printf '%s\n' 22; }
        port_is_effective_ssh_port() { return 1; }
        port_in_use_for_protocols() { return 1; }

        choose_node_port "" tcp "" 20001 <<< $'20001\n20002' > "$output"
        assert_file_contains "$output" '^20002$'
    ) 2> "$TEST_TMP/sibling-port.err"
    assert_file_contains "$TEST_TMP/sibling-port.err" '端口 20001 已被另一个节点使用'
}

test_stopped_target_port_is_rechecked_against_system_listeners() {
    (
        local output="$TEST_TMP/stopped-target-port.out"
        docker_reserved_ports_for_port_choice() { printf '\n'; }
        ssh_effective_ports_csv() { printf '%s\n' 22; }
        port_is_effective_ssh_port() { return 1; }
        singbox_config_pids() { return 0; }
        port_in_use_for_protocols() { [ "$1" = 20001 ]; }

        choose_node_port 20001 tcp tcp "" <<< $'20001\n20002' > "$output"
        assert_file_contains "$output" '^20002$'
    ) 2> "$TEST_TMP/stopped-target-port.err"
    assert_file_contains "$TEST_TMP/stopped-target-port.err" '端口 20001 已被占用'
}

test_delete_one_protocol_keeps_sibling_running() {
    (
        local event_log="$TEST_TMP/delete-events"
        set_node_paths "$TEST_TMP/delete-one"
        mkdir -p "$NODE_CONFIG_DIR"
        write_ss_config_fixture "$SS_CONFIG_PATH"
        write_vless_config_fixture "$VLESS_CONFIG_PATH"
        write_ss_state_fixture "$SS_STATE_FILE"
        write_vless_state_fixture "$VLESS_STATE_FILE"
        # shellcheck disable=SC2218 # 先调用生产实现生成基线，随后才覆盖为事件记录 mock。
        write_uri_files
        : > "$event_log"

        begin_node_transaction() { printf 'transaction\n' >> "$event_log"; }
        mark_node_transaction_mutated() { printf 'mutated\n' >> "$event_log"; }
        commit_node_transaction() { printf 'commit\n' >> "$event_log"; }
        rollback_active_node_transaction() { printf 'rollback\n' >> "$event_log"; }
        firewall_prepare_port_transition() { printf 'prepare\n' >> "$event_log"; }
        service_stop() { printf 'stop\n' >> "$event_log"; }
        stop_singbox_config_processes() { return 0; }
        service_manager_is_active() { return 1; }
        singbox_config_pids() { return 0; }
        port_in_use_for_protocols() { return 1; }
        write_uri_files() { printf 'links\n' >> "$event_log"; }
        check_node_config_set() { return 0; }
        setup_service() { printf 'setup\n' >> "$event_log"; }
        restart_singbox_cleanly() { printf 'restart\n' >> "$event_log"; }
        verify_all_node_runtime() { printf 'verify\n' >> "$event_log"; }
        firewall_complete_port_transition() { printf 'complete\n' >> "$event_log"; }

        delete_vless_reality_node <<< y >/dev/null

        [ ! -e "$VLESS_CONFIG_PATH" ] && [ ! -e "$VLESS_STATE_FILE" ] ||
            fail "目标 VLESS 文件应被删除"
        [ -e "$SS_CONFIG_PATH" ] && [ -e "$SS_STATE_FILE" ] ||
            fail "Shadowsocks 兄弟节点文件必须保留"
        assert_file_contains "$event_log" '^restart$'
        assert_file_contains "$event_log" '^verify$'
        assert_file_contains "$event_log" '^complete$'
    )
}

test_delete_last_protocol_disables_service() {
    (
        local event_log="$TEST_TMP/delete-last-events"
        set_node_paths "$TEST_TMP/delete-last"
        mkdir -p "$NODE_CONFIG_DIR"
        write_vless_config_fixture "$VLESS_CONFIG_PATH"
        write_vless_state_fixture "$VLESS_STATE_FILE"
        write_uri_files
        : > "$event_log"

        begin_node_transaction() { printf 'transaction\n' >> "$event_log"; }
        mark_node_transaction_mutated() { printf 'mutated\n' >> "$event_log"; }
        commit_node_transaction() { printf 'commit\n' >> "$event_log"; }
        rollback_active_node_transaction() { printf 'rollback\n' >> "$event_log"; }
        firewall_prepare_port_transition() { printf 'prepare\n' >> "$event_log"; }
        service_stop() { printf 'stop\n' >> "$event_log"; }
        stop_singbox_config_processes() { return 0; }
        service_manager_is_active() { return 1; }
        singbox_config_pids() { return 0; }
        port_in_use_for_protocols() { return 1; }
        service_disable() { printf 'disable\n' >> "$event_log"; }
        service_is_enabled() { return 1; }
        firewall_complete_port_transition() { printf 'complete\n' >> "$event_log"; }

        delete_vless_reality_node <<< y >/dev/null

        [ ! -e "$VLESS_CONFIG_PATH" ] && [ ! -e "$VLESS_STATE_FILE" ] ||
            fail "最后一个节点的文件应被删除"
        assert_file_contains "$event_log" '^disable$'
        assert_file_contains "$event_log" '^complete$'
        assert_file_not_contains "$event_log" '^(setup|restart)$'
    )
}

test_delete_residual_node_without_singbox_keeps_sibling_static() {
    (
        local event_log="$TEST_TMP/delete-without-singbox.events"
        local output="$TEST_TMP/delete-without-singbox.out"
        set_node_paths "$TEST_TMP/delete-without-singbox"
        mkdir -p "$NODE_CONFIG_DIR"
        write_ss_config_fixture "$SS_CONFIG_PATH"
        write_vless_config_fixture "$VLESS_CONFIG_PATH"
        write_ss_state_fixture "$SS_STATE_FILE"
        write_vless_state_fixture "$VLESS_STATE_FILE"
        write_uri_files
        : > "$event_log"

        command() {
            if [ "${1:-}" = -v ]; then
                case "${2:-}" in sing-box|ss) return 1 ;; esac
            fi
            builtin command "$@"
        }
        missing_node_commands() {
            local command_name
            for command_name in "$@"; do
                [ "$command_name" != ss ] || { printf 'ss\n'; return 0; }
            done
            printf '\n'
        }
        # shellcheck disable=SC2120 # 调用来自运行时 source 的生产函数。
        begin_node_transaction() { printf 'transaction:%s\n' "$1" >> "$event_log"; }
        mark_node_transaction_mutated() { printf '%s\n' mutated >> "$event_log"; }
        commit_node_transaction() { printf '%s\n' commit >> "$event_log"; }
        rollback_active_node_transaction() { printf '%s\n' rollback >> "$event_log"; }
        firewall_prepare_port_transition() { printf '%s\n' prepare >> "$event_log"; }
        firewall_complete_port_transition() { printf '%s\n' complete >> "$event_log"; }
        service_manager_is_active() { return 1; }
        singbox_config_pids() { return 0; }
        service_stop() { printf '%s\n' unexpected:service-stop >> "$event_log"; return 1; }
        stop_singbox_config_processes() { printf '%s\n' unexpected:process-stop >> "$event_log"; return 1; }
        port_in_use_for_protocols() { printf '%s\n' unexpected:port-check >> "$event_log"; return 1; }
        setup_service() { printf '%s\n' unexpected:setup >> "$event_log"; return 1; }
        restart_singbox_cleanly() { printf '%s\n' unexpected:restart >> "$event_log"; return 1; }
        verify_all_node_runtime() { printf '%s\n' unexpected:verify >> "$event_log"; return 1; }

        delete_vless_reality_node <<< y > "$output"

        [ ! -e "$VLESS_CONFIG_PATH" ] && [ ! -e "$VLESS_STATE_FILE" ] ||
            fail "sing-box 缺失时应能删除目标残留节点"
        [ -e "$SS_CONFIG_PATH" ] && [ -e "$SS_STATE_FILE" ] ||
            fail "sing-box 缺失时必须保留兄弟节点配置"
        assert_file_contains "$event_log" '^transaction:static$'
        assert_file_contains "$event_log" '^complete$'
        assert_file_not_contains "$event_log" '^(unexpected:|rollback$)'
        assert_file_contains "$output" '其他节点配置已保留，但 sing-box 未安装，当前不会运行'
    )
}

test_delete_last_residual_node_without_singbox_skips_missing_service() {
    (
        local event_log="$TEST_TMP/delete-last-without-singbox.events"
        local output="$TEST_TMP/delete-last-without-singbox.out"
        set_node_paths "$TEST_TMP/delete-last-without-singbox"
        mkdir -p "$NODE_CONFIG_DIR"
        write_vless_config_fixture "$VLESS_CONFIG_PATH"
        write_vless_state_fixture "$VLESS_STATE_FILE"
        write_uri_files
        : > "$event_log"

        command() {
            if [ "${1:-}" = -v ]; then
                case "${2:-}" in sing-box|ss) return 1 ;; esac
            fi
            builtin command "$@"
        }
        # shellcheck disable=SC2120 # 调用来自运行时 source 的生产函数。
        begin_node_transaction() { printf 'transaction:%s\n' "$1" >> "$event_log"; }
        mark_node_transaction_mutated() { printf '%s\n' mutated >> "$event_log"; }
        commit_node_transaction() { printf '%s\n' commit >> "$event_log"; }
        rollback_active_node_transaction() { printf '%s\n' rollback >> "$event_log"; }
        firewall_prepare_port_transition() { printf '%s\n' prepare >> "$event_log"; }
        firewall_complete_port_transition() { printf '%s\n' complete >> "$event_log"; }
        service_manager_is_active() { return 1; }
        service_is_enabled() { return 1; }
        singbox_config_pids() { return 0; }
        port_in_use_for_protocols() { printf '%s\n' unexpected:port-check >> "$event_log"; return 1; }
        service_stop() { printf '%s\n' unexpected:service-stop >> "$event_log"; return 1; }
        service_disable() { printf '%s\n' unexpected:disable >> "$event_log"; return 1; }
        stop_singbox_config_processes() { printf '%s\n' unexpected:process-stop >> "$event_log"; return 1; }

        delete_vless_reality_node <<< y > "$output"

        [ ! -e "$VLESS_CONFIG_PATH" ] && [ ! -e "$VLESS_STATE_FILE" ] ||
            fail "sing-box 缺失时应能删除最后一个残留节点"
        assert_file_contains "$event_log" '^transaction:static$'
        assert_file_contains "$event_log" '^complete$'
        assert_file_not_contains "$event_log" '^(unexpected:|rollback$)'
        assert_file_contains "$output" 'sing-box 未安装，无需停止服务'
    )
}

test_static_node_backup_validation_does_not_execute_singbox() {
    (
        local backup="$TEST_TMP/static-backup-validation/backup"
        set_node_paths "$TEST_TMP/static-backup-validation/node"
        mkdir -p "$NODE_CONFIG_DIR"
        write_ss_config_fixture "$SS_CONFIG_PATH"
        write_ss_state_fixture "$SS_STATE_FILE"
        write_uri_files
        service_is_running() { return 1; }
        service_is_enabled() { return 1; }
        sing-box() { fail "静态事务备份校验不得执行 sing-box"; }

        backup_node_files "$backup"
        validate_node_transaction_backup "$backup" ||
            fail "没有 sing-box 时，哈希及配置状态一致的备份应通过静态校验"
        printf '%s\n' tampered >> "$backup/ss-state.env"
        if validate_node_transaction_backup "$backup"; then
            fail "静态校验仍必须拒绝哈希被篡改的备份"
        fi
    )
}

test_node_transaction_full_and_static_validation_modes() {
    (
        set_node_paths "$TEST_TMP/transaction-validation-modes"
        mkdir -p "$NODE_CONFIG_DIR"
        write_ss_config_fixture "$SS_CONFIG_PATH"
        write_ss_state_fixture "$SS_STATE_FILE"
        write_uri_files
        service_is_running() { return 1; }
        service_is_enabled() { return 1; }
        sing-box() {
            [ "${1:-}" != check ] || return 1
        }

        begin_node_transaction static ||
            fail "静态事务校验不应依赖 sing-box check"
        [ -f "$NODE_TRANSACTION_DIR/pending" ] ||
            fail "静态事务校验成功后应建立 pending 标记"
        cancel_unmodified_node_transaction ||
            fail "静态事务测试完成后应能清理未修改事务"

        if begin_node_transaction full > "$TEST_TMP/full-transaction-check.out" 2>&1; then
            fail "完整事务校验必须拒绝 sing-box check 失败的备份"
        fi
        [ ! -e "$NODE_TRANSACTION_DIR" ] ||
            fail "完整事务校验失败后不得保留未生效事务目录"
        assert_file_contains "$TEST_TMP/full-transaction-check.out" '未通过 sing-box 配置检查'
    )
}

test_dual_node_backup_restore_round_trip() {
    (
        local backup="$TEST_TMP/dual-backup"
        set_node_paths "$TEST_TMP/backup-round-trip"
        mkdir -p "$NODE_CONFIG_DIR"
        write_ss_config_fixture "$SS_CONFIG_PATH"
        write_vless_config_fixture "$VLESS_CONFIG_PATH"
        write_ss_state_fixture "$SS_STATE_FILE"
        write_vless_state_fixture "$VLESS_STATE_FILE"
        write_uri_files

        service_is_running() { return 1; }
        service_is_enabled() { return 1; }
        backup_node_files "$backup"

        printf 'broken\n' > "$SS_CONFIG_PATH"
        rm -f "$VLESS_CONFIG_PATH" "$SS_STATE_FILE" "$VLESS_STATE_FILE" \
            "$SS_URI_FILE" "$VLESS_URI_FILE" "$URI_FILE"

        service_stop() { return 0; }
        stop_singbox_config_processes() { return 0; }
        service_manager_is_active() { return 1; }
        singbox_config_pids() { return 0; }
        is_systemd() { return 1; }
        OS=unknown
        : "$OS"
        service_disable() { return 0; }
        service_is_enabled() { return 1; }
        singbox_installed() { return 1; }

        restore_node_files "$backup" >/dev/null

        assert_file_contains "$SS_CONFIG_PATH" '"type": "shadowsocks"'
        assert_file_contains "$VLESS_CONFIG_PATH" '"type": "vless"'
        assert_file_contains "$SS_STATE_FILE" '^PROTOCOL=shadowsocks$'
        assert_file_contains "$VLESS_STATE_FILE" '^PROTOCOL=vless-reality$'
        assert_file_contains "$URI_FILE" '^ss://'
    )
}

test_verify_runtime_checks_both_protocols() {
    (
        local checked=""
        service_is_running() { return 0; }
        protocol_visible_exists() { return 0; }
        load_protocol_state() {
            if [ "$1" = vless ]; then
                PORT=20002
                REALITY_PRIVATE_KEY=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
            else
                PORT=20001
            fi
            : "$PORT" "${REALITY_PRIVATE_KEY:-}"
        }
        wait_for_port_listener() {
            checked="${checked}${1}:$2 "
        }

        verify_all_node_runtime
        assert_eq "20002:tcp 20001:both " "$checked"
    )
}

test_cancel_eof_and_input_interrupt_have_no_mutation() {
    (
        local event_log="$TEST_TMP/cancel-no-mutation.events"
        set_node_paths "$TEST_TMP/cancel-no-mutation"
        : > "$event_log"
        require_valid_node_state_if_present() { return 0; }
        protocol_visible_exists() { return 1; }
        configured_node_ports_csv() { printf '\n'; }
        prompt_node_host() { printf -v "$1" '%s' ss.example.com; }
        choose_node_port() { printf '%s\n' 20001; }
        confirm_default_yes() { return 1; }
        begin_node_transaction() { printf 'transaction\n' >> "$event_log"; }
        install_singbox_if_missing() { printf 'install\n' >> "$event_log"; }
        service_stop() { printf 'stop\n' >> "$event_log"; }
        restart_singbox_cleanly() { printf 'restart\n' >> "$event_log"; }
        firewall_prepare_port_transition() { printf 'firewall\n' >> "$event_log"; }

        create_or_rebuild_node <<< $'\n' >/dev/null
        assert_empty_file "$event_log" "最终取消不得停止服务、安装依赖或刷新防火墙"
    )
    (
        local event_log="$TEST_TMP/eof-no-mutation.events"
        set_node_paths "$TEST_TMP/eof-no-mutation"
        : > "$event_log"
        require_valid_node_state_if_present() { return 0; }
        protocol_visible_exists() { return 1; }
        configured_node_ports_csv() { printf '\n'; }
        prompt_node_host() { printf -v "$1" '%s' ss.example.com; }
        begin_node_transaction() { printf 'transaction\n' >> "$event_log"; }
        service_stop() { printf 'stop\n' >> "$event_log"; }
        firewall_refresh_if_enabled() { printf 'firewall\n' >> "$event_log"; }

        if create_or_rebuild_node </dev/null >/dev/null 2>&1; then
            fail "名称输入遇到 EOF 时应取消创建"
        fi
        assert_empty_file "$event_log" "EOF 不得建立事务、停止服务或刷新防火墙"
    )
    (
        local event_log="$TEST_TMP/interrupt-no-mutation.events"
        set_node_paths "$TEST_TMP/interrupt-no-mutation"
        : > "$event_log"
        require_valid_node_state_if_present() { return 0; }
        protocol_visible_exists() { return 1; }
        configured_node_ports_csv() { printf '\n'; }
        prompt_node_host() { return 130; }
        begin_node_transaction() { printf 'transaction\n' >> "$event_log"; }
        service_stop() { printf 'stop\n' >> "$event_log"; }
        firewall_refresh_if_enabled() { printf 'firewall\n' >> "$event_log"; }

        if create_or_rebuild_node >/dev/null 2>&1; then
            fail "输入阶段中断时应取消创建"
        fi
        assert_empty_file "$event_log" "输入阶段 Ctrl+C 不得建立事务或触发服务、防火墙操作"
    )
}

test_pending_transaction_recovers_after_hard_interruption() {
    (
        set_node_paths "$TEST_TMP/pending-recovery"
        mkdir -p "$NODE_CONFIG_DIR"
        write_ss_config_fixture "$SS_CONFIG_PATH"
        write_ss_state_fixture "$SS_STATE_FILE"
        write_uri_files
        service_is_running() { return 1; }
        service_is_enabled() { return 1; }

        begin_node_transaction
        mark_node_transaction_mutated
        printf 'broken\n' > "$SS_CONFIG_PATH"
        rm -f "$SS_STATE_FILE" "$URI_FILE" "$SS_URI_FILE"
        ACTIVE_NODE_BACKUP=""

        service_stop() { return 0; }
        stop_singbox_config_processes() { return 0; }
        service_manager_is_active() { return 1; }
        singbox_config_pids() { return 0; }
        service_disable() { return 0; }
        service_is_enabled() { return 1; }
        firewall_refresh_if_enabled() { return 0; }
        is_systemd() { return 1; }
        OS=unknown

        recover_pending_node_transaction >/dev/null

        assert_file_contains "$SS_STATE_FILE" '^CONFIG_ID=111111111111111111111111$'
        assert_file_contains "$SS_CONFIG_PATH" '"type": "shadowsocks"'
        assert_file_contains "$URI_FILE" '^ss://'
        [ ! -e "$NODE_TRANSACTION_DIR" ] || fail "恢复完成后应清理 pending 事务"
    )
}

test_absent_backup_entry_removes_target_and_invalid_entry_is_rejected() {
    (
        local backup_dir target

        backup_dir="$TEST_TMP/restore-entry-status/backup"
        target="$TEST_TMP/restore-entry-status/target"
        mkdir -p "$backup_dir"
        printf 'current\n' > "$target"
        node_backup_entry_is_present() { return 1; }

        restore_node_file_from_backup "$backup_dir" absent "$backup_dir/unused" "$target"
        [ ! -e "$target" ] || fail "备份清单标记 absent 时应删除当前目标文件"

        printf 'current\n' > "$target"
        node_backup_entry_is_present() { return 2; }
        if restore_node_file_from_backup "$backup_dir" invalid "$backup_dir/unused" "$target"; then
            fail "备份清单条目无效时不得继续恢复"
        fi
        assert_file_contains "$target" '^current$' "条目无效时不得删除当前目标文件"
    )
}

test_unmodified_pending_transaction_is_discarded_without_service_stop() {
    (
        set_node_paths "$TEST_TMP/pending-unmodified"
        mkdir -p "$NODE_CONFIG_DIR"
        write_ss_config_fixture "$SS_CONFIG_PATH"
        write_ss_state_fixture "$SS_STATE_FILE"
        write_uri_files
        service_is_running() { return 1; }
        service_is_enabled() { return 1; }
        begin_node_transaction
        ACTIVE_NODE_BACKUP=""
        service_stop() { fail "尚未修改节点文件时不得停止 sing-box"; }

        recover_pending_node_transaction >/dev/null

        assert_file_contains "$SS_CONFIG_PATH" '"type": "shadowsocks"'
        [ ! -e "$NODE_TRANSACTION_DIR" ] ||
            fail "没有 mutated 标记的 pending 事务应直接清理"
    )
}

test_corrupted_node_backup_is_rejected_before_overwrite() {
    (
        set_node_paths "$TEST_TMP/pending-corrupt"
        mkdir -p "$NODE_CONFIG_DIR"
        write_ss_config_fixture "$SS_CONFIG_PATH"
        write_ss_state_fixture "$SS_STATE_FILE"
        write_uri_files
        service_is_running() { return 1; }
        service_is_enabled() { return 1; }
        begin_node_transaction
        mark_node_transaction_mutated
        printf '%s\n' tampered >> "$NODE_TRANSACTION_BACKUP/ss-state.env"
        printf '%s\n' current-live > "$SS_CONFIG_PATH"
        ACTIVE_NODE_BACKUP=""
        service_stop() { fail "备份校验失败时不得停止或覆盖现有服务"; }

        if recover_pending_node_transaction >/dev/null 2>&1; then
            fail "哈希损坏的节点备份不得自动恢复"
        fi
        assert_file_contains "$SS_CONFIG_PATH" '^current-live$'
        [ -d "$NODE_TRANSACTION_BACKUP" ] ||
            fail "损坏的事务备份必须保留供人工处理"
    )
}

test_failed_recovery_keeps_transaction_backup() {
    (
        set_node_paths "$TEST_TMP/pending-stop-failure"
        mkdir -p "$NODE_CONFIG_DIR"
        write_ss_config_fixture "$SS_CONFIG_PATH"
        write_ss_state_fixture "$SS_STATE_FILE"
        write_uri_files
        service_is_running() { return 1; }
        service_is_enabled() { return 1; }
        begin_node_transaction
        mark_node_transaction_mutated
        printf 'broken\n' > "$SS_CONFIG_PATH"
        ACTIVE_NODE_BACKUP=""

        service_stop() { return 1; }
        stop_singbox_config_processes() { return 1; }
        service_manager_is_active() { return 0; }
        singbox_config_pids() { printf '%s\n' 1234; }

        if recover_pending_node_transaction > "$TEST_TMP/pending-stop-failure.out" 2>&1; then
            fail "服务或残留进程未停止时恢复不得成功"
        fi
        [ -f "$NODE_TRANSACTION_DIR/pending" ] ||
            fail "恢复失败后必须保留 pending 标记"
        [ -d "$NODE_TRANSACTION_BACKUP" ] ||
            fail "恢复失败后必须保留节点备份"
        assert_file_contains "$SS_CONFIG_PATH" '^broken$' \
            "停止失败时不得开始覆盖现有文件"
    )
}

test_committed_transaction_is_not_rolled_back() {
    (
        set_node_paths "$TEST_TMP/committed-recovery"
        mkdir -p "$NODE_CONFIG_DIR"
        write_ss_config_fixture "$SS_CONFIG_PATH"
        write_ss_state_fixture "$SS_STATE_FILE"
        write_uri_files
        service_is_running() { return 1; }
        service_is_enabled() { return 1; }
        begin_node_transaction
        printf 'committed-new-state\n' > "$SS_CONFIG_PATH"
        : > "$NODE_TRANSACTION_DIR/committed"
        chmod 600 "$NODE_TRANSACTION_DIR/committed"
        # shellcheck disable=SC2034 # 被被测的事务恢复函数动态读取。
        ACTIVE_NODE_BACKUP=""
        service_stop() { fail "committed 事务不得触发操作前状态恢复"; }

        recover_pending_node_transaction >/dev/null

        assert_file_contains "$SS_CONFIG_PATH" '^committed-new-state$'
        [ ! -e "$NODE_TRANSACTION_DIR" ] || fail "committed 残留事务应只清理目录"
    )
}

test_config_state_identity_and_credentials_must_match() {
    (
        set_node_paths "$TEST_TMP/mismatch-ss-id"
        mkdir -p "$NODE_CONFIG_DIR"
        write_ss_config_fixture "$SS_CONFIG_PATH"
        write_ss_state_fixture "$SS_STATE_FILE" 20001 999999999999999999999999
        if validate_protocol_node_artifacts ss "$SS_CONFIG_PATH" "$SS_STATE_FILE" "$SS_URI_FILE"; then
            fail "配置标识不一致时 Shadowsocks 完整性校验不得通过"
        fi
    )
    (
        set_node_paths "$TEST_TMP/mismatch-ss-password"
        mkdir -p "$NODE_CONFIG_DIR"
        write_ss_config_fixture "$SS_CONFIG_PATH"
        write_ss_state_fixture "$SS_STATE_FILE"
        sed -i 's/^PASSWORD=.*/PASSWORD=TkVXTkVXTkVXTkVXTkVXQQ==/' "$SS_STATE_FILE"
        if validate_protocol_node_artifacts ss "$SS_CONFIG_PATH" "$SS_STATE_FILE" "$SS_URI_FILE"; then
            fail "Shadowsocks 密码不一致时完整性校验不得通过"
        fi
    )
    (
        set_node_paths "$TEST_TMP/mismatch-vless-port"
        mkdir -p "$NODE_CONFIG_DIR"
        write_vless_config_fixture "$VLESS_CONFIG_PATH"
        write_vless_state_fixture "$VLESS_STATE_FILE" 29999
        if validate_protocol_node_artifacts vless "$VLESS_CONFIG_PATH" "$VLESS_STATE_FILE" "$VLESS_URI_FILE"; then
            fail "VLESS 端口不一致时完整性校验不得通过"
        fi
    )
    (
        set_node_paths "$TEST_TMP/mismatch-vless-credentials"
        mkdir -p "$NODE_CONFIG_DIR"
        write_vless_config_fixture "$VLESS_CONFIG_PATH"
        write_vless_state_fixture "$VLESS_STATE_FILE"
        sed -i \
            -e 's/^UUID=.*/UUID=aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee/' \
            -e 's/^REALITY_PRIVATE_KEY=.*/REALITY_PRIVATE_KEY=CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC/' \
            "$VLESS_STATE_FILE"
        if validate_protocol_node_artifacts vless "$VLESS_CONFIG_PATH" "$VLESS_STATE_FILE" "$VLESS_URI_FILE"; then
            fail "VLESS UUID 或 Reality 私钥不一致时完整性校验不得通过"
        fi
    )
}

test_aggregate_uri_must_match_independent_nodes() {
    (
        set_node_paths "$TEST_TMP/mismatch-aggregate-uri"
        mkdir -p "$NODE_CONFIG_DIR"
        write_ss_config_fixture "$SS_CONFIG_PATH"
        write_ss_state_fixture "$SS_STATE_FILE"
        write_uri_files
        printf 'stale-aggregate\n' > "$URI_FILE"

        if require_valid_node_state_if_present >/dev/null 2>&1; then
            fail "汇总链接与独立节点不一致时完整性校验不得通过"
        fi
    )
}

test_singbox_update_rejects_mismatched_layout_before_download() {
    (
        local event_log="$TEST_TMP/update-mismatch.events"
        set_node_paths "$TEST_TMP/update-mismatch"
        mkdir -p "$NODE_CONFIG_DIR"
        write_ss_config_fixture "$SS_CONFIG_PATH"
        write_ss_state_fixture "$SS_STATE_FILE" 29999
        : > "$event_log"
        singbox_installed() { return 0; }
        singbox_version() { printf '%s\n' 1.13.13; }
        singbox_binary_is_package_managed() { return 0; }
        install_deps() { printf 'deps\n' >> "$event_log"; }
        run_singbox_installer() { printf 'installer\n' >> "$event_log"; }

        if update_singbox > "$TEST_TMP/update-mismatch.out" 2>&1; then
            fail "节点配置错配时 sing-box 更新不得继续"
        fi
        assert_empty_file "$event_log" "完整性失败必须发生在依赖下载和二进制替换前"
        assert_file_contains "$TEST_TMP/update-mismatch.out" '节点配置完整性未通过'
    )
}

test_uri_group_failure_restores_old_files() {
    local fail_at

    for fail_at in 2 3; do
        (
            local move_count=0 before_aggregate before_ss before_vless build_dir
            set_node_paths "$TEST_TMP/uri-failure-$fail_at"
            mkdir -p "$NODE_CONFIG_DIR"
            write_ss_config_fixture "$SS_CONFIG_PATH"
            write_vless_config_fixture "$VLESS_CONFIG_PATH"
            write_ss_state_fixture "$SS_STATE_FILE"
            write_vless_state_fixture "$VLESS_STATE_FILE"
            write_uri_files
            before_aggregate="$(cat "$URI_FILE")"
            before_ss="$(cat "$SS_URI_FILE")"
            before_vless="$(cat "$VLESS_URI_FILE")"
            build_dir="$TEST_TMP/uri-failure-$fail_at-build"
            mkdir -p "$build_dir"
            printf 'new-aggregate\n' > "$build_dir/${URI_FILE##*/}"
            printf 'new-ss\n' > "$build_dir/${SS_URI_FILE##*/}"
            printf 'new-vless\n' > "$build_dir/${VLESS_URI_FILE##*/}"
            chmod 600 "$build_dir"/*.txt
            mv() {
                move_count=$((move_count + 1))
                if [ "$move_count" -eq "$fail_at" ]; then
                    return 42
                fi
                command mv "$@"
            }

            if publish_uri_file_group "$build_dir" >/dev/null 2>&1; then
                unset -f mv
                fail "第 $fail_at 次链接替换失败时不应报告成功"
            fi
            unset -f mv
            assert_eq "$before_aggregate" "$(cat "$URI_FILE")" "汇总链接必须恢复"
            assert_eq "$before_ss" "$(cat "$SS_URI_FILE")" "Shadowsocks 链接必须恢复"
            assert_eq "$before_vless" "$(cat "$VLESS_URI_FILE")" "VLESS 链接必须恢复"
        )
    done
}

test_last_uri_delete_failure_is_not_masked() {
    (
        local failed_once=0
        set_node_paths "$TEST_TMP/uri-delete-failure"
        mkdir -p "$CONFIG_DIR"
        printf 'old-link\n' > "$URI_FILE"
        chmod 600 "$URI_FILE"
        rm() {
            if [ "$failed_once" -eq 0 ] && [ "${1:-}" = "-f" ] &&
                [[ " $* " == *" $URI_FILE "* ]]; then
                failed_once=1
                return 42
            fi
            command rm "$@"
        }

        if write_uri_files >/dev/null 2>&1; then
            unset -f rm
            fail "删除最后一个汇总链接失败时不得报告成功"
        fi
        unset -f rm
        assert_file_contains "$URI_FILE" '^old-link$'
    )
}

test_insecure_node_permissions_are_rejected() {
    (
        if [ "$(id -u)" -ne 0 ]; then
            return 0
        fi
        set_node_paths "$TEST_TMP/insecure-permissions"
        mkdir -p "$NODE_CONFIG_DIR"
        write_ss_config_fixture "$SS_CONFIG_PATH"
        write_ss_state_fixture "$SS_STATE_FILE"
        write_uri_files
        node_file_is_secure() {
            local owner group mode
            [ -f "$1" ] && [ ! -L "$1" ] || return 1
            owner="$(stat -c '%u' "$1")" || return 1
            group="$(stat -c '%g' "$1")" || return 1
            mode="$(stat -c '%a' "$1")" || return 1
            [ "$owner" = 0 ] && [ "$group" = 0 ] && [ "$mode" = 600 ]
        }
        node_dir_is_secure() {
            local owner group mode
            [ -d "$1" ] && [ ! -L "$1" ] || return 1
            owner="$(stat -c '%u' "$1")" || return 1
            group="$(stat -c '%g' "$1")" || return 1
            mode="$(stat -c '%a' "$1")" || return 1
            [ "$owner" = 0 ] && [ "$group" = 0 ] && [ "$mode" = 700 ]
        }
        command chown root:root "$CONFIG_DIR" "$NODE_CONFIG_DIR" \
            "$SS_CONFIG_PATH" "$SS_STATE_FILE" "$URI_FILE" "$SS_URI_FILE"
        chmod 700 "$CONFIG_DIR" "$NODE_CONFIG_DIR"
        chmod 600 "$SS_CONFIG_PATH" "$SS_STATE_FILE" "$URI_FILE" "$SS_URI_FILE"

        chmod 666 "$SS_CONFIG_PATH"
        if require_valid_node_state_if_present >/dev/null 2>&1; then
            fail "0666 节点配置必须被拒绝"
        fi
        chmod 600 "$SS_CONFIG_PATH"
        chmod 755 "$NODE_CONFIG_DIR"
        if require_valid_node_state_if_present >/dev/null 2>&1; then
            fail "权限不是 700 的节点目录必须被拒绝"
        fi
        chmod 700 "$NODE_CONFIG_DIR"
        command chown 65534:65534 "$SS_STATE_FILE"
        if require_valid_node_state_if_present >/dev/null 2>&1; then
            fail "所有者不是 root 的节点状态必须被拒绝"
        fi
    )
}

test_self_check_keeps_valid_sibling_visible() {
    (
        set_node_paths "$TEST_TMP/self-check-sibling"
        mkdir -p "$NODE_CONFIG_DIR"
        write_ss_config_fixture "$SS_CONFIG_PATH"
        write_ss_state_fixture "$SS_STATE_FILE"
        write_vless_config_fixture "$VLESS_CONFIG_PATH"
        write_vless_state_fixture "$VLESS_STATE_FILE" 29999
        singbox_installed() { return 1; }
        port_listener_ready() { return 1; }
        resolve_host_ips() { printf '%s\n' 192.0.2.1; }
        public_ipv4() { return 1; }
        firewall_control_plane_present() { return 1; }

        run_self_check > "$TEST_TMP/self-check-sibling.out" 2>&1

        assert_file_contains "$TEST_TMP/self-check-sibling.out" '配置完整性.*未通过'
        assert_file_contains "$TEST_TMP/self-check-sibling.out" 'Shadowsocks 节点'
        assert_file_not_contains "$TEST_TMP/self-check-sibling.out" '配置文件.*不存在'
    )
}

main() {
    local test status passed=0
    local -a tests=(
        test_complete_configs_merge_with_unique_tags
        test_create_shadowsocks_preserves_vless_node
        test_create_vless_preserves_shadowsocks_node
        test_independent_states_and_links_are_aggregated
        test_service_definition_uses_independent_config_directory
        test_orphan_protocol_uri_is_rejected
        test_stopped_sibling_port_is_rejected
        test_stopped_target_port_is_rechecked_against_system_listeners
        test_delete_one_protocol_keeps_sibling_running
        test_delete_last_protocol_disables_service
        test_delete_residual_node_without_singbox_keeps_sibling_static
        test_delete_last_residual_node_without_singbox_skips_missing_service
        test_static_node_backup_validation_does_not_execute_singbox
        test_node_transaction_full_and_static_validation_modes
        test_dual_node_backup_restore_round_trip
        test_verify_runtime_checks_both_protocols
        test_cancel_eof_and_input_interrupt_have_no_mutation
        test_absent_backup_entry_removes_target_and_invalid_entry_is_rejected
        test_pending_transaction_recovers_after_hard_interruption
        test_unmodified_pending_transaction_is_discarded_without_service_stop
        test_corrupted_node_backup_is_rejected_before_overwrite
        test_failed_recovery_keeps_transaction_backup
        test_committed_transaction_is_not_rolled_back
        test_config_state_identity_and_credentials_must_match
        test_aggregate_uri_must_match_independent_nodes
        test_singbox_update_rejects_mismatched_layout_before_download
        test_uri_group_failure_restores_old_files
        test_last_uri_delete_failure_is_not_masked
        test_insecure_node_permissions_are_rejected
        test_self_check_keeps_valid_sibling_visible
    )

    for test in "${tests[@]}"; do
        set +e
        (set -e; "$test")
        status=$?
        set -e
        if [ "$status" -eq 0 ]; then
            printf 'ok - %s\n' "$test"
            passed=$((passed + 1))
        else
            printf 'not ok - %s\n' "$test" >&2
            return 1
        fi
    done
    printf '%s dual node tests passed.\n' "$passed"
}

main "$@"
