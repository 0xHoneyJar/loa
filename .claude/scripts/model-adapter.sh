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

# cycle-099 sprint-1B (T1.8): bring the canonical model registry into scope
# (MODEL_PROVIDERS / MODEL_IDS / COST_INPUT / COST_OUTPUT). The local
# MODEL_TO_ALIAS map below is preserved for the test contract in
# tests/unit/model-adapter-aliases.bats (T8 greps the file for keys),
# but lookups now prefer resolve_provider_id at the call site (line ~470)
# so retired aliases fail loudly at the codegen layer instead of silent-
# routing through a stale local entry.
# shellcheck source=lib/model-resolver.sh
source "$SCRIPT_DIR/lib/model-resolver.sh"

# cycle-099 sprint-2C (T2.5): source the operator-extras-aware overlay
# helper. Sourcing this file only declares functions and resolves the
# (readonly) merged/lockfile/python3 paths — it does NOT touch the
# filesystem or invoke the hook. The actual init (`loa_overlay_init`)
# happens INSIDE `main()` only when v2.0 routing is enabled, so the
# default legacy path stays bit-identical to pre-cycle-099 behavior
# (per GP-F2 / CYP-F11 dual-review fix).
# shellcheck source=lib/overlay-source-helper.sh
source "$SCRIPT_DIR/lib/overlay-source-helper.sh"

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
    ["opus"]="anthropic:claude-opus-4-7"
    ["claude-opus-4.7"]="anthropic:claude-opus-4-7"
    ["claude-opus-4-7"]="anthropic:claude-opus-4-7"    # Current canonical (cycle-082)
    ["claude-opus-4.6"]="anthropic:claude-opus-4-7"    # Retargeted to current (bash path); YAML preserves 4.6 for pinning
    ["claude-opus-4-6"]="anthropic:claude-opus-4-7"    # Retargeted to current (bash path); YAML preserves 4.6 for pinning
    ["claude-opus-4.5"]="anthropic:claude-opus-4-7"
    ["claude-opus-4-5"]="anthropic:claude-opus-4-7"    # Hyphenated → current
    ["claude-opus-4.1"]="anthropic:claude-opus-4-7"    # Legacy → current
    ["claude-opus-4-1"]="anthropic:claude-opus-4-7"    # Legacy hyphenated → current
    ["claude-opus-4.0"]="anthropic:claude-opus-4-7"    # Legacy → current
    ["claude-opus-4-0"]="anthropic:claude-opus-4-7"    # Legacy hyphenated → current
    ["gemini-2.0"]="google:gemini-2.0-flash"
    ["gemini-2.5-flash"]="google:gemini-2.5-flash"
    ["gemini-2.5-pro"]="google:gemini-2.5-pro"
    # gemini-3-flash, gemini-3-pro, gemini-3.1-pro removed per #574 —
    # they passed allowlist but Google v1beta returned NOT_FOUND. Re-add
    # when vendor confirms availability (smoke test via live API first).
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
# Probe-cache integration (Sprint 3B Task 3B.7 — SDD §5.1 row 4-5, §6.2)
# =============================================================================

PROBE_CACHE_PATH="${LOA_CACHE_DIR:-.run}/model-health-cache.json"
PROBE_SCRIPT="${LOA_PROBE_SCRIPT:-$(dirname "${BASH_SOURCE[0]}")/model-health-probe.sh}"

# Honor LOA_PROBE_BYPASS in the adapter as well — the probe script handles the
# audit + TTL on bypass set; the adapter only reads the env var to decide
# whether to consult the cache at all. The probe-side `_check_bypass` already
# refused-with-audit when no reason is given.
_adapter_bypass_active() {
    [[ "${LOA_PROBE_BYPASS:-0}" == "1" ]] && [[ -n "${LOA_PROBE_BYPASS_REASON:-}" ]]
}

# Lock-free cache read with one parse-retry (SDD §3.6 Pattern 2).
# Stdout: full cache JSON, or empty shell on read/parse failure.
_adapter_cache_read() {
    local attempt=0 cache
    [[ -f "$PROBE_CACHE_PATH" ]] || { echo '{"schema_version":"1.0","entries":{}}'; return 0; }
    while [[ $attempt -lt 2 ]]; do
        cache="$(cat "$PROBE_CACHE_PATH" 2>/dev/null)" || { attempt=$((attempt+1)); sleep 0.05; continue; }
        if echo "$cache" | jq empty 2>/dev/null; then
            echo "$cache"
            return 0
        fi
        attempt=$((attempt+1))
        sleep 0.05
    done
    # Two failed attempts -> treat as cold-start; never block adapter on read.
    # Surface to stderr (review iter-2 S-2 — observability gap fix).
    error "model-health-cache.json corrupt or torn after retry; treating as cold-start. Run \`.claude/scripts/model-health-probe.sh --invalidate\` to regenerate."
    echo '{"schema_version":"1.0","entries":{}}'
}

# Spawn a background re-probe if no probe is already running for the provider.
# Uses the same PID sentinel as model-health-probe.sh's _spawn_bg_probe_if_none_running,
# including the `set -C` atomic-claim race fix (review iter-2 B-2).
_adapter_spawn_bg_probe() {
    local provider="$1"
    local sentinel="${LOA_CACHE_DIR:-.run}/model-health-probe.${provider}.pid"
    [[ -x "$PROBE_SCRIPT" ]] || return 0  # probe missing -> no-op

    # Stale-sentinel cleanup: PID dead OR file >10min old (defensive).
    if [[ -f "$sentinel" ]]; then
        local pid age_s
        pid="$(cat "$sentinel" 2>/dev/null || echo "")"
        age_s=$(( $(date +%s) - $(stat -c %Y "$sentinel" 2>/dev/null || stat -f %m "$sentinel" 2>/dev/null || echo 0) ))
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null && (( age_s < 600 )); then
            return 0   # already running
        fi
        rm -f "$sentinel"
    fi

    # Atomic claim — `set -C` (noclobber) makes `>` fail if the file exists,
    # closing the TOCTOU race when multiple adapter calls reach this point
    # simultaneously. First caller wins; the rest dedup silently.
    if ! ( set -C; echo "$$" > "$sentinel" ) 2>/dev/null; then
        return 0
    fi

    (
        # Replace the parent's PID with the subshell's so kill -0 reflects probe liveness.
        echo "$$" > "$sentinel"
        trap 'rm -f "$sentinel"' EXIT
        "$PROBE_SCRIPT" --provider "$provider" --once --quiet >/dev/null 2>&1 || true
    ) &
    disown 2>/dev/null || true
}

# Pre-flight cache consult — SDD §5.1 row 4-5, §6.2.
# Returns 0 if model is OK to use; returns 1 with actionable stderr otherwise.
# Best-effort: cache absent / jq missing / parse failure -> fail-open.
_probe_cache_check() {
    local provider_model_id="$1"
    [[ -z "$provider_model_id" || "$provider_model_id" != *":"* ]] && return 0

    if _adapter_bypass_active; then
        log "LOA_PROBE_BYPASS=1 with reason; skipping cache check"
        return 0
    fi

    command -v jq >/dev/null 2>&1 || return 0  # jq missing -> fail-open
    [[ -f "$PROBE_CACHE_PATH" ]] || return 0   # cold-start -> fail-open

    local cache state reason probed_at
    cache="$(_adapter_cache_read)"
    state="$(echo "$cache" | jq -r --arg k "$provider_model_id" '.entries[$k].state // empty')"
    reason="$(echo "$cache" | jq -r --arg k "$provider_model_id" '.entries[$k].reason // empty')"
    probed_at="$(echo "$cache" | jq -r --arg k "$provider_model_id" '.entries[$k].probed_at // empty')"

    # Async re-probe if entry exists and is stale-ish (>= positive_ttl).
    if [[ -n "$state" ]]; then
        local provider="${provider_model_id%%:*}"
        local probed_epoch now age_h
        probed_epoch="$(date -u -d "$probed_at" +%s 2>/dev/null || date -ju -f "%Y-%m-%dT%H:%M:%SZ" "$probed_at" +%s 2>/dev/null || echo 0)"
        if [[ "$probed_epoch" -gt 0 ]]; then
            now="$(date +%s)"
            age_h=$(( (now - probed_epoch) / 3600 ))
            # Spawn bg re-probe if entry is older than ~24h (positive_ttl boundary).
            if (( age_h >= 24 )); then
                _adapter_spawn_bg_probe "$provider"
            fi
        fi
    fi

    case "$state" in
        AVAILABLE|"")
            return 0
            ;;
        UNAVAILABLE)
            error "Model '$provider_model_id' marked UNAVAILABLE by probe on ${probed_at}: ${reason}"
            error "  Run: .claude/scripts/model-health-probe.sh --invalidate ${provider_model_id##*:}"
            error "  Or:  set LOA_PROBE_BYPASS=1 with LOA_PROBE_BYPASS_REASON to override (24h TTL, audit-logged)"
            return 1
            ;;
        UNKNOWN)
            local degraded_ok="true"
            if command -v yq >/dev/null 2>&1 && [[ -f "${LOA_CONFIG:-.loa.config.yaml}" ]]; then
                local v
                v="$(yq eval '.model_health_probe.degraded_ok' "${LOA_CONFIG:-.loa.config.yaml}" 2>/dev/null)"
                [[ "$v" == "false" ]] && degraded_ok="false"
            fi
            if [[ "$degraded_ok" == "true" ]]; then
                log "Model '$provider_model_id' state UNKNOWN; proceeding (degraded_ok=true; reason: ${reason})"
                return 0
            else
                error "Model '$provider_model_id' state UNKNOWN and degraded_ok=false: ${reason}"
                error "  Run: .claude/scripts/model-health-probe.sh --invalidate ${provider_model_id##*:}"
                return 1
            fi
            ;;
    esac
    return 0
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
  opus, claude-opus-4.7      Claude Opus 4.7 (current; 4.6 alias retargeted to 4.7 in bash layer)
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

    # cycle-099 sprint-2C (T2.5): initialize the operator-extras-aware
    # overlay. Best-effort — if the merged file is unavailable and the
    # hook regen also fails, the framework-only model-resolver.sh resolver
    # below remains the resolution path.
    loa_overlay_init || true

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

    # cycle-099 sprint-2C (T2.5) + sprint-1B (T1.8): resolution chain in
    # precedence order:
    #   (a) overlay-source-helper.sh::loa_overlay_resolve_provider_id —
    #       operator-extras-aware (.run/merged-model-aliases.sh, when present);
    #       includes both framework defaults AND `model_aliases_extra` entries.
    #   (b) model-resolver.sh::resolve_provider_id — framework-only canonical
    #       map; hits when overlay is unavailable.
    #   (c) local MODEL_TO_ALIAS — backward-compat retargets (4.0-4.5 → 4.7).
    #   (d) pass-through — last resort; may already be `provider:model_id`.
    #
    # Defense: refresh-if-stale picks up cross-process regen between adapter
    # invocations (NFR-Compat-X loader contract per SDD §6.3.4). Cheap header
    # read; no-op when overlay is unavailable.
    loa_overlay_refresh_if_stale 2>/dev/null || true

    local model_override
    if model_override="$(loa_overlay_resolve_provider_id "$model" 2>/dev/null)"; then
        : # operator-extras-aware overlay resolved
    elif model_override="$(resolve_provider_id "$model" 2>/dev/null)"; then
        : # framework canonical alias resolved
    elif [[ -n "${MODEL_TO_ALIAS[$model]:-}" ]]; then
        model_override="${MODEL_TO_ALIAS[$model]}"
    else
        model_override="$model"
    fi

    log "Mode '$mode' → Agent '$agent'"
    log "Model: $model → $model_override, Phase: $phase"

    # Probe-cache pre-flight (Sprint 3B Task 3B.7) — short-circuit on
    # UNAVAILABLE before spending an API call. Skipped in mock and dry-run.
    if [[ "${FLATLINE_MOCK_MODE:-}" != "true" ]] && [[ "$dry_run" != "true" ]]; then
        if ! _probe_cache_check "$model_override"; then
            exit 4   # Same code as missing-key family — model not usable
        fi
    fi

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
