#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

# =============================================================================
# tests/unit/issue-759-scoring-engine-degraded-output.bats
#
# Issue #759: flatline-orchestrator emits empty stdout + 'ERROR: No items to
# score' on partial-success Phase 1 (3-of-6 OK). When both score files have
# zero items, scoring-engine.sh should emit a structured DEGRADED consensus
# JSON instead of `exit 3` with no output, so:
#   - operators get a machine-readable result (CI / dashboards)
#   - the orchestrator's `result=$(run_consensus ...)` capture isn't empty
#   - the empty-consensus state is observable, not silent
#
# Tests (B1):
#   B1.1 — both empty → emit structured JSON (not exit 3 with empty stdout)
#   B1.2 — JSON contains required top-level fields (high_consensus, disputed, etc.)
#   B1.3 — degraded=true and confidence="degraded" set on empty-input output
#   B1.4 — exit 0 (success — empty consensus IS a valid consensus result)
#   B1.5 — single-non-empty input still produces consensus (regression — was already supported)
#   B1.6 — orchestrator captures non-empty stdout when both inputs degraded
# =============================================================================

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    SCORING_ENGINE="$PROJECT_ROOT/.claude/scripts/scoring-engine.sh"
    [[ -f "$SCORING_ENGINE" ]] || skip "scoring-engine.sh not present"
    command -v jq >/dev/null 2>&1 || skip "jq not present"

    WORK_DIR="$(mktemp -d)"
    cd "$WORK_DIR"

    # Empty score files (both Phase 1 calls failed → both arrays empty).
    echo '{"scores":[]}' > "$WORK_DIR/gpt-empty.json"
    echo '{"scores":[]}' > "$WORK_DIR/opus-empty.json"
    echo '{"concerns":[]}' > "$WORK_DIR/gpt-skeptic-empty.json"
    echo '{"concerns":[]}' > "$WORK_DIR/opus-skeptic-empty.json"

    # Non-empty score files for regression coverage.
    cat > "$WORK_DIR/gpt-with-scores.json" <<'JSON'
{"scores":[{"id":"f1","weight":600,"justification":"test"}]}
JSON
    cat > "$WORK_DIR/opus-with-scores.json" <<'JSON'
{"scores":[{"id":"f1","weight":700,"justification":"test"}]}
JSON
}

teardown() {
    cd /
    if [[ -n "${WORK_DIR:-}" ]] && [[ -d "$WORK_DIR" ]]; then
        rm -rf "$WORK_DIR"
    fi
    return 0
}

@test "B1.1 — both empty inputs → emit JSON to stdout (not silent exit 3)" {
    run --separate-stderr "$SCORING_ENGINE" \
        --gpt-scores "$WORK_DIR/gpt-empty.json" \
        --opus-scores "$WORK_DIR/opus-empty.json" \
        --include-blockers \
        --skeptic-gpt "$WORK_DIR/gpt-skeptic-empty.json" \
        --skeptic-opus "$WORK_DIR/opus-skeptic-empty.json" \
        --json
    # Stdout MUST contain valid JSON (non-empty between { and }).
    [[ -n "$output" ]]
    echo "$output" | jq empty
}

@test "B1.2 — JSON contains required top-level fields per consensus contract" {
    run --separate-stderr "$SCORING_ENGINE" \
        --gpt-scores "$WORK_DIR/gpt-empty.json" \
        --opus-scores "$WORK_DIR/opus-empty.json" \
        --include-blockers \
        --json
    echo "$output" | jq empty
    # Required fields per consensus output contract (regular path uses
    # `consensus_summary`; #759 degraded path mirrors that key).
    [[ "$(echo "$output" | jq 'has("consensus_summary")')" == "true" ]]
    [[ "$(echo "$output" | jq 'has("high_consensus")')" == "true" ]]
    [[ "$(echo "$output" | jq 'has("disputed")')" == "true" ]]
    [[ "$(echo "$output" | jq 'has("low_value")')" == "true" ]]
    [[ "$(echo "$output" | jq 'has("blockers")')" == "true" ]]
    [[ "$(echo "$output" | jq '.high_consensus | type == "array"')" == "true" ]]
    [[ "$(echo "$output" | jq '.disputed | type == "array"')" == "true" ]]
}

@test "B1.3 — degraded=true and confidence reflects empty-input state" {
    run --separate-stderr "$SCORING_ENGINE" \
        --gpt-scores "$WORK_DIR/gpt-empty.json" \
        --opus-scores "$WORK_DIR/opus-empty.json" \
        --include-blockers \
        --json
    [[ "$(echo "$output" | jq -r '.degraded // false')" == "true" ]]
    [[ "$(echo "$output" | jq -r '.confidence // "?"')" == "degraded" ]]
    [[ "$(echo "$output" | jq -r '.degradation_reason // "?"')" == "no_items_to_score" ]]
    # Empty arrays — the degraded state should not invent findings.
    [[ "$(echo "$output" | jq -r '.consensus_summary.high_consensus_count')" == "0" ]]
    [[ "$(echo "$output" | jq -r '.consensus_summary.disputed_count')" == "0" ]]
}

@test "B1.4 — exit 0 (empty consensus IS a valid result, not an error)" {
    run --separate-stderr "$SCORING_ENGINE" \
        --gpt-scores "$WORK_DIR/gpt-empty.json" \
        --opus-scores "$WORK_DIR/opus-empty.json" \
        --include-blockers \
        --json
    [ "$status" -eq 0 ]
}

@test "B1.5 — single-empty input still produces consensus (regression)" {
    # gpt empty + opus has scores: should produce single-model consensus,
    # NOT trigger the "no items in either file" path. Pre-#759 the regular
    # output uses `consensus_summary` key + top-level `confidence`; the
    # degraded path emits `summary` key. Either is valid per the existing
    # contract — test that we got A consensus, not the degraded path.
    run --separate-stderr "$SCORING_ENGINE" \
        --gpt-scores "$WORK_DIR/gpt-empty.json" \
        --opus-scores "$WORK_DIR/opus-with-scores.json" \
        --include-blockers \
        --json
    [ "$status" -eq 0 ]
    echo "$output" | jq empty
    # Top-level `confidence` exists in BOTH the regular and degraded shapes.
    [[ "$(echo "$output" | jq -r '.confidence // "?"')" =~ ^(single_model|full|degraded)$ ]]
    # And NOT the #759 sentinel (this is the "single empty" path, not the "both empty" path).
    [[ "$(echo "$output" | jq -r '.degradation_reason // "none"')" != "no_items_to_score" ]]
}

@test "B1.6 — orchestrator-style capture: result=\$(scoring-engine ...) yields non-empty when degraded" {
    # Mirrors the orchestrator's run_consensus capture pattern. When the
    # scoring engine returns empty stdout, this captures "" and the
    # orchestrator's stdout is silently empty (the #759 main symptom).
    local result
    result=$("$SCORING_ENGINE" \
        --gpt-scores "$WORK_DIR/gpt-empty.json" \
        --opus-scores "$WORK_DIR/opus-empty.json" \
        --include-blockers \
        --skeptic-gpt "$WORK_DIR/gpt-skeptic-empty.json" \
        --skeptic-opus "$WORK_DIR/opus-skeptic-empty.json" \
        --json) || true
    [[ -n "$result" ]] || { echo "FAIL — result was empty (#759 reproduction)" >&2; return 1; }
    echo "$result" | jq empty
    [[ "$(echo "$result" | jq 'has("consensus_summary")')" == "true" ]]
}
