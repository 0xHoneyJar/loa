#!/bin/bash
# Check if Beads is installed and initialized
# Usage: check-beads.sh
#
# Returns:
#   0 - Beads is installed and initialized
#   1 - Beads not installed
#   2 - Beads installed but not initialized

set -euo pipefail

# Check if bd is installed
if ! command -v bd &> /dev/null; then
    echo "NOT_INSTALLED"
    exit 1
fi

# Check if beads is initialized in current project
if [[ ! -d ".beads" ]]; then
    echo "NOT_INITIALIZED"
    exit 2
fi

# Beads is ready
echo "READY"
exit 0
