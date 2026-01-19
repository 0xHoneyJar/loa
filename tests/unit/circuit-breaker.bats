#!/usr/bin/env bats

# Unit tests for Run Mode Circuit Breaker
# Tests the circuit breaker trigger conditions and state transitions
#
# Test coverage:
#   - Same issue threshold trigger (3 consecutive identical issues)
#   - No progress threshold trigger (5 cycles without file changes)
#   - Cycle limit trigger (max cycles exceeded)
#   - Timeout trigger (exceeded time limit)
#   - State transitions (CLOSED → OPEN)
#   - Reset functionality

setup() {
  BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"

  # Create temp directory for test artifacts
  export BATS_TMPDIR="${BATS_TMPDIR:-/tmp}"
  export TEST_TMPDIR="$BATS_TMPDIR/circuit-breaker-test-$$"
  mkdir -p "$TEST_TMPDIR/.run"
  cd "$TEST_TMPDIR"

  # Initialize default circuit breaker state
  init_circuit_breaker 20 8
}

teardown() {
  cd /
  if [[ -d "$TEST_TMPDIR" ]]; then
    rm -rf "$TEST_TMPDIR"
  fi
}

# ============================================================================
# Helper Functions (implement circuit breaker logic for testing)
# ============================================================================

init_circuit_breaker() {
  local max_cycles="${1:-20}"
  local timeout_hours="${2:-8}"
  local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  cat > .run/circuit-breaker.json << EOF
{
  "state": "CLOSED",
  "triggers": {
    "same_issue": {
      "count": 0,
      "threshold": 3,
      "last_hash": null
    },
    "no_progress": {
      "count": 0,
      "threshold": 5
    },
    "cycle_count": {
      "current": 0,
      "limit": $max_cycles
    },
    "timeout": {
      "started": "$timestamp",
      "limit_hours": $timeout_hours
    }
  },
  "history": []
}
EOF
}

get_state() {
  jq -r '.state' .run/circuit-breaker.json
}

get_same_issue_count() {
  jq -r '.triggers.same_issue.count' .run/circuit-breaker.json
}

get_no_progress_count() {
  jq -r '.triggers.no_progress.count' .run/circuit-breaker.json
}

get_cycle_count() {
  jq -r '.triggers.cycle_count.current' .run/circuit-breaker.json
}

get_last_hash() {
  jq -r '.triggers.same_issue.last_hash // "null"' .run/circuit-breaker.json
}

increment_same_issue() {
  jq '.triggers.same_issue.count += 1' .run/circuit-breaker.json > .run/circuit-breaker.json.tmp
  mv .run/circuit-breaker.json.tmp .run/circuit-breaker.json
}

set_same_issue_hash() {
  local hash="$1"
  jq --arg h "$hash" '.triggers.same_issue.last_hash = $h' .run/circuit-breaker.json > .run/circuit-breaker.json.tmp
  mv .run/circuit-breaker.json.tmp .run/circuit-breaker.json
}

reset_same_issue() {
  local hash="$1"
  jq --arg h "$hash" '
    .triggers.same_issue.count = 1 |
    .triggers.same_issue.last_hash = $h
  ' .run/circuit-breaker.json > .run/circuit-breaker.json.tmp
  mv .run/circuit-breaker.json.tmp .run/circuit-breaker.json
}

increment_no_progress() {
  jq '.triggers.no_progress.count += 1' .run/circuit-breaker.json > .run/circuit-breaker.json.tmp
  mv .run/circuit-breaker.json.tmp .run/circuit-breaker.json
}

reset_no_progress() {
  jq '.triggers.no_progress.count = 0' .run/circuit-breaker.json > .run/circuit-breaker.json.tmp
  mv .run/circuit-breaker.json.tmp .run/circuit-breaker.json
}

increment_cycle() {
  jq '.triggers.cycle_count.current += 1' .run/circuit-breaker.json > .run/circuit-breaker.json.tmp
  mv .run/circuit-breaker.json.tmp .run/circuit-breaker.json
}

set_cycle_count() {
  local count="$1"
  jq --argjson c "$count" '.triggers.cycle_count.current = $c' .run/circuit-breaker.json > .run/circuit-breaker.json.tmp
  mv .run/circuit-breaker.json.tmp .run/circuit-breaker.json
}

set_started_time() {
  local timestamp="$1"
  jq --arg t "$timestamp" '.triggers.timeout.started = $t' .run/circuit-breaker.json > .run/circuit-breaker.json.tmp
  mv .run/circuit-breaker.json.tmp .run/circuit-breaker.json
}

trip_breaker() {
  local trigger="$1"
  local reason="$2"
  local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  jq --arg t "$trigger" --arg r "$reason" --arg ts "$timestamp" '
    .state = "OPEN" |
    .history += [{"timestamp": $ts, "trigger": $t, "reason": $r}]
  ' .run/circuit-breaker.json > .run/circuit-breaker.json.tmp
  mv .run/circuit-breaker.json.tmp .run/circuit-breaker.json
}

reset_breaker() {
  local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  jq --arg ts "$timestamp" '
    .state = "CLOSED" |
    .triggers.same_issue.count = 0 |
    .triggers.same_issue.last_hash = null |
    .triggers.no_progress.count = 0 |
    .triggers.cycle_count.current = 0 |
    .triggers.timeout.started = $ts
  ' .run/circuit-breaker.json > .run/circuit-breaker.json.tmp
  mv .run/circuit-breaker.json.tmp .run/circuit-breaker.json
}

check_same_issue_trigger() {
  local count=$(jq '.triggers.same_issue.count' .run/circuit-breaker.json)
  local threshold=$(jq '.triggers.same_issue.threshold' .run/circuit-breaker.json)
  [[ $count -ge $threshold ]]
}

check_no_progress_trigger() {
  local count=$(jq '.triggers.no_progress.count' .run/circuit-breaker.json)
  local threshold=$(jq '.triggers.no_progress.threshold' .run/circuit-breaker.json)
  [[ $count -ge $threshold ]]
}

check_cycle_limit_trigger() {
  local current=$(jq '.triggers.cycle_count.current' .run/circuit-breaker.json)
  local limit=$(jq '.triggers.cycle_count.limit' .run/circuit-breaker.json)
  [[ $current -ge $limit ]]
}

check_timeout_trigger() {
  local started=$(jq -r '.triggers.timeout.started' .run/circuit-breaker.json)
  local limit_hours=$(jq '.triggers.timeout.limit_hours' .run/circuit-breaker.json)
  local elapsed_seconds=$(($(date +%s) - $(date -d "$started" +%s)))
  local limit_seconds=$((limit_hours * 3600))
  [[ $elapsed_seconds -ge $limit_seconds ]]
}

# Hash findings for comparison
hash_findings() {
  local content="$1"
  echo -n "$content" | md5sum | cut -d' ' -f1
}

# ============================================================================
# Initialization Tests
# ============================================================================

@test "init: creates circuit breaker file" {
  [ -f ".run/circuit-breaker.json" ]
}

@test "init: state is CLOSED" {
  [ "$(get_state)" = "CLOSED" ]
}

@test "init: same_issue count is 0" {
  [ "$(get_same_issue_count)" = "0" ]
}

@test "init: no_progress count is 0" {
  [ "$(get_no_progress_count)" = "0" ]
}

@test "init: cycle count is 0" {
  [ "$(get_cycle_count)" = "0" ]
}

@test "init: respects custom max_cycles" {
  init_circuit_breaker 10 4
  local limit=$(jq '.triggers.cycle_count.limit' .run/circuit-breaker.json)
  [ "$limit" = "10" ]
}

@test "init: respects custom timeout_hours" {
  init_circuit_breaker 20 12
  local hours=$(jq '.triggers.timeout.limit_hours' .run/circuit-breaker.json)
  [ "$hours" = "12" ]
}

# ============================================================================
# Same Issue Threshold Tests
# ============================================================================

@test "same_issue: does not trigger below threshold" {
  increment_same_issue
  increment_same_issue

  [ "$(get_same_issue_count)" = "2" ]
  ! check_same_issue_trigger
}

@test "same_issue: triggers at threshold" {
  increment_same_issue
  increment_same_issue
  increment_same_issue

  [ "$(get_same_issue_count)" = "3" ]
  check_same_issue_trigger
}

@test "same_issue: tracks last_hash" {
  local hash=$(hash_findings "test finding")
  set_same_issue_hash "$hash"

  [ "$(get_last_hash)" = "$hash" ]
}

@test "same_issue: resets on new issue" {
  increment_same_issue
  increment_same_issue

  [ "$(get_same_issue_count)" = "2" ]

  local new_hash=$(hash_findings "different finding")
  reset_same_issue "$new_hash"

  [ "$(get_same_issue_count)" = "1" ]
  [ "$(get_last_hash)" = "$new_hash" ]
}

@test "same_issue: trips breaker at threshold" {
  increment_same_issue
  increment_same_issue
  increment_same_issue

  if check_same_issue_trigger; then
    trip_breaker "same_issue" "Same finding repeated 3 times"
  fi

  [ "$(get_state)" = "OPEN" ]
}

# ============================================================================
# No Progress Threshold Tests
# ============================================================================

@test "no_progress: does not trigger below threshold" {
  increment_no_progress
  increment_no_progress
  increment_no_progress
  increment_no_progress

  [ "$(get_no_progress_count)" = "4" ]
  ! check_no_progress_trigger
}

@test "no_progress: triggers at threshold" {
  for i in {1..5}; do
    increment_no_progress
  done

  [ "$(get_no_progress_count)" = "5" ]
  check_no_progress_trigger
}

@test "no_progress: resets on progress" {
  increment_no_progress
  increment_no_progress
  increment_no_progress

  reset_no_progress

  [ "$(get_no_progress_count)" = "0" ]
}

@test "no_progress: trips breaker at threshold" {
  for i in {1..5}; do
    increment_no_progress
  done

  if check_no_progress_trigger; then
    trip_breaker "no_progress" "No file changes for 5 cycles"
  fi

  [ "$(get_state)" = "OPEN" ]
}

# ============================================================================
# Cycle Limit Tests
# ============================================================================

@test "cycle_limit: does not trigger below limit" {
  init_circuit_breaker 5 8

  set_cycle_count 4

  ! check_cycle_limit_trigger
}

@test "cycle_limit: triggers at limit" {
  init_circuit_breaker 5 8

  set_cycle_count 5

  check_cycle_limit_trigger
}

@test "cycle_limit: increment works correctly" {
  increment_cycle
  increment_cycle
  increment_cycle

  [ "$(get_cycle_count)" = "3" ]
}

@test "cycle_limit: trips breaker at limit" {
  init_circuit_breaker 3 8

  set_cycle_count 3

  if check_cycle_limit_trigger; then
    trip_breaker "cycle_limit" "Maximum cycles (3) exceeded"
  fi

  [ "$(get_state)" = "OPEN" ]
}

# ============================================================================
# Timeout Tests
# ============================================================================

@test "timeout: does not trigger within limit" {
  # Started now, 8 hour limit - should not trigger
  ! check_timeout_trigger
}

@test "timeout: triggers when exceeded" {
  # Set started time to 9 hours ago
  local nine_hours_ago=$(date -u -d "9 hours ago" +"%Y-%m-%dT%H:%M:%SZ")
  set_started_time "$nine_hours_ago"

  check_timeout_trigger
}

@test "timeout: respects custom limit" {
  init_circuit_breaker 20 1  # 1 hour limit

  # Set started time to 2 hours ago
  local two_hours_ago=$(date -u -d "2 hours ago" +"%Y-%m-%dT%H:%M:%SZ")
  set_started_time "$two_hours_ago"

  check_timeout_trigger
}

@test "timeout: trips breaker when exceeded" {
  local nine_hours_ago=$(date -u -d "9 hours ago" +"%Y-%m-%dT%H:%M:%SZ")
  set_started_time "$nine_hours_ago"

  if check_timeout_trigger; then
    trip_breaker "timeout" "Timeout exceeded (8h)"
  fi

  [ "$(get_state)" = "OPEN" ]
}

# ============================================================================
# State Transition Tests
# ============================================================================

@test "state: starts CLOSED" {
  [ "$(get_state)" = "CLOSED" ]
}

@test "state: transitions to OPEN on trip" {
  trip_breaker "test" "Test trip"

  [ "$(get_state)" = "OPEN" ]
}

@test "state: records history on trip" {
  trip_breaker "same_issue" "Test trip reason"

  local trigger=$(jq -r '.history[0].trigger' .run/circuit-breaker.json)
  local reason=$(jq -r '.history[0].reason' .run/circuit-breaker.json)

  [ "$trigger" = "same_issue" ]
  [ "$reason" = "Test trip reason" ]
}

@test "state: preserves history across trips" {
  trip_breaker "trigger1" "First trip"

  # Reset and trip again
  jq '.state = "CLOSED"' .run/circuit-breaker.json > .run/circuit-breaker.json.tmp
  mv .run/circuit-breaker.json.tmp .run/circuit-breaker.json

  trip_breaker "trigger2" "Second trip"

  local count=$(jq '.history | length' .run/circuit-breaker.json)
  [ "$count" = "2" ]
}

# ============================================================================
# Reset Functionality Tests
# ============================================================================

@test "reset: changes state to CLOSED" {
  trip_breaker "test" "Test trip"
  [ "$(get_state)" = "OPEN" ]

  reset_breaker
  [ "$(get_state)" = "CLOSED" ]
}

@test "reset: clears same_issue counter" {
  increment_same_issue
  increment_same_issue

  reset_breaker

  [ "$(get_same_issue_count)" = "0" ]
}

@test "reset: clears same_issue hash" {
  set_same_issue_hash "abc123"

  reset_breaker

  [ "$(get_last_hash)" = "null" ]
}

@test "reset: clears no_progress counter" {
  increment_no_progress
  increment_no_progress
  increment_no_progress

  reset_breaker

  [ "$(get_no_progress_count)" = "0" ]
}

@test "reset: clears cycle counter" {
  set_cycle_count 10

  reset_breaker

  [ "$(get_cycle_count)" = "0" ]
}

@test "reset: resets timeout start time" {
  local old_start=$(jq -r '.triggers.timeout.started' .run/circuit-breaker.json)
  sleep 1

  reset_breaker

  local new_start=$(jq -r '.triggers.timeout.started' .run/circuit-breaker.json)
  [ "$old_start" != "$new_start" ]
}

# ============================================================================
# Hash Function Tests
# ============================================================================

@test "hash: same content produces same hash" {
  local hash1=$(hash_findings "test content")
  local hash2=$(hash_findings "test content")

  [ "$hash1" = "$hash2" ]
}

@test "hash: different content produces different hash" {
  local hash1=$(hash_findings "content one")
  local hash2=$(hash_findings "content two")

  [ "$hash1" != "$hash2" ]
}

@test "hash: empty content produces valid hash" {
  local hash=$(hash_findings "")

  # MD5 hash is 32 characters
  [ ${#hash} -eq 32 ]
}

# ============================================================================
# JSON File Integrity Tests
# ============================================================================

@test "json: file remains valid after operations" {
  increment_same_issue
  increment_no_progress
  increment_cycle
  set_same_issue_hash "test123"

  # Validate JSON
  jq . .run/circuit-breaker.json > /dev/null
  [ $? -eq 0 ]
}

@test "json: atomic write prevents corruption" {
  # Simulate multiple concurrent writes
  for i in {1..5}; do
    increment_cycle &
  done
  wait

  # File should still be valid JSON
  jq . .run/circuit-breaker.json > /dev/null
  [ $? -eq 0 ]
}

@test "json: temp file is cleaned up" {
  increment_same_issue

  # No .tmp files should remain
  [ ! -f ".run/circuit-breaker.json.tmp" ]
}
