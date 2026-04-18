#!/usr/bin/env bats
# =============================================================================
# stash-safety.bats — Tests for stash-safety.sh helper (Issue #555)
# =============================================================================
# Sprint-bug-106. Validates the stash_with_guard helper that wraps
# git stash push/pop with count-delta invariants.

setup() {
    export PROJECT_ROOT="$BATS_TEST_DIRNAME/../.."
    export HELPER="$PROJECT_ROOT/.claude/scripts/stash-safety.sh"
    export REPO="$BATS_TEST_TMPDIR/repo"

    mkdir -p "$REPO"
    cd "$REPO"

    git init -q
    git config user.email "test@example.com"
    git config user.name "Test"
    git config commit.gpgsign false 2>/dev/null || true

    echo "v1" > file.txt
    git add file.txt
    git commit -qm "init"
}

teardown() {
    cd /
    rm -rf "$BATS_TEST_TMPDIR/repo" 2>/dev/null || true
}

# =========================================================================
# SS-T1: happy path — callback runs, stash push/pop cleanly
# =========================================================================

@test "stash_with_guard happy path: clean push, run callback, clean pop" {
    cd "$REPO"
    echo "v2" > file.txt

    source "$HELPER"
    run stash_with_guard "happy" -- true
    [ "$status" -eq 0 ]

    # Worktree content restored
    [ "$(cat file.txt)" = "v2" ]
    # No stash entries remain
    [ "$(_stash_count)" = "0" ]
}

# =========================================================================
# SS-T2: callback exit propagated
# =========================================================================

@test "stash_with_guard preserves callback non-zero exit" {
    cd "$REPO"
    echo "v2" > file.txt

    source "$HELPER"
    run stash_with_guard "fail-cb" -- false
    [ "$status" -eq 1 ]
    [ "$(cat file.txt)" = "v2" ]
}

# =========================================================================
# SS-T3: missing callback is a usage error (exit 12)
# =========================================================================

@test "stash_with_guard without callback exits 12" {
    cd "$REPO"

    source "$HELPER"
    run stash_with_guard "no-cb" --
    [ "$status" -eq 12 ]
    [[ "$output" == *"STASH_SAFETY_VIOLATION"* ]]
    [[ "$output" == *"requires a callback"* ]]
}

# =========================================================================
# SS-T4: missing `--` delimiter is a usage error (exit 12)
# =========================================================================

@test "stash_with_guard without -- delimiter exits 12" {
    cd "$REPO"

    source "$HELPER"
    run stash_with_guard "bad-delim" true
    [ "$status" -eq 12 ]
    [[ "$output" == *"STASH_SAFETY_VIOLATION"* ]]
    [[ "$output" == *"requires '--'"* ]]
}

# =========================================================================
# SS-T5: mid-flight stash shift detected (exit 11)
# =========================================================================
# The hazard the helper exists to catch: something between push and pop
# drops the helper's stash, leaving count mismatched. Simulate by dropping
# the helper's stash inside the callback.

@test "stash_with_guard detects dropped stash (pop fails on empty)" {
    cd "$REPO"
    echo "v2" > file.txt

    source "$HELPER"
    run stash_with_guard "will-be-dropped" -- git stash drop
    [ "$status" -eq 11 ]
    [[ "$output" == *"STASH_SAFETY_VIOLATION"* ]]
    # When callback drops the helper's own stash, pop fails (no entries
    # found). Count delta happens to match (0 → 0), so the violation
    # surfaces via the pop-failed branch.
    [[ "$output" == *"stash pop failed"* ]]
}

# =========================================================================
# SS-T6: mid-flight extra stash pushed detected (exit 11)
# =========================================================================
# Simulates pre-commit's internal stash collision: an extra stash pushed
# inside the callback shifts indexes.

@test "stash_with_guard detects extra stash pushed by callback" {
    cd "$REPO"
    echo "v2" > file.txt

    # Create a callback that introduces a second stash
    _extra_stash_callback() {
        echo "v3" > another.txt
        git add another.txt
        git stash push -m "injected" --include-untracked
    }
    export -f _extra_stash_callback 2>/dev/null || true

    source "$HELPER"
    run stash_with_guard "outer" -- _extra_stash_callback
    [ "$status" -eq 11 ]
    [[ "$output" == *"STASH_SAFETY_VIOLATION"* ]]
}

# =========================================================================
# SS-T7: empty-worktree push no-op detected (exit 10)
# =========================================================================
# If the worktree is clean, `git stash push` no-ops (no stash created).
# Without the count check, the callback would run on "stashed" data that
# doesn't exist, and `pop` would operate on the wrong entry (the previous
# stash, if any).

@test "stash_with_guard detects no-op push on clean worktree" {
    cd "$REPO"
    # Do NOT modify file.txt — worktree is clean

    source "$HELPER"
    run stash_with_guard "no-op" -- true
    [ "$status" -eq 10 ]
    [[ "$output" == *"STASH_SAFETY_VIOLATION"* ]]
}

# =========================================================================
# SS-T8: helper surfaces stash output (no `| tail`, no `2>/dev/null`)
# =========================================================================

@test "stash_with_guard emits stash push output to stdout (not swallowed)" {
    cd "$REPO"
    echo "v2" > file.txt

    source "$HELPER"
    run stash_with_guard "surfaced" -- true
    [ "$status" -eq 0 ]
    # `git stash push` prints "Saved working directory and index state" —
    # that output MUST appear; it's the user's main diagnostic.
    [[ "$output" == *"Saved working directory"* ]] || [[ "$output" == *"working tree"* ]]
}

# =========================================================================
# SS-T9: idempotent re-source (no function re-declaration errors)
# =========================================================================

@test "stash_with_guard is idempotent on re-source" {
    source "$HELPER"
    source "$HELPER"
    # If re-source crashed, bats would fail. Also verify function still works.
    cd "$REPO"
    echo "v2" > file.txt
    run stash_with_guard "reentrant" -- true
    [ "$status" -eq 0 ]
}

# =========================================================================
# SS-T10: invariant — no stash pop output suppression in .claude/scripts/
# =========================================================================
# Guards against regression: nothing in .claude/scripts/**/*.sh should
# pipe `git stash pop` through `tail` or follow it with `|| true`.

@test "invariant: no 'git stash pop | tail' in .claude/scripts/" {
    cd "$PROJECT_ROOT"
    # Exclude stash-safety.sh (which documents the pattern as a negative
    # example in its header comment).
    run bash -c "grep -rE 'stash[[:space:]]+pop[^|]*\|[[:space:]]*tail' .claude/scripts/ --exclude=stash-safety.sh 2>/dev/null || true"
    [ -z "$output" ]
}

@test "invariant: no 'git stash pop ... || true' in .claude/scripts/" {
    cd "$PROJECT_ROOT"
    run bash -c "grep -rE 'stash[[:space:]]+pop[^|]*\|\|[[:space:]]*true' .claude/scripts/ 2>/dev/null || true"
    [ -z "$output" ]
}

@test "invariant: no '2>/dev/null' on git stash in .claude/scripts/ (excluding helper)" {
    cd "$PROJECT_ROOT"
    # Helper itself is allowed to reference `2>/dev/null` in comments/docs.
    run bash -c "grep -rE 'git[[:space:]]+stash[[:space:]]+(push|pop)[^#]*2>/dev/null' .claude/scripts/ --exclude=stash-safety.sh 2>/dev/null || true"
    [ -z "$output" ]
}
