#!/usr/bin/env bash
# api-resilience.sh - API call utilities with retry, backoff, and circuit breaker
# Part of Flatline-Enhanced Compound Learning (Sprint 1)
# Addresses: IMP-001, SKP-001, SKP-004, SKP-005

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration (can be overridden via environment or .loa.config.yaml)
API_MAX_RETRIES="${LOA_API_MAX_RETRIES:-3}"
API_INITIAL_BACKOFF_MS="${LOA_API_INITIAL_BACKOFF_MS:-1000}"
API_MAX_BACKOFF_MS="${LOA_API_MAX_BACKOFF_MS:-30000}"
API_TIMEOUT_SECONDS="${LOA_API_TIMEOUT_SECONDS:-60}"
CIRCUIT_FAILURE_THRESHOLD="${LOA_CIRCUIT_FAILURE_THRESHOLD:-5}"
CIRCUIT_RESET_TIMEOUT_SECONDS="${LOA_CIRCUIT_RESET_TIMEOUT_SECONDS:-300}"

# Budget configuration
DAILY_BUDGET_CENTS="${LOA_DAILY_BUDGET_CENTS:-500}"
BUDGET_WARN_PERCENT="${LOA_BUDGET_WARN_PERCENT:-80}"

# State directories
CIRCUIT_STATE_DIR="${LOA_CIRCUIT_STATE_DIR:-grimoires/loa/a2a/compound/.circuit-state}"
BUDGET_STATE_FILE="${LOA_BUDGET_STATE_FILE:-grimoires/loa/a2a/compound/.budget-state.json}"
DEAD_LETTER_FILE="${LOA_DEAD_LETTER_FILE:-grimoires/loa/a2a/compound/dead-letter.jsonl}"

# Source common utilities if available
if [[ -f "${SCRIPT_DIR}/common.sh" ]]; then
    source "${SCRIPT_DIR}/common.sh"
fi

# Logging functions
log_error() { echo "[ERROR] $(date -Iseconds) $*" >&2; }
log_warning() { echo "[WARN] $(date -Iseconds) $*" >&2; }
log_info() { echo "[INFO] $(date -Iseconds) $*" >&2; }
log_debug() { [[ "${LOA_DEBUG:-false}" == "true" ]] && echo "[DEBUG] $(date -Iseconds) $*" >&2 || true; }

# Initialize state directories
init_state_dirs() {
    mkdir -p "$CIRCUIT_STATE_DIR"
    mkdir -p "$(dirname "$BUDGET_STATE_FILE")"
    mkdir -p "$(dirname "$DEAD_LETTER_FILE")"
}

# Normalize endpoint key for circuit breaker state file
normalize_endpoint_key() {
    local url="$1"
    # Extract host + first path segment
    echo "$url" | sed -E 's|https?://([^/]+)/([^/]+).*|\1_\2|' | tr '.' '_' | tr '/' '_'
}

# Get circuit breaker state
# Returns: CLOSED, OPEN, or HALF_OPEN
get_circuit_state() {
    local endpoint_key="$1"
    local state_file="${CIRCUIT_STATE_DIR}/${endpoint_key}.json"

    if [[ ! -f "$state_file" ]]; then
        echo "CLOSED"
        return 0
    fi

    local state failures last_failure now elapsed
    state=$(jq -r '.state // "CLOSED"' "$state_file")
    failures=$(jq -r '.failures // 0' "$state_file")
    last_failure=$(jq -r '.last_failure // 0' "$state_file")
    now=$(date +%s)

    # Check for stale state (>24h old)
    local last_change
    last_change=$(jq -r '.last_state_change // 0' "$state_file")
    if (( last_change > 0 )); then
        local age=$((now - last_change))
        if (( age > 86400 )); then
            # Reset stale circuit
            echo '{"state":"CLOSED","failures":0,"last_state_change":'$now'}' > "$state_file"
            log_info "Reset stale circuit breaker for $endpoint_key"
            echo "CLOSED"
            return 0
        fi
    fi

    if [[ "$state" == "OPEN" ]]; then
        # Check if reset timeout has passed
        if (( last_failure > 0 )); then
            elapsed=$((now - last_failure))
            if (( elapsed > CIRCUIT_RESET_TIMEOUT_SECONDS )); then
                # Transition to HALF_OPEN
                update_circuit_state "$endpoint_key" "HALF_OPEN"
                echo "HALF_OPEN"
                return 0
            fi
        fi
    fi

    echo "$state"
}

# Update circuit breaker state
update_circuit_state() {
    local endpoint_key="$1"
    local new_state="$2"
    local state_file="${CIRCUIT_STATE_DIR}/${endpoint_key}.json"
    local now=$(date +%s)

    init_state_dirs

    if [[ ! -f "$state_file" ]]; then
        echo '{"state":"CLOSED","failures":0}' > "$state_file"
    fi

    jq --arg state "$new_state" --argjson now "$now" '
        .state = $state |
        .last_state_change = $now
    ' "$state_file" > "${state_file}.tmp" && mv "${state_file}.tmp" "$state_file"
}

# Record circuit failure
record_circuit_failure() {
    local endpoint_key="$1"
    local state_file="${CIRCUIT_STATE_DIR}/${endpoint_key}.json"
    local now=$(date +%s)

    init_state_dirs

    if [[ ! -f "$state_file" ]]; then
        echo '{"state":"CLOSED","failures":0}' > "$state_file"
    fi

    local failures
    failures=$(jq -r '.failures // 0' "$state_file")
    ((failures++))

    if (( failures >= CIRCUIT_FAILURE_THRESHOLD )); then
        # Open the circuit
        jq --argjson f "$failures" --argjson now "$now" '
            .failures = $f |
            .last_failure = $now |
            .state = "OPEN" |
            .last_state_change = $now
        ' "$state_file" > "${state_file}.tmp" && mv "${state_file}.tmp" "$state_file"
        log_warning "Circuit breaker OPEN for $endpoint_key (failures: $failures)"
    else
        jq --argjson f "$failures" --argjson now "$now" '
            .failures = $f |
            .last_failure = $now
        ' "$state_file" > "${state_file}.tmp" && mv "${state_file}.tmp" "$state_file"
    fi
}

# Record circuit success
record_circuit_success() {
    local endpoint_key="$1"
    local state_file="${CIRCUIT_STATE_DIR}/${endpoint_key}.json"
    local now=$(date +%s)

    if [[ ! -f "$state_file" ]]; then
        return 0
    fi

    local current_state
    current_state=$(jq -r '.state // "CLOSED"' "$state_file")

    if [[ "$current_state" == "HALF_OPEN" ]]; then
        # Success in HALF_OPEN, close the circuit
        jq --argjson now "$now" '
            .state = "CLOSED" |
            .failures = 0 |
            .last_success = $now |
            .last_state_change = $now
        ' "$state_file" > "${state_file}.tmp" && mv "${state_file}.tmp" "$state_file"
        log_info "Circuit breaker CLOSED for $endpoint_key"
    else
        # Record success
        jq --argjson now "$now" '.last_success = $now' "$state_file" > "${state_file}.tmp" && mv "${state_file}.tmp" "$state_file"
    fi
}

# Check and update budget
# Returns: 0 if budget available, 1 if exceeded
check_budget() {
    local operation="$1"
    local cost_cents="${2:-0}"

    init_state_dirs

    # Initialize budget state if needed
    if [[ ! -f "$BUDGET_STATE_FILE" ]]; then
        local today=$(date +%Y-%m-%d)
        echo "{\"date\":\"$today\",\"spent_cents\":0,\"operations\":[]}" > "$BUDGET_STATE_FILE"
    fi

    # Check if it's a new day
    local state_date today
    state_date=$(jq -r '.date' "$BUDGET_STATE_FILE")
    today=$(date +%Y-%m-%d)

    if [[ "$state_date" != "$today" ]]; then
        # Reset for new day
        echo "{\"date\":\"$today\",\"spent_cents\":0,\"operations\":[]}" > "$BUDGET_STATE_FILE"
    fi

    local spent
    spent=$(jq -r '.spent_cents // 0' "$BUDGET_STATE_FILE")

    # Check if budget would be exceeded
    if (( spent + cost_cents > DAILY_BUDGET_CENTS )); then
        log_error "Budget exceeded: spent=$spent, requested=$cost_cents, limit=$DAILY_BUDGET_CENTS"
        return 1
    fi

    # Check warning threshold
    local warn_threshold=$((DAILY_BUDGET_CENTS * BUDGET_WARN_PERCENT / 100))
    if (( spent + cost_cents > warn_threshold )); then
        log_warning "Budget warning: ${BUDGET_WARN_PERCENT}% of daily limit reached"
    fi

    return 0
}

# Record spend
record_spend() {
    local operation="$1"
    local cost_cents="$2"
    local now=$(date -Iseconds)

    init_state_dirs

    if [[ ! -f "$BUDGET_STATE_FILE" ]]; then
        check_budget "$operation" 0
    fi

    jq --arg op "$operation" --argjson cost "$cost_cents" --arg ts "$now" '
        .spent_cents += $cost |
        .operations += [{"operation": $op, "cost_cents": $cost, "timestamp": $ts}]
    ' "$BUDGET_STATE_FILE" > "${BUDGET_STATE_FILE}.tmp" && mv "${BUDGET_STATE_FILE}.tmp" "$BUDGET_STATE_FILE"

    log_debug "Recorded spend: $operation = $cost_cents cents"
}

# Get current daily spend
get_daily_spend() {
    if [[ ! -f "$BUDGET_STATE_FILE" ]]; then
        echo "0"
        return
    fi

    local state_date today
    state_date=$(jq -r '.date' "$BUDGET_STATE_FILE")
    today=$(date +%Y-%m-%d)

    if [[ "$state_date" != "$today" ]]; then
        echo "0"
    else
        jq -r '.spent_cents // 0' "$BUDGET_STATE_FILE"
    fi
}

# Write to dead letter queue
write_dead_letter() {
    local item="$1"
    local failure_type="$2"
    local error_message="${3:-}"
    local retry_count="${4:-0}"
    local now=$(date -Iseconds)

    init_state_dirs

    local dead_letter
    dead_letter=$(jq -c -n \
        --argjson item "$item" \
        --arg failure_type "$failure_type" \
        --arg failure_time "$now" \
        --argjson retry_count "$retry_count" \
        --arg last_error "$error_message" \
        '{
            failure_type: $failure_type,
            failure_time: $failure_time,
            retry_count: $retry_count,
            last_error: $last_error,
            original_item: $item
        }')

    # Atomic append with file locking
    (
        flock -x -w 10 200 || { log_error "Failed to acquire lock for dead letter"; return 1; }
        echo "$dead_letter" >> "$DEAD_LETTER_FILE"
    ) 200>"${DEAD_LETTER_FILE}.lock"

    log_info "Item written to dead letter queue: $failure_type"
}

# Classify HTTP error
# Returns: retryable, fatal, or rate_limited
classify_http_error() {
    local status_code="$1"

    case "$status_code" in
        429)
            echo "rate_limited"
            ;;
        500|502|503|504)
            echo "retryable"
            ;;
        401|403)
            echo "fatal"
            ;;
        400|404|405)
            echo "fatal"
            ;;
        *)
            if (( status_code >= 500 )); then
                echo "retryable"
            else
                echo "fatal"
            fi
            ;;
    esac
}

# Calculate backoff delay in milliseconds
calculate_backoff() {
    local attempt="$1"
    local delay=$((API_INITIAL_BACKOFF_MS * (2 ** (attempt - 1))))

    if (( delay > API_MAX_BACKOFF_MS )); then
        delay=$API_MAX_BACKOFF_MS
    fi

    echo "$delay"
}

# Make API call with retry and circuit breaker
# Usage: call_api_with_retry <endpoint> <method> <data> [timeout]
# Returns: Response body on success, empty on failure
call_api_with_retry() {
    local endpoint="$1"
    local method="${2:-POST}"
    local data="${3:-}"
    local timeout="${4:-$API_TIMEOUT_SECONDS}"

    local endpoint_key
    endpoint_key=$(normalize_endpoint_key "$endpoint")

    # Check circuit breaker
    local circuit_state
    circuit_state=$(get_circuit_state "$endpoint_key")

    if [[ "$circuit_state" == "OPEN" ]]; then
        log_error "Circuit breaker OPEN for $endpoint_key - request blocked"
        return 1
    fi

    local attempt=0
    local response status_code error_class

    while (( attempt < API_MAX_RETRIES )); do
        ((attempt++))

        log_debug "API call attempt $attempt/$API_MAX_RETRIES to $endpoint"

        # Make the request
        local http_response
        http_response=$(curl -s -w "\n%{http_code}" \
            --max-time "$timeout" \
            -X "$method" \
            -H "Content-Type: application/json" \
            ${data:+-d "$data"} \
            "$endpoint" 2>&1) || {
            log_warning "curl failed (timeout or network error)"
            record_circuit_failure "$endpoint_key"
            if (( attempt < API_MAX_RETRIES )); then
                local backoff=$(calculate_backoff $attempt)
                log_info "Retrying in ${backoff}ms..."
                sleep "$(echo "scale=3; $backoff/1000" | bc)"
                continue
            fi
            return 1
        }

        # Parse response
        response=$(echo "$http_response" | sed '$d')
        status_code=$(echo "$http_response" | tail -1)

        log_debug "HTTP $status_code from $endpoint"

        # Check for success
        if [[ "$status_code" =~ ^2 ]]; then
            record_circuit_success "$endpoint_key"
            echo "$response"
            return 0
        fi

        # Classify error
        error_class=$(classify_http_error "$status_code")

        case "$error_class" in
            fatal)
                log_error "Fatal error $status_code from $endpoint"
                record_circuit_failure "$endpoint_key"
                return 1
                ;;
            rate_limited)
                log_warning "Rate limited ($status_code) from $endpoint"
                # Check for Retry-After header (we'd need to parse it from headers)
                local backoff=$((API_MAX_BACKOFF_MS))
                log_info "Backing off for ${backoff}ms..."
                sleep "$(echo "scale=3; $backoff/1000" | bc)"
                ;;
            retryable)
                record_circuit_failure "$endpoint_key"
                if (( attempt < API_MAX_RETRIES )); then
                    local backoff=$(calculate_backoff $attempt)
                    log_info "Retryable error $status_code, retrying in ${backoff}ms..."
                    sleep "$(echo "scale=3; $backoff/1000" | bc)"
                fi
                ;;
        esac
    done

    log_error "All $API_MAX_RETRIES attempts failed for $endpoint"
    return 1
}

# CLI interface
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        --help|-h)
            echo "Usage: api-resilience.sh <command> [args]"
            echo ""
            echo "Commands:"
            echo "  call <endpoint> [method] [data]    Make API call with retry"
            echo "  circuit-status <endpoint>          Check circuit breaker status"
            echo "  budget-status                      Check budget status"
            echo "  reset-circuit <endpoint>           Reset circuit breaker"
            echo ""
            echo "Environment variables:"
            echo "  LOA_API_MAX_RETRIES               Max retry attempts (default: 3)"
            echo "  LOA_API_TIMEOUT_SECONDS           Request timeout (default: 60)"
            echo "  LOA_DAILY_BUDGET_CENTS            Daily budget limit (default: 500)"
            ;;
        call)
            call_api_with_retry "${2:-}" "${3:-POST}" "${4:-}"
            ;;
        circuit-status)
            endpoint_key=$(normalize_endpoint_key "${2:-}")
            echo "Endpoint: $endpoint_key"
            echo "State: $(get_circuit_state "$endpoint_key")"
            ;;
        budget-status)
            echo "Daily budget: $DAILY_BUDGET_CENTS cents"
            echo "Spent today: $(get_daily_spend) cents"
            ;;
        reset-circuit)
            endpoint_key=$(normalize_endpoint_key "${2:-}")
            update_circuit_state "$endpoint_key" "CLOSED"
            echo "Circuit reset for $endpoint_key"
            ;;
        *)
            echo "Unknown command: ${1:-}" >&2
            echo "Use --help for usage" >&2
            exit 1
            ;;
    esac
fi
