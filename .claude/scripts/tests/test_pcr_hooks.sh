#!/usr/bin/env bash
# test_pcr_hooks.sh - Unit tests for Post-Compact Recovery hooks
#
# Usage:
#   bash test_pcr_hooks.sh
#   bash test_pcr_hooks.sh --verbose

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_DIR="$(dirname "$SCRIPT_DIR")/../hooks"

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
    export HOME="$TEST_TMPDIR/home"
    mkdir -p "$HOME/.local/state/loa-compact"
    mkdir -p "$PROJECT_ROOT/.run"
    mkdir -p "$PROJECT_ROOT/grimoires/loa/a2a"

    echo "=========================================="
    echo "Post-Compact Recovery Hooks - Unit Tests"
    echo "=========================================="
    echo ""
}

teardown() {
    rm -rf "$TEST_TMPDIR" 2>/dev/null || true
}

# =============================================================================
# Pre-Compact Marker Tests
# =============================================================================

test_pre_compact_creates_project_marker() {
    # Run the hook
    bash "$HOOKS_DIR/pre-compact-marker.sh" 2>/dev/null

    # Check marker exists
    if [[ -f "$PROJECT_ROOT/.run/compact-pending" ]]; then
        log_pass "Pre-compact creates project marker"
    else
        log_fail "Pre-compact creates project marker"
    fi
}

test_pre_compact_creates_global_marker() {
    # Run the hook
    bash "$HOOKS_DIR/pre-compact-marker.sh" 2>/dev/null

    # Check global marker exists
    if [[ -f "$HOME/.local/state/loa-compact/compact-pending" ]]; then
        log_pass "Pre-compact creates global marker"
    else
        log_fail "Pre-compact creates global marker"
    fi
}

test_pre_compact_marker_contains_json() {
    # Run the hook
    bash "$HOOKS_DIR/pre-compact-marker.sh" 2>/dev/null

    # Verify marker is valid JSON
    if jq -e '.' "$PROJECT_ROOT/.run/compact-pending" >/dev/null 2>&1; then
        log_pass "Pre-compact marker contains valid JSON"
    else
        log_fail "Pre-compact marker contains valid JSON"
    fi
}

test_pre_compact_marker_has_timestamp() {
    # Run the hook
    bash "$HOOKS_DIR/pre-compact-marker.sh" 2>/dev/null

    # Check for timestamp field
    local timestamp
    timestamp=$(jq -r '.timestamp' "$PROJECT_ROOT/.run/compact-pending" 2>/dev/null)

    if [[ -n "$timestamp" && "$timestamp" != "null" ]]; then
        log_pass "Pre-compact marker has timestamp"
    else
        log_fail "Pre-compact marker has timestamp"
    fi
}

test_pre_compact_captures_run_mode() {
    # Create mock run mode state
    cat > "$PROJECT_ROOT/.run/sprint-plan-state.json" << 'EOF'
{"state": "RUNNING", "sprints": {"current": "sprint-2"}}
EOF

    # Run the hook
    bash "$HOOKS_DIR/pre-compact-marker.sh" 2>/dev/null

    # Check run_mode.active
    local active
    active=$(jq -r '.run_mode.active' "$PROJECT_ROOT/.run/compact-pending" 2>/dev/null)

    if [[ "$active" == "true" ]]; then
        log_pass "Pre-compact captures run mode active"
    else
        log_fail "Pre-compact captures run mode active (got: $active)"
    fi
}

test_pre_compact_always_exits_zero() {
    # Run in subshell to capture exit code
    local exit_code=0
    bash "$HOOKS_DIR/pre-compact-marker.sh" 2>/dev/null || exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        log_pass "Pre-compact always exits zero"
    else
        log_fail "Pre-compact always exits zero (got: $exit_code)"
    fi
}

# =============================================================================
# Post-Compact Reminder Tests
# =============================================================================

test_post_compact_no_marker_silent() {
    # Ensure no markers exist
    rm -f "$PROJECT_ROOT/.run/compact-pending" 2>/dev/null || true
    rm -f "$HOME/.local/state/loa-compact/compact-pending" 2>/dev/null || true

    # Run the hook, capture output
    local output
    output=$(bash "$HOOKS_DIR/post-compact-reminder.sh" 2>/dev/null)

    if [[ -z "$output" ]]; then
        log_pass "Post-compact silent when no marker"
    else
        log_fail "Post-compact silent when no marker (got output)"
    fi
}

test_post_compact_detects_project_marker() {
    # Create project marker
    echo '{"timestamp":"2026-02-05T12:00:00Z"}' > "$PROJECT_ROOT/.run/compact-pending"

    # Run the hook, capture output
    local output
    output=$(bash "$HOOKS_DIR/post-compact-reminder.sh" 2>/dev/null)

    if [[ "$output" == *"CONTEXT COMPACTION DETECTED"* ]]; then
        log_pass "Post-compact detects project marker"
    else
        log_fail "Post-compact detects project marker"
    fi
}

test_post_compact_detects_global_marker() {
    # Create only global marker
    rm -f "$PROJECT_ROOT/.run/compact-pending" 2>/dev/null || true
    echo '{"timestamp":"2026-02-05T12:00:00Z"}' > "$HOME/.local/state/loa-compact/compact-pending"

    # Run the hook, capture output
    local output
    output=$(bash "$HOOKS_DIR/post-compact-reminder.sh" 2>/dev/null)

    if [[ "$output" == *"CONTEXT COMPACTION DETECTED"* ]]; then
        log_pass "Post-compact detects global marker"
    else
        log_fail "Post-compact detects global marker"
    fi
}

test_post_compact_deletes_markers() {
    # Create both markers
    echo '{"timestamp":"2026-02-05T12:00:00Z"}' > "$PROJECT_ROOT/.run/compact-pending"
    echo '{"timestamp":"2026-02-05T12:00:00Z"}' > "$HOME/.local/state/loa-compact/compact-pending"

    # Run the hook
    bash "$HOOKS_DIR/post-compact-reminder.sh" >/dev/null 2>&1

    # Check markers are deleted
    if [[ ! -f "$PROJECT_ROOT/.run/compact-pending" ]] && \
       [[ ! -f "$HOME/.local/state/loa-compact/compact-pending" ]]; then
        log_pass "Post-compact deletes markers (one-shot)"
    else
        log_fail "Post-compact deletes markers (one-shot)"
    fi
}

test_post_compact_reminder_has_recovery_steps() {
    # Create marker
    echo '{"timestamp":"2026-02-05T12:00:00Z"}' > "$PROJECT_ROOT/.run/compact-pending"

    # Run the hook
    local output
    output=$(bash "$HOOKS_DIR/post-compact-reminder.sh" 2>/dev/null)

    # Check for key recovery instructions
    local pass=true
    [[ "$output" != *"Re-read Project Conventions"* ]] && pass=false
    [[ "$output" != *"Check Run Mode State"* ]] && pass=false
    [[ "$output" != *"Check Simstim State"* ]] && pass=false
    [[ "$output" != *"Review Project Memory"* ]] && pass=false

    if [[ "$pass" == "true" ]]; then
        log_pass "Post-compact reminder has recovery steps"
    else
        log_fail "Post-compact reminder has recovery steps"
    fi
}

test_post_compact_shows_active_run_mode() {
    # Create marker with active run mode
    cat > "$PROJECT_ROOT/.run/compact-pending" << 'EOF'
{"timestamp":"2026-02-05T12:00:00Z","run_mode":{"active":true,"state":"RUNNING"}}
EOF

    # Run the hook
    local output
    output=$(bash "$HOOKS_DIR/post-compact-reminder.sh" 2>/dev/null)

    if [[ "$output" == *"Run Mode was ACTIVE"* ]] && \
       [[ "$output" == *"RUNNING"* ]]; then
        log_pass "Post-compact shows active run mode"
    else
        log_fail "Post-compact shows active run mode"
    fi
}

test_post_compact_logs_to_trajectory() {
    # Create marker
    echo '{"timestamp":"2026-02-05T12:00:00Z"}' > "$PROJECT_ROOT/.run/compact-pending"

    # Run the hook
    bash "$HOOKS_DIR/post-compact-reminder.sh" >/dev/null 2>&1

    # Check trajectory log
    if [[ -f "$PROJECT_ROOT/grimoires/loa/a2a/trajectory/compact-events.jsonl" ]]; then
        local event
        event=$(tail -1 "$PROJECT_ROOT/grimoires/loa/a2a/trajectory/compact-events.jsonl")
        if [[ "$event" == *"compact_recovery"* ]]; then
            log_pass "Post-compact logs to trajectory"
        else
            log_fail "Post-compact logs to trajectory (wrong format)"
        fi
    else
        log_fail "Post-compact logs to trajectory (no file)"
    fi
}

# =============================================================================
# Main
# =============================================================================

main() {
    setup

    echo "--- Pre-Compact Marker Tests ---"
    test_pre_compact_creates_project_marker
    test_pre_compact_creates_global_marker
    test_pre_compact_marker_contains_json
    test_pre_compact_marker_has_timestamp
    test_pre_compact_captures_run_mode
    test_pre_compact_always_exits_zero

    echo ""
    echo "--- Post-Compact Reminder Tests ---"
    test_post_compact_no_marker_silent
    test_post_compact_detects_project_marker
    test_post_compact_detects_global_marker
    test_post_compact_deletes_markers
    test_post_compact_reminder_has_recovery_steps
    test_post_compact_shows_active_run_mode
    test_post_compact_logs_to_trajectory

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
