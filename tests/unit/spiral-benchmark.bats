#!/usr/bin/env bats
# Tests for spiral benchmark comparison tool (cycle-072)
# Covers: AC-14

setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    BENCHMARK="$PROJECT_ROOT/.claude/scripts/spiral-benchmark.sh"
    TEST_TMPDIR="$(mktemp -d)"

    # Create a sample flight recorder
    cat > "$TEST_TMPDIR/recorder-a.jsonl" << 'JSONL'
{"seq":1,"ts":"2026-04-15T10:00:00Z","phase":"CONFIG","actor":"spiral-harness","action":"profile","input_checksum":null,"output_checksum":null,"output_path":null,"output_bytes":0,"duration_ms":0,"cost_usd":0,"verdict":"profile=standard gates=sprint advisor=opus"}
{"seq":2,"ts":"2026-04-15T10:00:01Z","phase":"DISCOVERY","actor":"claude-sonnet","action":"invoke","input_checksum":null,"output_checksum":null,"output_path":"evidence/discovery-stdout.json","output_bytes":1500,"duration_ms":11000,"cost_usd":1,"verdict":null}
{"seq":3,"ts":"2026-04-15T10:02:00Z","phase":"GATE_sprint","actor":"flatline-orchestrator","action":"multi_model_review","input_checksum":null,"output_checksum":"abc123","output_path":"evidence/flatline-sprint.json","output_bytes":5000,"duration_ms":0,"cost_usd":0,"verdict":"high=4 blockers=3"}
{"seq":4,"ts":"2026-04-15T10:05:00Z","phase":"IMPLEMENTATION","actor":"claude-sonnet","action":"invoke","input_checksum":null,"output_checksum":null,"output_path":"evidence/implementation-stdout.json","output_bytes":3000,"duration_ms":252000,"cost_usd":5,"verdict":null}
{"seq":5,"ts":"2026-04-15T10:08:00Z","phase":"GATE_REVIEW","actor":"claude-opus","action":"verdict","input_checksum":null,"output_checksum":"def456","output_path":"feedback.md","output_bytes":5000,"duration_ms":0,"cost_usd":0,"verdict":"APPROVED"}
{"seq":6,"ts":"2026-04-15T10:09:00Z","phase":"GATE_AUDIT","actor":"claude-opus","action":"verdict","input_checksum":null,"output_checksum":"ghi789","output_path":"audit.md","output_bytes":4000,"duration_ms":0,"cost_usd":0,"verdict":"APPROVED"}
{"seq":7,"ts":"2026-04-15T10:09:30Z","phase":"SUMMARY","actor":"spiral-harness","action":"finalize","input_checksum":null,"output_checksum":null,"output_path":null,"output_bytes":0,"duration_ms":0,"cost_usd":6,"verdict":"actions=6 failures=0 cost=6"}
JSONL
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

# ---------------------------------------------------------------------------
# Test 1: produces markdown output from two recorders (AC-14)
# ---------------------------------------------------------------------------
@test "benchmark: produces markdown from two flight recorders" {
    run "$BENCHMARK" \
        --a "$TEST_TMPDIR/recorder-a.jsonl" \
        --b "$TEST_TMPDIR/recorder-a.jsonl" \
        --label-a "Run A" --label-b "Run B"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"# Spiral Benchmark Comparison"* ]]
    [[ "$output" == *"Run A"* ]]
    [[ "$output" == *"Run B"* ]]
}

# ---------------------------------------------------------------------------
# Test 2: handles missing flight recorder gracefully (AC-14)
# ---------------------------------------------------------------------------
@test "benchmark: handles missing flight recorder" {
    run "$BENCHMARK" \
        --a "$TEST_TMPDIR/recorder-a.jsonl" \
        --b "$TEST_TMPDIR/nonexistent.jsonl" \
        --label-a "Harness" --label-b "Raw Claude"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"N/A"* ]]
    [[ "$output" == *"ABSENT"* ]]
}

# ---------------------------------------------------------------------------
# Test 3: comparison includes all required dimensions (AC-14)
# ---------------------------------------------------------------------------
@test "benchmark: includes all comparison dimensions" {
    run "$BENCHMARK" \
        --a "$TEST_TMPDIR/recorder-a.jsonl" \
        --b "$TEST_TMPDIR/recorder-a.jsonl"
    [[ "$status" -eq 0 ]]
    # Check all required dimensions are present
    [[ "$output" == *"Profile"* ]]
    [[ "$output" == *"Total Cost"* ]]
    [[ "$output" == *"Total Duration"* ]]
    [[ "$output" == *"Invocations"* ]]
    [[ "$output" == *"Failures"* ]]
    [[ "$output" == *"Review"* ]]
    [[ "$output" == *"Audit"* ]]
    [[ "$output" == *"Flatline"* ]]
    [[ "$output" == *"Evidence Artifacts"* ]]
}

# ---------------------------------------------------------------------------
# Test 4: extracts correct cost from recorder
# ---------------------------------------------------------------------------
@test "benchmark: extracts correct total cost" {
    run "$BENCHMARK" \
        --a "$TEST_TMPDIR/recorder-a.jsonl" \
        --b "$TEST_TMPDIR/recorder-a.jsonl"
    [[ "$status" -eq 0 ]]
    # Total cost should include the $6 from the SUMMARY entry
    [[ "$output" == *'$'*"6"* || "$output" == *'$'*"12"* ]]
}

# ---------------------------------------------------------------------------
# Test 5: requires both --a and --b flags
# ---------------------------------------------------------------------------
@test "benchmark: requires both --a and --b flags" {
    run "$BENCHMARK" --a "$TEST_TMPDIR/recorder-a.jsonl"
    [[ "$status" -eq 2 ]]
    [[ "$output" == *"--a and --b required"* ]]
}
