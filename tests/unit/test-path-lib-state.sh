#!/usr/bin/env bash
# test-path-lib-state.sh - Unit tests for path-lib.sh state-dir extensions
# Part of: cycle-038 Sprint 1
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAL_PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Test counter (file-based for subshell propagation)
TEST_RESULTS=$(mktemp)
echo "0 0 0" > "$TEST_RESULTS"

cleanup_tmp() {
  rm -rf "$TEST_TMPDIR" "$TEST_RESULTS"
}

TEST_TMPDIR=$(mktemp -d)
trap cleanup_tmp EXIT

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  local counts
  counts=$(cat "$TEST_RESULTS")
  local total pass fail
  total=$(echo "$counts" | awk '{print $1}')
  pass=$(echo "$counts" | awk '{print $2}')
  fail=$(echo "$counts" | awk '{print $3}')
  total=$((total + 1))
  if [[ "$expected" == "$actual" ]]; then
    echo "  PASS: $desc"
    pass=$((pass + 1))
  else
    echo "  FAIL: $desc"
    echo "    Expected: $expected"
    echo "    Actual:   $actual"
    fail=$((fail + 1))
  fi
  echo "$total $pass $fail" > "$TEST_RESULTS"
}

record_pass() {
  local desc="$1"
  local counts
  counts=$(cat "$TEST_RESULTS")
  local total pass fail
  total=$(echo "$counts" | awk '{print $1}')
  pass=$(echo "$counts" | awk '{print $2}')
  fail=$(echo "$counts" | awk '{print $3}')
  echo "$((total + 1)) $((pass + 1)) $fail" > "$TEST_RESULTS"
  echo "  PASS: $desc"
}

record_fail() {
  local desc="$1"
  local counts
  counts=$(cat "$TEST_RESULTS")
  local total pass fail
  total=$(echo "$counts" | awk '{print $1}')
  pass=$(echo "$counts" | awk '{print $2}')
  fail=$(echo "$counts" | awk '{print $3}')
  echo "$((total + 1)) $pass $((fail + 1))" > "$TEST_RESULTS"
  echo "  FAIL: $desc"
}

setup_test_project() {
  local test_dir="$TEST_TMPDIR/test-$$-$RANDOM"
  mkdir -p "$test_dir/.claude/scripts"
  cp "$REAL_PROJECT_ROOT/.claude/scripts/path-lib.sh" "$test_dir/.claude/scripts/"
  echo "$test_dir"
}

echo "path-lib.sh State-Dir Extension Tests"
echo "======================================"
echo ""

# --- Test 1: Default state dir ---
echo "Test 1: Default state directory"
(
  test_dir=$(setup_test_project)
  export PROJECT_ROOT="$test_dir"
  export CONFIG_FILE="$test_dir/.loa.config.yaml"
  unset LOA_STATE_DIR LOA_GRIMOIRE_DIR LOA_USE_LEGACY_PATHS LOA_ALLOW_ABSOLUTE_STATE 2>/dev/null || true
  _path_lib_initialized=false
  source "$test_dir/.claude/scripts/path-lib.sh"
  result=$(get_state_dir 2>/dev/null) || true
  assert_eq "Default state dir is .loa-state" "$test_dir/.loa-state" "$result"
)

# --- Test 2: Env var takes precedence ---
echo "Test 2: Environment variable precedence"
(
  test_dir=$(setup_test_project)
  export PROJECT_ROOT="$test_dir"
  export CONFIG_FILE="$test_dir/.loa.config.yaml"
  export LOA_STATE_DIR="custom-state"
  unset LOA_GRIMOIRE_DIR LOA_USE_LEGACY_PATHS LOA_ALLOW_ABSOLUTE_STATE 2>/dev/null || true
  _path_lib_initialized=false
  source "$test_dir/.claude/scripts/path-lib.sh"
  result=$(get_state_dir 2>/dev/null) || true
  assert_eq "Env var overrides default" "$test_dir/custom-state" "$result"
)

# --- Test 3: Config takes precedence over default ---
echo "Test 3: Config precedence over default"
(
  test_dir=$(setup_test_project)
  export PROJECT_ROOT="$test_dir"
  export CONFIG_FILE="$test_dir/.loa.config.yaml"
  unset LOA_STATE_DIR LOA_GRIMOIRE_DIR LOA_USE_LEGACY_PATHS LOA_ALLOW_ABSOLUTE_STATE 2>/dev/null || true
  cat > "$test_dir/.loa.config.yaml" <<'YAML'
paths:
  state_dir: my-state-dir
YAML
  _path_lib_initialized=false
  source "$test_dir/.claude/scripts/path-lib.sh"
  result=$(get_state_dir 2>/dev/null) || true
  assert_eq "Config overrides default" "$test_dir/my-state-dir" "$result"
)

# --- Test 4: Absolute path rejected by default ---
echo "Test 4: Absolute path rejection"
(
  test_dir=$(setup_test_project)
  export PROJECT_ROOT="$test_dir"
  export CONFIG_FILE="$test_dir/.loa.config.yaml"
  export LOA_STATE_DIR="/tmp/absolute-state"
  unset LOA_GRIMOIRE_DIR LOA_USE_LEGACY_PATHS LOA_ALLOW_ABSOLUTE_STATE 2>/dev/null || true
  _path_lib_initialized=false
  source "$test_dir/.claude/scripts/path-lib.sh"
  if get_state_dir >/dev/null 2>&1; then
    record_fail "Absolute path should be rejected"
  else
    record_pass "Absolute path rejected"
  fi
)

# --- Test 5: Absolute path allowed with opt-in ---
echo "Test 5: Absolute path with LOA_ALLOW_ABSOLUTE_STATE"
(
  test_dir=$(setup_test_project)
  abs_state_dir="/tmp/test-loa-state-$$"
  mkdir -p "$abs_state_dir"
  export PROJECT_ROOT="$test_dir"
  export CONFIG_FILE="$test_dir/.loa.config.yaml"
  export LOA_STATE_DIR="$abs_state_dir"
  export LOA_ALLOW_ABSOLUTE_STATE=1
  unset LOA_GRIMOIRE_DIR LOA_USE_LEGACY_PATHS 2>/dev/null || true
  _path_lib_initialized=false
  source "$test_dir/.claude/scripts/path-lib.sh"
  result=$(get_state_dir 2>/dev/null) || true
  assert_eq "Absolute path accepted with opt-in" "$abs_state_dir" "$result"
  rm -rf "$abs_state_dir"
)

# --- Test 6: ensure_state_structure creates dirs ---
echo "Test 6: ensure_state_structure()"
(
  test_dir=$(setup_test_project)
  export PROJECT_ROOT="$test_dir"
  export CONFIG_FILE="$test_dir/.loa.config.yaml"
  unset LOA_STATE_DIR LOA_GRIMOIRE_DIR LOA_USE_LEGACY_PATHS LOA_ALLOW_ABSOLUTE_STATE 2>/dev/null || true
  _path_lib_initialized=false
  source "$test_dir/.claude/scripts/path-lib.sh"
  ensure_state_structure 2>/dev/null

  sd="$test_dir/.loa-state"
  assert_eq "beads/ created" "true" "$( [[ -d "$sd/beads" ]] && echo true || echo false )"
  assert_eq "ck/ created" "true" "$( [[ -d "$sd/ck" ]] && echo true || echo false )"
  assert_eq "run/bridge-reviews/ created" "true" "$( [[ -d "$sd/run/bridge-reviews" ]] && echo true || echo false )"
  assert_eq "memory/archive/ created" "true" "$( [[ -d "$sd/memory/archive" ]] && echo true || echo false )"
  assert_eq "trajectory/current/ created" "true" "$( [[ -d "$sd/trajectory/current" ]] && echo true || echo false )"
  assert_eq "trajectory/archive/ created" "true" "$( [[ -d "$sd/trajectory/archive" ]] && echo true || echo false )"
  assert_eq ".loa-version.json created" "true" "$( [[ -f "$test_dir/.loa-version.json" ]] && echo true || echo false )"
)

# --- Test 7: detect_state_layout ---
echo "Test 7: detect_state_layout()"
(
  test_dir=$(setup_test_project)
  export PROJECT_ROOT="$test_dir"
  export CONFIG_FILE="$test_dir/.loa.config.yaml"
  unset LOA_STATE_DIR LOA_GRIMOIRE_DIR LOA_USE_LEGACY_PATHS LOA_ALLOW_ABSOLUTE_STATE 2>/dev/null || true
  _path_lib_initialized=false
  source "$test_dir/.claude/scripts/path-lib.sh"

  result=$(detect_state_layout)
  assert_eq "Missing version file returns 0" "0" "$result"

  echo '{"state_layout_version": 2, "created": "2026-01-01T00:00:00Z", "last_migration": null}' > "$test_dir/.loa-version.json"
  result=$(detect_state_layout)
  assert_eq "Version file v2 returns 2" "2" "$result"

  echo '{"state_layout_version": 1, "created": "2026-01-01T00:00:00Z", "last_migration": null}' > "$test_dir/.loa-version.json"
  result=$(detect_state_layout)
  assert_eq "Version file v1 returns 1" "1" "$result"
)

# --- Test 8: init_version_file ---
echo "Test 8: init_version_file()"
(
  test_dir=$(setup_test_project)
  export PROJECT_ROOT="$test_dir"
  export CONFIG_FILE="$test_dir/.loa.config.yaml"
  unset LOA_STATE_DIR LOA_GRIMOIRE_DIR LOA_USE_LEGACY_PATHS LOA_ALLOW_ABSOLUTE_STATE 2>/dev/null || true
  _path_lib_initialized=false
  source "$test_dir/.claude/scripts/path-lib.sh"

  init_version_file
  result=$(jq -r '.state_layout_version' "$test_dir/.loa-version.json")
  assert_eq "Fresh install gets v2" "2" "$result"

  rm "$test_dir/.loa-version.json"

  mkdir -p "$test_dir/.beads"
  init_version_file
  result=$(jq -r '.state_layout_version' "$test_dir/.loa-version.json")
  assert_eq "Legacy dirs get v1" "1" "$result"
)

# --- Test 9: append_jsonl ---
echo "Test 9: append_jsonl()"
(
  test_dir=$(setup_test_project)
  export PROJECT_ROOT="$test_dir"
  export CONFIG_FILE="$test_dir/.loa.config.yaml"
  unset LOA_STATE_DIR LOA_GRIMOIRE_DIR LOA_USE_LEGACY_PATHS LOA_ALLOW_ABSOLUTE_STATE 2>/dev/null || true
  _path_lib_initialized=false
  source "$test_dir/.claude/scripts/path-lib.sh"

  tf="$test_dir/test.jsonl"
  append_jsonl "$tf" '{"key":"value1"}'
  append_jsonl "$tf" '{"key":"value2"}'

  lines=$(wc -l < "$tf" | tr -d ' ')
  assert_eq "Two entries written" "2" "$lines"

  first=$(head -1 "$tf")
  assert_eq "First entry correct" '{"key":"value1"}' "$first"

  assert_eq "Lock file exists" "true" "$( [[ -f "$tf.lock" ]] && echo true || echo false )"
)

# --- Test 10: append_jsonl concurrent ---
echo "Test 10: append_jsonl() concurrent writes"
(
  test_dir=$(setup_test_project)
  export PROJECT_ROOT="$test_dir"
  export CONFIG_FILE="$test_dir/.loa.config.yaml"
  unset LOA_STATE_DIR LOA_GRIMOIRE_DIR LOA_USE_LEGACY_PATHS LOA_ALLOW_ABSOLUTE_STATE 2>/dev/null || true
  _path_lib_initialized=false
  source "$test_dir/.claude/scripts/path-lib.sh"

  tf="$test_dir/concurrent.jsonl"

  for i in $(seq 1 10); do
    append_jsonl "$tf" "{\"writer\":$i}" &
  done
  wait

  lines=$(wc -l < "$tf" | tr -d ' ')
  assert_eq "All 10 concurrent entries written" "10" "$lines"

  valid=true
  while IFS= read -r line; do
    if ! echo "$line" | jq empty 2>/dev/null; then
      valid=false
      break
    fi
  done < "$tf"
  assert_eq "All entries are valid JSON" "true" "$valid"
)

echo ""
echo "======================================"
counts=$(cat "$TEST_RESULTS")
total=$(echo "$counts" | awk '{print $1}')
pass=$(echo "$counts" | awk '{print $2}')
fail=$(echo "$counts" | awk '{print $3}')
echo "Results: $pass/$total passed, $fail failed"
echo ""

if [[ "$fail" -gt 0 ]]; then
  exit 1
fi
exit 0
