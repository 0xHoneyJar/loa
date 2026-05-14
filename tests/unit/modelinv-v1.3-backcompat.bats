#!/usr/bin/env bats
# =============================================================================
# tests/unit/modelinv-v1.3-backcompat.bats
#
# cycle-109 Sprint 1 T1.4 — MODELINV envelope v1.3 additive over v1.2.
#
# v1.3 adds a single optional field `capability_evaluation` to the
# model.invoke.complete payload, carrying the capability-aware substrate
# pre-flight gate decision (cycle-109 SDD §3.3.1). The field is additive:
#
#   - v1.2 envelopes WITHOUT the field continue to validate against the
#     v1.3 schema (backwards-compat — required for replay against the
#     last-30d log).
#   - v1.3 envelopes WITH the field validate when shape matches:
#       {
#         effective_input_ceiling: int|null,
#         reasoning_class: bool,
#         recommended_for: [role-tag],
#         ceiling_stale: bool,
#         estimated_input_tokens: int,
#         preflight_decision: "dispatch" | "preempt" | "chunk"
#       }
#   - writer_version SoT file reads "1.3" for cycle-109+ emitters; the
#     bump is the audit-trail signal that the writer can emit the
#     capability_evaluation field even if a particular call elides it.
#
# Sprint AC: existing .run/model-invoke.jsonl entries (v1.2 shape) continue
# parsing; hash-chain signatures verify; replay against last-30d log
# passes. NFR-Rel-4 (schema additive only — no breaking changes to v1.2
# field positions / required-set).
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    SCHEMA_PATH="$PROJECT_ROOT/.claude/data/trajectory-schemas/model-events/model-invoke-complete.payload.schema.json"
    WRITER_VERSION_PATH="$PROJECT_ROOT/.claude/data/cycle-108/modelinv-writer-version"
    MODEL_INVOKE_LOG="$PROJECT_ROOT/.run/model-invoke.jsonl"

    [[ -f "$SCHEMA_PATH" ]] || {
        printf 'FATAL: schema not found at %s\n' "$SCHEMA_PATH" >&2
        return 1
    }

    if [[ -x "$PROJECT_ROOT/.venv/bin/python" ]]; then
        PYTHON_BIN="$PROJECT_ROOT/.venv/bin/python"
    else
        PYTHON_BIN="$(command -v python3)"
    fi

    BATS_TMP="$(mktemp -d "${BATS_TMPDIR:-/tmp}/modelinv-v13.XXXXXX")"
}

teardown() {
    rm -rf "$BATS_TMP" 2>/dev/null || true
}

# Validate a JSON payload against the v1.3 schema. Echoes "VALID" or the
# jsonschema error to stdout; returns the python exit code so bats `run`
# can assert pass/fail.
_validate_payload() {
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

# Register the model-error.schema.json under its loa:// $id so the
# \$ref inside model-invoke-complete.payload.schema.json resolves.
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

# =============================================================================
# V-1: writer_version SoT advances to "1.3"
# =============================================================================

@test "V1: writer_version SoT file reads 1.3 for cycle-109+ emitters" {
    [[ -f "$WRITER_VERSION_PATH" ]]
    local version
    version="$(tr -d '[:space:]' < "$WRITER_VERSION_PATH")"
    [[ "$version" == "1.3" ]]
}

# =============================================================================
# V-2: backward-compat — minimal v1.2 envelope (no capability_evaluation)
# =============================================================================

@test "V2: v1.2 minimal envelope (no capability_evaluation) validates under v1.3 schema" {
    local payload="$BATS_TMP/v12-minimal.json"
    cat > "$payload" <<'JSON'
{
    "models_requested": ["anthropic:claude-opus-4-7"],
    "models_succeeded": ["anthropic:claude-opus-4-7"],
    "models_failed": [],
    "operator_visible_warn": false
}
JSON
    run _validate_payload "$payload"
    [ "$status" -eq 0 ]
    [[ "$output" == *"VALID"* ]]
}

# =============================================================================
# V-3: backward-compat — full v1.2 envelope validates
# =============================================================================

@test "V3: v1.2 full envelope (all v1.2 fields) validates under v1.3 schema" {
    local payload="$BATS_TMP/v12-full.json"
    cat > "$payload" <<'JSON'
{
    "models_requested": ["openai:gpt-5.5-pro"],
    "models_succeeded": ["openai:gpt-5.5-pro"],
    "models_failed": [],
    "operator_visible_warn": false,
    "calling_primitive": "L3",
    "capability_class": "top-reasoning",
    "invocation_latency_ms": 3200,
    "cost_micro_usd": 1500,
    "kill_switch_active": false,
    "streaming": true,
    "final_model_id": "openai:gpt-5.5-pro",
    "transport": "http",
    "config_observed": {
        "headless_mode": "prefer-api",
        "headless_mode_source": "default"
    },
    "role": "review",
    "tier": "advisor",
    "tier_source": "default",
    "tier_resolution": "dynamic",
    "sprint_kind": "glue",
    "writer_version": "1.2",
    "invocation_chain": ["reviewing-code", "cheval"]
}
JSON
    run _validate_payload "$payload"
    [ "$status" -eq 0 ]
    [[ "$output" == *"VALID"* ]]
}

# =============================================================================
# V-4: v1.3 envelope WITH capability_evaluation (preempt path)
# =============================================================================

@test "V4: v1.3 envelope with capability_evaluation (preflight_decision=preempt) validates" {
    local payload="$BATS_TMP/v13-preempt.json"
    cat > "$payload" <<'JSON'
{
    "models_requested": ["anthropic:claude-opus-4-7"],
    "models_succeeded": [],
    "models_failed": [
        {
            "model": "anthropic:claude-opus-4-7",
            "provider": "anthropic",
            "error_class": "ROUTING_MISS",
            "message_redacted": "estimated 50000 input tokens > 40000 effective_input_ceiling"
        }
    ],
    "operator_visible_warn": true,
    "writer_version": "1.3",
    "capability_evaluation": {
        "effective_input_ceiling": 40000,
        "reasoning_class": true,
        "recommended_for": ["review", "audit"],
        "ceiling_stale": false,
        "estimated_input_tokens": 50000,
        "preflight_decision": "preempt"
    }
}
JSON
    run _validate_payload "$payload"
    [ "$status" -eq 0 ]
    [[ "$output" == *"VALID"* ]]
}

# =============================================================================
# V-5: v1.3 envelope with capability_evaluation (dispatch path)
# =============================================================================

@test "V5: v1.3 envelope with capability_evaluation (preflight_decision=dispatch) validates" {
    local payload="$BATS_TMP/v13-dispatch.json"
    cat > "$payload" <<'JSON'
{
    "models_requested": ["openai:gpt-4o-mini"],
    "models_succeeded": ["openai:gpt-4o-mini"],
    "models_failed": [],
    "operator_visible_warn": false,
    "writer_version": "1.3",
    "capability_evaluation": {
        "effective_input_ceiling": 30000,
        "reasoning_class": false,
        "recommended_for": ["review", "audit", "implementation", "dissent", "arbiter"],
        "ceiling_stale": false,
        "estimated_input_tokens": 1200,
        "preflight_decision": "dispatch"
    }
}
JSON
    run _validate_payload "$payload"
    [ "$status" -eq 0 ]
    [[ "$output" == *"VALID"* ]]
}

# =============================================================================
# V-6: v1.3 envelope with capability_evaluation (chunk path — Sprint 4)
# =============================================================================

@test "V6: v1.3 envelope with capability_evaluation (preflight_decision=chunk) validates" {
    local payload="$BATS_TMP/v13-chunk.json"
    cat > "$payload" <<'JSON'
{
    "models_requested": ["anthropic:claude-opus-4-7"],
    "models_succeeded": ["anthropic:claude-opus-4-7"],
    "models_failed": [],
    "operator_visible_warn": false,
    "writer_version": "1.3",
    "capability_evaluation": {
        "effective_input_ceiling": 40000,
        "reasoning_class": true,
        "recommended_for": ["review", "audit"],
        "ceiling_stale": true,
        "estimated_input_tokens": 80000,
        "preflight_decision": "chunk"
    }
}
JSON
    run _validate_payload "$payload"
    [ "$status" -eq 0 ]
    [[ "$output" == *"VALID"* ]]
}

# =============================================================================
# V-7: capability_evaluation with null effective_input_ceiling (v2-only entry)
# =============================================================================

@test "V7: capability_evaluation with null effective_input_ceiling validates (v2-config compat)" {
    # When a v3 emitter walks against a model still on v2 config, the gate
    # disables itself but the audit envelope STILL records the evaluation
    # ran — distinguishes 'gate-disabled-because-no-v3-data' from
    # 'gate-not-evaluated-at-all'. Schema must allow null ceiling.
    local payload="$BATS_TMP/v13-null-ceiling.json"
    cat > "$payload" <<'JSON'
{
    "models_requested": ["openai:gpt-5.5-pro"],
    "models_succeeded": ["openai:gpt-5.5-pro"],
    "models_failed": [],
    "operator_visible_warn": false,
    "writer_version": "1.3",
    "capability_evaluation": {
        "effective_input_ceiling": null,
        "reasoning_class": false,
        "recommended_for": ["review", "audit", "implementation", "dissent", "arbiter"],
        "ceiling_stale": false,
        "estimated_input_tokens": 8000,
        "preflight_decision": "dispatch"
    }
}
JSON
    run _validate_payload "$payload"
    [ "$status" -eq 0 ]
    [[ "$output" == *"VALID"* ]]
}

# =============================================================================
# V-8: schema REJECTS unknown preflight_decision values
# =============================================================================

@test "V8: schema rejects unknown preflight_decision enum values" {
    local payload="$BATS_TMP/v13-bad-decision.json"
    cat > "$payload" <<'JSON'
{
    "models_requested": ["anthropic:claude-opus-4-7"],
    "models_succeeded": ["anthropic:claude-opus-4-7"],
    "models_failed": [],
    "operator_visible_warn": false,
    "capability_evaluation": {
        "effective_input_ceiling": 40000,
        "reasoning_class": true,
        "recommended_for": ["review"],
        "ceiling_stale": false,
        "estimated_input_tokens": 5000,
        "preflight_decision": "force_dispatch"
    }
}
JSON
    run _validate_payload "$payload"
    [ "$status" -ne 0 ]
    [[ "$output" == *"INVALID"* ]]
}

# =============================================================================
# V-9: schema REJECTS missing required keys inside capability_evaluation
# =============================================================================

@test "V9: schema rejects capability_evaluation with missing required keys" {
    local payload="$BATS_TMP/v13-missing-keys.json"
    cat > "$payload" <<'JSON'
{
    "models_requested": ["anthropic:claude-opus-4-7"],
    "models_succeeded": ["anthropic:claude-opus-4-7"],
    "models_failed": [],
    "operator_visible_warn": false,
    "capability_evaluation": {
        "effective_input_ceiling": 40000,
        "reasoning_class": true,
        "preflight_decision": "dispatch"
    }
}
JSON
    run _validate_payload "$payload"
    [ "$status" -ne 0 ]
    [[ "$output" == *"INVALID"* ]]
}

# =============================================================================
# V-10: schema REJECTS additionalProperties inside capability_evaluation
# =============================================================================

@test "V10: schema rejects capability_evaluation with unknown nested keys" {
    local payload="$BATS_TMP/v13-extra-key.json"
    cat > "$payload" <<'JSON'
{
    "models_requested": ["anthropic:claude-opus-4-7"],
    "models_succeeded": ["anthropic:claude-opus-4-7"],
    "models_failed": [],
    "operator_visible_warn": false,
    "capability_evaluation": {
        "effective_input_ceiling": 40000,
        "reasoning_class": true,
        "recommended_for": ["review"],
        "ceiling_stale": false,
        "estimated_input_tokens": 5000,
        "preflight_decision": "dispatch",
        "unknown_field": "leak"
    }
}
JSON
    run _validate_payload "$payload"
    [ "$status" -ne 0 ]
    [[ "$output" == *"INVALID"* ]]
}

# =============================================================================
# V-11: replay last-30d log — every entry parses + payload validates
# =============================================================================

@test "V11: replay against last-30d .run/model-invoke.jsonl parses + validates payloads" {
    # NFR-Rel-4 + sprint AC: "existing .run/model-invoke.jsonl entries
    # continue parsing; hash-chain signatures verify; replay against
    # last-30d log". This assertion covers the parse + payload-schema
    # half of the replay. Signature verification is an audit-envelope
    # responsibility tested by audit-envelope-recovery tests separately.
    [[ -f "$MODEL_INVOKE_LOG" ]] || skip "no .run/model-invoke.jsonl log present"

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
model_error_path = ROOT / ".claude" / "data" / "trajectory-schemas" / "model-error.schema.json"
registry = Registry()
if model_error_path.is_file():
    with model_error_path.open() as fh:
        me = json.load(fh)
    registry = registry.with_resource(
        uri="loa://schemas/model-error/v1.0.0",
        resource=Resource.from_contents(me),
    )
validator_cls = jsonschema.validators.validator_for(schema)
validator = validator_cls(schema, registry=registry)

log_path = Path("$MODEL_INVOKE_LOG")
errors = []
count = 0
with log_path.open() as f:
    for lineno, raw in enumerate(f, start=1):
        raw = raw.strip()
        if not raw:
            continue
        try:
            entry = json.loads(raw)
        except json.JSONDecodeError as e:
            errors.append(f"line {lineno}: parse error: {e}")
            continue
        payload = entry.get("payload")
        if payload is None:
            errors.append(f"line {lineno}: missing payload key")
            continue
        schema_errs = list(validator.iter_errors(payload))
        if schema_errs:
            errors.append(f"line {lineno}: schema validation: {schema_errs[0].message}")
        else:
            count += 1
if errors:
    print("REPLAY_FAILURES:")
    for err in errors[:10]:
        print(err)
    if len(errors) > 10:
        print(f"... and {len(errors) - 10} more")
    sys.exit(1)
print(f"OK: {count} entries validated against v1.3 schema")
PY
}

# =============================================================================
# V-12: emit_model_invoke_complete accepts capability_evaluation kwarg
# =============================================================================

@test "V12: emit_model_invoke_complete carries capability_evaluation into payload" {
    run "$PYTHON_BIN" - <<PY
import json
import os
import sys
import types
from pathlib import Path

ROOT = Path("$PROJECT_ROOT")
sys.path.insert(0, str(ROOT / ".claude" / "adapters"))

# Intercept audit_emit so we can inspect the payload pre-write.
captured = {}
def _fake_audit_emit(primitive_id, event_type, payload, log_path):
    captured["payload"] = payload
fake = types.ModuleType("loa_cheval.audit_envelope")
fake.audit_emit = _fake_audit_emit
sys.modules["loa_cheval.audit_envelope"] = fake

os.environ.pop("LOA_MODELINV_AUDIT_DISABLE", None)
from loa_cheval.audit.modelinv import (
    emit_model_invoke_complete,
    _reset_writer_version_cache_for_tests,
)
_reset_writer_version_cache_for_tests()

emit_model_invoke_complete(
    models_requested=["anthropic:claude-opus-4-7"],
    models_succeeded=["anthropic:claude-opus-4-7"],
    models_failed=[],
    operator_visible_warn=False,
    capability_evaluation={
        "effective_input_ceiling": 40000,
        "reasoning_class": True,
        "recommended_for": ["review", "audit"],
        "ceiling_stale": False,
        "estimated_input_tokens": 5000,
        "preflight_decision": "dispatch",
    },
)
payload = captured.get("payload")
assert payload is not None, "emit_model_invoke_complete did not call audit_emit"
ce = payload.get("capability_evaluation")
assert ce is not None, f"capability_evaluation missing from payload: keys={list(payload.keys())}"
assert ce["effective_input_ceiling"] == 40000
assert ce["reasoning_class"] is True
assert ce["preflight_decision"] == "dispatch"
# writer_version bumped to 1.3
assert payload.get("writer_version") == "1.3", f"writer_version: {payload.get('writer_version')!r}"
print("OK")
PY
    [ "$status" -eq 0 ]
}

# =============================================================================
# V-13: backward-compat — omitting capability_evaluation produces v1.2 shape
# =============================================================================

@test "V13: emit_model_invoke_complete without capability_evaluation omits the field" {
    run "$PYTHON_BIN" - <<PY
import os
import sys
import types
from pathlib import Path

ROOT = Path("$PROJECT_ROOT")
sys.path.insert(0, str(ROOT / ".claude" / "adapters"))

captured = {}
def _fake_audit_emit(primitive_id, event_type, payload, log_path):
    captured["payload"] = payload
fake = types.ModuleType("loa_cheval.audit_envelope")
fake.audit_emit = _fake_audit_emit
sys.modules["loa_cheval.audit_envelope"] = fake

os.environ.pop("LOA_MODELINV_AUDIT_DISABLE", None)
from loa_cheval.audit.modelinv import (
    emit_model_invoke_complete,
    _reset_writer_version_cache_for_tests,
)
_reset_writer_version_cache_for_tests()

emit_model_invoke_complete(
    models_requested=["openai:gpt-5.5"],
    models_succeeded=["openai:gpt-5.5"],
    models_failed=[],
    operator_visible_warn=False,
)
payload = captured.get("payload")
assert payload is not None
# Backward-compat: omitting the kwarg means the field is absent.
assert "capability_evaluation" not in payload, "capability_evaluation should not appear when kwarg omitted"
# Writer version still bumps (audit-trail signal that the writer COULD have emitted it).
assert payload.get("writer_version") == "1.3", f"writer_version: {payload.get('writer_version')!r}"
print("OK")
PY
    [ "$status" -eq 0 ]
}
