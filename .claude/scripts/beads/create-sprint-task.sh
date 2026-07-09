#!/usr/bin/env bash
# Create a task under a sprint epic
# Usage: create-sprint-task.sh <epic-id> "Task title" [priority] [type] [--deps <id1,id2|none>]
#
# Examples:
#   create-sprint-task.sh beads-a1b2 "Implement auth API" 1
#   create-sprint-task.sh beads-a1b2 "Fix login bug" 0 bug
#   create-sprint-task.sh beads-a1b2 "Add OAuth support" 2 feature --deps beads-c3d4
#   create-sprint-task.sh beads-a1b2 "Write API docs" 3 task --deps none
#
# --deps captures blocking dependencies AT CREATION — the moment the ordering
# knowledge exists (a sprint plan is an ordered list). A task graph with edges is
# schedulable (topological order, parallel tracks, unblock counts); a flat list
# is not, and retrofitting edges later costs O(n^2) review.
#   --deps "id1,id2"  -> this task is blocked by id1 and id2 (br dep add)
#   --deps none       -> explicit no-blockers assertion (label deps:none)
#   omitted           -> allowed (backward compatible), warns on stderr
#
# Part of Loa beads_rust integration

set -euo pipefail

POSITIONAL=()
DEPS=""
DEPS_SET=false

while [ $# -gt 0 ]; do
  case "$1" in
    --deps)
      if [ $# -lt 2 ]; then
        echo "ERROR: --deps requires a value (comma-separated ids, or 'none')" >&2
        exit 1
      fi
      DEPS="$2"
      DEPS_SET=true
      shift 2
      ;;
    --deps=*)
      DEPS="${1#--deps=}"
      DEPS_SET=true
      shift
      ;;
    *)
      POSITIONAL+=("$1")
      shift
      ;;
  esac
done

EPIC_ID="${POSITIONAL[0]:-}"
TITLE="${POSITIONAL[1]:-}"
PRIORITY="${POSITIONAL[2]:-2}"
TYPE="${POSITIONAL[3]:-task}"

if [ -z "$EPIC_ID" ] || [ -z "$TITLE" ]; then
  echo "Usage: create-sprint-task.sh <epic-id> \"Task title\" [priority] [type] [--deps <id1,id2|none>]" >&2
  echo "" >&2
  echo "Arguments:" >&2
  echo "  epic-id   - Parent epic ID (e.g., beads-a1b2)" >&2
  echo "  title     - Task title" >&2
  echo "  priority  - 0-4, default: 2" >&2
  echo "  type      - task|bug|feature, default: task" >&2
  echo "  --deps    - Blocking dependencies: comma-separated bead ids, or 'none'" >&2
  echo "              to assert the task has no blockers (label deps:none)" >&2
  echo "" >&2
  echo "Examples:" >&2
  echo "  create-sprint-task.sh beads-a1b2 \"Implement auth\" 1 task --deps none" >&2
  echo "  create-sprint-task.sh beads-a1b2 \"Wire login route\" 2 task --deps beads-c3d4" >&2
  exit 1
fi

# Navigate to project root
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# Verify epic exists
if ! br show "$EPIC_ID" --json &>/dev/null; then
  echo "ERROR: Epic $EPIC_ID not found" >&2
  exit 1
fi

# Verify dependencies BEFORE creating the task — a bad id must not leave an
# orphan bead behind.
DEP_IDS=()
if [ "$DEPS_SET" = true ] && [ "$DEPS" != "none" ]; then
  IFS=',' read -ra DEP_IDS <<< "$DEPS"
  for DEP in "${DEP_IDS[@]}"; do
    DEP="$(echo "$DEP" | xargs)"  # trim whitespace
    [ -z "$DEP" ] && continue
    if ! br show "$DEP" --json &>/dev/null; then
      echo "ERROR: dependency $DEP not found — task not created" >&2
      exit 1
    fi
  done
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

# Record dependency edges (or the explicit no-blockers assertion)
if [ "$DEPS_SET" = true ]; then
  if [ "$DEPS" = "none" ]; then
    br label add "$TASK_ID" "deps:none" 2>/dev/null || true
  else
    for DEP in "${DEP_IDS[@]}"; do
      DEP="$(echo "$DEP" | xargs)"
      [ -z "$DEP" ] && continue
      if br dep add "$TASK_ID" "$DEP" >/dev/null 2>&1; then
        echo "  dep: $TASK_ID blocked-by $DEP" >&2
      else
        echo "WARNING: failed to add dependency $TASK_ID -> $DEP" >&2
      fi
    done
  fi
else
  echo "note: no --deps declared for $TASK_ID (pass --deps none to assert no blockers)" >&2
fi

echo "Created $TYPE: $TASK_ID - $TITLE (under $EPIC_ID)" >&2
echo "$TASK_ID"
