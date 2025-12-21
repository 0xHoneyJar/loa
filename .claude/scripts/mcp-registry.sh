#!/bin/bash
# mcp-registry.sh
# Purpose: Query and validate MCP registry
# Usage: ./mcp-registry.sh <command> [args]
#
# Commands:
#   list              - List all available servers
#   info <server>     - Get details about a server
#   required-by <srv> - Find what requires a server
#   check <server>    - Check if server is configured
#   group <name>      - List servers in a group
#   groups            - List all available groups
#   setup <server>    - Get setup instructions for a server

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGISTRY="${SCRIPT_DIR}/../mcp-registry.yaml"
SETTINGS="${SCRIPT_DIR}/../settings.local.json"

# Check if registry exists
if [ ! -f "$REGISTRY" ]; then
    echo "ERROR: MCP registry not found at $REGISTRY" >&2
    exit 1
fi

# Simple YAML parser for basic queries (no external dependencies)
# Returns lines matching a key pattern
yaml_get_section() {
    local key="$1"
    local in_section=false
    local indent=""

    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*${key}:[[:space:]]* ]]; then
            in_section=true
            indent=$(echo "$line" | sed 's/[^ ].*//')
            continue
        fi

        if $in_section; then
            # Check if we've left the section (less or equal indent with content)
            local current_indent=$(echo "$line" | sed 's/[^ ].*//')
            if [[ -n "${line// /}" && "${#current_indent}" -le "${#indent}" && ! "$line" =~ ^[[:space:]]*$ ]]; then
                break
            fi
            echo "$line"
        fi
    done < "$REGISTRY"
}

# Get value for a simple key: value pair
yaml_get_value() {
    local key="$1"
    grep -E "^[[:space:]]*${key}:" "$REGISTRY" | head -1 | sed "s/.*${key}:[[:space:]]*//" | tr -d '"'
}

# List all server names
list_servers() {
    echo "Available MCP Servers:"
    echo ""

    # Find servers section and list server names (2-space indented keys under "servers:")
    local in_servers=false
    while IFS= read -r line; do
        if [[ "$line" == "servers:" ]]; then
            in_servers=true
            continue
        fi

        # Stop at groups section or other top-level key
        if $in_servers && [[ "$line" =~ ^[a-z]+: && ! "$line" =~ ^[[:space:]] ]]; then
            break
        fi

        # Server names are 2-space indented
        if $in_servers && [[ "$line" =~ ^[[:space:]]{2}[a-z][a-z0-9-]*:[[:space:]]*$ ]]; then
            server=$(echo "$line" | cut -d: -f1 | tr -d ' ')
            # Get description from next few lines
            desc=$(grep -A 2 "^  ${server}:" "$REGISTRY" | grep "description:" | sed 's/.*description:[[:space:]]*//' | tr -d '"')
            printf "  %-15s %s\n" "$server" "$desc"
        fi
    done < "$REGISTRY"
}

# Get info about a specific server
get_server_info() {
    local server="$1"

    if ! grep -q "^  ${server}:" "$REGISTRY"; then
        echo "ERROR: Server '$server' not found in registry" >&2
        exit 1
    fi

    echo "=== $server ==="
    echo ""

    # Get basic info
    local name=$(grep -A 1 "^  ${server}:" "$REGISTRY" | grep "name:" | sed 's/.*name:[[:space:]]*//' | tr -d '"')
    local desc=$(grep -A 2 "^  ${server}:" "$REGISTRY" | grep "description:" | sed 's/.*description:[[:space:]]*//' | tr -d '"')
    local url=$(grep -A 3 "^  ${server}:" "$REGISTRY" | grep "url:" | sed 's/.*url:[[:space:]]*//' | tr -d '"')
    local docs=$(grep -A 4 "^  ${server}:" "$REGISTRY" | grep "docs:" | sed 's/.*docs:[[:space:]]*//' | tr -d '"')

    echo "Name: $name"
    echo "Description: $desc"
    echo "URL: $url"
    echo "Docs: $docs"
    echo ""

    # Get scopes - stop at required_by section
    echo "Scopes:"
    local in_scopes=false
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]{4}scopes: ]]; then
            in_scopes=true
            continue
        fi

        if $in_scopes; then
            # Stop at next section (required_by, setup, etc.)
            if [[ "$line" =~ ^[[:space:]]{4}[a-z_]+: && ! "$line" =~ ^[[:space:]]{6} ]]; then
                break
            fi

            # Parse scope lines (6-space indented with -)
            if [[ "$line" =~ ^[[:space:]]{6}-[[:space:]] ]]; then
                scope=$(echo "$line" | sed 's/.*- //' | cut -d'#' -f1 | tr -d ' ')
                comment=$(echo "$line" | grep '#' | sed 's/.*# //' || true)
                if [ -n "$comment" ]; then
                    printf "  - %-12s # %s\n" "$scope" "$comment"
                else
                    echo "  - $scope"
                fi
            fi
        fi
    done < <(grep -A 30 "^  ${server}:" "$REGISTRY")
    echo ""

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

    if ! grep -q "^  ${server}:" "$REGISTRY"; then
        echo "ERROR: Server '$server' not found in registry" >&2
        exit 1
    fi

    echo "=== Setup Instructions for $server ==="
    echo ""

    # Get steps
    echo "Steps:"
    grep -A 50 "^  ${server}:" "$REGISTRY" | grep -A 20 "setup:" | grep -A 10 "steps:" | grep "^        - " | while read -r line; do
        step=$(echo "$line" | sed 's/.*- "//' | tr -d '"')
        echo "  $step"
    done
    echo ""

    # Get env vars
    echo "Environment Variables:"
    grep -A 50 "^  ${server}:" "$REGISTRY" | grep -A 20 "setup:" | grep -A 5 "env_vars:" | grep "^        - " | while read -r line; do
        var=$(echo "$line" | sed 's/.*- //')
        echo "  - $var"
    done
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

    if ! grep -q "^  ${group}:" "$REGISTRY"; then
        echo "ERROR: Group '$group' not found in registry" >&2
        exit 1
    fi

    # Get group description
    local desc=$(grep -A 2 "^  ${group}:" "$REGISTRY" | grep "description:" | sed 's/.*description:[[:space:]]*//' | tr -d '"')
    echo "Group: $group"
    echo "Description: $desc"
    echo ""
    echo "Servers:"

    # Parse servers list - stop at next group
    local in_servers=false
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]{4}servers: ]]; then
            in_servers=true
            continue
        fi

        if $in_servers; then
            # Stop at next section (another 2-space indented key)
            if [[ "$line" =~ ^[[:space:]]{2}[a-z]+: && ! "$line" =~ ^[[:space:]]{4} ]]; then
                break
            fi

            # Server lines are 6-space indented
            if [[ "$line" =~ ^[[:space:]]{6}-[[:space:]] ]]; then
                server=$(echo "$line" | sed 's/.*- //')
                echo "  - $server"
            fi
        fi
    done < <(grep -A 15 "^  ${group}:" "$REGISTRY")
}

# List all groups
list_groups() {
    echo "Available MCP Groups:"
    echo ""

    # Find the groups section and list group names
    local in_groups=false
    while IFS= read -r line; do
        if [[ "$line" == "groups:" ]]; then
            in_groups=true
            continue
        fi

        if $in_groups; then
            if [[ "$line" =~ ^[[:space:]]{2}[a-z]+: ]]; then
                group=$(echo "$line" | cut -d: -f1 | tr -d ' ')
                # Get description from next line
                desc=$(grep -A 1 "^  ${group}:" "$REGISTRY" | grep "description:" | sed 's/.*description:[[:space:]]*//' | tr -d '"')
                printf "  %-15s %s\n" "$group" "$desc"
            fi
        fi
    done < "$REGISTRY"
}

# Find what requires a server
required_by() {
    local server="$1"

    if ! grep -q "^  ${server}:" "$REGISTRY"; then
        echo "ERROR: Server '$server' not found in registry" >&2
        exit 1
    fi

    echo "=== What requires $server ==="
    echo ""

    # Parse required_by section
    local in_required=false
    local in_server=false

    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]{2}${server}: ]]; then
            in_server=true
            continue
        fi

        if $in_server && [[ "$line" =~ ^[[:space:]]{4}required_by: ]]; then
            in_required=true
            continue
        fi

        if $in_server && $in_required; then
            # Exit if we hit another top-level key
            if [[ "$line" =~ ^[[:space:]]{4}[a-z]+: && ! "$line" =~ ^[[:space:]]{6} ]]; then
                break
            fi

            if [[ "$line" =~ ^[[:space:]]{6}- ]]; then
                # Extract command or skill
                if [[ "$line" =~ command: ]]; then
                    cmd=$(echo "$line" | sed 's/.*command:[[:space:]]*//' | tr -d '"')
                    echo "Command: $cmd"
                elif [[ "$line" =~ skill: ]]; then
                    skill=$(echo "$line" | sed 's/.*skill:[[:space:]]*//' | tr -d '"')
                    echo "Skill: $skill"
                fi
            elif [[ "$line" =~ reason: ]]; then
                reason=$(echo "$line" | sed 's/.*reason:[[:space:]]*//' | tr -d '"')
                echo "  Reason: $reason"
            elif [[ "$line" =~ required: ]]; then
                req=$(echo "$line" | sed 's/.*required:[[:space:]]*//' | tr -d '"')
                echo "  Required: $req"
                echo ""
            fi
        fi

        # Exit server section if we hit another server
        if $in_server && [[ "$line" =~ ^[[:space:]]{2}[a-z]+: && ! "$line" =~ ^[[:space:]]{4} ]]; then
            break
        fi
    done < "$REGISTRY"
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

    required-by)
        if [ -z "${2:-}" ]; then
            echo "Usage: $0 required-by <server-name>" >&2
            exit 1
        fi
        required_by "$2"
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
        echo "Commands:"
        echo "  list              List all available MCP servers"
        echo "  info <server>     Get detailed info about a server"
        echo "  setup <server>    Get setup instructions for a server"
        echo "  check <server>    Check if server is configured"
        echo "  required-by <srv> Find what commands/skills require a server"
        echo "  group <name>      List servers in a group"
        echo "  groups            List all available groups"
        echo ""
        echo "Examples:"
        echo "  $0 list"
        echo "  $0 info linear"
        echo "  $0 setup github"
        echo "  $0 check vercel"
        echo "  $0 group essential"
        exit 1
        ;;
esac
