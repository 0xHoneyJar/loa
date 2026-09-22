#!/usr/bin/env bash
# =============================================================================
# verdict-consistency.sh — LOA-VERDICT trailer present and consistent
#
# cycle-124 Sprint 3 (PRD FR-9). Args: $1=workspace, $2=review file
# (default review.md), $3=gate review|audit (default review). Delegates to
# .claude/scripts/verdict-derive.sh --require-trailer, the same mechanical
# filter the golden path uses, so an eval review is held to the production
# contract (prose/trailer agreement, one-way severity rule).
#
# Output: {"pass","score","details":{verdict,consistent,counts,excluded,violations[]}}
# Exit: 0 pass, 1 fail, 2 error
# =============================================================================
set -euo pipefail

workspace="${1:-}"
review_name="${2:-review.md}"
gate="${3:-review}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DERIVE="${VERDICT_DERIVE:-$REPO_ROOT/.claude/scripts/verdict-derive.sh}"

err() { printf '{"pass":false,"score":0,"details":{"error":%s},"grader_version":"1.0.0"}\n' "$(jq -Rn --arg m "$1" '$m')"; exit 2; }
[[ -n "$workspace" && -d "$workspace" ]] || err "invalid workspace"
[[ "$gate" == "review" || "$gate" == "audit" ]] || err "gate must be review|audit"
case "$review_name" in */*|..*) err "review file must be a bare name" ;; esac
[[ -f "$DERIVE" ]] || err "verdict-derive.sh not found: $DERIVE"

file="$workspace/$review_name"
if [[ ! -f "$file" ]]; then
  printf '{"pass":false,"score":0,"details":{"error":"review file not found: %s"},"grader_version":"1.0.0"}\n' "$review_name"
  exit 1
fi

rc=0
out="$(bash "$DERIVE" --file "$file" --gate "$gate" --require-trailer --json 2>/dev/null)" || rc=$?
# verdict-derive pretty-prints its JSON (violations go to stderr); take the
# object from the first '{' line to the end and compact it.
json="$(printf '%s\n' "$out" | sed -n '/^{/,$p' | jq -c . 2>/dev/null || true)"
[[ -n "$json" ]] || json='{"verdict":null,"consistent":false,"violations":["verdict-derive produced no JSON"]}'

consistent="$(jq -r '.consistent // false' <<<"$json")"
pass=false
[[ $rc -eq 0 && "$consistent" == "true" ]] && pass=true
score=0; [[ "$pass" == "true" ]] && score=100

jq -n --argjson pass "$pass" --argjson score "$score" --argjson d "$json" \
  '{pass:$pass, score:$score,
    details:{verdict:$d.verdict, consistent:$d.consistent, counts:$d.counts, excluded:($d.excluded // 0), violations:($d.violations // [])},
    grader_version:"1.0.0"}'
[[ "$pass" == "true" ]] && exit 0 || exit 1
