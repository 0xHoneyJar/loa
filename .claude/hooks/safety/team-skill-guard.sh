#!/usr/bin/env bash
# =============================================================================
# PreToolUse:Skill Team Role Guard — Enforce Lead-Only Skill Invocations
# =============================================================================
# When LOA_TEAM_MEMBER is set (indicating a teammate context in Agent Teams
# mode), blocks skill invocations that are restricted to the team lead:
#   - /plan-and-analyze, /architect, /sprint-plan     → C-TEAM-001
#   - /simstim, /autonomous                           → C-TEAM-001
#   - /run-sprint-plan, /run-bridge, /run             → C-TEAM-001
#   - /ride, /update-loa, /ship, /deploy-production   → C-TEAM-001
#   - /mount, /loa-eject, /loa-setup, /plan           → C-TEAM-001
#   - /archive-cycle, /flatline-review, /constructs   → C-TEAM-001
#   - /eval                                           → C-TEAM-001
#
# When LOA_TEAM_MEMBER is unset or empty, this hook is a complete no-op.
# Single-agent mode is unaffected.
#
# IMPORTANT: No set -euo pipefail — this hook must never fail closed.
# A jq failure must result in exit 0 (allow), not an error.
# Fail-open with logging is the standard pattern for inline security hooks.
#
# Registered in settings.hooks.json as PreToolUse matcher: "Skill"
# Part of Agent Teams Compatibility (cycle-020, issue #337)
# Source: Sprint 4 — Advisory-to-Mechanical Promotion
# =============================================================================

# Early exit: if not a teammate, allow everything
if [[ -z "${LOA_TEAM_MEMBER:-}" ]]; then
  exit 0
fi

# Read tool input from stdin (JSON with tool_input.skill)
input=$(cat)
skill=$(echo "$input" | jq -r '.tool_input.skill // empty' 2>/dev/null) || true

# If we can't parse the skill name, allow (don't block on parse errors)
if [[ -z "$skill" ]]; then
  exit 0
fi

# Strip namespace prefix if present (e.g., "projectSettings:plan-and-analyze" -> "plan-and-analyze")
skill="${skill##*:}"

# Re-check after stripping (e.g., trailing colon "plan-and-analyze:" -> empty)
if [[ -z "$skill" ]]; then
  exit 0
fi

# ---------------------------------------------------------------------------
# C-TEAM-001: Lead-only skill blocklist
# These skills produce single shared artifacts (PRD, SDD, sprint plan, state
# files) or orchestrate workflows that assume single-agent control.
# Teammate-allowed skills: implement, review-sprint, audit-sprint, bug,
# review, build, feedback, translate, validate, audit, and others.
# ---------------------------------------------------------------------------
LEAD_ONLY_SKILLS=(
  "plan-and-analyze"
  "architect"
  "sprint-plan"
  "simstim"
  "autonomous"
  "run-sprint-plan"  # belt-and-suspenders: also caught by "run" for /run sprint-plan
  "run-bridge"
  "run"
  "ride"
  "update-loa"
  "ship"
  "deploy-production"
  "mount"
  "loa-eject"
  "loa-setup"
  "plan"
  "archive-cycle"
  "flatline-review"
  "constructs"
  "eval"
)

for blocked in "${LEAD_ONLY_SKILLS[@]}"; do
  if [[ "$skill" == "$blocked" ]]; then
    echo "BLOCKED [team-skill-guard]: Skill /$skill is lead-only in Agent Teams mode (C-TEAM-001)." >&2
    echo "Teammate '$LOA_TEAM_MEMBER' cannot invoke planning/orchestration skills. Report to the team lead via SendMessage." >&2
    exit 2
  fi
done

# All checks passed — allow the skill invocation
exit 0
