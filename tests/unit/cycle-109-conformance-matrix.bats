#!/usr/bin/env bats
# =============================================================================
# tests/unit/cycle-109-conformance-matrix.bats
#
# cycle-109 Sprint 2 T2.8 — verdict_quality conformance matrix (FR-2.7).
#
# Runs each canonical regression fixture through the canonical Python
# classifier (`loa_cheval.verdict.quality.compute_verdict_status` invoked
# via the `compute` CLI) and asserts:
#
#   1. Fixture envelope validates against verdict-quality.schema.json.
#   2. Computed status matches the fixture's declared status.
#   3. Producer invariants (validate_invariants) pass.
#
# Fixture corpus at `tests/fixtures/cycle-109/verdict-quality-conformance/`.
# Each fixture is one of the 5 canonical regression cases (#807, #809,
# #868, #805, cycle-109 PRD-review).
#
# Conformance closure: a future regression that emits "clean" status when
# the underlying state matches one of these fixtures MUST fail this matrix.
# This is the executable contract behind NFR-Rel-1.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    FIXTURE_DIR="$PROJECT_ROOT/tests/fixtures/cycle-109/verdict-quality-conformance"
    SCHEMA_PATH="$PROJECT_ROOT/.claude/data/schemas/verdict-quality.schema.json"

    if [[ -x "$PROJECT_ROOT/.venv/bin/python" ]]; then
        PYTHON_BIN="$PROJECT_ROOT/.venv/bin/python"
    else
        PYTHON_BIN="$(command -v python3)"
    fi
    export PYTHONPATH="$PROJECT_ROOT/.claude/adapters"
}

_require_jsonschema() {
    "$PYTHON_BIN" -c "import jsonschema" 2>/dev/null \
        || skip "jsonschema not installed in this Python env"
}

# Validate a fixture against verdict-quality.schema.json.
_validate_envelope() {
    local fixture="$1"
    "$PYTHON_BIN" - <<PY
import json, sys
import jsonschema
schema = json.load(open("$SCHEMA_PATH"))
envelope = json.load(open("$fixture"))
errors = list(jsonschema.validators.validator_for(schema)(schema).iter_errors(envelope))
if errors:
    print(f"INVALID: {errors[0].message}")
    sys.exit(1)
print("VALID")
PY
}

# Compute the canonical status for a fixture via the Python classifier CLI.
_compute_status() {
    local fixture="$1"
    "$PYTHON_BIN" -m loa_cheval.verdict.quality compute < "$fixture"
}

# Run validate_invariants on a fixture; succeeds on well-formed envelopes,
# raises EnvelopeInvariantViolation on producer-side violations.
_validate_invariants() {
    local fixture="$1"
    "$PYTHON_BIN" -c "
import sys, json
sys.path.insert(0, '$PROJECT_ROOT/.claude/adapters')
from loa_cheval.verdict.quality import validate_invariants
envelope = json.load(open('$fixture'))
validate_invariants(envelope)
print('OK')
"
}

# =============================================================================
# CFM-1..5 — Each canonical fixture validates against schema
# =============================================================================

@test "CFM1: kf002-empty-content-prd-review validates against verdict-quality schema" {
    _require_jsonschema
    run _validate_envelope "$FIXTURE_DIR/kf002-empty-content-prd-review.json"
    [ "$status" -eq 0 ]
    [[ "$output" == "VALID" ]]
}

@test "CFM2: bug-807-multi-model-fallback-misses validates" {
    _require_jsonschema
    run _validate_envelope "$FIXTURE_DIR/bug-807-multi-model-fallback-misses.json"
    [ "$status" -eq 0 ]
    [[ "$output" == "VALID" ]]
}

@test "CFM3: bug-809-status-clean-misleading validates" {
    _require_jsonschema
    run _validate_envelope "$FIXTURE_DIR/bug-809-status-clean-misleading.json"
    [ "$status" -eq 0 ]
    [[ "$output" == "VALID" ]]
}

@test "CFM4: bug-868-chain-exhausted-both-phases validates" {
    _require_jsonschema
    run _validate_envelope "$FIXTURE_DIR/bug-868-chain-exhausted-both-phases.json"
    [ "$status" -eq 0 ]
    [[ "$output" == "VALID" ]]
}

@test "CFM5: bug-805-single-model-bb-claim validates" {
    _require_jsonschema
    run _validate_envelope "$FIXTURE_DIR/bug-805-single-model-bb-claim.json"
    [ "$status" -eq 0 ]
    [[ "$output" == "VALID" ]]
}

# =============================================================================
# CFM-6..10 — Each fixture's status MATCHES the canonical classifier
# =============================================================================

@test "CFM6: kf002-empty-content-prd-review classifies as DEGRADED" {
    # Canonical PRD-review trajectory: 2/3 succeeded, 1 dropped with
    # blocker_risk=med under implementation sprint → DEGRADED (NOT clean).
    run _compute_status "$FIXTURE_DIR/kf002-empty-content-prd-review.json"
    [ "$status" -eq 0 ]
    [[ "$output" == "DEGRADED" ]]
}

@test "CFM7: bug-807-multi-model-fallback-misses classifies as DEGRADED" {
    # #807 closure: 1-of-3 voice succeeded; remaining 2 dropped with
    # blocker_risk=med — DEGRADED, not the pre-T2.x silent 'clean'.
    run _compute_status "$FIXTURE_DIR/bug-807-multi-model-fallback-misses.json"
    [ "$status" -eq 0 ]
    [[ "$output" == "DEGRADED" ]]
}

@test "CFM8: bug-809-status-clean-misleading classifies as FAILED (NFR-Rel-1)" {
    # #809 closure: 0/3 voices produced findings → FAILED auto-promotion
    # via voices_succeeded=0 short-circuit. Pre-T2.x: status='clean'.
    run _compute_status "$FIXTURE_DIR/bug-809-status-clean-misleading.json"
    [ "$status" -eq 0 ]
    [[ "$output" == "FAILED" ]]
}

@test "CFM9: bug-868-chain-exhausted-both-phases classifies as FAILED" {
    # #868 closure: ChainExhausted reason → blocker_risk=high (hard rule)
    # → FAILED auto-promotion.
    run _compute_status "$FIXTURE_DIR/bug-868-chain-exhausted-both-phases.json"
    [ "$status" -eq 0 ]
    [[ "$output" == "FAILED" ]]
}

@test "CFM10: bug-805-single-model-bb-claim classifies as DEGRADED" {
    # #805 closure: single-voice chain walked to fallback; succeeded but
    # chain_health=degraded violates APPROVED invariant → DEGRADED.
    run _compute_status "$FIXTURE_DIR/bug-805-single-model-bb-claim.json"
    [ "$status" -eq 0 ]
    [[ "$output" == "DEGRADED" ]]
}

# =============================================================================
# CFM-11..15 — Each fixture passes validate_invariants (producer-side)
# =============================================================================

@test "CFM11: kf002-empty-content-prd-review passes validate_invariants" {
    run _validate_invariants "$FIXTURE_DIR/kf002-empty-content-prd-review.json"
    [ "$status" -eq 0 ]
    [[ "$output" == "OK" ]]
}

@test "CFM12: bug-807-multi-model-fallback-misses passes validate_invariants" {
    run _validate_invariants "$FIXTURE_DIR/bug-807-multi-model-fallback-misses.json"
    [ "$status" -eq 0 ]
    [[ "$output" == "OK" ]]
}

@test "CFM13: bug-809-status-clean-misleading passes validate_invariants" {
    run _validate_invariants "$FIXTURE_DIR/bug-809-status-clean-misleading.json"
    [ "$status" -eq 0 ]
    [[ "$output" == "OK" ]]
}

@test "CFM14: bug-868-chain-exhausted-both-phases passes validate_invariants" {
    run _validate_invariants "$FIXTURE_DIR/bug-868-chain-exhausted-both-phases.json"
    [ "$status" -eq 0 ]
    [[ "$output" == "OK" ]]
}

@test "CFM15: bug-805-single-model-bb-claim passes validate_invariants" {
    run _validate_invariants "$FIXTURE_DIR/bug-805-single-model-bb-claim.json"
    [ "$status" -eq 0 ]
    [[ "$output" == "OK" ]]
}

# =============================================================================
# CFM-16 — Fixture corpus is complete (5 canonical regressions exist)
# =============================================================================

@test "CFM16: all 5 canonical regression fixtures exist on disk" {
    [[ -f "$FIXTURE_DIR/kf002-empty-content-prd-review.json" ]]
    [[ -f "$FIXTURE_DIR/bug-807-multi-model-fallback-misses.json" ]]
    [[ -f "$FIXTURE_DIR/bug-809-status-clean-misleading.json" ]]
    [[ -f "$FIXTURE_DIR/bug-868-chain-exhausted-both-phases.json" ]]
    [[ -f "$FIXTURE_DIR/bug-805-single-model-bb-claim.json" ]]
    [[ -f "$FIXTURE_DIR/README.md" ]]
}
