#!/usr/bin/env bats
# Unit tests for spiral-evidence.sh — Flight Recorder + Evidence Verification
# Cycle-071: Spiral Harness Architecture

setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"

    export BATS_TMPDIR="${BATS_TMPDIR:-/tmp}"
    export TEST_TMPDIR="$BATS_TMPDIR/spiral-evidence-test-$$"
    mkdir -p "$TEST_TMPDIR/cycle-test"

    export PROJECT_ROOT="$TEST_TMPDIR"

    # Source the evidence library
    source "$BATS_TEST_DIR/../../.claude/scripts/spiral-evidence.sh"
}

teardown() {
    cd /
    if [[ -d "$TEST_TMPDIR" ]]; then
        rm -rf "$TEST_TMPDIR"
    fi
}

# =============================================================================
# Flight Recorder Init
# =============================================================================

@test "evidence: init creates flight recorder file" {
    _init_flight_recorder "$TEST_TMPDIR/cycle-test"
    [ -f "$TEST_TMPDIR/cycle-test/flight-recorder.jsonl" ]
}

@test "evidence: init creates file with 600 permissions" {
    _init_flight_recorder "$TEST_TMPDIR/cycle-test"
    local perms
    perms=$(stat -c %a "$TEST_TMPDIR/cycle-test/flight-recorder.jsonl" 2>/dev/null || \
            stat -f %Lp "$TEST_TMPDIR/cycle-test/flight-recorder.jsonl" 2>/dev/null)
    [ "$perms" = "600" ]
}

@test "evidence: init resets seq to 0" {
    _init_flight_recorder "$TEST_TMPDIR/cycle-test"
    [ "$_FLIGHT_RECORDER_SEQ" -eq 0 ]
}

# =============================================================================
# Record Action
# =============================================================================

@test "evidence: record_action appends valid JSONL" {
    _init_flight_recorder "$TEST_TMPDIR/cycle-test"
    _record_action "DISCOVERY" "claude-opus" "write_prd" "" "sha256:abc" "prd.md" 2847 36000 0.85 ""

    local lines
    lines=$(wc -l < "$TEST_TMPDIR/cycle-test/flight-recorder.jsonl")
    [ "$lines" -eq 1 ]

    # Validate JSON
    jq empty "$TEST_TMPDIR/cycle-test/flight-recorder.jsonl"
}

@test "evidence: seq numbers increment monotonically" {
    _init_flight_recorder "$TEST_TMPDIR/cycle-test"
    _record_action "PHASE1" "test" "test" "" "" "" 0 0 0 ""
    _record_action "PHASE2" "test" "test" "" "" "" 0 0 0 ""
    _record_action "PHASE3" "test" "test" "" "" "" 0 0 0 ""

    local seq1 seq2 seq3
    seq1=$(sed -n '1p' "$TEST_TMPDIR/cycle-test/flight-recorder.jsonl" | jq '.seq')
    seq2=$(sed -n '2p' "$TEST_TMPDIR/cycle-test/flight-recorder.jsonl" | jq '.seq')
    seq3=$(sed -n '3p' "$TEST_TMPDIR/cycle-test/flight-recorder.jsonl" | jq '.seq')

    [ "$seq1" -eq 1 ]
    [ "$seq2" -eq 2 ]
    [ "$seq3" -eq 3 ]
}

@test "evidence: record_action includes all fields" {
    _init_flight_recorder "$TEST_TMPDIR/cycle-test"
    _record_action "DISCOVERY" "claude-opus" "write_prd" "sha256:in" "sha256:out" "prd.md" 2847 36000 0.85 "OK"

    local entry
    entry=$(head -1 "$TEST_TMPDIR/cycle-test/flight-recorder.jsonl")

    echo "$entry" | jq -e '.phase == "DISCOVERY"'
    echo "$entry" | jq -e '.actor == "claude-opus"'
    echo "$entry" | jq -e '.action == "write_prd"'
    echo "$entry" | jq -e '.input_checksum == "sha256:in"'
    echo "$entry" | jq -e '.output_checksum == "sha256:out"'
    echo "$entry" | jq -e '.output_path == "prd.md"'
    echo "$entry" | jq -e '.output_bytes == 2847'
    echo "$entry" | jq -e '.cost_usd == 0.85'
    echo "$entry" | jq -e '.verdict == "OK"'
}

@test "evidence: null fields handled correctly" {
    _init_flight_recorder "$TEST_TMPDIR/cycle-test"
    _record_action "TEST" "test" "test" "" "" "" 0 0 0 ""

    local entry
    entry=$(head -1 "$TEST_TMPDIR/cycle-test/flight-recorder.jsonl")
    echo "$entry" | jq -e '.input_checksum == null'
    echo "$entry" | jq -e '.output_checksum == null'
    echo "$entry" | jq -e '.verdict == null'
}

@test "evidence: record_failure creates FAILED entry" {
    _init_flight_recorder "$TEST_TMPDIR/cycle-test"
    _record_failure "GATE_PRD" "MISSING_ARTIFACT" "prd.md"

    local entry
    entry=$(head -1 "$TEST_TMPDIR/cycle-test/flight-recorder.jsonl")
    echo "$entry" | jq -e '.action == "FAILED"'
    echo "$entry" | jq -e '.verdict | startswith("FAIL:")'
}

# =============================================================================
# Artifact Verification
# =============================================================================

@test "evidence: verify_artifact passes for valid file" {
    _init_flight_recorder "$TEST_TMPDIR/cycle-test"
    # Create a 1000-byte file
    head -c 1000 /dev/urandom | base64 > "$TEST_TMPDIR/valid-artifact.md"

    local checksum
    checksum=$(_verify_artifact "TEST" "$TEST_TMPDIR/valid-artifact.md" 500)
    [ $? -eq 0 ]
    [ -n "$checksum" ]
    [[ "$checksum" =~ ^[a-f0-9]{64}$ ]]
}

@test "evidence: verify_artifact fails for missing file" {
    _init_flight_recorder "$TEST_TMPDIR/cycle-test"

    run _verify_artifact "TEST" "$TEST_TMPDIR/nonexistent.md" 500
    [ "$status" -eq 1 ]
}

@test "evidence: verify_artifact fails for too-small file" {
    _init_flight_recorder "$TEST_TMPDIR/cycle-test"
    echo "tiny" > "$TEST_TMPDIR/small.md"

    run _verify_artifact "TEST" "$TEST_TMPDIR/small.md" 500
    [ "$status" -eq 1 ]
}

# =============================================================================
# Flatline Output Verification
# =============================================================================

@test "evidence: verify_flatline passes for valid consensus" {
    _init_flight_recorder "$TEST_TMPDIR/cycle-test"
    echo '{"consensus_summary":{"high_consensus_count":5,"blocker_count":3}}' > "$TEST_TMPDIR/flatline.json"

    local result
    result=$(_verify_flatline_output "PRD" "$TEST_TMPDIR/flatline.json")
    [ $? -eq 0 ]
    [[ "$result" == *"high=5"* ]]
    [[ "$result" == *"blockers=3"* ]]
}

@test "evidence: verify_flatline fails for missing file" {
    _init_flight_recorder "$TEST_TMPDIR/cycle-test"

    run _verify_flatline_output "PRD" "$TEST_TMPDIR/nonexistent.json"
    [ "$status" -eq 1 ]
}

@test "evidence: verify_flatline fails for invalid JSON" {
    _init_flight_recorder "$TEST_TMPDIR/cycle-test"
    echo "not json" > "$TEST_TMPDIR/bad.json"

    run _verify_flatline_output "PRD" "$TEST_TMPDIR/bad.json"
    [ "$status" -eq 1 ]
}

@test "evidence: verify_flatline fails for missing consensus" {
    _init_flight_recorder "$TEST_TMPDIR/cycle-test"
    echo '{"some_other_field": true}' > "$TEST_TMPDIR/no-consensus.json"

    run _verify_flatline_output "PRD" "$TEST_TMPDIR/no-consensus.json"
    [ "$status" -eq 1 ]
}

# =============================================================================
# Review Verdict Verification
# =============================================================================

@test "evidence: verify_verdict detects APPROVED" {
    _init_flight_recorder "$TEST_TMPDIR/cycle-test"
    echo "All good. Sprint approved." > "$TEST_TMPDIR/feedback.md"

    _verify_review_verdict "REVIEW" "$TEST_TMPDIR/feedback.md"
    [ $? -eq 0 ]
}

@test "evidence: verify_verdict detects CHANGES_REQUIRED" {
    _init_flight_recorder "$TEST_TMPDIR/cycle-test"
    echo "CHANGES_REQUIRED: fix the bug." > "$TEST_TMPDIR/feedback.md"

    run _verify_review_verdict "REVIEW" "$TEST_TMPDIR/feedback.md"
    [ "$status" -eq 1 ]
}

@test "evidence: verify_verdict fails for missing verdict" {
    _init_flight_recorder "$TEST_TMPDIR/cycle-test"
    echo "Some text without a verdict." > "$TEST_TMPDIR/feedback.md"

    run _verify_review_verdict "REVIEW" "$TEST_TMPDIR/feedback.md"
    [ "$status" -eq 1 ]
}

@test "evidence: verify_verdict fails for missing file" {
    _init_flight_recorder "$TEST_TMPDIR/cycle-test"

    run _verify_review_verdict "REVIEW" "$TEST_TMPDIR/nonexistent.md"
    [ "$status" -eq 1 ]
}

# =============================================================================
# Cost Tracking
# =============================================================================

@test "evidence: cumulative cost sums correctly" {
    _init_flight_recorder "$TEST_TMPDIR/cycle-test"
    _record_action "P1" "test" "test" "" "" "" 0 0 0.50 ""
    _record_action "P2" "test" "test" "" "" "" 0 0 1.25 ""
    _record_action "P3" "test" "test" "" "" "" 0 0 0.75 ""

    local total
    total=$(_get_cumulative_cost)
    # Should be 2.5
    [ "$(echo "$total" | awk '{printf "%.1f", $1}')" = "2.5" ]
}

@test "evidence: check_budget passes when within limit" {
    _init_flight_recorder "$TEST_TMPDIR/cycle-test"
    _record_action "P1" "test" "test" "" "" "" 0 0 3.00 ""

    _check_budget 10
    [ $? -eq 0 ]
}

@test "evidence: check_budget fails when exceeded" {
    _init_flight_recorder "$TEST_TMPDIR/cycle-test"
    _record_action "P1" "test" "test" "" "" "" 0 0 11.00 ""

    run _check_budget 10
    [ "$status" -eq 1 ]
}

# =============================================================================
# Budget boundary (Issue #515): spent == max should PASS, not fail
# =============================================================================

@test "evidence: check_budget passes when spent equals exactly max (Issue #515)" {
    _init_flight_recorder "$TEST_TMPDIR/cycle-test"
    # Simulate exactly $10 cumulative spend (the #515 boundary condition)
    _record_action "DISCOVERY" "test" "test" "" "" "" 0 0 1.00 ""
    _record_action "ARCHITECTURE" "test" "test" "" "" "" 0 0 1.00 ""
    _record_action "PLANNING" "test" "test" "" "" "" 0 0 1.00 ""
    _record_action "IMPLEMENTATION" "test" "test" "" "" "" 0 0 5.00 ""
    _record_action "REVIEW" "test" "test" "" "" "" 0 0 2.00 ""

    # Total = $10.00, max = $10 → should PASS (strictly greater, not >=)
    _check_budget 10
    [ $? -eq 0 ]
}

@test "evidence: check_budget fails when spent is strictly greater than max" {
    _init_flight_recorder "$TEST_TMPDIR/cycle-test"
    _record_action "P1" "test" "test" "" "" "" 0 0 10.01 ""

    run _check_budget 10
    [ "$status" -eq 1 ]
}

# =============================================================================
# Flatline Summary
# =============================================================================

@test "evidence: summarize_flatline extracts findings" {
    echo '{"high_consensus":[{"description":"Good finding"}],"blockers":[{"concern":"Bad thing"}]}' > "$TEST_TMPDIR/flatline.json"

    local summary
    summary=$(_summarize_flatline "$TEST_TMPDIR/flatline.json")
    [[ "$summary" == *"Good finding"* ]]
    [[ "$summary" == *"Bad thing"* ]]
}

@test "evidence: summarize_flatline handles empty file" {
    local summary
    summary=$(_summarize_flatline "$TEST_TMPDIR/nonexistent.json")
    [ -z "$summary" ]
}

# =============================================================================
# Finalize
# =============================================================================

@test "evidence: finalize adds summary entry" {
    _init_flight_recorder "$TEST_TMPDIR/cycle-test"
    _record_action "P1" "test" "test" "" "" "" 0 0 1.00 ""
    _record_action "P2" "test" "test" "" "" "" 0 0 2.00 ""
    _finalize_flight_recorder "$TEST_TMPDIR/cycle-test"

    local last_entry
    last_entry=$(tail -1 "$TEST_TMPDIR/cycle-test/flight-recorder.jsonl")
    echo "$last_entry" | jq -e '.phase == "SUMMARY"'
    echo "$last_entry" | jq -e '.action == "finalize"'
    echo "$last_entry" | jq -e '.verdict | contains("actions=2")'
}
