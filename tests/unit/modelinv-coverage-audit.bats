#!/usr/bin/env bats
# =============================================================================
# Cycle-108 sprint-2 T2.M — tools/modelinv-coverage-audit.py
# =============================================================================
# SR-7 + [ASSUMPTION-A4]. Validates:
#   - envelope-side v1.2 coverage computation
#   - per-cycle / per-skill breakdown
#   - skill-log comparison (optional --skill-log)
#   - --threshold + --strict-threshold (exit 3 on under)
#   - markdown report written
# =============================================================================

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    AUDIT="$REPO_ROOT/tools/modelinv-coverage-audit.py"
    TMP="$(mktemp -d)"
    cd "$TMP"

    # Synthetic envelope log: 4 entries (2 with v1.2 marker, 2 without).
    cat > envelopes.jsonl <<'EOF'
{"schema_version":"1.1.0","primitive_id":"MODELINV","event_type":"model.invoke.complete","ts_utc":"2026-05-10T10:00:00Z","prev_hash":"GENESIS","payload":{"models_requested":["anthropic:claude-opus-4-7"],"models_succeeded":["anthropic:claude-opus-4-7"],"models_failed":[],"operator_visible_warn":false,"writer_version":"1.2","pricing_snapshot":{"input_per_mtok":1000,"output_per_mtok":2000},"invocation_chain":["sprint-2","implement","skill-a"]}}
{"schema_version":"1.1.0","primitive_id":"MODELINV","event_type":"model.invoke.complete","ts_utc":"2026-05-10T11:00:00Z","prev_hash":"AAA","payload":{"models_requested":["anthropic:claude-opus-4-7"],"models_succeeded":["anthropic:claude-opus-4-7"],"models_failed":[],"operator_visible_warn":false,"writer_version":"1.2","invocation_chain":["sprint-2","review","skill-a"]}}
{"schema_version":"1.1.0","primitive_id":"MODELINV","event_type":"model.invoke.complete","ts_utc":"2026-05-10T12:00:00Z","prev_hash":"BBB","payload":{"models_requested":["openai:gpt-5.5"],"models_succeeded":["openai:gpt-5.5"],"models_failed":[],"operator_visible_warn":false,"invocation_chain":["sprint-1","implement","skill-b"]}}
{"schema_version":"1.1.0","primitive_id":"MODELINV","event_type":"model.invoke.complete","ts_utc":"2026-05-10T13:00:00Z","prev_hash":"CCC","payload":{"models_requested":["openai:gpt-5.5"],"models_succeeded":["openai:gpt-5.5"],"models_failed":[],"operator_visible_warn":false,"calling_primitive":"L1"}}
EOF
    OUT_MD="$TMP/coverage-audit.md"
}

teardown() {
    rm -rf "$TMP"
}

@test "T2.M: v1.2 coverage computed correctly (2/4 = 50%)" {
    run python3 "$AUDIT" --input envelopes.jsonl --markdown "$OUT_MD"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.envelope_coverage.total_envelopes == 4'
    echo "$output" | jq -e '.envelope_coverage.v12_marked == 2'
    echo "$output" | jq -e '.envelope_coverage.v12_coverage_pct == 0.5'
}

@test "T2.M: pricing_captured counts envelopes with pricing_snapshot" {
    run python3 "$AUDIT" --input envelopes.jsonl --markdown "$OUT_MD"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.envelope_coverage.pricing_captured == 1'
}

@test "T2.M: per-cycle attribution from invocation_chain" {
    run python3 "$AUDIT" --input envelopes.jsonl --markdown "$OUT_MD"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.envelope_coverage.per_cycle["sprint-2"].total == 2'
    echo "$output" | jq -e '.envelope_coverage.per_cycle["sprint-1"].total == 1'
}

@test "T2.M: per-skill rollup uses invocation_chain[0]" {
    run python3 "$AUDIT" --input envelopes.jsonl --markdown "$OUT_MD"
    [ "$status" -eq 0 ]
    # chain[0] is the cycle/sprint name in our synthetic data
    echo "$output" | jq -e '.envelope_coverage.per_skill["sprint-2"].total == 2'
}

@test "T2.M: --threshold pass when coverage >= threshold" {
    run python3 "$AUDIT" --input envelopes.jsonl --threshold 0.5 --markdown "$OUT_MD"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.threshold_pass == true'
}

@test "T2.M: --threshold reports fail when coverage < threshold" {
    run python3 "$AUDIT" --input envelopes.jsonl --threshold 0.9 --markdown "$OUT_MD"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.threshold_pass == false'
}

@test "T2.M: --strict-threshold exits 3 on under-threshold" {
    run python3 "$AUDIT" --input envelopes.jsonl --threshold 0.9 --strict-threshold --markdown "$OUT_MD"
    [ "$status" -eq 3 ]
    echo "$output" | grep -q "COVERAGE-AUDIT-FAIL"
}

@test "T2.M: --strict-threshold passes when at threshold" {
    run python3 "$AUDIT" --input envelopes.jsonl --threshold 0.5 --strict-threshold --markdown "$OUT_MD"
    [ "$status" -eq 0 ]
}

@test "T2.M: markdown report written" {
    run python3 "$AUDIT" --input envelopes.jsonl --markdown "$OUT_MD"
    [ "$status" -eq 0 ]
    [ -f "$OUT_MD" ]
    grep -q "# MODELINV coverage audit" "$OUT_MD"
    grep -q "Per-cycle breakdown" "$OUT_MD"
    grep -q "sprint-2" "$OUT_MD"
}

@test "T2.M: skill-log comparison" {
    cat > skill-log.jsonl <<'EOF'
{"skill": "sprint-2"}
{"skill": "sprint-2"}
{"skill": "sprint-2"}
{"skill": "sprint-2"}
{"skill": "sprint-1"}
EOF
    run python3 "$AUDIT" --input envelopes.jsonl --skill-log skill-log.jsonl --markdown "$OUT_MD"
    [ "$status" -eq 0 ]
    # skill-log has 5 invocations; envelopes-per-skill has sprint-2:2, sprint-1:1
    # matched = min(2,4) + min(1,1) = 3; pct = 3/5 = 0.6
    echo "$output" | jq -e '.skill_log_comparison.total_invocations == 5'
    echo "$output" | jq -e '.skill_log_comparison.total_envelopes_matched == 3'
}

@test "T2.M: missing input → 0 envelopes, no crash" {
    run python3 "$AUDIT" --input nonexistent.jsonl --markdown "$OUT_MD"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.envelope_coverage.total_envelopes == 0'
}

@test "T2.M: seal markers in log are skipped" {
    cat > with_markers.jsonl <<'EOF'
{"schema_version":"1.1.0","primitive_id":"MODELINV","event_type":"model.invoke.complete","ts_utc":"2026-05-10T10:00:00Z","prev_hash":"GENESIS","payload":{"models_requested":["anthropic:claude-opus-4-7"],"models_succeeded":[],"models_failed":[],"operator_visible_warn":false,"writer_version":"1.2"}}
[L4-DISABLED] some seal marker
EOF
    run python3 "$AUDIT" --input with_markers.jsonl --markdown "$OUT_MD"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.envelope_coverage.total_envelopes == 1'
}
