#!/usr/bin/env bash
# Create a task under a sprint epic
# Usage: create-sprint-task.sh <epic-id> "Task title" [priority] [type]
#
# Examples:
#   create-sprint-task.sh beads-a1b2 "Implement auth API" 1
#   create-sprint-task.sh beads-a1b2 "Fix login bug" 0 bug
#   create-sprint-task.sh beads-a1b2 "Add OAuth support" 2 feature
#
# Part of Loa beads_rust integration

set -euo pipefail

EPIC_ID="${1:-}"
TITLE="${2:-}"
PRIORITY="${3:-2}"
TYPE="${4:-task}"

if [ -z "$EPIC_ID" ] || [ -z "$TITLE" ]; then
  echo "Usage: create-sprint-task.sh <epic-id> \"Task title\" [priority] [type]" >&2
  echo "" >&2
  echo "Arguments:" >&2
  echo "  epic-id   - Parent epic ID (e.g., beads-a1b2)" >&2
  echo "  title     - Task title" >&2
  echo "  priority  - 0-4, default: 2" >&2
  echo "  type      - task|bug|feature, default: task" >&2
  echo "" >&2
  echo "Examples:" >&2
  echo "  create-sprint-task.sh beads-a1b2 \"Implement auth\" 1 task" >&2
  echo "  create-sprint-task.sh beads-a1b2 \"Fix login bug\" 0 bug" >&2
  exit 1
fi

# Navigate to project root
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# Verify epic exists
if ! br show "$EPIC_ID" --json &>/dev/null; then
  echo "ERROR: Epic $EPIC_ID not found" >&2
  exit 1
fi

# Create the task
RESULT=$(br create "$TITLE" --type "$TYPE" --priority "$PRIORITY" --json)
TASK_ID=$(echo "$RESULT" | jq -r '.id')

if [ -z "$TASK_ID" ] || [ "$TASK_ID" = "null" ]; then
  echo "ERROR: Failed to create task" >&2
  echo "$RESULT" >&2
  exit 1
fi

# Add epic label for association
br label add "$TASK_ID" "epic:$EPIC_ID" 2>/dev/null || true

# Inherit sprint label from epic if present
EPIC_LABELS=$(br label list "$EPIC_ID" 2>/dev/null || echo "")
SPRINT_LABEL=$(echo "$EPIC_LABELS" | grep -oE 'sprint:[0-9]+' | head -1 || echo "")
if [ -n "$SPRINT_LABEL" ]; then
  br label add "$TASK_ID" "$SPRINT_LABEL" 2>/dev/null || true
fi

echo "Created $TYPE: $TASK_ID - $TITLE (under $EPIC_ID)" >&2
echo "$TASK_ID"
