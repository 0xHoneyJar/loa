#!/usr/bin/env bats
# =============================================================================
# Cycle-108 sprint-2 T2.F + T2.G + T2.H + T2.K (rollup side) — tests
# =============================================================================
# Validates:
#   T2.F — grouping by skill / role / tier / model / stratum
#   T2.G — hash-chain fail-closed (broken chain → exit 1, no partial output)
#   T2.H — strip-attack detection on post-v1.2-cutoff missing-writer entries
#   T2.K — default mode EXCLUDES replay_marker; --include-replays opts in
# =============================================================================

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    ROLLUP="$REPO_ROOT/tools/modelinv-rollup.sh"
    TMP="$(mktemp -d)"
    cd "$TMP"

    # Synthetic clean log: 4 envelopes (mix of strata + replay marker).
    # Note: no real prev_hash chain — we use --no-chain-verify in most tests.
    cat > clean.jsonl <<'EOF'
{"schema_version":"1.1.0","primitive_id":"MODELINV","event_type":"model.invoke.complete","ts_utc":"2026-05-10T10:00:00Z","prev_hash":"GENESIS","payload":{"models_requested":["anthropic:claude-opus-4-7"],"models_succeeded":["anthropic:claude-opus-4-7"],"models_failed":[],"operator_visible_warn":false,"final_model_id":"anthropic:claude-opus-4-7","cost_micro_usd":1000000,"writer_version":"1.2","role":"review","tier":"advisor","sprint_kind":"glue","calling_primitive":"L1"}}
{"schema_version":"1.1.0","primitive_id":"MODELINV","event_type":"model.invoke.complete","ts_utc":"2026-05-10T11:00:00Z","prev_hash":"AAA","payload":{"models_requested":["openai:gpt-5.5"],"models_succeeded":["openai:gpt-5.5"],"models_failed":[],"operator_visible_warn":false,"final_model_id":"openai:gpt-5.5","cost_micro_usd":500000,"writer_version":"1.2","role":"implementation","tier":"executor","sprint_kind":"parser","calling_primitive":"L1"}}
{"schema_version":"1.1.0","primitive_id":"MODELINV","event_type":"model.invoke.complete","ts_utc":"2026-05-10T12:00:00Z","prev_hash":"BBB","payload":{"models_requested":["anthropic:claude-opus-4-7"],"models_succeeded":["anthropic:claude-opus-4-7"],"models_failed":[],"operator_visible_warn":false,"final_model_id":"anthropic:claude-opus-4-7","cost_micro_usd":750000,"writer_version":"1.2","role":"review","tier":"advisor","sprint_kind":"glue","replay_marker":true}}
{"schema_version":"1.1.0","primitive_id":"MODELINV","event_type":"model.invoke.complete","ts_utc":"2026-05-10T13:00:00Z","prev_hash":"CCC","payload":{"models_requested":["anthropic:claude-opus-4-7"],"models_succeeded":["anthropic:claude-opus-4-7"],"models_failed":[],"operator_visible_warn":false,"final_model_id":"anthropic:claude-opus-4-7","cost_micro_usd":250000,"writer_version":"1.2","role":"planning","tier":"advisor","sprint_kind":"glue"}}
EOF
}

teardown() {
    rm -rf "$TMP"
}

@test "T2.F: --per-model groups by final_model_id (3 distinct)" {
    run bash "$ROLLUP" --no-chain-verify --no-strip-detect --input clean.jsonl --per-model
    [ "$status" -eq 0 ]
    # 3 envelopes (one is replay-marker, excluded) → 2 distinct models
    echo "$output" | grep -q '"total_envelopes": 3'
    echo "$output" | grep -q '"anthropic:claude-opus-4-7"'
    echo "$output" | grep -q '"openai:gpt-5.5"'
}

@test "T2.F: --per-stratum groups by sprint_kind" {
    run bash "$ROLLUP" --no-chain-verify --no-strip-detect --input clean.jsonl --per-stratum
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '"glue"'
    echo "$output" | grep -q '"parser"'
}

@test "T2.F: --per-role groups by role" {
    run bash "$ROLLUP" --no-chain-verify --no-strip-detect --input clean.jsonl --per-role
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '"review"'
    echo "$output" | grep -q '"implementation"'
    echo "$output" | grep -q '"planning"'
}

@test "T2.K: default mode EXCLUDES replay_marker envelopes" {
    run bash "$ROLLUP" --no-chain-verify --no-strip-detect --input clean.jsonl --per-model
    [ "$status" -eq 0 ]
    # 4 input - 1 replay = 3
    echo "$output" | grep -q '"total_envelopes": 3'
    echo "$output" | grep -q '"include_replays": false'
}

@test "T2.K: --include-replays opts in" {
    run bash "$ROLLUP" --no-chain-verify --no-strip-detect --input clean.jsonl --per-model --include-replays
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '"total_envelopes": 4'
    echo "$output" | grep -q '"include_replays": true'
}

@test "T2.F: cost aggregation per group" {
    run bash "$ROLLUP" --no-chain-verify --no-strip-detect --input clean.jsonl --per-model
    [ "$status" -eq 0 ]
    # anthropic ($1.00 + $0.25 = $1.25 = 1250000 micro-USD) — replay excluded
    echo "$output" | jq -e '.groups[] | select(.group_key == "anthropic:claude-opus-4-7") | select(.total_cost_micro_usd == 1250000)'
}

@test "T2.F: composite group (--per-skill --per-tier)" {
    run bash "$ROLLUP" --no-chain-verify --no-strip-detect --input clean.jsonl --per-skill --per-tier
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '"group_fields"'
    echo "$output" | grep -q '"skill"'
    echo "$output" | grep -q '"tier"'
}

@test "T2.H: strip-attack — post-cutoff envelope WITHOUT writer_version → exit 1" {
    # cutoff = first v1.2 envelope's ts_utc; an entry AFTER it without writer_version
    cat > strip.jsonl <<'EOF'
{"schema_version":"1.1.0","primitive_id":"MODELINV","event_type":"model.invoke.complete","ts_utc":"2026-05-10T10:00:00Z","prev_hash":"GENESIS","payload":{"models_requested":["anthropic:claude-opus-4-7"],"models_succeeded":["anthropic:claude-opus-4-7"],"models_failed":[],"operator_visible_warn":false,"writer_version":"1.2","final_model_id":"anthropic:claude-opus-4-7"}}
{"schema_version":"1.1.0","primitive_id":"MODELINV","event_type":"model.invoke.complete","ts_utc":"2026-05-10T11:00:00Z","prev_hash":"AAA","payload":{"models_requested":["anthropic:claude-opus-4-7"],"models_succeeded":["anthropic:claude-opus-4-7"],"models_failed":[],"operator_visible_warn":false,"final_model_id":"anthropic:claude-opus-4-7"}}
EOF
    run bash "$ROLLUP" --no-chain-verify --input strip.jsonl --per-model
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "STRIP-ATTACK-DETECTED"
}

@test "T2.H: --strict-strip exits 78 instead of 1" {
    cat > strip2.jsonl <<'EOF'
{"schema_version":"1.1.0","primitive_id":"MODELINV","event_type":"model.invoke.complete","ts_utc":"2026-05-10T10:00:00Z","prev_hash":"GENESIS","payload":{"models_requested":["anthropic:claude-opus-4-7"],"models_succeeded":["anthropic:claude-opus-4-7"],"models_failed":[],"operator_visible_warn":false,"writer_version":"1.2"}}
{"schema_version":"1.1.0","primitive_id":"MODELINV","event_type":"model.invoke.complete","ts_utc":"2026-05-10T11:00:00Z","prev_hash":"AAA","payload":{"models_requested":["anthropic:claude-opus-4-7"],"models_succeeded":["anthropic:claude-opus-4-7"],"models_failed":[],"operator_visible_warn":false}}
EOF
    run bash "$ROLLUP" --no-chain-verify --strict-strip --input strip2.jsonl --per-model
    [ "$status" -eq 78 ]
}

@test "T2.H: clean v1.2 chain rolls up without strip-attack" {
    run bash "$ROLLUP" --no-chain-verify --input clean.jsonl --per-model
    [ "$status" -eq 0 ]
    # No strip-attack message
    if echo "$output" | grep -q "STRIP-ATTACK-DETECTED"; then
        echo "FAIL: clean log should not trigger strip-attack"
        return 1
    fi
}

@test "T2.H: pre-cutoff v1.1 envelopes are NOT flagged (grandfathered)" {
    # All envelopes are pre-T1.F (no writer_version anywhere) → no cutoff → no detection
    cat > legacy.jsonl <<'EOF'
{"schema_version":"1.1.0","primitive_id":"MODELINV","event_type":"model.invoke.complete","ts_utc":"2025-12-01T10:00:00Z","prev_hash":"GENESIS","payload":{"models_requested":["anthropic:claude-opus-4-7"],"models_succeeded":["anthropic:claude-opus-4-7"],"models_failed":[],"operator_visible_warn":false}}
EOF
    run bash "$ROLLUP" --no-chain-verify --input legacy.jsonl --per-model
    [ "$status" -eq 0 ]
}

@test "T2.F: --output-md emits Markdown table" {
    run bash "$ROLLUP" --no-chain-verify --no-strip-detect --input clean.jsonl --per-model --output-md /tmp/rollup.md
    [ "$status" -eq 0 ]
    grep -q "# MODELINV cost rollup" /tmp/rollup.md
    grep -q "| Group | Count | Total cost" /tmp/rollup.md
    grep -q "anthropic:claude-opus-4-7" /tmp/rollup.md
    rm -f /tmp/rollup.md
}

@test "T2.F: --output-json writes JSON file" {
    run bash "$ROLLUP" --no-chain-verify --no-strip-detect --input clean.jsonl --per-model --output-json /tmp/rollup.json
    [ "$status" -eq 0 ]
    jq -e '.total_envelopes == 3' /tmp/rollup.json
    rm -f /tmp/rollup.json
}

@test "T2.F: missing input file exits 2" {
    run bash "$ROLLUP" --no-chain-verify --no-strip-detect --input nonexistent.jsonl
    [ "$status" -eq 2 ]
}

@test "T2.G: chain-verify ON — synthetic fixture without signatures fails closed" {
    # Default chain-verify is ON. The fixture lacks signatures, which post-
    # cutoff triggers STRIP-ATTACK-DETECTED from audit_verify_chain.
    # Either way: exit 1, NO partial JSON output to stdout.
    run bash "$ROLLUP" --no-strip-detect --input clean.jsonl --per-model
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "CHAIN-VERIFY-FAILED\|STRIP-ATTACK-DETECTED\|BROKEN"
    # No partial JSON aggregation should appear on stdout.
    if echo "$output" | grep -q '"groups":'; then
        echo "FAIL: partial JSON output emitted on chain-verify failure"
        return 1
    fi
}

@test "T2.G: chain-verify recovery hint mentions runbook" {
    run bash "$ROLLUP" --no-strip-detect --input clean.jsonl --per-model
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "advisor-strategy-rollback.md\|audit-keys-bootstrap.md\|Recovery"
}
