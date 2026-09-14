#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    INSTALLER="$BATS_TEST_TMPDIR/download"
    FIX="$BATS_TEST_TMPDIR/consumer"
    mkdir -p "$INSTALLER/lib" "$FIX"
    cp "$REPO_ROOT/.claude/scripts/mount-loa.sh" \
        "$REPO_ROOT/.claude/scripts/compat-lib.sh" "$INSTALLER/"
    cp "$REPO_ROOT/.claude/scripts/lib/scaffold-post-merge-workflow.sh" "$INSTALLER/lib/"
    cat > "$INSTALLER/mount-submodule.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[[ -f .claude/.mount-lock ]] || exit 91
kill -0 "$(cat .claude/.mount-lock)" || exit 92
printf '%s\n' "$@" > child-args
exit "${CHILD_STATUS:-0}"
SH
    chmod +x "$INSTALLER/mount-submodule.sh"
    git -C "$FIX" init -q
    cd "$FIX"
}

assert_lock_released() {
    local expected="$1"
    run env CHILD_STATUS="$expected" _LOA_MOUNT_TMPDIR="$INSTALLER" \
        bash "$INSTALLER/mount-loa.sh" --no-commit --ref test-ref
    echo "$output"
    [ "$status" -eq "$expected" ]
    [ "$(cat child-args)" = $'--ref\ntest-ref\n--no-commit' ]
    [ ! -e .claude/.mount-lock ]
    [ ! -e "$INSTALLER" ]
}

@test "#1232: submodule success releases the mount lock and download directory" {
    assert_lock_released 0
}

@test "#1232: submodule failure preserves exit status and releases the mount lock" {
    assert_lock_released 23
}
