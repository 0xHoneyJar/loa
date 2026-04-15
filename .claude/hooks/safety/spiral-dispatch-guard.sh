#!/usr/bin/env bash
# =============================================================================
# PreToolUse:Write/Edit — Spiral Dispatch Guard (Mechanical Enforcement)
# =============================================================================
# When /spiraling has been invoked with a task (detected via simstim state
# or spiral sentinel), blocks direct Write/Edit to application and framework
# code unless spiral-harness.sh has been dispatched.
#
# This is the MECHANICAL layer that prevents the agent from bypassing the
# pipeline. The agent-level layers (SKILL.md guard, C-PROC-017, CLAUDE.loa.md)
# are instructions. This hook is enforcement.
#
# Exit 0 = allow, Exit 2 = block (stderr message fed back to agent).
#
# IMPORTANT: No set -euo pipefail — fail-open. Parse errors must not block.
#
# Registered in settings.hooks.json as PreToolUse matcher: "Write" and "Edit"
# Part of Spiral Cost Optimization (cycle-072)
# Source: PR #506 incident — agent bypassed all quality gates
# =============================================================================

# Read tool input from stdin
input=$(cat)
file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || true

# If we can't parse the file path, allow
if [[ -z "$file_path" ]]; then
    exit 0
fi

# ---------------------------------------------------------------------------
# Check 1: Is the spiral dispatch guard active?
# The sentinel file is created when /spiraling is invoked with a task.
# It's removed when spiral-harness.sh completes or when /spiraling exits.
# ---------------------------------------------------------------------------
SENTINEL="${LOA_PROJECT_ROOT:-.}/.run/spiral-dispatch-active"

if [[ ! -f "$SENTINEL" ]]; then
    # No active spiral dispatch — allow all writes
    exit 0
fi

# ---------------------------------------------------------------------------
# Check 2: Has the harness been dispatched?
# If spiral-harness.sh is running (or has produced a flight recorder),
# the agent is operating within the pipeline — allow writes.
# ---------------------------------------------------------------------------
HARNESS_DISPATCHED="${LOA_PROJECT_ROOT:-.}/.run/spiral-harness-dispatched"

if [[ -f "$HARNESS_DISPATCHED" ]]; then
    # Harness is running — agent is within the pipeline, allow writes
    exit 0
fi

# ---------------------------------------------------------------------------
# Check 3: Is this a write to grimoires/ (planning artifacts)?
# Planning artifacts (PRD, SDD, sprint) are allowed during the simstim
# planning phases. Only application/framework code is blocked.
# ---------------------------------------------------------------------------
case "$file_path" in
    */grimoires/*)
        exit 0  # Planning artifacts allowed
        ;;
    */.run/*)
        exit 0  # State files allowed
        ;;
    */.beads/*)
        exit 0  # Beads state allowed
        ;;
    */.claude/plans/*)
        exit 0  # Plan files allowed
        ;;
esac

# ---------------------------------------------------------------------------
# BLOCK: Agent is trying to write application/framework code while
# /spiraling is active but harness hasn't been dispatched.
# ---------------------------------------------------------------------------
echo "BLOCKED [spiral-dispatch-guard]: Write to '$file_path' blocked." >&2
echo "" >&2
echo "/spiraling is active but spiral-harness.sh has not been dispatched." >&2
echo "You MUST route implementation through the pipeline:" >&2
echo "  1. /simstim — for full HITL cycle" >&2
echo "  2. /run sprint-plan — if sprint plan exists" >&2
echo "  3. spiral-harness.sh — for autonomous execution" >&2
echo "" >&2
echo "Do NOT implement code directly in conversation. (C-PROC-017)" >&2
echo "See: .claude/skills/spiraling/SKILL.md dispatch guard" >&2
exit 2
