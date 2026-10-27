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
    function fieldval(line, label,   reA, reB, v) {
      # Two field-line variants, both with an optional "- " list marker:
      #   A) **Label**: value                 (colon outside the bold)
      #   B) **Label[ (suffix)]:** value       (colon inside the bold; suffix
      #      may contain spaces/parens/em-dash but no "*")
      reA = "^(- )?\\*\\*" label "\\*\\*: ?"
      reB = "^(- )?\\*\\*" label "[^*]*:\\*\\* ?"
      if (line ~ reA) { v = line; sub(reA, "", v); return v }
      if (line ~ reB) { v = line; sub(reB, "", v); return v }
      return ""
    }
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
emit_decisions(){
  local f="${G}/decisions.yaml" j v=""; [[ -f "$f" ]] || return 0
  command -v yq >/dev/null 2>&1 && v="$(yq --version 2>&1 || true)"
  if [[ "$v" != *mikefarah*"version v4."* ]]; then
    echo "grimoire-index: NOTE: decisions family skipped (needs Mike Farah yq v4)" >&2; return 0
  fi
  if ! j="$(yq -o=json -I0 '.decisions // []' "$f" 2>/dev/null)" || ! printf '%s' "$j" | jq -e 'type == "array"' >/dev/null 2>&1; then
    echo "grimoire-index: NOTE: decisions family skipped (grimoires/loa/decisions.yaml does not parse)" >&2; return 0
  fi
  # Rows are agent-authored and UNTRUSTED (as in loa-decisions-surface.sh): every field is cleaned in jq.
  # C0/C1 controls (tab and newline included, so no cell shifts the TAB columns) and U+2028/9 become
  # spaces, < and > become single guillemets, and each field is capped at 160 code points.
  printf '%s' "$j" | jq -r '
    def s: tostring | gsub("[[:cntrl:]\u0080-\u009f\u2028\u2029]"; " ") | gsub("<"; "\u2039") | gsub(">"; "\u203a")
           | gsub("  +"; " ") | sub("^ "; "") | sub(" $"; "") | .[0:160];
    .[] | objects | select(((.id // "") | s) != "")
    | ["decisions", (.id | s), ((.status // "") | s), ((.summary // "") | s), ("grimoires/loa/decisions.yaml#" + (.id | s)),
       ((.source // "") | s), "", "", ((.decided_by // .proposed_by // "") | s)] | join("\t")'
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
    bad="$(echo "$JSON" | jq -r '[.families[][] | select((.id|length)==0 or (.path|length)==0 or (.family|test("[^a-z]")))] | length')"
    if [[ "$bad" != "0" ]]; then echo "::error::[GRIMOIRE-INDEX] refusing to write — $bad malformed records (id/path/family). Likely a corrupt source filename." >&2; exit 1; fi
    exec 9>"$LOCK"; flock 9 2>/dev/null || true
    tmpj="$(mktemp)"; printf '%s\n' "$JSON" > "$tmpj"; mv "$tmpj" "$OUT_JSON"
    tmpm="$(mktemp)"; render_md "$JSON" > "$tmpm"; mv "$tmpm" "$OUT_MD"
    log "grimoire-index: wrote ${OUT_MD#$PROJECT_ROOT/} + ${OUT_JSON#$PROJECT_ROOT/} ($(echo "$JSON" | jq -r '.total') entries)" ;;
esac
