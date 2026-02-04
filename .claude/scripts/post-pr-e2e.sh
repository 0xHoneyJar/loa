#!/usr/bin/env bash
# post-pr-e2e.sh - E2E Testing for Post-PR Validation Loop
# Part of Loa Framework v1.25.0
#
# Runs build and tests with fresh context for "fresh-eyes" validation.
#
# Usage:
#   post-pr-e2e.sh [--pr-number <n>] [--build-cmd <cmd>] [--test-cmd <cmd>] [--timeout <secs>]
#
# Exit codes:
#   0 - PASSED (all tests pass)
#   1 - FAILED (test failures)
#   2 - BUILD_FAILED (build errors)
#   3 - ERROR (script error)

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/bootstrap.sh"
readonly STATE_SCRIPT="${SCRIPT_DIR}/post-pr-state.sh"

# Default commands (detected from package.json or config)
BUILD_CMD="${BUILD_CMD:-}"
TEST_CMD="${TEST_CMD:-}"
BUILD_TIMEOUT="${BUILD_TIMEOUT:-300}"  # 5 minutes
TEST_TIMEOUT="${TEST_TIMEOUT:-600}"     # 10 minutes

# Output directory (use path-lib)
_GRIMOIRE_DIR=$(get_grimoire_dir)
readonly BASE_CONTEXT_DIR="${BASE_CONTEXT_DIR:-${_GRIMOIRE_DIR}/a2a}"

# ============================================================================
# Utility Functions
# ============================================================================

log_info() {
  echo "[INFO] $*" >&2
}

log_error() {
  echo "[ERROR] $*" >&2
}

log_debug() {
  if [[ "${DEBUG:-}" == "true" ]]; then
    echo "[DEBUG] $*" >&2
  fi
}

timestamp() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# Validate command against allowlist of safe prefixes
# Returns 0 if command starts with a known-safe prefix, 1 otherwise
# This prevents command injection via malicious package.json or user input
validate_command() {
  local cmd="$1"

  # Allowlist of safe command prefixes
  # These are standard build/test tools that don't allow arbitrary execution
  local -a allowed_prefixes=(
    "npm "
    "npm run "
    "npx "
    "yarn "
    "pnpm "
    "make "
    "cargo "
    "go "
    "pytest "
    "python -m pytest"
    "jest "
    "vitest "
    "mocha "
    "bun "
    "deno "
    "gradle "
    "mvn "
    "dotnet "
  )

  for prefix in "${allowed_prefixes[@]}"; do
    if [[ "$cmd" == "$prefix"* ]]; then
      return 0
    fi
  done

  # Log warning for unrecognized commands
  log_error "Command not in allowlist: ${cmd:0:50}..."
  log_error "Allowed prefixes: npm, yarn, pnpm, make, cargo, go, pytest, jest, vitest, mocha, bun, deno, gradle, mvn, dotnet"
  return 1
}

# Run command with timeout
# Note: Commands may be multi-word strings (e.g., "npm run build") requiring shell expansion.
# This is safe because: (1) commands are auto-detected from project config or (2) user-provided
# via CLI (same privilege level). Use eval for explicit shell expansion intent.
run_with_timeout() {
  local timeout_val="$1"
  shift
  local cmd="$*"

  # Validate command is not empty
  if [[ -z "$cmd" ]]; then
    log_error "Empty command provided to run_with_timeout"
    return 1
  fi

  # Validate command against allowlist (HIGH-001 remediation)
  if ! validate_command "$cmd"; then
    log_error "Command rejected by security allowlist"
    return 1
  fi

  if command -v timeout &>/dev/null; then
    timeout "$timeout_val" bash -c "$cmd"
  else
    # Fallback for systems without timeout (macOS)
    local pid
    bash -c "$cmd" &
    pid=$!

    local count=0
    while kill -0 "$pid" 2>/dev/null; do
      sleep 1
      ((++count))
      if (( count >= timeout_val )); then
        kill -TERM "$pid" 2>/dev/null || true
        sleep 2
        kill -KILL "$pid" 2>/dev/null || true
        return 124  # timeout exit code
      fi
    done

    wait "$pid"
  fi
}

# ============================================================================
# Test Failure Identity Algorithm
# ============================================================================

# Generate stable 16-char hash for a test failure
# Uses: test_name, file, error_type
test_failure_identity() {
  local test_name="${1:-}"
  local file="${2:-}"
  local error_type="${3:-}"

  # Build identity string
  local identity_str="${test_name}|${file}|${error_type}"

  # Generate SHA256 and take first 16 chars
  echo -n "$identity_str" | sha256sum | cut -c1-16
}

# Add failure identity to state
add_failure_identity() {
  local identity="$1"

  if [[ -x "$STATE_SCRIPT" ]]; then
    # Get current identities
    local current
    current=$("$STATE_SCRIPT" get "e2e.failure_identities" 2>/dev/null || echo "[]")

    # Add new identity
    local updated
    updated=$(echo "$current" | jq --arg id "$identity" '. + [$id] | unique')

    # Update state file directly
    if [[ -f ".run/post-pr-state.json" ]]; then
      jq --argjson ids "$updated" '.e2e.failure_identities = $ids' ".run/post-pr-state.json" > ".run/post-pr-state.json.tmp"
      mv ".run/post-pr-state.json.tmp" ".run/post-pr-state.json"
    fi
  fi
}

# ============================================================================
# Command Detection
# ============================================================================

# Detect build command from project
detect_build_command() {
  if [[ -n "$BUILD_CMD" ]]; then
    echo "$BUILD_CMD"
    return 0
  fi

  # Check package.json
  if [[ -f "package.json" ]]; then
    local build_script
    build_script=$(jq -r '.scripts.build // empty' package.json 2>/dev/null || echo "")
    if [[ -n "$build_script" ]]; then
      echo "npm run build"
      return 0
    fi
  fi

  # Check Makefile
  if [[ -f "Makefile" ]]; then
    if grep -q "^build:" Makefile 2>/dev/null; then
      echo "make build"
      return 0
    fi
  fi

  # Check Cargo.toml (Rust)
  if [[ -f "Cargo.toml" ]]; then
    echo "cargo build"
    return 0
  fi

  # Check go.mod (Go)
  if [[ -f "go.mod" ]]; then
    echo "go build ./..."
    return 0
  fi

  # No build command found (some projects don't need one)
  echo ""
}

# Detect test command from project
detect_test_command() {
  if [[ -n "$TEST_CMD" ]]; then
    echo "$TEST_CMD"
    return 0
  fi

  # Check package.json
  if [[ -f "package.json" ]]; then
    local test_script
    test_script=$(jq -r '.scripts.test // empty' package.json 2>/dev/null || echo "")
    if [[ -n "$test_script" ]]; then
      echo "npm test"
      return 0
    fi
  fi

  # Check Makefile
  if [[ -f "Makefile" ]]; then
    if grep -q "^test:" Makefile 2>/dev/null; then
      echo "make test"
      return 0
    fi
  fi

  # Check Cargo.toml (Rust)
  if [[ -f "Cargo.toml" ]]; then
    echo "cargo test"
    return 0
  fi

  # Check go.mod (Go)
  if [[ -f "go.mod" ]]; then
    echo "go test ./..."
    return 0
  fi

  # Check for pytest (Python)
  if [[ -f "pytest.ini" ]] || [[ -f "pyproject.toml" ]]; then
    echo "pytest"
    return 0
  fi

  # No test command found
  echo ""
}

# ============================================================================
# Branch Validation
# ============================================================================

validate_branch() {
  local expected_branch="$1"

  if [[ -z "$expected_branch" ]]; then
    log_debug "No expected branch, skipping validation"
    return 0
  fi

  local current_branch
  current_branch=$(git branch --show-current 2>/dev/null || echo "")

  if [[ -z "$current_branch" ]]; then
    log_error "Could not determine current branch"
    return 1
  fi

  if [[ "$current_branch" != "$expected_branch" ]]; then
    log_error "Branch mismatch: expected '$expected_branch', got '$current_branch'"
    return 1
  fi

  log_info "Branch validated: $current_branch"
  return 0
}

# ============================================================================
# Test Execution
# ============================================================================

run_build() {
  local build_cmd="$1"
  local output_file="$2"

  if [[ -z "$build_cmd" ]]; then
    log_info "No build command, skipping build"
    return 0
  fi

  log_info "Running build: $build_cmd"

  local result=0
  if run_with_timeout "$BUILD_TIMEOUT" "$build_cmd" > "$output_file" 2>&1; then
    log_info "Build succeeded"
    return 0
  else
    result=$?
    if (( result == 124 )); then
      log_error "Build timed out after ${BUILD_TIMEOUT}s"
    else
      log_error "Build failed with exit code: $result"
    fi
    return 2
  fi
}

run_tests() {
  local test_cmd="$1"
  local output_file="$2"

  if [[ -z "$test_cmd" ]]; then
    log_error "No test command available"
    return 3
  fi

  log_info "Running tests: $test_cmd"

  local result=0
  if run_with_timeout "$TEST_TIMEOUT" "$test_cmd" > "$output_file" 2>&1; then
    log_info "Tests passed"
    return 0
  else
    result=$?
    if (( result == 124 )); then
      log_error "Tests timed out after ${TEST_TIMEOUT}s"
      return 1
    else
      log_error "Tests failed with exit code: $result"
      return 1
    fi
  fi
}

# Parse test output for failures
parse_test_failures() {
  local output_file="$1"
  local failures='[]'

  # Check for common test failure patterns

  # Jest/Mocha style: "FAIL" or "✕"
  if grep -E "(FAIL|✕|✖)" "$output_file" 2>/dev/null; then
    while IFS= read -r line; do
      local test_name file
      test_name=$(echo "$line" | sed -E 's/.*FAIL\s+//' | sed -E 's/.*✕\s+//' | head -c 100)
      file=$(echo "$line" | grep -oE '\S+\.(test|spec)\.(js|ts|jsx|tsx)' | head -1 || echo "unknown")

      local identity
      identity=$(test_failure_identity "$test_name" "$file" "assertion")

      failures=$(echo "$failures" | jq --arg name "$test_name" --arg f "$file" --arg id "$identity" \
        '. + [{"id": $id, "name": $name, "file": $f, "type": "assertion"}]')

      add_failure_identity "$identity"
    done < <(grep -E "(FAIL|✕|✖)" "$output_file" 2>/dev/null | head -10)
  fi

  # pytest style: "FAILED"
  if grep -E "^FAILED" "$output_file" 2>/dev/null; then
    while IFS= read -r line; do
      local test_name file
      test_name=$(echo "$line" | sed 's/^FAILED //' | head -c 100)
      file=$(echo "$line" | grep -oE '\S+\.py::\S+' | cut -d: -f1 || echo "unknown")

      local identity
      identity=$(test_failure_identity "$test_name" "$file" "assertion")

      failures=$(echo "$failures" | jq --arg name "$test_name" --arg f "$file" --arg id "$identity" \
        '. + [{"id": $id, "name": $name, "file": $f, "type": "assertion"}]')

      add_failure_identity "$identity"
    done < <(grep -E "^FAILED" "$output_file" 2>/dev/null | head -10)
  fi

  # Go test style: "--- FAIL:"
  if grep -E "^--- FAIL:" "$output_file" 2>/dev/null; then
    while IFS= read -r line; do
      local test_name
      test_name=$(echo "$line" | sed 's/^--- FAIL: //' | cut -d' ' -f1)

      local identity
      identity=$(test_failure_identity "$test_name" "" "assertion")

      failures=$(echo "$failures" | jq --arg name "$test_name" --arg id "$identity" \
        '. + [{"id": $id, "name": $name, "file": "", "type": "assertion"}]')

      add_failure_identity "$identity"
    done < <(grep -E "^--- FAIL:" "$output_file" 2>/dev/null | head -10)
  fi

  # Rust/Cargo test style: "test ... FAILED"
  if grep -E "test .* FAILED" "$output_file" 2>/dev/null; then
    while IFS= read -r line; do
      local test_name
      test_name=$(echo "$line" | sed -E 's/^test\s+//' | sed 's/ ... FAILED//')

      local identity
      identity=$(test_failure_identity "$test_name" "" "assertion")

      failures=$(echo "$failures" | jq --arg name "$test_name" --arg id "$identity" \
        '. + [{"id": $id, "name": $name, "file": "", "type": "assertion"}]')

      add_failure_identity "$identity"
    done < <(grep -E "test .* FAILED" "$output_file" 2>/dev/null | head -10)
  fi

  echo "$failures"
}

# ============================================================================
# Results Saving
# ============================================================================

save_results() {
  local pr_number="$1"
  local verdict="$2"
  local build_output="$3"
  local test_output="$4"
  local failures="$5"

  local results_dir="${BASE_CONTEXT_DIR}/pr-${pr_number}"
  mkdir -p "$results_dir"

  local results_file="${results_dir}/e2e-results.json"

  jq -n \
    --arg v "$verdict" \
    --arg ts "$(timestamp)" \
    --argjson failures "$failures" \
    '{
      verdict: $v,
      timestamp: $ts,
      failures: $failures,
      failure_count: ($failures | length)
    }' > "$results_file"

  # Save outputs
  if [[ -f "$build_output" ]]; then
    cp "$build_output" "${results_dir}/build-output.log"
  fi

  if [[ -f "$test_output" ]]; then
    cp "$test_output" "${results_dir}/test-output.log"
  fi

  log_info "Results saved to $results_file"
}

# ============================================================================
# Main
# ============================================================================

main() {
  local pr_number=""

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --pr-number)
        pr_number="$2"
        shift 2
        ;;
      --build-cmd)
        BUILD_CMD="$2"
        shift 2
        ;;
      --test-cmd)
        TEST_CMD="$2"
        shift 2
        ;;
      --build-timeout)
        BUILD_TIMEOUT="$2"
        shift 2
        ;;
      --test-timeout)
        TEST_TIMEOUT="$2"
        shift 2
        ;;
      --help|-h)
        echo "Usage: post-pr-e2e.sh [--pr-number <n>] [--build-cmd <cmd>] [--test-cmd <cmd>]"
        echo ""
        echo "Exit codes:"
        echo "  0 - PASSED"
        echo "  1 - FAILED"
        echo "  2 - BUILD_FAILED"
        echo "  3 - ERROR"
        exit 0
        ;;
      *)
        log_error "Unknown option: $1"
        exit 3
        ;;
    esac
  done

  # Get PR number from state if not provided
  if [[ -z "$pr_number" ]] && [[ -x "$STATE_SCRIPT" ]]; then
    pr_number=$("$STATE_SCRIPT" get pr_number 2>/dev/null || echo "")
  fi

  if [[ -z "$pr_number" ]]; then
    log_error "PR number required (--pr-number or from state)"
    exit 3
  fi

  # Get expected branch from state
  local expected_branch=""
  if [[ -x "$STATE_SCRIPT" ]]; then
    expected_branch=$("$STATE_SCRIPT" get branch 2>/dev/null || echo "")
  fi

  # Validate branch
  if ! validate_branch "$expected_branch"; then
    exit 3
  fi

  # Detect commands
  local build_cmd test_cmd
  build_cmd=$(detect_build_command)
  test_cmd=$(detect_test_command)

  log_info "Build command: ${build_cmd:-none}"
  log_info "Test command: ${test_cmd:-none}"

  # Create temp files for output
  local build_output test_output
  build_output=$(mktemp)
  test_output=$(mktemp)
  trap "rm -f '$build_output' '$test_output'" EXIT

  # Run build
  local build_result=0
  if ! run_build "$build_cmd" "$build_output"; then
    build_result=$?
    log_error "Build failed"
    save_results "$pr_number" "BUILD_FAILED" "$build_output" "" "[]"
    exit 2
  fi

  # Run tests
  local test_result=0
  if ! run_tests "$test_cmd" "$test_output"; then
    test_result=$?

    # Parse failures
    local failures
    failures=$(parse_test_failures "$test_output")
    local failure_count
    failure_count=$(echo "$failures" | jq 'length')

    log_error "Tests failed: $failure_count failure(s)"
    save_results "$pr_number" "FAILED" "$build_output" "$test_output" "$failures"
    exit 1
  fi

  # Success
  log_info "All tests passed"
  save_results "$pr_number" "PASSED" "$build_output" "$test_output" "[]"
  exit 0
}

main "$@"
