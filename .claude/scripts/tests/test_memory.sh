#!/usr/bin/env bash
# test_memory.sh - Unit tests for Persistent Memory System
#
# Usage:
#   bash test_memory.sh
#   bash test_memory.sh --verbose

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MEMORY_WRITER="$(dirname "$SCRIPT_DIR")/../hooks/memory-writer.sh"
MEMORY_QUERY="$(dirname "$SCRIPT_DIR")/memory-query.sh"

# Test configuration
VERBOSE="${1:-}"
PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Test temp directory
TEST_TMPDIR=""

# =============================================================================
# Test Framework
# =============================================================================

log_pass() {
    echo -e "${GREEN}PASS${NC}: $1"
    ((PASS_COUNT++)) || true
}

log_fail() {
    echo -e "${RED}FAIL${NC}: $1"
    ((FAIL_COUNT++)) || true
}

log_skip() {
    echo -e "${YELLOW}SKIP${NC}: $1"
    ((SKIP_COUNT++)) || true
}

# =============================================================================
# Setup / Teardown
# =============================================================================

setup() {
    TEST_TMPDIR=$(mktemp -d)
    export PROJECT_ROOT="$TEST_TMPDIR"
    export LOA_SESSION_ID="test-session-$$"
    mkdir -p "$TEST_TMPDIR/grimoires/loa/memory/sessions"
    touch "$TEST_TMPDIR/grimoires/loa/memory/observations.jsonl"

    echo "=========================================="
    echo "Persistent Memory System - Unit Tests"
    echo "=========================================="
    echo ""
}

teardown() {
    rm -rf "$TEST_TMPDIR" 2>/dev/null || true
}

# Helper: Create test observation
create_test_observation() {
    local type="${1:-discovery}"
    local summary="${2:-Test observation}"
    local id="obs-$(date +%s)-$(echo "$summary" | sha256sum | cut -c1-8)"

    cat <<EOF
{"id":"$id","timestamp":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","session_id":"$LOA_SESSION_ID","type":"$type","summary":"$summary","tool":"test","private":false,"details":"","tags":[],"references":[]}
EOF
}

# Helper: Add observation to file
add_observation() {
    local obs="$1"
    echo "$obs" >> "$TEST_TMPDIR/grimoires/loa/memory/observations.jsonl"
}

# =============================================================================
# Script Existence Tests
# =============================================================================

test_memory_writer_exists() {
    if [[ -f "$MEMORY_WRITER" ]]; then
        log_pass "Memory writer hook exists"
    else
        log_fail "Memory writer hook exists (not found: $MEMORY_WRITER)"
    fi
}

test_memory_writer_executable() {
    if [[ -x "$MEMORY_WRITER" ]]; then
        log_pass "Memory writer hook is executable"
    else
        log_fail "Memory writer hook is executable"
    fi
}

test_memory_query_exists() {
    if [[ -f "$MEMORY_QUERY" ]]; then
        log_pass "Memory query script exists"
    else
        log_fail "Memory query script exists (not found: $MEMORY_QUERY)"
    fi
}

test_memory_query_executable() {
    if [[ -x "$MEMORY_QUERY" ]]; then
        log_pass "Memory query script is executable"
    else
        log_fail "Memory query script is executable"
    fi
}

# =============================================================================
# Memory Writer Tests
# =============================================================================

test_writer_skips_read_tools() {
    local exit_code=0
    echo "Test content" | "$MEMORY_WRITER" "Read" 2>/dev/null || exit_code=$?

    # Writer should always exit 0
    if [[ $exit_code -eq 0 ]]; then
        log_pass "Memory writer skips Read tool"
    else
        log_fail "Memory writer skips Read tool"
    fi
}

test_writer_captures_learning_signals() {
    # Clear observations
    > "$TEST_TMPDIR/grimoires/loa/memory/observations.jsonl"

    # Send content with learning signal
    echo "I discovered the root cause of the bug" | "$MEMORY_WRITER" "Edit" 2>/dev/null || true

    # Check if observation was created
    if [[ -s "$TEST_TMPDIR/grimoires/loa/memory/observations.jsonl" ]]; then
        log_pass "Memory writer captures learning signals"
    else
        log_fail "Memory writer captures learning signals"
    fi
}

test_writer_creates_session_file() {
    # Clear files
    > "$TEST_TMPDIR/grimoires/loa/memory/observations.jsonl"
    rm -f "$TEST_TMPDIR/grimoires/loa/memory/sessions/$LOA_SESSION_ID.jsonl"

    # Send content with learning signal
    echo "I learned something new about the API" | "$MEMORY_WRITER" "Write" 2>/dev/null || true

    # Check if session file was created
    if [[ -f "$TEST_TMPDIR/grimoires/loa/memory/sessions/$LOA_SESSION_ID.jsonl" ]]; then
        log_pass "Memory writer creates session file"
    else
        log_fail "Memory writer creates session file"
    fi
}

test_writer_always_exits_zero() {
    local exit_code=0
    # Even with invalid input, should exit 0
    echo "" | "$MEMORY_WRITER" "Unknown" 2>/dev/null || exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        log_pass "Memory writer always exits zero"
    else
        log_fail "Memory writer always exits zero"
    fi
}

test_writer_respects_disabled_config() {
    # Clear observations
    > "$TEST_TMPDIR/grimoires/loa/memory/observations.jsonl"

    # Run with memory disabled
    echo "I discovered something" | LOA_MEMORY_ENABLED=false "$MEMORY_WRITER" "Edit" 2>/dev/null || true

    # Should not create observation
    if [[ ! -s "$TEST_TMPDIR/grimoires/loa/memory/observations.jsonl" ]]; then
        log_pass "Memory writer respects disabled config"
    else
        log_fail "Memory writer respects disabled config"
    fi
}

# =============================================================================
# Memory Query Tests
# =============================================================================

test_query_help_output() {
    local output
    output=$("$MEMORY_QUERY" --help 2>&1) || true

    if [[ "$output" == *"--index"* ]] && \
       [[ "$output" == *"--full"* ]] && \
       [[ "$output" == *"--type"* ]]; then
        log_pass "Memory query help shows all options"
    else
        log_fail "Memory query help shows all options"
    fi
}

test_query_empty_observations() {
    # Clear observations
    > "$TEST_TMPDIR/grimoires/loa/memory/observations.jsonl"

    local output
    output=$("$MEMORY_QUERY" --index 2>&1) || true

    # Should handle empty gracefully
    if [[ "$output" == *"No observations"* ]] || [[ "$output" == "[]" ]]; then
        log_pass "Memory query handles empty observations"
    else
        log_fail "Memory query handles empty observations"
    fi
}

test_query_index_mode() {
    # Add test observations
    add_observation "$(create_test_observation "discovery" "Found API endpoint")"
    add_observation "$(create_test_observation "learning" "Learned about caching")"

    local output
    output=$("$MEMORY_QUERY" --index --limit 2 2>&1) || true

    if [[ "$output" == *"id"* ]] && [[ "$output" == *"type"* ]]; then
        log_pass "Memory query index mode works"
    else
        log_fail "Memory query index mode works"
    fi
}

test_query_filter_by_type() {
    # Clear and add test observations
    > "$TEST_TMPDIR/grimoires/loa/memory/observations.jsonl"
    add_observation "$(create_test_observation "discovery" "Found something")"
    add_observation "$(create_test_observation "learning" "Learned something")"
    add_observation "$(create_test_observation "error" "Fixed an error")"

    local output
    output=$("$MEMORY_QUERY" --type learning --limit 5 2>&1) || true

    if [[ "$output" == *"learning"* ]] && [[ "$output" != *"error"* ]]; then
        log_pass "Memory query filters by type"
    else
        log_fail "Memory query filters by type"
    fi
}

test_query_full_details() {
    # Clear and add test observation
    > "$TEST_TMPDIR/grimoires/loa/memory/observations.jsonl"
    local obs
    obs=$(create_test_observation "discovery" "Test full observation")
    add_observation "$obs"

    local obs_id
    obs_id=$(echo "$obs" | jq -r '.id')

    local output
    output=$("$MEMORY_QUERY" --full "$obs_id" 2>&1) || true

    if [[ "$output" == *"$obs_id"* ]] && [[ "$output" == *"summary"* ]]; then
        log_pass "Memory query full details works"
    else
        log_fail "Memory query full details works"
    fi
}

test_query_search() {
    # Clear and add test observations
    > "$TEST_TMPDIR/grimoires/loa/memory/observations.jsonl"
    add_observation "$(create_test_observation "discovery" "Authentication pattern found")"
    add_observation "$(create_test_observation "learning" "Database connection pooling")"

    local output
    output=$("$MEMORY_QUERY" "Authentication" 2>&1) || true

    if [[ "$output" == *"Authentication"* ]]; then
        log_pass "Memory query search works"
    else
        log_fail "Memory query search works"
    fi
}

test_query_stats() {
    # Add some observations
    add_observation "$(create_test_observation "discovery" "Stat test 1")"
    add_observation "$(create_test_observation "learning" "Stat test 2")"

    local output
    output=$("$MEMORY_QUERY" --stats 2>&1) || true

    if [[ "$output" == *"total_observations"* ]] || [[ "$output" == *"by_type"* ]]; then
        log_pass "Memory query stats works"
    else
        log_fail "Memory query stats works"
    fi
}

# =============================================================================
# Directory Structure Tests
# =============================================================================

test_memory_dir_exists() {
    if [[ -d "$TEST_TMPDIR/grimoires/loa/memory" ]]; then
        log_pass "Memory directory exists"
    else
        log_fail "Memory directory exists"
    fi
}

test_sessions_dir_exists() {
    if [[ -d "$TEST_TMPDIR/grimoires/loa/memory/sessions" ]]; then
        log_pass "Sessions directory exists"
    else
        log_fail "Sessions directory exists"
    fi
}

test_observations_file_exists() {
    if [[ -f "$TEST_TMPDIR/grimoires/loa/memory/observations.jsonl" ]]; then
        log_pass "Observations file exists"
    else
        log_fail "Observations file exists"
    fi
}

# =============================================================================
# Main
# =============================================================================

main() {
    setup

    echo "--- Script Existence Tests ---"
    test_memory_writer_exists
    test_memory_writer_executable
    test_memory_query_exists
    test_memory_query_executable

    echo ""
    echo "--- Memory Writer Tests ---"
    test_writer_skips_read_tools
    test_writer_captures_learning_signals
    test_writer_creates_session_file
    test_writer_always_exits_zero
    test_writer_respects_disabled_config

    echo ""
    echo "--- Memory Query Tests ---"
    test_query_help_output
    test_query_empty_observations
    test_query_index_mode
    test_query_filter_by_type
    test_query_full_details
    test_query_search
    test_query_stats

    echo ""
    echo "--- Directory Structure Tests ---"
    test_memory_dir_exists
    test_sessions_dir_exists
    test_observations_file_exists

    echo ""
    echo "=========================================="
    echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed, $SKIP_COUNT skipped"

    teardown

    if [[ $FAIL_COUNT -gt 0 ]]; then
        echo -e "${RED}Some tests failed${NC}"
        exit 1
    else
        echo -e "${GREEN}All tests passed${NC}"
        exit 0
    fi
}

main "$@"
