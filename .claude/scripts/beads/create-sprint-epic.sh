#!/usr/bin/env bash
# Create a sprint epic and return its ID
# Usage: create-sprint-epic.sh "Sprint N: Theme" [priority]
#
# Examples:
#   create-sprint-epic.sh "Sprint 1: Foundation"
#   create-sprint-epic.sh "Sprint 2: Auth System" 0  # P0 priority
#
# Part of Loa beads_rust integration

set -euo pipefail

TITLE="${1:-}"
PRIORITY="${2:-1}"

if [ -z "$TITLE" ]; then
  echo "Usage: create-sprint-epic.sh \"Sprint N: Theme\" [priority]" >&2
  echo "" >&2
  echo "Examples:" >&2
  echo "  create-sprint-epic.sh \"Sprint 1: Foundation\"" >&2
  echo "  create-sprint-epic.sh \"Sprint 2: Auth\" 0" >&2
  exit 1
fi

# Navigate to project root
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# Create the epic
RESULT=$(br create "$TITLE" --type epic --priority "$PRIORITY" --json)
EPIC_ID=$(echo "$RESULT" | jq -r '.id')

if [ -z "$EPIC_ID" ] || [ "$EPIC_ID" = "null" ]; then
  echo "ERROR: Failed to create epic" >&2
  echo "$RESULT" >&2
  exit 1
fi

# Add sprint label for easier querying
# Extract sprint number from title if present
SPRINT_NUM=$(echo "$TITLE" | grep -oE 'Sprint [0-9]+' | grep -oE '[0-9]+' || echo "")
if [ -n "$SPRINT_NUM" ]; then
  br label add "$EPIC_ID" "sprint:$SPRINT_NUM" 2>/dev/null || true
fi

echo "Created epic: $EPIC_ID - $TITLE" >&2
echo "$EPIC_ID"
