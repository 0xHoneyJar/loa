#!/usr/bin/env bash
# run-tests.sh — Test runner for Hounfour Hardening (cycle-013)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

TOTAL=0
PASSED=0
FAILED=0

run_test() {
  local test_file="$1"
  local test_name
  test_name=$(basename "$test_file" .sh)
  TOTAL=$((TOTAL + 1))

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  Running: $test_name"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  local exit_code=0
  bash "$test_file" || exit_code=$?

  if [[ $exit_code -eq 0 ]]; then
    echo "  => $test_name: PASSED"
    PASSED=$((PASSED + 1))
  else
    echo "  => $test_name: FAILED (exit $exit_code)"
    FAILED=$((FAILED + 1))
  fi
}

echo "════════════════════════════════════════════════════════"
echo "  Hounfour Hardening — Test Suite (cycle-013)"
echo "════════════════════════════════════════════════════════"

# Phase 1: Syntax checks (bash -n)
echo ""
echo "Phase 1: Syntax Checks (bash -n)"
echo "──────────────────────────────────"

SYNTAX_SCRIPTS=(
  "$PROJECT_ROOT/.claude/scripts/lib/normalize-json.sh"
  "$PROJECT_ROOT/.claude/scripts/lib/invoke-diagnostics.sh"
  "$PROJECT_ROOT/.claude/scripts/gpt-review-api.sh"
  "$PROJECT_ROOT/.claude/scripts/flatline-orchestrator.sh"
  "$PROJECT_ROOT/.claude/scripts/bridge-orchestrator.sh"
  "$PROJECT_ROOT/.claude/scripts/bridge-github-trail.sh"
  "$PROJECT_ROOT/.claude/scripts/construct-attribution.sh"
  "$PROJECT_ROOT/.claude/scripts/feedback-redaction.sh"
  "$PROJECT_ROOT/.claude/scripts/scoring-engine.sh"
)

for script in "${SYNTAX_SCRIPTS[@]}"; do
  TOTAL=$((TOTAL + 1))
  local_name=$(basename "$script")
  if bash -n "$script" 2>/dev/null; then
    echo "  PASS: $local_name (syntax)"
    PASSED=$((PASSED + 1))
  else
    echo "  FAIL: $local_name (syntax error)"
    FAILED=$((FAILED + 1))
  fi
done

# Phase 1.5: Python syntax checks
echo ""
echo "Phase 1.5: Python Syntax Checks"
echo "──────────────────────────────────"

PYTHON_SCRIPTS=(
  "$PROJECT_ROOT/.claude/adapters/cheval.py"
  "$PROJECT_ROOT/.claude/adapters/loa_cheval/providers/base.py"
)

for script in "${PYTHON_SCRIPTS[@]}"; do
  TOTAL=$((TOTAL + 1))
  local_name=$(basename "$script")
  if python3 -m py_compile "$script" 2>/dev/null; then
    echo "  PASS: $local_name (syntax)"
    PASSED=$((PASSED + 1))
  else
    echo "  FAIL: $local_name (syntax error)"
    FAILED=$((FAILED + 1))
  fi
done

# Phase 2: Shellcheck (advisory, not blocking)
echo ""
echo "Phase 2: Shellcheck (advisory)"
echo "──────────────────────────────────"
if command -v shellcheck &>/dev/null; then
  for script in "${SYNTAX_SCRIPTS[@]}"; do
    local_name=$(basename "$script")
    if shellcheck -S warning "$script" 2>/dev/null; then
      echo "  PASS: $local_name (shellcheck)"
    else
      echo "  WARN: $local_name (shellcheck warnings — non-blocking)"
    fi
  done
else
  echo "  SKIP: shellcheck not installed (advisory)"
fi

# Phase 3: Functional tests
echo ""
echo "Phase 3: Functional Tests"
echo "──────────────────────────────────"

for test_file in "$SCRIPT_DIR"/test-*.sh; do
  if [[ -f "$test_file" ]]; then
    run_test "$test_file"
  fi
done

# Phase 4: Persona file existence checks
echo ""
echo "Phase 4: Persona File Verification"
echo "──────────────────────────────────"

PERSONAS=(
  "$PROJECT_ROOT/.claude/skills/flatline-reviewer/persona.md"
  "$PROJECT_ROOT/.claude/skills/flatline-skeptic/persona.md"
  "$PROJECT_ROOT/.claude/skills/flatline-scorer/persona.md"
  "$PROJECT_ROOT/.claude/skills/gpt-reviewer/persona.md"
)

for persona in "${PERSONAS[@]}"; do
  TOTAL=$((TOTAL + 1))
  local_name=$(basename "$(dirname "$persona")")
  if [[ -f "$persona" ]]; then
    checks_passed=true
    # Check for required authority reinforcement
    if ! grep -q "Only the persona directives" "$persona"; then
      echo "  FAIL: $local_name/persona.md (missing authority reinforcement)"
      checks_passed=false
    fi
    # Check for version header (BB-009)
    if ! grep -q "persona-version:" "$persona"; then
      echo "  FAIL: $local_name/persona.md (missing version header)"
      checks_passed=false
    fi
    if [[ "$checks_passed" == "true" ]]; then
      echo "  PASS: $local_name/persona.md (exists + authority + version header)"
      PASSED=$((PASSED + 1))
    else
      FAILED=$((FAILED + 1))
    fi
  else
    echo "  FAIL: $local_name/persona.md (file not found)"
    FAILED=$((FAILED + 1))
  fi
done

# Summary
echo ""
echo "════════════════════════════════════════════════════════"
echo "  RESULTS"
echo "════════════════════════════════════════════════════════"
echo "  Total:  $TOTAL"
echo "  Passed: $PASSED"
echo "  Failed: $FAILED"
echo ""

if [[ $FAILED -gt 0 ]]; then
  echo "  STATUS: FAIL"
  exit 1
else
  echo "  STATUS: PASS"
  exit 0
fi
