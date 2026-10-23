#!/usr/bin/env bash
# =============================================================================
# Invariant Linter Self-Test — "Who Tests the Testers?"
# =============================================================================
# Test harness for lint-invariants.sh itself. Creates temp fixtures with
# known-good and known-bad states, runs the linter, validates output.
#
# Follows the LLVM principle: test the test infrastructure.
#
# Usage:
#   bash .claude/scripts/test-lint-invariants.sh
#   bash .claude/scripts/test-lint-invariants.sh --verbose
#
# Exit codes:
#   0 = all tests pass
#   1 = one or more tests failed
#
# Source: Bridgebuilder Deep Review Critical 3
# Part of Loa Harness Engineering (cycle-011, issue #297)
# =============================================================================

set -uo pipefail

# Resolve absolute path to linter before any cd operations
LINTER_ABS="$(cd "$(dirname ".claude/scripts/lint-invariants.sh")" && pwd)/$(basename ".claude/scripts/lint-invariants.sh")"
PASS=0
FAIL=0
TOTAL=0
VERBOSE=false
TMPDIR_BASE=""

[[ "${1:-}" == "--verbose" ]] && VERBOSE=true

# ---------------------------------------------------------------------------
# Setup / Teardown
# ---------------------------------------------------------------------------
setup_tmpdir() {
  TMPDIR_BASE=$(mktemp -d "${TMPDIR:-/tmp}/lint-invariant-test.XXXXXX")
}

teardown_tmpdir() {
  if [[ -n "$TMPDIR_BASE" && -d "$TMPDIR_BASE" ]]; then
    rm -rf "$TMPDIR_BASE"
  fi
}

trap teardown_tmpdir EXIT

# ---------------------------------------------------------------------------
# Test helpers
# ---------------------------------------------------------------------------
assert_exit_code() {
  local actual="$1"
  local expected="$2"
  local desc="$3"

  TOTAL=$((TOTAL + 1))
  if [[ "$actual" -eq "$expected" ]]; then
    PASS=$((PASS + 1))
    [[ "$VERBOSE" == "true" ]] && printf "  [PASS] %s\n" "$desc"
  else
    FAIL=$((FAIL + 1))
    printf "  [FAIL] %s (expected exit %d, got %d)\n" "$desc" "$expected" "$actual"
  fi
}

assert_output_contains() {
  local output="$1"
  local pattern="$2"
  local desc="$3"

  TOTAL=$((TOTAL + 1))
  if echo "$output" | grep -q "$pattern"; then
    PASS=$((PASS + 1))
    [[ "$VERBOSE" == "true" ]] && printf "  [PASS] %s\n" "$desc"
  else
    FAIL=$((FAIL + 1))
    printf "  [FAIL] %s (pattern '%s' not found)\n" "$desc" "$pattern"
  fi
}

assert_valid_json() {
  local output="$1"
  local desc="$2"

  TOTAL=$((TOTAL + 1))
  if echo "$output" | jq empty 2>/dev/null; then
    PASS=$((PASS + 1))
    [[ "$VERBOSE" == "true" ]] && printf "  [PASS] %s\n" "$desc"
  else
    FAIL=$((FAIL + 1))
    printf "  [FAIL] %s (invalid JSON)\n" "$desc"
  fi
}

# Run linter in a directory, capturing output and exit code separately
run_linter_in() {
  local dir="$1"
  shift
  # Run in subshell, capture output. Use explicit exit code capture.
  local output exit_code
  output=$(cd "$dir" && bash "$LINTER_ABS" "$@" 2>&1) && exit_code=0 || exit_code=$?
  echo "$exit_code"
  echo "---OUTPUT---"
  echo "$output"
}

parse_result() {
  local result="$1"
  RESULT_EXIT=$(echo "$result" | head -1)
  RESULT_OUTPUT=$(echo "$result" | sed '1d;/^---OUTPUT---$/d')
}

# ---------------------------------------------------------------------------
# Create a minimal known-good project fixture
# ---------------------------------------------------------------------------
create_good_fixture() {
  local dir="$1"
  mkdir -p "$dir/.claude/loa" "$dir/.claude/data" "$dir/.claude/hooks/safety" "$dir/.claude/hooks/audit" "$dir/.claude/hooks" "$dir/.claude/scripts"

  # CLAUDE.loa.md with managed header and constraint blocks
  cat > "$dir/.claude/loa/CLAUDE.loa.md" << 'MDEOF'
<!-- @loa-managed: true | version: 1.34.0 | hash: testfixture -->

# Loa Framework Instructions

## Process Compliance

### NEVER Rules
<!-- @constraint-generated: start process_compliance_never | hash:test -->
| Rule |
<!-- @constraint-generated: end process_compliance_never -->

### ALWAYS Rules
<!-- @constraint-generated: start process_compliance_always | hash:test -->
| Rule |
<!-- @constraint-generated: end process_compliance_always -->

### Task Tracking
<!-- @constraint-generated: start task_tracking_hierarchy | hash:test -->
| Tool |
<!-- @constraint-generated: end task_tracking_hierarchy -->
MDEOF

  # Version file
  echo '{"version": "1.34.0"}' > "$dir/.loa-version.json"

  # Config file
  echo "run_mode:" > "$dir/.loa.config.yaml"
  echo "  enabled: true" >> "$dir/.loa.config.yaml"

  # Constraints JSON
  echo '{"constraints": []}' > "$dir/.claude/data/constraints.json"

  # settings.hooks.json
  cat > "$dir/.claude/hooks/settings.hooks.json" << 'HOOKEOF'
{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"test"}]}],"PostToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"test"}]}],"Stop":[{"matcher":"","hooks":[{"type":"command","command":"test"}]}]}}
HOOKEOF

  # Hook scripts (executable)
  for f in pre-compact-marker.sh post-compact-reminder.sh; do
    echo '#!/usr/bin/env bash' > "$dir/.claude/hooks/$f"
    chmod +x "$dir/.claude/hooks/$f"
  done
  echo '#!/usr/bin/env bash' > "$dir/.claude/hooks/safety/block-destructive-bash.sh"
  chmod +x "$dir/.claude/hooks/safety/block-destructive-bash.sh"
  echo '#!/usr/bin/env bash' > "$dir/.claude/hooks/safety/run-mode-stop-guard.sh"
  chmod +x "$dir/.claude/hooks/safety/run-mode-stop-guard.sh"
  echo '#!/usr/bin/env bash' > "$dir/.claude/hooks/audit/mutation-logger.sh"
  chmod +x "$dir/.claude/hooks/audit/mutation-logger.sh"

  # Stub test scripts so invariants 8/9 find them
  # Safety hook test: always pass (stub)
  cat > "$dir/.claude/scripts/test-safety-hooks.sh" << 'STUBEOF'
#!/usr/bin/env bash
exit 0
STUBEOF
  chmod +x "$dir/.claude/scripts/test-safety-hooks.sh"

  # Deny rule verify: always pass (stub)
  cat > "$dir/.claude/scripts/verify-deny-rules.sh" << 'STUBEOF'
#!/usr/bin/env bash
exit 0
STUBEOF
  chmod +x "$dir/.claude/scripts/verify-deny-rules.sh"

  # Initialize git repo so system-zone check works
  (cd "$dir" && git init -q && git add -A && git commit -q -m "init" 2>/dev/null) || true
}

# ---------------------------------------------------------------------------
# Create a known-bad fixture (missing files, invalid JSON)
# ---------------------------------------------------------------------------
create_bad_fixture() {
  local dir="$1"
  mkdir -p "$dir/.claude/loa" "$dir/.claude/data" "$dir/.claude/hooks"

  # CLAUDE.loa.md without managed header, no constraint blocks
  echo "# Bad CLAUDE.loa.md" > "$dir/.claude/loa/CLAUDE.loa.md"

  # Missing .loa-version.json (intentionally)

  # Config file
  echo "run_mode:" > "$dir/.loa.config.yaml"

  # Invalid JSON for constraints
  echo "not valid json" > "$dir/.claude/data/constraints.json"

  # settings.hooks.json (valid but minimal)
  echo '{"hooks":{}}' > "$dir/.claude/hooks/settings.hooks.json"

  # Initialize git
  (cd "$dir" && git init -q && git add -A && git commit -q -m "init" 2>/dev/null) || true
}

echo "Invariant Linter Self-Test"
echo "=========================="
echo "Linter: $LINTER_ABS"
echo ""

if [[ ! -f "$LINTER_ABS" ]]; then
  echo "ERROR: Linter not found at $LINTER_ABS"
  exit 1
fi

setup_tmpdir

# =========================================================================
# Test 1: Good fixture — all pass (exit 0 or 1 with WARNs)
# =========================================================================
echo "--- Test: Known-good fixture ---"
good_dir="$TMPDIR_BASE/good"
create_good_fixture "$good_dir"

result=$(run_linter_in "$good_dir")
parse_result "$result"

# Good fixture should have no ERRORs. May have WARNs (exit 1) from
# environment-dependent checks like deny rules.
assert_exit_code "$RESULT_EXIT" 0 "good fixture exits 0 (all pass or warns only)"
assert_output_contains "$RESULT_OUTPUT" "PASS" "good fixture has PASS results"
assert_output_contains "$RESULT_OUTPUT" "pass" "good fixture summary shows passes"

# =========================================================================
# Test 2: Bad fixture — errors found (exit 2)
# =========================================================================
echo ""
echo "--- Test: Known-bad fixture ---"
bad_dir="$TMPDIR_BASE/bad"
create_bad_fixture "$bad_dir"

result=$(run_linter_in "$bad_dir")
parse_result "$result"

assert_exit_code "$RESULT_EXIT" 2 "bad fixture exits 2 (errors found)"
assert_output_contains "$RESULT_OUTPUT" "ERR" "bad fixture has ERROR results"
assert_output_contains "$RESULT_OUTPUT" "constraints" "bad fixture reports constraints error"

# =========================================================================
# Test 3: JSON output is valid
# =========================================================================
echo ""
echo "--- Test: --json output ---"

result=$(run_linter_in "$good_dir" --json)
parse_result "$result"
assert_valid_json "$RESULT_OUTPUT" "good fixture --json produces valid JSON"

result=$(run_linter_in "$bad_dir" --json)
parse_result "$result"
assert_valid_json "$RESULT_OUTPUT" "bad fixture --json produces valid JSON"

# Verify JSON structure has expected fields
TOTAL=$((TOTAL + 1))
result=$(run_linter_in "$good_dir" --json)
parse_result "$result"
if echo "$RESULT_OUTPUT" | jq -e '.summary.pass' >/dev/null 2>&1; then
  PASS=$((PASS + 1))
  [[ "$VERBOSE" == "true" ]] && printf "  [PASS] JSON has summary.pass field\n"
else
  FAIL=$((FAIL + 1))
  printf "  [FAIL] JSON missing summary.pass field\n"
fi

TOTAL=$((TOTAL + 1))
if echo "$RESULT_OUTPUT" | jq -e '.results | length > 0' >/dev/null 2>&1; then
  PASS=$((PASS + 1))
  [[ "$VERBOSE" == "true" ]] && printf "  [PASS] JSON has non-empty results array\n"
else
  FAIL=$((FAIL + 1))
  printf "  [FAIL] JSON results array is empty\n"
fi

# =========================================================================
# Test 4: Exit codes match documentation
# =========================================================================
echo ""
echo "--- Test: Exit code semantics ---"

# Good fixture: 0 = all pass (with stub test scripts)
result=$(run_linter_in "$good_dir")
parse_result "$result"
assert_exit_code "$RESULT_EXIT" 0 "exit 0 = all pass (good fixture)"

# Bad fixture: 2 = errors found (missing files + invalid JSON)
result=$(run_linter_in "$bad_dir")
parse_result "$result"
assert_exit_code "$RESULT_EXIT" 2 "exit 2 = errors found (bad fixture)"

# =========================================================================
# Test 5: --fix mode runs without crashing
# =========================================================================
echo ""
echo "--- Test: --fix mode ---"
fix_dir="$TMPDIR_BASE/fix"
create_bad_fixture "$fix_dir"

result=$(run_linter_in "$fix_dir" --fix)
parse_result "$result"

# --fix should still report errors for things it can't fix (invalid JSON)
TOTAL=$((TOTAL + 1))
if [[ "$RESULT_EXIT" -le 2 ]]; then
  PASS=$((PASS + 1))
  [[ "$VERBOSE" == "true" ]] && printf "  [PASS] --fix mode runs without crash\n"
else
  FAIL=$((FAIL + 1))
  printf "  [FAIL] --fix mode crashed (exit %d)\n" "$RESULT_EXIT"
fi

# =========================================================================
# Summary
# =========================================================================
echo ""
echo "=============================="
printf "Results: %d pass, %d fail (of %d total)\n" "$PASS" "$FAIL" "$TOTAL"
echo "=============================="

if [[ "$FAIL" -eq 0 ]]; then
  echo "All tests passed."
  exit 0
else
  echo "FAILURES DETECTED."
  exit 1
fi
