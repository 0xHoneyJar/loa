#!/usr/bin/env bash
# test_dcg.sh - Unit tests for Destructive Command Guard
#
# Usage:
#   bash test_dcg.sh
#   bash test_dcg.sh --verbose

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DCG_DIR="$(dirname "$SCRIPT_DIR")"

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

assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="$3"

    if [[ "$expected" == "$actual" ]]; then
        log_pass "$message"
        return 0
    else
        log_fail "$message (expected: $expected, got: $actual)"
        return 1
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="$3"

    if [[ "$haystack" == *"$needle"* ]]; then
        log_pass "$message"
        return 0
    else
        log_fail "$message (expected to contain: $needle)"
        return 1
    fi
}

assert_not_empty() {
    local value="$1"
    local message="$2"

    if [[ -n "$value" ]]; then
        log_pass "$message"
        return 0
    else
        log_fail "$message (expected non-empty value)"
        return 1
    fi
}

# =============================================================================
# Setup
# =============================================================================

setup() {
    # Source the DCG modules
    export PROJECT_ROOT="$DCG_DIR/../.."

    # Create temp config for testing
    export _TEST_TMPDIR=$(mktemp -d)
    export DCG_CONTEXT="test"

    # Source modules
    source "$DCG_DIR/destructive-command-guard.sh" 2>/dev/null || {
        echo "ERROR: Failed to source destructive-command-guard.sh"
        exit 1
    }

    # Initialize DCG
    dcg_init 2>/dev/null || true

    echo "=========================================="
    echo "DCG Unit Tests"
    echo "=========================================="
    echo ""
}

teardown() {
    rm -rf "$_TEST_TMPDIR" 2>/dev/null || true
}

# =============================================================================
# Parser Tests
# =============================================================================

test_parser_simple_command() {
    if ! type dcg_parse &>/dev/null; then
        source "$DCG_DIR/dcg-parser.sh"
    fi

    local result
    result=$(dcg_parse "echo hello")
    local segments
    segments=$(echo "$result" | jq -r '.segments[0]' 2>/dev/null)

    assert_equals "echo hello" "$segments" "Parser: simple command"
}

test_parser_chained_commands() {
    if ! type dcg_parse &>/dev/null; then
        source "$DCG_DIR/dcg-parser.sh"
    fi

    local result
    result=$(dcg_parse "npm test && rm -rf dist")
    local count
    count=$(echo "$result" | jq '.segments | length' 2>/dev/null)

    assert_equals "2" "$count" "Parser: chained commands (&&)"
}

test_parser_pipe_commands() {
    if ! type dcg_parse &>/dev/null; then
        source "$DCG_DIR/dcg-parser.sh"
    fi

    local result
    result=$(dcg_parse "cat file.txt | grep pattern")
    local count
    count=$(echo "$result" | jq '.segments | length' 2>/dev/null)

    assert_equals "2" "$count" "Parser: piped commands"
}

test_parser_semicolon_commands() {
    if ! type dcg_parse &>/dev/null; then
        source "$DCG_DIR/dcg-parser.sh"
    fi

    local result
    result=$(dcg_parse "echo a; echo b; echo c")
    local count
    count=$(echo "$result" | jq '.segments | length' 2>/dev/null)

    assert_equals "3" "$count" "Parser: semicolon-separated commands"
}

# =============================================================================
# Core Pattern Tests - BLOCK
# =============================================================================

test_block_rm_rf_root() {
    local result
    result=$(dcg_validate "rm -rf /")
    local action
    action=$(echo "$result" | jq -r '.action' 2>/dev/null)

    assert_equals "BLOCK" "$action" "Block: rm -rf /"
}

test_block_rm_rf_root_star() {
    local result
    result=$(dcg_validate "rm -rf /*")
    local action
    action=$(echo "$result" | jq -r '.action' 2>/dev/null)

    assert_equals "BLOCK" "$action" "Block: rm -rf /*"
}

test_block_rm_rf_home() {
    local result
    result=$(dcg_validate "rm -rf ~")
    local action
    action=$(echo "$result" | jq -r '.action' 2>/dev/null)

    assert_equals "BLOCK" "$action" "Block: rm -rf ~"
}

test_block_rm_rf_etc() {
    local result
    result=$(dcg_validate "rm -rf /etc")
    local action
    action=$(echo "$result" | jq -r '.action' 2>/dev/null)

    assert_equals "BLOCK" "$action" "Block: rm -rf /etc"
}

test_block_rm_rf_usr() {
    local result
    result=$(dcg_validate "rm -rf /usr")
    local action
    action=$(echo "$result" | jq -r '.action' 2>/dev/null)

    assert_equals "BLOCK" "$action" "Block: rm -rf /usr"
}

test_block_git_push_force() {
    local result
    result=$(dcg_validate "git push --force origin main")
    local action
    action=$(echo "$result" | jq -r '.action' 2>/dev/null)

    assert_equals "BLOCK" "$action" "Block: git push --force"
}

test_block_git_push_force_short() {
    local result
    result=$(dcg_validate "git push -f origin main")
    local action
    action=$(echo "$result" | jq -r '.action' 2>/dev/null)

    assert_equals "BLOCK" "$action" "Block: git push -f"
}

# =============================================================================
# Core Pattern Tests - WARN
# =============================================================================

test_warn_git_reset_hard() {
    local result
    result=$(dcg_validate "git reset --hard HEAD~1")
    local action
    action=$(echo "$result" | jq -r '.action' 2>/dev/null)

    assert_equals "WARN" "$action" "Warn: git reset --hard"
}

test_warn_git_clean_force() {
    local result
    result=$(dcg_validate "git clean -fd")
    local action
    action=$(echo "$result" | jq -r '.action' 2>/dev/null)

    assert_equals "WARN" "$action" "Warn: git clean -fd"
}

test_warn_eval() {
    local result
    result=$(dcg_validate 'eval "$cmd"')
    local action
    action=$(echo "$result" | jq -r '.action' 2>/dev/null)

    assert_equals "WARN" "$action" "Warn: eval with variable"
}

# =============================================================================
# Safe Context Tests
# =============================================================================

test_safe_grep_rm() {
    local result
    result=$(dcg_validate "grep 'rm -rf' file.txt")
    local action
    action=$(echo "$result" | jq -r '.action' 2>/dev/null)

    assert_equals "ALLOW" "$action" "Safe context: grep 'rm -rf'"
}

test_safe_echo_drop() {
    local result
    result=$(dcg_validate "echo 'DROP TABLE users'")
    local action
    action=$(echo "$result" | jq -r '.action' 2>/dev/null)

    assert_equals "ALLOW" "$action" "Safe context: echo 'DROP TABLE'"
}

test_safe_cat_file() {
    local result
    result=$(dcg_validate "cat /etc/passwd")
    local action
    action=$(echo "$result" | jq -r '.action' 2>/dev/null)

    assert_equals "ALLOW" "$action" "Safe context: cat file"
}

test_safe_dry_run() {
    local result
    result=$(dcg_validate "terraform destroy --dry-run")
    local action
    action=$(echo "$result" | jq -r '.action' 2>/dev/null)

    assert_equals "ALLOW" "$action" "Safe context: --dry-run flag"
}

test_safe_help() {
    local result
    result=$(dcg_validate "rm --help")
    local action
    action=$(echo "$result" | jq -r '.action' 2>/dev/null)

    assert_equals "ALLOW" "$action" "Safe context: --help flag"
}

# =============================================================================
# Safe Path Tests
# =============================================================================

test_safe_path_tmp() {
    local result
    result=$(dcg_validate "rm -rf /tmp/test-cache")
    local action
    action=$(echo "$result" | jq -r '.action' 2>/dev/null)

    assert_equals "ALLOW" "$action" "Safe path: /tmp"
}

test_safe_path_node_modules() {
    # Requires PROJECT_ROOT to be set
    local result
    result=$(dcg_validate "rm -rf ${PROJECT_ROOT}/node_modules")
    local action
    action=$(echo "$result" | jq -r '.action' 2>/dev/null)

    assert_equals "ALLOW" "$action" "Safe path: node_modules"
}

# =============================================================================
# Chaining Tests
# =============================================================================

test_chain_block_any_dangerous() {
    local result
    result=$(dcg_validate "echo hello && rm -rf /")
    local action
    action=$(echo "$result" | jq -r '.action' 2>/dev/null)

    assert_equals "BLOCK" "$action" "Chain: block if any segment dangerous"
}

test_chain_allow_safe() {
    local result
    result=$(dcg_validate "npm test && npm build")
    local action
    action=$(echo "$result" | jq -r '.action' 2>/dev/null)

    assert_equals "ALLOW" "$action" "Chain: allow safe commands"
}

test_chain_warn_any() {
    local result
    result=$(dcg_validate "npm test && git reset --hard")
    local action
    action=$(echo "$result" | jq -r '.action' 2>/dev/null)

    assert_equals "WARN" "$action" "Chain: warn if any segment warns"
}

# =============================================================================
# Allow Tests
# =============================================================================

test_allow_npm_test() {
    local result
    result=$(dcg_validate "npm test")
    local action
    action=$(echo "$result" | jq -r '.action' 2>/dev/null)

    assert_equals "ALLOW" "$action" "Allow: npm test"
}

test_allow_ls() {
    local result
    result=$(dcg_validate "ls -la")
    local action
    action=$(echo "$result" | jq -r '.action' 2>/dev/null)

    assert_equals "ALLOW" "$action" "Allow: ls -la"
}

test_allow_git_status() {
    local result
    result=$(dcg_validate "git status")
    local action
    action=$(echo "$result" | jq -r '.action' 2>/dev/null)

    assert_equals "ALLOW" "$action" "Allow: git status"
}

# =============================================================================
# Main
# =============================================================================

main() {
    setup

    # Parser tests
    test_parser_simple_command
    test_parser_chained_commands
    test_parser_pipe_commands
    test_parser_semicolon_commands

    echo ""

    # BLOCK tests
    test_block_rm_rf_root
    test_block_rm_rf_root_star
    test_block_rm_rf_home
    test_block_rm_rf_etc
    test_block_rm_rf_usr
    test_block_git_push_force
    test_block_git_push_force_short

    echo ""

    # WARN tests
    test_warn_git_reset_hard
    test_warn_git_clean_force
    test_warn_eval

    echo ""

    # Safe context tests
    test_safe_grep_rm
    test_safe_echo_drop
    test_safe_cat_file
    test_safe_dry_run
    test_safe_help

    echo ""

    # Safe path tests
    test_safe_path_tmp
    test_safe_path_node_modules

    echo ""

    # Chaining tests
    test_chain_block_any_dangerous
    test_chain_allow_safe
    test_chain_warn_any

    echo ""

    # Allow tests
    test_allow_npm_test
    test_allow_ls
    test_allow_git_status

    echo ""
    echo "=========================================="
    echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed, $SKIP_COUNT skipped"

    if [[ $FAIL_COUNT -gt 0 ]]; then
        echo -e "${RED}Some tests failed${NC}"
        teardown
        exit 1
    else
        echo -e "${GREEN}All tests passed${NC}"
        teardown
        exit 0
    fi
}

main "$@"
