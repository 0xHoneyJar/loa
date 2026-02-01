#!/usr/bin/env bash
# Get highest priority ready work
# Usage: get-ready-work.sh [limit] [--ids-only]
#
# Examples:
#   get-ready-work.sh           # Top 5 ready tasks, full JSON
#   get-ready-work.sh 10        # Top 10 ready tasks
#   get-ready-work.sh 1 --ids-only  # Just the top task ID
#
# Part of Loa beads_rust integration

set -euo pipefail

LIMIT=${1:-5}
IDS_ONLY=false

# Check for --ids-only flag
for arg in "$@"; do
  if [ "$arg" = "--ids-only" ]; then
    IDS_ONLY=true
  fi
done

# Navigate to project root
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# Get ready work sorted by priority
READY=$(br ready --json 2>/dev/null || echo "[]")

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

if [ "$IDS_ONLY" = true ]; then
  echo "$READY" | jq -r "sort_by(.priority) | limit($LIMIT; .[]) | .id"
else
  echo "$READY" | jq -r "sort_by(.priority) | limit($LIMIT; .[])"
fi
