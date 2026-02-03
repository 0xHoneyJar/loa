#!/usr/bin/env bash
# =============================================================================
# validation-history.sh - Layer 2 Circular Prevention via History Tracking
# =============================================================================
# Part of Flatline-Enhanced Compound Learning v1.23.0 (Sprint 2)
# Addresses: T2.4 - Implement validation history management (SDD 7.1)
#
# Provides:
# - check_validation_history(): Check if learning was already validated
# - record_validation(): Record a validation in history
# - clear_validation_history(): Clear history for new cycle
# - check_rate_limit(): Layer 3 rate limiting
#
# Usage:
#   source lib/validation-history.sh
#   if check_validation_history "learn-001"; then
#     echo "Already validated"
#   fi
# =============================================================================

set -euo pipefail

# Configuration
SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/../../.." && pwd)}"
COMPOUND_DIR="${PROJECT_ROOT}/grimoires/loa/a2a/compound"
HISTORY_FILE="${COMPOUND_DIR}/.validation-history"
TIMESTAMPS_FILE="${COMPOUND_DIR}/.validation-timestamps"
RATE_LIMIT_SECONDS="${LOA_VALIDATION_RATE_LIMIT:-30}"

# Logging
log_debug() { [[ "${LOA_DEBUG:-false}" == "true" ]] && echo "[DEBUG] $*" >&2 || true; }

# Initialize validation history storage
init_validation_storage() {
    mkdir -p "$COMPOUND_DIR"

    if [[ ! -f "$HISTORY_FILE" ]]; then
        echo '{"validated_learnings":[],"cycle_id":"","created_at":""}' > "$HISTORY_FILE"
    fi

    if [[ ! -f "$TIMESTAMPS_FILE" ]]; then
        echo '{}' > "$TIMESTAMPS_FILE"
    fi
}

# Check if a learning was already validated in this cycle (Layer 2)
# Returns: 0 if already validated, 1 if not validated
check_validation_history() {
    local learning_id="$1"

    init_validation_storage

    # Check if learning ID is in history
    local found
    found=$(jq -r --arg id "$learning_id" '
        .validated_learnings | any(. == $id)
    ' "$HISTORY_FILE")

    if [[ "$found" == "true" ]]; then
        log_debug "Learning $learning_id found in validation history"
        return 0
    fi

    log_debug "Learning $learning_id not in validation history"
    return 1
}

# Record a validation in history (with flock for concurrency safety - HIGH-003)
record_validation() {
    local learning_id="$1"
    local result="${2:-}"  # Optional: approve, reject, disputed
    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    init_validation_storage

    # Use flock for atomic writes to prevent race conditions (Security: HIGH-003)
    local lock_file="${HISTORY_FILE}.lock"

    (
        # Acquire exclusive lock with 10-second timeout
        if ! flock -x -w 10 200 2>/dev/null; then
            log_debug "Warning: Could not acquire lock for $HISTORY_FILE, proceeding anyway"
        fi

        # Add to history with atomic write
        local temp_file
        temp_file=$(mktemp)

        jq --arg id "$learning_id" --arg ts "$now" --arg result "$result" '
            .validated_learnings += [$id] |
            .validated_learnings |= unique |
            .last_validation = $ts |
            if $result != "" then .last_result = $result else . end
        ' "$HISTORY_FILE" > "$temp_file" && mv "$temp_file" "$HISTORY_FILE"

        # Also record timestamp for rate limiting
        jq --arg id "$learning_id" --argjson ts "$(date +%s)" '
            .[$id] = $ts
        ' "$TIMESTAMPS_FILE" > "$temp_file" && mv "$temp_file" "$TIMESTAMPS_FILE"

    ) 200>"$lock_file"

    log_debug "Recorded validation for $learning_id"
}

# Clear validation history (for new compound cycle)
clear_validation_history() {
    local cycle_id="${1:-}"
    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    init_validation_storage

    # Use flock for atomic writes (Security: HIGH-003)
    local lock_file="${HISTORY_FILE}.lock"

    (
        # Acquire exclusive lock with 10-second timeout
        if ! flock -x -w 10 200 2>/dev/null; then
            log_debug "Warning: Could not acquire lock for $HISTORY_FILE, proceeding anyway"
        fi

        # Archive old history if it has entries
        local old_count
        old_count=$(jq '.validated_learnings | length' "$HISTORY_FILE")

        if [[ "$old_count" -gt 0 ]]; then
            local archive_file="${HISTORY_FILE}.$(date +%Y%m%d%H%M%S)"
            cp "$HISTORY_FILE" "$archive_file"
            log_debug "Archived $old_count validation history entries to $archive_file"
        fi

        # Reset history
        jq -n --arg cycle "$cycle_id" --arg ts "$now" '{
            validated_learnings: [],
            cycle_id: $cycle,
            created_at: $ts
        }' > "$HISTORY_FILE"

        # Clear timestamps
        echo '{}' > "$TIMESTAMPS_FILE"

    ) 200>"$lock_file"

    log_debug "Cleared validation history for cycle: $cycle_id"
}

# Check rate limit (Layer 3)
# Returns: 0 if rate limited, 1 if OK to proceed
check_rate_limit() {
    local learning_id="$1"

    init_validation_storage

    local now
    now=$(date +%s)

    # Get last validation timestamp for this learning
    local last_ts
    last_ts=$(jq -r --arg id "$learning_id" '.[$id] // 0' "$TIMESTAMPS_FILE")

    if [[ "$last_ts" -gt 0 ]]; then
        local elapsed=$((now - last_ts))

        if [[ "$elapsed" -lt "$RATE_LIMIT_SECONDS" ]]; then
            local remaining=$((RATE_LIMIT_SECONDS - elapsed))
            log_debug "Rate limited: $learning_id (${remaining}s remaining)"
            return 0  # Rate limited
        fi
    fi

    return 1  # OK to proceed
}

# Get validation count for current cycle
get_validation_count() {
    init_validation_storage
    jq '.validated_learnings | length' "$HISTORY_FILE"
}

# Get last validation result
get_last_result() {
    local learning_id="$1"

    init_validation_storage

    # This would need a more complex data structure to track per-learning results
    # For now, just return the global last result
    jq -r '.last_result // ""' "$HISTORY_FILE"
}

# CLI interface
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        --help|-h)
            echo "Usage: validation-history.sh <command> [args]"
            echo ""
            echo "Commands:"
            echo "  check <learning_id>     Check if learning was validated"
            echo "  record <learning_id>    Record a validation"
            echo "  clear [cycle_id]        Clear history for new cycle"
            echo "  count                   Get validation count"
            echo "  rate-check <id>         Check rate limit status"
            ;;
        check)
            if check_validation_history "${2:-}"; then
                echo "true"
                exit 0
            else
                echo "false"
                exit 1
            fi
            ;;
        record)
            record_validation "${2:-}" "${3:-}"
            echo "recorded"
            ;;
        clear)
            clear_validation_history "${2:-}"
            echo "cleared"
            ;;
        count)
            get_validation_count
            ;;
        rate-check)
            if check_rate_limit "${2:-}"; then
                echo "rate_limited"
                exit 0
            else
                echo "ok"
                exit 1
            fi
            ;;
        *)
            echo "Unknown command: ${1:-}" >&2
            echo "Use --help for usage" >&2
            exit 1
            ;;
    esac
fi
