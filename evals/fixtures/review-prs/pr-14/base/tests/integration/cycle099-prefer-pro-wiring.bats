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
#   Test surface (P1-P6):
#     P1   — operator's .loa.config.yaml::prefer_pro_models: true retargets a
#            modern skill_models resolution at S6 (e.g., gpt-5.5 → gpt-5.5-pro).
#     P2   — FR-3.4 legacy gate: prefer_pro_models on a legacy `<skill>.models.<role>`
#            entry is GATED OFF unless the skill declares `respect_prefer_pro: true`.
#     P3   — per-skill `respect_prefer_pro: true` opens the gate for legacy
#            shapes; S6 applied + retargets.
#     P4   — prefer_pro_models absent → no S6 entry in path.
#     P4b  — prefer_pro_models: false (explicit) → no S6 entry. Pins the
#            resolver's `is True` strict-truth check (regression catches
#            future refactor that changes False/None handling).
#     P5   — Operator-override path: skill_models tier-tag `mid` with
#            operator's tier_groups.mappings.mid.openai = gpt-5.5 resolves
#            via S2-cascade-to-S3 + S6 retarget to gpt-5.5-pro. Verifies the
#            operator-override + S6 composition (NOT the framework-defaults
#            path; that's covered by P6).
#     P6   — Framework defaults path: skill_models tier-tag `mid` (no
#            operator tier_groups override) resolves through framework
#            tier_groups.mappings.mid.anthropic = cheap. Verifies the
#            production data shipped by T2.7.
#
# All test fixtures use `aliases:` STRING form (e.g., `gpt-5.5: "openai:gpt-5.5"`)
# matching production model-config.yaml. The resolver's _normalize_alias_entry
# accepts both dict-form and string-form, but production fixtures stay aligned
# with the model-config-v2 schema's string-only constraint.
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

# Helper: run resolver against $WORK_DIR/cfg.yaml (caller writes the file).
_resolve_pp() {
    python3 "$RESOLVER" resolve --config "$WORK_DIR/cfg.yaml" --skill "$1" --role "$2"
}

@test "P1 — operator prefer_pro_models: true retargets modern skill_models at S6 (gpt-5.5 → gpt-5.5-pro)" {
    cat > "$WORK_DIR/cfg.yaml" <<'YAML'
schema_version: 2
framework_defaults:
  providers:
    openai:
      models:
        gpt-5.5: { context_window: 200000 }
        gpt-5.5-pro: { context_window: 400000 }
  aliases:
    gpt-5.5: "openai:gpt-5.5"
    gpt-5.5-pro: "openai:gpt-5.5-pro"
  agents: {}
operator_config:
  prefer_pro_models: true
  skill_models:
    test_skill:
      primary: gpt-5.5
YAML
    local out provider model_id last_label last_outcome last_to
    out=$(_resolve_pp test_skill primary)
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
    gpt-5.5: "openai:gpt-5.5"
    gpt-5.5-pro: "openai:gpt-5.5-pro"
  agents: {}
operator_config:
  prefer_pro_models: true
  legacy_skill:
    models:
      primary: gpt-5.5
YAML
    local out model_id last_label last_outcome last_reason
    out=$(_resolve_pp legacy_skill primary)
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
    gpt-5.5: "openai:gpt-5.5"
    gpt-5.5-pro: "openai:gpt-5.5-pro"
  agents: {}
operator_config:
  prefer_pro_models: true
  legacy_skill:
    respect_prefer_pro: true
    models:
      primary: gpt-5.5
YAML
    local out model_id last_label last_outcome last_to
    out=$(_resolve_pp legacy_skill primary)
    model_id=$(echo "$out" | jq -r '.resolved_model_id')
    last_label=$(echo "$out" | jq -r '.resolution_path[-1].label')
    last_outcome=$(echo "$out" | jq -r '.resolution_path[-1].outcome')
    last_to=$(echo "$out" | jq -r '.resolution_path[-1].details.to // empty')

    [[ "$model_id" == "gpt-5.5-pro" ]] || { echo "expected retarget to gpt-5.5-pro, got=$model_id"; echo "$out"; return 1; }
    [[ "$last_label" == "stage6_prefer_pro_overlay" ]] || { echo "expected last stage6, got=$last_label"; echo "$out"; return 1; }
    [[ "$last_outcome" == "applied" ]] || { echo "expected applied, got=$last_outcome"; echo "$out"; return 1; }
    [[ "$last_to" == "gpt-5.5-pro" ]] || { echo "expected to=gpt-5.5-pro, got=$last_to"; echo "$out"; return 1; }
}

@test "P4 — prefer_pro_models absent → no S6 entry in resolution_path" {
    cat > "$WORK_DIR/cfg.yaml" <<'YAML'
schema_version: 2
framework_defaults:
  providers:
    openai:
      models:
        gpt-5.5: { context_window: 200000 }
        gpt-5.5-pro: { context_window: 400000 }
  aliases:
    gpt-5.5: "openai:gpt-5.5"
    gpt-5.5-pro: "openai:gpt-5.5-pro"
  agents: {}
operator_config:
  skill_models:
    test_skill:
      primary: gpt-5.5
YAML
    local out has_stage6
    out=$(_resolve_pp test_skill primary)
    has_stage6=$(echo "$out" | jq -r '[.resolution_path[]?.stage] | any(. == 6)')
    [[ "$has_stage6" == "false" ]] || { echo "stage 6 unexpectedly present when prefer_pro absent"; echo "$out"; return 1; }
}

@test "P4b — prefer_pro_models: false (explicit) → no S6 entry; pins resolver's strict 'is True' check" {
    cat > "$WORK_DIR/cfg.yaml" <<'YAML'
schema_version: 2
framework_defaults:
  providers:
    openai:
      models:
        gpt-5.5: { context_window: 200000 }
        gpt-5.5-pro: { context_window: 400000 }
  aliases:
    gpt-5.5: "openai:gpt-5.5"
    gpt-5.5-pro: "openai:gpt-5.5-pro"
  agents: {}
operator_config:
  prefer_pro_models: false
  skill_models:
    test_skill:
      primary: gpt-5.5
YAML
    # The resolver's _stage6_prefer_pro at line 591 uses
    # `operator_config.get("prefer_pro_models") is True` (strict identity, not
    # truthy). False, None, missing all mean "S6 not emitted." A future
    # refactor that changes `is True` to `if x:` would correctly handle
    # absent (None is falsy) but break for explicit False (still falsy in
    # bool, but observable difference if the check became `if x != False`).
    # P4b pins the explicit-false case as a regression sentinel.
    local out has_stage6
    out=$(_resolve_pp test_skill primary)
    has_stage6=$(echo "$out" | jq -r '[.resolution_path[]?.stage] | any(. == 6)')
    [[ "$has_stage6" == "false" ]] || { echo "stage 6 unexpectedly present when prefer_pro=false"; echo "$out"; return 1; }
}

@test "P5 — operator-override path: skill_models tier 'mid' + operator tier_groups override → S3 + S6 retargets" {
    # Per T2.7, framework's tier_groups.mappings.mid.openai = gpt-5.5.
    # The resolver picks provider via sorted(operator_tier_mappings.keys())[0]
    # if operator override is present. We confine operator override to ONLY
    # have openai so resolver picks that path. This verifies the
    # OPERATOR-OVERRIDE path through S2 cascade → S3 → S6 retarget. P6 covers
    # the framework-defaults path explicitly.
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
    local out provider model_id has_stage3 last_label last_to
    out=$(_resolve_pp test_skill primary)
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

@test "P6 — framework-defaults path: skill_models tier 'mid' (no operator override) → S3 (anthropic:cheap) + S6 skipped:no_pro_variant_for_alias" {
    # Closes the framework-defaults coverage gap: P5 tests operator-override
    # (which short-circuits framework_tier_mappings), so framework's actual
    # tier_groups data was never live-tested. P6 omits operator's
    # tier_groups.mappings entirely. The resolver consults framework's
    # tier_groups.mappings.mid → picks sorted([anthropic, google, openai])[0]
    # = anthropic → resolves via aliases.cheap → claude-sonnet-4-6.
    # Then S6 looks up `cheap-pro` which doesn't exist → outcome=skipped,
    # reason=no_pro_variant_for_alias. The test pins the cycle-099 production
    # behavior on the framework path.
    cat > "$WORK_DIR/cfg.yaml" <<YAML
schema_version: 2
framework_defaults:
$(sed 's/^/  /' "$CONFIG")
operator_config:
  prefer_pro_models: true
  skill_models:
    test_skill:
      primary: mid
YAML
    local out provider model_id resolved_alias has_stage3 last_label last_outcome last_reason
    out=$(_resolve_pp test_skill primary)
    provider=$(echo "$out" | jq -r '.resolved_provider')
    model_id=$(echo "$out" | jq -r '.resolved_model_id')
    has_stage3=$(echo "$out" | jq -r '[.resolution_path[]?.label] | any(. == "stage3_tier_groups")')
    resolved_alias=$(echo "$out" | jq -r '[.resolution_path[]? | select(.label=="stage3_tier_groups") | .details.resolved_alias][0] // empty')
    last_label=$(echo "$out" | jq -r '.resolution_path[-1].label')
    last_outcome=$(echo "$out" | jq -r '.resolution_path[-1].outcome')
    last_reason=$(echo "$out" | jq -r '.resolution_path[-1].details.reason // empty')

    [[ "$has_stage3" == "true" ]] || { echo "expected stage3 in path"; echo "$out"; return 1; }
    [[ "$provider" == "anthropic" ]] || { echo "framework-default mid: expected anthropic, got=$provider"; echo "$out"; return 1; }
    [[ "$resolved_alias" == "cheap" ]] || { echo "expected resolved_alias=cheap (mid.anthropic), got=$resolved_alias"; echo "$out"; return 1; }
    [[ "$model_id" == "claude-sonnet-4-6" ]] || { echo "expected claude-sonnet-4-6, got=$model_id"; echo "$out"; return 1; }
    # S6 is emitted but skipped because `cheap-pro` alias doesn't exist.
    [[ "$last_label" == "stage6_prefer_pro_overlay" ]] || { echo "expected last stage6, got=$last_label"; echo "$out"; return 1; }
    [[ "$last_outcome" == "skipped" ]] || { echo "expected S6 skipped, got=$last_outcome"; echo "$out"; return 1; }
    [[ "$last_reason" == "no_pro_variant_for_alias" ]] || { echo "expected no_pro_variant_for_alias, got=$last_reason"; echo "$out"; return 1; }
}
