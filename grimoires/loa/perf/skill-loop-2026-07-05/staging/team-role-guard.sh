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
# perf pass-2 (2026-07-05, skill-loop): fork/exec reduction. The 13
# `echo | grep -qE` dispatches (11 spawns before the first block on the
# common teammate paths) are replaced by bash [[ =~ ]] over grep's per-line
# model (see _match). GNU shorthand classes were expanded to their exact
# grep-documented definitions (`\s` ≡ [[:space:]], `\S` ≡ [^[:space:]])
# because bash =~ compiles with the SYSTEM regex library and BSD libc has
# no \s/\S. stdin now streams straight into jq (no cat spawn / echo-pipe).
#
# Registered in settings.hooks.json as PreToolUse matcher: "Bash"
# Part of Agent Teams Compatibility (cycle-020, issue #337)
# Source: Bridgebuilder SPECULATION-1 (bridge-20260216-c020te iter-1)
# =============================================================================

# Early exit: if not a teammate, allow everything
if [[ -z "${LOA_TEAM_MEMBER:-}" ]]; then
  exit 0
fi

# perf pass-2: pin byte-oriented ASCII regex semantics (patterns are pure
# ASCII; this matches what the test/golden harness already pins).
export LC_ALL=C

# Read tool input from stdin (JSON with tool_input.command).
# perf pass-2: jq reads the hook's stdin directly — same bytes, same jq
# program; the interim $(cat) copy and echo-pipe only added 2 forks.
command=$(jq -r '.tool_input.command // empty' 2>/dev/null) || true

# If we can't parse the command, allow (don't block on parse errors)
if [[ -z "$command" ]]; then
  exit 0
fi

# ---------------------------------------------------------------------------
# perf pass-2 line-model helper (see block-destructive-bash.sh for the full
# rationale): grep -qE tests per LINE; [[ =~ ]] tests the whole string. Split
# $command into grep's line model once and test per line — byte-identical
# semantics, zero spawns. Invalid regex → silent non-match, same as the old
# `grep -qE … 2>/dev/null`.
# ---------------------------------------------------------------------------
_cmd_lines=()
if [[ "$command" == *$'\n'* ]]; then
  mapfile -t _cmd_lines <<<"${command%$'\n'}"
else
  _cmd_lines=("$command")
fi

_match() {
  local _l
  for _l in "${_cmd_lines[@]}"; do
    [[ "$_l" =~ $1 ]] && return 0
  done
  return 1
}

# ---------------------------------------------------------------------------
# Helper: check pattern and block with message
# Uses extended regex for universal compatibility (no PCRE required).
# ---------------------------------------------------------------------------
check_and_block() {
  local pattern="$1"
  local message="$2"

  if _match "$pattern"; then
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
  '(^|/|;|&&|\|)[[:space:]]*(sudo[[:space:]]+)?br[[:space:]]' \
  "Beads (br) commands are lead-only in Agent Teams mode (C-TEAM-002). Report task status to the lead via SendMessage."

# ---------------------------------------------------------------------------
# C-TEAM-003: Block writes to .run/ state files
# Matches: overwrite (>) to .run/*.json, cp/mv to .run/*.json, tee to .run/*.json
# Does NOT match: append (>>) to any .run/ file (append-only is safe)
# Does NOT match: reads (cat .run/state.json without redirect)
# (^|[^>]) anchors at start-of-line AND excludes >> (append).
# ---------------------------------------------------------------------------
check_and_block \
  '(^|[^>])>[[:space:]]*\.run/[^/]*\.json' \
  "Writing to .run/ state files is lead-only in Agent Teams mode (C-TEAM-003). Report status to the lead via SendMessage."

check_and_block \
  '(cp|mv)[[:space:]]+.*[[:space:]]+\.run/[^/]*\.json' \
  "Writing to .run/ state files is lead-only in Agent Teams mode (C-TEAM-003). Report status to the lead via SendMessage."

check_and_block \
  'tee[[:space:]]+(-[^a][^[:space:]]*[[:space:]]+)*\.run/[^/]*\.json' \
  "Writing to .run/ state files via tee is lead-only in Agent Teams mode (C-TEAM-003). Report status to the lead via SendMessage."

# ---------------------------------------------------------------------------
# C-TEAM-005: Block mutations to System Zone (.claude/)
# Matches: cp/mv, redirect (>), tee, sed -i to .claude/ (relative or absolute)
# Does NOT match: reads (cat .claude/...), append (>> .claude/...)
# ---------------------------------------------------------------------------
check_and_block \
  '(cp|mv)[[:space:]]+.*[[:space:]]+([^[:space:]]*/)?\.claude/' \
  "Writing to System Zone (.claude/) is lead-only in Agent Teams mode (C-TEAM-005). Framework files are read-only for teammates."

check_and_block \
  '(^|[^>])>[[:space:]]*([^[:space:]]*/)?\.claude/' \
  "Redirect to System Zone (.claude/) is lead-only in Agent Teams mode (C-TEAM-005). Framework files are read-only for teammates."

check_and_block \
  'tee[[:space:]]+(-[^a][^[:space:]]*[[:space:]]+)*([^[:space:]]*/)?\.claude/' \
  "Writing to System Zone (.claude/) via tee is lead-only in Agent Teams mode (C-TEAM-005). Framework files are read-only for teammates."

check_and_block \
  'sed[[:space:]]+(-[a-zA-Z]*i|--in-place).*([^[:space:]]*/)?\.claude/' \
  "In-place editing System Zone (.claude/) files is lead-only in Agent Teams mode (C-TEAM-005). Framework files are read-only for teammates."

check_and_block \
  'install[[:space:]]+.*([^[:space:]]*/)?\.claude/' \
  "Using 'install' to write to System Zone (.claude/) is lead-only in Agent Teams mode (C-TEAM-005). Framework files are read-only for teammates."

check_and_block \
  'patch[[:space:]]+.*([^[:space:]]*/)?\.claude/' \
  "Patching System Zone (.claude/) files is lead-only in Agent Teams mode (C-TEAM-005). Framework files are read-only for teammates."

# ---------------------------------------------------------------------------
# C-TEAM-004: Block git commit and push
# Matches: git commit, git push (including env/sudo wrappers)
# Does NOT match: git status, git diff, git log (read-only operations)
# ---------------------------------------------------------------------------
check_and_block \
  '(^|;|&&|\|)[[:space:]]*(sudo[[:space:]]+|env[[:space:]]+[^;]*[[:space:]]+)?git[[:space:]]+commit' \
  "Git commit is lead-only in Agent Teams mode (C-TEAM-004). Report completed work to the lead via SendMessage."

check_and_block \
  '(^|;|&&|\|)[[:space:]]*(sudo[[:space:]]+|env[[:space:]]+[^;]*[[:space:]]+)?git[[:space:]]+push' \
  "Git push is lead-only in Agent Teams mode (C-TEAM-004). Report completed work to the lead via SendMessage."

# ---------------------------------------------------------------------------
# ATK-011: Block LOA_TEAM_MEMBER unset attempts
# Matches: unset LOA_TEAM_MEMBER, env -u LOA_TEAM_MEMBER
# Prevents teammate from removing their own role identity to bypass guards.
# ---------------------------------------------------------------------------
check_and_block \
  'unset[[:space:]]+LOA_TEAM_MEMBER' \
  "Cannot unset LOA_TEAM_MEMBER in Agent Teams mode (ATK-011). Team role identity is immutable."

check_and_block \
  'env[[:space:]]+(-[a-zA-Z]*u[a-zA-Z]*[[:space:]]+LOA_TEAM_MEMBER|-u[[:space:]]+LOA_TEAM_MEMBER)' \
  "Cannot remove LOA_TEAM_MEMBER via env wrapper in Agent Teams mode (ATK-011). Team role identity is immutable."

# All checks passed — allow execution
exit 0
