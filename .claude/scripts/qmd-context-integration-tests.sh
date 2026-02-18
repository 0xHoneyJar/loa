#!/usr/bin/env bash
# Integration tests for QMD context injection across skills
# Tests BB-408 through BB-412: verify context flows from query to skill
set -euo pipefail

PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
QUERY_SCRIPT="$PROJECT_ROOT/.claude/scripts/qmd-context-query.sh"

PASS_COUNT=0
FAIL_COUNT=0
TOTAL=0

pass() { PASS_COUNT=$((PASS_COUNT + 1)); TOTAL=$((TOTAL + 1)); echo "  PASS: $1"; }
fail() { FAIL_COUNT=$((FAIL_COUNT + 1)); TOTAL=$((TOTAL + 1)); echo "  FAIL: $1 — $2"; }

# ============================================================
# 1. /implement integration (BB-408)
# ============================================================
echo "=== BB-408: /implement Context Injection ==="

# Test: SKILL.md contains QMD context instruction
IMPLEMENT_SKILL="$PROJECT_ROOT/.claude/skills/implementing-tasks/SKILL.md"
if grep -q "qmd-context-query.sh" "$IMPLEMENT_SKILL" 2>/dev/null; then
  pass "implementing-tasks/SKILL.md references qmd-context-query.sh"
else
  fail "implementing-tasks/SKILL.md missing qmd-context-query.sh reference" "BB-408 not integrated"
fi

# Test: SKILL.md specifies grimoires scope
if grep -q "\-\-scope grimoires" "$IMPLEMENT_SKILL" 2>/dev/null; then
  pass "implementing-tasks/SKILL.md uses grimoires scope"
else
  fail "implementing-tasks/SKILL.md missing grimoires scope" "Expected --scope grimoires"
fi

# Test: SKILL.md specifies 2000 token budget
if grep -q "\-\-budget 2000" "$IMPLEMENT_SKILL" 2>/dev/null; then
  pass "implementing-tasks/SKILL.md uses 2000 token budget"
else
  fail "implementing-tasks/SKILL.md missing budget 2000" "Expected --budget 2000"
fi

# Test: Graceful no-op instruction present
if grep -q "graceful no-op" "$IMPLEMENT_SKILL" 2>/dev/null; then
  pass "implementing-tasks/SKILL.md includes graceful no-op instruction"
else
  fail "implementing-tasks/SKILL.md missing graceful no-op" "Must degrade gracefully"
fi

# ============================================================
# 2. /review-sprint integration (BB-409)
# ============================================================
echo "=== BB-409: /review-sprint Context Injection ==="

REVIEW_SKILL="$PROJECT_ROOT/.claude/skills/reviewing-code/SKILL.md"
if grep -q "qmd-context-query.sh" "$REVIEW_SKILL" 2>/dev/null; then
  pass "reviewing-code/SKILL.md references qmd-context-query.sh"
else
  fail "reviewing-code/SKILL.md missing qmd-context-query.sh reference" "BB-409 not integrated"
fi

if grep -q "\-\-scope grimoires" "$REVIEW_SKILL" 2>/dev/null; then
  pass "reviewing-code/SKILL.md uses grimoires scope"
else
  fail "reviewing-code/SKILL.md missing grimoires scope" "Expected --scope grimoires"
fi

if grep -q "\-\-budget 1500" "$REVIEW_SKILL" 2>/dev/null; then
  pass "reviewing-code/SKILL.md uses 1500 token budget"
else
  fail "reviewing-code/SKILL.md missing budget 1500" "Expected --budget 1500"
fi

if grep -q "graceful no-op" "$REVIEW_SKILL" 2>/dev/null; then
  pass "reviewing-code/SKILL.md includes graceful no-op instruction"
else
  fail "reviewing-code/SKILL.md missing graceful no-op" "Must degrade gracefully"
fi

# ============================================================
# 3. /ride integration (BB-410)
# ============================================================
echo "=== BB-410: /ride Context Injection ==="

RIDE_SKILL="$PROJECT_ROOT/.claude/skills/riding-codebase/SKILL.md"
if grep -q "qmd-context-query.sh" "$RIDE_SKILL" 2>/dev/null; then
  pass "riding-codebase/SKILL.md references qmd-context-query.sh"
else
  fail "riding-codebase/SKILL.md missing qmd-context-query.sh reference" "BB-410 not integrated"
fi

if grep -q "\-\-scope reality" "$RIDE_SKILL" 2>/dev/null; then
  pass "riding-codebase/SKILL.md uses reality scope"
else
  fail "riding-codebase/SKILL.md missing reality scope" "Expected --scope reality"
fi

if grep -q "\-\-budget 2000" "$RIDE_SKILL" 2>/dev/null; then
  pass "riding-codebase/SKILL.md uses 2000 token budget"
else
  fail "riding-codebase/SKILL.md missing budget 2000" "Expected --budget 2000"
fi

if grep -q "graceful no-op" "$RIDE_SKILL" 2>/dev/null; then
  pass "riding-codebase/SKILL.md includes graceful no-op instruction"
else
  fail "riding-codebase/SKILL.md missing graceful no-op" "Must degrade gracefully"
fi

# ============================================================
# 4. /run-bridge integration (BB-411)
# ============================================================
echo "=== BB-411: /run-bridge Context Injection ==="

BRIDGE_SCRIPT="$PROJECT_ROOT/.claude/scripts/bridge-orchestrator.sh"
if grep -q "load_bridge_context" "$BRIDGE_SCRIPT" 2>/dev/null; then
  pass "bridge-orchestrator.sh contains load_bridge_context function"
else
  fail "bridge-orchestrator.sh missing load_bridge_context" "BB-411 not integrated"
fi

if grep -q "qmd-context-query.sh" "$BRIDGE_SCRIPT" 2>/dev/null; then
  pass "bridge-orchestrator.sh references qmd-context-query.sh"
else
  fail "bridge-orchestrator.sh missing qmd-context-query.sh reference" "Expected query script call"
fi

if grep -q "\-\-budget 2500" "$BRIDGE_SCRIPT" 2>/dev/null; then
  pass "bridge-orchestrator.sh uses 2500 token budget"
else
  fail "bridge-orchestrator.sh missing budget 2500" "Expected --budget 2500"
fi

if grep -q "BRIDGE_CONTEXT" "$BRIDGE_SCRIPT" 2>/dev/null; then
  pass "bridge-orchestrator.sh exports BRIDGE_CONTEXT variable"
else
  fail "bridge-orchestrator.sh missing BRIDGE_CONTEXT variable" "Expected context variable"
fi

# ============================================================
# 5. Gate 0 pre-flight integration (BB-412)
# ============================================================
echo "=== BB-412: Gate 0 Pre-flight Context Injection ==="

PREFLIGHT_SCRIPT="$PROJECT_ROOT/.claude/scripts/preflight.sh"
if grep -q "qmd-context-query.sh" "$PREFLIGHT_SCRIPT" 2>/dev/null; then
  pass "preflight.sh references qmd-context-query.sh"
else
  fail "preflight.sh missing qmd-context-query.sh reference" "BB-412 not integrated"
fi

if grep -q "\-\-scope notes" "$PREFLIGHT_SCRIPT" 2>/dev/null; then
  pass "preflight.sh uses notes scope"
else
  fail "preflight.sh missing notes scope" "Expected --scope notes"
fi

if grep -q "\-\-budget 1000" "$PREFLIGHT_SCRIPT" 2>/dev/null; then
  pass "preflight.sh uses 1000 token budget"
else
  fail "preflight.sh missing budget 1000" "Expected --budget 1000"
fi

if grep -q "Known issues context" "$PREFLIGHT_SCRIPT" 2>/dev/null; then
  pass "preflight.sh surfaces known issues context"
else
  fail "preflight.sh missing known issues output" "Expected context surfacing"
fi

# ============================================================
# 6. Cross-cutting: disabled config produces no context
# ============================================================
echo "=== Cross-cutting: Disabled Config ==="

# Test: query script respects enabled flag
if [[ -x "$QUERY_SCRIPT" ]]; then
  # Create temp config with qmd_context.enabled: false
  TEMP_DIR=$(mktemp -d)
  trap "rm -rf '$TEMP_DIR'" EXIT
  cat > "$TEMP_DIR/.loa.config.yaml" << 'YAML'
qmd_context:
  enabled: false
YAML

  # Run query with disabled config (using temp dir as working context)
  RESULT=$(cd "$TEMP_DIR" && "$QUERY_SCRIPT" --query "test" --scope grimoires --format json 2>/dev/null) || RESULT="[]"
  if [[ "$RESULT" == "[]" ]]; then
    pass "Query returns empty when qmd_context.enabled: false"
  else
    fail "Query returned results when disabled" "Expected empty array, got: $RESULT"
  fi
else
  fail "Query script not executable" "Cannot test disabled config"
fi

# Test: all SKILL.md files reference qmd_context.enabled check
SKILL_CHECK_COUNT=0
for skill_file in "$IMPLEMENT_SKILL" "$REVIEW_SKILL" "$RIDE_SKILL"; do
  if grep -q "qmd_context.enabled" "$skill_file" 2>/dev/null; then
    SKILL_CHECK_COUNT=$((SKILL_CHECK_COUNT + 1))
  fi
done
if [[ $SKILL_CHECK_COUNT -eq 3 ]]; then
  pass "All 3 SKILL.md files check qmd_context.enabled"
else
  fail "Only $SKILL_CHECK_COUNT/3 SKILL.md files check qmd_context.enabled" "All must respect config"
fi

# ============================================================
# Summary
# ============================================================
echo ""
echo "════════════════════════════════════════"
echo "  Integration Tests: $PASS_COUNT/$TOTAL passed"
if [[ $FAIL_COUNT -gt 0 ]]; then
  echo "  FAILURES: $FAIL_COUNT"
  echo "════════════════════════════════════════"
  exit 1
else
  echo "════════════════════════════════════════"
  exit 0
fi
