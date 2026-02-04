#!/usr/bin/env bash
# update-beads-state.sh
# Purpose: Manage .run/beads-state.json for beads-first infrastructure
# Part of Beads-First Architecture (v1.29.0)
#
# Usage:
#   ./update-beads-state.sh --health <status>       # Update health status
#   ./update-beads-state.sh --opt-out "<reason>"    # Record opt-out with reason
#   ./update-beads-state.sh --opt-out-check         # Check if opt-out is valid
#   ./update-beads-state.sh --sync-import           # Record sync import
#   ./update-beads-state.sh --sync-flush            # Record sync flush
#   ./update-beads-state.sh --recovery-attempt      # Record recovery attempt
#   ./update-beads-state.sh --reset                 # Reset state file
#   ./update-beads-state.sh --show                  # Show current state
#
# Exit codes:
#   0 - Success
#   1 - Invalid arguments
#   2 - State file error
#   3 - Opt-out expired (for --opt-out-check)

set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Allow PROJECT_ROOT override for testing
if [[ -z "${PROJECT_ROOT:-}" ]]; then
    PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
fi

STATE_FILE="${PROJECT_ROOT}/.run/beads-state.json"
STATE_DIR="${PROJECT_ROOT}/.run"

# Default opt-out expiry (hours)
OPT_OUT_EXPIRY_HOURS="${LOA_BEADS_OPT_OUT_HOURS:-24}"
MAX_CONSECUTIVE_OPT_OUTS="${LOA_BEADS_MAX_OPT_OUTS:-3}"

# -----------------------------------------------------------------------------
# Utility Functions
# -----------------------------------------------------------------------------
ensure_state_dir() {
    mkdir -p "${STATE_DIR}"
}

get_timestamp() {
    date -u +%Y-%m-%dT%H:%M:%SZ
}

get_expiry_timestamp() {
    local hours="${1:-${OPT_OUT_EXPIRY_HOURS}}"
    # Cross-platform date arithmetic
    if date --version &>/dev/null 2>&1; then
        # GNU date
        date -u -d "+${hours} hours" +%Y-%m-%dT%H:%M:%SZ
    else
        # BSD date (macOS)
        date -u -v+${hours}H +%Y-%m-%dT%H:%M:%SZ
    fi
}

init_state() {
    ensure_state_dir

    cat > "${STATE_FILE}" <<EOF
{
  "schema_version": 1,
  "health": {
    "status": "UNKNOWN",
    "last_check": null,
    "last_healthy": null,
    "consecutive_failures": 0,
    "details": {}
  },
  "opt_out": {
    "active": false,
    "reason": null,
    "acknowledged_at": null,
    "expires_at": null,
    "consecutive_opt_outs": 0,
    "history": []
  },
  "recovery": {
    "last_attempt": null,
    "attempts_since_healthy": 0,
    "history": []
  },
  "sync": {
    "last_import": null,
    "last_flush": null
  }
}
EOF
}

read_state() {
    if [[ ! -f "${STATE_FILE}" ]]; then
        init_state
    fi
    cat "${STATE_FILE}"
}

write_state() {
    local new_state="$1"
    ensure_state_dir

    # Atomic write
    local tmp_file="${STATE_FILE}.tmp.$$"
    echo "${new_state}" > "${tmp_file}"
    mv "${tmp_file}" "${STATE_FILE}"
}

# -----------------------------------------------------------------------------
# Health Status Management
# -----------------------------------------------------------------------------
update_health() {
    local status="$1"
    local timestamp
    timestamp=$(get_timestamp)

    local state
    state=$(read_state)

    local prev_status
    prev_status=$(echo "${state}" | jq -r '.health.status')

    # Update consecutive failures
    local consecutive_failures
    if [[ "${status}" == "HEALTHY" ]]; then
        consecutive_failures=0
    else
        consecutive_failures=$(echo "${state}" | jq -r '.health.consecutive_failures')
        consecutive_failures=$((consecutive_failures + 1))
    fi

    # Update last_healthy if healthy
    local last_healthy
    if [[ "${status}" == "HEALTHY" ]]; then
        last_healthy="${timestamp}"
    else
        last_healthy=$(echo "${state}" | jq -r '.health.last_healthy // null')
    fi

    # Build updated state
    local new_state
    new_state=$(echo "${state}" | jq \
        --arg status "${status}" \
        --arg last_check "${timestamp}" \
        --arg last_healthy "${last_healthy}" \
        --argjson consecutive_failures "${consecutive_failures}" \
        '.health.status = $status |
         .health.last_check = $last_check |
         .health.last_healthy = (if $last_healthy == "null" then null else $last_healthy end) |
         .health.consecutive_failures = $consecutive_failures')

    write_state "${new_state}"

    echo "Health status updated: ${prev_status} -> ${status}"
}

# -----------------------------------------------------------------------------
# Opt-Out Management
# -----------------------------------------------------------------------------
record_opt_out() {
    local reason="$1"
    local timestamp
    timestamp=$(get_timestamp)
    local expires_at
    expires_at=$(get_expiry_timestamp "${OPT_OUT_EXPIRY_HOURS}")

    local state
    state=$(read_state)

    # Increment consecutive opt-outs
    local consecutive
    consecutive=$(echo "${state}" | jq -r '.opt_out.consecutive_opt_outs')
    consecutive=$((consecutive + 1))

    # Build history entry
    local history_entry
    history_entry=$(jq -n \
        --arg reason "${reason}" \
        --arg acknowledged_at "${timestamp}" \
        --arg expires_at "${expires_at}" \
        '{reason: $reason, acknowledged_at: $acknowledged_at, expires_at: $expires_at}')

    # Update state
    local new_state
    new_state=$(echo "${state}" | jq \
        --arg reason "${reason}" \
        --arg acknowledged_at "${timestamp}" \
        --arg expires_at "${expires_at}" \
        --argjson consecutive "${consecutive}" \
        --argjson history_entry "${history_entry}" \
        '.opt_out.active = true |
         .opt_out.reason = $reason |
         .opt_out.acknowledged_at = $acknowledged_at |
         .opt_out.expires_at = $expires_at |
         .opt_out.consecutive_opt_outs = $consecutive |
         .opt_out.history = (.opt_out.history + [$history_entry])')

    write_state "${new_state}"

    echo "Opt-out recorded (expires: ${expires_at})"

    # Warn if approaching max consecutive
    if [[ ${consecutive} -ge ${MAX_CONSECUTIVE_OPT_OUTS} ]]; then
        echo "WARNING: ${consecutive} consecutive opt-outs. Consider installing beads."
    fi
}

check_opt_out() {
    local state
    state=$(read_state)

    local active
    active=$(echo "${state}" | jq -r '.opt_out.active')

    if [[ "${active}" != "true" ]]; then
        echo "NO_OPT_OUT"
        exit 3
    fi

    local expires_at
    expires_at=$(echo "${state}" | jq -r '.opt_out.expires_at')

    if [[ -z "${expires_at}" || "${expires_at}" == "null" ]]; then
        echo "OPT_OUT_INVALID"
        exit 3
    fi

    # Check if expired
    local now_epoch expires_epoch
    now_epoch=$(date +%s)

    # Parse ISO timestamp to epoch
    if date --version &>/dev/null 2>&1; then
        # GNU date
        expires_epoch=$(date -d "${expires_at}" +%s 2>/dev/null || echo "0")
    else
        # BSD date (macOS)
        expires_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "${expires_at}" +%s 2>/dev/null || echo "0")
    fi

    if [[ ${now_epoch} -gt ${expires_epoch} ]]; then
        # Clear expired opt-out
        local new_state
        new_state=$(echo "${state}" | jq '.opt_out.active = false')
        write_state "${new_state}"

        echo "OPT_OUT_EXPIRED"
        exit 3
    fi

    local reason
    reason=$(echo "${state}" | jq -r '.opt_out.reason')
    echo "OPT_OUT_VALID|${expires_at}|${reason}"
    exit 0
}

# -----------------------------------------------------------------------------
# Sync Tracking
# -----------------------------------------------------------------------------
record_sync_import() {
    local timestamp
    timestamp=$(get_timestamp)

    local state
    state=$(read_state)

    local new_state
    new_state=$(echo "${state}" | jq --arg ts "${timestamp}" '.sync.last_import = $ts')

    write_state "${new_state}"
    echo "Sync import recorded: ${timestamp}"
}

record_sync_flush() {
    local timestamp
    timestamp=$(get_timestamp)

    local state
    state=$(read_state)

    local new_state
    new_state=$(echo "${state}" | jq --arg ts "${timestamp}" '.sync.last_flush = $ts')

    write_state "${new_state}"
    echo "Sync flush recorded: ${timestamp}"
}

# -----------------------------------------------------------------------------
# Recovery Tracking
# -----------------------------------------------------------------------------
record_recovery_attempt() {
    local timestamp
    timestamp=$(get_timestamp)

    local state
    state=$(read_state)

    local attempts
    attempts=$(echo "${state}" | jq -r '.recovery.attempts_since_healthy')
    attempts=$((attempts + 1))

    # Build history entry
    local history_entry
    history_entry=$(jq -n --arg ts "${timestamp}" '{timestamp: $ts}')

    local new_state
    new_state=$(echo "${state}" | jq \
        --arg ts "${timestamp}" \
        --argjson attempts "${attempts}" \
        --argjson history_entry "${history_entry}" \
        '.recovery.last_attempt = $ts |
         .recovery.attempts_since_healthy = $attempts |
         .recovery.history = (.recovery.history + [$history_entry])')

    write_state "${new_state}"
    echo "Recovery attempt #${attempts} recorded"
}

# -----------------------------------------------------------------------------
# Display
# -----------------------------------------------------------------------------
show_state() {
    if [[ ! -f "${STATE_FILE}" ]]; then
        echo "No state file found at ${STATE_FILE}"
        exit 2
    fi

    cat "${STATE_FILE}" | jq .
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    if [[ $# -eq 0 ]]; then
        echo "Usage: $0 <action> [args...]"
        echo ""
        echo "Actions:"
        echo "  --health <status>     Update health status"
        echo "  --opt-out \"<reason>\"  Record opt-out with reason"
        echo "  --opt-out-check       Check if opt-out is valid"
        echo "  --sync-import         Record sync import"
        echo "  --sync-flush          Record sync flush"
        echo "  --recovery-attempt    Record recovery attempt"
        echo "  --reset               Reset state file"
        echo "  --show                Show current state"
        exit 1
    fi

    case "$1" in
        --health)
            if [[ -z "${2:-}" ]]; then
                echo "Error: status required" >&2
                exit 1
            fi
            update_health "$2"
            ;;
        --opt-out)
            if [[ -z "${2:-}" ]]; then
                echo "Error: reason required" >&2
                exit 1
            fi
            record_opt_out "$2"
            ;;
        --opt-out-check)
            check_opt_out
            ;;
        --sync-import)
            record_sync_import
            ;;
        --sync-flush)
            record_sync_flush
            ;;
        --recovery-attempt)
            record_recovery_attempt
            ;;
        --reset)
            init_state
            echo "State file reset"
            ;;
        --show)
            show_state
            ;;
        *)
            echo "Unknown action: $1" >&2
            exit 1
            ;;
    esac
}

main "$@"
