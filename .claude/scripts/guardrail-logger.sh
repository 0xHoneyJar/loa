#!/usr/bin/env bash
# =============================================================================
# guardrail-logger.sh - Trajectory logging for guardrail events
# =============================================================================
# Version: 1.0.0
# Part of: Input Guardrails & Tool Risk Enforcement v1.20.0
#
# Usage:
#   guardrail-logger.sh --type input_guardrail --skill implementing-tasks --action PROCEED --checks '[]'
#   guardrail-logger.sh --type danger_level --skill deploying-infrastructure --action BLOCK --level high
#   guardrail-logger.sh --type handoff --from implementing-tasks --to reviewing-code
#
# Logs events to: grimoires/loa/a2a/trajectory/guardrails-{date}.jsonl
# =============================================================================

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_NAME="$(basename "$0")"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly TRAJECTORY_DIR="$PROJECT_ROOT/grimoires/loa/a2a/trajectory"
readonly CONFIG_FILE="$PROJECT_ROOT/.loa.config.yaml"

# =============================================================================
# Functions
# =============================================================================

show_help() {
    cat <<EOF
Usage: $SCRIPT_NAME [OPTIONS]

Log guardrail events to trajectory.

Required Options:
  --type TYPE       Event type: input_guardrail, danger_level, or handoff
  --skill NAME      Skill identifier

Common Options:
  --action ACTION   Action taken: PROCEED, WARN, or BLOCK
  --session-id ID   Session ID for correlation
  --latency-ms N    Latency in milliseconds

input_guardrail Options:
  --checks JSON     JSON array of check results
  --input-size N    Input size in bytes
  --redacted TEXT   Redacted input text

danger_level Options:
  --level LEVEL     Danger level: safe, moderate, high, critical
  --mode MODE       Execution mode: interactive or autonomous
  --override        Flag if --allow-high was used
  --reason TEXT     Reason for the action

handoff Options:
  --from AGENT      Source agent/skill
  --to AGENT        Target agent/skill
  --handoff-type T  Handoff type: file_based, memory, direct
  --artifacts JSON  JSON array of artifact objects
  --context JSON    JSON array of preserved context fields

Output Control:
  --quiet           Suppress output (just log)
  --dry-run         Show what would be logged without writing
  -h, --help        Show this help message

Examples:
  $SCRIPT_NAME --type input_guardrail --skill implementing-tasks --action PROCEED \\
    --checks '[{"name":"pii_filter","status":"PASS","redactions":0}]'

  $SCRIPT_NAME --type danger_level --skill deploying-infrastructure --action BLOCK \\
    --level high --mode autonomous --reason "high-risk blocked"

  $SCRIPT_NAME --type handoff --skill implementing-tasks --action PROCEED \\
    --from implementing-tasks --to reviewing-code --handoff-type file_based
EOF
}

# Check if logging is enabled in config
is_logging_enabled() {
    if [[ -f "$CONFIG_FILE" ]]; then
        local enabled
        enabled=$(yq -r '.guardrails.logging.enabled // true' "$CONFIG_FILE" 2>/dev/null || echo "true")
        [[ "$enabled" == "true" ]]
    else
        return 0  # Default to enabled
    fi
}

# Check if specific event type logging is enabled
is_event_type_enabled() {
    local event_type="$1"

    if [[ -f "$CONFIG_FILE" ]]; then
        local key=""
        case "$event_type" in
            input_guardrail) key=".guardrails.logging.input_guardrails" ;;
            danger_level) key=".guardrails.logging.danger_level_decisions" ;;
            handoff) key=".guardrails.logging.handoffs" ;;
        esac

        if [[ -n "$key" ]]; then
            local enabled
            enabled=$(yq -r "$key // true" "$CONFIG_FILE" 2>/dev/null || echo "true")
            [[ "$enabled" == "true" ]]
        else
            return 0
        fi
    else
        return 0  # Default to enabled
    fi
}

# Build input_guardrail event JSON
build_input_guardrail_event() {
    local timestamp="$1"
    local session_id="$2"
    local skill="$3"
    local action="$4"
    local checks="$5"
    local latency_ms="$6"
    local input_size="${7:-0}"
    local redacted_input="$8"

    local redacted_json="null"
    if [[ -n "$redacted_input" ]]; then
        redacted_json=$(echo "$redacted_input" | jq -Rs .)
    fi

    cat <<EOF
{
  "type": "input_guardrail",
  "timestamp": "$timestamp",
  "session_id": "$session_id",
  "skill": "$skill",
  "action": "$action",
  "latency_ms": ${latency_ms:-0},
  "checks": $checks,
  "input_size_bytes": $input_size,
  "redacted_input": $redacted_json
}
EOF
}

# Build danger_level event JSON (M-5 fix: use jq for safe escaping)
build_danger_level_event() {
    local timestamp="$1"
    local session_id="$2"
    local skill="$3"
    local action="$4"
    local level="$5"
    local mode="$6"
    local override_used="$7"
    local reason="$8"

    jq -n \
        --arg type "danger_level" \
        --arg timestamp "$timestamp" \
        --arg session_id "$session_id" \
        --arg skill "$skill" \
        --arg action "$action" \
        --arg level "$level" \
        --arg mode "$mode" \
        --argjson override_used "$override_used" \
        --arg reason "$reason" \
        '{type: $type, timestamp: $timestamp, session_id: $session_id, skill: $skill, action: $action, level: $level, mode: $mode, override_used: $override_used, reason: $reason}'
}

# Build handoff event JSON (M-5 fix: use jq for safe escaping)
build_handoff_event() {
    local timestamp="$1"
    local session_id="$2"
    local skill="$3"
    local action="$4"
    local from_agent="$5"
    local to_agent="$6"
    local handoff_type="$7"
    local artifacts="$8"
    local context_preserved="$9"

    jq -n \
        --arg type "handoff" \
        --arg timestamp "$timestamp" \
        --arg session_id "$session_id" \
        --arg skill "$skill" \
        --arg action "$action" \
        --arg from_agent "$from_agent" \
        --arg to_agent "$to_agent" \
        --arg handoff_type "$handoff_type" \
        --argjson artifacts "$artifacts" \
        --argjson context_preserved "$context_preserved" \
        '{type: $type, timestamp: $timestamp, session_id: $session_id, skill: $skill, action: $action, from_agent: $from_agent, to_agent: $to_agent, handoff_type: $handoff_type, artifacts: $artifacts, context_preserved: $context_preserved}'
}

# Write event to trajectory log
write_to_trajectory() {
    local event="$1"

    # Ensure trajectory directory exists
    mkdir -p "$TRAJECTORY_DIR"

    local date_str
    date_str=$(date +%Y-%m-%d)
    local log_file="$TRAJECTORY_DIR/guardrails-$date_str.jsonl"

    # Append compact JSON
    echo "$event" | jq -c . >> "$log_file"

    echo "$log_file"
}

# =============================================================================
# Main
# =============================================================================

main() {
    local event_type=""
    local skill=""
    local action="PROCEED"
    local session_id="${CLAUDE_SESSION_ID:-}"
    local latency_ms="0"

    # input_guardrail specific
    local checks="[]"
    local input_size="0"
    local redacted_input=""

    # danger_level specific
    local level=""
    local mode=""
    local override_used="false"
    local reason=""

    # handoff specific
    local from_agent=""
    local to_agent=""
    local handoff_type="file_based"
    local artifacts="[]"
    local context_preserved="[]"

    # Output control
    local quiet="false"
    local dry_run="false"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --type)
                event_type="$2"
                shift 2
                ;;
            --skill)
                skill="$2"
                shift 2
                ;;
            --action)
                action="$2"
                shift 2
                ;;
            --session-id)
                session_id="$2"
                shift 2
                ;;
            --latency-ms)
                latency_ms="$2"
                shift 2
                ;;
            --checks)
                checks="$2"
                shift 2
                ;;
            --input-size)
                input_size="$2"
                shift 2
                ;;
            --redacted)
                redacted_input="$2"
                shift 2
                ;;
            --level)
                level="$2"
                shift 2
                ;;
            --mode)
                mode="$2"
                shift 2
                ;;
            --override)
                override_used="true"
                shift
                ;;
            --reason)
                reason="$2"
                shift 2
                ;;
            --from)
                from_agent="$2"
                shift 2
                ;;
            --to)
                to_agent="$2"
                shift 2
                ;;
            --handoff-type)
                handoff_type="$2"
                shift 2
                ;;
            --artifacts)
                artifacts="$2"
                shift 2
                ;;
            --context)
                context_preserved="$2"
                shift 2
                ;;
            --quiet)
                quiet="true"
                shift
                ;;
            --dry-run)
                dry_run="true"
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
    if [[ -z "$event_type" ]]; then
        echo "Error: --type is required" >&2
        exit 1
    fi

    if [[ -z "$skill" ]]; then
        echo "Error: --skill is required" >&2
        exit 1
    fi

    # Validate event type
    if [[ "$event_type" != "input_guardrail" && "$event_type" != "danger_level" && "$event_type" != "handoff" ]]; then
        echo "Error: --type must be input_guardrail, danger_level, or handoff" >&2
        exit 1
    fi

    # Check if logging is enabled
    if ! is_logging_enabled || ! is_event_type_enabled "$event_type"; then
        if [[ "$quiet" != "true" ]]; then
            echo '{"status": "skipped", "reason": "logging disabled in config"}'
        fi
        exit 0
    fi

    # Get timestamp
    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Build event JSON based on type
    local event=""
    case "$event_type" in
        input_guardrail)
            event=$(build_input_guardrail_event "$timestamp" "$session_id" "$skill" "$action" "$checks" "$latency_ms" "$input_size" "$redacted_input")
            ;;
        danger_level)
            if [[ -z "$level" || -z "$mode" ]]; then
                echo "Error: --level and --mode required for danger_level events" >&2
                exit 1
            fi
            event=$(build_danger_level_event "$timestamp" "$session_id" "$skill" "$action" "$level" "$mode" "$override_used" "$reason")
            ;;
        handoff)
            if [[ -z "$from_agent" || -z "$to_agent" ]]; then
                echo "Error: --from and --to required for handoff events" >&2
                exit 1
            fi
            event=$(build_handoff_event "$timestamp" "$session_id" "$skill" "$action" "$from_agent" "$to_agent" "$handoff_type" "$artifacts" "$context_preserved")
            ;;
    esac

    # Output or write
    if [[ "$dry_run" == "true" ]]; then
        echo "$event" | jq .
    else
        local log_file
        log_file=$(write_to_trajectory "$event")

        if [[ "$quiet" != "true" ]]; then
            cat <<EOF
{
  "status": "logged",
  "file": "$log_file",
  "event": $(echo "$event" | jq -c .)
}
EOF
        fi
    fi
}

main "$@"
