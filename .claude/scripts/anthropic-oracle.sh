#!/usr/bin/env bash
# anthropic-oracle.sh - Monitor Anthropic updates and query Loa learnings
#
# This script checks Anthropic's official sources for updates that could
# benefit Loa, and queries Loa's own compound learnings for patterns.
#
# Usage:
#   anthropic-oracle.sh check                    # Check for Anthropic updates
#   anthropic-oracle.sh sources                  # List monitored sources
#   anthropic-oracle.sh history                  # Show previous checks
#   anthropic-oracle.sh template                 # Output research document template
#   anthropic-oracle.sh query <terms> [options]  # Query knowledge sources
#
# Query Options:
#   --scope <loa|anthropic|all>  Source scope (default: all)
#   --format <json|text>         Output format (default: text)
#   --limit <N>                  Max results (default: 10)
#   --min-weight <0.0-1.0>       Minimum source weight filter
#   --index <auto|qmd|grep>      Force specific indexer (default: auto)
#
# Environment:
#   ANTHROPIC_ORACLE_CACHE  - Cache directory (default: ~/.loa/cache/oracle)
#   ANTHROPIC_ORACLE_TTL    - Cache TTL in hours (default: 24)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Configuration
CACHE_DIR="${ANTHROPIC_ORACLE_CACHE:-$HOME/.loa/cache/oracle}"
CACHE_TTL_HOURS="${ANTHROPIC_ORACLE_TTL:-24}"
HISTORY_FILE="$CACHE_DIR/check-history.jsonl"
LAST_CHECK_FILE="$CACHE_DIR/last-check.json"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

# Check bash version (associative arrays require bash 4+)
check_bash_version() {
    if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
        echo -e "${RED}ERROR: bash 4.0+ required (found ${BASH_VERSION})${NC}" >&2
        echo "" >&2
        echo "Upgrade bash:" >&2
        echo "  macOS:  brew install bash" >&2
        echo "          Then add /opt/homebrew/bin/bash to /etc/shells" >&2
        echo "          And run: chsh -s /opt/homebrew/bin/bash" >&2
        exit 1
    fi
}

# Check dependencies
check_dependencies() {
    local missing=()

    # jq is required for JSON processing
    if ! command -v jq &> /dev/null; then
        missing+=("jq")
    fi

    # curl is required for HTTP fetches
    if ! command -v curl &> /dev/null; then
        missing+=("curl")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo -e "${RED}ERROR: Missing dependencies: ${missing[*]}${NC}" >&2
        echo "" >&2
        echo "Install missing dependencies:" >&2
        echo "  macOS:  brew install ${missing[*]}" >&2
        echo "  Ubuntu: sudo apt install ${missing[*]}" >&2
        exit 1
    fi
}

# Run checks before anything else
check_bash_version
check_dependencies

# Configuration file
CONFIG_FILE="$PROJECT_ROOT/.loa.config.yaml"

# Read config value with yq, fallback to default
read_config() {
    local path="$1"
    local default="$2"
    if [[ -f "$CONFIG_FILE" ]] && command -v yq &> /dev/null; then
        local value
        value=$(yq -r "$path // \"\"" "$CONFIG_FILE" 2>/dev/null)
        if [[ -n "$value" && "$value" != "null" ]]; then
            echo "$value"
            return
        fi
    fi
    echo "$default"
}

# Check if QMD is available
qmd_available() {
    command -v qmd &> /dev/null
}

# Get default indexer from config
get_default_indexer() {
    read_config '.oracle.query.default_indexer' 'auto'
}

# Get default scope from config
get_default_scope() {
    read_config '.oracle.query.default_scope' 'all'
}

# Get default limit from config
get_default_limit() {
    read_config '.oracle.query.default_limit' '10'
}

# Source weights (hierarchical - from Issue #76)
# Loa learnings = 1.0 (highest - our own proven patterns)
# Anthropic docs = 0.8 (authoritative external source)
# Community = 0.5 (useful but less verified)
declare -A SOURCE_WEIGHTS=(
    ["loa"]="1.0"
    ["anthropic"]="0.8"
    ["community"]="0.5"
)

# Loa sources for compound learnings
declare -A LOA_SOURCES=(
    ["skills"]=".claude/skills/**/*.md"
    ["feedback"]="grimoires/loa/feedback/*.yaml"
    ["decisions"]="grimoires/loa/decisions.yaml"
    ["learnings"]="grimoires/loa/a2a/compound/learnings.json"
)

# Anthropic sources to monitor
# Note: Claude Code docs moved from docs.anthropic.com to code.claude.com in early 2026
declare -A SOURCES=(
    ["docs"]="https://code.claude.com/docs/en/overview"
    ["changelog"]="https://code.claude.com/docs/en/changelog"
    ["memory"]="https://code.claude.com/docs/en/memory"
    ["skills"]="https://code.claude.com/docs/en/skills"
    ["hooks"]="https://code.claude.com/docs/en/hooks"
    ["api_reference"]="https://docs.anthropic.com/en/api"
    ["blog"]="https://www.anthropic.com/news"
    ["github_claude_code"]="https://github.com/anthropics/claude-code"
    ["github_sdk"]="https://github.com/anthropics/anthropic-sdk-python"
)

# Interest areas for Loa
INTEREST_AREAS=(
    "hooks"
    "tools"
    "context"
    "agents"
    "mcp"
    "memory"
    "skills"
    "commands"
    "slash commands"
    "settings"
    "configuration"
    "api"
    "sdk"
    "streaming"
    "batch"
    "vision"
    "files"
)

# Initialize cache directory (ORACLE-L-3: set restrictive umask before mkdir)
init_cache() {
    umask 077
    mkdir -p "$CACHE_DIR"
}

# Log to history
log_check() {
    local timestamp="$1"
    local source="$2"
    local status="$3"
    local findings="${4:-}"

    echo "{\"timestamp\": \"$timestamp\", \"source\": \"$source\", \"status\": \"$status\", \"findings\": \"$findings\"}" >> "$HISTORY_FILE"
}

# Show monitored sources
show_sources() {
    echo -e "${BOLD}${CYAN}Monitored Anthropic Sources${NC}"
    echo "─────────────────────────────────────────"
    echo ""

    for key in "${!SOURCES[@]}"; do
        local url="${SOURCES[$key]}"
        printf "  ${GREEN}%-20s${NC} %s\n" "$key" "$url"
    done

    echo ""
    echo -e "${BOLD}Interest Areas:${NC}"
    echo "  ${INTEREST_AREAS[*]}"
    echo ""
}

# Check if cache is valid
cache_valid() {
    local cache_file="$1"

    if [[ ! -f "$cache_file" ]]; then
        return 1
    fi

    local cache_age
    cache_age=$(( ($(date +%s) - $(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file")) / 3600 ))

    if [[ $cache_age -ge $CACHE_TTL_HOURS ]]; then
        return 1
    fi

    return 0
}

# Fetch URL content (for later processing by Claude)
fetch_source() {
    local name="$1"
    local url="$2"
    local cache_file="$CACHE_DIR/${name}.html"

    if cache_valid "$cache_file"; then
        echo "$cache_file"
        return 0
    fi

    # ORACLE-L-2: Add --fail-with-body to properly handle HTTP errors
    # HIGH-002 FIX: Enforce HTTPS and TLS 1.2+
    if curl -sL --proto =https --tlsv1.2 --fail-with-body --max-time 30 "$url" -o "$cache_file" 2>/dev/null; then
        echo "$cache_file"
        return 0
    else
        echo ""
        return 1
    fi
}

# Generate check manifest
generate_manifest() {
    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    cat << EOF
{
  "timestamp": "$timestamp",
  "sources": {
EOF

    local first=true
    for key in "${!SOURCES[@]}"; do
        if [[ "$first" != "true" ]]; then
            echo ","
        fi
        first=false
        printf '    "%s": "%s"' "$key" "${SOURCES[$key]}"
    done

    cat << EOF

  },
  "interest_areas": $(printf '%s\n' "${INTEREST_AREAS[@]}" | jq -R . | jq -s .),
  "loa_version": "$(cat "$PROJECT_ROOT/.loa-version.json" 2>/dev/null | jq -r '.framework_version' || echo 'unknown')",
  "instructions": "Analyze these sources for updates relevant to Loa framework. Focus on: new features, API changes, deprecations, best practices, and patterns that could enhance Loa's capabilities."
}
EOF
}

# Check for updates (outputs JSON manifest for Claude to process)
check_updates() {
    init_cache

    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    echo -e "${BOLD}${CYAN}Anthropic Oracle - Checking for Updates${NC}"
    echo "─────────────────────────────────────────"
    echo ""
    echo -e "Timestamp: ${BLUE}$timestamp${NC}"
    echo -e "Cache TTL: ${BLUE}${CACHE_TTL_HOURS}h${NC}"
    echo ""

    # Fetch each source
    local fetched=0
    local failed=0

    for key in "${!SOURCES[@]}"; do
        local url="${SOURCES[$key]}"
        echo -n "  Fetching $key... "

        if fetch_source "$key" "$url" > /dev/null; then
            echo -e "${GREEN}✓${NC}"
            ((fetched++))
        else
            echo -e "${YELLOW}⚠ (cached or failed)${NC}"
            ((failed++))
        fi
    done

    echo ""
    echo -e "Fetched: ${GREEN}$fetched${NC}, Skipped/Failed: ${YELLOW}$failed${NC}"
    echo ""

    # Generate manifest
    local manifest_file="$CACHE_DIR/manifest.json"
    generate_manifest > "$manifest_file"

    echo -e "Manifest: ${CYAN}$manifest_file${NC}"
    echo ""
    echo -e "${BOLD}Next Steps:${NC}"
    echo "  1. Run '/oracle-analyze' to have Claude analyze the fetched content"
    echo "  2. Or manually review cached content in: $CACHE_DIR"
    echo ""

    # Save last check info
    cat > "$LAST_CHECK_FILE" << EOF
{
  "timestamp": "$timestamp",
  "fetched": $fetched,
  "failed": $failed,
  "manifest": "$manifest_file"
}
EOF

    log_check "$timestamp" "all" "completed" "$fetched sources fetched"
}

# Show check history
show_history() {
    init_cache

    echo -e "${BOLD}${CYAN}Oracle Check History${NC}"
    echo "─────────────────────────────────────────"
    echo ""

    if [[ ! -f "$HISTORY_FILE" ]]; then
        echo "No history available."
        return 0
    fi

    # Show last 10 checks
    tail -n 10 "$HISTORY_FILE" | while read -r line; do
        local ts source status
        ts=$(echo "$line" | jq -r '.timestamp')
        source=$(echo "$line" | jq -r '.source')
        status=$(echo "$line" | jq -r '.status')

        printf "  ${BLUE}%-24s${NC} %-15s %s\n" "$ts" "$source" "$status"
    done

    echo ""
}

# Query sources based on scope
# Routes to appropriate indexer (loa-learnings-index.sh or grep on anthropic cache)
query_sources() {
    local terms="$1"
    local scope="${2:-all}"
    local format="${3:-text}"
    local limit="${4:-10}"
    local min_weight="${5:-0.0}"
    local indexer="${6:-auto}"

    local results=()
    local loa_results=""
    local anthropic_results=""

    # Query Loa sources
    if [[ "$scope" == "loa" || "$scope" == "all" ]]; then
        if [[ -x "$SCRIPT_DIR/loa-learnings-index.sh" ]]; then
            # Pass indexer flag to loa-learnings-index.sh
            loa_results=$("$SCRIPT_DIR/loa-learnings-index.sh" query "$terms" --format json --index "$indexer" 2>/dev/null || echo "[]")
        else
            # Fallback: grep-based search on Loa sources
            loa_results=$(query_loa_with_grep "$terms")
        fi
    fi

    # Query Anthropic sources (cached content)
    if [[ "$scope" == "anthropic" || "$scope" == "all" ]]; then
        anthropic_results=$(query_anthropic_cache "$terms")
    fi

    # Merge and rank results
    merge_and_rank "$loa_results" "$anthropic_results" "$format" "$limit" "$min_weight"
}

# Grep-based query for Loa sources (fallback when loa-learnings-index.sh not available)
query_loa_with_grep() {
    local terms="$1"
    local results="[]"

    # Convert OR-joined terms to grep pattern
    local pattern
    pattern=$(echo "$terms" | sed 's/|/\\|/g')

    cd "$PROJECT_ROOT" || return

    # Search skills (ORACLE-M-1: use find with -print0 and read -d '' to handle filenames safely)
    if [[ -d ".claude/skills" ]]; then
        while IFS= read -r -d '' match; do
            local snippet
            snippet=$(grep -i -m 1 "$pattern" "$match" 2>/dev/null | head -c 200 || true)
            results=$(echo "$results" | jq --arg file "$match" --arg snippet "$snippet" \
                '. + [{"source": "loa", "type": "skill", "file": $file, "snippet": $snippet, "score": 0.7, "weight": 1.0}]')
        done < <(find .claude/skills -name "*.md" -type f -exec grep -l -i "$pattern" {} + -print0 2>/dev/null || true)
    fi

    # Search feedback (ORACLE-M-1: use find with -print0 and read -d '' to handle filenames safely)
    if [[ -d "grimoires/loa/feedback" ]]; then
        while IFS= read -r -d '' match; do
            local snippet
            snippet=$(grep -i -m 1 "$pattern" "$match" 2>/dev/null | head -c 200 || true)
            results=$(echo "$results" | jq --arg file "$match" --arg snippet "$snippet" \
                '. + [{"source": "loa", "type": "feedback", "file": $file, "snippet": $snippet, "score": 0.8, "weight": 1.0}]')
        done < <(find grimoires/loa/feedback -name "*.yaml" -type f -exec grep -l -i "$pattern" {} + -print0 2>/dev/null || true)
    fi

    # Search decisions
    if [[ -f "grimoires/loa/decisions.yaml" ]]; then
        if grep -q -i "$pattern" grimoires/loa/decisions.yaml 2>/dev/null; then
            local snippet
            snippet=$(grep -i -m 1 "$pattern" grimoires/loa/decisions.yaml 2>/dev/null | head -c 200 || true)
            results=$(echo "$results" | jq --arg snippet "$snippet" \
                '. + [{"source": "loa", "type": "decision", "file": "grimoires/loa/decisions.yaml", "snippet": $snippet, "score": 0.9, "weight": 1.0}]')
        fi
    fi

    echo "$results"
}

# Query Anthropic cached content
query_anthropic_cache() {
    local terms="$1"
    local results="[]"

    # Convert OR-joined terms to grep pattern
    local pattern
    pattern=$(echo "$terms" | sed 's/|/\\|/g')

    if [[ ! -d "$CACHE_DIR" ]]; then
        echo "[]"
        return
    fi

    # Search cached HTML files
    for cache_file in "$CACHE_DIR"/*.html; do
        [[ -f "$cache_file" ]] || continue

        local name
        name=$(basename "$cache_file" .html)

        if grep -q -i "$pattern" "$cache_file" 2>/dev/null; then
            local snippet
            snippet=$(grep -i -m 1 "$pattern" "$cache_file" 2>/dev/null | sed 's/<[^>]*>//g' | head -c 200 || true)
            local url="${SOURCES[$name]:-unknown}"
            results=$(echo "$results" | jq --arg name "$name" --arg url "$url" --arg snippet "$snippet" \
                '. + [{"source": "anthropic", "type": "doc", "name": $name, "url": $url, "snippet": $snippet, "score": 0.6, "weight": 0.8}]')
        fi
    done

    echo "$results"
}

# Merge results from multiple sources and rank by weighted score
merge_and_rank() {
    local loa_results="${1:-[]}"
    local anthropic_results="${2:-[]}"
    local format="$3"
    local limit="$4"
    local min_weight="$5"

    # Merge arrays
    local merged
    merged=$(jq -n --argjson loa "$loa_results" --argjson anthropic "$anthropic_results" \
        '$loa + $anthropic')

    # Calculate weighted scores and filter
    local ranked
    ranked=$(echo "$merged" | jq --argjson min_weight "$min_weight" '
        [.[] |
            . + {weighted_score: (.score * .weight)} |
            select(.weight >= $min_weight)
        ] | sort_by(-.weighted_score)')

    # Apply limit
    local limited
    limited=$(echo "$ranked" | jq --argjson limit "$limit" '.[:$limit]')

    # Output based on format
    if [[ "$format" == "json" ]]; then
        echo "$limited"
    else
        # Text format
        local count
        count=$(echo "$limited" | jq 'length')

        if [[ "$count" == "0" ]]; then
            echo -e "${YELLOW}No results found.${NC}"
            return 4
        fi

        echo -e "${BOLD}${CYAN}Oracle Query Results${NC}"
        echo "─────────────────────────────────────────"
        echo ""

        echo "$limited" | jq -r '.[] | "\(.source)|\(.type)|\(.weighted_score)|\(.title // .file // .name // .source_file)|\(.trigger // .snippet // .solution // "")"' | \
        while IFS='|' read -r source type score title snippet; do
            local weight="${SOURCE_WEIGHTS[$source]:-0.5}"
            local color="${GREEN}"
            [[ "$source" == "anthropic" ]] && color="${BLUE}"
            [[ "$source" == "community" ]] && color="${YELLOW}"

            printf "  ${color}[%s]${NC} %-10s (%.2f) %s\n" "$source" "$type" "$score" "$title"
            if [[ -n "$snippet" && "$snippet" != "null" ]]; then
                printf "         ${CYAN}%s${NC}\n" "${snippet:0:80}..."
            fi
            echo ""
        done

        echo "─────────────────────────────────────────"
        echo -e "Results: ${GREEN}$count${NC} (limit: $limit, min-weight: $min_weight)"
    fi
}

# Parse query command arguments
parse_query_args() {
    local terms=""
    local scope=""
    local format="text"
    local limit=""
    local min_weight="0.0"
    local indexer=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --scope)
                scope="$2"
                shift 2
                ;;
            --format)
                format="$2"
                shift 2
                ;;
            --limit)
                limit="$2"
                shift 2
                ;;
            --min-weight)
                min_weight="$2"
                shift 2
                ;;
            --index)
                indexer="$2"
                shift 2
                ;;
            -*)
                echo -e "${RED}Unknown option: $1${NC}" >&2
                exit 1
                ;;
            *)
                if [[ -z "$terms" ]]; then
                    terms="$1"
                else
                    terms="$terms|$1"
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$terms" ]]; then
        echo -e "${RED}Error: Query terms required${NC}" >&2
        echo "Usage: anthropic-oracle.sh query <terms> [--scope loa|anthropic|all] [--format json|text] [--limit N] [--index auto|qmd|grep]" >&2
        exit 1
    fi

    # Read defaults from config if not specified
    if [[ -z "$scope" ]]; then
        scope=$(get_default_scope)
    fi
    if [[ -z "$limit" ]]; then
        limit=$(get_default_limit)
    fi
    if [[ -z "$indexer" ]]; then
        indexer=$(get_default_indexer)
    fi

    # Validate scope
    if [[ ! "$scope" =~ ^(loa|anthropic|all)$ ]]; then
        echo -e "${RED}Error: Invalid scope '$scope'. Use: loa, anthropic, or all${NC}" >&2
        exit 1
    fi

    # Validate indexer
    if [[ ! "$indexer" =~ ^(auto|qmd|grep)$ ]]; then
        echo -e "${RED}Error: Invalid indexer '$indexer'. Use: auto, qmd, or grep${NC}" >&2
        exit 1
    fi

    # Check QMD availability if requested
    if [[ "$indexer" == "qmd" ]] && ! qmd_available; then
        echo -e "${RED}Error: QMD requested but not available. Install qmd or use --index grep${NC}" >&2
        exit 1
    fi

    query_sources "$terms" "$scope" "$format" "$limit" "$min_weight" "$indexer"
}

# Generate research document template
generate_research_template() {
    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local date_short
    date_short=$(date +%Y-%m-%d)

    cat << 'EOF'
# Anthropic Updates Analysis

**Date**: DATE_PLACEHOLDER
**Oracle Run**: TIMESTAMP_PLACEHOLDER
**Analyst**: Claude (via Anthropic Oracle)

## Executive Summary

[Summary of findings from Anthropic's official sources]

---

## New Features Identified

### Feature 1: [Feature Name]

**Source**: [URL]
**Relevance to Loa**: [High/Medium/Low]

**Description**:
[What the feature does]

**Potential Integration**:
[How Loa could benefit]

**Implementation Effort**: [Low/Medium/High]

---

## API Changes

| Change | Type | Impact on Loa | Action Required |
|--------|------|---------------|-----------------|
| [Change] | [New/Modified/Deprecated] | [Description] | [Yes/No] |

---

## Deprecations & Breaking Changes

### [Deprecation Name]

**Effective Date**: [Date]
**Loa Impact**: [Description]
**Migration Path**: [Steps]

---

## Best Practices Updates

### [Practice Name]

**Previous Approach**: [What we did before]
**New Recommendation**: [What Anthropic now recommends]
**Loa Files Affected**: [List of files]

---

## Gaps Analysis

| Loa Feature | Anthropic Capability | Gap | Priority |
|-------------|---------------------|-----|----------|
| [Feature] | [What Anthropic offers] | [What's missing] | [P0-P3] |

---

## Recommended Actions

### Priority 1 (Immediate)

1. **[Action]**: [Description]
   - Effort: [Low/Medium/High]
   - Files: [Affected files]

### Priority 2 (Next Release)

1. **[Action]**: [Description]

### Priority 3 (Future)

1. **[Action]**: [Description]

---

## Sources Analyzed

- [Source 1](URL)
- [Source 2](URL)

---

## Next Oracle Run

Recommended: [Date] or when Anthropic announces major updates.
EOF
}

# Main
main() {
    local command="${1:-help}"

    case "$command" in
        check)
            check_updates
            ;;
        sources)
            show_sources
            ;;
        history)
            show_history
            ;;
        template)
            generate_research_template
            ;;
        query)
            shift
            parse_query_args "$@"
            ;;
        generate)
            echo -e "${YELLOW}Note:${NC} Use '/oracle-analyze' command in Claude Code to generate research PR."
            echo ""
            echo "This command fetches sources and prepares them for Claude to analyze."
            echo "Run 'anthropic-oracle.sh check' first, then '/oracle-analyze' in Claude Code."
            ;;
        help|--help|-h)
            cat << 'HELP'
anthropic-oracle.sh - Monitor Anthropic updates and query Loa learnings

Usage:
  anthropic-oracle.sh check                    Check for updates (fetch Anthropic sources)
  anthropic-oracle.sh sources                  List monitored sources
  anthropic-oracle.sh history                  Show previous checks
  anthropic-oracle.sh template                 Output research document template
  anthropic-oracle.sh query <terms> [options]  Query knowledge sources

Query Command:
  anthropic-oracle.sh query "auth token" --scope loa      # Query Loa learnings only
  anthropic-oracle.sh query "hooks" --scope anthropic     # Query Anthropic docs only
  anthropic-oracle.sh query "agents|mcp" --scope all      # Query all sources (default)

Query Options:
  --scope <all|loa|anthropic>   Source scope: all (Recommended), loa, anthropic
  --format <text|json>          Output format: text (Recommended), json
  --limit <N>                   Max results (default: 10)
  --min-weight <0.0-1.0>        Minimum source weight filter
  --index <auto|qmd|grep>       Indexer: auto (Recommended), qmd, grep
                                auto: use QMD if available, fallback to grep
                                qmd: require QMD semantic search
                                grep: force grep-based search

Source Weights:
  loa       1.0   Loa's own compound learnings (highest priority)
  anthropic 0.8   Anthropic official documentation
  community 0.5   Community contributions

Environment Variables:
  ANTHROPIC_ORACLE_CACHE   Cache directory (default: ~/.loa/cache/oracle)
  ANTHROPIC_ORACLE_TTL     Cache TTL in hours (default: 24)

Workflows:
  Anthropic Updates:
    1. Run 'anthropic-oracle.sh check' to fetch latest content
    2. Run '/oracle-analyze' in Claude Code to analyze and generate PR

  Loa Learnings Query:
    1. Run 'loa-learnings-index.sh index' to build/update index
    2. Run 'anthropic-oracle.sh query <terms> --scope loa'

HELP
            ;;
        *)
            echo -e "${RED}Unknown command: $command${NC}"
            echo "Run 'anthropic-oracle.sh help' for usage"
            exit 1
            ;;
    esac
}

main "$@"
