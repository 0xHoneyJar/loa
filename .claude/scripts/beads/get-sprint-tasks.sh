#!/bin/bash
# Get all tasks under a sprint epic
# Usage: get-sprint-tasks.sh <sprint-epic-id>
#
# Returns JSON array of tasks that belong to the specified sprint epic.
# Tasks are identified by IDs starting with "<epic-id>."

set -euo pipefail

EPIC_ID="${1:-}"

if [[ -z "$EPIC_ID" ]]; then
    echo "Usage: $0 <sprint-epic-id>" >&2
    echo "Example: $0 bd-a3f8" >&2
    exit 1
fi

# Check if bd is installed
if ! command -v bd &> /dev/null; then
    echo "Error: bd (beads) is not installed" >&2
    echo "Install with: curl -fsSL https://raw.githubusercontent.com/steveyegge/beads/main/scripts/install.sh | bash" >&2
    exit 1
fi

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "Error: jq is not installed" >&2
    exit 1
fi

# Get tasks under the epic
bd list --json | jq --arg epic "$EPIC_ID" '[.[] | select(.id | startswith($epic + "."))]'
