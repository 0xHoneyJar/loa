#!/usr/bin/env bash
# test-ux-phase2.sh — Smoke tests for UX Redesign Phase 2
# Validates all Phase 2 changes are correctly applied.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
errors=0

pass() { echo "  ✓ $1"; }
fail() { echo "  ✗ $1"; ((errors+=1)); }

echo "UX Redesign Phase 2 — Smoke Tests"
echo "══════════════════════════════════"
echo ""

# --- Post-Completion Debrief (#385) ---
echo "1. Post-Completion Debrief"

for skill in discovering-requirements designing-architecture planning-sprints; do
  file="$REPO_ROOT/skills/$skill/SKILL.md"
  if grep -q '<post_completion>' "$file" 2>/dev/null; then
    pass "$skill has <post_completion>"
  else
    fail "$skill missing <post_completion>"
  fi
done

# --- Free-Text-First /plan (#386) ---
echo ""
echo "2. Free-Text-First /plan"

plan_file="$REPO_ROOT/../.claude/commands/plan.md"
if [[ -f "$REPO_ROOT/commands/plan.md" ]]; then
  plan_file="$REPO_ROOT/commands/plan.md"
fi

if grep -q 'Tell me about your project' "$plan_file" 2>/dev/null; then
  pass "Free-text prompt present in plan.md"
else
  fail "Free-text prompt missing from plan.md"
fi

if grep -q 'Archetype Selection' "$plan_file" 2>/dev/null; then
  fail "Archetype selection UI still present in plan.md"
else
  pass "No archetype selection UI in plan.md"
fi

# Check for the actual AskUserQuestion gate, not comments mentioning it
if grep -q 'Ready to plan your project with Loa?' "$plan_file" 2>/dev/null; then
  fail "Use-case qualification gate still present"
else
  pass "No use-case qualification gate in plan.md"
fi

if grep -q 'I have context files ready' "$plan_file" 2>/dev/null; then
  pass "Context files shortcut option present"
else
  fail "Context files shortcut option missing"
fi

# --- Sprint Time Calibration (#387) ---
echo ""
echo "3. Sprint Time Calibration"

sprint_skill="$REPO_ROOT/skills/planning-sprints/SKILL.md"

if grep -q '2\.5' "$sprint_skill" 2>/dev/null; then
  fail "planning-sprints/SKILL.md still contains '2.5'"
else
  pass "No '2.5 days' in planning-sprints/SKILL.md"
fi

if grep -q 'SMALL.*MEDIUM.*LARGE\|SMALL/MEDIUM/LARGE' "$sprint_skill" 2>/dev/null; then
  pass "SMALL/MEDIUM/LARGE sizing present"
else
  fail "SMALL/MEDIUM/LARGE sizing missing"
fi

# --- Tool Hesitancy Fix (#389) ---
echo ""
echo "4. Tool Hesitancy Fix"

impl_skill="$REPO_ROOT/skills/implementing-tasks/SKILL.md"

if grep -q 'Read/Write.*App zone\|Read/Write.*implementation target' "$impl_skill" 2>/dev/null; then
  pass "App zone shows Read/Write"
else
  fail "App zone does not show Read/Write"
fi

if grep -q '<cli_tool_permissions>' "$impl_skill" 2>/dev/null; then
  pass "<cli_tool_permissions> section exists"
else
  fail "<cli_tool_permissions> section missing"
fi

# --- Tension-Driven /feedback (#388) ---
echo ""
echo "5. Tension-Driven /feedback"

loa_cmd="$REPO_ROOT/commands/loa.md"
if grep -q '/feedback reports it directly' "$loa_cmd" 2>/dev/null; then
  pass "/feedback in doctor warnings (loa.md)"
else
  fail "/feedback missing from doctor warnings"
fi

flatline_tmpl="$REPO_ROOT/templates/flatline-postlude.md.template"
if grep -q '/feedback if you disagree' "$flatline_tmpl" 2>/dev/null; then
  pass "/feedback in Flatline result display"
else
  fail "/feedback missing from Flatline result display"
fi

# --- CLI Permissions ---
echo ""
echo "6. CLI Permissions"

for skill in discovering-requirements designing-architecture planning-sprints; do
  file="$REPO_ROOT/skills/$skill/SKILL.md"
  if grep -q 'read-only CLI tools' "$file" 2>/dev/null; then
    pass "$skill has CLI read-only permission"
  else
    fail "$skill missing CLI read-only permission"
  fi
done

# --- Summary ---
echo ""
echo "══════════════════════════════════"
if [[ $errors -eq 0 ]]; then
  echo "ALL TESTS PASSED"
  exit 0
else
  echo "FAILED: $errors test(s) failed"
  exit 1
fi
