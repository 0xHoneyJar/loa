#!/bin/bash
# Get all tasks associated with a sprint epic
# Usage: get-sprint-tasks.sh <epic-id> [--status <status>]
#
# Examples:
#   get-sprint-tasks.sh beads-a1b2              # All tasks in epic
#   get-sprint-tasks.sh beads-a1b2 --status open  # Only open tasks
#   get-sprint-tasks.sh beads-a1b2 --ready      # Only ready (unblocked) tasks
#
# Part of Loa beads_rust integration

set -euo pipefail

EPIC_ID="${1:-}"
shift || true

# Parse flags
STATUS=""
READY_ONLY=false
while [ $# -gt 0 ]; do
  case "$1" in
    --status)
      STATUS="${2:-}"
      shift 2 || true
      ;;
    --ready)
      READY_ONLY=true
      shift
      ;;
    *)
      shift
      ;;
  esac
done

if [ -z "$EPIC_ID" ]; then
  echo "Usage: get-sprint-tasks.sh <epic-id> [--status <status>] [--ready]" >&2
  echo "" >&2
  echo "Options:" >&2
  echo "  --status <status>  Filter by status (open, in_progress, closed)" >&2
  echo "  --ready            Show only unblocked tasks" >&2
  exit 1
fi

# Navigate to project root
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

if [ "$READY_ONLY" = true ]; then
  # Get ready work filtered by epic
  br ready --json | jq --arg epic "$EPIC_ID" '[.[] | select(.labels[]? | contains("epic:" + $epic))]'
else
  # Build jq filter
  FILTER="[.[] | select(.labels[]? | contains(\"epic:$EPIC_ID\"))"

  if [ -n "$STATUS" ]; then
    FILTER="$FILTER | select(.status == \"$STATUS\")"
  fi

  FILTER="$FILTER]"

  br list --json | jq "$FILTER"
fi
