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
    MODELS[tertiary]=$(read_config_value ".flatline_protocol.models.tertiary" "gemini-2.5-pro")
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

    if [[ $configured_count -eq 0 ]]; then
        echo "NO_API_KEYS"
        return 2
    elif [[ $available_count -eq 0 ]]; then
        echo "NO_API_KEYS"
        return 2
    elif [[ $available_count -lt $configured_count ]]; then
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
        --argjson recommendations "$recs_json" \
        --arg timestamp "$timestamp" \
        '{
            status: $status,
            exit_code: $exit_code,
            providers: $providers,
            models: $models,
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
