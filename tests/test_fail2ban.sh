#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=tests/test_helper.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/test_helper.sh"

# vpsbox.sh 通过直接执行保护后可以安全加载；测试只覆盖函数，不运行主菜单。
# shellcheck disable=SC1091
source "$REPO_DIR/vpsbox.sh"

MOCK_CALL_LOG="$TEST_TMP/fail2ban-calls.log"
MOCK_JAIL_STATE="$TEST_TMP/fail2ban-jail.state"
MOCK_BACKEND_STATE="$TEST_TMP/fail2ban-backend.state"
MOCK_ACTION_NAME="nftables-multiport"
MOCK_ACTIONBAN="/usr/sbin/nft add element inet f2b-table addr-set-sshd { <ip> }"
MOCK_BAN_MODE="normal"
MOCK_UNBAN_FAIL=0

test_cleanup() {
    if [ "${KEEP_TEST_TMP:-0}" = "1" ]; then
        printf '保留测试临时目录：%s\n' "$TEST_TMP" >&2
    else
        rm -rf -- "$TEST_TMP"
    fi
}
trap test_cleanup EXIT

reset_mock() {
    : > "$MOCK_CALL_LOG"
    : > "$MOCK_JAIL_STATE"
    : > "$MOCK_BACKEND_STATE"
    MOCK_ACTION_NAME="nftables-multiport"
    MOCK_ACTIONBAN="/usr/sbin/nft add element inet f2b-table addr-set-sshd { <ip> }"
    MOCK_BAN_MODE="normal"
    MOCK_UNBAN_FAIL=0
    ACTIVE_FAIL2BAN_TEST_IP=""
    # Read by the production cleanup function through shared global state.
    # shellcheck disable=SC2034
    ACTIVE_FAIL2BAN_TEST_BACKENDS=""
}

remove_mock_ip() {
    local file="$1" ip="$2" tmp
    tmp="${file}.tmp"
    grep -Fvx -- "$ip" "$file" > "$tmp" || true
    mv -f -- "$tmp" "$file"
}

fail2ban-client() {
    printf '%s\n' "$*" >> "$MOCK_CALL_LOG"

    if [ "${1:-}" = "-t" ]; then
        return 0
    fi
    case "${1:-} ${2:-} ${3:-}" in
        "get sshd actions")
            printf 'The jail sshd has the following actions:\n%s\n' "$MOCK_ACTION_NAME"
            ;;
        "get sshd action")
            [ "${5:-}" = "actionban" ] || return 2
            printf '%s\n' "$MOCK_ACTIONBAN"
            ;;
        "get sshd banip")
            tr '\n' ' ' < "$MOCK_JAIL_STATE"
            printf '\n'
            ;;
        "set sshd banip")
            local ip="${4:-}"
            [ -n "$ip" ] || return 2
            [ "$MOCK_BAN_MODE" != "command-fails" ] || return 1
            printf '%s\n' "$ip" >> "$MOCK_JAIL_STATE"
            if [ "$MOCK_BAN_MODE" = "normal" ]; then
                printf '%s\n' "$ip" >> "$MOCK_BACKEND_STATE"
            fi
            printf '1\n'
            ;;
        "set sshd unbanip")
            local ip="${4:-}"
            [ -n "$ip" ] || return 2
            [ "$MOCK_UNBAN_FAIL" -eq 0 ] || return 1
            remove_mock_ip "$MOCK_JAIL_STATE" "$ip"
            remove_mock_ip "$MOCK_BACKEND_STATE" "$ip"
            printf '1\n'
            ;;
        "status sshd ")
            return 0
            ;;
        *)
            return 2
            ;;
    esac
}

nft() {
    if [[ " $* " != *" list ruleset "* ]]; then
        return 2
    fi

    printf 'table inet f2b-table {\n'
    printf '  set addr-set-sshd { type ipv4_addr; elements = { '
    paste -sd ', ' "$MOCK_BACKEND_STATE"
    printf ' } }\n}\n'
}

iptables-save() {
    cat "$MOCK_BACKEND_STATE"
}

ipset() {
    [ "${1:-}" = "save" ] || return 2
    cat "$MOCK_BACKEND_STATE"
}

ufw() {
    [ "${1:-} ${2:-}" = "show raw" ] || return 2
    cat "$MOCK_BACKEND_STATE"
}

firewall-cmd() {
    case "$*" in
        "--direct --get-all-rules") cat "$MOCK_BACKEND_STATE" ;;
        "--list-all-zones"|"--get-ipsets") return 0 ;;
        *) return 2 ;;
    esac
}

# 重试等待在本地 mock 中无需真实耗时。
sleep() {
    :
}

test_action_parser() {
    local -a actions=()
    reset_mock
    mapfile -t actions < <(fail2ban_action_names)
    assert_eq "1" "${#actions[@]}" "应只解析实际 action 名称"
    assert_eq "nftables-multiport" "${actions[0]}" "action 名称解析错误"
}

test_exact_ipv4_match() {
    fail2ban_ipv4_in_text '192.0.2.1' 'elements = { 192.0.2.10 }' &&
        fail "精确匹配不得把 192.0.2.10 识别为 192.0.2.1"
    fail2ban_ipv4_in_text '192.0.2.1' 'elements = { 192.0.2.1/24 }' &&
        fail "精确匹配不得把网段识别为单个测试地址"
    fail2ban_ipv4_in_text '192.0.2.1' 'elements = { 192.0.2.1/32 }' ||
        fail "精确匹配应识别带 /32 的 IPv4"
}

test_supported_backend_snapshots() {
    local backend
    reset_mock
    printf 'rule contains 192.0.2.254/32\n' > "$MOCK_BACKEND_STATE"

    for backend in nftables iptables ipset ufw firewalld; do
        fail2ban_backend_has_ip "$backend" 192.0.2.254 ||
            fail "$backend 后端快照应能找到精确测试地址"
    done
}

assert_action_round_trip() {
    local label="$1" action="$2" actionban="$3" output

    output="$TEST_TMP/action-$label.out"

    reset_mock
    MOCK_ACTION_NAME="$action"
    MOCK_ACTIONBAN="$actionban"
    if ! verify_fail2ban_real_ban > "$output" 2>&1; then
        sed -n '1,120p' "$output" >&2
        fail "$label 官方防火墙动作应完成封禁往返验证"
    fi
    assert_empty_file "$MOCK_JAIL_STATE" "$label 验证后 jail 不应有残留"
    assert_empty_file "$MOCK_BACKEND_STATE" "$label 验证后后端不应有残留"
}

test_supported_action_round_trips() {
    assert_action_round_trip iptables iptables-multiport \
        '/usr/sbin/iptables -w -I f2b-sshd 1 -s <ip> -j REJECT'
    assert_action_round_trip ipset iptables-ipset-proto4 \
        'ipset --test f2b-sshd <ip> || ipset --add f2b-sshd <ip>'
    assert_action_round_trip ufw ufw \
        $'if [ -n "" ] && ufw app info ""\nthen\n  ufw prepend reject from <ip> to any comment "by Fail2Ban"\nelse\n  ufw prepend reject from <ip> to any comment "by Fail2Ban"\nfi'
    assert_action_round_trip firewalld firewallcmd-multiport \
        'firewall-cmd --direct --add-rule ipv4 filter f2b-sshd 0 -s <ip> -j REJECT'
}

test_successful_real_ban_round_trip() {
    local output="$TEST_TMP/success.out"
    reset_mock

    if ! verify_fail2ban_real_ban > "$output" 2>&1; then
        sed -n '1,120p' "$output" >&2
        fail "真实封禁验证的成功路径不应失败"
    fi

    assert_file_contains "$MOCK_CALL_LOG" \
        '^set sshd banip (192\.0\.2\.|198\.51\.100\.|203\.0\.113\.)' \
        "应使用 TEST-NET IPv4 执行手动封禁"
    assert_file_contains "$MOCK_CALL_LOG" '^set sshd unbanip ' "验证后必须解封测试地址"
    assert_empty_file "$MOCK_JAIL_STATE" "验证后 jail 内不应残留测试地址"
    assert_empty_file "$MOCK_BACKEND_STATE" "验证后 nftables 内不应残留测试地址"
    assert_eq "" "$ACTIVE_FAIL2BAN_TEST_IP" "成功清理后应清空活动测试 IP"
}

test_unknown_action_is_rejected_before_ban() {
    local output="$TEST_TMP/unknown-action.out"
    reset_mock
    MOCK_ACTION_NAME="sendmail-whois"
    MOCK_ACTIONBAN="printf '%s' '<ip>' | /usr/sbin/sendmail root"

    if verify_fail2ban_real_ban > "$output" 2>&1; then
        fail "含未知或外部副作用 action 时必须拒绝测试"
    fi

    assert_file_not_contains "$MOCK_CALL_LOG" '^set sshd banip ' \
        "拒绝未知 action 后不得执行手动封禁"
    assert_empty_file "$MOCK_JAIL_STATE"
    assert_empty_file "$MOCK_BACKEND_STATE"
}

test_missing_backend_rule_is_cleaned() {
    local output="$TEST_TMP/missing-backend.out"
    reset_mock
    MOCK_BAN_MODE="jail-only"

    if verify_fail2ban_real_ban > "$output" 2>&1; then
        fail "jail 已记录但真实防火墙未落地时必须报失败"
    fi

    assert_file_contains "$MOCK_CALL_LOG" '^set sshd unbanip ' \
        "部分封禁失败后仍必须尝试解封"
    assert_empty_file "$MOCK_JAIL_STATE" "失败清理后 jail 内不应残留测试地址"
    assert_empty_file "$MOCK_BACKEND_STATE" "失败清理后防火墙内不应残留测试地址"
    assert_eq "" "$ACTIVE_FAIL2BAN_TEST_IP" "清理完成后应清空活动测试 IP"
}

test_cleanup_keeps_residual_state_visible() {
    local output="$TEST_TMP/unban-failure.out" residual_ip status
    reset_mock
    MOCK_UNBAN_FAIL=1

    if verify_fail2ban_real_ban > "$output" 2>&1; then
        fail "无法解封测试地址时验证必须报失败"
    else
        status=$?
    fi

    assert_eq "2" "$status" "存在残留时应返回专用状态码"
    residual_ip="$ACTIVE_FAIL2BAN_TEST_IP"
    [ -n "$residual_ip" ] || fail "解封失败后必须保留活动测试 IP 供再次清理"
    assert_file_contains "$MOCK_JAIL_STATE" "^${residual_ip//./\\.}$" \
        "解封失败场景应能观察到 jail 残留"

    MOCK_UNBAN_FAIL=0
    cleanup_active_fail2ban_test > /dev/null 2>&1 || fail "恢复后再次清理应成功"
    assert_empty_file "$MOCK_JAIL_STATE"
    assert_empty_file "$MOCK_BACKEND_STATE"
    assert_eq "" "$ACTIVE_FAIL2BAN_TEST_IP" "再次清理成功后应清空活动测试 IP"
}

test_runtime_cleanup_reuses_active_unban() {
    reset_mock
    printf '198.51.100.254\n' > "$MOCK_JAIL_STATE"
    printf '198.51.100.254\n' > "$MOCK_BACKEND_STATE"
    ACTIVE_FAIL2BAN_TEST_IP="198.51.100.254"
    ACTIVE_FAIL2BAN_TEST_BACKENDS="nftables"

    cleanup_vpsbox_runtime > /dev/null 2>&1 || fail "全局运行时清理应复用 Fail2ban 解封"
    assert_empty_file "$MOCK_JAIL_STATE"
    assert_empty_file "$MOCK_BACKEND_STATE"
    assert_eq "" "$ACTIVE_FAIL2BAN_TEST_IP"
}

test_stale_active_test_blocks_new_ban() {
    local status old_ip="203.0.113.253"
    reset_mock
    printf '%s\n' "$old_ip" > "$MOCK_JAIL_STATE"
    printf '%s\n' "$old_ip" > "$MOCK_BACKEND_STATE"
    ACTIVE_FAIL2BAN_TEST_IP="$old_ip"
    ACTIVE_FAIL2BAN_TEST_BACKENDS="nftables"
    MOCK_UNBAN_FAIL=1

    if verify_fail2ban_real_ban > "$TEST_TMP/stale-active.out" 2>&1; then
        fail "旧测试地址未清理时不得启动新验证"
    else
        status=$?
    fi
    assert_eq "2" "$status"
    assert_eq "$old_ip" "$ACTIVE_FAIL2BAN_TEST_IP" "不得覆盖旧的活动测试地址"
    assert_file_not_contains "$MOCK_CALL_LOG" '^set sshd banip ' "不得封禁新的测试地址"

    MOCK_UNBAN_FAIL=0
    cleanup_active_fail2ban_test >/dev/null 2>&1 || fail "测试收尾应能清理旧地址"
}

test_sync_validation_failure_rolls_back() {
    local sync_dir="$TEST_TMP/sync-rollback" systemctl_log="$TEST_TMP/systemctl.log"
    reset_mock
    mkdir -p "$sync_dir"
    FAIL2BAN_CONFIG_DIR="$sync_dir"
    FAIL2BAN_VPSBOX_SSHD_CONF="$sync_dir/99-vpsbox-sshd.local"
    printf 'old-config\n' > "$FAIL2BAN_VPSBOX_SSHD_CONF"
    : > "$systemctl_log"
    MOCK_ACTION_NAME="sendmail-whois"
    MOCK_ACTIONBAN="/usr/sbin/sendmail root"

    fail2ban_installed() { return 0; }
    fail2ban_service_state() { printf '运行中\n'; }
    fail2ban_service_is_enabled() { return 0; }
    manifest_set_once() { return 0; }
    backup_change_file_once() { return 0; }
    begin_change_transaction() { return 0; }
    ssh_effective_ports_csv() { printf '6384\n'; }
    is_systemd() { return 0; }
    systemctl() { printf '%s\n' "$*" >> "$systemctl_log"; }
    mark_change_applied() { printf 'marked\n' >> "$systemctl_log"; }

    if sync_fail2ban_sshd_port > "$TEST_TMP/sync-rollback.out" 2>&1; then
        fail "真实封禁验证失败时同步必须报失败"
    fi
    assert_file_contains "$FAIL2BAN_VPSBOX_SSHD_CONF" '^old-config$' "应恢复同步前配置"
    assert_file_contains "$systemctl_log" '^restart fail2ban$' "应按原运行状态重启旧配置"
    assert_file_not_contains "$systemctl_log" '^marked$' "验证失败不得标记变更已应用"
}

test_sync_restores_initial_stopped_state() {
    local sync_dir="$TEST_TMP/sync-stopped" systemctl_log="$TEST_TMP/systemctl-stopped.log"
    local running=0
    reset_mock
    mkdir -p "$sync_dir"
    FAIL2BAN_CONFIG_DIR="$sync_dir"
    FAIL2BAN_VPSBOX_SSHD_CONF="$sync_dir/99-vpsbox-sshd.local"
    : > "$systemctl_log"

    fail2ban_installed() { return 0; }
    fail2ban_service_state() { [ "$running" -eq 1 ] && printf '运行中\n' || printf '未运行\n'; }
    fail2ban_service_is_enabled() { return 1; }
    manifest_set_once() { return 0; }
    backup_change_file_once() { return 0; }
    begin_change_transaction() { return 0; }
    ssh_effective_ports_csv() { printf '2222\n'; }
    is_systemd() { return 0; }
    systemctl() {
        printf '%s\n' "$*" >> "$systemctl_log"
        case "${1:-}" in
            start|restart) running=1 ;;
            stop) running=0 ;;
        esac
    }
    mark_change_applied() { printf 'marked\n' >> "$systemctl_log"; }

    sync_fail2ban_sshd_port > "$TEST_TMP/sync-stopped.out" 2>&1 ||
        fail "原本停止的 Fail2ban 应能临时验证并恢复停止状态"
    assert_file_contains "$systemctl_log" '^start fail2ban$' "验证前应临时启动 Fail2ban"
    assert_file_contains "$systemctl_log" '^stop fail2ban$' "验证后应恢复原停止状态"
    assert_file_contains "$systemctl_log" '^marked$'
    assert_eq 0 "$running" "同步后不得把原本停止的 Fail2ban 留在运行状态"
}

test_fail2ban_backup_rotation_keeps_five() {
    local dir="$TEST_TMP/fail2ban-backups" i count
    mkdir -p "$dir"
    FAIL2BAN_VPSBOX_SSHD_CONF="$dir/99-vpsbox-sshd.local"
    for i in {1..8}; do
        printf '%s\n' "$i" > "${FAIL2BAN_VPSBOX_SSHD_CONF}.bak.2026010100000${i}"
    done

    prune_fail2ban_sshd_backups
    count="$(find "$dir" -maxdepth 1 -type f -name '*.bak.*' | wc -l | tr -d ' ')"
    assert_eq 5 "$count" "Fail2ban 历史备份应只保留最近 5 份"
    [ ! -e "${FAIL2BAN_VPSBOX_SSHD_CONF}.bak.20260101000001" ] || fail "最旧备份未删除"
    [ -e "${FAIL2BAN_VPSBOX_SSHD_CONF}.bak.20260101000008" ] || fail "最新备份不应删除"
}

main() {
    local -a required=(
        fail2ban_action_names
        fail2ban_ipv4_in_text
        verify_fail2ban_real_ban
        cleanup_active_fail2ban_test
    )
    local name test status passed=0
    local -a tests=(
        test_action_parser
        test_exact_ipv4_match
        test_supported_backend_snapshots
        test_supported_action_round_trips
        test_successful_real_ban_round_trip
        test_unknown_action_is_rejected_before_ban
        test_missing_backend_rule_is_cleaned
        test_cleanup_keeps_residual_state_visible
        test_runtime_cleanup_reuses_active_unban
        test_stale_active_test_blocks_new_ban
        test_sync_validation_failure_rolls_back
        test_sync_restores_initial_stopped_state
        test_fail2ban_backup_rotation_keeps_five
    )

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

    printf '%s Fail2Ban mock tests passed.\n' "$passed"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
