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

    # sprint-bug-210 (#1025): the triage script soft-sources compat-lib.sh
    # (jq_strict) from its own SCRIPT_DIR — copy it alongside.
    cp "$PROJECT_ROOT/.claude/scripts/compat-lib.sh" "$TEST_TMPDIR/.claude/scripts/"

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

@test "triage: malformed findings file fails loud (DEGRADED, not silent skip)" {
    # sprint-bug-210 (#1025): this test previously asserted exit 0 ("just skip
    # malformed files") — that silent skip WAS the KF-004 bug. The corrected
    # contract: a corrupt findings artifact exits 3 with a DEGRADED convergence
    # record, never a clean FLATLINE. (See T-A1 for the convergence assertions.)
    echo "not valid json" > "$TEST_TMPDIR/.run/bridge-reviews/bridge-broken-iter1-findings.json"
    run "$TEST_TMPDIR/.claude/scripts/post-pr-triage.sh" --pr 100
    [ "$status" -eq 3 ]
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

# Bridgebuilder H1 (PR #466 review): generated bug IDs MUST match the schema's
# auto_dispatched_bug_id pattern. Previously the schema rejected hyphens after
# the YYYYMMDD prefix; generator produces "20260413-autobridge-<finding_id>"
# which includes hyphens. Schema updated to allow hyphens; test verifies.
@test "schema: auto_dispatched_bug_id pattern accepts generated bug IDs" {
    local schema="$PROJECT_ROOT/.claude/data/trajectory-schemas/bridge-triage.schema.json"
    local pattern
    pattern=$(jq -r '.properties.auto_dispatched_bug_id.pattern' "$schema")

    # Sample bug IDs the generator produces
    local ids=(
        "20260413-autobridge-critical-1"
        "20260413-autobridge-high-2"
        "20260101-autobridge-f3"
    )
    for id in "${ids[@]}"; do
        run bash -c "echo '$id' | grep -qE '$pattern'"
        [ "$status" -eq 0 ] || { echo "Pattern rejected valid ID: $id" >&2; return 1; }
    done
}

# Bridgebuilder H2 (PR #466 review): orchestrator must pass --review-dir to
# triage so the script reads from wherever bridge-orchestrator wrote, regardless
# of script deployment path.
@test "orchestrator: passes --review-dir to post-pr-triage.sh" {
    run grep -A 6 "post-pr-triage.sh" "$PROJECT_ROOT/.claude/scripts/post-pr-orchestrator.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"--review-dir"* ]]
}

# Bridgebuilder H2 (PR #466 v2 review): finding IDs with uppercase/underscores
# would produce bug_seed_id that fails schema pattern validation. Sanitization
# must lowercase, replace underscores with hyphens, and strip invalid chars.
@test "triage: sanitizes uppercase finding IDs before composing bug_seed_id" {
    create_findings_file "bridge-test-iter1-findings.json" "CRITICAL" "HIGH-Security-Issue-1" "Uppercase ID"
    run "$TEST_TMPDIR/.claude/scripts/post-pr-triage.sh" --pr 100 --auto-triage true
    [ "$status" -eq 0 ]

    local bug_id
    bug_id=$(jq -r '.suggested_bug_id' "$TEST_TMPDIR/.run/bridge-pending-bugs.jsonl")

    # Must match schema pattern ^[0-9]{8}-[a-z0-9][a-z0-9-]*$
    local schema_pattern="^[0-9]{8}-[a-z0-9][a-z0-9-]*$"
    run bash -c "echo '$bug_id' | grep -qE '$schema_pattern'"
    [ "$status" -eq 0 ] || { echo "Bug ID $bug_id does not match schema pattern" >&2; return 1; }

    # Must contain the sanitized finding ID as a suffix
    [[ "$bug_id" == *"high-security-issue-1" ]]
}

@test "triage: sanitizes underscores in finding IDs to hyphens" {
    create_findings_file "bridge-test-iter1-findings.json" "CRITICAL" "security_auth_bypass" "Underscore ID"
    run "$TEST_TMPDIR/.claude/scripts/post-pr-triage.sh" --pr 100 --auto-triage true
    [ "$status" -eq 0 ]

    local bug_id
    bug_id=$(jq -r '.suggested_bug_id' "$TEST_TMPDIR/.run/bridge-pending-bugs.jsonl")

    # Must match schema pattern
    local schema_pattern="^[0-9]{8}-[a-z0-9][a-z0-9-]*$"
    run bash -c "echo '$bug_id' | grep -qE '$schema_pattern'"
    [ "$status" -eq 0 ]

    # Underscores converted to hyphens
    [[ "$bug_id" != *"_"* ]]
    [[ "$bug_id" == *"security-auth-bypass" ]]
}

# Kaironic termination pattern (PR #466 v3 convergence demo):
# Triage must write a machine-readable convergence record after processing
# so callers can short-circuit the iteration loop when FLATLINE is reached.
@test "triage: emits FLATLINE convergence state when no CRITICAL/BLOCKER findings" {
    # Only LOW + PRAISE findings → should flatline
    create_findings_file "bridge-test-iter1-findings.json" "LOW" "low-1" "Minor"
    run "$TEST_TMPDIR/.claude/scripts/post-pr-triage.sh" --pr 100 --auto-triage true
    [ "$status" -eq 0 ]

    local convergence_file="$TEST_TMPDIR/.run/bridge-triage-convergence.json"
    [ -f "$convergence_file" ]

    run jq -r '.state' "$convergence_file"
    [[ "$output" == "FLATLINE" ]]

    run jq -r '.actionable_high' "$convergence_file"
    [[ "$output" == "0" ]]
}

@test "triage: emits KEEP_ITERATING convergence state when CRITICAL findings present" {
    create_findings_file "bridge-test-iter1-findings.json" "CRITICAL" "crit-1" "Real bug"
    run "$TEST_TMPDIR/.claude/scripts/post-pr-triage.sh" --pr 100 --auto-triage true
    [ "$status" -eq 0 ]

    local convergence_file="$TEST_TMPDIR/.run/bridge-triage-convergence.json"
    [ -f "$convergence_file" ]

    run jq -r '.state' "$convergence_file"
    [[ "$output" == "KEEP_ITERATING" ]]

    run jq -r '.actionable_high' "$convergence_file"
    [[ "$output" != "0" ]]
}

@test "orchestrator: iterates up to depth then short-circuits on FLATLINE" {
    run grep -c "while \[\[ \$iter -lt \$max_iters" "$PROJECT_ROOT/.claude/scripts/post-pr-orchestrator.sh"
    [ "$status" -eq 0 ]
    [[ "$output" -ge 1 ]]

    run grep "Kaironic convergence reached" "$PROJECT_ROOT/.claude/scripts/post-pr-orchestrator.sh"
    [ "$status" -eq 0 ]
}

# Bridgebuilder H4 (PR #466 v2 review): default REVIEW_DIR should resolve
# relative to cwd (not script location) to stay consistent with orchestrator.
@test "triage: default REVIEW_DIR is cwd-relative (H4 fix)" {
    # Copy the script to a location OUTSIDE the normal .claude/scripts path
    local alt_script_dir="$TEST_TMPDIR/alt-install"
    mkdir -p "$alt_script_dir"
    cp "$PROJECT_ROOT/.claude/scripts/post-pr-triage.sh" "$alt_script_dir/"
    # sprint-bug-210 (#1025): compat-lib.sh (jq_strict) is a co-located sibling
    # in every real .claude/scripts/ install and travels via the copy-set.
    cp "$PROJECT_ROOT/.claude/scripts/compat-lib.sh" "$alt_script_dir/"

    # Run from $TEST_TMPDIR — default paths should resolve relative to cwd
    create_findings_file "bridge-test-iter1-findings.json" "HIGH" "h1" "Test H4"
    run "$alt_script_dir/post-pr-triage.sh" --pr 100 --auto-triage true
    [ "$status" -eq 0 ]

    # Trajectory should land in $TEST_TMPDIR (cwd), not alt_script_dir's parent
    local traj_count
    traj_count=$(ls "$TEST_TMPDIR/grimoires/loa/a2a/trajectory/"bridge-triage-*.jsonl 2>/dev/null | wc -l)
    [ "$traj_count" -ge 1 ]
}


# =============================================================================
# sprint-bug-210 / #1025 sweep leg 2 — KF-004 guards (post-pr-triage.sh)
# A corrupt Bridgebuilder findings artifact must never produce a clean
# FLATLINE / exit-0 triage; a corrupt bridge-state.json must never fall
# through to the glob-all legacy path (#676 Defect B resurrection).
# =============================================================================

@test "KF-004 guard: corrupt findings file → exit 3 + DEGRADED convergence, never FLATLINE (T-A1)" {
    echo 'this is not json' > "$TEST_TMPDIR/.run/bridge-reviews/bridge-x-iter1-findings.json"
    run "$TEST_TMPDIR/.claude/scripts/post-pr-triage.sh" --pr 100 --auto-triage true
    [ "$status" -eq 3 ]
    local conv="$TEST_TMPDIR/.run/bridge-triage-convergence.json"
    [ -f "$conv" ]
    [ "$(jq -r '.state' "$conv")" == "DEGRADED" ]
    [ "$(jq -r '.parse_failures' "$conv")" -ge 1 ]
}

@test "KF-004 guard: valid+corrupt mix → CRITICAL still queued, run degraded (T-A2)" {
    create_findings_file "bridge-x-iter1-findings.json" "CRITICAL" "crit-1" "Real blocker"
    echo '{broken' > "$TEST_TMPDIR/.run/bridge-reviews/bridge-x-iter2-findings.json"
    run "$TEST_TMPDIR/.claude/scripts/post-pr-triage.sh" --pr 100 --auto-triage true
    [ "$status" -eq 3 ]
    [ -f "$TEST_TMPDIR/.run/bridge-pending-bugs.jsonl" ]
    [ "$(jq -r '.finding.severity' "$TEST_TMPDIR/.run/bridge-pending-bugs.jsonl")" == "CRITICAL" ]
    [ "$(jq -r '.state' "$TEST_TMPDIR/.run/bridge-triage-convergence.json")" == "DEGRADED" ]
}

@test "KF-004 guard: corrupt bridge-state.json → exit 1, no glob fall-through (T-A3)" {
    echo 'garbage{' > "$TEST_TMPDIR/.run/bridge-state.json"
    create_findings_file "stale-bridge-iter1-findings.json" "CRITICAL" "stale-1" "Stale finding"
    run "$TEST_TMPDIR/.claude/scripts/post-pr-triage.sh" --pr 100 --auto-triage true
    [ "$status" -eq 1 ]
    [ ! -f "$TEST_TMPDIR/.run/bridge-pending-bugs.jsonl" ]
}

@test "dep-guard: missing compat-lib (jq_strict undefined) → config-error exit 2, not misleading DEGRADED (T-A6, DISS-001 iter-3)" {
    rm -f "$TEST_TMPDIR/.claude/scripts/compat-lib.sh"
    create_findings_file "bridge-x-iter1-findings.json" "CRITICAL" "c1" "Real finding"
    run "$TEST_TMPDIR/.claude/scripts/post-pr-triage.sh" --pr 100 --auto-triage true
    [ "$status" -eq 2 ]
    [[ "$output" == *"dependencies unavailable"* || "$output" == *"FATAL"* ]]
}

@test "dep-guard: dependency failure invalidates a stale FLATLINE convergence record (T-A7, DISS-002 iter-4)" {
    # The dep-guard exit must not leave a prior run's FLATLINE record for the
    # orchestrator to read as clean (same stale-convergence class as T-A5).
    mkdir -p "$TEST_TMPDIR/.run"
    cat > "$TEST_TMPDIR/.run/bridge-triage-convergence.json" <<'JSON'
{"timestamp":"2020-01-01T00:00:00Z","pr_number":100,"state":"FLATLINE","actionable_high":0,"blocker_count":0,"disputed_count":0}
JSON
    rm -f "$TEST_TMPDIR/.claude/scripts/compat-lib.sh"
    create_findings_file "bridge-x-iter1-findings.json" "CRITICAL" "c1" "Real finding"
    run "$TEST_TMPDIR/.claude/scripts/post-pr-triage.sh" --pr 100 --auto-triage true
    [ "$status" -eq 2 ]
    # Stale FLATLINE must be gone (absent → orchestrator defaults KEEP_ITERATING, not clean)
    [ ! -f "$TEST_TMPDIR/.run/bridge-triage-convergence.json" ]
}

@test "KF-004 guard: corrupt bridge-state.json overwrites stale FLATLINE convergence → DEGRADED (T-A5)" {
    # DISS-001: the corrupt-state early-return must not let a prior iteration's
    # clean convergence record survive — the orchestrator reads .state from it.
    mkdir -p "$TEST_TMPDIR/.run"
    cat > "$TEST_TMPDIR/.run/bridge-triage-convergence.json" <<'JSON'
{"timestamp":"2020-01-01T00:00:00Z","pr_number":100,"state":"FLATLINE","actionable_high":0,"blocker_count":0,"disputed_count":0}
JSON
    echo 'garbage{' > "$TEST_TMPDIR/.run/bridge-state.json"
    run "$TEST_TMPDIR/.claude/scripts/post-pr-triage.sh" --pr 100 --auto-triage true
    [ "$status" -eq 1 ]
    # Stale FLATLINE must have been overwritten with DEGRADED
    [ "$(jq -r '.state' "$TEST_TMPDIR/.run/bridge-triage-convergence.json")" == "DEGRADED" ]
}

@test "regression pin: bridge-state.json without bridge_id → legacy glob unchanged (T-A4)" {
    echo '{}' > "$TEST_TMPDIR/.run/bridge-state.json"
    create_findings_file "any-iter1-findings.json" "PRAISE" "p-1" "Nice work"
    run "$TEST_TMPDIR/.claude/scripts/post-pr-triage.sh" --pr 100 --auto-triage true
    [ "$status" -eq 0 ]
    [ -f "$TEST_TMPDIR/.run/bridge-lore-candidates.jsonl" ]
}
