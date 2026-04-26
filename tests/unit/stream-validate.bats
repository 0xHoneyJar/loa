#!/usr/bin/env bats
# =============================================================================
# Tests for .claude/scripts/stream-validate.sh — cycle-005 L2
# Validates Signal / Verdict / Artifact / Intent / Operator-Model JSON rows
# against schemas at .claude/schemas/<slug>.schema.json.
#
# Two execution paths:
#   * python3 + jsonschema → full Draft-07 validation
#   * fallback             → required-field presence only (jq)
# Tests cover both paths where they differ; full-schema-only assertions
# skip when jsonschema is unavailable.
# =============================================================================

setup_file() {
    # Bridgebuilder F-001: clear skip when external tooling is missing.
    # stream-validate.sh always needs jq (final-payload sanity-check). The
    # python3+jsonschema path is optional and gated separately at test scope.
    command -v jq >/dev/null 2>&1 || skip "jq required (the script under test depends on it)"
}

setup() {
    TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
    export PROJECT_ROOT
    SCRIPT="$PROJECT_ROOT/.claude/scripts/stream-validate.sh"
    SCHEMA_DIR="$PROJECT_ROOT/.claude/schemas"

    HAS_JSONSCHEMA=0
    if command -v python3 >/dev/null 2>&1 && python3 -c "import jsonschema" >/dev/null 2>&1; then
        HAS_JSONSCHEMA=1
    fi
}

# -----------------------------------------------------------------------------
# Help / usage
# -----------------------------------------------------------------------------
@test "stream-validate: zero args -> usage on stderr, exit 2" {
    run "$SCRIPT"
    [ "$status" -eq 2 ]
}

@test "stream-validate: only stream type -> usage, exit 2" {
    run "$SCRIPT" Signal
    [ "$status" -eq 2 ]
}

# -----------------------------------------------------------------------------
# Stream type recognition (all 5)
# -----------------------------------------------------------------------------
@test "stream-validate: unknown stream type -> exit 2" {
    run "$SCRIPT" Bogus '{"foo":"bar"}'
    [ "$status" -eq 2 ]
    [[ "$output" == *"unknown stream_type"* ]]
}

@test "stream-validate: each canonical type maps to its schema slug" {
    # Map enforced in schema_slug() inside the script: case-sensitive 1:1 mapping.
    for t in Signal Verdict Artifact Intent Operator-Model; do
        local slug
        case "$t" in
            Operator-Model) slug="operator-model" ;;
            *)              slug="$(echo "$t" | tr '[:upper:]' '[:lower:]')" ;;
        esac
        [ -f "$SCHEMA_DIR/${slug}.schema.json" ]
    done
}

# -----------------------------------------------------------------------------
# Valid happy paths (every stream type)
# -----------------------------------------------------------------------------
@test "stream-validate: Signal with all required fields -> exit 0" {
    local payload='{"stream_type":"Signal","schema_version":"1.0.0","timestamp":"2026-04-26T12:00:00Z","source":"test-suite","observation":"unit-test signal"}'
    run "$SCRIPT" Signal "$payload"
    [ "$status" -eq 0 ]
}

@test "stream-validate: Verdict with all required fields -> exit 0" {
    local payload='{"stream_type":"Verdict","schema_version":"1.0.0","timestamp":"2026-04-26T12:00:00Z","source":"test-suite","verdict":"all checks passed"}'
    run "$SCRIPT" Verdict "$payload"
    [ "$status" -eq 0 ]
}

@test "stream-validate: Artifact required fields -> exit 0" {
    # Bridgebuilder iter-2 F-003: assert exit 0 strictly. Schema's required[]
    # is ["stream_type","schema_version","timestamp","path"] — payload covers
    # exactly those. Permissive escapes were masking real regressions.
    local payload='{"stream_type":"Artifact","schema_version":"1.0.0","timestamp":"2026-04-26T12:00:00Z","path":"/tmp/artifact"}'
    run "$SCRIPT" Artifact "$payload"
    [ "$status" -eq 0 ]
}

@test "stream-validate: Intent required fields -> exit 0" {
    # Schema required: stream_type, schema_version, timestamp, intent
    local payload='{"stream_type":"Intent","schema_version":"1.0.0","timestamp":"2026-04-26T12:00:00Z","intent":"run probes"}'
    run "$SCRIPT" Intent "$payload"
    [ "$status" -eq 0 ]
}

@test "stream-validate: Operator-Model required fields -> exit 0" {
    # Schema required: stream_type, schema_version, timestamp
    local payload='{"stream_type":"Operator-Model","schema_version":"1.0.0","timestamp":"2026-04-26T12:00:00Z"}'
    run "$SCRIPT" Operator-Model "$payload"
    [ "$status" -eq 0 ]
}

@test "stream-validate: Artifact missing 'path' -> exit 1" {
    local payload='{"stream_type":"Artifact","schema_version":"1.0.0","timestamp":"2026-04-26T12:00:00Z"}'
    run "$SCRIPT" Artifact "$payload"
    [ "$status" -eq 1 ]
}

@test "stream-validate: Intent missing 'intent' -> exit 1" {
    local payload='{"stream_type":"Intent","schema_version":"1.0.0","timestamp":"2026-04-26T12:00:00Z"}'
    run "$SCRIPT" Intent "$payload"
    [ "$status" -eq 1 ]
}

# -----------------------------------------------------------------------------
# Required-field rejection (works in both jsonschema and fallback paths)
# -----------------------------------------------------------------------------
@test "stream-validate: Signal missing 'observation' -> exit 1" {
    local payload='{"stream_type":"Signal","schema_version":"1.0.0","timestamp":"2026-04-26T12:00:00Z","source":"test"}'
    run "$SCRIPT" Signal "$payload"
    [ "$status" -eq 1 ]
    [[ "$output" == *"INVALID"* || "$output" == *"observation"* ]]
}

@test "stream-validate: Verdict missing 'verdict' -> exit 1" {
    local payload='{"stream_type":"Verdict","schema_version":"1.0.0","timestamp":"2026-04-26T12:00:00Z","source":"test"}'
    run "$SCRIPT" Verdict "$payload"
    [ "$status" -eq 1 ]
}

# -----------------------------------------------------------------------------
# Stream type mismatch / invalid JSON
# -----------------------------------------------------------------------------
@test "stream-validate: payload declares wrong stream_type -> exit 1" {
    local payload='{"stream_type":"Verdict","schema_version":"1.0.0","timestamp":"2026-04-26T12:00:00Z","source":"x","verdict":"y"}'
    run "$SCRIPT" Signal "$payload"
    [ "$status" -eq 1 ]
    [[ "$output" == *"declares stream_type"* ]]
}

@test "stream-validate: invalid JSON -> exit 1 with parser hint" {
    run "$SCRIPT" Signal 'not-json{'
    [ "$status" -eq 1 ]
    [[ "$output" == *"not valid JSON"* ]]
}

# -----------------------------------------------------------------------------
# Input modes — --file and stdin
# -----------------------------------------------------------------------------
@test "stream-validate: --file mode reads JSON from path" {
    local f="$BATS_TEST_TMPDIR/sig.json"
    printf '%s' '{"stream_type":"Signal","schema_version":"1.0.0","timestamp":"2026-04-26T12:00:00Z","source":"test","observation":"file-mode"}' > "$f"
    run "$SCRIPT" Signal --file "$f"
    [ "$status" -eq 0 ]
}

@test "stream-validate: --file with missing path argument -> exit 2" {
    run "$SCRIPT" Signal --file
    [ "$status" -eq 2 ]
}

@test "stream-validate: stdin (- arg) reads JSON from stdin" {
    local payload='{"stream_type":"Signal","schema_version":"1.0.0","timestamp":"2026-04-26T12:00:00Z","source":"test","observation":"stdin-mode"}'
    run bash -c "echo '$payload' | '$SCRIPT' Signal -"
    [ "$status" -eq 0 ]
}

# -----------------------------------------------------------------------------
# Full-schema-only checks. Note: jsonschema's Draft7Validator does NOT validate
# the `format` keyword by default (format is informational unless a
# FormatChecker is passed explicitly), so we don't assert on bad-timestamp
# strings here. The schema's `pattern` keyword IS validated, so the
# semver-pattern test below is real.
# -----------------------------------------------------------------------------
@test "stream-validate: schema_version not semver -> exit 1 (jsonschema only)" {
    [ "$HAS_JSONSCHEMA" = 1 ] || skip "python3 jsonschema unavailable; fallback path doesn't enforce pattern"
    local payload='{"stream_type":"Signal","schema_version":"vNotSemver","timestamp":"2026-04-26T12:00:00Z","source":"test","observation":"x"}'
    run "$SCRIPT" Signal "$payload"
    [ "$status" -eq 1 ]
}
