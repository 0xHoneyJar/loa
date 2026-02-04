#!/usr/bin/env bash
# dcg-golden-test-runner.sh - Run golden tests for DCG
#
# Validates DCG patterns against a comprehensive test corpus.
#
# Usage:
#   bash dcg-golden-test-runner.sh [test-file.yaml]
#   bash dcg-golden-test-runner.sh --verbose

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DCG_DIR="$(dirname "$SCRIPT_DIR")"

# Configuration
VERBOSE="${VERBOSE:-false}"
TEST_FILE="${1:-$SCRIPT_DIR/dcg-golden-tests.yaml}"

# Counters
PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# =============================================================================
# Setup
# =============================================================================

setup() {
    # Check dependencies
    if ! command -v yq &>/dev/null; then
        echo "ERROR: yq is required for golden tests"
        exit 1
    fi

    # Check yq version - need v4 (mikefarah/yq)
    local yq_version=""
    yq_version=$(yq --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1) || yq_version=""
    local yq_major="${yq_version%%.*}"

    if [[ -z "$yq_major" ]] || [[ "$yq_major" -lt 4 ]]; then
        echo "ERROR: yq v4+ (mikefarah/yq) is required for golden tests"
        echo "       Current version appears to be yq v${yq_version:-unknown} (Python yq)"
        echo "       Install mikefarah/yq: https://github.com/mikefarah/yq#install"
        echo ""
        echo "SKIP: Golden tests skipped due to yq version requirement"
        exit 0
    fi

    if ! command -v jq &>/dev/null; then
        echo "ERROR: jq is required for golden tests"
        exit 1
    fi

    # Check test file
    if [[ ! -f "$TEST_FILE" ]]; then
        echo "ERROR: Test file not found: $TEST_FILE"
        exit 1
    fi

    # Parse verbose flag
    if [[ "${1:-}" == "--verbose" || "${1:-}" == "-v" ]]; then
        VERBOSE=true
        TEST_FILE="${2:-$SCRIPT_DIR/dcg-golden-tests.yaml}"
    fi

    # Source DCG modules
    export PROJECT_ROOT="$DCG_DIR/../.."
    export DCG_CONTEXT="test"

    source "$DCG_DIR/destructive-command-guard.sh" 2>/dev/null || {
        echo "ERROR: Failed to source destructive-command-guard.sh"
        exit 1
    }

    # Initialize DCG
    dcg_init 2>/dev/null || true

    echo "=========================================="
    echo "DCG Golden Tests"
    echo "=========================================="
    echo "Test file: $TEST_FILE"
    echo ""
}

# =============================================================================
# Test Execution
# =============================================================================

run_tests() {
    local test_count
    test_count=$(yq e '.tests | length' "$TEST_FILE")

    echo "Running $test_count tests..."
    echo ""

    for ((i=0; i<test_count; i++)); do
        local id input expected pattern description
        id=$(yq e ".tests[$i].id // \"test_$i\"" "$TEST_FILE")
        input=$(yq e ".tests[$i].input" "$TEST_FILE")
        expected=$(yq e ".tests[$i].expected" "$TEST_FILE")
        pattern=$(yq e ".tests[$i].pattern // \"\"" "$TEST_FILE")
        description=$(yq e ".tests[$i].description // \"\"" "$TEST_FILE")

        run_single_test "$id" "$input" "$expected" "$pattern" "$description"
    done
}

run_single_test() {
    local id="$1"
    local input="$2"
    local expected="$3"
    local pattern="$4"
    local description="$5"

    # Validate command
    local result
    result=$(dcg_validate "$input" 2>/dev/null) || result='{"action":"ERROR"}'

    local actual
    actual=$(echo "$result" | jq -r '.action // "ERROR"' 2>/dev/null) || actual="ERROR"

    # Compare
    if [[ "$actual" == "$expected" ]]; then
        ((PASS_COUNT++))
        if [[ "$VERBOSE" == "true" ]]; then
            echo -e "${GREEN}PASS${NC} [$id] $description"
            echo "       Input: $input"
            echo "       Expected: $expected, Got: $actual"
        else
            echo -e "${GREEN}✓${NC} $id"
        fi
    else
        ((FAIL_COUNT++))
        echo -e "${RED}FAIL${NC} [$id] $description"
        echo "       Input: $input"
        echo "       Expected: $expected, Got: $actual"
        if [[ -n "$pattern" ]]; then
            echo "       Pattern: $pattern"
        fi
        echo ""
    fi
}

# =============================================================================
# Summary
# =============================================================================

summary() {
    echo ""
    echo "=========================================="
    echo "Results"
    echo "=========================================="
    echo -e "Passed:  ${GREEN}$PASS_COUNT${NC}"
    echo -e "Failed:  ${RED}$FAIL_COUNT${NC}"
    echo -e "Skipped: ${YELLOW}$SKIP_COUNT${NC}"
    echo ""

    local total=$((PASS_COUNT + FAIL_COUNT + SKIP_COUNT))
    if [[ $total -gt 0 ]]; then
        local pass_rate=$((PASS_COUNT * 100 / total))
        echo "Pass rate: $pass_rate%"
    fi

    echo ""

    if [[ $FAIL_COUNT -gt 0 ]]; then
        echo -e "${RED}Some tests failed${NC}"
        exit 1
    else
        echo -e "${GREEN}All tests passed${NC}"
        exit 0
    fi
}

# =============================================================================
# Main
# =============================================================================

main() {
    setup "$@"
    run_tests
    summary
}

main "$@"
