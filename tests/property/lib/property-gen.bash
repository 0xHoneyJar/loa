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
# Uses bash slice substitution `${@:idx:1}` instead of `eval` to keep the
# code path metaprogramming-free (cypherpunk HIGH-4: avoid eval-on-positional).
# Validates `n` post-Python (cypherpunk MED-6: bounds-check defense even
# though prop_rand_int's mod-N already constrains n in [0, $#)).
prop_pick() {
    local seed="$1" tag="$2"; shift 2
    local count=$#
    if (( count == 0 )); then
        printf '[property-gen] prop_pick called with empty list\n' >&2
        return 1
    fi
    local n
    n=$(prop_rand_int "$seed" "$tag" "$count") || return 1
    if ! [[ "$n" =~ ^(0|[1-9][0-9]*)$ ]] || (( n < 0 )) || (( n >= count )); then
        printf '[property-gen] prop_pick got invalid n=%q (count=%q)\n' "$n" "$count" >&2
        return 1
    fi
    printf '%s\n' "${@:$((n + 1)):1}"
}

# Pool of values that satisfy the resolver's pattern constraints.
# These also avoid known reserved tier names where the test contract
# would be ambiguous.
#
# Pool-design invariants:
#   * `_PROP_ALIAS_NAMES` MUST NOT contain entries with `-pro` suffix —
#     INV3 constructs `${alias_base}-pro` and registers it in
#     framework_aliases; collision would create silent shadowing.
#   * `_PROP_ALIAS_NAMES` and `_PROP_ALIAS_NAMES_PRO` MUST be disjoint
#     from `_PROP_TIER_NAMES` (max/cheap/mid/tiny) — otherwise IMP-007
#     alias-collides-with-tier triggers and the resolver takes the
#     tier-tag interpretation, breaking direct-alias-path assertions.
_PROP_PROVIDERS=(anthropic openai google operator-extra-vendor)
_PROP_MODEL_IDS=(model-alpha-1 model-beta-2 model-gamma-3.4 model-delta_5 alpha.7 beta_9 m1 m2)
_PROP_ALIAS_NAMES=(opus haiku sonnet flash gpt5 nova lite gemini)
# Cypherpunk MED-4: expanded from 3 → 8 entries to widen INV3's
# distinct-config space from ~288 to ~768. Each entry has a `-pro`
# variant registered by the inv3 generator at YAML emission time.
_PROP_ALIAS_NAMES_PRO=(opus haiku sonnet flash nova premium expert deluxe)
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
#
# Cypherpunk HIGH-1: `framework_target` carries `-fwt` suffix to guarantee
# disjointness from `model_id` (both pick from `_PROP_MODEL_IDS`).
# Without the suffix, a 1/8 collision rate made the
# `actual_model_id == expected_pin_model_id` assertion vacuously true on
# ~12 of 100 iterations even if a buggy resolver took the S4 path.
prop_gen_inv1_config() {
    local seed="$1"
    local skill role provider model_id alias_name framework_target
    skill=$(prop_pick "$seed" "inv1.skill" "${_PROP_SKILL_NAMES[@]}") || return 1
    role=$(prop_pick "$seed" "inv1.role" "${_PROP_ROLE_NAMES[@]}") || return 1
    provider=$(prop_pick "$seed" "inv1.provider" "${_PROP_PROVIDERS[@]}") || return 1
    model_id=$(prop_pick "$seed" "inv1.model_id" "${_PROP_MODEL_IDS[@]}") || return 1
    alias_name=$(prop_pick "$seed" "inv1.alias" "${_PROP_ALIAS_NAMES[@]}") || return 1
    framework_target=$(prop_pick "$seed" "inv1.framework_target" "${_PROP_MODEL_IDS[@]}")-fwt || return 1
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

# Invariant 2: same-priority pre-validation mechanisms always produce
# an error (stage 0). Never silent tiebreaker.
#
# Two flavours via `seed mod 2`:
#   F0: id collides in `model_aliases_extra` and `model_aliases_override`
#       → `[MODEL-EXTRA-OVERRIDE-CONFLICT]`
#   F1: `model_aliases_override` targets unknown framework model_id
#       → `[OVERRIDE-UNKNOWN-MODEL]`
#
# Cypherpunk MED-1: targets carry `-extra-tgt` / `-override-tgt` suffixes
# to guarantee distinct framework_models keys (without suffix, both pick
# from `_PROP_MODEL_IDS` with 1/8 collision rate, producing degenerate
# same-target configs).
prop_gen_inv2_config() {
    local seed="$1"
    local skill role conflict_id provider extra_target_id override_target_id flavour_n
    skill=$(prop_pick "$seed" "inv2.skill" "${_PROP_SKILL_NAMES[@]}") || return 1
    role=$(prop_pick "$seed" "inv2.role" "${_PROP_ROLE_NAMES[@]}") || return 1
    conflict_id=$(prop_pick "$seed" "inv2.conflict" "${_PROP_ALIAS_NAMES[@]}") || return 1
    provider=$(prop_pick "$seed" "inv2.provider" "${_PROP_PROVIDERS[@]}") || return 1
    extra_target_id=$(prop_pick "$seed" "inv2.extra_target" "${_PROP_MODEL_IDS[@]}")-extra-tgt || return 1
    override_target_id=$(prop_pick "$seed" "inv2.override_target" "${_PROP_MODEL_IDS[@]}")-override-tgt || return 1
    flavour_n=$(prop_rand_int "$seed" "inv2.flavour" 2) || return 1

    if [[ "$flavour_n" == "0" ]]; then
        # F0: extra + override id collision
        cat <<YAML
_property_query:
  invariant: 2
  flavour: "extra_override_id_collision"
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
    else
        # F1: override targets a model_id that is NOT in framework models
        local unknown_id="${override_target_id}-not-in-framework"
        cat <<YAML
_property_query:
  invariant: 2
  flavour: "override_unknown_model"
  skill: "$skill"
  role: "$role"
  expected_error_code: "[OVERRIDE-UNKNOWN-MODEL]"
  expected_stage_failed: 0
schema_version: 2
framework_defaults:
  providers:
    $provider:
      models:
        $extra_target_id:
          context_window: 100000
  aliases: {}
  agents: {}
operator_config:
  model_aliases_override:
    $conflict_id: { provider: $provider, model_id: $unknown_id }
YAML
    fi
}

# Invariant 3: `prefer_pro_models` overlay (S6) — exactness invariants:
#   * `prefer_pro_models: false` (or absent) ⟹ NO stage 6 entry in path.
#   * `prefer_pro_models: true`  ⟹ exactly one stage 6 entry, AND it is
#     the LAST entry of resolution_path.
#
# Cypherpunk CRIT-1 / GP HIGH-1: multi-flavour generator covers all
# distinct emission-paths so a regression that mis-orders S6 cannot ship
# silently. Each invocation chooses one of 8 flavours via `seed mod 8`:
#
#   F0: prefer_pro=false, S2-direct-alias path → no S6 entry
#   F1: prefer_pro=true,  S1-explicit-pin path  → S6 skipped:no_alias_to_overlay (last)
#   F2: prefer_pro=true,  S2-direct-alias, with pro variant → S6 applied (last)
#   F3: prefer_pro=true,  S2-direct-alias, NO pro variant → S6 skipped:no_pro_variant_for_alias (last)
#   F4: prefer_pro=true,  S3-tier-cascade, with pro variant → S6 applied (last)
#   F5: prefer_pro=true,  S4-legacy + respect_prefer_pro=true, with pro variant → S6 applied (last)
#   F6: prefer_pro=true,  S4-legacy WITHOUT respect_prefer_pro → S6 skipped:legacy_shape_without_respect_prefer_pro (last)
#   F7: prefer_pro=true,  S5-framework-default, with pro variant → S6 applied (last)
prop_gen_inv3_config() {
    local seed="$1"
    local skill role provider alias_base alias_pro flavour_n flavour
    skill=$(prop_pick "$seed" "inv3.skill" "${_PROP_SKILL_NAMES[@]}") || return 1
    role=$(prop_pick "$seed" "inv3.role" "${_PROP_ROLE_NAMES[@]}") || return 1
    provider=$(prop_pick "$seed" "inv3.provider" "${_PROP_PROVIDERS[@]}") || return 1
    alias_base=$(prop_pick "$seed" "inv3.alias_base" "${_PROP_ALIAS_NAMES_PRO[@]}") || return 1
    alias_pro="${alias_base}-pro"
    flavour_n=$(prop_rand_int "$seed" "inv3.flavour" 8) || return 1

    case "$flavour_n" in
        0)
            flavour="prefer_pro_false_s2"
            cat <<YAML
_property_query:
  invariant: 3
  flavour: "$flavour"
  skill: "$skill"
  role: "$role"
  prefer_pro: false
  expect_stage6_count: 0
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
  skill_models:
    $skill:
      $role: $alias_base
YAML
            ;;
        1)
            flavour="prefer_pro_true_s1_pin"
            local target="${alias_base}-base-model"
            cat <<YAML
_property_query:
  invariant: 3
  flavour: "$flavour"
  skill: "$skill"
  role: "$role"
  prefer_pro: true
  expect_stage6_count: 1
  expect_stage6_outcome: "skipped"
  expect_stage6_reason: "no_alias_to_overlay"
schema_version: 2
framework_defaults:
  providers:
    $provider:
      models:
        $target:
          context_window: 200000
  aliases: {}
  agents: {}
operator_config:
  prefer_pro_models: true
  skill_models:
    $skill:
      $role: "$provider:$target"
YAML
            ;;
        2)
            flavour="prefer_pro_true_s2_with_pro"
            cat <<YAML
_property_query:
  invariant: 3
  flavour: "$flavour"
  skill: "$skill"
  role: "$role"
  prefer_pro: true
  expect_stage6_count: 1
  expect_stage6_outcome: "applied"
  expect_alias_pro: "$alias_pro"
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
            ;;
        3)
            flavour="prefer_pro_true_s2_no_pro_variant"
            # Use a different alias name (not from PRO pool) so no -pro
            # variant exists. We register only the base alias.
            local plain_alias
            plain_alias=$(prop_pick "$seed" "inv3.plain" "${_PROP_ALIAS_NAMES[@]}") || return 1
            cat <<YAML
_property_query:
  invariant: 3
  flavour: "$flavour"
  skill: "$skill"
  role: "$role"
  prefer_pro: true
  expect_stage6_count: 1
  expect_stage6_outcome: "skipped"
  expect_stage6_reason: "no_pro_variant_for_alias"
schema_version: 2
framework_defaults:
  providers:
    $provider:
      models:
        ${plain_alias}-target:
          context_window: 200000
  aliases:
    $plain_alias: { provider: $provider, model_id: ${plain_alias}-target }
  agents: {}
operator_config:
  prefer_pro_models: true
  skill_models:
    $skill:
      $role: $plain_alias
YAML
            ;;
        4)
            flavour="prefer_pro_true_s3_cascade_with_pro"
            local tier
            tier=$(prop_pick "$seed" "inv3.tier" "${_PROP_TIER_NAMES[@]}") || return 1
            cat <<YAML
_property_query:
  invariant: 3
  flavour: "$flavour"
  skill: "$skill"
  role: "$role"
  prefer_pro: true
  expect_stage6_count: 1
  expect_stage6_outcome: "applied"
  expect_alias_pro: "$alias_pro"
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
  tier_groups:
    mappings:
      $tier:
        $provider: $alias_base
  agents: {}
operator_config:
  prefer_pro_models: true
  skill_models:
    $skill:
      $role: $tier
YAML
            ;;
        5)
            flavour="prefer_pro_true_s4_with_respect"
            cat <<YAML
_property_query:
  invariant: 3
  flavour: "$flavour"
  skill: "$skill"
  role: "$role"
  prefer_pro: true
  expect_stage6_count: 1
  expect_stage6_outcome: "applied"
  expect_alias_pro: "$alias_pro"
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
  $skill:
    respect_prefer_pro: true
    models:
      $role: $alias_base
YAML
            ;;
        6)
            flavour="prefer_pro_true_s4_no_respect"
            cat <<YAML
_property_query:
  invariant: 3
  flavour: "$flavour"
  skill: "$skill"
  role: "$role"
  prefer_pro: true
  expect_stage6_count: 1
  expect_stage6_outcome: "skipped"
  expect_stage6_reason: "legacy_shape_without_respect_prefer_pro"
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
  $skill:
    models:
      $role: $alias_base
YAML
            ;;
        7)
            flavour="prefer_pro_true_s5_with_pro"
            cat <<YAML
_property_query:
  invariant: 3
  flavour: "$flavour"
  skill: "$skill"
  role: "$role"
  prefer_pro: true
  expect_stage6_count: 1
  expect_stage6_outcome: "applied"
  expect_alias_pro: "$alias_pro"
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
  agents:
    $skill:
      model: $alias_base
operator_config:
  prefer_pro_models: true
YAML
            ;;
        *)
            printf '[property-gen] inv3 unexpected flavour=%q\n' "$flavour_n" >&2
            return 1
            ;;
    esac
}

# Invariant 4: deprecation warning emitted ⟺ stage 4 was the resolution
# path. Strengthened to per-entry biconditional:
#
#   * any entry has `details.warning == "[LEGACY-SHAPE-DEPRECATED]"`
#       ⟺ that entry's `label == "stage4_legacy_shape"`
#
# i.e., the warning never appears outside the S4 entry, AND every S4
# resolution emits the warning.
#
# Cypherpunk CRIT-2 / GP HIGH-2: three flavours via `seed mod 3` cover
# both the resolvable-S4-path AND the unresolvable-alias-falls-through
# case (where stage 4 returns None, falling through to S5; biconditional
# must still hold — no warning anywhere).
#
#   F0: legacy shape only, alias resolvable → S4 hit + warning
#   F1: modern shape only (skill_models), no legacy block → no S4, no warning
#   F2: legacy shape only, alias UNRESOLVABLE → S4 returns None, falls
#       through to S5 (must be present); biconditional: no warning
prop_gen_inv4_config() {
    local seed="$1"
    local skill role provider alias_name model_target s5_alias s5_target flavour_n flavour
    skill=$(prop_pick "$seed" "inv4.skill" "${_PROP_SKILL_NAMES[@]}") || return 1
    role=$(prop_pick "$seed" "inv4.role" "${_PROP_ROLE_NAMES[@]}") || return 1
    provider=$(prop_pick "$seed" "inv4.provider" "${_PROP_PROVIDERS[@]}") || return 1
    alias_name=$(prop_pick "$seed" "inv4.alias" "${_PROP_ALIAS_NAMES[@]}") || return 1
    model_target=$(prop_pick "$seed" "inv4.target" "${_PROP_MODEL_IDS[@]}")-tgt || return 1
    s5_alias=$(prop_pick "$seed" "inv4.s5_alias" "${_PROP_ALIAS_NAMES[@]}")-s5 || return 1
    s5_target=$(prop_pick "$seed" "inv4.s5_target" "${_PROP_MODEL_IDS[@]}")-s5tgt || return 1
    flavour_n=$(prop_rand_int "$seed" "inv4.flavour" 3) || return 1

    case "$flavour_n" in
        0)
            flavour="legacy_resolvable"
            cat <<YAML
_property_query:
  invariant: 4
  flavour: "$flavour"
  skill: "$skill"
  role: "$role"
  expect_warning: true
  expect_stage4: true
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
  $skill:
    models:
      $role: $alias_name
YAML
            ;;
        1)
            flavour="modern_no_legacy"
            cat <<YAML
_property_query:
  invariant: 4
  flavour: "$flavour"
  skill: "$skill"
  role: "$role"
  expect_warning: false
  expect_stage4: false
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
  skill_models:
    $skill:
      $role: $alias_name
YAML
            ;;
        2)
            flavour="legacy_unresolvable_falls_to_s5"
            # Legacy shape references an alias name that does NOT exist
            # in framework_aliases. Stage 4 returns None per resolver
            # `_stage4_legacy_shape:467`; falls through to stage 5 where
            # `agents.<skill>.model` resolves the alternate alias. No
            # warning emitted anywhere along this path — the resolver
            # only emits the S4 warning when S4 successfully returns.
            cat <<YAML
_property_query:
  invariant: 4
  flavour: "$flavour"
  skill: "$skill"
  role: "$role"
  expect_warning: false
  expect_stage4: false
schema_version: 2
framework_defaults:
  providers:
    $provider:
      models:
        $s5_target:
          context_window: 100000
  aliases:
    $s5_alias: { provider: $provider, model_id: $s5_target }
  agents:
    $skill:
      model: $s5_alias
operator_config:
  $skill:
    models:
      $role: $alias_name-unresolvable
YAML
            ;;
        *)
            printf '[property-gen] inv4 unexpected flavour=%q\n' "$flavour_n" >&2
            return 1
            ;;
    esac
}

# Invariant 5: operator-set tier_groups.mappings precedence over framework
# default. Generator sets DIFFERENT alias targets in operator vs framework
# tier_groups for the same (tier, provider) cell. Resolver MUST resolve
# via the operator's alias.
#
# GP MED-1: two flavours probe the precedence at different granularities:
#   F0: single-provider, both operator and framework have same provider
#       under the tier with different aliases → tests value precedence.
#   F1: multi-provider, operator declares 2 providers under tier and
#       framework declares 2 different providers — verifies the resolver
#       picks `provider=sorted(operator_keys)[0]`, NOT a framework key.
#
# Cypherpunk HIGH-3: bats also asserts `has_stage5=false` so a resolver
# bug that "took stage3 correctly but ALSO emitted stage5" surfaces.
prop_gen_inv5_config() {
    local seed="$1"
    local skill role tier provider operator_alias framework_alias operator_target framework_target flavour_n flavour
    skill=$(prop_pick "$seed" "inv5.skill" "${_PROP_SKILL_NAMES[@]}") || return 1
    role=$(prop_pick "$seed" "inv5.role" "${_PROP_ROLE_NAMES[@]}") || return 1
    tier=$(prop_pick "$seed" "inv5.tier" "${_PROP_TIER_NAMES[@]}") || return 1
    provider=$(prop_pick "$seed" "inv5.provider" "${_PROP_PROVIDERS[@]}") || return 1
    operator_alias=$(prop_pick "$seed" "inv5.opaa" "${_PROP_ALIAS_NAMES[@]}")-op || return 1
    framework_alias=$(prop_pick "$seed" "inv5.fwaa" "${_PROP_ALIAS_NAMES[@]}")-fw || return 1
    operator_target=$(prop_pick "$seed" "inv5.optgt" "${_PROP_MODEL_IDS[@]}")-operator || return 1
    framework_target=$(prop_pick "$seed" "inv5.fwtgt" "${_PROP_MODEL_IDS[@]}")-framework || return 1
    flavour_n=$(prop_rand_int "$seed" "inv5.flavour" 2) || return 1

    if [[ "$flavour_n" == "0" ]]; then
        flavour="single_provider"
        cat <<YAML
_property_query:
  invariant: 5
  flavour: "$flavour"
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
    else
        flavour="multi_provider"
        # Operator has providers `op1` and `op2`; framework has `op2`
        # and `op3`. Resolver picks `provider=sorted(op1, op2)[0]=op1`.
        # The operator-keys are what's sorted, NOT the framework's.
        # This catches bugs where the resolver picks from
        # framework_tier_mappings.keys() when it shouldn't.
        local op1="provider-aaa"
        local op2="provider-bbb"
        local op3="provider-ccc"
        local op1_alias="${operator_alias}-op1"
        local op1_target="${operator_target}-op1"
        local op2_alias="${operator_alias}-op2"
        local op2_target="${operator_target}-op2"
        local op3_alias="${framework_alias}-op3"
        local op3_target="${framework_target}-op3"
        cat <<YAML
_property_query:
  invariant: 5
  flavour: "$flavour"
  skill: "$skill"
  role: "$role"
  tier: "$tier"
  expected_resolved_alias: "$op1_alias"
  expected_resolved_model_id: "$op1_target"
  expected_resolved_provider: "$op1"
schema_version: 2
framework_defaults:
  providers:
    $op1:
      models:
        $op1_target:
          context_window: 100000
    $op2:
      models:
        $op2_target:
          context_window: 100000
    $op3:
      models:
        $op3_target:
          context_window: 100000
  aliases:
    $op1_alias: { provider: $op1, model_id: $op1_target }
    $op2_alias: { provider: $op2, model_id: $op2_target }
    $op3_alias: { provider: $op3, model_id: $op3_target }
  tier_groups:
    mappings:
      $tier:
        $op2: $op2_alias
        $op3: $op3_alias
  agents: {}
operator_config:
  tier_groups:
    mappings:
      $tier:
        $op1: $op1_alias
        $op2: $op2_alias
  skill_models:
    $skill:
      $role: $tier
YAML
    fi
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

# Invariant 7: positive S5 control — when no `skill_models` and no
# legacy `<skill>.models.<role>` are set, but `agents.<skill>.{model,
# default_tier}` IS set, the resolver MUST hit S5 (`stage5_framework_default`)
# and produce the expected provider/model_id.
#
# Cypherpunk HIGH-3: I6 asserts "S5 not in resolution_path" when tier is
# unmapped. Without a positive control, a regression that broke S5
# entirely (always returns None) would still pass I6. I7 is the positive
# counterpart: under the right config, S5 must hit.
#
# Two flavours via `seed mod 2`:
#   F0: agents.<skill>.model directly set → S5 hit via direct model alias
#   F1: agents.<skill>.default_tier set + tier_groups.mappings populated
#       → S5 hit via default_tier cascade
prop_gen_inv7_config() {
    local seed="$1"
    local skill role provider alias_name model_target tier flavour_n flavour
    skill=$(prop_pick "$seed" "inv7.skill" "${_PROP_SKILL_NAMES[@]}") || return 1
    role=$(prop_pick "$seed" "inv7.role" "${_PROP_ROLE_NAMES[@]}") || return 1
    provider=$(prop_pick "$seed" "inv7.provider" "${_PROP_PROVIDERS[@]}") || return 1
    alias_name=$(prop_pick "$seed" "inv7.alias" "${_PROP_ALIAS_NAMES[@]}") || return 1
    model_target=$(prop_pick "$seed" "inv7.target" "${_PROP_MODEL_IDS[@]}")-s5 || return 1
    tier=$(prop_pick "$seed" "inv7.tier" "${_PROP_TIER_NAMES[@]}") || return 1
    flavour_n=$(prop_rand_int "$seed" "inv7.flavour" 2) || return 1

    if [[ "$flavour_n" == "0" ]]; then
        flavour="agents_direct_model"
        cat <<YAML
_property_query:
  invariant: 7
  flavour: "$flavour"
  skill: "$skill"
  role: "$role"
  expected_resolved_provider: "$provider"
  expected_resolved_model_id: "$model_target"
schema_version: 2
framework_defaults:
  providers:
    $provider:
      models:
        $model_target:
          context_window: 100000
  aliases:
    $alias_name: { provider: $provider, model_id: $model_target }
  agents:
    $skill:
      model: $alias_name
operator_config: {}
YAML
    else
        flavour="agents_default_tier"
        cat <<YAML
_property_query:
  invariant: 7
  flavour: "$flavour"
  skill: "$skill"
  role: "$role"
  expected_resolved_provider: "$provider"
  expected_resolved_model_id: "$model_target"
schema_version: 2
framework_defaults:
  providers:
    $provider:
      models:
        $model_target:
          context_window: 100000
  aliases:
    $alias_name: { provider: $provider, model_id: $model_target }
  tier_groups:
    mappings:
      $tier:
        $provider: $alias_name
  agents:
    $skill:
      default_tier: $tier
operator_config: {}
YAML
    fi
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
        7) prop_gen_inv7_config "$seed" ;;
        *) printf '[property-gen] unknown invariant=%q\n' "$invariant" >&2; return 1 ;;
    esac
}
