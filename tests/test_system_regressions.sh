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
        test_debian_update_stops_after_first_failure
        test_debian_update_uses_upgrade_timeout
        test_debian_upgrade_failure_skips_autoremove
        test_alpine_update_uses_bounded_steps
        test_ntp_package_rollback_restores_timesyncd
        test_first_ssh_port_rollback_clears_tracking
        test_first_ssh_hardening_rollback_clears_tracking
        test_existing_ssh_baseline_survives_later_rollback
        test_ssh_pre_mark_failure_cleans_first_baseline
        test_runtime_cleanup_clears_interrupted_ssh_baseline
        test_failed_ssh_tracking_cleanup_remains_retryable
        test_stale_unapplied_ssh_baseline_is_removed_on_next_run
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
