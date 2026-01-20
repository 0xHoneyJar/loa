#!/bin/bash
# Log a discovered bug/debt during task implementation
# Usage: log-discovered-issue.sh <parent-id> "Issue title" [type] [priority]
#
# This creates a new issue and labels it with the semantic relationship
# "discovered-during:<parent-id>" to maintain traceability.
#
# Examples:
#   log-discovered-issue.sh beads-a1b2 "Found: NPE in auth handler"
#   log-discovered-issue.sh beads-a1b2 "Tech debt: refactor user service" task 3
#   log-discovered-issue.sh beads-a1b2 "Security: SQL injection risk" bug 0
#
# Part of Loa beads_rust integration

set -euo pipefail

PARENT_ID="${1:-}"
TITLE="${2:-}"
TYPE="${3:-bug}"
PRIORITY="${4:-2}"

if [ -z "$PARENT_ID" ] || [ -z "$TITLE" ]; then
  echo "Usage: log-discovered-issue.sh <parent-id> \"Issue title\" [type] [priority]" >&2
  echo "" >&2
  echo "Arguments:" >&2
  echo "  parent-id - ID of task where issue was discovered" >&2
  echo "  title     - Description of discovered issue" >&2
  echo "  type      - bug|task|feature, default: bug" >&2
  echo "  priority  - 0-4, default: 2" >&2
  echo "" >&2
  echo "The new issue will be labeled 'discovered-during:<parent-id>'" >&2
  exit 1
fi

# Navigate to project root
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# Verify parent exists
if ! br show "$PARENT_ID" --json &>/dev/null; then
  echo "WARNING: Parent $PARENT_ID not found, creating anyway" >&2
fi

# Create the discovered issue
RESULT=$(br create "$TITLE" --type "$TYPE" --priority "$PRIORITY" --json)
NEW_ID=$(echo "$RESULT" | jq -r '.id')

if [ -z "$NEW_ID" ] || [ "$NEW_ID" = "null" ]; then
  echo "ERROR: Failed to create issue" >&2
  echo "$RESULT" >&2
  exit 1
fi

# Add semantic label for traceability
br label add "$NEW_ID" "discovered-during:$PARENT_ID" 2>/dev/null || true

# Inherit sprint label from parent if present
PARENT_LABELS=$(br label list "$PARENT_ID" 2>/dev/null || echo "")
SPRINT_LABEL=$(echo "$PARENT_LABELS" | grep -oE 'sprint:[0-9]+' | head -1 || echo "")
if [ -n "$SPRINT_LABEL" ]; then
  br label add "$NEW_ID" "$SPRINT_LABEL" 2>/dev/null || true
fi

# Optionally copy epic label
EPIC_LABEL=$(echo "$PARENT_LABELS" | grep -oE 'epic:beads-[a-z0-9]+' | head -1 || echo "")
if [ -n "$EPIC_LABEL" ]; then
  br label add "$NEW_ID" "$EPIC_LABEL" 2>/dev/null || true
fi

# Add a comment to parent noting the discovery
br comments add "$PARENT_ID" "Discovered issue: $NEW_ID - $TITLE" 2>/dev/null || true

echo "Created discovered $TYPE: $NEW_ID - $TITLE" >&2
echo "  Labeled: discovered-during:$PARENT_ID" >&2
echo "$NEW_ID"
