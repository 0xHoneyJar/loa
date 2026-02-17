#!/usr/bin/env bash
# =============================================================================
# PreToolUse:Bash Team Role Guard — Enforce Lead-Only Operations
# =============================================================================
# When LOA_TEAM_MEMBER is set (indicating a teammate context in Agent Teams
# mode), blocks patterns that are restricted to the team lead:
#   - beads (br) commands          → C-TEAM-002
#   - .run/ state file writes      → C-TEAM-003
#   - git commit/push              → C-TEAM-004
#   - .claude/ mutations           → C-TEAM-005
#
# When LOA_TEAM_MEMBER is unset or empty, this hook is a complete no-op.
# Single-agent mode is unaffected.
#
# IMPORTANT: No set -euo pipefail — this hook must never fail closed.
# A grep or jq failure must result in exit 0 (allow), not an error.
# Fail-open with logging is the standard pattern for inline security hooks.
# (cf. block-destructive-bash.sh, ModSecurity DetectionOnly mode)
#
# WHY fail-open: A safety hook that crashes must NOT block the agent from
# operating. Fail-closed would make jq/grep bugs into denial-of-service
# attacks against the agent.
#
# WHY ERE not PCRE: grep -E (Extended Regex) is POSIX and universally
# available. grep -P (PCRE) is a GNU extension not available on macOS/BSD.
#
# Registered in settings.hooks.json as PreToolUse matcher: "Bash"
# Part of Agent Teams Compatibility (cycle-020, issue #337)
# Source: Bridgebuilder SPECULATION-1 (bridge-20260216-c020te iter-1)
# =============================================================================

# Early exit: if not a teammate, allow everything
if [[ -z "${LOA_TEAM_MEMBER:-}" ]]; then
  exit 0
fi

# Read tool input from stdin (JSON with tool_input.command)
input=$(cat)
command=$(echo "$input" | jq -r '.tool_input.command // empty' 2>/dev/null) || true

# If we can't parse the command, allow (don't block on parse errors)
if [[ -z "$command" ]]; then
  exit 0
fi

# ---------------------------------------------------------------------------
# Helper: check pattern and block with message
# Uses extended regex (-E) for universal compatibility (no PCRE required).
# ---------------------------------------------------------------------------
check_and_block() {
  local pattern="$1"
  local message="$2"

  if echo "$command" | grep -qE "$pattern" 2>/dev/null; then
    echo "BLOCKED [team-role-guard]: $message" >&2
    echo "Teammate '$LOA_TEAM_MEMBER' cannot perform this operation. Report to the team lead via SendMessage." >&2
    exit 2
  fi
}

# ---------------------------------------------------------------------------
# C-TEAM-002: Block beads (br) commands
# Matches: br close, br update, br sync, br ready, br create, etc.
# Includes /path/to/br and sudo br for consistency with git patterns.
# ---------------------------------------------------------------------------
check_and_block \
  '(^|/|;|&&|\|)\s*(sudo\s+)?br\s' \
  "Beads (br) commands are lead-only in Agent Teams mode (C-TEAM-002). Report task status to the lead via SendMessage."

# ---------------------------------------------------------------------------
# C-TEAM-003: Block writes to .run/ state files
# Matches: overwrite (>) to .run/*.json, cp/mv to .run/*.json, tee to .run/*.json
# Does NOT match: append (>>) to any .run/ file (append-only is safe)
# Does NOT match: reads (cat .run/state.json without redirect)
# (^|[^>]) anchors at start-of-line AND excludes >> (append).
# ---------------------------------------------------------------------------
check_and_block \
  '(^|[^>])>\s*\.run/[^/]*\.json' \
  "Writing to .run/ state files is lead-only in Agent Teams mode (C-TEAM-003). Report status to the lead via SendMessage."

check_and_block \
  '(cp|mv)\s+.*\s+\.run/[^/]*\.json' \
  "Writing to .run/ state files is lead-only in Agent Teams mode (C-TEAM-003). Report status to the lead via SendMessage."

check_and_block \
  'tee\s+(-[^a]\S*\s+)*\.run/[^/]*\.json' \
  "Writing to .run/ state files via tee is lead-only in Agent Teams mode (C-TEAM-003). Report status to the lead via SendMessage."

# ---------------------------------------------------------------------------
# C-TEAM-005: Block mutations to System Zone (.claude/)
# Matches: cp/mv, redirect (>), tee, sed -i to .claude/ (relative or absolute)
# Does NOT match: reads (cat .claude/...), append (>> .claude/...)
# ---------------------------------------------------------------------------
check_and_block \
  '(cp|mv)\s+.*\s+(\S*/)?\.claude/' \
  "Writing to System Zone (.claude/) is lead-only in Agent Teams mode (C-TEAM-005). Framework files are read-only for teammates."

check_and_block \
  '(^|[^>])>\s*(\S*/)?\.claude/' \
  "Redirect to System Zone (.claude/) is lead-only in Agent Teams mode (C-TEAM-005). Framework files are read-only for teammates."

check_and_block \
  'tee\s+(-[^a]\S*\s+)*(\S*/)?\.claude/' \
  "Writing to System Zone (.claude/) via tee is lead-only in Agent Teams mode (C-TEAM-005). Framework files are read-only for teammates."

check_and_block \
  'sed\s+(-[a-zA-Z]*i|--in-place).*(\S*/)?\.claude/' \
  "In-place editing System Zone (.claude/) files is lead-only in Agent Teams mode (C-TEAM-005). Framework files are read-only for teammates."

check_and_block \
  'install\s+.*(\S*/)?\.claude/' \
  "Using 'install' to write to System Zone (.claude/) is lead-only in Agent Teams mode (C-TEAM-005). Framework files are read-only for teammates."

check_and_block \
  'patch\s+.*(\S*/)?\.claude/' \
  "Patching System Zone (.claude/) files is lead-only in Agent Teams mode (C-TEAM-005). Framework files are read-only for teammates."

# ---------------------------------------------------------------------------
# C-TEAM-004: Block git commit and push
# Matches: git commit, git push
# Does NOT match: git status, git diff, git log (read-only operations)
# ---------------------------------------------------------------------------
check_and_block \
  '(^|;|&&|\|)\s*(sudo\s+)?git\s+commit' \
  "Git commit is lead-only in Agent Teams mode (C-TEAM-004). Report completed work to the lead via SendMessage."

check_and_block \
  '(^|;|&&|\|)\s*(sudo\s+)?git\s+push' \
  "Git push is lead-only in Agent Teams mode (C-TEAM-004). Report completed work to the lead via SendMessage."

# All checks passed — allow execution
exit 0
