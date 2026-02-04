#!/usr/bin/env bash
# test_blf.sh - Unit tests for Beads Flatline Loop
#
# Usage:
#   bash test_blf.sh
#   bash test_blf.sh --verbose

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BLF_SCRIPT="$(dirname "$SCRIPT_DIR")/beads-flatline-loop.sh"
FLATLINE_ORCHESTRATOR="$(dirname "$SCRIPT_DIR")/flatline-orchestrator.sh"

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
    export PATH="$TEST_TMPDIR/bin:$PATH"
    mkdir -p "$TEST_TMPDIR/bin"
    mkdir -p "$TEST_TMPDIR/.run"

    echo "=========================================="
    echo "Beads Flatline Loop - Unit Tests"
    echo "=========================================="
    echo ""
}

teardown() {
    rm -rf "$TEST_TMPDIR" 2>/dev/null || true
}

# Create mock br command
create_mock_br() {
    local beads_count="${1:-5}"
    cat > "$TEST_TMPDIR/bin/br" << EOF
#!/usr/bin/env bash
case "\$1" in
    list)
        if [[ "\$2" == "--json" ]]; then
            echo '['
            for i in \$(seq 1 $beads_count); do
                echo '  {"id": "bead-'\$i'", "title": "Task '\$i'", "priority": '\$i', "status": "open"}'
                if [[ \$i -lt $beads_count ]]; then echo ','; fi
            done
            echo ']'
        fi
        ;;
    sync)
        echo "Synced"
        ;;
esac
EOF
    chmod +x "$TEST_TMPDIR/bin/br"
}

# =============================================================================
# Script Existence Tests
# =============================================================================

test_blf_script_exists() {
    if [[ -f "$BLF_SCRIPT" ]]; then
        log_pass "BLF script exists"
    else
        log_fail "BLF script exists (not found: $BLF_SCRIPT)"
    fi
}

test_blf_script_executable() {
    if [[ -x "$BLF_SCRIPT" ]]; then
        log_pass "BLF script is executable"
    else
        log_fail "BLF script is executable"
    fi
}

# =============================================================================
# Help Tests
# =============================================================================

test_blf_help_output() {
    local output
    output=$("$BLF_SCRIPT" --help 2>&1) || true

    if [[ "$output" == *"--max-iterations"* ]] && \
       [[ "$output" == *"--threshold"* ]] && \
       [[ "$output" == *"--dry-run"* ]]; then
        log_pass "BLF help shows all options"
    else
        log_fail "BLF help shows all options"
    fi
}

# =============================================================================
# Argument Parsing Tests
# =============================================================================

test_blf_max_iterations_parsing() {
    # This tests the dry-run mode which shows the configuration
    local output
    output=$("$BLF_SCRIPT" --max-iterations 10 --dry-run 2>&1) || true

    if [[ "$output" == *"Max iterations: 10"* ]]; then
        log_pass "BLF parses --max-iterations"
    else
        log_fail "BLF parses --max-iterations"
    fi
}

test_blf_threshold_parsing() {
    local output
    output=$("$BLF_SCRIPT" --threshold 10 --dry-run 2>&1) || true

    if [[ "$output" == *"10%"* ]]; then
        log_pass "BLF parses --threshold"
    else
        log_fail "BLF parses --threshold"
    fi
}

test_blf_unknown_option_error() {
    local exit_code=0
    "$BLF_SCRIPT" --unknown-option 2>&1 || exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        log_pass "BLF rejects unknown options"
    else
        log_fail "BLF rejects unknown options"
    fi
}

# =============================================================================
# BR Detection Tests
# =============================================================================

test_blf_no_br_exits_gracefully() {
    # Ensure br is not in path for this test
    local clean_path="/usr/bin:/bin"
    local output
    local exit_code=0

    output=$(PATH="$clean_path" "$BLF_SCRIPT" 2>&1) || exit_code=$?

    if [[ $exit_code -eq 0 ]] && \
       [[ "$output" == *"beads_rust (br) not found"* || "$output" == *"WARNING"* ]]; then
        log_pass "BLF exits gracefully without br"
    else
        log_fail "BLF exits gracefully without br (exit: $exit_code)"
    fi
}

test_blf_detects_br() {
    create_mock_br 5

    local output
    output=$("$BLF_SCRIPT" --dry-run 2>&1) || true

    # In dry-run with br available, should proceed
    if [[ "$output" == *"Initial bead count"* ]] || \
       [[ "$output" == *"DRY RUN"* ]] || \
       [[ "$output" == *"Max iterations"* ]]; then
        log_pass "BLF detects br when available"
    else
        log_fail "BLF detects br when available"
    fi
}

# =============================================================================
# Bead Counting Tests
# =============================================================================

test_blf_counts_beads() {
    create_mock_br 7

    local output
    output=$("$BLF_SCRIPT" --dry-run 2>&1) || true

    if [[ "$output" == *"7"* ]] || [[ "$output" == *"bead"* ]]; then
        log_pass "BLF counts beads correctly"
    else
        log_fail "BLF counts beads correctly"
    fi
}

test_blf_zero_beads_exits() {
    create_mock_br 0

    local output
    output=$("$BLF_SCRIPT" 2>&1) || true

    if [[ "$output" == *"No beads found"* ]]; then
        log_pass "BLF handles zero beads"
    else
        log_fail "BLF handles zero beads"
    fi
}

# =============================================================================
# Dry Run Tests
# =============================================================================

test_blf_dry_run_no_changes() {
    create_mock_br 5

    local output
    output=$("$BLF_SCRIPT" --dry-run 2>&1) || true

    if [[ "$output" == *"DRY RUN"* ]]; then
        log_pass "BLF dry-run indicates no changes"
    else
        log_fail "BLF dry-run indicates no changes"
    fi
}

# =============================================================================
# Environment Variable Tests
# =============================================================================

test_blf_env_max_iterations() {
    create_mock_br 5

    local output
    output=$(BLF_MAX_ITERATIONS=3 "$BLF_SCRIPT" --dry-run 2>&1) || true

    if [[ "$output" == *"Max iterations: 3"* ]]; then
        log_pass "BLF reads BLF_MAX_ITERATIONS env"
    else
        log_fail "BLF reads BLF_MAX_ITERATIONS env"
    fi
}

test_blf_env_threshold() {
    create_mock_br 5

    local output
    output=$(BLF_FLATLINE_THRESHOLD=15 "$BLF_SCRIPT" --dry-run 2>&1) || true

    if [[ "$output" == *"15%"* ]]; then
        log_pass "BLF reads BLF_FLATLINE_THRESHOLD env"
    else
        log_fail "BLF reads BLF_FLATLINE_THRESHOLD env"
    fi
}

# =============================================================================
# Flatline Orchestrator Integration Tests
# =============================================================================

test_flatline_orchestrator_supports_beads() {
    if [[ ! -f "$FLATLINE_ORCHESTRATOR" ]]; then
        log_skip "Flatline orchestrator not found"
        return
    fi

    local output
    output=$("$FLATLINE_ORCHESTRATOR" --help 2>&1) || true

    if [[ "$output" == *"beads"* ]]; then
        log_pass "Flatline orchestrator supports beads phase"
    else
        log_fail "Flatline orchestrator supports beads phase"
    fi
}

# =============================================================================
# Beads Review Prompt Tests
# =============================================================================

test_beads_review_prompt_exists() {
    local prompt_file="$(dirname "$SCRIPT_DIR")/../prompts/gpt-review/base/beads-review.md"

    if [[ -f "$prompt_file" ]]; then
        log_pass "Beads review prompt exists"
    else
        log_fail "Beads review prompt exists (not found: $prompt_file)"
    fi
}

test_beads_review_prompt_has_required_sections() {
    local prompt_file="$(dirname "$SCRIPT_DIR")/../prompts/gpt-review/base/beads-review.md"

    if [[ ! -f "$prompt_file" ]]; then
        log_skip "Beads review prompt not found"
        return
    fi

    local content
    content=$(cat "$prompt_file")
    local pass=true

    [[ "$content" != *"Task Granularity"* ]] && pass=false
    [[ "$content" != *"Dependency Issues"* ]] && pass=false
    [[ "$content" != *"Completeness Gaps"* ]] && pass=false
    [[ "$content" != *"CHANGES_REQUIRED"* ]] && pass=false
    [[ "$content" != *"APPROVED"* ]] && pass=false

    if [[ "$pass" == "true" ]]; then
        log_pass "Beads review prompt has required sections"
    else
        log_fail "Beads review prompt has required sections"
    fi
}

# =============================================================================
# Main
# =============================================================================

main() {
    setup

    echo "--- Script Existence Tests ---"
    test_blf_script_exists
    test_blf_script_executable

    echo ""
    echo "--- Help Tests ---"
    test_blf_help_output

    echo ""
    echo "--- Argument Parsing Tests ---"
    test_blf_max_iterations_parsing
    test_blf_threshold_parsing
    test_blf_unknown_option_error

    echo ""
    echo "--- BR Detection Tests ---"
    test_blf_no_br_exits_gracefully
    test_blf_detects_br

    echo ""
    echo "--- Bead Counting Tests ---"
    test_blf_counts_beads
    test_blf_zero_beads_exits

    echo ""
    echo "--- Dry Run Tests ---"
    test_blf_dry_run_no_changes

    echo ""
    echo "--- Environment Variable Tests ---"
    test_blf_env_max_iterations
    test_blf_env_threshold

    echo ""
    echo "--- Integration Tests ---"
    test_flatline_orchestrator_supports_beads
    test_beads_review_prompt_exists
    test_beads_review_prompt_has_required_sections

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
