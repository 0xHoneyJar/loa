#!/usr/bin/env bash
# Check if beads_rust (br) is installed and initialized
# Usage: check-beads.sh [--verbose] [--json]
#
# Returns:
#   0 - beads_rust is installed and initialized (READY)
#   1 - beads_rust not installed (NOT_INSTALLED)
#   2 - beads_rust installed but not initialized (NOT_INITIALIZED)
#   3 - Legacy bd detected, migration needed (MIGRATION_NEEDED)
#
# With --verbose flag, outputs additional diagnostic information.
# With --json flag, outputs JSON format.

set -euo pipefail

VERBOSE=false
JSON=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --verbose)
            VERBOSE=true
            shift
            ;;
        --json)
            JSON=true
            shift
            ;;
        *)
            shift
            ;;
    esac
done

# JSON output helper
json_output() {
    local status="$1"
    local message="$2"
    local details="${3:-{}}"
    echo "{\"status\":\"$status\",\"message\":\"$message\",\"details\":$details}"
}

# Check for br (beads_rust) - the current CLI
BR_INSTALLED=false
BR_VERSION=""
if command -v br &> /dev/null; then
    BR_INSTALLED=true
    BR_VERSION=$(br --version 2>/dev/null | head -1 || echo "unknown")
fi

# Check for bd (legacy beads) - deprecated
BD_INSTALLED=false
BD_VERSION=""
if command -v bd &> /dev/null; then
    BD_INSTALLED=true
    BD_VERSION=$(bd --version 2>/dev/null | head -1 || echo "unknown")
fi

# Detect .beads directory state
HAS_BEADS_DIR=false
HAS_BR_CONFIG=false
HAS_BD_CONFIG=false
HAS_JSONL=false
JSONL_FILE=""

if [[ -d ".beads" ]]; then
    HAS_BEADS_DIR=true

    # br uses beads.db and .beads/config.toml or br-specific markers
    if [[ -f ".beads/beads.db" ]]; then
        # Check if it's br schema (has issues table with owner column)
        if sqlite3 .beads/beads.db "SELECT owner FROM issues LIMIT 1" &>/dev/null; then
            HAS_BR_CONFIG=true
        fi
    fi

    # bd uses config.yaml
    if [[ -f ".beads/config.yaml" ]]; then
        HAS_BD_CONFIG=true
    fi

    # Check for JSONL files
    for f in ".beads/issues.jsonl" ".beads/beads.left.jsonl" ".beads/export.jsonl"; do
        if [[ -f "$f" ]]; then
            HAS_JSONL=true
            JSONL_FILE="$f"
            break
        fi
    done
fi

# Decision logic
if [[ "$BR_INSTALLED" == "false" ]]; then
    # br not installed
    if $JSON; then
        json_output "NOT_INSTALLED" "beads_rust (br) is not installed" \
            "{\"bd_installed\":$BD_INSTALLED,\"bd_version\":\"$BD_VERSION\"}"
    else
        echo "NOT_INSTALLED"
        if $VERBOSE; then
            echo ""
            echo "The 'br' command (beads_rust) is not found in PATH."
            echo "Install with: .claude/scripts/beads/install-br.sh"
            if [[ "$BD_INSTALLED" == "true" ]]; then
                echo ""
                echo "Note: Legacy 'bd' CLI is installed ($BD_VERSION)"
                echo "Loa v1.1.0+ uses 'br' instead of 'bd'"
            fi
        fi
    fi
    exit 1
fi

# br is installed - check initialization state
if [[ "$HAS_BEADS_DIR" == "false" ]]; then
    # No .beads directory
    if $JSON; then
        json_output "NOT_INITIALIZED" "beads_rust is installed but not initialized" \
            "{\"br_version\":\"$BR_VERSION\"}"
    else
        echo "NOT_INITIALIZED"
        if $VERBOSE; then
            echo ""
            echo "beads_rust ($BR_VERSION) is installed but not initialized."
            echo "Initialize with: br init"
        fi
    fi
    exit 2
fi

# .beads exists - check if migration needed
if [[ "$HAS_BD_CONFIG" == "true" ]] && [[ "$HAS_BR_CONFIG" == "false" ]]; then
    # Has bd config but not br-compatible database
    if $JSON; then
        json_output "MIGRATION_NEEDED" "Legacy bd data detected, migration required" \
            "{\"br_version\":\"$BR_VERSION\",\"bd_installed\":$BD_INSTALLED,\"has_jsonl\":$HAS_JSONL}"
    else
        echo "MIGRATION_NEEDED"
        if $VERBOSE; then
            echo ""
            echo "Legacy beads (bd) data detected in .beads/"
            echo "Migration required to use with beads_rust (br)"
            echo ""
            echo "Run migration:"
            echo "  .claude/scripts/beads/migrate-to-br.sh"
            echo ""
            echo "Or start fresh:"
            echo "  rm -rf .beads && br init"
        fi
    fi
    exit 3
fi

# Check if br can read the database
if ! br doctor &>/dev/null; then
    if $JSON; then
        json_output "MIGRATION_NEEDED" "Database schema incompatible with br" \
            "{\"br_version\":\"$BR_VERSION\",\"has_jsonl\":$HAS_JSONL}"
    else
        echo "MIGRATION_NEEDED"
        if $VERBOSE; then
            echo ""
            echo "The .beads/ database has an incompatible schema."
            echo "This may be from an older version of bd or br."
            echo ""
            echo "Run migration:"
            echo "  .claude/scripts/beads/migrate-to-br.sh"
            echo ""
            echo "Diagnostic:"
            br doctor 2>&1 || true
        fi
    fi
    exit 3
fi

# All good - br is ready
if $JSON; then
    STATS=$(br stats --json 2>/dev/null || echo '{}')
    json_output "READY" "beads_rust is installed and initialized" \
        "{\"br_version\":\"$BR_VERSION\",\"stats\":$STATS}"
else
    echo "READY"
    if $VERBOSE; then
        echo ""
        echo "beads_rust ($BR_VERSION) is installed and initialized."
        echo "Location: $(which br)"
        echo ""
        br stats 2>/dev/null || true
        echo ""
        echo "Quick commands:"
        echo "  br ready        # Find next actionable tasks"
        echo "  br list         # List all issues"
        echo "  br stats        # Show statistics"
        echo "  br sync         # Sync with git"
        if [[ "$BD_INSTALLED" == "true" ]]; then
            echo ""
            echo "Note: Legacy 'bd' is still installed. Consider uninstalling:"
            echo "  pip uninstall beads"
        fi
    fi
fi
exit 0
