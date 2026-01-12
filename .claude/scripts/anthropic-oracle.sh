#!/usr/bin/env bash
# anthropic-oracle.sh - Monitor Anthropic updates for Loa improvements
#
# This script checks Anthropic's official sources for updates that could
# benefit Loa and generates research documents for review.
#
# Usage:
#   anthropic-oracle.sh check          # Check for updates (outputs JSON)
#   anthropic-oracle.sh sources        # List monitored sources
#   anthropic-oracle.sh generate       # Generate research PR (requires Claude)
#   anthropic-oracle.sh history        # Show previous checks
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

# Anthropic sources to monitor
declare -A SOURCES=(
    ["docs"]="https://docs.anthropic.com/en/docs/claude-code"
    ["changelog"]="https://docs.anthropic.com/en/release-notes/claude-code"
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

# Initialize cache directory
init_cache() {
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

    if curl -sL --max-time 30 "$url" -o "$cache_file" 2>/dev/null; then
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
        generate)
            echo -e "${YELLOW}Note:${NC} Use '/oracle-analyze' command in Claude Code to generate research PR."
            echo ""
            echo "This command fetches sources and prepares them for Claude to analyze."
            echo "Run 'anthropic-oracle.sh check' first, then '/oracle-analyze' in Claude Code."
            ;;
        help|--help|-h)
            cat << 'HELP'
anthropic-oracle.sh - Monitor Anthropic updates for Loa improvements

Usage:
  anthropic-oracle.sh check      Check for updates (fetch sources)
  anthropic-oracle.sh sources    List monitored sources
  anthropic-oracle.sh history    Show previous checks
  anthropic-oracle.sh template   Output research document template
  anthropic-oracle.sh generate   Instructions for generating research PR

Environment Variables:
  ANTHROPIC_ORACLE_CACHE   Cache directory (default: ~/.loa/cache/oracle)
  ANTHROPIC_ORACLE_TTL     Cache TTL in hours (default: 24)

Workflow:
  1. Run 'anthropic-oracle.sh check' to fetch latest content
  2. Run '/oracle-analyze' in Claude Code to analyze and generate PR
  3. Review generated research document
  4. Merge PR if improvements are valuable

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
