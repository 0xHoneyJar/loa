#!/usr/bin/env bash
# =============================================================================
# tools/check-round-independence.sh: is an interview transcript asked in
# prerequisite-ordered rounds?
#
# In `interview.pacing: rounds` every round of questions ends with one comment
# block (discovering-requirements/resources/REFERENCE.md §Question Pacing):
#
#   <!-- round: 2; questions: [{"id":"Q4","depends_on":[]},{"id":"Q2","depends_on":[],"reasked":true}] -->
#
# This checker reads those blocks from a transcript (markdown or plain text,
# one block per line) and fails when:
#   * a `depends_on` names a question asked in the same round,
#   * a `depends_on` names a question not asked in an earlier round,
#   * a non-reasked id repeats, or a `reasked` id was never asked before,
#   * round numbers do not increase, or a block is malformed,
#   * the rounds average fewer than --min-average new questions (default 2).
# `reasked` entries are skipped for id uniqueness and for the average. The
# final round is exempt from the average when there are two or more rounds.
#
# Usage:
#   tools/check-round-independence.sh <transcript> [--min-average N] [--json]
#
# Exit codes: 0 independent · 1 violation · 2 usage, unreadable file, or no
#             round block in the transcript
# =============================================================================
set -euo pipefail
export LC_ALL=C

usage() { sed -n '/^# Usage:/,/^# Exit codes/p' "$0" | sed 's/^# \{0,1\}//'; }

TRANSCRIPT=""
MIN_AVG="2"
JSON=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --min-average)
      [[ $# -ge 2 ]] || { echo "check-round-independence.sh: --min-average needs a number" >&2; exit 2; }
      MIN_AVG="$2"; shift 2 ;;
    --json) JSON=1; shift ;;
    --help|-h) usage; exit 0 ;;
    --) shift; [[ $# -ge 1 ]] && { TRANSCRIPT="$1"; shift; } ;;
    -*) echo "check-round-independence.sh: unknown flag $1" >&2; exit 2 ;;
    *)
      [[ -z "$TRANSCRIPT" ]] || { echo "check-round-independence.sh: one transcript only" >&2; exit 2; }
      TRANSCRIPT="$1"; shift ;;
  esac
done

[[ -n "$TRANSCRIPT" ]] || { echo "check-round-independence.sh: transcript path required" >&2; usage >&2; exit 2; }
[[ -f "$TRANSCRIPT" && -r "$TRANSCRIPT" ]] || { echo "check-round-independence.sh: cannot read $TRANSCRIPT" >&2; exit 2; }
[[ "$MIN_AVG" =~ ^[0-9]+([.][0-9]+)?$ ]] || { echo "check-round-independence.sh: --min-average must be a non-negative number, got '$MIN_AVG'" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "check-round-independence.sh: jq is required" >&2; exit 2; }

BLOCK_RE='<!--[[:space:]]*round:[[:space:]]*[0-9]+[[:space:]]*;[[:space:]]*questions:[[:space:]]*\[.*\][[:space:]]*-->'

# One JSON object per block: {round, questions} or {round, malformed}. grep exits
# 1 on no match, which is the "no block" case below, not an error.
blocks="$(grep -oE "$BLOCK_RE" "$TRANSCRIPT" || true)"
if [[ -z "$blocks" ]]; then
  echo "check-round-independence.sh: no <!-- round: N; questions: [...] --> block in $TRANSCRIPT" >&2
  exit 2
fi

# Transcript content never travels as a jq argv string (Linux caps one argument
# at 128 KiB): each block and the accumulated rounds go through temp files.
WORK="$(mktemp -d "${TMPDIR:-/tmp}/check-round-independence.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
MAX_BLOCK_BYTES=65536
ID_RE='^[A-Za-z0-9_.-]{1,64}$'
: > "$WORK/rounds.jsonl"

while IFS= read -r block; do
  [[ -n "$block" ]] || continue
  n="$(printf '%s\n' "$block" | sed -E 's/^<!--[[:space:]]*round:[[:space:]]*([0-9]+).*/\1/')"
  [[ ${#n} -le 9 ]] || { echo "check-round-independence.sh: round number $n is too long" >&2; exit 1; }
  n=$((10#$n))   # "02" is not valid JSON; the round number is decimal
  printf '%s\n' "$block" | sed -E 's/^<!--[[:space:]]*round:[[:space:]]*[0-9]+[[:space:]]*;[[:space:]]*questions:[[:space:]]*//; s/[[:space:]]*-->$//' > "$WORK/arr.json"
  bytes="$(wc -c < "$WORK/arr.json" | tr -d '[:space:]')"
  if [[ "$bytes" -gt "$MAX_BLOCK_BYTES" ]]; then
    jq -cn --argjson r "$n" --arg why "block is $bytes bytes, over the $MAX_BLOCK_BYTES-byte limit" \
      '{round: $r, malformed: $why}' >> "$WORK/rounds.jsonl"
  # -s slurps the capture: exactly one JSON value, a well-formed array whose
  # ids and depends_on names match ID_RE. Without -s, `[] [{...}]` (two values)
  # would pass on the last one. Ids are untrusted model output, so the pattern
  # also keeps escapes and control characters out of every printed line.
  elif jq -se --arg re "$ID_RE" 'length == 1 and (.[0] | type == "array" and all(.[];
        type == "object" and (.id | type == "string" and test($re))
        and (.depends_on | type == "array" and all(.[]; type == "string" and test($re)))))' \
        "$WORK/arr.json" >/dev/null 2>&1; then
    jq -c --argjson r "$n" '{round: $r, questions: .}' "$WORK/arr.json" >> "$WORK/rounds.jsonl"
  else
    jq -cn --argjson r "$n" \
      '{round: $r, malformed: "each entry needs an id and depends_on names matching [A-Za-z0-9_.-]{1,64}"}' \
      >> "$WORK/rounds.jsonl"
  fi
done <<< "$blocks"
jq -s '.' "$WORK/rounds.jsonl" > "$WORK/rounds.json"

report="$(jq -n --slurpfile rs "$WORK/rounds.json" --argjson min "$MIN_AVG" '
  $rs[0] as $rounds
  | reduce range(0; $rounds | length) as $i (
    {asked: [], violations: [], per_round: [], prev: null};
    $rounds[$i] as $r
    | (if .prev != null and $r.round <= .prev
         then .violations += ["round \($r.round) does not follow round \(.prev)"] else . end)
    | .prev = $r.round
    | if $r.malformed != null then
        .violations += ["round \($r.round): malformed questions array (\($r.malformed))"]
        | .per_round += [{round: $r.round, new: 0, reasked: 0, ids: []}]
      else
        ($r.questions | map(.id)) as $here
        | .asked as $before
        | reduce $r.questions[] as $q (.;
            ($q.reasked == true) as $re
            | (if $re then
                 (if ($before | index([$q.id])) == null
                    then .violations += ["round \($r.round): \($q.id) is marked reasked but was not asked in an earlier round"] else . end)
               else
                 (if (.asked | index([$q.id])) != null
                    then .violations += ["round \($r.round): \($q.id) is asked again without \"reasked\": true"] else . end)
                 | .asked += [$q.id]
               end)
            | reduce $q.depends_on[] as $d (.;
                if ($here | index([$d])) != null and $d != $q.id then
                  .violations += ["round \($r.round): \($q.id) depends on \($d), asked in the same round"]
                elif $d == $q.id then
                  .violations += ["round \($r.round): \($q.id) depends on itself"]
                elif ($before | index([$d])) == null then
                  .violations += ["round \($r.round): \($q.id) depends on \($d), not asked in an earlier round"]
                else . end))
        | .per_round += [{
            round: $r.round,
            new: ($r.questions | map(select(.reasked != true)) | length),
            reasked: ($r.questions | map(select(.reasked == true)) | length),
            ids: $here }]
      end)
  | .counted = (if (.per_round | length) >= 2 then .per_round[0:-1] else .per_round end)
  | .average = (if (.counted | length) == 0 then 0
                else ((.counted | map(.new) | add) / (.counted | length)) end)
  | (if .average < $min
       then .violations += ["average \(.average * 100 | round / 100) new questions per round is below --min-average \($min)"] else . end)
  | {
      rounds: (.per_round | length),
      questions: (.per_round | map(.new) | add),
      reasked: (.per_round | map(.reasked) | add),
      average: (.average * 100 | round / 100),
      min_average: $min,
      final_round_exempt: ((.per_round | length) >= 2),
      per_round: .per_round,
      violations: .violations,
      verdict: (if (.violations | length) == 0 then "PASS" else "FAIL" end)
    }')"

if [[ "$JSON" -eq 1 ]]; then
  printf '%s\n' "$report"
else
  # Strip control characters from every printed line: ids are validated above,
  # this keeps any future field from putting a raw ESC on the terminal.
  printf '%s\n' "$report" | jq -r '
    def clean: gsub("[[:cntrl:]]"; "?");
    ((.per_round[] | "round \(.round): \(.new) new question(s)\(if .reasked > 0 then ", \(.reasked) re-asked" else "" end) [\(.ids | join(" "))]"),
    "rounds: \(.rounds); questions: \(.questions); average: \(.average) per round\(if .final_round_exempt then " (final round exempt)" else "" end); min-average: \(.min_average)",
    (.violations[] | "VIOLATION: \(.)"),
    .verdict) | clean'
fi

verdict="$(printf '%s\n' "$report" | jq -r '.verdict')"
[[ "$verdict" == "PASS" ]]
