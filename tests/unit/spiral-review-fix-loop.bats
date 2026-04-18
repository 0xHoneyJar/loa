#!/usr/bin/env bats
# =============================================================================
# spiral-review-fix-loop.bats — Tests for _review_fix_loop (#545)
# =============================================================================
# Sprint-bug-107 cycle-084. Validates that the review fix-loop re-invokes
# _phase_implement_with_feedback when REVIEW returns CHANGES_REQUIRED,
# rather than retrying the same reviewer against the same unchanged
# implementation until circuit-breaker.
#
# Approach: isolate _review_fix_loop by extracting just the function
# under test into a minimal test harness. Mock _run_gate,
# _phase_implement_with_feedback, _record_action, log, _gate_review.

setup() {
    export PROJECT_ROOT="$BATS_TEST_DIRNAME/../.."
    export HARNESS_SCRIPT="$PROJECT_ROOT/.claude/scripts/spiral-harness.sh"
    export TEST_DIR="$BATS_TEST_TMPDIR"

    cat > "$TEST_DIR/test-harness.sh" <<'EOF'
# Minimal mock harness — override the dependencies that _review_fix_loop
# calls. Tests set the behavior of each mock via env vars.

# Counters observed by tests
export _MOCK_RUN_GATE_CALLS=0
export _MOCK_IMPL_FIX_CALLS=0
export _MOCK_RECORD_CALLS=0

# Configurable: space-separated list of review verdicts (PASS or FAIL).
# First token is consumed on the first _run_gate REVIEW call, etc.
: "${_MOCK_REVIEW_VERDICTS:=PASS}"

# Configurable: "PASS" (default) or "FAIL" for _phase_implement_with_feedback
: "${_MOCK_IMPL_FIX_VERDICT:=PASS}"

log() { :; }
error() { echo "ERROR: $*" >&2; }
_record_action() { _MOCK_RECORD_CALLS=$((_MOCK_RECORD_CALLS + 1)); }
_record_failure() { :; }
_gate_review() { :; }

_run_gate() {
    _MOCK_RUN_GATE_CALLS=$((_MOCK_RUN_GATE_CALLS + 1))
    local gate_name="$1"
    [[ "$gate_name" == "REVIEW" ]] || return 0
    # Consume next verdict from the space-separated list
    local first rest
    first=$(echo "$_MOCK_REVIEW_VERDICTS" | awk '{print $1}')
    rest=$(echo "$_MOCK_REVIEW_VERDICTS" | awk '{$1=""; print $0}' | sed 's/^ *//')
    export _MOCK_REVIEW_VERDICTS="$rest"
    if [[ "$first" == "PASS" ]]; then return 0; else return 1; fi
}

_phase_implement_with_feedback() {
    _MOCK_IMPL_FIX_CALLS=$((_MOCK_IMPL_FIX_CALLS + 1))
    if [[ "$_MOCK_IMPL_FIX_VERDICT" == "PASS" ]]; then return 0; else return 1; fi
}
EOF

    # Extract _review_fix_loop from the real script into an isolated file
    awk '/^# _review_fix_loop — review with automatic/,/^}$/' "$HARNESS_SCRIPT" \
        > "$TEST_DIR/review-fix-loop.sh"
}

teardown() {
    unset _MOCK_RUN_GATE_CALLS _MOCK_IMPL_FIX_CALLS _MOCK_RECORD_CALLS
    unset _MOCK_REVIEW_VERDICTS _MOCK_IMPL_FIX_VERDICT
    unset REVIEW_MAX_ITERATIONS
}

# =========================================================================
# RFL-T1: REVIEW passes first attempt — no fix dispatched
# =========================================================================

@test "review_fix_loop: PASS on first attempt — no impl-fix dispatch" {
    export _MOCK_REVIEW_VERDICTS="PASS"
    export REVIEW_MAX_ITERATIONS=2

    run env _MOCK_REVIEW_VERDICTS="$_MOCK_REVIEW_VERDICTS" _MOCK_IMPL_FIX_VERDICT="${_MOCK_IMPL_FIX_VERDICT:-PASS}" REVIEW_MAX_ITERATIONS="${REVIEW_MAX_ITERATIONS:-}" bash -c "source '$TEST_DIR/test-harness.sh'; source '$TEST_DIR/review-fix-loop.sh'; _review_fix_loop; rc=\$?; echo \"RUN_GATE=\$_MOCK_RUN_GATE_CALLS IMPL_FIX=\$_MOCK_IMPL_FIX_CALLS\"; exit \$rc"
    [ "$status" -eq 0 ]
    [[ "$output" == *"RUN_GATE=1"* ]]
    [[ "$output" == *"IMPL_FIX=0"* ]]
}

# =========================================================================
# RFL-T2: REVIEW fails first, passes after fix — fix called once
# =========================================================================

@test "review_fix_loop: FAIL then PASS — impl-fix dispatched once" {
    export _MOCK_REVIEW_VERDICTS="FAIL PASS"
    export REVIEW_MAX_ITERATIONS=2

    run env _MOCK_REVIEW_VERDICTS="$_MOCK_REVIEW_VERDICTS" _MOCK_IMPL_FIX_VERDICT="${_MOCK_IMPL_FIX_VERDICT:-PASS}" REVIEW_MAX_ITERATIONS="${REVIEW_MAX_ITERATIONS:-}" bash -c "source '$TEST_DIR/test-harness.sh'; source '$TEST_DIR/review-fix-loop.sh'; _review_fix_loop; rc=\$?; echo \"RUN_GATE=\$_MOCK_RUN_GATE_CALLS IMPL_FIX=\$_MOCK_IMPL_FIX_CALLS\"; exit \$rc"
    [ "$status" -eq 0 ]
    [[ "$output" == *"RUN_GATE=2"* ]]
    [[ "$output" == *"IMPL_FIX=1"* ]]
}

# =========================================================================
# RFL-T3: REVIEW fails all iterations — exhausts budget, returns 1
# =========================================================================

@test "review_fix_loop: FAIL FAIL — exhausts iterations and returns 1" {
    export _MOCK_REVIEW_VERDICTS="FAIL FAIL"
    export REVIEW_MAX_ITERATIONS=2

    run env _MOCK_REVIEW_VERDICTS="$_MOCK_REVIEW_VERDICTS" _MOCK_IMPL_FIX_VERDICT="${_MOCK_IMPL_FIX_VERDICT:-PASS}" REVIEW_MAX_ITERATIONS="${REVIEW_MAX_ITERATIONS:-}" bash -c "source '$TEST_DIR/test-harness.sh'; source '$TEST_DIR/review-fix-loop.sh'; _review_fix_loop; rc=\$?; echo \"RUN_GATE=\$_MOCK_RUN_GATE_CALLS IMPL_FIX=\$_MOCK_IMPL_FIX_CALLS\"; exit \$rc"
    [ "$status" -eq 1 ]
    [[ "$output" == *"RUN_GATE=2"* ]]
    [[ "$output" == *"IMPL_FIX=1"* ]]
}

# =========================================================================
# RFL-T4: REVIEW_MAX_ITERATIONS=3 with all FAIL — three reviews, two fixes
# =========================================================================

@test "review_fix_loop: honors REVIEW_MAX_ITERATIONS=3" {
    export _MOCK_REVIEW_VERDICTS="FAIL FAIL FAIL"
    export REVIEW_MAX_ITERATIONS=3

    run env _MOCK_REVIEW_VERDICTS="$_MOCK_REVIEW_VERDICTS" _MOCK_IMPL_FIX_VERDICT="${_MOCK_IMPL_FIX_VERDICT:-PASS}" REVIEW_MAX_ITERATIONS="${REVIEW_MAX_ITERATIONS:-}" bash -c "source '$TEST_DIR/test-harness.sh'; source '$TEST_DIR/review-fix-loop.sh'; _review_fix_loop; rc=\$?; echo \"RUN_GATE=\$_MOCK_RUN_GATE_CALLS IMPL_FIX=\$_MOCK_IMPL_FIX_CALLS\"; exit \$rc"
    [ "$status" -eq 1 ]
    [[ "$output" == *"RUN_GATE=3"* ]]
    [[ "$output" == *"IMPL_FIX=2"* ]]
}

# =========================================================================
# RFL-T5: IMPLEMENTATION_FIX fails — returns 1 early
# =========================================================================

@test "review_fix_loop: implementation-fix failure returns 1 without further review" {
    export _MOCK_REVIEW_VERDICTS="FAIL PASS PASS"
    export _MOCK_IMPL_FIX_VERDICT="FAIL"
    export REVIEW_MAX_ITERATIONS=3

    run env _MOCK_REVIEW_VERDICTS="$_MOCK_REVIEW_VERDICTS" _MOCK_IMPL_FIX_VERDICT="${_MOCK_IMPL_FIX_VERDICT:-PASS}" REVIEW_MAX_ITERATIONS="${REVIEW_MAX_ITERATIONS:-}" bash -c "source '$TEST_DIR/test-harness.sh'; source '$TEST_DIR/review-fix-loop.sh'; _review_fix_loop; rc=\$?; echo \"RUN_GATE=\$_MOCK_RUN_GATE_CALLS IMPL_FIX=\$_MOCK_IMPL_FIX_CALLS\"; exit \$rc"
    [ "$status" -eq 1 ]
    # One review (FAIL) then one failed fix dispatch, no second review
    [[ "$output" == *"RUN_GATE=1"* ]]
    [[ "$output" == *"IMPL_FIX=1"* ]]
}

# =========================================================================
# RFL-T6: default REVIEW_MAX_ITERATIONS is 2
# =========================================================================

@test "review_fix_loop: default max iterations is 2" {
    export _MOCK_REVIEW_VERDICTS="FAIL FAIL FAIL"
    unset REVIEW_MAX_ITERATIONS

    run env _MOCK_REVIEW_VERDICTS="$_MOCK_REVIEW_VERDICTS" _MOCK_IMPL_FIX_VERDICT="${_MOCK_IMPL_FIX_VERDICT:-PASS}" REVIEW_MAX_ITERATIONS="${REVIEW_MAX_ITERATIONS:-}" bash -c "source '$TEST_DIR/test-harness.sh'; source '$TEST_DIR/review-fix-loop.sh'; _review_fix_loop; rc=\$?; echo \"RUN_GATE=\$_MOCK_RUN_GATE_CALLS IMPL_FIX=\$_MOCK_IMPL_FIX_CALLS\"; exit \$rc"
    [ "$status" -eq 1 ]
    # Default is 2: two reviews, one fix dispatch
    [[ "$output" == *"RUN_GATE=2"* ]]
    [[ "$output" == *"IMPL_FIX=1"* ]]
}
