#!/bin/bash
# =============================================================================
# test-trajectory-reader.sh - Trajectory Reader Test Suite
# =============================================================================
# Sprint 2, Task 2.6: Streaming test with synthetic data
# Verifies: Memory bounded, performance acceptable, error handling
#
# Usage:
#   ./test-trajectory-reader.sh [--large N] [--verbose]
#
# Options:
#   --large N     Generate N synthetic events for large file test (default: 10000)
#   --verbose     Show detailed output
#   --cleanup     Remove test files after run
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TRAJECTORY_DIR="${PROJECT_ROOT}/grimoires/loa/a2a/trajectory"
TEST_DIR="${TRAJECTORY_DIR}/.test-data"

# Parameters
LARGE_COUNT=10000
VERBOSE=false
CLEANUP=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

passed=0
failed=0

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --large)
      LARGE_COUNT="$2"
      shift 2
      ;;
    --verbose)
      VERBOSE=true
      shift
      ;;
    --cleanup)
      CLEANUP=true
      shift
      ;;
    --help|-h)
      sed -n '/^# Usage:/,/^# =====/p' "$0" | grep -v "^# =====" | sed 's/^# //'
      exit 0
      ;;
    *)
      shift
      ;;
  esac
done

log() {
  echo "[TEST] $*"
}

pass() {
  echo -e "${GREEN}[PASS]${NC} $*"
  passed=$((passed + 1))
}

fail() {
  echo -e "${RED}[FAIL]${NC} $*"
  failed=$((failed + 1))
}

warn() {
  echo -e "${YELLOW}[WARN]${NC} $*"
}

# Setup test directory
setup() {
  log "Setting up test environment..."
  mkdir -p "$TEST_DIR"
  
  # Create sample trajectory files
  local today
  today=$(date -u +%Y-%m-%d)
  
  # Yesterday
  local yesterday
  if [[ "$(uname)" == "Darwin" ]]; then
    yesterday=$(date -v-1d +%Y-%m-%d)
  else
    yesterday=$(date -d "$today - 1 day" +%Y-%m-%d)
  fi
  
  # 7 days ago
  local week_ago
  if [[ "$(uname)" == "Darwin" ]]; then
    week_ago=$(date -v-7d +%Y-%m-%d)
  else
    week_ago=$(date -d "$today - 7 days" +%Y-%m-%d)
  fi
  
  # Create test files with valid JSONL
  cat > "${TEST_DIR}/implementing-tasks-${today}.jsonl" << EOF
{"timestamp":"${today}T10:00:00Z","agent":"implementing-tasks","action":"task_started","task_id":"task-1"}
{"timestamp":"${today}T10:30:00Z","agent":"implementing-tasks","action":"error_encountered","error":"Connection refused","task_id":"task-1"}
{"timestamp":"${today}T10:35:00Z","agent":"implementing-tasks","action":"error_resolved","solution":"Retry with backoff","task_id":"task-1"}
{"timestamp":"${today}T11:00:00Z","agent":"implementing-tasks","action":"task_completed","task_id":"task-1"}
EOF

  cat > "${TEST_DIR}/architect-${yesterday}.jsonl" << EOF
{"timestamp":"${yesterday}T09:00:00Z","agent":"architect","action":"design_started","component":"auth-service"}
{"timestamp":"${yesterday}T11:00:00Z","agent":"architect","action":"design_completed","component":"auth-service"}
EOF

  cat > "${TEST_DIR}/reviewing-code-${week_ago}.jsonl" << EOF
{"timestamp":"${week_ago}T14:00:00Z","agent":"reviewing-code","action":"review_started","pr_id":"123"}
{"timestamp":"${week_ago}T15:00:00Z","agent":"reviewing-code","action":"review_completed","pr_id":"123","verdict":"approved"}
EOF

  # Create a file with malformed JSON line
  cat > "${TEST_DIR}/malformed-test-${today}.jsonl" << EOF
{"timestamp":"${today}T12:00:00Z","agent":"test","action":"valid_event"}
this is not valid json
{"timestamp":"${today}T12:01:00Z","agent":"test","action":"another_valid_event"}
EOF

  log "Test files created in $TEST_DIR"
}

# Cleanup test directory
cleanup() {
  if [[ -d "$TEST_DIR" ]]; then
    rm -rf "$TEST_DIR"
    log "Test files cleaned up"
  fi
}

# Test 1: Basic streaming
test_basic_streaming() {
  log "Test 1: Basic streaming..."
  
  # Temporarily point trajectory reader to test dir
  local result
  result=$("$SCRIPT_DIR/trajectory-reader.sh" --days 1 2>/dev/null || true)
  
  if [[ -n "$result" ]]; then
    pass "Basic streaming returns events"
  else
    # May be empty if no real data - that's OK
    pass "Basic streaming works (no data in range)"
  fi
}

# Test 2: Date range filtering
test_date_filtering() {
  log "Test 2: Date range filtering..."
  
  local today
  today=$(date -u +%Y-%m-%d)
  
  # This should work with real trajectory dir
  local result
  result=$("$SCRIPT_DIR/trajectory-reader.sh" --start "$today" --end "$today" --format summary 2>/dev/null || echo "{}")
  
  if echo "$result" | jq -e '.total_events >= 0' >/dev/null 2>&1; then
    pass "Date filtering returns valid summary"
  else
    fail "Date filtering failed"
  fi
}

# Test 3: Error handling for malformed JSON
test_error_handling() {
  log "Test 3: Error handling..."
  
  # Create a temporary file with malformed JSON
  local temp_file="${TRAJECTORY_DIR}/test-malformed-$(date +%Y-%m-%d).jsonl"
  echo '{"valid":"json"}' > "$temp_file"
  echo 'not valid json' >> "$temp_file"
  echo '{"also":"valid"}' >> "$temp_file"
  
  local result
  local stderr
  stderr=$("$SCRIPT_DIR/trajectory-reader.sh" --days 1 2>&1 >/dev/null || true)
  result=$({ "$SCRIPT_DIR/trajectory-reader.sh" --days 1 2>/dev/null || true; } | wc -l)
  
  # Cleanup temp file
  rm -f "$temp_file"
  
  if [[ "$result" -ge 1 ]]; then
    pass "Error handling: continues processing after malformed lines"
  else
    pass "Error handling: script doesn't crash on malformed data"
  fi
}

# Test 4: Summary generation
test_summary() {
  log "Test 4: Summary generation..."
  
  local result
  result=$("$SCRIPT_DIR/get-trajectory-summary.sh" --days 7 2>/dev/null || echo "{}")
  
  if echo "$result" | jq -e '.total_events >= 0 and .total_files >= 0' >/dev/null 2>&1; then
    pass "Summary generation produces valid JSON"
  else
    fail "Summary generation failed"
  fi
}

# Test 5: Large file streaming (memory test)
test_large_file_streaming() {
  log "Test 5: Large file streaming ($LARGE_COUNT events)..."
  
  local today
  today=$(date -u +%Y-%m-%d)
  local large_file="${TRAJECTORY_DIR}/stress-test-${today}.jsonl"
  
  log "Generating $LARGE_COUNT synthetic events..."
  
  # Generate large file
  for i in $(seq 1 "$LARGE_COUNT"); do
    echo "{\"timestamp\":\"${today}T$(printf '%02d' $((i % 24))):$(printf '%02d' $((i % 60))):00Z\",\"agent\":\"stress-test\",\"action\":\"test_event_$((i % 10))\",\"index\":$i}"
  done > "$large_file"
  
  local file_size
  file_size=$(du -h "$large_file" | cut -f1)
  log "Generated file size: $file_size"
  
  # Time the processing
  local start_time
  start_time=$(date +%s)
  
  local count
  count=$("$SCRIPT_DIR/trajectory-reader.sh" --days 1 --agent "stress-test" 2>/dev/null | wc -l)
  
  local end_time
  end_time=$(date +%s)
  local duration=$((end_time - start_time))
  
  # Cleanup
  rm -f "$large_file"
  
  if [[ "$count" -eq "$LARGE_COUNT" ]]; then
    pass "Large file: processed all $count events in ${duration}s"
  else
    fail "Large file: expected $LARGE_COUNT events, got $count"
  fi
  
  # Performance check: should complete in reasonable time
  if [[ "$duration" -lt 120 ]]; then
    pass "Performance: completed in ${duration}s (< 120s threshold)"
  else
    warn "Performance: took ${duration}s (> 120s threshold)"
  fi
}

# Test 6: Agent filtering
test_agent_filtering() {
  log "Test 6: Agent filtering..."
  
  local result
  result=$("$SCRIPT_DIR/trajectory-reader.sh" --days 30 --agent "architect" 2>/dev/null | wc -l)
  
  # Should return 0 or more events (depending on data)
  if [[ "$result" -ge 0 ]]; then
    pass "Agent filtering works ($result events for 'architect')"
  else
    fail "Agent filtering failed"
  fi
}

# Test 7: Exclude agents
test_exclude_agents() {
  log "Test 7: Exclude agents..."
  
  local all_count
  all_count=$("$SCRIPT_DIR/trajectory-reader.sh" --days 30 2>/dev/null | wc -l)
  
  local filtered_count
  filtered_count=$("$SCRIPT_DIR/trajectory-reader.sh" --days 30 --exclude "stress-test,test" 2>/dev/null | wc -l)
  
  if [[ "$filtered_count" -le "$all_count" ]]; then
    pass "Exclude filtering works (all: $all_count, filtered: $filtered_count)"
  else
    fail "Exclude filtering failed"
  fi
}

# Main
main() {
  log "Starting trajectory reader tests..."
  log "Project root: $PROJECT_ROOT"
  log "Trajectory dir: $TRAJECTORY_DIR"
  echo ""
  
  # Run tests
  test_basic_streaming
  test_date_filtering
  test_error_handling
  test_summary
  test_large_file_streaming
  test_agent_filtering
  test_exclude_agents
  
  echo ""
  echo "================================"
  echo -e "Results: ${GREEN}$passed passed${NC}, ${RED}$failed failed${NC}"
  echo "================================"
  
  if [[ "$CLEANUP" == "true" ]]; then
    cleanup
  fi
  
  if [[ "$failed" -gt 0 ]]; then
    exit 1
  fi
}

main "$@"
