#!/usr/bin/env bats
# =============================================================================
# tripwire-handler-rollback.bats — Tests for perform_rollback precheck (#563)
# =============================================================================
# Sprint-bug-109. Validates the untracked-only precheck fix so perform_rollback
# does not return "no_changes" when the worktree has only untracked files.

setup() {
    export PROJECT_ROOT="$BATS_TEST_DIRNAME/../.."
    export SCRIPT="$PROJECT_ROOT/.claude/scripts/tripwire-handler.sh"
    export REPO="$BATS_TEST_TMPDIR/repo"

    mkdir -p "$REPO"
    cd "$REPO"

    git init -q
    git config user.email "test@example.com"
    git config user.name "Test"
    git config commit.gpgsign false 2>/dev/null || true

    echo "v1" > tracked.txt
    git add tracked.txt
    git commit -qm "init"
}

teardown() {
    cd /
    rm -rf "$BATS_TEST_TMPDIR/repo" 2>/dev/null || true
}

# Invoke `perform_rollback` and return only the final stdout line (the verdict).
invoke_rollback() {
    # Source the script, call the function, emit only its verdict.
    bash -c "cd '$REPO' && source '$SCRIPT' && perform_rollback" 2>/dev/null | tail -1
}

# =========================================================================
# TH-T1: clean worktree → no_changes (unchanged behavior)
# =========================================================================

@test "perform_rollback: clean worktree returns no_changes" {
    cd "$REPO"
    run invoke_rollback
    [ "$status" -eq 0 ]
    [ "$output" = "no_changes" ]
}

# =========================================================================
# TH-T2: untracked-only worktree — regression case from #563
# =========================================================================

@test "perform_rollback: untracked-only worktree does NOT return no_changes" {
    cd "$REPO"
    echo "new" > new-untracked.txt
    run invoke_rollback
    [ "$status" -eq 0 ]
    [ "$output" != "no_changes" ]
    # Accept true (stash succeeded) or false (stash failed; we just want
    # the precheck to NOT short-circuit).
    [[ "$output" == "true" || "$output" == "false" ]]
}

# =========================================================================
# TH-T3: tracked-modified worktree — existing behavior preserved
# =========================================================================

@test "perform_rollback: tracked-modified worktree attempts backup" {
    cd "$REPO"
    echo "v2" > tracked.txt
    run invoke_rollback
    [ "$status" -eq 0 ]
    [ "$output" != "no_changes" ]
}

# =========================================================================
# TH-T4: mixed (tracked + untracked) — existing behavior preserved
# =========================================================================

@test "perform_rollback: mixed tracked + untracked attempts backup" {
    cd "$REPO"
    echo "v2" > tracked.txt
    echo "new" > added-untracked.txt
    run invoke_rollback
    [ "$status" -eq 0 ]
    [ "$output" != "no_changes" ]
}

# =========================================================================
# TH-T5: ignored files do NOT trigger a rollback attempt
# =========================================================================
# `--exclude-standard` in ls-files should ignore .gitignore-matched files.
# If a user has only gitignored files in the worktree, we should still
# return no_changes (they're not meant to be rolled back).

@test "perform_rollback: only gitignored files → no_changes" {
    cd "$REPO"
    echo "build/" > .gitignore
    git add .gitignore
    git commit -qm "add gitignore"
    mkdir -p build
    echo "binary" > build/artifact.bin
    # The .gitignore change was committed; worktree only has gitignored
    # build/ artifacts. Those should NOT count as changes worth preserving.
    run invoke_rollback
    [ "$status" -eq 0 ]
    [ "$output" = "no_changes" ]
}

# =========================================================================
# TH-T6: untracked inside a subdirectory also detected
# =========================================================================

@test "perform_rollback: untracked in subdirectory detected" {
    cd "$REPO"
    mkdir -p src
    echo "content" > src/new-file.ts
    run invoke_rollback
    [ "$status" -eq 0 ]
    [ "$output" != "no_changes" ]
}
