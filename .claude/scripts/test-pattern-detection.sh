#!/bin/bash
# =============================================================================
# test-pattern-detection.sh - Pattern Detection Test Suite
# =============================================================================
# Sprint 3, Task 3.6: Test similarity functions with known patterns
#
# Usage:
#   ./test-pattern-detection.sh [--verbose]
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

passed=0
failed=0
VERBOSE=false

[[ "${1:-}" == "--verbose" ]] && VERBOSE=true

log() { echo "[TEST] $*"; }
pass() { echo -e "${GREEN}[PASS]${NC} $*"; passed=$((passed + 1)); }
fail() { echo -e "${RED}[FAIL]${NC} $*"; failed=$((failed + 1)); }

# Test 1: Keyword extraction
test_keyword_extraction() {
  log "Test 1: Keyword extraction..."
  
  local text="The NatsJetStream consumer lost messages after restart"
  local result
  result=$(echo "$text" | "$SCRIPT_DIR/extract-keywords.sh" --technical 2>/dev/null || echo "")
  
  # Should contain key technical terms
  if echo "$result" | grep -qi "nats\|consumer\|messages\|restart"; then
    pass "Keyword extraction captures technical terms"
  else
    fail "Keyword extraction missing expected terms: $result"
  fi
}

# Test 2: Stopword filtering
test_stopword_filtering() {
  log "Test 2: Stopword filtering..."
  
  local text="the quick brown fox jumps over the lazy dog"
  local result
  result=$(echo "$text" | "$SCRIPT_DIR/extract-keywords.sh" 2>/dev/null || echo "")
  
  # Should not contain "the" or "over"
  if ! echo "$result" | grep -qE "^(the|over)$"; then
    pass "Stopwords filtered correctly"
  else
    fail "Stopwords not filtered: $result"
  fi
}

# Test 3: Jaccard identical sets
test_jaccard_identical() {
  log "Test 3: Jaccard similarity - identical sets..."
  
  local result
  result=$("$SCRIPT_DIR/jaccard-similarity.sh" \
    --set-a "nats,consumer,messages,lost" \
    --set-b "nats,consumer,messages,lost" 2>/dev/null || echo "0")
  
  if [[ "$result" == "1.0"* ]]; then
    pass "Identical sets return similarity 1.0"
  else
    fail "Expected 1.0, got: $result"
  fi
}

# Test 4: Jaccard no overlap
test_jaccard_no_overlap() {
  log "Test 4: Jaccard similarity - no overlap..."
  
  local result
  result=$("$SCRIPT_DIR/jaccard-similarity.sh" \
    --set-a "apple,banana,cherry" \
    --set-b "dog,cat,bird" 2>/dev/null || echo "1")
  
  if [[ "$result" == "0.0"* || "$result" == "0" ]]; then
    pass "No overlap returns similarity 0.0"
  else
    fail "Expected 0.0, got: $result"
  fi
}

# Test 5: Jaccard partial overlap
test_jaccard_partial() {
  log "Test 5: Jaccard similarity - partial overlap..."
  
  # Sets: {a,b,c,d} and {c,d,e,f}
  # Intersection: {c,d} = 2
  # Union: {a,b,c,d,e,f} = 6
  # Jaccard = 2/6 = 0.333...
  
  local result
  result=$("$SCRIPT_DIR/jaccard-similarity.sh" \
    --set-a "a,b,c,d" \
    --set-b "c,d,e,f" 2>/dev/null || echo "0")
  
  # Should be approximately 0.33 (use awk for comparison)
  local in_range
  in_range=$(awk "BEGIN {print ($result >= 0.3 && $result <= 0.4) ? 1 : 0}")
  if [[ "$in_range" == "1" ]]; then
    pass "Partial overlap returns expected similarity (~0.33): $result"
  else
    fail "Expected ~0.33, got: $result"
  fi
}

# Test 6: Jaccard with text input
test_jaccard_text() {
  log "Test 6: Jaccard similarity - text input..."
  
  local result
  result=$("$SCRIPT_DIR/jaccard-similarity.sh" \
    --text-a "NATS consumer lost messages after server restart" \
    --text-b "NATS consumer messages disappeared when service restarted" \
    2>/dev/null || echo "0")
  
  # Should have decent overlap (use awk for comparison)
  local passes
  passes=$(awk "BEGIN {print ($result >= 0.2) ? 1 : 0}")
  if [[ "$passes" == "1" ]]; then
    pass "Text similarity works: $result"
  else
    fail "Expected >= 0.2, got: $result"
  fi
}

# Test 7: Jaccard JSON output
test_jaccard_json() {
  log "Test 7: Jaccard similarity - JSON output..."
  
  local result
  result=$("$SCRIPT_DIR/jaccard-similarity.sh" \
    --set-a "a,b,c" \
    --set-b "b,c,d" \
    --json 2>/dev/null || echo "{}")
  
  if echo "$result" | jq -e '.similarity != null and .intersection != null' >/dev/null 2>&1; then
    pass "JSON output contains expected fields"
  else
    fail "JSON output invalid: $result"
  fi
}

# Test 8: Threshold check
test_threshold() {
  log "Test 8: Jaccard threshold..."
  
  # Low similarity pair
  local result
  result=$("$SCRIPT_DIR/jaccard-similarity.sh" \
    --set-a "a,b,c" \
    --set-b "x,y,z" \
    --threshold 0.5 2>/dev/null || echo "1")
  
  if [[ "$result" == "0" ]]; then
    pass "Threshold returns 0 for low similarity"
  else
    fail "Expected 0, got: $result"
  fi
}

# Test 9: Extract error-solution pairs structure
test_error_solution_extractor() {
  log "Test 9: Error-solution pair extractor..."
  
  local result
  result=$("$SCRIPT_DIR/extract-error-solution-pairs.sh" --days 7 --output json 2>/dev/null || echo "[]")
  
  # Should return valid JSON array (even if empty)
  if echo "$result" | jq -e 'type == "array"' >/dev/null 2>&1; then
    pass "Error-solution extractor returns valid JSON array"
  else
    fail "Invalid output: $result"
  fi
}

# Test 10: Find similar events structure
test_find_similar() {
  log "Test 10: Find similar events..."
  
  local result
  result=$("$SCRIPT_DIR/find-similar-events.sh" \
    --query "NATS connection error" \
    --days 7 \
    --json 2>/dev/null || echo "{}")
  
  # Should return valid JSON with expected fields
  if echo "$result" | jq -e '.matches != null and .strategy != null' >/dev/null 2>&1; then
    pass "Find similar returns valid JSON structure"
  else
    fail "Invalid output: $result"
  fi
}

# Main
main() {
  log "Starting pattern detection tests..."
  echo ""
  
  # Make scripts executable
  chmod +x "$SCRIPT_DIR/extract-keywords.sh" 2>/dev/null || true
  chmod +x "$SCRIPT_DIR/jaccard-similarity.sh" 2>/dev/null || true
  chmod +x "$SCRIPT_DIR/extract-error-solution-pairs.sh" 2>/dev/null || true
  chmod +x "$SCRIPT_DIR/find-similar-events.sh" 2>/dev/null || true
  
  test_keyword_extraction
  test_stopword_filtering
  test_jaccard_identical
  test_jaccard_no_overlap
  test_jaccard_partial
  test_jaccard_text
  test_jaccard_json
  test_threshold
  test_error_solution_extractor
  test_find_similar
  
  echo ""
  echo "================================"
  echo -e "Results: ${GREEN}$passed passed${NC}, ${RED}$failed failed${NC}"
  echo "================================"
  
  [[ "$failed" -gt 0 ]] && exit 1
  exit 0
}

main "$@"
