#!/usr/bin/env bash
# =============================================================================
# danger-level-enforcer.sh - Skill risk enforcement for guardrails
# =============================================================================
# Version: 1.0.0
# Part of: Input Guardrails & Tool Risk Enforcement v1.20.0
#
# Usage:
#   danger-level-enforcer.sh --skill implementing-tasks --mode autonomous
#   danger-level-enforcer.sh --skill deploying-infrastructure --mode autonomous --allow-high
#   danger-level-enforcer.sh --skill autonomous-agent --mode interactive
#
# Output: JSON with action (PROCEED/WARN/BLOCK) and reason
# =============================================================================

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_NAME="$(basename "$0")"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly SKILLS_DIR="$PROJECT_ROOT/.claude/skills"
readonly CONFIG_FILE="$PROJECT_ROOT/.loa.config.yaml"
readonly TRAJECTORY_DIR="$PROJECT_ROOT/grimoires/loa/a2a/trajectory"

# Require bash 4.0+ (associative arrays)
# shellcheck source=bash-version-guard.sh
source "$SCRIPT_DIR/bash-version-guard.sh"

# =============================================================================
# Default danger levels for skills (if not specified in index.yaml)
# =============================================================================

declare -A DEFAULT_DANGER_LEVELS=(
    ["discovering-requirements"]="safe"
    ["designing-architecture"]="safe"
    ["planning-sprints"]="safe"
    ["implementing-tasks"]="moderate"
    ["reviewing-code"]="safe"
    ["auditing-security"]="safe"
    ["deploying-infrastructure"]="high"
    ["run-mode"]="high"
    ["autonomous-agent"]="critical"
    ["riding-codebase"]="safe"
    ["mounting-framework"]="moderate"
    ["continuous-learning"]="safe"
    ["translating-for-executives"]="safe"
    ["enhancing-prompts"]="safe"
)

# =============================================================================
# Functions
# =============================================================================

show_help() {
    cat <<EOF
Usage: $SCRIPT_NAME [OPTIONS]

Check danger level for a skill and enforce access control.

Options:
  --skill NAME      Skill identifier (required)
  --mode MODE       Execution mode: interactive or autonomous (required)
  --allow-high      Allow high-risk skills in autonomous mode
  --log             Write decision to trajectory log
  --session-id ID   Session ID for trajectory correlation
  -h, --help        Show this help message

Danger Levels:
  safe       - Read-only operations, no side effects
  moderate   - Writes to project files
  high       - Creates infrastructure, external effects
  critical   - Full autonomous control, irreversible actions

Mode Behavior:
  Interactive:
    safe       → Execute immediately
    moderate   → Execute with notice
    high       → Require confirmation
    critical   → Require confirmation with reason

  Autonomous:
    safe       → Execute immediately
    moderate   → Execute with enhanced logging
    high       → BLOCK (unless --allow-high)
    critical   → ALWAYS BLOCK (no override)

Output (JSON):
  {
    "action": "PROCEED|WARN|BLOCK",
    "skill": "skill-name",
    "level": "safe|moderate|high|critical",
    "mode": "interactive|autonomous",
    "reason": "explanation",
    "log": true,
    "override_used": false
  }

Examples:
  $SCRIPT_NAME --skill implementing-tasks --mode autonomous
  $SCRIPT_NAME --skill deploying-infrastructure --mode autonomous --allow-high
  $SCRIPT_NAME --skill autonomous-agent --mode interactive --log
EOF
}

# Get danger level from skill index.yaml or defaults
get_danger_level() {
    local skill="$1"
    local index_file="$SKILLS_DIR/$skill/index.yaml"

    # Try to read from index.yaml
    if [[ -f "$index_file" ]]; then
        local level
        level=$(yq -r '.danger_level // "unknown"' "$index_file" 2>/dev/null || echo "unknown")
        if [[ "$level" != "unknown" && "$level" != "null" ]]; then
            echo "$level"
            return
        fi
    fi

    # Fall back to defaults
    if [[ -n "${DEFAULT_DANGER_LEVELS[$skill]:-}" ]]; then
        echo "${DEFAULT_DANGER_LEVELS[$skill]}"
        return
    fi

    # Unknown skill defaults to critical (fail-safe)
    echo "critical"
}

# Check if enforcement is enabled in config
is_enforcement_enabled() {
    if [[ -f "$CONFIG_FILE" ]]; then
        local enforce
        enforce=$(yq -r '.guardrails.danger_level.enforce // true' "$CONFIG_FILE" 2>/dev/null || echo "true")
        [[ "$enforce" == "true" ]]
    else
        return 0  # Default to enabled
    fi
}

# Log decision to trajectory (M-5 fix: use jq for safe JSON construction)
log_to_trajectory() {
    local skill="$1"
    local level="$2"
    local mode="$3"
    local action="$4"
    local reason="$5"
    local override_used="${6:-false}"
    local session_id="${7:-}"

    # Ensure trajectory directory exists
    mkdir -p "$TRAJECTORY_DIR"

    local date_str
    date_str=$(date +%Y-%m-%d)
    local log_file="$TRAJECTORY_DIR/guardrails-$date_str.jsonl"

    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Build JSON entry using jq for safe escaping (M-5 fix)
    local entry
    entry=$(jq -n \
        --arg type "danger_level" \
        --arg timestamp "$timestamp" \
        --arg session_id "$session_id" \
        --arg skill "$skill" \
        --arg action "$action" \
        --arg level "$level" \
        --arg mode "$mode" \
        --argjson override_used "$override_used" \
        --arg reason "$reason" \
        '{type: $type, timestamp: $timestamp, session_id: $session_id, skill: $skill, action: $action, level: $level, mode: $mode, override_used: $override_used, reason: $reason}')

    # Append to log (compact JSON)
    echo "$entry" | jq -c . >> "$log_file"
}

# Enforce danger level for interactive mode
enforce_interactive() {
    local skill="$1"
    local level="$2"

    case "$level" in
        safe)
            echo "PROCEED"
            echo "safe skills execute immediately in interactive mode"
            ;;
        moderate)
            echo "PROCEED"
            echo "moderate skills execute with notice in interactive mode"
            ;;
        high)
            echo "WARN"
            echo "high-risk skills require confirmation in interactive mode"
            ;;
        critical)
            echo "WARN"
            echo "critical skills require confirmation with reason in interactive mode"
            ;;
        *)
            echo "BLOCK"
            echo "unknown danger level defaults to critical behavior"
            ;;
    esac
}

# Enforce danger level for autonomous mode
enforce_autonomous() {
    local skill="$1"
    local level="$2"
    local allow_high="$3"

    case "$level" in
        safe)
            echo "PROCEED"
            echo "safe skills execute immediately in autonomous mode"
            ;;
        moderate)
            echo "PROCEED"
            echo "moderate skills execute with enhanced logging in autonomous mode"
            ;;
        high)
            if [[ "$allow_high" == "true" ]]; then
                echo "WARN"
                echo "high-risk skill allowed via --allow-high override"
            else
                echo "BLOCK"
                echo "high-risk skills blocked in autonomous mode without --allow-high"
            fi
            ;;
        critical)
            echo "BLOCK"
            echo "critical skills always blocked in autonomous mode (no override available)"
            ;;
        *)
            echo "BLOCK"
            echo "unknown danger level defaults to critical behavior"
            ;;
    esac
}

# =============================================================================
# Main
# =============================================================================

main() {
    local skill=""
    local mode=""
    local allow_high="false"
    local do_log="false"
    local session_id=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --skill)
                skill="$2"
                shift 2
                ;;
            --mode)
                mode="$2"
                shift 2
                ;;
            --allow-high)
                allow_high="true"
                shift
                ;;
            --log)
                do_log="true"
                shift
                ;;
            --session-id)
                session_id="$2"
                shift 2
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                echo "Unknown option: $1" >&2
                show_help
                exit 1
                ;;
        esac
    done

    # Validate required arguments
    if [[ -z "$skill" ]]; then
        echo "Error: --skill is required" >&2
        exit 1
    fi

    if [[ -z "$mode" ]]; then
        echo "Error: --mode is required" >&2
        exit 1
    fi

    if [[ "$mode" != "interactive" && "$mode" != "autonomous" ]]; then
        echo "Error: --mode must be 'interactive' or 'autonomous'" >&2
        exit 1
    fi

    # Check if enforcement is enabled
    if ! is_enforcement_enabled; then
        # Use jq for safe JSON output (M-5 fix)
        jq -n \
            --arg action "PROCEED" \
            --arg skill "$skill" \
            --arg level "unknown" \
            --arg mode "$mode" \
            --arg reason "danger level enforcement disabled in config" \
            --argjson log false \
            --argjson override_used false \
            '{action: $action, skill: $skill, level: $level, mode: $mode, reason: $reason, log: $log, override_used: $override_used}'
        exit 0
    fi

    # Get danger level for skill
    local level
    level=$(get_danger_level "$skill")

    # Enforce based on mode
    local result
    local action
    local reason

    if [[ "$mode" == "interactive" ]]; then
        result=$(enforce_interactive "$skill" "$level")
    else
        result=$(enforce_autonomous "$skill" "$level" "$allow_high")
    fi

    action=$(echo "$result" | head -1)
    reason=$(echo "$result" | tail -1)

    # Determine override status
    local override_used="false"
    if [[ "$allow_high" == "true" && "$level" == "high" && "$mode" == "autonomous" ]]; then
        override_used="true"
    fi

    # Log if requested
    if [[ "$do_log" == "true" ]]; then
        log_to_trajectory "$skill" "$level" "$mode" "$action" "$reason" "$override_used" "$session_id"
    fi

    # Output JSON result using jq for safe escaping (M-5 fix)
    jq -n \
        --arg action "$action" \
        --arg skill "$skill" \
        --arg level "$level" \
        --arg mode "$mode" \
        --arg reason "$reason" \
        --argjson log "$do_log" \
        --argjson override_used "$override_used" \
        '{action: $action, skill: $skill, level: $level, mode: $mode, reason: $reason, log: $log, override_used: $override_used}'
}

main "$@"
