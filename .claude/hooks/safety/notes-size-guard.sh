#!/usr/bin/env bash
# =============================================================================
# notes-size-guard.sh — PreToolUse Write|Edit|MultiEdit|NotebookEdit fence for
# grimoires/loa/NOTES.md (cycle-124 Sprint 4, PRD FR-10 / SDD §3.7)
#
# Acts ONLY when the payload's file_path realpath-resolves to the grimoire's
# NOTES.md (LOA_GRIMOIRE_DIR is the configurable dir; symlinks and relative
# paths resolve). Direction-aware: it computes the write's byte delta —
#   Write:     bytes(content) − current size
#   Edit:      (bytes(new_string) − bytes(old_string)) × occurrences when
#              replace_all, × 1 otherwise
#   MultiEdit: the sum over edits
# and denies (exit 2, remedy on stderr) only when the delta is positive AND the
# file would sit at/over 200 KiB afterwards (notes-guard.sh check --delta).
# Shrinking edits (compaction), every other path, a missing file and an
# unparseable payload exit 0 fast — the hook fails OPEN, and hook-guard.sh
# allows on a syntax error.
#
# Accepted bypass classes (fence, not boundary): Bash writers other than `>>`
# (python -c, heredocs into the file, tee) are not inspected here — `>>` is
# FR-NOTES in block-destructive-bash.sh and the writer-side gate lives in
# update-notes-learnings.sh. The escape hatch, `notes-guard.sh rotate`, uses
# mv and is never intercepted.
# Tests: tests/unit/notes-size-guard.bats.
# =============================================================================
set -uo pipefail
export LC_ALL=C

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HOOK_DIR/../../.." && pwd)"
GUARD="$REPO_ROOT/.claude/scripts/notes-guard.sh"
BLOCK_BYTES=204800

payload=$(cat 2>/dev/null) || exit 0
[[ -n "$payload" ]] || exit 0
command -v jq >/dev/null 2>&1 || exit 0
jq -e . >/dev/null 2>&1 <<<"$payload" || exit 0

target=$(jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' <<<"$payload" 2>/dev/null) || exit 0
[[ -n "$target" ]] || exit 0

notes="${LOA_GRIMOIRE_DIR:-$REPO_ROOT/grimoires/loa}/NOTES.md"
notes_real=$(realpath -m -- "$notes" 2>/dev/null) || exit 0
target_real=$(realpath -m -- "$target" 2>/dev/null) || exit 0
[[ "$target_real" == "$notes_real" ]] || exit 0
[[ -f "$notes_real" ]] || exit 0
size=$(stat -c%s -- "$notes_real" 2>/dev/null) || exit 0

# read a JSON string field byte-exact (trailing newlines preserved via NUL delimiter)
_field() {  # _field <jq-path> → prints the string
  local v=""
  IFS= read -r -d '' v < <(jq -j "($1 // \"\"), \"\\u0000\"" <<<"$payload" 2>/dev/null) || true
  printf '%s' "$v"
}
_occurrences() {  # _occurrences <needle> → count of needle in the live file (≥ 1)
  local needle="$1" text stripped n
  [[ -n "$needle" ]] || { echo 1; return; }
  text=$(<"$notes_real")
  stripped=${text//"$needle"/}
  n=$(( (${#text} - ${#stripped}) / ${#needle} ))
  (( n >= 1 )) || n=1
  echo "$n"
}

tool=$(jq -r '.tool_name // empty' <<<"$payload" 2>/dev/null)
delta=0
case "$tool" in
  Write)
    new_bytes=$(jq -r '(.tool_input.content // "") | utf8bytelength' <<<"$payload" 2>/dev/null) || exit 0
    delta=$(( new_bytes - size )) ;;
  Edit)
    old=$(_field '.tool_input.old_string'); new=$(_field '.tool_input.new_string')
    all=$(jq -r '.tool_input.replace_all // false' <<<"$payload" 2>/dev/null)
    occ=1; [[ "$all" == "true" ]] && occ=$(_occurrences "$old")
    delta=$(( (${#new} - ${#old}) * occ )) ;;
  MultiEdit)
    n_edits=$(jq -r '.tool_input.edits | length' <<<"$payload" 2>/dev/null) || exit 0
    [[ "$n_edits" =~ ^[0-9]+$ ]] || exit 0
    i=0
    while (( i < n_edits )); do
      old=$(_field ".tool_input.edits[$i].old_string"); new=$(_field ".tool_input.edits[$i].new_string")
      all=$(jq -r ".tool_input.edits[$i].replace_all // false" <<<"$payload" 2>/dev/null)
      occ=1; [[ "$all" == "true" ]] && occ=$(_occurrences "$old")
      delta=$(( delta + (${#new} - ${#old}) * occ ))
      i=$(( i + 1 ))
    done ;;
  *) exit 0 ;;   # NotebookEdit and anything else never targets NOTES.md
esac

(( delta > 0 )) || exit 0                       # compaction is always allowed
(( size + delta >= BLOCK_BYTES )) || exit 0     # stays under the line
[[ -x "$GUARD" ]] || exit 0                     # no guard script → fail open

rc=0
"$GUARD" check --delta "$delta" --file "$notes_real" || rc=$?
if [[ $rc -eq 3 ]]; then
  echo "[notes-size-guard] BLOCKED: $tool on $notes_real would grow it by $delta bytes past the 200 KiB block line (now $size bytes). Rotate first: .claude/scripts/notes-guard.sh rotate — shrinking edits are never blocked." >&2
  exit 2
fi
exit 0
