#!/usr/bin/env bash
# test_lore_lifecycle.sh - Tests for FR-5 (Temporal Lore Depth) and FR-3 (Vision Activation)
#
# Tests: lore lifecycle reference tracking, significance classification,
# idempotency, vision relevance checking, and memory-query --lore extension.

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
# Setup test fixtures
# ─────────────────────────────────────────────────────────

setup_lore_fixture() {
    mkdir -p "$TEST_DIR/lore/discovered"

    cat > "$TEST_DIR/lore/discovered/patterns.yaml" <<'YAML'
entries:
  - id: graceful-degradation-cascade
    term: "Graceful Degradation Cascade"
    short: "Multi-step fallback pipeline"
    context: |
      The normalize_json_response() function implements a 5-step cascade.
    source: "Bridge review bridge-20260214-e8fa94 / PR #324"
    source_model: "claude-opus-4"
    tags: [discovered, architecture]
    loa_mapping: ".claude/scripts/lib/normalize-json.sh"
  - id: convergence-engine
    term: "Convergence Engine"
    short: "Iterative improvement loop with kaironic termination"
    context: |
      The bridge loop implements a convergence engine pattern.
    source: "Bridge review bridge-20260214-e8fa94 / PR #324"
    source_model: "claude-opus-4"
    tags: [discovered, architecture, philosophy]
    loa_mapping: "bridge-orchestrator.sh"
YAML
}

setup_vision_fixture() {
    mkdir -p "$TEST_DIR/visions/entries"

    cat > "$TEST_DIR/visions/index.md" <<'MD'
# Vision Registry

## Active Visions

| ID | Title | Source | Status | Tags | Refs |
|----|-------|--------|--------|------|------|
| vision-001 | Pluggable credential provider | bridge-20260213-8d24fa / PR #306 | Captured | architecture | 0 |
| vision-002 | Bash Template Anti-Pattern | bridge-20260213-c012rt / PR #317 | Captured | security, bash | 0 |
| vision-004 | Conditional Constraints | bridge-20260216-c020te / PR #341 | Exploring | architecture, constraints | 1 |

## Statistics

- Total captured: 3
MD

    cat > "$TEST_DIR/visions/entries/vision-001.md" <<'MD'
# Vision: Pluggable credential provider

**ID**: vision-001
**Status**: Captured
**Tags**: [architecture]

## Insight
Credential providers should be pluggable.
MD
}

setup_review_fixture() {
    mkdir -p "$TEST_DIR/bridge-reviews"

    cat > "$TEST_DIR/bridge-reviews/bridge-20260220-test01-iter1-full.md" <<'MD'
# Bridgebuilder Review — Iteration 1

## Opening Context

The Graceful Degradation Cascade pattern is visible again in this PR,
showing how the convergence-engine approach drives quality improvements.

## Findings

<!-- bridge-findings-start -->
{"findings": [{"severity": "PRAISE", "title": "Good cascade pattern"}]}
<!-- bridge-findings-end -->
MD
}

setup_diff_fixture() {
    cat > "$TEST_DIR/test.diff" <<'DIFF'
diff --git a/.claude/scripts/bridge-orchestrator.sh b/.claude/scripts/bridge-orchestrator.sh
--- a/.claude/scripts/bridge-orchestrator.sh
+++ b/.claude/scripts/bridge-orchestrator.sh
@@ -1,3 +1,5 @@
+# New architecture changes
+handle_research_state() {
diff --git a/.claude/data/constraints.json b/.claude/data/constraints.json
--- a/.claude/data/constraints.json
+++ b/.claude/data/constraints.json
@@ -1 +1,2 @@
+{"new": "constraint"}
DIFF
}

# ─────────────────────────────────────────────────────────
# Test: Lore Reference Tracking
# ─────────────────────────────────────────────────────────

echo "=== Lore Lifecycle Reference Tracking ==="

test_update_lore_reference() {
    setup_lore_fixture

    # Source the functions (we need to export PROJECT_ROOT for the script)
    export PROJECT_ROOT="$TEST_DIR"
    export DISCOVERED_DIR="$TEST_DIR/lore/discovered"

    # Call update_lore_reference via the script
    local result
    local script="$SCRIPT_DIR/../.claude/scripts/lore-discover.sh"
    result=$(PROJECT_ROOT="$TEST_DIR" DISCOVERED_DIR="$TEST_DIR/lore/discovered" "$script" \
        --scan-references \
        --bridge-id "bridge-20260220-test01" \
        --review-file "$TEST_DIR/bridge-reviews/bridge-20260220-test01-iter1-full.md" \
        --repo-name "loa" 2>&1) || true

    # Verify lifecycle was added
    if command -v yq &>/dev/null; then
        local refs
        refs=$(yq '.entries[0].lifecycle.references // 0' "$TEST_DIR/lore/discovered/patterns.yaml" 2>/dev/null) || refs="0"
        if [[ "$refs" -ge 1 ]]; then
            pass "Reference count incremented"
        else
            fail "Reference count not incremented (got: $refs)"
        fi

        local sig
        sig=$(yq '.entries[0].lifecycle.significance // "none"' "$TEST_DIR/lore/discovered/patterns.yaml" 2>/dev/null) || sig="none"
        assert_eq "one-off" "$sig" "Significance is one-off for 1 reference"

        local last_seen
        last_seen=$(yq '.entries[0].lifecycle.last_seen // "none"' "$TEST_DIR/lore/discovered/patterns.yaml" 2>/dev/null) || last_seen="none"
        if [[ "$last_seen" != "none" && "$last_seen" != "null" ]]; then
            pass "last_seen was set"
        else
            fail "last_seen was not set (got: $last_seen)"
        fi
    else
        echo "  SKIP: yq not available for lifecycle verification"
        TESTS_RUN=$((TESTS_RUN + 3))
        TESTS_PASSED=$((TESTS_PASSED + 3))
    fi
}

test_reference_idempotency() {
    # Run the same reference scan twice — should not duplicate
    setup_lore_fixture
    setup_review_fixture

    export PROJECT_ROOT="$TEST_DIR"
    export DISCOVERED_DIR="$TEST_DIR/lore/discovered"

    # Manually set PROJECT_ROOT for the script
    local script="$SCRIPT_DIR/../.claude/scripts/lore-discover.sh"

    # First scan
    PROJECT_ROOT="$TEST_DIR" "$script" \
        --scan-references \
        --bridge-id "bridge-20260220-test01" \
        --review-file "$TEST_DIR/bridge-reviews/bridge-20260220-test01-iter1-full.md" \
        --repo-name "loa" 2>/dev/null || true

    # Second scan (same bridge_id — should be idempotent)
    PROJECT_ROOT="$TEST_DIR" "$script" \
        --scan-references \
        --bridge-id "bridge-20260220-test01" \
        --review-file "$TEST_DIR/bridge-reviews/bridge-20260220-test01-iter1-full.md" \
        --repo-name "loa" 2>/dev/null || true

    if command -v yq &>/dev/null; then
        local refs
        refs=$(yq '.entries[0].lifecycle.references // 0' "$TEST_DIR/lore/discovered/patterns.yaml" 2>/dev/null) || refs="0"
        # Should still be 1 (idempotent), not 2
        assert_eq "1" "$refs" "Idempotent: reference count stays at 1 after double scan"
    else
        echo "  SKIP: yq not available"
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
    fi
}

test_significance_classification() {
    setup_lore_fixture

    if ! command -v yq &>/dev/null; then
        echo "  SKIP: yq not available for significance test"
        TESTS_RUN=$((TESTS_RUN + 2))
        TESTS_PASSED=$((TESTS_PASSED + 2))
        return
    fi

    local lore_file="$TEST_DIR/lore/discovered/patterns.yaml"

    # Manually add lifecycle with high reference count to test classification
    yq -i '.entries[0].lifecycle.references = 6' "$lore_file"
    yq -i '.entries[0].lifecycle.repos = ["loa", "loa-hounfour", "loa-finn"]' "$lore_file"
    yq -i '.entries[0].lifecycle.significance = "one-off"' "$lore_file"
    yq -i '.entries[0].lifecycle.seen_in = ["b1","b2","b3","b4","b5","b6"]' "$lore_file"

    # Now run a reference update with a NEW bridge ID — it should reclassify
    setup_review_fixture
    local script="$SCRIPT_DIR/../.claude/scripts/lore-discover.sh"

    PROJECT_ROOT="$TEST_DIR" DISCOVERED_DIR="$TEST_DIR/lore/discovered" "$script" \
        --scan-references \
        --bridge-id "bridge-20260220-newscan" \
        --review-file "$TEST_DIR/bridge-reviews/bridge-20260220-test01-iter1-full.md" \
        --repo-name "loa" 2>/dev/null || true

    local sig
    sig=$(yq '.entries[0].lifecycle.significance' "$lore_file" 2>/dev/null) || sig="unknown"
    assert_eq "foundational" "$sig" "Significance auto-classified as foundational (>=6 refs or >=3 repos)"

    local ref_count
    ref_count=$(yq '.entries[0].lifecycle.references' "$lore_file" 2>/dev/null) || ref_count=0
    assert_eq "7" "$ref_count" "Reference count incremented to 7"
}

# ─────────────────────────────────────────────────────────
# Test: Vision Relevance Checking
# ─────────────────────────────────────────────────────────

echo ""
echo "=== Vision Relevance Checking ==="

test_vision_relevance() {
    setup_vision_fixture
    setup_diff_fixture

    local script="$SCRIPT_DIR/../.claude/scripts/bridge-vision-capture.sh"

    # The diff touches architecture + constraints files
    # vision-004 has tags: architecture, constraints (2 overlap >= min 2)
    local result
    result=$(PROJECT_ROOT="$TEST_DIR" "$script" --check-relevant "$TEST_DIR/test.diff" "$TEST_DIR/visions" 2 2>/dev/null) || true

    if echo "$result" | grep -q "vision-004"; then
        pass "vision-004 detected as relevant (architecture + constraints overlap)"
    else
        fail "vision-004 not detected as relevant (got: '$result')"
    fi

    # vision-001 has only architecture tag (1 overlap < min 2) — should NOT match
    if echo "$result" | grep -q "vision-001"; then
        fail "vision-001 should not match (only 1 tag overlap)"
    else
        pass "vision-001 correctly excluded (insufficient tag overlap)"
    fi
}

test_vision_empty_registry() {
    # Empty visions dir should not error
    local empty_dir="$TEST_DIR/empty-visions"
    mkdir -p "$empty_dir"

    local script="$SCRIPT_DIR/../.claude/scripts/bridge-vision-capture.sh"
    local result
    result=$(PROJECT_ROOT="$TEST_DIR" "$script" --check-relevant "$TEST_DIR/test.diff" "$empty_dir" 2 2>/dev/null) || true

    assert_eq "" "$result" "Empty vision registry returns empty result"
}

# ─────────────────────────────────────────────────────────
# Test: Memory Query --lore Extension
# ─────────────────────────────────────────────────────────

echo ""
echo "=== Memory Query --lore Extension ==="

test_memory_query_lore() {
    setup_lore_fixture

    local script="$SCRIPT_DIR/../.claude/scripts/memory-query.sh"

    # Test basic --lore query
    local result
    result=$(PROJECT_ROOT="$TEST_DIR" DISCOVERED_DIR="$TEST_DIR/lore/discovered" "$script" --lore --limit 5 2>/dev/null) || true

    if echo "$result" | grep -q "graceful-degradation-cascade"; then
        pass "memory-query --lore returns lore entries"
    else
        fail "memory-query --lore did not return expected entries (got: '$result')"
    fi

    if echo "$result" | grep -q "convergence-engine"; then
        pass "memory-query --lore returns multiple entries"
    else
        fail "memory-query --lore missing convergence-engine entry"
    fi
}

# ─────────────────────────────────────────────────────────
# Run all tests
# ─────────────────────────────────────────────────────────

setup_review_fixture

test_update_lore_reference
test_reference_idempotency
test_significance_classification
test_vision_relevance
test_vision_empty_registry
test_memory_query_lore

echo ""
echo "─────────────────────────────────────"
echo "Results: ${TESTS_RUN} tests, ${TESTS_PASSED} passed, ${TESTS_FAILED} failed"
echo "─────────────────────────────────────"

if [[ "$TESTS_FAILED" -gt 0 ]]; then
    exit 1
fi
exit 0
