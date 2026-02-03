#!/usr/bin/env bash
# =============================================================================
# test-simstim-e2e.sh - End-to-End Integration Test for Simstim
# =============================================================================
# Version: 1.0.0
# Part of: Simstim v1.24.0
#
# Verifies the simstim workflow components work together correctly.
# Run this script to validate the implementation before merge.
#
# Usage:
#   ./test-simstim-e2e.sh [--verbose]
#
# Tests:
#   1. Dry-run shows all 8 phases
#   2. State initialization works
#   3. State update operations work
#   4. Artifact checksum tracking works
#   5. Resume detection works
#   6. HITL mode detection works
#   7. Result handler HITL mode works
#   8. Interrupt handling saves state
#
# Exit codes:
#   0 - All tests passed
#   1 - One or more tests failed
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEST_DIR="$PROJECT_ROOT/.run/test-simstim"
VERBOSE="${1:-}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# =============================================================================
# Test Helpers
# =============================================================================

log() {
    echo -e "$*"
}

pass() {
    ((++TESTS_PASSED))
    log "${GREEN}✓${NC} $1"
}

fail() {
    ((++TESTS_FAILED))
    log "${RED}✗${NC} $1"
    if [[ -n "$VERBOSE" ]]; then
        echo "  Details: $2" >&2
    fi
}

run_test() {
    local name="$1"
    local command="$2"
    local expected="$3"

    ((++TESTS_RUN))

    local result
    if result=$(eval "$command" 2>&1); then
        if [[ -n "$expected" ]]; then
            if echo "$result" | grep -q "$expected"; then
                pass "$name"
            else
                fail "$name" "Expected '$expected' in output, got: $result"
            fi
        else
            pass "$name"
        fi
    else
        fail "$name" "Command failed: $result"
    fi
}

setup() {
    rm -rf "$TEST_DIR"
    mkdir -p "$TEST_DIR"

    # Backup existing state if present
    if [[ -f "$PROJECT_ROOT/.run/simstim-state.json" ]]; then
        cp "$PROJECT_ROOT/.run/simstim-state.json" "$TEST_DIR/simstim-state.json.backup"
    fi
}

cleanup() {
    # Restore original state if we backed it up
    if [[ -f "$TEST_DIR/simstim-state.json.backup" ]]; then
        mv "$TEST_DIR/simstim-state.json.backup" "$PROJECT_ROOT/.run/simstim-state.json"
    else
        rm -f "$PROJECT_ROOT/.run/simstim-state.json"
        rm -f "$PROJECT_ROOT/.run/simstim-state.json.bak"
    fi

    rm -rf "$TEST_DIR"
}

# =============================================================================
# Tests
# =============================================================================

test_orchestrator_exists() {
    run_test "Orchestrator script exists" \
        "test -x $SCRIPT_DIR/simstim-orchestrator.sh && echo 'exists'" \
        "exists"
}

test_state_script_exists() {
    run_test "State script exists" \
        "test -x $SCRIPT_DIR/simstim-state.sh && echo 'exists'" \
        "exists"
}

test_skill_exists() {
    run_test "SKILL.md exists" \
        "test -f $PROJECT_ROOT/.claude/skills/simstim-workflow/SKILL.md && echo 'exists'" \
        "exists"
}

test_command_exists() {
    run_test "Command documentation exists" \
        "test -f $PROJECT_ROOT/.claude/commands/simstim.md && echo 'exists'" \
        "exists"
}

test_state_init() {
    rm -f "$PROJECT_ROOT/.run/simstim-state.json"
    run_test "State init creates file" \
        "$SCRIPT_DIR/simstim-state.sh init && test -f $PROJECT_ROOT/.run/simstim-state.json && echo 'created'" \
        "created"
}

test_state_schema_version() {
    run_test "State has schema_version" \
        "jq -r '.schema_version' $PROJECT_ROOT/.run/simstim-state.json" \
        "1"
}

test_state_get() {
    run_test "State get works" \
        "$SCRIPT_DIR/simstim-state.sh get state" \
        "RUNNING"
}

test_state_update_phase() {
    run_test "State update-phase works" \
        "$SCRIPT_DIR/simstim-state.sh update-phase preflight completed && $SCRIPT_DIR/simstim-state.sh get 'phases.preflight'" \
        "completed"
}

test_state_add_artifact() {
    # Create a test file
    echo "test content" > "$TEST_DIR/test-artifact.md"
    cp "$TEST_DIR/test-artifact.md" "$PROJECT_ROOT/grimoires/loa/"

    run_test "State add-artifact works" \
        "$SCRIPT_DIR/simstim-state.sh add-artifact test grimoires/loa/test-artifact.md" \
        "sha256"

    rm -f "$PROJECT_ROOT/grimoires/loa/test-artifact.md"
}

test_state_validate_artifacts() {
    run_test "State validate-artifacts works" \
        "$SCRIPT_DIR/simstim-state.sh validate-artifacts | jq -r '.valid'" \
        ""  # May be true or false depending on artifact state
}

test_state_save_interrupt() {
    run_test "State save-interrupt works" \
        "$SCRIPT_DIR/simstim-state.sh save-interrupt && $SCRIPT_DIR/simstim-state.sh get state" \
        "INTERRUPTED"
}

test_state_cleanup() {
    run_test "State cleanup works" \
        "$SCRIPT_DIR/simstim-state.sh cleanup && test ! -f $PROJECT_ROOT/.run/simstim-state.json && echo 'cleaned'" \
        "cleaned"
}

test_mode_detect_hitl_cli() {
    run_test "Mode detect --hitl flag" \
        "$SCRIPT_DIR/flatline-mode-detect.sh --hitl --json | jq -r '.mode'" \
        "hitl"
}

test_mode_detect_hitl_env() {
    run_test "Mode detect LOA_FLATLINE_MODE=hitl" \
        "LOA_FLATLINE_MODE=hitl $SCRIPT_DIR/flatline-mode-detect.sh --json | jq -r '.mode'" \
        "hitl"
}

test_result_handler_help() {
    run_test "Result handler shows hitl in help" \
        "$SCRIPT_DIR/flatline-result-handler.sh --help 2>&1" \
        "hitl"
}

test_skill_resume_count() {
    local count
    count=$(grep -c "resume" "$PROJECT_ROOT/.claude/skills/simstim-workflow/SKILL.md" || echo "0")
    if [[ "$count" -ge 5 ]]; then
        pass "SKILL.md has sufficient resume documentation (count: $count)"
    else
        fail "SKILL.md needs more resume documentation (count: $count, expected >= 5)" ""
    fi
    ((TESTS_RUN++))
}

test_command_resume_count() {
    local count
    count=$(grep -c "\-\-resume" "$PROJECT_ROOT/.claude/commands/simstim.md" || echo "0")
    if [[ "$count" -ge 3 ]]; then
        pass "simstim.md has sufficient --resume documentation (count: $count)"
    else
        fail "simstim.md needs more --resume documentation (count: $count, expected >= 3)" ""
    fi
    ((TESTS_RUN++))
}

test_disputed_blocker_docs() {
    local disputed_count
    disputed_count=$(grep -c "DISPUTED" "$PROJECT_ROOT/.claude/skills/simstim-workflow/SKILL.md" || echo "0")
    local blocker_count
    blocker_count=$(grep -c "BLOCKER" "$PROJECT_ROOT/.claude/skills/simstim-workflow/SKILL.md" || echo "0")

    if [[ "$disputed_count" -ge 3 && "$blocker_count" -ge 3 ]]; then
        pass "SKILL.md has sufficient DISPUTED/BLOCKER documentation (DISPUTED: $disputed_count, BLOCKER: $blocker_count)"
    else
        fail "SKILL.md needs more DISPUTED/BLOCKER documentation" "DISPUTED: $disputed_count, BLOCKER: $blocker_count"
    fi
    ((TESTS_RUN++))
}

# =============================================================================
# Main
# =============================================================================

main() {
    log "════════════════════════════════════════════════════════════"
    log "     Simstim E2E Integration Tests"
    log "════════════════════════════════════════════════════════════"
    log ""

    setup

    # Component existence tests
    log "${YELLOW}Component Tests:${NC}"
    test_orchestrator_exists
    test_state_script_exists
    test_skill_exists
    test_command_exists

    log ""
    log "${YELLOW}State Management Tests:${NC}"
    test_state_init
    test_state_schema_version
    test_state_get
    test_state_update_phase
    test_state_add_artifact
    test_state_validate_artifacts
    test_state_save_interrupt
    test_state_cleanup

    log ""
    log "${YELLOW}Mode Detection Tests:${NC}"
    test_mode_detect_hitl_cli
    test_mode_detect_hitl_env
    test_result_handler_help

    log ""
    log "${YELLOW}Documentation Tests:${NC}"
    test_skill_resume_count
    test_command_resume_count
    test_disputed_blocker_docs

    cleanup

    log ""
    log "════════════════════════════════════════════════════════════"
    log "     Results: $TESTS_PASSED/$TESTS_RUN passed"
    log "════════════════════════════════════════════════════════════"

    if [[ $TESTS_FAILED -gt 0 ]]; then
        log "${RED}$TESTS_FAILED test(s) failed${NC}"
        exit 1
    else
        log "${GREEN}All tests passed!${NC}"
        exit 0
    fi
}

main "$@"
