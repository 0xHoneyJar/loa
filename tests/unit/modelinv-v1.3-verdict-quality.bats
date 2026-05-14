#!/usr/bin/env bats
# =============================================================================
# tests/unit/modelinv-v1.3-verdict-quality.bats
#
# cycle-109 Sprint 2 T2.3 — MODELINV v1.3 envelope `verdict_quality` field
# (PRODUCER #1 per SDD §3.2.3 IMP-004 dependency-ordered consumer refactor).
#
# Per SDD §3.3.1 the v1.3 payload adds a single optional `verdict_quality`
# field carrying the validated, status-stamped envelope built by
# `loa_cheval.verdict.quality.emit_envelope_with_status`. Schema additivity:
#
#   - Payloads WITHOUT `verdict_quality` continue to validate (legacy +
#     pre-T2.3 callers).
#   - Payloads WITH `verdict_quality` carrying a well-formed envelope validate.
#   - Payloads WITH `verdict_quality` carrying a MALFORMED envelope (missing
#     required field, wrong status enum, etc.) REJECT — the redaction-gate
#     downstream relies on schema validity.
#
# Pairs with .claude/adapters/tests/test_modelinv_verdict_quality.py (the
# Python emitter contract) and test_blocker_risk_classifier.py (the input
# side that populates voices_dropped[].blocker_risk).
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    SCHEMA_PATH="$PROJECT_ROOT/.claude/data/trajectory-schemas/model-events/model-invoke-complete.payload.schema.json"
    VERDICT_SCHEMA_PATH="$PROJECT_ROOT/.claude/data/schemas/verdict-quality.schema.json"

    [[ -f "$SCHEMA_PATH" ]] || {
        printf 'FATAL: schema not found at %s\n' "$SCHEMA_PATH" >&2
        return 1
    }
    [[ -f "$VERDICT_SCHEMA_PATH" ]] || {
        printf 'FATAL: verdict schema not found at %s\n' "$VERDICT_SCHEMA_PATH" >&2
        return 1
    }

    if [[ -x "$PROJECT_ROOT/.venv/bin/python" ]]; then
        PYTHON_BIN="$PROJECT_ROOT/.venv/bin/python"
    else
        PYTHON_BIN="$(command -v python3)"
    fi

    BATS_TMP="$(mktemp -d "${BATS_TMPDIR:-/tmp}/modelinv-vq.XXXXXX")"
}

teardown() {
    rm -rf "$BATS_TMP" 2>/dev/null || true
}

_require_schema_deps() {
    "$PYTHON_BIN" -c "import jsonschema; from referencing import Registry, Resource" 2>/dev/null \
        || skip "jsonschema+referencing not installed in this Python env"
}

# Validate a MODELINV payload against the v1.3 schema. The verdict_quality
# field, when present, is validated as an embedded object (the inner
# validation against verdict-quality.schema.json is the verdict-quality
# schema test's responsibility — this file pins the outer additivity).
_validate_modelinv_payload() {
    local payload_file="$1"
    "$PYTHON_BIN" - <<PY
import json
import sys
from pathlib import Path
try:
    import jsonschema
    from referencing import Registry, Resource
except ImportError:
    print("SKIP: jsonschema/referencing not installed", file=sys.stderr)
    sys.exit(77)

ROOT = Path("$PROJECT_ROOT")
schema = json.load(open("$SCHEMA_PATH"))
payload = json.load(open("$payload_file"))

model_error_path = ROOT / ".claude" / "data" / "trajectory-schemas" / "model-error.schema.json"
registry = Registry()
if model_error_path.is_file():
    with model_error_path.open() as fh:
        me = json.load(fh)
    resource = Resource.from_contents(me)
    registry = registry.with_resource(uri="loa://schemas/model-error/v1.0.0", resource=resource)

validator_cls = jsonschema.validators.validator_for(schema)
validator = validator_cls(schema, registry=registry)
errors = list(validator.iter_errors(payload))
if errors:
    print(f"INVALID: {errors[0].message}")
    sys.exit(1)
print("VALID")
PY
}

# Validate JUST the verdict-quality envelope against verdict-quality.schema.json.
# Independent assertion path so we can pin "the envelope alone is valid" and
# "the envelope inside MODELINV is valid" separately.
_validate_verdict_envelope() {
    local envelope_file="$1"
    "$PYTHON_BIN" - <<PY
import json
import sys
try:
    import jsonschema
except ImportError:
    print("SKIP: jsonschema not installed", file=sys.stderr)
    sys.exit(77)

schema = json.load(open("$VERDICT_SCHEMA_PATH"))
envelope = json.load(open("$envelope_file"))
validator_cls = jsonschema.validators.validator_for(schema)
validator = validator_cls(schema)
errors = list(validator.iter_errors(envelope))
if errors:
    print(f"INVALID: {errors[0].message}")
    sys.exit(1)
print("VALID")
PY
}

# =============================================================================
# VQ-1: backward compat — payload without verdict_quality still validates
# =============================================================================

@test "VQ1: v1.3 payload WITHOUT verdict_quality validates (backward compat)" {
    _require_schema_deps
    local payload="$BATS_TMP/no-vq.json"
    cat > "$payload" <<'JSON'
{
    "models_requested": ["anthropic:claude-opus-4-7"],
    "models_succeeded": ["anthropic:claude-opus-4-7"],
    "models_failed": [],
    "operator_visible_warn": false
}
JSON
    run _validate_modelinv_payload "$payload"
    [ "$status" -eq 0 ]
    [[ "$output" == *"VALID"* ]]
}

# =============================================================================
# VQ-2: APPROVED envelope embedded in MODELINV payload validates
# =============================================================================

@test "VQ2: v1.3 payload WITH APPROVED verdict_quality validates" {
    _require_schema_deps
    local payload="$BATS_TMP/approved.json"
    cat > "$payload" <<'JSON'
{
    "models_requested": ["anthropic:claude-opus-4-7"],
    "models_succeeded": ["anthropic:claude-opus-4-7"],
    "models_failed": [],
    "operator_visible_warn": false,
    "final_model_id": "anthropic:claude-opus-4-7",
    "transport": "http",
    "verdict_quality": {
        "status": "APPROVED",
        "consensus_outcome": "consensus",
        "truncation_waiver_applied": false,
        "voices_planned": 1,
        "voices_succeeded": 1,
        "voices_succeeded_ids": ["claude-opus-4-7"],
        "voices_dropped": [],
        "chain_health": "ok",
        "confidence_floor": "low",
        "rationale": "single-voice cheval invoke; chain_health=ok",
        "single_voice_call": true
    }
}
JSON
    run _validate_modelinv_payload "$payload"
    [ "$status" -eq 0 ]
    [[ "$output" == *"VALID"* ]]
}

# =============================================================================
# VQ-3: DEGRADED envelope (chain walked to fallback) validates
# =============================================================================

@test "VQ3: v1.3 payload WITH DEGRADED verdict_quality (chain walked) validates" {
    _require_schema_deps
    local payload="$BATS_TMP/degraded.json"
    cat > "$payload" <<'JSON'
{
    "models_requested": ["anthropic:claude-opus-4-7", "anthropic:claude-opus-4-6"],
    "models_succeeded": ["anthropic:claude-opus-4-6"],
    "models_failed": [
        {
            "model": "anthropic:claude-opus-4-7",
            "provider": "anthropic",
            "error_class": "EMPTY_CONTENT",
            "message_redacted": "empty content"
        }
    ],
    "operator_visible_warn": true,
    "final_model_id": "anthropic:claude-opus-4-6",
    "transport": "http",
    "verdict_quality": {
        "status": "APPROVED",
        "consensus_outcome": "consensus",
        "truncation_waiver_applied": false,
        "voices_planned": 1,
        "voices_succeeded": 1,
        "voices_succeeded_ids": ["claude-opus-4-6"],
        "voices_dropped": [],
        "chain_health": "degraded",
        "confidence_floor": "low",
        "rationale": "single-voice cheval invoke; chain walked to fallback (claude-opus-4-6)",
        "single_voice_call": true
    }
}
JSON
    run _validate_modelinv_payload "$payload"
    [ "$status" -eq 0 ]
    [[ "$output" == *"VALID"* ]]
}

# =============================================================================
# VQ-4: FAILED envelope (chain exhausted) validates
# =============================================================================

@test "VQ4: v1.3 payload WITH FAILED verdict_quality (chain exhausted) validates" {
    _require_schema_deps
    local payload="$BATS_TMP/failed.json"
    cat > "$payload" <<'JSON'
{
    "models_requested": ["anthropic:claude-opus-4-7"],
    "models_succeeded": [],
    "models_failed": [
        {
            "model": "anthropic:claude-opus-4-7",
            "provider": "anthropic",
            "error_class": "RETRIES_EXHAUSTED",
            "message_redacted": "all retries failed"
        }
    ],
    "operator_visible_warn": true,
    "verdict_quality": {
        "status": "FAILED",
        "consensus_outcome": "consensus",
        "truncation_waiver_applied": false,
        "voices_planned": 1,
        "voices_succeeded": 0,
        "voices_succeeded_ids": [],
        "voices_dropped": [
            {
                "voice": "claude-opus-4-7",
                "reason": "RetriesExhausted",
                "exit_code": 7,
                "blocker_risk": "high",
                "chain_walk": ["anthropic:claude-opus-4-7"]
            }
        ],
        "chain_health": "exhausted",
        "confidence_floor": "low",
        "rationale": "single-voice cheval invoke; chain exhausted",
        "single_voice_call": true
    }
}
JSON
    run _validate_modelinv_payload "$payload"
    [ "$status" -eq 0 ]
    [[ "$output" == *"VALID"* ]]
}

# =============================================================================
# VQ-5: envelope-alone validation — APPROVED shape passes verdict schema
# =============================================================================

@test "VQ5: APPROVED envelope alone validates against verdict-quality schema" {
    _require_schema_deps
    local envelope="$BATS_TMP/approved-envelope.json"
    cat > "$envelope" <<'JSON'
{
    "status": "APPROVED",
    "consensus_outcome": "consensus",
    "truncation_waiver_applied": false,
    "voices_planned": 1,
    "voices_succeeded": 1,
    "voices_succeeded_ids": ["claude-opus-4-7"],
    "voices_dropped": [],
    "chain_health": "ok",
    "confidence_floor": "low",
    "rationale": "single-voice cheval invoke; chain_health=ok",
    "single_voice_call": true
}
JSON
    run _validate_verdict_envelope "$envelope"
    [ "$status" -eq 0 ]
    [[ "$output" == *"VALID"* ]]
}

# =============================================================================
# VQ-6: envelope-alone — FAILED shape with chain_walk passes
# =============================================================================

@test "VQ6: FAILED envelope with chain_walk validates against verdict-quality schema" {
    _require_schema_deps
    local envelope="$BATS_TMP/failed-envelope.json"
    cat > "$envelope" <<'JSON'
{
    "status": "FAILED",
    "consensus_outcome": "consensus",
    "truncation_waiver_applied": false,
    "voices_planned": 1,
    "voices_succeeded": 0,
    "voices_succeeded_ids": [],
    "voices_dropped": [
        {
            "voice": "claude-opus-4-7",
            "reason": "ChainExhausted",
            "exit_code": 11,
            "blocker_risk": "high",
            "chain_walk": [
                "anthropic:claude-opus-4-7",
                "anthropic:claude-opus-4-6",
                "anthropic:claude-headless"
            ]
        }
    ],
    "chain_health": "exhausted",
    "confidence_floor": "low",
    "rationale": "all 3 chain entries failed",
    "single_voice_call": true
}
JSON
    run _validate_verdict_envelope "$envelope"
    [ "$status" -eq 0 ]
    [[ "$output" == *"VALID"* ]]
}

# =============================================================================
# VQ-7: rejection — verdict_quality missing required `status` rejects MODELINV
# =============================================================================

@test "VQ7: MODELINV payload WITH verdict_quality missing 'status' is rejected" {
    _require_schema_deps
    local payload="$BATS_TMP/missing-status.json"
    cat > "$payload" <<'JSON'
{
    "models_requested": ["anthropic:claude-opus-4-7"],
    "models_succeeded": ["anthropic:claude-opus-4-7"],
    "models_failed": [],
    "operator_visible_warn": false,
    "verdict_quality": {
        "consensus_outcome": "consensus",
        "truncation_waiver_applied": false,
        "voices_planned": 1,
        "voices_succeeded": 1,
        "voices_succeeded_ids": ["claude-opus-4-7"],
        "voices_dropped": [],
        "chain_health": "ok",
        "confidence_floor": "low",
        "rationale": "test"
    }
}
JSON
    run _validate_modelinv_payload "$payload"
    [ "$status" -ne 0 ]
    [[ "$output" == *"INVALID"* ]]
}

# =============================================================================
# VQ-8: rejection — verdict_quality status outside enum rejects
# =============================================================================

@test "VQ8: MODELINV payload WITH verdict_quality status='clean' is rejected" {
    _require_schema_deps
    local payload="$BATS_TMP/bad-status.json"
    cat > "$payload" <<'JSON'
{
    "models_requested": ["anthropic:claude-opus-4-7"],
    "models_succeeded": ["anthropic:claude-opus-4-7"],
    "models_failed": [],
    "operator_visible_warn": false,
    "verdict_quality": {
        "status": "clean",
        "consensus_outcome": "consensus",
        "truncation_waiver_applied": false,
        "voices_planned": 1,
        "voices_succeeded": 1,
        "voices_succeeded_ids": ["claude-opus-4-7"],
        "voices_dropped": [],
        "chain_health": "ok",
        "confidence_floor": "low",
        "rationale": "this status is not in the enum and must reject"
    }
}
JSON
    run _validate_modelinv_payload "$payload"
    [ "$status" -ne 0 ]
    [[ "$output" == *"INVALID"* ]]
}
