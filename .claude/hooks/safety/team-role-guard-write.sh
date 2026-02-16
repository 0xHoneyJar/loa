#!/usr/bin/env bash
# =============================================================================
# PreToolUse:Write/Edit Team Role Guard — Enforce System Zone & State Files
# =============================================================================
# When LOA_TEAM_MEMBER is set (indicating a teammate context in Agent Teams
# mode), blocks Write/Edit operations to protected paths:
#   - .claude/ (System Zone)            → C-TEAM-005
#   - .run/*.json (top-level state)     → C-TEAM-003
#   - Append-only files (audit.jsonl, NOTES.md) — must use Bash append (>>)
#
# When LOA_TEAM_MEMBER is unset or empty, this hook is a complete no-op.
# Single-agent mode is unaffected.
#
# IMPORTANT: No set -euo pipefail — this hook must never fail closed.
# A jq failure must result in exit 0 (allow), not an error.
# Fail-open with logging is the standard pattern for inline security hooks.
#
# Registered in settings.hooks.json as PreToolUse matcher: "Write", "Edit"
# Part of Agent Teams Compatibility (cycle-020, issue #337)
# Source: Bridgebuilder Horizon Review Section VI.1 (PR #341)
# =============================================================================

# Early exit: if not a teammate, allow everything
if [[ -z "${LOA_TEAM_MEMBER:-}" ]]; then
  exit 0
fi

# Read tool input from stdin (JSON with tool_input.file_path)
input=$(cat)
file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || true

# If we can't parse the file path, allow (don't block on parse errors)
if [[ -z "$file_path" ]]; then
  exit 0
fi

# Normalize: resolve to repo-relative path
# Write/Edit tools pass absolute paths (e.g., /home/user/project/.claude/foo)
# We need repo-relative paths for our prefix checks to work.
# NOTE: -m (canonicalize-missing) resolves paths even when intermediate dirs
# don't exist. Without -m, Write to .claude/new-dir/file.sh would bypass
# because realpath fails → empty → fail-open. --relative-to is GNU coreutils;
# macOS users need `brew install coreutils`. Acceptable: Agent Teams is Linux-first.
file_path=$(realpath -m --relative-to=. "$file_path" 2>/dev/null) || true
if [[ -z "$file_path" ]]; then
  exit 0
fi
# Strip leading ./ if realpath produced one
file_path="${file_path#./}"

# ---------------------------------------------------------------------------
# C-TEAM-005: Block writes to System Zone (.claude/)
# The System Zone contains constraint definitions, hook scripts, schemas,
# and framework-managed files. Teammates must not modify these.
# ---------------------------------------------------------------------------
if [[ "$file_path" == .claude/* || "$file_path" == ".claude" ]]; then
  echo "BLOCKED [team-role-guard-write]: System Zone (.claude/) is read-only for teammates (C-TEAM-005)." >&2
  echo "Teammate '$LOA_TEAM_MEMBER' cannot modify framework files. Report to the team lead via SendMessage." >&2
  exit 2
fi

# ---------------------------------------------------------------------------
# C-TEAM-003: Block writes to .run/ top-level state files
# Matches: .run/simstim-state.json, .run/bridge-state.json, etc.
# Does NOT match: .run/bugs/*/state.json (teammate-owned subdirectories)
# Does NOT match: .run/audit.jsonl (append-only, but Write tool is full replace)
# Does NOT match: .run/bridge-reviews/*.md (review output files)
# ---------------------------------------------------------------------------
if echo "$file_path" | grep -qE '^\.run/[^/]+\.json$' 2>/dev/null; then
  echo "BLOCKED [team-role-guard-write]: Writing to .run/ state files is lead-only in Agent Teams mode (C-TEAM-003)." >&2
  echo "Teammate '$LOA_TEAM_MEMBER' cannot modify state files. Report status to the lead via SendMessage." >&2
  exit 2
fi

# ---------------------------------------------------------------------------
# Append-Only File Protection
# These files MUST use Bash append (echo >> file) for POSIX atomic writes.
# The Write tool does full read-modify-write which is NOT concurrent-safe.
# Block Write/Edit for teammates; they must use Bash append instead.
# ---------------------------------------------------------------------------
APPEND_ONLY_FILES=".run/audit.jsonl grimoires/loa/NOTES.md"
for protected in $APPEND_ONLY_FILES; do
  if [[ "$file_path" == "$protected" ]]; then
    echo "BLOCKED [team-role-guard-write]: '$file_path' is append-only. Use Bash: echo \"...\" >> $file_path (POSIX atomic writes)." >&2
    echo "Teammate '$LOA_TEAM_MEMBER' must NOT use Write/Edit for append-only files — only Bash append (>>)." >&2
    exit 2
  fi
done

# All checks passed — allow the operation
exit 0
