#!/usr/bin/env bash
# =============================================================================
# log-handoff.sh - Log handoff events between agents to trajectory
# =============================================================================
# Version: 1.0.0
# Part of: Input Guardrails & Tool Risk Enforcement v1.20.0
#
# Usage:
#   log-handoff.sh --from implementing-tasks --to reviewing-code --artifact reviewer.md
#   log-handoff.sh --from reviewing-code --to auditing-security --type file_based
#
# Output: JSON confirmation of logged handoff
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

Log handoff events between agents/skills to trajectory.

Required Options:
  --from AGENT      Source agent/skill identifier
  --to AGENT        Target agent/skill identifier

Optional:
  --type TYPE       Handoff type: file_based (default), memory, direct
  --artifact PATH   Artifact file path (can be repeated)
  --context KEY     Context key preserved (can be repeated)
  --session-id ID   Session ID for trajectory correlation
  --quiet           Suppress output
  -h, --help        Show this help message

Handoff Types:
  file_based  - Handoff via a2a files (default, most common)
  memory      - Handoff via in-memory state (future)
  direct      - Direct function call handoff (future)

Output (JSON):
  {
    "status": "logged",
    "from_agent": "implementing-tasks",
    "to_agent": "reviewing-code",
    "handoff_type": "file_based",
    "artifacts": [...],
    "context_preserved": [...]
  }

Examples:
  $SCRIPT_NAME --from implementing-tasks --to reviewing-code --artifact reviewer.md
  $SCRIPT_NAME --from reviewing-code --to auditing-security --context sprint_id --context task_list
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

# Check if handoff logging is enabled
is_logging_enabled() {
    local enabled
    enabled=$(get_config ".guardrails.logging.handoffs" "true")
    [[ "$enabled" == "true" ]]
}

# Get file size in bytes
get_file_size() {
    local path="$1"
    local full_path="$PROJECT_ROOT/$path"

    if [[ -f "$full_path" ]]; then
        stat -f%z "$full_path" 2>/dev/null || stat -c%s "$full_path" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

# Get file checksum
get_file_checksum() {
    local path="$1"
    local full_path="$PROJECT_ROOT/$path"

    if [[ -f "$full_path" ]]; then
        sha256sum "$full_path" 2>/dev/null | cut -d' ' -f1 || echo ""
    else
        echo ""
    fi
}

# Log handoff event to trajectory
log_handoff() {
    local from_agent="$1"
    local to_agent="$2"
    local handoff_type="$3"
    local artifacts_json="$4"
    local context_json="$5"
    local session_id="$6"

    # Use guardrail-logger.sh
    "$GUARDRAIL_LOGGER" \
        --type handoff \
        --skill "$from_agent" \
        --action PROCEED \
        --from "$from_agent" \
        --to "$to_agent" \
        --handoff-type "$handoff_type" \
        --artifacts "$artifacts_json" \
        --context "$context_json" \
        --session-id "$session_id" \
        --quiet
}

# =============================================================================
# Main
# =============================================================================

main() {
    local from_agent=""
    local to_agent=""
    local handoff_type="file_based"
    local artifacts=()
    local context_keys=()
    local session_id="${CLAUDE_SESSION_ID:-}"
    local quiet="false"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --from)
                from_agent="$2"
                shift 2
                ;;
            --to)
                to_agent="$2"
                shift 2
                ;;
            --type)
                handoff_type="$2"
                shift 2
                ;;
            --artifact)
                artifacts+=("$2")
                shift 2
                ;;
            --context)
                context_keys+=("$2")
                shift 2
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
    if [[ -z "$from_agent" ]]; then
        echo "Error: --from is required" >&2
        exit 1
    fi

    if [[ -z "$to_agent" ]]; then
        echo "Error: --to is required" >&2
        exit 1
    fi

    # Check if logging is enabled
    if ! is_logging_enabled; then
        if [[ "$quiet" != "true" ]]; then
            echo '{"status": "skipped", "reason": "handoff logging disabled"}'
        fi
        exit 0
    fi

    # Build artifacts JSON array
    local artifacts_json="["
    local first=true
    for artifact in "${artifacts[@]}"; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            artifacts_json+=","
        fi

        local size
        size=$(get_file_size "$artifact")
        local checksum
        checksum=$(get_file_checksum "$artifact")

        artifacts_json+="{\"path\":\"$artifact\",\"size_bytes\":$size"
        if [[ -n "$checksum" ]]; then
            artifacts_json+=",\"checksum\":\"$checksum\""
        fi
        artifacts_json+="}"
    done
    artifacts_json+="]"

    # Build context JSON array
    local context_json="["
    first=true
    for key in "${context_keys[@]}"; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            context_json+=","
        fi
        context_json+="\"$key\""
    done
    context_json+="]"

    # Log the handoff
    log_handoff "$from_agent" "$to_agent" "$handoff_type" "$artifacts_json" "$context_json" "$session_id"

    # Output result
    if [[ "$quiet" != "true" ]]; then
        cat <<EOF
{
  "status": "logged",
  "from_agent": "$from_agent",
  "to_agent": "$to_agent",
  "handoff_type": "$handoff_type",
  "artifacts": $artifacts_json,
  "context_preserved": $context_json
}
EOF
    fi
}

main "$@"
