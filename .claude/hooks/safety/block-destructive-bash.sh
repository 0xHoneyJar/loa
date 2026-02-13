#!/usr/bin/env bash
# =============================================================================
# PreToolUse:Bash Safety Hook — Block Destructive Commands
# =============================================================================
# Blocks dangerous patterns and suggests safer alternatives.
# Exit 0 = allow, Exit 2 = block (stderr message fed back to agent).
#
# Registered in settings.hooks.json as PreToolUse matcher: "Bash"
# Part of Loa Harness Engineering (cycle-011, issue #297)
# Source: Trail of Bits claude-code-config safety patterns
# =============================================================================

set -euo pipefail

# Read tool input from stdin (JSON with tool_input.command)
input=$(cat)
command=$(echo "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)

# If we can't parse the command, allow (don't block on parse errors)
if [[ -z "$command" ]]; then
  exit 0
fi

# ---------------------------------------------------------------------------
# Pattern 1: rm -rf (suggest trash or individual removal)
# ---------------------------------------------------------------------------
# Matches: rm -rf, rm -fr, rm --recursive --force, etc.
# Does NOT match: rm file.txt, rm -r dir/ (without -f)
if echo "$command" | grep -qP '\brm\s+(-[a-zA-Z]*r[a-zA-Z]*f|-[a-zA-Z]*f[a-zA-Z]*r|--recursive\s+--force|--force\s+--recursive)\b'; then
  echo "BLOCKED: rm -rf detected. Use 'trash' or remove files individually. If you must force-remove, do it in smaller, targeted steps." >&2
  exit 2
fi

# ---------------------------------------------------------------------------
# Pattern 2: git push --force (suggest --force-with-lease or feature branch)
# ---------------------------------------------------------------------------
# Matches: git push --force, git push -f, git push --force origin main
# Does NOT match: git push origin feature, git push --force-with-lease
if echo "$command" | grep -qP 'git\s+push\s+.*--force(?!-with-lease)\b|git\s+push\s+-f\b'; then
  echo "BLOCKED: git push --force detected. Use --force-with-lease for safer force push, or push to a feature branch." >&2
  exit 2
fi

# ---------------------------------------------------------------------------
# Pattern 3: git reset --hard (suggest git stash)
# ---------------------------------------------------------------------------
# Matches: git reset --hard, git reset --hard HEAD~1
# Does NOT match: git reset HEAD file.txt, git reset --soft
if echo "$command" | grep -qP 'git\s+reset\s+--hard\b'; then
  echo "BLOCKED: git reset --hard discards uncommitted work. Use 'git stash' to save changes, or 'git reset --soft' to keep them staged." >&2
  exit 2
fi

# ---------------------------------------------------------------------------
# Pattern 4: git clean -f without -n dry-run (suggest dry-run first)
# ---------------------------------------------------------------------------
# Matches: git clean -fd, git clean -f, git clean -xfd
# Does NOT match: git clean -nd, git clean -nfd (dry-run present)
if echo "$command" | grep -qP 'git\s+clean\s+-[a-zA-Z]*f' && ! echo "$command" | grep -qP 'git\s+clean\s+-[a-zA-Z]*n'; then
  echo "BLOCKED: git clean -f without dry-run. Run 'git clean -nd' first to preview what would be deleted." >&2
  exit 2
fi

# All checks passed — allow execution
exit 0
