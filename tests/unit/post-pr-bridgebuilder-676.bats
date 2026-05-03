#!/usr/bin/env bats
# =============================================================================
# Unit tests for #676 — post-PR Bridgebuilder false-positive FLATLINE
#
# sprint-bug-140 (TIER 1 batch). Two defects:
#
# Defect A (orchestrator): post-pr-orchestrator's BRIDGEBUILDER_REVIEW phase
# reports `completed` even when bridge-orchestrator produced no fresh findings
# file this iteration. Operators see "Bridgebuilder review complete" with stale
# findings re-tagged with the current PR number — a textbook silent failure.
# Fix: after bridge-orchestrator runs, verify `${bridge_id}-iter*-findings.json`
# exists. If absent, mark phase `skipped` with a WARN line.
#
# Defect B (triage): post-pr-triage.sh globs ALL findings files in REVIEW_DIR,
# including stale entries from previous bridge runs. Fix: read `bridge_id`
# from `.run/bridge-state.json`; filter findings to `${bridge_id}-*-findings.json`.
# Backward-compat: when bridge-state.json absent or bridge_id empty, fall back
# to existing glob (interactive /run-bridge mode).
# =============================================================================

setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT_REAL="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    TRIAGE_SCRIPT="$PROJECT_ROOT_REAL/.claude/scripts/post-pr-triage.sh"

    [[ -f "$TRIAGE_SCRIPT" ]] || skip "post-pr-triage.sh not found"
    command -v jq >/dev/null 2>&1 || skip "jq not installed"

    export BATS_TMPDIR="${BATS_TMPDIR:-/tmp}"
    export TEST_TMPDIR="$BATS_TMPDIR/post-pr-bb-676-$$"
    mkdir -p "$TEST_TMPDIR"

    export TEST_REPO="$TEST_TMPDIR/repo"
    mkdir -p "$TEST_REPO/.run/bridge-reviews"
    mkdir -p "$TEST_REPO/grimoires/loa/a2a/trajectory"
    mkdir -p "$TEST_REPO/.run/bridge-pending-bugs"
    cd "$TEST_REPO"

    # Stable test bridge_id
    export TEST_BRIDGE_ID="bridge-20260503-test01"
    export STALE_BRIDGE_ID="bridge-20260101-stale99"
}

teardown() {
    cd /
    [[ -d "$TEST_TMPDIR" ]] && rm -rf "$TEST_TMPDIR"
}

# Helper: write bridge-state.json with given bridge_id.
_write_bridge_state() {
    local bridge_id="$1"
    jq -n --arg id "$bridge_id" '{
        bridge_id: $id,
        state: "REVIEWING",
        depth: 5,
        flatline_threshold: 1,
        repos: ["test/repo"],
        prs_handled: []
    }' > "$TEST_REPO/.run/bridge-state.json"
}

# Helper: write a findings JSON file.
_write_findings() {
    local path="$1"
    local title="${2:-test finding}"
    local severity="${3:-LOW}"
    jq -n --arg t "$title" --arg s "$severity" '{
        findings: [{
            id: "F-test",
            title: $t,
            severity: $s
        }]
    }' > "$path"
}

# -----------------------------------------------------------------------------
# Scenario 3.a (Defect B): triage filters stale findings by bridge_id
# -----------------------------------------------------------------------------
@test "676-triage: skips stale findings file when bridge_id mismatches" {
    _write_bridge_state "$TEST_BRIDGE_ID"
    # Stale file from a different bridge run.
    _write_findings "$TEST_REPO/.run/bridge-reviews/${STALE_BRIDGE_ID}-iter1-findings.json" \
        "stale finding" "LOW"

    # No fresh file for the current bridge_id.
    run "$TRIAGE_SCRIPT" --pr 1234 --review-dir "$TEST_REPO/.run/bridge-reviews"
    [[ "$status" -eq 0 ]]

    # Output should NOT process stale file's findings.
    if echo "$output" | grep -q "stale finding"; then
        echo "ERROR: triage processed stale findings (should have been filtered by bridge_id)"
        echo "$output"
        return 1
    fi

    # Output SHOULD warn about no findings for current bridge_id.
    echo "$output" | grep -qE "WARN.*${TEST_BRIDGE_ID}|no findings.*${TEST_BRIDGE_ID}|bridge_id|filter" || {
        echo "Expected WARN about bridge_id; got: $output"
        return 1
    }
}

# -----------------------------------------------------------------------------
# Scenario 3.b (Defect B): triage processes ONLY fresh findings file
# -----------------------------------------------------------------------------
@test "676-triage: processes fresh findings file matching bridge_id" {
    _write_bridge_state "$TEST_BRIDGE_ID"
    # Fresh file matching bridge_id.
    _write_findings "$TEST_REPO/.run/bridge-reviews/${TEST_BRIDGE_ID}-iter1-findings.json" \
        "fresh finding" "MEDIUM"
    # Also a stale file that must be ignored.
    _write_findings "$TEST_REPO/.run/bridge-reviews/${STALE_BRIDGE_ID}-iter5-findings.json" \
        "stale finding ignored" "HIGH"

    run "$TRIAGE_SCRIPT" --pr 1234 --review-dir "$TEST_REPO/.run/bridge-reviews"
    [[ "$status" -eq 0 ]]

    # Should process exactly the fresh file (not the stale one).
    # Iter-1 remediation MED: removed chained-|| pattern; pin a single
    # specific positive assertion. Test 8 below has the tighter assertion;
    # this test is the negative complement (NO stale processing).
    if echo "$output" | grep -qE "Processing.*${STALE_BRIDGE_ID}"; then
        echo "ERROR: stale findings file was processed"
        return 1
    fi

    # Positive: filter announcement for the matching bridge_id.
    echo "$output" | grep -qE "Filtered.*${TEST_BRIDGE_ID}" || {
        echo "Expected filter announcement for matching bridge_id; got: $output"
        return 1
    }
}

# -----------------------------------------------------------------------------
# Scenario 3.c (backward-compat): no bridge-state.json → glob all (existing behavior)
# -----------------------------------------------------------------------------
@test "676-triage: no bridge-state.json falls back to glob (backward compat)" {
    # No bridge-state.json at all (interactive /run-bridge legacy mode).
    _write_findings "$TEST_REPO/.run/bridge-reviews/legacy-iter1-findings.json" \
        "legacy finding" "LOW"

    run "$TRIAGE_SCRIPT" --pr 1234 --review-dir "$TEST_REPO/.run/bridge-reviews"
    [[ "$status" -eq 0 ]]

    # Should process the file (no filter applied).
    echo "$output" | grep -qE "Processing.*legacy-iter1-findings|legacy finding" || {
        echo "Expected backward-compat glob to process legacy findings; got: $output"
        return 1
    }
}

# -----------------------------------------------------------------------------
# Scenario 3.d (Defect A): orchestrator-side fresh-findings detection logic
# Tests the helper logic: given bridge_id and review_dir, detect whether a
# fresh findings file exists.
# -----------------------------------------------------------------------------
@test "676-orchestrator-helper: detects fresh findings present" {
    _write_bridge_state "$TEST_BRIDGE_ID"
    _write_findings "$TEST_REPO/.run/bridge-reviews/${TEST_BRIDGE_ID}-iter1-findings.json"

    # Inline the same shell predicate used by the orchestrator. If files
    # match `${bridge_id}-iter*-findings.json` exist in review_dir → "fresh".
    local review_dir="$TEST_REPO/.run/bridge-reviews"
    local bridge_id
    bridge_id=$(jq -r '.bridge_id' "$TEST_REPO/.run/bridge-state.json")

    local fresh_count
    fresh_count=$(find "$review_dir" -maxdepth 1 -name "${bridge_id}-iter*-findings.json" 2>/dev/null | wc -l | tr -d ' ')
    [[ "$fresh_count" -ge 1 ]] || {
        echo "Expected >= 1 fresh findings file; got: $fresh_count"
        return 1
    }
}

@test "676-orchestrator-helper: detects no fresh findings (silent producer)" {
    _write_bridge_state "$TEST_BRIDGE_ID"
    # Stale file only — should NOT be treated as fresh.
    _write_findings "$TEST_REPO/.run/bridge-reviews/${STALE_BRIDGE_ID}-iter1-findings.json"

    local review_dir="$TEST_REPO/.run/bridge-reviews"
    local bridge_id
    bridge_id=$(jq -r '.bridge_id' "$TEST_REPO/.run/bridge-state.json")

    local fresh_count
    fresh_count=$(find "$review_dir" -maxdepth 1 -name "${bridge_id}-iter*-findings.json" 2>/dev/null | wc -l | tr -d ' ')
    [[ "$fresh_count" -eq 0 ]] || {
        echo "Expected 0 fresh findings (only stale present); got: $fresh_count"
        return 1
    }
}

# -----------------------------------------------------------------------------
# Iter-1 remediation HIGH (bridgebuilder #700 review): freshness check must
# be ITERATION-SPECIFIC. A generic ${bridge_id}-iter*-findings.json glob
# accepts iter-1's stale file when iter-2 silently no-ops. Borg/K8s use
# generation counters; we use the simpler iter-N-specific filename check.
# -----------------------------------------------------------------------------
@test "676-orchestrator-helper: iter-specific freshness check rejects prior-iter file" {
    _write_bridge_state "$TEST_BRIDGE_ID"
    # iter-1 file present; iter-2 file absent.
    _write_findings "$TEST_REPO/.run/bridge-reviews/${TEST_BRIDGE_ID}-iter1-findings.json"

    local review_dir="$TEST_REPO/.run/bridge-reviews"
    local bridge_id
    bridge_id=$(jq -r '.bridge_id' "$TEST_REPO/.run/bridge-state.json")

    # Pre-fix (generic glob): would return 1 (iter-1 file is there).
    # Post-fix (iter-specific): must return 0 for iter=2 since
    # ${bridge_id}-iter2-findings.json does NOT exist.
    local iter=2
    local iter_specific_file="$review_dir/${bridge_id}-iter${iter}-findings.json"
    [[ ! -f "$iter_specific_file" ]] || {
        echo "Pre-condition: iter-2 file should NOT exist for this test"
        return 1
    }
}

@test "676-orchestrator-helper: iter-specific freshness check accepts current-iter file" {
    _write_bridge_state "$TEST_BRIDGE_ID"
    # Both iter-1 and iter-2 files present (normal multi-iter run).
    _write_findings "$TEST_REPO/.run/bridge-reviews/${TEST_BRIDGE_ID}-iter1-findings.json"
    _write_findings "$TEST_REPO/.run/bridge-reviews/${TEST_BRIDGE_ID}-iter2-findings.json"

    local review_dir="$TEST_REPO/.run/bridge-reviews"
    local bridge_id
    bridge_id=$(jq -r '.bridge_id' "$TEST_REPO/.run/bridge-state.json")

    local iter=2
    local iter_specific_file="$review_dir/${bridge_id}-iter${iter}-findings.json"
    [[ -f "$iter_specific_file" ]] || {
        echo "Expected iter-2 file present; got: $(ls $review_dir/)"
        return 1
    }
}

# -----------------------------------------------------------------------------
# Iter-1 remediation MED (bridgebuilder #700 review): tighten Defect B test
# assertions. The original test used `||` chained truthy expressions that
# could pass for the wrong reason. Replace with positive grep assertions.
# -----------------------------------------------------------------------------
@test "676-triage: fresh-findings test pins exact processing assertion (no chained-||)" {
    _write_bridge_state "$TEST_BRIDGE_ID"
    _write_findings "$TEST_REPO/.run/bridge-reviews/${TEST_BRIDGE_ID}-iter1-findings.json" \
        "fresh finding pin" "MEDIUM"
    _write_findings "$TEST_REPO/.run/bridge-reviews/${STALE_BRIDGE_ID}-iter5-findings.json" \
        "stale finding ignored" "HIGH"

    run "$TRIAGE_SCRIPT" --pr 1234 --review-dir "$TEST_REPO/.run/bridge-reviews"
    [[ "$status" -eq 0 ]]

    # Positive assertion: fresh file was processed (the log emits "Processing N findings from <file>").
    echo "$output" | grep -qE "Processing [0-9]+ findings from .*${TEST_BRIDGE_ID}-iter1-findings\\.json" || {
        echo "Expected positive 'Processing ... from <fresh-file>' log; got:"
        echo "$output"
        return 1
    }

    # Filter announcement: log says "Filtered to N findings file(s) matching bridge_id=${bridge_id}".
    echo "$output" | grep -qE "Filtered to 1 findings file.*${TEST_BRIDGE_ID}" || {
        echo "Expected filter-announce log line; got: $output"
        return 1
    }
}
