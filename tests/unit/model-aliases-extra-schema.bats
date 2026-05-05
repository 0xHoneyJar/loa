#!/usr/bin/env bats
# =============================================================================
# tests/unit/model-aliases-extra-schema.bats
#
# cycle-099 Sprint 2A (T2.1) — JSON Schema contract pin for the
# `.claude/data/trajectory-schemas/model-aliases-extra.schema.json` file
# (DD-5 path-locked) and the validator helper at
# `.claude/scripts/lib/validate-model-aliases-extra.{py,sh}`.
#
# Closes AC-S2.1 partial (schema correctness; loader integration is Sprint 2B).
#
# Test taxonomy:
#   E0      POSITIVE CONTROL: SDD §4.2.1 UC-1 valid example loads cleanly
#   E1-E5   STRUCTURAL: missing required fields rejected
#   E6-E10  TYPE: wrong-type values rejected
#   E11-E15 ENUM: invalid enum values rejected
#   E16-E18 CONSTRAINTS: pattern / minLength / maxLength / range rejected
#   E19-E22 SECURITY: forbidden auth field, glob/wildcard ids, unknown providers
#   E23-E25 PERMISSIONS: FR-1.4 acknowledge_permissions_baseline gate
#   B1-B3   BASH TWIN: wrapper API surface
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    SCHEMA="$PROJECT_ROOT/.claude/data/trajectory-schemas/model-aliases-extra.schema.json"
    VALIDATOR_PY="$PROJECT_ROOT/.claude/scripts/lib/validate-model-aliases-extra.py"
    VALIDATOR_SH="$PROJECT_ROOT/.claude/scripts/lib/validate-model-aliases-extra.sh"

    # BB iter-2 F9: HARD-FAIL on the files this PR ships (schema +
    # validator). Skip-on-missing was masking CI regressions where a refactor
    # could rename/move these and silently skip every test in the file.
    [[ -f "$SCHEMA" ]] || {
        printf 'FATAL: schema not present at %s — Sprint 2A invariant broken\n' "$SCHEMA" >&2
        return 1
    }
    [[ -f "$VALIDATOR_PY" ]] || {
        printf 'FATAL: Python validator not present at %s — Sprint 2A invariant broken\n' "$VALIDATOR_PY" >&2
        return 1
    }
    [[ -f "$VALIDATOR_SH" ]] || {
        printf 'FATAL: bash wrapper not present at %s — Sprint 2A invariant broken\n' "$VALIDATOR_SH" >&2
        return 1
    }

    if [[ -x "$PROJECT_ROOT/.venv/bin/python" ]]; then
        PYTHON_BIN="$PROJECT_ROOT/.venv/bin/python"
    else
        PYTHON_BIN="${PYTHON_BIN:-python3}"
    fi
    # Skip-on-missing for OPTIONAL deps (jsonschema/pyyaml may not be in
    # ambient python3; cheval venv is preferred). Operators running locally
    # without venv can still skip cleanly.
    "$PYTHON_BIN" -c "import jsonschema, yaml" 2>/dev/null \
        || skip "jsonschema + pyyaml not available in $PYTHON_BIN"

    WORK_DIR="$(mktemp -d)"
}

teardown() {
    if [[ -n "${WORK_DIR:-}" ]] && [[ -d "$WORK_DIR" ]]; then
        rm -rf "$WORK_DIR"
    fi
    return 0
}

# BB iter-1 F4 / unused-helpers: helpers `_run_validator`, `_run_validator_verbose`,
# `_write_config` were defined but never used (every test inlined `run` and
# heredoc-write). Removed to avoid drift.

# ---------------------------------------------------------------------------
# E0 POSITIVE CONTROL — SDD §4.2.1 UC-1 fixture
# ---------------------------------------------------------------------------

@test "E0 positive control: UC-1 (operator adopts gpt-5.7-pro) loads cleanly" {
    cat > "$WORK_DIR/uc1.yaml" <<'EOF'
model_aliases_extra:
  schema_version: "1.0.0"
  entries:
    - id: gpt-5.7-pro
      provider: openai
      api_id: gpt-5.7-pro
      endpoint_family: responses
      capabilities: [chat, tools, function_calling, code]
      context_window: 256000
      pricing:
        input_per_mtok: 40000000
        output_per_mtok: 200000000
      acknowledge_permissions_baseline: true
EOF
    run "$VALIDATOR_PY" --config "$WORK_DIR/uc1.yaml"
    [[ "$status" -eq 0 ]] || {
        printf 'expected status=0; got=%d output=%s\n' "$status" "$output" >&2
        return 1
    }
}

# ---------------------------------------------------------------------------
# Vacuous — config missing OR block absent → vacuous success
# ---------------------------------------------------------------------------

@test "V1 absent config file → vacuous success (operator hasn't created .loa.config.yaml)" {
    run "$VALIDATOR_PY" --config "$WORK_DIR/nonexistent.yaml"
    [[ "$status" -eq 0 ]]
}

@test "V2 config file present without model_aliases_extra → vacuous success" {
    cat > "$WORK_DIR/no-block.yaml" <<'EOF'
hounfour:
  flatline_routing: false
ride:
  depth: medium
EOF
    run "$VALIDATOR_PY" --config "$WORK_DIR/no-block.yaml"
    [[ "$status" -eq 0 ]]
}

# ---------------------------------------------------------------------------
# E1-E5 STRUCTURAL — missing required fields
# ---------------------------------------------------------------------------

@test "E1 reject: missing schema_version" {
    cat > "$WORK_DIR/e1.yaml" <<'EOF'
model_aliases_extra:
  entries:
    - id: foo
      provider: openai
      api_id: foo
      capabilities: [chat]
      context_window: 128000
      pricing: {input_per_mtok: 100, output_per_mtok: 200}
      acknowledge_permissions_baseline: true
EOF
    run "$VALIDATOR_PY" --config "$WORK_DIR/e1.yaml" --quiet
    [[ "$status" -eq 78 ]]
}

@test "E2 reject: entry missing required 'id'" {
    cat > "$WORK_DIR/e2.yaml" <<'EOF'
model_aliases_extra:
  schema_version: "1.0.0"
  entries:
    - provider: openai
      api_id: foo
      capabilities: [chat]
      context_window: 128000
      pricing: {input_per_mtok: 100, output_per_mtok: 200}
      acknowledge_permissions_baseline: true
EOF
    run "$VALIDATOR_PY" --config "$WORK_DIR/e2.yaml" --quiet
    [[ "$status" -eq 78 ]]
}

@test "E3 reject: entry missing required 'provider'" {
    cat > "$WORK_DIR/e3.yaml" <<'EOF'
model_aliases_extra:
  schema_version: "1.0.0"
  entries:
    - id: foo
      api_id: foo
      capabilities: [chat]
      context_window: 128000
      pricing: {input_per_mtok: 100, output_per_mtok: 200}
      acknowledge_permissions_baseline: true
EOF
    run "$VALIDATOR_PY" --config "$WORK_DIR/e3.yaml" --quiet
    [[ "$status" -eq 78 ]]
}

@test "E4 reject: entry missing required 'pricing'" {
    cat > "$WORK_DIR/e4.yaml" <<'EOF'
model_aliases_extra:
  schema_version: "1.0.0"
  entries:
    - id: foo
      provider: openai
      api_id: foo
      capabilities: [chat]
      context_window: 128000
      acknowledge_permissions_baseline: true
EOF
    run "$VALIDATOR_PY" --config "$WORK_DIR/e4.yaml" --quiet
    [[ "$status" -eq 78 ]]
}

@test "E5 reject: pricing missing required input_per_mtok" {
    cat > "$WORK_DIR/e5.yaml" <<'EOF'
model_aliases_extra:
  schema_version: "1.0.0"
  entries:
    - id: foo
      provider: openai
      api_id: foo
      capabilities: [chat]
      context_window: 128000
      pricing: {output_per_mtok: 200}
      acknowledge_permissions_baseline: true
EOF
    run "$VALIDATOR_PY" --config "$WORK_DIR/e5.yaml" --quiet
    [[ "$status" -eq 78 ]]
}

# ---------------------------------------------------------------------------
# E6-E10 TYPE — wrong-type values
# ---------------------------------------------------------------------------

@test "E6 reject: schema_version wrong const value" {
    cat > "$WORK_DIR/e6.yaml" <<'EOF'
model_aliases_extra:
  schema_version: "2.0.0"
  entries: []
EOF
    run "$VALIDATOR_PY" --config "$WORK_DIR/e6.yaml" --quiet
    [[ "$status" -eq 78 ]]
}

@test "E7 reject: context_window as string" {
    cat > "$WORK_DIR/e7.yaml" <<'EOF'
model_aliases_extra:
  schema_version: "1.0.0"
  entries:
    - id: foo
      provider: openai
      api_id: foo
      capabilities: [chat]
      context_window: "128000"
      pricing: {input_per_mtok: 100, output_per_mtok: 200}
      acknowledge_permissions_baseline: true
EOF
    run "$VALIDATOR_PY" --config "$WORK_DIR/e7.yaml" --quiet
    [[ "$status" -eq 78 ]]
}

@test "E8 reject: capabilities not an array" {
    cat > "$WORK_DIR/e8.yaml" <<'EOF'
model_aliases_extra:
  schema_version: "1.0.0"
  entries:
    - id: foo
      provider: openai
      api_id: foo
      capabilities: "chat"
      context_window: 128000
      pricing: {input_per_mtok: 100, output_per_mtok: 200}
      acknowledge_permissions_baseline: true
EOF
    run "$VALIDATOR_PY" --config "$WORK_DIR/e8.yaml" --quiet
    [[ "$status" -eq 78 ]]
}

@test "E9 reject: pricing.input_per_mtok as float" {
    cat > "$WORK_DIR/e9.yaml" <<'EOF'
model_aliases_extra:
  schema_version: "1.0.0"
  entries:
    - id: foo
      provider: openai
      api_id: foo
      capabilities: [chat]
      context_window: 128000
      pricing: {input_per_mtok: 100.5, output_per_mtok: 200}
      acknowledge_permissions_baseline: true
EOF
    run "$VALIDATOR_PY" --config "$WORK_DIR/e9.yaml" --quiet
    [[ "$status" -eq 78 ]]
}

@test "E10 reject: capabilities empty array (minItems: 1)" {
    cat > "$WORK_DIR/e10.yaml" <<'EOF'
model_aliases_extra:
  schema_version: "1.0.0"
  entries:
    - id: foo
      provider: openai
      api_id: foo
      capabilities: []
      context_window: 128000
      pricing: {input_per_mtok: 100, output_per_mtok: 200}
      acknowledge_permissions_baseline: true
EOF
    run "$VALIDATOR_PY" --config "$WORK_DIR/e10.yaml" --quiet
    [[ "$status" -eq 78 ]]
}

# ---------------------------------------------------------------------------
# E11-E15 ENUM — invalid enum values
# ---------------------------------------------------------------------------

@test "E11 reject: unknown provider 'azure'" {
    cat > "$WORK_DIR/e11.yaml" <<'EOF'
model_aliases_extra:
  schema_version: "1.0.0"
  entries:
    - id: foo
      provider: azure
      api_id: foo
      capabilities: [chat]
      context_window: 128000
      pricing: {input_per_mtok: 100, output_per_mtok: 200}
      acknowledge_permissions_baseline: true
EOF
    run "$VALIDATOR_PY" --config "$WORK_DIR/e11.yaml" --quiet
    [[ "$status" -eq 78 ]]
}

@test "E12 reject: invalid endpoint_family" {
    cat > "$WORK_DIR/e12.yaml" <<'EOF'
model_aliases_extra:
  schema_version: "1.0.0"
  entries:
    - id: foo
      provider: openai
      api_id: foo
      endpoint_family: completions
      capabilities: [chat]
      context_window: 128000
      pricing: {input_per_mtok: 100, output_per_mtok: 200}
      acknowledge_permissions_baseline: true
EOF
    run "$VALIDATOR_PY" --config "$WORK_DIR/e12.yaml" --quiet
    [[ "$status" -eq 78 ]]
}

@test "E13 reject: unknown capability 'image_generation'" {
    cat > "$WORK_DIR/e13.yaml" <<'EOF'
model_aliases_extra:
  schema_version: "1.0.0"
  entries:
    - id: foo
      provider: openai
      api_id: foo
      capabilities: [chat, image_generation]
      context_window: 128000
      pricing: {input_per_mtok: 100, output_per_mtok: 200}
      acknowledge_permissions_baseline: true
EOF
    run "$VALIDATOR_PY" --config "$WORK_DIR/e13.yaml" --quiet
    [[ "$status" -eq 78 ]]
}

@test "E14 reject: invalid token_param" {
    cat > "$WORK_DIR/e14.yaml" <<'EOF'
model_aliases_extra:
  schema_version: "1.0.0"
  entries:
    - id: foo
      provider: openai
      api_id: foo
      token_param: max_output_tokens
      capabilities: [chat]
      context_window: 128000
      pricing: {input_per_mtok: 100, output_per_mtok: 200}
      acknowledge_permissions_baseline: true
EOF
    run "$VALIDATOR_PY" --config "$WORK_DIR/e14.yaml" --quiet
    [[ "$status" -eq 78 ]]
}

@test "E15 accept: all 4 valid providers + all valid capabilities + all valid endpoint_families" {
    cat > "$WORK_DIR/e15.yaml" <<'EOF'
model_aliases_extra:
  schema_version: "1.0.0"
  entries:
    - id: m-openai
      provider: openai
      api_id: m-openai
      endpoint_family: chat
      capabilities: [chat, tools, function_calling, code, thinking_traces, deep_research]
      context_window: 128000
      token_param: max_tokens
      pricing: {input_per_mtok: 100, output_per_mtok: 200}
      acknowledge_permissions_baseline: true
    - id: m-anthropic
      provider: anthropic
      api_id: m-anthropic
      endpoint_family: messages
      capabilities: [chat]
      context_window: 200000
      token_param: max_completion_tokens
      pricing: {input_per_mtok: 100, output_per_mtok: 200}
      acknowledge_permissions_baseline: true
    - id: m-google
      provider: google
      api_id: m-google
      endpoint_family: responses
      capabilities: [chat]
      context_window: 1000000
      pricing: {input_per_mtok: 100, output_per_mtok: 200}
      acknowledge_permissions_baseline: true
    - id: m-bedrock
      provider: bedrock
      api_id: m-bedrock
      endpoint_family: converse
      capabilities: [chat]
      context_window: 200000
      pricing: {input_per_mtok: 100, output_per_mtok: 200}
      acknowledge_permissions_baseline: true
EOF
    run "$VALIDATOR_PY" --config "$WORK_DIR/e15.yaml"
    [[ "$status" -eq 0 ]]
}

# ---------------------------------------------------------------------------
# E16-E18 CONSTRAINTS — pattern / range
# ---------------------------------------------------------------------------

@test "E16 reject: id pattern violation (shell metachar)" {
    cat > "$WORK_DIR/e16.yaml" <<'EOF'
model_aliases_extra:
  schema_version: "1.0.0"
  entries:
    - id: "foo;bar"
      provider: openai
      api_id: foo
      capabilities: [chat]
      context_window: 128000
      pricing: {input_per_mtok: 100, output_per_mtok: 200}
      acknowledge_permissions_baseline: true
EOF
    run "$VALIDATOR_PY" --config "$WORK_DIR/e16.yaml" --quiet
    [[ "$status" -eq 78 ]]
}

@test "E16b reject: id with path separator" {
    cat > "$WORK_DIR/e16b.yaml" <<'EOF'
model_aliases_extra:
  schema_version: "1.0.0"
  entries:
    - id: "foo/bar"
      provider: openai
      api_id: foo
      capabilities: [chat]
      context_window: 128000
      pricing: {input_per_mtok: 100, output_per_mtok: 200}
      acknowledge_permissions_baseline: true
EOF
    run "$VALIDATOR_PY" --config "$WORK_DIR/e16b.yaml" --quiet
    [[ "$status" -eq 78 ]]
}

@test "E16c reject: id with whitespace" {
    cat > "$WORK_DIR/e16c.yaml" <<'EOF'
model_aliases_extra:
  schema_version: "1.0.0"
  entries:
    - id: "foo bar"
      provider: openai
      api_id: foo
      capabilities: [chat]
      context_window: 128000
      pricing: {input_per_mtok: 100, output_per_mtok: 200}
      acknowledge_permissions_baseline: true
EOF
    run "$VALIDATOR_PY" --config "$WORK_DIR/e16c.yaml" --quiet
    [[ "$status" -eq 78 ]]
}

@test "E17 reject: context_window below minimum (1024)" {
    cat > "$WORK_DIR/e17.yaml" <<'EOF'
model_aliases_extra:
  schema_version: "1.0.0"
  entries:
    - id: foo
      provider: openai
      api_id: foo
      capabilities: [chat]
      context_window: 1023
      pricing: {input_per_mtok: 100, output_per_mtok: 200}
      acknowledge_permissions_baseline: true
EOF
    run "$VALIDATOR_PY" --config "$WORK_DIR/e17.yaml" --quiet
    [[ "$status" -eq 78 ]]
}

@test "E17b reject: context_window above maximum (10000000)" {
    cat > "$WORK_DIR/e17b.yaml" <<'EOF'
model_aliases_extra:
  schema_version: "1.0.0"
  entries:
    - id: foo
      provider: openai
      api_id: foo
      capabilities: [chat]
      context_window: 10000001
      pricing: {input_per_mtok: 100, output_per_mtok: 200}
      acknowledge_permissions_baseline: true
EOF
    run "$VALIDATOR_PY" --config "$WORK_DIR/e17b.yaml" --quiet
    [[ "$status" -eq 78 ]]
}

@test "E18 reject: id below minLength (2)" {
    cat > "$WORK_DIR/e18.yaml" <<'EOF'
model_aliases_extra:
  schema_version: "1.0.0"
  entries:
    - id: "x"
      provider: openai
      api_id: foo
      capabilities: [chat]
      context_window: 128000
      pricing: {input_per_mtok: 100, output_per_mtok: 200}
      acknowledge_permissions_baseline: true
EOF
    run "$VALIDATOR_PY" --config "$WORK_DIR/e18.yaml" --quiet
    [[ "$status" -eq 78 ]]
}

# ---------------------------------------------------------------------------
# E19-E22 SECURITY — auth field forbidden + glob ids + unknown top fields
# ---------------------------------------------------------------------------

@test "E19 reject: auth field present in entry (NFR-Sec-5)" {
    cat > "$WORK_DIR/e19.yaml" <<'EOF'
model_aliases_extra:
  schema_version: "1.0.0"
  entries:
    - id: foo
      provider: openai
      api_id: foo
      auth: {api_key: "sk-evil"}
      capabilities: [chat]
      context_window: 128000
      pricing: {input_per_mtok: 100, output_per_mtok: 200}
      acknowledge_permissions_baseline: true
EOF
    run "$VALIDATOR_PY" --config "$WORK_DIR/e19.yaml" --quiet
    [[ "$status" -eq 78 ]]
}

@test "E20 reject: id with glob '*' (cycle-099 sprint-1E.c.3.c host wildcard pattern)" {
    cat > "$WORK_DIR/e20.yaml" <<'EOF'
model_aliases_extra:
  schema_version: "1.0.0"
  entries:
    - id: "*"
      provider: openai
      api_id: foo
      capabilities: [chat]
      context_window: 128000
      pricing: {input_per_mtok: 100, output_per_mtok: 200}
      acknowledge_permissions_baseline: true
EOF
    run "$VALIDATOR_PY" --config "$WORK_DIR/e20.yaml" --quiet
    [[ "$status" -eq 78 ]]
}

@test "E21 reject: unknown property at top-level (additionalProperties: false)" {
    cat > "$WORK_DIR/e21.yaml" <<'EOF'
model_aliases_extra:
  schema_version: "1.0.0"
  entries: []
  unknown_field: "should fail"
EOF
    run "$VALIDATOR_PY" --config "$WORK_DIR/e21.yaml" --quiet
    [[ "$status" -eq 78 ]]
}

@test "E22 reject: unknown property in ModelExtra (additionalProperties: false)" {
    cat > "$WORK_DIR/e22.yaml" <<'EOF'
model_aliases_extra:
  schema_version: "1.0.0"
  entries:
    - id: foo
      provider: openai
      api_id: foo
      capabilities: [chat]
      context_window: 128000
      pricing: {input_per_mtok: 100, output_per_mtok: 200}
      acknowledge_permissions_baseline: true
      mystery_field: "should fail"
EOF
    run "$VALIDATOR_PY" --config "$WORK_DIR/e22.yaml" --quiet
    [[ "$status" -eq 78 ]]
}

# ---------------------------------------------------------------------------
# E23-E25 PERMISSIONS — FR-1.4 acknowledge_permissions_baseline gate
# ---------------------------------------------------------------------------

@test "E23 reject: no permissions block AND no acknowledge_permissions_baseline" {
    cat > "$WORK_DIR/e23.yaml" <<'EOF'
model_aliases_extra:
  schema_version: "1.0.0"
  entries:
    - id: foo
      provider: openai
      api_id: foo
      capabilities: [chat]
      context_window: 128000
      pricing: {input_per_mtok: 100, output_per_mtok: 200}
EOF
    run "$VALIDATOR_PY" --config "$WORK_DIR/e23.yaml" --quiet
    [[ "$status" -eq 78 ]]
}

@test "E24 accept: permissions block present (no acknowledge needed)" {
    cat > "$WORK_DIR/e24.yaml" <<'EOF'
model_aliases_extra:
  schema_version: "1.0.0"
  entries:
    - id: foo
      provider: openai
      api_id: foo
      capabilities: [chat]
      context_window: 128000
      pricing: {input_per_mtok: 100, output_per_mtok: 200}
      permissions:
        chat: {allowed: true}
EOF
    run "$VALIDATOR_PY" --config "$WORK_DIR/e24.yaml"
    [[ "$status" -eq 0 ]]
}

@test "E25 accept: acknowledge_permissions_baseline: true (no permissions block)" {
    cat > "$WORK_DIR/e25.yaml" <<'EOF'
model_aliases_extra:
  schema_version: "1.0.0"
  entries:
    - id: foo
      provider: openai
      api_id: foo
      capabilities: [chat]
      context_window: 128000
      pricing: {input_per_mtok: 100, output_per_mtok: 200}
      acknowledge_permissions_baseline: true
EOF
    run "$VALIDATOR_PY" --config "$WORK_DIR/e25.yaml"
    [[ "$status" -eq 0 ]]
}

# gp L4 / cypherpunk L4 fix: acknowledge_permissions_baseline now uses
# `const: true` so false is REJECTED at the schema layer.
@test "E25b reject: acknowledge_permissions_baseline: false (gp/cypherpunk L4 fix)" {
    cat > "$WORK_DIR/e25b.yaml" <<'EOF'
model_aliases_extra:
  schema_version: "1.0.0"
  entries:
    - id: foo
      provider: openai
      api_id: foo
      capabilities: [chat]
      context_window: 128000
      pricing: {input_per_mtok: 100, output_per_mtok: 200}
      acknowledge_permissions_baseline: false
EOF
    run "$VALIDATOR_PY" --config "$WORK_DIR/e25b.yaml" --quiet
    [[ "$status" -eq 78 ]] || {
        printf 'acknowledge_permissions_baseline: false MUST be rejected (const true); got status=%d\n' "$status" >&2
        return 1
    }
}

# gp + cypherpunk HIGH H1 fix: permissions: {} (empty object) MUST be
# rejected — previously bypassed FR-1.4 because `if not required[permissions]`
# only fired when the field was ABSENT. Schema now requires
# permissions.minProperties: 1 AND the allOf treats empty == absent.
@test "E26 reject: permissions: {} (empty object bypasses FR-1.4) — H1 fix" {
    cat > "$WORK_DIR/e26.yaml" <<'EOF'
model_aliases_extra:
  schema_version: "1.0.0"
  entries:
    - id: foo
      provider: openai
      api_id: foo
      capabilities: [chat]
      context_window: 128000
      pricing: {input_per_mtok: 100, output_per_mtok: 200}
      permissions: {}
EOF
    run "$VALIDATOR_PY" --config "$WORK_DIR/e26.yaml" --quiet
    [[ "$status" -eq 78 ]] || {
        printf 'permissions: {} MUST be rejected (FR-1.4 bypass); got status=%d\n' "$status" >&2
        return 1
    }
}

# cypherpunk M1 fix: id pattern now has not.anyOf rejecting `..` plus
# leading/trailing meta chars. The bare regex `[a-zA-Z0-9._-]+` accepted `..`
# because each `.` is individually in the char class
# (cycle-099 sprint-1E.c.3.b feedback_charclass_dotdot_bypass).
@test "E27 reject: id == '..' (charclass dot-dot bypass) — cypherpunk M1 fix" {
    cat > "$WORK_DIR/e27.yaml" <<'EOF'
model_aliases_extra:
  schema_version: "1.0.0"
  entries:
    - id: ".."
      provider: openai
      api_id: foo
      capabilities: [chat]
      context_window: 128000
      pricing: {input_per_mtok: 100, output_per_mtok: 200}
      acknowledge_permissions_baseline: true
EOF
    run "$VALIDATOR_PY" --config "$WORK_DIR/e27.yaml" --quiet
    [[ "$status" -eq 78 ]]
}

@test "E27b reject: id with embedded '..' (path traversal pattern)" {
    cat > "$WORK_DIR/e27b.yaml" <<'EOF'
model_aliases_extra:
  schema_version: "1.0.0"
  entries:
    - id: "foo..bar"
      provider: openai
      api_id: foo
      capabilities: [chat]
      context_window: 128000
      pricing: {input_per_mtok: 100, output_per_mtok: 200}
      acknowledge_permissions_baseline: true
EOF
    run "$VALIDATOR_PY" --config "$WORK_DIR/e27b.yaml" --quiet
    [[ "$status" -eq 78 ]]
}

@test "E27c reject: id starting with '.' (leading-meta)" {
    cat > "$WORK_DIR/e27c.yaml" <<'EOF'
model_aliases_extra:
  schema_version: "1.0.0"
  entries:
    - id: ".foo"
      provider: openai
      api_id: foo
      capabilities: [chat]
      context_window: 128000
      pricing: {input_per_mtok: 100, output_per_mtok: 200}
      acknowledge_permissions_baseline: true
EOF
    run "$VALIDATOR_PY" --config "$WORK_DIR/e27c.yaml" --quiet
    [[ "$status" -eq 78 ]]
}

# cypherpunk L5: id pattern is ASCII-anchored, so non-ASCII MUST reject.
# Pin the contract via positive-control-of-rejection.
@test "E28 reject: id with non-ASCII char (Unicode boundary — cypherpunk L5)" {
    cat > "$WORK_DIR/e28.yaml" <<'EOF'
model_aliases_extra:
  schema_version: "1.0.0"
  entries:
    - id: "éxperimental"
      provider: openai
      api_id: foo
      capabilities: [chat]
      context_window: 128000
      pricing: {input_per_mtok: 100, output_per_mtok: 200}
      acknowledge_permissions_baseline: true
EOF
    run "$VALIDATOR_PY" --config "$WORK_DIR/e28.yaml" --quiet
    [[ "$status" -eq 78 ]]
}

# gp M1 / cypherpunk M2: schema-layer endpoint validation. format: uri is
# advisory in jsonschema-Python so we added pattern: ^https://. Pin it.
@test "E29 reject: endpoint with non-https scheme (HTTP)" {
    cat > "$WORK_DIR/e29.yaml" <<'EOF'
model_aliases_extra:
  schema_version: "1.0.0"
  entries:
    - id: foo
      provider: openai
      api_id: foo
      endpoint: "http://api.openai.com/v1"
      capabilities: [chat]
      context_window: 128000
      pricing: {input_per_mtok: 100, output_per_mtok: 200}
      acknowledge_permissions_baseline: true
EOF
    run "$VALIDATOR_PY" --config "$WORK_DIR/e29.yaml" --quiet
    [[ "$status" -eq 78 ]]
}

@test "E29b reject: endpoint with javascript: scheme (XSS-class payload)" {
    cat > "$WORK_DIR/e29b.yaml" <<'EOF'
model_aliases_extra:
  schema_version: "1.0.0"
  entries:
    - id: foo
      provider: openai
      api_id: foo
      endpoint: "javascript:alert(1)"
      capabilities: [chat]
      context_window: 128000
      pricing: {input_per_mtok: 100, output_per_mtok: 200}
      acknowledge_permissions_baseline: true
EOF
    run "$VALIDATOR_PY" --config "$WORK_DIR/e29b.yaml" --quiet
    [[ "$status" -eq 78 ]]
}

@test "E29c accept: endpoint with valid https URI" {
    cat > "$WORK_DIR/e29c.yaml" <<'EOF'
model_aliases_extra:
  schema_version: "1.0.0"
  entries:
    - id: foo
      provider: openai
      api_id: foo
      endpoint: "https://api.openai.com/v1/responses"
      capabilities: [chat]
      context_window: 128000
      pricing: {input_per_mtok: 100, output_per_mtok: 200}
      acknowledge_permissions_baseline: true
EOF
    run "$VALIDATOR_PY" --config "$WORK_DIR/e29c.yaml"
    [[ "$status" -eq 0 ]]
}

# cypherpunk H3 / IMP-004 fix: collision check against framework defaults.
# Operator-added IDs MUST NOT collide with framework-shipped IDs.
@test "E30 reject: id collides with framework-default model id — cypherpunk H3 fix" {
    cat > "$WORK_DIR/e30.yaml" <<'EOF'
model_aliases_extra:
  schema_version: "1.0.0"
  entries:
    - id: claude-opus-4-7
      provider: anthropic
      api_id: claude-opus-4-7
      capabilities: [chat]
      context_window: 200000
      pricing: {input_per_mtok: 100, output_per_mtok: 200}
      acknowledge_permissions_baseline: true
EOF
    run "$VALIDATOR_PY" --config "$WORK_DIR/e30.yaml" --quiet
    [[ "$status" -eq 78 ]] || {
        printf 'collision with framework default claude-opus-4-7 MUST be rejected; got=%d\n' "$status" >&2
        return 1
    }
}

@test "E30b accept: collision check disabled via --no-collision-check" {
    # Sprint 2B integration tests use this to test schema in isolation.
    cat > "$WORK_DIR/e30b.yaml" <<'EOF'
model_aliases_extra:
  schema_version: "1.0.0"
  entries:
    - id: claude-opus-4-7
      provider: anthropic
      api_id: claude-opus-4-7
      capabilities: [chat]
      context_window: 200000
      pricing: {input_per_mtok: 100, output_per_mtok: 200}
      acknowledge_permissions_baseline: true
EOF
    run "$VALIDATOR_PY" --config "$WORK_DIR/e30b.yaml" --no-collision-check
    [[ "$status" -eq 0 ]]
}

# cypherpunk L6: yaml.safe_load MUST reject !!python/object tags.
# BB iter-1 hardcoded-tmp-file fix: use $WORK_DIR/-prefixed path with PID
# so concurrent test runs don't share state and stale files from prior
# failures can't mask current exploits.
@test "E31 reject: !!python/object payload (yaml.safe_load contract pin — cypherpunk L6)" {
    # BB iter-2 F2: $WORK_DIR is already per-test (mktemp -d); $$ suffix
    # was redundant. Drop it.
    local pwned_path="$WORK_DIR/e31-pwned"
    # Unquoted heredoc so $pwned_path is interpolated into the YAML payload.
    cat > "$WORK_DIR/e31.yaml" <<EOF
model_aliases_extra:
  schema_version: "1.0.0"
  entries:
    - id: !!python/object/new:os.system [touch $pwned_path]
      provider: openai
      api_id: foo
      capabilities: [chat]
      context_window: 128000
      pricing: {input_per_mtok: 100, output_per_mtok: 200}
      acknowledge_permissions_baseline: true
EOF
    run "$VALIDATOR_PY" --config "$WORK_DIR/e31.yaml" --quiet
    # BB iter-2 F3: tighten to exact exit-code pin. safe_load on
    # !!python/object MUST raise YAMLError → EX_USAGE (64). Allowing 78
    # would mask a regression where the YAML parsed (gadget chain fired)
    # and the schema then rejected the result with 78.
    [[ "$status" -eq 64 ]] || {
        printf '!!python/object MUST exit 64 (YAMLError path); got=%d\n' "$status" >&2
        return 1
    }
    # Sanity: side-effect (file creation) MUST NOT have happened. The
    # path is per-test ($WORK_DIR) so a positive result is genuine.
    [[ ! -f "$pwned_path" ]] || {
        printf 'CRITICAL: !!python/object payload executed and created %s!\n' "$pwned_path" >&2
        return 1
    }
}

# BB iter-2 F6: reject duplicate ids within entries[]. JSON Schema can't
# dedupe by inner key natively; Python-side post-validation check fires.
@test "E32 reject: duplicate id within entries[] (BB F6)" {
    cat > "$WORK_DIR/e32.yaml" <<'EOF'
model_aliases_extra:
  schema_version: "1.0.0"
  entries:
    - id: shadow
      provider: openai
      api_id: foo
      capabilities: [chat]
      context_window: 128000
      pricing: {input_per_mtok: 100, output_per_mtok: 200}
      acknowledge_permissions_baseline: true
    - id: shadow
      provider: anthropic
      api_id: bar
      capabilities: [chat]
      context_window: 128000
      pricing: {input_per_mtok: 100, output_per_mtok: 200}
      acknowledge_permissions_baseline: true
EOF
    run "$VALIDATOR_PY" --config "$WORK_DIR/e32.yaml" --quiet
    [[ "$status" -eq 78 ]] || {
        printf 'duplicate id MUST be rejected; got=%d\n' "$status" >&2
        return 1
    }
}

# BB iter-2 F7: pin pricing minimum:0 — explicitly reject negative values.
@test "E33 reject: negative pricing.input_per_mtok (BB F7)" {
    cat > "$WORK_DIR/e33.yaml" <<'EOF'
model_aliases_extra:
  schema_version: "1.0.0"
  entries:
    - id: foo
      provider: openai
      api_id: foo
      capabilities: [chat]
      context_window: 128000
      pricing: {input_per_mtok: -1, output_per_mtok: 200}
      acknowledge_permissions_baseline: true
EOF
    run "$VALIDATOR_PY" --config "$WORK_DIR/e33.yaml" --quiet
    [[ "$status" -eq 78 ]]
}

@test "E33b reject: negative pricing.output_per_mtok (BB F7)" {
    cat > "$WORK_DIR/e33b.yaml" <<'EOF'
model_aliases_extra:
  schema_version: "1.0.0"
  entries:
    - id: foo
      provider: openai
      api_id: foo
      capabilities: [chat]
      context_window: 128000
      pricing: {input_per_mtok: 100, output_per_mtok: -200}
      acknowledge_permissions_baseline: true
EOF
    run "$VALIDATOR_PY" --config "$WORK_DIR/e33b.yaml" --quiet
    [[ "$status" -eq 78 ]]
}

# BB iter-2 F4: --no-collision-check MUST suppress ONLY collision detection,
# not other schema validation. Pin via mixed-violation fixture.
@test "E34 --no-collision-check still rejects schema-invalid entries (BB F4)" {
    cat > "$WORK_DIR/e34.yaml" <<'EOF'
model_aliases_extra:
  schema_version: "1.0.0"
  entries:
    - id: claude-opus-4-7
      provider: azure
      api_id: foo
      capabilities: [chat]
      context_window: 128000
      pricing: {input_per_mtok: 100, output_per_mtok: 200}
      acknowledge_permissions_baseline: true
EOF
    run "$VALIDATOR_PY" --config "$WORK_DIR/e34.yaml" --no-collision-check --quiet
    [[ "$status" -eq 78 ]] || {
        printf '--no-collision-check should suppress collision only, not schema validation; got=%d\n' "$status" >&2
        return 1
    }
}

# gp M2: malformed --block paths must be rejected, not silently swallowed.
@test "B4 reject: malformed --block path (empty)" {
    cat > "$WORK_DIR/b4.yaml" <<'EOF'
model_aliases_extra:
  schema_version: "1.0.0"
  entries: []
EOF
    run "$VALIDATOR_PY" --config "$WORK_DIR/b4.yaml" --block ""
    [[ "$status" -eq 64 ]] || {
        printf 'empty --block must reject with EX_USAGE; got=%d\n' "$status" >&2
        return 1
    }
}

@test "B4b reject: malformed --block path (embedded ..)" {
    cat > "$WORK_DIR/uc1b.yaml" <<'EOF'
model_aliases_extra:
  schema_version: "1.0.0"
  entries: []
EOF
    run "$VALIDATOR_PY" --config "$WORK_DIR/uc1b.yaml" --block ".foo..bar"
    [[ "$status" -eq 64 ]]
}

@test "B4c reject: malformed --block path (trailing dot)" {
    cat > "$WORK_DIR/uc1c.yaml" <<'EOF'
model_aliases_extra:
  schema_version: "1.0.0"
  entries: []
EOF
    run "$VALIDATOR_PY" --config "$WORK_DIR/uc1c.yaml" --block ".foo."
    [[ "$status" -eq 64 ]]
}

@test "B4d accept: well-formed --block path (single field)" {
    cat > "$WORK_DIR/uc1d.yaml" <<'EOF'
nested:
  model_aliases_extra:
    schema_version: "1.0.0"
    entries: []
EOF
    run "$VALIDATOR_PY" --config "$WORK_DIR/uc1d.yaml" --block ".nested.model_aliases_extra"
    [[ "$status" -eq 0 ]]
}

# ---------------------------------------------------------------------------
# B1-B3 BASH TWIN — wrapper exit-code parity
# ---------------------------------------------------------------------------

@test "B1 bash wrapper: valid config → exit 0" {
    cat > "$WORK_DIR/b1.yaml" <<'EOF'
model_aliases_extra:
  schema_version: "1.0.0"
  entries: []
EOF
    run "$VALIDATOR_SH" --config "$WORK_DIR/b1.yaml"
    [[ "$status" -eq 0 ]] || {
        printf 'bash wrapper status=%d output=%s\n' "$status" "$output" >&2
        return 1
    }
}

@test "B2 bash wrapper: invalid config → exit 78" {
    cat > "$WORK_DIR/b2.yaml" <<'EOF'
model_aliases_extra:
  schema_version: "wrong"
  entries: []
EOF
    run "$VALIDATOR_SH" --config "$WORK_DIR/b2.yaml" --quiet
    [[ "$status" -eq 78 ]]
}

@test "B3 bash wrapper: --json passthrough" {
    cat > "$WORK_DIR/b3.yaml" <<'EOF'
model_aliases_extra:
  schema_version: "1.0.0"
  entries: []
EOF
    run "$VALIDATOR_SH" --config "$WORK_DIR/b3.yaml" --json
    [[ "$status" -eq 0 ]]
    echo "$output" | grep -q '"valid":true' || {
        printf 'expected "valid":true in JSON output; got: %s\n' "$output" >&2
        return 1
    }
}

# ---------------------------------------------------------------------------
# Edge cases: schema-validation production smoke
# ---------------------------------------------------------------------------

@test "S1 schema file is well-formed Draft 2020-12" {
    "$PYTHON_BIN" -I -c "
import json, jsonschema, sys
schema = json.load(open('$SCHEMA'))
jsonschema.Draft202012Validator.check_schema(schema)
print('OK')
"
}

@test "S2 schema enforces required field set on top-level (schema_version REQUIRED)" {
    cat > "$WORK_DIR/s2.yaml" <<'EOF'
model_aliases_extra:
  entries: []
EOF
    run "$VALIDATOR_PY" --config "$WORK_DIR/s2.yaml" --quiet
    [[ "$status" -eq 78 ]]
}

@test "S3 entries field is OPTIONAL (operator with schema_version only)" {
    cat > "$WORK_DIR/s3.yaml" <<'EOF'
model_aliases_extra:
  schema_version: "1.0.0"
EOF
    run "$VALIDATOR_PY" --config "$WORK_DIR/s3.yaml"
    [[ "$status" -eq 0 ]]
}
