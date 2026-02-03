#!/usr/bin/env bash
# =============================================================================
# flatline-error-handler.sh - Error categorization and retry for Flatline
# =============================================================================
# Version: 1.0.0
# Part of: Autonomous Flatline Integration v1.22.0
#
# Categorizes errors as transient or fatal, implements retry with exponential
# backoff, and handles escalation based on configuration.
#
# Usage:
#   flatline-error-handler.sh categorize <error_type>
#   flatline-error-handler.sh retry <command> [args...]
#   flatline-error-handler.sh escalate <error_json>
#
# Exit codes:
#   0 - Success
#   1 - Fatal error (no retry)
#   2 - Transient error (retried, all failed)
#   3 - Invalid arguments
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_FILE="$PROJECT_ROOT/.loa.config.yaml"
TRAJECTORY_DIR="$PROJECT_ROOT/grimoires/loa/a2a/trajectory"

# Default configuration
DEFAULT_MAX_ATTEMPTS=3
DEFAULT_BASE_DELAY_MS=1000
DEFAULT_MAX_DELAY_MS=30000

# =============================================================================
# Logging
# =============================================================================

log() {
    echo "[error-handler] $*" >&2
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

    (umask 077 && mkdir -p "$TRAJECTORY_DIR")
    local date_str
    date_str=$(date +%Y-%m-%d)
    local log_file="$TRAJECTORY_DIR/flatline-errors-$date_str.jsonl"

    touch "$log_file"
    chmod 600 "$log_file"

    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    jq -n \
        --arg type "flatline_error_handler" \
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

get_max_attempts() {
    read_config '.autonomous_mode.retry.max_attempts' "$DEFAULT_MAX_ATTEMPTS"
}

get_base_delay() {
    read_config '.autonomous_mode.retry.base_delay_ms' "$DEFAULT_BASE_DELAY_MS"
}

get_max_delay() {
    read_config '.autonomous_mode.retry.max_delay_ms' "$DEFAULT_MAX_DELAY_MS"
}

get_on_error() {
    read_config '.autonomous_mode.on_error' 'halt'
}

# =============================================================================
# Error Categories
# =============================================================================

# Transient errors: can be retried
TRANSIENT_ERRORS=(
    "rate_limit"
    "timeout"
    "network"
    "overloaded"
    "service_unavailable"
    "connection_reset"
    "connection_refused"
    "temporary_failure"
    "throttled"
    "capacity"
)

# Fatal errors: no retry
FATAL_ERRORS=(
    "auth"
    "authentication"
    "authorization"
    "invalid_request"
    "invalid_response"
    "not_found"
    "budget_exceeded"
    "schema_error"
    "permission_denied"
    "malformed"
    "invalid_api_key"
    "model_not_available"
    "content_filter"
)

# Check if error is transient
is_transient() {
    local error_type="$1"
    error_type=$(echo "$error_type" | tr '[:upper:]' '[:lower:]')

    for pattern in "${TRANSIENT_ERRORS[@]}"; do
        if [[ "$error_type" == *"$pattern"* ]]; then
            return 0
        fi
    done

    return 1
}

# Check if error is fatal
is_fatal() {
    local error_type="$1"
    error_type=$(echo "$error_type" | tr '[:upper:]' '[:lower:]')

    for pattern in "${FATAL_ERRORS[@]}"; do
        if [[ "$error_type" == *"$pattern"* ]]; then
            return 0
        fi
    done

    return 1
}

# Categorize an error
categorize_error() {
    local error_type="$1"

    if is_fatal "$error_type"; then
        echo "fatal"
        return 1
    elif is_transient "$error_type"; then
        echo "transient"
        return 0
    else
        # Unknown errors default to transient (be optimistic)
        echo "unknown"
        return 0
    fi
}

# =============================================================================
# Retry Logic
# =============================================================================

# Calculate delay with exponential backoff and jitter
calculate_delay() {
    local attempt="$1"
    local base_delay
    base_delay=$(get_base_delay)
    local max_delay
    max_delay=$(get_max_delay)

    # Exponential backoff: base * 2^attempt
    local delay=$((base_delay * (1 << attempt)))

    # Cap at max delay
    if [[ $delay -gt $max_delay ]]; then
        delay=$max_delay
    fi

    # Add jitter (0-25% of delay)
    local jitter=$((RANDOM % (delay / 4 + 1)))
    delay=$((delay + jitter))

    echo "$delay"
}

# Retry a command with exponential backoff
retry_command() {
    local max_attempts
    max_attempts=$(get_max_attempts)

    local attempt=0
    local last_error=""
    local last_output=""

    while [[ $attempt -lt $max_attempts ]]; do
        ((attempt++))
        log "Attempt $attempt of $max_attempts: $*"

        # Execute command
        local exit_code=0
        last_output=$("$@" 2>&1) || exit_code=$?

        if [[ $exit_code -eq 0 ]]; then
            log "Command succeeded on attempt $attempt"
            echo "$last_output"
            return 0
        fi

        # Parse error from output
        last_error=$(echo "$last_output" | grep -iE "error|fail|exception" | head -1)
        if [[ -z "$last_error" ]]; then
            last_error="Exit code: $exit_code"
        fi

        # Categorize error
        local category
        category=$(categorize_error "$last_error") || true

        log_trajectory "retry_attempt" "{\"attempt\": $attempt, \"error\": \"$last_error\", \"category\": \"$category\"}"

        if is_fatal "$last_error"; then
            error "Fatal error, not retrying: $last_error"
            echo "$last_output"
            return 1
        fi

        if [[ $attempt -lt $max_attempts ]]; then
            local delay
            delay=$(calculate_delay "$attempt")
            log "Transient error, retrying in ${delay}ms: $last_error"
            sleep "$(echo "scale=3; $delay / 1000" | bc)"
        fi
    done

    error "All $max_attempts attempts failed"
    error "Last error: $last_error"
    echo "$last_output"

    log_trajectory "retry_exhausted" "{\"attempts\": $max_attempts, \"last_error\": \"$last_error\"}"

    return 2
}

# =============================================================================
# Escalation
# =============================================================================

escalate_error() {
    local error_json="$1"

    local on_error
    on_error=$(get_on_error)

    log_trajectory "escalation" "$error_json"

    case "$on_error" in
        halt)
            error "Escalating error with HALT"
            echo "$error_json" | jq '. + {action: "halt"}'
            return 1
            ;;
        continue)
            warn "Escalating error with CONTINUE"
            echo "$error_json" | jq '. + {action: "continue"}'
            return 0
            ;;
        *)
            error "Unknown on_error action: $on_error"
            return 1
            ;;
    esac
}

# =============================================================================
# Error Parsing
# =============================================================================

# Parse error from various response formats
parse_error() {
    local response="$1"

    # Try JSON error field
    local error_msg
    error_msg=$(echo "$response" | jq -r '.error // .error.message // .message // ""' 2>/dev/null)

    if [[ -n "$error_msg" && "$error_msg" != "null" ]]; then
        echo "$error_msg"
        return 0
    fi

    # Try status code
    local status
    status=$(echo "$response" | jq -r '.status // .status_code // ""' 2>/dev/null)

    case "$status" in
        401|403) echo "authentication" ;;
        404) echo "not_found" ;;
        429) echo "rate_limit" ;;
        500) echo "service_unavailable" ;;
        502|503|504) echo "temporary_failure" ;;
        *) echo "unknown" ;;
    esac
}

# =============================================================================
# Main
# =============================================================================

usage() {
    cat <<EOF
Usage: flatline-error-handler.sh <command> [args...]

Commands:
  categorize <error_type>
      Categorize error as transient or fatal

  is-transient <error_type>
      Check if error is transient (exit 0 = yes, 1 = no)

  is-fatal <error_type>
      Check if error is fatal (exit 0 = yes, 1 = no)

  retry <command> [args...]
      Execute command with retry on transient errors

  escalate <error_json>
      Escalate error based on on_error config

  parse <response>
      Parse error from response JSON

Exit codes:
  0 - Success
  1 - Fatal error
  2 - Transient error (all retries exhausted)
  3 - Invalid arguments

Examples:
  flatline-error-handler.sh categorize "rate_limit"
  flatline-error-handler.sh retry curl -s https://api.example.com/data
  flatline-error-handler.sh escalate '{"error": "timeout", "context": "phase1"}'
EOF
}

main() {
    if [[ $# -lt 1 ]]; then
        usage
        exit 3
    fi

    local command="$1"
    shift

    case "$command" in
        categorize)
            if [[ $# -lt 1 ]]; then
                error "Usage: categorize <error_type>"
                exit 3
            fi
            categorize_error "$1"
            ;;

        is-transient)
            if [[ $# -lt 1 ]]; then
                error "Usage: is-transient <error_type>"
                exit 3
            fi
            if is_transient "$1"; then
                echo "true"
                exit 0
            else
                echo "false"
                exit 1
            fi
            ;;

        is-fatal)
            if [[ $# -lt 1 ]]; then
                error "Usage: is-fatal <error_type>"
                exit 3
            fi
            if is_fatal "$1"; then
                echo "true"
                exit 0
            else
                echo "false"
                exit 1
            fi
            ;;

        retry)
            if [[ $# -lt 1 ]]; then
                error "Usage: retry <command> [args...]"
                exit 3
            fi
            retry_command "$@"
            ;;

        escalate)
            if [[ $# -lt 1 ]]; then
                error "Usage: escalate <error_json>"
                exit 3
            fi
            escalate_error "$1"
            ;;

        parse)
            if [[ $# -lt 1 ]]; then
                error "Usage: parse <response>"
                exit 3
            fi
            parse_error "$1"
            ;;

        -h|--help|help)
            usage
            exit 0
            ;;

        *)
            error "Unknown command: $command"
            usage
            exit 3
            ;;
    esac
}

main "$@"
