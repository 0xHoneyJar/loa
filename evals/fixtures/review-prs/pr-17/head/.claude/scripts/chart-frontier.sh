#!/usr/bin/env bash
# =============================================================================
# chart-frontier.sh: the frontier of a decision map (charting-decisions skill, SDD D-4.4).
#
# The frontier is every open, unblocked, unclaimed `question` child of the map epic: the tickets
# a /chart session may take next. Membership comes from
#   br ready --parent <epic> --type question --unassigned --limit 0 --json
# filtered again here (status open, type question, no assignee, exactly one `decision:` label when
# the output carries labels), so a `br` that ignores a filter cannot widen the set. Order: when `bv` is on PATH, the dependency-graph
# order that `get-ready-work.sh --graph` uses (`bv --robot-triage` ranks, unranked beads after,
# by priority); otherwise `br ready` order. get-ready-work.sh itself is not called because the
# build path's work selection drops `question` beads by design.
#
# Usage: chart-frontier.sh <epic-id|map-slug> [--json] [--root DIR]
#   A map slug is resolved through grimoires/loa/maps/<slug>.md (`**Epic**:` line).
# Output: one "<id><TAB><title>" line per ticket (titles control-stripped); --json prints the
#   filtered br objects as an array. An empty frontier prints nothing (exit 0).
# Exit: 0 ok; 1 unknown map or unreadable br output; 2 usage or `br` missing.
# =============================================================================
export LC_ALL=C
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd -P)"
TARGET=""
JSON=0
usage(){ echo "chart-frontier: $*" >&2; echo "usage: chart-frontier.sh <epic-id|map-slug> [--json] [--root DIR]" >&2; exit 2; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) JSON=1; shift ;;
    --root) [[ -n "${2:-}" && -d "${2:-}" ]] || usage "--root needs a directory"; ROOT="$(cd "$2" && pwd -P)"; shift 2 ;;
    -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) usage "unknown flag '$1'" ;;
    *) [[ -z "$TARGET" ]] || usage "one target only"; TARGET="$1"; shift ;;
  esac
done
[[ -n "$TARGET" ]] || usage "a map slug or epic id is required"
[[ "$TARGET" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$ ]] || usage "target must match ^[A-Za-z0-9][A-Za-z0-9._-]*$"
command -v br >/dev/null 2>&1 || { echo "chart-frontier: br (beads_rust) is not on PATH; a map's frontier lives on beads" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "chart-frontier: jq is required" >&2; exit 2; }

EPIC="$TARGET"
MAP="${ROOT}/grimoires/loa/maps/${TARGET}.md"
if [[ -f "$MAP" ]]; then
  EPIC="$(grep -m1 -E '^\*\*Epic\*\*:' "$MAP" | sed -E 's/^\*\*Epic\*\*:[[:space:]]*//; s/[[:space:]]+$//' || true)"
  [[ "$EPIC" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$ ]] || { echo "chart-frontier: ${MAP#"${ROOT}/"} has no usable **Epic**: line" >&2; exit 1; }
fi

READY="$(br ready --parent "$EPIC" --type question --unassigned --limit 0 --json 2>/dev/null)" \
  || { echo "chart-frontier: br ready failed for ${EPIC} (unknown epic?)" >&2; exit 1; }
[[ -n "$READY" ]] || READY="[]"
FILTER='
  (if type == "array" then . elif type == "object" and has("issues") then .issues else error("not a list") end)
  | map(select(((.issue_type // .type // "") == "question")
               and ((.status // "open") == "open")
               and (((.assignee // "") | tostring) == "")
               and ((has("labels") | not)
                    or ([(.labels // [])[] | tostring | select(startswith("decision:"))] | length) == 1)))'
FR="$(printf '%s' "$READY" | jq -c "$FILTER" 2>/dev/null)" || { echo "chart-frontier: unreadable br ready output" >&2; exit 1; }

if [[ "$FR" != "[]" ]] && command -v bv >/dev/null 2>&1; then
  RANKS="$(cd "$ROOT" && CI=1 BV_ROBOT_HISTORY_TIMEOUT_MS="${BV_ROBOT_HISTORY_TIMEOUT_MS:-3000}" bv --robot-triage 2>/dev/null \
    | jq -c '[(.triage.recommendations // .recommendations // [])[].id]' 2>/dev/null || echo "[]")"
  [[ -n "$RANKS" ]] || RANKS="[]"
  if [[ "$RANKS" != "[]" ]]; then
    FR="$(printf '%s' "$FR" | jq -c --argjson r "$RANKS" '
      to_entries
      | sort_by(((.value.id) as $i | ($r | index($i))) // 999999, (.value.priority // 9), .key)
      | map(.value)')"
  fi
fi

if [[ $JSON -eq 1 ]]; then printf '%s\n' "$FR"; exit 0; fi
printf '%s' "$FR" | jq -r '.[] | [(.id | tostring), ((.title // "") | tostring | gsub("[[:cntrl:]]"; " "))] | join("\t")'
