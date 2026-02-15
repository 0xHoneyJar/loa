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
OVERWRITE=false

# ─────────────────────────────────────────────────────────
# Argument Parsing
# ─────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=true; shift ;;
        --bridge-id) BRIDGE_ID="$2"; shift 2 ;;
        --output) OUTPUT_FILE="$2"; shift 2 ;;
        --overwrite) OVERWRITE=true; shift ;;
        -h|--help)
            echo "Usage: lore-discover.sh [--dry-run] [--bridge-id ID] [--output FILE] [--overwrite]"
            echo "  --dry-run       Show candidates without writing"
            echo "  --bridge-id ID  Extract from specific bridge only"
            echo "  --output FILE   Write to specific file"
            echo "  --overwrite     Overwrite output file instead of appending (destructive)"
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
            local title category source_model
            title=$(echo "$finding" | jq -r '.title // ""')
            category=$(echo "$finding" | jq -r '.category // "architecture"')
            # Extract source model from finding metadata if available
            source_model=$(echo "$finding" | jq -r '.source_model // .model // empty' 2>/dev/null || true)
            source_model="${source_model:-unknown}"
            # Escape double quotes in source_model to prevent YAML corruption
            source_model=$(echo "$source_model" | sed 's/"/\\"/g')

            if [[ -z "$title" ]]; then
                continue
            fi

            local entry_id safe_title
            entry_id=$(slugify "$title")
            # Escape double quotes in title to prevent YAML corruption
            safe_title=$(echo "$title" | sed 's/"/\\"/g' | head -c 60)

            echo "  - id: $entry_id"
            echo "    term: \"$safe_title\""
            echo "    short: \"Validated practice: $safe_title\""
            echo "    context: |"
            echo "      Discovered as a PRAISE finding during bridge review."
            echo "      Source bridge: $bridge_id_from_file"
            echo "    source: \"Bridge review $bridge_id_from_file\""
            echo "    source_model: \"$source_model\""
            echo "    tags: $(map_tags "$category" "PRAISE")"
            echo ""
        done
    done <<< "$findings_files"
}

# EXPERIMENTAL: keyword-based extraction from review prose. Expect noise in results.
# This heuristic approach matches on architectural keywords and counts occurrences.
# Future: ML-based or LLM-assisted extraction for higher signal-to-noise ratio.
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
# Deduplication
# ─────────────────────────────────────────────────────────

# Extract existing entry IDs from the output file.
# Returns one ID per line.
get_existing_ids() {
    if [[ ! -f "$OUTPUT_FILE" ]]; then
        return
    fi
    grep '^ *- id:' "$OUTPUT_FILE" 2>/dev/null | sed 's/.*id: *//' | sed 's/ *$//'
}

# Filter new entries, removing any whose IDs already exist.
# Reads new YAML entries from stdin, outputs only non-duplicate entries.
dedup_entries() {
    local existing_ids="$1"
    local new_count=0
    local dup_count=0
    local in_entry=false
    local current_entry=""
    local current_id=""

    while IFS= read -r line; do
        # Detect entry start
        if echo "$line" | grep -q '^ *- id:'; then
            # Flush previous entry if it was non-duplicate
            if [[ -n "$current_entry" && -n "$current_id" ]]; then
                if echo "$existing_ids" | grep -qxF "$current_id"; then
                    dup_count=$((dup_count + 1))
                else
                    echo "$current_entry"
                    new_count=$((new_count + 1))
                fi
            fi
            current_id=$(echo "$line" | sed 's/.*id: *//' | sed 's/ *$//')
            current_entry="$line"
            in_entry=true
        elif [[ "$in_entry" == "true" ]]; then
            # Lines belonging to current entry (indented or blank)
            if echo "$line" | grep -qE '^  [a-z]|^    |^$'; then
                current_entry="${current_entry}
${line}"
            else
                # Non-entry line (comment etc) — flush current entry
                if [[ -n "$current_entry" && -n "$current_id" ]]; then
                    if echo "$existing_ids" | grep -qxF "$current_id"; then
                        dup_count=$((dup_count + 1))
                    else
                        echo "$current_entry"
                        new_count=$((new_count + 1))
                    fi
                fi
                current_entry=""
                current_id=""
                in_entry=false
                echo "$line"
            fi
        else
            echo "$line"
        fi
    done

    # Flush last entry
    if [[ -n "$current_entry" && -n "$current_id" ]]; then
        if echo "$existing_ids" | grep -qxF "$current_id"; then
            dup_count=$((dup_count + 1))
        else
            echo "$current_entry"
            new_count=$((new_count + 1))
        fi
    fi

    # Output counts on stderr for the caller to parse
    echo "NEW:$new_count DUP:$dup_count" >&2
}

# ─────────────────────────────────────────────────────────
# Append with Deduplication (default write mode)
# ─────────────────────────────────────────────────────────

# Append new lore entries to the output file, skipping duplicates by ID.
# Args: $1 = full generated output, $2 = candidate count from generation
append_with_dedup() {
    local output="$1"
    local candidate_count="$2"

    mkdir -p "$(dirname "$OUTPUT_FILE")"

    if [[ ! -f "$OUTPUT_FILE" ]] || [[ ! -s "$OUTPUT_FILE" ]]; then
        # No existing file — write fresh
        echo "$output" > "$OUTPUT_FILE"
        echo "$candidate_count new, 0 duplicates skipped, $candidate_count total"
        return
    fi

    # Extract existing entry IDs and count
    local existing_ids existing_count
    existing_ids=$(get_existing_ids)
    existing_count=$(echo "$existing_ids" | grep -c . 2>/dev/null || echo "0")

    # Extract just the entries portion from new output
    local new_entries
    new_entries=$(echo "$output" | sed -n '/^entries:/,$ p' | tail -n +2)

    if [[ -z "$new_entries" ]]; then
        echo "0 new, 0 duplicates skipped, $existing_count total"
        return
    fi

    # Run dedup and capture both output and stats
    local deduped_entries dedup_stderr stats
    dedup_stderr=$(mktemp)
    deduped_entries=$(echo "$new_entries" | dedup_entries "$existing_ids" 2>"$dedup_stderr")
    stats=$(cat "$dedup_stderr")
    rm -f "$dedup_stderr"

    local new_count dup_count
    new_count=$(echo "$stats" | grep -oP 'NEW:\K[0-9]+' || echo "0")
    dup_count=$(echo "$stats" | grep -oP 'DUP:\K[0-9]+' || echo "0")

    if [[ "$new_count" -gt 0 && -n "$deduped_entries" ]]; then
        # Append new entries to existing file
        echo "" >> "$OUTPUT_FILE"
        echo "$deduped_entries" >> "$OUTPUT_FILE"
    fi

    local total_count=$((existing_count + new_count))
    echo "$new_count new, $dup_count duplicates skipped, $total_count total"
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
elif [[ "$OVERWRITE" == "true" ]]; then
    # Legacy destructive write (explicit opt-in only)
    mkdir -p "$(dirname "$OUTPUT_FILE")"
    echo "$output" > "$OUTPUT_FILE"
    echo "Wrote $candidate_count lore candidates to $OUTPUT_FILE (overwrite mode)"
else
    # Append-with-dedup (default): preserve existing entries, add only new ones
    append_with_dedup "$output" "$candidate_count"
fi
