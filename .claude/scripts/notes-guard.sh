#!/usr/bin/env bash
# =============================================================================
# notes-guard.sh — bounded session memory for grimoires/loa/NOTES.md
# (cycle-124 Sprint 4, PRD FR-10 / SDD §3.7)
#
#   notes-guard.sh check  [--delta N] [--file PATH]
#       Size gate. Silent below 100 KiB; `NOTES-WARN` on stderr (exit 0) from
#       100 KiB; `NOTES-BLOCK` with the remedy (exit 3) from 200 KiB.
#       --delta N asks "would a write of N bytes land at or over the block
#       line?" — a negative or zero delta (compaction) never blocks.
#   notes-guard.sh read   [--full | --index | --section SPEC] [--file PATH]
#       NOTES.md default: every `## Blockers` block (file order), the newest
#       `## Session Continuity*` block and the 3 newest `## Decision Log*`
#       blocks (newest first; recency is the YYYY-MM-DD in the heading, file
#       position only when no date parses). Hard cap 69,632 bytes (≤ 20k
#       tokens at 3.5 bytes/token) with a footer naming `read --full`.
#       Template drift (none of the three headings) falls back loudly to the
#       file head. Never empty. `--full` prints the whole file.
#       --index          one line per `## ` heading: `L<start>-L<end>  <bytes>B  <heading>`
#                        (the default for any file other than NOTES.md).
#       --section SPEC   one H2 block, capped like the default read. SPEC is
#                        `Sprint N` (matches `## Sprint N:`), `N` / `N.` (a
#                        numbered section `## N. …`), or a case-insensitive
#                        substring of a heading (first match). No match →
#                        one loud line naming the headings, then the index.
#       Works on prd.md / sdd.md / sprint.md / NOTES.md (cycle-125 FR-2).
#   notes-guard.sh rotate [--file PATH]
#       Copy the whole file to <dir>/archive/notes/NOTES-<UTC>.md, fsync the
#       archive, refuse an existing target (exit 4), then rewrite the live
#       file with the `read` selection plus an `## Archive pointers` line via
#       tmp file + mv. Never stashes (the issue #555 data-loss class).
#
# Thresholds are literals on purpose (PRD FR-10: no config key, no env knob).
# Default --file: $LOA_GRIMOIRE_DIR/NOTES.md, else <repo>/grimoires/loa/NOTES.md.
# Exit codes: 0 ok/allow · 2 usage · 3 NOTES-BLOCK · 4 rotate target exists.
# Tests: tests/unit/notes-guard.bats (fixtures: tests/fixtures/notes/).
# =============================================================================
set -euo pipefail
export LC_ALL=C

WARN_BYTES=102400
BLOCK_BYTES=204800
READ_CAP=69632

usage() {
  sed -n '3,/^# Thresholds/p' "$0" | sed 's/^# \{0,1\}//' >&2
  exit 2
}

sub="${1:-}"
[[ -n "$sub" ]] || usage
shift
file="" delta="" full=0 index=0 section=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --file)    [[ $# -ge 2 && -n "$2" ]] || usage; file="$2"; shift 2 ;;
    --delta)   [[ $# -ge 2 && "$2" =~ ^-?[0-9]+$ ]] || usage; delta="$2"; shift 2 ;;
    --full)    full=1; shift ;;
    --index)   index=1; shift ;;
    --section) [[ $# -ge 2 && -n "$2" ]] || usage; section="$2"; shift 2 ;;
    *) usage ;;
  esac
done
_modes=$(( index + full )); [[ -z "$section" ]] || _modes=$(( _modes + 1 ))
(( _modes <= 1 )) || usage   # --full / --index / --section are exclusive
if [[ -z "$file" ]]; then
  _root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  file="${LOA_GRIMOIRE_DIR:-$_root/grimoires/loa}/NOTES.md"
fi

size_of() { if [[ -f "$1" ]]; then stat -c%s "$1"; else echo 0; fi; }

# --- check -------------------------------------------------------------------
cmd_check() {
  local size projected
  size=$(size_of "$file")
  projected=$size
  if [[ -n "$delta" ]]; then
    (( delta > 0 )) || return 0          # shrinking / no-op writes never block
    projected=$(( size + delta ))
  fi
  if (( projected >= BLOCK_BYTES )); then
    echo "NOTES-BLOCK: $file is $size bytes (block line $BLOCK_BYTES) — appends refused. Run .claude/scripts/notes-guard.sh rotate --file $file (or /compound) first; shrinking edits and rotate itself are never blocked." >&2
    return 3
  fi
  if (( size >= WARN_BYTES )); then
    echo "NOTES-WARN: $file is $size bytes (warn line $WARN_BYTES) — run /compound or notes-guard.sh rotate before it reaches $BLOCK_BYTES." >&2
  fi
  return 0
}

# --- read --------------------------------------------------------------------
# One awk pass over `^## ` boundaries:
# "start<TAB>end<TAB>kind<TAB>date<TAB>bytes<TAB>heading" (bytes: the block
# including its heading line and newlines; LC_ALL=C so length() counts bytes).
# The heading is the LAST field so a TAB inside it cannot shift the others;
# consumers take the heading as "everything after the fifth TAB".
index_blocks() {
  awk '
    function flush(end) { if (start) printf "%d\t%d\t%s\t%s\t%d\t%s\n", start, end, kind, date, bytes, heading }
    BEGIN { start = 0; bytes = 0 }
    /^## / {
      flush(NR - 1)
      start = NR; heading = $0; date = ""; kind = "other"; bytes = length($0) + 1
      if (heading ~ /^## Blockers/) kind = "blockers"
      else if (heading ~ /^## Session Continuity/) kind = "sc"
      else if (heading ~ /^## Decision Log/) kind = "dl"
      if (match(heading, /[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/)) date = substr(heading, RSTART, RLENGTH)
      next
    }
    { if (start) bytes += length($0) + 1 }
    END { flush(NR) }
  ' "$file"
}

# --index: one line per H2 in file order. Never empty.
cmd_index() {
  local idx
  idx=$(index_blocks)
  if [[ -z "$idx" ]]; then
    echo "NOTES-GUARD: no '## ' headings in $file ($(size_of "$file") bytes) — use read --full --file $file"
    return 0
  fi
  awk -F'\t' '{ h = $0; for (i = 1; i <= 5; i++) sub(/^[^\t]*\t/, "", h); printf "L%d-L%d  %dB  %s\n", $1, $2, $5, h }' <<<"$idx"
}

# Resolve a --section SPEC to "start end" (first matching H2), or nothing.
# `Sprint N` stops at the digit run AND at a dot, so `Sprint 2` never returns
# `## Sprint 2.5`; the substring spec travels through ENVIRON (no `-v`
# backslash processing). Headings are rebuilt from the sixth field onward.
find_section() {
  local spec="$1" idx n
  idx=$(index_blocks)
  [[ -n "$idx" ]] || return 0
  if [[ "$spec" =~ ^[Ss]print[[:space:]]+([0-9]+)$ ]]; then
    n="${BASH_REMATCH[1]}"
    awk -F'\t' -v n="$n" '{ h = $0; for (i = 1; i <= 5; i++) sub(/^[^\t]*\t/, "", h) }
      h ~ ("^## Sprint " n "([^0-9.]|$)") { print $1 " " $2; exit }' <<<"$idx"
  elif [[ "$spec" =~ ^([0-9]+)\.?$ ]]; then
    n="${BASH_REMATCH[1]}"
    awk -F'\t' -v n="$n" '{ h = $0; for (i = 1; i <= 5; i++) sub(/^[^\t]*\t/, "", h) }
      h ~ ("^## " n "\\. ") { print $1 " " $2; exit }' <<<"$idx"
  else
    NG_SPEC="$spec" awk -F'\t' 'BEGIN { s = tolower(ENVIRON["NG_SPEC"]) }
      { h = $0; for (i = 1; i <= 5; i++) sub(/^[^\t]*\t/, "", h) }
      index(tolower(h), s) > 0 { print $1 " " $2; exit }' <<<"$idx"
  fi
}

# Selected line ranges ("start end" per line) in output order: Blockers first
# (highest signal survives the cap), then the newest Session Continuity, then
# the 3 newest Decision Logs. Dated blocks rank by date (newest first); undated
# blocks rank after them by position (earlier first — the live file prepends).
select_ranges() {
  local idx
  idx=$(index_blocks)
  [[ -n "$idx" ]] || return 0
  awk -F'\t' '$3 == "blockers" { print $1 " " $2 }' <<<"$idx"
  awk -F'\t' '$3 == "sc" { print $4 "\t" $1 "\t" $2 }' <<<"$idx" \
    | sort -t"$(printf '\t')" -k1,1r -k2,2n | head -1 | awk -F'\t' '{ print $2 " " $3 }'
  awk -F'\t' '$3 == "dl" { print $4 "\t" $1 "\t" $2 }' <<<"$idx" \
    | sort -t"$(printf '\t')" -k1,1r -k2,2n | head -3 | awk -F'\t' '{ print $2 " " $3 }'
}

emit_ranges() {  # stdin: "start end" lines → the blocks, separated by one blank line
  local s e first=1
  while read -r s e; do
    [[ -n "${s:-}" ]] || continue
    (( first )) || printf '\n'
    sed -n "${s},${e}p" "$file"
    first=0
  done
}

# Emit "start end" ranges (stdin) under READ_CAP with the footer.
emit_capped() {
  local tmp bytes footer budget
  tmp=$(mktemp)
  emit_ranges > "$tmp"
  bytes=$(stat -c%s "$tmp")
  if (( bytes > READ_CAP )); then
    footer=$'\n'"[notes-guard: capped at $READ_CAP of $bytes selected bytes — run notes-guard.sh read --full --file $file for the whole file]"$'\n'
    budget=$(( READ_CAP - ${#footer} ))
    head -c "$budget" -- "$tmp"
    printf '%s' "$footer"
  else
    cat -- "$tmp"
  fi
  rm -f -- "$tmp"
}

cmd_read() {
  if (( full )); then cat -- "$file"; return 0; fi
  if [[ -e "$file" && ! -f "$file" ]]; then echo "NOTES-GUARD: $file is not a regular file — nothing to read"; return 0; fi
  if [[ ! -f "$file" ]]; then echo "NOTES-GUARD: $file does not exist — nothing to read"; return 0; fi
  local ranges
  if (( index )); then cmd_index; return 0; fi
  if [[ -n "$section" ]]; then
    ranges=$(find_section "$section")
    if [[ -z "$ranges" ]]; then
      echo "NOTES-GUARD: no section matching '$section' in $file; headings: $(grep '^## ' -- "$file" | sed 's/^## //' | paste -sd'|' - | head -c 400)"
      cmd_index
      return 0
    fi
    emit_capped <<<"$ranges"
    return 0
  fi
  # No mode flag: NOTES.md keeps its recovery selection; any other artefact
  # gets the index (a blind full read is what the Read cap rejects).
  if [[ "$(basename -- "$file")" != "NOTES.md" ]]; then cmd_index; return 0; fi
  ranges=$(select_ranges)
  if [[ -z "$ranges" ]]; then
    echo "NOTES-GUARD: no known sections (template drift) — showing head; expected ## Blockers / ## Session Continuity / ## Decision Log (see .claude/templates/NOTES.md.template)"
    head -c "$READ_CAP" -- "$file"
    [[ -s "$file" ]] || echo "NOTES-GUARD: $file is empty"
    return 0
  fi
  emit_capped <<<"$ranges"
}

# --- rotate ------------------------------------------------------------------
cmd_rotate() {
  if [[ ! -f "$file" ]]; then echo "notes-guard: $file does not exist — nothing to rotate" >&2; return 2; fi
  local dir archive_dir stamp target tmp sel ranges
  dir=$(dirname -- "$file")
  archive_dir="$dir/archive/notes"
  stamp=$(date -u +%Y%m%dT%H%M%SZ)
  target="$archive_dir/NOTES-$stamp.md"
  mkdir -p -- "$archive_dir"
  if [[ -e "$target" ]]; then
    echo "notes-guard: archive target already exists: $target — refusing to overwrite (retry in a second)" >&2
    return 4
  fi
  # 1. archive the whole file and make it durable BEFORE the live file changes
  cp -- "$file" "$target"
  sync -d -- "$target" 2>/dev/null || sync
  # 2. retained content = the read selection (same order, same cap) + archive pointer
  sel=$(mktemp)
  ranges=$(select_ranges)
  if [[ -n "$ranges" ]]; then emit_ranges <<<"$ranges" > "$sel"; else cat -- "$file" > "$sel"; fi
  tmp=$(mktemp -- "$dir/.NOTES.md.rotate.XXXXXX")
  head -c "$READ_CAP" -- "$sel" > "$tmp"
  printf '\n## Archive pointers\n\n- %s — %s bytes archived %s by notes-guard.sh rotate (full history: notes-guard.sh read --full --file %s)\n' \
    "$target" "$(stat -c%s "$target")" "$stamp" "$target" >> "$tmp"
  rm -f -- "$sel"
  # 3. atomic replace in the same directory; no stash, no in-place edit
  mv -f -- "$tmp" "$file"
  echo "notes-guard: rotated $file → $target ($(stat -c%s "$target") bytes archived, $(stat -c%s "$file") bytes retained)" >&2
  return 0
}

case "$sub" in
  check)  cmd_check ;;
  read)   cmd_read ;;
  rotate) cmd_rotate ;;
  *) usage ;;
esac
