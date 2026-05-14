#!/usr/bin/env bats
# =============================================================================
# tests/unit/migrate-preserve-thresholds.bats
#
# cycle-109 followup B (#888) — Shape B live-migration semantics.
#
# Shape A (default; cycle-109 sprint-1 T1.2 behavior):
#   effective_input_ceiling = min(50% × api_context_window, 30000)
#   Conservative SDD §3.1.2 default. Pre-flight gate (T1.3) preempts at 30K
#   for most models, which is a behavior change from the pre-cycle-109
#   threshold of `streaming_max_input_tokens` (typically 80K-200K).
#
# Shape B (new; --preserve-thresholds flag):
#   effective_input_ceiling = streaming_max_input_tokens
#                          || legacy_max_input_tokens
#                          || max_input_tokens
#                          || Shape A formula (fallback when no v2 threshold)
#   No behavior change: pre-flight gate fires at the same threshold the
#   substrate already operates at. Operator-friendly for the live YAML
#   migration that lands before sprint-2.
#
# Sprint-1's _lookup_capability + _preflight_check consume
# effective_input_ceiling identically regardless of which Shape populated
# it — Shape B is purely a migration-time semantic choice; no runtime
# code path differs.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    MIGRATE_CLI="$PROJECT_ROOT/.claude/scripts/loa-migrate-model-config.py"

    if [[ -x "$PROJECT_ROOT/.venv/bin/python" ]]; then
        PYTHON_BIN="$PROJECT_ROOT/.venv/bin/python"
    else
        PYTHON_BIN="$(command -v python3)"
    fi

    BATS_TMP="$(mktemp -d "${BATS_TMPDIR:-/tmp}/migrate-preserve.XXXXXX")"
}

teardown() {
    rm -rf "$BATS_TMP" 2>/dev/null || true
}

_require_migrator_deps() {
    "$PYTHON_BIN" -c "import ruamel.yaml, jsonschema" 2>/dev/null \
        || skip "ruamel.yaml + jsonschema not installed in this Python env"
}

# Standard v2 fixture: opus-like (200K api_context, 80K streaming, 60K legacy)
# + non-streaming-aware model (no streaming_max_input_tokens, only api).
_write_v2_fixture() {
    cat > "$BATS_TMP/v2.yaml" <<'YAML'
schema_version: 2
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
        streaming_max_input_tokens: 80000
        legacy_max_input_tokens: 60000
        max_output_tokens: 32000
        pricing:
          input_per_mtok: 15000000
          output_per_mtok: 75000000
  openai:
    type: openai
    endpoint: "https://api.openai.com/v1"
    auth: "{env:OPENAI_API_KEY}"
    models:
      gpt-5.5-pro:
        capabilities: [chat]
        context_window: 400000
        token_param: max_completion_tokens
        endpoint_family: chat
        streaming_max_input_tokens: 180000
        max_output_tokens: 32000
        pricing:
          input_per_mtok: 5000000
          output_per_mtok: 30000000
      gpt-no-thresholds:
        capabilities: [chat]
        context_window: 64000
        token_param: max_completion_tokens
        endpoint_family: chat
        max_output_tokens: 8000
        pricing:
          input_per_mtok: 1000000
          output_per_mtok: 3000000
aliases:
  opus: claude-opus-4-7
  pro: gpt-5.5-pro
tier_groups:
  mappings:
    max: {anthropic: opus}
    cheap: {anthropic: opus, openai: pro}
    tiny: {anthropic: opus}
agents:
  reviewing-code:
    default_tier: max
YAML
}

_read_ceiling() {
    local model="$1"
    "$PYTHON_BIN" - <<PY
import yaml
cfg = yaml.safe_load(open("$BATS_TMP/v3.yaml"))
# Find the model under any provider.
for prov, p in cfg.get("providers", {}).items():
    for m_id, m in p.get("models", {}).items():
        if m_id == "$model":
            print(m.get("effective_input_ceiling"))
            raise SystemExit(0)
print("MODEL_NOT_FOUND")
PY
}

# =============================================================================
# PT1: Shape A (default) — pre-cycle-109 sprint-1 behavior preserved
# =============================================================================

@test "PT1: --to-v3 without --preserve-thresholds applies SDD §3.1.2 conservative defaults (Shape A)" {
    _require_migrator_deps
    _write_v2_fixture
    run "$PYTHON_BIN" "$MIGRATE_CLI" \
        "$BATS_TMP/v2.yaml" -o "$BATS_TMP/v3.yaml" \
        --to-v3 --calibrated-at "2026-05-14T00:00:00Z"
    [ "$status" -eq 0 ]
    # Shape A: min(200000//2, 30000) = 30000 for opus
    run _read_ceiling "claude-opus-4-7"
    [[ "$output" == "30000" ]]
    # Shape A: min(400000//2, 30000) = 30000 for gpt-5.5-pro
    run _read_ceiling "gpt-5.5-pro"
    [[ "$output" == "30000" ]]
    # Shape A: min(64000//2, 30000) = 30000 for the no-thresholds model
    run _read_ceiling "gpt-no-thresholds"
    [[ "$output" == "30000" ]]
}

# =============================================================================
# PT2: Shape B — streaming_max_input_tokens takes priority
# =============================================================================

@test "PT2: --preserve-thresholds populates effective_input_ceiling from streaming_max_input_tokens" {
    _require_migrator_deps
    _write_v2_fixture
    run "$PYTHON_BIN" "$MIGRATE_CLI" \
        "$BATS_TMP/v2.yaml" -o "$BATS_TMP/v3.yaml" \
        --to-v3 --preserve-thresholds \
        --calibrated-at "2026-05-14T00:00:00Z"
    [ "$status" -eq 0 ]
    run _read_ceiling "claude-opus-4-7"
    [[ "$output" == "80000" ]]
    run _read_ceiling "gpt-5.5-pro"
    [[ "$output" == "180000" ]]
}

# =============================================================================
# PT3: Shape B — falls back to legacy_max_input_tokens when streaming absent
# =============================================================================

@test "PT3: --preserve-thresholds falls back to legacy_max_input_tokens" {
    _require_migrator_deps
    cat > "$BATS_TMP/v2.yaml" <<'YAML'
schema_version: 2
providers:
  anthropic:
    type: anthropic
    endpoint: "https://api.anthropic.com/v1"
    auth: "{env:ANTHROPIC_API_KEY}"
    models:
      claude-opus-4-7:
        capabilities: [chat]
        context_window: 200000
        token_param: max_tokens
        legacy_max_input_tokens: 60000
        max_output_tokens: 32000
        pricing: {input_per_mtok: 15000000, output_per_mtok: 75000000}
aliases: {opus: claude-opus-4-7}
tier_groups:
  mappings:
    max: {anthropic: opus}
    cheap: {anthropic: opus}
    tiny: {anthropic: opus}
agents: {}
YAML
    run "$PYTHON_BIN" "$MIGRATE_CLI" \
        "$BATS_TMP/v2.yaml" -o "$BATS_TMP/v3.yaml" \
        --to-v3 --preserve-thresholds \
        --calibrated-at "2026-05-14T00:00:00Z"
    [ "$status" -eq 0 ]
    run _read_ceiling "claude-opus-4-7"
    [[ "$output" == "60000" ]]
}

# =============================================================================
# PT4: Shape B — falls back to max_input_tokens (v2 single-field)
# =============================================================================

@test "PT4: --preserve-thresholds falls back to max_input_tokens (v2 single-field)" {
    _require_migrator_deps
    cat > "$BATS_TMP/v2.yaml" <<'YAML'
schema_version: 2
providers:
  anthropic:
    type: anthropic
    endpoint: "https://api.anthropic.com/v1"
    auth: "{env:ANTHROPIC_API_KEY}"
    models:
      claude-opus-4-7:
        capabilities: [chat]
        context_window: 200000
        token_param: max_tokens
        max_input_tokens: 50000
        max_output_tokens: 32000
        pricing: {input_per_mtok: 15000000, output_per_mtok: 75000000}
aliases: {opus: claude-opus-4-7}
tier_groups:
  mappings:
    max: {anthropic: opus}
    cheap: {anthropic: opus}
    tiny: {anthropic: opus}
agents: {}
YAML
    run "$PYTHON_BIN" "$MIGRATE_CLI" \
        "$BATS_TMP/v2.yaml" -o "$BATS_TMP/v3.yaml" \
        --to-v3 --preserve-thresholds \
        --calibrated-at "2026-05-14T00:00:00Z"
    [ "$status" -eq 0 ]
    run _read_ceiling "claude-opus-4-7"
    [[ "$output" == "50000" ]]
}

# =============================================================================
# PT5: Shape B — leaves effective_input_ceiling UNSET when no v2 threshold present
#
# True no-behavior-change semantics: models with no v2 threshold field
# weren't gated pre-migration; leaving the v3 field unset keeps the
# pre-flight gate inactive for them. _lookup_capability returns None
# for the ceiling and _preflight_check returns None — gate doesn't fire.
# Operator can populate later via tools/ceiling-probe.py once empirical
# data is available.
# =============================================================================

@test "PT5: --preserve-thresholds leaves effective_input_ceiling UNSET when no v2 threshold field exists" {
    _require_migrator_deps
    _write_v2_fixture
    run "$PYTHON_BIN" "$MIGRATE_CLI" \
        "$BATS_TMP/v2.yaml" -o "$BATS_TMP/v3.yaml" \
        --to-v3 --preserve-thresholds \
        --calibrated-at "2026-05-14T00:00:00Z"
    [ "$status" -eq 0 ]
    # gpt-no-thresholds has no streaming/legacy/max-input fields — Shape B
    # leaves the v3 effective_input_ceiling field unset (None).
    run _read_ceiling "gpt-no-thresholds"
    [[ "$output" == "None" ]]
}

# =============================================================================
# PT6: Shape B — operator-supplied effective_input_ceiling wins (no overwrite)
# =============================================================================

@test "PT6: --preserve-thresholds does NOT overwrite an operator-supplied effective_input_ceiling" {
    _require_migrator_deps
    cat > "$BATS_TMP/v2.yaml" <<'YAML'
schema_version: 2
providers:
  anthropic:
    type: anthropic
    endpoint: "https://api.anthropic.com/v1"
    auth: "{env:ANTHROPIC_API_KEY}"
    models:
      claude-opus-4-7:
        capabilities: [chat]
        context_window: 200000
        token_param: max_tokens
        streaming_max_input_tokens: 80000
        max_output_tokens: 32000
        effective_input_ceiling: 45000  # operator-pinned (e.g., empirical probe result)
        pricing: {input_per_mtok: 15000000, output_per_mtok: 75000000}
aliases: {opus: claude-opus-4-7}
tier_groups:
  mappings:
    max: {anthropic: opus}
    cheap: {anthropic: opus}
    tiny: {anthropic: opus}
agents: {}
YAML
    run "$PYTHON_BIN" "$MIGRATE_CLI" \
        "$BATS_TMP/v2.yaml" -o "$BATS_TMP/v3.yaml" \
        --to-v3 --preserve-thresholds \
        --calibrated-at "2026-05-14T00:00:00Z"
    [ "$status" -eq 0 ]
    run _read_ceiling "claude-opus-4-7"
    [[ "$output" == "45000" ]]
}

# =============================================================================
# PT7: idempotent — running with --preserve-thresholds twice produces same result
# =============================================================================

@test "PT7: --preserve-thresholds is idempotent (v3 input → idempotent_noop)" {
    _require_migrator_deps
    _write_v2_fixture
    run "$PYTHON_BIN" "$MIGRATE_CLI" \
        "$BATS_TMP/v2.yaml" -o "$BATS_TMP/v3.yaml" \
        --to-v3 --preserve-thresholds \
        --calibrated-at "2026-05-14T00:00:00Z"
    [ "$status" -eq 0 ]
    # Re-running on the v3 output should be a noop (v3 input → no migration).
    run "$PYTHON_BIN" "$MIGRATE_CLI" \
        "$BATS_TMP/v3.yaml" -o "$BATS_TMP/v3-second.yaml" \
        --to-v3 --preserve-thresholds \
        --calibrated-at "2026-05-14T00:00:00Z"
    [ "$status" -eq 0 ]
    # The two outputs must be byte-identical (idempotency property).
    local h1 h2
    h1="$(sha256sum "$BATS_TMP/v3.yaml" | awk '{print $1}')"
    h2="$(sha256sum "$BATS_TMP/v3-second.yaml" | awk '{print $1}')"
    [[ "$h1" == "$h2" ]]
}
