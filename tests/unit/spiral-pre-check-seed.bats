#!/usr/bin/env bats
# =============================================================================
# spiral-pre-check-seed.bats — tests for #575 item 3 (SEED environment gate)
# =============================================================================
# Validates:
# - Hard-fail when CWD is not a git work tree (cycle-084 class)
# - Hard-fail when grimoires/loa/ missing from CWD
# - Hard-fail when cycle dir / parent not writable
# - Warn (not fail) when SEED_CONTEXT path doesn't resolve
# - Strict mode promotes warnings to errors
# - Records PRE_CHECK_SEED trajectory entry
# =============================================================================

setup() {
    export PROJECT_ROOT="$BATS_TEST_DIRNAME/../.."
    export EVIDENCE_SH="$PROJECT_ROOT/.claude/scripts/spiral-evidence.sh"
    export TEST_DIR="$BATS_TEST_TMPDIR/spiral-pre-seed-test"
    mkdir -p "$TEST_DIR"
}

teardown() {
    [[ -d "$TEST_DIR" ]] && rm -rf "$TEST_DIR"
}

# Helper: initialize a fake git repo with grimoires/loa layout
_make_git_project() {
    local dir="$1"
    mkdir -p "$dir/grimoires/loa"
    mkdir -p "$dir/.run/cycles"
    (cd "$dir" && git init -q 2>&1 | head -0; git config user.email test@test; git config user.name test)
}

# =========================================================================
# PCS-T1: happy path
# =========================================================================

@test "pre_check passes in a valid git project with grimoires/loa and writable cycle dir" {
    _make_git_project "$TEST_DIR/proj"
    mkdir -p "$TEST_DIR/proj/.run/cycles/cycle-001"

    run bash -c "
        cd '$TEST_DIR/proj'
        source '$EVIDENCE_SH'
        unset SEED_CONTEXT
        _pre_check_seed '$TEST_DIR/proj/.run/cycles/cycle-001'
    "
    [ "$status" -eq 0 ]
}

@test "pre_check passes when cycle dir doesn't exist but parent is writable" {
    _make_git_project "$TEST_DIR/proj"

    run bash -c "
        cd '$TEST_DIR/proj'
        source '$EVIDENCE_SH'
        unset SEED_CONTEXT
        _pre_check_seed '$TEST_DIR/proj/.run/cycles/cycle-002'
    "
    [ "$status" -eq 0 ]
}

# =========================================================================
# PCS-T2: CWD checks (cycle-084 class)
# =========================================================================

@test "pre_check fails when CWD is not a git work tree" {
    # No git init — CWD is just a plain directory
    mkdir -p "$TEST_DIR/not-a-git-repo/grimoires/loa"

    run bash -c "
        cd '$TEST_DIR/not-a-git-repo'
        source '$EVIDENCE_SH'
        unset SEED_CONTEXT
        _pre_check_seed '$TEST_DIR/not-a-git-repo/.run/cycles/cycle-001'
    "
    [ "$status" -ne 0 ]
    [[ "$output" == *"not inside a git work tree"* ]]
}

@test "pre_check fails when grimoires/loa/ is missing from CWD" {
    mkdir -p "$TEST_DIR/no-grimoires"
    (cd "$TEST_DIR/no-grimoires" && git init -q)

    run bash -c "
        cd '$TEST_DIR/no-grimoires'
        source '$EVIDENCE_SH'
        unset SEED_CONTEXT
        _pre_check_seed '$TEST_DIR/no-grimoires/.run/cycles/cycle-001'
    "
    [ "$status" -ne 0 ]
    [[ "$output" == *"grimoires/loa/ not found"* ]]
    [[ "$output" == *"cycle-084 class"* ]]
}

# =========================================================================
# PCS-T3: cycle dir writability
# =========================================================================

@test "pre_check fails when cycle dir parent is not writable" {
    _make_git_project "$TEST_DIR/proj"
    mkdir -p "$TEST_DIR/proj/readonly-parent"
    chmod 555 "$TEST_DIR/proj/readonly-parent"

    run bash -c "
        cd '$TEST_DIR/proj'
        source '$EVIDENCE_SH'
        unset SEED_CONTEXT
        _pre_check_seed '$TEST_DIR/proj/readonly-parent/cycle-001'
    "
    # Restore permissions for cleanup
    chmod 755 "$TEST_DIR/proj/readonly-parent"

    [ "$status" -ne 0 ]
    [[ "$output" == *"not writable"* ]]
}

# =========================================================================
# PCS-T4: SEED_CONTEXT warnings (non-blocking by default)
# =========================================================================

@test "pre_check warns (but passes) when SEED_CONTEXT path missing" {
    _make_git_project "$TEST_DIR/proj"
    mkdir -p "$TEST_DIR/proj/.run/cycles/cycle-001"

    run bash -c "
        cd '$TEST_DIR/proj'
        source '$EVIDENCE_SH'
        export SEED_CONTEXT='/nonexistent/seed.md'
        _pre_check_seed '$TEST_DIR/proj/.run/cycles/cycle-001'
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN"* ]]
    [[ "$output" == *"does not resolve"* ]]
}

@test "pre_check warns when SEED_CONTEXT file is empty" {
    _make_git_project "$TEST_DIR/proj"
    mkdir -p "$TEST_DIR/proj/.run/cycles/cycle-001"
    touch "$TEST_DIR/proj/empty-seed.md"

    run bash -c "
        cd '$TEST_DIR/proj'
        source '$EVIDENCE_SH'
        export SEED_CONTEXT='$TEST_DIR/proj/empty-seed.md'
        _pre_check_seed '$TEST_DIR/proj/.run/cycles/cycle-001'
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN"* ]]
    [[ "$output" == *"empty"* ]]
}

@test "pre_check passes cleanly when SEED_CONTEXT is unset" {
    _make_git_project "$TEST_DIR/proj"
    mkdir -p "$TEST_DIR/proj/.run/cycles/cycle-001"

    run bash -c "
        cd '$TEST_DIR/proj'
        source '$EVIDENCE_SH'
        unset SEED_CONTEXT
        _pre_check_seed '$TEST_DIR/proj/.run/cycles/cycle-001'
    "
    [ "$status" -eq 0 ]
    # No WARN because nothing to warn about
    [[ "$output" != *"WARN"* ]]
}

@test "pre_check passes with populated SEED_CONTEXT file" {
    _make_git_project "$TEST_DIR/proj"
    mkdir -p "$TEST_DIR/proj/.run/cycles/cycle-001"
    echo "# Real seed content" > "$TEST_DIR/proj/valid-seed.md"

    run bash -c "
        cd '$TEST_DIR/proj'
        source '$EVIDENCE_SH'
        export SEED_CONTEXT='$TEST_DIR/proj/valid-seed.md'
        _pre_check_seed '$TEST_DIR/proj/.run/cycles/cycle-001'
    "
    [ "$status" -eq 0 ]
    [[ "$output" != *"WARN"* ]]
    [[ "$output" != *"FAIL"* ]]
}

# =========================================================================
# PCS-T5: strict mode promotes warnings to errors
# =========================================================================

@test "strict mode promotes missing SEED_CONTEXT to error" {
    _make_git_project "$TEST_DIR/proj"
    mkdir -p "$TEST_DIR/proj/.run/cycles/cycle-001"

    run bash -c "
        cd '$TEST_DIR/proj'
        source '$EVIDENCE_SH'
        export SEED_CONTEXT='/nonexistent/seed.md'
        export SPIRAL_PRE_CHECK_SEED_STRICT=true
        _pre_check_seed '$TEST_DIR/proj/.run/cycles/cycle-001'
    "
    [ "$status" -ne 0 ]
    [[ "$output" == *"WARN"* ]]
}

@test "strict=false (default) keeps warnings non-blocking" {
    _make_git_project "$TEST_DIR/proj"
    mkdir -p "$TEST_DIR/proj/.run/cycles/cycle-001"

    run bash -c "
        cd '$TEST_DIR/proj'
        source '$EVIDENCE_SH'
        export SEED_CONTEXT='/nonexistent/seed.md'
        export SPIRAL_PRE_CHECK_SEED_STRICT=false
        _pre_check_seed '$TEST_DIR/proj/.run/cycles/cycle-001'
    "
    [ "$status" -eq 0 ]
}

# =========================================================================
# PCS-T6: trajectory recording
# =========================================================================

@test "pre_check emits PRE_CHECK_SEED trajectory action when flight recorder active" {
    _make_git_project "$TEST_DIR/proj"
    mkdir -p "$TEST_DIR/proj/.run/cycles/cycle-001"
    touch "$TEST_DIR/proj/.run/cycles/cycle-001/flight-recorder.jsonl"

    bash -c "
        cd '$TEST_DIR/proj'
        source '$EVIDENCE_SH'
        export _FLIGHT_RECORDER='$TEST_DIR/proj/.run/cycles/cycle-001/flight-recorder.jsonl'
        export _FLIGHT_RECORDER_SEQ=0
        unset SEED_CONTEXT
        _pre_check_seed '$TEST_DIR/proj/.run/cycles/cycle-001'
    "
    run jq -r '.phase' "$TEST_DIR/proj/.run/cycles/cycle-001/flight-recorder.jsonl"
    [ "$output" = "PRE_CHECK_SEED" ]

    run jq -r '.action' "$TEST_DIR/proj/.run/cycles/cycle-001/flight-recorder.jsonl"
    [ "$output" = "seed_ready" ]
}

@test "pre_check records PASS verdict when all checks pass" {
    _make_git_project "$TEST_DIR/proj"
    mkdir -p "$TEST_DIR/proj/.run/cycles/cycle-001"
    touch "$TEST_DIR/proj/.run/cycles/cycle-001/flight-recorder.jsonl"

    bash -c "
        cd '$TEST_DIR/proj'
        source '$EVIDENCE_SH'
        export _FLIGHT_RECORDER='$TEST_DIR/proj/.run/cycles/cycle-001/flight-recorder.jsonl'
        export _FLIGHT_RECORDER_SEQ=0
        unset SEED_CONTEXT
        _pre_check_seed '$TEST_DIR/proj/.run/cycles/cycle-001'
    "
    run jq -r '.verdict' "$TEST_DIR/proj/.run/cycles/cycle-001/flight-recorder.jsonl"
    [[ "$output" == PASS:* ]]
}

# =========================================================================
# PCS-T7: missing cycle_dir argument
# =========================================================================

@test "pre_check tolerates empty cycle_dir argument (checks CWD only)" {
    _make_git_project "$TEST_DIR/proj"

    run bash -c "
        cd '$TEST_DIR/proj'
        source '$EVIDENCE_SH'
        unset SEED_CONTEXT
        _pre_check_seed ''
    "
    [ "$status" -eq 0 ]
}
