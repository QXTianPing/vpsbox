#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=tests/test_helper.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/test_helper.sh"

# shellcheck source=../vpsbox.sh
source "$REPO_DIR/vpsbox.sh"

CASE_PIDS=""

cleanup_case_pids() {
    local pid

    for pid in $CASE_PIDS; do
        kill -KILL "$pid" 2>/dev/null || true
    done
    for pid in $CASE_PIDS; do
        wait "$pid" 2>/dev/null || true
    done
    CASE_PIDS=""
}

test_cleanup() {
    cleanup_case_pids
    if [ "${KEEP_TEST_TMP:-0}" = "1" ]; then
        printf '保留测试临时目录：%s\n' "$TEST_TMP" >&2
    else
        rm -rf -- "$TEST_TMP"
    fi
}
trap test_cleanup EXIT

wait_for_file() {
    local path="$1"

    for _ in {1..50}; do
        [ -s "$path" ] && return 0
        sleep 0.1
    done
    fail "等待文件超时：$path"
}

process_children() {
    local pid="$1"

    cat "/proc/$pid/task/$pid/children" 2>/dev/null || true
}

remember_process_tree() {
    local pid="$1" child

    for child in $(process_children "$pid"); do
        CASE_PIDS="$CASE_PIDS $child"
        remember_process_tree "$child"
    done
}

assert_fd_closed() {
    local pid="$1" fd="$2" message="$3"

    [ ! -e "/proc/$pid/fd/$fd" ] || fail "$message（PID $pid 仍持有 FD $fd）"
}

assert_lock_available() {
    local path="$1" message="$2"

    exec 201<>"$path"
    if ! flock -n 201; then
        exec 201>&-
        fail "$message"
        return 1
    fi
    flock -u 201
    exec 201>&-
}

emit_public_listener_sample() {
    printf '%s\n' \
        'udp UNCONN 0 0 0.0.0.0:30000 0.0.0.0:* users:(("sing-box",pid=759,fd=8))' \
        'udp UNCONN 0 0 1.1.1.1:68 0.0.0.0:* users:(("dhcpcd",pid=623,fd=3))' \
        'udp UNCONN 0 0 *:443 *:* users:(("caddy",pid=754,fd=7))' \
        'udp UNCONN 0 0 [2606:4700:4700::1111]:546 [::]:* users:(("dhcpcd",pid=730,fd=3))' \
        'udp UNCONN 0 0 [fe80::1234]%ens3:546 [::]:* users:(("dhcpcd",pid=604,fd=3))' \
        'tcp LISTEN 0 128 0.0.0.0:22222 0.0.0.0:* users:(("sshd",pid=779,fd=6))' \
        'tcp LISTEN 0 4096 0.0.0.0:30000 0.0.0.0:* users:(("sing-box",pid=759,fd=7))' \
        'tcp LISTEN 0 128 [::]:22222 [::]:* users:(("sshd",pid=779,fd=7))' \
        'tcp LISTEN 0 4096 *:443 *:* users:(("caddy",pid=754,fd=6))' \
        'tcp LISTEN 0 4096 *:80 *:* users:(("caddy",pid=754,fd=8))' \
        'tcp LISTEN 0 4096 127.0.0.1:2019 0.0.0.0:* users:(("caddy",pid=754,fd=9))' \
        'tcp LISTEN 0 4096 10.0.0.2:3001 0.0.0.0:* users:(("private-api",pid=900,fd=3))' \
        'tcp LISTEN 0 4096 100.64.1.2:41641 0.0.0.0:* users:(("tailscaled",pid=901,fd=3))'
}

test_port_decimal_normalization() {
    local normalized

    normalized="$(normalize_port_csv "00080,80,00443,443,65535")"
    assert_eq "80,443,65535" "$normalized" "端口 CSV 应统一为十进制并去重"
    normalize_port_decimal "00080" | grep -qx 80 ||
        fail "旧状态中的前导零端口应可规范为十进制"
    is_valid_port 80 || fail "规范十进制端口应通过交互校验"
    if is_valid_port 00080; then
        fail "交互端口不应接受带前导零的非规范表示"
    fi
    if normalize_port_decimal 00000 >/dev/null; then
        fail "端口 0 不应通过规范化"
    fi
}

test_public_listener_address_classification() {
    local addr

    for addr in 0.0.0.0 '*' :: '[::]' 1.1.1.1 192.0.0.9 192.0.0.10 192.0.1.1 \
        2606:4700:4700::1111 100:1::1 2001:3::1 3fff:1000::1 ::ffff:0808:0808; do
        is_public_listen_addr "$addr" || fail "应识别为公网监听地址：$addr"
    done
    for addr in 127.0.0.1 ::1 10.0.0.1 100.64.1.2 169.254.1.1 172.16.0.1 \
        192.0.0.1 192.0.2.1 192.168.1.1 198.18.0.1 203.0.113.1 \
        fe80::1%ens3 '[fe80::1]%ens3' fd00::1 ff02::1 100::1 100:0:0:1::1 \
        2001:2::1 2001:10::1 2001:1f::1 2001:20::1 2001:2f::1 \
        2001:db8::1 3fff:0fff::1 ::ffff:c0a8:101; do
        if is_public_listen_addr "$addr"; then
            fail "不应识别为公网监听地址：$addr"
        fi
    done
}

test_listener_sample_collects_expected_public_ports() {
    (
        ss() { emit_public_listener_sample; }

        firewall_detect_public_listeners
        assert_eq '80,443,22222,30000' "$FW_PUBLIC_TCP" "公网 TCP 应包含 Caddy、SSH 与节点"
        assert_eq '443,30000' "$FW_PUBLIC_UDP" "公网 UDP 应包含 Caddy HTTP/3 与节点"
    )
}

test_security_group_suggestions_exclude_dhcp_clients() {
    local output

    output="$({
        ss() { emit_public_listener_sample; }
        show_ports_security_group
    })"
    printf '%s\n' "$output" | grep -Eq '^TCP 80$' || fail "自检应建议放行 Caddy TCP 80"
    printf '%s\n' "$output" | grep -Eq '^TCP 443$' || fail "自检应建议放行 Caddy TCP 443"
    printf '%s\n' "$output" | grep -Eq '^UDP 443$' || fail "自检应建议放行 Caddy UDP 443"
    if printf '%s\n' "$output" | grep -Eq '^UDP (68|546)$'; then
        fail "DHCP 客户端端口不应进入普通入站放行建议"
    fi
    printf '%s\n' "$output" | grep -Eq '^UDP[[:space:]]+68[[:space:]]+dhcpcd$' ||
        fail "DHCP 客户端监听仍应显示在非公网列表"
}

test_allowed_ports_merge_known_public_docker_and_extra_sources() {
    (
        FW_EXTRA_TCP='8443'
        FW_EXTRA_UDP='5353'
        ssh_effective_ports_csv() { printf '%s\n' 23333; }
        ssh_listening_ports_csv() { printf '%s\n' 23333; }
        require_valid_node_state_if_present() { :; }
        protocol_visible_exists() { return 0; }
        load_protocol_state() {
            if [ "$1" = vless ]; then
                PORT=43333
                PROTOCOL=vless-reality
            else
                PORT=31423
                PROTOCOL=shadowsocks
            fi
            : "$PORT" "$PROTOCOL"
        }
        firewall_detect_docker_ports() {
            FW_DOCKER_PUBLIC_TCP='8080'
            FW_DOCKER_PUBLIC_UDP=''
        }
        firewall_detect_public_listeners() {
            FW_PUBLIC_TCP='80,443,8080,8443,23333,31423,43333'
            FW_PUBLIC_UDP='443,5353,31423'
        }

        firewall_detect_allowed_ports
        assert_eq '80,443,8080,8443,23333,31423,43333' "$FW_ALLOWED_TCP" "TCP 应合并两种节点及其他放行来源"
        assert_eq '443,5353,31423' "$FW_ALLOWED_UDP" "UDP 应合并所有放行来源"
        assert_eq '80,443' "$FW_OTHER_PUBLIC_TCP" "其他公网 TCP 应扣除已分类来源"
        assert_eq '443' "$FW_OTHER_PUBLIC_UDP" "其他公网 UDP 应扣除节点与额外端口"
    )
}

test_stopped_public_service_is_removed_unless_extra() {
    (
        local detected_tcp='80' detected_udp='443'
        FW_EXTRA_TCP='8443'
        FW_EXTRA_UDP='5353'
        ssh_effective_ports_csv() { printf '%s\n' 23333; }
        ssh_listening_ports_csv() { printf '%s\n' 23333; }
        require_valid_node_state_if_present() { :; }
        protocol_visible_exists() { return 1; }
        firewall_detect_docker_ports() {
            FW_DOCKER_PUBLIC_TCP=''
            FW_DOCKER_PUBLIC_UDP=''
            : "$FW_DOCKER_PUBLIC_TCP" "$FW_DOCKER_PUBLIC_UDP"
        }
        firewall_detect_public_listeners() {
            FW_PUBLIC_TCP="$detected_tcp"
            FW_PUBLIC_UDP="$detected_udp"
        }

        firewall_detect_allowed_ports
        assert_eq '80,8443,23333' "$FW_ALLOWED_TCP" "运行中的公网服务应自动放行"
        assert_eq '443,5353' "$FW_ALLOWED_UDP" "运行中的公网 UDP 服务应自动放行"

        detected_tcp=''
        detected_udp=''
        firewall_detect_allowed_ports
        assert_eq '8443,23333' "$FW_ALLOWED_TCP" "停止的普通服务应在下次完整更新移除"
        assert_eq '5353' "$FW_ALLOWED_UDP" "额外 UDP 应在服务停止后继续保留"
    )
}

emit_live_firewall_table_sample() {
    cat <<'EOF'
table inet vpsbox {
    set docker4_tcp_ports {
        type inet_service
        elements = { 18080 }
    }
    set docker6_udp_ports {
        type inet_service
        elements = { 18443 }
    }
    set extra_tcp_dnat_ports {
        type inet_service
        elements = { 20000 }
    }
    chain input {
        type filter hook input priority filter; policy drop;
        meta nfproto ipv4 udp sport 67 udp dport 68 accept
        meta nfproto ipv6 udp sport 547 udp dport 546 accept
        tcp dport { 23333, 31423 } accept
        udp dport 31423 accept
    }
    chain docker_port_guard {
        meta l4proto tcp ct original proto-dst @extra_tcp_dnat_ports accept
        meta nfproto ipv4 meta l4proto tcp oifname @docker_bridge_ifaces ct original proto-dst @docker4_tcp_ports accept
        meta l4proto tcp drop
        meta nfproto ipv6 meta l4proto udp oifname @docker_bridge_ifaces ct original proto-dst @docker6_udp_ports accept
        meta l4proto udp drop
        drop
    }
    chain docker_forward {
        type filter hook forward priority -1; policy accept;
        ct direction original ct status dnat jump docker_port_guard
    }
}
EOF
}

test_view_rules_reads_live_nft_instead_of_current_listeners() {
    (
        local output="$TEST_TMP/firewall-live-view.out"
        firewall_runtime_enabled() { return 0; }
        firewall_persistence_state() { printf '已启用\n'; }
        firewall_detect_allowed_ports() { fail "查看实际规则不得重新扫描当前监听"; }
        nft() {
            [ "$*" = '-nn list table inet vpsbox' ] || return 1
            emit_live_firewall_table_sample
        }

        firewall_view_rules > "$output"

        assert_file_contains "$output" '主机入站[[:space:]]+TCP[[:space:]]+23333,31423'
        assert_file_contains "$output" '主机入站[[:space:]]+UDP[[:space:]]+31423'
        assert_file_contains "$output" 'Docker 转发[[:space:]]+TCP[[:space:]]+18080'
        assert_file_contains "$output" 'Docker 转发[[:space:]]+UDP[[:space:]]+18443'
        assert_file_contains "$output" '额外 DNAT[[:space:]]+TCP[[:space:]]+20000'
        assert_file_not_contains "$output" '(^|[^0-9])(68|546|80|443)([^0-9]|$)' \
            "未实际放行的新监听和 DHCP 客户端端口不得显示"
    )
}

test_view_rules_inactive_reports_no_live_ports_without_scanning() {
    (
        local output="$TEST_TMP/firewall-inactive-view.out"
        firewall_runtime_enabled() { return 1; }
        firewall_runtime_state() { printf '配置存在但未运行\n'; }
        firewall_persistence_state() { printf '已启用\n'; }
        firewall_detect_allowed_ports() { fail "停用防火墙的查看操作不得扫描期望端口"; }
        nft() { fail "停用防火墙时不得读取不存在的 live 表"; }

        firewall_view_rules > "$output"

        assert_file_contains "$output" '主机入站[[:space:]]+TCP[[:space:]]+-$'
        assert_file_contains "$output" '防火墙：配置存在但未运行'
        assert_file_contains "$output" '当前没有正在生效的 vpsbox 防火墙规则'
    )
}

test_view_rules_accepts_normalized_forward_priority_expression() {
    (
        local output="$TEST_TMP/firewall-normalized-forward-priority.out"
        firewall_runtime_enabled() { return 0; }
        firewall_persistence_state() { printf '已启用\n'; }
        nft() {
            [ "$*" = '-nn list table inet vpsbox' ] || return 1
            emit_live_firewall_table_sample | sed 's/hook forward priority -1; policy accept;/hook forward priority filter - 1; policy accept;/'
        }

        firewall_view_rules > "$output"
        assert_file_contains "$output" 'Docker 转发[[:space:]]+TCP[[:space:]]+18080'
        assert_file_contains "$output" '防火墙：运行中'
    )
}

test_view_rules_rejects_unhooked_or_permissive_base_chains() {
    (
        local output="$TEST_TMP/firewall-invalid-input-base.out"
        firewall_runtime_enabled() { return 0; }
        firewall_persistence_state() { printf '已启用\n'; }
        nft() {
            [ "$*" = '-nn list table inet vpsbox' ] || return 1
            emit_live_firewall_table_sample | sed 's/hook input priority filter; policy drop;/hook input priority filter; policy accept;/'
        }

        if firewall_view_rules > "$output" 2>&1; then
            fail "policy accept 的 input 链不得被报告为正在生效的放行规则"
        fi
        assert_file_contains "$output" '无法可靠读取当前 nftables 放行规则'
    )
    (
        local output="$TEST_TMP/firewall-invalid-forward-base.out"
        firewall_runtime_enabled() { return 0; }
        firewall_persistence_state() { printf '已启用\n'; }
        nft() {
            [ "$*" = '-nn list table inet vpsbox' ] || return 1
            emit_live_firewall_table_sample | sed 's/hook forward priority -1; policy accept;/hook forward priority 0; policy accept;/'
        }

        if firewall_view_rules > "$output" 2>&1; then
            fail "未使用受管优先级的 forward 链不得被报告为有效 Docker 转发规则"
        fi
        assert_file_contains "$output" '无法可靠读取当前 nftables 放行规则'
    )
}

test_firewall_table_parsers_consume_large_trailing_input() {
    local table body rules i

    table="$(
        emit_live_firewall_table_sample
        for ((i = 0; i < 12000; i++)); do
            printf '# trailing filler for pipefail regression %05d\n' "$i"
        done
    )"
    body="$(printf '%s\n' "$table" | firewall_set_body_lines docker4_tcp_ports)" ||
        fail "set 解析器不得因提前关闭大型输入管道而触发 pipefail"
    rules="$(printf '%s\n' "$table" | firewall_chain_rule_lines input)" ||
        fail "chain 解析器不得因提前关闭大型输入管道而触发 pipefail"
    [[ "$body" == *'elements = { 18080 }'* ]] ||
        fail "大型表中的端口 set 未正确解析"
    [[ "$rules" == *'tcp dport { 23333, 31423 } accept'* ]] ||
        fail "大型表中的 input 规则未正确解析"
}

test_systemd_enabled_inactive_firewalld_conflict() {
    (
        # Consumed by firewall_firewalld_enabled_or_active from the sourced script.
        # shellcheck disable=SC2034
        OS=debian
        is_systemd() { return 0; }
        systemctl() {
            case "${1:-}" in
                is-active) return 1 ;;
                is-enabled) return 0 ;;
                *) return 1 ;;
            esac
        }

        if firewall_check_conflicts >/dev/null 2>&1; then
            fail "systemd 中已启用但未运行的 firewalld 应被识别为冲突"
        fi
    )
}

test_openrc_enabled_inactive_firewalld_conflict() {
    local runlevels="$TEST_TMP/openrc-runlevels"

    mkdir -p "$runlevels/default"
    ln -s /etc/init.d/firewalld "$runlevels/default/firewalld"
    firewall_openrc_service_enabled firewalld "$runlevels" ||
        fail "OpenRC runlevel 中的 firewalld 启用链接应被识别"

    (
        # Consumed by firewall_firewalld_enabled_or_active from the sourced script.
        # shellcheck disable=SC2034
        OS=alpine
        is_systemd() { return 1; }
        rc-service() { return 1; }
        firewall_openrc_service_enabled() { return 0; }

        if firewall_check_conflicts >/dev/null 2>&1; then
            fail "OpenRC 中已启用但未运行的 firewalld 应被识别为冲突"
        fi
    )
}

test_bounded_background_processes_release_lock() {
    local case_dir="$TEST_TMP/bounded-lock" driver ready lock child_count=0
    local driver_pid descendants pid

    mkdir -p "$case_dir"
    driver="$case_dir/driver.sh"
    ready="$case_dir/ready"
    lock="$case_dir/menu.lock"
    cat > "$driver" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$REPO_DIR/vpsbox.sh"
PACKAGE_KILL_GRACE=1
exec 200<>"$LOCK_TARGET"
flock 200
run_bounded_in_new_session 20 sh -c 'printf ready > "$1"; sleep 30' sh "$READY_FILE"
EOF
    chmod 700 "$driver"

    REPO_DIR="$REPO_DIR" LOCK_TARGET="$lock" READY_FILE="$ready" bash "$driver" &
    driver_pid=$!
    CASE_PIDS="$driver_pid"
    wait_for_file "$ready"
    for _ in {1..50}; do
        descendants="$(process_children "$driver_pid")"
        child_count="$(wc -w <<< "$descendants")"
        [ "$child_count" -ge 2 ] && break
        sleep 0.1
    done
    [ "$child_count" -ge 2 ] || fail "未观察到受限命令及其超时计时器"
    remember_process_tree "$driver_pid"
    for pid in $(process_children "$driver_pid"); do
        assert_fd_closed "$pid" 200 "受限命令或超时计时器继承了菜单锁"
    done

    kill -KILL "$driver_pid"
    wait "$driver_pid" 2>/dev/null || true
    assert_lock_available "$lock" "父菜单被 SIGKILL 后，后台受限命令仍占用 flock"
    cleanup_case_pids
}

run_timeout_lock_case() {
    local name="$1" mode="$2"
    local case_dir="$TEST_TMP/$name" driver ready lock driver_pid pid
    local real_timeout test_path="$PATH"

    mkdir -p "$case_dir"
    driver="$case_dir/driver.sh"
    ready="$case_dir/ready"
    lock="$case_dir/menu.lock"
    if [ "$mode" = "busybox-fallback" ]; then
        real_timeout="$(command -v timeout)"
        mkdir -p "$case_dir/bin"
        cat > "$case_dir/bin/timeout" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "-k" ]; then
    exit 125
fi
exec "$REAL_TIMEOUT" "$@"
EOF
        chmod 700 "$case_dir/bin/timeout"
        test_path="$case_dir/bin:$PATH"
    fi
    cat > "$driver" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$REPO_DIR/vpsbox.sh"
PACKAGE_KILL_GRACE=1
exec 200<>"$LOCK_TARGET"
flock 200
run_bounded_with_timeout 20 sh -c 'printf ready > "$1"; sleep 30' sh "$READY_FILE"
EOF
    chmod 700 "$driver"

    REPO_DIR="$REPO_DIR" LOCK_TARGET="$lock" READY_FILE="$ready" \
        REAL_TIMEOUT="${real_timeout:-}" PATH="$test_path" bash "$driver" &
    driver_pid=$!
    CASE_PIDS="$driver_pid"
    wait_for_file "$ready"
    remember_process_tree "$driver_pid"
    [ "$(wc -w <<< "$CASE_PIDS")" -ge 3 ] ||
        fail "未观察到 timeout 及其受限命令"
    for pid in $CASE_PIDS; do
        [ "$pid" = "$driver_pid" ] ||
            assert_fd_closed "$pid" 200 "timeout 兼容路径继承了菜单锁"
    done

    kill -KILL "$driver_pid"
    wait "$driver_pid" 2>/dev/null || true
    assert_lock_available "$lock" "父菜单被 SIGKILL 后，timeout 兼容路径仍占用 flock"
    cleanup_case_pids
}

test_timeout_processes_release_lock() {
    run_timeout_lock_case timeout-lock supported
}

test_busybox_timeout_fallback_releases_lock() {
    run_timeout_lock_case timeout-fallback busybox-fallback
}

test_watchdog_survives_parent_without_holding_lock() {
    local case_dir="$TEST_TMP/watchdog-lock" driver ready lock runtime snapshot
    local driver_pid watchdog child=""

    mkdir -p "$case_dir"
    driver="$case_dir/driver.sh"
    ready="$case_dir/ready"
    lock="$case_dir/menu.lock"
    runtime="$case_dir/run"
    snapshot="$runtime/firewall-rollback.test"
    cat > "$driver" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$REPO_DIR/vpsbox.sh"
RUNTIME_DIR="$RUNTIME_TARGET"
snapshot="$RUNTIME_DIR/firewall-rollback.test"
mkdir -p "$snapshot"
printf '%s\n' '#!/bin/sh' 'sleep 30' > "$snapshot/rollback.sh"
chmod 700 "$snapshot/rollback.sh"
exec 200<>"$LOCK_TARGET"
flock 200
firewall_start_rollback_watchdog "$snapshot"
cat "$snapshot/watchdog.pid" > "$WATCHDOG_FILE"
printf ready > "$READY_FILE"
wait "$(cat "$snapshot/watchdog.pid")"
EOF
    chmod 700 "$driver"

    REPO_DIR="$REPO_DIR" RUNTIME_TARGET="$runtime" LOCK_TARGET="$lock" \
        WATCHDOG_FILE="$case_dir/watchdog.pid" READY_FILE="$ready" bash "$driver" &
    driver_pid=$!
    CASE_PIDS="$driver_pid"
    wait_for_file "$ready"
    watchdog="$(cat "$case_dir/watchdog.pid")"
    CASE_PIDS="$CASE_PIDS $watchdog"
    for _ in {1..50}; do
        child="$(process_children "$watchdog" | awk '{print $1}')"
        [ -n "$child" ] && break
        sleep 0.1
    done
    [ -n "$child" ] || fail "watchdog 未创建等待子进程"
    CASE_PIDS="$CASE_PIDS $child"
    assert_fd_closed "$watchdog" 200 "防火墙 watchdog 继承了菜单锁"
    assert_fd_closed "$child" 200 "watchdog 的等待子进程继承了菜单锁"

    kill -KILL "$driver_pid"
    wait "$driver_pid" 2>/dev/null || true
    kill -0 "$watchdog" 2>/dev/null || fail "父菜单异常退出不应破坏防火墙 watchdog"
    assert_lock_available "$lock" "父菜单被 SIGKILL 后，防火墙 watchdog 仍占用 flock"
    cleanup_case_pids
    rm -rf -- "$snapshot"
}

test_stopped_docker_fixed_binding_is_public() {
    (
        docker() { :; }
        firewall_docker_available() { return 0; }
        firewall_validate_docker_daemon_mode() { return 0; }
        firewall_detect_docker_proxy_ports() { return 0; }
        firewall_docker_daemon_identity_unchanged() { return 0; }
        docker_with_timeout() {
            case "$*" in
                "context show") printf '%s\n' default ;;
                "context inspect --format {{.Endpoints.docker.Host}} default") printf '%s\n' unix:///var/run/docker.sock ;;
                "info --format {{json .SecurityOptions}}") printf '%s\n' '[]' ;;
                "info --format {{.Swarm.LocalNodeState}}") printf '%s\n' inactive ;;
                "ps -aq") printf '%s\n' stopped-container ;;
                "inspect --format {{.HostConfig.NetworkMode}} stopped-container") printf '%s\n' bridge ;;
                "inspect --format {{.HostConfig.PublishAllPorts}} stopped-container") printf '%s\n' false ;;
                "inspect --format {{range \$port, \$bindings := .HostConfig.PortBindings}}{{range \$bindings}}{{printf \"%s|%s|%s\\n\" \$port .HostIp .HostPort}}{{end}}{{end}} stopped-container")
                    printf '%s\n' '80/tcp|0.0.0.0|8080'
                    ;;
                "inspect --format {{.State.Running}} stopped-container") printf '%s\n' false ;;
                "network ls --format {{.ID}}|{{.Name}}|{{.Driver}}") : ;;
                *)
                    printf 'unexpected docker call: %s\n' "$*" >&2
                    return 1
                    ;;
            esac
        }

        firewall_detect_docker_ports || fail "停止容器的固定映射应能完成检测"
        assert_eq 8080 "$FW_DOCKER_TCP" "固定映射应进入 Docker TCP 端口集合"
        assert_eq 8080 "$FW_DOCKER_PUBLIC4_TCP" "0.0.0.0 固定映射应进入 IPv4 公网端口集合"
        assert_eq 8080 "$FW_DOCKER_PUBLIC_TCP" "停止容器的公网固定映射不得被遗漏"
    )
}

test_additive_config_builder_adds_tcp_without_rebuilding_other_rules() {
    local source="$TEST_TMP/additive-tcp-old.nft"
    local dest="$TEST_TMP/additive-tcp-new.nft"

    FW_ALLOWED_TCP="443,6384,8080"
    FW_ALLOWED_UDP=""
    FW_EXTRA_TCP="8080"
    FW_EXTRA_UDP=""
    FW_DOCKER_PUBLIC4_TCP=""
    FW_DOCKER_PUBLIC4_UDP=""
    FW_DOCKER_PUBLIC6_TCP=""
    FW_DOCKER_PUBLIC6_UDP=""
    FW_DOCKER_PROXY4_TCP=""
    FW_DOCKER_PROXY4_UDP=""
    FW_DOCKER_PROXY6_TCP=""
    FW_DOCKER_PROXY6_UDP=""
    FW_DOCKER_BRIDGES=""
    : "$FW_ALLOWED_TCP" "$FW_ALLOWED_UDP" "$FW_DOCKER_PUBLIC4_UDP" \
        "$FW_DOCKER_PUBLIC6_TCP" "$FW_DOCKER_PUBLIC6_UDP" \
        "$FW_DOCKER_PROXY4_TCP" "$FW_DOCKER_PROXY4_UDP" \
        "$FW_DOCKER_PROXY6_TCP" "$FW_DOCKER_PROXY6_UDP" "$FW_DOCKER_BRIDGES"
    firewall_write_config "$source"
    firewall_config_additive_shape_valid "$source" 8080 "" ||
        fail "受管防火墙配置应满足 TCP 轻量新增前置结构"

    FW_EXTRA_TCP="8080,8443"
    firewall_build_config_with_added_ports "$source" "$dest" tcp

    assert_file_contains "$dest" '^[[:space:]]*tcp dport \{ 443, 6384, 8080, 8443 \} accept$'
    assert_file_contains "$dest" '^[[:space:]]*set extra_tcp_dnat_ports \{$'
    assert_file_contains "$dest" '^[[:space:]]*elements = \{ 8080, 8443 \}$'
    assert_eq 1 "$(grep -Fxc '        meta l4proto tcp ct original proto-dst @extra_tcp_dnat_ports accept' "$dest")" \
        "TCP Docker DNAT 放行规则应恰好一条"
    assert_file_contains "$dest" '^# Managed by vpsbox\.' "轻量更新不得替换其他受管规则"
}

test_additive_config_builder_creates_first_udp_rule_and_set() {
    local source="$TEST_TMP/additive-udp-old.nft"
    local dest="$TEST_TMP/additive-udp-new.nft"

    FW_ALLOWED_TCP="6384"
    FW_ALLOWED_UDP=""
    FW_EXTRA_TCP=""
    FW_EXTRA_UDP=""
    FW_DOCKER_PUBLIC4_TCP=""
    FW_DOCKER_PUBLIC4_UDP=""
    FW_DOCKER_PUBLIC6_TCP=""
    FW_DOCKER_PUBLIC6_UDP=""
    FW_DOCKER_PROXY4_TCP=""
    FW_DOCKER_PROXY4_UDP=""
    FW_DOCKER_PROXY6_TCP=""
    FW_DOCKER_PROXY6_UDP=""
    FW_DOCKER_BRIDGES=""
    : "$FW_ALLOWED_TCP" "$FW_ALLOWED_UDP" "$FW_DOCKER_PUBLIC4_UDP" \
        "$FW_DOCKER_PUBLIC6_TCP" "$FW_DOCKER_PUBLIC6_UDP" \
        "$FW_DOCKER_PROXY4_TCP" "$FW_DOCKER_PROXY4_UDP" \
        "$FW_DOCKER_PROXY6_TCP" "$FW_DOCKER_PROXY6_UDP" "$FW_DOCKER_BRIDGES"
    firewall_write_config "$source"
    firewall_config_additive_shape_valid "$source" "" "" ||
        fail "受管防火墙配置应满足首次 UDP 轻量新增前置结构"

    FW_EXTRA_UDP="5353"
    firewall_build_config_with_added_ports "$source" "$dest" udp

    assert_file_contains "$dest" '^[[:space:]]*udp dport \{ 5353 \} accept$'
    assert_file_contains "$dest" '^[[:space:]]*set extra_udp_dnat_ports \{$'
    assert_file_contains "$dest" '^[[:space:]]*elements = \{ 5353 \}$'
    assert_eq 1 "$(grep -Fxc '        meta l4proto udp ct original proto-dst @extra_udp_dnat_ports accept' "$dest")" \
        "UDP Docker DNAT 放行规则应恰好一条"
}

test_adding_port_uses_lightweight_commit_path() {
    (
        local log="$TEST_TMP/additive-route.log"
        firewall_settle_pending_port_transition() { :; }
        firewall_load_state() { FW_EXTRA_TCP="8080"; FW_EXTRA_UDP=""; }
        firewall_prompt_port() { printf '%s\n' 8443; }
        firewall_control_plane_present() { return 0; }
        firewall_apply_added_ports() {
            printf '%s|%s|%s|%s|%s\n' "$1" "$2" "$3" "$FW_EXTRA_TCP" "$FW_EXTRA_UDP" > "$log"
        }
        firewall_apply_desired_state() { fail "新增端口不得调用完整防火墙更新"; }

        firewall_add_extra_port tcp
        assert_file_contains "$log" '^tcp\|8443\|8080\|8080,8443\|$'
    )
}

test_lightweight_add_does_not_rescan_docker_or_ssh() {
    (
        local case_dir="$TEST_TMP/additive-apply" log="$TEST_TMP/additive-apply.log"
        mkdir -p "$case_dir"
        RUNTIME_DIR="$case_dir/run"
        FIREWALL_CONFIG="$case_dir/firewall.nft"
        FIREWALL_STATE_FILE="$case_dir/firewall.env"
        : > "$FIREWALL_CONFIG"
        : > "$FIREWALL_STATE_FILE"
        : > "$log"
        FW_EXTRA_TCP="8080,8443"
        FW_EXTRA_UDP=""

        firewall_recover_pending_rollbacks() { :; }
        firewall_runtime_enabled() { return 0; }
        firewall_managed_file_is_secure() { return 0; }
        firewall_state_file_is_secure() { return 0; }
        firewall_config_additive_shape_valid() { return 0; }
        prepare_runtime_dir() { mkdir -p "$RUNTIME_DIR"; }
        firewall_build_config_with_added_ports() { printf '%s\n' config > "$2"; }
        firewall_write_state_file() { printf '%s\n' state > "$1"; }
        firewall_check_config_file() { return 0; }
        firewall_config_direct_ports() { printf '%s\n' 6384; }
        firewall_create_rollback_snapshot() {
            printf 'snapshot:%s\n' "$2" >> "$log"
            mkdir -p "$case_dir/snapshot"
            printf -v "$1" '%s' "$case_dir/snapshot"
        }
        firewall_apply_config_file() { printf '%s\n' apply >> "$log"; }
        firewall_live_added_ports_match() { printf '%s\n' verify >> "$log"; }
        firewall_begin_commit() { printf '%s\n' begin >> "$log"; }
        firewall_install_managed_file() { printf '%s\n' install >> "$log"; }
        firewall_finish_commit() { printf '%s\n' finish >> "$log"; }
        firewall_detect_allowed_ports() { fail "轻量新增不得重新扫描 SSH、节点或 Docker"; }

        firewall_apply_added_ports tcp 8443 8080 ""
        assert_file_contains "$log" '^snapshot:6384$'
        assert_file_contains "$log" '^apply$'
        assert_eq 2 "$(grep -Fxc verify "$log")" "运行规则与持久化后都应验证新增端口"
        assert_file_contains "$log" '^begin$'
        assert_eq 2 "$(grep -Fxc install "$log")" "配置与状态应分别原子落盘"
        assert_file_contains "$log" '^finish$'
    )
}

main() {
    local name test status passed=0
    local -a required=(
        normalize_port_decimal
        normalize_port_csv
        is_public_listen_addr
        collect_listening_sockets
        firewall_check_conflicts
        firewall_openrc_service_enabled
        run_bounded_in_new_session
        run_bounded_with_timeout
        firewall_start_rollback_watchdog
        firewall_detect_docker_ports
        firewall_detect_public_listeners
        firewall_detect_allowed_ports
        firewall_build_config_with_added_ports
        firewall_read_live_allowed_ports
        firewall_view_rules
    )
    local -a tests=(
        test_port_decimal_normalization
        test_public_listener_address_classification
        test_listener_sample_collects_expected_public_ports
        test_security_group_suggestions_exclude_dhcp_clients
        test_allowed_ports_merge_known_public_docker_and_extra_sources
        test_stopped_public_service_is_removed_unless_extra
        test_view_rules_reads_live_nft_instead_of_current_listeners
        test_view_rules_inactive_reports_no_live_ports_without_scanning
        test_view_rules_accepts_normalized_forward_priority_expression
        test_view_rules_rejects_unhooked_or_permissive_base_chains
        test_firewall_table_parsers_consume_large_trailing_input
        test_systemd_enabled_inactive_firewalld_conflict
        test_openrc_enabled_inactive_firewalld_conflict
        test_bounded_background_processes_release_lock
        test_timeout_processes_release_lock
        test_busybox_timeout_fallback_releases_lock
        test_watchdog_survives_parent_without_holding_lock
        test_stopped_docker_fixed_binding_is_public
        test_additive_config_builder_adds_tcp_without_rebuilding_other_rules
        test_additive_config_builder_creates_first_udp_rule_and_set
        test_adding_port_uses_lightweight_commit_path
        test_lightweight_add_does_not_rescan_docker_or_ssh
    )

    command -v flock >/dev/null 2>&1 || fail "测试需要 flock"
    for name in "${required[@]}"; do
        require_function "$name"
    done
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
    printf '%s firewall regression tests passed.\n' "$passed"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
