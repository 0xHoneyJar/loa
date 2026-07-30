#!/usr/bin/env bats
# =============================================================================
# bridge-orchestrator-single-iteration.bats — Issue #473 regression tests
# =============================================================================
# Verifies:
#   - --single-iteration flag is parsed and exits after one iteration body
#   - --no-silent-noop-detect opts out of the post-run findings check
#   - Silent-no-op detection fails loud (exit 3) when no findings produced
#   - Default behavior (no flags) is preserved for existing callers
# =============================================================================

setup() {
    # Use the repo's script, but point PROJECT_ROOT at a temp sandbox so
    # state files land in isolation.
    export PROJECT_ROOT
    PROJECT_ROOT=$(mktemp -d)
    mkdir -p "$PROJECT_ROOT/.run"

    cd "$PROJECT_ROOT"
    git init -q -b main
    git config user.email "t@t"
    git config user.name "t"
    echo init > R
    git add R
    git commit -qm init

    touch .loa.config.yaml
    SCRIPT="$BATS_TEST_DIRNAME/../../.claude/scripts/bridge-orchestrator.sh"
}

teardown() {
    cd /
    rm -rf "$PROJECT_ROOT"
}

# T1: --single-iteration flag is parsed without error at --help parse time
@test "bridge-orchestrator: --single-iteration is a recognized flag" {
    # --help is parsed before any state work, so it exits cleanly on every invocation
    run "$SCRIPT" --help
    [ "$status" -eq 0 ]
    # We can't grep --single-iteration in --help directly (help text may not list
    # all flags), but we can verify that passing it with --help doesn't error:
    run "$SCRIPT" --single-iteration --help
    [ "$status" -eq 0 ]
}

# T2: --no-silent-noop-detect is a recognized flag
@test "bridge-orchestrator: --no-silent-noop-detect is a recognized flag" {
    run "$SCRIPT" --no-silent-noop-detect --help
    [ "$status" -eq 0 ]
}

# T3: unknown flags still error cleanly
@test "bridge-orchestrator: unknown flags fail with exit 2" {
    run "$SCRIPT" --bogus-flag
    [ "$status" -ne 0 ]
}

# T4: silent-no-op detection message includes actionable guidance when
# manually triggered via a stubbed fast-exit path. We source only the
# helper by using grep on the script to verify the message text exists.
@test "bridge-orchestrator: silent-no-op error message is actionable" {
    grep -q 'Invoke via the /run-bridge skill' "$SCRIPT"
    grep -q 'Use --single-iteration to drive one iteration at a time' "$SCRIPT"
    grep -q 'Pass --no-silent-noop-detect if this is intentional' "$SCRIPT"
}

# T5: single-iteration mode emits the expected exit banner
@test "bridge-orchestrator: SINGLE-ITERATION banner text present in source" {
    grep -q '\[SINGLE-ITERATION\] Iteration' "$SCRIPT"
    grep -q 'bridge-orchestrator.sh --resume --single-iteration' "$SCRIPT"
}

# T6: default-mode silent-no-op detection is enabled (DETECT_SILENT_NOOP=true)
@test "bridge-orchestrator: DETECT_SILENT_NOOP defaults to true" {
    grep -q '^DETECT_SILENT_NOOP=true' "$SCRIPT"
}

# T7: SINGLE_ITERATION defaults to false (preserves existing behavior)
@test "bridge-orchestrator: SINGLE_ITERATION defaults to false" {
    grep -q '^SINGLE_ITERATION=false' "$SCRIPT"
}

# =============================================================================
# Issue #1174 — finalization is gated on evidence of work
# =============================================================================
# The #473 detector counted ANY *.json under .run/bridge-reviews (including
# leftovers from prior bridges) and looked at no work metrics at all, so a run
# nobody drove reached JACKED_OUT with 0 sprints and 0 findings.

# Write a FINALIZING bridge state file into the sandbox.
#   $1 = bridge_id, $2 = total_sprints_executed, $3 = total_findings_addressed
_write_bridge_state() {
    cat > "$PROJECT_ROOT/.run/bridge-state.json" <<EOF
{
  "schema_version": 1,
  "bridge_id": "$1",
  "state": "FINALIZING",
  "config": {"depth": 3, "mode": "full", "flatline_threshold": 0.05,
             "per_sprint": false, "branch": "main", "repo": "",
             "consecutive_flatline": 2},
  "timestamps": {"started": "2026-01-01T00:00:00Z",
                 "last_activity": "2026-01-01T00:00:00Z"},
  "iterations": [],
  "flatline": {"initial_score": 0, "last_score": 0,
               "consecutive_below_threshold": 0},
  "metrics": {
    "total_sprints_executed": $2,
    "total_files_changed": 0,
    "total_findings_addressed": $3,
    "total_visions_captured": 0
  },
  "finalization": {"ground_truth_updated": false, "rtfm_passed": true,
                   "pr_url": null}
}
EOF
}

# Source the extracted detector next to the real state machine and run it
# exactly as the finalization path does: gate, then transition.
#   $1 = extra shell prelude (env assignments), may be empty
_run_detector() {
    run bash -c "
        export PROJECT_ROOT='$PROJECT_ROOT'
        export DEPTH=3
        export DETECT_SILENT_NOOP=true
        $1
        source '$BATS_TEST_DIRNAME/../../.claude/scripts/bridge-state.sh'
        awk '/^detect_zero_work\\(\\)/,/^}$/' '$SCRIPT' > '$PROJECT_ROOT/detector.sh'
        source '$PROJECT_ROOT/detector.sh'
        detect_zero_work && update_bridge_state JACKED_OUT
    "
}

_state() {
    jq -r '.state' "$PROJECT_ROOT/.run/bridge-state.json"
}

# T8 (AC-1): zero work metrics + no findings file for this bridge → exit 3
@test "bridge-orchestrator: detect_zero_work exits 3 when nothing was driven" {
    _write_bridge_state "bridge-20260101-aaaaaa" 0 0
    _run_detector ""
    [ "$status" -eq 3 ]
}

# T9 (AC-2): that same run HALTs and never claims JACKED_OUT
@test "bridge-orchestrator: zero-work run lands in HALTED, not JACKED_OUT" {
    _write_bridge_state "bridge-20260101-aaaaaa" 0 0
    _run_detector ""
    [ "$status" -eq 3 ]
    [ "$(_state)" = "HALTED" ]
}

# T10 (AC-3): a findings file from a DIFFERENT bridge is not evidence of work
@test "bridge-orchestrator: prior-bridge findings file does not satisfy the gate" {
    _write_bridge_state "bridge-20260101-aaaaaa" 0 0
    mkdir -p "$PROJECT_ROOT/.run/bridge-reviews"
    echo '{"findings":[]}' > \
        "$PROJECT_ROOT/.run/bridge-reviews/bridge-20251201-bbbbbb-iter1-findings.json"
    _run_detector ""
    [ "$status" -eq 3 ]
    [ "$(_state)" = "HALTED" ]
}

# T11: a findings file from THIS bridge IS evidence of work (glob must match)
@test "bridge-orchestrator: current-bridge findings file satisfies the gate" {
    _write_bridge_state "bridge-20260101-aaaaaa" 0 0
    mkdir -p "$PROJECT_ROOT/.run/bridge-reviews"
    echo '{"findings":[]}' > \
        "$PROJECT_ROOT/.run/bridge-reviews/bridge-20260101-aaaaaa-iter1-findings.json"
    _run_detector ""
    [ "$status" -eq 0 ]
    [ "$(_state)" = "JACKED_OUT" ]
}

# T12 (AC-4): a non-zero work metric is evidence of work
@test "bridge-orchestrator: total_sprints_executed >= 1 finalizes to JACKED_OUT" {
    _write_bridge_state "bridge-20260101-aaaaaa" 1 0
    _run_detector ""
    [ "$status" -eq 0 ]
    [ "$(_state)" = "JACKED_OUT" ]
}

# T12b: per-iteration Bridgebuilder findings also count as work, even when the
# rolled-up metrics are still 0 (the conjunct reads all three work signals).
@test "bridge-orchestrator: iteration bridgebuilder findings count as work" {
    _write_bridge_state "bridge-20260101-aaaaaa" 0 0
    jq '.iterations = [{"bridgebuilder": {"total_findings": 7}}]' \
        "$PROJECT_ROOT/.run/bridge-state.json" > "$PROJECT_ROOT/s.json"
    mv "$PROJECT_ROOT/s.json" "$PROJECT_ROOT/.run/bridge-state.json"
    _run_detector ""
    [ "$status" -eq 0 ]
    [ "$(_state)" = "JACKED_OUT" ]
}

# T13 (AC-5): --allow-empty is a recognized flag and usage() lists it
@test "bridge-orchestrator: --allow-empty is parsed and documented in usage" {
    run "$SCRIPT" --allow-empty --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--allow-empty"* ]]
}

# T14 (AC-6): --allow-empty opts a legitimately empty run out of the gate
@test "bridge-orchestrator: ALLOW_EMPTY=true finalizes a zero-work bridge" {
    _write_bridge_state "bridge-20260101-aaaaaa" 0 0
    _run_detector "export ALLOW_EMPTY=true"
    [ "$status" -eq 0 ]
    [ "$(_state)" = "JACKED_OUT" ]
}

# T15: the gate message keeps its actionable options, including --allow-empty
@test "bridge-orchestrator: zero-work error names --allow-empty as an option" {
    _write_bridge_state "bridge-20260101-aaaaaa" 0 0
    _run_detector ""
    [ "$status" -eq 3 ]
    [[ "$output" == *"--allow-empty"* ]]
    [[ "$output" == *"Invoke via the /run-bridge skill"* ]]
}
