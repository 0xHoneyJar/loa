#!/usr/bin/env bats
# cycle-109 Sprint 5 T5.5 — substrate-health CLI: threshold warnings +
# log-redactor integration (FR-5.7 + NFR-Sec-3).

setup() {
    export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    export TMP="$(mktemp -d -t loa-substrate-health-XXXXXX)"
    export PYTHONPATH="$PROJECT_ROOT/.claude/adapters${PYTHONPATH:+:$PYTHONPATH}"
    export CLI="$PROJECT_ROOT/.claude/scripts/loa-substrate-health.sh"
}

teardown() {
    rm -rf "$TMP"
}

# --- Helper: write a MODELINV envelope to the test log ---------------------
_emit() {
    local log="$1"; local ts="$2"; local payload="$3"
    printf '{"primitive_id":"MODELINV","event_type":"model.invoke.complete","timestamp":"%s","payload":%s}\n' \
        "$ts" "$payload" >> "$log"
}

# ---------------------------------------------------------------------------
# Threshold warnings (FR-5.7)
# ---------------------------------------------------------------------------

@test "T5.5: red band emits RED warning + KF-suggest text" {
    log="$TMP/red.jsonl"
    # 10 invocations: 2 succeed, 8 fail → 20% red
    for i in 1 2; do
        _emit "$log" "$(date -u -Iseconds | sed 's/+00:00/Z/')" \
            '{"models_requested":["anthropic:claude-opus-4-7"],"models_succeeded":["anthropic:claude-opus-4-7"],"models_failed":[],"operator_visible_warn":false,"final_model_id":"anthropic:claude-opus-4-7"}'
    done
    for i in 1 2 3 4 5 6 7 8; do
        _emit "$log" "$(date -u -Iseconds | sed 's/+00:00/Z/')" \
            '{"models_requested":["anthropic:claude-opus-4-7"],"models_succeeded":[],"models_failed":[{"model":"anthropic:claude-opus-4-7","provider":"anthropic","error_class":"EMPTY_CONTENT","message_redacted":"x"}],"operator_visible_warn":true}'
    done

    run "$CLI" --log-path "$log" --window 24h
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "RED"
    echo "$output" | grep -q "RED band"
    echo "$output" | grep -q "KF entry"
}

@test "T5.5: yellow band emits YELLOW warning" {
    log="$TMP/yellow.jsonl"
    # 10 invocations: 6 succeed, 4 fail → 60% yellow
    for i in 1 2 3 4 5 6; do
        _emit "$log" "$(date -u -Iseconds | sed 's/+00:00/Z/')" \
            '{"models_requested":["anthropic:claude-opus-4-7"],"models_succeeded":["anthropic:claude-opus-4-7"],"models_failed":[],"operator_visible_warn":false,"final_model_id":"anthropic:claude-opus-4-7"}'
    done
    for i in 1 2 3 4; do
        _emit "$log" "$(date -u -Iseconds | sed 's/+00:00/Z/')" \
            '{"models_requested":["anthropic:claude-opus-4-7"],"models_succeeded":[],"models_failed":[{"model":"anthropic:claude-opus-4-7","provider":"anthropic","error_class":"EMPTY_CONTENT","message_redacted":"x"}],"operator_visible_warn":true}'
    done

    run "$CLI" --log-path "$log" --window 24h
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "YELLOW"
    echo "$output" | grep -q "YELLOW band"
}

@test "T5.5: green band does NOT emit threshold warning text" {
    log="$TMP/green.jsonl"
    # 10 succeed → 100% green
    for i in 1 2 3 4 5 6 7 8 9 10; do
        _emit "$log" "$(date -u -Iseconds | sed 's/+00:00/Z/')" \
            '{"models_requested":["anthropic:claude-opus-4-7"],"models_succeeded":["anthropic:claude-opus-4-7"],"models_failed":[],"operator_visible_warn":false,"final_model_id":"anthropic:claude-opus-4-7"}'
    done

    run "$CLI" --log-path "$log" --window 24h
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "GREEN"
    ! echo "$output" | grep -q "RED band"
    ! echo "$output" | grep -q "YELLOW band"
}

# ---------------------------------------------------------------------------
# Log-redactor integration (NFR-Sec-3)
# ---------------------------------------------------------------------------

@test "T5.5: rationale-borne fake AKIA token is scrubbed from output" {
    skip_unless_redactor

    log="$TMP/leak.jsonl"
    # Embed a fake AWS access key shape in verdict_quality.rationale
    _emit "$log" "$(date -u -Iseconds | sed 's/+00:00/Z/')" \
        '{"models_requested":["anthropic:claude-opus-4-7"],"models_succeeded":["anthropic:claude-opus-4-7"],"models_failed":[],"operator_visible_warn":false,"final_model_id":"anthropic:claude-opus-4-7","verdict_quality":{"status":"APPROVED","consensus_outcome":"consensus","truncation_waiver_applied":false,"voices_planned":1,"voices_succeeded":1,"voices_succeeded_ids":["x"],"voices_dropped":[],"chain_health":"ok","confidence_floor":"low","rationale":"investigated AKIAIOSFODNN7EXAMPLE found in payload"}}'

    run "$CLI" --log-path "$log" --window 24h --json
    [ "$status" -eq 0 ]
    # The literal AKIA shape MUST NOT appear in scrubbed stdout
    ! echo "$output" | grep -q "AKIAIOSFODNN7EXAMPLE"
}

@test "T5.5: rationale-borne fake Bearer token is scrubbed from output" {
    skip_unless_redactor

    log="$TMP/leak2.jsonl"
    _emit "$log" "$(date -u -Iseconds | sed 's/+00:00/Z/')" \
        '{"models_requested":["anthropic:claude-opus-4-7"],"models_succeeded":["anthropic:claude-opus-4-7"],"models_failed":[],"operator_visible_warn":false,"final_model_id":"anthropic:claude-opus-4-7","verdict_quality":{"status":"APPROVED","consensus_outcome":"consensus","truncation_waiver_applied":false,"voices_planned":1,"voices_succeeded":1,"voices_succeeded_ids":["x"],"voices_dropped":[],"chain_health":"ok","confidence_floor":"low","rationale":"saw Bearer sk-ant-fake1234567890ABCDEFGHIJK token"}}'

    run "$CLI" --log-path "$log" --window 24h --json
    [ "$status" -eq 0 ]
    ! echo "$output" | grep -q "sk-ant-fake1234567890ABCDEFGHIJK"
}

# ---------------------------------------------------------------------------
# Misc CLI behavior
# ---------------------------------------------------------------------------

@test "T5.5: missing log path yields zero-invocation report (no crash)" {
    run "$CLI" --log-path "$TMP/does-not-exist.jsonl" --window 24h
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "total invocations: 0"
}

@test "T5.5: --json output is valid JSON" {
    log="$TMP/json.jsonl"
    _emit "$log" "$(date -u -Iseconds | sed 's/+00:00/Z/')" \
        '{"models_requested":["anthropic:claude-opus-4-7"],"models_succeeded":["anthropic:claude-opus-4-7"],"models_failed":[],"operator_visible_warn":false,"final_model_id":"anthropic:claude-opus-4-7"}'

    run "$CLI" --log-path "$log" --json --window 24h
    [ "$status" -eq 0 ]
    echo "$output" | python3 -c "import json,sys; json.loads(sys.stdin.read())"
}

@test "T5.5: --model filter restricts aggregation" {
    log="$TMP/filter.jsonl"
    _emit "$log" "$(date -u -Iseconds | sed 's/+00:00/Z/')" \
        '{"models_requested":["anthropic:claude-opus-4-7"],"models_succeeded":["anthropic:claude-opus-4-7"],"models_failed":[],"operator_visible_warn":false,"final_model_id":"anthropic:claude-opus-4-7"}'
    _emit "$log" "$(date -u -Iseconds | sed 's/+00:00/Z/')" \
        '{"models_requested":["openai:gpt-5.5-pro"],"models_succeeded":["openai:gpt-5.5-pro"],"models_failed":[],"operator_visible_warn":false,"final_model_id":"openai:gpt-5.5-pro"}'

    run "$CLI" --log-path "$log" --model "claude-opus-4-7" --json --window 24h
    [ "$status" -eq 0 ]
    # Only opus should appear; gpt-5.5-pro filtered out
    echo "$output" | grep -q "claude-opus-4-7"
    ! echo "$output" | grep -q "gpt-5.5-pro"
}

# --- Helpers ---------------------------------------------------------------

skip_unless_redactor() {
    if [[ ! -x "$PROJECT_ROOT/.claude/scripts/lib/log-redactor.sh" ]]; then
        skip "log-redactor.sh not present or not executable"
    fi
}
