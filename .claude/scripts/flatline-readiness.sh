#!/usr/bin/env bash
# =============================================================================
# flatline-readiness.sh — Flatline Protocol readiness check
# =============================================================================
# Version: 1.0.0
# Part of: Community Feedback — Review Pipeline Hardening (cycle-048, FR-3)
#
# Checks whether the Flatline Protocol can operate by verifying:
# 1. flatline_protocol.enabled is true in .loa.config.yaml
# 2. Model-to-provider mapping resolves for configured models
# 3. Required API key env vars are present (no API calls made)
#
# Exit codes:
#   0 = READY       (all configured providers have API keys)
#   1 = DISABLED    (flatline_protocol.enabled is false)
#   2 = NO_API_KEYS (zero provider keys present)
#   3 = DEGRADED    (some but not all provider keys present)
#
# Usage:
#   flatline-readiness.sh [--json] [--quick]
#
# Flags:
#   --json   Structured JSON output (mirrors beads-health.sh interface)
#   --quick  Fast check (env vars only, skip config parsing beyond enabled)
#
# Environment:
#   PROJECT_ROOT  Override for test isolation
#
# JSON output schema:
#   {
#     "status": "READY|DEGRADED|NO_API_KEYS|DISABLED",
#     "exit_code": 0,
#     "providers": {
#       "anthropic": { "configured": true, "available": true, "env_var": "ANTHROPIC_API_KEY" },
#       ...
#     },
#     "models": { "primary": "opus", "secondary": "gpt-5.3-codex", "tertiary": "gemini-2.5-pro" },
#     "recommendations": [],
#     "timestamp": "2026-02-28T09:00:00Z"
#   }
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source bootstrap for PROJECT_ROOT and CONFIG_FILE
source "$SCRIPT_DIR/bootstrap.sh"

# =============================================================================
# Configuration
# =============================================================================

OUTPUT_MODE="text"
QUICK=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --json)
            OUTPUT_MODE="json"
            shift
            ;;
        --quick)
            QUICK=true
            shift
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Usage: flatline-readiness.sh [--json] [--quick]" >&2
            exit 1
            ;;
    esac
done

# =============================================================================
# Provider Mapping
# =============================================================================

# Map model name to "provider:PRIMARY_ENV_VAR[:ALIAS_ENV_VAR]"
map_model_to_provider() {
    local model="$1"
    case "$model" in
        opus|claude-*|anthropic-*)
            echo "anthropic:ANTHROPIC_API_KEY" ;;
        gpt-*|openai-*)
            echo "openai:OPENAI_API_KEY" ;;
        gemini-*|google-*)
            # GOOGLE_API_KEY is canonical (per cheval.py, google_adapter.py)
            # GEMINI_API_KEY accepted as alias with deprecation warning
            echo "google:GOOGLE_API_KEY:GEMINI_API_KEY" ;;
        *)
            echo "unknown:" ;;
    esac
}

# =============================================================================
# Config Reading
# =============================================================================

read_config_value() {
    local path="$1"
    local default="$2"
    if [[ -f "$CONFIG_FILE" ]] && command -v yq &>/dev/null; then
        local value
        value=$(yq -r "$path // \"\"" "$CONFIG_FILE" 2>/dev/null)
        if [[ -n "$value" && "$value" != "null" ]]; then
            echo "$value"
            return
        fi
    fi
    echo "$default"
}

# =============================================================================
# Check Functions
# =============================================================================

# Populated by check functions
declare -A PROVIDERS_CONFIGURED  # provider -> true/false
declare -A PROVIDERS_AVAILABLE   # provider -> true/false
declare -A PROVIDERS_ENV_VAR     # provider -> env var name
declare -A MODELS                # role -> model name
declare -a RECOMMENDATIONS=()

check_enabled() {
    local enabled
    enabled=$(read_config_value ".flatline_protocol.enabled" "false")
    [[ "$enabled" == "true" ]]
}

check_models() {
    MODELS[primary]=$(read_config_value ".flatline_protocol.models.primary" "opus")
    MODELS[secondary]=$(read_config_value ".flatline_protocol.models.secondary" "gpt-5.3-codex")
    # Issue #756: orchestrator's get_model_tertiary() reads hounfour first,
    # then flatline_protocol.models.tertiary. Mirror that lookup order so
    # readiness reports the same active tertiary the orchestrator will use —
    # otherwise readiness can show "Tertiary: gemini-2.5-pro" while the
    # orchestrator runs gemini-3.1-pro-preview, which masks misconfiguration.
    local tertiary_hounfour
    tertiary_hounfour=$(read_config_value ".hounfour.flatline_tertiary_model" "")
    if [[ -n "$tertiary_hounfour" ]]; then
        MODELS[tertiary]="$tertiary_hounfour"
    else
        MODELS[tertiary]=$(read_config_value ".flatline_protocol.models.tertiary" "gemini-2.5-pro")
    fi
}

# Issue #756: eager validation against the alias registry. Without this, an
# operator setting `hounfour.flatline_tertiary_model: gemini-3.1-pro-preview`
# (the canonical google api id, NOT a registered alias) sees readiness report
# READY but every Flatline tertiary call then fails with cheval's
# `Unknown alias: 'gemini-3.1-pro-preview'`. Surface DEGRADED + actionable
# error AT readiness time instead of after the operator burns API spend.
#
# Accepts:
#   1. Registered alias name (in `.aliases` of model-config.yaml).
#   2. Explicit pin form `<provider>:<model_id>` (matches FR-3.9 stage 1).
#
# Populates ALIAS_VALIDATION_ERRORS[role] = error string on miss.
declare -A ALIAS_VALIDATION_ERRORS
declare -a REGISTERED_ALIASES_CACHE=()
_REGISTERED_ALIASES_LOADED=false
_REGISTRY_AVAILABLE=false  # set to true when registry actually loaded ≥1 alias

_load_registered_aliases() {
    if [[ "$_REGISTERED_ALIASES_LOADED" == "true" ]]; then
        return 0
    fi
    local defaults_yaml="${LOA_DEFAULTS_YAML:-${PROJECT_ROOT:-.}/.claude/defaults/model-config.yaml}"
    if [[ ! -f "$defaults_yaml" ]]; then
        # Registry unavailable: alias validation must be SKIPPED (not applied
        # to an empty cache). is_valid_alias gates on _REGISTRY_AVAILABLE so
        # operators in submodule-without-defaults-symlink mode (issue #755 if
        # not yet applied) don't see false-positive DEGRADED states. The
        # operator's actual misconfiguration (a model_id where alias is
        # expected) will surface later via cheval — degraded behaviour, but
        # this readiness check is informational, not the canonical defense.
        # Warning behind LOA_FLATLINE_VERBOSE=1 because bats `run` merges
        # stderr into output, polluting JSON-parse assertions in existing
        # readiness tests that don't have the defaults yaml available.
        if [[ "${LOA_FLATLINE_VERBOSE:-0}" == "1" ]]; then
            echo "WARNING: $defaults_yaml not found; alias validation skipped (#756 gate inactive)" >&2
        fi
        _REGISTERED_ALIASES_LOADED=true
        return 0
    fi
    # Read alias keys from yaml. yq exits non-zero on missing key; tolerate.
    local aliases_str
    aliases_str=$(yq -r '.aliases // {} | keys | .[]' "$defaults_yaml" 2>/dev/null || true)
    if [[ -n "$aliases_str" ]]; then
        # Read alias-by-alias into the array (newline-delimited).
        while IFS= read -r alias_name; do
            [[ -n "$alias_name" ]] && REGISTERED_ALIASES_CACHE+=("$alias_name")
        done <<< "$aliases_str"
    fi
    if [[ ${#REGISTERED_ALIASES_CACHE[@]} -gt 0 ]]; then
        _REGISTRY_AVAILABLE=true
    fi
    _REGISTERED_ALIASES_LOADED=true
}

# is_valid_alias <model_or_pin> — return 0 if valid, 1 if not. Quiet — caller
# decides whether to emit error.
is_valid_alias() {
    local model="$1"
    [[ -z "$model" ]] && return 1
    # Accept explicit pin form `<provider>:<model_id>` (FR-3.9 stage 1).
    # The bash twin's _stage1_explicit_pin uses the same partition.
    if [[ "$model" == *:* ]]; then
        local provider="${model%%:*}"
        local model_id="${model#*:}"
        # Reject URL-shaped values (cycle-099 #761 hardening). A legitimate
        # provider:model_id pin never has `//` after the colon.
        if [[ "$model_id" == //* ]]; then
            return 1
        fi
        if [[ -n "$provider" && -n "$model_id" ]]; then
            return 0
        fi
    fi
    _load_registered_aliases
    local registered
    for registered in "${REGISTERED_ALIASES_CACHE[@]:-}"; do
        if [[ "$registered" == "$model" ]]; then
            return 0
        fi
    done
    return 1
}

# Issue #756 main validator: cross-check each role's configured model
# against the alias registry. Records error messages with the alias-list
# hint so operators can map their mistake to the correct alias name.
# Skip entirely when the registry isn't loadable (submodule without defaults
# symlink; test isolation that strips defaults yaml). The check is
# informational; the canonical failure mode is cheval rejecting at runtime.
check_alias_registry() {
    _load_registered_aliases
    if [[ "$_REGISTRY_AVAILABLE" != "true" ]]; then
        return 0
    fi
    local roles=("primary" "secondary" "tertiary")
    local role
    for role in "${roles[@]}"; do
        local model="${MODELS[$role]:-}"
        [[ -z "$model" ]] && continue
        if ! is_valid_alias "$model"; then
            local hint=""
            if [[ ${#REGISTERED_ALIASES_CACHE[@]} -gt 0 ]]; then
                hint=" Available aliases: $(printf '%s, ' "${REGISTERED_ALIASES_CACHE[@]}" | sed 's/, $//')"
            fi
            ALIAS_VALIDATION_ERRORS[$role]="Configured $role '$model' is not a registered alias and not a 'provider:model_id' pin.$hint"
            RECOMMENDATIONS+=("Set ${role^} to a registered alias (e.g. 'gemini-3.1-pro' instead of 'gemini-3.1-pro-preview') or use 'google:<model_id>' pin form")
        fi
    done
}

check_provider_keys() {
    # Build unique provider set from configured models
    local roles=("primary" "secondary" "tertiary")

    for role in "${roles[@]}"; do
        local model="${MODELS[$role]:-}"
        [[ -z "$model" ]] && continue

        local mapping
        mapping=$(map_model_to_provider "$model")

        local provider="${mapping%%:*}"
        local env_info="${mapping#*:}"
        local primary_var="${env_info%%:*}"
        local alias_var=""

        # Check for alias (third colon-separated field)
        if [[ "$env_info" == *:* ]]; then
            alias_var="${env_info#*:}"
        fi

        [[ -z "$provider" || "$provider" == "unknown" ]] && continue

        PROVIDERS_CONFIGURED[$provider]=true
        PROVIDERS_ENV_VAR[$provider]="$primary_var"

        # Check primary env var
        if [[ -n "${!primary_var:-}" ]]; then
            PROVIDERS_AVAILABLE[$provider]=true
        elif [[ -n "$alias_var" && -n "${!alias_var:-}" ]]; then
            # Alias present — use it but emit deprecation warning
            PROVIDERS_AVAILABLE[$provider]=true
            echo "WARNING: $alias_var is deprecated, use $primary_var" >&2
        else
            PROVIDERS_AVAILABLE[$provider]=false
            RECOMMENDATIONS+=("Set $primary_var for $provider provider")
        fi
    done
}

# =============================================================================
# Status Determination
# =============================================================================

determine_status() {
    local configured_count=0
    local available_count=0

    for provider in "${!PROVIDERS_CONFIGURED[@]}"; do
        if [[ "${PROVIDERS_CONFIGURED[$provider]}" == "true" ]]; then
            configured_count=$((configured_count + 1))
            if [[ "${PROVIDERS_AVAILABLE[$provider]}" == "true" ]]; then
                available_count=$((available_count + 1))
            fi
        fi
    done

    # Issue #756: any alias-validation error downgrades to DEGRADED
    # regardless of provider-key availability. An invalid alias means the
    # actual cheval call will fail, so READY would be a lie.
    # bash 5.2 still raises "unbound variable" on `${!foo[@]}` for an empty
    # associative array under `set -u`; gate via `${foo[@]+_}` first.
    local alias_error_count=0
    if [[ "${ALIAS_VALIDATION_ERRORS[@]+_}" ]]; then
        local _role
        for _role in "${!ALIAS_VALIDATION_ERRORS[@]}"; do
            if [[ -n "${ALIAS_VALIDATION_ERRORS[$_role]}" ]]; then
                alias_error_count=$((alias_error_count + 1))
            fi
        done
    fi

    if [[ $configured_count -eq 0 ]]; then
        echo "NO_API_KEYS"
        return 2
    elif [[ $available_count -eq 0 ]]; then
        echo "NO_API_KEYS"
        return 2
    elif [[ $available_count -lt $configured_count ]] || [[ $alias_error_count -gt 0 ]]; then
        echo "DEGRADED"
        return 3
    else
        echo "READY"
        return 0
    fi
}

# =============================================================================
# Output Functions
# =============================================================================

output_json() {
    local status="$1"
    local exit_code="$2"

    # Build providers object using jq -n to avoid string interpolation injection
    local providers_json
    providers_json=$(jq -n \
        --argjson anthro_configured "${PROVIDERS_CONFIGURED[anthropic]:-false}" \
        --argjson anthro_available "${PROVIDERS_AVAILABLE[anthropic]:-false}" \
        --arg anthro_env "${PROVIDERS_ENV_VAR[anthropic]:-}" \
        --argjson openai_configured "${PROVIDERS_CONFIGURED[openai]:-false}" \
        --argjson openai_available "${PROVIDERS_AVAILABLE[openai]:-false}" \
        --arg openai_env "${PROVIDERS_ENV_VAR[openai]:-}" \
        --argjson google_configured "${PROVIDERS_CONFIGURED[google]:-false}" \
        --argjson google_available "${PROVIDERS_AVAILABLE[google]:-false}" \
        --arg google_env "${PROVIDERS_ENV_VAR[google]:-}" \
        '{
            anthropic: {configured: $anthro_configured, available: $anthro_available, env_var: $anthro_env},
            openai: {configured: $openai_configured, available: $openai_available, env_var: $openai_env},
            google: {configured: $google_configured, available: $google_available, env_var: $google_env}
        }')

    # Build models object
    local models_json
    models_json=$(jq -n \
        --arg primary "${MODELS[primary]:-}" \
        --arg secondary "${MODELS[secondary]:-}" \
        --arg tertiary "${MODELS[tertiary]:-}" \
        '{primary: $primary, secondary: $secondary, tertiary: $tertiary}')

    # Issue #756: surface alias-validation errors in JSON output. Operators
    # parsing this output (CI, dashboards) need a machine-readable signal,
    # not a recommendations text-blob.
    # `${ALIAS_VALIDATION_ERRORS[@]+_}` guard to avoid bash 5.2's strict-mode
    # `unbound variable` on accessing an empty associative array's keys.
    local alias_errors_json="{}"
    if [[ "${ALIAS_VALIDATION_ERRORS[@]+_}" ]]; then
        # Reach individual entries via the +_ guard form so missing keys
        # produce empty strings instead of raising under set -u.
        local _ae_primary _ae_secondary _ae_tertiary
        _ae_primary="${ALIAS_VALIDATION_ERRORS[primary]+${ALIAS_VALIDATION_ERRORS[primary]}}"
        _ae_secondary="${ALIAS_VALIDATION_ERRORS[secondary]+${ALIAS_VALIDATION_ERRORS[secondary]}}"
        _ae_tertiary="${ALIAS_VALIDATION_ERRORS[tertiary]+${ALIAS_VALIDATION_ERRORS[tertiary]}}"
        alias_errors_json=$(jq -n \
            --arg primary "$_ae_primary" \
            --arg secondary "$_ae_secondary" \
            --arg tertiary "$_ae_tertiary" \
            '{primary: $primary, secondary: $secondary, tertiary: $tertiary}
             | with_entries(select(.value != ""))')
    fi

    # Build recommendations array
    local recs_json
    if [[ ${#RECOMMENDATIONS[@]} -gt 0 ]]; then
        recs_json=$(printf '%s\n' "${RECOMMENDATIONS[@]}" | jq -R . | jq -s .)
    else
        recs_json="[]"
    fi

    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    jq -n \
        --arg status "$status" \
        --argjson exit_code "$exit_code" \
        --argjson providers "$providers_json" \
        --argjson models "$models_json" \
        --argjson alias_errors "$alias_errors_json" \
        --argjson recommendations "$recs_json" \
        --arg timestamp "$timestamp" \
        '{
            status: $status,
            exit_code: $exit_code,
            providers: $providers,
            models: $models,
            alias_validation_errors: $alias_errors,
            recommendations: $recommendations,
            timestamp: $timestamp
        }'
}

output_text() {
    local status="$1"

    echo "Flatline Protocol Readiness"
    echo "==========================="
    echo ""
    echo "Status: $status"
    echo ""
    echo "Models:"
    echo "  Primary:   ${MODELS[primary]:-unset}"
    echo "  Secondary: ${MODELS[secondary]:-unset}"
    echo "  Tertiary:  ${MODELS[tertiary]:-unset}"
    echo ""
    echo "Providers:"
    for provider in anthropic openai google; do
        local configured="${PROVIDERS_CONFIGURED[$provider]:-false}"
        local available="${PROVIDERS_AVAILABLE[$provider]:-false}"
        if [[ "$configured" == "true" ]]; then
            local env_var="${PROVIDERS_ENV_VAR[$provider]:-}"
            local icon="[x]"
            [[ "$available" != "true" ]] && icon="[ ]"
            echo "  $icon $provider ($env_var)"
        fi
    done
    echo ""

    if [[ ${#RECOMMENDATIONS[@]} -gt 0 ]]; then
        echo "Recommendations:"
        for rec in "${RECOMMENDATIONS[@]}"; do
            [[ -n "$rec" ]] && echo "  - $rec"
        done
    fi
}

# =============================================================================
# Main
# =============================================================================

main() {
    # Check if flatline protocol is enabled
    if ! check_enabled; then
        RECOMMENDATIONS+=("Enable flatline_protocol in .loa.config.yaml")
        if [[ "$OUTPUT_MODE" == "json" ]]; then
            # Initialize empty provider/model state for disabled output
            local timestamp
            timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
            jq -n \
                --arg status "DISABLED" \
                --argjson exit_code 1 \
                --argjson providers '{}' \
                --argjson models '{}' \
                --arg timestamp "$timestamp" \
                '{
                    status: $status,
                    exit_code: $exit_code,
                    providers: $providers,
                    models: $models,
                    recommendations: ["Enable flatline_protocol in .loa.config.yaml"],
                    timestamp: $timestamp
                }'
        else
            echo "Flatline Protocol: DISABLED"
            echo ""
            echo "Enable with: flatline_protocol.enabled: true in .loa.config.yaml"
        fi
        exit 1
    fi

    # Read model configuration
    check_models

    # Issue #756: validate configured models against the alias registry
    # BEFORE provider-key checks, so a misconfigured alias surfaces DEGRADED
    # even if all keys are present. Without this, the operator hits cheval's
    # `Unknown alias: ...` at runtime instead of seeing the readiness signal.
    check_alias_registry

    # Check provider API keys
    check_provider_keys

    # Determine overall status
    local status exit_code
    set +e
    status=$(determine_status)
    exit_code=$?
    set -e

    # Output results
    if [[ "$OUTPUT_MODE" == "json" ]]; then
        output_json "$status" "$exit_code"
    else
        output_text "$status"
    fi

    exit "$exit_code"
}

main "$@"
