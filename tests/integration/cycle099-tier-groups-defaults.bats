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

# Helper: run resolver against framework_defaults + operator_config snippet
_resolve() {
    local tier="$1" override_yaml="${2:-{}}"
    cat > "$WORK_DIR/cfg.yaml" <<YAML
schema_version: 2
framework_defaults: $(yq -o json '.' "$CONFIG" | python3 -c 'import json,sys,yaml; print(yaml.safe_dump(json.load(sys.stdin)))' | sed 's/^/  /')
operator_config:
  skill_models:
    probe_skill:
      primary: $tier
$override_yaml
YAML
    python3 "$RESOLVER" resolve --config "$WORK_DIR/cfg.yaml" --skill probe_skill --role primary
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

@test "T4 — each tier resolves cleanly via FR-3.9 stage 2/3 path against production framework_defaults" {
    # Synthesize: operator declares skill_models.probe_skill.primary: <tier>.
    # Resolver picks provider=sorted(framework_tier_mappings_keys)[0]=anthropic.
    # Verify resolved_provider+model_id non-empty + resolution_path includes stage 3.
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
        local out
        out=$(python3 "$RESOLVER" resolve --config "$cfg_yaml" --skill probe_skill --role primary)
        local provider model_id stage3
        provider=$(echo "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("resolved_provider",""))')
        model_id=$(echo "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("resolved_model_id",""))')
        stage3=$(echo "$out" | python3 -c 'import json,sys; r=json.load(sys.stdin).get("resolution_path",[]); print("|".join(str(e.get("stage")) for e in r))')
        [[ -n "$provider" ]] || { echo "tier=$tier resolved_provider empty: $out" >&2; return 1; }
        [[ -n "$model_id" ]] || { echo "tier=$tier resolved_model_id empty: $out" >&2; return 1; }
        # stage path should include 3 (tier_groups hit) somewhere
        if [[ "$stage3" != *"3"* ]]; then
            echo "tier=$tier did not pass through stage 3 (got stages=$stage3)" >&2
            return 1
        fi
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
