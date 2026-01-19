#!/bin/bash
# Check if beads_rust (br) is installed and initialized
# Usage: check-beads.sh [--verbose]
#
# Returns:
#   0 - beads_rust is installed and initialized (READY)
#   1 - beads_rust not installed (NOT_INSTALLED)
#   2 - beads_rust installed but not initialized (NOT_INITIALIZED)
#
# With --verbose flag, outputs additional diagnostic information.
#
# Part of Loa beads_rust integration

set -euo pipefail

VERBOSE=false
if [[ "${1:-}" == "--verbose" ]]; then
    VERBOSE=true
fi

# Check if br is installed
if ! command -v br &> /dev/null; then
    echo "NOT_INSTALLED"
    if $VERBOSE; then
        echo ""
        echo "The 'br' command is not found in PATH."
        echo "Install with: .claude/scripts/beads/install-br.sh"
        echo ""
        echo "Or manually: curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/beads_rust/main/install.sh | bash"
        echo ""
        echo "Current PATH: $PATH"
    fi
    exit 1
fi

# Get version info
if $VERBOSE; then
    VERSION=$(br --version 2>/dev/null || echo "unknown")
    echo "br version: $VERSION"
    echo "br location: $(which br)"
fi

# Check if beads is initialized in current project
if [[ ! -d ".beads" ]]; then
    echo "NOT_INITIALIZED"
    if $VERBOSE; then
        echo ""
        echo "beads_rust is installed but not initialized in this project."
        echo "Initialize with: br init"
        echo ""
        echo "Current directory: $(pwd)"
    fi
    exit 2
fi

# Check if beads.db exists (SQLite is primary storage in beads_rust)
if [[ ! -f ".beads/beads.db" ]]; then
    echo "NOT_INITIALIZED"
    if $VERBOSE; then
        echo ""
        echo ".beads/ directory exists but beads.db is missing."
        echo "Re-initialize with: br init"
    fi
    exit 2
fi

# beads_rust is ready
echo "READY"
if $VERBOSE; then
    echo ""
    echo "beads_rust is installed and initialized."
    echo "Database: .beads/beads.db"
    # Count issues via br list
    ISSUE_COUNT=$(br list --json 2>/dev/null | jq 'length' || echo "0")
    echo "Issues in database: $ISSUE_COUNT"
    echo ""
    echo "Quick commands:"
    echo "  br ready --json     # Find next actionable tasks"
    echo "  br list --json      # List all issues"
    echo "  br stats            # Show statistics"
    echo ""
    echo "Sync protocol:"
    echo "  br sync --import-only  # Import JSONL → SQLite (session start)"
    echo "  br sync --flush-only   # Export SQLite → JSONL (before commit)"
fi
exit 0
