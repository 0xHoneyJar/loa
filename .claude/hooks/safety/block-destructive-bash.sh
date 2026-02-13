#!/usr/bin/env bash
# =============================================================================
# PreToolUse:Bash Safety Hook — Block Destructive Commands
# =============================================================================
# Blocks dangerous patterns and suggests safer alternatives.
# Exit 0 = allow, Exit 2 = block (stderr message fed back to agent).
#
# IMPORTANT: No set -euo pipefail — this hook must never fail closed.
# A grep or jq failure must result in exit 0 (allow), not an error.
#
# WHY fail-open (not fail-closed): A safety hook that crashes or encounters
# a parse error must NOT block the agent from operating. The alternative —
# fail-closed — would make jq/grep bugs into denial-of-service attacks
# against the agent. Fail-open with logging is the standard pattern for
# inline security hooks (cf. ModSecurity DetectionOnly mode).
# (Source: bridge-20260213-c011he iter-1 HIGH-1 fix)
#
# WHY ERE not PCRE: grep -P (PCRE) is a GNU extension not available on
# macOS/BSD or minimal containers. grep -E (Extended Regex) is POSIX and
# universally available. The patterns are slightly more verbose but the
# portability guarantee is non-negotiable for a safety-critical hook.
# (Source: bridge-20260213-c011he iter-1 HIGH-1 fix)
#
# WHY single script for all patterns: Consolidating all destructive command
# patterns into one hook reduces the PreToolUse:Bash execution cost to a
# single script invocation. Multiple hooks would each read stdin, parse JSON,
# and run regex — multiplying latency per command. A single check_and_block()
# helper with sequential patterns is simpler and faster.
#
# Registered in settings.hooks.json as PreToolUse matcher: "Bash"
# Part of Loa Harness Engineering (cycle-011, issue #297)
# Source: Trail of Bits claude-code-config safety patterns
# =============================================================================

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
# Returns 0 if blocked (caller should exit 2), 1 if not matched.
# ---------------------------------------------------------------------------
check_and_block() {
  local pattern="$1"
  local message="$2"

  if echo "$command" | grep -qE "$pattern" 2>/dev/null; then
    echo "BLOCKED: $message" >&2
    exit 2
  fi
}

# ---------------------------------------------------------------------------
# Pattern 1: rm -rf (suggest trash or individual removal)
# ---------------------------------------------------------------------------
# Matches: rm -rf, rm -fr, rm -rfi, rm --recursive --force, /usr/bin/rm -rf
# Does NOT match: rm file.txt, rm -r dir/ (without -f)
check_and_block \
  '(^|/|;|&&|\|)\s*rm\s+(-[a-zA-Z]*r[a-zA-Z]*f|-[a-zA-Z]*f[a-zA-Z]*r|--recursive\s+--force|--force\s+--recursive)' \
  "rm -rf detected. Use 'trash' or remove files individually. If you must force-remove, do it in smaller, targeted steps."

# ---------------------------------------------------------------------------
# Pattern 2: git push --force (suggest --force-with-lease or feature branch)
# ---------------------------------------------------------------------------
# Matches: git push --force, git push -f, /usr/bin/git push --force origin main
# Does NOT match: git push origin feature, git push --force-with-lease
check_and_block \
  '(^|/|;|&&|\|)\s*(sudo\s+)?git\s+push\s+.*--force($|[^-])' \
  "git push --force detected. Use --force-with-lease for safer force push, or push to a feature branch."
check_and_block \
  '(^|/|;|&&|\|)\s*(sudo\s+)?git\s+push\s+.*-f($|\s)' \
  "git push -f detected. Use --force-with-lease for safer force push, or push to a feature branch."

# ---------------------------------------------------------------------------
# Pattern 3: git reset --hard (suggest git stash)
# ---------------------------------------------------------------------------
# Matches: git reset --hard, git reset --hard HEAD~1
# Does NOT match: git reset HEAD file.txt, git reset --soft
check_and_block \
  '(^|/|;|&&|\|)\s*(sudo\s+)?git\s+reset\s+--hard' \
  "git reset --hard discards uncommitted work. Use 'git stash' to save changes, or 'git reset --soft' to keep them staged."

# ---------------------------------------------------------------------------
# Pattern 4: git clean -f without -n dry-run (suggest dry-run first)
# ---------------------------------------------------------------------------
# Matches: git clean -fd, git clean -f, git clean -xfd
# Does NOT match: git clean -nd, git clean -nfd (dry-run present)
has_clean_f=false
has_clean_n=false

if echo "$command" | grep -qE '(^|/|;|&&|\|)\s*(sudo\s+)?git\s+clean\s+-[a-zA-Z]*f' 2>/dev/null; then
  has_clean_f=true
fi
if echo "$command" | grep -qE '(^|/|;|&&|\|)\s*(sudo\s+)?git\s+clean\s+-[a-zA-Z]*n' 2>/dev/null; then
  has_clean_n=true
fi

if [[ "$has_clean_f" == "true" && "$has_clean_n" == "false" ]]; then
  echo "BLOCKED: git clean -f without dry-run. Run 'git clean -nd' first to preview what would be deleted." >&2
  exit 2
fi

# All checks passed — allow execution
exit 0
