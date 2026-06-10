#!/usr/bin/env bats
# =============================================================================
# Intel-routing fix-plan #1 (2026-06-10) — cheval cost-attribution rollup
# =============================================================================
# Pins the contract of loa_cheval.metering.rollup: per-actor aggregation over
# the cost ledger (the sequencing gate before any tier→dispatch wiring), and
# the unpriced-call detector (pricing_source != "config" metered as $0 — the
# blind spot that motivated pricing-before-routability).
# =============================================================================

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    TMP_DIR="$(mktemp -d)"
    LEDGER="$TMP_DIR/ledger.jsonl"
    export PYTHONPATH="$REPO_ROOT/.claude/adapters"
    cat > "$LEDGER" <<'JSONL'
{"ts":"2026-06-09T10:00:00.000Z","trace_id":"t-1","agent":"jam-reviewer-gpt","provider":"openai","model":"gpt-5.5","tokens_in":1000,"tokens_out":200,"tokens_reasoning":0,"cost_micro_usd":5000,"pricing_source":"config"}
{"ts":"2026-06-10T11:00:00.000Z","trace_id":"t-2","agent":"jam-reviewer-gpt","provider":"openai","model":"gpt-5.5","tokens_in":2000,"tokens_out":400,"tokens_reasoning":0,"cost_micro_usd":10000,"pricing_source":"config"}
{"ts":"2026-06-10T12:00:00.000Z","trace_id":"t-2","agent":"deep-thinker","provider":"google","model":"gemini-3.1-pro","tokens_in":500,"tokens_out":100,"tokens_reasoning":50,"cost_micro_usd":0,"pricing_source":"unknown"}
JSONL
}

teardown() {
    rm -rf "$TMP_DIR"
}

_rollup() {
    python3 -m loa_cheval.metering.rollup --ledger "$LEDGER" "$@"
}

@test "rollup: by agent aggregates calls, tokens, cost (cost-desc order)" {
    run _rollup --by agent --json
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -r '.rows[0].key')" = "jam-reviewer-gpt" ]
    [ "$(echo "$output" | jq -r '.rows[0].calls')" = "2" ]
    [ "$(echo "$output" | jq -r '.rows[0].tokens_in')" = "3000" ]
    [ "$(echo "$output" | jq -r '.rows[0].cost_micro_usd')" = "15000" ]
}

@test "rollup: unpriced calls are counted, never silently folded into cost" {
    run _rollup --by agent --json
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -r '.rows[] | select(.key=="deep-thinker") | .unpriced_calls')" = "1" ]
    [ "$(echo "$output" | jq -r '.rows[] | select(.key=="deep-thinker") | .cost_micro_usd')" = "0" ]
}

@test "rollup: table mode emits the UNDERSTATES warning when unpriced calls exist" {
    run _rollup --by agent
    [ "$status" -eq 0 ]
    [[ "$output" == *"UNDERSTATES"* ]] || { echo "$output"; false; }
}

@test "rollup: --since filters by UTC day (inclusive)" {
    run _rollup --by agent --since 2026-06-10 --json
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -r '.rows[] | select(.key=="jam-reviewer-gpt") | .calls')" = "1" ]
}

@test "rollup: by day and by trace group correctly" {
    run _rollup --by day --json
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -r '[.rows[].key] | sort | join(",")')" = "2026-06-09,2026-06-10" ]
    run _rollup --by trace --json
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -r '.rows[] | select(.key=="t-2") | .calls')" = "2" ]
}

@test "rollup: empty ledger is a clean exit, not an error" {
    run python3 -m loa_cheval.metering.rollup --ledger "$TMP_DIR/nope.jsonl"
    [ "$status" -eq 0 ]
    [[ "$output" == *"empty"* ]]
}
