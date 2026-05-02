#!/usr/bin/env bats
# =============================================================================
# flatline-exit-classifier.bats — Tests for classify_flatline_exit (Issue #663)
# =============================================================================
# sprint-bug-126. Validates that the helper distinguishes validation/config
# errors from real flatline blockers, so post-pr-orchestrator does not
# misattribute "Invalid phase: pr" as a blocker halt.

setup() {
    export PROJECT_ROOT="$BATS_TEST_DIRNAME/../.."
    export LIB="$PROJECT_ROOT/.claude/scripts/lib/flatline-exit-classifier.sh"

    export TMPDIR_TEST="$(mktemp -d)"
    export STDERR_FILE="$TMPDIR_TEST/stderr"
}

teardown() {
    if [[ -n "${TMPDIR_TEST:-}" && -d "$TMPDIR_TEST" ]]; then
        rm -rf "$TMPDIR_TEST"
    fi
}

# =========================================================================
# FEC-T1..T2: success and timeout
# =========================================================================

@test "FEC-T1: exit 0 → ok" {
    run "$LIB" 0 /dev/null
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
}

@test "FEC-T2: exit 124 → timeout" {
    run "$LIB" 124 /dev/null
    [ "$status" -eq 0 ]
    [ "$output" = "timeout" ]
}

# =========================================================================
# FEC-T3..T6: validation/config errors → flatline_orchestrator_error (the #663 defect)
# =========================================================================

@test "FEC-T3: exit 1 + 'Invalid phase: pr' stderr → flatline_orchestrator_error" {
    echo "ERROR: Invalid phase: pr (expected: prd, sdd, sprint, beads, spec)" >"$STDERR_FILE"
    run "$LIB" 1 "$STDERR_FILE"
    [ "$status" -eq 0 ]
    [ "$output" = "flatline_orchestrator_error" ]
}

@test "FEC-T4: exit 1 + 'Unknown option' stderr → flatline_orchestrator_error" {
    echo "ERROR: Unknown option: --foo" >"$STDERR_FILE"
    run "$LIB" 1 "$STDERR_FILE"
    [ "$output" = "flatline_orchestrator_error" ]
}

@test "FEC-T5: exit 1 + 'Document not found:' → flatline_orchestrator_error" {
    echo "ERROR: Document not found: /tmp/missing.md" >"$STDERR_FILE"
    run "$LIB" 1 "$STDERR_FILE"
    [ "$output" = "flatline_orchestrator_error" ]
}

@test "FEC-T6: exit 1 + 'Invalid mode:' → flatline_orchestrator_error" {
    echo "ERROR: Invalid mode: wibble (expected: review, red-team, inquiry)" >"$STDERR_FILE"
    run "$LIB" 1 "$STDERR_FILE"
    [ "$output" = "flatline_orchestrator_error" ]
}

# =========================================================================
# FEC-T7: legacy blocker semantics preserved (exit 1 without validation pattern)
# =========================================================================

@test "FEC-T7: exit 1 + non-validation stderr → flatline_blocker (legacy compat)" {
    echo "BLOCKER: critical security issue found" >"$STDERR_FILE"
    run "$LIB" 1 "$STDERR_FILE"
    [ "$output" = "flatline_blocker" ]
}

@test "FEC-T8: exit 1 with empty stderr → flatline_blocker (legacy compat)" {
    : >"$STDERR_FILE"
    run "$LIB" 1 "$STDERR_FILE"
    [ "$output" = "flatline_blocker" ]
}

# =========================================================================
# FEC-T9..T11: other non-zero exits → flatline_error
# =========================================================================

@test "FEC-T9: exit 3 (model failures) → flatline_error" {
    echo "ERROR: All model calls failed" >"$STDERR_FILE"
    run "$LIB" 3 "$STDERR_FILE"
    [ "$output" = "flatline_error" ]
}

@test "FEC-T10: exit 5 (budget) → flatline_error" {
    echo "ERROR: Budget exceeded" >"$STDERR_FILE"
    run "$LIB" 5 "$STDERR_FILE"
    [ "$output" = "flatline_error" ]
}

@test "FEC-T11: exit 7 (silent no-op) → flatline_error" {
    echo "Silent no-op detected" >"$STDERR_FILE"
    run "$LIB" 7 "$STDERR_FILE"
    [ "$output" = "flatline_error" ]
}

# =========================================================================
# FEC-T12: validation pattern wins over high exit code (defense-in-depth)
# =========================================================================

@test "FEC-T12: exit 7 + Invalid phase stderr → flatline_orchestrator_error" {
    # If a validation pattern matches, we trust it over the exit code.
    # In practice, validation errors come with exit 1, but defense-in-depth.
    echo "ERROR: Invalid phase: bogus" >"$STDERR_FILE"
    run "$LIB" 7 "$STDERR_FILE"
    [ "$output" = "flatline_orchestrator_error" ]
}
