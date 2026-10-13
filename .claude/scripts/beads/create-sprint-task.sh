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
# Failure contract: dependency ids are verified BEFORE the bead is created (a
# bad id creates no orphan). If an edge or the deps:none label fails to WRITE
# after creation, the script exits 1 — the task id is still printed on stdout
# so the caller can repair (br dep add <task> <dep>) instead of retrying into
# a duplicate.
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

# A --deps value that is empty (or trims to empty) is neither edges nor an
# assertion — it would slip through the edge-or-none rule unnoticed. Refuse
# it. Trimming here also makes '--deps " none "' a valid assertion. A value
# starting with '-' is an omitted value that swallowed the next flag.
if [ "$DEPS_SET" = true ]; then
  DEPS="$(echo "$DEPS" | xargs)"
  case "$DEPS" in
    -*)
      echo "ERROR: --deps requires a value, got flag-like '$DEPS' (comma-separated ids, or 'none')" >&2
      exit 1
      ;;
  esac
  if [ -z "$DEPS" ]; then
    echo "ERROR: --deps requires ids or 'none' (got an empty value)" >&2
    exit 1
  fi
fi

if [ -z "$EPIC_ID" ] || [ -z "$TITLE" ]; then
  echo "Usage: create-sprint-task.sh <epic-id> \"Task title\" [priority] [type] [--deps <id1,id2|none>]" >&2
  echo "" >&2
  echo "Arguments:" >&2
  echo "  epic-id   - Parent epic ID (e.g., beads-a1b2)" >&2
  echo "  title     - Task title" >&2
  echo "  priority  - 0-4, default: 2" >&2
  echo "  type      - task|bug|feature, default: task (question is refused: use /chart)" >&2
  echo "  --deps    - Blocking dependencies: comma-separated bead ids, or 'none'" >&2
  echo "              to assert the task has no blockers (label deps:none)" >&2
  echo "" >&2
  echo "Examples:" >&2
  echo "  create-sprint-task.sh beads-a1b2 \"Implement auth\" 1 task --deps none" >&2
  echo "  create-sprint-task.sh beads-a1b2 \"Wire login route\" 2 task --deps beads-c3d4" >&2
  exit 1
fi

# Decision tickets (type question) belong to a /chart map, never to a sprint:
# the build path cannot select them (get-ready-work.sh excludes the type), and
# a sprint epic is build work. Refused here, before any br call, so no bead
# exists afterwards (grimoires/loa/sdd.md D-4.7).
TYPE_LC="$(printf '%s' "$TYPE" | tr '[:upper:]' '[:lower:]')"
if [ "$TYPE_LC" = "question" ]; then
  echo "ERROR: type 'question' refused: decision tickets never go under a sprint epic; chart them with /chart" >&2
  exit 1
fi

# Navigate to project root
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# Verify epic exists
if ! EPIC_JSON="$(br show "$EPIC_ID" --json 2>/dev/null)"; then
  echo "ERROR: Epic $EPIC_ID not found" >&2
  exit 1
fi

# A map epic (label `map`) is a /chart decision map: its children are question
# beads only, so no sprint task is created under it. br show --json is a
# one-element array; labels are strings (older releases: {name} objects).
EPIC_IS_MAP="$(printf '%s' "$EPIC_JSON" | jq -r '
  (if type == "array" then (.[0] // {}) else . end)
  | [(.labels // [])[] | if type == "object" then (.name // "") else tostring end]
  | if any(.[]; . == "map") then "yes" else "no" end' 2>/dev/null || echo "unknown")"
if [ "$EPIC_IS_MAP" = "unknown" ] || [ -z "$EPIC_IS_MAP" ]; then
  echo "ERROR: could not read the labels of $EPIC_ID from 'br show $EPIC_ID --json'; task not created (check br and jq, then retry)" >&2
  exit 1
fi
if [ "$EPIC_IS_MAP" = "yes" ]; then
  echo "ERROR: $EPIC_ID is a map epic (label map): it holds decision tickets only, and decision tickets never go under a sprint epic; chart them with /chart" >&2
  exit 1
fi

# Verify dependencies BEFORE creating the task — a bad id must not leave an
# orphan bead behind. Comma-split tokens are trimmed; at least one non-empty
# id must survive, or the value was noise like ',' / 'id,,' masquerading as
# edges (the whitespace-only case was already refused above).
DEP_IDS=()
if [ "$DEPS_SET" = true ] && [ "$DEPS" != "none" ]; then
  IFS=',' read -ra RAW_DEPS <<< "$DEPS"
  for DEP in "${RAW_DEPS[@]}"; do
    DEP="$(echo "$DEP" | xargs)"  # trim whitespace
    [ -z "$DEP" ] && continue
    if ! br show "$DEP" --json &>/dev/null; then
      echo "ERROR: dependency $DEP not found — task not created" >&2
      exit 1
    fi
    DEP_IDS+=("$DEP")
  done
  if [ ${#DEP_IDS[@]} -eq 0 ]; then
    echo "ERROR: --deps requires ids or 'none' (got an empty value)" >&2
    exit 1
  fi
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

# Record dependency edges (or the explicit no-blockers assertion). A write
# failure here must not be silent: a task reported as created-with-edges but
# missing them would surface in `br ready` as falsely unblocked. Per the
# failure contract above, print the task id and exit 1 so the caller repairs
# instead of retrying into a duplicate.
if [ "$DEPS_SET" = true ]; then
  if [ "$DEPS" = "none" ]; then
    if ! br label add "$TASK_ID" "deps:none" 2>/dev/null; then
      echo "ERROR: $TASK_ID created but the deps:none assertion failed to record — repair with: br label add $TASK_ID deps:none" >&2
      echo "$TASK_ID"
      exit 1
    fi
  else
    EDGE_FAILURES=0
    for DEP in "${DEP_IDS[@]}"; do
      if br dep add "$TASK_ID" "$DEP" >/dev/null 2>&1; then
        echo "  dep: $TASK_ID blocked-by $DEP" >&2
      else
        echo "ERROR: failed to add dependency edge $TASK_ID -> $DEP" >&2
        EDGE_FAILURES=$((EDGE_FAILURES + 1))
      fi
    done
    if [ "$EDGE_FAILURES" -gt 0 ]; then
      echo "ERROR: $TASK_ID created but $EDGE_FAILURES dependency edge(s) missing — repair with: br dep add $TASK_ID <dep-id>" >&2
      echo "$TASK_ID"
      exit 1
    fi
  fi
else
  echo "note: no --deps declared for $TASK_ID (pass --deps none to assert no blockers)" >&2
fi

echo "Created $TYPE: $TASK_ID - $TITLE (under $EPIC_ID)" >&2
echo "$TASK_ID"
