#!/usr/bin/env bash
# Get highest priority ready work
# Usage: get-ready-work.sh [limit] [--ids-only] [--graph]
#
# Examples:
#   get-ready-work.sh               # Top 5 ready tasks, priority order, full JSON
#   get-ready-work.sh 10            # Top 10 ready tasks
#   get-ready-work.sh 1 --ids-only  # Just the top task ID
#   get-ready-work.sh 5 --graph     # Graph-aware order (bv), same output shape
#
# --graph REORDERS the ready set by dependency-graph impact (bv --robot-triage:
# unblock counts, PageRank, staleness) instead of priority alone — so a task
# that unblocks ten others outranks a higher-priority leaf. Membership never
# changes: the candidates are exactly `br ready` in both modes (same objects,
# same shape), only their order differs, so downstream consumers (/implement,
# /run) need no changes. Requires bv (beads_viewer) on PATH; falls back
# silently to priority order when bv is absent or errors. Never runs bare `bv`
# (that launches a TUI).
#
# Part of Loa beads_rust integration

set -euo pipefail

LIMIT=${1:-5}
IDS_ONLY=false
GRAPH=false

# Check flags
for arg in "$@"; do
  case "$arg" in
    --ids-only) IDS_ONLY=true ;;
    --graph)    GRAPH=true ;;
  esac
done

# Navigate to project root
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# Get ready work sorted by priority
READY=$(br ready --json 2>/dev/null || echo "[]")

# Graph mode: rank the SAME ready set by bv's triage order. Ready beads that bv
# does not rank keep their priority order, after the ranked ones.
if [ "$GRAPH" = true ] && [ "$READY" != "[]" ] && command -v bv &>/dev/null; then
  # Bound the git-history prologue so this stays snappy at session start.
  BV_RANKS=$(CI=1 BV_ROBOT_HISTORY_TIMEOUT_MS="${BV_ROBOT_HISTORY_TIMEOUT_MS:-3000}" \
    bv --robot-triage 2>/dev/null \
    | jq -c '[(.triage.recommendations // [])[].id]' 2>/dev/null || echo "[]")
  if [ "$BV_RANKS" != "[]" ] && [ -n "$BV_RANKS" ]; then
    READY=$(echo "$READY" | jq --argjson ranks "$BV_RANKS" '
      sort_by(
        (if (. as $i | $ranks | index($i.id)) != null
         then (. as $i | $ranks | index($i.id))
         else 999999 end),
        .priority
      )')
    GRAPH_SORTED=true
  fi
  # bv absent, errored, or unranked -> READY keeps priority order below.
fi
GRAPH_SORTED=${GRAPH_SORTED:-false}

if [ "$READY" = "[]" ]; then
  if [ "$IDS_ONLY" = true ]; then
    exit 0  # Silent exit for scripting
  else
    echo "No ready tasks available."
    echo ""
    echo "Check blocked issues:"
    echo "  br blocked --json"
    exit 0
  fi
fi

# In graph mode READY is already ranked; re-sorting by priority would undo it.
if [ "$GRAPH_SORTED" = true ]; then
  ORDER="."
else
  ORDER="sort_by(.priority)"
fi

if [ "$IDS_ONLY" = true ]; then
  echo "$READY" | jq -r "$ORDER | limit($LIMIT; .[]) | .id"
else
  echo "$READY" | jq -r "$ORDER | limit($LIMIT; .[])"
fi
