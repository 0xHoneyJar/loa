#!/usr/bin/env bash
# =============================================================================
# grimoire-index.sh — unified cross-family index of the grimoire corpus
#
# OKF/ICM adoption cycle, Sprint 3 (rec #1, the keystone). Walks the State-Zone
# knowledge families that today have SEPARATE id namespaces and no shared index,
# and emits ONE traversable catalog so an agent can navigate KF → vision → lore →
# handoff → observation without bespoke per-family knowledge.
#
# Families (v1): KF (## KF-NNN: headings, enriched from the ## Index table),
#   vision (visions/entries/), lore (lore/index.yaml), handoff (handoffs/INDEX.md),
#   decisions (grimoires/loa/decisions.yaml rows; needs yq v4, else skipped with a note),
#
# SECURITY: L5/L6/L7 + observation bodies are UNTRUSTED (CLAUDE.md universal
#   invariant). This generator extracts ONLY id/status/path/title/tags and
#   ID-SHAPED outbound refs (strict regex), control-byte-sanitizes every field,
#   and NEVER interprets body prose as instructions. Titles are sanitized + capped.
#
# DETERMINISM: pure function of inputs (no wall-clock); records sorted by
#   family,id under LC_ALL=C — output is stable and drift-gateable.
#
# Emits: grimoires/loa/INDEX.md (human) + .run/grimoire-index.json (machine).
#   Both are DERIVED + gitignored — regenerate on demand (e.g. at session start); they
#   index partly-gitignored families, so committing them would carry dangling refs.
# Flags: --json (print JSON to stdout) --tsv (print the raw sorted TSV records) --validate (integrity + KF-table drift) --quiet
# =============================================================================
export LC_ALL=C
export TZ=UTC
set -euo pipefail

# Environment (kept out of the --help text above, which is lines 2-30 verbatim):
#   LOA_GRIMOIRE_INDEX_NO_CACHE=1  disables the decisions-family cache
#     (.run/perf-cache/grimoire-index-decisions.v1.tsv) for both read and write. CI or GITHUB_ACTIONS
#     set disables it too. Trust boundary and key: see emit_decisions.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
G="${PROJECT_ROOT}/grimoires/loa"
OUT_MD="${G}/INDEX.md"
OUT_JSON="${PROJECT_ROOT}/.run/grimoire-index.json"
LOCK="${PROJECT_ROOT}/.run/.grimoire-index.lock"
MODE="write"; QUIET=0
source "${SCRIPT_DIR}/compat-lib.sh"

require_jq(){ command -v jq >/dev/null 2>&1 || { echo "grimoire-index: jq required" >&2; exit 3; }; }
log(){ [[ $QUIET -eq 0 ]] && echo "$@" >&2 || true; }

parse_args(){
  while [[ $# -gt 0 ]]; do case "$1" in
    --json) MODE="json" ;;
    --tsv) MODE="tsv" ;;
    --validate) MODE="validate" ;;
    --quiet) QUIET=1 ;;
    -h|--help) sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "grimoire-index: unknown arg: $1" >&2; exit 2 ;;
  esac; shift; done
}

# Strip control bytes (keep UTF-8 multibyte), flatten whitespace, cap length.
san(){ printf '%s' "${1-}" | tr -d '\000-\010\013\014\016-\037\177' | tr '\t\n\r' '   ' | sed -E 's/  +/ /g; s/^ //; s/ $//' | cut -c1-160; }
# Byte-for-byte awk twin of san() (LC_ALL=C: substr/length count BYTES, like cut -c), plus rd(), an
# emulation of `IFS=$'\t' read -r` (a whitespace IFS: leading/trailing tabs trimmed, tab RUNS collapse to
# one separator, last variable takes the remainder). Prepended to the emit_* awk programs so each family
# is ONE pass with no per-field subprocesses. Keep san() and SAN_AWK in lock-step.
SAN_AWK='
# Byte cap: under LC_ALL=C substr() caps BYTES. GNU cut -c was already byte-based on Linux, so Linux
# output is unchanged; BSD cut hosts formerly capped characters.
function san(s) {
  gsub(/\000/, "", s)
  gsub(/[\001-\010\013\014\016-\037\177]/, "", s)
  gsub(/[\t\n\r]/, " ", s)
  gsub(/  +/, " ", s)
  sub(/^ /, "", s); sub(/ $/, "", s)
  return substr(s, 1, 160)
}
function rd(line, n, out,   i, p) {
  gsub(/\000/, "", line)
  sub(/^\t+/, "", line)
  for (i = 1; i < n; i++) {
    p = index(line, "\t")
    if (p == 0) { out[i] = line; line = "" }
    else { out[i] = substr(line, 1, p - 1); line = substr(line, p + 1); sub(/^\t+/, "", line) }
  }
  sub(/\t+$/, "", line); out[n] = line
}
'
# Extract ONLY id-shaped outbound refs (never free prose), deduped, comma-joined.
refs_of(){ grep -oE 'KF-[0-9]{3}|vision-[0-9]{3}|#[0-9]{2,5}|sha256:[a-f0-9]{8}' "${1}" 2>/dev/null | awk '!s[$0]++' | head -20 | paste -sd, - || true; }

# TSV rows: family<TAB>id<TAB>status<TAB>title<TAB>relpath<TAB>refs<TAB>symptom<TAB>recurrence
# The kf family generates its rows FROM the ## KF-NNN: headings (source of truth,
# complete) — the hand-maintained "## Index" table can no longer make the derived
# Index drift. Each row's status/symptom/recurrence are parsed from the entry body.
emit_kf(){
  local f="${G}/known-failures.md"; [[ -f "$f" ]] || return 0
  # Parse per-id Status / Symptom / Recurrence from each entry body. We read the
  # whole file once in awk: on a ## KF-NNN: heading we open a new entry; the first
  # **Status**/**Symptom**/**Recurrence count** line of that entry wins. Recurrence
  # is reduced to a leading integer (5+ -> 5, >=7 -> 7); non-numeric (many/every/
  # n/a) -> "?". Bodies are UNTRUSTED — sanitized at surfacing by san() (its awk twin in SAN_AWK).
  awk "$SAN_AWK"'
    function fieldval(line, label,   reA, reB, reC, v) {
      # Three field-line variants, each with an optional "- " list marker:
      #   A) **Label**: value                 (colon outside the bold)
      #   B) **Label[ (suffix)]:** value       (colon inside the bold; suffix
      #      may contain spaces/parens/em-dash but no "*")
      #   C) **Label (suffix)**: value         (a space after the label, colon outside the bold),
      #      for Symptom and Recurrence count ONLY: a qualified Status ("Status (original)") is a
      #      historical annotation and never the entry status (sdd D-2.2). Keep in step with the twin.
      reA = "^(- )?\\*\\*" label "\\*\\*: ?"
      reB = "^(- )?\\*\\*" label "[^*]*:\\*\\* ?"
      reC = "^(- )?\\*\\*" label "( [^*]*)?\\*\\*: ?"
      if (line ~ reA) { v = line; sub(reA, "", v); return v }
      if (line ~ reB) { v = line; sub(reB, "", v); return v }
      if ((label == "Symptom" || label == "Recurrence count") && line ~ reC) { v = line; sub(reC, "", v); return v }
      return ""
    }
    # Every H2 heading closes the current entry; only a ## KF-NNN: heading opens one.
    /^## / { cur = "" }
    /^## KF-[0-9]+:/ {
      if (match($0, /KF-[0-9]+/)) { id = substr($0, RSTART, RLENGTH) }
      else { id = "" }
      title = $0; sub(/^## KF-[0-9]+: */, "", title)
      if (id != "" && !(id in seen)) { order[++n] = id; seen[id] = 1; ttl[id] = title }
      cur = id; next
    }
    cur != "" {
      if (st[cur] == "") { v = fieldval($0, "Status");          if (v != "") { st[cur] = v; next } }
      if (sy[cur] == "") { v = fieldval($0, "Symptom");         if (v != "") { sy[cur] = v; next } }
      if (rc[cur] == "") { v = fieldval($0, "Recurrence count"); if (v != "") { rc[cur] = v; next } }
    }
    END {
      for (i = 1; i <= n; i++) {
        id = order[i]
        r = rc[id]
        # Numeric recurrence ONLY when the value LEADS with digits, after an
        # optional run of comparison markers. ">=7" -> 7, "5+" -> 5,
        # "≥ 7" -> 7. Non-numeric leads (many / every PR since dd54fe9c /
        # n/a (cycle-102)) -> "?" — a digit is NEVER scraped from prose.
        num = "?"
        v = r
        # peel a leading comparison prefix: ASCII >=~ , spaces, and the UTF-8
        # >= glyph (bytes \342\211\245).
        gsub(/^([>=~ ]|\342\211\245)+/, "", v)
        if (match(v, /^[0-9]+/)) num = substr(v, RSTART, RLENGTH)
        # Tab-split exactly as the former `IFS=$'\t' read -r` row loop did (an
        # empty Status/Symptom collapses its tab and shifts the later columns —
        # preserved byte-for-byte): id, status, title, symptom, recurrence.
        rd(id "\t" st[id] "\t" ttl[id] "\t" sy[id] "\t" num, 5, f)
        if (f[1] == "") continue
        recurrence = f[5]; if (recurrence == "") recurrence = "?"
        # cycle-121: recurrence >=3 is the load-bearing signal (CLAUDE.md intake
        # discipline) — an unparseable count silently disarms it, so WARN loudly.
        if (recurrence == "?")
          print "grimoire-index: WARN — " f[1] " Recurrence count is not integer-leading; the >=3 escalation signal cannot fire for it" > "/dev/stderr"
        # Status cells are tier-2 index material: truncate resolution prose >120
        # chars (tier-3 detail belongs in the entry body, not the index row).
        status = f[2]
        if (length(status) > 120) status = substr(status, 1, 117) "..."
        printf "kf\t%s\t%s\t%s\tgrimoires/loa/known-failures.md\t\t%s\t%s\n", \
          san(f[1]), san(status), san(f[3]), san(f[4]), san(recurrence)
      }
    }
  ' "$f"
}
emit_vision(){
  local d="${G}/visions/entries"; [[ -d "$d" ]] || return 0
  local f bn src
  for f in "$d"/vision-*.md; do
    [[ -e "$f" ]] || continue
    bn="${f##*/}"; src="$f"
    if [[ ! -r "$f" ]]; then
      echo "grimoire-index: WARN — ${f} is unreadable; its vision row is emitted with blank id/status/title" >&2; src=/dev/null
    fi
    # One awk per file: first **ID**: vision-N (else the file stem), first **Status**: and first
    # "# Vision:" line, each san()-ed in awk. Only refs_of stays a separate (untouched) pipeline.
    printf '%s\t%s\n' "$(BN="$bn" awk "$SAN_AWK"'
      !hi && match($0, /^\*\*ID\*\*: *vision-[0-9]+/) {
        hi = 1; id = substr($0, RSTART, RLENGTH); match(id, /vision-[0-9]+/); id = substr(id, RSTART, RLENGTH)
      }
      !hs && /^\*\*Status\*\*:/ { hs = 1; status = $0; sub(/^\*\*Status\*\*: */, "", status) }
      !ht && /^# Vision:/ { ht = 1; title = $0; sub(/^# Vision: */, "", title) }
      END {
        if (id == "") { id = ENVIRON["BN"]; sub(/\.md$/, "", id) }
        printf "vision\t%s\t%s\t%s\tgrimoires/loa/visions/entries/%s", san(id), san(status), san(title), san(ENVIRON["BN"])
      }' "$src")" "$(refs_of "$f")"
  done
}
emit_lore(){
  local f="${G}/lore/index.yaml"; [[ -f "$f" ]] || return 0
  awk "$SAN_AWK"'
    /^[[:space:]]*-[[:space:]]*id:[[:space:]]*/ { id=$0; sub(/^[[:space:]]*-[[:space:]]*id:[[:space:]]*/,"",id); have=1; st="" }
    have && /^[[:space:]]*status:[[:space:]]*/ {
      st=$0; sub(/^[[:space:]]*status:[[:space:]]*/,"",st); have=0
      rd(id "\t" st, 2, f)
      printf "lore\t%s\t%s\t%s\tgrimoires/loa/lore/index.yaml\t\n", san(f[1]), san(f[2]), san(f[1])
    }
  ' "$f"
}
emit_handoff(){
  local f="${G}/handoffs/INDEX.md"; [[ -f "$f" ]] || return 0
  # Fields split on "|" like the former `IFS='|' read -r _ hid file _from _to topic ts _rest`. Exits 1
  # when no row matches, as the grep it replaces did (pipefail/errexit semantics preserved).
  awk "$SAN_AWK"'
    /^\| *sha256:[a-f0-9]+ *\|/ {
      m = 1; split($0, a, "|")
      printf "handoff\t%s\t%s\t%s\tgrimoires/loa/handoffs/%s\t\n", san(a[2]), san(a[7]), san(a[6]), san(a[3])
    }
    END { if (!m) exit 1 }
  ' "$f"
}
# notes family (cycle-121): surfaces NOTES.md's ## headings so sessions can
# jump to current working state without reading the whole file.
emit_notes(){
  local f="${G}/NOTES.md"; [[ -f "$f" ]] || return 0
  # A final line with no trailing newline was never seen by the `while read` loop this replaces, so
  # it is dropped here too (unterminated=1): rows are emitted one record late and the last is held back.
  local unterminated=0; [[ -n "$(tail -c1 "$f")" ]] && unterminated=1
  awk -v unterminated="$unterminated" "$SAN_AWK"'
    { if (pend != "") { print pend; pend = "" } }
    /^## / { pend = sprintf("notes\tL%d\t\t%s\tgrimoires/loa/NOTES.md#L%d\t", NR, san(substr($0, 4)), NR) }
    END { if (pend != "" && !unterminated) print pend }
  ' "$f"
}

# decisions family: one row per grimoires/loa/decisions.yaml entry. Columns: id,
# status, summary (title slot), path <ledger>#<id>, refs = source, two empty slots,
# voice ninth (decided_by // proposed_by). yq is optional here: without Mike Farah
# yq v4, or on an unparsable ledger, the family is skipped with a stderr note.
#
# Decisions cache (cycle-137 FR-5, sdd \u00a7 3 / \u00a7 5.5). The family's rows, exactly as printed, are kept in
# $PROJECT_ROOT/.run/perf-cache/grimoire-index-decisions.v1.tsv: line 1 is the key
#   <GI_DEC_KEY_PREFIX>:<sha256 of the decisions.yaml snapshot>:<yq major.minor>:<jq major.minor>:<rows>
# and each later line is one row. Trust boundary, checked before any read or write: .run and
# .run/perf-cache are real directories (not symlinks) owned by the current uid with no group or other
# write bit, the cache file is not a symlink, CI and GITHUB_ACTIONS are unset and
# LOA_GRIMOIRE_INDEX_NO_CACHE is not 1. Otherwise the family is built exactly as before the cache. The
# key and the rows come from ONE snapshot of decisions.yaml (sha256 and yq both read the copy), so a
# rewrite mid-run cannot pair a new key with old rows. A cache that fails validation is a miss; a
# failed write is ignored (never fatal, never a stderr line).
#
# Cache-key prefix, bound to GI_DEC_JQ just below: ANY edit of that jq program (its `s` sanitiser
# included) must bump GI_DEC_KEY_PREFIX (v1 -> v2) in the same commit, or rows rendered by the old
# program would be served as current. tests/unit/grimoire-index.bats pins each (prefix, sha256 of the
# GI_DEC_JQ literal) pair, so an edit without a bump fails there.
GI_DEC_KEY_PREFIX="v1"
# Rows are agent-authored and UNTRUSTED (as in loa-decisions-surface.sh): every field is cleaned in jq.
# C0/C1 controls (tab and newline included, so no cell shifts the TAB columns) and U+2028/9 become
# spaces, < and > become single guillemets, and each field is capped at 160 code points.
GI_DEC_JQ='
    def s: tostring | gsub("[[:cntrl:]\u0080-\u009f\u2028\u2029]"; " ") | gsub("<"; "\u2039") | gsub(">"; "\u203a")
           | gsub("  +"; " ") | sub("^ "; "") | sub(" $"; "") | .[0:160];
    .[] | objects | select(((.id // "") | s) != "")
    | ["decisions", (.id | s), ((.status // "") | s), ((.summary // "") | s), ("grimoires/loa/decisions.yaml#" + (.id | s)),
       ((.source // "") | s), "", "", ((.decided_by // .proposed_by // "") | s)] | join("\t")'

# _gi_trusted_dir <dir>: 0 when <dir> is a real directory (not a symlink) owned by the current uid with
# no group or other write bit. GNU stat, then BSD stat; any stat failure means "not trusted".
_gi_trusted_dir(){
  local st
  [[ -d "$1" && ! -L "$1" ]] || return 1
  st="$(stat -c '%u %a' -- "$1" 2>/dev/null)" || st="$(stat -f '%u %Lp' -- "$1" 2>/dev/null)" || return 1
  [[ "$st" =~ ^([0-9]+)\ ([0-7]+)$ ]] || return 1
  [[ "${BASH_REMATCH[1]}" == "$EUID" ]] || return 1
  (( (8#${BASH_REMATCH[2]} & 8#022) == 0 ))
}
# _gi_dec_cache_on: the environment and directory half of the trust boundary (a missing perf-cache
# directory is allowed: the writer creates it under umask 077 and re-checks it).
_gi_dec_cache_on(){
  [[ "${LOA_GRIMOIRE_INDEX_NO_CACHE:-}" != "1" && -z "${CI+x}" && -z "${GITHUB_ACTIONS+x}" ]] || return 1
  _gi_trusted_dir "${PROJECT_ROOT}/.run" || return 1
  [[ ! -L "${PROJECT_ROOT}/.run/perf-cache" ]] || return 1
  [[ ! -e "${PROJECT_ROOT}/.run/perf-cache" ]] || _gi_trusted_dir "${PROJECT_ROOT}/.run/perf-cache"
}
# _gi_dec_key <snapshot> <yq --version text>: sets the caller's `key` to
# <prefix>:<sha256 of the snapshot>:<yq major.minor>:<jq major.minor>; 1 when any part is unavailable.
_gi_dec_key(){
  local sum yv jv
  [[ "$2" =~ version\ v([0-9]+)\.([0-9]+) ]] || return 1
  yv="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"
  jv="$(jq --version 2>/dev/null)" || return 1
  [[ "$jv" =~ ([0-9]+)\.([0-9]+) ]] || return 1
  jv="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"
  sum="$(sha256_portable < "$1" 2>/dev/null)" || return 1
  sum="${sum%% *}"
  [[ "$sum" =~ ^[0-9a-f]{64}$ ]] || return 1
  key="${GI_DEC_KEY_PREFIX}:${sum}:${yv}:${jv}"
}
# _gi_dec_read <cache> <key>: ONE awk validates the whole file \u2014 line 1 is "<key>:<n>", then exactly n
# rows of 9 TAB-separated fields with no byte of [\000-\010\012-\037\177<>] (outside the jq sanitiser's
# output alphabet) \u2014 and prints the rows only after all of it validated; exit 1 is a miss. NUL is tested
# with index() and a one-byte NUL string, not /\000/: busybox awk reads /\000/ as an empty regex that
# matches every line (and ends a record at a NUL, so a NUL row there fails the field or row count).
_gi_dec_read(){
  awk -v k="$2" '
    BEGIN { z = sprintf("%c", 0) }
    NR == 1 {
      if (index($0, k ":") != 1) { bad = 1; exit }
      c = substr($0, length(k) + 2)
      if (c !~ /^(0|[1-9][0-9]*)$/) { bad = 1; exit }
      next
    }
    split($0, fld, "\t") != 9 || /[\001-\010\012-\037\177<>]/ || (z != "" && index($0, z)) { bad = 1; exit }
    { row[NR - 1] = $0 }
    END {
      if (bad || NR < 1 || NR - 1 != c + 0) exit 1
      for (i = 1; i < NR; i++) print row[i]
    }' "$1"
}
# _gi_dec_write <cache> <key> <rows>: umask 077; mkdir -p (when absent), then re-check the directory (not a symlink,
# trusted); an exclusive mktemp beside the cache; key line + rows; re-check that the cache path is not
# a symlink immediately before the rename; mv -f -T (mv -f where -T is unsupported). Any failure
# removes the temp and returns 1. Concurrent writers: the rename is atomic, same key => same rows.
_gi_dec_write(){
  ( umask 077
    dir="${1%/*}" tmp=""
    if { [[ -d "$dir" ]] || mkdir -p -- "$dir" 2>/dev/null; } && _gi_trusted_dir "$dir" && [[ ! -L "$1" ]] &&
       tmp="$(mktemp "$1.XXXXXX" 2>/dev/null)" &&
       { if [[ -n "$3" ]]; then printf '%s\n' "$3"; fi |
           awk -v k="$2" '{ r[NR] = $0 } END { print k ":" NR; for (i = 1; i <= NR; i++) print r[i] }' > "$tmp"; } 2>/dev/null &&
       [[ ! -L "$1" ]] &&
       { mv -f -T -- "$tmp" "$1" 2>/dev/null || { [[ ! -d "$1" && ! -L "$1" ]] && mv -f -- "$tmp" "$1" 2>/dev/null; }; }
    then exit 0; fi
    [[ -z "$tmp" ]] || rm -f -- "$tmp" 2>/dev/null
    exit 1 )
}
emit_decisions(){
  local f="${G}/decisions.yaml" j v=""; [[ -f "$f" ]] || return 0
  command -v yq >/dev/null 2>&1 && v="$(yq --version 2>&1 || true)"
  if [[ "$v" != *mikefarah*"version v4."* ]]; then
    echo "grimoire-index: NOTE: decisions family skipped (needs Mike Farah yq v4)" >&2; return 0
  fi
  local cache="${PROJECT_ROOT}/.run/perf-cache/grimoire-index-decisions.v1.tsv" snap="" key="" rows=""
  if _gi_dec_cache_on && [[ ! -L "$cache" ]] && snap="$(mktemp 2>/dev/null)"; then
    if cp -- "$f" "$snap" 2>/dev/null && _gi_dec_key "$snap" "$v"; then
      if [[ -f "$cache" ]] && rows="$(_gi_dec_read "$cache" "$key")"; then
        rm -f -- "$snap"; [[ -z "$rows" ]] || printf '%s\n' "$rows"; return 0   # hit (zero rows is a hit too)
      fi
      f="$snap"   # miss: parse the snapshot the key was computed from
    else
      rm -f -- "$snap"; snap=""
    fi
  else
    snap=""
  fi
  if ! j="$(yq -o=json -I0 '.decisions // []' "$f" 2>/dev/null)" || ! printf '%s' "$j" | jq -e 'type == "array"' >/dev/null 2>&1; then
    [[ -z "$snap" ]] || rm -f -- "$snap"
    echo "grimoire-index: NOTE: decisions family skipped (grimoires/loa/decisions.yaml does not parse)" >&2; return 0
  fi
  if [[ -n "$snap" ]]; then
    rm -f -- "$snap"
    if rows="$(printf '%s' "$j" | jq -r "$GI_DEC_JQ" 2>/dev/null)"; then
      [[ -z "$rows" ]] || printf '%s\n' "$rows"
      _gi_dec_write "$cache" "$key" "$rows" || true
      return 0
    fi
  fi
  printf '%s' "$j" | jq -r "$GI_DEC_JQ"
}

# emit_obs removed cycle-121 (observation store deleted)

collect(){ { emit_kf; emit_vision; emit_lore; emit_handoff; emit_notes; emit_decisions; } | LC_ALL=C sort -t$'\t' -k1,1 -k2,2; }

to_json(){
  collect | jq -R -s '
    [ split("\n")[] | select(length>0) | split("\t")
      | {family:.[0], id:.[1], status:.[2], title:.[3], path:.[4],
         refs:(.[5]//""|if .=="" then [] else split(",") end),
         symptom:(.[6]//""), recurrence:(.[7]//""), voice:(.[8]//"")} ]
    | { families: (group_by(.family) | map({key:.[0].family, value:.}) | from_entries),
        counts: (group_by(.family) | map({key:.[0].family, value:length}) | from_entries),
        total: length }
  '
}

# One jq program, fed the index JSON once, renders the whole markdown body (it used to re-parse the full
# index JSON in up to 13 separate jq processes: .total, then per family a count and a rows pass). Family
# order is fixed; a family with no count is skipped; every cell goes through esc (pipe-escaping).
render_md(){
  local json="$1"
  echo "<!-- generated by grimoire-index.sh — DO NOT EDIT. Regenerate: bash .claude/scripts/grimoire-index.sh -->"
  echo
  echo "# Grimoire Index"
  echo
  echo "$json" | jq -r '
    def esc: gsub("\\|";"\\|");
    . as $d
    | "Unified cross-family catalog of the grimoire knowledge corpus (KF · vision · lore · handoff · observation). Generated; do not hand-edit. Total entries: \($d.total).", "",
      ("decisions","handoff","kf","lore","notes","vision") as $fam
      | ($d.counts[$fam] // 0) as $count
      | select($count != 0)
      | "## \($fam) (\($count))", "",
        (if $fam == "decisions" then
          # decisions rows: Decided by = decided_by, or the proposing voice while the row awaits /decisions confirm.
          "| ID | Status | Decided by | Summary | Source |",
          "|----|--------|------------|---------|--------|",
          ($d.families[$fam][] | "| \(.id|esc) | \(.status|esc) | \((.voice//"")|esc) | \(.title|esc) | \((.refs//[])|join(",")|esc) |")
        elif $fam == "kf" then
          # kf rows are generated from the ## KF-NNN: headings (source of truth) and
          # carry a parsed Symptom + numeric Recurrence — drift-proof by construction.
          "| ID | Status | Recurrence | Symptom | Title | Path |",
          "|----|--------|------------|---------|-------|------|",
          ($d.families[$fam][] | "| \(.id|esc) | \(.status|esc) | \((.recurrence//"")|esc) | \((.symptom//"")|esc) | \(.title|esc) | \(.path|esc) |")
        else
          "| ID | Status | Title | Path | Refs |",
          "|----|--------|-------|------|------|",
          ($d.families[$fam][] | "| \(.id|esc) | \(.status|esc) | \(.title|esc) | \(.path|esc) | \((.refs//[])|join(", ")|esc) |")
        end),
        ""'
}

# --- main ---
parse_args "$@"
require_jq
if [[ "$MODE" == "tsv" ]]; then collect; exit 0; fi
mkdir -p "${PROJECT_ROOT}/.run"
JSON="$(to_json)"

case "$MODE" in
  json) echo "$JSON" ;;
  validate)
    rc=0
    bad="$(echo "$JSON" | jq -r '[.families[][] | select((.id|length)==0 or (.path|length)==0)] | length')"
    [[ "$bad" != "0" ]] && { echo "::error::[GRIMOIRE-INDEX] $bad entries missing id/path" >&2; rc=1; }
    # KF Index drift — FAIL-ON-DRIFT assertion (cycle-115 D1). The derived kf
    # Index is now AUTHORITATIVE: one row is generated per ## KF-NNN: heading
    # (source of truth). raw_heads is the literal heading count; gen_kf is the
    # number of rows emitted (deduplicated by id). On a clean file these are
    # equal. A mismatch means a heading id is DUPLICATED (two entries claiming
    # one KF-NNN — a defect in the append-only log) or the generator silently
    # dropped/added an entry — either way the derived Index no longer faithfully
    # mirrors the headings. That is a hard error, not an informational warning.
    raw_heads=$(grep -cE '^## KF-[0-9]+:' "${G}/known-failures.md" 2>/dev/null || true); raw_heads=${raw_heads:-0}
    gen_kf=$(echo "$JSON" | jq -r '.counts.kf // 0')
    if [[ "$raw_heads" != "$gen_kf" ]]; then
      echo "::error::[GRIMOIRE-INDEX] generated kf Index has ${gen_kf} rows but known-failures.md has ${raw_heads} ## KF- headings — derived Index drifted from source of truth (duplicate heading id, or a dropped/added entry)." >&2
      rc=1
    fi
    # The hand-maintained "## Index" table inside known-failures.md is being
    # superseded by this derived Index; its staleness is informational only
    # (human-edit scope, tracked separately) and does NOT fail validation.
    hand_rows=$(awk '/^## Index/{i=1;next} i&&/^## /{exit} i' "${G}/known-failures.md" 2>/dev/null | grep -cE '^\| *\[KF-[0-9]+\]' || true); hand_rows=${hand_rows:-0}
    if [[ "$hand_rows" != "$raw_heads" ]]; then
      echo "::warning::[GRIMOIRE-INDEX] known-failures.md hand ## Index table lists ${hand_rows} KF rows but there are ${raw_heads} ## KF- entries — hand table is stale (informational; the derived Index is authoritative)." >&2
    fi
    [[ $rc -eq 0 ]] && log "grimoire-index: valid ($(echo "$JSON" | jq -r '.total') entries; kf=${gen_kf}, headings=${raw_heads}, hand-table=${hand_rows})"
    exit $rc ;;
  write)
    # The malformed-record count and .total come from ONE jq that keeps the root object. Exactly two
    # output lines are required (read without mapfile, which bash 3.2 lacks); a jq failure or any other
    # line count refuses the write, as a nonzero count does.
    wm="$(echo "$JSON" | jq -r '. as $root | ([$root.families[][] | select((.id|length)==0 or (.path|length)==0 or (.family|test("[^a-z]")))] | length), $root.total')" || wm=""
    bad="?"; total=""
    if [[ "$wm" == *$'\n'* && "${wm#*$'\n'}" != *$'\n'* ]]; then bad="${wm%%$'\n'*}"; total="${wm#*$'\n'}"; fi
    if [[ "$bad" != "0" ]]; then echo "::error::[GRIMOIRE-INDEX] refusing to write — $bad malformed records (id/path/family). Likely a corrupt source filename." >&2; exit 1; fi
    exec 9>"$LOCK"; flock 9 2>/dev/null || true
    tmpj="$(mktemp)"; printf '%s\n' "$JSON" > "$tmpj"; mv "$tmpj" "$OUT_JSON"
    tmpm="$(mktemp)"; render_md "$JSON" > "$tmpm"; mv "$tmpm" "$OUT_MD"
    log "grimoire-index: wrote ${OUT_MD#$PROJECT_ROOT/} + ${OUT_JSON#$PROJECT_ROOT/} (${total} entries)" ;;
esac
