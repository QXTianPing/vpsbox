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

main() {
    local name test status passed=0
    local -a required=(
        normalize_port_decimal
        normalize_port_csv
        firewall_check_conflicts
        firewall_openrc_service_enabled
        run_bounded_in_new_session
        run_bounded_with_timeout
        firewall_start_rollback_watchdog
        firewall_detect_docker_ports
    )
    local -a tests=(
        test_port_decimal_normalization
        test_systemd_enabled_inactive_firewalld_conflict
        test_openrc_enabled_inactive_firewalld_conflict
        test_bounded_background_processes_release_lock
        test_timeout_processes_release_lock
        test_busybox_timeout_fallback_releases_lock
        test_watchdog_survives_parent_without_holding_lock
        test_stopped_docker_fixed_binding_is_public
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
