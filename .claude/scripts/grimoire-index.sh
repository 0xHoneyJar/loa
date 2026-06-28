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
#   obs (memory/observations.jsonl).
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
# Flags: --json (print JSON to stdout) --validate (integrity + KF-table drift) --quiet
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
    --validate) MODE="validate" ;;
    --quiet) QUIET=1 ;;
    -h|--help) sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "grimoire-index: unknown arg: $1" >&2; exit 2 ;;
  esac; shift; done
}

# Strip control bytes (keep UTF-8 multibyte), flatten whitespace, cap length.
san(){ printf '%s' "${1-}" | tr -d '\000-\010\013\014\016-\037\177' | tr '\t\n\r' '   ' | sed -E 's/  +/ /g; s/^ //; s/ $//' | cut -c1-160; }
# Extract ONLY id-shaped outbound refs (never free prose), deduped, comma-joined.
refs_of(){ grep -oE 'KF-[0-9]{3}|vision-[0-9]{3}|#[0-9]{2,5}|sha256:[a-f0-9]{8}' "${1}" 2>/dev/null | awk '!s[$0]++' | head -20 | paste -sd, - || true; }

# TSV rows: family<TAB>id<TAB>status<TAB>title<TAB>relpath<TAB>refs
emit_kf(){
  local f="${G}/known-failures.md"; [[ -f "$f" ]] || return 0
  local idx; idx="$(mktemp)"
  # id->status lookup from the maintained "## Index" table (| [KF-NNN](#a) | status | ... |)
  awk '/^## Index/{i=1;next} i&&/^## /{exit} i' "$f" \
    | grep -E '^\| *\[KF-[0-9]+\]' \
    | while IFS='|' read -r _ idcell st _feat _rec _rest; do
        kid="$(printf '%s' "$idcell" | grep -oE 'KF-[0-9]+' | head -1)"
        [[ -n "$kid" ]] && printf '%s\t%s\n' "$kid" "$(san "$st")"
      done > "$idx"
  # Index from the REAL entry headings (## KF-NNN: — source of truth, complete), deduped by id.
  grep -E '^## KF-[0-9]+:' "$f" \
    | awk '{ if(match($0,/KF-[0-9]+/)){k=substr($0,RSTART,RLENGTH); if(!s[k]++) print}}' \
    | while IFS= read -r line; do
        id="$(printf '%s' "$line" | grep -oE 'KF-[0-9]+' | head -1)"
        title="$(printf '%s' "$line" | sed -E 's/^## KF-[0-9]+: *//')"
        st="$(awk -F'\t' -v k="$id" '$1==k{print $2; exit}' "$idx")"
        printf 'kf\t%s\t%s\t%s\tgrimoires/loa/known-failures.md\t\n' \
          "$(san "$id")" "$(san "${st:-}")" "$(san "$title")"
      done
  rm -f "$idx"
}
emit_vision(){
  local d="${G}/visions/entries"; [[ -d "$d" ]] || return 0
  local f id status title
  for f in "$d"/vision-*.md; do
    [[ -e "$f" ]] || continue
    id="$(grep -m1 -oE '^\*\*ID\*\*: *vision-[0-9]+' "$f" | grep -oE 'vision-[0-9]+' || true)"
    [[ -z "$id" ]] && id="$(basename "$f" .md)"
    status="$(grep -m1 -E '^\*\*Status\*\*:' "$f" | sed -E 's/^\*\*Status\*\*: *//' || true)"
    title="$(grep -m1 -E '^# Vision:' "$f" | sed -E 's/^# Vision: *//' || true)"
    printf 'vision\t%s\t%s\t%s\t%s\t%s\n' \
      "$(san "$id")" "$(san "$status")" "$(san "$title")" "grimoires/loa/visions/entries/$(san "$(basename "$f")")" "$(refs_of "$f")"
  done
}
emit_lore(){
  local f="${G}/lore/index.yaml"; [[ -f "$f" ]] || return 0
  awk '
    /^[[:space:]]*-[[:space:]]*id:[[:space:]]*/ { id=$0; sub(/^[[:space:]]*-[[:space:]]*id:[[:space:]]*/,"",id); have=1; st="" }
    have && /^[[:space:]]*status:[[:space:]]*/ { st=$0; sub(/^[[:space:]]*status:[[:space:]]*/,"",st); print id "\t" st; have=0 }
  ' "$f" | while IFS=$'\t' read -r id st; do
    printf 'lore\t%s\t%s\t%s\tgrimoires/loa/lore/index.yaml\t\n' "$(san "$id")" "$(san "$st")" "$(san "$id")"
  done
}
emit_handoff(){
  local f="${G}/handoffs/INDEX.md"; [[ -f "$f" ]] || return 0
  grep -E '^\| *sha256:[a-f0-9]+ *\|' "$f" \
    | while IFS='|' read -r _ hid file _from _to topic ts _rest; do
        printf 'handoff\t%s\t%s\t%s\t%s\t\n' \
          "$(san "$hid")" "$(san "$ts")" "$(san "$topic")" "grimoires/loa/handoffs/$(san "$file")"
      done
}
emit_obs(){
  local f="${G}/memory/observations.jsonl"; [[ -f "$f" ]] || return 0
  local n=0 line ts ty cat title sha id
  while IFS= read -r line || [[ -n "$line" ]]; do
    n=$((n+1)); [[ -z "$line" ]] && continue
    echo "$line" | jq -e . >/dev/null 2>&1 || continue
    ts="$(echo "$line"   | jq -r '.timestamp // ""')"
    ty="$(echo "$line"   | jq -r '.type // ""')"
    cat="$(echo "$line"  | jq -r '.category // ""')"
    title="$(echo "$line"| jq -r '.title // ""')"
    sha="$(printf '%s|%s' "$ts" "$title" | sha256_portable | cut -c1-8)"
    id="obs-${sha}"
    printf 'obs\t%s\t%s\t%s\t%s\t%s\n' \
      "$id" "$(san "$ty")" "$(san "$title")" "grimoires/loa/memory/observations.jsonl#L${n}" ""
  done < "$f"
}

collect(){ { emit_kf; emit_vision; emit_lore; emit_handoff; emit_obs; } | LC_ALL=C sort -t$'\t' -k1,1 -k2,2; }

to_json(){
  collect | jq -R -s '
    [ split("\n")[] | select(length>0) | split("\t")
      | {family:.[0], id:.[1], status:.[2], title:.[3], path:.[4], refs:(.[5]//""|if .=="" then [] else split(",") end)} ]
    | { families: (group_by(.family) | map({key:.[0].family, value:.}) | from_entries),
        counts: (group_by(.family) | map({key:.[0].family, value:length}) | from_entries),
        total: length }
  '
}

render_md(){
  local json="$1" fam count
  echo "<!-- generated by grimoire-index.sh — DO NOT EDIT. Regenerate: bash .claude/scripts/grimoire-index.sh -->"
  echo
  echo "# Grimoire Index"
  echo
  echo "Unified cross-family catalog of the grimoire knowledge corpus (KF · vision · lore · handoff · observation). Generated; do not hand-edit. Total entries: $(echo "$json" | jq -r '.total')."
  echo
  for fam in handoff kf lore obs vision; do
    count="$(echo "$json" | jq -r --arg f "$fam" '.counts[$f] // 0')"
    [[ "$count" == "0" ]] && continue
    echo "## ${fam} (${count})"
    echo
    echo "| ID | Status | Title | Path | Refs |"
    echo "|----|--------|-------|------|------|"
    echo "$json" | jq -r --arg f "$fam" 'def esc: gsub("\\|";"\\|"); .families[$f][] | "| \(.id|esc) | \(.status|esc) | \(.title|esc) | \(.path|esc) | \((.refs//[])|join(", ")|esc) |"'
    echo
  done
}

# --- main ---
parse_args "$@"
require_jq
mkdir -p "${PROJECT_ROOT}/.run"
JSON="$(to_json)"

case "$MODE" in
  json) echo "$JSON" ;;
  validate)
    rc=0
    bad="$(echo "$JSON" | jq -r '[.families[][] | select((.id|length)==0 or (.path|length)==0)] | length')"
    [[ "$bad" != "0" ]] && { echo "::error::[GRIMOIRE-INDEX] $bad entries missing id/path" >&2; rc=1; }
    # KF Index-table coverage vs real headings — informational WARNING (hand-maintained
    # table drift is a data issue, not a generator failure; do not bot-rewrite the
    # append-only known-failures.md).
    idx_rows=$(awk '/^## Index/{i=1;next} i&&/^## /{exit} i' "${G}/known-failures.md" 2>/dev/null | grep -cE '^\| *\[KF-[0-9]+\]' || true); idx_rows=${idx_rows:-0}
    heads=$(echo "$JSON" | jq -r '.counts.kf // 0')
    if [[ "$idx_rows" != "$heads" ]]; then
      echo "::warning::[GRIMOIRE-INDEX] known-failures.md ## Index table lists ${idx_rows} KF rows but there are ${heads} ## KF- entries — Index table is stale (informational; repair the table)." >&2
    fi
    [[ $rc -eq 0 ]] && log "grimoire-index: valid ($(echo "$JSON" | jq -r '.total') entries; kf=${heads}, index-table=${idx_rows})"
    exit $rc ;;
  write)
    bad="$(echo "$JSON" | jq -r '[.families[][] | select((.id|length)==0 or (.path|length)==0 or (.family|test("[^a-z]")))] | length')"
    if [[ "$bad" != "0" ]]; then echo "::error::[GRIMOIRE-INDEX] refusing to write — $bad malformed records (id/path/family). Likely a corrupt source filename." >&2; exit 1; fi
    exec 9>"$LOCK"; flock 9 2>/dev/null || true
    tmpj="$(mktemp)"; printf '%s\n' "$JSON" > "$tmpj"; mv "$tmpj" "$OUT_JSON"
    tmpm="$(mktemp)"; render_md "$JSON" > "$tmpm"; mv "$tmpm" "$OUT_MD"
    log "grimoire-index: wrote ${OUT_MD#$PROJECT_ROOT/} + ${OUT_JSON#$PROJECT_ROOT/} ($(echo "$JSON" | jq -r '.total') entries)" ;;
esac
