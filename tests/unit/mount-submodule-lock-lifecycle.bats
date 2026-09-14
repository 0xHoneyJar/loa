#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    INSTALLER="$BATS_TEST_TMPDIR/download"
    FIX="$BATS_TEST_TMPDIR/consumer"
    mkdir -p "$INSTALLER/lib" "$FIX"
    cp "$REPO_ROOT/.claude/scripts/mount-loa.sh" \
        "$REPO_ROOT/.claude/scripts/compat-lib.sh" "$INSTALLER/"
    cp "$REPO_ROOT/.claude/scripts/lib/scaffold-post-merge-workflow.sh" "$INSTALLER/lib/"
    cp "$REPO_ROOT/.claude/scripts/lib/mount-supervisor.py" "$INSTALLER/lib/"
    cat > "$INSTALLER/mount-submodule.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[[ -d .loa-mount-lock ]] || exit 91
owner=$(cat .loa-mount-lock/owner)
kill -0 "${owner%%:*}" || exit 92
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
    [ ! -e .loa-mount-lock ]
    [ ! -e "$INSTALLER" ]
}

@test "#1232: submodule success releases the mount lock and download directory" {
    assert_lock_released 0
}

@test "#1232: submodule failure preserves exit status and releases the mount lock" {
    assert_lock_released 23
}

@test "#1232: cancellation, terminal input and competing lock owners" {
    run env PYTHONDONTWRITEBYTECODE=1 python3 \
        "$REPO_ROOT/tests/unit/test_mount_reliability.py" -v
    echo "$output"
    [ "$status" -eq 0 ]
}

@test "#1232: generated ignores keep mount ownership out of the install commit" {
    run bash -c '
        source "$1" --source-only
        update_gitignore_for_submodule
        mkdir -p .claude .loa-mount-lock
        printf "owner\n" > .loa-mount-lock/owner
        printf "framework\n" > .claude/kept
        git add .
        [[ "$(git diff --cached --name-only)" == $'"'"'.claude/kept\n.gitignore'"'"' ]]
        git check-ignore .loa-mount-lock/owner
    ' _ "$REPO_ROOT/.claude/scripts/mount-submodule.sh"
    echo "$output"
    [ "$status" -eq 0 ]
}
