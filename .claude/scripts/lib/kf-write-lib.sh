#!/usr/bin/env bash
# =============================================================================
# kf-write-lib.sh — minimal-conformance APPEND helper for known-failures.md + NOTES.md
#
# OKF/ICM adoption cycle, Sprint 5 (rec #7). known-failures.md is append-only and
# anti-tamper (vision-024 / feedback_zero_blocker_demotion_pattern.md): the Evidence
# cell (commit SHA / PR# / run ID) is the load-bearing field. This helper enforces
# ONLY that floor — non-empty id/Status, and a non-empty Evidence cell on any
# Attempts row — and leaves everything else free-text. It performs the three
# allowed mutations from the file header (new entry append, Attempts-row append,
# recurrence increment) PLUS an advisory NOTES dated-header — never a whole-file
# rewrite, never a bot auto-append, never `git stash` (the #555 data-loss class).
#
# Parse grammar mirrors the canonical reader .claude/scripts/lib/kf-auto-link.py:
#   - entry header:  ^##[[:space:]]+(KF-\d+):     (one-or-more ws, incl tab/multi-space)
#   - field:         **Name**: value               (single line; empty Status = malformed)
#   - Attempts row:  | Date | What we tried | Outcome | Evidence |
#   - Index row:     | [KF-NNN](#anchor) | Status | Feature | Recurrence |
#
# CONCURRENCY/SAFETY: every mutation acquires the flock FIRST, then reads $f,
#   builds a temp via head/insert/tail, VERIFIES (never shrinks, never drops an
#   existing KF id, intended change present), then atomically renames — the whole
#   read-modify-write is under the lock (no TOCTOU lost-update). Verification
#   failure aborts without touching the original.
#
# Ops:
#   new        --title T --status S [--feature F] [--symptom Y] [--first-observed FO]
#              [--workaround W] [--upstream U] [--related R] [--reading-guide RG]
#              [--recur N] [--attempt-date D --attempt-what WH --attempt-outcome O --attempt-evidence E]
#   attempt    --id KF-NNN --date D --what WH --outcome O --evidence E   (evidence REQUIRED)
#   recur      --id KF-NNN                                               (integer count +1)
#   notes-header --date D --cycle C [--note N]                          (prepend dated section)
# Common: --file PATH (override target), --quiet
# =============================================================================
export LC_ALL=C
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
G="${PROJECT_ROOT}/grimoires/loa"
KF_FILE="${G}/known-failures.md"
NOTES_FILE="${G}/NOTES.md"
LOCK="${PROJECT_ROOT}/.run/.kf-write.lock"
QUIET=0
# Grammar shared with kf-auto-link.py (^##\s+(KF-\d+):).
KF_HEAD_RE='^##[[:space:]]+KF-[0-9]+'

log(){ [[ $QUIET -eq 0 ]] && echo "$@" >&2 || true; }
die(){ echo "kf-write: $*" >&2; exit 1; }

# Single-line scalar: strip control bytes, flatten whitespace, trim.
san1(){ printf '%s' "${1-}" | tr -d '\000-\010\013\014\016-\037\177' | tr '\t\n\r' '   ' | sed -E 's/  +/ /g; s/^ //; s/ $//'; }
# Table cell: single-line + escape the column delimiter so it can't break the table.
cell(){ san1 "${1-}" | sed -E 's/\|/\\|/g'; }
# GitHub-style heading anchor (lowercase; keep [a-z0-9_-] + space; EACH space->hyphen — GitHub
# never collapses them, so `a / b` is `a--b`: cycle-126).
# Underscores are KEPT — GitHub's algorithm preserves them and the existing Index
# links rely on it (e.g. #kf-005-beads_rust-021-...).
# A non-ASCII heading is slugged as GitHub does — its Unicode letters lowercased and KEPT, the rule the ledger link lint holds —
# by python3; under this script's LC_ALL=C, tr/sed see bytes and would drop them (cycle-126 thirty-third run, e2c DISS-C-001).
# A title that is not UTF-8 has no GitHub slug: refused before any write.
gh_anchor(){
  if [[ -z "$(printf '%s' "${1-}" | tr -d '\000-\177')" ]]; then
    printf '%s' "${1-}" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9_ -]//g' | tr ' ' '-'
    return 0
  fi
  command -v python3 >/dev/null 2>&1 || die "new: a non-ASCII title needs python3 for its GitHub anchor"
  # (thirty-fourth run, e2c DISS-C-001: GitHub's slugger keeps every letter, mark, number and connector punctuation — a
  # combining mark (an NFD accent) too, which \w drops; DISS-C-002: only a decode failure is a non-UTF-8 title)
  # (thirty-fifth run, e2c DISS-C-001: GitHub keeps \p{Word} — Alphabetic, Mark, Decimal_Number, Connector_Punctuation,
  # Join_Control — so an Other_Number (², ½, ①) is dropped, and an Other_Alphabetic symbol (Ⓐ, 🄰 — the four So ranges of
  # PropList's Other_Alphabetic, which unicodedata cannot name) and ZWNJ/ZWJ are kept; checked against perl's \w codepoint
  # by codepoint)
  # (thirty-sixth run, e2c DISS-C-002: the slug references disagree exactly there — perl's \w, Onigmo's \p{Word} and
  # github-slugger split on Other_Number, ZWNJ/ZWJ and the Other_Alphabetic symbols, and Python's lower() alone applies
  # Final_Sigma — so a title holding one, or any format character, has no settled anchor: refused, never guessed)
  local rc=0
  printf '%s' "${1-}" | python3 -c 'import sys, unicodedata
try:
    h = sys.stdin.buffer.read().decode("utf-8")
except UnicodeDecodeError:
    sys.exit(3)
oa = ((0x24B6, 0x24E9), (0x1F130, 0x1F149), (0x1F150, 0x1F169), (0x1F170, 0x1F189))
if (any(unicodedata.category(c) in ("No", "Cf") or any(a <= ord(c) <= b for a, b in oa) for c in h)
        or h.lower() != "".join(c.lower() for c in h)):
    sys.exit(4)
def word(c):
    k = unicodedata.category(c)
    return k[0] in "LM" or k in ("Nd", "Nl", "Pc") or c in "\u200c\u200d" or any(a <= ord(c) <= b for a, b in oa)
sys.stdout.buffer.write("".join(c for c in h.lower() if c in "- " or word(c)).replace(" ", "-").encode("utf-8"))' || rc=$?
  [[ $rc -ne 3 ]] || die "new: the title is not valid UTF-8 — it has no GitHub heading anchor"
  [[ $rc -ne 4 ]] || die "new: the title's GitHub heading anchor is not settled — it holds an Other_Number (², ½, ①), a format character (ZWJ, ZWNJ), an Other_Alphabetic symbol (Ⓐ) or a word-final capital sigma, on which GitHub's slug references disagree; rephrase it"
  [[ $rc -eq 0 ]] || die "new: python3 failed (exit $rc) computing the title's GitHub anchor"
}
# GitHub slugs a heading's RENDERED text: a title holding a link, an HTML tag, a character reference, an underscore emphasis
# outside a code span or a closing # sequence renders as other text than it reads, so no raw-text slug is its anchor — refused
# before any write, the title to be rephrased (thirty-fifth run, e2c DISS-C-002; the link lint names such a heading too)
gh_title_renders_raw(){
  # (a byte >= 0x80 beside an underscore counts as punctuation: “_x_” and —_x_— are emphasis on GitHub, and é_x_é is refused
  # with them, conservatively — the writer at least as strict as the link lint: thirty-sixth run, e2c DISS-C-001)
  local t nw=$'[^[:alnum:]_]' ns='[^_[:space:]]'
  local mk='\]\(|\]\[|<[A-Za-z/!?]|&(#[0-9]+|#[xX][0-9A-Fa-f]+|[A-Za-z][A-Za-z0-9]*);' cl='(^|[[:space:]])#+[[:space:]]*$'
  local em="(^|$nw)_+$ns(.*$ns)?_+($nw|$)"
  # (CommonMark closes a backtick run only on one of equal length, and strips one space from each end of a span padded at both:
  # a run of two or more, or such a span, is refused, so the left-to-right single-backtick pairing below is CommonMark's —
  # thirty-seventh run, e2c DISS-C-001 / DISS-C-002)
  # (a code span is punctuation to the underscores beside it — `a`_y_ opens emphasis on GitHub — so it becomes one placeholder,
  # never nothing; and a backslash-escaped backtick opens no span, so a title holding one is refused: thirty-eighth run, e2c DISS-C-001)
  local cs=0
  [[ "${1-}" != *'``'* && "${1-}" != *'\`'* ]] || cs=1
  printf '%s' "${1-}" | awk -F'`' '{ for (i = 2; i < NF; i += 2) if ($i ~ /^ / && $i ~ / $/ && $i ~ /[^ ]/) f = 1 } END { exit !f }' && cs=1
  t="$(printf '%s' "${1-}" | sed -E "s/\`[^\`]*\`/'/g")"
  if [[ $cs -eq 1 || "$t" =~ $mk || "$t" =~ $em || "$t" =~ $cl ]]; then
    die "new: the title renders on GitHub as other text than it reads (a link, an HTML tag, a character reference, an _emphasis_, a closing #, a backtick run of two or more, an escaped backtick or a code span padded at both ends) — its heading anchor would match no Index link; rephrase it"
  fi
}

# NB: grep can legitimately match nothing; with `set -o pipefail` the pipe then
# returns non-zero, so every grep-in-substitution is guarded with `|| true`.
next_kf_id(){ local f="$1" m; m="$( { grep -oE "$KF_HEAD_RE" "$f" 2>/dev/null | grep -oE '[0-9]+' | sort -n | tail -1; } || true)"; m="${m:-0}"; printf 'KF-%03d' "$((10#$m + 1))"; }

# Ensure the file ends with a newline so head/tail line-arithmetic is exact.
ensure_trailing_nl(){ local f="$1"; [[ -s "$f" ]] || return 0; [[ -n "$(tail -c1 "$f")" ]] && printf '\n' >> "$f" || true; }

# Verify a candidate replacement is non-destructive, then atomically swap it in.
verify_and_swap(){ # tmp target
  local tmp="$1" target="$2" ol nl lost
  ol="$(wc -l < "$target")"; nl="$(wc -l < "$tmp")"
  if [[ "$nl" -lt "$ol" ]]; then rm -f "$tmp"; die "ABORT — output ($nl lines) shorter than input ($ol); refusing to write (data-loss guard)"; fi
  lost="$(comm -23 <(grep -oE "$KF_HEAD_RE" "$target" 2>/dev/null | sort -u) <(grep -oE "$KF_HEAD_RE" "$tmp" 2>/dev/null | sort -u) || true)"
  if [[ -n "$lost" ]]; then rm -f "$tmp"; die "ABORT — would drop existing entries: $(echo $lost | tr '\n' ' ')"; fi
  mv "$tmp" "$target"
}

with_lock(){ mkdir -p "$(dirname "$LOCK")"; exec 9>"$LOCK"; flock 9 2>/dev/null || true; }

# ---- arg parsing (subcommand + --key value) ----
declare -A A
CMD="${1:-}"; [[ -n "$CMD" ]] && shift || true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --quiet) QUIET=1; shift ;;
    --*) k="${1#--}"; shift; A[$k]="${1-}"; [[ $# -gt 0 ]] && shift || true ;;
    *) die "unexpected arg: $1" ;;
  esac
done
TARGET="${A[file]-}"

# ---- region helpers (operate within a single KF entry) ----
entry_start(){ { grep -nE "^##[[:space:]]+${1}:" "$2" 2>/dev/null | head -1 | cut -d: -f1; } || true; }
entry_end(){ # id file start  -> last line of entry (line before next ## KF- heading, else EOF)
  local id="$1" f="$2" s="$3" e
  e="$(awk -v s="$s" -v re="$KF_HEAD_RE" 'NR>s && $0 ~ (re ":"){print NR-1; exit}' "$f")"
  [[ -z "$e" ]] && e="$(wc -l < "$f")"
  printf '%s' "$e"
}

op_new(){
  local f="${TARGET:-$KF_FILE}"
  [[ -f "$f" ]] || die "target not found: $f"
  local title status; title="$(san1 "${A[title]-}")"; status="$(san1 "${A[status]-}")"
  [[ -n "$title" ]] || die "new: --title required"
  [[ -n "$status" ]] || die "new: --status required (empty Status is a malformed entry per IMP-005)"
  local ad aw ao ae have_attempt=0
  ad="$(cell "${A[attempt-date]-}")"; aw="$(cell "${A[attempt-what]-}")"; ao="$(cell "${A[attempt-outcome]-}")"; ae="$(cell "${A[attempt-evidence]-}")"
  if [[ -n "${A[attempt-date]-}${A[attempt-what]-}${A[attempt-outcome]-}${A[attempt-evidence]-}" ]]; then
    have_attempt=1
    [[ -n "$ae" ]] || die "new: --attempt-evidence is REQUIRED for an Attempts row (commit SHA / PR# / run ID)"
  fi
  # (the title's anchor is computed — and a title without one refused — before the lock and the trailing-newline repair: a refused
  # title never touches the ledger; thirty-fourth run, e2c DISS-001. "KF-NNN: t" slugs as "kf-nnn" + the slug of ": t")
  gh_title_renders_raw "$title"
  # (the refusal inside the substitution reaches here by this check — never `local tail="$(…)"`, whose status is local's own:
  # thirty-eighth run, e2c DISS-C-002)
  local tail; tail="$(gh_anchor ": ${title}")" || exit 1
  with_lock
  ensure_trailing_nl "$f"
  local id anchor recur; id="$(next_kf_id "$f")"
  recur="$(san1 "${A[recur]-1}")"; recur="${recur:-1}"
  anchor="$(printf '%s' "$id" | tr '[:upper:]' '[:lower:]')${tail}"
  if grep -qiE "^##[[:space:]]+KF-[0-9]+: $(printf '%s' "$title" | sed -E 's/[.[\*^$(){}+?|/]/\\&/g')$" "$f"; then
    die "new: an entry titled \"$title\" already exists — refusing to duplicate"
  fi
  local idx_row tmp; idx_row="| [${id}](#${anchor}) | $(cell "$status") | $(cell "${A[feature]-}") | $(cell "$recur") |"
  tmp="$(mktemp)"
  local first_entry last_idx
  first_entry="$( { grep -nE "${KF_HEAD_RE}:" "$f" | head -1 | cut -d: -f1; } || true)"; first_entry="${first_entry:-$(($(wc -l < "$f")+1))}"
  last_idx="$(awk -v fe="$first_entry" 'NR<fe && /^\|[[:space:]]*\[KF-[0-9]+\]/{n=NR} END{print n+0}' "$f")"
  if [[ "$last_idx" -eq 0 ]]; then
    # empty Index table — insert after its header separator row (|----|----|...)
    last_idx="$(awk '/^## Index/{f=1} f&&/^\|[-| :]+$/{print NR; exit}' "$f")"
  fi
  [[ "${last_idx:-0}" -gt 0 ]] || die "new: could not locate the ## Index table"
  {
    head -n "$last_idx" "$f"
    printf '%s\n' "$idx_row"
    tail -n +"$((last_idx+1))" "$f"
    printf '\n## %s: %s\n\n' "$id" "$title"
    printf '**Status**: %s\n' "$status"
    printf '**Feature**: %s\n' "$(san1 "${A[feature]-unspecified}")"
    printf '**Symptom**: %s\n' "$(san1 "${A[symptom]-unspecified}")"
    printf '**First observed**: %s\n' "$(san1 "${A[first-observed]-unspecified}")"
    printf '**Recurrence count**: %s\n' "$recur"
    printf '**Current workaround**: %s\n' "$(san1 "${A[workaround]-none yet}")"
    printf '**Upstream issue**: %s\n' "$(san1 "${A[upstream]-not filed}")"
    printf '**Related visions / lore**: %s\n' "$(san1 "${A[related]-none}")"
    printf '\n### Attempts\n\n'
    printf '| Date | What we tried | Outcome | Evidence |\n'
    printf '|------|---------------|---------|----------|\n'
    [[ "$have_attempt" -eq 1 ]] && printf '| %s | %s | %s | %s |\n' "${ad:-unspecified}" "${aw:-unspecified}" "${ao:-unspecified}" "$ae"
    printf '\n### Reading guide\n\n%s\n' "$(san1 "${A[reading-guide]-TODO: what a future agent should do on this symptom.}")"
  } > "$tmp"
  verify_and_swap "$tmp" "$f"
  grep -qE "^##[[:space:]]+${id}: " "$f" || die "post-write check failed: ${id} heading missing"
  log "kf-write: appended ${id} (\"${title}\") + Index row"
  echo "$id"
}

op_attempt(){
  local f="${TARGET:-$KF_FILE}"
  [[ -f "$f" ]] || die "target not found: $f"
  local id; id="$(san1 "${A[id]-}")"
  [[ "$id" =~ ^KF-[0-9]+$ ]] || die "attempt: --id KF-NNN required"
  local ae; ae="$(cell "${A[evidence]-}")"
  [[ -n "$ae" ]] || die "attempt: --evidence is REQUIRED (the load-bearing cell: commit SHA / PR# / run ID)"
  local ad aw ao; ad="$(cell "${A[date]-}")"; aw="$(cell "${A[what]-}")"; ao="$(cell "${A[outcome]-}")"
  [[ -n "$ad" && -n "$aw" && -n "$ao" ]] || die "attempt: --date, --what, --outcome are required"
  with_lock
  ensure_trailing_nl "$f"
  local s e; s="$(entry_start "$id" "$f")"; [[ -n "$s" ]] || die "attempt: ${id} not found"
  e="$(entry_end "$id" "$f" "$s")"
  local ah; ah="$(awk -v s="$s" -v e="$e" 'NR>=s&&NR<=e&&/^### Attempts/{print NR; exit}' "$f")"
  [[ -n "$ah" ]] || die "attempt: ${id} has no '### Attempts' table — add one manually first"
  # bound the search to the Attempts SUBSECTION only: stop at the next ###/## heading,
  # so a table in a later subsection (e.g. ### Reading guide) is never targeted.
  local sub_end; sub_end="$(awk -v s="$ah" -v e="$e" 'NR>s&&NR<=e&&/^#{2,3}[[:space:]]/{print NR-1; exit}' "$f")"; sub_end="${sub_end:-$e}"
  local last_row; last_row="$(awk -v s="$ah" -v e="$sub_end" 'NR>s&&NR<=e&&/^\|/{n=NR} END{print n+0}' "$f")"
  [[ "$last_row" -gt 0 ]] || die "attempt: could not locate the Attempts table rows under ${id}"
  local row tmp; row="| ${ad} | ${aw} | ${ao} | ${ae} |"
  tmp="$(mktemp)"
  { head -n "$last_row" "$f"; printf '%s\n' "$row"; tail -n +"$((last_row+1))" "$f"; } > "$tmp"
  verify_and_swap "$tmp" "$f"
  log "kf-write: appended Attempts row to ${id}"
}

op_recur(){
  local f="${TARGET:-$KF_FILE}"
  [[ -f "$f" ]] || die "target not found: $f"
  local id; id="$(san1 "${A[id]-}")"
  [[ "$id" =~ ^KF-[0-9]+$ ]] || die "recur: --id KF-NNN required"
  with_lock
  ensure_trailing_nl "$f"
  local s e; s="$(entry_start "$id" "$f")"; [[ -n "$s" ]] || die "recur: ${id} not found"
  e="$(entry_end "$id" "$f" "$s")"
  local cur; cur="$(awk -v s="$s" -v e="$e" 'NR>=s&&NR<=e&&/^\*\*Recurrence count\*\*:/{sub(/^[^:]*:[[:space:]]*/,"");print;exit}' "$f")"
  cur="$(san1 "$cur")"
  # cycle-121: accept values that LEAD with an integer after optional
  # comparison markers (">=28 prose...", "\u2265 7 across...", "6 (notes)").
  # Increment the leading integer IN PLACE, preserving prefix + prose tail.
  local prefix="" lead="" tail="" v="$cur" geq
  geq="$(printf '\342\211\245')"   # UTF-8 ">=" glyph
  while :; do
    case "$v" in
      ">"*|"="*|"~"*|" "*) v="${v#?}" ;;
      "$geq"*)             v="${v#"$geq"}" ;;
      *) break ;;
    esac
  done
  if [[ "$v" =~ ^([0-9]+)(.*)$ ]]; then
    lead="${BASH_REMATCH[1]}"; tail="${BASH_REMATCH[2]}"; prefix="${cur%"$v"}"
  fi
  [[ -n "$lead" ]] || die "recur: ${id} Recurrence count has no leading integer (\"$cur\") — normalize it to lead with a number (prose may follow), then retry"
  local newv=$((lead + 1)) tmp; tmp="$(mktemp)"
  local newfield="${prefix}${newv}${tail}"
  awk -v s="$s" -v e="$e" -v nf="$newfield" '
    NR>=s && NR<=e && /^\*\*Recurrence count\*\*:/ && !done { $0 = "**Recurrence count**: " nf; done=1 }
    { print }
  ' "$f" > "$tmp"
  local idxcur; idxcur="$(awk -F'|' -v id="$id" '$0 ~ ("^\\|[[:space:]]*\\[" id "\\]") && NF>=5 {gsub(/^[[:space:]]+|[[:space:]]+$/,"",$5); print $5; exit}' "$tmp")"
  if [[ "$idxcur" =~ ^[0-9]+$ ]]; then
    local tmp2; tmp2="$(mktemp)"
    awk -F'|' -v OFS='|' -v id="$id" -v nv="$newv" '$0 ~ ("^\\|[[:space:]]*\\[" id "\\]") && NF>=5 { $5=" " nv " " } { print }' "$tmp" > "$tmp2"
    mv "$tmp2" "$tmp"
  else
    log "kf-write: NOTE — ${id} Index recurrence cell is non-integer/unmatched (\"$idxcur\"); left unchanged"
  fi
  verify_and_swap "$tmp" "$f"
  log "kf-write: ${id} Recurrence count leading integer ${lead} -> ${newv}"
}

op_notes_header(){
  local f="${TARGET:-$NOTES_FILE}"
  [[ -f "$f" ]] || die "target not found: $f"
  local date cycle note; date="$(san1 "${A[date]-}")"; cycle="$(san1 "${A[cycle]-}")"; note="$(san1 "${A[note]-}")"
  [[ -n "$date" ]] || die "notes-header: --date YYYY-MM-DD required"
  [[ -n "$cycle" ]] || die "notes-header: --cycle required"
  with_lock
  ensure_trailing_nl "$f"
  local hdr="## Decision Log — ${date} (${cycle})"
  local title_line; title_line="$( { grep -nE '^# ' "$f" | head -1 | cut -d: -f1; } || true)"; title_line="${title_line:-0}"
  local tmp; tmp="$(mktemp)"
  {
    [[ "$title_line" -gt 0 ]] && head -n "$title_line" "$f"
    printf '\n%s\n' "$hdr"
    [[ -n "$note" ]] && printf '\n%s\n' "$note"
    [[ "$title_line" -gt 0 ]] && tail -n +"$((title_line+1))" "$f" || cat "$f"
  } > "$tmp"
  local ol nl; ol="$(wc -l < "$f")"; nl="$(wc -l < "$tmp")"
  [[ "$nl" -ge "$ol" ]] || { rm -f "$tmp"; die "notes-header: ABORT — output shorter than input"; }
  mv "$tmp" "$f"
  log "kf-write: prepended NOTES header \"${hdr}\""
}

case "$CMD" in
  new) op_new ;;
  attempt) op_attempt ;;
  recur) op_recur ;;
  notes-header) op_notes_header ;;
  -h|--help|"") sed -n '2,40p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; [[ "$CMD" == "" ]] && exit 2 || exit 0 ;;
  *) die "unknown command: $CMD (new|attempt|recur|notes-header)" ;;
esac
