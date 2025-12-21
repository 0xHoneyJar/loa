#!/bin/bash
# Get ready work sorted by priority
# Usage: get-ready-by-priority.sh [limit]
#
# Returns ready work (no open blockers) sorted by priority (P1 first).
# Optional limit parameter restricts number of results.

set -euo pipefail

LIMIT="${1:-}"

# Check if bd is installed
if ! command -v bd &> /dev/null; then
    echo "Error: bd (beads) is not installed" >&2
    echo "Install with: curl -fsSL https://raw.githubusercontent.com/steveyegge/beads/main/scripts/install.sh | bash" >&2
    exit 1
fi

# Get ready work sorted by priority
if [[ -n "$LIMIT" ]]; then
    bd ready --sort priority --limit "$LIMIT" --json
else
    bd ready --sort priority --json
fi
