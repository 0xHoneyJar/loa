#!/usr/bin/env bash
# =============================================================================
# tools/cycle-ratio.sh: the two release-notes lines of a cycle, task-kind
# counts and the volume ratio (grimoires/loa/sdd.md D-10.3, PRD FR-10).
#
#   kinds: mechanical N · judgment N · operator N
#   volume: script lines changed N (*.sh *.py *.ts *.js) · prose bytes changed N (*.md) · model calls N (MODELINV rows between the two commits' timestamps) · scope: host · modelinv: <path>
#
# Mapping (the glossary's "Kind counts" and "Volume ratio" entries):
#   kinds          the 'kind: <value>' token that ends each top-level '- [ ]' /
#                  '- [x]' task line under '### Technical Tasks', and each
#                  '- [ ] Task ...' line under a '### Task N.E2E' heading, inside
#                  a '## Sprint N' block of the sprint plan (fenced code skipped,
#                  the same scope validate-artifact.sh --type sprint enforces);
#                  untagged task lines are counted in --json and WARNed
#   script lines   added + deleted lines of *.sh *.py *.ts *.js files between
#                  the two commits (git diff --numstat, renames detected,
#                  binary files skipped)
#   prose bytes    bytes of the added and removed *.md lines between the two
#                  commits, newline included, diff markers excluded
#   model calls    MODELINV rows (primitive_id MODELINV) in the MODELINV log
#                  whose ts_utc lies between the two commits' committer
#                  timestamps, both ends included. The log is host-local, so
#                  the count covers only the calls made on this host: "scope:
#                  host". A missing log prints "model calls n/a" and a WARN.
#
# Git runs in the current directory's repository; --sprint-plan and --modelinv
# default to paths under its top level.
#
# Usage:
#   tools/cycle-ratio.sh --from SHA --to SHA [--sprint-plan PATH]
#                        [--modelinv PATH] [--json]
#
#   --sprint-plan PATH  default grimoires/loa/sprint.md
#   --modelinv PATH     default .run/model-invoke.jsonl
#   --json              one JSON object instead of the two lines
#
# Exit 2 also covers: not a git repository, an unreadable sprint plan, jq missing.
# Exit codes: 0 printed · 2 usage or unreadable input · 3 a SHA names no commit
# =============================================================================
set -euo pipefail
export LC_ALL=C

usage() { sed -n '/^# Usage:/,/^# Exit codes/p' "$0" | sed 's/^# \{0,1\}//'; }
die() { echo "cycle-ratio.sh: $2" >&2; exit "$1"; }

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FENCE_AWK="$SCRIPT_ROOT/.claude/scripts/lib/md-fence.awk"

FROM=""
TO=""
PLAN=""
MODELINV=""
JSON=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --from|--to|--sprint-plan|--modelinv)
      [[ $# -ge 2 && -n "$2" ]] || { echo "cycle-ratio.sh: $1 needs a value" >&2; usage >&2; exit 2; }
      case "$1" in
        --from) FROM="$2" ;;
        --to) TO="$2" ;;
        --sprint-plan) PLAN="$2" ;;
        --modelinv) MODELINV="$2" ;;
      esac
      shift 2 ;;
    --json) JSON=1; shift ;;
    --help|-h) usage; exit 0 ;;
    *) echo "cycle-ratio.sh: unknown argument $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ -n "$FROM" && -n "$TO" ]] || { echo "cycle-ratio.sh: --from and --to are required" >&2; usage >&2; exit 2; }
command -v jq >/dev/null 2>&1 || die 2 "jq is required"
TOP="$(git rev-parse --show-toplevel 2>/dev/null)" || die 2 "not inside a git repository"
[[ -n "$PLAN" ]] || PLAN="$TOP/grimoires/loa/sprint.md"
[[ -n "$MODELINV" ]] || MODELINV="$TOP/.run/model-invoke.jsonl"
[[ -r "$PLAN" && -f "$PLAN" ]] || die 2 "sprint plan not readable: $PLAN"
[[ -r "$FENCE_AWK" ]] || die 2 "cannot read $FENCE_AWK (reinstall the framework scripts)"

# A leading '-' would reach git as an option; a SHA never starts with one.
case "$FROM" in -*) die 3 "unknown commit: $FROM" ;; esac
case "$TO" in -*) die 3 "unknown commit: $TO" ;; esac
FROM_SHA="$(git rev-parse --verify --quiet "${FROM}^{commit}")" || die 3 "unknown commit: $FROM"
TO_SHA="$(git rev-parse --verify --quiet "${TO}^{commit}")" || die 3 "unknown commit: $TO"

# --- kinds -------------------------------------------------------------------
kinds="$(awk "$(cat "$FENCE_AWK")"'
  md_fence($0) { next }
  /^## / { insp = ($0 ~ /^## Sprint [0-9]/); sec = 0; next }
  !insp { next }
  /^### / {
    sec = 0
    if ($0 ~ /^### Technical Tasks[[:space:]]*$/) sec = 1
    else if ($0 ~ /^### Task [0-9A-Za-z]+\.E2E([^A-Za-z0-9]|$)/) sec = 2
    next
  }
  !sec || $0 !~ /^- \[[ xX]\] / { next }
  sec == 2 && $0 !~ /^- \[[ xX]\] Task / { next }
  {
    if (match($0, /(^|[^A-Za-z0-9_])kind[[:space:]]*:[[:space:]]*(mechanical|judgment|operator)[[:space:]]*$/)) {
      v = substr($0, RSTART, RLENGTH)
      sub(/^.*:[[:space:]]*/, "", v); sub(/[[:space:]]+$/, "", v)
      n[v]++
    } else n["untagged"]++
  }
  END { printf "%d %d %d %d\n", n["mechanical"], n["judgment"], n["operator"], n["untagged"] }
' "$PLAN")"
read -r K_MECH K_JUDG K_OPER K_UNTAGGED <<< "$kinds"
[[ "$K_UNTAGGED" -eq 0 ]] || echo "WARN: $K_UNTAGGED task line(s) in $PLAN carry no kind: tag and are not counted" >&2

# --- volume ------------------------------------------------------------------
GIT_DIFF=(git -c core.quotePath=false diff --no-color --no-ext-diff --no-textconv -M)
SCRIPT_LINES="$("${GIT_DIFF[@]}" --numstat "$FROM_SHA" "$TO_SHA" -- '*.sh' '*.py' '*.ts' '*.js' \
  | awk -F'\t' '$1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ { s += $1 + $2 } END { printf "%d\n", s }')"
PROSE_BYTES="$("${GIT_DIFF[@]}" --unified=0 "$FROM_SHA" "$TO_SHA" -- '*.md' \
  | awk '
      /^diff --git / { hunk = 0; next }
      /^@@ / { hunk = 1; next }
      # the marker byte stands in for the newline the diff line drops
      hunk && /^[+-]/ { s += length($0) }
      END { printf "%d\n", s }
    ')"

# --- model calls -------------------------------------------------------------
FROM_TS="$(git show -s --format=%ct "$FROM_SHA")"
TO_TS="$(git show -s --format=%ct "$TO_SHA")"
MODEL_CALLS=""
if [[ -f "$MODELINV" && -r "$MODELINV" ]]; then
  MODEL_CALLS="$(jq -R --argjson lo "$FROM_TS" --argjson hi "$TO_TS" '
      fromjson? | select(type == "object" and .primitive_id == "MODELINV")
      | (.ts_utc // "") | tostring
      | (try (sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | fromdateiso8601) catch null)
      | select(. != null and . >= $lo and . <= $hi)
    ' "$MODELINV" | wc -l | tr -d ' ')"
else
  echo "WARN: MODELINV log not found at $MODELINV; model calls n/a" >&2
fi

iso() { jq -nr --argjson t "$1" '$t | todateiso8601'; }

if [[ "$JSON" -eq 1 ]]; then
  jq -n \
    --arg from "$FROM_SHA" --arg to "$TO_SHA" \
    --arg from_ts "$(iso "$FROM_TS")" --arg to_ts "$(iso "$TO_TS")" \
    --arg plan "$PLAN" --arg modelinv "$MODELINV" \
    --argjson mech "$K_MECH" --argjson judg "$K_JUDG" --argjson oper "$K_OPER" --argjson untagged "$K_UNTAGGED" \
    --argjson script_lines "$SCRIPT_LINES" --argjson prose_bytes "$PROSE_BYTES" \
    --arg calls "$MODEL_CALLS" \
    '{from: $from, to: $to, window: {from: $from_ts, to: $to_ts}, sprint_plan: $plan,
      kinds: {mechanical: $mech, judgment: $judg, operator: $oper, untagged: $untagged},
      volume: {script_lines_changed: $script_lines, prose_bytes_changed: $prose_bytes,
               model_calls: (if $calls == "" then null else ($calls | tonumber) end),
               scope: "host", modelinv: $modelinv}}'
else
  printf 'kinds: mechanical %s · judgment %s · operator %s\n' "$K_MECH" "$K_JUDG" "$K_OPER"
  printf "volume: script lines changed %s (*.sh *.py *.ts *.js) · prose bytes changed %s (*.md) · model calls %s (MODELINV rows between the two commits' timestamps) · scope: host · modelinv: %s\n" \
    "$SCRIPT_LINES" "$PROSE_BYTES" "${MODEL_CALLS:-n/a}" "$MODELINV"
fi
