#!/usr/bin/env bash
# =============================================================================
# model-adapter.sh - Compatibility shim for Flatline Protocol (SDD §4.4.3)
# =============================================================================
# Version: 2.0.0
# Part of: Hounfour Upstream Extraction (Sprint 2)
#
# This shim provides backward compatibility for callers that use the legacy
# model-adapter.sh interface (--model/--mode flags). When the feature flag
# `hounfour.flatline_routing` is true, it translates calls to model-invoke.
# When false (default), it delegates to model-adapter.sh.legacy.
#
# Usage:
#   model-adapter.sh --model <model> --mode <mode> [options]
#
# Feature Flag:
#   hounfour.flatline_routing: true   → Route through model-invoke (cheval.py)
#   hounfour.flatline_routing: false   → Use legacy implementation (default)
#
# Mode → Agent Mapping:
#   review   → flatline-reviewer
#   skeptic  → flatline-skeptic
#   score    → flatline-scorer
#   dissent  → flatline-dissenter
#
# Exit codes match legacy (SDD §4.4.3):
#   0 - Success
#   1 - API error
#   2 - Invalid input
#   3 - Timeout
#   4 - Missing API key
#   5 - Invalid response format
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_FILE="$PROJECT_ROOT/.loa.config.yaml"
LEGACY_ADAPTER="$SCRIPT_DIR/model-adapter.sh.legacy"
MODEL_INVOKE="$SCRIPT_DIR/model-invoke"

# =============================================================================
# Feature Flag Check
# =============================================================================

is_flatline_routing_enabled() {
    # Check environment override first
    if [[ "${HOUNFOUR_FLATLINE_ROUTING:-}" == "true" ]]; then
        return 0
    fi
    if [[ "${HOUNFOUR_FLATLINE_ROUTING:-}" == "false" ]]; then
        return 1
    fi

    # Check config file
    if [[ -f "$CONFIG_FILE" ]] && command -v yq &> /dev/null; then
        local value
        value=$(yq -r '.hounfour.flatline_routing // false' "$CONFIG_FILE" 2>/dev/null)
        if [[ "$value" == "true" ]]; then
            return 0
        fi
    fi

    # Default: disabled
    return 1
}

# =============================================================================
# Legacy Delegation
# =============================================================================

delegate_to_legacy() {
    if [[ ! -x "$LEGACY_ADAPTER" ]]; then
        echo "ERROR: Legacy adapter not found: $LEGACY_ADAPTER" >&2
        exit 2
    fi
    exec "$LEGACY_ADAPTER" "$@"
}

# =============================================================================
# Mode → Agent Mapping
# =============================================================================

declare -A MODE_TO_AGENT=(
    ["review"]="flatline-reviewer"
    ["skeptic"]="flatline-skeptic"
    ["score"]="flatline-scorer"
    ["dissent"]="flatline-dissenter"
)

# =============================================================================
# Legacy Model Name → model-invoke Alias Translation
# =============================================================================

# The legacy adapter uses model names like "gpt-5.2" and "opus" directly.
# model-invoke uses aliases (reviewer, reasoning, opus, cheap) or
# provider:model-id format. This maps legacy names to model-invoke format.
declare -A MODEL_TO_ALIAS=(
    ["gpt-5.2"]="openai:gpt-5.2"
    ["gpt-5.3-codex"]="openai:gpt-5.3-codex"
    ["gpt-5.2-codex"]="openai:gpt-5.3-codex"    # Backward compat alias
    ["opus"]="anthropic:claude-opus-4-6"
    ["claude-opus-4.6"]="anthropic:claude-opus-4-6"
    ["claude-opus-4.5"]="anthropic:claude-opus-4-6"
    ["gemini-2.0"]="google:gemini-2.0-flash"
    ["gemini-2.5-flash"]="google:gemini-2.5-flash"
    ["gemini-2.5-pro"]="google:gemini-2.5-pro"
    ["gemini-3-flash"]="google:gemini-3-flash"
    ["gemini-3-pro"]="google:gemini-3-pro"
)

# =============================================================================
# Logging
# =============================================================================

log() {
    echo "[model-adapter:shim] $*" >&2
}

error() {
    echo "ERROR: $*" >&2
}

# =============================================================================
# Output Format Translation
# =============================================================================

# Translate model-invoke JSON output to legacy format.
# Legacy: {content, tokens_input, tokens_output, latency_ms, retries, model, mode, phase, cost_usd}
# model-invoke: {content, model, provider, usage: {input_tokens, output_tokens}, latency_ms}
translate_output() {
    local model="$1"
    local mode="$2"
    local phase="$3"

    jq \
        --arg model "$model" \
        --arg mode "$mode" \
        --arg phase "$phase" \
        '{
            content: .content,
            tokens_input: (.usage.input_tokens // 0),
            tokens_output: (.usage.output_tokens // 0),
            latency_ms: (.latency_ms // 0),
            retries: 0,
            model: $model,
            mode: $mode,
            phase: $phase,
            cost_usd: 0
        }'
}

# =============================================================================
# Shim Main
# =============================================================================

usage() {
    cat <<EOF
Usage: model-adapter.sh --model <model> --mode <mode> [options]

Compatibility shim (v2.0.0) — routes through model-invoke when
hounfour.flatline_routing is enabled, otherwise uses legacy adapter.

Models:
  gpt-5.2                    OpenAI GPT-5.2
  gpt-5.3-codex              OpenAI GPT-5.3 Codex
  opus, claude-opus-4.6      Claude Opus 4.6
  (Full model list depends on routing path)

Modes:
  review                     Generate improvements (→ flatline-reviewer)
  skeptic                    Generate concerns (→ flatline-skeptic)
  score                      Score items (→ flatline-scorer)
  dissent                    Adversarial review (→ flatline-dissenter)

Options:
  --input <file>             Input document/items to process (required)
  --phase <type>             Phase: prd, sdd, sprint (default: prd)
  --context <file>           Knowledge context file
  --prompt <file>            Custom prompt template
  --timeout <seconds>        API timeout (default: 60)
  --max-retries <n>          Max retry attempts (default: 3)
  --json                     Output as JSON (default)
  --dry-run                  Validate without calling API

Feature flag:
  hounfour.flatline_routing: true   Route through model-invoke
  hounfour.flatline_routing: false  Use legacy adapter (default)
  HOUNFOUR_FLATLINE_ROUTING=true    Environment override

Exit codes:
  0 - Success
  1 - API error
  2 - Invalid input
  3 - Timeout
  4 - Missing API key
  5 - Invalid response format
EOF
}

main() {
    # If feature flag is disabled, delegate entirely to legacy
    if ! is_flatline_routing_enabled; then
        delegate_to_legacy "$@"
        # exec above means we never reach here
    fi

    log "Flatline routing enabled — using model-invoke"

    # Parse arguments (same interface as legacy)
    local model=""
    local mode=""
    local input_file=""
    local phase="prd"
    local context_file=""
    local prompt_file=""
    local timeout="60"
    local dry_run=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --model)
                model="$2"
                shift 2
                ;;
            --mode)
                mode="$2"
                shift 2
                ;;
            --input)
                input_file="$2"
                shift 2
                ;;
            --phase)
                phase="$2"
                shift 2
                ;;
            --context)
                context_file="$2"
                shift 2
                ;;
            --prompt)
                prompt_file="$2"
                shift 2
                ;;
            --timeout)
                timeout="$2"
                shift 2
                ;;
            --max-retries)
                # Consumed but not passed through — model-invoke handles retry internally
                shift 2
                ;;
            --json)
                # Default behavior in both paths
                shift
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                usage
                exit 2
                ;;
        esac
    done

    # Validate required arguments
    if [[ -z "$model" ]]; then
        error "Model required (--model)"
        usage
        exit 2
    fi

    if [[ -z "$mode" ]]; then
        error "Mode required (--mode)"
        usage
        exit 2
    fi

    # Validate mode and resolve agent
    local agent="${MODE_TO_AGENT[$mode]:-}"
    if [[ -z "$agent" ]]; then
        error "Invalid mode: $mode"
        echo "Valid modes: review, skeptic, score, dissent" >&2
        exit 2
    fi

    if [[ -z "$input_file" ]]; then
        error "Input file required (--input)"
        exit 2
    fi

    if [[ ! -f "$input_file" ]]; then
        error "Input file not found: $input_file"
        exit 2
    fi

    if [[ ! -x "$MODEL_INVOKE" ]]; then
        error "model-invoke not found or not executable: $MODEL_INVOKE"
        exit 2
    fi

    # Translate legacy model name to model-invoke provider:model-id format
    local model_override="${MODEL_TO_ALIAS[$model]:-}"
    if [[ -z "$model_override" ]]; then
        # Unknown model — try passing as-is (may be already in provider:model format)
        model_override="$model"
    fi

    log "Mode '$mode' → Agent '$agent'"
    log "Model: $model → $model_override, Phase: $phase"

    # Mock mode — delegate to legacy which has mock fixtures
    if [[ "${FLATLINE_MOCK_MODE:-}" == "true" ]]; then
        log "Mock mode — delegating to legacy adapter"
        delegate_to_legacy --model "$model" --mode "$mode" --input "$input_file" \
            --phase "$phase" ${context_file:+--context "$context_file"} \
            ${prompt_file:+--prompt "$prompt_file"} --timeout "$timeout"
        # exec above means we never reach here
    fi

    # Build model-invoke arguments
    local -a invoke_args=(
        --agent "$agent"
        --input "$input_file"
        --model "$model_override"
        --output-format json
        --json-errors
        --timeout "$timeout"
    )

    # Map --context to --system (context file becomes system prompt for model-invoke)
    if [[ -n "$context_file" && -f "$context_file" ]]; then
        invoke_args+=(--system "$context_file")
    fi

    # Map --prompt to --system (custom prompt takes precedence over context)
    if [[ -n "$prompt_file" && -f "$prompt_file" ]]; then
        invoke_args+=(--system "$prompt_file")
    fi

    # Dry run
    if [[ "$dry_run" == "true" ]]; then
        log "Dry run — validating through model-invoke"
        "$MODEL_INVOKE" --agent "$agent" --model "$model_override" --dry-run
        exit $?
    fi

    # Call model-invoke and translate output
    local result exit_code=0
    result=$("$MODEL_INVOKE" "${invoke_args[@]}" 2>/dev/null) || exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        error "model-invoke failed with exit code $exit_code"
        exit $exit_code
    fi

    # Translate output format for backward compatibility
    echo "$result" | translate_output "$model" "$mode" "$phase"
}

main "$@"
