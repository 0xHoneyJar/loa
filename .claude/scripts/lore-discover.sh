#!/usr/bin/env bash
# lore-discover.sh - Pattern Discovery Extractor for Bidirectional Lore
#
# Processes Bridgebuilder review files to extract patterns worthy of becoming
# lore entries. Reads bridge review findings (PRAISE severity) and full prose
# reviews, identifies architectural patterns and teachable moments, and outputs
# candidate lore entries in YAML format.
#
# Usage:
#   lore-discover.sh                       # Extract from all bridge reviews
#   lore-discover.sh --bridge-id ID        # Extract from specific bridge
#   lore-discover.sh --dry-run             # Show candidates without writing
#   lore-discover.sh --output FILE         # Write to specific file
#
# Exit codes:
#   0 - Success (candidates found or not)
#   1 - Invalid arguments

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source bootstrap for PROJECT_ROOT
if [[ -f "$SCRIPT_DIR/bootstrap.sh" ]]; then
    source "$SCRIPT_DIR/bootstrap.sh"
fi

PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"

# ─────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────

REVIEWS_DIR="${PROJECT_ROOT}/.run/bridge-reviews"
LORE_DIR="${PROJECT_ROOT}/.claude/data/lore"
DISCOVERED_DIR="${LORE_DIR}/discovered"
OUTPUT_FILE="${DISCOVERED_DIR}/patterns.yaml"

DRY_RUN=false
BRIDGE_ID=""

# ─────────────────────────────────────────────────────────
# Argument Parsing
# ─────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=true; shift ;;
        --bridge-id) BRIDGE_ID="$2"; shift 2 ;;
        --output) OUTPUT_FILE="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: lore-discover.sh [--dry-run] [--bridge-id ID] [--output FILE]"
            echo "  --dry-run       Show candidates without writing"
            echo "  --bridge-id ID  Extract from specific bridge only"
            echo "  --output FILE   Write to specific file"
            exit 0
            ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

# ─────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────

# Slugify a title into a lore entry ID
slugify() {
    echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//' | head -c 40
}

# Map finding category to lore tags
map_tags() {
    local category="$1"
    local severity="${2:-}"

    local tags="discovered"
    case "$category" in
        security) tags="$tags, security" ;;
        architecture|design) tags="$tags, architecture" ;;
        logic|completeness) tags="$tags, architecture" ;;
        portability|reliability) tags="$tags, architecture" ;;
        documentation) tags="$tags, naming" ;;
        *) tags="$tags, architecture" ;;
    esac

    echo "[$tags]"
}

# ─────────────────────────────────────────────────────────
# Pattern Extraction
# ─────────────────────────────────────────────────────────

# Extract PRAISE findings from JSON files as validated good practices
extract_praise_patterns() {
    local findings_files

    if [[ -n "$BRIDGE_ID" ]]; then
        findings_files=$(find "$REVIEWS_DIR" -name "${BRIDGE_ID}*-findings.json" 2>/dev/null)
    else
        findings_files=$(find "$REVIEWS_DIR" -name "*-findings.json" 2>/dev/null)
    fi

    if [[ -z "$findings_files" ]]; then
        return
    fi

    while IFS= read -r file; do
        local bridge_id_from_file pr_ref

        # Extract bridge ID from filename: bridge-YYYYMMDD-HASH-iterN-findings.json
        bridge_id_from_file=$(basename "$file" | sed 's/-iter[0-9]*-findings.json//')

        # Extract PRAISE findings
        jq -r '.findings[]? | select(.severity == "PRAISE") | @json' "$file" 2>/dev/null | while IFS= read -r finding; do
            local title category
            title=$(echo "$finding" | jq -r '.title // ""')
            category=$(echo "$finding" | jq -r '.category // "architecture"')

            if [[ -z "$title" ]]; then
                continue
            fi

            local entry_id
            entry_id=$(slugify "$title")

            echo "  - id: $entry_id"
            echo "    term: \"$(echo "$title" | head -c 60)\""
            echo "    short: \"Validated practice: $title\""
            echo "    context: |"
            echo "      Discovered as a PRAISE finding during bridge review."
            echo "      Source bridge: $bridge_id_from_file"
            echo "    source: \"Bridge review $bridge_id_from_file\""
            echo "    tags: $(map_tags "$category" "PRAISE")"
            echo ""
        done
    done <<< "$findings_files"
}

# Extract recurring patterns from full review prose
extract_prose_patterns() {
    local review_files

    if [[ -n "$BRIDGE_ID" ]]; then
        review_files=$(find "$REVIEWS_DIR" -name "${BRIDGE_ID}*-full.md" 2>/dev/null)
    else
        # Only process the most recent 10 reviews to keep output manageable
        review_files=$(find "$REVIEWS_DIR" -name "*-full.md" -type f 2>/dev/null | sort -r | head -10)
    fi

    if [[ -z "$review_files" ]]; then
        return
    fi

    # Look for recurring architectural patterns mentioned across reviews
    # Pattern: lines containing "pattern", "paradigm", "principle", "architecture"
    local pattern_mentions
    pattern_mentions=$(echo "$review_files" | xargs grep -hioP '(?:pattern|paradigm|principle|architecture|cascade|pipeline|isolation|convergence)[\s:]+[^.]+\.' 2>/dev/null | \
        sort | uniq -c | sort -rn | head -5) || true

    # Output is informational — shows what patterns recur across reviews
    if [[ -n "$pattern_mentions" ]]; then
        echo "  # Recurring patterns detected in bridge review prose:"
        echo "$pattern_mentions" | while IFS= read -r line; do
            local count pattern
            count=$(echo "$line" | awk '{print $1}')
            pattern=$(echo "$line" | sed 's/^ *[0-9]* *//' | head -c 80)
            if [[ "$count" -ge 2 ]]; then
                echo "  # [$count occurrences] $pattern"
            fi
        done
        echo ""
    fi
}

# ─────────────────────────────────────────────────────────
# Output Generation
# ─────────────────────────────────────────────────────────

generate_output() {
    echo "# Discovered Patterns — Auto-extracted from Bridge Reviews"
    echo "# Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "# Source: lore-discover.sh"
    echo "#"
    echo "# These entries were extracted from Bridgebuilder review findings"
    echo "# (PRAISE severity = validated good practices, patterns = recurring themes)"
    echo ""
    echo "entries:"

    extract_praise_patterns
    extract_prose_patterns
}

# ─────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────

if [[ ! -d "$REVIEWS_DIR" ]]; then
    echo "No bridge reviews found at $REVIEWS_DIR" >&2
    echo "Run a bridge loop first to generate review data." >&2
    exit 0
fi

output=$(generate_output)

candidate_count=$(echo "$output" | grep -c "^  - id:" || true)

if [[ "$DRY_RUN" == "true" ]]; then
    echo "=== Lore Discovery (dry-run) ==="
    echo "Reviews directory: $REVIEWS_DIR"
    echo "Candidates found: $candidate_count"
    echo ""
    echo "$output"
    echo ""
    echo "=== End dry-run (no files written) ==="
else
    mkdir -p "$(dirname "$OUTPUT_FILE")"
    echo "$output" > "$OUTPUT_FILE"
    echo "Wrote $candidate_count lore candidates to $OUTPUT_FILE"
fi
