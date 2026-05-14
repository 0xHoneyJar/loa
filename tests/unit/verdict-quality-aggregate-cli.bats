#!/usr/bin/env bats
# =============================================================================
# tests/unit/verdict-quality-aggregate-cli.bats
#
# cycle-109 Sprint 2 T2.4 — bash twin contract for the verdict_quality
# multi-voice aggregator CLI.
#
# Per SDD §5.2.1 (single canonical Python + bash twin shells out), the
# bash side (flatline-orchestrator.sh) MUST invoke the aggregator via
# `python -m loa_cheval.verdict.aggregate <file1> <file2> ...` rather
# than reimplementing the merge logic in jq. This file pins the CLI
# contract:
#
#   - Positional args = paths to single-voice envelope JSON files.
#   - Stdout = aggregated multi-voice envelope JSON (compact).
#   - Exit 0 on success.
#   - Exit 2 on invariant violation (one of the inputs is malformed
#     OR aggregated envelope fails validate_invariants).
#   - Exit 3 on malformed JSON input (one of the files is not valid JSON).
#   - Exit 64 on usage error (no files provided).
#
# The aggregated output round-trips through the verdict-quality.schema.json
# (verified here against the same registry-based path that the
# modelinv-v1.3 bats suite uses).
#
# Pair with: .claude/adapters/tests/test_verdict_quality_aggregate.py
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    VERDICT_SCHEMA_PATH="$PROJECT_ROOT/.claude/data/schemas/verdict-quality.schema.json"

    [[ -f "$VERDICT_SCHEMA_PATH" ]] || {
        printf 'FATAL: verdict schema not found at %s\n' "$VERDICT_SCHEMA_PATH" >&2
        return 1
    }

    if [[ -x "$PROJECT_ROOT/.venv/bin/python" ]]; then
        PYTHON_BIN="$PROJECT_ROOT/.venv/bin/python"
    else
        PYTHON_BIN="$(command -v python3)"
    fi

    export PYTHONPATH="$PROJECT_ROOT/.claude/adapters"

    BATS_TMP="$(mktemp -d "${BATS_TMPDIR:-/tmp}/vq-aggregate.XXXXXX")"
}

teardown() {
    rm -rf "$BATS_TMP" 2>/dev/null || true
}

# Write a single-voice envelope fixture (APPROVED).
_write_approved() {
    local path="$1"
    local voice_id="${2:-voice-a}"
    cat > "$path" <<JSON
{
    "status": "APPROVED",
    "consensus_outcome": "consensus",
    "truncation_waiver_applied": false,
    "voices_planned": 1,
    "voices_succeeded": 1,
    "voices_succeeded_ids": ["${voice_id}"],
    "voices_dropped": [],
    "chain_health": "ok",
    "confidence_floor": "low",
    "rationale": "single-voice cheval invoke (voice=${voice_id})",
    "single_voice_call": true
}
JSON
}

# Write a single-voice envelope fixture (FAILED).
_write_failed() {
    local path="$1"
    local voice_id="${2:-voice-c}"
    local risk="${3:-med}"
    cat > "$path" <<JSON
{
    "status": "FAILED",
    "consensus_outcome": "consensus",
    "truncation_waiver_applied": false,
    "voices_planned": 1,
    "voices_succeeded": 0,
    "voices_succeeded_ids": [],
    "voices_dropped": [
        {
            "voice": "${voice_id}",
            "reason": "EmptyContent",
            "exit_code": 1,
            "blocker_risk": "${risk}",
            "chain_walk": []
        }
    ],
    "chain_health": "exhausted",
    "confidence_floor": "low",
    "rationale": "single-voice cheval invoke (voice=${voice_id}); failed",
    "single_voice_call": true
}
JSON
}

# Validate JSON-on-stdin against verdict-quality.schema.json.
_validate_envelope_stdin() {
    "$PYTHON_BIN" - <<PY
import json
import sys
try:
    import jsonschema
except ImportError:
    print("SKIP: jsonschema not installed", file=sys.stderr)
    sys.exit(77)

schema = json.load(open("$VERDICT_SCHEMA_PATH"))
envelope = json.load(sys.stdin)
validator_cls = jsonschema.validators.validator_for(schema)
validator = validator_cls(schema)
errors = list(validator.iter_errors(envelope))
if errors:
    print(f"INVALID: {errors[0].message}")
    sys.exit(1)
print("VALID")
PY
}

_require_jsonschema() {
    "$PYTHON_BIN" -c "import jsonschema" 2>/dev/null \
        || skip "jsonschema not installed in this Python env"
}

# =============================================================================
# AG-1: usage error — no positional args
# =============================================================================

@test "AG1: aggregate CLI exits 64 when no input files supplied" {
    run "$PYTHON_BIN" -m loa_cheval.verdict.aggregate
    [ "$status" -eq 64 ]
}

# =============================================================================
# AG-2: 3-voice APPROVED canonical path
# =============================================================================

@test "AG2: 3-voice APPROVED inputs aggregate to APPROVED multi-voice envelope" {
    _require_jsonschema
    local f1="$BATS_TMP/v1.json"
    local f2="$BATS_TMP/v2.json"
    local f3="$BATS_TMP/v3.json"
    _write_approved "$f1" "gpt-5.5-pro"
    _write_approved "$f2" "claude-opus-4-7"
    _write_approved "$f3" "gemini-3.1-pro"

    run "$PYTHON_BIN" -m loa_cheval.verdict.aggregate "$f1" "$f2" "$f3"
    [ "$status" -eq 0 ]

    local status_value voices_planned voices_succeeded
    status_value=$(echo "$output" | jq -r '.status')
    voices_planned=$(echo "$output" | jq -r '.voices_planned')
    voices_succeeded=$(echo "$output" | jq -r '.voices_succeeded')
    [ "$status_value" = "APPROVED" ]
    [ "$voices_planned" -eq 3 ]
    [ "$voices_succeeded" -eq 3 ]

    # Round-trip the aggregate through the schema validator.
    run bash -c "echo '$output' | _validate_envelope_stdin"
    # Note: heredoc subshell call — re-run with proper invocation
    echo "$output" | _validate_envelope_stdin
}

# =============================================================================
# AG-3: 2/3 voice drop → DEGRADED
# =============================================================================

@test "AG3: 2 succeeded + 1 failed (med) aggregates to DEGRADED" {
    _require_jsonschema
    local f1="$BATS_TMP/v1.json"
    local f2="$BATS_TMP/v2.json"
    local f3="$BATS_TMP/v3.json"
    _write_approved "$f1" "gpt-5.5-pro"
    _write_approved "$f2" "claude-opus-4-7"
    _write_failed "$f3" "gemini-3.1-pro" "med"

    run "$PYTHON_BIN" -m loa_cheval.verdict.aggregate "$f1" "$f2" "$f3"
    [ "$status" -eq 0 ]

    local status_value chain_health voices_dropped_count
    status_value=$(echo "$output" | jq -r '.status')
    chain_health=$(echo "$output" | jq -r '.chain_health')
    voices_dropped_count=$(echo "$output" | jq -r '.voices_dropped | length')
    [ "$status_value" = "DEGRADED" ]
    [ "$chain_health" = "exhausted" ]
    [ "$voices_dropped_count" -eq 1 ]
}

# =============================================================================
# AG-4: any high blocker_risk promotes to FAILED
# =============================================================================

@test "AG4: 2 succeeded + 1 failed (high) aggregates to FAILED" {
    _require_jsonschema
    local f1="$BATS_TMP/v1.json"
    local f2="$BATS_TMP/v2.json"
    local f3="$BATS_TMP/v3.json"
    _write_approved "$f1" "gpt-5.5-pro"
    _write_approved "$f2" "claude-opus-4-7"
    _write_failed "$f3" "gemini-3.1-pro" "high"

    run "$PYTHON_BIN" -m loa_cheval.verdict.aggregate "$f1" "$f2" "$f3"
    [ "$status" -eq 0 ]

    local status_value
    status_value=$(echo "$output" | jq -r '.status')
    [ "$status_value" = "FAILED" ]
}

# =============================================================================
# AG-5: stdout is compact JSON (no whitespace) — bash twin parsing contract
# =============================================================================

@test "AG5: aggregate CLI stdout is compact single-line JSON" {
    _require_jsonschema
    local f1="$BATS_TMP/v1.json"
    local f2="$BATS_TMP/v2.json"
    _write_approved "$f1" "a"
    _write_approved "$f2" "b"

    run "$PYTHON_BIN" -m loa_cheval.verdict.aggregate "$f1" "$f2"
    [ "$status" -eq 0 ]

    # Compact JSON has no ": " or ", " separators.
    [[ "$output" != *": "* ]]
    [[ "$output" != *", "* ]]
    # Single line: no embedded newlines
    [[ "$output" != *$'\n'* ]]
}

# =============================================================================
# AG-6: malformed JSON input → exit 3
# =============================================================================

@test "AG6: aggregate CLI exits 3 on malformed JSON input file" {
    local f1="$BATS_TMP/bad.json"
    printf 'not json {' > "$f1"

    run "$PYTHON_BIN" -m loa_cheval.verdict.aggregate "$f1"
    [ "$status" -eq 3 ]
}

# =============================================================================
# AG-7: missing file → exit 3 (treated as malformed-input class)
# =============================================================================

@test "AG7: aggregate CLI exits 3 when input file does not exist" {
    run "$PYTHON_BIN" -m loa_cheval.verdict.aggregate \
        "$BATS_TMP/nonexistent.json"
    [ "$status" -eq 3 ]
}

# =============================================================================
# AG-8: aggregated envelope passes the verdict-quality.schema.json
# =============================================================================

@test "AG8: 3-voice aggregate output validates against verdict-quality schema" {
    _require_jsonschema
    local f1="$BATS_TMP/v1.json"
    local f2="$BATS_TMP/v2.json"
    local f3="$BATS_TMP/v3.json"
    _write_approved "$f1" "a"
    _write_approved "$f2" "b"
    _write_failed "$f3" "c" "low"

    local agg
    agg=$("$PYTHON_BIN" -m loa_cheval.verdict.aggregate "$f1" "$f2" "$f3")
    [ -n "$agg" ]

    run bash -c "echo '$agg' | $0:_validate_envelope_stdin" || true
    # Inline validation (avoid bash function-export complexity):
    local result
    result=$(echo "$agg" | "$PYTHON_BIN" - <<PY
import json, sys
import jsonschema
schema = json.load(open("$VERDICT_SCHEMA_PATH"))
envelope = json.load(sys.stdin)
errors = list(jsonschema.validators.validator_for(schema)(schema).iter_errors(envelope))
print("INVALID:" + errors[0].message if errors else "VALID")
sys.exit(1 if errors else 0)
PY
)
    [[ "$result" == "VALID" ]]
}
