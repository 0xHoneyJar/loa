#!/usr/bin/env bash
# test_path_lib.sh - Unit tests for path-lib.sh
# Version: 1.0.0
#
# Run with: bash .claude/scripts/tests/test_path_lib.sh
# path-lib: exempt

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# =============================================================================
# Test Helpers
# =============================================================================

_create_test_project() {
  local test_dir
  test_dir=$(mktemp -d)

  # Create minimal Loa structure
  mkdir -p "$test_dir/.claude/scripts"
  mkdir -p "$test_dir/grimoires/loa"

  # Copy path-lib.sh
  cp "$LIB_DIR/path-lib.sh" "$test_dir/.claude/scripts/"

  echo "$test_dir"
}

run_test() {
  local test_name="$1"
  shift

  TESTS_RUN=$((TESTS_RUN + 1))
  echo -n "  $test_name... "

  local output exit_code=0
  output=$("$@" 2>&1) || exit_code=$?

  if [[ $exit_code -eq 0 ]]; then
    echo -e "${GREEN}PASS${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo -e "${RED}FAIL${NC}"
    [[ -n "$output" ]] && echo "    $output"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

# =============================================================================
# Test Cases (each runs in fresh subshell)
# =============================================================================

test_default_grimoire_path() {
  local test_dir
  test_dir=$(_create_test_project)

  (
    export PROJECT_ROOT="$test_dir"
    export CONFIG_FILE="$test_dir/.loa.config.yaml"
    source "$test_dir/.claude/scripts/path-lib.sh"

    result=$(get_grimoire_dir)
    [[ "$result" == *"grimoires/loa" ]] || { echo "Expected grimoires/loa, got $result"; exit 1; }
  )
  local rc=$?

  rm -rf "$test_dir"
  return $rc
}

_has_yq_v4() {
  if ! command -v yq &>/dev/null; then
    return 1
  fi
  local version
  version=$(yq --version 2>&1 | grep -oE '[0-9]+\.[0-9]+' | head -1) || return 1
  local major="${version%%.*}"
  [[ -n "$major" && "$major" -ge 4 ]]
}

test_custom_grimoire_path() {
  # Skip if yq v4+ not available (config reading requires it)
  if ! _has_yq_v4; then
    echo "SKIP: yq v4+ required"
    return 0
  fi

  local test_dir
  test_dir=$(_create_test_project)

  cat > "$test_dir/.loa.config.yaml" << 'EOF'
paths:
  grimoire: custom/grimoire/path
EOF
  mkdir -p "$test_dir/custom/grimoire/path"

  (
    export PROJECT_ROOT="$test_dir"
    export CONFIG_FILE="$test_dir/.loa.config.yaml"
    source "$test_dir/.claude/scripts/path-lib.sh"

    result=$(get_grimoire_dir)
    [[ "$result" == *"custom/grimoire/path" ]] || { echo "Expected custom/grimoire/path, got $result"; exit 1; }
  )
  local rc=$?

  rm -rf "$test_dir"
  return $rc
}

test_absolute_path_rejected() {
  local test_dir
  test_dir=$(_create_test_project)

  cat > "$test_dir/.loa.config.yaml" << 'EOF'
paths:
  grimoire: /etc/passwd
EOF

  (
    export PROJECT_ROOT="$test_dir"
    export CONFIG_FILE="$test_dir/.loa.config.yaml"
    source "$test_dir/.claude/scripts/path-lib.sh"

    # Should fail
    if get_grimoire_dir 2>/dev/null; then
      echo "Absolute path should be rejected"
      exit 1
    fi
    exit 0
  )
  local rc=$?

  rm -rf "$test_dir"
  return $rc
}

test_soul_source_equals_output_rejected() {
  local test_dir
  test_dir=$(_create_test_project)

  cat > "$test_dir/.loa.config.yaml" << 'EOF'
paths:
  soul:
    source: same/path.md
    output: same/path.md
EOF

  (
    export PROJECT_ROOT="$test_dir"
    export CONFIG_FILE="$test_dir/.loa.config.yaml"
    source "$test_dir/.claude/scripts/path-lib.sh"

    if get_grimoire_dir 2>/dev/null; then
      echo "Same source/output should be rejected"
      exit 1
    fi
    exit 0
  )
  local rc=$?

  rm -rf "$test_dir"
  return $rc
}

test_environment_inheritance() {
  local test_dir
  test_dir=$(_create_test_project)

  (
    export PROJECT_ROOT="$test_dir"
    export CONFIG_FILE="$test_dir/.loa.config.yaml"
    export LOA_GRIMOIRE_DIR="$test_dir/inherited/path"
    export LOA_BEADS_DIR="$test_dir/.beads"
    export LOA_SOUL_SOURCE="$test_dir/source.md"
    export LOA_SOUL_OUTPUT="$test_dir/output.md"
    source "$test_dir/.claude/scripts/path-lib.sh"

    result=$(get_grimoire_dir)
    [[ "$result" == "$test_dir/inherited/path" ]] || { echo "Expected inherited path, got $result"; exit 1; }
  )
  local rc=$?

  rm -rf "$test_dir"
  return $rc
}

test_legacy_mode() {
  local test_dir
  test_dir=$(_create_test_project)

  cat > "$test_dir/.loa.config.yaml" << 'EOF'
paths:
  grimoire: custom/should/be/ignored
EOF

  (
    export PROJECT_ROOT="$test_dir"
    export CONFIG_FILE="$test_dir/.loa.config.yaml"
    export LOA_USE_LEGACY_PATHS=1
    source "$test_dir/.claude/scripts/path-lib.sh"

    result=$(get_grimoire_dir)
    [[ "$result" == *"grimoires/loa" ]] || { echo "Legacy mode should use hardcoded path, got $result"; exit 1; }
  )
  local rc=$?

  rm -rf "$test_dir"
  return $rc
}

test_all_getters_return_values() {
  local test_dir
  test_dir=$(_create_test_project)

  (
    export PROJECT_ROOT="$test_dir"
    export CONFIG_FILE="$test_dir/.loa.config.yaml"
    source "$test_dir/.claude/scripts/path-lib.sh"

    getters=(
      get_grimoire_dir get_beads_dir get_ledger_path get_notes_path
      get_trajectory_dir get_compound_dir get_flatline_dir get_archive_dir
      get_analytics_dir get_context_dir get_skills_dir get_skills_pending_dir
      get_decisions_path get_urls_path get_beauvoir_path get_soul_output_path
    )

    for getter in "${getters[@]}"; do
      value=$($getter)
      [[ -n "$value" ]] || { echo "$getter returned empty"; exit 1; }
    done
  )
  local rc=$?

  rm -rf "$test_dir"
  return $rc
}

test_derived_paths_use_grimoire_dir() {
  # Skip if yq v4+ not available (config reading requires it)
  if ! _has_yq_v4; then
    echo "SKIP: yq v4+ required"
    return 0
  fi

  local test_dir
  test_dir=$(_create_test_project)

  cat > "$test_dir/.loa.config.yaml" << 'EOF'
paths:
  grimoire: custom/grimoire
EOF
  mkdir -p "$test_dir/custom/grimoire"

  (
    export PROJECT_ROOT="$test_dir"
    export CONFIG_FILE="$test_dir/.loa.config.yaml"
    source "$test_dir/.claude/scripts/path-lib.sh"

    ledger=$(get_ledger_path)
    [[ "$ledger" == *"custom/grimoire/ledger.json" ]] || { echo "Ledger should use custom grimoire dir, got $ledger"; exit 1; }
  )
  local rc=$?

  rm -rf "$test_dir"
  return $rc
}

test_ensure_grimoire_structure() {
  local test_dir
  test_dir=$(_create_test_project)

  (
    export PROJECT_ROOT="$test_dir"
    export CONFIG_FILE="$test_dir/.loa.config.yaml"
    source "$test_dir/.claude/scripts/path-lib.sh"

    rm -rf "$test_dir/grimoires/loa"
    ensure_grimoire_structure

    [[ -d "$test_dir/grimoires/loa/a2a/trajectory" ]] || { echo "trajectory dir missing"; exit 1; }
    [[ -d "$test_dir/grimoires/loa/a2a/compound" ]] || { echo "compound dir missing"; exit 1; }
    [[ -d "$test_dir/grimoires/loa/archive" ]] || { echo "archive dir missing"; exit 1; }
  )
  local rc=$?

  rm -rf "$test_dir"
  return $rc
}

test_version_function() {
  local test_dir
  test_dir=$(_create_test_project)

  (
    export PROJECT_ROOT="$test_dir"
    export CONFIG_FILE="$test_dir/.loa.config.yaml"
    source "$test_dir/.claude/scripts/path-lib.sh"

    version=$(get_path_lib_version)
    [[ "$version" == "1.0.0" ]] || { echo "Expected 1.0.0, got $version"; exit 1; }
  )
  local rc=$?

  rm -rf "$test_dir"
  return $rc
}

# =============================================================================
# Main
# =============================================================================

main() {
  echo "========================================"
  echo "path-lib.sh Unit Tests"
  echo "========================================"
  echo ""

  run_test "Default grimoire path" test_default_grimoire_path
  run_test "Custom grimoire path from config" test_custom_grimoire_path
  run_test "Absolute path rejected" test_absolute_path_rejected
  run_test "Soul source == output rejected" test_soul_source_equals_output_rejected
  run_test "Environment inheritance" test_environment_inheritance
  run_test "Legacy mode (LOA_USE_LEGACY_PATHS=1)" test_legacy_mode
  run_test "All 16 getters return values" test_all_getters_return_values
  run_test "Derived paths use grimoire dir" test_derived_paths_use_grimoire_dir
  run_test "ensure_grimoire_structure creates dirs" test_ensure_grimoire_structure
  run_test "Version function returns version" test_version_function

  echo ""
  echo "========================================"
  echo "Results: ${TESTS_PASSED}/${TESTS_RUN} passed"
  if [[ $TESTS_FAILED -gt 0 ]]; then
    echo -e "${RED}${TESTS_FAILED} tests failed${NC}"
    exit 1
  else
    echo -e "${GREEN}All tests passed${NC}"
    exit 0
  fi
}

main "$@"
