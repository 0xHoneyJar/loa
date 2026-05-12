#!/usr/bin/env bats
# =============================================================================
# Cycle-108 sprint-3 T3.A — tools/compute-baselines.py
# =============================================================================
# PRD §5 FR-8 (IMP-001) + SDD §5.9 + §20.3 ATK-A4.
# =============================================================================

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    COMPUTE="$REPO_ROOT/tools/compute-baselines.py"
    TMP="$(mktemp -d)"
    cd "$TMP"
    # Empty synthetic log → forces default-baseline path.
    : > envelopes.jsonl
    OUTPUT="$TMP/baselines.json"
    AUDIT="$TMP/baselines.audit.jsonl"
}

teardown() {
    rm -rf "$TMP"
}

@test "T3.A: emits baselines.json with all 6 strata" {
    run python3 "$COMPUTE" --input envelopes.jsonl --output "$OUTPUT" --audit-out "$AUDIT"
    [ "$status" -eq 0 ]
    [ -f "$OUTPUT" ]
    jq -e '.strata.glue.advisor_baseline.audit_pass_rate' "$OUTPUT"
    jq -e '.strata.parser.advisor_baseline.audit_pass_rate' "$OUTPUT"
    jq -e '.strata.cryptographic.advisor_baseline.audit_pass_rate' "$OUTPUT"
    jq -e '.strata.testing.advisor_baseline.audit_pass_rate' "$OUTPUT"
    jq -e '.strata.infrastructure.advisor_baseline.audit_pass_rate' "$OUTPUT"
    jq -e '.strata.frontend.advisor_baseline.audit_pass_rate' "$OUTPUT"
}

@test "T3.A: executor_target derives from advisor_baseline × 0.95" {
    run python3 "$COMPUTE" --input envelopes.jsonl --output "$OUTPUT" --audit-out "$AUDIT"
    [ "$status" -eq 0 ]
    # cryptographic advisor=0.99, executor target=0.99*0.95=0.9405
    jq -e '.strata.cryptographic.executor_target.audit_pass_rate == 0.9405' "$OUTPUT"
}

@test "T3.A: signed flag is false until signed" {
    run python3 "$COMPUTE" --input envelopes.jsonl --output "$OUTPUT" --audit-out "$AUDIT"
    [ "$status" -eq 0 ]
    jq -e '.signed == false' "$OUTPUT"
}

@test "T3.A: git_sha_at_signing captures current HEAD" {
    run python3 "$COMPUTE" --input envelopes.jsonl --output "$OUTPUT" --audit-out "$AUDIT"
    [ "$status" -eq 0 ]
    sha=$(jq -r '.git_sha_at_signing' "$OUTPUT")
    expected=$(git -C "$REPO_ROOT" rev-parse HEAD)
    [ "$sha" = "$expected" ]
}

@test "T3.A: insufficient data → default_baseline provenance" {
    run python3 "$COMPUTE" --input envelopes.jsonl --output "$OUTPUT" --audit-out "$AUDIT"
    [ "$status" -eq 0 ]
    jq -e '.strata.glue.provenance.source == "default_baseline"' "$OUTPUT"
    jq -e '.strata.glue.provenance.historical_n == 0' "$OUTPUT"
}

@test "T3.A: --strata filters to subset" {
    run python3 "$COMPUTE" --input envelopes.jsonl --output "$OUTPUT" --audit-out "$AUDIT" --strata glue,parser
    [ "$status" -eq 0 ]
    jq -e '.strata | keys | length == 2' "$OUTPUT"
    jq -e '.strata | has("glue")' "$OUTPUT"
    jq -e '.strata | has("parser")' "$OUTPUT"
}

@test "T3.A: deterministic output (sort_keys=True)" {
    python3 "$COMPUTE" --input envelopes.jsonl --output "$OUTPUT.1" --audit-out "$AUDIT"
    python3 "$COMPUTE" --input envelopes.jsonl --output "$OUTPUT.2" --audit-out "$AUDIT"
    # The only difference between the two runs is ts_utc; strip it before diff.
    jq 'del(.ts_utc)' "$OUTPUT.1" > "$OUTPUT.1.clean"
    jq 'del(.ts_utc)' "$OUTPUT.2" > "$OUTPUT.2.clean"
    diff "$OUTPUT.1.clean" "$OUTPUT.2.clean"
}

@test "T3.A: WARN message for insufficient historical data" {
    run python3 "$COMPUTE" --input envelopes.jsonl --output "$OUTPUT" --audit-out "$AUDIT"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "insufficient historical data\|default_baseline"
}

@test "T3.A: notes field references T3.A.OP + anti-fitting protection" {
    run python3 "$COMPUTE" --input envelopes.jsonl --output "$OUTPUT" --audit-out "$AUDIT"
    [ "$status" -eq 0 ]
    grep -q "T3.A.OP\|Anti-fitting" "$OUTPUT"
}

@test "T3.A: --operator-key-id annotates signed_by_key_id" {
    run python3 "$COMPUTE" --input envelopes.jsonl --output "$OUTPUT" --audit-out "$AUDIT" --operator-key-id "OP-2026-05"
    [ "$status" -eq 0 ]
    jq -e '.signed_by_key_id == "OP-2026-05"' "$OUTPUT"
}
