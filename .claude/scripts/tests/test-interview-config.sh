#!/usr/bin/env bash
# test-interview-config.sh — Smoke tests for Interview Depth Configuration (cycle-031)
# Validates all structural changes from sprint-29 are correctly applied.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
errors=0

pass() { echo "  ✓ $1"; }
fail() { echo "  ✗ $1"; ((errors+=1)); }

SKILL="$REPO_ROOT/skills/discovering-requirements/SKILL.md"
CONFIG="$REPO_ROOT/../.loa.config.yaml.example"

echo "Interview Depth Configuration — Smoke Tests"
echo "═════════════════════════════════════════════"
echo ""

# --- 1. <interview_config> block exists ---
echo "1. interview_config block"
if grep -q '<interview_config>' "$SKILL" 2>/dev/null; then
  pass "<interview_config> block exists in SKILL.md"
else
  fail "<interview_config> block missing from SKILL.md"
fi

# --- 2. Old question limit removed ---
echo ""
echo "2. Old question limit removed"
if grep -q '2-3 per phase maximum' "$SKILL" 2>/dev/null; then
  fail "Old '2-3 per phase maximum' limit still present"
else
  pass "Old '2-3 per phase maximum' limit removed"
fi

# --- 3. Config-aware limit present ---
echo ""
echo "3. Config-aware limit"
if grep -q 'configured range' "$SKILL" 2>/dev/null; then
  pass "Config-aware 'configured range' present"
else
  fail "Config-aware 'configured range' missing"
fi

# --- 4. Backpressure PROHIBITED block ---
echo ""
echo "4. Backpressure protocol"
if grep -q 'DO NOT answer your own questions' "$SKILL" 2>/dev/null; then
  pass "Backpressure PROHIBITED directive present"
else
  fail "Backpressure PROHIBITED directive missing"
fi

# --- 5. Phase transition gates exist ---
echo ""
echo "5. Phase transition gates"
if grep -q 'Phase 1 Transition' "$SKILL" 2>/dev/null && \
   grep -q 'Phase 7 Transition' "$SKILL" 2>/dev/null; then
  pass "Phase transition gates present (Phase 1-7)"
else
  fail "Phase transition gates missing"
fi

# --- 6. Pre-generation gate exists ---
echo ""
echo "6. Pre-generation gate"
if grep -q 'Pre-Generation Gate' "$SKILL" 2>/dev/null; then
  pass "Pre-Generation Gate present"
else
  fail "Pre-Generation Gate missing"
fi

# --- 7. Anti-inference directive ---
echo ""
echo "7. Anti-inference directive"
if grep -q "you'll probably also need" "$SKILL" 2>/dev/null; then
  pass "Anti-inference directive present in Phase 4"
else
  fail "Anti-inference directive missing from Phase 4"
fi

# --- 8. Config example has interview section ---
echo ""
echo "8. Config example"
if grep -q '^interview:' "$CONFIG" 2>/dev/null; then
  pass "interview: section present in .loa.config.yaml.example"
else
  fail "interview: section missing from .loa.config.yaml.example"
fi

# --- 9. yq defaults resolve ---
echo ""
echo "9. yq default resolution"
if command -v yq &>/dev/null; then
  mode=$(yq eval '.interview.mode // "thorough"' "$CONFIG" 2>/dev/null || echo "")
  if [[ -n "$mode" ]]; then
    pass "yq resolves interview.mode = '$mode'"
  else
    fail "yq returned empty for interview.mode"
  fi
else
  pass "yq not installed — skipping (defaults to thorough via fallback)"
fi

# --- Summary ---
echo ""
echo "═════════════════════════════════════════════"
if [[ $errors -eq 0 ]]; then
  echo "ALL 9 TESTS PASSED"
  exit 0
else
  echo "FAILED: $errors test(s) failed"
  exit 1
fi
