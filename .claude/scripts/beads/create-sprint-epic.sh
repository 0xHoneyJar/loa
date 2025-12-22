#!/bin/bash
# Create a new sprint epic
# Usage: create-sprint-epic.sh "Sprint N: Description"
#
# Creates a new epic-type issue with priority 1 (Urgent).
# Returns the created issue as JSON.

set -euo pipefail

TITLE="${1:-}"

if [[ -z "$TITLE" ]]; then
    echo "Usage: $0 \"Sprint N: Description\"" >&2
    echo "Example: $0 \"Sprint 1: Core Authentication\"" >&2
    exit 1
fi

# Check if bd is installed
if ! command -v bd &> /dev/null; then
    echo "Error: bd (beads) is not installed" >&2
    echo "Install with: curl -fsSL https://raw.githubusercontent.com/steveyegge/beads/main/scripts/install.sh | bash" >&2
    exit 1
fi

# Create epic with priority 1 (urgent for sprint epics)
bd create "$TITLE" -t epic -p 1 --json
