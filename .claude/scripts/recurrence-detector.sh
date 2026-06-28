#!/usr/bin/env bash
# =============================================================================
# recurrence-detector.sh — cross-session recurrence detector (READ-ONLY, PROPOSE-ONLY)
#
# OKF/ICM adoption cycle, Sprint 8 (rec #9; closes ICM §6.3). Scans the
# trajectory / a2a JSONL corpus for a normalized finding that recurs across ≥N
# DISTINCT sessions and SURFACES a proposed source edit (a draft KF Attempts-row
# / new-KF stub) for HUMAN review. It NEVER writes .claude/ and NEVER appends
# known-failures.md — the append-only/anti-tamper log is mutated only by a human
# via /implement (+ kf-write-lib.sh). The "recurrence count ≥ 3 = structural"
# rule (CLAUDE.md / known-failures.md) is the load-bearing threshold this detects.
#
# Output (State zone, gitignored): .run/recurrence-proposals.json + .md.
#
# SAFETY / OVER-CLASSIFICATION GUARDRAILS:
#   - session = source file (dated trajectory files ≈ per-session); a finding must
#     appear in ≥ --min-sessions DISTINCT files (intra-session repeats don't count)
#   - normalization strips session-specific tokens (SHAs, #issue, bd-/KF-/sprint-ids,
#     dates, numbers, paths) so only the durable phrase remains
#   - a fingerprint needs ≥ MIN_WORDS significant words (stopworded) — generic
#     one-liners are dropped, not proposed
#   - proposals are capped (--max) and any truncation is logged, never silent
#   - findings already covered by a KF entry are flagged (likely-existing), not
#     re-proposed as new
#
# Flags: --json (proposals to stdout) --output DIR (default .run) --min-sessions N
#        (default 3) --max N (default 50) --sources "p1,p2,..." --quiet
# =============================================================================
export LC_ALL=C
export TZ=UTC
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
G="${PROJECT_ROOT}/grimoires/loa"
OUT_DIR="${PROJECT_ROOT}/.run"
KF_FILE="${G}/known-failures.md"
MIN_SESSIONS=3
MAX_PROPOSALS=50
MIN_WORDS=4
FP_WORDS=6
MODE="write"; QUIET=0
SOURCES_CSV=""

source "${SCRIPT_DIR}/compat-lib.sh"
require_jq(){ command -v jq >/dev/null 2>&1 || { echo "recurrence-detector: jq required" >&2; exit 3; }; }
log(){ [[ $QUIET -eq 0 ]] && echo "$@" >&2 || true; }

parse_args(){
  while [[ $# -gt 0 ]]; do case "$1" in
    --json) MODE="json" ;;
    --output) [[ -n "${2:-}" ]] || { echo "recurrence-detector: --output requires a value" >&2; exit 2; }; OUT_DIR="$2"; shift ;;
    --min-sessions) [[ "${2:-}" =~ ^[0-9]+$ ]] || { echo "recurrence-detector: --min-sessions requires a non-negative integer" >&2; exit 2; }; MIN_SESSIONS="$2"; shift ;;
    --max) [[ "${2:-}" =~ ^[0-9]+$ ]] || { echo "recurrence-detector: --max requires a non-negative integer" >&2; exit 2; }; MAX_PROPOSALS="$2"; shift ;;
    --sources) [[ -n "${2:-}" ]] || { echo "recurrence-detector: --sources requires a value" >&2; exit 2; }; SOURCES_CSV="$2"; shift ;;
    --quiet) QUIET=1 ;;
    -h|--help) sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "recurrence-detector: unknown arg: $1" >&2; exit 2 ;;
  esac; shift; done
}

# Resolve the JSONL sources to scan (default: trajectory corpus + observations).
resolve_sources(){
  if [[ -n "$SOURCES_CSV" ]]; then
    printf '%s\n' "${SOURCES_CSV//,/$'\n'}"
    return
  fi
  find "${G}/a2a/trajectory" -name '*.jsonl' -type f 2>/dev/null || true
  [[ -f "${G}/memory/observations.jsonl" ]] && printf '%s\n' "${G}/memory/observations.jsonl"
}

# Emit "session<TAB>finding-text" for every record carrying a textual finding.
extract_signals(){
  local p base
  while IFS= read -r p; do
    [[ -f "$p" ]] || continue
    base="$(basename "$p")"
    # first non-null string among the known finding-bearing fields
    # Tolerant per-line parse (-R + fromjson?): one corrupt / non-JSON line in an
    # UNTRUSTED, possibly crash-truncated source must NEVER abort the run. Collapse
    # embedded newlines/tabs so a multi-line finding stays ONE fingerprintable signal
    # (else shared boilerplate footers would falsely cluster).
    jq -R -r 'fromjson? | [ .reason?, .data?.reason?, .data?.message?, .title?, .finding?, .symptom?, .message?, .detail? ]
      | map(select(type=="string" and (.|length)>0)) | .[0] // empty | gsub("[\n\r\t]+";" ")' "$p" 2>/dev/null \
      | while IFS= read -r line; do
          [[ -n "$line" ]] && printf '%s\t%s\n' "$base" "$line"
        done
  done < <(resolve_sources)
}

# awk: normalize text, fingerprint to first FP_WORDS significant words, and group
# by fingerprint counting DISTINCT sessions. Emits: sessions<TAB>fingerprint<TAB>example
group_recurrences(){
  awk -F'\t' -v minw="$MIN_WORDS" -v fpw="$FP_WORDS" -v mins="$MIN_SESSIONS" '
    BEGIN{
      split("the a an of to in on for and or but with from this that these those is are was were be been being it its as at by we our you your they their he she his her i me my not no yes do does did has have had will would can could should may might must a b c d e f", SW, " ")
      for (k in SW) stop[SW[k]]=1
    }
    {
      # Normalize WITHOUT {n,m} interval regexes — mawk mishandles them (KF-012-class
      # portability trap). Only +/*/? quantifiers, which every awk supports.
      sess=$1; raw=$2
      t=tolower(raw)
      gsub(/#[0-9]+/," ",t)                   # issue refs
      gsub(/bd-[a-z0-9]+/," ",t)              # bead ids
      gsub(/kf-[0-9]+/," ",t)                 # KF ids (match the pattern, not the id)
      gsub(/sprint-(bug-)?[0-9]+/," ",t)      # sprint ids
      gsub(/[0-9]+/," ",t)                    # all remaining digit runs (SHAs/dates lose their digits)
      gsub(/[^a-z ]+/," ",t)                  # drop punctuation / path residue
      n=split(t, w, /[ ]+/)
      fp=""; cnt=0
      for (i=1;i<=n && cnt<fpw;i++){
        wd=w[i]
        if (wd=="" || length(wd)<3 || (wd in stop)) continue
        fp = (fp=="" ? wd : fp" "wd); cnt++
      }
      if (cnt < minw) next                    # too generic → drop (guardrail)
      key=fp
      total[key]++
      if (!seen[key SUBSEP sess]++) { sesscnt[key]++; sesslist[key]=sesslist[key] (sesslist[key]==""?"":",") sess }
      if (!(key in example)) example[key]=raw
    }
    END{
      for (key in sesscnt) if (sesscnt[key] >= mins)
        printf "%d\t%d\t%s\t%s\t%s\n", sesscnt[key], total[key], key, example[key], sesslist[key]
    }
  '
}

# Flag a fingerprint that likely overlaps an existing KF (≥2 shared significant words
# with a KF heading title) so we propose UPDATING, not duplicating.
kf_overlap(){ # fingerprint
  local fp="$1" w hit=""
  [[ -f "$KF_FILE" ]] || { printf ''; return; }
  # build a lowercase KF-title corpus once per call (small file section)
  local titles; titles="$(grep -E '^## KF-[0-9]+:' "$KF_FILE" 2>/dev/null | tr '[:upper:]' '[:lower:]')"
  local shared=0
  for w in $fp; do printf '%s\n' "$titles" | grep -qwF "$w" && shared=$((shared+1)); done
  [[ "$shared" -ge 2 ]] && printf 'likely-existing' || printf 'new'
}

build_json(){
  local rows="$1" emitted=0 truncated=0 json='[]'
  # rows sorted by sessions desc, then fingerprint
  while IFS=$'\t' read -r sess total fp example sesslist; do
    [[ -z "$fp" ]] && continue
    if [[ "$emitted" -ge "$MAX_PROPOSALS" ]]; then truncated=$((truncated+1)); continue; fi
    local pid kind
    pid="rp-$(printf '%s' "$fp" | sha256_portable | cut -c1-8)"
    kind="$(kf_overlap "$fp")"
    json="$(jq -c \
      --arg id "$pid" --arg fp "$fp" --arg ex "$example" --arg kind "$kind" \
      --argjson sessions "$sess" --argjson total "$total" --arg list "$sesslist" \
      '. + [{
        id:$id, fingerprint:$fp, distinct_sessions:$sessions, total_occurrences:$total,
        classification:$kind, example:$ex, sessions:($list|split(",")),
        proposed_action: (if $kind=="likely-existing"
          then "Review the matching KF entry; if this is the same failure class, increment its Recurrence count and add an Attempts row (human, via kf-write-lib.sh) - do NOT auto-edit."
          else "Consider a NEW KF entry for this recurring finding (human authors via /implement + kf-write-lib.sh; Evidence cell required)." end)
      }]' <<<"$json")"
    emitted=$((emitted+1))
  done <<< "$rows"
  jq -n --argjson props "$json" --argjson trunc "$truncated" --argjson mins "$MIN_SESSIONS" \
    '{min_sessions:$mins, proposal_count:($props|length), truncated:$trunc, proposals:$props}'
}

render_md(){ # json
  local json="$1" mins count trunc
  mins="$(echo "$json" | jq -r '.min_sessions')"
  count="$(echo "$json" | jq -r '.proposal_count')"
  trunc="$(echo "$json" | jq -r '.truncated')"
  echo "<!-- generated by recurrence-detector.sh — PROPOSALS ONLY. Nothing here is authoritative."
  echo "     A human reviews each and applies via /implement + kf-write-lib.sh (Evidence required). -->"
  echo
  echo "# Cross-Session Recurrence Proposals"
  echo
  echo "Findings recurring across >= ${mins} distinct sessions. Count: ${count} (truncated: ${trunc})."
  echo
  echo "$json" | jq -r '.proposals[] | "## \(.id) — \(.classification) (\(.distinct_sessions) sessions, \(.total_occurrences) hits)\n\n- **Pattern:** \(.fingerprint)\n- **Example:** \(.example)\n- **Proposed:** \(.proposed_action)\n"'
}

# --- main ---
parse_args "$@"
require_jq
mkdir -p "$OUT_DIR"
SIGNALS="$(mktemp)"; extract_signals > "$SIGNALS"
ROWS="$(group_recurrences < "$SIGNALS" | LC_ALL=C sort -t$'\t' -k1,1nr -k3,3)"
rm -f "$SIGNALS"
JSON="$(build_json "$ROWS")"

case "$MODE" in
  json) echo "$JSON" ;;
  write)
    tmpj="$(mktemp)"; printf '%s\n' "$JSON" > "$tmpj"; mv "$tmpj" "${OUT_DIR}/recurrence-proposals.json"
    tmpm="$(mktemp)"; render_md "$JSON" > "$tmpm"; mv "$tmpm" "${OUT_DIR}/recurrence-proposals.md"
    log "recurrence-detector: $(echo "$JSON" | jq -r '.proposal_count') proposal(s) (≥${MIN_SESSIONS} sessions) → ${OUT_DIR#$PROJECT_ROOT/}/recurrence-proposals.{json,md}; wrote nothing authoritative" ;;
esac
