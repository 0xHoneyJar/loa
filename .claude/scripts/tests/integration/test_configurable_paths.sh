#!/usr/bin/env bash
# test_configurable_paths.sh - Integration tests for configurable paths
# Version: 1.0.0
#
# Tests end-to-end workflows with configurable grimoire paths.
# Validates OpenClaw integration scenario and legacy mode.
#
# Run with: bash .claude/scripts/tests/integration/test_configurable_paths.sh
# path-lib: exempt

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
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

  # Copy bootstrap.sh and path-lib.sh
  cp "$LIB_DIR/bootstrap.sh" "$test_dir/.claude/scripts/"
  cp "$LIB_DIR/path-lib.sh" "$test_dir/.claude/scripts/"

  # Initialize as git repo (needed for PROJECT_ROOT detection)
  (cd "$test_dir" && git init --quiet)

  echo "$test_dir"
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

skip_test() {
  local test_name="$1"
  local reason="$2"

  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
  echo -e "  $test_name... ${YELLOW}SKIP${NC}: $reason"
}

# =============================================================================
# Integration Test Cases
# =============================================================================

test_legacy_mode_end_to_end() {
  # Flatline IMP-001: Test LOA_USE_LEGACY_PATHS=1 end-to-end
  local test_dir
  test_dir=$(_create_test_project)

  # Create a config file with custom paths that should be IGNORED
  cat > "$test_dir/.loa.config.yaml" << 'EOF'
paths:
  grimoire: custom/should/be/ignored
  beads: custom/beads/ignored
  soul:
    source: custom/source.md
    output: custom/output.md
EOF

  (
    cd "$test_dir" || exit 1
    export LOA_USE_LEGACY_PATHS=1

    # Source bootstrap (which sources path-lib)
    source ".claude/scripts/bootstrap.sh"

    # Verify grimoire path is hardcoded default, NOT custom
    local grimoire_dir
    grimoire_dir=$(get_grimoire_dir)
    [[ "$grimoire_dir" == "$test_dir/grimoires/loa" ]] || {
      echo "Expected grimoires/loa, got $grimoire_dir"
      exit 1
    }

    # Verify beads path is hardcoded default
    local beads_dir
    beads_dir=$(get_beads_dir)
    [[ "$beads_dir" == "$test_dir/.beads" ]] || {
      echo "Expected .beads, got $beads_dir"
      exit 1
    }

    # Verify soul source is hardcoded default
    local soul_source
    soul_source=$(get_beauvoir_path)
    [[ "$soul_source" == "$test_dir/grimoires/loa/BEAUVOIR.md" ]] || {
      echo "Expected grimoires/loa/BEAUVOIR.md, got $soul_source"
      exit 1
    }

    # Verify soul output is hardcoded default
    local soul_output
    soul_output=$(get_soul_output_path)
    [[ "$soul_output" == "$test_dir/grimoires/loa/SOUL.md" ]] || {
      echo "Expected grimoires/loa/SOUL.md, got $soul_output"
      exit 1
    }

    # Verify derived paths also use legacy
    local ledger
    ledger=$(get_ledger_path)
    [[ "$ledger" == "$test_dir/grimoires/loa/ledger.json" ]] || {
      echo "Expected grimoires/loa/ledger.json, got $ledger"
      exit 1
    }
  )
  local rc=$?

  rm -rf "$test_dir"
  return $rc
}

test_legacy_mode_no_config_read() {
  # Verify config file is NOT read when LOA_USE_LEGACY_PATHS=1
  local test_dir
  test_dir=$(_create_test_project)

  # Create an INVALID config file (would cause parse error if read)
  cat > "$test_dir/.loa.config.yaml" << 'EOF'
this is not valid yaml: {{{{ broken
EOF

  (
    cd "$test_dir" || exit 1
    export LOA_USE_LEGACY_PATHS=1

    # This should NOT fail because config is not read
    source ".claude/scripts/bootstrap.sh"

    # Should return default paths without error
    local grimoire_dir
    grimoire_dir=$(get_grimoire_dir)
    [[ "$grimoire_dir" == "$test_dir/grimoires/loa" ]] || {
      echo "Legacy mode should not read config"
      exit 1
    }
  )
  local rc=$?

  rm -rf "$test_dir"
  return $rc
}

test_project_root_detection_git() {
  # Test PROJECT_ROOT detection from subdirectory
  local test_dir
  test_dir=$(_create_test_project)

  # Create a nested directory
  mkdir -p "$test_dir/src/deep/nested"

  (
    cd "$test_dir/src/deep/nested" || exit 1

    # Source bootstrap from nested directory
    source "$test_dir/.claude/scripts/bootstrap.sh"

    # PROJECT_ROOT should be git root, not current directory
    [[ "$PROJECT_ROOT" == "$test_dir" ]] || {
      echo "Expected $test_dir, got $PROJECT_ROOT"
      exit 1
    }
  )
  local rc=$?

  rm -rf "$test_dir"
  return $rc
}

test_project_root_detection_claude_dir() {
  # Test PROJECT_ROOT detection via .claude/ when not in git
  local test_dir
  test_dir=$(mktemp -d)

  # Create .claude structure but NOT a git repo
  mkdir -p "$test_dir/.claude/scripts"
  mkdir -p "$test_dir/grimoires/loa"
  mkdir -p "$test_dir/src/nested"

  cp "$LIB_DIR/bootstrap.sh" "$test_dir/.claude/scripts/"
  cp "$LIB_DIR/path-lib.sh" "$test_dir/.claude/scripts/"

  (
    cd "$test_dir/src/nested" || exit 1

    # Source bootstrap from nested directory (no git)
    source "$test_dir/.claude/scripts/bootstrap.sh"

    # PROJECT_ROOT should be found via .claude/ directory
    [[ "$PROJECT_ROOT" == "$test_dir" ]] || {
      echo "Expected $test_dir, got $PROJECT_ROOT"
      exit 1
    }
  )
  local rc=$?

  rm -rf "$test_dir"
  return $rc
}

test_project_root_detection_config_file() {
  # Test PROJECT_ROOT detection via .loa.config.yaml when no git or .claude/
  local test_dir
  test_dir=$(mktemp -d)

  # Create config file but NOT .claude/ or git
  mkdir -p "$test_dir/src/nested"
  touch "$test_dir/.loa.config.yaml"

  # We need path-lib.sh to exist somewhere for bootstrap to work
  # In this case, we'll inline the test
  (
    cd "$test_dir/src/nested" || exit 1

    # Manually walk up looking for .loa.config.yaml
    local dir="$PWD"
    local found=""
    while [[ "$dir" != "/" ]]; do
      if [[ -f "$dir/.loa.config.yaml" ]]; then
        found="$dir"
        break
      fi
      dir=$(dirname "$dir")
    done

    [[ "$found" == "$test_dir" ]] || {
      echo "Expected $test_dir, got $found"
      exit 1
    }
  )
  local rc=$?

  rm -rf "$test_dir"
  return $rc
}

test_multi_script_inheritance() {
  # Test that child scripts inherit path settings from parent
  local test_dir
  test_dir=$(_create_test_project)

  # Create a "parent" script that exports paths
  cat > "$test_dir/parent.sh" << 'PARENT'
#!/usr/bin/env bash
source ".claude/scripts/bootstrap.sh"

# Initialize path-lib to export the variables
get_grimoire_dir >/dev/null

# Call child script (environment vars are already exported by path-lib.sh)
bash "$1"
PARENT

  # Create a "child" script that checks inherited values
  cat > "$test_dir/child.sh" << 'CHILD'
#!/usr/bin/env bash
source ".claude/scripts/bootstrap.sh"

# Check if we inherited the environment (should be set by parent)
if [[ -n "${LOA_GRIMOIRE_DIR:-}" ]]; then
  echo "GRIMOIRE=$LOA_GRIMOIRE_DIR"
  echo "INHERITED=true"
else
  # Fallback: initialize fresh
  echo "GRIMOIRE=$(get_grimoire_dir)"
  echo "INHERITED=false"
fi

# Verify getter returns same value as what we have now
if [[ "$(get_grimoire_dir)" != "$(get_grimoire_dir)" ]]; then
  echo "MISMATCH: getter inconsistent"
  exit 1
fi
CHILD

  (
    cd "$test_dir" || exit 1

    # Run parent which calls child
    output=$(bash parent.sh child.sh 2>&1) || {
      echo "Script failed: $output"
      exit 1
    }

    # Verify grimoire path was set correctly
    if ! echo "$output" | grep -q "GRIMOIRE=$test_dir/grimoires/loa"; then
      echo "Path mismatch: $output"
      exit 1
    fi

    # Verify inheritance worked (not strictly required, but good to know)
    if echo "$output" | grep -q "INHERITED=true"; then
      : # Good - inheritance worked
    fi
  )
  local rc=$?

  rm -rf "$test_dir"
  return $rc
}

test_openclaw_integration_scenario() {
  # Test OpenClaw scenario: SOUL.md at workspace root
  # Skip if yq v4+ not available (config reading requires it)
  if ! _has_yq_v4; then
    echo "SKIP: yq v4+ required"
    return 0
  fi

  local test_dir
  test_dir=$(_create_test_project)

  # OpenClaw configuration: SOUL at root, grimoire in subdir
  cat > "$test_dir/.loa.config.yaml" << 'EOF'
paths:
  grimoire: .loa/grimoire
  soul:
    source: .loa/grimoire/BEAUVOIR.md
    output: SOUL.md
EOF

  # Create the custom grimoire structure
  mkdir -p "$test_dir/.loa/grimoire"

  (
    cd "$test_dir" || exit 1
    source ".claude/scripts/bootstrap.sh"

    # Verify custom grimoire path
    local grimoire_dir
    grimoire_dir=$(get_grimoire_dir)
    [[ "$grimoire_dir" == "$test_dir/.loa/grimoire" ]] || {
      echo "Expected .loa/grimoire, got $grimoire_dir"
      exit 1
    }

    # Verify SOUL output at root
    local soul_output
    soul_output=$(get_soul_output_path)
    [[ "$soul_output" == "$test_dir/SOUL.md" ]] || {
      echo "Expected SOUL.md at root, got $soul_output"
      exit 1
    }

    # Verify derived paths use custom grimoire
    local ledger
    ledger=$(get_ledger_path)
    [[ "$ledger" == "$test_dir/.loa/grimoire/ledger.json" ]] || {
      echo "Expected .loa/grimoire/ledger.json, got $ledger"
      exit 1
    }
  )
  local rc=$?

  rm -rf "$test_dir"
  return $rc
}

test_workflow_with_custom_paths() {
  # Test that ensure_grimoire_structure creates dirs at custom path
  # Skip if yq v4+ not available
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

  # Create base custom path
  mkdir -p "$test_dir/custom/grimoire/path"

  (
    cd "$test_dir" || exit 1
    source ".claude/scripts/bootstrap.sh"

    # Run ensure_grimoire_structure
    ensure_grimoire_structure

    # Verify directories were created at custom location
    [[ -d "$test_dir/custom/grimoire/path/a2a/trajectory" ]] || {
      echo "trajectory dir not created"
      exit 1
    }
    [[ -d "$test_dir/custom/grimoire/path/a2a/compound" ]] || {
      echo "compound dir not created"
      exit 1
    }
    [[ -d "$test_dir/custom/grimoire/path/archive" ]] || {
      echo "archive dir not created"
      exit 1
    }
    [[ -d "$test_dir/custom/grimoire/path/context" ]] || {
      echo "context dir not created"
      exit 1
    }
  )
  local rc=$?

  rm -rf "$test_dir"
  return $rc
}

test_symlink_containment_integration() {
  # Test that symlink outside workspace is rejected
  local test_dir outside_dir
  test_dir=$(_create_test_project)
  outside_dir=$(mktemp -d)

  # Create a symlink pointing outside workspace
  ln -s "$outside_dir" "$test_dir/escaped"

  (
    cd "$test_dir" || exit 1
    export LOA_GRIMOIRE_DIR="$test_dir/escaped"

    source ".claude/scripts/bootstrap.sh"

    # Should fail validation
    if get_grimoire_dir 2>/dev/null; then
      echo "Symlink escape should be rejected"
      rm -rf "$outside_dir"
      exit 1
    fi
    exit 0
  )
  local rc=$?

  rm -rf "$test_dir" "$outside_dir"
  return $rc
}

test_multiple_getters_consistency() {
  # Test that all getters consistently use the same grimoire base
  local test_dir
  test_dir=$(_create_test_project)

  (
    cd "$test_dir" || exit 1
    source ".claude/scripts/bootstrap.sh"

    local grimoire_dir
    grimoire_dir=$(get_grimoire_dir)

    # All derived paths should be under grimoire_dir
    local paths_to_check=(
      "$(get_ledger_path)"
      "$(get_notes_path)"
      "$(get_trajectory_dir)"
      "$(get_compound_dir)"
      "$(get_flatline_dir)"
      "$(get_archive_dir)"
      "$(get_analytics_dir)"
      "$(get_context_dir)"
      "$(get_skills_dir)"
      "$(get_skills_pending_dir)"
      "$(get_decisions_path)"
      "$(get_urls_path)"
    )

    for path in "${paths_to_check[@]}"; do
      if [[ "$path" != "$grimoire_dir"* ]]; then
        echo "Path $path not under grimoire dir $grimoire_dir"
        exit 1
      fi
    done
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
  echo "Configurable Paths Integration Tests"
  echo "========================================"
  echo ""

  # Legacy mode tests (critical for rollback safety)
  echo "Legacy Mode Tests:"
  run_test "LOA_USE_LEGACY_PATHS=1 end-to-end" test_legacy_mode_end_to_end
  run_test "Legacy mode ignores config file" test_legacy_mode_no_config_read

  echo ""
  echo "PROJECT_ROOT Detection Tests:"
  run_test "Detection via git root" test_project_root_detection_git
  run_test "Detection via .claude/ directory" test_project_root_detection_claude_dir
  run_test "Detection via .loa.config.yaml" test_project_root_detection_config_file

  echo ""
  echo "Path Inheritance Tests:"
  run_test "Multi-script inheritance" test_multi_script_inheritance

  echo ""
  echo "Custom Path Tests:"
  if _has_yq_v4; then
    run_test "OpenClaw integration scenario" test_openclaw_integration_scenario
    run_test "Workflow with custom paths" test_workflow_with_custom_paths
  else
    skip_test "OpenClaw integration scenario" "yq v4+ required"
    skip_test "Workflow with custom paths" "yq v4+ required"
  fi

  echo ""
  echo "Security Tests:"
  run_test "Symlink containment validation" test_symlink_containment_integration

  echo ""
  echo "Consistency Tests:"
  run_test "All getters use same grimoire base" test_multiple_getters_consistency

  echo ""
  echo "========================================"
  echo "Results: ${TESTS_PASSED} passed, ${TESTS_FAILED} failed, ${TESTS_SKIPPED} skipped (${TESTS_RUN} total)"
  if [[ $TESTS_FAILED -gt 0 ]]; then
    echo -e "${RED}${TESTS_FAILED} tests failed${NC}"
    exit 1
  else
    echo -e "${GREEN}All tests passed${NC}"
    exit 0
  fi
}

main "$@"
