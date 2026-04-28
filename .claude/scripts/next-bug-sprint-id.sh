#!/usr/bin/env bash
# =============================================================================
# next-bug-sprint-id.sh — Pick the next safe `sprint-bug-N` identifier.
# =============================================================================
#
# `/bug` (bug-triaging skill) historically picked
#   counter = local_ledger.global_sprint_counter + 1
# which collides when multiple `/bug` invocations run from the same starting
# commit (each incrementing the local counter to the same N) and when local
# main is behind origin/main (someone else merged a bug-cycle since last pull).
#
# This script is the source-of-truth for next-id picking. It consults:
#   1. local ledger.json's `global_sprint_counter`
#   2. max sprint-bug-N referenced on disk in any
#      `grimoires/loa/a2a/bug-*/sprint.md`
#   3. origin/main's ledger.json's `global_sprint_counter` (best-effort —
#      no fetch; uses whatever's in the local refspec)
# …and emits `sprint-bug-{max+1}` on stdout.
#
# Diagnostic-only output goes to stderr; stdout is exactly one line:
#   sprint-bug-N
# so callers can `id="$(next-bug-sprint-id.sh)"` without shell post-processing.
#
# Exit codes:
#   0 — success
#   1 — fatal error (jq missing, project root unresolvable, etc.)
#
# Environment:
#   PROJECT_ROOT   — override repo root detection (default: git toplevel)
#   LOA_BUG_REMOTE — override remote name to consult (default: origin)
#   LOA_BUG_BRANCH — override branch name to consult (default: main)
# =============================================================================

set -euo pipefail

PROJECT_ROOT="${PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
LEDGER="$PROJECT_ROOT/grimoires/loa/ledger.json"
REMOTE="${LOA_BUG_REMOTE:-origin}"
BRANCH="${LOA_BUG_BRANCH:-main}"

_log() { echo "[next-bug-sprint-id] $*" >&2; }

command -v jq >/dev/null 2>&1 || { _log "ERROR: jq required"; exit 1; }

# 1. Local ledger's global_sprint_counter
local_counter=0
if [[ -f "$LEDGER" ]]; then
    local_counter=$(jq -r '.global_sprint_counter // 0' "$LEDGER" 2>/dev/null || echo 0)
    [[ "$local_counter" =~ ^[0-9]+$ ]] || local_counter=0
fi

# 2. Max sprint-bug-N on disk under grimoires/loa/a2a/bug-*/sprint.md
disk_max=0
shopt -s nullglob
for f in "$PROJECT_ROOT"/grimoires/loa/a2a/bug-*/sprint.md; do
    [[ -f "$f" ]] || continue
    while IFS= read -r n; do
        [[ "$n" =~ ^[0-9]+$ ]] || continue
        if [[ "$n" -gt "$disk_max" ]]; then
            disk_max="$n"
        fi
    done < <(grep -oE 'sprint-bug-[0-9]+' "$f" 2>/dev/null | grep -oE '[0-9]+$' || true)
done
shopt -u nullglob

# 3. origin/main's global_sprint_counter (best-effort, no fetch)
origin_counter=0
if git -C "$PROJECT_ROOT" rev-parse "${REMOTE}/${BRANCH}" >/dev/null 2>&1; then
    if origin_blob=$(git -C "$PROJECT_ROOT" show "${REMOTE}/${BRANCH}:grimoires/loa/ledger.json" 2>/dev/null); then
        origin_counter=$(echo "$origin_blob" | jq -r '.global_sprint_counter // 0' 2>/dev/null || echo 0)
        [[ "$origin_counter" =~ ^[0-9]+$ ]] || origin_counter=0
    fi
fi

# Pick the max of all three, then increment
next="$local_counter"
[[ "$disk_max" -gt "$next" ]] && next="$disk_max"
[[ "$origin_counter" -gt "$next" ]] && next="$origin_counter"
next=$((next + 1))

echo "sprint-bug-$next"
