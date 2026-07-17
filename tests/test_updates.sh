#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=tests/test_helper.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/test_helper.sh"

# shellcheck source=../vpsbox.sh
source "$REPO_DIR/vpsbox.sh"

MOCK_REMOTE_SCRIPT=""
MOCK_EVENT_LOG="$TEST_TMP/update-events.log"
MOCK_CURL_LOG="$TEST_TMP/update-curl.log"
MOCK_CURL_FAIL_URLS=""
UPDATE_TEST_CURRENT=""
UPDATE_TEST_OLDER=""
UPDATE_TEST_NEWER=""

derive_update_test_versions() {
    local raw="${VPSBOX_VERSION#v}"
    local major minor patch extra=""

    IFS=. read -r major minor patch extra <<< "$raw"
    [[ "$major" =~ ^[0-9]+$ && "$minor" =~ ^[0-9]+$ && "$patch" =~ ^[0-9]+$ && -z "$extra" ]] ||
        fail "无法从 VPSBOX_VERSION 派生更新测试版本：$VPSBOX_VERSION"
    major=$((10#$major))
    minor=$((10#$minor))
    patch=$((10#$patch))

    UPDATE_TEST_CURRENT="v${major}.${minor}.${patch}"
    UPDATE_TEST_NEWER="v${major}.${minor}.$((patch + 1))"
    if [ "$patch" -gt 0 ]; then
        UPDATE_TEST_OLDER="v${major}.${minor}.$((patch - 1))"
    elif [ "$minor" -gt 0 ]; then
        UPDATE_TEST_OLDER="v${major}.$((minor - 1)).999"
    elif [ "$major" -gt 0 ]; then
        UPDATE_TEST_OLDER="v$((major - 1)).999.999"
    else
        fail "VPSBOX_VERSION 不能使用 v0.0.0：无法构造更旧版本"
    fi
}

derive_update_test_versions

test_cleanup() {
    if [ "${KEEP_TEST_TMP:-0}" = "1" ]; then
        printf '保留测试临时目录：%s\n' "$TEST_TMP" >&2
    else
        rm -rf -- "$TEST_TMP"
    fi
}
trap test_cleanup EXIT

write_fixture() {
    local path="$1" version="$2" marker="$3"
    local script_url="${4:-$SCRIPT_URL}"
    cat >"$path" <<EOF
#!/usr/bin/env bash
APP_NAME="vpsbox"
VPSBOX_VERSION="$version"
SCRIPT_URL="$script_url"
vpsbox_main() {
    printf '%s\n' '$marker'
}
if [[ "\${BASH_SOURCE[0]}" == "\$0" ]]; then
    vpsbox_main "\$@"
fi
EOF
    chmod 755 "$path"
}

assert_fixture_version() {
    local file="$1" version="$2"

    if ! grep -Fqx -- "VPSBOX_VERSION=\"$version\"" "$file"; then
        fail "文件版本不符合预期（期望：$version）"
    fi
}

curl() {
    local output="" url=""

    while [ "$#" -gt 0 ]; do
        case "$1" in
            -o)
                output="${2:-}"
                shift 2
                ;;
            https://*)
                url="$1"
                shift
                ;;
            *) shift ;;
        esac
    done
    [ -n "$output" ] && [ -n "$url" ] || return 2
    printf '%s\n' "$url" >> "$MOCK_CURL_LOG"
    if [ -n "$MOCK_CURL_FAIL_URLS" ] &&
        grep -Fqx -- "$url" <<< "$MOCK_CURL_FAIL_URLS"; then
        return 22
    fi
    cp "$MOCK_REMOTE_SCRIPT" "$output"
}

install_command_alias() {
    printf '%s\n' alias >> "$MOCK_EVENT_LOG"
}

cleanup_vpsbox_lock() {
    printf '%s\n' cleanup-lock >> "$MOCK_EVENT_LOG"
}

reexec_updated_vpsbox() {
    printf 'reexec:%s\n' "${1:-}" >> "$MOCK_EVENT_LOG"
}

acquire_lock() {
    printf '%s\n' acquire-lock >> "$MOCK_EVENT_LOG"
}

reset_update_case() {
    local name="$1"

    CASE_DIR="$TEST_TMP/$name"
    mkdir -p "$CASE_DIR"
    CMD_PATH="$CASE_DIR/vpsbox"
    MOCK_REMOTE_SCRIPT="$CASE_DIR/remote.sh"
    MOCK_EVENT_LOG="$CASE_DIR/events.log"
    MOCK_CURL_LOG="$CASE_DIR/curl.log"
    MOCK_CURL_FAIL_URLS=""
    : > "$MOCK_EVENT_LOG"
    : > "$MOCK_CURL_LOG"
    RUNTIME_DIR="$CASE_DIR/run"
    mkdir -p "$RUNTIME_DIR"
    REMOTE_VERSION="v9.9.9"
    UPDATE_AVAILABLE=1
}

test_version_relation() {
    assert_eq newer "$(version_relation v1.2.4 v1.2.3)"
    assert_eq same "$(version_relation 1.2.3 v1.2.3)"
    assert_eq older "$(version_relation v1.2.2 1.2.3)"
    assert_eq newer "$(version_relation v1.3.0 v1.2.99)"
    if version_relation v1.2 v1.2.3 >/dev/null 2>&1; then
        fail "畸形版本不应通过比较"
    fi
}

test_username_migration_identity_compatibility() {
    local legacy="$TEST_TMP/legacy-old-owner.sh"
    local future="$TEST_TMP/future-new-owner.sh"
    local third_party="$TEST_TMP/third-party.sh"

    grep -Fqx -- 'SCRIPT_URL="https://raw.githubusercontent.com/TianPingXi/vpsbox/main/vpsbox.sh"' \
        "$REPO_DIR/vpsbox.sh" ||
        fail "v1.0.24 必须使用 TianPingXi 作为主地址"
    grep -Fqx -- 'LEGACY_SCRIPT_URL="https://raw.githubusercontent.com/QXTianPing/vpsbox/main/vpsbox.sh"' \
        "$REPO_DIR/vpsbox.sh" ||
        fail "必须只保留旧地址用于本地历史备份身份兼容"

    write_fixture "$legacy" "$UPDATE_TEST_OLDER" legacy "$LEGACY_SCRIPT_URL"
    vpsbox_script_identity_valid "$legacy" ||
        fail "v1.0.24 必须能识别并恢复 v1.0.23 旧地址备份"

    write_fixture "$future" "$UPDATE_TEST_NEWER" future "$SCRIPT_URL"
    vpsbox_script_identity_valid "$future" ||
        fail "v1.0.24 必须接受使用 TianPingXi 地址的候选"

    write_fixture "$third_party" "$UPDATE_TEST_NEWER" third-party \
        "https://raw.githubusercontent.com/example/vpsbox/main/vpsbox.sh"
    if vpsbox_script_identity_valid "$third_party"; then
        fail "第三方仓库地址不得通过项目身份校验"
    fi
}

test_vpsbox_same_is_noop() {
    local output="$TEST_TMP/same.out"
    reset_update_case same
    write_fixture "$CMD_PATH" "$UPDATE_TEST_CURRENT" installed
    printf 'keep-backup\n' > "${CMD_PATH}.previous"
    write_fixture "$MOCK_REMOTE_SCRIPT" "$UPDATE_TEST_CURRENT" remote

    update_vpsbox > "$output" 2>&1 || fail "相同版本应正常返回"

    assert_file_contains "$output" '当前已是最新版，无需更新'
    assert_file_contains "$CMD_PATH" 'installed'
    assert_file_contains "${CMD_PATH}.previous" '^keep-backup$'
    assert_empty_file "$MOCK_EVENT_LOG" "相同版本不得触发替换后的副作用"
    assert_eq "0" "$UPDATE_AVAILABLE"
    assert_eq "" "$REMOTE_VERSION"
}

test_vpsbox_older_is_noop() {
    local output="$TEST_TMP/older.out"
    reset_update_case older
    write_fixture "$CMD_PATH" "$UPDATE_TEST_CURRENT" installed
    printf 'keep-backup\n' > "${CMD_PATH}.previous"
    write_fixture "$MOCK_REMOTE_SCRIPT" "$UPDATE_TEST_OLDER" remote

    update_vpsbox > "$output" 2>&1 || fail "远端旧版本应安全返回"

    assert_file_contains "$output" '低于当前版本.*已拒绝降级'
    assert_file_contains "$CMD_PATH" 'installed'
    assert_file_contains "${CMD_PATH}.previous" '^keep-backup$'
    assert_empty_file "$MOCK_EVENT_LOG" "远端旧版本不得触发替换后的副作用"
}

test_vpsbox_newer_updates_once() {
    reset_update_case newer
    write_fixture "$CMD_PATH" "$UPDATE_TEST_CURRENT" installed
    write_fixture "$MOCK_REMOTE_SCRIPT" "$UPDATE_TEST_NEWER" remote

    update_vpsbox > "$TEST_TMP/newer.out" 2>&1 || fail "远端新版本应更新成功"

    assert_fixture_version "$CMD_PATH" "$UPDATE_TEST_NEWER"
    assert_file_contains "$CMD_PATH" 'remote'
    assert_file_contains "${CMD_PATH}.previous" 'installed'
    assert_file_contains "$MOCK_EVENT_LOG" '^alias$'
    assert_file_contains "$MOCK_EVENT_LOG" '^cleanup-lock$'
    grep -Fqx -- "reexec:${CMD_PATH}.previous" "$MOCK_EVENT_LOG" ||
        fail "更新后重新执行必须携带本次 .previous 备份路径"
    assert_eq "$SCRIPT_URL" "$(cat "$MOCK_CURL_LOG")" \
        "新地址可用时只应访问当前官方地址"
}

test_vpsbox_never_fetches_old_owner_url() {
    local primary_count legacy_count

    reset_update_case owner-failure
    write_fixture "$CMD_PATH" "$UPDATE_TEST_CURRENT" installed
    printf 'keep-backup\n' >"${CMD_PATH}.previous"
    write_fixture "$MOCK_REMOTE_SCRIPT" "$UPDATE_TEST_NEWER" remote
    MOCK_CURL_FAIL_URLS="$SCRIPT_URL"
    sleep() { :; }

    if update_vpsbox >"$TEST_TMP/owner-failure.out" 2>&1; then
        fail "当前官方地址失败时更新必须失败"
    fi

    assert_file_contains "$CMD_PATH" 'installed'
    assert_file_contains "${CMD_PATH}.previous" '^keep-backup$'
    primary_count="$(grep -Fxc -- "$SCRIPT_URL" "$MOCK_CURL_LOG" || true)"
    legacy_count="$(grep -Fxc -- "$LEGACY_SCRIPT_URL" "$MOCK_CURL_LOG" || true)"
    assert_eq 3 "$primary_count" "应只重试当前官方地址"
    assert_eq 0 "$legacy_count" "不得从可被重新注册的旧用户名下载脚本"
}

test_primary_url_failure_preserves_current() {
    local primary_count

    reset_update_case primary-url-fail
    write_fixture "$CMD_PATH" "$UPDATE_TEST_CURRENT" installed
    printf 'keep-backup\n' >"${CMD_PATH}.previous"
    write_fixture "$MOCK_REMOTE_SCRIPT" "$UPDATE_TEST_NEWER" remote
    MOCK_CURL_FAIL_URLS="$SCRIPT_URL"
    sleep() { :; }

    if update_vpsbox >"$TEST_TMP/primary-url-fail.out" 2>&1; then
        fail "当前官方地址失败时更新必须报失败"
    fi

    assert_file_contains "$CMD_PATH" 'installed'
    assert_file_contains "${CMD_PATH}.previous" '^keep-backup$'
    assert_empty_file "$MOCK_EVENT_LOG" "下载失败不得触发替换后的副作用"
    primary_count="$(grep -Fxc -- "$SCRIPT_URL" "$MOCK_CURL_LOG" || true)"
    assert_eq 3 "$primary_count" "每轮都应尝试新主地址"
}

test_vpsbox_invalid_download_preserves_current() {
    local output="$TEST_TMP/invalid.out"
    reset_update_case invalid
    write_fixture "$CMD_PATH" "$UPDATE_TEST_CURRENT" installed
    printf 'keep-backup\n' > "${CMD_PATH}.previous"
    printf '#!/usr/bin/env bash\nif then\n' > "$MOCK_REMOTE_SCRIPT"

    if update_vpsbox > "$output" 2>&1; then
        fail "语法损坏的远程脚本必须报失败"
    fi

    assert_file_contains "$output" '未通过语法检查'
    assert_file_contains "$CMD_PATH" 'installed'
    assert_file_contains "${CMD_PATH}.previous" '^keep-backup$'
    assert_empty_file "$MOCK_EVENT_LOG" "下载校验失败不得触发替换后的副作用"
}

test_vpsbox_wrong_project_preserves_current() {
    local output="$TEST_TMP/wrong-project.out"
    reset_update_case wrong-project
    write_fixture "$CMD_PATH" "$UPDATE_TEST_CURRENT" installed
    printf 'keep-backup\n' > "${CMD_PATH}.previous"
    cat > "$MOCK_REMOTE_SCRIPT" <<EOF
#!/usr/bin/env bash
VPSBOX_VERSION="$UPDATE_TEST_NEWER"
printf '%s\n' wrong-project
EOF
    chmod 755 "$MOCK_REMOTE_SCRIPT"

    if update_vpsbox > "$output" 2>&1; then
        fail "仅伪造高版本号的错误项目脚本必须报失败"
    fi

    assert_file_contains "$output" '缺少 vpsbox 项目标识或必要入口'
    assert_file_contains "$CMD_PATH" 'installed'
    assert_file_contains "${CMD_PATH}.previous" '^keep-backup$'
    assert_empty_file "$MOCK_EVENT_LOG" "项目身份校验失败不得触发替换后的副作用"
}

test_vpsbox_reexec_failure_restores_previous() {
    local output="$TEST_TMP/reexec-failure.out"
    reset_update_case reexec-failure
    write_fixture "$CMD_PATH" "$UPDATE_TEST_CURRENT" installed "$LEGACY_SCRIPT_URL"
    write_fixture "$MOCK_REMOTE_SCRIPT" "$UPDATE_TEST_NEWER" remote
    reexec_updated_vpsbox() {
        printf 'reexec-failed:%s\n' "${1:-}" >> "$MOCK_EVENT_LOG"
        return 42
    }

    if update_vpsbox > "$output" 2>&1; then
        fail "新版重新执行失败时应返回失败"
    fi

    assert_fixture_version "$CMD_PATH" "$UPDATE_TEST_CURRENT"
    assert_file_contains "$CMD_PATH" 'installed'
    assert_fixture_version "${CMD_PATH}.previous" "$UPDATE_TEST_CURRENT"
    grep -Fqx -- "reexec-failed:${CMD_PATH}.previous" "$MOCK_EVENT_LOG" ||
        fail "重执行失败路径未收到本次备份路径"
    assert_file_contains "$MOCK_EVENT_LOG" '^acquire-lock$'
    assert_file_contains "$output" '已从 .*previous 恢复旧版 vpsbox'
}

test_pending_update_startup_failure_restores_previous() {
    local status

    reset_update_case startup-rollback
    write_fixture "${CMD_PATH}.previous" "$UPDATE_TEST_CURRENT" installed
    cat > "$CMD_PATH" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$REPO_DIR/vpsbox.sh"
CMD_PATH="$TARGET_PATH"
RUNTIME_DIR="$RUNTIME_TARGET"
LOCK_FILE="$RUNTIME_DIR/vpsbox.lock"
LOCK_DIR="$RUNTIME_DIR/lockdir"
install_command_alias() { :; }
need_root() { return 42; }
vpsbox_main
EOF
    chmod 755 "$CMD_PATH"

    set +e
    REPO_DIR="$REPO_DIR" TARGET_PATH="$CMD_PATH" RUNTIME_TARGET="$RUNTIME_DIR" bash -c '
        set -euo pipefail
        source "$REPO_DIR/vpsbox.sh"
        CMD_PATH="$TARGET_PATH"
        RUNTIME_DIR="$RUNTIME_TARGET"
        LOCK_FILE="$RUNTIME_DIR/vpsbox.lock"
        LOCK_DIR="$RUNTIME_DIR/lockdir"
        install_command_alias() { :; }
        reexec_updated_vpsbox "${TARGET_PATH}.previous"
    ' >"$TEST_TMP/startup-rollback.out" 2>&1
    status=$?
    set -e

    assert_eq 42 "$status" "新版启动失败的原退出状态不应被回滚处理吞掉"
    assert_fixture_version "$CMD_PATH" "$UPDATE_TEST_CURRENT"
    assert_file_contains "$CMD_PATH" 'installed'
    assert_fixture_version "${CMD_PATH}.previous" "$UPDATE_TEST_CURRENT"
    assert_file_contains "$TEST_TMP/startup-rollback.out" '未完成首次界面启动'
    assert_file_contains "$TEST_TMP/startup-rollback.out" '已从 .*previous 恢复旧版 vpsbox'
}

test_top_level_startup_failure_restores_previous() {
    local status restored=0

    reset_update_case top-level-rollback
    write_fixture "${CMD_PATH}.previous" "$UPDATE_TEST_CURRENT" installed
    cat > "$CMD_PATH" <<EOF
#!/usr/bin/env bash
exit 41
APP_NAME="vpsbox"
VPSBOX_VERSION="$UPDATE_TEST_NEWER"
SCRIPT_URL="https://raw.githubusercontent.com/TianPingXi/vpsbox/main/vpsbox.sh"
vpsbox_main() {
    printf '%s\n' should-not-run
}
if [[ "\${BASH_SOURCE[0]}" == "\$0" ]]; then
    vpsbox_main "\$@"
fi
EOF
    chmod 755 "$CMD_PATH"
    vpsbox_script_identity_valid "$CMD_PATH" ||
        fail "测试候选应能通过现有静态身份校验"

    set +e
    REPO_DIR="$REPO_DIR" TARGET_PATH="$CMD_PATH" RUNTIME_TARGET="$RUNTIME_DIR" bash -c '
        set -euo pipefail
        source "$REPO_DIR/vpsbox.sh"
        CMD_PATH="$TARGET_PATH"
        RUNTIME_DIR="$RUNTIME_TARGET"
        LOCK_FILE="$RUNTIME_DIR/vpsbox.lock"
        LOCK_DIR="$RUNTIME_DIR/lockdir"
        install_command_alias() { :; }
        reexec_updated_vpsbox "${TARGET_PATH}.previous"
    ' >"$TEST_TMP/top-level-rollback.out" 2>&1
    status=$?
    set -e

    assert_eq 41 "$status" "候选顶层退出码不应被监护进程吞掉"
    for _ in {1..50}; do
        if grep -Fq installed "$CMD_PATH" 2>/dev/null; then
            restored=1
            break
        fi
        sleep 0.1
    done
    assert_eq 1 "$restored" "候选在进入 vpsbox_main 前退出时应自动恢复旧版"
    assert_fixture_version "$CMD_PATH" "$UPDATE_TEST_CURRENT"
    assert_file_contains "$CMD_PATH" 'installed'
}

test_pending_update_confirmation_prevents_rollback() {
    local ready_dir ready

    reset_update_case startup-confirmed
    write_fixture "$CMD_PATH" "$UPDATE_TEST_NEWER" remote
    write_fixture "${CMD_PATH}.previous" "$UPDATE_TEST_CURRENT" installed
    ready_dir="$RUNTIME_DIR/update-startup.confirmed"
    ready="$ready_dir/ready"
    mkdir -p "$ready_dir"
    PENDING_VPSBOX_UPDATE_BACKUP="${CMD_PATH}.previous"
    PENDING_VPSBOX_UPDATE_READY_FILE="$ready"
    VPSBOX_UPDATE_STARTUP_CONFIRMED=0

    confirm_pending_vpsbox_update
    rollback_pending_vpsbox_update

    assert_fixture_version "$CMD_PATH" "$UPDATE_TEST_NEWER"
    assert_file_contains "$CMD_PATH" 'remote'
    assert_eq "" "$PENDING_VPSBOX_UPDATE_BACKUP"
    assert_eq "" "$PENDING_VPSBOX_UPDATE_READY_FILE"
    assert_eq 1 "$VPSBOX_UPDATE_STARTUP_CONFIRMED"
    [ -f "$ready" ] || fail "确认新版启动时应通知父进程 watchdog"
}

test_stale_previous_without_handshake_is_ignored() {
    reset_update_case startup-no-handshake
    write_fixture "$CMD_PATH" "$UPDATE_TEST_NEWER" remote
    write_fixture "${CMD_PATH}.previous" "$UPDATE_TEST_CURRENT" installed
    PENDING_VPSBOX_UPDATE_BACKUP=""
    PENDING_VPSBOX_UPDATE_READY_FILE=""
    VPSBOX_UPDATE_STARTUP_CONFIRMED=0

    rollback_pending_vpsbox_update

    assert_fixture_version "$CMD_PATH" "$UPDATE_TEST_NEWER"
    assert_file_contains "$CMD_PATH" 'remote'
}

test_pending_update_rejects_unexpected_backup_path() {
    local ready_dir

    reset_update_case startup-invalid-backup
    write_fixture "$CMD_PATH" "$UPDATE_TEST_NEWER" remote
    write_fixture "$CASE_DIR/unexpected.previous" "$UPDATE_TEST_CURRENT" installed
    ready_dir="$RUNTIME_DIR/update-startup.invalid"
    mkdir -p "$ready_dir"
    PENDING_VPSBOX_UPDATE_BACKUP="$CASE_DIR/unexpected.previous"
    PENDING_VPSBOX_UPDATE_READY_FILE="$ready_dir/ready"
    VPSBOX_UPDATE_STARTUP_CONFIRMED=0

    if rollback_pending_vpsbox_update >"$TEST_TMP/invalid-backup.out" 2>&1; then
        fail "启动回滚不得接受非 ${CMD_PATH}.previous 路径"
    fi
    assert_fixture_version "$CMD_PATH" "$UPDATE_TEST_NEWER"
    assert_file_contains "$TEST_TMP/invalid-backup.out" '拒绝使用非预期'
}

MOCK_SINGBOX_VERSION=""
MOCK_SINGBOX_EVENT_LOG=""

singbox_installed() { return 0; }
singbox_version() { printf '%s\n' "$MOCK_SINGBOX_VERSION"; }
service_is_running() { return 1; }
service_is_enabled() { return 1; }
service_manager_is_active() { return 1; }
service_stop() { printf '%s\n' service-stop >> "$MOCK_SINGBOX_EVENT_LOG"; }
stop_singbox_config_processes() { printf '%s\n' process-stop >> "$MOCK_SINGBOX_EVENT_LOG"; }
node_exists() { return 1; }
install_deps() { printf '%s\n' deps >> "$MOCK_SINGBOX_EVENT_LOG"; }
singbox_binary_is_package_managed() { return 0; }
prepare_singbox_rollback_package() {
    local package="$2/sing-box-old.pkg"
    : > "$package"
    printf '%s\n' "$package"
}
run_singbox_installer() {
    printf 'installer:%s\n' "${1:-$SINGBOX_RELEASE_VERSION}" >> "$MOCK_SINGBOX_EVENT_LOG"
    MOCK_SINGBOX_VERSION="${1:-$SINGBOX_RELEASE_VERSION}"
}
restore_singbox_service_state() {
    printf 'restore:%s:%s\n' "$1" "$2" >> "$MOCK_SINGBOX_EVENT_LOG"
}

reset_singbox_case() {
    local name="$1"

    MOCK_SINGBOX_EVENT_LOG="$TEST_TMP/singbox-$name.log"
    : > "$MOCK_SINGBOX_EVENT_LOG"
}

test_singbox_version_guards() {
    local fake_bin="$TEST_TMP/bin"
    mkdir -p "$fake_bin"
    printf '#!/usr/bin/env bash\nexit 0\n' > "$fake_bin/sing-box"
    chmod 755 "$fake_bin/sing-box"
    PATH="$fake_bin:$PATH"

    reset_singbox_case same
    MOCK_SINGBOX_VERSION="$SINGBOX_RELEASE_VERSION"
    update_singbox > "$TEST_TMP/singbox-same.out" 2>&1 || fail "相同 sing-box 版本应正常返回"
    assert_empty_file "$MOCK_SINGBOX_EVENT_LOG" "相同版本不得安装依赖或二进制"

    reset_singbox_case higher
    MOCK_SINGBOX_VERSION="1.14.0"
    update_singbox > "$TEST_TMP/singbox-higher.out" 2>&1 || fail "较高 sing-box 版本应拒绝降级并正常返回"
    assert_empty_file "$MOCK_SINGBOX_EVENT_LOG" "较高版本不得隐式降级"
    assert_file_contains "$TEST_TMP/singbox-higher.out" '已拒绝隐式降级'

    reset_singbox_case lower
    MOCK_SINGBOX_VERSION="1.13.13"
    update_singbox > "$TEST_TMP/singbox-lower.out" 2>&1 || fail "较低 sing-box 版本应更新"
    assert_file_contains "$MOCK_SINGBOX_EVENT_LOG" '^deps$'
    assert_file_contains "$MOCK_SINGBOX_EVENT_LOG" '^installer:1\.13\.14$'
}

main() {
    local test status passed=0
    local -a tests=(
        test_version_relation
        test_username_migration_identity_compatibility
        test_vpsbox_same_is_noop
        test_vpsbox_older_is_noop
        test_vpsbox_newer_updates_once
        test_vpsbox_never_fetches_old_owner_url
        test_primary_url_failure_preserves_current
        test_vpsbox_invalid_download_preserves_current
        test_vpsbox_wrong_project_preserves_current
        test_vpsbox_reexec_failure_restores_previous
        test_pending_update_startup_failure_restores_previous
        test_top_level_startup_failure_restores_previous
        test_pending_update_confirmation_prevents_rollback
        test_stale_previous_without_handshake_is_ignored
        test_pending_update_rejects_unexpected_backup_path
        test_singbox_version_guards
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
    printf '%s update mock tests passed.\n' "$passed"
}

main "$@"
