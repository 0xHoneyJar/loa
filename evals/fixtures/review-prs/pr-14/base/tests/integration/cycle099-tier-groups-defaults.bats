#!/usr/bin/env bats
# =============================================================================
# tests/integration/cycle099-tier-groups-defaults.bats
#
# cycle-099 Sprint 2E (T2.7) — verify `.claude/defaults/model-config.yaml`
# `tier_groups.mappings` is populated per SDD §3.1.2 with probe-confirmed
# defaults, AND that each (tier, provider) cell resolves cleanly through
# the FR-3.9 6-stage resolver.
#
# Test surface (T-series, T1-T6):
#   T1   — 4 tiers × 3 providers = 12 mappings populated
#   T2   — Every alias name in mappings is declared in `aliases:` block
#   T3   — Every alias resolves to a model declared in `providers.<p>.models`
#   T4   — Each tier resolves cleanly via FR-3.9 stage 2/3 path
#   T5   — Per-provider operator override at stage 2 wins over framework defaults
#   T6   — `denylist` and `max_cost_per_session_micro_usd` preserved (cycle-095 carry-forward)
# =============================================================================

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    CONFIG="$PROJECT_ROOT/.claude/defaults/model-config.yaml"
    RESOLVER="$PROJECT_ROOT/.claude/scripts/lib/model-resolver.py"
    [[ -f "$CONFIG" ]] || skip "model-config.yaml not present"
    [[ -f "$RESOLVER" ]] || skip "model-resolver.py not present"
    command -v yq >/dev/null 2>&1 || skip "yq not present"
    command -v python3 >/dev/null 2>&1 || skip "python3 not present"
    WORK_DIR="$(mktemp -d)"
}

teardown() {
    if [[ -n "${WORK_DIR:-}" ]] && [[ -d "$WORK_DIR" ]]; then
        rm -rf "$WORK_DIR"
    fi
    return 0
}

@test "T1 — tier_groups.mappings has 4 tiers × 3 providers populated" {
    # Verify presence of all 4 tier names + 3 provider keys per tier.
    for tier in max cheap mid tiny; do
        local provider_keys
        provider_keys=$(yq ".tier_groups.mappings.$tier | keys | .[]" "$CONFIG")
        [[ -n "$provider_keys" ]] || {
            echo "tier=$tier missing from tier_groups.mappings" >&2
            return 1
        }
        for provider in anthropic openai google; do
            local val
            val=$(yq ".tier_groups.mappings.$tier.$provider" "$CONFIG")
            if [[ -z "$val" ]] || [[ "$val" == "null" ]]; then
                echo "tier=$tier provider=$provider missing alias" >&2
                return 1
            fi
        done
    done
}

@test "T2 — every tier_groups alias name is declared in aliases: block" {
    local missing=0
    for tier in max cheap mid tiny; do
        for provider in anthropic openai google; do
            local alias
            alias=$(yq ".tier_groups.mappings.$tier.$provider" "$CONFIG")
            local resolved
            resolved=$(yq ".aliases.\"$alias\"" "$CONFIG")
            if [[ -z "$resolved" ]] || [[ "$resolved" == "null" ]]; then
                echo "alias '$alias' (tier=$tier provider=$provider) NOT in aliases:" >&2
                missing=$((missing + 1))
            fi
        done
    done
    [[ "$missing" == "0" ]] || return 1
}

@test "T3 — every tier_groups alias resolves to a model declared in providers.<p>.models" {
    local missing=0
    for tier in max cheap mid tiny; do
        for provider in anthropic openai google; do
            local alias resolved model_provider model_id
            alias=$(yq ".tier_groups.mappings.$tier.$provider" "$CONFIG")
            resolved=$(yq ".aliases.\"$alias\"" "$CONFIG")
            # resolved is "provider:model_id"; split.
            model_provider="${resolved%%:*}"
            model_id="${resolved#*:}"
            local model_decl
            model_decl=$(yq ".providers.\"$model_provider\".models.\"$model_id\"" "$CONFIG")
            if [[ -z "$model_decl" ]] || [[ "$model_decl" == "null" ]]; then
                echo "model '$resolved' (tier=$tier provider=$provider alias=$alias) NOT in providers.$model_provider.models" >&2
                missing=$((missing + 1))
            fi
        done
    done
    [[ "$missing" == "0" ]] || return 1
}

@test "T4 — each tier resolves cleanly via FR-3.9 stage 2/3 against framework defaults (anthropic cell)" {
    # Synthesize: operator declares skill_models.probe_skill.primary: <tier>.
    # Resolver picks provider=sorted(framework_tier_mappings_keys)[0]=anthropic.
    # This test ONLY covers the anthropic cell of each tier; T4b covers the
    # remaining openai/google cells via per-cell forced-single-provider override.
    local cfg_yaml="$WORK_DIR/probe_cfg.yaml"
    for tier in max cheap mid tiny; do
        cat > "$cfg_yaml" <<YAML
schema_version: 2
framework_defaults:
$(sed 's/^/  /' "$CONFIG")
operator_config:
  skill_models:
    probe_skill:
      primary: $tier
YAML
        local out provider model_id has_stage3
        out=$(python3 "$RESOLVER" resolve --config "$cfg_yaml" --skill probe_skill --role primary)
        provider=$(echo "$out" | jq -r '.resolved_provider // empty')
        model_id=$(echo "$out" | jq -r '.resolved_model_id // empty')
        # MED-3 fix: jq-explicit stage-3 check (was `*"3"*` substring match — would
        # false-pass on stage 13/30 if resolver ever expands stage range).
        has_stage3=$(echo "$out" | jq -r '[.resolution_path[]?.stage] | any(. == 3)')
        [[ -n "$provider" ]] || { echo "tier=$tier resolved_provider empty: $out" >&2; return 1; }
        [[ -n "$model_id" ]] || { echo "tier=$tier resolved_model_id empty: $out" >&2; return 1; }
        [[ "$has_stage3" == "true" ]] || { echo "tier=$tier missing stage 3: $out" >&2; return 1; }
        [[ "$provider" == "anthropic" ]] || { echo "tier=$tier expected anthropic (sort tiebreak), got=$provider" >&2; return 1; }
    done
}

@test "T4b — every tier × provider cell resolves cleanly via per-cell forced-single-provider override" {
    # Coverage gap from T4: resolver picks sorted(mapping.keys())[0], so T4
    # only ever exercises the anthropic cell. T4b drives each of the 12
    # (tier, provider) cells deterministically by overriding operator's
    # tier_groups.mappings.<tier> to ONLY include one provider — forcing the
    # resolver's provider-pick to that one. Verifies each new alias
    # (gpt-5.5-pro, gpt-5.5, gpt-5.3-codex) resolves through to a model_id.
    local cfg_yaml="$WORK_DIR/probe_t4b.yaml"
    local total=0 fails=0
    for tier in max cheap mid tiny; do
        for provider in anthropic openai google; do
            local alias
            alias=$(yq -r ".tier_groups.mappings.$tier.$provider" "$CONFIG")
            cat > "$cfg_yaml" <<YAML
schema_version: 2
framework_defaults:
$(sed 's/^/  /' "$CONFIG")
operator_config:
  tier_groups:
    mappings:
      $tier:
        $provider: $alias
  skill_models:
    probe_skill:
      primary: $tier
YAML
            local out resolved_provider resolved_model_id
            out=$(python3 "$RESOLVER" resolve --config "$cfg_yaml" --skill probe_skill --role primary)
            resolved_provider=$(echo "$out" | jq -r '.resolved_provider // empty')
            resolved_model_id=$(echo "$out" | jq -r '.resolved_model_id // empty')
            total=$((total + 1))
            if [[ "$resolved_provider" != "$provider" ]] || [[ -z "$resolved_model_id" ]]; then
                echo "tier=$tier provider=$provider alias=$alias FAILED → got provider=$resolved_provider model_id=$resolved_model_id" >&2
                echo "$out" >&2
                fails=$((fails + 1))
            fi
        done
    done
    [[ "$fails" == "0" ]] || { echo "T4b: $fails of $total cells failed" >&2; return 1; }
    [[ "$total" == "12" ]] || { echo "T4b: expected 12 cells, ran $total" >&2; return 1; }
}

@test "T4c — framework default tier_groups (no operator override) resolves via S3 anthropic cell" {
    # Closes HIGH-2 (gp): explicit test that framework_defaults.tier_groups.mappings
    # data is consulted when operator omits its own tier_groups.mappings.<tier>.
    # This is the production "operator only adds skill_models" scenario.
    local cfg_yaml="$WORK_DIR/probe_t4c.yaml"
    for tier in max cheap mid tiny; do
        cat > "$cfg_yaml" <<YAML
schema_version: 2
framework_defaults:
$(sed 's/^/  /' "$CONFIG")
operator_config:
  skill_models:
    probe_skill:
      primary: $tier
YAML
        local out resolved_alias resolved_provider expected_alias
        out=$(python3 "$RESOLVER" resolve --config "$cfg_yaml" --skill probe_skill --role primary)
        resolved_provider=$(echo "$out" | jq -r '.resolved_provider // empty')
        resolved_alias=$(echo "$out" | jq -r '[.resolution_path[]? | select(.label=="stage3_tier_groups") | .details.resolved_alias][0] // empty')
        expected_alias=$(yq -r ".tier_groups.mappings.$tier.anthropic" "$CONFIG")
        [[ "$resolved_provider" == "anthropic" ]] || { echo "tier=$tier framework path: expected anthropic, got=$resolved_provider"; echo "$out"; return 1; }
        [[ "$resolved_alias" == "$expected_alias" ]] || { echo "tier=$tier framework path: expected resolved_alias=$expected_alias, got=$resolved_alias"; echo "$out"; return 1; }
    done
}

@test "T5 — operator override at tier_groups.mappings wins over framework defaults" {
    # Operator declares: tier_groups.mappings.max.anthropic = cheap (overriding default opus).
    # Verify resolution lands on cheap → claude-sonnet-4-6 (operator wins).
    local cfg_yaml="$WORK_DIR/override.yaml"
    cat > "$cfg_yaml" <<YAML
schema_version: 2
framework_defaults:
$(sed 's/^/  /' "$CONFIG")
operator_config:
  tier_groups:
    mappings:
      max:
        anthropic: cheap
  skill_models:
    probe_skill:
      primary: max
YAML
    local out
    out=$(python3 "$RESOLVER" resolve --config "$cfg_yaml" --skill probe_skill --role primary)
    local model_id
    model_id=$(echo "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("resolved_model_id",""))')
    [[ "$model_id" == "claude-sonnet-4-6" ]] || {
        echo "expected operator override → claude-sonnet-4-6, got $model_id" >&2
        echo "$out" >&2
        return 1
    }
}

@test "T6 — denylist and max_cost_per_session_micro_usd preserved (cycle-095 carry-forward)" {
    # yq -o json strips trailing comments that come back inline with the
    # scalar in default YAML output mode.
    local denylist_kind cost_cap
    denylist_kind=$(yq -o json '.tier_groups.denylist | type' "$CONFIG")
    [[ "$denylist_kind" == "\"!!seq\"" ]] || [[ "$denylist_kind" == "array" ]] || {
        echo "denylist not a sequence: $denylist_kind" >&2; return 1;
    }
    local denylist_count
    denylist_count=$(yq -o json '.tier_groups.denylist | length' "$CONFIG")
    [[ "$denylist_count" == "0" ]] || { echo "denylist has entries: $denylist_count" >&2; return 1; }
    cost_cap=$(yq -o json '.tier_groups.max_cost_per_session_micro_usd' "$CONFIG")
    [[ "$cost_cap" == "null" ]] || { echo "cost cap not preserved: $cost_cap" >&2; return 1; }
}
