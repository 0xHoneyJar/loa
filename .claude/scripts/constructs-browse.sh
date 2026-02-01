#!/usr/bin/env bash
# =============================================================================
# Loa Constructs - Browse Script
# =============================================================================
# Browse available packs from the Loa Constructs Registry.
#
# Usage:
#   constructs-browse.sh list              # List available packs (human readable)
#   constructs-browse.sh list --json       # List packs as JSON (for UI integration)
#   constructs-browse.sh info <slug>       # Show pack details
#   constructs-browse.sh search <query>    # Search packs by name/description
#
# Exit Codes:
#   0 = success
#   1 = authentication error
#   2 = network error
#   3 = not found
#   6 = general error
#
# Environment Variables:
#   LOA_CONSTRUCTS_API_KEY  - API key for authentication (optional for free packs)
#   LOA_REGISTRY_URL        - Override API URL
#
# Sources: GitHub Issue #77
# Updated: GitHub Issue #106 - API endpoint migration to /constructs
# =============================================================================

set -euo pipefail

# Get script directory for sourcing dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source shared library
if [[ -f "$SCRIPT_DIR/constructs-lib.sh" ]]; then
    source "$SCRIPT_DIR/constructs-lib.sh"
else
    echo "ERROR: constructs-lib.sh not found" >&2
    exit 6
fi

# =============================================================================
# Exit Codes
# =============================================================================

EXIT_SUCCESS=0
EXIT_AUTH_ERROR=1
EXIT_NETWORK_ERROR=2
EXIT_NOT_FOUND=3
EXIT_ERROR=6

# =============================================================================
# Cache Management
# =============================================================================

CACHE_DIR="${HOME}/.loa/cache/packs"
CACHE_TTL=3600  # 1 hour

# Ensure cache directory exists
ensure_cache_dir() {
    mkdir -p "$CACHE_DIR"
}

# Get cache file path for a key
get_cache_path() {
    local key="$1"
    echo "$CACHE_DIR/${key}.json"
}

# Check if cache is valid (exists and not expired)
is_cache_valid() {
    local cache_file="$1"
    
    if [[ ! -f "$cache_file" ]]; then
        return 1
    fi
    
    local file_age
    if [[ "$(uname)" == "Darwin" ]]; then
        # macOS
        file_age=$(( $(date +%s) - $(stat -f %m "$cache_file") ))
    else
        # Linux
        file_age=$(( $(date +%s) - $(stat -c %Y "$cache_file") ))
    fi
    
    [[ $file_age -lt $CACHE_TTL ]]
}

# =============================================================================
# API Functions
# =============================================================================

# Fetch packs list from registry
# Uses unified /constructs endpoint with type=pack filter
# @see issue #106: API endpoint migration
fetch_packs() {
    local registry_url
    registry_url=$(get_registry_url)

    local api_key
    api_key=$(get_api_key 2>/dev/null || echo "")

    local cache_file
    cache_file=$(get_cache_path "packs-list")

    # Try cache first
    if is_cache_valid "$cache_file"; then
        cat "$cache_file"
        return 0
    fi

    # Fetch from API - use unified /constructs endpoint
    local curl_args=(-s -f)
    if [[ -n "$api_key" ]]; then
        curl_args+=(-H "Authorization: Bearer $api_key")
    fi

    local response http_code
    # Capture both response and HTTP code
    response=$(curl "${curl_args[@]}" -w "\n%{http_code}" "${registry_url}/constructs?type=pack" 2>/dev/null) || true
    http_code=$(echo "$response" | tail -n1)
    response=$(echo "$response" | sed '$d')

    # Check for successful response
    if [[ "$http_code" == "200" ]] && [[ -n "$response" ]]; then
        # Verify it's valid JSON with data array
        if echo "$response" | jq -e '.data' &>/dev/null; then
            # Cache the response
            ensure_cache_dir
            echo "$response" > "$cache_file"
            echo "$response"
            return 0
        fi
    fi

    # Check for specific error codes
    local error_code
    error_code=$(echo "$response" | jq -r '.error.code // empty' 2>/dev/null)

    if [[ "$error_code" == "INTERNAL_ERROR" ]]; then
        echo "ERROR: Registry service temporarily unavailable" >&2
    elif [[ "$error_code" == "NOT_FOUND" ]]; then
        echo "ERROR: Registry endpoint not found (API may have changed)" >&2
    elif [[ -n "$error_code" ]]; then
        echo "ERROR: Registry returned: $error_code" >&2
    fi

    # Network or API error - try cache even if expired
    if [[ -f "$cache_file" ]]; then
        echo "  Using cached data..." >&2
        cat "$cache_file"
        return 0
    fi

    return $EXIT_NETWORK_ERROR
}

# Fetch single pack info
# Uses unified /constructs/:slug endpoint
# @see issue #106: API endpoint migration
fetch_pack_info() {
    local slug="$1"
    local registry_url
    registry_url=$(get_registry_url)

    local api_key
    api_key=$(get_api_key 2>/dev/null || echo "")

    local curl_args=(-s -f)
    if [[ -n "$api_key" ]]; then
        curl_args+=(-H "Authorization: Bearer $api_key")
    fi

    local response http_code
    response=$(curl "${curl_args[@]}" -w "\n%{http_code}" "${registry_url}/constructs/${slug}" 2>/dev/null) || true
    http_code=$(echo "$response" | tail -n1)
    response=$(echo "$response" | sed '$d')

    if [[ "$http_code" == "200" ]] && [[ -n "$response" ]]; then
        echo "$response"
        return 0
    fi

    # Handle errors gracefully
    local error_code
    error_code=$(echo "$response" | jq -r '.error.code // empty' 2>/dev/null)

    if [[ "$error_code" == "NOT_FOUND" ]]; then
        return $EXIT_NOT_FOUND
    elif [[ "$error_code" == "INTERNAL_ERROR" ]]; then
        echo "ERROR: Registry service temporarily unavailable" >&2
        return $EXIT_NETWORK_ERROR
    fi

    return $EXIT_NOT_FOUND
}

# =============================================================================
# Output Formatting
# =============================================================================

# Format packs list for human reading
format_packs_human() {
    local packs_json="$1"
    
    echo ""
    echo "╭───────────────────────────────────────────────────────────────╮"
    echo "│  LOA CONSTRUCTS REGISTRY                                      │"
    echo "╰───────────────────────────────────────────────────────────────╯"
    echo ""
    
    # Parse and display each pack
    # API returns { data: [...], pagination: {...} } envelope
    echo "$packs_json" | jq -r '.data[]? | "\(.icon // "📦") \(.name) (\(.skills_count // .skills | length // 0) skills) - \(.tier_required // .tier // "free")\n   \(.description)\n"' 2>/dev/null || {
        echo "No packs available or error parsing response"
        return 1
    }
}

# Format packs as JSON for UI integration
format_packs_json() {
    local packs_json="$1"
    
    # Normalize to array format expected by UI
    # API returns { data: [...], pagination: {...} } envelope
    echo "$packs_json" | jq '[
        .data[]? | {
            slug: .slug,
            name: .name,
            description: .description,
            skills_count: (.skills_count // (.skills | length?) // 0),
            tier: (.tier_required // .tier // "free"),
            icon: (.icon // "📦"),
            version: (.latest_version.version // .version // "1.0.0")
        }
    ]' 2>/dev/null || echo "[]"
}

# =============================================================================
# Commands
# =============================================================================

cmd_list() {
    local json_output=false

    # Parse args
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json|-j)
                json_output=true
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    local packs_json
    if ! packs_json=$(fetch_packs 2>&1); then
        # fetch_packs already printed specific error messages
        if [[ "$json_output" == true ]]; then
            echo "[]"
        else
            echo ""
            echo "╭───────────────────────────────────────────────────────────────╮"
            echo "│  LOA CONSTRUCTS REGISTRY                                      │"
            echo "╰───────────────────────────────────────────────────────────────╯"
            echo ""
            echo "  Registry unavailable. Please try again later."
            echo ""
            echo "  If this persists, check:"
            echo "    - https://status.constructs.network (if available)"
            echo "    - https://github.com/0xHoneyJar/loa-constructs/issues"
            echo ""
        fi
        return $EXIT_NETWORK_ERROR
    fi

    if [[ "$json_output" == true ]]; then
        format_packs_json "$packs_json"
    else
        format_packs_human "$packs_json"
    fi
}

cmd_info() {
    local slug="${1:-}"
    
    if [[ -z "$slug" ]]; then
        echo "ERROR: Pack slug required" >&2
        echo "Usage: constructs-browse.sh info <slug>" >&2
        return $EXIT_ERROR
    fi
    
    local pack_json
    if ! pack_json=$(fetch_pack_info "$slug"); then
        echo "ERROR: Pack '$slug' not found" >&2
        return $EXIT_NOT_FOUND
    fi
    
    echo ""
    # API returns { data: {...} } envelope for single pack
    echo "$pack_json" | jq -r '.data | "╭───────────────────────────────────────────────────────────────╮
│  \(.icon // "📦") \(.name)
╰───────────────────────────────────────────────────────────────╯

\(.description)

Version: \(.latest_version.version // .version // "1.0.0")
Tier: \(.tier_required // .tier // "free")
Downloads: \(.downloads // 0)

\(if .latest_version.changelog then "Changelog: \(.latest_version.changelog)" else "" end)"' 2>/dev/null
}

cmd_search() {
    local query="${1:-}"

    if [[ -z "$query" ]]; then
        # No query = list all
        cmd_list
        return
    fi

    local packs_json
    if ! packs_json=$(fetch_packs 2>&1); then
        echo "ERROR: Could not fetch packs from registry" >&2
        return $EXIT_NETWORK_ERROR
    fi

    # Filter packs by query (case-insensitive)
    # API returns { data: [...], pagination: {...} } envelope
    local query_lower
    query_lower=$(echo "$query" | tr '[:upper:]' '[:lower:]')

    local filtered
    filtered=$(echo "$packs_json" | jq --arg q "$query_lower" '[
        .data[]? |
        select(
            (.name | ascii_downcase | contains($q)) or
            (.description | ascii_downcase | contains($q)) or
            (.slug | ascii_downcase | contains($q))
        )
    ]')

    if [[ "$(echo "$filtered" | jq 'length')" == "0" ]]; then
        echo "No packs matching '$query'" >&2
        return $EXIT_NOT_FOUND
    fi

    format_packs_human "{\"data\": $filtered}"
}

# =============================================================================
# Main
# =============================================================================

show_help() {
    cat << 'HELP'
Loa Constructs Browser

Usage:
  constructs-browse.sh list [--json]    List available packs
  constructs-browse.sh info <slug>      Show pack details
  constructs-browse.sh search <query>   Search packs

Options:
  --json, -j    Output in JSON format (for UI integration)

Examples:
  constructs-browse.sh list
  constructs-browse.sh list --json
  constructs-browse.sh info observer
  constructs-browse.sh search validation
HELP
}

main() {
    local cmd="${1:-list}"
    shift || true
    
    case "$cmd" in
        list)
            cmd_list "$@"
            ;;
        info)
            cmd_info "$@"
            ;;
        search)
            cmd_search "$@"
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            echo "Unknown command: $cmd" >&2
            show_help >&2
            exit $EXIT_ERROR
            ;;
    esac
}

main "$@"
