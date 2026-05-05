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
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FIXTURES_DIR="${LOA_GOLDEN_FIXTURES_DIR:-$PROJECT_ROOT/tests/fixtures/model-resolution}"
RESOLVER="${LOA_GOLDEN_RESOLVER:-$PROJECT_ROOT/.claude/scripts/lib/model-resolver.sh}"

if [[ ! -d "$FIXTURES_DIR" ]]; then
    printf 'golden_resolution.sh: fixtures dir %q not present\n' "$FIXTURES_DIR" >&2
    exit 2
fi
if [[ ! -f "$RESOLVER" ]]; then
    printf 'golden_resolution.sh: resolver %q not present\n' "$RESOLVER" >&2
    exit 2
fi

# Sourcing populates MODEL_PROVIDERS + MODEL_IDS associative arrays AND
# defines `resolve_alias` / `resolve_provider_id` functions. The resolver
# script's strict-mode-respect means we don't need to set anything special.
# shellcheck source=/dev/null
source "$RESOLVER"

# For each fixture, extract sprint_1d_query.alias, run resolution, emit JSON.
# Sort by filename so output ordering is deterministic across runtimes.
while IFS= read -r -d '' fixture_path; do
    fixture_name=$(basename "$fixture_path" .yaml)
    alias_input=$(yq eval '.sprint_1d_query.alias // ""' "$fixture_path")
    if [[ -z "$alias_input" || "$alias_input" == "null" ]]; then
        # Malformed fixture — emit error marker (uniform across runtimes).
        jq -n --arg fix "$fixture_name" \
            '{fixture: $fix, error: "missing-sprint_1d_query-alias", subset_supported: false}' \
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
