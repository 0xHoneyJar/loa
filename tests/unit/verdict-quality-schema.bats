#!/usr/bin/env bats
# =============================================================================
# tests/unit/verdict-quality-schema.bats
#
# cycle-109 Sprint 2 T2.1 — verdict-quality envelope v1.0 schema (PRD §FR-2.1,
# SDD §3.2.1). The schema is the load-bearing contract for sprint-2's
# substrate-output-quality story: every cheval / Flatline / adversarial-review
# / BB / red-team / post-PR-triage emission carries this envelope.
#
# Coverage focuses on the load-bearing invariants:
#
#   - status enum (SKP-001 canonical classification — REQUIRED)
#   - consensus_outcome enum + REQUIRED (SKP-002 v5 closure)
#   - truncation_waiver_applied bool + REQUIRED (SKP-001 v6 closure)
#   - voices_succeeded_ids array + REQUIRED (SKP-003 v6 closure)
#   - voices_dropped[].blocker_risk enum (SKP-002)
#   - additionalProperties: false (closes the unknown-field leak surface)
#
# T2.1 ships ONLY the schema. T2.2 ships the canonical Python classifier
# + bash twin; T2.3-T2.7 refactor the 7 consumers in IMP-004 dependency
# order.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    SCHEMA_PATH="$PROJECT_ROOT/.claude/data/schemas/verdict-quality.schema.json"

    if [[ -x "$PROJECT_ROOT/.venv/bin/python" ]]; then
        PYTHON_BIN="$PROJECT_ROOT/.venv/bin/python"
    else
        PYTHON_BIN="$(command -v python3)"
    fi

    BATS_TMP="$(mktemp -d "${BATS_TMPDIR:-/tmp}/verdict-quality-schema.XXXXXX")"
}

teardown() {
    rm -rf "$BATS_TMP" 2>/dev/null || true
}

# Skip gracefully when jsonschema isn't installed (CI bats-tests.yml env).
_require_schema_deps() {
    "$PYTHON_BIN" -c "import jsonschema" 2>/dev/null \
        || skip "jsonschema not installed in this Python env"
}

# Validate a JSON payload against the schema; echo "VALID" or "INVALID: <msg>"
# and exit accordingly.
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

# A well-formed v1.0 verdict-quality envelope (used as the positive
# control baseline; per-test fixtures mutate one field at a time).
_write_baseline() {
    local path="$1"
    cat > "$path" <<'JSON'
{
    "status": "APPROVED",
    "consensus_outcome": "consensus",
    "truncation_waiver_applied": false,
    "voices_planned": 3,
    "voices_succeeded": 3,
    "voices_succeeded_ids": ["opus", "gpt-5.5-pro", "gemini-3.1-pro"],
    "voices_dropped": [],
    "chain_health": "ok",
    "confidence_floor": "high",
    "rationale": "All 3 voices succeeded; consensus reached"
}
JSON
}

# =============================================================================
# VQ1: schema file exists at the canonical path
# =============================================================================

@test "VQ1: schema file exists at .claude/data/schemas/verdict-quality.schema.json" {
    [[ -f "$SCHEMA_PATH" ]]
}

# =============================================================================
# VQ2: baseline well-formed envelope validates (positive control)
# =============================================================================

@test "VQ2: well-formed envelope validates" {
    _require_schema_deps
    _write_baseline "$BATS_TMP/baseline.json"
    run _validate "$BATS_TMP/baseline.json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"VALID"* ]]
}

# =============================================================================
# VQ3: status REQUIRED (schema rejects envelope without it) — SKP-001 closure
# =============================================================================

@test "VQ3: schema REQUIRES status field (SKP-001 canonical classification)" {
    _require_schema_deps
    _write_baseline "$BATS_TMP/no-status.json"
    "$PYTHON_BIN" -c "
import json
p = json.load(open('$BATS_TMP/no-status.json'))
p.pop('status')
json.dump(p, open('$BATS_TMP/no-status.json', 'w'))
"
    run _validate "$BATS_TMP/no-status.json"
    [ "$status" -ne 0 ]
    [[ "$output" == *"INVALID"* ]]
}

# =============================================================================
# VQ4: status enum (APPROVED | DEGRADED | FAILED)
# =============================================================================

@test "VQ4: status enum rejects unknown values" {
    _require_schema_deps
    _write_baseline "$BATS_TMP/bad-status.json"
    "$PYTHON_BIN" -c "
import json
p = json.load(open('$BATS_TMP/bad-status.json'))
p['status'] = 'PENDING'
json.dump(p, open('$BATS_TMP/bad-status.json', 'w'))
"
    run _validate "$BATS_TMP/bad-status.json"
    [ "$status" -ne 0 ]
}

# =============================================================================
# VQ5: consensus_outcome REQUIRED + enum (SKP-002 v5 closure)
# =============================================================================

@test "VQ5: consensus_outcome REQUIRED + enum (consensus | impossible)" {
    _require_schema_deps
    _write_baseline "$BATS_TMP/no-consensus.json"
    "$PYTHON_BIN" -c "
import json
p = json.load(open('$BATS_TMP/no-consensus.json'))
p.pop('consensus_outcome')
json.dump(p, open('$BATS_TMP/no-consensus.json', 'w'))
"
    run _validate "$BATS_TMP/no-consensus.json"
    [ "$status" -ne 0 ]
}

# =============================================================================
# VQ6: truncation_waiver_applied REQUIRED + bool (SKP-001 v6 closure)
# =============================================================================

@test "VQ6: truncation_waiver_applied REQUIRED + bool (SKP-001 v6 closure)" {
    _require_schema_deps
    _write_baseline "$BATS_TMP/no-waiver.json"
    "$PYTHON_BIN" -c "
import json
p = json.load(open('$BATS_TMP/no-waiver.json'))
p.pop('truncation_waiver_applied')
json.dump(p, open('$BATS_TMP/no-waiver.json', 'w'))
"
    run _validate "$BATS_TMP/no-waiver.json"
    [ "$status" -ne 0 ]
}

# =============================================================================
# VQ7: voices_succeeded_ids REQUIRED (SKP-003 v6 closure)
# =============================================================================

@test "VQ7: voices_succeeded_ids REQUIRED (SKP-003 v6 closure)" {
    _require_schema_deps
    _write_baseline "$BATS_TMP/no-ids.json"
    "$PYTHON_BIN" -c "
import json
p = json.load(open('$BATS_TMP/no-ids.json'))
p.pop('voices_succeeded_ids')
json.dump(p, open('$BATS_TMP/no-ids.json', 'w'))
"
    run _validate "$BATS_TMP/no-ids.json"
    [ "$status" -ne 0 ]
}

# =============================================================================
# VQ8: voices_dropped[].blocker_risk REQUIRED on each entry (SKP-002)
# =============================================================================

@test "VQ8: voices_dropped[] entries REQUIRE blocker_risk (SKP-002)" {
    _require_schema_deps
    "$PYTHON_BIN" -c "
import json
p = {
    'status': 'DEGRADED',
    'consensus_outcome': 'consensus',
    'truncation_waiver_applied': False,
    'voices_planned': 3,
    'voices_succeeded': 2,
    'voices_succeeded_ids': ['opus', 'gpt-5.5'],
    'voices_dropped': [
        {'voice': 'gemini-3.1-pro', 'reason': 'EmptyContent', 'exit_code': 1}
    ],
    'chain_health': 'degraded',
    'confidence_floor': 'med',
    'rationale': 'gemini dropped',
}
json.dump(p, open('$BATS_TMP/no-risk.json', 'w'))
"
    run _validate "$BATS_TMP/no-risk.json"
    [ "$status" -ne 0 ]
}

# =============================================================================
# VQ9: voices_dropped[].blocker_risk enum (unknown | low | med | high)
# =============================================================================

@test "VQ9: blocker_risk enum rejects unknown values" {
    _require_schema_deps
    "$PYTHON_BIN" -c "
import json
p = {
    'status': 'DEGRADED',
    'consensus_outcome': 'consensus',
    'truncation_waiver_applied': False,
    'voices_planned': 3,
    'voices_succeeded': 2,
    'voices_succeeded_ids': ['opus', 'gpt-5.5'],
    'voices_dropped': [
        {'voice': 'gemini-3.1-pro', 'reason': 'EmptyContent', 'exit_code': 1, 'blocker_risk': 'CRITICAL'}
    ],
    'chain_health': 'degraded',
    'confidence_floor': 'med',
    'rationale': 'test',
}
json.dump(p, open('$BATS_TMP/bad-risk.json', 'w'))
"
    run _validate "$BATS_TMP/bad-risk.json"
    [ "$status" -ne 0 ]
}

# =============================================================================
# VQ10: additionalProperties: false at top level rejects unknown keys
# =============================================================================

@test "VQ10: additionalProperties: false rejects unknown top-level keys" {
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

# =============================================================================
# VQ11: DEGRADED envelope with dropped voice + blocker_risk: med is well-formed
# =============================================================================

@test "VQ11: DEGRADED envelope with voices_dropped + blocker_risk validates" {
    _require_schema_deps
    "$PYTHON_BIN" -c "
import json
p = {
    'status': 'DEGRADED',
    'consensus_outcome': 'consensus',
    'truncation_waiver_applied': False,
    'voices_planned': 3,
    'voices_succeeded': 2,
    'voices_succeeded_ids': ['opus', 'gpt-5.5-pro'],
    'voices_dropped': [
        {'voice': 'gemini-3.1-pro', 'reason': 'EmptyContent', 'exit_code': 1, 'blocker_risk': 'med'}
    ],
    'chain_health': 'degraded',
    'confidence_floor': 'med',
    'rationale': 'gemini dropped; remaining voices reached consensus',
}
json.dump(p, open('$BATS_TMP/degraded.json', 'w'))
"
    run _validate "$BATS_TMP/degraded.json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"VALID"* ]]
}

# =============================================================================
# VQ12: chain_health enum (ok | degraded | exhausted)
# =============================================================================

@test "VQ12: chain_health enum rejects unknown values" {
    _require_schema_deps
    _write_baseline "$BATS_TMP/bad-chain.json"
    "$PYTHON_BIN" -c "
import json
p = json.load(open('$BATS_TMP/bad-chain.json'))
p['chain_health'] = 'partial'
json.dump(p, open('$BATS_TMP/bad-chain.json', 'w'))
"
    run _validate "$BATS_TMP/bad-chain.json"
    [ "$status" -ne 0 ]
}
