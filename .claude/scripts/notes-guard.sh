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
#       file section by section via tmp file + mv (cycle-133 C-4(b)):
#       every `## Blockers` block whole, every `## Active Sub-Goals` block
#       whole, the newest `## Session Continuity*` block whole, the three
#       newest `## Decision Log*` blocks (the only section truncated: to the
#       69,632-byte budget the others leave, headings always kept, plus a
#       truncation line naming the archive), the newest 20 `## Session Log`
#       entries (table rows or list items; the first block's preamble and
#       table header kept), then `## Archive pointers`. A section whose
#       header is missing from the source is emitted as its header alone.
#       Other sections stay in the archive. Never stashes (issue #555 class).
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
      else if (heading ~ /^## Active Sub-Goals/) kind = "asg"
      else if (heading ~ /^## Session Log/) kind = "slog"
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
# Ranges ("start end") of every block of one kind, file order.
kind_ranges() { awk -F'\t' -v k="$2" '$3 == k { print $1 " " $2 }' <<<"$1"; }
# The newest N blocks of one kind (heading date desc, then position), as select_ranges ranks them.
newest_ranges() {
  awk -F'\t' -v k="$2" '$3 == k { print $4 "\t" $1 "\t" $2 }' <<<"$1" \
    | sort -t"$(printf '\t')" -k1,1r -k2,2n | head -"$3" | awk -F'\t' '{ print $2 " " $3 }'
}
# Emit the ranges given in $1, or the bare header $2 when there are none.
whole_or_header() {
  if [[ -n "$1" ]]; then emit_ranges <<<"$1"; else printf '%s\n' "$2"; fi
}
# Session Log: the first block's heading and preamble (comments, table header
# and separator), then the newest 20 entries across every Session Log block
# (append-only: the newest are last). An entry is a list item or a table row
# that is neither a separator nor a header (a row followed by a separator).
session_log_part() {  # $1=ranges
  [[ -n "$1" ]] || { printf '## Session Log\n'; return 0; }
  emit_ranges <<<"$1" | awk -v keep=20 '
    function is_sep(x) { return x ~ /^\|[[:space:]:|-]+\|?[[:space:]]*$/ }
    { line[NR] = $0 }
    END {
      blk = 0; ne = 0; np = 0; started = 0
      for (i = 1; i <= NR; i++) {
        l = line[i]
        if (l ~ /^## Session Log/) { blk++; if (blk == 1) pre[++np] = l; started = 0; continue }
        sep = is_sep(l)
        hdr = (l ~ /^\|/ && !sep && i < NR && is_sep(line[i + 1]))
        if (!sep && !hdr && (l ~ /^\|/ || l ~ /^[-*] /)) { ent[++ne] = l; started = 1; continue }
        if (blk == 1 && !started && (sep || hdr || l ~ /^<!--/ || l == "")) pre[++np] = l
      }
      while (np > 1 && pre[np] == "") np--
      for (i = 1; i <= np; i++) print pre[i]
      for (i = (ne > keep ? ne - keep + 1 : 1); i <= ne; i++) print ent[i]
    }'
}
# The retained file of rotate, on stdout. $1 = the archive path a truncation line names.
build_retained() {
  local archive="$1" idx w budget used i
  idx=$(index_blocks)
  w=$(mktemp -d)
  whole_or_header "$(kind_ranges "$idx" blockers)" "## Blockers" > "$w/1"
  whole_or_header "$(kind_ranges "$idx" asg)" "## Active Sub-Goals" > "$w/2"
  whole_or_header "$(newest_ranges "$idx" sc 1)" "## Session Continuity" > "$w/3"
  whole_or_header "$(newest_ranges "$idx" dl 3)" "## Decision Log" > "$w/4"
  session_log_part "$(kind_ranges "$idx" slog)" > "$w/5"
  used=$(( $(stat -c%s "$w/1") + $(stat -c%s "$w/2") + $(stat -c%s "$w/3") + $(stat -c%s "$w/5") ))
  budget=$(( READ_CAP - used ))
  if (( $(stat -c%s "$w/4") > budget )); then
    # every heading kept; body lines past the budget dropped; the archive holds the rest
    awk -v b="$budget" '/^## / { print; n += length($0) + 1; next }
      { n += length($0) + 1; if (n <= b) print }' "$w/4" > "$w/4c"
    printf '[notes-guard: Decision Log truncated at the %d-byte retention budget — full blocks in %s]\n' "$READ_CAP" "$archive" >> "$w/4c"
    mv -f -- "$w/4c" "$w/4"
  fi
  for i in 1 2 3 4 5; do
    (( i == 1 )) || printf '\n'
    cat -- "$w/$i"
  done
  find "$w" -mindepth 1 -delete
  rmdir -- "$w"
}

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
  # 2. retained content = section by section (build_retained) + archive pointer
  sel=$(mktemp)
  build_retained "$target" > "$sel"
  tmp=$(mktemp -- "$dir/.NOTES.md.rotate.XXXXXX")
  cat -- "$sel" > "$tmp"
  printf '\n## Archive pointers\n\n- %s — %s bytes archived %s by notes-guard.sh rotate (full history: notes-guard.sh read --full --file %s)\n' \
    "$target" "$(stat -c%s "$target")" "$stamp" "$target" >> "$tmp"
  rm -f -- "$sel"
  # 3. atomic replace in the same directory; no stash, no in-place edit
  mv -f -- "$tmp" "$file"
  echo "notes-guard: rotated $file → $target ($(stat -c%s "$target") bytes archived, $(stat -c%s "$file") bytes retained)" >&2
  if (( $(stat -c%s "$file") >= WARN_BYTES )); then
    echo "NOTES-WARN: the whole-kept sections (Blockers, Active Sub-Goals, Session Continuity) leave $(stat -c%s "$file") bytes — close resolved blockers and finished sub-goals" >&2
  fi
  return 0
}

case "$sub" in
  check)  cmd_check ;;
  read)   cmd_read ;;
  rotate) cmd_rotate ;;
  *) usage ;;
esac
