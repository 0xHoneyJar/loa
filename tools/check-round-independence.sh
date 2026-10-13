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

rounds_json="[]"
while IFS= read -r block; do
  [[ -n "$block" ]] || continue
  n="$(printf '%s\n' "$block" | sed -E 's/^<!--[[:space:]]*round:[[:space:]]*([0-9]+).*/\1/')"
  [[ ${#n} -le 9 ]] || { echo "check-round-independence.sh: round number $n is too long" >&2; exit 1; }
  n=$((10#$n))   # "02" is not valid JSON; the round number is decimal
  arr="$(printf '%s\n' "$block" | sed -E 's/^<!--[[:space:]]*round:[[:space:]]*[0-9]+[[:space:]]*;[[:space:]]*questions:[[:space:]]*//; s/[[:space:]]*-->$//')"
  # -s slurps the capture: exactly one JSON value, and it is a well-formed
  # array. Without -s, `[] [{...}]` (two values) would pass on the last one
  # and break --argjson below.
  if printf '%s' "$arr" | jq -se 'length == 1 and (.[0] | type == "array" and all(.[];
        type == "object" and (.id | type == "string" and length > 0)
        and (.depends_on | type == "array" and all(.[]; type == "string"))))' >/dev/null 2>&1; then
    entry="$(jq -cn --argjson r "$n" --argjson q "$arr" '{round: $r, questions: $q}')"
  else
    entry="$(jq -cn --argjson r "$n" --arg raw "$arr" '{round: $r, malformed: $raw}')"
  fi
  rounds_json="$(jq -cn --argjson a "$rounds_json" --argjson e "$entry" '$a + [$e]')"
done <<< "$blocks"

report="$(jq -n --argjson rounds "$rounds_json" --argjson min "$MIN_AVG" '
  reduce range(0; $rounds | length) as $i (
    {asked: [], violations: [], per_round: [], prev: null};
    $rounds[$i] as $r
    | (if .prev != null and $r.round <= .prev
         then .violations += ["round \($r.round) does not follow round \(.prev)"] else . end)
    | .prev = $r.round
    | if $r.malformed != null then
        .violations += ["round \($r.round): malformed questions array (each entry needs a string id and a depends_on array of strings)"]
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
  printf '%s\n' "$report" | jq -r '
    (.per_round[] | "round \(.round): \(.new) new question(s)\(if .reasked > 0 then ", \(.reasked) re-asked" else "" end) [\(.ids | join(" "))]"),
    "rounds: \(.rounds); questions: \(.questions); average: \(.average) per round\(if .final_round_exempt then " (final round exempt)" else "" end); min-average: \(.min_average)",
    (.violations[] | "VIOLATION: \(.)"),
    .verdict'
fi

verdict="$(printf '%s\n' "$report" | jq -r '.verdict')"
[[ "$verdict" == "PASS" ]]
