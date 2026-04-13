#!/usr/bin/env bats
#
# post-pr-bridgebuilder.bats — Unit tests for Amendment 1 (cycle-053).
# Tests the BRIDGEBUILDER_REVIEW phase in post-pr-orchestrator.sh and the
# companion post-pr-triage.sh script.
#
# Related files:
#   - .claude/scripts/post-pr-orchestrator.sh (phase_bridgebuilder_review)
#   - .claude/scripts/post-pr-triage.sh (classification + trajectory logging)
#   - .claude/data/trajectory-schemas/bridge-triage.schema.json (entry schema)
#
# Tracking: Issue #464 Part B, sprint-1 of cycle-053

setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"

    export BATS_TMPDIR="${BATS_TMPDIR:-/tmp}"
    export TEST_TMPDIR="$BATS_TMPDIR/post-pr-bridgebuilder-test-$$"
    mkdir -p "$TEST_TMPDIR/.run/bridge-reviews"
    mkdir -p "$TEST_TMPDIR/grimoires/loa/a2a/trajectory"
    mkdir -p "$TEST_TMPDIR/.claude/scripts"

    # Copy the triage script (unit under test)
    cp "$PROJECT_ROOT/.claude/scripts/post-pr-triage.sh" "$TEST_TMPDIR/.claude/scripts/"
    chmod +x "$TEST_TMPDIR/.claude/scripts/post-pr-triage.sh"

    cd "$TEST_TMPDIR"
}

teardown() {
    cd /
    rm -rf "$TEST_TMPDIR"
}

# Helper: create a synthetic findings file with given severity + id
create_findings_file() {
    local filename="$1"
    local severity="$2"
    local fid="$3"
    local title="${4:-Test finding}"
    cat > "$TEST_TMPDIR/.run/bridge-reviews/$filename" <<EOF
{
  "schema_version": 1,
  "total": 1,
  "findings": [
    {
      "id": "$fid",
      "title": "$title",
      "severity": "$severity",
      "category": "test",
      "file": "test.ts:1",
      "description": "Synthetic finding for unit test",
      "suggestion": "Apply fix",
      "weight": 5
    }
  ]
}
EOF
}

# ============================================================================
# T6 — Tests for post-pr-triage.sh
# ============================================================================

@test "triage: --pr is required" {
    run "$TEST_TMPDIR/.claude/scripts/post-pr-triage.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"--pr <PR_NUMBER> required"* ]]
}

@test "triage: --pr rejects non-numeric values" {
    run "$TEST_TMPDIR/.claude/scripts/post-pr-triage.sh" --pr abc
    [ "$status" -eq 1 ]
    [[ "$output" == *"positive integer"* ]]
}

@test "triage: empty review directory is not an error" {
    run "$TEST_TMPDIR/.claude/scripts/post-pr-triage.sh" --pr 100
    [ "$status" -eq 0 ]
}

@test "triage: CRITICAL finding classifies as dispatch_bug" {
    create_findings_file "bridge-test-iter1-findings.json" "CRITICAL" "critical-1" "Test critical"
    run "$TEST_TMPDIR/.claude/scripts/post-pr-triage.sh" --pr 100 --auto-triage true
    [ "$status" -eq 0 ]

    local queue="$TEST_TMPDIR/.run/bridge-pending-bugs.jsonl"
    [ -f "$queue" ]
    run jq -r '.status' "$queue"
    [[ "$output" == "pending_dispatch" ]]

    run jq -r '.finding.severity' "$queue"
    [[ "$output" == "CRITICAL" ]]
}

@test "triage: HIGH finding classifies as log_only (autonomous mode)" {
    create_findings_file "bridge-test-iter1-findings.json" "HIGH" "high-1" "Test high"
    run "$TEST_TMPDIR/.claude/scripts/post-pr-triage.sh" --pr 100 --auto-triage true
    [ "$status" -eq 0 ]

    # Should NOT create bug queue for HIGH
    [ ! -f "$TEST_TMPDIR/.run/bridge-pending-bugs.jsonl" ]

    # Should create trajectory entry
    local traj_dir="$TEST_TMPDIR/grimoires/loa/a2a/trajectory"
    run ls "$traj_dir"
    [[ "$output" == *bridge-triage* ]]
}

@test "triage: PRAISE finding goes to lore-candidates queue" {
    create_findings_file "bridge-test-iter1-findings.json" "PRAISE" "praise-1" "Good pattern"
    run "$TEST_TMPDIR/.claude/scripts/post-pr-triage.sh" --pr 100 --auto-triage true
    [ "$status" -eq 0 ]

    local lore_q="$TEST_TMPDIR/.run/bridge-lore-candidates.jsonl"
    [ -f "$lore_q" ]
    run jq -r '.finding.severity' "$lore_q"
    [[ "$output" == "PRAISE" ]]
}

@test "triage: trajectory entry includes mandatory reasoning field" {
    create_findings_file "bridge-test-iter1-findings.json" "HIGH" "high-1" "Must log reasoning"
    run "$TEST_TMPDIR/.claude/scripts/post-pr-triage.sh" --pr 100 --auto-triage true
    [ "$status" -eq 0 ]

    local traj_file
    traj_file=$(ls "$TEST_TMPDIR/grimoires/loa/a2a/trajectory/"bridge-triage-*.jsonl | head -1)
    [ -f "$traj_file" ]

    # Every entry must have 'reasoning' field per schema
    run jq -r '.reasoning' "$traj_file"
    [ "$status" -eq 0 ]
    # reasoning must not be empty
    [ -n "$output" ]
    [[ "$output" != "null" ]]
}

@test "triage: trajectory entry includes pr_number, finding_id, severity, action" {
    create_findings_file "bridge-test-iter1-findings.json" "MEDIUM" "med-1" "Test medium"
    run "$TEST_TMPDIR/.claude/scripts/post-pr-triage.sh" --pr 42 --auto-triage true
    [ "$status" -eq 0 ]

    local traj_file
    traj_file=$(ls "$TEST_TMPDIR/grimoires/loa/a2a/trajectory/"bridge-triage-*.jsonl | head -1)

    run jq -r '.pr_number' "$traj_file"
    [[ "$output" == "42" ]]

    run jq -r '.finding_id' "$traj_file"
    [[ "$output" == "med-1" ]]

    run jq -r '.severity' "$traj_file"
    [[ "$output" == "MEDIUM" ]]

    run jq -r '.action' "$traj_file"
    [[ "$output" == "log_only" ]]
}

@test "triage: auto-triage=false defers CRITICAL instead of dispatching" {
    create_findings_file "bridge-test-iter1-findings.json" "CRITICAL" "critical-1" "Auto off"
    run "$TEST_TMPDIR/.claude/scripts/post-pr-triage.sh" --pr 100 --auto-triage false
    [ "$status" -eq 0 ]

    # No bug queue created when auto-triage is off
    [ ! -f "$TEST_TMPDIR/.run/bridge-pending-bugs.jsonl" ]

    # But trajectory entry exists with action=defer
    local traj_file
    traj_file=$(ls "$TEST_TMPDIR/grimoires/loa/a2a/trajectory/"bridge-triage-*.jsonl | head -1)
    run jq -r '.action' "$traj_file"
    [[ "$output" == "defer" ]]
}

@test "triage: --dry-run does not write any files" {
    create_findings_file "bridge-test-iter1-findings.json" "CRITICAL" "critical-1" "Dry run"
    run "$TEST_TMPDIR/.claude/scripts/post-pr-triage.sh" --pr 100 --dry-run
    [ "$status" -eq 0 ]

    [ ! -f "$TEST_TMPDIR/.run/bridge-pending-bugs.jsonl" ]
    [ ! -f "$TEST_TMPDIR/.run/bridge-lore-candidates.jsonl" ]

    # No trajectory files
    local traj_count
    traj_count=$(ls "$TEST_TMPDIR/grimoires/loa/a2a/trajectory/"bridge-triage-*.jsonl 2>/dev/null | wc -l)
    [ "$traj_count" -eq 0 ]
}

@test "triage: multiple findings files processed" {
    create_findings_file "bridge-test-iter1-findings.json" "HIGH" "h1" "Iter 1"
    create_findings_file "bridge-test-iter2-findings.json" "HIGH" "h2" "Iter 2"
    create_findings_file "bridge-test-iter3-findings.json" "CRITICAL" "c1" "Iter 3"

    run "$TEST_TMPDIR/.claude/scripts/post-pr-triage.sh" --pr 100 --auto-triage true
    [ "$status" -eq 0 ]

    # Bug queue gets 1 entry (CRITICAL from iter3)
    local bug_count
    bug_count=$(wc -l < "$TEST_TMPDIR/.run/bridge-pending-bugs.jsonl")
    [ "$bug_count" -eq 1 ]

    # Trajectory gets 3 entries (one per finding)
    local traj_file
    traj_file=$(ls "$TEST_TMPDIR/grimoires/loa/a2a/trajectory/"bridge-triage-*.jsonl | head -1)
    local traj_count
    traj_count=$(wc -l < "$traj_file")
    [ "$traj_count" -eq 3 ]
}

@test "triage: queued bug entry includes suggested bug ID with finding.id" {
    create_findings_file "bridge-test-iter1-findings.json" "CRITICAL" "crit-xyz" "Has finding ID"
    run "$TEST_TMPDIR/.claude/scripts/post-pr-triage.sh" --pr 100 --auto-triage true
    [ "$status" -eq 0 ]

    run jq -r '.suggested_bug_id' "$TEST_TMPDIR/.run/bridge-pending-bugs.jsonl"
    [[ "$output" == *crit-xyz* ]]
}

@test "triage: malformed findings file is handled gracefully" {
    echo "not valid json" > "$TEST_TMPDIR/.run/bridge-reviews/bridge-broken-iter1-findings.json"
    run "$TEST_TMPDIR/.claude/scripts/post-pr-triage.sh" --pr 100
    # Should not crash — just skip malformed files
    [ "$status" -eq 0 ]
}

# ============================================================================
# T6 — Integration check for phase wiring (validates orchestrator edits)
# ============================================================================

@test "orchestrator: STATE_BRIDGEBUILDER_REVIEW constant is defined" {
    run grep "STATE_BRIDGEBUILDER_REVIEW" "$PROJECT_ROOT/.claude/scripts/post-pr-orchestrator.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *BRIDGEBUILDER_REVIEW* ]]
}

@test "orchestrator: phase_bridgebuilder_review function exists" {
    run grep "^phase_bridgebuilder_review()" "$PROJECT_ROOT/.claude/scripts/post-pr-orchestrator.sh"
    [ "$status" -eq 0 ]
}

@test "orchestrator: --skip-bridgebuilder flag is parsed" {
    run grep -- "--skip-bridgebuilder" "$PROJECT_ROOT/.claude/scripts/post-pr-orchestrator.sh"
    [ "$status" -eq 0 ]
}

@test "state: BRIDGEBUILDER_REVIEW is in VALID_STATES" {
    run grep "BRIDGEBUILDER_REVIEW" "$PROJECT_ROOT/.claude/scripts/post-pr-state.sh"
    [ "$status" -eq 0 ]
}

@test "schema: bridge-triage.schema.json exists and requires reasoning field" {
    local schema="$PROJECT_ROOT/.claude/data/trajectory-schemas/bridge-triage.schema.json"
    [ -f "$schema" ]
    run jq -r '.required | index("reasoning")' "$schema"
    # "reasoning" is in the required array (index >= 0)
    [ "$output" != "null" ]
}
