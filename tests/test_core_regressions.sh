#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=tests/test_helper.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/test_helper.sh"

# shellcheck source=../vpsbox.sh
source "$REPO_DIR/vpsbox.sh"

cleanup() {
    rm -rf -- "$TEST_TMP"
}
trap cleanup EXIT

test_address_fallback_validation() {
    local ip
    local -a accepted=(
        "1:2:3:4:5:6:7::"
        "::1:2:3:4:5:6:7"
        "2001:db8::1"
        "::ffff:192.0.2.1"
        "1:2:3:4:5:6:192.0.2.1"
    )
    local -a rejected=(
        "1:2:3:4:5:6:7:8::"
        "1:2:3:4:5:6:7"
        "1::2::3"
        "::ffff:192.168.001.1"
        "01.2.3.4"
        "1.2.3.999"
    )

    for ip in "${accepted[@]}"; do
        is_ipv4_address "$ip" || is_ipv6_address_basic "$ip" ||
            fail "合法地址被回退校验拒绝：$ip"
    done
    for ip in "${rejected[@]}"; do
        if is_ipv4_address "$ip" || is_ipv6_address_basic "$ip"; then
            fail "非法地址被回退校验接受：$ip"
        fi
    done
}

test_blank_node_host_uses_detected_public_ipv4() {
    (
        local domain=""
        local output="$TEST_TMP/node-host-auto.out"
        public_ipv4() { printf '%s\n' 198.51.100.42; }
        node_ipv4_is_assigned_locally() { return 0; }

        prompt_node_host domain "地址：" <<< $'\n' >"$output" 2>&1
        assert_eq "198.51.100.42" "$domain" "留空时应采用自动检测到的公网 IPv4"
        assert_file_contains "$output" '自动检测到公网 IPv4：198\.51\.100\.42'
        assert_file_contains "$output" '已识别节点连接地址：198\.51\.100\.42'
    )
}

test_node_host_detection_failure_falls_back_to_manual_input() {
    (
        local domain=""
        local output="$TEST_TMP/node-host-fallback.out"
        public_ipv4() { return 1; }

        prompt_node_host domain "地址：" <<< $'\nnode.example.com' >"$output" 2>&1
        assert_eq "node.example.com" "$domain" "自动检测失败后应接受手动地址"
        assert_file_contains "$output" '公网 IPv4 自动检测失败，请手动输入节点连接地址。'
    )
}

test_node_host_rejected_detection_falls_back_to_manual_input() {
    (
        local domain=""
        local output="$TEST_TMP/node-host-reject.out"
        public_ipv4() { printf '%s\n' 198.51.100.42; }
        node_ipv4_is_assigned_locally() { return 0; }

        prompt_node_host domain "地址：" <<< $'\nn\nnode.example.com' >"$output" 2>&1
        assert_eq "node.example.com" "$domain" "拒绝自动地址后应接受手动地址"
        assert_file_contains "$output" '请手动输入节点连接地址。'
    )
}

test_node_host_warns_for_possible_nat() {
    (
        local domain=""
        local output="$TEST_TMP/node-host-nat.out"
        public_ipv4() { printf '%s\n' 198.51.100.42; }
        node_ipv4_is_assigned_locally() { return 1; }

        prompt_node_host domain "地址：" <<< $'\n' >"$output" 2>&1
        assert_eq "198.51.100.42" "$domain"
        assert_file_contains "$output" '当前 VPS 可能使用 NAT。'
        assert_file_contains "$output" '将后续节点端口映射到相同端口。'
    )
}

test_uri_write_preserves_existing_on_failure() {
    (
        CONFIG_DIR="$TEST_TMP/uri-config"
        URI_FILE="$CONFIG_DIR/vpsbox-uri.txt"
        mkdir -p "$CONFIG_DIR"
        printf '%s\n' keep > "$URI_FILE"
        secure_config_dir() { return 0; }
        generate_link() { return 42; }

        if write_uri_file; then
            fail "链接生成失败时 write_uri_file 不应成功"
        fi
        assert_file_contains "$URI_FILE" '^keep$' "生成失败不应截断原链接文件"
    )
}

test_node_eof_rolls_back_fresh_install_config() {
    local creator

    for creator in create_or_rebuild_node create_vless_reality_node; do
        (
            CONFIG_DIR="$TEST_TMP/$creator-config"
            CONFIG_PATH="$CONFIG_DIR/config.json"
            URI_FILE="$CONFIG_DIR/vpsbox-uri.txt"
            ACTIVE_NODE_BACKUP=""
            require_valid_node_state_if_present() { return 0; }
            node_exists() { return 1; }
            backup_node_files() { mkdir -p "$1"; }
            install_singbox_if_missing() {
                mkdir -p "$CONFIG_DIR"
                printf '%s\n' package-default > "$CONFIG_PATH"
            }
            rollback_node_files_transaction() {
                local backup="${ACTIVE_NODE_BACKUP:-}"
                ACTIVE_NODE_BACKUP=""
                rm -f -- "$CONFIG_PATH"
                rm -rf -- "$backup"
                printf '%s\n' rolled-back > "$TEST_TMP/$creator.rollback"
            }

            if "$creator" </dev/null >"$TEST_TMP/$creator.out" 2>&1; then
                fail "$creator 在 EOF 取消时应返回失败"
            fi
            [ ! -e "$CONFIG_PATH" ] || fail "$creator 留下了阻塞后续创建的默认配置"
            assert_file_contains "$TEST_TMP/$creator.rollback" '^rolled-back$'
        )
    done
}

test_reality_checks_require_bounded_dns_and_openssl() {
    (
        local log="$TEST_TMP/dns-bounded.log"
        getent() { return 0; }
        run_bounded_command() {
            printf '%s\n' "$*" > "$log"
            return 1
        }
        if resolve_host_ips example.com; then
            fail "有界 DNS 命令失败时解析不应成功"
        fi
        assert_file_contains "$log" '^12 getent ahosts example\.com$'
    )
    (
        resolve_host_ips() { printf '%s\n' 192.0.2.1; }
        command() {
            if [ "${1:-}" = "-v" ] && [ "${2:-}" = "openssl" ]; then
                return 1
            fi
            builtin command "$@"
        }
        if check_reality_server example.com >/dev/null 2>&1; then
            fail "缺少 openssl 时不得把 Reality TLS 检查视为成功"
        fi
    )
}

test_view_node_propagates_uri_failure() {
    (
        require_valid_node_state_if_present() { return 0; }
        node_exists() { return 0; }
        load_state() { return 0; }
        write_uri_file() { return 1; }

        if view_node_link >/dev/null 2>&1; then
            fail "节点链接写入失败时查看功能不应成功"
        fi
    )
}

test_node_state_writes_are_atomic() {
    (
        local old_state="$TEST_TMP/state-atomic/old"
        CONFIG_DIR="$TEST_TMP/state-atomic/config"
        STATE_FILE="$CONFIG_DIR/vpsbox.env"
        mkdir -p "$CONFIG_DIR"
        printf '%s\n' keep-old > "$STATE_FILE"
        secure_config_dir() { return 0; }
        printf() {
            [ "${1:-}" != 'NAME=%s\n' ] || return 42
            builtin printf "$@"
        }

        if save_state example.com node 12345 secret; then
            unset -f printf
            fail "SS 状态中途写入失败时不应报告成功"
        fi
        unset -f printf
        cp "$STATE_FILE" "$old_state"
        assert_file_contains "$old_state" '^keep-old$' "SS 写入失败不得截断旧状态"
        [ -z "$(find "$CONFIG_DIR" -maxdepth 1 -name '.vpsbox-state.*' -print -quit)" ] ||
            fail "SS 写入失败后残留临时状态文件"

        printf '%s\n' keep-vless > "$STATE_FILE"
        printf() {
            [ "${1:-}" != 'UUID=%s\n' ] || return 42
            builtin printf "$@"
        }
        if save_vless_reality_state example.com node 12345 uuid sni key abcdef0123456789; then
            unset -f printf
            fail "VLESS 状态中途写入失败时不应报告成功"
        fi
        unset -f printf
        assert_file_contains "$STATE_FILE" '^keep-vless$' "VLESS 写入失败不得截断旧状态"
        [ -z "$(find "$CONFIG_DIR" -maxdepth 1 -name '.vpsbox-state.*' -print -quit)" ] ||
            fail "VLESS 写入失败后残留临时状态文件"
    )
}

test_service_running_requires_exact_config_process() {
    (
        singbox_installed() { return 0; }
        service_manager_is_active() { return 0; }
        singbox_config_pids() { return 0; }
        if service_is_running; then
            fail "服务管理器 active 但没有配置匹配进程时不得报告运行中"
        fi
        singbox_config_pids() { printf '%s\n' 1234; }
        service_is_running || fail "服务 active 且存在配置匹配进程时应报告运行中"
    )
}

test_service_restore_checks_final_state() {
    (
        service_disable() { return 23; }
        service_is_enabled() { return 1; }
        service_stop() { return 23; }
        service_manager_is_active() { return 1; }
        stop_singbox_config_processes() { return 0; }
        singbox_config_pids() { return 0; }

        restore_singbox_service_state 0 0 ||
            fail "服务命令报错但禁用/停止目标状态已满足时应允许恢复完成"

        service_start() { return 0; }
        service_is_running() { return 1; }
        service_stop() { return 0; }
        if restart_singbox_cleanly; then
            fail "服务启动命令成功但实际进程未运行时不得报告重启成功"
        fi
    )
}

test_test_mode_blocks_real_service_mutation() {
    if service_start >"$TEST_TMP/service-guard.out" 2>&1; then
        fail "测试模式不得调用真实服务启动命令"
    fi
    assert_file_contains "$TEST_TMP/service-guard.out" '测试模式禁止调用真实服务管理命令'
}

test_protocol_specific_listener_checks() {
    (
        local tcp_ready=1 udp_ready=0
        ss() {
            case "$*" in
                '-H -ltn') [ "$tcp_ready" -eq 1 ] && printf '%s\n' 'LISTEN 0 4096 0.0.0.0:43333 0.0.0.0:*' ;;
                '-H -lun') [ "$udp_ready" -eq 1 ] && printf '%s\n' 'UNCONN 0 0 0.0.0.0:43333 0.0.0.0:*' ;;
            esac
        }

        port_listener_ready 43333 tcp || fail "VLESS 的 TCP 监听应被识别"
        if port_listener_ready 43333 both; then
            fail "SS 只有 TCP、缺少 UDP 时不得通过监听检查"
        fi
        if port_conflicts_with_existing_node 43333 both tcp; then
            fail "VLESS 切换到 SS 时，旧节点占用的 TCP 不应被误判为外部冲突"
        fi
        udp_ready=1
        port_listener_ready 43333 both || fail "SS 的 TCP 与 UDP 都监听时应通过"
        port_conflicts_with_existing_node 43333 both tcp ||
            fail "VLESS 切换到 SS 时应识别额外的 UDP 端口冲突"
        if port_conflicts_with_existing_node 43333 tcp both; then
            fail "SS 切换到 VLESS 时，旧节点已有的 TCP 监听可以复用"
        fi
    )
}

test_install_self_reports_download_failure() {
    (
        CMD_PATH="$TEST_TMP/install-self/bin/vpsbox"
        download_vpsbox_script() { return 23; }
        if install_self_command /dev/fd/63 >"$TEST_TMP/install-self.out" 2>&1; then
            fail "进程替换首次安装下载失败时必须返回非零"
        fi
        [ ! -e "$CMD_PATH" ] || fail "下载失败不应留下管理命令"
    )
}

test_interrupted_singbox_update_rolls_back() {
    (
        local case_dir="$TEST_TMP/singbox-interrupt"
        local binary="$case_dir/sing-box" backup_dir="$case_dir/update" backup="$case_dir/update/sing-box"
        mkdir -p "$backup_dir"
        printf '%s\n' old-binary > "$binary"
        cp "$binary" "$backup"
        service_stop() { return 0; }
        service_manager_is_active() { return 1; }
        stop_singbox_config_processes() { return 0; }
        node_exists() { return 1; }
        restore_singbox_service_state() { printf '%s %s\n' "$1" "$2" > "$case_dir/service-state"; }
        cleanup_vpsbox_lock() { return 0; }

        begin_singbox_update_transaction "$binary" "$backup" "$backup_dir" 1 1
        # 由已 source 的 cleanup_vpsbox_runtime 间接读取。
        # shellcheck disable=SC2034
        ACTIVE_SINGBOX_UPDATE_MUTATED=1
        printf '%s\n' partial-new-binary > "$binary"
        cleanup_vpsbox_runtime

        assert_file_contains "$binary" '^old-binary$' "更新中断后应恢复旧二进制"
        assert_file_contains "$case_dir/service-state" '^1 1$' "更新中断后应恢复原服务状态"
        assert_eq "" "$ACTIVE_SINGBOX_UPDATE_DIR" "回滚后必须清空活动更新事务"
    )
}

test_lockdir_metadata_window_is_waited() {
    (
        LOCK_DIR="$TEST_TMP/lock-window/lockdir"
        mkdir -p "$LOCK_DIR"
        (sleep 0.2; printf '%s\n' 'pid=4242' > "$LOCK_DIR/pid") &
        wait_for_lockdir_metadata || fail "锁目录创建后应等待并发持有者写入元数据"
        assert_eq 4242 "$(lock_pid_from_file "$LOCK_DIR/pid")"
        wait
    )
}

test_same_second_timestamp_is_not_after() {
    if timestamp_strictly_after 100 100; then
        fail "同秒 Docker 配置时间不得误判为启动后修改"
    fi
    timestamp_strictly_after 101 100 || fail "严格更晚的配置时间应被识别"
}

test_singbox_dependency_failure_does_not_touch_service() {
    (
        local fake_bin="$TEST_TMP/singbox-deps-bin"
        local event_log="$TEST_TMP/singbox-deps-events"
        local update_backup="$TEST_TMP/singbox-deps-backup"
        mkdir -p "$fake_bin"
        printf '%s\n' old-binary > "$fake_bin/sing-box"
        chmod 755 "$fake_bin/sing-box"
        PATH="$fake_bin:$PATH"
        : > "$event_log"

        singbox_installed() { return 0; }
        singbox_version() { printf '%s\n' 1.13.13; }
        singbox_binary_is_package_managed() { return 0; }
        service_is_running() { return 0; }
        service_is_enabled() { return 0; }
        install_deps() {
            printf '%s\n' deps >> "$event_log"
            return 23
        }
        run_singbox_installer() { printf '%s\n' installer >> "$event_log"; }
        restore_singbox_update_backup() { printf '%s\n' restore >> "$event_log"; }
        mktemp() {
            if [ "${1:-}" = "-d" ] && [[ "${2:-}" == /tmp/vpsbox-sing-box-update.* ]]; then
                mkdir -p "$update_backup"
                printf '%s\n' "$update_backup"
            else
                command mktemp "$@"
            fi
        }

        if update_singbox >"$TEST_TMP/singbox-deps.out" 2>&1; then
            fail "依赖准备失败时 update_singbox 应返回失败"
        fi
        assert_file_contains "$fake_bin/sing-box" '^old-binary$'
        assert_file_contains "$event_log" '^deps$'
        assert_file_not_contains "$event_log" '^(installer|restore)$'
        [ ! -e "$update_backup" ] || fail "未修改二进制时不应保留无用更新备份"
    )
}

test_failed_singbox_update_restores_binary_and_state() {
    (
        local fake_bin="$TEST_TMP/singbox-bin"
        local output="$TEST_TMP/singbox-update.out"
        local update_backup="$TEST_TMP/singbox-update-backup"
        mkdir -p "$fake_bin"
        printf '%s\n' old-binary > "$fake_bin/sing-box"
        chmod 755 "$fake_bin/sing-box"
        PATH="$fake_bin:$PATH"

        singbox_installed() { return 0; }
        singbox_version() { printf '%s\n' 1.13.13; }
        singbox_binary_is_package_managed() { return 0; }
        service_is_running() { return 0; }
        service_is_enabled() { return 0; }
        node_exists() { return 1; }
        install_deps() { return 0; }
        prepare_singbox_rollback_package() {
            local package="$2/sing-box-old.pkg"
            : > "$package"
            printf '%s\n' "$package"
        }
        install_singbox_package_file() {
            cp "$update_backup/sing-box" "$fake_bin/sing-box"
        }
        run_singbox_installer() {
            printf '%s\n' broken-new-binary > "$fake_bin/sing-box"
            return 1
        }
        service_stop() { return 0; }
        stop_singbox_config_processes() { return 0; }
        setup_service() { return 0; }
        restore_singbox_service_state() {
            printf '%s %s\n' "$1" "$2" > "$TEST_TMP/restored-service-state"
        }
        mktemp() {
            if [ "${1:-}" = "-d" ] && [[ "${2:-}" == /tmp/vpsbox-sing-box-update.* ]]; then
                mkdir -p "$update_backup"
                printf '%s\n' "$update_backup"
            else
                command mktemp "$@"
            fi
        }

        if update_singbox >"$output" 2>&1; then
            fail "安装器失败时 update_singbox 应返回失败"
        fi
        assert_file_contains "$fake_bin/sing-box" '^old-binary$'
        assert_file_contains "$TEST_TMP/restored-service-state" '^1 1$'
        [ -f "$update_backup/sing-box" ] || fail "更新失败后应保留旧二进制备份"
    )
}

test_external_singbox_update_is_rejected_before_mutation() {
    (
        local fake_bin="$TEST_TMP/singbox-external-bin"
        local event_log="$TEST_TMP/singbox-external-events"
        mkdir -p "$fake_bin"
        printf '%s\n' external-binary > "$fake_bin/sing-box"
        chmod 755 "$fake_bin/sing-box"
        PATH="$fake_bin:$PATH"
        : > "$event_log"

        singbox_installed() { return 0; }
        singbox_version() { printf '%s\n' 1.13.13; }
        singbox_binary_is_package_managed() { return 1; }
        install_deps() { printf '%s\n' deps >> "$event_log"; }
        run_singbox_installer() { printf '%s\n' installer >> "$event_log"; }

        if update_singbox >"$TEST_TMP/singbox-external.out" 2>&1; then
            fail "非软件包管理的 sing-box 应拒绝自动更新"
        fi
        assert_file_contains "$fake_bin/sing-box" '^external-binary$'
        assert_empty_file "$event_log" "拒绝外部安装时不得准备依赖或运行安装器"
        assert_file_contains "$TEST_TMP/singbox-external.out" '不是由系统 sing-box 软件包管理'
    )
}

main() {
    local test status passed=0
    local -a tests=(
        test_address_fallback_validation
        test_blank_node_host_uses_detected_public_ipv4
        test_node_host_detection_failure_falls_back_to_manual_input
        test_node_host_rejected_detection_falls_back_to_manual_input
        test_node_host_warns_for_possible_nat
        test_uri_write_preserves_existing_on_failure
        test_node_eof_rolls_back_fresh_install_config
        test_reality_checks_require_bounded_dns_and_openssl
        test_view_node_propagates_uri_failure
        test_node_state_writes_are_atomic
        test_service_running_requires_exact_config_process
        test_service_restore_checks_final_state
        test_test_mode_blocks_real_service_mutation
        test_protocol_specific_listener_checks
        test_install_self_reports_download_failure
        test_interrupted_singbox_update_rolls_back
        test_lockdir_metadata_window_is_waited
        test_same_second_timestamp_is_not_after
        test_singbox_dependency_failure_does_not_touch_service
        test_failed_singbox_update_restores_binary_and_state
        test_external_singbox_update_is_rejected_before_mutation
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
    printf '%s core regression tests passed.\n' "$passed"
}

main "$@"
