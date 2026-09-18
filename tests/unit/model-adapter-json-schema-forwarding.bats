#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# =============================================================================
# tests/unit/model-adapter-json-schema-forwarding.bats
#
# cycle-124 Sprint 2 Task 2.3 (FR-7): model-adapter.sh forwards --json-schema to
# MODEL_INVOKE (cheval) and translate_output carries schema_enforced through to
# the dissent hop — without it the flag would die at the adapter boundary.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    export PROJECT_ROOT
    export LOA_MODELINV_LOG_PATH="$BATS_TEST_TMPDIR/model-invoke.jsonl"
    export LOA_COST_LEDGER_PATH="$BATS_TEST_TMPDIR/cost-ledger.jsonl"
    ADAPTER="$PROJECT_ROOT/.claude/scripts/model-adapter.sh"
    WIRE="$PROJECT_ROOT/.claude/schemas/wire/dissent-review.wire.json"
    SHIM="$BATS_TEST_TMPDIR/model-invoke-shim"
    ARGV="$BATS_TEST_TMPDIR/argv.recorded"
    cat > "$SHIM" <<SHIM
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$ARGV"
cat <<'JSON'
{"content": "{\\"findings\\": []}", "model": "stub", "provider": "stub", "usage": {"input_tokens": 1, "output_tokens": 1}, "latency_ms": 1, "schema_enforced": true}
JSON
SHIM
    chmod +x "$SHIM"
    export MODEL_INVOKE="$SHIM"
    export TEMP_DIR="$BATS_TEST_TMPDIR"
    echo "doc" > "$BATS_TEST_TMPDIR/input.txt"
}

_argv_value() {  # print the value following flag $1 in the recorded argv
    awk -v f="$1" '$0==f{getline; print; exit}' "$ARGV"
}

@test "MA-JS-1: --json-schema <file> is forwarded to MODEL_INVOKE argv verbatim" {
    [ -f "$WIRE" ]
    FLATLINE_MOCK_MODE=true run "$ADAPTER" --model claude-opus-4-7 --mode dissent \
        --input "$BATS_TEST_TMPDIR/input.txt" --json-schema "$WIRE"
    [ -s "$ARGV" ] || { echo "$output" >&2; return 1; }
    [ "$(_argv_value --json-schema)" = "$WIRE" ]
}

@test "MA-JS-2: without --json-schema the flag is absent (unenforced call, byte-identical argv)" {
    FLATLINE_MOCK_MODE=true run "$ADAPTER" --model claude-opus-4-7 --mode dissent \
        --input "$BATS_TEST_TMPDIR/input.txt"
    [ -s "$ARGV" ] || { echo "$output" >&2; return 1; }
    ! grep -qx -- '--json-schema' "$ARGV"
}

@test "MA-JS-3: translate_output carries schema_enforced (true from cheval, false when absent)" {
    eval "$(sed -n '/^translate_output()/,/^}/p' "$ADAPTER")"
    local out
    out=$(echo '{"content":"x","usage":{},"latency_ms":1,"schema_enforced":true}' | translate_output m d p)
    [ "$(jq -r '.schema_enforced' <<<"$out")" = "true" ]
    out=$(echo '{"content":"x","usage":{},"latency_ms":1}' | translate_output m d p)
    [ "$(jq -r '.schema_enforced' <<<"$out")" = "false" ]
}

@test "MA-JS-4: the adapter's translated envelope reports schema_enforced from the shim (end to end)" {
    FLATLINE_MOCK_MODE=true run --separate-stderr "$ADAPTER" --model claude-opus-4-7 --mode dissent \
        --input "$BATS_TEST_TMPDIR/input.txt" --json-schema "$WIRE"
    [ "$status" -eq 0 ] || { echo "$output" >&2; echo "$stderr" >&2; return 1; }
    [ "$(jq -r '.schema_enforced' <<<"$output")" = "true" ] || { echo "stdout: $output" >&2; return 1; }
}
