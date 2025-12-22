#!/bin/bash
# Check if Beads is installed and initialized
# Usage: check-beads.sh [--verbose]
#
# Returns:
#   0 - Beads is installed and initialized (READY)
#   1 - Beads not installed (NOT_INSTALLED)
#   2 - Beads installed but not initialized (NOT_INITIALIZED)
#
# With --verbose flag, outputs additional diagnostic information.

set -euo pipefail

VERBOSE=false
if [[ "${1:-}" == "--verbose" ]]; then
    VERBOSE=true
fi

# Check if bd is installed
if ! command -v bd &> /dev/null; then
    echo "NOT_INSTALLED"
    if $VERBOSE; then
        echo ""
        echo "The 'bd' command is not found in PATH."
        echo "Install with: .claude/scripts/beads/install-beads.sh"
        echo ""
        echo "Current PATH: $PATH"
    fi
    exit 1
fi

# Get version info
if $VERBOSE; then
    VERSION=$(bd --version 2>/dev/null || echo "unknown")
    echo "bd version: $VERSION"
    echo "bd location: $(which bd)"
fi

# Check if beads is initialized in current project
if [[ ! -d ".beads" ]]; then
    echo "NOT_INITIALIZED"
    if $VERBOSE; then
        echo ""
        echo "Beads is installed but not initialized in this project."
        echo "Initialize with: bd init"
        echo ""
        echo "Current directory: $(pwd)"
    fi
    exit 2
fi

# Check if beads.jsonl exists and is valid
if [[ ! -f ".beads/beads.jsonl" ]]; then
    echo "NOT_INITIALIZED"
    if $VERBOSE; then
        echo ""
        echo ".beads/ directory exists but beads.jsonl is missing."
        echo "Re-initialize with: bd init --force"
    fi
    exit 2
fi

# Beads is ready
echo "READY"
if $VERBOSE; then
    echo ""
    echo "Beads is installed and initialized."
    echo "Database: .beads/beads.jsonl"
    ISSUE_COUNT=$(wc -l < .beads/beads.jsonl 2>/dev/null || echo "0")
    echo "Issues in database: $ISSUE_COUNT"
    echo ""
    echo "Quick commands:"
    echo "  bd ready --json     # Find next actionable tasks"
    echo "  bd list --json      # List all issues"
    echo "  bd stats            # Show statistics"
fi
exit 0
