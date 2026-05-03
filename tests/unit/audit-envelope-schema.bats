#!/usr/bin/env bats
# =============================================================================
# tests/unit/audit-envelope-schema.bats
#
# cycle-098 Sprint 1A — CC-11 (normative JSON Schema validated by ajv at
# write-time; jsonschema fallback per R15). Exercises positive and negative
# schema cases.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    AUDIT_ENVELOPE="$PROJECT_ROOT/.claude/scripts/audit-envelope.sh"
    SCHEMA="$PROJECT_ROOT/.claude/data/trajectory-schemas/agent-network-envelope.schema.json"

    [[ -f "$AUDIT_ENVELOPE" ]] || skip "audit-envelope.sh not present"
    [[ -f "$SCHEMA" ]] || skip "schema not present"

    TEST_DIR="$(mktemp -d)"

    # shellcheck disable=SC1090
    source "$AUDIT_ENVELOPE"
}

teardown() {
    if [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]]; then
        find "$TEST_DIR" -type f -delete 2>/dev/null || true
        rmdir "$TEST_DIR" 2>/dev/null || true
    fi
}

# -----------------------------------------------------------------------------
# Schema is itself well-formed
# -----------------------------------------------------------------------------
@test "schema: file is valid JSON" {
    run jq empty "$SCHEMA"
    [[ "$status" -eq 0 ]]
}

@test "schema: declares draft 2020-12" {
    local declared
    declared=$(jq -r '.["$schema"]' "$SCHEMA")
    [[ "$declared" == *"2020-12"* ]]
}

@test "schema: required fields per SDD §3.2.1" {
    # Sprint 1A allows signature/signing_key_id to be omitted (added by 1B).
    # Required: schema_version, primitive_id, event_type, ts_utc, prev_hash, payload.
    local required
    required=$(jq -r '.required[]' "$SCHEMA" | sort | tr '\n' ',')
    [[ "$required" == *"event_type"* ]]
    [[ "$required" == *"payload"* ]]
    [[ "$required" == *"prev_hash"* ]]
    [[ "$required" == *"primitive_id"* ]]
    [[ "$required" == *"schema_version"* ]]
    [[ "$required" == *"ts_utc"* ]]
}

@test "schema: primitive_id enum is L1..L7" {
    local enum_str
    enum_str=$(jq -r '.properties.primitive_id.enum | join(",")' "$SCHEMA")
    [[ "$enum_str" == "L1,L2,L3,L4,L5,L6,L7" ]]
}

@test "schema: payload allows additional properties (additive evolution per IMP-001)" {
    local addl
    addl=$(jq -r '.properties.payload.additionalProperties' "$SCHEMA")
    [[ "$addl" == "true" ]]
}

# -----------------------------------------------------------------------------
# Positive validation
# -----------------------------------------------------------------------------
@test "validate: well-formed envelope passes" {
    local LOG="$TEST_DIR/log.jsonl"
    run audit_emit L1 panel.bind '{"decision_id":"d-1"}' "$LOG"
    [[ "$status" -eq 0 ]]
    [[ -f "$LOG" ]]
    # Confirm one line, well-formed envelope JSON.
    [[ "$(wc -l < "$LOG")" -eq 1 ]]
    run jq -e '.schema_version and .primitive_id and .event_type and .ts_utc and .prev_hash and .payload' "$LOG"
    [[ "$status" -eq 0 ]]
}

@test "validate: schema_version follows semver" {
    local LOG="$TEST_DIR/log.jsonl"
    audit_emit L1 panel.bind '{"decision_id":"d-1"}' "$LOG"
    local sv
    sv=$(jq -r '.schema_version' "$LOG")
    [[ "$sv" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

@test "validate: ts_utc is microsecond-precision UTC ISO-8601" {
    local LOG="$TEST_DIR/log.jsonl"
    audit_emit L1 panel.bind '{"decision_id":"d-1"}' "$LOG"
    local ts
    ts=$(jq -r '.ts_utc' "$LOG")
    # YYYY-MM-DDTHH:MM:SS.uuuuuuZ
    [[ "$ts" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{6}Z$ ]]
}

# -----------------------------------------------------------------------------
# Negative validation: invalid envelopes must be rejected.
# We exercise the validator directly because audit_emit only produces
# well-formed envelopes by construction.
# -----------------------------------------------------------------------------
@test "validate: missing payload is rejected" {
    # Hand-crafted bad envelope — missing payload.
    local bad='{"schema_version":"1.0.0","primitive_id":"L1","event_type":"x","ts_utc":"2026-05-15T00:00:00.000000Z","prev_hash":"GENESIS"}'
    run _audit_validate_envelope "$bad"
    [[ "$status" -ne 0 ]]
}

@test "validate: invalid primitive_id is rejected" {
    local bad='{"schema_version":"1.0.0","primitive_id":"L99","event_type":"x","ts_utc":"2026-05-15T00:00:00.000000Z","prev_hash":"GENESIS","payload":{}}'
    run _audit_validate_envelope "$bad"
    [[ "$status" -ne 0 ]]
}

@test "validate: invalid prev_hash format is rejected (not GENESIS, not 64-hex)" {
    local bad='{"schema_version":"1.0.0","primitive_id":"L1","event_type":"x","ts_utc":"2026-05-15T00:00:00.000000Z","prev_hash":"abc","payload":{}}'
    run _audit_validate_envelope "$bad"
    [[ "$status" -ne 0 ]]
}

@test "validate: schema_version not semver is rejected" {
    local bad='{"schema_version":"v1","primitive_id":"L1","event_type":"x","ts_utc":"2026-05-15T00:00:00.000000Z","prev_hash":"GENESIS","payload":{}}'
    run _audit_validate_envelope "$bad"
    [[ "$status" -ne 0 ]]
}

# -----------------------------------------------------------------------------
# Sprint 1A scope marker: signature is OPTIONAL until 1B.
# -----------------------------------------------------------------------------
@test "validate: envelope without signature is accepted (Sprint 1A)" {
    local ok='{"schema_version":"1.0.0","primitive_id":"L1","event_type":"x","ts_utc":"2026-05-15T00:00:00.000000Z","prev_hash":"GENESIS","payload":{}}'
    run _audit_validate_envelope "$ok"
    [[ "$status" -eq 0 ]]
}
