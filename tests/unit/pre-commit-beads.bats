#!/usr/bin/env bats
# =============================================================================
# pre-commit-beads.bats — Tests for hardened pre-commit hook (Issue #661)
# =============================================================================
# sprint-bug-128. Validates that the source-of-truth pre-commit template
# captures stderr (not /dev/null), pattern-matches the upstream migration-
# bug signature, and emits a structured diagnostic block instead of the
# canned "Failed to flush" message that hid the actual VDBE error.

setup() {
    export PROJECT_ROOT="$BATS_TEST_DIRNAME/../.."
    export HOOK="$PROJECT_ROOT/.claude/scripts/git-hooks/pre-commit-beads"

    # Hermetic temp git repo with stub PATH for `br` and `git`
    export TMPDIR_TEST="$(mktemp -d)"
    export STUB_BIN="$TMPDIR_TEST/bin"
    mkdir -p "$STUB_BIN"
    export PATH="$STUB_BIN:$PATH"

    # Init a real git repo so `git rev-parse` works inside the hook
    export TEST_REPO="$TMPDIR_TEST/repo"
    mkdir -p "$TEST_REPO/.beads"
    cd "$TEST_REPO"
    git init -q -b main >/dev/null 2>&1
    # Mark the repo as a beads workspace
    touch .beads/.placeholder
}

teardown() {
    if [[ -n "${TMPDIR_TEST:-}" && -d "$TMPDIR_TEST" ]]; then
        rm -rf "$TMPDIR_TEST"
    fi
}

# Helper: install a `br` stub that succeeds
_stub_br_ok() {
    cat >"$STUB_BIN/br" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
    chmod +x "$STUB_BIN/br"
}

# Helper: install a `br` stub that fails with the upstream signature
_stub_br_migration_bug() {
    cat >"$STUB_BIN/br" <<'STUB'
#!/usr/bin/env bash
echo "[ERROR] run_migrations failed: Database(Internal(\"VDBE halted with code 19: NOT NULL constraint failed: dirty_issues.marked_at\"))" >&2
exit 1
STUB
    chmod +x "$STUB_BIN/br"
}

# Helper: install a `br` stub that fails with unrelated stderr
_stub_br_other_failure() {
    cat >"$STUB_BIN/br" <<'STUB'
#!/usr/bin/env bash
echo "Error: connection to remote refused" >&2
exit 1
STUB
    chmod +x "$STUB_BIN/br"
}

# Helper: install a stub that pretends `br` is missing (PATH-shadowing)
_stub_br_missing() {
    rm -f "$STUB_BIN/br"
}

# =========================================================================
# PCB-T1..T2: success path
# =========================================================================

@test "PCB-T1: br succeeds → hook exits 0 with no diagnostic" {
    _stub_br_ok
    cd "$TEST_REPO"
    run "$HOOK"
    [ "$status" -eq 0 ]
    [[ "$output" != *"NOT NULL constraint"* ]]
    [[ "$output" != *"upstream beads_rust"* ]]
}

@test "PCB-T2: br missing → hook exits 0 with skip message" {
    # Bridgebuilder F004 (PR #670): the previous test included /usr/bin and
    # /bin on PATH, so a host-installed `br` would silently satisfy the
    # lookup. Build a hermetic minimal-PATH that contains ONLY the
    # utilities the hook needs (git, sed, mktemp, grep) — and explicitly
    # NOT br. Then assert the skip-branch output prefix to confirm we
    # actually exercised the missing-br path.
    _stub_br_missing
    local safe_bin="$TMPDIR_TEST/safe-bin"
    mkdir -p "$safe_bin"
    for tool in git sed mktemp grep dirname basename; do
        if command -v "$tool" >/dev/null 2>&1; then
            ln -sf "$(command -v "$tool")" "$safe_bin/$tool"
        fi
    done

    # Verify the test PATH genuinely lacks br (skip if host has br on this minimal PATH)
    if PATH="$safe_bin" command -v br >/dev/null 2>&1; then
        skip "minimal PATH unexpectedly resolved br; test infrastructure issue"
    fi

    cd "$TEST_REPO"
    run env PATH="$safe_bin" "$HOOK"
    [ "$status" -eq 0 ]
    # Positive evidence the skip-branch was exercised
    [[ "$output" == *"br command not found"* ]]
}

# =========================================================================
# PCB-T3..T5: known migration-bug signature → structured diagnostic
# =========================================================================

@test "PCB-T3: br migration error → diagnostic block emitted" {
    _stub_br_migration_bug
    cd "$TEST_REPO"
    run "$HOOK"
    # cycle-105 T2.1: on the known upstream migration-bug signature the hook
    # emits the diagnostic but exits 0 so the commit proceeds (CI is the hard
    # gate; operators repair at their convenience). Was exit 1 pre-cycle-105.
    [ "$status" -eq 0 ]
    [[ "$output" == *"br migration error detected (upstream beads_rust"* ]]
    [[ "$output" == *"NOT NULL constraint failed: dirty_issues.marked_at"* ]]
}

@test "PCB-T4: diagnostic includes recommended workaround" {
    _stub_br_migration_bug
    cd "$TEST_REPO"
    run "$HOOK"
    [[ "$output" == *"git commit --no-verify"* ]]
}

@test "PCB-T5: diagnostic includes upstream tracking link" {
    _stub_br_migration_bug
    cd "$TEST_REPO"
    run "$HOOK"
    [[ "$output" == *"github.com/0xHoneyJar/loa/issues/661"* ]]
}

# =========================================================================
# PCB-T6: unrelated failure → verbatim stderr, no swallow
# =========================================================================

@test "PCB-T6: unrelated br failure → captured stderr passes through" {
    _stub_br_other_failure
    cd "$TEST_REPO"
    run "$HOOK"
    [ "$status" -eq 1 ]
    [[ "$output" == *"connection to remote refused"* ]]
    # Must NOT include the migration-specific diagnostic (signature didn't match)
    [[ "$output" != *"upstream beads_rust 0.2.1"* ]]
}

# =============================================================================
# bug-991 / KF-014: linked-worktree support. The hook resolved the main
# checkout's .beads via --git-common-dir but invoked plain `br sync` from the
# worktree CWD, where br finds no .beads and dies with "Beads not initialized".
# =============================================================================

# Helper: br stub that mimics real br's CWD resolution — succeeds only when
# CWD contains .beads, and records its physical CWD for assertions.
_stub_br_cwd_sensitive() {
    cat >"$STUB_BIN/br" <<'STUB'
#!/usr/bin/env bash
pwd -P >> "${BR_CWD_LOG:?}"
if [ -d .beads ]; then
    exit 0
fi
echo "Error: Beads not initialized: run 'br init' first" >&2
exit 1
STUB
    chmod +x "$STUB_BIN/br"
}

@test "PCB-T7 (bug-991): hook runs flush from MAIN repo root inside a linked worktree" {
    _stub_br_cwd_sensitive
    export BR_CWD_LOG="$TMPDIR_TEST/br-cwd.log"
    git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
    git worktree add -q "$TMPDIR_TEST/wt" -b wt-branch
    cd "$TMPDIR_TEST/wt"
    run sh "$HOOK"
    [ "$status" -eq 0 ]
    grep -qx "$(cd "$TEST_REPO" && pwd -P)" "$BR_CWD_LOG"
}

@test "PCB-T8 (bug-991): main-checkout invocation still flushes from the repo root (regression guard)" {
    _stub_br_cwd_sensitive
    export BR_CWD_LOG="$TMPDIR_TEST/br-cwd-main.log"
    run sh "$HOOK"
    [ "$status" -eq 0 ]
    grep -qx "$(cd "$TEST_REPO" && pwd -P)" "$BR_CWD_LOG"
}

@test "PCB-T9 (bug-991): worktree failure path still surfaces verbatim stderr" {
    _stub_br_other_failure
    git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
    git worktree add -q "$TMPDIR_TEST/wt9" -b wt-branch-9
    cd "$TMPDIR_TEST/wt9"
    run sh "$HOOK"
    [ "$status" -eq 1 ]
    [[ "$output" == *"connection to remote refused"* ]]
}
