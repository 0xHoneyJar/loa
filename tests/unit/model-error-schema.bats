#!/usr/bin/env bats
# =============================================================================
# tests/unit/model-error-schema.bats
#
# cycle-102 Sprint 1 (T1.1) — JSON Schema contract pin for the typed
# model-error envelope at
# `.claude/data/trajectory-schemas/model-error.schema.json` (SDD section 4.1)
# and the validator helper at
# `.claude/scripts/lib/validate-model-error.{py,sh}`.
#
# Closes AC-1.1.test (partial — cheval mapping pinned in T1.5 bats).
#
# Test taxonomy:
#   E0       POSITIVE: minimal valid envelope accepted
#   E1-E5    STRUCTURAL: missing required fields rejected
#   E6-E10   TYPE: wrong-type values rejected
#   E11-E12  ENUM: invalid error_class / severity rejected
#   E13      LENGTH: message_redacted > 8192 chars rejected
#   E14-E16  CONDITIONAL: UNKNOWN <-> original_exception coupling
#   E17-E18  CONDITIONAL: fallback_from <-> fallback_to coupling
#   E19-E20  ADDITIONAL: extra fields rejected (additionalProperties:false)
#   E21      ALL 10 error_class values accepted (taxonomy completeness)
#   B1-B3    BASH TWIN: wrapper exit codes + JSON output
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    SCHEMA="$PROJECT_ROOT/.claude/data/trajectory-schemas/model-error.schema.json"
    VALIDATOR_PY="$PROJECT_ROOT/.claude/scripts/lib/validate-model-error.py"
    VALIDATOR_SH="$PROJECT_ROOT/.claude/scripts/lib/validate-model-error.sh"

    # HARD-FAIL on missing files (mirrors model-aliases-extra-schema.bats
    # rationale: skip-on-missing masks regressions where refactors rename
    # files and every test silently passes).
    [[ -f "$SCHEMA" ]] || {
        printf 'FATAL: schema missing at %s — T1.1 invariant broken\n' "$SCHEMA" >&2
        return 1
    }
    [[ -f "$VALIDATOR_PY" ]] || {
        printf 'FATAL: Python validator missing at %s — T1.1 invariant broken\n' "$VALIDATOR_PY" >&2
        return 1
    }
    [[ -f "$VALIDATOR_SH" ]] || {
        printf 'FATAL: bash wrapper missing at %s — T1.1 invariant broken\n' "$VALIDATOR_SH" >&2
        return 1
    }

    if [[ -x "$PROJECT_ROOT/.venv/bin/python" ]]; then
        PYTHON_BIN="$PROJECT_ROOT/.venv/bin/python"
    else
        PYTHON_BIN="${PYTHON_BIN:-python3}"
    fi
    # BB iter-3 FIND-004 (low): align preflight with runtime — both must
    # use python -I and import the exact modules the validator uses.
    "$PYTHON_BIN" -I -c "from jsonschema import Draft202012Validator" 2>/dev/null \
        || skip "jsonschema (Draft202012Validator) not available under python -I"

    # BB iter-3 FIND-003 (med): jq is only required by E13/E13b/E21 (the
    # payload-building tests). Scoping the skip to those tests via the
    # _need_jq helper avoids hiding 22+ pure-schema tests behind a setup
    # skip when a CI image happens to lack jq.
    HAVE_JQ=1
    command -v jq >/dev/null 2>&1 || HAVE_JQ=0

    WORK_DIR="$(mktemp -d)"
}

# Per-test jq prereq. Tests that need jq call `_need_jq` first.
_need_jq() {
    [[ "${HAVE_JQ:-0}" == "1" ]] || skip "jq not installed (required for this payload-building test)"
}

teardown() {
    [[ -n "${WORK_DIR:-}" && -d "$WORK_DIR" ]] && rm -rf "$WORK_DIR"
}

# Helper: write payload to temp file and validate via Python
_validate_py() {
    local payload="$1"
    local out="$WORK_DIR/payload.json"
    printf '%s' "$payload" > "$out"
    "$PYTHON_BIN" -I "$VALIDATOR_PY" --input "$out" --json --quiet
}

# Helper: write payload to temp file and validate via bash wrapper
_validate_sh() {
    local payload="$1"
    local out="$WORK_DIR/payload.json"
    printf '%s' "$payload" > "$out"
    "$VALIDATOR_SH" --input "$out" --json --quiet
}

# -----------------------------------------------------------------------------
# E0 — POSITIVE: minimal valid envelope accepted
# -----------------------------------------------------------------------------

@test "E0: minimal valid envelope (5 required fields) accepted" {
    payload='{"error_class":"TIMEOUT","severity":"WARN","message_redacted":"timed out after 30s","provider":"openai","model":"gpt-5.5-pro"}'
    run _validate_py "$payload"
    [ "$status" -eq 0 ]
}

@test "E0b: full envelope with all optional fields accepted" {
    payload='{"error_class":"BUDGET_EXHAUSTED","severity":"BLOCKER","message_redacted":"budget cap reached","provider":"anthropic","model":"claude-opus-4-7","retryable":false,"fallback_from":"claude-opus-4-7","fallback_to":"claude-sonnet-4-6","ts_utc":"2026-05-09T05:42:00Z"}'
    run _validate_py "$payload"
    [ "$status" -eq 0 ]
}

# -----------------------------------------------------------------------------
# E1-E5 — STRUCTURAL: missing required fields rejected
# -----------------------------------------------------------------------------

@test "E1: missing error_class rejected" {
    payload='{"severity":"WARN","message_redacted":"x","provider":"openai","model":"gpt-5.5-pro"}'
    run _validate_py "$payload"
    [ "$status" -eq 78 ]
}

@test "E2: missing severity rejected" {
    payload='{"error_class":"TIMEOUT","message_redacted":"x","provider":"openai","model":"gpt-5.5-pro"}'
    run _validate_py "$payload"
    [ "$status" -eq 78 ]
}

@test "E3: missing message_redacted rejected" {
    payload='{"error_class":"TIMEOUT","severity":"WARN","provider":"openai","model":"gpt-5.5-pro"}'
    run _validate_py "$payload"
    [ "$status" -eq 78 ]
}

@test "E4: missing provider rejected" {
    payload='{"error_class":"TIMEOUT","severity":"WARN","message_redacted":"x","model":"gpt-5.5-pro"}'
    run _validate_py "$payload"
    [ "$status" -eq 78 ]
}

@test "E5: missing model rejected" {
    payload='{"error_class":"TIMEOUT","severity":"WARN","message_redacted":"x","provider":"openai"}'
    run _validate_py "$payload"
    [ "$status" -eq 78 ]
}

# -----------------------------------------------------------------------------
# E6-E10 — TYPE: wrong-type values rejected
# -----------------------------------------------------------------------------

@test "E6: error_class as integer rejected" {
    payload='{"error_class":42,"severity":"WARN","message_redacted":"x","provider":"openai","model":"m"}'
    run _validate_py "$payload"
    [ "$status" -eq 78 ]
}

@test "E7: severity as array rejected" {
    payload='{"error_class":"TIMEOUT","severity":["WARN"],"message_redacted":"x","provider":"openai","model":"m"}'
    run _validate_py "$payload"
    [ "$status" -eq 78 ]
}

@test "E8: provider as null rejected" {
    payload='{"error_class":"TIMEOUT","severity":"WARN","message_redacted":"x","provider":null,"model":"m"}'
    run _validate_py "$payload"
    [ "$status" -eq 78 ]
}

@test "E9: retryable as string rejected" {
    payload='{"error_class":"TIMEOUT","severity":"WARN","message_redacted":"x","provider":"openai","model":"m","retryable":"yes"}'
    run _validate_py "$payload"
    [ "$status" -eq 78 ]
}

@test "E10: ts_utc as integer rejected (must be ISO-8601 string)" {
    payload='{"error_class":"TIMEOUT","severity":"WARN","message_redacted":"x","provider":"openai","model":"m","ts_utc":1715234567}'
    run _validate_py "$payload"
    [ "$status" -eq 78 ]
}

# -----------------------------------------------------------------------------
# E11-E13 — ENUM and LENGTH constraints
# -----------------------------------------------------------------------------

@test "E11: invalid error_class value (NOT_AN_ENUM) rejected" {
    payload='{"error_class":"DEFINITELY_NOT_AN_ENUM","severity":"WARN","message_redacted":"x","provider":"openai","model":"m"}'
    run _validate_py "$payload"
    [ "$status" -eq 78 ]
}

@test "E12: invalid severity (CRITICAL) rejected — must be WARN/ERROR/BLOCKER" {
    payload='{"error_class":"TIMEOUT","severity":"CRITICAL","message_redacted":"x","provider":"openai","model":"m"}'
    run _validate_py "$payload"
    [ "$status" -eq 78 ]
}

@test "E13: message_redacted > 8192 chars rejected" {
    _need_jq
    # BB iter-2 F2 (low): build the long string via Python (already a hard
    # dep) instead of `printf 'x%.0s' $(seq 1 8193)` which spawns a
    # subshell with 8193 args (ARG_MAX-adjacent on minimal containers).
    local long_msg
    long_msg="$("$PYTHON_BIN" -I -c 'print("x"*8193, end="")')"
    payload="$(jq -nc --arg m "$long_msg" '{error_class:"TIMEOUT",severity:"WARN",message_redacted:$m,provider:"openai",model:"m"}')"
    run _validate_py "$payload"
    [ "$status" -eq 78 ]
}

@test "E13b: message_redacted exactly 8192 chars accepted (boundary)" {
    _need_jq
    local at_cap
    at_cap="$("$PYTHON_BIN" -I -c 'print("x"*8192, end="")')"
    payload="$(jq -nc --arg m "$at_cap" '{error_class:"TIMEOUT",severity:"WARN",message_redacted:$m,provider:"openai",model:"m"}')"
    run _validate_py "$payload"
    [ "$status" -eq 0 ]
}

# -----------------------------------------------------------------------------
# E14-E16 — CONDITIONAL: UNKNOWN <-> original_exception coupling
# -----------------------------------------------------------------------------

@test "E14: error_class=UNKNOWN without original_exception rejected" {
    payload='{"error_class":"UNKNOWN","severity":"BLOCKER","message_redacted":"unmapped","provider":"openai","model":"m"}'
    run _validate_py "$payload"
    [ "$status" -eq 78 ]
}

@test "E15: error_class=UNKNOWN WITH original_exception accepted" {
    payload='{"error_class":"UNKNOWN","severity":"BLOCKER","message_redacted":"unmapped","provider":"openai","model":"m","original_exception":"Traceback (most recent call last):\n  File \"x.py\", line 1\n    foo()\n"}'
    run _validate_py "$payload"
    [ "$status" -eq 0 ]
}

@test "E16: typed error_class WITH original_exception rejected (only UNKNOWN may carry it)" {
    payload='{"error_class":"TIMEOUT","severity":"WARN","message_redacted":"x","provider":"openai","model":"m","original_exception":"some trace"}'
    run _validate_py "$payload"
    [ "$status" -eq 78 ]
}

# -----------------------------------------------------------------------------
# E17-E18 — CONDITIONAL: fallback_from <-> fallback_to coupling
# -----------------------------------------------------------------------------

@test "E17: fallback_from without fallback_to rejected" {
    payload='{"error_class":"TIMEOUT","severity":"WARN","message_redacted":"x","provider":"openai","model":"m","fallback_from":"gpt-5.5-pro"}'
    run _validate_py "$payload"
    [ "$status" -eq 78 ]
}

@test "E18: fallback_to without fallback_from rejected" {
    payload='{"error_class":"TIMEOUT","severity":"WARN","message_redacted":"x","provider":"openai","model":"m","fallback_to":"gpt-5.3-codex"}'
    run _validate_py "$payload"
    [ "$status" -eq 78 ]
}

@test "E18b: both fallback_from AND fallback_to accepted" {
    payload='{"error_class":"PROVIDER_OUTAGE","severity":"WARN","message_redacted":"503","provider":"openai","model":"gpt-5.5-pro","fallback_from":"gpt-5.5-pro","fallback_to":"gpt-5.3-codex"}'
    run _validate_py "$payload"
    [ "$status" -eq 0 ]
}

# -----------------------------------------------------------------------------
# E19-E20 — ADDITIONAL: extra fields rejected
# -----------------------------------------------------------------------------

@test "E19: unknown top-level field (foo) rejected" {
    payload='{"error_class":"TIMEOUT","severity":"WARN","message_redacted":"x","provider":"openai","model":"m","foo":"bar"}'
    run _validate_py "$payload"
    [ "$status" -eq 78 ]
}

@test "E20: prescriptive-rejection style (override:true) rejected" {
    # Defense-in-depth: an attacker who plants a bypass hint must still be
    # rejected by additionalProperties:false.
    payload='{"error_class":"TIMEOUT","severity":"WARN","message_redacted":"x","provider":"openai","model":"m","prescriptive_override":true}'
    run _validate_py "$payload"
    [ "$status" -eq 78 ]
}

# -----------------------------------------------------------------------------
# E21 — TAXONOMY COMPLETENESS: all 10 error_class values accepted
# -----------------------------------------------------------------------------

@test "E21: every enum value in the schema is accepted (read from schema, not hardcoded)" {
    _need_jq
    # BB iter-2 F1 (low): reads the enum from the schema at test time so
    # adding an 11th class can't silently bypass coverage. UNKNOWN is
    # handled separately because of the conditional original_exception
    # coupling — the loop skips it and the explicit case below covers it.
    local classes
    mapfile -t classes < <(jq -r '.properties.error_class.enum[]' "$SCHEMA")
    [ "${#classes[@]}" -ge 10 ] || {
        printf 'schema has fewer than 10 error_class values — taxonomy regression?\n' >&2
        return 1
    }
    local cls
    for cls in "${classes[@]}"; do
        if [[ "$cls" == "UNKNOWN" ]]; then
            continue   # covered explicitly below (requires original_exception)
        fi
        local payload
        payload="$(jq -nc --arg c "$cls" '{error_class:$c,severity:"WARN",message_redacted:"x",provider:"openai",model:"m"}')"
        run _validate_py "$payload"
        [ "$status" -eq 0 ] || {
            printf 'FAIL: error_class=%s (from schema enum) rejected, expected accepted\n' "$cls" >&2
            return 1
        }
    done
    # UNKNOWN separately (requires original_exception)
    payload='{"error_class":"UNKNOWN","severity":"BLOCKER","message_redacted":"x","provider":"openai","model":"m","original_exception":"trace"}'
    run _validate_py "$payload"
    [ "$status" -eq 0 ]
}

# -----------------------------------------------------------------------------
# B1-B3 — BASH TWIN: wrapper exit codes + JSON output
# -----------------------------------------------------------------------------

@test "B1: bash wrapper accepts valid envelope (exit 0)" {
    payload='{"error_class":"TIMEOUT","severity":"WARN","message_redacted":"x","provider":"openai","model":"gpt-5.5-pro"}'
    run _validate_sh "$payload"
    [ "$status" -eq 0 ]
}

@test "B2: bash wrapper rejects invalid envelope (exit 78)" {
    payload='{"error_class":"TIMEOUT"}'
    run _validate_sh "$payload"
    [ "$status" -eq 78 ]
}

@test "B3: bash wrapper --json output is parseable JSON (valid case)" {
    payload='{"error_class":"TIMEOUT","severity":"WARN","message_redacted":"x","provider":"openai","model":"m"}'
    local out="$WORK_DIR/payload.json"
    printf '%s' "$payload" > "$out"
    run "$VALIDATOR_SH" --input "$out" --json
    [ "$status" -eq 0 ]
    echo "$output" | "$PYTHON_BIN" -I -c 'import json,sys; d=json.loads(sys.stdin.read()); assert d["valid"] is True'
}

@test "B3b: bash wrapper --json with invalid input emits parseable error JSON" {
    payload='{"error_class":"BAD_ENUM","severity":"WARN","message_redacted":"x","provider":"openai","model":"m"}'
    local out="$WORK_DIR/payload.json"
    printf '%s' "$payload" > "$out"
    run "$VALIDATOR_SH" --input "$out" --json
    [ "$status" -eq 78 ]
    echo "$output" | "$PYTHON_BIN" -I -c 'import json,sys; d=json.loads(sys.stdin.read()); assert d["valid"] is False, "expected valid:false"; assert len(d["errors"]) >= 1'
}

# -----------------------------------------------------------------------------
# Integrity: schema itself is well-formed Draft 2020-12
# -----------------------------------------------------------------------------

@test "S0: schema is valid JSON" {
    "$PYTHON_BIN" -I -c "import json; json.load(open('$SCHEMA'))"
}

@test "S1: schema is well-formed Draft 2020-12" {
    "$PYTHON_BIN" -I -c "import json, jsonschema; jsonschema.Draft202012Validator.check_schema(json.load(open('$SCHEMA')))"
}

@test "S2: schema enumerates exactly 10 error_class values (taxonomy pin)" {
    local n
    n="$("$PYTHON_BIN" -I -c "import json; print(len(json.load(open('$SCHEMA'))['properties']['error_class']['enum']))")"
    [ "$n" -eq 10 ]
}
