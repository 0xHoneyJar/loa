#!/usr/bin/env bash
# Cache Manager - Semantic result cache for recursive JIT context system
# Part of the Loa framework's Recursive JIT Context System
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Allow environment variable overrides for testing
CONFIG_FILE="${CONFIG_FILE:-${SCRIPT_DIR}/../../.loa.config.yaml}"
CACHE_DIR="${CACHE_DIR:-${SCRIPT_DIR}/../cache}"
CACHE_INDEX="${CACHE_INDEX:-${CACHE_DIR}/index.json}"
RESULTS_DIR="${RESULTS_DIR:-${CACHE_DIR}/results}"
FULL_DIR="${FULL_DIR:-${CACHE_DIR}/full}"

# Default configuration values
DEFAULT_CACHE_ENABLED="true"
DEFAULT_MAX_SIZE_MB="100"
DEFAULT_TTL_DAYS="30"

# Secret patterns to detect (simple patterns for shell validation)
SECRET_PATTERNS=(
    'PRIVATE.KEY'
    'BEGIN RSA'
    'BEGIN EC PRIVATE'
    'password.*='
    'secret.*='
    'api_key.*='
    'apikey.*='
    'access_token.*='
    'bearer.*='
)

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
    cat << 'USAGE'
Usage: cache-manager.sh <command> [options]

Cache Manager - Semantic result cache for recursive JIT context system

Commands:
  get --key <key>                   Get cached result by key
  set --key <key> --condensed <json> [--full <file>] [--synthesize <msg>]  Store result
  delete --key <key>                Delete cached entry
  generate-key --paths <paths> --query <query> --operation <op>  Generate cache key
  invalidate --paths <glob>         Invalidate entries by path pattern
  cleanup --max-size-mb <n>         Run LRU cleanup
  clear                             Remove all cache entries
  stats [--json]                    Show cache statistics

Options:
  --help, -h                        Show this help message
  --json                            Output as JSON

Configuration (.loa.config.yaml):
  recursive_jit:
    cache:
      enabled: true                 # Enable/disable cache
      max_size_mb: 100              # Max cache size in MB
      ttl_days: 30                  # Time-to-live in days
    continuous_synthesis:
      on_cache_set: true            # Auto-write to NOTES.md on cache set

Environment Variable Overrides:
  LOA_CACHE_ENABLED=false           # Disable cache
  LOA_CACHE_MAX_SIZE_MB=50          # Override max size
  LOA_CACHE_TTL_DAYS=7              # Override TTL

Examples:
  cache-manager.sh generate-key --paths "src/auth.ts,src/user.ts" --query "security audit" --operation "audit"
  cache-manager.sh set --key abc123 --condensed '{"verdict":"PASS"}'
  cache-manager.sh set --key abc123 --condensed '{"verdict":"PASS"}' --synthesize "Auth audit: PASS"
  cache-manager.sh get --key abc123
  cache-manager.sh stats --json
  cache-manager.sh cleanup --max-size-mb 50
USAGE
}

#######################################
# Print colored output
#######################################
print_info() {
    echo -e "${BLUE}i${NC} $1"
}

print_success() {
    echo -e "${GREEN}v${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}!${NC} $1"
}

print_error() {
    echo -e "${RED}x${NC} $1"
}

#######################################
# Check dependencies
#######################################
check_dependencies() {
    local missing=()

    if ! command -v jq &>/dev/null; then
        missing+=("jq")
    fi

    if ! command -v sha256sum &>/dev/null && ! command -v shasum &>/dev/null; then
        missing+=("sha256sum or shasum")
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
# Calculate SHA256 hash (portable)
#######################################
sha256_hash() {
    local input="$1"
    if command -v sha256sum &>/dev/null; then
        echo -n "$input" | sha256sum | cut -d' ' -f1
    else
        echo -n "$input" | shasum -a 256 | cut -d' ' -f1
    fi
}

#######################################
# Get configuration value
#######################################
get_config() {
    local key="$1"
    local default="${2:-}"

    if [[ -f "$CONFIG_FILE" ]] && command -v yq &>/dev/null; then
        local exists
        exists=$(yq -r ".$key | type" "$CONFIG_FILE" 2>/dev/null || echo "null")
        if [[ "$exists" != "null" ]]; then
            local value
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
# Check if cache is enabled
#######################################
is_cache_enabled() {
    # Environment override takes precedence
    if [[ -n "${LOA_CACHE_ENABLED:-}" ]]; then
        [[ "$LOA_CACHE_ENABLED" == "true" ]]
        return $?
    fi

    local enabled
    enabled=$(get_config "recursive_jit.cache.enabled" "$DEFAULT_CACHE_ENABLED")
    [[ "$enabled" == "true" ]]
}

#######################################
# Get max cache size in MB
#######################################
get_max_size_mb() {
    if [[ -n "${LOA_CACHE_MAX_SIZE_MB:-}" ]]; then
        echo "$LOA_CACHE_MAX_SIZE_MB"
        return
    fi
    get_config "recursive_jit.cache.max_size_mb" "$DEFAULT_MAX_SIZE_MB"
}

#######################################
# Get TTL in days
#######################################
get_ttl_days() {
    if [[ -n "${LOA_CACHE_TTL_DAYS:-}" ]]; then
        echo "$LOA_CACHE_TTL_DAYS"
        return
    fi
    get_config "recursive_jit.cache.ttl_days" "$DEFAULT_TTL_DAYS"
}

#######################################
# Initialize cache if needed
#######################################
init_cache() {
    mkdir -p "$CACHE_DIR" "$RESULTS_DIR" "$FULL_DIR"

    if [[ ! -f "$CACHE_INDEX" ]]; then
        local now
        now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        echo "{\"schema_version\":\"1.0.0\",\"created_at\":\"$now\",\"entries\":{},\"stats\":{\"hits\":0,\"misses\":0,\"invalidations\":0}}" | jq . > "$CACHE_INDEX"
    fi
}

#######################################
# Validate JSON format
#######################################
validate_json() {
    local json="$1"
    echo "$json" | jq -e '.' &>/dev/null
}

#######################################
# Check for secret patterns in content
#######################################
detect_secrets() {
    local content="$1"

    for pattern in "${SECRET_PATTERNS[@]}"; do
        if echo "$content" | grep -qi "$pattern"; then
            return 0  # Secret detected
        fi
    done

    return 1  # No secrets
}

#######################################
# Get file modification time as epoch
#######################################
get_mtime() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        echo "0"
        return
    fi

    if [[ "$(uname)" == "Darwin" ]]; then
        stat -f%m "$file" 2>/dev/null || echo "0"
    else
        stat -c%Y "$file" 2>/dev/null || echo "0"
    fi
}

#######################################
# Get current epoch time
#######################################
get_epoch() {
    date +%s
}

#######################################
# Generate cache key from components
#######################################
generate_cache_key() {
    local paths="$1"
    local query="$2"
    local operation="$3"

    # Normalize paths: sort and dedupe
    local paths_normalized
    paths_normalized=$(echo "$paths" | tr ',' '\n' | sort -u | tr '\n' ',' | sed 's/,$//')

    # Normalize query: lowercase, trim whitespace
    local query_normalized
    query_normalized=$(echo "$query" | tr '[:upper:]' '[:lower:]' | xargs)

    # Hash the combination
    local key_input="${paths_normalized}|${query_normalized}|${operation}"
    sha256_hash "$key_input"
}

#######################################
# Calculate integrity hash for content
#######################################
calculate_integrity() {
    local content="$1"
    sha256_hash "$content"
}

#######################################
# CMD: Generate key
#######################################
cmd_generate_key() {
    local paths=""
    local query=""
    local operation=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --paths) paths="$2"; shift 2 ;;
            --query) query="$2"; shift 2 ;;
            --operation) operation="$2"; shift 2 ;;
            *)
                print_error "Unknown option: $1"
                return 1
                ;;
        esac
    done

    if [[ -z "$paths" ]] || [[ -z "$query" ]] || [[ -z "$operation" ]]; then
        print_error "Required: --paths, --query, --operation"
        return 1
    fi

    generate_cache_key "$paths" "$query" "$operation"
}

#######################################
# CMD: Get cached result
#######################################
cmd_get() {
    local key=""
    local json_output="false"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --key) key="$2"; shift 2 ;;
            --json) json_output="true"; shift ;;
            *)
                print_error "Unknown option: $1"
                return 1
                ;;
        esac
    done

    if [[ -z "$key" ]]; then
        print_error "Required: --key"
        return 1
    fi

    if ! is_cache_enabled; then
        if [[ "$json_output" == "true" ]]; then
            echo '{"status":"disabled","key":"'"$key"'"}'
        fi
        return 1
    fi

    init_cache

    # Check if entry exists
    local entry
    entry=$(jq -r ".entries[\"$key\"] // empty" "$CACHE_INDEX" 2>/dev/null)

    if [[ -z "$entry" ]]; then
        # Cache miss
        jq --arg key "$key" '.stats.misses += 1' "$CACHE_INDEX" > "${CACHE_INDEX}.tmp" && mv "${CACHE_INDEX}.tmp" "$CACHE_INDEX"

        if [[ "$json_output" == "true" ]]; then
            echo '{"status":"miss","key":"'"$key"'"}'
        fi
        return 1
    fi

    # Check mtime invalidation
    local source_paths
    source_paths=$(echo "$entry" | jq -r '.source_paths // []')
    local cached_mtime
    cached_mtime=$(echo "$entry" | jq -r '.cached_mtime // 0')

    # Check if any source file is newer
    local invalidate="false"
    while IFS= read -r path; do
        [[ -z "$path" ]] && continue
        local current_mtime
        current_mtime=$(get_mtime "$path")
        if [[ "$current_mtime" -gt "$cached_mtime" ]]; then
            invalidate="true"
            break
        fi
    done < <(echo "$source_paths" | jq -r '.[]' 2>/dev/null)

    if [[ "$invalidate" == "true" ]]; then
        # Cache invalidated due to newer source
        jq --arg key "$key" '.stats.invalidations += 1 | .stats.misses += 1 | del(.entries[$key])' "$CACHE_INDEX" > "${CACHE_INDEX}.tmp" && mv "${CACHE_INDEX}.tmp" "$CACHE_INDEX"

        # Remove result file
        rm -f "${RESULTS_DIR}/${key}.json" 2>/dev/null

        if [[ "$json_output" == "true" ]]; then
            echo '{"status":"invalidated","key":"'"$key"'","reason":"source_modified"}'
        fi
        return 1
    fi

    # Check TTL
    local created_at
    created_at=$(echo "$entry" | jq -r '.created_at // 0')
    local ttl_days
    ttl_days=$(get_ttl_days)
    local ttl_seconds=$((ttl_days * 86400))
    local now
    now=$(get_epoch)

    if [[ $((now - created_at)) -gt $ttl_seconds ]]; then
        # Cache expired
        jq --arg key "$key" '.stats.invalidations += 1 | .stats.misses += 1 | del(.entries[$key])' "$CACHE_INDEX" > "${CACHE_INDEX}.tmp" && mv "${CACHE_INDEX}.tmp" "$CACHE_INDEX"

        rm -f "${RESULTS_DIR}/${key}.json" 2>/dev/null

        if [[ "$json_output" == "true" ]]; then
            echo '{"status":"expired","key":"'"$key"'"}'
        fi
        return 1
    fi

    # Read result file
    local result_file="${RESULTS_DIR}/${key}.json"
    if [[ ! -f "$result_file" ]]; then
        # Index entry exists but file missing - corrupt
        jq --arg key "$key" '.stats.misses += 1 | del(.entries[$key])' "$CACHE_INDEX" > "${CACHE_INDEX}.tmp" && mv "${CACHE_INDEX}.tmp" "$CACHE_INDEX"

        if [[ "$json_output" == "true" ]]; then
            echo '{"status":"corrupt","key":"'"$key"'"}'
        fi
        return 1
    fi

    # Verify integrity
    local stored_hash
    stored_hash=$(echo "$entry" | jq -r '.integrity_hash // ""')
    local content
    content=$(cat "$result_file")
    local current_hash
    current_hash=$(calculate_integrity "$content")

    if [[ "$stored_hash" != "$current_hash" ]]; then
        # Integrity check failed
        jq --arg key "$key" '.stats.invalidations += 1 | .stats.misses += 1 | del(.entries[$key])' "$CACHE_INDEX" > "${CACHE_INDEX}.tmp" && mv "${CACHE_INDEX}.tmp" "$CACHE_INDEX"

        rm -f "$result_file" 2>/dev/null

        if [[ "$json_output" == "true" ]]; then
            echo '{"status":"corrupt","key":"'"$key"'","reason":"integrity_mismatch"}'
        fi
        return 1
    fi

    # Cache hit - update stats
    jq --arg key "$key" '
        .stats.hits += 1 |
        .entries[$key].hit_count = ((.entries[$key].hit_count // 0) + 1) |
        .entries[$key].last_hit = now
    ' "$CACHE_INDEX" > "${CACHE_INDEX}.tmp" && mv "${CACHE_INDEX}.tmp" "$CACHE_INDEX"

    # Return the cached content
    echo "$content"
}

#######################################
# CMD: Set cached result
#######################################
cmd_set() {
    local key=""
    local condensed=""
    local full_path=""
    local source_paths=""
    local synthesize_msg=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --key) key="$2"; shift 2 ;;
            --condensed) condensed="$2"; shift 2 ;;
            --full) full_path="$2"; shift 2 ;;
            --sources) source_paths="$2"; shift 2 ;;
            --synthesize) synthesize_msg="$2"; shift 2 ;;
            *)
                print_error "Unknown option: $1"
                return 1
                ;;
        esac
    done

    if [[ -z "$key" ]] || [[ -z "$condensed" ]]; then
        print_error "Required: --key, --condensed"
        return 1
    fi

    if ! is_cache_enabled; then
        print_warning "Cache disabled"
        return 0
    fi

    # Validate JSON
    if ! validate_json "$condensed"; then
        print_error "Invalid JSON in --condensed"
        return 1
    fi

    # Check for secrets
    if detect_secrets "$condensed"; then
        print_error "Secret patterns detected in content - refusing to cache"
        return 1
    fi

    init_cache

    # Calculate integrity hash
    local integrity_hash
    integrity_hash=$(calculate_integrity "$condensed")

    # Get current mtime of source files
    local cached_mtime
    cached_mtime=$(get_epoch)

    # Parse source paths into JSON array
    local sources_json="[]"
    if [[ -n "$source_paths" ]]; then
        sources_json=$(echo "$source_paths" | tr ',' '\n' | jq -R . | jq -s .)
    fi

    # Store result file
    local result_file="${RESULTS_DIR}/${key}.json"
    echo "$condensed" > "$result_file"

    # Handle full result externalization
    local full_result_path=""
    if [[ -n "$full_path" ]] && [[ -f "$full_path" ]]; then
        local full_hash
        full_hash=$(sha256_hash "$(cat "$full_path")")
        local full_dest="${FULL_DIR}/${full_hash}.json"
        cp "$full_path" "$full_dest"
        full_result_path="$full_dest"
    fi

    # Update index
    local now
    now=$(get_epoch)

    jq --arg key "$key" \
       --argjson sources "$sources_json" \
       --argjson mtime "$cached_mtime" \
       --arg hash "$integrity_hash" \
       --arg full "$full_result_path" \
       --argjson created "$now" \
       '
        .entries[$key] = {
            created_at: $created,
            cached_mtime: $mtime,
            source_paths: $sources,
            integrity_hash: $hash,
            full_result_path: (if $full == "" then null else $full end),
            hit_count: 0,
            last_hit: null
        }
    ' "$CACHE_INDEX" > "${CACHE_INDEX}.tmp" && mv "${CACHE_INDEX}.tmp" "$CACHE_INDEX"

    print_success "Cached result for key: $key"

    # Continuous synthesis: write to ledger if enabled
    if [[ -n "$synthesize_msg" ]]; then
        local synthesize_script="${SCRIPT_DIR}/synthesize-to-ledger.sh"
        if [[ -x "$synthesize_script" ]]; then
            "$synthesize_script" decision --message "$synthesize_msg" --source cache --quiet
        fi
    elif is_auto_synthesize_enabled; then
        # Auto-synthesize: extract verdict from condensed JSON if available
        local auto_msg=""
        if echo "$condensed" | jq -e '.verdict' &>/dev/null; then
            auto_msg="Cache: $(echo "$condensed" | jq -r '.verdict // "stored"') [key: ${key:0:8}...]"
        else
            auto_msg="Cache: result stored [key: ${key:0:8}...]"
        fi
        local synthesize_script="${SCRIPT_DIR}/synthesize-to-ledger.sh"
        if [[ -x "$synthesize_script" ]]; then
            "$synthesize_script" decision --message "$auto_msg" --source cache --quiet
        fi
    fi
}

#######################################
# Check if auto-synthesize is enabled
#######################################
is_auto_synthesize_enabled() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        return 1
    fi

    if command -v yq &>/dev/null; then
        local enabled
        enabled=$(yq '.recursive_jit.continuous_synthesis.on_cache_set // true' "$CONFIG_FILE" 2>/dev/null)
        [[ "$enabled" == "true" ]]
    else
        return 1
    fi
}

#######################################
# CMD: Delete cached entry
#######################################
cmd_delete() {
    local key=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --key) key="$2"; shift 2 ;;
            *)
                print_error "Unknown option: $1"
                return 1
                ;;
        esac
    done

    if [[ -z "$key" ]]; then
        print_error "Required: --key"
        return 1
    fi

    init_cache

    # Remove from index
    jq --arg key "$key" 'del(.entries[$key])' "$CACHE_INDEX" > "${CACHE_INDEX}.tmp" && mv "${CACHE_INDEX}.tmp" "$CACHE_INDEX"

    # Remove result file
    rm -f "${RESULTS_DIR}/${key}.json" 2>/dev/null

    print_success "Deleted cache entry: $key"
}

#######################################
# CMD: Invalidate by path pattern
#######################################
cmd_invalidate() {
    local pattern=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --paths) pattern="$2"; shift 2 ;;
            *)
                print_error "Unknown option: $1"
                return 1
                ;;
        esac
    done

    if [[ -z "$pattern" ]]; then
        print_error "Required: --paths <glob pattern>"
        return 1
    fi

    init_cache

    local count=0
    local keys_to_delete=()

    # Find entries that match the pattern
    while IFS= read -r key; do
        [[ -z "$key" ]] && continue

        local sources
        sources=$(jq -r ".entries[\"$key\"].source_paths // []" "$CACHE_INDEX")

        # Check if any source matches the pattern
        while IFS= read -r source; do
            [[ -z "$source" ]] && continue
            # shellcheck disable=SC2053
            if [[ "$source" == $pattern ]]; then
                keys_to_delete+=("$key")
                count=$((count + 1))
                break
            fi
        done < <(echo "$sources" | jq -r '.[]' 2>/dev/null)
    done < <(jq -r '.entries | keys[]' "$CACHE_INDEX" 2>/dev/null)

    # Delete matching entries
    for key in "${keys_to_delete[@]}"; do
        jq --arg key "$key" 'del(.entries[$key]) | .stats.invalidations += 1' "$CACHE_INDEX" > "${CACHE_INDEX}.tmp" && mv "${CACHE_INDEX}.tmp" "$CACHE_INDEX"
        rm -f "${RESULTS_DIR}/${key}.json" 2>/dev/null
    done

    print_success "Invalidated $count entries matching: $pattern"
}

#######################################
# CMD: Cleanup with LRU eviction
#######################################
cmd_cleanup() {
    local max_size_mb=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --max-size-mb) max_size_mb="$2"; shift 2 ;;
            *)
                print_error "Unknown option: $1"
                return 1
                ;;
        esac
    done

    if [[ -z "$max_size_mb" ]]; then
        max_size_mb=$(get_max_size_mb)
    fi

    init_cache

    # Calculate current cache size
    local current_size_bytes
    current_size_bytes=$(du -sb "$CACHE_DIR" 2>/dev/null | cut -f1 || echo "0")
    local max_size_bytes=$((max_size_mb * 1024 * 1024))

    if [[ "$current_size_bytes" -le "$max_size_bytes" ]]; then
        print_info "Cache size OK: $((current_size_bytes / 1024 / 1024))MB / ${max_size_mb}MB"
        return 0
    fi

    print_info "Cache exceeds limit: $((current_size_bytes / 1024 / 1024))MB / ${max_size_mb}MB"
    print_info "Running LRU eviction..."

    # Get entries sorted by last_hit (oldest first), then by created_at
    local evicted=0
    while IFS= read -r key; do
        [[ -z "$key" ]] && continue

        # Delete entry
        jq --arg key "$key" 'del(.entries[$key])' "$CACHE_INDEX" > "${CACHE_INDEX}.tmp" && mv "${CACHE_INDEX}.tmp" "$CACHE_INDEX"
        rm -f "${RESULTS_DIR}/${key}.json" 2>/dev/null
        evicted=$((evicted + 1))

        # Check if we're under the limit now
        current_size_bytes=$(du -sb "$CACHE_DIR" 2>/dev/null | cut -f1 || echo "0")
        if [[ "$current_size_bytes" -le "$max_size_bytes" ]]; then
            break
        fi
    done < <(jq -r '.entries | to_entries | sort_by(.value.last_hit // .value.created_at) | .[].key' "$CACHE_INDEX" 2>/dev/null)

    print_success "Evicted $evicted entries"
    print_info "New cache size: $((current_size_bytes / 1024 / 1024))MB"
}

#######################################
# CMD: Clear all cache entries
#######################################
cmd_clear() {
    init_cache

    # Count entries before clearing
    local count
    count=$(jq -r '.entries | length' "$CACHE_INDEX" 2>/dev/null || echo "0")

    # Reset index
    local now
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    echo "{\"schema_version\":\"1.0.0\",\"created_at\":\"$now\",\"entries\":{},\"stats\":{\"hits\":0,\"misses\":0,\"invalidations\":0}}" | jq . > "$CACHE_INDEX"

    # Remove all result files
    rm -f "${RESULTS_DIR}"/*.json 2>/dev/null
    rm -f "${FULL_DIR}"/*.json 2>/dev/null

    print_success "Cleared $count cache entries"
}

#######################################
# CMD: Show statistics
#######################################
cmd_stats() {
    local json_output="false"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json) json_output="true"; shift ;;
            *)
                print_error "Unknown option: $1"
                return 1
                ;;
        esac
    done

    init_cache

    local entry_count
    entry_count=$(jq -r '.entries | length' "$CACHE_INDEX" 2>/dev/null || echo "0")

    local hits misses invalidations
    hits=$(jq -r '.stats.hits // 0' "$CACHE_INDEX" 2>/dev/null)
    misses=$(jq -r '.stats.misses // 0' "$CACHE_INDEX" 2>/dev/null)
    invalidations=$(jq -r '.stats.invalidations // 0' "$CACHE_INDEX" 2>/dev/null)

    local total_requests=$((hits + misses))
    local hit_rate="0"
    if [[ "$total_requests" -gt 0 ]]; then
        hit_rate=$(echo "scale=2; $hits * 100 / $total_requests" | bc 2>/dev/null || echo "0")
    fi

    # Calculate size
    local size_bytes
    size_bytes=$(du -sb "$CACHE_DIR" 2>/dev/null | cut -f1 || echo "0")
    local size_mb
    size_mb=$(echo "scale=2; $size_bytes / 1024 / 1024" | bc 2>/dev/null || echo "0")

    local max_size_mb
    max_size_mb=$(get_max_size_mb)

    local enabled
    enabled=$(is_cache_enabled && echo "true" || echo "false")

    if [[ "$json_output" == "true" ]]; then
        jq -n \
            --argjson enabled "$enabled" \
            --argjson entries "$entry_count" \
            --argjson hits "$hits" \
            --argjson misses "$misses" \
            --argjson invalidations "$invalidations" \
            --arg hit_rate "$hit_rate" \
            --arg size_mb "$size_mb" \
            --arg max_size_mb "$max_size_mb" \
            '{enabled: $enabled, entries: $entries, hits: $hits, misses: $misses, invalidations: $invalidations, hit_rate_pct: $hit_rate, size_mb: $size_mb, max_size_mb: $max_size_mb}'
    else
        echo ""
        echo -e "${CYAN}Cache Statistics${NC}"
        echo "================="
        echo ""
        if [[ "$enabled" == "true" ]]; then
            echo -e "  Status:        ${GREEN}enabled${NC}"
        else
            echo -e "  Status:        ${YELLOW}disabled${NC}"
        fi
        echo "  Entries:       $entry_count"
        echo "  Hits:          $hits"
        echo "  Misses:        $misses"
        echo "  Invalidations: $invalidations"
        echo "  Hit Rate:      ${hit_rate}%"
        echo ""
        echo "  Size:          ${size_mb}MB / ${max_size_mb}MB"
        echo ""
    fi
}

#######################################
# Main entry point
#######################################
main() {
    local command=""

    if [[ $# -eq 0 ]]; then
        usage
        exit 1
    fi

    command="$1"
    shift

    case "$command" in
        get)
            check_dependencies || exit 1
            cmd_get "$@"
            ;;
        set)
            check_dependencies || exit 1
            cmd_set "$@"
            ;;
        delete)
            check_dependencies || exit 1
            cmd_delete "$@"
            ;;
        generate-key)
            check_dependencies || exit 1
            cmd_generate_key "$@"
            ;;
        invalidate)
            check_dependencies || exit 1
            cmd_invalidate "$@"
            ;;
        cleanup)
            check_dependencies || exit 1
            cmd_cleanup "$@"
            ;;
        clear)
            check_dependencies || exit 1
            cmd_clear "$@"
            ;;
        stats)
            check_dependencies || exit 1
            cmd_stats "$@"
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
