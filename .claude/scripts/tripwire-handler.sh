#!/usr/bin/env bash
# =============================================================================
# tripwire-handler.sh - Handle tripwire events for parallel guardrail failures
# =============================================================================
# Version: 1.0.0
# Part of: Input Guardrails & Tool Risk Enforcement v1.20.0
#
# Usage:
#   tripwire-handler.sh --skill implementing-tasks --check injection_detection --reason "Injection detected"
#   tripwire-handler.sh --skill deploying-infrastructure --check pii_filter --rollback
#
# Output: JSON with tripwire action taken
# =============================================================================

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_NAME="$(basename "$0")"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly CONFIG_FILE="$PROJECT_ROOT/.loa.config.yaml"
readonly TRAJECTORY_DIR="$PROJECT_ROOT/grimoires/loa/a2a/trajectory"
readonly GUARDRAIL_LOGGER="$SCRIPT_DIR/guardrail-logger.sh"

# =============================================================================
# Functions
# =============================================================================

show_help() {
    cat <<EOF
Usage: $SCRIPT_NAME [OPTIONS]

Handle tripwire events when parallel guardrails fail.

Required Options:
  --skill NAME      Skill that triggered tripwire
  --check NAME      Guardrail check that failed
  --reason TEXT     Reason for failure

Optional:
  --rollback        Attempt to rollback uncommitted changes
  --session-id ID   Session ID for trajectory correlation
  --quiet           Suppress user notification
  -h, --help        Show this help message

Tripwire Actions:
  halt    - Stop execution immediately
  warn    - Log warning and continue
  log     - Log event only

Output (JSON):
  {
    "action": "halt|warn|log",
    "skill": "skill-name",
    "check": "check-name",
    "reason": "failure reason",
    "rollback_performed": true|false
  }

Examples:
  $SCRIPT_NAME --skill implementing-tasks --check injection_detection --reason "Score 0.85"
  $SCRIPT_NAME --skill deploying-infrastructure --check pii_filter --rollback
EOF
}

# Read config value with default
get_config() {
    local key="$1"
    local default="$2"

    if [[ -f "$CONFIG_FILE" ]]; then
        local value
        value=$(yq -r "$key // \"$default\"" "$CONFIG_FILE" 2>/dev/null || echo "$default")
        if [[ "$value" == "null" ]]; then
            echo "$default"
        else
            echo "$value"
        fi
    else
        echo "$default"
    fi
}

# Check if tripwire is enabled
is_tripwire_enabled() {
    local enabled
    enabled=$(get_config ".guardrails.tripwire.enabled" "true")
    [[ "$enabled" == "true" ]]
}

# Get tripwire action mode
get_tripwire_action() {
    get_config ".guardrails.tripwire.on_failure" "halt"
}

# Check if rollback is enabled
is_rollback_enabled() {
    local enabled
    enabled=$(get_config ".guardrails.tripwire.rollback_on_halt" "false")
    [[ "$enabled" == "true" ]]
}

# Attempt to rollback uncommitted changes (M-4 fix: stash before rollback)
perform_rollback() {
    local rollback_result="false"

    # Check for uncommitted changes
    if git diff --quiet 2>/dev/null && git diff --cached --quiet 2>/dev/null; then
        echo "no_changes"
        return
    fi

    # M-4 fix: Create stash backup before rollback to prevent data loss
    local stash_name="guardrail-rollback-$(date +%s)"
    if git stash push -m "$stash_name" --include-untracked 2>/dev/null; then
        # Log the stash for recovery
        echo "Changes stashed as: $stash_name" >&2
        echo "To recover: git stash pop" >&2
        rollback_result="true"
    else
        # Stash failed, try direct restore (less safe)
        if git restore . 2>/dev/null; then
            rollback_result="true"
        fi
    fi

    echo "$rollback_result"
}

# Log tripwire event to trajectory (M-5 fix: use jq for safe JSON construction)
log_tripwire() {
    local skill="$1"
    local check="$2"
    local reason="$3"
    local action="$4"
    local rollback_performed="$5"
    local session_id="${6:-}"

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
        --arg type "tripwire" \
        --arg timestamp "$timestamp" \
        --arg session_id "$session_id" \
        --arg skill "$skill" \
        --arg check "$check" \
        --arg action "$action" \
        --arg reason "$reason" \
        --argjson rollback_performed "$rollback_performed" \
        '{type: $type, timestamp: $timestamp, session_id: $session_id, skill: $skill, check: $check, action: $action, reason: $reason, rollback_performed: $rollback_performed}')

    echo "$entry" | jq -c . >> "$log_file"
}

# Show user notification
show_notification() {
    local skill="$1"
    local check="$2"
    local reason="$3"
    local action="$4"
    local rollback_performed="$5"

    local emoji="⚠️"
    local title="Tripwire Activated"
    if [[ "$action" == "halt" ]]; then
        emoji="🛑"
        title="Tripwire HALT"
    fi

    cat <<EOF
┌────────────────────────────────────────────────────────────┐
│ $emoji  $title
├────────────────────────────────────────────────────────────┤
│ Skill: $skill
│ Failed Check: $check
│ Reason: $reason
│ Action: $action
EOF

    if [[ "$rollback_performed" == "true" ]]; then
        echo "│ Rollback: Uncommitted changes restored"
    fi

    cat <<EOF
│
│ A parallel guardrail check failed after skill started.
│ Execution has been halted to prevent potential issues.
└────────────────────────────────────────────────────────────┘
EOF
}

# =============================================================================
# Main
# =============================================================================

main() {
    local skill=""
    local check=""
    local reason=""
    local do_rollback="false"
    local session_id="${CLAUDE_SESSION_ID:-}"
    local quiet="false"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --skill)
                skill="$2"
                shift 2
                ;;
            --check)
                check="$2"
                shift 2
                ;;
            --reason)
                reason="$2"
                shift 2
                ;;
            --rollback)
                do_rollback="true"
                shift
                ;;
            --session-id)
                session_id="$2"
                shift 2
                ;;
            --quiet)
                quiet="true"
                shift
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

    if [[ -z "$check" ]]; then
        echo "Error: --check is required" >&2
        exit 1
    fi

    if [[ -z "$reason" ]]; then
        echo "Error: --reason is required" >&2
        exit 1
    fi

    # Check if tripwire is enabled
    if ! is_tripwire_enabled; then
        # Use jq for safe JSON output (M-5 fix)
        jq -n \
            --arg action "disabled" \
            --arg skill "$skill" \
            --arg check "$check" \
            --arg reason "$reason" \
            --argjson rollback_performed false \
            '{action: $action, skill: $skill, check: $check, reason: $reason, rollback_performed: $rollback_performed}'
        exit 0
    fi

    # Get tripwire action mode
    local action
    action=$(get_tripwire_action)

    # Perform rollback if requested and enabled
    local rollback_performed="false"
    if [[ "$do_rollback" == "true" && "$action" == "halt" ]]; then
        if is_rollback_enabled; then
            local rollback_result
            rollback_result=$(perform_rollback)
            if [[ "$rollback_result" == "true" ]]; then
                rollback_performed="true"
            fi
        fi
    fi

    # Log to trajectory
    log_tripwire "$skill" "$check" "$reason" "$action" "$rollback_performed" "$session_id"

    # Show notification (unless quiet)
    if [[ "$quiet" != "true" && "$action" != "log" ]]; then
        show_notification "$skill" "$check" "$reason" "$action" "$rollback_performed" >&2
    fi

    # Output JSON result using jq for safe escaping (M-5 fix)
    jq -n \
        --arg action "$action" \
        --arg skill "$skill" \
        --arg check "$check" \
        --arg reason "$reason" \
        --argjson rollback_performed "$rollback_performed" \
        '{action: $action, skill: $skill, check: $check, reason: $reason, rollback_performed: $rollback_performed}'

    # Exit with error code for halt
    if [[ "$action" == "halt" ]]; then
        exit 1
    fi
}

main "$@"
