#!/usr/bin/env bats
# =============================================================================
# tests/unit/v3-codegen-byte-equality.bats
#
# cycle-109 Sprint 1 T1.8 — codegen byte-equality across v2 / v3 schemas.
#
# Sprint AC (PRD §FR-1): "Codegen byte-equality preserved across bash/
# python/TS for new fields — cross-runtime-diff.yml CI gate green".
#
# The gen-adapter-maps.sh script reads only v2 fields (providers,
# model_id, pricing). Adding v3 capability fields (effective_input_ceiling,
# reasoning_class, recommended_for, failure_modes_observed,
# ceiling_calibration, streaming_recovery) is supposed to be TRANSPARENT
# to the codegen output — the generated bash maps are byte-identical
# whether v3 fields are present or absent.
#
# This test contract pins that property.
#
# Live model-config.yaml migration is NOT in scope here; that's covered
# by T1.10 baselines-capture under the operator-driven C109.OP track.
# T1.8 ships the schema fix (kind field) + the transparency contract.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    GEN_ADAPTER_MAPS="$PROJECT_ROOT/.claude/scripts/gen-adapter-maps.sh"
    SCHEMA_V3="$PROJECT_ROOT/.claude/data/schemas/model-config-v3.schema.json"
    MIGRATE_CLI="$PROJECT_ROOT/.claude/scripts/loa-migrate-model-config.py"

    if [[ -x "$PROJECT_ROOT/.venv/bin/python" ]]; then
        PYTHON_BIN="$PROJECT_ROOT/.venv/bin/python"
    else
        PYTHON_BIN="$(command -v python3)"
    fi

    BATS_TMP="$(mktemp -d "${BATS_TMPDIR:-/tmp}/v3-codegen.XXXXXX")"
}

teardown() {
    rm -rf "$BATS_TMP" 2>/dev/null || true
}

# Minimal v2-shape fixture exercising the fields gen-adapter-maps.sh
# actually reads.
_v2_fixture() {
    cat > "$BATS_TMP/v2.yaml" <<'YAML'
providers:
  anthropic:
    type: anthropic
    endpoint: "https://api.anthropic.com/v1"
    auth: "{env:ANTHROPIC_API_KEY}"
    models:
      claude-opus-4-7:
        capabilities: [chat, tools]
        context_window: 200000
        token_param: max_tokens
        max_output_tokens: 32000
        streaming_max_input_tokens: 80000
        legacy_max_input_tokens: 60000
        pricing:
          input_per_mtok: 15000000
          output_per_mtok: 75000000
  openai:
    type: openai
    endpoint: "https://api.openai.com/v1"
    auth: "{env:OPENAI_API_KEY}"
    models:
      gpt-5.5-pro:
        capabilities: [chat, tools, function_calling]
        context_window: 128000
        token_param: max_completion_tokens
        endpoint_family: chat
        max_output_tokens: 16000
        pricing:
          input_per_mtok: 5000000
          output_per_mtok: 25000000
aliases:
  opus: claude-opus-4-7
  pro: gpt-5.5-pro
agents:
  reviewing-code:
    model: opus
    temperature: 0.3
YAML
}

# Same fixture with v3 capability fields layered on top of each model
# entry. gen-adapter-maps.sh MUST emit byte-identical output.
_v2_plus_v3_fixture() {
    cat > "$BATS_TMP/v2plusv3.yaml" <<'YAML'
schema_version: 3
providers:
  anthropic:
    type: anthropic
    endpoint: "https://api.anthropic.com/v1"
    auth: "{env:ANTHROPIC_API_KEY}"
    models:
      claude-opus-4-7:
        capabilities: [chat, tools]
        context_window: 200000
        token_param: max_tokens
        max_output_tokens: 32000
        streaming_max_input_tokens: 80000
        legacy_max_input_tokens: 60000
        pricing:
          input_per_mtok: 15000000
          output_per_mtok: 75000000
        # v3 additions — codegen MUST ignore these.
        effective_input_ceiling: 40000
        reasoning_class: true
        recommended_for: [review, audit, implementation, dissent, arbiter]
        failure_modes_observed: []
        ceiling_calibration:
          source: conservative_default
          calibrated_at: null
          sample_size: null
          stale_after_days: 30
          reprobe_trigger: ''
  openai:
    type: openai
    endpoint: "https://api.openai.com/v1"
    auth: "{env:OPENAI_API_KEY}"
    models:
      gpt-5.5-pro:
        capabilities: [chat, tools, function_calling]
        context_window: 128000
        token_param: max_completion_tokens
        endpoint_family: chat
        max_output_tokens: 16000
        pricing:
          input_per_mtok: 5000000
          output_per_mtok: 25000000
        effective_input_ceiling: 30000
        reasoning_class: true
        recommended_for: [review, audit, implementation, dissent, arbiter]
        failure_modes_observed: []
        ceiling_calibration:
          source: conservative_default
          calibrated_at: null
          sample_size: null
          stale_after_days: 30
          reprobe_trigger: ''
aliases:
  opus: claude-opus-4-7
  pro: gpt-5.5-pro
agents:
  reviewing-code:
    model: opus
    temperature: 0.3
YAML
}

# Run gen-adapter-maps.sh against a fixture, write output to $2.
_run_gen() {
    local cfg="$1"
    local out="$2"
    LOA_MODEL_CONFIG="$cfg" LOA_GENERATED_MAPS="$out" \
        bash "$GEN_ADAPTER_MAPS" >/dev/null 2>&1
}

# =============================================================================
# Z1: bash codegen output is byte-identical for v2-only vs v2+v3 input
# =============================================================================

@test "Z1: gen-adapter-maps.sh emits byte-identical bash maps for v2 vs v2+v3 inputs" {
    _v2_fixture
    _v2_plus_v3_fixture
    _run_gen "$BATS_TMP/v2.yaml" "$BATS_TMP/v2.out.sh"
    _run_gen "$BATS_TMP/v2plusv3.yaml" "$BATS_TMP/v2plusv3.out.sh"

    [[ -f "$BATS_TMP/v2.out.sh" ]]
    [[ -f "$BATS_TMP/v2plusv3.out.sh" ]]
    local h1 h2
    h1="$(sha256sum "$BATS_TMP/v2.out.sh" | awk '{print $1}')"
    h2="$(sha256sum "$BATS_TMP/v2plusv3.out.sh" | awk '{print $1}')"
    [[ "$h1" == "$h2" ]]
}

# =============================================================================
# Z2: gen-adapter-maps.sh --check passes for a v3-fielded fixture vs its
#     own output (idempotent regen)
# =============================================================================

@test "Z2: gen-adapter-maps.sh --check passes against own output for v3-fielded fixture" {
    _v2_plus_v3_fixture
    _run_gen "$BATS_TMP/v2plusv3.yaml" "$BATS_TMP/v2plusv3.out.sh"
    LOA_MODEL_CONFIG="$BATS_TMP/v2plusv3.yaml" \
        LOA_GENERATED_MAPS="$BATS_TMP/v2plusv3.out.sh" \
        bash "$GEN_ADAPTER_MAPS" --check
    # --check exits 0 when no drift.
}

# =============================================================================
# Z3: v3 schema accepts `kind: cli` on a model entry (headless adapter)
# =============================================================================

@test "Z3: v3 schema accepts kind: cli on model entries (headless adapter routing)" {
    cat > "$BATS_TMP/kind-fixture.yaml" <<'YAML'
schema_version: 3
providers:
  anthropic:
    type: anthropic
    endpoint: "https://api.anthropic.com/v1"
    auth: "{env:ANTHROPIC_API_KEY}"
    models:
      claude-headless:
        capabilities: [chat]
        context_window: 200000
        kind: cli
        token_param: max_tokens
        max_output_tokens: 32000
        pricing:
          input_per_mtok: 0
          output_per_mtok: 0
        effective_input_ceiling: 40000
        reasoning_class: true
        recommended_for: [review, audit, implementation, dissent, arbiter]
        failure_modes_observed: []
        ceiling_calibration:
          source: conservative_default
          calibrated_at: null
          sample_size: null
          stale_after_days: 30
          reprobe_trigger: ''
aliases:
  claude-headless: claude-headless
agents: {}
YAML
    run "$PYTHON_BIN" - <<PY
import json, yaml, sys
try:
    import jsonschema
except ImportError:
    print("SKIP: jsonschema not installed", file=sys.stderr); sys.exit(77)
schema = json.load(open("$SCHEMA_V3"))
doc = yaml.safe_load(open("$BATS_TMP/kind-fixture.yaml"))
try:
    jsonschema.validate(doc, schema)
    print("VALID")
except jsonschema.ValidationError as e:
    print(f"INVALID: {e.message}")
    sys.exit(1)
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *"VALID"* ]]
}

# =============================================================================
# Z4: v3 schema rejects unknown `kind` enum values
# =============================================================================

@test "Z4: v3 schema rejects kind values outside the enum (e.g., 'invalid')" {
    cat > "$BATS_TMP/bad-kind.yaml" <<'YAML'
schema_version: 3
providers:
  anthropic:
    type: anthropic
    endpoint: "x"
    auth: "x"
    models:
      claude-headless:
        capabilities: [chat]
        context_window: 200000
        kind: rocketfuel
        pricing: {input_per_mtok: 0, output_per_mtok: 0}
        effective_input_ceiling: 40000
        reasoning_class: false
        recommended_for: [review]
        failure_modes_observed: []
        ceiling_calibration:
          source: conservative_default
          calibrated_at: null
          sample_size: null
          stale_after_days: 30
          reprobe_trigger: ''
aliases: {}
agents: {}
YAML
    run "$PYTHON_BIN" - <<PY
import json, yaml, sys
try:
    import jsonschema
except ImportError:
    print("SKIP: jsonschema not installed", file=sys.stderr); sys.exit(77)
schema = json.load(open("$SCHEMA_V3"))
doc = yaml.safe_load(open("$BATS_TMP/bad-kind.yaml"))
try:
    jsonschema.validate(doc, schema)
    print("VALID")
except jsonschema.ValidationError as e:
    print("INVALID")
    sys.exit(1)
PY
    [ "$status" -ne 0 ]
    [[ "$output" == *"INVALID"* ]]
}

# =============================================================================
# Z5: migrator runs cleanly on a fixture that mirrors live-config shape
#     (the headless `kind: cli` entries that previously blocked migration)
# =============================================================================

@test "Z5: migrator succeeds on a fixture with kind:cli headless entries" {
    cat > "$BATS_TMP/live-shape.yaml" <<'YAML'
providers:
  anthropic:
    type: anthropic
    endpoint: "https://api.anthropic.com/v1"
    auth: "{env:ANTHROPIC_API_KEY}"
    models:
      claude-opus-4-7:
        capabilities: [chat, tools]
        context_window: 200000
        token_param: max_tokens
        max_output_tokens: 32000
        streaming_max_input_tokens: 80000
        legacy_max_input_tokens: 60000
        pricing:
          input_per_mtok: 15000000
          output_per_mtok: 75000000
      claude-headless:
        capabilities: [chat]
        context_window: 200000
        kind: cli
        token_param: max_tokens
        max_output_tokens: 32000
        pricing:
          input_per_mtok: 0
          output_per_mtok: 0
  openai:
    type: openai
    endpoint: "https://api.openai.com/v1"
    auth: "{env:OPENAI_API_KEY}"
    models:
      codex-headless:
        capabilities: [chat]
        context_window: 128000
        kind: cli
        token_param: max_completion_tokens
        endpoint_family: chat
        pricing:
          input_per_mtok: 0
          output_per_mtok: 0
aliases: {}
agents: {}
YAML
    run "$PYTHON_BIN" "$MIGRATE_CLI" \
        "$BATS_TMP/live-shape.yaml" \
        -o "$BATS_TMP/live-shape.v3.yaml" \
        --to-v3 \
        --calibrated-at "2026-05-13T00:00:00Z"
    [ "$status" -eq 0 ]
    [[ -f "$BATS_TMP/live-shape.v3.yaml" ]]
}

# =============================================================================
# Z6: post-migration, gen-adapter-maps.sh output matches the pre-migration
#     output (no codegen drift from migration itself)
# =============================================================================

@test "Z6: post-migration codegen output matches pre-migration baseline (drift-free)" {
    cat > "$BATS_TMP/pre.yaml" <<'YAML'
providers:
  anthropic:
    type: anthropic
    endpoint: "x"
    auth: "x"
    models:
      claude-opus-4-7:
        capabilities: [chat]
        context_window: 200000
        token_param: max_tokens
        max_output_tokens: 32000
        pricing:
          input_per_mtok: 15000000
          output_per_mtok: 75000000
aliases:
  opus: claude-opus-4-7
agents: {}
YAML
    _run_gen "$BATS_TMP/pre.yaml" "$BATS_TMP/pre.out.sh"
    "$PYTHON_BIN" "$MIGRATE_CLI" \
        "$BATS_TMP/pre.yaml" \
        -o "$BATS_TMP/post.yaml" \
        --to-v3 \
        --calibrated-at "2026-05-13T00:00:00Z"
    [ "$status" -eq 0 ]
    _run_gen "$BATS_TMP/post.yaml" "$BATS_TMP/post.out.sh"

    local h1 h2
    h1="$(sha256sum "$BATS_TMP/pre.out.sh" | awk '{print $1}')"
    h2="$(sha256sum "$BATS_TMP/post.out.sh" | awk '{print $1}')"
    [[ "$h1" == "$h2" ]]
}
