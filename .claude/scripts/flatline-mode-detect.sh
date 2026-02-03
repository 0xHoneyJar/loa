#!/usr/bin/env bash
# =============================================================================
# flatline-mode-detect.sh - Mode detection for Flatline Protocol
# =============================================================================
# Version: 1.1.0
# Part of: Autonomous Flatline Integration v1.22.0, Simstim v1.24.0
#
# Determines whether Flatline should operate in interactive, autonomous, or hitl mode.
# Implements hardened detection with strong vs weak signal distinction.
#
# Usage:
#   flatline-mode-detect.sh [options]
#
# Options:
#   --interactive      Force interactive mode
#   --autonomous       Force autonomous mode
#   --hitl             Force HITL mode (for /simstim)
#   --json             Output as JSON (default: human-readable)
#   --quiet            Suppress logging
#
# Precedence (highest to lowest):
#   1. CLI flags (--interactive, --autonomous, --hitl)
#   2. Environment variable (LOA_FLATLINE_MODE)
#   3. Simstim context (.run/simstim-state.json exists with state=RUNNING)
#   4. Config file (autonomous_mode.enabled)
#   5. Auto-detection (strong signals only)
#   6. Default (interactive)
#
# Exit codes:
#   0 - Success
#   1 - Configuration error
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_FILE="$PROJECT_ROOT/.loa.config.yaml"
TRAJECTORY_DIR="$PROJECT_ROOT/grimoires/loa/a2a/trajectory"
SIMSTIM_STATE="$PROJECT_ROOT/.run/simstim-state.json"

# =============================================================================
# Defaults
# =============================================================================

MODE=""
REASON=""
OPERATOR_TYPE=""
CONFIDENCE=""
CLI_FLAG=""
ENV_VAR=""
CONFIG_VALUE=""
AUTO_DETECT_VALUE=""
JSON_OUTPUT=false
QUIET=false

# =============================================================================
# Logging
# =============================================================================

log() {
    if [[ "$QUIET" != "true" ]]; then
        echo "[mode-detect] $*" >&2
    fi
}

error() {
    echo "ERROR: $*" >&2
}

warn() {
    echo "WARNING: $*" >&2
}

# Log to trajectory
log_trajectory() {
    local event_type="$1"
    local data="$2"

    # Security: Create log directory with restrictive permissions
    (umask 077 && mkdir -p "$TRAJECTORY_DIR")
    local date_str
    date_str=$(date +%Y-%m-%d)
    local log_file="$TRAJECTORY_DIR/flatline-mode-$date_str.jsonl"

    # Ensure log file has restrictive permissions
    touch "$log_file"
    chmod 600 "$log_file"

    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    jq -n \
        --arg type "flatline_mode_detection" \
        --arg event "$event_type" \
        --arg timestamp "$timestamp" \
        --argjson data "$data" \
        '{type: $type, event: $event, timestamp: $timestamp, data: $data}' >> "$log_file"
}

# =============================================================================
# Configuration
# =============================================================================

read_config() {
    local path="$1"
    local default="$2"
    if [[ -f "$CONFIG_FILE" ]] && command -v yq &> /dev/null; then
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
# Operator Detection (Strong vs Weak signals)
# =============================================================================

# Detect operator type: ai_strong, ai_weak, or human
# Strong signals: Verifiable or explicit indicators
# Weak signals: Heuristic indicators that require explicit opt-in
detect_operator_type() {
    local signals=()
    local strong_signals=()
    local weak_signals=()

    # Strong Signal 1: CLAWDBOT_GATEWAY_TOKEN (verifiable AI agent token)
    if [[ -n "${CLAWDBOT_GATEWAY_TOKEN:-}" ]]; then
        strong_signals+=("CLAWDBOT_GATEWAY_TOKEN present")
    fi

    # Strong Signal 2: Explicit LOA_OPERATOR=ai
    if [[ "${LOA_OPERATOR:-}" == "ai" ]]; then
        strong_signals+=("LOA_OPERATOR=ai")
    fi

    # Strong Signal 3: Running under Claude Code gateway (verified token structure)
    if [[ -n "${ANTHROPIC_API_KEY:-}" ]] && [[ "${ANTHROPIC_API_KEY:-}" == claude-gateway-* ]]; then
        strong_signals+=("Claude gateway token detected")
    fi

    # Weak Signal 1: Non-TTY (could be piped script, CI, etc.)
    if ! tty -s 2>/dev/null; then
        weak_signals+=("Non-TTY environment")
    fi

    # Weak Signal 2: CLAUDECODE environment variable (may be set in various contexts)
    if [[ -n "${CLAUDECODE:-}" ]]; then
        weak_signals+=("CLAUDECODE env var set")
    fi

    # Weak Signal 3: CLAWDBOT_AGENT marker
    if [[ -n "${CLAWDBOT_AGENT:-}" ]]; then
        weak_signals+=("CLAWDBOT_AGENT marker")
    fi

    # Weak Signal 4: CI environment detection
    if [[ -n "${CI:-}" ]] || [[ -n "${GITHUB_ACTIONS:-}" ]] || [[ -n "${GITLAB_CI:-}" ]]; then
        weak_signals+=("CI environment detected")
    fi

    # Weak Signal 5: Moltbot/automation markers
    if [[ -n "${MOLTBOT_RUN_ID:-}" ]]; then
        weak_signals+=("MOLTBOT_RUN_ID present")
    fi

    # Determine operator type based on signals
    if [[ ${#strong_signals[@]} -gt 0 ]]; then
        OPERATOR_TYPE="ai_strong"
        CONFIDENCE="high"
        signals=("${strong_signals[@]}")
        log "Strong AI signals detected: ${strong_signals[*]}"
    elif [[ ${#weak_signals[@]} -gt 0 ]]; then
        OPERATOR_TYPE="ai_weak"
        CONFIDENCE="low"
        signals=("${weak_signals[@]}")
        warn "Weak AI signals detected: ${weak_signals[*]}"
        warn "Autonomous mode requires explicit opt-in for weak signals"
    else
        OPERATOR_TYPE="human"
        CONFIDENCE="high"
        signals+=("Interactive TTY detected" "No AI markers found")
        log "Human operator detected"
    fi

    # Return signals as JSON array for logging
    printf '%s\n' "${signals[@]}" | jq -R . | jq -s .
}

# Verify that autonomous mode is allowed given the operator type
# Returns 0 if allowed, 1 if not allowed
verify_autonomous_allowed() {
    local operator_type="$1"
    local auto_enable_for_ai
    auto_enable_for_ai=$(read_config '.autonomous_mode.auto_enable_for_ai' 'true')

    case "$operator_type" in
        "ai_strong")
            # Strong AI signals always allow autonomous if auto_enable_for_ai is true
            if [[ "$auto_enable_for_ai" == "true" ]]; then
                return 0
            else
                log "autonomous_mode.auto_enable_for_ai is false, blocking auto-enable"
                return 1
            fi
            ;;
        "ai_weak")
            # Weak signals never auto-enable - require explicit config
            warn "Weak AI signals cannot auto-enable autonomous mode"
            return 1
            ;;
        "human")
            # Human operators can use autonomous mode only with explicit config
            log "Human operator - autonomous mode requires explicit configuration"
            return 1
            ;;
        *)
            error "Unknown operator type: $operator_type"
            return 1
            ;;
    esac
}

# =============================================================================
# Simstim Context Detection
# =============================================================================

# Check if we're running within a simstim workflow
# Returns 0 if simstim is active, 1 otherwise
detect_simstim_context() {
    if [[ -f "$SIMSTIM_STATE" ]]; then
        local state
        state=$(jq -r '.state // ""' "$SIMSTIM_STATE" 2>/dev/null)
        if [[ "$state" == "RUNNING" ]]; then
            log "Simstim context detected (state=RUNNING)"
            return 0
        fi
    fi
    return 1
}

# =============================================================================
# Mode Resolution
# =============================================================================

resolve_mode() {
    # Priority 1: CLI flags (already parsed, stored in CLI_FLAG)
    if [[ -n "$CLI_FLAG" ]]; then
        MODE="$CLI_FLAG"
        REASON="CLI flag --$CLI_FLAG"
        log "Mode resolved from CLI flag: $MODE"
        return
    fi

    # Priority 2: Environment variable
    if [[ -n "${LOA_FLATLINE_MODE:-}" ]]; then
        case "${LOA_FLATLINE_MODE}" in
            "interactive"|"autonomous"|"hitl")
                MODE="$LOA_FLATLINE_MODE"
                REASON="Environment variable LOA_FLATLINE_MODE=$LOA_FLATLINE_MODE"
                ENV_VAR="$LOA_FLATLINE_MODE"
                log "Mode resolved from environment: $MODE"
                return
                ;;
            *)
                warn "Invalid LOA_FLATLINE_MODE value: $LOA_FLATLINE_MODE (expected: interactive, autonomous, hitl)"
                ;;
        esac
    fi

    # Priority 3: Simstim context (implies HITL mode)
    if detect_simstim_context; then
        MODE="hitl"
        REASON="Simstim workflow active (.run/simstim-state.json state=RUNNING)"
        log "Mode resolved from simstim context: hitl"
        return
    fi

    # Priority 4: Config file
    local config_enabled
    config_enabled=$(read_config '.autonomous_mode.enabled' 'false')
    CONFIG_VALUE="$config_enabled"

    if [[ "$config_enabled" == "true" ]]; then
        MODE="autonomous"
        REASON="Config autonomous_mode.enabled=true"
        log "Mode resolved from config: autonomous"
        return
    fi

    # Priority 5: Auto-detection (only for strong signals)
    local signals
    signals=$(detect_operator_type)

    if [[ "$OPERATOR_TYPE" == "ai_strong" ]]; then
        if verify_autonomous_allowed "$OPERATOR_TYPE"; then
            MODE="autonomous"
            REASON="Auto-detect: Strong AI operator signals"
            AUTO_DETECT_VALUE="ai_strong"
            log "Mode auto-detected: autonomous (strong AI signals)"
            return
        fi
    elif [[ "$OPERATOR_TYPE" == "ai_weak" ]]; then
        AUTO_DETECT_VALUE="ai_weak"
        warn "Weak AI signals detected but autonomous mode requires explicit opt-in"
        warn "Set autonomous_mode.enabled: true in .loa.config.yaml to enable"
    fi

    # Priority 6: Default to interactive
    MODE="interactive"
    REASON="Default (no explicit mode specified)"
    log "Mode defaulted to interactive"
}

# =============================================================================
# Output
# =============================================================================

output_result() {
    local result
    result=$(jq -n \
        --arg mode "$MODE" \
        --arg reason "$REASON" \
        --arg operator_type "$OPERATOR_TYPE" \
        --arg confidence "$CONFIDENCE" \
        --arg cli_flag "${CLI_FLAG:-null}" \
        --arg env_var "${ENV_VAR:-null}" \
        --arg config_value "${CONFIG_VALUE:-null}" \
        --arg auto_detect "${AUTO_DETECT_VALUE:-null}" \
        '{
            mode: $mode,
            reason: $reason,
            operator: {
                type: $operator_type,
                confidence: $confidence
            },
            detection: {
                cli_flag: (if $cli_flag == "null" then null else $cli_flag end),
                env_var: (if $env_var == "null" then null else $env_var end),
                config: (if $config_value == "null" then null else ($config_value == "true") end),
                auto_detect: (if $auto_detect == "null" then null else $auto_detect end)
            }
        }')

    # Log to trajectory
    log_trajectory "mode_resolved" "$result"

    if [[ "$JSON_OUTPUT" == "true" ]]; then
        echo "$result"
    else
        echo "Mode: $MODE"
        echo "Reason: $REASON"
        echo "Operator Type: $OPERATOR_TYPE"
        echo "Confidence: $CONFIDENCE"
        if [[ -n "$CLI_FLAG" ]]; then
            echo "CLI Flag: --$CLI_FLAG"
        fi
        if [[ -n "$ENV_VAR" ]]; then
            echo "Environment: LOA_FLATLINE_MODE=$ENV_VAR"
        fi
        if [[ -n "$CONFIG_VALUE" ]]; then
            echo "Config: autonomous_mode.enabled=$CONFIG_VALUE"
        fi
        if [[ -n "$AUTO_DETECT_VALUE" ]]; then
            echo "Auto-Detect: $AUTO_DETECT_VALUE"
        fi
    fi
}

# =============================================================================
# Main
# =============================================================================

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --interactive)
                CLI_FLAG="interactive"
                shift
                ;;
            --autonomous)
                CLI_FLAG="autonomous"
                shift
                ;;
            --hitl)
                CLI_FLAG="hitl"
                shift
                ;;
            --json)
                JSON_OUTPUT=true
                shift
                ;;
            --quiet|-q)
                QUIET=true
                shift
                ;;
            --help|-h)
                grep '^#' "$0" | grep -v '#!/' | sed 's/^# //' | sed 's/^#//'
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    # Resolve mode using precedence chain
    resolve_mode

    # Output result
    output_result

    # Return appropriate exit code based on mode for scripting
    if [[ "$MODE" == "autonomous" ]]; then
        exit 0
    else
        exit 0  # Both modes are valid results
    fi
}

main "$@"
