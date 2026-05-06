#!/usr/bin/env bats
# =============================================================================
# tests/integration/cycle099-prefer-pro-wiring.bats
#
# cycle-099 Sprint 2E (T2.8) — verify `prefer_pro_models` operator-config
# wiring against the FR-3.9 6-stage resolver.
#
# Sprint 2D shipped the resolver-side semantics (S6 stage). T2.8 verifies the
# operator-config knob propagates through to resolution end-to-end:
#
#   Test surface (P1-P5):
#     P1   — operator's .loa.config.yaml::prefer_pro_models: true retargets a
#            modern skill_models resolution at S6 (e.g., gpt-5.5 → gpt-5.5-pro).
#     P2   — FR-3.4 legacy gate: prefer_pro_models on a legacy `<skill>.models.<role>`
#            entry is GATED OFF unless the skill declares `respect_prefer_pro: true`.
#     P3   — per-skill `respect_prefer_pro: true` opens the gate for legacy
#            shapes; S6 applied + retargets.
#     P4   — prefer_pro_models: false (or absent) → no S6 entry in path.
#     P5   — End-to-end via T2.7 tier_groups: skill_models tier-tag `mid`
#            resolves to gpt-5.5 via S3, then S6 retargets to gpt-5.5-pro.
# =============================================================================

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    CONFIG="$PROJECT_ROOT/.claude/defaults/model-config.yaml"
    RESOLVER="$PROJECT_ROOT/.claude/scripts/lib/model-resolver.py"
    [[ -f "$CONFIG" ]] || skip "model-config.yaml not present"
    [[ -f "$RESOLVER" ]] || skip "model-resolver.py not present"
    command -v yq >/dev/null 2>&1 || skip "yq not present"
    command -v python3 >/dev/null 2>&1 || skip "python3 not present"
    command -v jq >/dev/null 2>&1 || skip "jq not present"
    WORK_DIR="$(mktemp -d)"
}

teardown() {
    if [[ -n "${WORK_DIR:-}" ]] && [[ -d "$WORK_DIR" ]]; then
        rm -rf "$WORK_DIR"
    fi
    return 0
}

# Helper: write a synthetic merged-config YAML (skip large
# framework_defaults since we mock the relevant slice). Args:
# $1=tier_or_alias_or_pin, $2=operator_config_extra (YAML), $3=skill_block (YAML).
_write_synthetic_cfg() {
    local skill_models_value="$1"
    local operator_extra="${2:-}"
    cat > "$WORK_DIR/cfg.yaml" <<YAML
schema_version: 2
framework_defaults:
  providers:
    openai:
      models:
        gpt-5.5: { context_window: 200000 }
        gpt-5.5-pro: { context_window: 400000 }
    anthropic:
      models:
        claude-opus-4-7: { context_window: 200000 }
  aliases:
    gpt-5.5: { provider: openai, model_id: gpt-5.5 }
    gpt-5.5-pro: { provider: openai, model_id: gpt-5.5-pro }
    opus: { provider: anthropic, model_id: claude-opus-4-7 }
  agents: {}
operator_config:
$operator_extra
YAML
    if [[ -n "$skill_models_value" ]]; then
        cat >> "$WORK_DIR/cfg.yaml" <<YAML
  skill_models:
    test_skill:
      primary: $skill_models_value
YAML
    fi
}

# Helper: jq-extract a field from resolver output.
_resolve() {
    python3 "$RESOLVER" resolve --config "$WORK_DIR/cfg.yaml" --skill "$1" --role "$2"
}

@test "P1 — operator prefer_pro_models: true retargets modern skill_models at S6 (gpt-5.5 → gpt-5.5-pro)" {
    _write_synthetic_cfg "gpt-5.5" "  prefer_pro_models: true"
    local out
    out=$(_resolve test_skill primary)
    local provider model_id last_label last_outcome last_to
    provider=$(echo "$out" | jq -r '.resolved_provider')
    model_id=$(echo "$out" | jq -r '.resolved_model_id')
    last_label=$(echo "$out" | jq -r '.resolution_path[-1].label')
    last_outcome=$(echo "$out" | jq -r '.resolution_path[-1].outcome')
    last_to=$(echo "$out" | jq -r '.resolution_path[-1].details.to // empty')

    [[ "$provider" == "openai" ]] || { echo "expected openai got=$provider"; echo "$out"; return 1; }
    [[ "$model_id" == "gpt-5.5-pro" ]] || { echo "expected gpt-5.5-pro got=$model_id"; echo "$out"; return 1; }
    [[ "$last_label" == "stage6_prefer_pro_overlay" ]] || { echo "expected last stage6, got=$last_label"; echo "$out"; return 1; }
    [[ "$last_outcome" == "applied" ]] || { echo "expected applied, got=$last_outcome"; echo "$out"; return 1; }
    [[ "$last_to" == "gpt-5.5-pro" ]] || { echo "expected to=gpt-5.5-pro, got=$last_to"; echo "$out"; return 1; }
}

@test "P2 — FR-3.4 legacy gate: prefer_pro on legacy shape WITHOUT respect_prefer_pro → S6 skipped" {
    cat > "$WORK_DIR/cfg.yaml" <<'YAML'
schema_version: 2
framework_defaults:
  providers:
    openai:
      models:
        gpt-5.5: { context_window: 200000 }
        gpt-5.5-pro: { context_window: 400000 }
  aliases:
    gpt-5.5: { provider: openai, model_id: gpt-5.5 }
    gpt-5.5-pro: { provider: openai, model_id: gpt-5.5-pro }
  agents: {}
operator_config:
  prefer_pro_models: true
  legacy_skill:
    models:
      primary: gpt-5.5
YAML
    local out
    out=$(_resolve legacy_skill primary)
    local model_id last_label last_outcome last_reason
    model_id=$(echo "$out" | jq -r '.resolved_model_id')
    last_label=$(echo "$out" | jq -r '.resolution_path[-1].label')
    last_outcome=$(echo "$out" | jq -r '.resolution_path[-1].outcome')
    last_reason=$(echo "$out" | jq -r '.resolution_path[-1].details.reason // empty')

    [[ "$model_id" == "gpt-5.5" ]] || { echo "FR-3.4 gate failed: expected gpt-5.5 (NO retarget), got=$model_id"; echo "$out"; return 1; }
    [[ "$last_label" == "stage6_prefer_pro_overlay" ]] || { echo "expected last stage6, got=$last_label"; echo "$out"; return 1; }
    [[ "$last_outcome" == "skipped" ]] || { echo "expected skipped, got=$last_outcome"; echo "$out"; return 1; }
    [[ "$last_reason" == "legacy_shape_without_respect_prefer_pro" ]] || { echo "expected legacy_shape_without_respect_prefer_pro reason, got=$last_reason"; echo "$out"; return 1; }
}

@test "P3 — per-skill respect_prefer_pro: true opens gate for legacy shapes; S6 applied" {
    cat > "$WORK_DIR/cfg.yaml" <<'YAML'
schema_version: 2
framework_defaults:
  providers:
    openai:
      models:
        gpt-5.5: { context_window: 200000 }
        gpt-5.5-pro: { context_window: 400000 }
  aliases:
    gpt-5.5: { provider: openai, model_id: gpt-5.5 }
    gpt-5.5-pro: { provider: openai, model_id: gpt-5.5-pro }
  agents: {}
operator_config:
  prefer_pro_models: true
  legacy_skill:
    respect_prefer_pro: true
    models:
      primary: gpt-5.5
YAML
    local out
    out=$(_resolve legacy_skill primary)
    local model_id last_label last_outcome last_to
    model_id=$(echo "$out" | jq -r '.resolved_model_id')
    last_label=$(echo "$out" | jq -r '.resolution_path[-1].label')
    last_outcome=$(echo "$out" | jq -r '.resolution_path[-1].outcome')
    last_to=$(echo "$out" | jq -r '.resolution_path[-1].details.to // empty')

    [[ "$model_id" == "gpt-5.5-pro" ]] || { echo "expected retarget to gpt-5.5-pro, got=$model_id"; echo "$out"; return 1; }
    [[ "$last_label" == "stage6_prefer_pro_overlay" ]] || { echo "expected last stage6, got=$last_label"; echo "$out"; return 1; }
    [[ "$last_outcome" == "applied" ]] || { echo "expected applied, got=$last_outcome"; echo "$out"; return 1; }
    [[ "$last_to" == "gpt-5.5-pro" ]] || { echo "expected to=gpt-5.5-pro, got=$last_to"; echo "$out"; return 1; }
}

@test "P4 — prefer_pro_models: false (absent) → no S6 entry in resolution_path" {
    _write_synthetic_cfg "gpt-5.5" ""
    local out
    out=$(_resolve test_skill primary)
    local has_stage6
    has_stage6=$(echo "$out" | jq -r '[.resolution_path[]?.stage] | any(. == 6)')
    [[ "$has_stage6" == "false" ]] || { echo "stage 6 unexpectedly present when prefer_pro absent"; echo "$out"; return 1; }
}

@test "P5 — end-to-end against PRODUCTION framework_defaults: skill_models tier 'mid' resolves via S3 then S6 retargets" {
    # Per T2.7, tier_groups.mappings.mid.openai = gpt-5.5 (alias).
    # The resolver picks provider via sorted(mapping.keys())[0] which yields
    # 'anthropic' first; to actually exercise the openai mid → gpt-5.5 path
    # we override the operator's tier_groups.mappings.mid to ONLY have openai.
    cat > "$WORK_DIR/cfg.yaml" <<YAML
schema_version: 2
framework_defaults:
$(sed 's/^/  /' "$CONFIG")
operator_config:
  prefer_pro_models: true
  tier_groups:
    mappings:
      mid:
        openai: gpt-5.5
  skill_models:
    test_skill:
      primary: mid
YAML
    local out
    out=$(_resolve test_skill primary)
    local provider model_id has_stage3 last_label last_to
    provider=$(echo "$out" | jq -r '.resolved_provider')
    model_id=$(echo "$out" | jq -r '.resolved_model_id')
    has_stage3=$(echo "$out" | jq -r '[.resolution_path[]?.label] | any(. == "stage3_tier_groups")')
    last_label=$(echo "$out" | jq -r '.resolution_path[-1].label')
    last_to=$(echo "$out" | jq -r '.resolution_path[-1].details.to // empty')

    [[ "$provider" == "openai" ]] || { echo "expected openai, got=$provider"; echo "$out"; return 1; }
    [[ "$model_id" == "gpt-5.5-pro" ]] || { echo "expected gpt-5.5-pro (S6 retarget), got=$model_id"; echo "$out"; return 1; }
    [[ "$has_stage3" == "true" ]] || { echo "expected stage3 tier_groups in path"; echo "$out"; return 1; }
    [[ "$last_label" == "stage6_prefer_pro_overlay" ]] || { echo "expected last stage6, got=$last_label"; echo "$out"; return 1; }
    [[ "$last_to" == "gpt-5.5-pro" ]] || { echo "expected to=gpt-5.5-pro, got=$last_to"; echo "$out"; return 1; }
}
