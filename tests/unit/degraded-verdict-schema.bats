#!/usr/bin/env bats
# =============================================================================
# tests/unit/degraded-verdict-schema.bats
#
# cycle-117 item D (#1177) — schema-conformance tests for the new
# degraded-verdict.schema.json (the trajectory record shape emitted by
# degraded-verdict-lib.sh whenever a gate writer produces a non-APPROVED
# verdict band). Modeled on tests/unit/verdict-quality-schema.bats.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    SCHEMA_PATH="$PROJECT_ROOT/.claude/data/trajectory-schemas/degraded-verdict.schema.json"

    if [[ -x "$PROJECT_ROOT/.venv/bin/python" ]]; then
        PYTHON_BIN="$PROJECT_ROOT/.venv/bin/python"
    else
        PYTHON_BIN="$(command -v python3)"
    fi

    BATS_TMP="$(mktemp -d "${BATS_TMPDIR:-/tmp}/degraded-verdict-schema.XXXXXX")"
}

teardown() {
    rm -rf "$BATS_TMP" 2>/dev/null || true
}

# Skip gracefully when jsonschema isn't installed (CI bats-tests.yml env).
_require_schema_deps() {
    "$PYTHON_BIN" -c "import jsonschema" 2>/dev/null \
        || skip "jsonschema not installed in this Python env"
}

_validate() {
    local payload="$1"
    "$PYTHON_BIN" - <<PY
import json, sys
try:
    import jsonschema
except ImportError:
    print("SKIP", file=sys.stderr); sys.exit(77)
schema = json.load(open("$SCHEMA_PATH"))
payload = json.load(open("$payload"))
try:
    jsonschema.validate(payload, schema)
    print("VALID")
except jsonschema.ValidationError as e:
    print(f"INVALID: {e.message}")
    sys.exit(1)
PY
}

_write_baseline() {
    local path="$1"
    cat > "$path" <<'JSON'
{
    "gate": "adversarial-review:audit",
    "verdict_band": "DEGRADED",
    "degradation_reason": "api_failure",
    "degraded_legs": ["gpt-5.5-pro"],
    "model_exit_code": 3,
    "sprint_id": "sprint-42",
    "ts": "2026-07-06T08:02:31Z"
}
JSON
}

@test "DV1: schema file exists at .claude/data/trajectory-schemas/degraded-verdict.schema.json" {
    [[ -f "$SCHEMA_PATH" ]]
}

@test "DV2: well-formed DEGRADED envelope validates" {
    _require_schema_deps
    _write_baseline "$BATS_TMP/baseline.json"
    run _validate "$BATS_TMP/baseline.json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"VALID"* ]]
}

@test "DV3: minimal envelope (only required fields) validates" {
    _require_schema_deps
    "$PYTHON_BIN" -c "
import json
p = {
    'gate': 'flatline:prd',
    'verdict_band': 'FAILED',
    'sprint_id': 'prd',
    'ts': '2026-07-06T08:02:31Z',
}
json.dump(p, open('$BATS_TMP/minimal.json', 'w'))
"
    run _validate "$BATS_TMP/minimal.json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"VALID"* ]]
}

@test "DV4: schema REQUIRES gate field" {
    _require_schema_deps
    _write_baseline "$BATS_TMP/no-gate.json"
    "$PYTHON_BIN" -c "
import json
p = json.load(open('$BATS_TMP/no-gate.json'))
p.pop('gate')
json.dump(p, open('$BATS_TMP/no-gate.json', 'w'))
"
    run _validate "$BATS_TMP/no-gate.json"
    [ "$status" -ne 0 ]
}

@test "DV5: schema REQUIRES verdict_band field" {
    _require_schema_deps
    _write_baseline "$BATS_TMP/no-band.json"
    "$PYTHON_BIN" -c "
import json
p = json.load(open('$BATS_TMP/no-band.json'))
p.pop('verdict_band')
json.dump(p, open('$BATS_TMP/no-band.json', 'w'))
"
    run _validate "$BATS_TMP/no-band.json"
    [ "$status" -ne 0 ]
}

@test "DV6: schema REQUIRES sprint_id field" {
    _require_schema_deps
    _write_baseline "$BATS_TMP/no-sprint.json"
    "$PYTHON_BIN" -c "
import json
p = json.load(open('$BATS_TMP/no-sprint.json'))
p.pop('sprint_id')
json.dump(p, open('$BATS_TMP/no-sprint.json', 'w'))
"
    run _validate "$BATS_TMP/no-sprint.json"
    [ "$status" -ne 0 ]
}

@test "DV7: schema REQUIRES ts field" {
    _require_schema_deps
    _write_baseline "$BATS_TMP/no-ts.json"
    "$PYTHON_BIN" -c "
import json
p = json.load(open('$BATS_TMP/no-ts.json'))
p.pop('ts')
json.dump(p, open('$BATS_TMP/no-ts.json', 'w'))
"
    run _validate "$BATS_TMP/no-ts.json"
    [ "$status" -ne 0 ]
}

@test "DV8: verdict_band enum rejects APPROVED (a clean run must never produce a record)" {
    _require_schema_deps
    _write_baseline "$BATS_TMP/bad-band.json"
    "$PYTHON_BIN" -c "
import json
p = json.load(open('$BATS_TMP/bad-band.json'))
p['verdict_band'] = 'APPROVED'
json.dump(p, open('$BATS_TMP/bad-band.json', 'w'))
"
    run _validate "$BATS_TMP/bad-band.json"
    [ "$status" -ne 0 ]
}

@test "DV9: verdict_band enum rejects UNKNOWN" {
    _require_schema_deps
    _write_baseline "$BATS_TMP/bad-band2.json"
    "$PYTHON_BIN" -c "
import json
p = json.load(open('$BATS_TMP/bad-band2.json'))
p['verdict_band'] = 'UNKNOWN'
json.dump(p, open('$BATS_TMP/bad-band2.json', 'w'))
"
    run _validate "$BATS_TMP/bad-band2.json"
    [ "$status" -ne 0 ]
}

@test "DV10: additionalProperties: false rejects unknown top-level keys" {
    _require_schema_deps
    _write_baseline "$BATS_TMP/extra.json"
    "$PYTHON_BIN" -c "
import json
p = json.load(open('$BATS_TMP/extra.json'))
p['private_unknown_field'] = 'leak'
json.dump(p, open('$BATS_TMP/extra.json', 'w'))
"
    run _validate "$BATS_TMP/extra.json"
    [ "$status" -ne 0 ]
}

@test "DV11: degraded_legs empty array is rejected (omit the field instead)" {
    _require_schema_deps
    _write_baseline "$BATS_TMP/empty-legs.json"
    "$PYTHON_BIN" -c "
import json
p = json.load(open('$BATS_TMP/empty-legs.json'))
p['degraded_legs'] = []
json.dump(p, open('$BATS_TMP/empty-legs.json', 'w'))
"
    run _validate "$BATS_TMP/empty-legs.json"
    [ "$status" -ne 0 ]
}

@test "DV12: model_exit_code accepts null" {
    _require_schema_deps
    _write_baseline "$BATS_TMP/null-mec.json"
    "$PYTHON_BIN" -c "
import json
p = json.load(open('$BATS_TMP/null-mec.json'))
p['model_exit_code'] = None
json.dump(p, open('$BATS_TMP/null-mec.json', 'w'))
"
    run _validate "$BATS_TMP/null-mec.json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"VALID"* ]]
}

@test "DV13: model_exit_code rejects a string value" {
    _require_schema_deps
    _write_baseline "$BATS_TMP/str-mec.json"
    "$PYTHON_BIN" -c "
import json
p = json.load(open('$BATS_TMP/str-mec.json'))
p['model_exit_code'] = 'not-a-number'
json.dump(p, open('$BATS_TMP/str-mec.json', 'w'))
"
    run _validate "$BATS_TMP/str-mec.json"
    [ "$status" -ne 0 ]
}

@test "DV14: FAILED band with multiple degraded_legs validates" {
    _require_schema_deps
    "$PYTHON_BIN" -c "
import json
p = {
    'gate': 'flatline:sdd',
    'verdict_band': 'FAILED',
    'degradation_reason': 'EmptyContent',
    'degraded_legs': ['gemini-3.1-pro', 'gpt-5.5-pro'],
    'model_exit_code': 1,
    'sprint_id': 'sdd',
    'ts': '2026-07-06T09:00:00Z',
}
json.dump(p, open('$BATS_TMP/multi-leg.json', 'w'))
"
    run _validate "$BATS_TMP/multi-leg.json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"VALID"* ]]
}
