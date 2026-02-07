#!/usr/bin/env bash
# beads-health.sh
# Purpose: Comprehensive health check for beads_rust infrastructure
# Part of Beads-First Architecture (v1.29.0)
#
# Exit codes:
#   0 - HEALTHY: All checks pass
#   1 - NOT_INSTALLED: br binary not found
#   2 - NOT_INITIALIZED: No .beads directory
#   3 - MIGRATION_NEEDED: Schema incompatible (missing owner column)
#   4 - DEGRADED: Partial functionality (recoverable)
#   5 - UNHEALTHY: Critical issues
#
# Usage:
#   ./beads-health.sh [--json|--verbose|--quick]
#
# Output (JSON mode):
#   {
#     "status": "HEALTHY|NOT_INSTALLED|NOT_INITIALIZED|MIGRATION_NEEDED|DEGRADED|UNHEALTHY",
#     "version": "0.1.7",
#     "checks": { ... },
#     "recommendations": [ ... ]
#   }

set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Require bash 4.0+ (associative arrays)
# shellcheck source=../bash-version-guard.sh
source "$SCRIPT_DIR/../bash-version-guard.sh"

# Allow PROJECT_ROOT override for testing
if [[ -z "${PROJECT_ROOT:-}" ]]; then
    PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
fi

# Source config paths if available
if [[ -f "${SCRIPT_DIR}/../get-config-paths.sh" ]]; then
    source "${SCRIPT_DIR}/../get-config-paths.sh"
    BEADS_DIR="${LOA_BEADS_DIR:-${PROJECT_ROOT}/.beads}"
else
    BEADS_DIR="${PROJECT_ROOT}/.beads"
fi

# Thresholds (can be overridden via config)
JSONL_WARN_SIZE_MB="${LOA_BEADS_JSONL_WARN_MB:-50}"
DB_WARN_SIZE_MB="${LOA_BEADS_DB_WARN_MB:-100}"
SYNC_STALE_HOURS="${LOA_BEADS_SYNC_STALE_HOURS:-24}"

# Output mode
OUTPUT_MODE="text"
VERBOSE=false
QUICK=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --json)
            OUTPUT_MODE="json"
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --quick)
            QUICK=true
            shift
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# -----------------------------------------------------------------------------
# Health Check Functions
# -----------------------------------------------------------------------------
declare -A CHECKS
declare -a RECOMMENDATIONS=()  # Initialize empty array

check_binary() {
    if command -v br &>/dev/null; then
        local version
        version=$(br --version 2>/dev/null | head -n1 || echo "unknown")
        CHECKS["binary"]="installed"
        CHECKS["version"]="${version}"
        return 0
    else
        CHECKS["binary"]="not_found"
        RECOMMENDATIONS+=("Install beads_rust: cargo install beads_rust")
        return 1
    fi
}

check_initialized() {
    if [[ -d "${BEADS_DIR}" ]]; then
        CHECKS["initialized"]="true"
        CHECKS["beads_dir"]="${BEADS_DIR}"
        return 0
    else
        CHECKS["initialized"]="false"
        RECOMMENDATIONS+=("Initialize beads: br init")
        return 2
    fi
}

check_database() {
    local db_path="${BEADS_DIR}/beads.db"

    if [[ ! -f "${db_path}" ]]; then
        CHECKS["database"]="missing"
        RECOMMENDATIONS+=("Database missing - run: br init")
        return 1
    fi

    # Check file size
    local db_size_bytes
    db_size_bytes=$(stat -f%z "${db_path}" 2>/dev/null || stat -c%s "${db_path}" 2>/dev/null || echo "0")
    local db_size_mb=$((db_size_bytes / 1024 / 1024))
    CHECKS["db_size_mb"]="${db_size_mb}"

    if [[ ${db_size_mb} -gt ${DB_WARN_SIZE_MB} ]]; then
        CHECKS["database"]="large"
        RECOMMENDATIONS+=("Database is large (${db_size_mb}MB) - consider archiving old issues")
    else
        CHECKS["database"]="ok"
    fi

    # Check accessibility
    if ! sqlite3 "${db_path}" "SELECT 1;" &>/dev/null; then
        CHECKS["database"]="corrupted"
        RECOMMENDATIONS+=("Database corrupted - restore from .beads/beads.db.bak or reinitialize")
        return 1
    fi

    return 0
}

check_schema() {
    local db_path="${BEADS_DIR}/beads.db"

    if [[ ! -f "${db_path}" ]]; then
        CHECKS["schema"]="no_database"
        return 1
    fi

    # Check for owner column (required for agent workflows)
    local has_owner
    has_owner=$(sqlite3 "${db_path}" "PRAGMA table_info(issues);" 2>/dev/null | grep -c "owner" || echo "0")

    if [[ "${has_owner}" -eq 0 ]]; then
        CHECKS["schema"]="missing_owner"
        RECOMMENDATIONS+=("Schema migration needed - owner column missing")
        return 3
    fi

    CHECKS["schema"]="compatible"
    return 0
}

check_doctor() {
    if [[ "${QUICK}" == true ]]; then
        CHECKS["doctor"]="skipped"
        return 0
    fi

    local doctor_output
    if doctor_output=$(br doctor 2>&1); then
        CHECKS["doctor"]="healthy"
        return 0
    else
        CHECKS["doctor"]="issues_found"
        CHECKS["doctor_output"]="${doctor_output}"
        RECOMMENDATIONS+=("Run 'br doctor' for details")
        return 4
    fi
}

check_jsonl_sync() {
    local jsonl_path="${BEADS_DIR}/issues.jsonl"

    if [[ ! -f "${jsonl_path}" ]]; then
        CHECKS["jsonl"]="not_synced"
        RECOMMENDATIONS+=("JSONL not synced - run: br sync --flush-only")
        return 4
    fi

    # Check file size
    local jsonl_size_bytes
    jsonl_size_bytes=$(stat -f%z "${jsonl_path}" 2>/dev/null || stat -c%s "${jsonl_path}" 2>/dev/null || echo "0")
    local jsonl_size_mb=$((jsonl_size_bytes / 1024 / 1024))
    CHECKS["jsonl_size_mb"]="${jsonl_size_mb}"

    if [[ ${jsonl_size_mb} -gt ${JSONL_WARN_SIZE_MB} ]]; then
        CHECKS["jsonl"]="large"
        RECOMMENDATIONS+=("JSONL is large (${jsonl_size_mb}MB) - consider archiving")
    else
        CHECKS["jsonl"]="ok"
    fi

    # Check staleness
    local jsonl_mtime
    jsonl_mtime=$(stat -f%m "${jsonl_path}" 2>/dev/null || stat -c%Y "${jsonl_path}" 2>/dev/null || echo "0")
    local now
    now=$(date +%s)
    local age_hours=$(( (now - jsonl_mtime) / 3600 ))
    CHECKS["jsonl_age_hours"]="${age_hours}"

    if [[ ${age_hours} -gt ${SYNC_STALE_HOURS} ]]; then
        CHECKS["jsonl_stale"]="true"
        RECOMMENDATIONS+=("JSONL is stale (${age_hours}h old) - run: br sync")
    else
        CHECKS["jsonl_stale"]="false"
    fi

    return 0
}

# -----------------------------------------------------------------------------
# Determine Overall Status
# -----------------------------------------------------------------------------
determine_status() {
    # Priority order: NOT_INSTALLED > NOT_INITIALIZED > MIGRATION_NEEDED > UNHEALTHY > DEGRADED > HEALTHY

    if [[ "${CHECKS[binary]}" == "not_found" ]]; then
        echo "NOT_INSTALLED"
        return 1
    fi

    if [[ "${CHECKS[initialized]}" == "false" ]]; then
        echo "NOT_INITIALIZED"
        return 2
    fi

    if [[ "${CHECKS[schema]:-}" == "missing_owner" ]]; then
        echo "MIGRATION_NEEDED"
        return 3
    fi

    if [[ "${CHECKS[database]:-}" == "corrupted" ]]; then
        echo "UNHEALTHY"
        return 5
    fi

    # Check for degraded conditions
    local degraded=false

    if [[ "${CHECKS[database]:-}" == "large" ]]; then
        degraded=true
    fi

    if [[ "${CHECKS[jsonl]:-}" == "not_synced" || "${CHECKS[jsonl]:-}" == "large" ]]; then
        degraded=true
    fi

    if [[ "${CHECKS[jsonl_stale]:-}" == "true" ]]; then
        degraded=true
    fi

    if [[ "${CHECKS[doctor]:-}" == "issues_found" ]]; then
        degraded=true
    fi

    if [[ "${degraded}" == true ]]; then
        echo "DEGRADED"
        return 4
    fi

    echo "HEALTHY"
    return 0
}

# -----------------------------------------------------------------------------
# Output Functions
# -----------------------------------------------------------------------------
output_json() {
    local status="$1"
    local exit_code="$2"

    # Build JSON output
    cat <<EOF
{
  "status": "${status}",
  "exit_code": ${exit_code},
  "version": "${CHECKS[version]:-unknown}",
  "beads_dir": "${BEADS_DIR}",
  "checks": {
    "binary": "${CHECKS[binary]:-unknown}",
    "initialized": ${CHECKS[initialized]:-false},
    "database": "${CHECKS[database]:-unknown}",
    "db_size_mb": ${CHECKS[db_size_mb]:-0},
    "schema": "${CHECKS[schema]:-unknown}",
    "doctor": "${CHECKS[doctor]:-unknown}",
    "jsonl": "${CHECKS[jsonl]:-unknown}",
    "jsonl_size_mb": ${CHECKS[jsonl_size_mb]:-0},
    "jsonl_age_hours": ${CHECKS[jsonl_age_hours]:-0},
    "jsonl_stale": ${CHECKS[jsonl_stale]:-false}
  },
  "recommendations": $(if [[ ${#RECOMMENDATIONS[@]} -gt 0 ]]; then printf '%s\n' "${RECOMMENDATIONS[@]}" | jq -R . | jq -s .; else echo "[]"; fi),
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
}

output_text() {
    local status="$1"

    echo "Beads Health Check"
    echo "=================="
    echo ""
    echo "Status: ${status}"
    echo "Version: ${CHECKS[version]:-unknown}"
    echo "Directory: ${BEADS_DIR}"
    echo ""

    if [[ "${VERBOSE}" == true ]]; then
        echo "Checks:"
        echo "  Binary: ${CHECKS[binary]:-unknown}"
        echo "  Initialized: ${CHECKS[initialized]:-unknown}"
        echo "  Database: ${CHECKS[database]:-unknown} (${CHECKS[db_size_mb]:-0}MB)"
        echo "  Schema: ${CHECKS[schema]:-unknown}"
        echo "  Doctor: ${CHECKS[doctor]:-unknown}"
        echo "  JSONL: ${CHECKS[jsonl]:-unknown} (${CHECKS[jsonl_size_mb]:-0}MB, ${CHECKS[jsonl_age_hours]:-0}h old)"
        echo ""
    fi

    local rec_count="${#RECOMMENDATIONS[@]}"
    if [[ "${rec_count}" -gt 0 ]]; then
        echo "Recommendations:"
        for rec in "${RECOMMENDATIONS[@]}"; do
            [[ -n "${rec}" ]] && echo "  - ${rec}"
        done
    fi
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    # Run checks in order
    check_binary || true

    # If binary not found, stop here
    if [[ "${CHECKS[binary]}" == "not_found" ]]; then
        local status="NOT_INSTALLED"
        if [[ "${OUTPUT_MODE}" == "json" ]]; then
            output_json "${status}" 1
        else
            output_text "${status}"
        fi
        exit 1
    fi

    check_initialized || true

    # If not initialized, stop here
    if [[ "${CHECKS[initialized]}" == "false" ]]; then
        local status="NOT_INITIALIZED"
        if [[ "${OUTPUT_MODE}" == "json" ]]; then
            output_json "${status}" 2
        else
            output_text "${status}"
        fi
        exit 2
    fi

    # Run remaining checks
    check_database || true
    check_schema || true
    check_doctor || true
    check_jsonl_sync || true

    # Determine overall status
    # Disable errexit for this assignment: determine_status uses non-zero
    # return codes to signal status (1=NOT_INSTALLED, 4=DEGRADED, etc.).
    # With set -e, the command substitution would abort the script before
    # output_json/output_text runs, producing zero output. Fixes #228.
    local status exit_code
    set +e
    status=$(determine_status)
    exit_code=$?
    set -e

    # Output results
    if [[ "${OUTPUT_MODE}" == "json" ]]; then
        output_json "${status}" "${exit_code}"
    else
        output_text "${status}"
    fi

    exit "${exit_code}"
}

main "$@"
