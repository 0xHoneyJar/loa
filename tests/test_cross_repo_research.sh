#!/usr/bin/env bash
# test_cross_repo_research.sh - Tests for FR-1 (Cross-Repo Query) and FR-2 (Research Mode)
#
# Tests: pattern extraction, repo resolution, cross-repo query, research mode
# state transitions, flatline score exclusion.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Temp directory for test fixtures
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

pass() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    TESTS_RUN=$((TESTS_RUN + 1))
    echo "  PASS: $1"
}

fail() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    TESTS_RUN=$((TESTS_RUN + 1))
    echo "  FAIL: $1"
}

assert_eq() {
    local expected="$1"
    local actual="$2"
    local msg="$3"
    if [[ "$expected" == "$actual" ]]; then
        pass "$msg"
    else
        fail "$msg (expected: '$expected', got: '$actual')"
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local msg="$3"
    if echo "$haystack" | grep -qF "$needle" 2>/dev/null; then
        pass "$msg"
    else
        fail "$msg (expected to contain: '$needle')"
    fi
}

# ─────────────────────────────────────────────────────────
# Test Fixtures
# ─────────────────────────────────────────────────────────

setup_diff_fixture() {
    cat > "$TEST_DIR/test.diff" <<'DIFF'
diff --git a/.claude/scripts/bridge-orchestrator.sh b/.claude/scripts/bridge-orchestrator.sh
--- a/.claude/scripts/bridge-orchestrator.sh
+++ b/.claude/scripts/bridge-orchestrator.sh
@@ -1,3 +1,10 @@
+function handle_convergence() {
+  local cascade_depth=$1
+  apply_middleware "$cascade_depth"
+}
+function validate_constraint() {
+  check_invariant "$1"
+}
diff --git a/.claude/data/constraints.json b/.claude/data/constraints.json
--- a/.claude/data/constraints.json
+++ b/.claude/data/constraints.json
@@ -1 +1,2 @@
+{"new": "constraint"}
DIFF
}

setup_sibling_repo_fixture() {
    # Create a fake sibling repo with BUTTERFREEZONE.md
    local sibling="$TEST_DIR/sibling-repo"
    mkdir -p "$sibling/grimoires"

    cat > "$sibling/BUTTERFREEZONE.md" <<'MD'
# BUTTERFREEZONE — sibling-repo

<!-- AGENT-CONTEXT -->
## Architecture
The convergence engine pattern drives quality improvements.
The cascade middleware handles multi-step fallback.
<!-- /AGENT-CONTEXT -->
MD

    cat > "$sibling/.loa.config.yaml" <<'YAML'
run_mode:
  enabled: true
YAML

    echo "$sibling"
}

setup_bridge_state_fixture() {
    mkdir -p "$TEST_DIR/.run"
    cat > "$TEST_DIR/.run/bridge-state.json" <<'JSON'
{
  "schema_version": 1,
  "bridge_id": "bridge-20260220-test01",
  "state": "ITERATING",
  "config": {
    "depth": 3,
    "mode": "full",
    "flatline_threshold": 0.05,
    "per_sprint": false,
    "branch": "feat/test",
    "repo": ""
  },
  "pr": 999,
  "timestamps": {
    "started": "2026-02-20T10:00:00Z",
    "last_activity": "2026-02-20T10:00:00Z"
  },
  "iterations": [
    {"iteration": 1, "status": "completed", "source": "existing"}
  ],
  "flatline": {
    "initial_score": 5,
    "last_score": 3,
    "consecutive_below_threshold": 0
  },
  "metrics": {
    "total_sprints_executed": 1,
    "total_files_changed": 10,
    "total_findings_addressed": 3,
    "total_visions_captured": 0,
    "research_iterations_completed": 0
  }
}
JSON
}

# ─────────────────────────────────────────────────────────
# Test: Pattern Extraction (Task 5.1)
# ─────────────────────────────────────────────────────────

echo "=== Cross-Repo Pattern Extraction ==="

test_pattern_extraction() {
    setup_diff_fixture

    local script="$SCRIPT_DIR/../.claude/scripts/cross-repo-query.sh"

    # Run with diff, expect JSON output
    local result
    result=$(PROJECT_ROOT="$TEST_DIR" "$script" --diff "$TEST_DIR/test.diff" 2>/dev/null) || true

    if [[ -n "$result" ]]; then
        # Check it's valid JSON
        if echo "$result" | jq . >/dev/null 2>&1; then
            pass "cross-repo-query returns valid JSON"
        else
            fail "cross-repo-query did not return valid JSON (got: '$result')"
        fi

        # Check structure
        local repos_queried
        repos_queried=$(echo "$result" | jq '.repos_queried // -1') || repos_queried=-1
        if [[ "$repos_queried" -ge 0 ]]; then
            pass "JSON has repos_queried field"
        else
            fail "Missing repos_queried field"
        fi

        local patterns
        patterns=$(echo "$result" | jq '.patterns_extracted // 0') || patterns=0
        if [[ "$patterns" -gt 0 ]]; then
            pass "Patterns extracted from diff ($patterns found)"
        else
            fail "No patterns extracted from diff"
        fi
    else
        fail "cross-repo-query returned empty result"
    fi
}

test_empty_diff() {
    local empty_diff="$TEST_DIR/empty.diff"
    touch "$empty_diff"

    local script="$SCRIPT_DIR/../.claude/scripts/cross-repo-query.sh"
    local result
    result=$(PROJECT_ROOT="$TEST_DIR" "$script" --diff "$empty_diff" 2>/dev/null) || true

    if echo "$result" | jq -e '.repos_queried == 0' >/dev/null 2>&1; then
        pass "Empty diff returns zero repos queried"
    else
        fail "Empty diff should return repos_queried=0 (got: '$result')"
    fi
}

# ─────────────────────────────────────────────────────────
# Test: Repo Resolution (Task 5.1)
# ─────────────────────────────────────────────────────────

echo ""
echo "=== Repo Resolution ==="

test_sibling_repo_resolution() {
    setup_diff_fixture
    local sibling
    sibling=$(setup_sibling_repo_fixture)

    local script="$SCRIPT_DIR/../.claude/scripts/cross-repo-query.sh"

    # Run from a directory whose parent contains the sibling
    local result
    result=$(PROJECT_ROOT="$TEST_DIR" "$script" \
        --diff "$TEST_DIR/test.diff" \
        --ecosystem "$sibling" 2>/dev/null) || true

    if echo "$result" | jq -e '.repos_queried >= 1' >/dev/null 2>&1; then
        pass "Sibling repo discovered and queried"
    else
        fail "Sibling repo not queried (got: '$result')"
    fi
}

test_ecosystem_override() {
    setup_diff_fixture

    local script="$SCRIPT_DIR/../.claude/scripts/cross-repo-query.sh"
    local result
    result=$(PROJECT_ROOT="$TEST_DIR" "$script" \
        --diff "$TEST_DIR/test.diff" \
        --ecosystem "/nonexistent/path" 2>/dev/null) || true

    # Should warn but not error
    if echo "$result" | jq -e '.repos_queried == 0' >/dev/null 2>&1; then
        pass "Nonexistent ecosystem path returns 0 repos (graceful)"
    else
        fail "Expected graceful handling of nonexistent path"
    fi
}

# ─────────────────────────────────────────────────────────
# Test: Research Mode State (Task 5.3)
# ─────────────────────────────────────────────────────────

echo ""
echo "=== Research Mode State Transitions ==="

test_research_state_transitions() {
    # Source bridge-state.sh and test RESEARCHING is a valid transition
    local state_script="$SCRIPT_DIR/../.claude/scripts/bridge-state.sh"

    # Check that RESEARCHING is in valid transitions from ITERATING
    local transitions
    transitions=$(grep '\["ITERATING"\]' "$state_script" | head -1)

    if echo "$transitions" | grep -q "RESEARCHING"; then
        pass "RESEARCHING is valid transition from ITERATING"
    else
        fail "RESEARCHING not found in ITERATING transitions"
    fi

    # Check RESEARCHING -> ITERATING is valid
    transitions=$(grep 'RESEARCHING' "$state_script" | head -1)
    if echo "$transitions" | grep -q "ITERATING"; then
        pass "ITERATING is valid transition from RESEARCHING"
    else
        fail "ITERATING not found in RESEARCHING transitions"
    fi
}

test_research_state_in_bridge_orchestrator() {
    local orch_script="$SCRIPT_DIR/../.claude/scripts/bridge-orchestrator.sh"

    # Check RESEARCHING state is referenced in orchestrator
    if grep -q "RESEARCHING" "$orch_script" 2>/dev/null; then
        pass "RESEARCHING state used in bridge-orchestrator.sh"
    else
        fail "RESEARCHING state not found in bridge-orchestrator.sh"
    fi

    # Check SIGNAL:RESEARCH_ITERATION
    if grep -q "SIGNAL:RESEARCH_ITERATION" "$orch_script" 2>/dev/null; then
        pass "SIGNAL:RESEARCH_ITERATION emitted in bridge-orchestrator.sh"
    else
        fail "SIGNAL:RESEARCH_ITERATION not found in bridge-orchestrator.sh"
    fi
}

test_cross_repo_signal_in_orchestrator() {
    local orch_script="$SCRIPT_DIR/../.claude/scripts/bridge-orchestrator.sh"

    if grep -q "SIGNAL:CROSS_REPO_QUERY" "$orch_script" 2>/dev/null; then
        pass "SIGNAL:CROSS_REPO_QUERY emitted in bridge-orchestrator.sh"
    else
        fail "SIGNAL:CROSS_REPO_QUERY not found in bridge-orchestrator.sh"
    fi
}

test_lore_reference_scan_signal() {
    local orch_script="$SCRIPT_DIR/../.claude/scripts/bridge-orchestrator.sh"

    if grep -q "SIGNAL:LORE_REFERENCE_SCAN" "$orch_script" 2>/dev/null; then
        pass "SIGNAL:LORE_REFERENCE_SCAN emitted in bridge-orchestrator.sh"
    else
        fail "SIGNAL:LORE_REFERENCE_SCAN not found in bridge-orchestrator.sh"
    fi
}

test_vision_check_signal() {
    local orch_script="$SCRIPT_DIR/../.claude/scripts/bridge-orchestrator.sh"

    if grep -q "SIGNAL:VISION_CHECK" "$orch_script" 2>/dev/null; then
        pass "SIGNAL:VISION_CHECK emitted in bridge-orchestrator.sh"
    else
        fail "SIGNAL:VISION_CHECK not found in bridge-orchestrator.sh"
    fi
}

# ─────────────────────────────────────────────────────────
# Test: Config Schema (Task 5.5)
# ─────────────────────────────────────────────────────────

echo ""
echo "=== Config Schema ==="

test_config_cross_repo() {
    local config="$SCRIPT_DIR/../.loa.config.yaml.example"

    if grep -q "cross_repo_query:" "$config" 2>/dev/null; then
        pass "cross_repo_query config section exists"
    else
        fail "cross_repo_query config section missing"
    fi

    if grep -q "max_repos:" "$config" 2>/dev/null; then
        pass "max_repos config key exists"
    else
        fail "max_repos config key missing"
    fi
}

test_config_research_mode() {
    local config="$SCRIPT_DIR/../.loa.config.yaml.example"

    if grep -q "research_mode:" "$config" 2>/dev/null; then
        pass "research_mode config section exists"
    else
        fail "research_mode config section missing"
    fi

    if grep -q "trigger_after_iteration:" "$config" 2>/dev/null; then
        pass "trigger_after_iteration config key exists"
    else
        fail "trigger_after_iteration config key missing"
    fi

    if grep -q "max_research_iterations:" "$config" 2>/dev/null; then
        pass "max_research_iterations config key exists"
    else
        fail "max_research_iterations config key missing"
    fi
}

# ─────────────────────────────────────────────────────────
# Test: Research Mode Trigger Semantics (BB-8ab2ce medium-1)
# ─────────────────────────────────────────────────────────

echo ""
echo "=== Research Mode Trigger Semantics ==="

test_research_trigger_inclusive() {
    # The guard should use -ge (inclusive) so trigger_after_iteration=1
    # means "fire after iteration 1 completes" (when iteration == 1)
    local orch_script="$SCRIPT_DIR/../.claude/scripts/bridge-orchestrator.sh"

    # Check for -ge (inclusive) not -gt (exclusive)
    if grep -q '\-ge \$research_trigger_after' "$orch_script" 2>/dev/null; then
        pass "Research mode trigger uses -ge (inclusive semantics)"
    else
        fail "Research mode trigger should use -ge, not -gt"
    fi

    # Check for inline documentation comment
    if grep -q 'trigger_after_iteration=N means' "$orch_script" 2>/dev/null; then
        pass "Research mode trigger has semantic documentation comment"
    else
        fail "Research mode trigger missing semantic documentation"
    fi
}

# ─────────────────────────────────────────────────────────
# Test: Cross-Repo Stop-Words Filtering (BB-8ab2ce medium-2)
# ─────────────────────────────────────────────────────────

echo ""
echo "=== Cross-Repo Stop-Words Filtering ==="

test_pattern_noise_filtering() {
    local query_script="$SCRIPT_DIR/../.claude/scripts/cross-repo-query.sh"

    # Verify stop-words list exists in the script
    if grep -q 'stop_words=' "$query_script" 2>/dev/null; then
        pass "Stop-words list defined in cross-repo-query.sh"
    else
        fail "Stop-words list not found in cross-repo-query.sh"
    fi

    # Verify minimum length filtering (4 chars)
    if grep -q 'lt 4' "$query_script" 2>/dev/null; then
        pass "Minimum pattern length filter (4 chars) present"
    else
        fail "Minimum pattern length filter not found"
    fi

    # Create a diff with short and stop-word patterns
    local test_diff="$TEST_DIR/noise-test.diff"
    cat > "$test_diff" << 'DIFF'
diff --git a/src/run.sh b/src/run.sh
+function init() {
+function get() {
+function set() {
+function orchestrate_bridge_query() {
+function validate_constraint_pipeline() {
DIFF

    # Source only the extract_patterns function for testing
    local extracted
    extracted=$(bash -c "
        source '$query_script' 2>/dev/null
        extract_patterns '$test_diff'
    " 2>/dev/null) || extracted=""

    # Check that short/stop patterns are filtered
    if echo "$extracted" | grep -qx "init" 2>/dev/null; then
        fail "Stop-word 'init' should be filtered"
    else
        pass "Stop-word 'init' correctly filtered"
    fi

    if echo "$extracted" | grep -qx "get" 2>/dev/null; then
        fail "Short pattern 'get' should be filtered"
    else
        pass "Short pattern 'get' correctly filtered"
    fi
}

# ─────────────────────────────────────────────────────────
# Test: Config Profiles (BB-8ab2ce medium-3)
# ─────────────────────────────────────────────────────────

echo ""
echo "=== Config Profile Documentation ==="

test_config_profiles() {
    local config="$SCRIPT_DIR/../.loa.config.yaml.example"

    if grep -q "Quick Start Profiles" "$config" 2>/dev/null; then
        pass "Quick Start Profiles documented in config"
    else
        fail "Quick Start Profiles not found in config"
    fi

    if grep -q "activation_enabled:" "$config" 2>/dev/null; then
        pass "vision_registry.activation_enabled config key present"
    else
        fail "vision_registry.activation_enabled config key missing"
    fi
}

# ─────────────────────────────────────────────────────────
# Run all tests
# ─────────────────────────────────────────────────────────

test_pattern_extraction
test_empty_diff
test_sibling_repo_resolution
test_ecosystem_override
test_research_state_transitions
test_research_state_in_bridge_orchestrator
test_cross_repo_signal_in_orchestrator
test_lore_reference_scan_signal
test_vision_check_signal
test_config_cross_repo
test_config_research_mode
test_research_trigger_inclusive
test_pattern_noise_filtering
test_config_profiles

echo ""
echo "─────────────────────────────────────"
echo "Results: ${TESTS_RUN} tests, ${TESTS_PASSED} passed, ${TESTS_FAILED} failed"
echo "─────────────────────────────────────"

if [[ "$TESTS_FAILED" -gt 0 ]]; then
    exit 1
fi
exit 0
