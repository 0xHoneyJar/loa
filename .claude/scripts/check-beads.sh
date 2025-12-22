#!/bin/bash
# check-beads.sh
# Purpose: Check if Beads (bd CLI) is installed and offer installation options
# Usage: ./check-beads.sh [--quiet]
#
# Exit codes:
#   0 - Beads is installed
#   1 - Beads is not installed (returns install instructions)
#
# Output (when not installed):
#   NOT_INSTALLED|brew install steveyegge/beads/bd|npm install -g @beads/bd

set -euo pipefail

QUIET="${1:-}"

# Check if bd CLI is available
if command -v bd &> /dev/null; then
    if [ "$QUIET" != "--quiet" ]; then
        echo "INSTALLED"
    fi
    exit 0
fi

# Beads not installed - return installation options
if [ "$QUIET" == "--quiet" ]; then
    echo "NOT_INSTALLED"
else
    echo "NOT_INSTALLED|brew install steveyegge/beads/bd|npm install -g @beads/bd"
fi
exit 1
