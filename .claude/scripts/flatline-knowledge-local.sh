#!/usr/bin/env bash
# =============================================================================
# flatline-knowledge-local.sh - Local grimoire knowledge retrieval
# =============================================================================
# Version: 1.0.0
# Part of: Flatline Protocol v1.17.0
#
# Usage:
#   flatline-knowledge-local.sh --domain <text> --phase <type> [options]
#
# Options:
#   --domain <text>       Domain keywords for search (required)
#   --phase <type>        Phase type: prd, sdd, sprint (required)
#   --limit <n>           Max results per source (default: 10)
#   --format <format>     Output format: text, json, markdown (default: markdown)
#   --track               Track query for effectiveness metrics
#
# Sources (Priority Order):
#   1. Framework Learnings (.claude/loa/learnings/) - weight 1.0
#   2. Project Learnings (grimoires/loa/a2a/compound/) - weight 0.9
#   3. Context Docs (grimoires/loa/context/) - weight 0.8
#   4. Decisions (grimoires/loa/decisions.yaml) - weight 0.8
#   5. Feedback (grimoires/loa/feedback/) - weight 0.7
#
# Exit codes:
#   0 - Success (results found)
#   0 - Success (no results, empty output)
#   1 - Invalid arguments
#   2 - Search error
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_FILE="$PROJECT_ROOT/.loa.config.yaml"

# Source directories
FRAMEWORK_LEARNINGS_DIR="$PROJECT_ROOT/.claude/loa/learnings"
PROJECT_LEARNINGS_DIR="$PROJECT_ROOT/grimoires/loa/a2a/compound"
CONTEXT_DIR="$PROJECT_ROOT/grimoires/loa/context"
DECISIONS_FILE="$PROJECT_ROOT/grimoires/loa/decisions.yaml"
FEEDBACK_DIR="$PROJECT_ROOT/grimoires/loa/feedback"

# Default weights
FRAMEWORK_WEIGHT=1.0
PROJECT_WEIGHT=0.9
CONTEXT_WEIGHT=0.8
DECISIONS_WEIGHT=0.8
FEEDBACK_WEIGHT=0.7

# Scripts
LOA_LEARNINGS_INDEX="$SCRIPT_DIR/loa-learnings-index.sh"
SEARCH_ORCHESTRATOR="$SCRIPT_DIR/search-orchestrator.sh"

# =============================================================================
# Logging
# =============================================================================

log() {
    echo "[flatline-knowledge] $*" >&2
}

error() {
    echo "ERROR: $*" >&2
}

# =============================================================================
# Configuration
# =============================================================================

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

# =============================================================================
# Search Functions
# =============================================================================

# Search framework learnings using existing index
search_framework_learnings() {
    local domain="$1"
    local phase="$2"
    local limit="$3"

    if [[ ! -d "$FRAMEWORK_LEARNINGS_DIR" ]]; then
        return 0
    fi

    local results=()

    # Search patterns.json
    if [[ -f "$FRAMEWORK_LEARNINGS_DIR/patterns.json" ]]; then
        local patterns
        patterns=$(jq -r --arg d "$domain" --arg p "$phase" '
            .patterns[] |
            select(
                (.title | ascii_downcase | contains($d | ascii_downcase)) or
                (.description | ascii_downcase | contains($d | ascii_downcase)) or
                (.tags[]? | ascii_downcase | contains($d | ascii_downcase)) or
                (.phases[]? | ascii_downcase | contains($p | ascii_downcase))
            ) |
            {
                type: "pattern",
                title: .title,
                description: .description,
                source: "framework/patterns.json",
                weight: 1.0
            }
        ' "$FRAMEWORK_LEARNINGS_DIR/patterns.json" 2>/dev/null | head -n "$limit")
        [[ -n "$patterns" ]] && results+=("$patterns")
    fi

    # Search anti-patterns.json
    if [[ -f "$FRAMEWORK_LEARNINGS_DIR/anti-patterns.json" ]]; then
        local anti_patterns
        anti_patterns=$(jq -r --arg d "$domain" '
            .anti_patterns[] |
            select(
                (.title | ascii_downcase | contains($d | ascii_downcase)) or
                (.description | ascii_downcase | contains($d | ascii_downcase)) or
                (.tags[]? | ascii_downcase | contains($d | ascii_downcase))
            ) |
            {
                type: "anti-pattern",
                title: .title,
                description: .description,
                source: "framework/anti-patterns.json",
                weight: 1.0
            }
        ' "$FRAMEWORK_LEARNINGS_DIR/anti-patterns.json" 2>/dev/null | head -n "$limit")
        [[ -n "$anti_patterns" ]] && results+=("$anti_patterns")
    fi

    # Search decisions.json
    if [[ -f "$FRAMEWORK_LEARNINGS_DIR/decisions.json" ]]; then
        local decisions
        decisions=$(jq -r --arg d "$domain" '
            .decisions[] |
            select(
                (.title | ascii_downcase | contains($d | ascii_downcase)) or
                (.rationale | ascii_downcase | contains($d | ascii_downcase)) or
                (.context | ascii_downcase | contains($d | ascii_downcase))
            ) |
            {
                type: "decision",
                title: .title,
                description: .rationale,
                source: "framework/decisions.json",
                weight: 1.0
            }
        ' "$FRAMEWORK_LEARNINGS_DIR/decisions.json" 2>/dev/null | head -n "$limit")
        [[ -n "$decisions" ]] && results+=("$decisions")
    fi

    # Search troubleshooting.json
    if [[ -f "$FRAMEWORK_LEARNINGS_DIR/troubleshooting.json" ]]; then
        local troubleshooting
        troubleshooting=$(jq -r --arg d "$domain" '
            .issues[] |
            select(
                (.problem | ascii_downcase | contains($d | ascii_downcase)) or
                (.solution | ascii_downcase | contains($d | ascii_downcase)) or
                (.symptoms[]? | ascii_downcase | contains($d | ascii_downcase))
            ) |
            {
                type: "troubleshooting",
                title: .problem,
                description: .solution,
                source: "framework/troubleshooting.json",
                weight: 1.0
            }
        ' "$FRAMEWORK_LEARNINGS_DIR/troubleshooting.json" 2>/dev/null | head -n "$limit")
        [[ -n "$troubleshooting" ]] && results+=("$troubleshooting")
    fi

    # Output combined results
    printf '%s\n' "${results[@]}" 2>/dev/null | jq -s 'add // []' 2>/dev/null || echo "[]"
}

# Search project learnings
search_project_learnings() {
    local domain="$1"
    local limit="$2"

    local learnings_file="$PROJECT_LEARNINGS_DIR/learnings.json"
    if [[ ! -f "$learnings_file" ]]; then
        echo "[]"
        return 0
    fi

    jq -r --arg d "$domain" --argjson limit "$limit" '
        [.learnings[]? |
        select(
            (.title | ascii_downcase | contains($d | ascii_downcase)) or
            (.description | ascii_downcase | contains($d | ascii_downcase)) or
            (.tags[]? | ascii_downcase | contains($d | ascii_downcase))
        ) |
        {
            type: "project-learning",
            title: .title,
            description: .description,
            source: "project/learnings.json",
            weight: 0.9,
            effectiveness: .effectiveness.score
        }] | .[:$limit]
    ' "$learnings_file" 2>/dev/null || echo "[]"
}

# Search context documents
search_context_docs() {
    local domain="$1"
    local limit="$2"

    if [[ ! -d "$CONTEXT_DIR" ]]; then
        echo "[]"
        return 0
    fi

    local results=()
    local count=0

    # Use grep to find matching files
    while IFS= read -r file; do
        [[ $count -ge $limit ]] && break

        local filename
        filename=$(basename "$file")
        local title="${filename%.md}"

        # Extract first paragraph as description
        local description
        description=$(head -n 20 "$file" | grep -v '^#' | grep -v '^$' | head -n 3 | tr '\n' ' ' | cut -c1-200)

        results+=("$(jq -n \
            --arg type "context" \
            --arg title "$title" \
            --arg desc "$description" \
            --arg src "context/$filename" \
            --argjson weight 0.8 \
            '{type: $type, title: $title, description: $desc, source: $src, weight: $weight}')")

        ((count++))
    # Security: Use grep -F (fixed strings) to prevent regex injection
    done < <(grep -Fril "$domain" "$CONTEXT_DIR"/*.md 2>/dev/null || true)

    if [[ ${#results[@]} -gt 0 ]]; then
        printf '%s\n' "${results[@]}" | jq -s '.'
    else
        echo "[]"
    fi
}

# Search decisions file
search_decisions() {
    local domain="$1"
    local limit="$2"

    if [[ ! -f "$DECISIONS_FILE" ]]; then
        echo "[]"
        return 0
    fi

    # Convert YAML to JSON and search
    if command -v yq &> /dev/null; then
        yq -o=json '.' "$DECISIONS_FILE" 2>/dev/null | jq -r --arg d "$domain" --argjson limit "$limit" '
            [.decisions[]? |
            select(
                (.title | ascii_downcase | contains($d | ascii_downcase)) or
                (.rationale | ascii_downcase | contains($d | ascii_downcase)) or
                (.context | ascii_downcase | contains($d | ascii_downcase))
            ) |
            {
                type: "decision",
                title: .title,
                description: .rationale,
                source: "decisions.yaml",
                weight: 0.8
            }] | .[:$limit]
        ' 2>/dev/null || echo "[]"
    else
        echo "[]"
    fi
}

# Search feedback files
search_feedback() {
    local domain="$1"
    local limit="$2"

    if [[ ! -d "$FEEDBACK_DIR" ]]; then
        echo "[]"
        return 0
    fi

    local results=()
    local count=0

    for file in "$FEEDBACK_DIR"/*.yaml; do
        [[ -f "$file" ]] || continue
        [[ $count -ge $limit ]] && break

        # Search feedback content (use -F for fixed strings to prevent regex injection)
        if grep -Fqi "$domain" "$file" 2>/dev/null; then
            local filename
            filename=$(basename "$file")

            if command -v yq &> /dev/null; then
                local title description
                title=$(yq -r '.title // .summary // "Feedback"' "$file" 2>/dev/null)
                description=$(yq -r '.description // .content // ""' "$file" 2>/dev/null | head -c 200)

                results+=("$(jq -n \
                    --arg type "feedback" \
                    --arg title "$title" \
                    --arg desc "$description" \
                    --arg src "feedback/$filename" \
                    --argjson weight 0.7 \
                    '{type: $type, title: $title, description: $desc, source: $src, weight: $weight}')")

                ((count++))
            fi
        fi
    done

    if [[ ${#results[@]} -gt 0 ]]; then
        printf '%s\n' "${results[@]}" | jq -s '.'
    else
        echo "[]"
    fi
}

# =============================================================================
# Output Formatting
# =============================================================================

format_as_markdown() {
    local results="$1"
    local domain="$2"
    local phase="$3"

    local total
    total=$(echo "$results" | jq 'length')

    cat <<EOF
## Knowledge Context for ${phase^^} Review

**Domain:** $domain
**Phase:** $phase
**Sources:** $total results

EOF

    # Group by type
    local patterns anti_patterns decisions troubleshooting learnings context feedback

    patterns=$(echo "$results" | jq '[.[] | select(.type == "pattern")]')
    anti_patterns=$(echo "$results" | jq '[.[] | select(.type == "anti-pattern")]')
    decisions=$(echo "$results" | jq '[.[] | select(.type == "decision")]')
    troubleshooting=$(echo "$results" | jq '[.[] | select(.type == "troubleshooting")]')
    learnings=$(echo "$results" | jq '[.[] | select(.type == "project-learning")]')
    context=$(echo "$results" | jq '[.[] | select(.type == "context")]')
    feedback=$(echo "$results" | jq '[.[] | select(.type == "feedback")]')

    # Output each category
    if [[ $(echo "$patterns" | jq 'length') -gt 0 ]]; then
        echo "### Relevant Patterns"
        echo ""
        echo "$patterns" | jq -r '.[] | "- **\(.title)** (score: \(.weight))\n  > \(.description)\n  > Source: `\(.source)`\n"'
    fi

    if [[ $(echo "$anti_patterns" | jq 'length') -gt 0 ]]; then
        echo "### Anti-Patterns to Avoid"
        echo ""
        echo "$anti_patterns" | jq -r '.[] | "- **\(.title)** (score: \(.weight))\n  > \(.description)\n  > Source: `\(.source)`\n"'
    fi

    if [[ $(echo "$decisions" | jq 'length') -gt 0 ]]; then
        echo "### Relevant Decisions"
        echo ""
        echo "$decisions" | jq -r '.[] | "- **\(.title)** (score: \(.weight))\n  > \(.description)\n  > Source: `\(.source)`\n"'
    fi

    if [[ $(echo "$troubleshooting" | jq 'length') -gt 0 ]]; then
        echo "### Troubleshooting Knowledge"
        echo ""
        echo "$troubleshooting" | jq -r '.[] | "- **\(.title)** (score: \(.weight))\n  > \(.description)\n  > Source: `\(.source)`\n"'
    fi

    if [[ $(echo "$learnings" | jq 'length') -gt 0 ]]; then
        echo "### Project Learnings"
        echo ""
        echo "$learnings" | jq -r '.[] | "- **\(.title)** (score: \(.weight), effectiveness: \(.effectiveness // "N/A"))\n  > \(.description)\n  > Source: `\(.source)`\n"'
    fi

    if [[ $(echo "$context" | jq 'length') -gt 0 ]]; then
        echo "### Domain Context"
        echo ""
        echo "$context" | jq -r '.[] | "- **\(.title)** (score: \(.weight))\n  > \(.description)\n  > Source: `\(.source)`\n"'
    fi

    if [[ $(echo "$feedback" | jq 'length') -gt 0 ]]; then
        echo "### Relevant Feedback"
        echo ""
        echo "$feedback" | jq -r '.[] | "- **\(.title)** (score: \(.weight))\n  > \(.description)\n  > Source: `\(.source)`\n"'
    fi
}

format_as_text() {
    local results="$1"
    local domain="$2"
    local phase="$3"

    echo "Knowledge Context for $phase review (domain: $domain)"
    echo "=================================================="
    echo ""

    echo "$results" | jq -r '.[] | "[\(.type)] \(.title)\n  \(.description)\n  Source: \(.source)\n"'
}

# =============================================================================
# Main
# =============================================================================

usage() {
    cat <<EOF
Usage: flatline-knowledge-local.sh --domain <text> --phase <type> [options]

Required:
  --domain <text>       Domain keywords for search
  --phase <type>        Phase type: prd, sdd, sprint

Options:
  --limit <n>           Max results per source (default: 10)
  --format <format>     Output format: text, json, markdown (default: markdown)
  --track               Track query for effectiveness metrics
  -h, --help            Show this help

Sources Searched (Priority Order):
  1. Framework Learnings (.claude/loa/learnings/) - weight 1.0
  2. Project Learnings (grimoires/loa/a2a/compound/) - weight 0.9
  3. Context Docs (grimoires/loa/context/) - weight 0.8
  4. Decisions (grimoires/loa/decisions.yaml) - weight 0.8
  5. Feedback (grimoires/loa/feedback/) - weight 0.7

Example:
  flatline-knowledge-local.sh --domain "crypto wallet" --phase prd --format markdown
EOF
}

main() {
    local domain=""
    local phase=""
    local limit=10
    local format="markdown"
    local track=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --domain)
                domain="$2"
                shift 2
                ;;
            --phase)
                phase="$2"
                shift 2
                ;;
            --limit)
                limit="$2"
                shift 2
                ;;
            --format)
                format="$2"
                shift 2
                ;;
            --track)
                track=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done

    # Validate required arguments
    if [[ -z "$domain" ]]; then
        error "Domain required (--domain)"
        usage
        exit 1
    fi

    if [[ -z "$phase" ]]; then
        error "Phase required (--phase)"
        usage
        exit 1
    fi

    if [[ "$phase" != "prd" && "$phase" != "sdd" && "$phase" != "sprint" ]]; then
        error "Invalid phase: $phase (expected: prd, sdd, sprint)"
        exit 1
    fi

    log "Searching for: $domain (phase: $phase, limit: $limit)"

    # Search all sources
    local framework_results project_results context_results decisions_results feedback_results

    framework_results=$(search_framework_learnings "$domain" "$phase" "$limit")
    project_results=$(search_project_learnings "$domain" "$limit")
    context_results=$(search_context_docs "$domain" "$limit")
    decisions_results=$(search_decisions "$domain" "$limit")
    feedback_results=$(search_feedback "$domain" "$limit")

    # Merge all results
    local all_results
    all_results=$(echo "[$framework_results, $project_results, $context_results, $decisions_results, $feedback_results]" | \
        jq 'add | sort_by(-.weight) | unique_by(.title)')

    local total
    total=$(echo "$all_results" | jq 'length')
    log "Found $total results"

    # Output in requested format
    case "$format" in
        json)
            echo "$all_results" | jq .
            ;;
        markdown)
            format_as_markdown "$all_results" "$domain" "$phase"
            ;;
        text)
            format_as_text "$all_results" "$domain" "$phase"
            ;;
        *)
            error "Unknown format: $format"
            exit 1
            ;;
    esac

    # Track query if requested
    if [[ "$track" == "true" ]]; then
        log "Query tracking not yet implemented"
    fi
}

main "$@"
