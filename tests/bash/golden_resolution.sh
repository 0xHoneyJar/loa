#!/usr/bin/env bash
# =============================================================================
# tests/bash/golden_resolution.sh
#
# cycle-099 Sprint 1D — Bash runner for the model-resolution golden corpus.
#
# Reads each .yaml fixture under tests/fixtures/model-resolution/ (sorted by
# filename), extracts `sprint_1d_query.alias`, performs alias resolution via
# `.claude/scripts/lib/model-resolver.sh`, and emits one canonical JSON line
# per fixture to stdout.
#
# Output schema (JSON Lines):
#   Supported (alias is in MODEL_IDS):
#     {"fixture":"<name>","input_alias":"<a>","resolved_model_id":"<m>","resolved_provider":"<p>","subset_supported":true}
#   Deferred (alias not in MODEL_IDS — Sprint 2 will assert resolver semantics):
#     {"fixture":"<name>","input_alias":"<a>","deferred_to":"sprint-2-T2.6","subset_supported":false}
#
# Keys are alphabetically sorted (jq -S) so byte-equality across runtimes is
# the cross-runtime-diff CI gate per SDD §7.6.2.
#
# Tested by tests/bash/golden_resolution.bats.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT_DEFAULT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# cypherpunk CRIT-3 (PR #735 review): env-override gate parity. Mirror the
# `model-resolver.sh::LOA_MODEL_RESOLVER_TEST_MODE` pattern. Each LOA_GOLDEN_*
# override REQUIRES `LOA_GOLDEN_TEST_MODE=1` OR `BATS_TEST_DIRNAME` (set by
# bats), else the override is IGNORED with a stderr warning. This prevents
# an attacker who controls the ambient environment from redirecting model
# lookups (especially the bash `source` of $RESOLVER) to attacker-controlled
# code.
_golden_test_mode_active() {
    [[ "${LOA_GOLDEN_TEST_MODE:-}" == "1" ]] || [[ -n "${BATS_TEST_DIRNAME:-}" ]]
}
_golden_apply_override() {
    # Args: var-name, env-name. If env-name is set + test mode active → use it.
    # Else if env-name is set without test mode → warn + ignore.
    local target_var="$1" env_var="$2" env_val
    env_val="${!env_var:-}"
    if [[ -n "$env_val" ]]; then
        if _golden_test_mode_active; then
            printf '[GOLDEN] override active: %s=%s\n' "$env_var" "$env_val" >&2
            printf -v "$target_var" '%s' "$env_val"
        else
            printf '[GOLDEN] WARNING: %s set but LOA_GOLDEN_TEST_MODE!=1 and not running under bats — IGNORED\n' "$env_var" >&2
        fi
    fi
}

PROJECT_ROOT="$PROJECT_ROOT_DEFAULT"
_golden_apply_override PROJECT_ROOT LOA_GOLDEN_PROJECT_ROOT

FIXTURES_DIR="$PROJECT_ROOT/tests/fixtures/model-resolution"
_golden_apply_override FIXTURES_DIR LOA_GOLDEN_FIXTURES_DIR

RESOLVER="$PROJECT_ROOT/.claude/scripts/lib/model-resolver.sh"
_golden_apply_override RESOLVER LOA_GOLDEN_RESOLVER

GENERATED_MAPS="$PROJECT_ROOT/.claude/scripts/generated-model-maps.sh"
_golden_apply_override GENERATED_MAPS LOA_GOLDEN_GENERATED_MAPS

if [[ ! -d "$FIXTURES_DIR" ]]; then
    printf 'golden_resolution.sh: fixtures dir %q not present\n' "$FIXTURES_DIR" >&2
    exit 2
fi
if [[ ! -f "$RESOLVER" ]]; then
    printf 'golden_resolution.sh: resolver %q not present\n' "$RESOLVER" >&2
    exit 2
fi

# cypherpunk HIGH-3 (PR #735 review): pre-source syntactic sanitizer for
# generated-model-maps.sh. Bash `source`s the file which would EXECUTE any
# embedded `$(...)` / backticks / `;` chains at sourcing time. The codegen
# never emits these characters; reject pre-source if they appear. Same
# defense-in-depth principle as the curl wrapper's allowlist tree-restriction.
#
# Allow only entries of shape `["KEY"]="VALUE"` where KEY and VALUE contain
# none of: `$`, backtick, `;`, `(`, `)`, `\`, `"` (double-quote inside the
# value would break the format anyway).
_sanitize_generated_maps() {
    local path="$1"
    # cycle-099 sprint-1D HIGH-3 sanitizer.
    #
    # The codegen at .claude/scripts/gen-adapter-maps.sh emits ONE strict shape:
    #   declare -A NAME=(            (opener — name + `=(` end-of-line)
    #       ["KEY"]="VALUE"          (one entry per line — quoted key + value)
    #       ...
    #   )                            (closer — `)` alone on its line)
    #
    # Bash sources this and would EXECUTE any embedded $(...) / backticks
    # / shell metacharacters at sourcing time. The sanitizer enforces the
    # production shape strictly:
    #
    #   1. Each `declare -A` opener line MUST end with `=(` (no body inline)
    #   2. Body lines MUST match the entry regex with no forbidden chars
    #   3. Closer MUST be `)` alone (with optional whitespace)
    #
    # Lines outside arrays (shebang, comments, blank lines) are ignored.
    local in_array=0 line line_num=0
    local entry_re='^[[:space:]]*\["[A-Za-z0-9._:/+-]+"\]="[A-Za-z0-9._:/+-]*"[[:space:]]*$'
    while IFS= read -r line; do
        line_num=$((line_num + 1))
        if [[ "$line" =~ ^declare[[:space:]]+-A ]]; then
            # Strict: opener line MUST end with `=(` (no inline body).
            # Reject `declare -A NAME=( ... )` single-line form (which is
            # how a hostile file would smuggle command-substitution past
            # the body-line check).
            if [[ ! "$line" =~ =\([[:space:]]*$ ]]; then
                printf '[GOLDEN] REJECT line %d: declare -A must use multi-line form (opener ends with `=(`)\n' "$line_num" >&2
                printf '[GOLDEN] saw: %q\n' "$line" >&2
                return 1
            fi
            in_array=1
            continue
        fi
        if [[ $in_array -eq 1 ]]; then
            if [[ "$line" =~ ^\)[[:space:]]*$ ]]; then
                in_array=0
                continue
            fi
            # Permit blank lines / comment lines inside array body.
            if [[ -z "${line//[[:space:]]/}" ]] || [[ "${line#"${line%%[![:space:]]*}"}" == \#* ]]; then
                continue
            fi
            # Strict-shape check: ["KEY"]="VALUE" only, with safe charset.
            if ! [[ "$line" =~ $entry_re ]]; then
                printf '[GOLDEN] REJECT line %d: array entry does not match safe ["KEY"]="VALUE" shape\n' "$line_num" >&2
                printf '[GOLDEN] saw: %q\n' "$line" >&2
                printf '[GOLDEN] expected charset: [A-Za-z0-9._:/+-] (no shell metas)\n' >&2
                return 1
            fi
        fi
    done < "$path"
    if [[ $in_array -eq 1 ]]; then
        printf '[GOLDEN] REJECT: unterminated `declare -A` block (no closing `)`)\n' >&2
        return 1
    fi
    return 0
}

if ! _sanitize_generated_maps "$GENERATED_MAPS"; then
    printf 'golden_resolution.sh: generated-model-maps.sh failed pre-source sanitizer (HIGH-3)\n' >&2
    exit 78
fi

# Sourcing populates MODEL_PROVIDERS + MODEL_IDS associative arrays AND
# defines `resolve_alias` / `resolve_provider_id` functions. The resolver
# script's strict-mode-respect means we don't need to set anything special.
# Sanitizer above guarantees no command substitution at source time.
#
# When LOA_GOLDEN_GENERATED_MAPS is honored under TEST_MODE, source the
# override directly (bypasses the resolver wrapper which would source the
# original maps anyway). For production paths, source the resolver which
# transitively sources the maps.
if [[ "$GENERATED_MAPS" != "$PROJECT_ROOT/.claude/scripts/generated-model-maps.sh" ]]; then
    # shellcheck source=/dev/null
    source "$GENERATED_MAPS"
else
    # shellcheck source=/dev/null
    source "$RESOLVER"
fi

# For each fixture, extract sprint_1d_query.alias, run resolution, emit JSON.
# Sort by filename so output ordering is deterministic across runtimes.
while IFS= read -r -d '' fixture_path; do
    fixture_name=$(basename "$fixture_path" .yaml)

    # cypherpunk CRIT-2 + gp HIGH-2 (PR #735 review): type-check the YAML
    # value of `sprint_1d_query.alias`. Only `!!str` is acceptable.
    # Booleans (`!!bool` — `false`/`true`) and numbers (`!!int`/`!!float`)
    # would yq-stringify to "false"/"42" and bash would proceed as if they
    # were valid aliases — diverging from python+TS which type-check.
    #
    # `yq eval '... | tag'` returns the YAML node tag (e.g., `!!str`,
    # `!!bool`, `!!null`). Use `|| true` to tolerate missing field.
    local_tag=$(yq eval '.sprint_1d_query.alias | tag' "$fixture_path" 2>/dev/null || true)
    if [[ -z "$local_tag" || "$local_tag" == "!!null" ]]; then
        # Field missing OR explicit null — uniform error marker.
        jq -n --arg fix "$fixture_name" \
            '{error: "missing-sprint_1d_query-alias", fixture: $fix, subset_supported: false}' \
            | jq -S -c .
        continue
    fi
    if [[ "$local_tag" != "!!str" ]]; then
        jq -n --arg fix "$fixture_name" --arg tag "$local_tag" \
            '{error: ("invalid-alias-type:" + $tag), fixture: $fix, subset_supported: false}' \
            | jq -S -c .
        continue
    fi
    alias_input=$(yq eval '.sprint_1d_query.alias' "$fixture_path")
    if [[ -z "$alias_input" ]]; then
        # Empty string — also a malformed fixture.
        jq -n --arg fix "$fixture_name" \
            '{error: "missing-sprint_1d_query-alias", fixture: $fix, subset_supported: false}' \
            | jq -S -c .
        continue
    fi

    # Idempotent canonical-id case: if alias is "<provider>:<model_id>"
    # (explicit pin form), strip the provider and resolve the model_id.
    if [[ "$alias_input" == *:* ]]; then
        # Stage 1 explicit pin: provider:model_id. Today's subset accepts
        # the pin as-is (idempotent). Sprint 2 will validate the provider
        # matches MODEL_PROVIDERS[model_id].
        provider_part="${alias_input%%:*}"
        model_part="${alias_input#*:}"
        if [[ -n "${MODEL_PROVIDERS[$model_part]+_}" ]]; then
            jq -n \
                --arg fix "$fixture_name" \
                --arg input "$alias_input" \
                --arg model "$model_part" \
                --arg provider "$provider_part" \
                '{fixture: $fix, input_alias: $input, resolved_model_id: $model, resolved_provider: $provider, subset_supported: true}' \
                | jq -S -c .
            continue
        fi
        # Pin's model_id not in MODEL_PROVIDERS — defer.
        jq -n \
            --arg fix "$fixture_name" \
            --arg input "$alias_input" \
            '{deferred_to: "sprint-2-T2.6", fixture: $fix, input_alias: $input, subset_supported: false}' \
            | jq -S -c .
        continue
    fi

    # Plain alias: resolve via MODEL_IDS / MODEL_PROVIDERS.
    if [[ -n "${MODEL_IDS[$alias_input]+_}" ]]; then
        resolved_id="${MODEL_IDS[$alias_input]}"
        resolved_provider="${MODEL_PROVIDERS[$resolved_id]:-${MODEL_PROVIDERS[$alias_input]:-unknown}}"
        jq -n \
            --arg fix "$fixture_name" \
            --arg input "$alias_input" \
            --arg model "$resolved_id" \
            --arg provider "$resolved_provider" \
            '{fixture: $fix, input_alias: $input, resolved_model_id: $model, resolved_provider: $provider, subset_supported: true}' \
            | jq -S -c .
    else
        jq -n \
            --arg fix "$fixture_name" \
            --arg input "$alias_input" \
            '{deferred_to: "sprint-2-T2.6", fixture: $fix, input_alias: $input, subset_supported: false}' \
            | jq -S -c .
    fi
done < <(find "$FIXTURES_DIR" -maxdepth 1 -name '*.yaml' -type f -print0 | sort -z)
