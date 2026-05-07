#!/usr/bin/env bats
# =============================================================================
# tests/unit/trust-events-schemas.bats
#
# cycle-098 Sprint 4A — schema-registry tests for L4 graduated-trust events.
#
# Pins the schema files at .claude/data/trajectory-schemas/trust-events/ and
# verifies each is valid JSON Schema 2020-12 and validates a representative
# happy-path payload. Defense for #708 F-007 pattern (per-event-type schema
# registry + drift-resistance).
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    SCHEMA_DIR="$PROJECT_ROOT/.claude/data/trajectory-schemas/trust-events"

    [[ -d "$SCHEMA_DIR" ]] || skip "trust-events schema dir missing"
}

@test "trust-events: schema directory contains expected event schemas" {
    for f in trust-query trust-grant trust-auto-drop trust-force-grant trust-auto-raise-eligible trust-disable; do
        [[ -f "$SCHEMA_DIR/${f}.payload.schema.json" ]] || {
            echo "missing schema: ${f}.payload.schema.json"
            return 1
        }
    done
}

@test "trust-events: trust-response.schema.json exists and is valid JSON" {
    local f="$SCHEMA_DIR/trust-response.schema.json"
    [[ -f "$f" ]]
    jq empty "$f"
}

@test "trust-events: every schema is valid JSON" {
    for f in "$SCHEMA_DIR"/*.json; do
        jq empty "$f" || {
            echo "not valid JSON: $f"
            return 1
        }
    done
}

@test "trust-events: every payload schema declares draft 2020-12" {
    for f in "$SCHEMA_DIR"/*.payload.schema.json; do
        local declared
        declared="$(jq -r '."$schema"' "$f")"
        [[ "$declared" == "https://json-schema.org/draft/2020-12/schema" ]] || {
            echo "wrong \$schema in $f: $declared"
            return 1
        }
    done
}

@test "trust-events: every schema sets additionalProperties=false (typo guard)" {
    for f in "$SCHEMA_DIR"/*.json; do
        # NOTE: jq's `//` triggers on `false` AND null, so use `has` + raw value.
        local present v
        present="$(jq -r 'has("additionalProperties") | tostring' "$f")"
        [[ "$present" == "true" ]] || {
            echo "additionalProperties missing in $f"
            return 1
        }
        v="$(jq -r '.additionalProperties | tostring' "$f")"
        [[ "$v" == "false" ]] || {
            echo "additionalProperties not false in $f (got $v)"
            return 1
        }
    done
}

@test "trust-events: trust-grant payload validates a happy-path sample" {
    if ! command -v ajv >/dev/null 2>&1; then
        skip "ajv not installed"
    fi
    local sample
    sample="$(jq -nc '{
        scope: "flatline",
        capability: "merge_main",
        actor: "deep-name",
        from_tier: "T0",
        to_tier: "T1",
        operator: "deep-name",
        reason: "validated initial alignment"
    }')"
    local sample_file
    sample_file="$(mktemp)"
    printf '%s' "$sample" > "$sample_file"
    run ajv validate -s "$SCHEMA_DIR/trust-grant.payload.schema.json" -d "$sample_file" --strict=false
    rm -f "$sample_file"
    [[ "$status" -eq 0 ]] || {
        echo "ajv output: $output"
        return 1
    }
}

@test "trust-events: trust-auto-drop payload validates a happy-path sample" {
    if ! command -v ajv >/dev/null 2>&1; then
        skip "ajv not installed"
    fi
    local sample sample_file
    sample="$(jq -nc '{
        scope: "flatline",
        capability: "merge_main",
        actor: "deep-name",
        from_tier: "T2",
        to_tier: "T1",
        decision_id: "panel-decision-2026-05-07-abc123",
        reason: "operator override on panel decision",
        cooldown_until: "2026-05-14T10:00:00.000Z",
        cooldown_seconds: 604800
    }')"
    sample_file="$(mktemp)"
    printf '%s' "$sample" > "$sample_file"
    run ajv validate -s "$SCHEMA_DIR/trust-auto-drop.payload.schema.json" -d "$sample_file" --strict=false
    rm -f "$sample_file"
    [[ "$status" -eq 0 ]] || {
        echo "ajv output: $output"
        return 1
    }
}

@test "trust-events: trust-force-grant payload requires cooldown_remaining_seconds_at_grant" {
    if ! command -v ajv >/dev/null 2>&1; then
        skip "ajv not installed"
    fi
    local sample sample_file
    sample="$(jq -nc '{
        scope: "flatline",
        capability: "merge_main",
        actor: "deep-name",
        from_tier: "T1",
        to_tier: "T2",
        operator: "deep-name",
        reason: "emergency override"
    }')"
    sample_file="$(mktemp)"
    printf '%s' "$sample" > "$sample_file"
    run ajv validate -s "$SCHEMA_DIR/trust-force-grant.payload.schema.json" -d "$sample_file" --strict=false
    rm -f "$sample_file"
    [[ "$status" -ne 0 ]] || {
        echo "expected validation failure (missing cooldown_remaining_seconds_at_grant)"
        return 1
    }
}

@test "trust-events: trust-auto-raise-eligible stub_outcome enum locked to eligibility_required" {
    local schema
    schema="$SCHEMA_DIR/trust-auto-raise-eligible.payload.schema.json"
    local enum_json
    enum_json="$(jq -c '.properties.stub_outcome.enum' "$schema")"
    [[ "$enum_json" == '["eligibility_required"]' ]]
}

@test "trust-events: trust-disable payload requires operator+reason+sealed_at" {
    if ! command -v ajv >/dev/null 2>&1; then
        skip "ajv not installed"
    fi
    local sample sample_file
    sample="$(jq -nc '{
        operator: "deep-name",
        reason: "rotating ledger",
        sealed_at: "2026-05-07T12:00:00.000Z"
    }')"
    sample_file="$(mktemp)"
    printf '%s' "$sample" > "$sample_file"
    run ajv validate -s "$SCHEMA_DIR/trust-disable.payload.schema.json" -d "$sample_file" --strict=false
    rm -f "$sample_file"
    [[ "$status" -eq 0 ]] || {
        echo "ajv output: $output"
        return 1
    }
}
