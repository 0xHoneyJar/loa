#!/usr/bin/env bats
# =============================================================================
# tests/unit/model-events-schemas.bats
#
# cycle-102 Sprint 1 (T1.2 + T1.4) — Schema contracts for the audit
# envelope's MODELINV expansion and the three model-event payload schemas:
#
#   .claude/data/trajectory-schemas/
#     agent-network-envelope.schema.json                       (T1.2 bump)
#     model-events/model-invoke-complete.payload.schema.json   (T1.4)
#     model-events/class-resolved.payload.schema.json          (T1.4)
#     model-events/probe-cache-refresh.payload.schema.json     (T1.4)
#
# Test taxonomy:
#   ENV1-ENV5    Envelope schema 1.2.0 + MODELINV invariants
#   MIC1-MIC8    model.invoke.complete payload constraints
#   CR1-CR5      class.resolved payload constraints
#   PR1-PR5      probe.cache.refresh payload constraints
#   X1-X2        Cross-schema integrity ($ref to model-error works)
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

    ENVELOPE_SCHEMA="$PROJECT_ROOT/.claude/data/trajectory-schemas/agent-network-envelope.schema.json"
    MODEL_ERROR_SCHEMA="$PROJECT_ROOT/.claude/data/trajectory-schemas/model-error.schema.json"
    MIC_SCHEMA="$PROJECT_ROOT/.claude/data/trajectory-schemas/model-events/model-invoke-complete.payload.schema.json"
    CR_SCHEMA="$PROJECT_ROOT/.claude/data/trajectory-schemas/model-events/class-resolved.payload.schema.json"
    PR_SCHEMA="$PROJECT_ROOT/.claude/data/trajectory-schemas/model-events/probe-cache-refresh.payload.schema.json"

    for f in "$ENVELOPE_SCHEMA" "$MODEL_ERROR_SCHEMA" "$MIC_SCHEMA" "$CR_SCHEMA" "$PR_SCHEMA"; do
        [[ -f "$f" ]] || {
            printf 'FATAL: schema missing: %s\n' "$f" >&2
            return 1
        }
    done

    if [[ -x "$PROJECT_ROOT/.venv/bin/python" ]]; then
        PYTHON_BIN="$PROJECT_ROOT/.venv/bin/python"
    else
        PYTHON_BIN="${PYTHON_BIN:-python3}"
    fi
    "$PYTHON_BIN" -c "import jsonschema" 2>/dev/null \
        || skip "jsonschema not available in $PYTHON_BIN"

    # BB iter-1 FIND-001 (medium): REPO_ROOT export MUST be inside setup()
    # so it picks up the freshly-assigned PROJECT_ROOT for this test run,
    # not whatever the caller's env had at file-load time.
    export REPO_ROOT="$PROJECT_ROOT"

    WORK_DIR="$(mktemp -d)"
}

teardown() {
    [[ -n "${WORK_DIR:-}" && -d "$WORK_DIR" ]] && rm -rf "$WORK_DIR"
}

# Helper: validate $payload against $schema_path. Uses a referencing registry
# so $ref to model-error.schema.json resolves cross-schema.
_validate() {
    local schema_path="$1"
    local payload="$2"
    local repo_root="$PROJECT_ROOT"
    "$PYTHON_BIN" -I -c "
import json, sys, os
import jsonschema
from jsonschema import Draft202012Validator
from referencing import Registry, Resource

repo_root = os.environ['REPO_ROOT']

def load(path):
    with open(path) as f:
        return json.load(f)

registry = Registry()
for rel in [
    '.claude/data/trajectory-schemas/model-error.schema.json',
    '.claude/data/trajectory-schemas/agent-network-envelope.schema.json',
    '.claude/data/trajectory-schemas/model-events/model-invoke-complete.payload.schema.json',
    '.claude/data/trajectory-schemas/model-events/class-resolved.payload.schema.json',
    '.claude/data/trajectory-schemas/model-events/probe-cache-refresh.payload.schema.json',
]:
    s = load(os.path.join(repo_root, rel))
    res = Resource.from_contents(s)
    registry = registry.with_resource(uri='file://'+os.path.abspath(os.path.join(repo_root, rel)), resource=res)
    if '\$id' in s:
        registry = registry.with_resource(uri=s['\$id'], resource=res)

schema = load(sys.argv[1])
payload = json.loads(sys.argv[2])

v = Draft202012Validator(schema, registry=registry)
errs = list(v.iter_errors(payload))
if errs:
    for e in errs:
        sys.stderr.write(f'  {list(e.absolute_path)}: {e.message}\n')
    sys.exit(78)
sys.exit(0)
" "$schema_path" "$payload"
}

# BB iter-1 FIND-001 (medium): REPO_ROOT was exported here at file load
# time, but PROJECT_ROOT is assigned in setup() — making the export
# read whatever was inherited from the caller's env (or empty). bats
# files have two execution phases (load + setup); env exports outside
# setup() leak the host's state into tests. Moved into setup() below
# so the export is correctly ordered after PROJECT_ROOT assignment.

# -----------------------------------------------------------------------------
# Schema integrity (Draft 2020-12 well-formedness)
# -----------------------------------------------------------------------------

@test "S0: all 5 schemas are well-formed Draft 2020-12" {
    "$PYTHON_BIN" -I -c "
import json, jsonschema
for f in ['$ENVELOPE_SCHEMA', '$MIC_SCHEMA', '$CR_SCHEMA', '$PR_SCHEMA', '$MODEL_ERROR_SCHEMA']:
    s = json.load(open(f))
    jsonschema.Draft202012Validator.check_schema(s)
"
}

# -----------------------------------------------------------------------------
# ENV1-ENV5 — Envelope 1.2.0 + MODELINV invariants
# -----------------------------------------------------------------------------

@test "ENV1: primitive_id enum now contains MODELINV" {
    n="$("$PYTHON_BIN" -I -c "
import json
s = json.load(open('$ENVELOPE_SCHEMA'))
print('MODELINV' in s['properties']['primitive_id']['enum'])
")"
    [ "$n" = "True" ]
}

@test "ENV2: primitive_id enum has all 7 original L-values + MODELINV (8 total)" {
    n="$("$PYTHON_BIN" -I -c "
import json
s = json.load(open('$ENVELOPE_SCHEMA'))
e = s['properties']['primitive_id']['enum']
print(len(e), 'L1' in e and 'L7' in e and 'MODELINV' in e)
")"
    [ "$n" = "8 True" ]
}

@test "ENV3: envelope accepts schema_version=1.2.0 + primitive_id=MODELINV" {
    payload='{"schema_version":"1.2.0","primitive_id":"MODELINV","event_type":"model.invoke.complete","ts_utc":"2026-05-09T05:50:00.000000Z","prev_hash":"GENESIS","payload":{"models_requested":["openai:gpt-5.5-pro"],"models_succeeded":["openai:gpt-5.5-pro"],"models_failed":[],"operator_visible_warn":false}}'
    run _validate "$ENVELOPE_SCHEMA" "$payload"
    [ "$status" -eq 0 ]
}

@test "ENV4: envelope rejects unknown primitive_id (defense against typos like MODELLINV)" {
    payload='{"schema_version":"1.2.0","primitive_id":"MODELLINV","event_type":"x","ts_utc":"2026-05-09T05:50:00Z","prev_hash":"GENESIS","payload":{}}'
    run _validate "$ENVELOPE_SCHEMA" "$payload"
    [ "$status" -eq 78 ]
}

@test "ENV5: envelope still accepts L1-L7 entries (additive invariant)" {
    for prim in L1 L2 L3 L4 L5 L6 L7; do
        payload="$(jq -nc --arg p "$prim" '{schema_version:"1.2.0",primitive_id:$p,event_type:"x",ts_utc:"2026-05-09T05:50:00Z",prev_hash:"GENESIS",payload:{}}')"
        run _validate "$ENVELOPE_SCHEMA" "$payload"
        [ "$status" -eq 0 ] || { printf 'FAIL: %s rejected\n' "$prim" >&2; return 1; }
    done
}

# -----------------------------------------------------------------------------
# MIC1-MIC8 — model.invoke.complete payload constraints
# -----------------------------------------------------------------------------

@test "MIC1: minimal valid payload accepted" {
    payload='{"models_requested":["openai:gpt-5.5-pro"],"models_succeeded":["openai:gpt-5.5-pro"],"models_failed":[],"operator_visible_warn":false}'
    run _validate "$MIC_SCHEMA" "$payload"
    [ "$status" -eq 0 ]
}

@test "MIC2: full payload with all optional fields accepted" {
    payload='{"models_requested":["openai:gpt-5.5-pro","anthropic:claude-opus-4-7"],"models_succeeded":["anthropic:claude-opus-4-7"],"models_failed":[{"model":"gpt-5.5-pro","error_class":"PROVIDER_OUTAGE","message_redacted":"503","fallback_from":"gpt-5.5-pro","fallback_to":"claude-opus-4-7","retryable":true}],"operator_visible_warn":true,"calling_primitive":"L1","capability_class":"top-reasoning","probe_latency_ms":120,"invocation_latency_ms":3400,"cost_micro_usd":15000,"kill_switch_active":false}'
    run _validate "$MIC_SCHEMA" "$payload"
    [ "$status" -eq 0 ]
}

@test "MIC3: empty models_requested rejected (minItems:1)" {
    payload='{"models_requested":[],"models_succeeded":[],"models_failed":[],"operator_visible_warn":false}'
    run _validate "$MIC_SCHEMA" "$payload"
    [ "$status" -eq 78 ]
}

@test "MIC4: invalid model id format (no provider:) rejected" {
    payload='{"models_requested":["just-a-model-id"],"models_succeeded":[],"models_failed":[],"operator_visible_warn":false}'
    run _validate "$MIC_SCHEMA" "$payload"
    [ "$status" -eq 78 ]
}

@test "MIC5: models_failed entry uses error_class enum from model-error.schema.json (cross-schema \$ref)" {
    # NOT_AN_ENUM should be rejected via the referenced enum
    payload='{"models_requested":["openai:m"],"models_succeeded":[],"models_failed":[{"model":"m","error_class":"NOT_AN_ENUM","message_redacted":"x"}],"operator_visible_warn":false}'
    run _validate "$MIC_SCHEMA" "$payload"
    [ "$status" -eq 78 ]
}

@test "MIC6: calling_primitive accepts null" {
    payload='{"models_requested":["openai:m"],"models_succeeded":["openai:m"],"models_failed":[],"operator_visible_warn":false,"calling_primitive":null}'
    run _validate "$MIC_SCHEMA" "$payload"
    [ "$status" -eq 0 ]
}

@test "MIC7: calling_primitive rejects MODELINV (only L1-L7 valid as caller)" {
    payload='{"models_requested":["openai:m"],"models_succeeded":["openai:m"],"models_failed":[],"operator_visible_warn":false,"calling_primitive":"MODELINV"}'
    run _validate "$MIC_SCHEMA" "$payload"
    [ "$status" -eq 78 ]
}

@test "MIC8: unknown top-level field rejected (additionalProperties:false)" {
    payload='{"models_requested":["openai:m"],"models_succeeded":[],"models_failed":[],"operator_visible_warn":false,"surprise":"extra"}'
    run _validate "$MIC_SCHEMA" "$payload"
    [ "$status" -eq 78 ]
}

# -----------------------------------------------------------------------------
# CR1-CR5 — class.resolved payload constraints
# -----------------------------------------------------------------------------

@test "CR1: minimal valid (RESOLVED outcome)" {
    payload='{"class_name":"top-reasoning","outcome":"RESOLVED","chosen_provider":"openai","chosen_model":"gpt-5.5-pro"}'
    run _validate "$CR_SCHEMA" "$payload"
    [ "$status" -eq 0 ]
}

@test "CR2: cycle-detection failure (FAILED + reason=cycle + cycle[])" {
    payload='{"class_name":"top-reasoning","outcome":"FAILED","error_class":"ROUTING_MISS","reason":"cycle","cycle":["openai:gpt-5.5-pro","anthropic:claude-opus-4-7","openai:gpt-5.5-pro"]}'
    run _validate "$CR_SCHEMA" "$payload"
    [ "$status" -eq 0 ]
}

@test "CR3: invalid outcome rejected" {
    payload='{"class_name":"top-reasoning","outcome":"PROBABLY_OK"}'
    run _validate "$CR_SCHEMA" "$payload"
    [ "$status" -eq 78 ]
}

@test "CR4: probe_outcomes enum tight (no surprise values)" {
    payload='{"class_name":"top-reasoning","outcome":"FALLBACK","chosen_provider":"anthropic","chosen_model":"claude-opus-4-7","probe_outcomes":["AVAILABLE","SOMETIMES"]}'
    run _validate "$CR_SCHEMA" "$payload"
    [ "$status" -eq 78 ]
}

@test "CR5: error_class field uses cross-schema \$ref (rejects unknown enum)" {
    payload='{"class_name":"top-reasoning","outcome":"FAILED","error_class":"NOT_AN_ENUM","reason":"x"}'
    run _validate "$CR_SCHEMA" "$payload"
    [ "$status" -eq 78 ]
}

# -----------------------------------------------------------------------------
# PR1-PR5 — probe.cache.refresh payload constraints
# -----------------------------------------------------------------------------

@test "PR1: minimal valid (AVAILABLE)" {
    payload='{"provider":"openai","model":"gpt-5.5-pro","outcome":"AVAILABLE","latency_ms":412}'
    run _validate "$PR_SCHEMA" "$payload"
    [ "$status" -eq 0 ]
}

@test "PR2: full payload with all optional fields" {
    payload='{"provider":"openai","model":"gpt-5.5-pro","outcome":"DEGRADED","latency_ms":1850,"error_class":"DEGRADED_PARTIAL","previous_outcome":"AVAILABLE","cache_path":".run/model-probe-cache/openai.json","stale_lock_recovered":false,"background_refresh":true,"runtime":"python","ts_utc":"2026-05-09T05:50:00Z"}'
    run _validate "$PR_SCHEMA" "$payload"
    [ "$status" -eq 0 ]
}

@test "PR3: latency_ms negative rejected" {
    payload='{"provider":"openai","model":"m","outcome":"AVAILABLE","latency_ms":-1}'
    run _validate "$PR_SCHEMA" "$payload"
    [ "$status" -eq 78 ]
}

@test "PR4: latency_ms 30001 rejected (cap = 30s)" {
    payload='{"provider":"openai","model":"m","outcome":"FAIL","latency_ms":30001}'
    run _validate "$PR_SCHEMA" "$payload"
    [ "$status" -eq 78 ]
}

@test "PR5: runtime enum tight (no 'go' or 'rust')" {
    payload='{"provider":"openai","model":"m","outcome":"AVAILABLE","latency_ms":100,"runtime":"go"}'
    run _validate "$PR_SCHEMA" "$payload"
    [ "$status" -eq 78 ]
}

# -----------------------------------------------------------------------------
# X1-X2 — Cross-schema $ref integrity
# -----------------------------------------------------------------------------

@test "X1: \$ref ../model-error.schema.json#/properties/error_class resolves and constrains correctly" {
    # Sanity: TIMEOUT (a valid error_class) accepted in models_failed[].error_class
    payload='{"models_requested":["openai:m"],"models_succeeded":[],"models_failed":[{"model":"m","error_class":"TIMEOUT","message_redacted":"x"}],"operator_visible_warn":true}'
    run _validate "$MIC_SCHEMA" "$payload"
    [ "$status" -eq 0 ]
}

@test "X2: cross-runtime byte-identical schema files (LF, no BOM, trailing newline)" {
    for f in "$ENVELOPE_SCHEMA" "$MIC_SCHEMA" "$CR_SCHEMA" "$PR_SCHEMA"; do
        # No CR (Windows line endings)
        ! grep -lU $'\r' "$f" || { printf 'CR found in %s\n' "$f" >&2; return 1; }
        # No UTF-8 BOM
        head -c 3 "$f" | grep -q $'\xEF\xBB\xBF' && { printf 'BOM found in %s\n' "$f" >&2; return 1; } || true
        # Ends with newline
        [[ "$(tail -c1 "$f" | xxd -p)" == "0a" ]] || { printf 'no trailing newline in %s\n' "$f" >&2; return 1; }
    done
}
