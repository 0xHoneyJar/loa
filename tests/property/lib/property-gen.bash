#!/usr/bin/env bash
# =============================================================================
# tests/property/lib/property-gen.bash
#
# cycle-099 Sprint 2D.d (T2.6 closure) — bash property generator for the
# FR-3.9 6-stage resolver per SDD §5 + DD-6 + SC-14.
#
# Emits N random valid model-config + operator_config combinations to stdout
# and exposes ~6 invariant-specific generator functions. Each invariant
# generator accepts an integer seed and emits:
#   * the merged-config YAML on stdout
#   * a top-level `_property_query` block declaring which (skill, role) the
#     test should query and the expected outcome shape
#
# The resolver (`.claude/scripts/lib/model-resolver.py`) ignores the
# `_property_query` block — it only consumes `framework_defaults` /
# `operator_config` / `runtime_state`. Bats consumes `_property_query` via
# `yq` to drive the assertion.
#
# Determinism: SHA-256 of "${seed}|${tag}" → integer mod range. Same seed +
# tag → same value, across hosts. CI logs the failing seed; operators
# reproduce by setting LOA_PROPERTY_SEED=N and running the bats locally.
#
# Per DD-6: 0 new dependencies (python3 is already required by the resolver).
# =============================================================================

# Idempotent source guard.
[[ "${LOA_PROPERTY_GEN_LOADED:-0}" == "1" ]] && return 0
LOA_PROPERTY_GEN_LOADED=1

# -----------------------------------------------------------------------------
# Internal helpers
# -----------------------------------------------------------------------------

# Reject control-byte injection in seed/tag. These flow into a YAML scalar
# (the generated config) and into Python via stdin; control bytes here
# would either crash YAML parsing or smuggle line-continuation. The
# resolver itself rejects [INPUT-CONTROL-BYTE], but the generator must
# reject earlier so a buggy caller doesn't accidentally produce
# error-shaped output that masquerades as a "real" property failure.
_prop_assert_clean() {
    local label="$1" val="$2"
    if printf '%s' "$val" | LC_ALL=C grep -q '[[:cntrl:]]'; then
        printf '[property-gen] %s contains control byte; refusing\n' "$label" >&2
        return 1
    fi
    return 0
}

# Hash (seed,tag) → integer in [0, max). Stable across hosts (SHA-256).
prop_rand_int() {
    local seed="$1" tag="$2" max="$3"
    _prop_assert_clean "seed" "$seed" || return 1
    _prop_assert_clean "tag" "$tag" || return 1
    if [[ -z "$max" ]] || ! [[ "$max" =~ ^[1-9][0-9]*$ ]]; then
        printf '[property-gen] invalid max=%q\n' "$max" >&2
        return 1
    fi
    printf '%s|%s' "$seed" "$tag" | LOA_PROP_MAX="$max" python3 -c '
import hashlib, os, sys
data = sys.stdin.buffer.read()
m = int(os.environ["LOA_PROP_MAX"])
print(int(hashlib.sha256(data).hexdigest()[:8], 16) % m)
'
}

# Pick one element from a list deterministically by (seed, tag).
prop_pick() {
    local seed="$1" tag="$2"; shift 2
    local n
    n=$(prop_rand_int "$seed" "$tag" "$#") || return 1
    # bash arrays are 1-indexed in `set --` positional context; n is 0-indexed
    eval "printf '%s\n' \"\${$((n + 1))}\""
}

# Pool of values that satisfy the resolver's pattern constraints.
# These also avoid known reserved tier names where the test contract
# would be ambiguous.
_PROP_PROVIDERS=(anthropic openai google operator-extra-vendor)
_PROP_MODEL_IDS=(model-alpha-1 model-beta-2 model-gamma-3.4 model-delta_5 alpha.7 beta_9 m1 m2)
_PROP_ALIAS_NAMES=(opus haiku sonnet flash gpt5 nova lite mini)
_PROP_ALIAS_NAMES_PRO=(opus haiku sonnet)   # have *-pro variants in the framework block
_PROP_SKILL_NAMES=(researcher writer reviewer flatline_protocol bridgebuilder gardener)
_PROP_ROLE_NAMES=(primary secondary tertiary reviewer)
_PROP_TIER_NAMES=(max cheap mid tiny)

# -----------------------------------------------------------------------------
# Invariant generators
#
# Contract: each function reads a single argument $seed (integer) and
# emits exactly one merged-config YAML to stdout. The YAML's
# `_property_query` block declares the (skill, role) tuple to query and
# the expected outcome family. The bats runner reads both via yq.
# -----------------------------------------------------------------------------

# Invariant 1: when both `skill_models.<skill>.<role>: provider:model_id`
# (S1) and legacy `<skill>.models.<role>: alias` (S4) are present, S1 wins.
# Resolution path MUST start with stage 1; MUST NOT contain stage 4.
prop_gen_inv1_config() {
    local seed="$1"
    local skill role provider model_id alias_name framework_target
    skill=$(prop_pick "$seed" "inv1.skill" "${_PROP_SKILL_NAMES[@]}") || return 1
    role=$(prop_pick "$seed" "inv1.role" "${_PROP_ROLE_NAMES[@]}") || return 1
    provider=$(prop_pick "$seed" "inv1.provider" "${_PROP_PROVIDERS[@]}") || return 1
    model_id=$(prop_pick "$seed" "inv1.model_id" "${_PROP_MODEL_IDS[@]}") || return 1
    alias_name=$(prop_pick "$seed" "inv1.alias" "${_PROP_ALIAS_NAMES[@]}") || return 1
    framework_target=$(prop_pick "$seed" "inv1.framework_target" "${_PROP_MODEL_IDS[@]}") || return 1
    cat <<YAML
_property_query:
  invariant: 1
  skill: "$skill"
  role: "$role"
  expected_pin_provider: "$provider"
  expected_pin_model_id: "$model_id"
schema_version: 2
framework_defaults:
  providers:
    $provider:
      models:
        $model_id:
          context_window: 200000
        $framework_target:
          context_window: 100000
  aliases:
    $alias_name: { provider: $provider, model_id: $framework_target }
  agents: {}
operator_config:
  skill_models:
    $skill:
      $role: "$provider:$model_id"
  $skill:
    models:
      $role: $alias_name
YAML
}

# Invariant 2: same id in BOTH `model_aliases_extra` and
# `model_aliases_override` → `[MODEL-EXTRA-OVERRIDE-CONFLICT]` error
# (stage 0). Never silent tiebreaker.
prop_gen_inv2_config() {
    local seed="$1"
    local skill role conflict_id provider extra_target_id override_target_id
    skill=$(prop_pick "$seed" "inv2.skill" "${_PROP_SKILL_NAMES[@]}") || return 1
    role=$(prop_pick "$seed" "inv2.role" "${_PROP_ROLE_NAMES[@]}") || return 1
    conflict_id=$(prop_pick "$seed" "inv2.conflict" "${_PROP_ALIAS_NAMES[@]}") || return 1
    provider=$(prop_pick "$seed" "inv2.provider" "${_PROP_PROVIDERS[@]}") || return 1
    extra_target_id=$(prop_pick "$seed" "inv2.extra_target" "${_PROP_MODEL_IDS[@]}") || return 1
    override_target_id=$(prop_pick "$seed" "inv2.override_target" "${_PROP_MODEL_IDS[@]}") || return 1
    cat <<YAML
_property_query:
  invariant: 2
  skill: "$skill"
  role: "$role"
  expected_error_code: "[MODEL-EXTRA-OVERRIDE-CONFLICT]"
  expected_stage_failed: 0
schema_version: 2
framework_defaults:
  providers:
    $provider:
      models:
        $extra_target_id:
          context_window: 100000
        $override_target_id:
          context_window: 100000
  aliases: {}
  agents: {}
operator_config:
  model_aliases_extra:
    $conflict_id: { provider: $provider, model_id: $extra_target_id }
  model_aliases_override:
    $conflict_id: { provider: $provider, model_id: $override_target_id }
YAML
}

# Invariant 3: `prefer_pro_models: true` overlay always last in
# resolution_path. Generates a config that resolves at S2 (direct alias
# hit) with a known *-pro framework variant, AND `prefer_pro_models: true`.
# Stage 6 entry MUST exist; MUST be the last entry of resolution_path.
prop_gen_inv3_config() {
    local seed="$1"
    local skill role provider alias_base alias_pro
    skill=$(prop_pick "$seed" "inv3.skill" "${_PROP_SKILL_NAMES[@]}") || return 1
    role=$(prop_pick "$seed" "inv3.role" "${_PROP_ROLE_NAMES[@]}") || return 1
    provider=$(prop_pick "$seed" "inv3.provider" "${_PROP_PROVIDERS[@]}") || return 1
    alias_base=$(prop_pick "$seed" "inv3.alias_base" "${_PROP_ALIAS_NAMES_PRO[@]}") || return 1
    alias_pro="${alias_base}-pro"
    cat <<YAML
_property_query:
  invariant: 3
  skill: "$skill"
  role: "$role"
  expected_alias_base: "$alias_base"
  expected_alias_pro: "$alias_pro"
schema_version: 2
framework_defaults:
  providers:
    $provider:
      models:
        ${alias_base}-base-model:
          context_window: 200000
        ${alias_base}-pro-model:
          context_window: 400000
  aliases:
    $alias_base: { provider: $provider, model_id: ${alias_base}-base-model }
    $alias_pro: { provider: $provider, model_id: ${alias_base}-pro-model }
  agents: {}
operator_config:
  prefer_pro_models: true
  skill_models:
    $skill:
      $role: $alias_base
YAML
}

# Invariant 4: deprecation warning emitted iff stage 4 was the resolution
# path. Generates two flavours per seed (driven by a coin flip):
#   * legacy_only=true  → only legacy `<skill>.models.<role>` set; expects
#     stage4 hit + warning="[LEGACY-SHAPE-DEPRECATED]"
#   * legacy_only=false → only `skill_models.<skill>.<role>` set, no legacy;
#     expects NO warning anywhere
# The biconditional: warning ⟺ stage 4 in resolution_path.
prop_gen_inv4_config() {
    local seed="$1"
    local skill role provider alias_name model_target legacy_only_n legacy_only
    skill=$(prop_pick "$seed" "inv4.skill" "${_PROP_SKILL_NAMES[@]}") || return 1
    role=$(prop_pick "$seed" "inv4.role" "${_PROP_ROLE_NAMES[@]}") || return 1
    provider=$(prop_pick "$seed" "inv4.provider" "${_PROP_PROVIDERS[@]}") || return 1
    alias_name=$(prop_pick "$seed" "inv4.alias" "${_PROP_ALIAS_NAMES[@]}") || return 1
    model_target=$(prop_pick "$seed" "inv4.target" "${_PROP_MODEL_IDS[@]}") || return 1
    legacy_only_n=$(prop_rand_int "$seed" "inv4.flavour" 2) || return 1
    if [[ "$legacy_only_n" == "0" ]]; then
        legacy_only="true"
    else
        legacy_only="false"
    fi
    cat <<YAML
_property_query:
  invariant: 4
  skill: "$skill"
  role: "$role"
  legacy_only: $legacy_only
schema_version: 2
framework_defaults:
  providers:
    $provider:
      models:
        $model_target:
          context_window: 100000
  aliases:
    $alias_name: { provider: $provider, model_id: $model_target }
  agents: {}
operator_config:
YAML
    if [[ "$legacy_only" == "true" ]]; then
        # Legacy shape only — S4 path
        cat <<YAML
  $skill:
    models:
      $role: $alias_name
YAML
    else
        # Modern shape only — S2 direct-alias path; no legacy block
        cat <<YAML
  skill_models:
    $skill:
      $role: $alias_name
YAML
    fi
}

# Invariant 5: operator-set tier_groups.mappings precedence over framework
# default. Generator sets DIFFERENT alias targets in operator vs framework
# tier_groups for the same (tier, provider) cell, both aliases existing in
# framework_aliases pointing to DIFFERENT models. Resolver MUST resolve via
# the operator's alias.
prop_gen_inv5_config() {
    local seed="$1"
    local skill role tier provider operator_alias framework_alias operator_target framework_target
    skill=$(prop_pick "$seed" "inv5.skill" "${_PROP_SKILL_NAMES[@]}") || return 1
    role=$(prop_pick "$seed" "inv5.role" "${_PROP_ROLE_NAMES[@]}") || return 1
    tier=$(prop_pick "$seed" "inv5.tier" "${_PROP_TIER_NAMES[@]}") || return 1
    provider=$(prop_pick "$seed" "inv5.provider" "${_PROP_PROVIDERS[@]}") || return 1
    # Two distinct alias names that both resolve in framework_aliases but
    # point to distinct models. Suffixes guarantee distinctness without
    # depending on prop_pick's randomness producing different values.
    operator_alias=$(prop_pick "$seed" "inv5.opaa" "${_PROP_ALIAS_NAMES[@]}")-op || return 1
    framework_alias=$(prop_pick "$seed" "inv5.fwaa" "${_PROP_ALIAS_NAMES[@]}")-fw || return 1
    operator_target=$(prop_pick "$seed" "inv5.optgt" "${_PROP_MODEL_IDS[@]}")-operator || return 1
    framework_target=$(prop_pick "$seed" "inv5.fwtgt" "${_PROP_MODEL_IDS[@]}")-framework || return 1
    cat <<YAML
_property_query:
  invariant: 5
  skill: "$skill"
  role: "$role"
  tier: "$tier"
  expected_resolved_alias: "$operator_alias"
  expected_resolved_model_id: "$operator_target"
schema_version: 2
framework_defaults:
  providers:
    $provider:
      models:
        $operator_target:
          context_window: 100000
        $framework_target:
          context_window: 100000
  aliases:
    $operator_alias: { provider: $provider, model_id: $operator_target }
    $framework_alias: { provider: $provider, model_id: $framework_target }
  tier_groups:
    mappings:
      $tier:
        $provider: $framework_alias
  agents: {}
operator_config:
  tier_groups:
    mappings:
      $tier:
        $provider: $operator_alias
  skill_models:
    $skill:
      $role: $tier
YAML
}

# Invariant 6: unmapped tier produces FR-3.8 fail-closed error
# (`[TIER-NO-MAPPING]`); MUST NOT silently fall through to S5.
# Generator sets:
#   * a tier-tag in skill_models that resolves at S2 → cascades to S3
#   * NO tier_groups.mappings for that tier (operator OR framework)
#   * a working `agents.<skill>` that WOULD resolve at S5 if reached
# The invariant is that resolver returns the S3 error, never the S5 hit.
prop_gen_inv6_config() {
    local seed="$1"
    local skill role tier provider s5_alias s5_target
    skill=$(prop_pick "$seed" "inv6.skill" "${_PROP_SKILL_NAMES[@]}") || return 1
    role=$(prop_pick "$seed" "inv6.role" "${_PROP_ROLE_NAMES[@]}") || return 1
    tier=$(prop_pick "$seed" "inv6.tier" "${_PROP_TIER_NAMES[@]}") || return 1
    provider=$(prop_pick "$seed" "inv6.provider" "${_PROP_PROVIDERS[@]}") || return 1
    s5_alias=$(prop_pick "$seed" "inv6.s5_alias" "${_PROP_ALIAS_NAMES[@]}")-s5 || return 1
    s5_target=$(prop_pick "$seed" "inv6.s5_target" "${_PROP_MODEL_IDS[@]}")-s5 || return 1
    cat <<YAML
_property_query:
  invariant: 6
  skill: "$skill"
  role: "$role"
  tier: "$tier"
  expected_error_code: "[TIER-NO-MAPPING]"
  expected_stage_failed: 3
schema_version: 2
framework_defaults:
  providers:
    $provider:
      models:
        $s5_target:
          context_window: 100000
  aliases:
    $s5_alias: { provider: $provider, model_id: $s5_target }
  tier_groups:
    mappings: {}
  agents:
    $skill:
      model: $s5_alias
operator_config:
  skill_models:
    $skill:
      $role: $tier
YAML
}

# -----------------------------------------------------------------------------
# Invariant dispatcher (keeps the bats runner small).
# -----------------------------------------------------------------------------

prop_gen() {
    local invariant="$1" seed="$2"
    case "$invariant" in
        1) prop_gen_inv1_config "$seed" ;;
        2) prop_gen_inv2_config "$seed" ;;
        3) prop_gen_inv3_config "$seed" ;;
        4) prop_gen_inv4_config "$seed" ;;
        5) prop_gen_inv5_config "$seed" ;;
        6) prop_gen_inv6_config "$seed" ;;
        *) printf '[property-gen] unknown invariant=%q\n' "$invariant" >&2; return 1 ;;
    esac
}
