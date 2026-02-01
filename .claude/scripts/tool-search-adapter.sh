#!/usr/bin/env bash
# Tool Search Adapter - Search and discover MCP tools and Loa Constructs
# Part of the Loa framework's Claude Platform Integration
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Allow environment variable overrides for testing
MCP_REGISTRY="${MCP_REGISTRY:-${SCRIPT_DIR}/../mcp-registry.yaml}"
SETTINGS_FILE="${SETTINGS_FILE:-${SCRIPT_DIR}/../settings.local.json}"
CONSTRUCTS_DIR="${CONSTRUCTS_DIR:-${SCRIPT_DIR}/../constructs}"
CONFIG_FILE="${CONFIG_FILE:-${SCRIPT_DIR}/../../.loa.config.yaml}"

# Cache configuration
DEFAULT_CACHE_DIR="${LOA_CACHE_DIR:-${HOME}/.loa/cache/tool-search}"
DEFAULT_CACHE_TTL_HOURS=24

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

#######################################
# Print usage information
#######################################
usage() {
    cat << EOF
Usage: $(basename "$0") <command> [options]

Commands:
  search <query>      Search for tools by name, description, or scope
  discover            Auto-discover available (configured) tools
  cache <action>      Manage search result cache

Options for 'search':
  --json              Output results as JSON
  --limit N           Limit results (default: 10)
  --include-unconfigured  Include tools that are not configured

Options for 'discover':
  --json              Output results as JSON
  --refresh           Force refresh (ignore cache)

Options for 'cache':
  list                Show cached entries
  clear               Remove all cached entries
  clear <query>       Remove specific cached entry

Global Options:
  --help              Show this help message

Configuration (in .loa.config.yaml):
  tool_search.enabled           Enable/disable tool search (default: true)
  tool_search.auto_discover     Auto-discover on startup (default: true)
  tool_search.cache_ttl_hours   Cache TTL in hours (default: 24)
  tool_search.include_constructs Include Loa Constructs (default: true)

Examples:
  $(basename "$0") search "github"
  $(basename "$0") search "issue tracking" --json
  $(basename "$0") discover --refresh
  $(basename "$0") cache list
  $(basename "$0") cache clear
EOF
}

#######################################
# Print colored output
#######################################
print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

#######################################
# Check dependencies
#######################################
check_dependencies() {
    local missing=()

    if ! command -v yq &>/dev/null; then
        missing+=("yq")
    fi

    if ! command -v jq &>/dev/null; then
        missing+=("jq")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        print_error "Missing dependencies: ${missing[*]}"
        echo ""
        echo "Install with:"
        echo "  macOS:  brew install ${missing[*]}"
        echo "  Ubuntu: sudo apt install ${missing[*]}"
        return 1
    fi

    return 0
}

#######################################
# Get configuration value
# Handles booleans (false is a valid value, not empty)
#######################################
get_config() {
    local key="$1"
    local default="${2:-}"

    if [[ -f "$CONFIG_FILE" ]] && command -v yq &>/dev/null; then
        local value
        # Use select to check if key exists, then get value
        # This handles boolean false correctly (doesn't treat as empty)
        local exists
        exists=$(yq -r ".$key | type" "$CONFIG_FILE" 2>/dev/null || echo "null")
        if [[ "$exists" != "null" ]]; then
            value=$(yq -r ".$key" "$CONFIG_FILE" 2>/dev/null || echo "")
            if [[ "$value" != "null" ]]; then
                echo "$value"
                return 0
            fi
        fi
    fi

    echo "$default"
}

#######################################
# Check if tool search is enabled
#######################################
is_enabled() {
    local enabled
    enabled=$(get_config "tool_search.enabled" "true")
    [[ "$enabled" == "true" ]]
}

#######################################
# Get cache directory
#######################################
get_cache_dir() {
    local cache_dir
    cache_dir=$(get_config "tool_search.cache_dir" "$DEFAULT_CACHE_DIR")
    echo "$cache_dir"
}

#######################################
# Get cache TTL in seconds
#######################################
get_cache_ttl_seconds() {
    local ttl_hours
    ttl_hours=$(get_config "tool_search.cache_ttl_hours" "$DEFAULT_CACHE_TTL_HOURS")
    echo $((ttl_hours * 3600))
}

#######################################
# Initialize cache directory
#######################################
init_cache() {
    local cache_dir
    cache_dir=$(get_cache_dir)
    mkdir -p "$cache_dir"
}

#######################################
# Get cache file path for a query
#######################################
get_cache_path() {
    local query="$1"
    local cache_dir
    cache_dir=$(get_cache_dir)

    # Hash the query for safe filename
    local hash
    hash=$(echo -n "$query" | md5sum | cut -d' ' -f1)
    echo "${cache_dir}/${hash}.json"
}

#######################################
# Check if cache entry is valid
#######################################
is_cache_valid() {
    local cache_file="$1"

    if [[ ! -f "$cache_file" ]]; then
        return 1
    fi

    local ttl_seconds
    ttl_seconds=$(get_cache_ttl_seconds)

    local file_age
    file_age=$(($(date +%s) - $(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file")))

    [[ $file_age -lt $ttl_seconds ]]
}

#######################################
# Write to cache
#######################################
write_cache() {
    local query="$1"
    local data="$2"

    init_cache
    local cache_file
    cache_file=$(get_cache_path "$query")

    # Store with metadata
    jq -n \
        --arg query "$query" \
        --arg timestamp "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
        --argjson results "$data" \
        '{query: $query, timestamp: $timestamp, results: $results}' > "$cache_file"
}

#######################################
# Read from cache
#######################################
read_cache() {
    local query="$1"
    local cache_file
    cache_file=$(get_cache_path "$query")

    if is_cache_valid "$cache_file"; then
        jq -r '.results' "$cache_file"
        return 0
    fi

    return 1
}

#######################################
# Check if server is configured
#######################################
is_server_configured() {
    local server="$1"

    if [[ ! -f "$SETTINGS_FILE" ]]; then
        return 1
    fi

    grep -q "\"${server}\"" "$SETTINGS_FILE" 2>/dev/null
}

#######################################
# Search MCP registry
#######################################
search_mcp_registry() {
    local query="$1"
    local include_unconfigured="${2:-false}"

    if [[ ! -f "$MCP_REGISTRY" ]]; then
        echo "[]"
        return 0
    fi

    local results="[]"
    local query_lower
    query_lower=$(echo "$query" | tr '[:upper:]' '[:lower:]')

    # Get all servers
    local servers
    servers=$(yq -r '.servers | keys | .[]' "$MCP_REGISTRY" 2>/dev/null || echo "")

    for server in $servers; do
        local name description scopes
        name=$(yq -r ".servers.[\"${server}\"].name // \"$server\"" "$MCP_REGISTRY" 2>/dev/null || echo "$server")
        description=$(yq -r ".servers.[\"${server}\"].description // \"\"" "$MCP_REGISTRY" 2>/dev/null || echo "")
        scopes=$(yq -r ".servers.[\"${server}\"].scopes // [] | join(\",\")" "$MCP_REGISTRY" 2>/dev/null || echo "")

        local name_lower desc_lower scopes_lower
        name_lower=$(echo "$name" | tr '[:upper:]' '[:lower:]')
        desc_lower=$(echo "$description" | tr '[:upper:]' '[:lower:]')
        scopes_lower=$(echo "$scopes" | tr '[:upper:]' '[:lower:]')

        # Calculate relevance score
        local score=0

        # Name match (highest weight)
        if [[ "$name_lower" == *"$query_lower"* ]]; then
            score=$((score + 100))
        fi

        # Server key match
        if [[ "$server" == *"$query_lower"* ]]; then
            score=$((score + 80))
        fi

        # Description match
        if [[ "$desc_lower" == *"$query_lower"* ]]; then
            score=$((score + 50))
        fi

        # Scope match
        if [[ "$scopes_lower" == *"$query_lower"* ]]; then
            score=$((score + 30))
        fi

        # Skip if no match (unless empty query)
        if [[ $score -eq 0 && -n "$query" ]]; then
            continue
        fi

        # Check if configured
        local configured="false"
        if is_server_configured "$server"; then
            configured="true"
        fi

        # Skip unconfigured if not requested
        if [[ "$include_unconfigured" != "true" && "$configured" != "true" && -n "$query" ]]; then
            continue
        fi

        # Build result entry
        local entry
        entry=$(jq -n \
            --arg id "$server" \
            --arg name "$name" \
            --arg description "$description" \
            --arg source "mcp" \
            --argjson score "$score" \
            --argjson configured "$configured" \
            '{id: $id, name: $name, description: $description, source: $source, score: $score, configured: $configured}'
        )

        results=$(echo "$results" | jq --argjson entry "$entry" '. + [$entry]')
    done

    # Sort by score descending
    echo "$results" | jq 'sort_by(-.score)'
}

#######################################
# Search Loa Constructs
#######################################
search_constructs() {
    local query="$1"

    local include_constructs
    include_constructs=$(get_config "tool_search.include_constructs" "true")

    if [[ "$include_constructs" != "true" ]]; then
        echo "[]"
        return 0
    fi

    if [[ ! -d "$CONSTRUCTS_DIR" ]]; then
        echo "[]"
        return 0
    fi

    local results="[]"
    local query_lower
    query_lower=$(echo "$query" | tr '[:upper:]' '[:lower:]')

    # Search skills in constructs
    if [[ -d "${CONSTRUCTS_DIR}/skills" ]]; then
        for vendor_dir in "${CONSTRUCTS_DIR}/skills"/*; do
            [[ -d "$vendor_dir" ]] || continue

            for skill_dir in "$vendor_dir"/*; do
                [[ -d "$skill_dir" ]] || continue

                local index_file="${skill_dir}/index.yaml"
                [[ -f "$index_file" ]] || continue

                local name description
                name=$(yq -r '.name // ""' "$index_file" 2>/dev/null || echo "")
                description=$(yq -r '.description // ""' "$index_file" 2>/dev/null || echo "")

                local name_lower desc_lower
                name_lower=$(echo "$name" | tr '[:upper:]' '[:lower:]')
                desc_lower=$(echo "$description" | tr '[:upper:]' '[:lower:]')

                local score=0

                if [[ "$name_lower" == *"$query_lower"* ]]; then
                    score=$((score + 100))
                fi

                if [[ "$desc_lower" == *"$query_lower"* ]]; then
                    score=$((score + 50))
                fi

                if [[ $score -eq 0 && -n "$query" ]]; then
                    continue
                fi

                local skill_id
                skill_id=$(basename "$skill_dir")
                local vendor
                vendor=$(basename "$vendor_dir")

                local entry
                entry=$(jq -n \
                    --arg id "${vendor}/${skill_id}" \
                    --arg name "$name" \
                    --arg description "$description" \
                    --arg source "constructs" \
                    --argjson score "$score" \
                    --argjson configured true \
                    '{id: $id, name: $name, description: $description, source: $source, score: $score, configured: $configured}'
                )

                results=$(echo "$results" | jq --argjson entry "$entry" '. + [$entry]')
            done
        done
    fi

    # Search packs
    if [[ -d "${CONSTRUCTS_DIR}/packs" ]]; then
        for pack_dir in "${CONSTRUCTS_DIR}/packs"/*; do
            [[ -d "$pack_dir" ]] || continue

            local manifest="${pack_dir}/manifest.json"
            [[ -f "$manifest" ]] || continue

            local name description
            name=$(jq -r '.name // ""' "$manifest" 2>/dev/null || echo "")
            description=$(jq -r '.description // ""' "$manifest" 2>/dev/null || echo "")

            local name_lower desc_lower
            name_lower=$(echo "$name" | tr '[:upper:]' '[:lower:]')
            desc_lower=$(echo "$description" | tr '[:upper:]' '[:lower:]')

            local score=0

            if [[ "$name_lower" == *"$query_lower"* ]]; then
                score=$((score + 100))
            fi

            if [[ "$desc_lower" == *"$query_lower"* ]]; then
                score=$((score + 50))
            fi

            if [[ $score -eq 0 && -n "$query" ]]; then
                continue
            fi

            local pack_id
            pack_id=$(basename "$pack_dir")

            local entry
            entry=$(jq -n \
                --arg id "pack:${pack_id}" \
                --arg name "$name" \
                --arg description "$description" \
                --arg source "constructs-pack" \
                --argjson score "$score" \
                --argjson configured true \
                '{id: $id, name: $name, description: $description, source: $source, score: $score, configured: $configured}'
            )

            results=$(echo "$results" | jq --argjson entry "$entry" '. + [$entry]')
        done
    fi

    echo "$results" | jq 'sort_by(-.score)'
}

#######################################
# Search command
#######################################
cmd_search() {
    local query=""
    local json_output="false"
    local limit=10
    local include_unconfigured="false"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json)
                json_output="true"
                shift
                ;;
            --limit)
                limit="$2"
                shift 2
                ;;
            --include-unconfigured)
                include_unconfigured="true"
                shift
                ;;
            -*)
                print_error "Unknown option: $1"
                return 1
                ;;
            *)
                query="$1"
                shift
                ;;
        esac
    done

    # Check if enabled
    if ! is_enabled; then
        if [[ "$json_output" == "true" ]]; then
            echo '{"error": "Tool search is disabled", "results": []}'
        else
            print_warning "Tool search is disabled in configuration"
        fi
        return 0
    fi

    # Check cache first
    local cache_key="search:${query}:${include_unconfigured}"
    local cached_results
    if cached_results=$(read_cache "$cache_key" 2>/dev/null); then
        if [[ "$json_output" == "true" ]]; then
            echo "$cached_results" | jq --argjson limit "$limit" '.[:$limit]'
        else
            print_info "Results (cached):"
            display_results "$cached_results" "$limit"
        fi
        return 0
    fi

    # Search MCP registry
    local mcp_results
    mcp_results=$(search_mcp_registry "$query" "$include_unconfigured")

    # Search Constructs
    local constructs_results
    constructs_results=$(search_constructs "$query")

    # Merge and sort results
    local all_results
    all_results=$(echo "$mcp_results" "$constructs_results" | jq -s 'add | sort_by(-.score)')

    # Cache results
    write_cache "$cache_key" "$all_results"

    # Output
    if [[ "$json_output" == "true" ]]; then
        echo "$all_results" | jq --argjson limit "$limit" '.[:$limit]'
    else
        if [[ -n "$query" ]]; then
            print_info "Search results for '$query':"
        else
            print_info "All available tools:"
        fi
        display_results "$all_results" "$limit"
    fi
}

#######################################
# Display results in human-readable format
#######################################
display_results() {
    local results="$1"
    local limit="${2:-10}"

    local count
    count=$(echo "$results" | jq 'length')

    if [[ "$count" -eq 0 ]]; then
        echo "  No results found"
        return 0
    fi

    echo ""
    echo "$results" | jq -r --argjson limit "$limit" '
        .[:$limit] | .[] |
        "  \u001b[36m\(.name)\u001b[0m (\(.source))\n    \(.description)\n    ID: \(.id) | Configured: \(if .configured then "✓" else "✗" end)\n"
    '

    local shown=$((count < limit ? count : limit))
    if [[ $count -gt $limit ]]; then
        echo "  ... and $((count - limit)) more results"
    fi
}

#######################################
# Discover command
#######################################
cmd_discover() {
    local json_output="false"
    local refresh="false"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json)
                json_output="true"
                shift
                ;;
            --refresh)
                refresh="true"
                shift
                ;;
            *)
                print_error "Unknown option: $1"
                return 1
                ;;
        esac
    done

    # Check if enabled
    if ! is_enabled; then
        if [[ "$json_output" == "true" ]]; then
            echo '{"error": "Tool search is disabled", "tools": []}'
        else
            print_warning "Tool search is disabled in configuration"
        fi
        return 0
    fi

    # Check cache first (unless refresh requested)
    local cache_key="discover:all"
    if [[ "$refresh" != "true" ]]; then
        local cached_results
        if cached_results=$(read_cache "$cache_key" 2>/dev/null); then
            if [[ "$json_output" == "true" ]]; then
                echo "$cached_results"
            else
                print_info "Available tools (cached):"
                display_discover_results "$cached_results"
            fi
            return 0
        fi
    fi

    local tools='{"mcp": [], "constructs": []}'

    # Discover MCP servers
    if [[ -f "$MCP_REGISTRY" ]]; then
        local servers
        servers=$(yq -r '.servers | keys | .[]' "$MCP_REGISTRY" 2>/dev/null || echo "")

        for server in $servers; do
            if is_server_configured "$server"; then
                local name description scopes
                name=$(yq -r ".servers.[\"${server}\"].name // \"$server\"" "$MCP_REGISTRY" 2>/dev/null || echo "$server")
                description=$(yq -r ".servers.[\"${server}\"].description // \"\"" "$MCP_REGISTRY" 2>/dev/null || echo "")
                scopes=$(yq -r ".servers.[\"${server}\"].scopes // []" "$MCP_REGISTRY" -o=json 2>/dev/null || echo "[]")

                local entry
                entry=$(jq -n \
                    --arg id "$server" \
                    --arg name "$name" \
                    --arg description "$description" \
                    --argjson scopes "$scopes" \
                    '{id: $id, name: $name, description: $description, scopes: $scopes}'
                )

                tools=$(echo "$tools" | jq --argjson entry "$entry" '.mcp += [$entry]')
            fi
        done
    fi

    # Discover Constructs
    local include_constructs
    include_constructs=$(get_config "tool_search.include_constructs" "true")

    if [[ "$include_constructs" == "true" && -d "$CONSTRUCTS_DIR" ]]; then
        # Discover skills
        if [[ -d "${CONSTRUCTS_DIR}/skills" ]]; then
            for vendor_dir in "${CONSTRUCTS_DIR}/skills"/*; do
                [[ -d "$vendor_dir" ]] || continue

                for skill_dir in "$vendor_dir"/*; do
                    [[ -d "$skill_dir" ]] || continue

                    local index_file="${skill_dir}/index.yaml"
                    [[ -f "$index_file" ]] || continue

                    local name description triggers
                    name=$(yq -r '.name // ""' "$index_file" 2>/dev/null || echo "")
                    description=$(yq -r '.description // ""' "$index_file" 2>/dev/null || echo "")
                    triggers=$(yq -r '.triggers // []' "$index_file" -o=json 2>/dev/null || echo "[]")

                    local skill_id vendor
                    skill_id=$(basename "$skill_dir")
                    vendor=$(basename "$vendor_dir")

                    local entry
                    entry=$(jq -n \
                        --arg id "${vendor}/${skill_id}" \
                        --arg name "$name" \
                        --arg description "$description" \
                        --argjson triggers "$triggers" \
                        --arg type "skill" \
                        '{id: $id, name: $name, description: $description, triggers: $triggers, type: $type}'
                    )

                    tools=$(echo "$tools" | jq --argjson entry "$entry" '.constructs += [$entry]')
                done
            done
        fi

        # Discover packs
        if [[ -d "${CONSTRUCTS_DIR}/packs" ]]; then
            for pack_dir in "${CONSTRUCTS_DIR}/packs"/*; do
                [[ -d "$pack_dir" ]] || continue

                local manifest="${pack_dir}/manifest.json"
                [[ -f "$manifest" ]] || continue

                local name description skills_count
                name=$(jq -r '.name // ""' "$manifest" 2>/dev/null || echo "")
                description=$(jq -r '.description // ""' "$manifest" 2>/dev/null || echo "")
                skills_count=$(jq -r '.skills | length' "$manifest" 2>/dev/null || echo "0")

                local pack_id
                pack_id=$(basename "$pack_dir")

                local entry
                entry=$(jq -n \
                    --arg id "pack:${pack_id}" \
                    --arg name "$name" \
                    --arg description "$description" \
                    --argjson skills_count "$skills_count" \
                    --arg type "pack" \
                    '{id: $id, name: $name, description: $description, skills_count: $skills_count, type: $type}'
                )

                tools=$(echo "$tools" | jq --argjson entry "$entry" '.constructs += [$entry]')
            done
        fi
    fi

    # Cache results
    write_cache "$cache_key" "$tools"

    # Output
    if [[ "$json_output" == "true" ]]; then
        echo "$tools"
    else
        print_info "Available tools:"
        display_discover_results "$tools"
    fi
}

#######################################
# Display discover results
#######################################
display_discover_results() {
    local results="$1"

    local mcp_count constructs_count
    mcp_count=$(echo "$results" | jq '.mcp | length')
    constructs_count=$(echo "$results" | jq '.constructs | length')

    echo ""
    echo -e "${CYAN}MCP Servers${NC} ($mcp_count configured):"
    if [[ "$mcp_count" -eq 0 ]]; then
        echo "  No MCP servers configured"
    else
        echo "$results" | jq -r '.mcp[] | "  \u001b[32m✓\u001b[0m \(.name) (\(.id))\n    \(.description)"'
    fi

    echo ""
    echo -e "${CYAN}Loa Constructs${NC} ($constructs_count installed):"
    if [[ "$constructs_count" -eq 0 ]]; then
        echo "  No constructs installed"
    else
        echo "$results" | jq -r '.constructs[] | "  \u001b[32m✓\u001b[0m \(.name) (\(.id))\n    \(.description)"'
    fi
}

#######################################
# Cache command
#######################################
cmd_cache() {
    local action="${1:-}"
    local query="${2:-}"

    local cache_dir
    cache_dir=$(get_cache_dir)

    case "$action" in
        list)
            if [[ ! -d "$cache_dir" ]]; then
                print_info "No cache entries"
                return 0
            fi

            local count
            count=$(find "$cache_dir" -name "*.json" 2>/dev/null | wc -l)

            if [[ "$count" -eq 0 ]]; then
                print_info "No cache entries"
                return 0
            fi

            print_info "Cache entries ($count):"
            echo ""

            for cache_file in "$cache_dir"/*.json; do
                [[ -f "$cache_file" ]] || continue

                local entry_query timestamp
                entry_query=$(jq -r '.query // "unknown"' "$cache_file")
                timestamp=$(jq -r '.timestamp // "unknown"' "$cache_file")

                echo "  Query: $entry_query"
                echo "  Cached: $timestamp"
                echo "  File: $(basename "$cache_file")"
                echo ""
            done
            ;;

        clear)
            if [[ -n "$query" ]]; then
                # Clear specific entry
                local cache_file
                cache_file=$(get_cache_path "$query")

                if [[ -f "$cache_file" ]]; then
                    rm -f "$cache_file"
                    print_success "Cleared cache for query: $query"
                else
                    print_warning "No cache entry found for query: $query"
                fi
            else
                # Clear all
                if [[ -d "$cache_dir" ]]; then
                    rm -rf "$cache_dir"
                    print_success "Cleared all cache entries"
                else
                    print_info "No cache to clear"
                fi
            fi
            ;;

        *)
            print_error "Unknown cache action: $action"
            echo "Usage: $(basename "$0") cache <list|clear> [query]"
            return 1
            ;;
    esac
}

#######################################
# Main entry point
#######################################
main() {
    local command=""

    # Parse command
    if [[ $# -eq 0 ]]; then
        usage
        exit 1
    fi

    command="$1"
    shift

    case "$command" in
        search)
            check_dependencies || exit 1
            cmd_search "$@"
            ;;
        discover)
            check_dependencies || exit 1
            cmd_discover "$@"
            ;;
        cache)
            cmd_cache "$@"
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            print_error "Unknown command: $command"
            usage
            exit 1
            ;;
    esac
}

main "$@"
