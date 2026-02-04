#!/usr/bin/env bash
# test_beads_health.sh
# Purpose: Unit tests for beads-first infrastructure
# Part of Beads-First Architecture (v1.29.0)
#
# Usage:
#   ./test_beads_health.sh [--verbose]
#
# Tests:
#   - Health check exit codes
#   - State file management
#   - Opt-out workflow
#   - Integration scenarios

set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
BEADS_HEALTH="${PROJECT_ROOT}/.claude/scripts/beads/beads-health.sh"
BEADS_STATE="${PROJECT_ROOT}/.claude/scripts/beads/update-beads-state.sh"

# Test isolation
TEST_DIR=""
ORIGINAL_BEADS_DIR=""
ORIGINAL_RUN_DIR=""

VERBOSE="${1:-}"
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# -----------------------------------------------------------------------------
# Test Framework
# -----------------------------------------------------------------------------
setup() {
    TEST_DIR=$(mktemp -d)
    ORIGINAL_BEADS_DIR="${PROJECT_ROOT}/.beads"
    ORIGINAL_RUN_DIR="${PROJECT_ROOT}/.run"

    # Create test directories
    mkdir -p "${TEST_DIR}/.beads"
    mkdir -p "${TEST_DIR}/.run"

    # Backup and redirect
    if [[ -d "${ORIGINAL_BEADS_DIR}" ]]; then
        mv "${ORIGINAL_BEADS_DIR}" "${ORIGINAL_BEADS_DIR}.test-backup"
    fi

    export LOA_BEADS_DIR="${TEST_DIR}/.beads"
    export LOA_RUN_DIR="${TEST_DIR}/.run"
}

teardown() {
    # Restore original directories
    if [[ -d "${ORIGINAL_BEADS_DIR}.test-backup" ]]; then
        mv "${ORIGINAL_BEADS_DIR}.test-backup" "${ORIGINAL_BEADS_DIR}"
    fi

    # Cleanup test directory
    if [[ -n "${TEST_DIR}" && -d "${TEST_DIR}" ]]; then
        rm -rf "${TEST_DIR}"
    fi

    unset LOA_BEADS_DIR
    unset LOA_RUN_DIR
}

run_test() {
    local test_name="$1"
    local test_func="$2"

    TESTS_RUN=$((TESTS_RUN + 1))

    if [[ "${VERBOSE}" == "--verbose" ]]; then
        echo -n "  Running: ${test_name}... "
    fi

    local result
    if result=$(${test_func} 2>&1); then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        if [[ "${VERBOSE}" == "--verbose" ]]; then
            echo -e "${GREEN}PASS${NC}"
        else
            echo -n "."
        fi
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        if [[ "${VERBOSE}" == "--verbose" ]]; then
            echo -e "${RED}FAIL${NC}"
            echo "    ${result}"
        else
            echo -n "F"
        fi
    fi
}

# -----------------------------------------------------------------------------
# Health Check Tests
# -----------------------------------------------------------------------------
test_healthy_state_returns_0() {
    # Setup: Create valid beads directory with database
    mkdir -p "${TEST_DIR}/.beads"

    # Create minimal SQLite database with owner column
    sqlite3 "${TEST_DIR}/.beads/beads.db" <<EOF
CREATE TABLE issues (
    id TEXT PRIMARY KEY,
    title TEXT,
    status TEXT,
    owner TEXT
);
INSERT INTO issues VALUES ('test-1', 'Test Issue', 'open', 'test-agent');
EOF

    # Create JSONL file
    echo '{"id":"test-1","title":"Test Issue","status":"open"}' > "${TEST_DIR}/.beads/issues.jsonl"

    # Symlink to test location
    ln -sf "${TEST_DIR}/.beads" "${PROJECT_ROOT}/.beads"

    local exit_code=0
    "${BEADS_HEALTH}" --quick >/dev/null 2>&1 || exit_code=$?

    # Cleanup
    rm -f "${PROJECT_ROOT}/.beads"

    if [[ ${exit_code} -ne 0 ]]; then
        return 1
    fi
}

test_not_installed_returns_1() {
    # Temporarily hide br
    local original_path="${PATH}"
    export PATH="/nonexistent"

    local exit_code=0
    "${BEADS_HEALTH}" --quick >/dev/null 2>&1 || exit_code=$?

    export PATH="${original_path}"

    if [[ ${exit_code} -ne 1 ]]; then
        echo "Expected exit code 1, got ${exit_code}"
        return 1
    fi
}

test_not_initialized_returns_2() {
    # Remove beads directory
    rm -rf "${TEST_DIR}/.beads"

    # Symlink empty location
    ln -sf "${TEST_DIR}/.beads" "${PROJECT_ROOT}/.beads" 2>/dev/null || true

    local exit_code=0
    "${BEADS_HEALTH}" --quick >/dev/null 2>&1 || exit_code=$?

    # Cleanup
    rm -f "${PROJECT_ROOT}/.beads"

    if [[ ${exit_code} -ne 2 ]]; then
        echo "Expected exit code 2, got ${exit_code}"
        return 1
    fi
}

test_json_output_valid() {
    # Test against real project (beads should be healthy)
    unset PROJECT_ROOT

    local output
    output=$("${BEADS_HEALTH}" --json 2>/dev/null || true)

    # Verify JSON is valid
    if ! echo "${output}" | jq . >/dev/null 2>&1; then
        echo "Invalid JSON output: ${output}"
        return 1
    fi

    # Verify required fields
    local status
    status=$(echo "${output}" | jq -r '.status')
    if [[ -z "${status}" || "${status}" == "null" ]]; then
        echo "Missing status field"
        return 1
    fi
}

# -----------------------------------------------------------------------------
# State Management Tests
# -----------------------------------------------------------------------------
test_state_file_created() {
    rm -f "${TEST_DIR}/.run/beads-state.json"
    mkdir -p "${TEST_DIR}/.run"

    # Force state creation with exported PROJECT_ROOT
    export PROJECT_ROOT="${TEST_DIR}"
    "${BEADS_STATE}" --reset >/dev/null 2>&1

    if [[ ! -f "${TEST_DIR}/.run/beads-state.json" ]]; then
        echo "State file not created"
        return 1
    fi

    # Verify schema
    local version
    version=$(jq -r '.schema_version' "${TEST_DIR}/.run/beads-state.json")
    if [[ "${version}" != "1" ]]; then
        echo "Invalid schema version: ${version}"
        return 1
    fi
}

test_opt_out_recorded() {
    mkdir -p "${TEST_DIR}/.run"
    export PROJECT_ROOT="${TEST_DIR}"
    "${BEADS_STATE}" --reset >/dev/null 2>&1
    "${BEADS_STATE}" --opt-out "Test reason" >/dev/null 2>&1

    local active
    active=$(jq -r '.opt_out.active' "${TEST_DIR}/.run/beads-state.json")
    if [[ "${active}" != "true" ]]; then
        echo "Opt-out not active"
        return 1
    fi

    local reason
    reason=$(jq -r '.opt_out.reason' "${TEST_DIR}/.run/beads-state.json")
    if [[ "${reason}" != "Test reason" ]]; then
        echo "Wrong reason: ${reason}"
        return 1
    fi
}

test_opt_out_check_valid() {
    mkdir -p "${TEST_DIR}/.run"
    export PROJECT_ROOT="${TEST_DIR}"
    "${BEADS_STATE}" --reset >/dev/null 2>&1
    "${BEADS_STATE}" --opt-out "Test reason" >/dev/null 2>&1

    local result
    result=$("${BEADS_STATE}" --opt-out-check 2>/dev/null || echo "FAILED")

    if [[ "${result}" != "OPT_OUT_VALID"* ]]; then
        echo "Opt-out check failed: ${result}"
        return 1
    fi
}

test_health_update() {
    mkdir -p "${TEST_DIR}/.run"
    export PROJECT_ROOT="${TEST_DIR}"
    "${BEADS_STATE}" --reset >/dev/null 2>&1
    "${BEADS_STATE}" --health HEALTHY >/dev/null 2>&1

    local status
    status=$(jq -r '.health.status' "${TEST_DIR}/.run/beads-state.json")
    if [[ "${status}" != "HEALTHY" ]]; then
        echo "Health status not updated: ${status}"
        return 1
    fi
}

test_consecutive_failures_tracked() {
    mkdir -p "${TEST_DIR}/.run"
    export PROJECT_ROOT="${TEST_DIR}"
    "${BEADS_STATE}" --reset >/dev/null 2>&1
    "${BEADS_STATE}" --health DEGRADED >/dev/null 2>&1
    "${BEADS_STATE}" --health DEGRADED >/dev/null 2>&1

    local failures
    failures=$(jq -r '.health.consecutive_failures' "${TEST_DIR}/.run/beads-state.json")
    if [[ "${failures}" -ne 2 ]]; then
        echo "Wrong failure count: ${failures}"
        return 1
    fi

    # Reset on healthy
    "${BEADS_STATE}" --health HEALTHY >/dev/null 2>&1
    failures=$(jq -r '.health.consecutive_failures' "${TEST_DIR}/.run/beads-state.json")
    if [[ "${failures}" -ne 0 ]]; then
        echo "Failures not reset on healthy: ${failures}"
        return 1
    fi
}

test_sync_tracking() {
    mkdir -p "${TEST_DIR}/.run"
    export PROJECT_ROOT="${TEST_DIR}"
    "${BEADS_STATE}" --reset >/dev/null 2>&1
    "${BEADS_STATE}" --sync-import >/dev/null 2>&1

    local last_import
    last_import=$(jq -r '.sync.last_import' "${TEST_DIR}/.run/beads-state.json")
    if [[ "${last_import}" == "null" ]]; then
        echo "Sync import not recorded"
        return 1
    fi

    "${BEADS_STATE}" --sync-flush >/dev/null 2>&1

    local last_flush
    last_flush=$(jq -r '.sync.last_flush' "${TEST_DIR}/.run/beads-state.json")
    if [[ "${last_flush}" == "null" ]]; then
        echo "Sync flush not recorded"
        return 1
    fi
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    echo "Beads-First Infrastructure Tests"
    echo "================================="
    echo ""

    # Trap to ensure cleanup
    trap teardown EXIT

    setup

    echo "Health Check Tests:"
    # Skip not_installed test if we want to keep br available
    # run_test "NOT_INSTALLED returns 1" test_not_installed_returns_1
    run_test "NOT_INITIALIZED returns 2" test_not_initialized_returns_2
    run_test "JSON output valid" test_json_output_valid
    # run_test "HEALTHY returns 0" test_healthy_state_returns_0  # Needs working br

    echo ""
    echo "State Management Tests:"
    run_test "State file created" test_state_file_created
    run_test "Opt-out recorded" test_opt_out_recorded
    run_test "Opt-out check valid" test_opt_out_check_valid
    run_test "Health update" test_health_update
    run_test "Consecutive failures tracked" test_consecutive_failures_tracked
    run_test "Sync tracking" test_sync_tracking

    echo ""
    echo ""
    echo "================================="
    echo -e "Results: ${TESTS_PASSED}/${TESTS_RUN} passed"

    if [[ ${TESTS_FAILED} -gt 0 ]]; then
        echo -e "${RED}${TESTS_FAILED} tests failed${NC}"
        exit 1
    else
        echo -e "${GREEN}All tests passed${NC}"
        exit 0
    fi
}

main "$@"
