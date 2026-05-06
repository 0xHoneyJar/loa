#!/usr/bin/env bash
# =============================================================================
# golden_resolution.sh — cycle-099 Sprint 2D bash golden test runner.
#
# Independent bash re-implementation of the FR-3.9 6-stage model resolver, used
# for cross-runtime parity verification. Per SDD §1.5.1 the production bash
# runtime sources `.run/merged-model-aliases.sh` (no resolver logic in
# production); this file is TEST CODE only — it re-implements the 6 stages in
# bash so the cross-runtime-diff CI gate can detect Python-vs-bash divergence.
#
# Reads each .yaml fixture under tests/fixtures/model-resolution/ (sorted by
# filename), runs the 6-stage resolver against `input.{framework_defaults,
# operator_config, runtime_state}` for each (skill, role) tuple declared in
# `expected.resolutions[]`, and emits one canonical JSON line per resolution
# to stdout.
#
# Output schema MUST be byte-identical to tests/python/golden_resolution.py
# (cross-runtime parity per SDD §7.6.2). The cross-runtime-diff CI gate
# byte-compares both runtimes' output; mismatch fails the build.
#
# Usage:
#     tests/bash/golden_resolution.sh > bash-resolution-output.jsonl
#
# Env-var test escapes (each REQUIRES `LOA_GOLDEN_TEST_MODE=1` OR running
# under bats — mirror cycle-099 sprint-1B `LOA_MODEL_RESOLVER_TEST_MODE`):
#     LOA_GOLDEN_PROJECT_ROOT  — override project root
#     LOA_GOLDEN_FIXTURES_DIR  — override fixtures directory
# =============================================================================

set -euo pipefail

# ----- test-mode override gating (parity with Python runner) -----

_golden_test_mode_active() {
    [[ "${LOA_GOLDEN_TEST_MODE:-}" == "1" ]] || [[ -n "${BATS_TEST_DIRNAME:-}" ]]
}

_golden_resolve_path() {
    local env_var="$1" default="$2"
    local val="${!env_var:-}"
    if [[ -n "$val" ]]; then
        if _golden_test_mode_active; then
            echo "[GOLDEN] override active: $env_var=$val" >&2
            printf '%s' "$val"
            return
        else
            echo "[GOLDEN] WARNING: $env_var set but LOA_GOLDEN_TEST_MODE!=1 and not running under bats — IGNORED" >&2
        fi
    fi
    printf '%s' "$default"
}

# ----- path resolution -----

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_DEFAULT_PROJECT_ROOT="$(cd "$_SCRIPT_DIR/../.." && pwd)"
PROJECT_ROOT="$(_golden_resolve_path LOA_GOLDEN_PROJECT_ROOT "$_DEFAULT_PROJECT_ROOT")"
FIXTURES_DIR="$(_golden_resolve_path LOA_GOLDEN_FIXTURES_DIR "$PROJECT_ROOT/tests/fixtures/model-resolution")"

# ----- preflight -----

if [[ ! -d "$FIXTURES_DIR" ]]; then
    echo "golden_resolution.sh: fixtures dir $FIXTURES_DIR not present" >&2
    exit 2
fi
command -v jq >/dev/null 2>&1 || { echo "golden_resolution.sh: jq not found" >&2; exit 2; }
command -v yq >/dev/null 2>&1 || { echo "golden_resolution.sh: yq not found" >&2; exit 2; }

# ----- stage labels (pinned per model-resolver-output.schema.json) -----

readonly _S1_LABEL="stage1_pin_check"
readonly _S2_LABEL="stage2_skill_models"
readonly _S3_LABEL="stage3_tier_groups"
readonly _S4_LABEL="stage4_legacy_shape"
readonly _S5_LABEL="stage5_framework_default"
readonly _S6_LABEL="stage6_prefer_pro_overlay"

# Tier names recognized as tier-tags. Per IMP-007, when a `skill_models.<skill>.<role>`
# value matches one of these AND also exists in `model_aliases_extra`, the tier-tag
# interpretation wins.
readonly _TIER_NAMES_RE='^(max|cheap|mid|tiny)$'

# Field separator for stage helper return values. \x01 (SOH) is unlikely to
# appear in any user-supplied alias name (alias pattern is [a-zA-Z0-9._-]).
readonly _SEP=$'\x01'

# ----- alias normalization helper -----

# `framework_defaults.aliases.<X>` may be either a dict {provider, model_id}
# (cycle-099 fixture corpus shape) OR a string "provider:model_id" (cycle-095
# back-compat shape used in `.claude/defaults/model-config.yaml`). The
# resolver supports both transparently; bash runner mirrors the Python
# `_lookup_alias` / `_normalize_alias_entry` helpers from
# `.claude/scripts/lib/model-resolver.py`.
#
# Emits a JSON object {provider, model_id} on stdout, or "null" if the
# alias is absent or malformed.
#
# Args: $1 = input_json, $2 = alias_name
_lookup_alias() {
    local input="$1" alias="$2"
    echo "$input" | jq -c --arg a "$alias" '
        (.framework_defaults.aliases // {})[$a] as $entry
        | if $entry == null then null
          elif ($entry | type) == "string"
          then
            ($entry | capture("^(?<provider>[^:]+):(?<model_id>.+)$") // null)
          elif ($entry | type) == "object"
          then
            (if (($entry.provider // "") | type == "string" and . != "")
                and (($entry.model_id // "") | type == "string" and . != "")
              then {provider: $entry.provider, model_id: $entry.model_id}
              else null
              end)
          else null
          end
    '
}

# ----- canonical JSON helpers -----

# Build a stage-entry JSON object.
#   $1 stage int, $2 outcome str, $3 label str, $4 details JSON ({} or null)
_make_stage_entry() {
    local stage="$1" outcome="$2" label="$3" details="${4:-null}"
    if [[ "$details" == "null" ]] || [[ "$details" == "{}" ]]; then
        jq -c -n --argjson stage "$stage" --arg outcome "$outcome" --arg label "$label" \
            '{stage:$stage,outcome:$outcome,label:$label}'
    else
        jq -c -n --argjson stage "$stage" --arg outcome "$outcome" --arg label "$label" --argjson details "$details" \
            '{stage:$stage,outcome:$outcome,label:$label,details:$details}'
    fi
}

# Emit a success result line (canonical JSON; sorted keys; literal UTF-8).
_emit_success() {
    local fixture="$1" skill="$2" role="$3" provider="$4" model_id="$5" path_json="$6"
    jq -S -c -n \
        --arg fixture "$fixture" --arg skill "$skill" --arg role "$role" \
        --arg provider "$provider" --arg model_id "$model_id" \
        --argjson path "$path_json" \
        '{fixture:$fixture, skill:$skill, role:$role,
          resolved_provider:$provider, resolved_model_id:$model_id,
          resolution_path:$path}'
}

_emit_error() {
    local fixture="$1" skill="$2" role="$3" code="$4" stage_failed="$5" detail="$6"
    if [[ -n "$skill" ]]; then
        jq -S -c -n \
            --arg fixture "$fixture" --arg skill "$skill" --arg role "$role" \
            --arg code "$code" --argjson stage_failed "$stage_failed" --arg detail "$detail" \
            '{fixture:$fixture, skill:$skill, role:$role,
              error:{code:$code, stage_failed:$stage_failed, detail:$detail}}'
    else
        # Fixture-level error (no skill/role context — e.g., YAML parse failure)
        jq -S -c -n \
            --arg fixture "$fixture" \
            --arg code "$code" --argjson stage_failed "$stage_failed" --arg detail "$detail" \
            '{fixture:$fixture,
              error:{code:$code, stage_failed:$stage_failed, detail:$detail}}'
    fi
}

# ----- pre-resolution validation (stage 0 — IMP-004) -----

# Args: $1 = input_json
# Stdout: error JSON object on violation; empty on pass
_pre_validate() {
    local input="$1"
    # Same id in extra AND override
    local collision
    collision=$(echo "$input" | jq -r '
        ((.operator_config.model_aliases_extra // {}) | keys) as $extra
        | ((.operator_config.model_aliases_override // {}) | keys) as $override
        | ($extra | map(select(. as $e | $override | index($e)))) | sort | first // empty
    ')
    if [[ -n "$collision" ]]; then
        jq -c -n --arg id "$collision" \
            '{code:"[MODEL-EXTRA-OVERRIDE-CONFLICT]", stage_failed:0, detail:"id `\($id)` appears in BOTH model_aliases_extra and model_aliases_override; mutually exclusive at entry level (IMP-004)"}'
        return
    fi
    # Override targets unknown framework id
    local unknown
    unknown=$(echo "$input" | jq -r '
        [.framework_defaults.providers // {} | to_entries[] | (.value.models // {}) | keys[]] as $known
        | ((.operator_config.model_aliases_override // {}) | keys)
        | map(select(. as $k | ($known | index($k)) | not))
        | sort | first // empty
    ')
    if [[ -n "$unknown" ]]; then
        jq -c -n --arg id "$unknown" \
            '{code:"[OVERRIDE-UNKNOWN-MODEL]", stage_failed:0, detail:"model_aliases_override targets `\($id)` which is not a framework-default ID"}'
        return
    fi
}

# ----- stage 1: explicit pin -----

# Args: $1 = skill_models_value
# Stdout (3-field): "<provider>${SEP}<model_id>${SEP}<stage_entry>" on hit; empty on miss
_stage1_explicit_pin() {
    local val="$1"
    [[ -z "$val" ]] && return
    [[ "$val" != *":"* ]] && return
    local provider="${val%%:*}"
    local model_id="${val#*:}"
    [[ -z "$provider" ]] && return
    [[ -z "$model_id" ]] && return
    local details
    details=$(jq -c -n --arg pin "$val" '{pin:$pin}')
    local entry
    entry=$(_make_stage_entry 1 hit "$_S1_LABEL" "$details")
    printf '%s%s%s%s%s' "$provider" "$_SEP" "$model_id" "$_SEP" "$entry"
}

# ----- stage 2: tag in skill_models — direct alias or tier cascade -----

# Args: $1 = skill_models_value, $2 = input_json
# Stdout:
#   "DIRECT${SEP}<provider>${SEP}<model_id>${SEP}<stage_entry>" — direct alias hit
#   "CASCADE${SEP}<tier>${SEP}<stage_entry>" — cascade to S3
#   empty — no S2 hit (S1 already handled, or value empty)
_stage2_skill_models() {
    local val="$1" input="$2"
    [[ -z "$val" ]] && return
    [[ "$val" == *":"* ]] && return  # explicit pin handled by S1

    local stage_entry details
    details=$(jq -c -n --arg alias "$val" '{alias:$alias}')
    stage_entry=$(_make_stage_entry 2 hit "$_S2_LABEL" "$details")

    # Determine if val is a tier-tag
    local is_tier=0
    if [[ "$val" =~ $_TIER_NAMES_RE ]]; then
        is_tier=1
    fi
    if [[ $is_tier -eq 0 ]]; then
        local tier_present
        tier_present=$(echo "$input" | jq -r --arg t "$val" '
            (((.operator_config.tier_groups // {}).mappings // {}) | has($t))
            or (((.framework_defaults.tier_groups // {}).mappings // {}) | has($t))
        ')
        if [[ "$tier_present" == "true" ]]; then
            is_tier=1
        fi
    fi

    if [[ $is_tier -eq 1 ]]; then
        printf 'CASCADE%s%s%s%s' "$_SEP" "$val" "$_SEP" "$stage_entry"
        return
    fi

    # Direct alias check — framework_aliases first (supports both string and
    # dict shape via _lookup_alias), then operator_config.model_aliases_extra
    # (always dict shape per Sprint 2A schema).
    local alias_entry
    alias_entry=$(_lookup_alias "$input" "$val")
    if [[ "$alias_entry" == "null" ]]; then
        # Fallback to model_aliases_extra (Sprint 2A schema mandates dict shape)
        alias_entry=$(echo "$input" | jq -c --arg a "$val" '
            (.operator_config.model_aliases_extra // {})[$a] as $e
            | if $e == null then null
              elif ($e | type) == "object"
                   and (($e.provider // "") | type == "string" and . != "")
                   and (($e.model_id // "") | type == "string" and . != "")
              then {provider: $e.provider, model_id: $e.model_id}
              else null
              end
        ')
    fi
    if [[ "$alias_entry" != "null" ]]; then
        local provider model_id
        provider=$(echo "$alias_entry" | jq -r '.provider')
        model_id=$(echo "$alias_entry" | jq -r '.model_id')
        printf 'DIRECT%s%s%s%s%s%s' "$_SEP" "$provider" "$_SEP" "$model_id" "$_SEP" "$stage_entry"
        return
    fi

    # Unknown — cascade (S3 will likely emit [TIER-NO-MAPPING])
    printf 'CASCADE%s%s%s%s' "$_SEP" "$val" "$_SEP" "$stage_entry"
}

# ----- stage 3: tier_groups.mappings lookup -----

# Args: $1 = tier, $2 = input_json
# Stdout:
#   "OK${SEP}<provider>${SEP}<model_id>${SEP}<stage_entry>"  — resolution succeeded
#   "ERR${SEP}<error_json>"  — TIER-NO-MAPPING
_stage3_tier_groups() {
    local tier="$1" input="$2"
    local mapping
    mapping=$(echo "$input" | jq -c --arg t "$tier" '
        ((.operator_config.tier_groups // {}).mappings // {})[$t]
        // ((.framework_defaults.tier_groups // {}).mappings // {})[$t]
        // null
    ')
    if [[ "$mapping" == "null" ]]; then
        local err
        err=$(jq -c -n --arg t "$tier" \
            '{code:"[TIER-NO-MAPPING]", stage_failed:3, detail:"tier `\($t)` has no mapping for any provider; configure tier_groups.mappings or use explicit alias"}')
        printf 'ERR%s%s' "$_SEP" "$err"
        return
    fi
    local provider
    provider=$(echo "$mapping" | jq -r 'keys | sort | .[0] // ""')
    if [[ -z "$provider" ]] || [[ "$provider" == "null" ]]; then
        local err
        err=$(jq -c -n --arg t "$tier" \
            '{code:"[TIER-NO-MAPPING]", stage_failed:3, detail:"tier `\($t)` has no mapping for any provider; configure tier_groups.mappings or use explicit alias"}')
        printf 'ERR%s%s' "$_SEP" "$err"
        return
    fi
    local alias
    alias=$(echo "$mapping" | jq -r --arg p "$provider" '.[$p] // ""')
    if [[ -z "$alias" ]] || [[ "$alias" == "null" ]]; then
        local err
        err=$(jq -c -n --arg t "$tier" --arg p "$provider" \
            '{code:"[TIER-NO-MAPPING]", stage_failed:3, detail:"tier `\($t)` mapped but provider `\($p)` has no alias"}')
        printf 'ERR%s%s' "$_SEP" "$err"
        return
    fi
    local alias_entry
    alias_entry=$(_lookup_alias "$input" "$alias")
    if [[ "$alias_entry" == "null" ]]; then
        local err
        err=$(jq -c -n --arg t "$tier" --arg a "$alias" --arg p "$provider" \
            '{code:"[TIER-NO-MAPPING]", stage_failed:3, detail:"tier `\($t)` mapped to alias `\($a)` for provider `\($p)` but alias not found in framework_defaults.aliases"}')
        printf 'ERR%s%s' "$_SEP" "$err"
        return
    fi
    local resolved_provider resolved_model_id
    resolved_provider=$(echo "$alias_entry" | jq -r '.provider')
    resolved_model_id=$(echo "$alias_entry" | jq -r '.model_id')

    # IMP-007: tier-tag name (input value) collides with model_aliases_extra entry
    local collides
    collides=$(echo "$input" | jq -r --arg t "$tier" '(.operator_config.model_aliases_extra // {}) | has($t)')
    local details
    if [[ "$collides" == "true" ]]; then
        details=$(jq -c -n --arg a "$alias" '{resolved_alias:$a, alias_collides_with_tier:true}')
    else
        details=$(jq -c -n --arg a "$alias" '{resolved_alias:$a}')
    fi
    local entry
    entry=$(_make_stage_entry 3 hit "$_S3_LABEL" "$details")
    printf 'OK%s%s%s%s%s%s' "$_SEP" "$resolved_provider" "$_SEP" "$resolved_model_id" "$_SEP" "$entry"
}

# ----- stage 4: legacy shape -----

# Args: $1 = skill, $2 = role, $3 = input_json
# Stdout: "OK${SEP}<provider>${SEP}<model_id>${SEP}<stage_entry>${SEP}<legacy_alias>" on hit; empty on miss
_stage4_legacy_shape() {
    local skill="$1" role="$2" input="$3"
    local alias
    alias=$(echo "$input" | jq -r --arg s "$skill" --arg r "$role" '
        (.operator_config[$s] // {}) | (.models // {})[$r] // ""
    ')
    [[ -z "$alias" ]] && return
    [[ "$alias" == "null" ]] && return
    local alias_entry
    alias_entry=$(_lookup_alias "$input" "$alias")
    if [[ "$alias_entry" == "null" ]]; then
        return  # Fall through to S5 per FR-3.7
    fi
    local provider model_id
    provider=$(echo "$alias_entry" | jq -r '.provider')
    model_id=$(echo "$alias_entry" | jq -r '.model_id')
    local details
    details=$(jq -c -n '{warning:"[LEGACY-SHAPE-DEPRECATED]"}')
    local entry
    entry=$(_make_stage_entry 4 hit "$_S4_LABEL" "$details")
    printf 'OK%s%s%s%s%s%s%s%s' "$_SEP" "$provider" "$_SEP" "$model_id" "$_SEP" "$entry" "$_SEP" "$alias"
}

# ----- stage 5: framework default -----

# Args: $1 = skill, $2 = input_json
# Stdout: "OK${SEP}<provider>${SEP}<model_id>${SEP}<stage_entry>${SEP}<resolved_alias>" on hit; empty on miss
_stage5_framework_default() {
    local skill="$1" input="$2"
    local agent
    agent=$(echo "$input" | jq -c --arg s "$skill" '.framework_defaults.agents[$s] // null')
    [[ "$agent" == "null" ]] && return

    local is_degraded
    is_degraded=$(echo "$input" | jq -r '(.runtime_state.overlay_state // "") == "degraded"')

    # Try direct .model
    local model_alias
    model_alias=$(echo "$agent" | jq -r '.model // ""')
    if [[ -n "$model_alias" ]] && [[ "$model_alias" != "null" ]]; then
        local alias_entry
        alias_entry=$(_lookup_alias "$input" "$model_alias")
        if [[ "$alias_entry" != "null" ]]; then
            local provider model_id
            provider=$(echo "$alias_entry" | jq -r '.provider')
            model_id=$(echo "$alias_entry" | jq -r '.model_id')
            local details
            if [[ "$is_degraded" == "true" ]]; then
                details=$(jq -c -n --arg a "$model_alias" '{alias:$a, source:"degraded_cache"}')
            else
                details=$(jq -c -n --arg a "$model_alias" '{alias:$a}')
            fi
            local entry
            entry=$(_make_stage_entry 5 hit "$_S5_LABEL" "$details")
            printf 'OK%s%s%s%s%s%s%s%s' "$_SEP" "$provider" "$_SEP" "$model_id" "$_SEP" "$entry" "$_SEP" "$model_alias"
            return
        fi
    fi

    # Fall back to default_tier
    local default_tier
    default_tier=$(echo "$agent" | jq -r '.default_tier // ""')
    [[ -z "$default_tier" ]] && return
    [[ "$default_tier" == "null" ]] && return

    # Try tier_groups.mappings.<tier> first
    local mapping
    mapping=$(echo "$input" | jq -c --arg t "$default_tier" '(.framework_defaults.tier_groups // {}).mappings[$t] // null')
    if [[ "$mapping" != "null" ]]; then
        local provider
        provider=$(echo "$mapping" | jq -r 'keys | sort | .[0] // ""')
        local alias
        alias=$(echo "$mapping" | jq -r --arg p "$provider" '.[$p] // ""')
        if [[ -n "$alias" ]] && [[ "$alias" != "null" ]]; then
            local alias_entry
            alias_entry=$(_lookup_alias "$input" "$alias")
            if [[ "$alias_entry" != "null" ]]; then
                local resolved_provider resolved_model_id
                resolved_provider=$(echo "$alias_entry" | jq -r '.provider')
                resolved_model_id=$(echo "$alias_entry" | jq -r '.model_id')
                local details
                if [[ "$is_degraded" == "true" ]]; then
                    details=$(jq -c -n --arg a "$alias" '{alias:$a, source:"degraded_cache"}')
                else
                    details=$(jq -c -n --arg a "$alias" '{alias:$a}')
                fi
                local entry
                entry=$(_make_stage_entry 5 hit "$_S5_LABEL" "$details")
                printf 'OK%s%s%s%s%s%s%s%s' "$_SEP" "$resolved_provider" "$_SEP" "$resolved_model_id" "$_SEP" "$entry" "$_SEP" "$alias"
                return
            fi
        fi
    fi

    # Permissive fallback: direct alias by tier name
    local alias_entry
    alias_entry=$(_lookup_alias "$input" "$default_tier")
    if [[ "$alias_entry" != "null" ]]; then
        local provider model_id
        provider=$(echo "$alias_entry" | jq -r '.provider')
        model_id=$(echo "$alias_entry" | jq -r '.model_id')
        local details
        if [[ "$is_degraded" == "true" ]]; then
            details=$(jq -c -n --arg a "$default_tier" '{alias:$a, source:"degraded_cache"}')
        else
            details=$(jq -c -n --arg a "$default_tier" '{alias:$a}')
        fi
        local entry
        entry=$(_make_stage_entry 5 hit "$_S5_LABEL" "$details")
        printf 'OK%s%s%s%s%s%s%s%s' "$_SEP" "$provider" "$_SEP" "$model_id" "$_SEP" "$entry" "$_SEP" "$default_tier"
    fi
}

# ----- stage 6: prefer_pro overlay -----

# Args: $1 = resolved_alias (may be empty), $2 = input_json, $3 = is_legacy_path (0/1)
# Stdout:
#   "RETARGET${SEP}<provider>${SEP}<model_id>${SEP}<stage_entry>" — retargeted to *-pro
#   "ENTRY${SEP}<stage_entry>" — entry emitted but not retargeted (skipped)
#   empty — prefer_pro disabled, no entry emitted
_stage6_prefer_pro() {
    local resolved_alias="$1" input="$2" is_legacy_path="$3"
    local prefer_pro
    prefer_pro=$(echo "$input" | jq -r '.operator_config.prefer_pro_models == true')
    [[ "$prefer_pro" != "true" ]] && return

    if [[ "$is_legacy_path" == "1" ]]; then
        local respect
        respect=$(echo "$input" | jq -r '.operator_config.respect_prefer_pro == true')
        if [[ "$respect" != "true" ]]; then
            local details
            details=$(jq -c -n '{reason:"legacy_shape_without_respect_prefer_pro"}')
            local entry
            entry=$(_make_stage_entry 6 skipped "$_S6_LABEL" "$details")
            printf 'ENTRY%s%s' "$_SEP" "$entry"
            return
        fi
    fi

    if [[ -z "$resolved_alias" ]]; then
        local details
        details=$(jq -c -n '{reason:"no_alias_to_overlay"}')
        local entry
        entry=$(_make_stage_entry 6 skipped "$_S6_LABEL" "$details")
        printf 'ENTRY%s%s' "$_SEP" "$entry"
        return
    fi

    local pro_alias="${resolved_alias}-pro"
    local pro_entry
    pro_entry=$(_lookup_alias "$input" "$pro_alias")
    if [[ "$pro_entry" == "null" ]]; then
        local details
        details=$(jq -c -n --arg a "$resolved_alias" '{reason:"no_pro_variant_for_alias", alias:$a}')
        local entry
        entry=$(_make_stage_entry 6 skipped "$_S6_LABEL" "$details")
        printf 'ENTRY%s%s' "$_SEP" "$entry"
        return
    fi

    local provider model_id
    provider=$(echo "$pro_entry" | jq -r '.provider')
    model_id=$(echo "$pro_entry" | jq -r '.model_id')
    local details
    details=$(jq -c -n --arg from "$resolved_alias" --arg to "$pro_alias" '{from:$from, to:$to}')
    local entry
    entry=$(_make_stage_entry 6 applied "$_S6_LABEL" "$details")
    printf 'RETARGET%s%s%s%s%s%s' "$_SEP" "$provider" "$_SEP" "$model_id" "$_SEP" "$entry"
}

# ----- helper: append S6 result to resolution_path; return final provider/model_id -----

# Args: $1 = current resolution_path JSON, $2 = current provider, $3 = current model_id,
#       $4 = s6_result string
# Side effect: prints 3 lines: new_path / new_provider / new_model_id
_apply_s6() {
    local path="$1" provider="$2" model_id="$3" s6_result="$4"
    if [[ -z "$s6_result" ]]; then
        printf '%s\n%s\n%s\n' "$path" "$provider" "$model_id"
        return
    fi
    local kind="${s6_result%%${_SEP}*}"
    if [[ "$kind" == "RETARGET" ]]; then
        local _ new_provider new_model_id s6_entry
        IFS="$_SEP" read -r _ new_provider new_model_id s6_entry <<< "$s6_result"
        path=$(echo "$path" | jq -c --argjson e "$s6_entry" '. + [$e]')
        printf '%s\n%s\n%s\n' "$path" "$new_provider" "$new_model_id"
    else  # ENTRY
        local s6_entry="${s6_result#ENTRY${_SEP}}"
        path=$(echo "$path" | jq -c --argjson e "$s6_entry" '. + [$e]')
        printf '%s\n%s\n%s\n' "$path" "$provider" "$model_id"
    fi
}

# ----- main resolver -----

# Args: $1 = fixture, $2 = skill, $3 = role, $4 = input_json
_resolve() {
    local fixture="$1" skill="$2" role="$3" input="$4"

    # Stage 0
    local pre_err
    pre_err=$(_pre_validate "$input")
    if [[ -n "$pre_err" ]]; then
        local code stage_failed detail
        code=$(echo "$pre_err" | jq -r '.code')
        stage_failed=$(echo "$pre_err" | jq -r '.stage_failed')
        detail=$(echo "$pre_err" | jq -r '.detail')
        _emit_error "$fixture" "$skill" "$role" "$code" "$stage_failed" "$detail"
        return
    fi

    local skill_value
    skill_value=$(echo "$input" | jq -r --arg s "$skill" --arg r "$role" '
        ((.operator_config.skill_models // {})[$s] // {})[$r] // ""
    ')

    local resolution_path='[]'
    local final_provider="" final_model_id=""

    # Stage 1
    local s1_result
    s1_result=$(_stage1_explicit_pin "$skill_value")
    if [[ -n "$s1_result" ]]; then
        local s1_entry
        IFS="$_SEP" read -r final_provider final_model_id s1_entry <<< "$s1_result"
        resolution_path=$(echo "$resolution_path" | jq -c --argjson e "$s1_entry" '. + [$e]')
        local s6_result
        s6_result=$(_stage6_prefer_pro "" "$input" 0)
        local applied
        applied=$(_apply_s6 "$resolution_path" "$final_provider" "$final_model_id" "$s6_result")
        { read -r resolution_path; read -r final_provider; read -r final_model_id; } <<< "$applied"
        _emit_success "$fixture" "$skill" "$role" "$final_provider" "$final_model_id" "$resolution_path"
        return
    fi

    # Stage 2
    local s2_result
    s2_result=$(_stage2_skill_models "$skill_value" "$input")
    if [[ -n "$s2_result" ]]; then
        local s2_kind="${s2_result%%${_SEP}*}"
        if [[ "$s2_kind" == "DIRECT" ]]; then
            local _ s2_entry
            IFS="$_SEP" read -r _ final_provider final_model_id s2_entry <<< "$s2_result"
            resolution_path=$(echo "$resolution_path" | jq -c --argjson e "$s2_entry" '. + [$e]')
            local s6_result
            s6_result=$(_stage6_prefer_pro "$skill_value" "$input" 0)
            local applied
            applied=$(_apply_s6 "$resolution_path" "$final_provider" "$final_model_id" "$s6_result")
            { read -r resolution_path; read -r final_provider; read -r final_model_id; } <<< "$applied"
            _emit_success "$fixture" "$skill" "$role" "$final_provider" "$final_model_id" "$resolution_path"
            return
        fi
        # CASCADE
        local _ tier s2_entry
        IFS="$_SEP" read -r _ tier s2_entry <<< "$s2_result"
        resolution_path=$(echo "$resolution_path" | jq -c --argjson e "$s2_entry" '. + [$e]')
        local s3_result
        s3_result=$(_stage3_tier_groups "$tier" "$input")
        local s3_kind="${s3_result%%${_SEP}*}"
        if [[ "$s3_kind" == "ERR" ]]; then
            local _ err_json
            IFS="$_SEP" read -r _ err_json <<< "$s3_result"
            local code stage_failed detail
            code=$(echo "$err_json" | jq -r '.code')
            stage_failed=$(echo "$err_json" | jq -r '.stage_failed')
            detail=$(echo "$err_json" | jq -r '.detail')
            _emit_error "$fixture" "$skill" "$role" "$code" "$stage_failed" "$detail"
            return
        fi
        local _ s3_entry
        IFS="$_SEP" read -r _ final_provider final_model_id s3_entry <<< "$s3_result"
        resolution_path=$(echo "$resolution_path" | jq -c --argjson e "$s3_entry" '. + [$e]')
        local resolved_alias_for_overlay
        resolved_alias_for_overlay=$(echo "$s3_entry" | jq -r '.details.resolved_alias // ""')
        local s6_result
        s6_result=$(_stage6_prefer_pro "$resolved_alias_for_overlay" "$input" 0)
        local applied
        applied=$(_apply_s6 "$resolution_path" "$final_provider" "$final_model_id" "$s6_result")
        { read -r resolution_path; read -r final_provider; read -r final_model_id; } <<< "$applied"
        _emit_success "$fixture" "$skill" "$role" "$final_provider" "$final_model_id" "$resolution_path"
        return
    fi

    # Stage 4
    local s4_result
    s4_result=$(_stage4_legacy_shape "$skill" "$role" "$input")
    if [[ -n "$s4_result" ]]; then
        local _ s4_entry legacy_alias
        IFS="$_SEP" read -r _ final_provider final_model_id s4_entry legacy_alias <<< "$s4_result"
        resolution_path=$(echo "$resolution_path" | jq -c --argjson e "$s4_entry" '. + [$e]')
        local s6_result
        s6_result=$(_stage6_prefer_pro "$legacy_alias" "$input" 1)
        local applied
        applied=$(_apply_s6 "$resolution_path" "$final_provider" "$final_model_id" "$s6_result")
        { read -r resolution_path; read -r final_provider; read -r final_model_id; } <<< "$applied"
        _emit_success "$fixture" "$skill" "$role" "$final_provider" "$final_model_id" "$resolution_path"
        return
    fi

    # Stage 5
    local s5_result
    s5_result=$(_stage5_framework_default "$skill" "$input")
    if [[ -n "$s5_result" ]]; then
        local _ s5_entry s5_alias
        IFS="$_SEP" read -r _ final_provider final_model_id s5_entry s5_alias <<< "$s5_result"
        resolution_path=$(echo "$resolution_path" | jq -c --argjson e "$s5_entry" '. + [$e]')
        local s6_result
        s6_result=$(_stage6_prefer_pro "$s5_alias" "$input" 0)
        local applied
        applied=$(_apply_s6 "$resolution_path" "$final_provider" "$final_model_id" "$s6_result")
        { read -r resolution_path; read -r final_provider; read -r final_model_id; } <<< "$applied"
        _emit_success "$fixture" "$skill" "$role" "$final_provider" "$final_model_id" "$resolution_path"
        return
    fi

    # All stages exhausted
    _emit_error "$fixture" "$skill" "$role" "[NO-RESOLUTION]" 5 \
        "no resolution for skill \`$skill\` role \`$role\`; check skill_models, legacy shape, and agents.$skill default"
}

# ----- main loop -----

# Iterate fixtures sorted by filename.
mapfile -t _FIXTURES < <(find "$FIXTURES_DIR" -maxdepth 1 -name '*.yaml' -type f | LC_ALL=C sort)

for fixture_path in "${_FIXTURES[@]}"; do
    fixture_name="$(basename "$fixture_path" .yaml)"

    if ! fixture_json=$(yq -o json '.' "$fixture_path" 2>/dev/null); then
        _emit_error "$fixture_name" "" "" "[YAML-PARSE-FAILED]" 0 "fixture YAML failed to parse"
        continue
    fi

    input_json=$(echo "$fixture_json" | jq -c '.input // {}')
    # Sort declared resolutions by (skill, role) for deterministic ordering
    resolutions=$(echo "$fixture_json" | jq -c '
        (.expected.resolutions // [])
        | map(select((.skill | type) == "string" and (.role | type) == "string"))
        | sort_by(.skill, .role)
        | .[]
    ')

    if [[ -z "$resolutions" ]]; then
        _emit_error "$fixture_name" "" "" "[NO-EXPECTED-RESOLUTIONS]" 0 "fixture lacks expected.resolutions[] block"
        continue
    fi

    while IFS= read -r entry; do
        [[ -z "$entry" ]] && continue
        skill=$(echo "$entry" | jq -r '.skill')
        role=$(echo "$entry" | jq -r '.role')
        _resolve "$fixture_name" "$skill" "$role" "$input_json"
    done <<< "$resolutions"
done
