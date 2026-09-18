#!/usr/bin/env bats
# =============================================================================
# tests/unit/flatline-call-model-schema.bats
#
# cycle-124 Sprint 2 Task 2.5 (FR-7): call_model's 7th positional (wire schema)
# reaches cheval as --json-schema on BOTH argv branches (--model pin and the
# D3 --role routing), the review / skeptic / score sites pass their wire
# schema, and the three run_inquiry dispatches pass none (regression-locked).
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    export PROJECT_ROOT
    export LOA_MODELINV_LOG_PATH="$BATS_TEST_TMPDIR/model-invoke.jsonl"
    export LOA_COST_LEDGER_PATH="$BATS_TEST_TMPDIR/cost-ledger.jsonl"
    ORCHESTRATOR="$PROJECT_ROOT/.claude/scripts/flatline-orchestrator.sh"
    WIRE_DIR="$PROJECT_ROOT/.claude/schemas/wire"
    SHIM="$BATS_TEST_TMPDIR/model-invoke-shim"
    ARGV="$BATS_TEST_TMPDIR/argv.recorded"
    cat > "$SHIM" <<SHIM
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$ARGV"
cat <<'JSON'
{"content": "{\\"improvements\\": []}", "model": "stub", "provider": "stub", "usage": {"input_tokens": 1, "output_tokens": 1}, "latency_ms": 1, "schema_enforced": true}
JSON
SHIM
    chmod +x "$SHIM"
    export MODEL_INVOKE="$SHIM"
    export TEMP_DIR="$BATS_TEST_TMPDIR"
    echo "doc" > "$BATS_TEST_TMPDIR/input.txt"
}

# <mode> <schema-file|""> [routing:0|1]
_call_model() {
    local mode="$1" schema="${2:-}" routing="${3:-1}"
    : > "$ARGV"
    MODE_ARG="$mode" SCHEMA_ARG="$schema" ROUTING_ARG="$routing" INPUT_ARG="$BATS_TEST_TMPDIR/input.txt" \
    ORCHESTRATOR_PATH="$ORCHESTRATOR" bash -c '
        SCRIPT_DIR="$PROJECT_ROOT/.claude/scripts"
        declare -A MODE_TO_AGENT=([review]=flatline-reviewer [skeptic]=flatline-skeptic [score]=flatline-scorer)
        DEFAULT_MODEL_TIMEOUT=30
        PER_CALL_MAX_TOKENS=""
        eval "$(grep -E "^(FLATLINE_(REVIEW|SCORE)_MAX_TOKENS|WIRE_SCHEMA_DIR|WIRE_REVIEWER|WIRE_SKEPTIC|WIRE_SCORER)=" "$ORCHESTRATOR_PATH")"
        log() { :; }; log_invoke_failure() { :; }; cleanup_invoke_log() { :; }
        redact_secrets() { cat; }
        setup_invoke_log() { echo "$TEMP_DIR/invoke-$$.log"; }
        configured_flatline_model() { return 1; }
        resolve_provider_id() { echo "anthropic:$1"; }
        is_stage_routing_scorer_enabled() { return "$ROUTING_ARG"; }
        eval "$(awk "/^call_model\(\)/,/^}/" "$ORCHESTRATOR_PATH")"
        call_model "opus" "$MODE_ARG" "$INPUT_ARG" "prd" "" "30" "$SCHEMA_ARG" >/dev/null 2>&1 || true
    '
    cat "$ARGV" 2>/dev/null
}

_argv_value() { awk -v flag="$1" '$0 == flag {getline; print; exit}' "$ARGV"; }

@test "CM-1: review with the reviewer wire schema → --json-schema <path> on the --model branch" {
    _call_model review "$WIRE_DIR/flatline-reviewer.wire.json" >/dev/null
    [ -s "$ARGV" ]
    [ "$(_argv_value --json-schema)" = "$WIRE_DIR/flatline-reviewer.wire.json" ]
    grep -qx -- '--model' "$ARGV"
}

@test "CM-2: score under D3 --role routing still carries --json-schema (appended after the if/else)" {
    _call_model score "$WIRE_DIR/flatline-scorer.wire.json" 0 >/dev/null
    grep -qx -- '--role' "$ARGV"
    [ "$(_argv_value --json-schema)" = "$WIRE_DIR/flatline-scorer.wire.json" ]
}

@test "CM-3: no 7th arg → no --json-schema (run_inquiry shape); a missing file is not forwarded either" {
    _call_model review "" >/dev/null
    ! grep -qx -- '--json-schema' "$ARGV"
    _call_model review "$BATS_TEST_TMPDIR/nope.wire.json" >/dev/null
    ! grep -qx -- '--json-schema' "$ARGV"
}

@test "CM-4: the review/skeptic/score call sites pass their wire schema (3 + 3 + 6) and run_inquiry passes none (grep-lock)" {
    [ "$(grep -cE 'call_model "\$[a-z_]+_model" review "\$doc" "\$phase" "\$context_file" "\$timeout" "\$WIRE_REVIEWER"' "$ORCHESTRATOR")" = "3" ]
    [ "$(grep -cE 'call_model "\$[a-z_]+_model" skeptic "\$doc" "\$phase" "\$context_file" "\$timeout" "\$WIRE_SKEPTIC"' "$ORCHESTRATOR")" = "3" ]
    [ "$(grep -cE 'call_model "\$[a-z_]+_model" score "\$[a-z_]+" "\$phase" "" "\$timeout" "\$WIRE_SCORER"' "$ORCHESTRATOR")" = "6" ]
    # the three inquiry dispatches: quoted "review" mode, no 7th arg
    [ "$(grep -cE 'call_model "\$(structural|historical|governance)_model" "review" "\$[a-z_]+_input" "\$phase" "\$context_file" "\$timeout" >' "$ORCHESTRATOR")" = "3" ]
    ! grep -qE 'call_model "\$(structural|historical|governance)_model" "review" .*WIRE_' "$ORCHESTRATOR"
}

@test "CM-5: the three wire constants point at files that exist" {
    eval "$(grep -E '^(SCRIPT_DIR|WIRE_SCHEMA_DIR|WIRE_REVIEWER|WIRE_SKEPTIC|WIRE_SCORER)=' "$ORCHESTRATOR" | sed "s|^SCRIPT_DIR=.*|SCRIPT_DIR=$PROJECT_ROOT/.claude/scripts|")"
    [ -f "$WIRE_REVIEWER" ] && [ -f "$WIRE_SKEPTIC" ] && [ -f "$WIRE_SCORER" ]
}
