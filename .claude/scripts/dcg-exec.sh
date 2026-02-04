#!/usr/bin/env bash
# dcg-exec.sh - Execute commands through Destructive Command Guard
#
# Entry point for all command execution requiring DCG validation.
# Validates commands against security packs before execution.
#
# Usage:
#   dcg-exec.sh <command>
#   dcg-exec.sh "rm -rf /tmp/cache && npm test"
#
# Environment:
#   DCG_CONTEXT    - Skill context (e.g., "implementing-tasks")
#   DCG_SKIP       - Set to "1" to bypass guard (for internal scripts)
#   PROJECT_ROOT   - Workspace root for path resolution
#
# Exit Codes:
#   0 - Command executed successfully
#   1 - Command blocked by DCG
#   2 - Configuration error
#   * - Command exit code (pass-through)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source bootstrap for PROJECT_ROOT and config
if [[ -f "$SCRIPT_DIR/bootstrap.sh" ]]; then
    source "$SCRIPT_DIR/bootstrap.sh"
fi

# =============================================================================
# Configuration
# =============================================================================

_dcg_get_config() {
    local key="$1"
    local default="$2"

    # Try yq first
    if command -v yq &>/dev/null && [[ -f "${PROJECT_ROOT:-.}/.loa.config.yaml" ]]; then
        local value
        value=$(yq e "$key // \"$default\"" "${PROJECT_ROOT:-.}/.loa.config.yaml" 2>/dev/null) || true
        if [[ -n "$value" && "$value" != "null" ]]; then
            echo "$value"
            return
        fi
    fi

    echo "$default"
}

# =============================================================================
# Main Entry Point
# =============================================================================

main() {
    local command="$*"

    # Validate input
    if [[ -z "$command" ]]; then
        echo "Usage: dcg-exec.sh <command>" >&2
        exit 2
    fi

    # Fast path: skip if bypass flag set
    if [[ "${DCG_SKIP:-}" == "1" ]]; then
        exec bash -c "$command"
    fi

    # Fast path: skip if DCG disabled
    local enabled
    enabled=$(_dcg_get_config '.destructive_command_guard.enabled' 'false')
    if [[ "$enabled" != "true" ]]; then
        exec bash -c "$command"
    fi

    # Source the guard engine
    if [[ ! -f "$SCRIPT_DIR/destructive-command-guard.sh" ]]; then
        echo "WARNING: DCG engine not found, executing directly" >&2
        exec bash -c "$command"
    fi

    source "$SCRIPT_DIR/destructive-command-guard.sh"

    # Validate command
    local result
    result=$(dcg_validate "$command" 2>/dev/null) || {
        # Validation error: fail-open
        echo "WARNING: DCG validation error, executing directly" >&2
        exec bash -c "$command"
    }

    # Parse result
    local action
    action=$(echo "$result" | jq -r '.action // "ALLOW"' 2>/dev/null) || action="ALLOW"

    case "$action" in
        ALLOW)
            exec bash -c "$command"
            ;;
        WARN)
            local message
            message=$(echo "$result" | jq -r '.message // "Warning"' 2>/dev/null)
            echo "⚠️  DCG Warning: $message" >&2
            exec bash -c "$command"
            ;;
        BLOCK)
            local message pattern severity
            message=$(echo "$result" | jq -r '.message // "Command blocked"' 2>/dev/null)
            pattern=$(echo "$result" | jq -r '.pattern // "unknown"' 2>/dev/null)
            severity=$(echo "$result" | jq -r '.severity // "high"' 2>/dev/null)

            echo "" >&2
            echo "════════════════════════════════════════════════════════════════" >&2
            echo " DESTRUCTIVE COMMAND GUARD - BLOCKED" >&2
            echo "════════════════════════════════════════════════════════════════" >&2
            echo "" >&2
            echo " Command: $command" >&2
            echo "" >&2
            echo " Pattern: $pattern" >&2
            echo " Severity: ${severity^^}" >&2
            echo "" >&2
            echo " Reason: $message" >&2
            echo "" >&2
            echo "════════════════════════════════════════════════════════════════" >&2
            echo "" >&2

            # Audit log
            _dcg_audit_log "BLOCK" "$command" "$pattern"

            exit 1
            ;;
        *)
            # Unknown action: allow
            exec bash -c "$command"
            ;;
    esac
}

# =============================================================================
# Audit Logging
# =============================================================================

_dcg_audit_log() {
    local action="$1"
    local command="$2"
    local pattern="${3:-}"

    local audit_enabled
    audit_enabled=$(_dcg_get_config '.destructive_command_guard.audit.enabled' 'true')

    if [[ "$audit_enabled" != "true" ]]; then
        return
    fi

    local trajectory_dir="${PROJECT_ROOT:-$(pwd)}/grimoires/loa/a2a/trajectory"
    mkdir -p "$trajectory_dir" 2>/dev/null || return

    local log_file="$trajectory_dir/dcg-$(date +%Y%m%d).jsonl"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local context="${DCG_CONTEXT:-unknown}"

    # Escape command for JSON
    local escaped_command
    escaped_command=$(echo "$command" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g; s/\n/\\n/g')

    echo "{\"timestamp\":\"$timestamp\",\"action\":\"$action\",\"pattern\":\"$pattern\",\"command\":\"$escaped_command\",\"context\":\"$context\"}" >> "$log_file" 2>/dev/null || true
}

# Run main
main "$@"
