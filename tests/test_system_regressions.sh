#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=tests/test_helper.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/test_helper.sh"

# shellcheck source=../vpsbox.sh
source "$REPO_DIR/vpsbox.sh"

test_cleanup() {
    rm -rf -- "$TEST_TMP"
}
trap test_cleanup EXIT

chown() { :; }

reset_change_store() {
    local name="$1"

    VPSBOX_STATE_DIR="$TEST_TMP/$name/state"
    CHANGE_MANIFEST="$VPSBOX_STATE_DIR/changes.env"
    CHANGE_BACKUP_DIR="$VPSBOX_STATE_DIR/backups"
    mkdir -p "$CHANGE_BACKUP_DIR"
    : > "$CHANGE_MANIFEST"
}

test_manifest_failure_preserves_existing_file() {
    reset_change_store manifest
    printf 'EXISTING=keep\n' > "$CHANGE_MANIFEST"
    awk() { return 42; }

    if manifest_set NEW value; then
        fail "awk 失败时 manifest_set 不应成功"
    fi
    assert_file_contains "$CHANGE_MANIFEST" '^EXISTING=keep$'
    assert_file_not_contains "$CHANGE_MANIFEST" '^NEW='
}

test_manifest_round_trips_ssh_port_csv() {
    reset_change_store manifest-port-csv

    manifest_set SSH_PORTS "22,2222"

    assert_eq "22,2222" "$(manifest_value SSH_PORTS)" \
        "变更清单应安全保存规范化的 SSH 多端口 CSV"
}

test_clear_change_tracking_reports_partial_failure() {
    local log="$TEST_TMP/clear-tracking.log"

    reset_change_store clear-tracking
    : > "$CHANGE_BACKUP_DIR/TEST"
    manifest_remove() {
        printf '%s\n' "$1" >> "$log"
        [ "$1" != "BACKUP_TEST" ]
    }

    if clear_change_tracking TEST; then
        fail "任一清理步骤失败时 clear_change_tracking 不应报告成功"
    fi
    assert_file_contains "$log" '^BACKUP_TEST$'
    assert_file_contains "$log" '^APPLIED_TEST$'
    [ ! -e "$CHANGE_BACKUP_DIR/TEST" ] || fail "可清理的备份文件仍应删除"
}

test_restore_replaces_target_symlink() {
    local target victim

    reset_change_store symlink
    target="$TEST_TMP/symlink/target"
    victim="$TEST_TMP/symlink/victim"
    printf 'original\n' > "$target"
    backup_change_file_once TEST_FILE "$target"
    printf 'victim\n' > "$victim"
    rm -f "$target"
    ln -s "$victim" "$target"

    restore_change_file TEST_FILE "$target"
    [ -f "$target" ] && [ ! -L "$target" ] || fail "恢复后目标应为普通文件"
    assert_file_contains "$target" '^original$'
    assert_file_contains "$victim" '^victim$' "不得覆盖符号链接指向的文件"
}

test_atomic_snapshot_restore_replaces_target_symlink() {
    local source target victim

    source="$TEST_TMP/atomic-restore/source"
    target="$TEST_TMP/atomic-restore/target"
    victim="$TEST_TMP/atomic-restore/victim"
    mkdir -p "$(dirname "$source")"
    printf 'snapshot\n' > "$source"
    printf 'victim\n' > "$victim"
    ln -s "$victim" "$target"

    restore_file_atomically_from_snapshot "$source" "$target"

    [ -f "$target" ] && [ ! -L "$target" ] ||
        fail "原子恢复后目标应为普通文件"
    assert_file_contains "$target" '^snapshot$'
    assert_file_contains "$victim" '^victim$' "不得写入原符号链接指向的文件"
}

test_atomic_snapshot_restore_rejects_directory_symlink() {
    local source target victim

    source="$TEST_TMP/atomic-restore-dir/source"
    target="$TEST_TMP/atomic-restore-dir/target"
    victim="$TEST_TMP/atomic-restore-dir/victim"
    mkdir -p "$(dirname "$source")" "$victim"
    printf 'snapshot\n' > "$source"
    ln -s "$victim" "$target"

    if restore_file_atomically_from_snapshot "$source" "$target"; then
        fail "指向目录的目标符号链接不得被当作恢复目录"
    fi
    [ -L "$target" ] || fail "拒绝恢复后应保留原目标符号链接"
    [ -z "$(find "$victim" -mindepth 1 -maxdepth 1 -print -quit)" ] ||
        fail "不得向符号链接指向的目录写入任何文件"
}

test_atomic_snapshot_restore_replaces_dangling_symlink() {
    local source target missing

    source="$TEST_TMP/atomic-restore-dangling/source"
    target="$TEST_TMP/atomic-restore-dangling/target"
    missing="$TEST_TMP/atomic-restore-dangling/missing"
    mkdir -p "$(dirname "$source")"
    printf 'snapshot\n' > "$source"
    ln -s "$missing" "$target"

    restore_file_atomically_from_snapshot "$source" "$target"

    [ -f "$target" ] && [ ! -L "$target" ] ||
        fail "原子恢复应安全替换悬空符号链接"
    assert_file_contains "$target" '^snapshot$'
    [ ! -e "$missing" ] || fail "不得创建悬空链接原本指向的文件"
}

test_atomic_snapshot_restore_move_failure_preserves_target() {
    (
        local source target

        source="$TEST_TMP/atomic-restore-move-failure/source"
        target="$TEST_TMP/atomic-restore-move-failure/target"
        mkdir -p "$(dirname "$source")"
        printf 'snapshot\n' > "$source"
        printf 'current\n' > "$target"
        mv() { return 1; }

        if restore_file_atomically_from_snapshot "$source" "$target"; then
            fail "最终替换失败时原子恢复不得报告成功"
        fi
        assert_file_contains "$target" '^current$' "最终替换失败时应保留原目标文件"
        [ -z "$(find "$(dirname "$target")" -maxdepth 1 -name '.vpsbox-restore.*' -print -quit)" ] ||
            fail "最终替换失败后应清理临时恢复文件"
    )
}

test_debian_update_stops_after_first_failure() {
    local log="$TEST_TMP/debian-update.log"

    detect_os() { OS=debian; }
    apt_get_bounded() {
        printf '%s\n' "$*" >> "$log"
        return 23
    }
    reboot_required_state() { printf '不需要\n'; }

    if update_system_packages <<< "y" >/dev/null 2>&1; then
        fail "apt update 失败时系统更新不应成功"
    fi
    assert_eq 1 "$(wc -l < "$log" | tr -d ' ')" "失败后不得继续 upgrade/autoremove"
    assert_file_contains "$log" ' update$'
}

test_debian_update_uses_upgrade_timeout() {
    local log="$TEST_TMP/debian-update-success.log"

    detect_os() { OS=debian; }
    apt_get_bounded() { printf '%s\n' "$*" >> "$log"; }
    reboot_required_state() { printf '不需要\n'; }

    update_system_packages <<< "y" >/dev/null
    assert_file_contains "$log" "^${PACKAGE_UPDATE_TIMEOUT} update$"
    assert_file_contains "$log" "^${SYSTEM_UPGRADE_TIMEOUT} upgrade -y$"
    assert_file_contains "$log" "^${SYSTEM_UPGRADE_TIMEOUT} autoremove -y$"
    assert_eq 3 "$(wc -l < "$log" | tr -d ' ')" "Debian 更新应依次执行三个有界步骤"
    [ "$SYSTEM_UPGRADE_TIMEOUT" -ge 3600 ] ||
        fail "完整系统升级的上限不应沿用短安装超时"
}

test_debian_upgrade_failure_skips_autoremove() {
    local log="$TEST_TMP/debian-upgrade-failure.log"

    detect_os() { OS=debian; }
    apt_get_bounded() {
        printf '%s\n' "$*" >> "$log"
        [[ "$*" != *" upgrade -y" ]]
    }
    reboot_required_state() { printf '不需要\n'; }

    if update_system_packages <<< "y" >/dev/null 2>&1; then
        fail "apt upgrade 失败时系统更新不应成功"
    fi
    assert_eq 2 "$(wc -l < "$log" | tr -d ' ')" "upgrade 失败后不得继续 autoremove"
    assert_file_not_contains "$log" 'autoremove'
}

test_alpine_update_uses_bounded_steps() {
    local log="$TEST_TMP/alpine-update.log"

    detect_os() { OS=alpine; }
    apk_bounded() { printf '%s\n' "$*" >> "$log"; }
    reboot_required_state() { printf '不需要\n'; }

    update_system_packages <<< "y" >/dev/null
    assert_file_contains "$log" "^${PACKAGE_UPDATE_TIMEOUT} update$"
    assert_file_contains "$log" "^${SYSTEM_UPGRADE_TIMEOUT} upgrade$"
    assert_eq 2 "$(wc -l < "$log" | tr -d ' ')" "Alpine 应只执行 update 和 upgrade"
}

test_ntp_package_rollback_restores_timesyncd() {
    local log="$TEST_TMP/ntp-packages.log"
    local chrony_installed=1 timesyncd_installed=0

    # Read by the sourced package-restore helper.
    # shellcheck disable=SC2034
    OS=debian
    ntp_package_installed() {
        case "$1" in
            chrony) [ "$chrony_installed" -eq 1 ] ;;
            systemd-timesyncd) [ "$timesyncd_installed" -eq 1 ] ;;
            *) return 1 ;;
        esac
    }
    apt_get_bounded() {
        printf '%s\n' "$*" >> "$log"
        case "$*" in
            *"purge -y chrony") chrony_installed=0 ;;
            *"install -y systemd-timesyncd") timesyncd_installed=1 ;;
        esac
    }

    restore_ntp_packages_to_state absent installed
    assert_eq 0 "$chrony_installed" "应移除本次新安装的 chrony"
    assert_eq 1 "$timesyncd_installed" "应重新安装原有 systemd-timesyncd"
    assert_file_contains "$log" 'purge -y chrony$'
    assert_file_contains "$log" 'install -y systemd-timesyncd$'
}

test_chrony_source_layout_detection() {
    (
        local dir="$TEST_TMP/chrony-layout" test_conf
        mkdir -p "$dir/sources.d"
        test_conf="$dir/chrony.conf"
        CHRONY_SOURCE_FILE="$dir/sources.d/vpsbox.sources"
        chrony_conf_path() { printf '%s\n' "$test_conf"; }

        printf 'sourcedir /etc/chrony/sources.d\n' > "$test_conf"
        chrony_expected_sources > "$CHRONY_SOURCE_FILE"
        chrony_sources_are_current || fail "独立 sources.d 配置应识别为当前状态"

        rm -f "$CHRONY_SOURCE_FILE"
        printf 'driftfile /var/lib/chrony/drift\n\n%s\n' "$NTP_SOURCES_BEGIN" > "$test_conf"
        chrony_expected_sources >> "$test_conf"
        printf '%s\n' "$NTP_SOURCES_END" >> "$test_conf"
        chrony_sources_are_current || fail "主配置中的规范 vpsbox 区块应识别为当前状态"

        printf 'pool unexpected.example iburst\n' >> "$test_conf"
        chrony_sources_are_current || fail "区块外的用户配置不应导致重复改写"
    )
}

test_enable_ntp_healthy_is_noop() {
    (
        local log="$TEST_TMP/ntp-healthy.log"
        : > "$log"
        detect_os() { :; }
        is_systemd() { return 0; }
        chrony_service_name() { printf 'chrony\n'; }
        chrony_conf_path() { printf '/unused/chrony.conf\n'; }
        ntp_package_installed() { [ "$1" = "chrony" ]; }
        systemd_unit_exists() { [ "$1" = "chrony.service" ]; }
        chrony_sources_are_current() { return 0; }
        ntp_service_state_is_healthy() { return 0; }
        show_ntp_runtime_details() { printf '%s\n' details >> "$log"; }
        backup_change_file_once() { printf '%s\n' backup >> "$log"; }
        apt_get_bounded() { printf '%s\n' package >> "$log"; }
        repair_ntp_service_state() { printf '%s\n' repair >> "$log"; }

        enable_ntp_sync >/dev/null
        assert_eq details "$(cat "$log")" \
            "健康但尚未同步时只能展示状态，不得安装、备份或修复"
    )
}

test_ntp_unsynchronized_status_is_nonfatal() {
    (
        local output="$TEST_TMP/ntp-unsynchronized.out"
        systemctl() {
            case "$*" in
                'is-enabled chrony') printf 'enabled\n' ;;
                'is-active chrony') printf 'active\n' ;;
                *) return 1 ;;
            esac
        }
        chronyc() {
            case "$1" in
                sources) printf 'time.cloudflare.com\n' ;;
                tracking) printf 'Leap status     : Not synchronised\n' ;;
                *) return 1 ;;
            esac
        }
        timedatectl() { return 0; }

        show_ntp_runtime_details chrony > "$output"
        assert_file_contains "$output" '首次同步可能需要几分钟'
        assert_file_contains "$output" '当前配置不会重复改写'
    )
}

test_ntp_service_drift_uses_light_repair() {
    (
        local log="$TEST_TMP/ntp-service-repair.log"
        local mock_chrony_enabled=0 mock_chrony_active=0
        local mock_timesyncd_enabled=1 mock_timesyncd_active=1
        : > "$log"
        systemd_unit_exists() { [ "$1" = "systemd-timesyncd.service" ]; }
        systemctl() {
            case "$*" in
                'is-enabled --quiet chrony') [ "$mock_chrony_enabled" -eq 1 ] ;;
                'is-active --quiet chrony') [ "$mock_chrony_active" -eq 1 ] ;;
                'is-enabled --quiet systemd-timesyncd') [ "$mock_timesyncd_enabled" -eq 1 ] ;;
                'is-active --quiet systemd-timesyncd') [ "$mock_timesyncd_active" -eq 1 ] ;;
                'enable chrony') mock_chrony_enabled=1; printf '%s\n' 'enable chrony' >> "$log" ;;
                'start chrony') mock_chrony_active=1; printf '%s\n' 'start chrony' >> "$log" ;;
                'disable --now systemd-timesyncd')
                    mock_timesyncd_enabled=0
                    mock_timesyncd_active=0
                    printf '%s\n' 'disable timesyncd' >> "$log"
                    ;;
                *) return 1 ;;
            esac
        }

        repair_ntp_service_state chrony >/dev/null
        assert_file_contains "$log" '^enable chrony$'
        assert_file_contains "$log" '^start chrony$'
        assert_file_contains "$log" '^disable timesyncd$'
    )
}

test_bbr_fq_healthy_is_noop() {
    (
        local log="$TEST_TMP/bbr-healthy.log"
        BBR_CONF="$TEST_TMP/99-vpsbox-bbr-healthy.conf"
        render_bbr_fq_config > "$BBR_CONF"
        : > "$log"
        sysctl() {
            case "$*" in
                '-n net.ipv4.tcp_congestion_control') printf 'bbr\n' ;;
                '-n net.core.default_qdisc') printf 'fq\n' ;;
                *) printf '%s\n' "$*" >> "$log" ;;
            esac
        }
        modprobe() { printf '%s\n' "$*" >> "$log"; }
        backup_change_file_once() { printf '%s\n' backup >> "$log"; }

        enable_bbr_fq >/dev/null
        assert_empty_file "$log" "健康的 BBR + fq 不得加载模块、应用 sysctl 或创建备份"
    )
}

test_bbr_fq_runtime_drift_uses_light_repair() {
    (
        local log="$TEST_TMP/bbr-repair.log"
        local cc=cubic fq=pfifo_fast
        BBR_CONF="$TEST_TMP/99-vpsbox-bbr-repair.conf"
        render_bbr_fq_config > "$BBR_CONF"
        : > "$log"
        sysctl() {
            case "$1" in
                -n)
                    [ "$2" = "net.ipv4.tcp_congestion_control" ] && printf '%s\n' "$cc" || printf '%s\n' "$fq"
                    ;;
                -p)
                    cc=bbr
                    fq=fq
                    printf '%s\n' 'sysctl-p' >> "$log"
                    ;;
                -w) return 0 ;;
                *) return 1 ;;
            esac
        }
        modprobe() { printf 'modprobe %s\n' "$1" >> "$log"; }
        backup_change_file_once() { printf '%s\n' backup >> "$log"; }
        bbr_state() { printf '%s\n' "$cc"; }
        fq_state() { printf '%s\n' "$fq"; }

        enable_bbr_fq >/dev/null
        assert_file_contains "$log" '^modprobe tcp_bbr$'
        assert_file_contains "$log" '^modprobe sch_fq$'
        assert_file_contains "$log" '^sysctl-p$'
        assert_file_not_contains "$log" '^backup$' "只修复运行参数时不得改写持久化配置"
    )
}

test_journald_healthy_is_noop() {
    (
        local log="$TEST_TMP/journald-healthy.log"
        : > "$log"
        is_systemd() { return 0; }
        journalctl() { return 0; }
        journald_limit_state() { printf '已配置\n'; }
        systemctl() {
            if [ "$*" = "is-active --quiet systemd-journald" ]; then
                return 0
            fi
            printf '%s\n' "$*" >> "$log"
        }
        journal_disk_usage() { printf '12M\n'; }
        backup_change_file_once() { printf '%s\n' backup >> "$log"; }

        limit_systemd_journal >/dev/null
        assert_empty_file "$log" "健康的 journald 限制不得备份、写配置或重启服务"
    )
}

prepare_ssh_change_tracking() {
    reset_change_store "$1"
    printf '%s\n' \
        'BACKUP_SSHD_MAIN=present' \
        'BACKUP_SSHD_PORT=present' \
        'BACKUP_SSHD_HARDENING=present' \
        'APPLIED_SSH_CONFIG=1' \
        'SSH_PORTS=22' > "$CHANGE_MANIFEST"
    : > "$CHANGE_BACKUP_DIR/SSHD_MAIN"
    : > "$CHANGE_BACKUP_DIR/SSHD_PORT"
    : > "$CHANGE_BACKUP_DIR/SSHD_HARDENING"
}

assert_ssh_tracking_cleared() {
    assert_file_not_contains "$CHANGE_MANIFEST" \
        '^(BACKUP_SSHD_(MAIN|PORT|HARDENING)|APPLIED_SSH_CONFIG|SSH_PORTS)='
    [ ! -e "$CHANGE_BACKUP_DIR/SSHD_MAIN" ] || fail "SSHD_MAIN 备份未清理"
    [ ! -e "$CHANGE_BACKUP_DIR/SSHD_PORT" ] || fail "SSHD_PORT 备份未清理"
    [ ! -e "$CHANGE_BACKUP_DIR/SSHD_HARDENING" ] || fail "SSHD_HARDENING 备份未清理"
}

test_first_ssh_port_rollback_clears_tracking() {
    prepare_ssh_change_tracking ssh-port-first
    restore_ssh_config_backup() { return 0; }
    sshd_binary() { printf '%s\n' /bin/true; }
    restart_ssh_service() { return 0; }
    wait_for_any_ssh_listener_csv() { return 0; }
    ssh_firewall_transition_abort() { return 0; }

    rollback_ssh_port_change "" "" 22 0
    assert_ssh_tracking_cleared
}

test_first_ssh_hardening_rollback_clears_tracking() {
    prepare_ssh_change_tracking ssh-hardening-first
    restore_ssh_config_backup() { return 0; }
    restart_ssh_service() { return 0; }

    rollback_ssh_hardening_change "" "" 0 1
    assert_ssh_tracking_cleared
}

test_existing_ssh_baseline_survives_later_rollback() {
    prepare_ssh_change_tracking ssh-existing
    restore_ssh_config_backup() { return 0; }
    restart_ssh_service() { return 0; }

    rollback_ssh_hardening_change "" "" 1 1
    assert_file_contains "$CHANGE_MANIFEST" '^BACKUP_SSHD_MAIN=present$'
    assert_file_contains "$CHANGE_MANIFEST" '^APPLIED_SSH_CONFIG=1$'
    assert_file_contains "$CHANGE_MANIFEST" '^SSH_PORTS=22$'
    [ -f "$CHANGE_BACKUP_DIR/SSHD_MAIN" ] ||
        fail "后续事务失败不应删除此前成功应用所需的 SSH 基线"
}

test_ssh_hardening_requires_listener_after_restart() {
    (
        local ssh_dir="$TEST_TMP/ssh-hardening-listener/etc/ssh"
        local log="$TEST_TMP/ssh-hardening-listener.log"
        local wait_calls=0
        reset_change_store ssh-hardening-listener
        mkdir -p "$ssh_dir/sshd_config.d"
        SSHD_MAIN_CONF="$ssh_dir/sshd_config"
        SSHD_CONFIG_DIR="$ssh_dir/sshd_config.d"
        SSHD_VPSBOX_PORT_CONF="$SSHD_CONFIG_DIR/00-vpsbox-ssh-port.conf"
        SSHD_VPSBOX_HARDENING_CONF="$SSHD_CONFIG_DIR/01-vpsbox-ssh-hardening.conf"
        printf '%s\n' 'Port 6384' > "$SSHD_MAIN_CONF"
        : > "$log"

        sshd_binary() { printf '%s\n' /bin/true; }
        settle_stale_unapplied_ssh_tracking() { return 0; }
        ssh_basic_hardening_effective() { return 1; }
        backup_change_file_once() { return 0; }
        ssh_effective_ports_csv() { printf '%s\n' 6384; }
        manifest_set_once() { return 0; }
        backup_ssh_file() { printf '%s\n' "$TEST_TMP/ssh-hardening-backup"; }
        mark_change_applied() { return 0; }
        write_vpsbox_ssh_hardening_config() { return 0; }
        ensure_sshd_dropin_include() { return 0; }
        validate_ssh_hardening_effective_config() { return 0; }
        restart_ssh_service() { printf '%s\n' restart >> "$log"; }
        wait_for_any_ssh_listener_csv() {
            wait_calls=$((wait_calls + 1))
            printf 'wait:%s:%s\n' "$wait_calls" "$1" >> "$log"
            [ "$wait_calls" -gt 1 ]
        }
        restore_ssh_config_backup() { printf '%s\n' restore >> "$log"; }
        clear_ssh_change_tracking() { printf '%s\n' clear >> "$log"; }

        if apply_ssh_basic_hardening <<< "y" >"$TEST_TMP/ssh-hardening-listener.out" 2>&1; then
            fail "SSH 重启后原端口未监听时加固不得报告成功"
        fi
        assert_file_contains "$log" '^wait:1:6384$'
        assert_file_contains "$log" '^restore$' "监听验证失败后必须回滚配置"
        assert_file_contains "$log" '^wait:2:6384$' "回滚后必须再次确认原端口监听"
        assert_file_contains "$log" '^clear$'
    )
}

test_ssh_pre_mark_failure_cleans_first_baseline() {
    local ssh_dir="$TEST_TMP/ssh-pre-mark/etc/ssh"

    reset_change_store ssh-pre-mark
    mkdir -p "$ssh_dir/sshd_config.d"
    SSHD_MAIN_CONF="$ssh_dir/sshd_config"
    SSHD_CONFIG_DIR="$ssh_dir/sshd_config.d"
    # Consumed indirectly by the sourced SSH transaction.
    # shellcheck disable=SC2034
    SSHD_VPSBOX_PORT_CONF="$SSHD_CONFIG_DIR/00-vpsbox-ssh-port.conf"
    # shellcheck disable=SC2034
    SSHD_VPSBOX_HARDENING_CONF="$SSHD_CONFIG_DIR/01-vpsbox-ssh-hardening.conf"
    printf '%s\n' 'Port 22' > "$SSHD_MAIN_CONF"
    ACTIVE_UNAPPLIED_SSH_TRACKING=0

    sshd_binary() { printf '%s\n' /bin/true; }
    ssh_socket_activation_active() { return 1; }
    choose_ssh_target_port() { printf '%s\n' 2222; }
    ssh_effective_ports_match_target() { return 1; }
    firewall_runtime_enabled() { return 1; }
    ssh_effective_ports_csv() { return 23; }

    if apply_ssh_port_change <<< "YES" >/dev/null 2>&1; then
        fail "首次 SSH 事务在 APPLIED 标记前失败时不应成功"
    fi
    assert_ssh_tracking_cleared
    assert_eq 0 "$ACTIVE_UNAPPLIED_SSH_TRACKING" "失败后不应保留活动清理标记"
}

test_runtime_cleanup_clears_interrupted_ssh_baseline() {
    prepare_ssh_change_tracking ssh-interrupted
    ACTIVE_UNAPPLIED_SSH_TRACKING=1
    cleanup_vpsbox_lock() { return 0; }

    cleanup_vpsbox_runtime

    assert_ssh_tracking_cleared
    assert_eq 0 "$ACTIVE_UNAPPLIED_SSH_TRACKING" "运行时清理后不应保留 SSH 首次事务标记"
}

test_failed_ssh_tracking_cleanup_remains_retryable() {
    local fail_once=1

    reset_change_store ssh-cleanup-retry
    : > "$CHANGE_BACKUP_DIR/SSHD_MAIN"
    ACTIVE_UNAPPLIED_SSH_TRACKING=1
    manifest_remove() {
        if [ "$1" = "BACKUP_SSHD_MAIN" ] && [ "$fail_once" -eq 1 ]; then
            fail_once=0
            return 23
        fi
        return 0
    }

    if cleanup_unapplied_ssh_tracking 0; then
        fail "首次清理失败时不应报告成功"
    fi
    assert_eq 1 "$ACTIVE_UNAPPLIED_SSH_TRACKING" "清理失败后必须保留重试标记"
    cleanup_unapplied_ssh_tracking 0
    assert_eq 0 "$ACTIVE_UNAPPLIED_SSH_TRACKING" "后续完整清理后才可清除重试标记"
}

test_stale_unapplied_ssh_baseline_is_removed_on_next_run() {
    prepare_ssh_change_tracking ssh-stale-unapplied
    manifest_remove APPLIED_SSH_CONFIG
    ACTIVE_UNAPPLIED_SSH_TRACKING=0

    settle_stale_unapplied_ssh_tracking

    assert_ssh_tracking_cleared
    assert_eq 0 "$ACTIVE_UNAPPLIED_SSH_TRACKING"
}

test_absent_resolv_conf_is_created_successfully() {
    (
        reset_change_store dns-absent
        RESOLV_CONF="$TEST_TMP/dns-absent/resolv.conf"
        verify_dns_resolution() { return 2; }

        write_resolv_conf_dns 1.1.1.1 8.8.8.8 >/dev/null

        assert_file_contains "$RESOLV_CONF" '^nameserver 1\.1\.1\.1$'
        assert_file_contains "$RESOLV_CONF" '^nameserver 8\.8\.8\.8$'
        assert_file_contains "$CHANGE_MANIFEST" '^APPLIED_DNS_RESOLV=1$'
    )
}

test_sshd_include_only_activates_vpsbox_files() {
    (
        local ssh_dir="$TEST_TMP/ssh-explicit-include"
        mkdir -p "$ssh_dir/sshd_config.d"
        SSHD_MAIN_CONF="$ssh_dir/sshd_config"
        SSHD_CONFIG_DIR="$ssh_dir/sshd_config.d"
        SSHD_VPSBOX_PORT_CONF="$SSHD_CONFIG_DIR/00-vpsbox-ssh-port.conf"
        SSHD_VPSBOX_HARDENING_CONF="$SSHD_CONFIG_DIR/01-vpsbox-ssh-hardening.conf"
        printf '%s\n' 'Port 22' > "$SSHD_MAIN_CONF"
        printf '%s\n' 'PasswordAuthentication yes' > "$SSHD_CONFIG_DIR/90-dormant.conf"

        ensure_sshd_dropin_include

        assert_file_contains "$SSHD_MAIN_CONF" \
            "^Include $SSHD_VPSBOX_PORT_CONF $SSHD_VPSBOX_HARDENING_CONF$"
        assert_file_not_contains "$SSHD_MAIN_CONF" 'sshd_config\.d/\*\.conf'
        assert_file_contains "$SSHD_CONFIG_DIR/90-dormant.conf" '^PasswordAuthentication yes$'
    )
}

test_enabled_inactive_ssh_socket_is_detected() {
    (
        is_systemd() { return 0; }
        systemctl() {
            case "$*" in
                "is-active --quiet "*) return 1 ;;
                "is-enabled --quiet ssh.socket") return 0 ;;
                *) return 1 ;;
            esac
        }

        ssh_socket_activation_enabled_or_active ||
            fail "已启用但未运行的 ssh.socket 必须被识别"
    )
}

test_multiple_ssh_socket_streams_are_parsed() {
    (
        is_systemd() { return 0; }
        systemctl() {
            case "$*" in
                "is-active --quiet ssh.socket") return 0 ;;
                "is-active --quiet sshd.socket") return 1 ;;
                "show ssh.socket --property=Listen --value")
                    printf '%s\n' '0.0.0.0:22 (Stream) [::]:2222 (Stream)'
                    ;;
                *) return 1 ;;
            esac
        }

        assert_eq "22,2222" "$(ssh_socket_activation_ports_csv)" \
            "多个 ListenStream 端口必须全部保留"
    )
}

test_ssh_restore_does_not_require_current_config_to_parse() {
    (
        local ssh_dir="$TEST_TMP/ssh-invalid-current" transition_log="$TEST_TMP/ssh-invalid-transition"
        reset_change_store ssh-invalid-current
        mkdir -p "$ssh_dir/sshd_config.d"
        SSHD_MAIN_CONF="$ssh_dir/sshd_config"
        SSHD_CONFIG_DIR="$ssh_dir/sshd_config.d"
        SSHD_VPSBOX_PORT_CONF="$SSHD_CONFIG_DIR/00-vpsbox-ssh-port.conf"
        SSHD_VPSBOX_HARDENING_CONF="$SSHD_CONFIG_DIR/01-vpsbox-ssh-hardening.conf"
        printf '%s\n' broken > "$SSHD_MAIN_CONF"
        # shellcheck disable=SC2034 # 被测的 SSH 连接端口解析函数动态读取。
        SSH_CONNECTION="192.0.2.10 50000 192.0.2.20 6384"
        manifest_value() {
            case "$1" in
                APPLIED_SSH_CONFIG) printf '%s\n' 1 ;;
                SSH_PORTS) printf '%s\n' 22 ;;
                *) return 1 ;;
            esac
        }
        ssh_listening_ports_csv() { printf '%s\n' 23333; }
        ssh_effective_ports_csv() { fail "损坏配置恢复入口不得调用 sshd -T"; }
        ssh_firewall_transition_begin() { printf '%s\n' "$1" > "$transition_log"; }
        restore_change_file() { return 0; }
        sshd_binary() { printf '%s\n' /bin/true; }
        restart_ssh_service() { return 0; }
        wait_for_any_ssh_listener_csv() { return 0; }
        ssh_firewall_transition_finish() { return 0; }
        clear_ssh_change_tracking() { return 0; }
        sync_fail2ban_sshd_port() { return 0; }

        restore_vpsbox_ssh_config <<< "YES" >/dev/null
        assert_file_contains "$transition_log" '^22,6384,23333$'
    )
}

test_failed_ssh_restore_preserves_retry_snapshot() {
    (
        local ssh_dir="$TEST_TMP/ssh-restore-snapshot/etc/ssh"
        local snapshot
        reset_change_store ssh-restore-snapshot
        mkdir -p "$ssh_dir/sshd_config.d"
        SSHD_MAIN_CONF="$ssh_dir/sshd_config"
        SSHD_CONFIG_DIR="$ssh_dir/sshd_config.d"
        SSHD_VPSBOX_PORT_CONF="$SSHD_CONFIG_DIR/00-vpsbox-ssh-port.conf"
        SSHD_VPSBOX_HARDENING_CONF="$SSHD_CONFIG_DIR/01-vpsbox-ssh-hardening.conf"
        printf '%s\n' broken > "$SSHD_MAIN_CONF"
        manifest_value() {
            case "$1" in
                APPLIED_SSH_CONFIG) printf '%s\n' 1 ;;
                SSH_PORTS) printf '%s\n' 22 ;;
                *) return 1 ;;
            esac
        }
        ssh_listening_ports_csv() { printf '%s\n' 23333; }
        ssh_firewall_transition_begin() { return 0; }
        restore_change_file() { return 1; }
        settle_failed_ssh_restore() { return 1; }

        if restore_vpsbox_ssh_config <<< "YES" >/dev/null 2>&1; then
            fail "SSH 配置恢复失败时不得报告成功"
        fi
        snapshot="$(find "$(ssh_restore_snapshot_root)" -maxdepth 1 -type d -name 'restore.*' -print -quit)"
        [ -d "$snapshot" ] || fail "二次回滚失败后必须保留恢复前快照"
        assert_file_contains "$snapshot/main" '^broken$'
    )
}

test_ssh_config_publish_failure_preserves_target() {
    (
        local dir="$TEST_TMP/ssh-atomic-publish"
        mkdir -p "$dir"
        printf '%s\n' old > "$dir/target"
        printf '%s\n' new > "$dir/source"
        chown() { return 0; }
        mv() { return 1; }

        if install_ssh_config_atomically "$dir/source" "$dir/target" 644; then
            fail "SSH 配置原子替换失败时不应报告成功"
        fi
        assert_file_contains "$dir/target" '^old$' "发布失败时必须保留原 SSH 配置"
        if find "$dir" -maxdepth 1 -name '.vpsbox-publish.*' -print -quit | grep -q .; then
            fail "SSH 配置发布失败后不应遗留临时文件"
        fi
    )
}

test_ssh_restore_snapshot_integrity_is_verified() {
    (
        local ssh_dir="$TEST_TMP/ssh-snapshot-integrity/etc/ssh" snapshot=""
        reset_change_store ssh-snapshot-integrity
        mkdir -p "$ssh_dir/sshd_config.d"
        SSHD_MAIN_CONF="$ssh_dir/sshd_config"
        SSHD_CONFIG_DIR="$ssh_dir/sshd_config.d"
        SSHD_VPSBOX_PORT_CONF="$SSHD_CONFIG_DIR/00-vpsbox-ssh-port.conf"
        SSHD_VPSBOX_HARDENING_CONF="$SSHD_CONFIG_DIR/01-vpsbox-ssh-hardening.conf"
        printf '%s\n' original > "$SSHD_MAIN_CONF"
        printf '%s\n' 'Port 23333' > "$SSHD_VPSBOX_PORT_CONF"

        create_ssh_restore_snapshot snapshot
        [[ "$snapshot" == "$(ssh_restore_snapshot_root)"/restore.* ]] ||
            fail "SSH 恢复快照必须位于 vpsbox 持久状态目录"
        ssh_restore_snapshot_dir_valid "$snapshot" ||
            fail "新建的 SSH 恢复快照应通过完整性校验"

        printf '%s\n' tampered > "$snapshot/main"
        printf '%s\n' current > "$SSHD_MAIN_CONF"
        if restore_ssh_runtime_snapshot "$snapshot" ""; then
            fail "被篡改的 SSH 恢复快照不得用于恢复"
        fi
        assert_file_contains "$SSHD_MAIN_CONF" '^current$' \
            "快照校验失败时不得修改现有 SSH 配置"
    )
}

test_dns_verification_uses_bounded_command() {
    (
        local log="$TEST_TMP/dns-verify-bounded.log"
        command() {
            if [ "${1:-}" = "-v" ] && [ "${2:-}" = "getent" ]; then
                return 0
            fi
            if [ "${1:-}" = "-v" ] && [ "${2:-}" = "resolvectl" ]; then
                return 1
            fi
            builtin command "$@"
        }
        run_bounded_command() {
            printf '%s\n' "$*" > "$log"
            printf '%s\n' '192.0.2.1 STREAM example.com'
        }

        verify_dns_resolution || fail "有界 DNS 命令返回地址时应验证成功"
        assert_file_contains "$log" '^8 getent ahosts example[.]com$'
    )
}

test_nexttrace_probe_uses_bounded_command() {
    (
        local log="$TEST_TMP/nexttrace-bounded.log"
        run_bounded_command() {
            printf '%s\n' "$*" > "$log"
        }

        run_nexttrace_sized_target 1.1.1.1 40000 1450
        assert_file_contains "$log" \
            '^30 nexttrace -n -P -C -T -p 80 --source-port 40000 --parallel-requests 1 --queries [0-9]+ --psize 1450 1[.]1[.]1[.]1$'
    )
}

test_nexttrace_help_uses_bounded_command_and_propagates_timeout() {
    (
        local log="$TEST_TMP/nexttrace-help-bounded.log"
        run_bounded_command() {
            printf '%s\n' "$*" > "$log"
            printf '%s\n' '--psize --source-port --parallel-requests --queries'
        }

        nexttrace_supports_size_compare || fail "有界帮助输出包含必需参数时应通过"
        assert_file_contains "$log" "^${NEXTTRACE_HELP_TIMEOUT} nexttrace --help$"
    )
    (
        local output="$TEST_TMP/nexttrace-help-timeout.out"
        run_bounded_command() { return 124; }

        if nexttrace_supports_size_compare > "$output" 2>&1; then
            fail "读取 nexttrace 帮助超时时不得继续测试"
        fi
        assert_file_contains "$output" "无法在 ${NEXTTRACE_HELP_TIMEOUT} 秒内可靠读取"
    )
}

test_hostname_failure_restores_current_operation_state() {
    (
        local runtime_hostname="first.example" fail_hosts_publish=1
        reset_change_store hostname-second-failure
        HOSTNAME_PATH="$TEST_TMP/hostname-second-failure/hostname"
        HOSTS_PATH="$TEST_TMP/hostname-second-failure/hosts"
        printf '%s\n' first.example > "$HOSTNAME_PATH"
        printf '%s\n' '127.0.0.1 localhost' '192.0.2.10 user-entry' > "$HOSTS_PATH"
        printf '%s\n' baseline.example > "$CHANGE_BACKUP_DIR/HOSTNAME_FILE"
        printf '%s\n' '127.0.0.1 baseline' > "$CHANGE_BACKUP_DIR/HOSTS_FILE"
        cat > "$CHANGE_MANIFEST" <<'EOF'
BACKUP_HOSTNAME_FILE=file
BACKUP_HOSTS_FILE=file
HOSTNAME_VALUE=baseline.example
APPLIED_HOSTNAME=1
EOF
        hostname_current_value() { printf '%s\n' "$runtime_hostname"; }
        set_system_hostname() { runtime_hostname="$1"; }
        mv() {
            local source target
            local -a args=("$@")
            source="${args[${#args[@]}-2]}"
            target="${args[${#args[@]}-1]}"
            if [ "$target" = "$HOSTS_PATH" ] && [[ "$source" == */.hosts.vpsbox.* ]] &&
                [ "$fail_hosts_publish" -eq 1 ]; then
                fail_hosts_publish=0
                return 23
            fi
            command mv "$@"
        }

        if change_system_hostname <<< "second.example" >/dev/null 2>&1; then
            fail "第二次主机名修改的 hosts 发布失败时不得报告成功"
        fi
        assert_file_contains "$HOSTNAME_PATH" '^first\.example$'
        assert_file_contains "$HOSTS_PATH" '^192\.0\.2\.10 user-entry$'
        assert_eq first.example "$runtime_hostname"
        assert_file_contains "$CHANGE_MANIFEST" '^APPLIED_HOSTNAME=1$'
        assert_file_not_contains "$CHANGE_MANIFEST" '^PENDING_HOSTNAME='
    )
}

test_signal_traps_preserve_exit_status() {
    local signal expected status

    for signal in INT TERM; do
        case "$signal" in
            INT) expected=130 ;;
            TERM) expected=143 ;;
        esac
        set +e
        REPO_DIR="$REPO_DIR" bash -c '
            set -euo pipefail
            source "$REPO_DIR/vpsbox.sh"
            install_lock_cleanup_traps
            kill -s "$1" "$$"
        ' _ "$signal" >/dev/null 2>&1
        status=$?
        set -e
        assert_eq "$expected" "$status" "$signal 不应被转换成成功退出"
    done
}

test_uninstall_restore_offer_runs_internal_restore() {
    (
        local log="$TEST_TMP/uninstall-restore.log"
        recorded_system_changes_present() { return 0; }
        show_vpsbox_changes() { printf '%s\n' show >> "$log"; }
        restore_vpsbox_system_changes() { printf 'restore:%s\n' "${1:-}" >> "$log"; }

        offer_restore_recorded_changes_before_uninstall <<< "YES" >/dev/null
        assert_file_contains "$log" '^show$'
        assert_file_contains "$log" '^restore:1$' "卸载恢复应跳过重复确认并执行内部恢复"
    )
}

test_uninstall_restore_offer_can_preserve_changes() {
    (
        local log="$TEST_TMP/uninstall-preserve.log"
        : > "$log"
        recorded_system_changes_present() { return 0; }
        show_vpsbox_changes() { :; }
        restore_vpsbox_system_changes() { printf '%s\n' restore >> "$log"; }

        offer_restore_recorded_changes_before_uninstall <<< "NO" >/dev/null
        assert_empty_file "$log" "选择保留现状时不得调用恢复"
    )
}

test_uninstall_restore_failure_aborts_offer() {
    (
        recorded_system_changes_present() { return 0; }
        show_vpsbox_changes() { :; }
        restore_vpsbox_system_changes() { return 23; }

        if offer_restore_recorded_changes_before_uninstall <<< "YES" >/dev/null 2>&1; then
            fail "系统设置恢复失败时卸载前置步骤不应成功"
        fi
    )
}

main() {
    local test status passed=0
    local -a tests=(
        test_manifest_failure_preserves_existing_file
        test_manifest_round_trips_ssh_port_csv
        test_clear_change_tracking_reports_partial_failure
        test_restore_replaces_target_symlink
        test_atomic_snapshot_restore_replaces_target_symlink
        test_atomic_snapshot_restore_rejects_directory_symlink
        test_atomic_snapshot_restore_replaces_dangling_symlink
        test_atomic_snapshot_restore_move_failure_preserves_target
        test_debian_update_stops_after_first_failure
        test_debian_update_uses_upgrade_timeout
        test_debian_upgrade_failure_skips_autoremove
        test_alpine_update_uses_bounded_steps
        test_ntp_package_rollback_restores_timesyncd
        test_chrony_source_layout_detection
        test_enable_ntp_healthy_is_noop
        test_ntp_unsynchronized_status_is_nonfatal
        test_ntp_service_drift_uses_light_repair
        test_bbr_fq_healthy_is_noop
        test_bbr_fq_runtime_drift_uses_light_repair
        test_journald_healthy_is_noop
        test_first_ssh_port_rollback_clears_tracking
        test_first_ssh_hardening_rollback_clears_tracking
        test_existing_ssh_baseline_survives_later_rollback
        test_ssh_hardening_requires_listener_after_restart
        test_ssh_pre_mark_failure_cleans_first_baseline
        test_runtime_cleanup_clears_interrupted_ssh_baseline
        test_failed_ssh_tracking_cleanup_remains_retryable
        test_stale_unapplied_ssh_baseline_is_removed_on_next_run
        test_absent_resolv_conf_is_created_successfully
        test_sshd_include_only_activates_vpsbox_files
        test_enabled_inactive_ssh_socket_is_detected
        test_multiple_ssh_socket_streams_are_parsed
        test_ssh_restore_does_not_require_current_config_to_parse
        test_failed_ssh_restore_preserves_retry_snapshot
        test_ssh_config_publish_failure_preserves_target
        test_ssh_restore_snapshot_integrity_is_verified
        test_dns_verification_uses_bounded_command
        test_nexttrace_probe_uses_bounded_command
        test_nexttrace_help_uses_bounded_command_and_propagates_timeout
        test_hostname_failure_restores_current_operation_state
        test_signal_traps_preserve_exit_status
        test_uninstall_restore_offer_runs_internal_restore
        test_uninstall_restore_offer_can_preserve_changes
        test_uninstall_restore_failure_aborts_offer
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
    printf '%s system regression tests passed.\n' "$passed"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
