#!/bin/bash
# mcp-registry.sh
# Purpose: Query MCP server registry using yq
# Usage: ./mcp-registry.sh <command> [args]
#
# Requires: yq (https://github.com/mikefarah/yq)
# Install: brew install yq / apt install yq / go install github.com/mikefarah/yq/v4@latest
#
# Commands:
#   list              - List all available servers
#   info <server>     - Get details about a server
#   setup <server>    - Get setup instructions
#   check <server>    - Check if server is configured
#   group <name>      - List servers in a group
#   groups            - List all available groups

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGISTRY="${SCRIPT_DIR}/../mcp-registry.yaml"
SETTINGS="${SCRIPT_DIR}/../settings.local.json"

# Check for yq
if ! command -v yq &> /dev/null; then
    echo "ERROR: yq is required but not installed." >&2
    echo "" >&2
    echo "Install yq:" >&2
    echo "  macOS:  brew install yq" >&2
    echo "  Ubuntu: sudo apt install yq" >&2
    echo "  Go:     go install github.com/mikefarah/yq/v4@latest" >&2
    exit 1
fi

# Check if registry exists
if [ ! -f "$REGISTRY" ]; then
    echo "ERROR: MCP registry not found at $REGISTRY" >&2
    exit 1
fi

# List all server names with descriptions
list_servers() {
    echo "Available MCP Servers:"
    echo ""
    yq -r '.servers | to_entries | .[] | "  \(.key)\t\(.value.description)"' "$REGISTRY" | column -t -s $'\t'
}

# Get info about a specific server
get_server_info() {
    local server="$1"

    if ! yq -e ".servers.${server}" "$REGISTRY" &>/dev/null; then
        echo "ERROR: Server '$server' not found in registry" >&2
        exit 1
    fi

    echo "=== $server ==="
    echo ""
    yq -r ".servers.${server} | \"Name: \(.name)\nDescription: \(.description)\nURL: \(.url)\nDocs: \(.docs)\"" "$REGISTRY"
    echo ""

    echo "Scopes:"
    yq -r ".servers.${server}.scopes[] | \"  - \" + ." "$REGISTRY"
    echo ""

    # Check if configured
    echo -n "Status: "
    if [ -f "$SETTINGS" ]; then
        if grep -q "\"${server}\"" "$SETTINGS" 2>/dev/null; then
            echo "CONFIGURED"
        else
            echo "NOT CONFIGURED"
        fi
    else
        echo "NO SETTINGS FILE"
    fi
}

# Get setup instructions for a server
get_setup_instructions() {
    local server="$1"

    if ! yq -e ".servers.${server}" "$REGISTRY" &>/dev/null; then
        echo "ERROR: Server '$server' not found in registry" >&2
        exit 1
    fi

    echo "=== Setup Instructions for $server ==="
    echo ""

    echo "Steps:"
    yq -r ".servers.${server}.setup.steps[] | \"  - \" + ." "$REGISTRY"
    echo ""

    echo "Environment Variables:"
    yq -r ".servers.${server}.setup.env_vars[] | \"  - \" + ." "$REGISTRY"
    echo ""

    echo "Example Configuration:"
    yq -r ".servers.${server}.setup.config_example" "$REGISTRY"
}

# Check if server is configured
check_server() {
    local server="$1"

    if [ ! -f "$SETTINGS" ]; then
        echo "NO_SETTINGS_FILE"
        exit 1
    fi

    if grep -q "\"${server}\"" "$SETTINGS" 2>/dev/null; then
        echo "CONFIGURED"
        exit 0
    else
        echo "NOT_CONFIGURED"
        exit 1
    fi
}

# List servers in a group
list_group() {
    local group="$1"

    if ! yq -e ".groups.${group}" "$REGISTRY" &>/dev/null; then
        echo "ERROR: Group '$group' not found in registry" >&2
        exit 1
    fi

    echo "Group: $group"
    yq -r ".groups.${group}.description | \"Description: \" + ." "$REGISTRY"
    echo ""
    echo "Servers:"
    yq -r ".groups.${group}.servers[] | \"  - \" + ." "$REGISTRY"
}

# List all groups
list_groups() {
    echo "Available MCP Groups:"
    echo ""
    yq -r '.groups | to_entries | .[] | "  \(.key)\t\(.value.description)"' "$REGISTRY" | column -t -s $'\t'
}

# Main command handler
case "${1:-}" in
    list)
        list_servers
        ;;

    info)
        if [ -z "${2:-}" ]; then
            echo "Usage: $0 info <server-name>" >&2
            exit 1
        fi
        get_server_info "$2"
        ;;

    setup)
        if [ -z "${2:-}" ]; then
            echo "Usage: $0 setup <server-name>" >&2
            exit 1
        fi
        get_setup_instructions "$2"
        ;;

    check)
        if [ -z "${2:-}" ]; then
            echo "Usage: $0 check <server-name>" >&2
            exit 1
        fi
        check_server "$2"
        ;;

    group)
        if [ -z "${2:-}" ]; then
            echo "Usage: $0 group <group-name>" >&2
            exit 1
        fi
        list_group "$2"
        ;;

    groups)
        list_groups
        ;;

    *)
        echo "MCP Registry Query Tool"
        echo ""
        echo "Usage: $0 <command> [args]"
        echo ""
        echo "Requires: yq (https://github.com/mikefarah/yq)"
        echo ""
        echo "Commands:"
        echo "  list              List all available MCP servers"
        echo "  info <server>     Get detailed info about a server"
        echo "  setup <server>    Get setup instructions for a server"
        echo "  check <server>    Check if server is configured"
        echo "  group <name>      List servers in a group"
        echo "  groups            List all available groups"
        echo ""
        echo "Examples:"
        echo "  $0 list"
        echo "  $0 info linear"
        echo "  $0 setup github"
        echo "  $0 group essential"
        exit 1
        ;;
esac
