#!/usr/bin/env bats
# =============================================================================
# post-pr-state.bats — Tests for post-pr-state.sh phase taxonomy (Issue #664)
# =============================================================================
# sprint-bug-125. Validates that `update-phase bridgebuilder_review <status>`
# is accepted by the validator (which previously rejected it as an "Invalid
# phase"), causing all six bridgebuilder-review-related update-phase calls
# in post-pr-orchestrator.sh to fail silently and the state file to never
# record the bridgebuilder_review phase.

setup() {
    export PROJECT_ROOT="$BATS_TEST_DIRNAME/../.."
    export SCRIPT="$PROJECT_ROOT/.claude/scripts/post-pr-state.sh"

    # Hermetic state dir per test
    export TMPDIR_TEST="$(mktemp -d)"
    export STATE_DIR="$TMPDIR_TEST/state"
    mkdir -p "$STATE_DIR"
    export STATE_FILE="$STATE_DIR/post-pr-state.json"

    # Hand-craft a minimal valid state file (skips full init flow)
    cat >"$STATE_FILE" <<'JSON'
{
  "post_pr_id": "post-pr-20260502-aabbccdd",
  "schema_version": 1,
  "state": "BRIDGEBUILDER_REVIEW",
  "pr_url": "https://github.com/0xHoneyJar/loa/pull/664",
  "pr_number": 664,
  "branch": "fix/sprint-bug-125",
  "mode": "autonomous",
  "phases": {
    "post_pr_audit": "completed",
    "context_clear": "completed",
    "e2e_testing": "completed",
    "flatline_pr": "completed"
  },
  "audit": {"iteration": 0, "max_iterations": 5, "findings": [], "finding_identities": []},
  "e2e": {"iteration": 0, "max_iterations": 3, "failures": [], "failure_identities": []},
  "timestamps": {"started": "2026-05-02T00:00:00Z", "last_activity": "2026-05-02T00:00:00Z"},
  "markers": []
}
JSON
    chmod 600 "$STATE_FILE"
}

teardown() {
    if [[ -n "${TMPDIR_TEST:-}" && -d "$TMPDIR_TEST" ]]; then
        rm -rf "$TMPDIR_TEST"
    fi
}

# =========================================================================
# PPS-T1..T3: bridgebuilder_review accepted (the #664 defect class)
# =========================================================================

@test "PPS-T1: update-phase bridgebuilder_review completed → exit 0" {
    run "$SCRIPT" update-phase bridgebuilder_review completed
    [ "$status" -eq 0 ]
    # State file persists the new phase
    run jq -r '.phases.bridgebuilder_review' "$STATE_FILE"
    [ "$status" -eq 0 ]
    [ "$output" = "completed" ]
}

@test "PPS-T2: update-phase bridgebuilder_review in_progress → exit 0" {
    run "$SCRIPT" update-phase bridgebuilder_review in_progress
    [ "$status" -eq 0 ]
    run jq -r '.phases.bridgebuilder_review' "$STATE_FILE"
    [ "$output" = "in_progress" ]
}

@test "PPS-T3: update-phase bridgebuilder_review skipped → exit 0" {
    run "$SCRIPT" update-phase bridgebuilder_review skipped
    [ "$status" -eq 0 ]
    run jq -r '.phases.bridgebuilder_review' "$STATE_FILE"
    [ "$output" = "skipped" ]
}

# =========================================================================
# PPS-T4: regression guard — unknown phases still rejected
# =========================================================================

@test "PPS-T4: update-phase nonexistent_phase completed → exit 1, error to stderr" {
    run "$SCRIPT" update-phase nonexistent_phase completed
    [ "$status" -ne 0 ]
    [[ "$output" == *"Invalid phase"* ]]
}

# =========================================================================
# PPS-T5..T8: regression guard — pre-existing phases still accepted
# =========================================================================

@test "PPS-T5: post_pr_audit still accepted (regression guard)" {
    run "$SCRIPT" update-phase post_pr_audit completed
    [ "$status" -eq 0 ]
}

@test "PPS-T6: context_clear still accepted (regression guard)" {
    run "$SCRIPT" update-phase context_clear completed
    [ "$status" -eq 0 ]
}

@test "PPS-T7: e2e_testing still accepted (regression guard)" {
    run "$SCRIPT" update-phase e2e_testing completed
    [ "$status" -eq 0 ]
}

@test "PPS-T8: flatline_pr still accepted (regression guard)" {
    run "$SCRIPT" update-phase flatline_pr completed
    [ "$status" -eq 0 ]
}

# =========================================================================
# PPS-T9: invalid status still rejected
# =========================================================================

@test "PPS-T9: bridgebuilder_review with invalid status → exit 1" {
    run "$SCRIPT" update-phase bridgebuilder_review wibble
    [ "$status" -ne 0 ]
    [[ "$output" == *"Invalid status"* ]]
}
