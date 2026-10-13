#!/usr/bin/env bash
# Get highest priority ready work
# Usage: get-ready-work.sh [limit] [--ids-only] [--graph] [--include-questions]
#
# Examples:
#   get-ready-work.sh               # Top 5 ready tasks, priority order, full JSON
#   get-ready-work.sh 10            # Top 10 ready tasks
#   get-ready-work.sh 1 --ids-only  # Just the top task ID
#   get-ready-work.sh 5 --graph     # Graph-aware order (bv), same output shape
#   get-ready-work.sh 5 --include-questions  # also list decision tickets
#
# Decision tickets (`question` beads, the /chart map tickets) are never build
# work, so they are dropped from the ready set whatever labels they carry (a
# `sprint:` label or an epic parent does not make one selectable). Only the
# `question` type is removed; every other type br reports (task, bug, feature,
# chore, docs, epic, ...) passes untouched, so a new type is never silently
# dropped. --include-questions keeps them (the /chart frontier uses it).
#
# --graph REORDERS the ready set by dependency-graph impact (bv --robot-triage:
# unblock counts, PageRank, staleness) instead of priority alone — so a task
# that unblocks ten others outranks a higher-priority leaf. Membership never
# changes: the candidates are exactly the filtered `br ready` set in both modes (same objects,
# same shape), only their order differs, so downstream consumers (/implement,
# /run) need no changes. Requires bv (beads_viewer) on PATH; falls back
# silently to priority order when bv is absent or errors. Never runs bare `bv`
# (that launches a TUI). SIDE EFFECT: bv's first run in a repo creates/updates a
# root .gitignore entry for its .bv/ cache — expected, but worth knowing in CI.
#
# Part of Loa beads_rust integration

set -euo pipefail

LIMIT=""
IDS_ONLY=false
GRAPH=false
INCLUDE_QUESTIONS=false

# Flags and the positional limit are parsed independently — `--graph` as the
# first argument must not become the limit (it would be interpolated into the
# jq program and fail to compile). The limit is validated as a number for the
# same reason.
for arg in "$@"; do
  case "$arg" in
    --ids-only) IDS_ONLY=true ;;
    --graph)    GRAPH=true ;;
    --include-questions) INCLUDE_QUESTIONS=true ;;
    -*)
      echo "ERROR: unknown flag '$arg'" >&2
      echo "Usage: get-ready-work.sh [limit] [--ids-only] [--graph] [--include-questions]" >&2
      exit 1
      ;;
    ''|*[!0-9]*)
      echo "ERROR: limit must be a non-negative integer (got '$arg')" >&2
      exit 1
      ;;
    *) LIMIT="$arg" ;;
  esac
done
LIMIT="${LIMIT:-5}"

# Navigate to project root
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# Get ready work sorted by priority
READY=$(br ready --json 2>/dev/null || echo "[]")

# Exclude decision tickets (see the header). A non-array reply (an error
# envelope, or nothing) reads as no ready work, as a failed br call does.
if [ "$INCLUDE_QUESTIONS" = true ]; then
  READY=$(printf '%s' "$READY" | jq -c 'if type == "array" then . else [] end' 2>/dev/null || echo "[]")
else
  # Fail closed: a reply in which no element names its type (neither `issue_type` nor `type`)
  # cannot be filtered, so it reads as no ready work, with a warning.
  if printf '%s' "$READY" | jq -e 'type == "array" and length > 0 and all(.[]; ((.issue_type // .type) == null))' >/dev/null 2>&1; then
    echo "WARN: br ready returned beads without issue_type or type; question beads cannot be excluded, so no work is listed" >&2
    READY="[]"
  else
    READY=$(printf '%s' "$READY" | jq -c 'if type == "array" then map(select(((.issue_type // .type // "") | tostring | ascii_downcase) != "question")) else [] end' 2>/dev/null || echo "[]")
  fi
fi
[ -n "$READY" ] || READY="[]"

# Graph mode: rank the SAME ready set by bv's triage order. Ready beads that bv
# does not rank keep their priority order, after the ranked ones.
if [ "$GRAPH" = true ] && [ "$READY" != "[]" ] && command -v bv &>/dev/null; then
  # Bound the git-history prologue so this stays snappy at session start.
  # bv v0.18.0 nests recommendations under .triage (verified against the
  # binary); the top-level fallback covers releases that flatten the envelope.
  BV_RANKS=$(CI=1 BV_ROBOT_HISTORY_TIMEOUT_MS="${BV_ROBOT_HISTORY_TIMEOUT_MS:-3000}" \
    bv --robot-triage 2>/dev/null \
    | jq -c '[(.triage.recommendations // .recommendations // [])[].id]' 2>/dev/null || echo "[]")
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
  echo "$READY" | jq -r --argjson limit "$LIMIT" "$ORDER | limit(\$limit; .[]) | .id"
else
  echo "$READY" | jq -r --argjson limit "$LIMIT" "$ORDER | limit(\$limit; .[])"
fi
