#!/bin/bash
# validate-mcp.sh
# Purpose: Validate that required MCP servers are configured
# Usage: ./validate-mcp.sh server1 [server2 ...]
#
# Exit codes:
#   0 - All servers configured
#   1 - One or more servers missing
#
# Output:
#   OK                    - All servers configured
#   MISSING:server1,srv2  - Listed servers not configured
#   NO_SETTINGS_FILE      - Settings file doesn't exist

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETTINGS="${SCRIPT_DIR}/../settings.local.json"

# Check for arguments
if [ $# -eq 0 ]; then
    echo "Usage: $0 server1 [server2 ...]" >&2
    echo "" >&2
    echo "Examples:" >&2
    echo "  $0 linear" >&2
    echo "  $0 github vercel" >&2
    exit 1
fi

# Check if settings file exists
if [ ! -f "$SETTINGS" ]; then
    echo "NO_SETTINGS_FILE"
    exit 1
fi

# Check each server
MISSING=()
for SERVER in "$@"; do
    if ! grep -q "\"${SERVER}\"" "$SETTINGS" 2>/dev/null; then
        MISSING+=("$SERVER")
    fi
done

# Report results
if [ ${#MISSING[@]} -gt 0 ]; then
    # Join array with commas
    MISSING_STR=$(IFS=,; echo "${MISSING[*]}")
    echo "MISSING:${MISSING_STR}"
    exit 1
fi

echo "OK"
exit 0
