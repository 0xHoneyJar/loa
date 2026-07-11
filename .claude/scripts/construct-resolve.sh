#!/usr/bin/env bash
# =============================================================================
# construct-resolve.sh — Name resolution + composition for constructs
# =============================================================================
# Resolves construct references by slug, name, or command, and checks
# composition viability between constructs via write/read path overlap.
#
# Usage:
#   construct-resolve.sh resolve <query> [--json] [--index PATH]
#   construct-resolve.sh compose <source> <target> [--json] [--index PATH]
#   construct-resolve.sh list [--json] [--index PATH]
#   construct-resolve.sh capabilities <slug> [--json] [--index PATH]
#
# Exit Codes:
#   0 = success (match found / overlap exists / listing ok)
#   1 = no match / no overlap / construct not found
#   2 = collision (ambiguous match — warning + first match returned)
#   3 = index file missing or unreadable
#
# Environment:
#   CONSTRUCT_INDEX_PATH   Override index file location
#   PROJECT_ROOT           Override project root
#
# Sources: cycle-051, Sprint 104
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

# Source shared libraries
if [[ -f "$SCRIPT_DIR/yq-safe.sh" ]]; then
    source "$SCRIPT_DIR/yq-safe.sh"
fi

# shellcheck source=lib/dx-utils.sh
source "$SCRIPT_DIR/lib/dx-utils.sh"

# =============================================================================
# Configuration
# =============================================================================

DEFAULT_INDEX_PATH="$PROJECT_ROOT/.run/construct-index.yaml"

# =============================================================================
# CLI Parsing
# =============================================================================

SUBCOMMAND=""
QUERY=""
SOURCE_SLUG=""
TARGET_SLUG=""
JSON_OUTPUT=false
INDEX_PATH=""

_parse_args() {
    if [[ $# -lt 1 ]]; then
        _usage
        exit 1
    fi

    SUBCOMMAND="$1"
    shift

    case "$SUBCOMMAND" in
        resolve)
            if [[ $# -lt 1 ]]; then
                echo "ERROR: resolve requires a <query> argument" >&2
                exit 1
            fi
            QUERY="$1"
            shift
            ;;
        compose)
            if [[ $# -lt 2 ]]; then
                echo "ERROR: compose requires <source-slug> and <target-slug>" >&2
                exit 1
            fi
            SOURCE_SLUG="$1"
            TARGET_SLUG="$2"
            shift 2
            ;;
        list)
            ;;
        capabilities)
            if [[ $# -lt 1 ]]; then
                echo "ERROR: capabilities requires a <slug> argument" >&2
                exit 1
            fi
            QUERY="$1"
            shift
            ;;
        -h|--help)
            _usage
            exit 0
            ;;
        *)
            echo "ERROR: Unknown subcommand: $SUBCOMMAND" >&2
            _usage
            exit 1
            ;;
    esac

    # Parse remaining flags
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json) JSON_OUTPUT=true; shift ;;
            --index) INDEX_PATH="$2"; shift 2 ;;
            -h|--help) _usage; exit 0 ;;
            *)
                dx_unknown_flag "$1" "Usage: construct-resolve.sh <subcommand> [args] [--json] [--index PATH]" \
                    --json --index --help
                exit 1
                ;;
        esac
    done
}

_usage() {
    cat >&2 <<'EOF'
Usage: construct-resolve.sh <subcommand> [args] [--json] [--index PATH]

Subcommands:
  resolve <query>                  Resolve construct by slug, name, or command
  compose <source> <target>        Check composition viability via path overlap
  list                             List all construct slugs
  capabilities <slug>              Show aggregated capabilities for a construct

Options:
  --json        Output JSON (default: human-readable)
  --index PATH  Override index file path (default: .run/construct-index.yaml)

Exit codes:
  0 = success    1 = no match/overlap    2 = collision    3 = index missing
EOF
}

# =============================================================================
# Index Loading
# =============================================================================

# Load index and convert to JSON for querying
# Sets INDEX_JSON global variable
_load_index() {
    local index_file="${INDEX_PATH:-${CONSTRUCT_INDEX_PATH:-$DEFAULT_INDEX_PATH}}"

    if [[ ! -f "$index_file" ]]; then
        echo "ERROR: Construct index not found: $index_file" >&2
        exit 3
    fi

    # Detect format and convert to JSON
    if [[ "$index_file" == *.json ]]; then
        INDEX_JSON=$(cat "$index_file")
    else
        # YAML — use yq to convert
        if ! command -v yq &>/dev/null; then
            echo "ERROR: yq required to read YAML index" >&2
            exit 3
        fi
        INDEX_JSON=$(yq eval -o=json '.' "$index_file" 2>/dev/null) || {
            echo "ERROR: Failed to parse index: $index_file" >&2
            exit 3
        }
    fi

    # Validate minimal structure
    if ! echo "$INDEX_JSON" | jq -e '.constructs' &>/dev/null; then
        echo "ERROR: Index missing 'constructs' key" >&2
        exit 3
    fi
}

# =============================================================================
# Subcommand: resolve
# =============================================================================

_resolve() {
    local query="$QUERY"

    # Tier 1: Exact slug match
    local matches
    matches=$(echo "$INDEX_JSON" | jq -c --arg q "$query" \
        '[.constructs[] | select(.slug == $q)]')
    local count
    count=$(echo "$matches" | jq 'length')

    if [[ "$count" -eq 1 ]]; then
        _output_match "$(echo "$matches" | jq '.[0]')" "slug"
        return 0
    fi
    if [[ "$count" -gt 1 ]]; then
        echo "WARNING: Multiple constructs with slug '$query'" >&2
        _output_match "$(echo "$matches" | jq '.[0]')" "slug"
        return 2
    fi

    # Tier 2: Case-insensitive name match
    local query_lower
    query_lower=$(echo "$query" | tr '[:upper:]' '[:lower:]')
    matches=$(echo "$INDEX_JSON" | jq -c --arg q "$query_lower" \
        '[.constructs[] | select((.name | ascii_downcase) == $q)]')
    count=$(echo "$matches" | jq 'length')

    if [[ "$count" -eq 1 ]]; then
        _output_match "$(echo "$matches" | jq '.[0]')" "name"
        return 0
    fi
    if [[ "$count" -gt 1 ]]; then
        echo "WARNING: Multiple constructs matching name '$query'" >&2
        _output_match "$(echo "$matches" | jq '.[0]')" "name"
        return 2
    fi

    # Tier 3: Command name match
    matches=$(echo "$INDEX_JSON" | jq -c --arg q "$query" \
        '[.constructs[] | select(.commands[]? | .name == $q)]')
    count=$(echo "$matches" | jq 'length')

    if [[ "$count" -eq 1 ]]; then
        _output_match "$(echo "$matches" | jq '.[0]')" "command"
        return 0
    fi
    if [[ "$count" -gt 1 ]]; then
        echo "WARNING: Multiple constructs claim command '$query'" >&2
        _output_match "$(echo "$matches" | jq '.[0]')" "command"
        return 2
    fi

    # No match
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        jq -n --arg q "$query" '{"resolved": false, "query": $q, "error": "no match"}'
    else
        echo "No construct found for: $query"
    fi
    return 1
}

_output_match() {
    local entry="$1"
    local tier="$2"

    if [[ "$JSON_OUTPUT" == "true" ]]; then
        jq -n --argjson entry "$entry" --arg tier "$tier" \
            '{"resolved": true, "tier": $tier, "construct": $entry}'
    else
        local slug name
        slug=$(echo "$entry" | jq -r '.slug')
        name=$(echo "$entry" | jq -r '.name')
        echo "$slug ($name) [matched by $tier]"
    fi
}

# =============================================================================
# Subcommand: compose
# =============================================================================

_compose() {
    local source_slug="$SOURCE_SLUG"
    local target_slug="$TARGET_SLUG"

    # Look up source construct
    local source_entry
    source_entry=$(echo "$INDEX_JSON" | jq -c --arg s "$source_slug" \
        '.constructs[] | select(.slug == $s)') || true

    if [[ -z "$source_entry" ]]; then
        echo "ERROR: Source construct not found: $source_slug" >&2
        return 1
    fi

    # Look up target construct
    local target_entry
    target_entry=$(echo "$INDEX_JSON" | jq -c --arg t "$target_slug" \
        '.constructs[] | select(.slug == $t)') || true

    if [[ -z "$target_entry" ]]; then
        echo "ERROR: Target construct not found: $target_slug" >&2
        return 1
    fi

    # Get writes/reads
    local source_writes source_reads target_writes target_reads
    source_writes=$(echo "$source_entry" | jq -c '.writes // []')
    target_reads=$(echo "$target_entry" | jq -c '.reads // []')
    source_reads=$(echo "$source_entry" | jq -c '.reads // []')
    target_writes=$(echo "$target_entry" | jq -c '.writes // []')

    # Check path overlap: source.writes ∩ target.reads (prefix matching)
    local forward_overlaps
    forward_overlaps=$(_find_path_overlaps "$source_writes" "$target_reads")

    # Check reverse: target.writes ∩ source.reads
    local reverse_overlaps
    reverse_overlaps=$(_find_path_overlaps "$target_writes" "$source_reads")

    # Merge results
    local all_overlaps
    all_overlaps=$(jq -n \
        --argjson fwd "$forward_overlaps" \
        --argjson rev "$reverse_overlaps" \
        '$fwd + $rev | unique')

    local overlap_count
    overlap_count=$(echo "$all_overlaps" | jq 'length')

    # Log composition check to audit.jsonl
    _audit_log "compose" "$source_slug" "$target_slug" "$overlap_count"

    if [[ "$overlap_count" -gt 0 ]]; then
        if [[ "$JSON_OUTPUT" == "true" ]]; then
            jq -n \
                --arg source "$source_slug" \
                --arg target "$target_slug" \
                --argjson overlaps "$all_overlaps" \
                '{"composable": true, "source": $source, "target": $target, "overlapping_paths": $overlaps}'
        else
            echo "Composable: $source_slug -> $target_slug"
            echo "Overlapping paths:"
            echo "$all_overlaps" | jq -r '.[]' | sed 's/^/  /'
        fi
        return 0
    else
        if [[ "$JSON_OUTPUT" == "true" ]]; then
            jq -n \
                --arg source "$source_slug" \
                --arg target "$target_slug" \
                '{"composable": false, "source": $source, "target": $target, "overlapping_paths": []}'
        else
            echo "No composition path: $source_slug -> $target_slug (no overlap)"
        fi
        return 1
    fi
}

# Find overlapping paths between two JSON arrays using string prefix matching
# Args: $1 = writes JSON array, $2 = reads JSON array
# Returns: JSON array of overlapping paths on stdout
_find_path_overlaps() {
    local writes_json="$1"
    local reads_json="$2"
    local overlaps="[]"

    # For each write path, check if any read path is a prefix match (or vice versa)
    local write_count read_count
    write_count=$(echo "$writes_json" | jq 'length')
    read_count=$(echo "$reads_json" | jq 'length')

    local wi=0
    while [[ $wi -lt $write_count ]]; do
        local write_path
        write_path=$(echo "$writes_json" | jq -r ".[$wi]")

        local ri=0
        while [[ $ri -lt $read_count ]]; do
            local read_path
            read_path=$(echo "$reads_json" | jq -r ".[$ri]")

            if _paths_overlap "$write_path" "$read_path"; then
                overlaps=$(echo "$overlaps" | jq --arg p "$write_path" '. + [$p]')
            fi

            ri=$((ri + 1))
        done

        wi=$((wi + 1))
    done

    echo "$overlaps" | jq 'unique'
}

# Check if two paths overlap via string prefix matching
# Supports glob patterns: trailing * or ** treated as prefix
# Args: $1 = path_a, $2 = path_b
# Returns: 0 if overlap, 1 if no overlap
_paths_overlap() {
    local a="$1"
    local b="$2"

    # Exact match
    if [[ "$a" == "$b" ]]; then
        return 0
    fi

    # Strip trailing glob markers and slashes for prefix comparison
    # e.g., "grimoires/shared/**" -> "grimoires/shared"
    local a_base="$a"
    local b_base="$b"
    # Remove all trailing * characters
    while [[ "$a_base" == *'*' ]]; do a_base="${a_base%\*}"; done
    while [[ "$b_base" == *'*' ]]; do b_base="${b_base%\*}"; done
    # Remove trailing slash if present
    a_base="${a_base%/}"
    b_base="${b_base%/}"

    # Prefix match: a_base is prefix of b or b_base is prefix of a
    # Also check if b starts with a_base/ (directory containment)
    if [[ -n "$a_base" ]] && { [[ "$b" == "$a_base"* ]] || [[ "$b" == "$a_base/"* ]]; }; then
        return 0
    fi
    if [[ -n "$b_base" ]] && { [[ "$a" == "$b_base"* ]] || [[ "$a" == "$b_base/"* ]]; }; then
        return 0
    fi

    return 1
}

# =============================================================================
# Subcommand: list
# =============================================================================

_list() {
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        echo "$INDEX_JSON" | jq '[.constructs[].slug]'
    else
        echo "$INDEX_JSON" | jq -r '.constructs[].slug'
    fi
    return 0
}

# =============================================================================
# Subcommand: capabilities
# =============================================================================

_capabilities() {
    local slug="$QUERY"

    local entry
    entry=$(echo "$INDEX_JSON" | jq -c --arg s "$slug" \
        '.constructs[] | select(.slug == $s)') || true

    if [[ -z "$entry" ]]; then
        echo "ERROR: Construct not found: $slug" >&2
        return 1
    fi

    local caps
    caps=$(echo "$entry" | jq '.aggregated_capabilities // {}')

    if [[ "$JSON_OUTPUT" == "true" ]]; then
        jq -n --arg slug "$slug" --argjson caps "$caps" \
            '{"slug": $slug, "capabilities": $caps}'
    else
        echo "Capabilities for $slug:"
        echo "$caps" | jq -r 'to_entries[] | "  \(.key): \(.value)"'
    fi
    return 0
}

# =============================================================================
# Audit Logging
# =============================================================================

_audit_log() {
    local action="$1"
    local source="$2"
    local target="$3"
    local overlap_count="$4"

    local audit_file="$PROJECT_ROOT/.run/audit.jsonl"
    mkdir -p "$(dirname "$audit_file")" 2>/dev/null || true

    jq -cn \
        --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg tool "construct-resolve" \
        --arg action "$action" \
        --arg source "$source" \
        --arg target "$target" \
        --argjson overlap_count "$overlap_count" \
        '{ts: $ts, tool: $tool, action: $action, source: $source, target: $target, overlap_count: $overlap_count}' \
        >> "$audit_file" 2>/dev/null || true
}

# =============================================================================
# Main
# =============================================================================

main() {
    _parse_args "$@"
    _load_index

    case "$SUBCOMMAND" in
        resolve)      _resolve ;;
        compose)      _compose ;;
        list)         _list ;;
        capabilities) _capabilities ;;
    esac
}

# Only run main if not being sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
