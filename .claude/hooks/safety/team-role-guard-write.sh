#!/usr/bin/env bash
# =============================================================================
# PreToolUse:Write/Edit Team Role Guard — Enforce System Zone & State Files
# =============================================================================
# When LOA_TEAM_MEMBER is set (indicating a teammate context in Agent Teams
# mode), blocks Write/Edit operations to protected paths:
#   - .claude/ (System Zone)            → C-TEAM-005
#   - .loa/.claude/ (Physical System Zone via submodule) → C-TEAM-005 (medium-2)
#   - .run/*.json (top-level state)     → C-TEAM-003
#   - Append-only files (audit.jsonl, NOTES.md) — must use Bash append (>>)
#
# Symlink-Aware Path Checking (Bridgebuilder finding medium-2):
#   In submodule mode, .claude/scripts → .loa/.claude/scripts (symlink).
#   realpath resolves through symlinks, so the RESOLVED path may be .loa/.claude/...
#   which would bypass the .claude/* prefix check. We check BOTH the raw
#   (pre-resolution) path AND the resolved path against all protected patterns.
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
# Hardened: Bridgebuilder Deep Review medium-2 (bridge-20260224-b4e7f1, PR #406)
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

# ---------------------------------------------------------------------------
# Path normalization: Compute BOTH raw and resolved paths
# ---------------------------------------------------------------------------
# Raw path: strip to repo-relative without resolving symlinks.
# This catches .claude/scripts/foo.sh even when it's a symlink.
repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || repo_root="$(pwd)"
raw_path="$file_path"
# If absolute, make relative to repo root
if [[ "$raw_path" == /* ]]; then
  raw_path="${raw_path#"$repo_root"/}"
fi
raw_path="${raw_path#./}"

# Resolved path: follow symlinks to physical location.
# This catches writes to .loa/.claude/... (the physical System Zone in submodule mode).
# NOTE: -m (canonicalize-missing) resolves paths even when intermediate dirs
# don't exist. Without -m, Write to .claude/new-dir/file.sh would bypass
# because realpath fails → empty → fail-open. --relative-to is GNU coreutils;
# macOS users need `brew install coreutils`. Acceptable: Agent Teams is Linux-first.
resolved_path=$(realpath -m --relative-to=. "$file_path" 2>/dev/null) || true
resolved_path="${resolved_path#./}"

# ---------------------------------------------------------------------------
# check_system_zone - Check a path against System Zone patterns
# Returns 0 (blocked) or 1 (allowed)
# ---------------------------------------------------------------------------
check_system_zone() {
  local check_path="$1"
  [[ -z "$check_path" ]] && return 1

  # C-TEAM-005: .claude/ (logical System Zone)
  if [[ "$check_path" == .claude/* || "$check_path" == ".claude" ]]; then
    return 0
  fi

  # C-TEAM-005 (medium-2): .loa/.claude/ (physical System Zone via submodule)
  # In submodule mode, .claude/scripts is a symlink to .loa/.claude/scripts.
  # A resolved path through this symlink lands in .loa/.claude/ which is
  # equally protected — it's the same framework content, just the physical location.
  if [[ "$check_path" == .loa/.claude/* || "$check_path" == ".loa/.claude" ]]; then
    return 0
  fi

  return 1
}

# ---------------------------------------------------------------------------
# C-TEAM-005: Block writes to System Zone — check BOTH raw and resolved paths
# ---------------------------------------------------------------------------
if check_system_zone "$raw_path"; then
  echo "BLOCKED [team-role-guard-write]: System Zone (.claude/) is read-only for teammates (C-TEAM-005)." >&2
  echo "Teammate '$LOA_TEAM_MEMBER' cannot modify framework files. Report to the team lead via SendMessage." >&2
  exit 2
fi

if check_system_zone "$resolved_path"; then
  echo "BLOCKED [team-role-guard-write]: System Zone (resolved through symlink to .loa/.claude/) is read-only for teammates (C-TEAM-005, medium-2)." >&2
  echo "Teammate '$LOA_TEAM_MEMBER' cannot modify framework files through symlinks. Report to the team lead via SendMessage." >&2
  exit 2
fi

# Use resolved path for remaining checks (state files, append-only)
file_path="${resolved_path:-$raw_path}"
if [[ -z "$file_path" ]]; then
  exit 0
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
