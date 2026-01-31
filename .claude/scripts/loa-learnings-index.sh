#!/usr/bin/env bash
# loa-learnings-index.sh - Index and query Loa compound learnings
#
# This script builds and queries an index of Loa's own knowledge sources:
# - Skills (.claude/skills/**/*.md)
# - Feedback (grimoires/loa/feedback/*.yaml)
# - Decisions (grimoires/loa/decisions.yaml)
# - Learnings (grimoires/loa/a2a/compound/learnings.json)
#
# Usage:
#   loa-learnings-index.sh index             Build/update index
#   loa-learnings-index.sh query <terms>     Search learnings
#   loa-learnings-index.sh status            Show index status
#   loa-learnings-index.sh validate          Validate learnings against schema
#   loa-learnings-index.sh add <file>        Add file to index incrementally
#
# Query Options:
#   --format <json|text>    Output format (default: text)
#   --limit <N>             Max results (default: 10)
#   --track                 Track query for effectiveness metrics
#
# Environment:
#   LOA_INDEX_DIR           Index directory (default: ~/.loa/cache/oracle/loa)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Configuration from .loa.config.yaml (with defaults)
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

# Get cache directory from config or environment
get_cache_dir() {
    local dir
    dir=$(read_config '.oracle.index.cache_dir' "$HOME/.loa/cache/oracle")
    # Expand tilde
    dir="${dir/#\~/$HOME}"
    echo "$dir"
}

# Check if source is enabled in config
is_source_enabled() {
    local source="$1"
    local default="${2:-true}"
    local value
    value=$(read_config ".oracle.loa_sources.$source.enabled" "$default")
    [[ "$value" == "true" ]]
}

# Get source paths from config
get_source_paths() {
    local source="$1"
    local default="$2"
    local paths
    paths=$(read_config ".oracle.loa_sources.$source.paths[]" "")
    if [[ -z "$paths" ]]; then
        echo "$default"
    else
        echo "$paths"
    fi
}

# Configuration
CACHE_BASE=$(get_cache_dir)
INDEX_DIR="${LOA_INDEX_DIR:-$CACHE_BASE/loa}"
SKILLS_INDEX="$INDEX_DIR/skills.idx"
FEEDBACK_INDEX="$INDEX_DIR/feedback.idx"
DECISIONS_INDEX="$INDEX_DIR/decisions.idx"
LEARNINGS_INDEX="$INDEX_DIR/learnings.idx"
INDEX_META="$INDEX_DIR/index.json"

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
        exit 1
    fi
}

# Check dependencies
check_dependencies() {
    local missing=()

    if ! command -v jq &> /dev/null; then
        missing+=("jq")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo -e "${RED}ERROR: Missing dependencies: ${missing[*]}${NC}" >&2
        exit 1
    fi
}

check_bash_version
check_dependencies

# Initialize index directory (ORACLE-L-3: set restrictive umask before mkdir)
init_index() {
    umask 077
    mkdir -p "$INDEX_DIR"
}

# Index skills from .claude/skills/
index_skills() {
    local count=0
    local output="[]"

    # Check if skills source is enabled
    if ! is_source_enabled "skills" "true"; then
        echo "[]" > "$SKILLS_INDEX"
        echo "0"
        return
    fi

    cd "$PROJECT_ROOT" || exit 1

    # Find all skill markdown files
    while IFS= read -r -d '' file; do
        local name
        name=$(basename "$(dirname "$file")")
        local title=""
        local description=""

        # Extract title (first H1)
        title=$(grep -m 1 "^# " "$file" 2>/dev/null | sed 's/^# //' || echo "$name")

        # Extract description (first paragraph after title)
        description=$(awk '/^# /{found=1; next} found && /^[^#]/ && !/^$/{print; exit}' "$file" 2>/dev/null | head -c 200 || true)

        # Extract keywords from content
        local keywords
        keywords=$(grep -oE '\b[A-Za-z_][A-Za-z0-9_]{3,}\b' "$file" 2>/dev/null | sort -u | head -20 | tr '\n' ' ' || true)

        output=$(echo "$output" | jq --arg file "$file" --arg name "$name" --arg title "$title" \
            --arg desc "$description" --arg kw "$keywords" \
            '. + [{
                "type": "skill",
                "file": $file,
                "name": $name,
                "title": $title,
                "description": $desc,
                "keywords": $kw,
                "indexed_at": (now | strftime("%Y-%m-%dT%H:%M:%SZ"))
            }]')

        ((count++))
    done < <(find .claude/skills -name "*.md" -type f -print0 2>/dev/null)

    echo "$output" > "$SKILLS_INDEX"
    echo "$count"
}

# Index feedback from grimoires/loa/feedback/
index_feedback() {
    local count=0
    local output="[]"

    # Check if feedback source is enabled
    if ! is_source_enabled "feedback" "true"; then
        echo "[]" > "$FEEDBACK_INDEX"
        echo "0"
        return
    fi

    cd "$PROJECT_ROOT" || exit 1

    if [[ ! -d "grimoires/loa/feedback" ]]; then
        echo "[]" > "$FEEDBACK_INDEX"
        echo "0"
        return
    fi

    # ORACLE-M-1: Use find with -print0 and read -d '' to handle filenames safely
    while IFS= read -r -d '' file; do
        [[ -f "$file" ]] || continue

        # Parse YAML learnings using yq (python wrapper) or fallback
        if command -v yq &> /dev/null; then
            local learnings
            # yq (python jq wrapper) uses jq syntax on YAML files
            learnings=$(yq '.learnings // []' "$file" 2>/dev/null || echo "[]")
            [[ "$learnings" == "null" ]] && learnings="[]"

            # Validate JSON
            if echo "$learnings" | jq empty 2>/dev/null; then
                output=$(echo "$output" | jq --argjson new "$learnings" --arg file "$file" \
                    '. + [$new[] | . + {"source_file": $file, "type": "feedback"}]')
            fi
        else
            # Fallback: grep-based extraction
            local title
            title=$(grep -m 1 "title:" "$file" 2>/dev/null | sed 's/.*title:\s*//' || true)
            local trigger
            trigger=$(grep -m 1 "trigger:" "$file" 2>/dev/null | sed 's/.*trigger:\s*//' || true)

            if [[ -n "$title" ]]; then
                output=$(echo "$output" | jq --arg file "$file" --arg title "$title" --arg trigger "$trigger" \
                    '. + [{
                        "type": "feedback",
                        "source_file": $file,
                        "title": $title,
                        "trigger": $trigger,
                        "indexed_at": (now | strftime("%Y-%m-%dT%H:%M:%SZ"))
                    }]')
            fi
        fi

        ((count++))
    done < <(find grimoires/loa/feedback -maxdepth 1 -name "*.yaml" -type f -print0 2>/dev/null)

    echo "$output" > "$FEEDBACK_INDEX"
    echo "$count"
}

# Index decisions from grimoires/loa/decisions.yaml
index_decisions() {
    local count=0
    local output="[]"

    # Check if decisions source is enabled
    if ! is_source_enabled "decisions" "true"; then
        echo "[]" > "$DECISIONS_INDEX"
        echo "0"
        return
    fi

    cd "$PROJECT_ROOT" || exit 1

    local decisions_file="grimoires/loa/decisions.yaml"
    if [[ ! -f "$decisions_file" ]]; then
        echo "[]" > "$DECISIONS_INDEX"
        echo "0"
        return
    fi

    if command -v yq &> /dev/null; then
        # Use yq if available
        output=$(yq -o=json '.decisions // []' "$decisions_file" 2>/dev/null || echo "[]")
        output=$(echo "$output" | jq '[.[] | . + {"type": "decision", "source_file": "grimoires/loa/decisions.yaml"}]')
        count=$(echo "$output" | jq 'length')
    else
        # Fallback: grep-based extraction
        while IFS= read -r line; do
            if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*id: ]]; then
                local id
                id=$(echo "$line" | sed 's/.*id:\s*//')
                output=$(echo "$output" | jq --arg id "$id" \
                    '. + [{"type": "decision", "id": $id, "source_file": "grimoires/loa/decisions.yaml"}]')
                ((count++))
            fi
        done < "$decisions_file"
    fi

    echo "$output" > "$DECISIONS_INDEX"
    echo "$count"
}

# Index memory entries from grimoires/loa/memory/
index_memory() {
    local count=0
    local output="[]"

    # Check if memory source is enabled (default: true if memory_schema.enabled)
    local memory_enabled
    memory_enabled=$(read_config ".memory_schema.enabled" "false")
    if [[ "$memory_enabled" != "true" ]]; then
        echo "[]" > "$INDEX_DIR/memory.idx"
        echo "0"
        return
    fi

    cd "$PROJECT_ROOT" || exit 1

    local memory_dir="grimoires/loa/memory"
    if [[ ! -d "$memory_dir" ]]; then
        echo "[]" > "$INDEX_DIR/memory.idx"
        echo "0"
        return
    fi

    # Index each memory YAML file
    for file in "$memory_dir"/*.yaml; do
        [[ -f "$file" ]] || continue
        local basename
        basename=$(basename "$file" .yaml)

        # Parse YAML entries (simple extraction)
        local entries
        entries=$(yq -o=json '.' "$file" 2>/dev/null || echo "[]")

        # Add source info to each entry
        entries=$(echo "$entries" | jq --arg file "$file" --arg type "$basename" \
            'if type == "array" then
                [.[] | . + {"type": "memory", "category": $type, "source_file": $file}]
            else
                []
            end')

        output=$(echo "$output $entries" | jq -s 'add')
        count=$((count + $(echo "$entries" | jq 'length')))
    done

    echo "$output" > "$INDEX_DIR/memory.idx"
    echo "$count"
}

# Index compound learnings from grimoires/loa/a2a/compound/learnings.json
index_learnings() {
    local count=0
    local output="[]"

    # Check if learnings source is enabled
    if ! is_source_enabled "learnings" "true"; then
        echo "[]" > "$LEARNINGS_INDEX"
        echo "0"
        return
    fi

    cd "$PROJECT_ROOT" || exit 1

    local learnings_file="grimoires/loa/a2a/compound/learnings.json"
    if [[ ! -f "$learnings_file" ]]; then
        echo "[]" > "$LEARNINGS_INDEX"
        echo "0"
        return
    fi

    output=$(jq '[.learnings // [] | .[] | . + {"type": "learning", "source_file": "grimoires/loa/a2a/compound/learnings.json"}]' "$learnings_file" 2>/dev/null || echo "[]")
    count=$(echo "$output" | jq 'length')

    echo "$output" > "$LEARNINGS_INDEX"
    echo "$count"
}

# Build complete index
build_index() {
    init_index

    echo -e "${BOLD}${CYAN}Building Loa Learnings Index${NC}"
    echo "─────────────────────────────────────────"
    echo ""

    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    echo -n "  Indexing skills... "
    local skills_count
    skills_count=$(index_skills)
    echo -e "${GREEN}$skills_count${NC}"

    echo -n "  Indexing feedback... "
    local feedback_count
    feedback_count=$(index_feedback)
    echo -e "${GREEN}$feedback_count${NC}"

    echo -n "  Indexing decisions... "
    local decisions_count
    decisions_count=$(index_decisions)
    echo -e "${GREEN}$decisions_count${NC}"

    echo -n "  Indexing learnings... "
    local learnings_count
    learnings_count=$(index_learnings)
    echo -e "${GREEN}$learnings_count${NC}"

    echo -n "  Indexing memory... "
    local memory_count
    memory_count=$(index_memory)
    echo -e "${GREEN}$memory_count${NC}"

    # Create metadata file
    cat > "$INDEX_META" << EOF
{
    "version": 1,
    "indexed_at": "$timestamp",
    "counts": {
        "skills": $skills_count,
        "feedback": $feedback_count,
        "decisions": $decisions_count,
        "learnings": $learnings_count,
        "memory": $memory_count
    },
    "total": $((skills_count + feedback_count + decisions_count + learnings_count + memory_count)),
    "index_dir": "$INDEX_DIR"
}
EOF

    echo ""
    echo "─────────────────────────────────────────"
    echo -e "Total indexed: ${GREEN}$((skills_count + feedback_count + decisions_count + learnings_count))${NC}"
    echo -e "Index location: ${CYAN}$INDEX_DIR${NC}"
    echo ""
}

# Query with grep (primary search method)
query_with_grep() {
    local terms="$1"
    local format="${2:-text}"
    local limit="${3:-10}"
    local track="${4:-false}"

    local results="[]"

    # Convert terms to jq-compatible regex pattern (pipe-separated for OR)
    local pattern
    pattern=$(echo "$terms" | sed 's/|/|/g')

    # ORACLE-L-1: Pass pattern directly to jq via --arg instead of environment variable
    local SEARCH_PATTERN="$pattern"

    # Search each index (including memory if enabled)
    local MEMORY_INDEX="$INDEX_DIR/memory.idx"
    for idx_file in "$SKILLS_INDEX" "$FEEDBACK_INDEX" "$DECISIONS_INDEX" "$LEARNINGS_INDEX" "$MEMORY_INDEX"; do
        [[ -f "$idx_file" ]] || continue

        # Search JSON index using environment variable
        local matches
        matches=$(jq --arg pattern "$SEARCH_PATTERN" '
            [.[] | select(
                (.title // "" | test($pattern; "i")) or
                (.description // "" | test($pattern; "i")) or
                (.trigger // "" | test($pattern; "i")) or
                (.solution // "" | test($pattern; "i")) or
                (.keywords // "" | test($pattern; "i")) or
                (.name // "" | test($pattern; "i")) or
                (.id // "" | test($pattern; "i"))
            )]
        ' "$idx_file" 2>/dev/null || echo "[]")

        results=$(echo "$results" | jq --argjson new "$matches" '. + $new')
    done

    # Calculate scores based on match quality
    results=$(echo "$results" | jq --arg pattern "$SEARCH_PATTERN" '
        [.[] | . + {
            score: (
                if (.title // "" | test($pattern; "i")) then 0.9
                elif (.trigger // "" | test($pattern; "i")) then 0.85
                elif (.solution // "" | test($pattern; "i")) then 0.8
                elif (.description // "" | test($pattern; "i")) then 0.7
                elif (.keywords // "" | test($pattern; "i")) then 0.6
                else 0.5
                end
            ),
            weight: 1.0,
            source: "loa"
        }]
    ' 2>/dev/null || echo "[]")

    # ORACLE-L-4: Sort by score and limit using jq limit() for efficiency with large indexes
    results=$(echo "$results" | jq --argjson limit "$limit" '
        sort_by(-.score) | limit($limit; .[])
    ' | jq -s '.')

    # Track query if requested
    if [[ "$track" == "true" ]]; then
        track_query "$terms" "$results"
    fi

    # Output
    if [[ "$format" == "json" ]]; then
        echo "$results"
    else
        format_text_results "$results"
    fi
}

# Format results as text
format_text_results() {
    local results="$1"

    local count
    count=$(echo "$results" | jq 'length')

    if [[ "$count" == "0" ]]; then
        echo -e "${YELLOW}No results found.${NC}"
        return 4
    fi

    echo -e "${BOLD}${CYAN}Loa Learnings Query Results${NC}"
    echo "─────────────────────────────────────────"
    echo ""

    echo "$results" | jq -r '.[] | "\(.type)|\(.score)|\(.title // .name // .id)|\(.file // .source_file)"' | \
    while IFS='|' read -r type score title file; do
        printf "  ${GREEN}[%s]${NC} (%.2f) %s\n" "$type" "$score" "$title"
        printf "         ${CYAN}%s${NC}\n" "$file"
        echo ""
    done

    echo "─────────────────────────────────────────"
    echo -e "Results: ${GREEN}$count${NC}"
}

# Track query for effectiveness metrics
track_query() {
    local terms="$1"
    local results="$2"

    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Get IDs of matched learnings
    local matched_ids
    matched_ids=$(echo "$results" | jq -r '[.[] | select(.type == "learning" or .type == "feedback") | .id // .title] | @csv' 2>/dev/null || echo "")

    [[ -z "$matched_ids" || "$matched_ids" == '""' ]] && return

    # Log to trajectory
    local trajectory_dir="$PROJECT_ROOT/grimoires/loa/a2a/trajectory"
    if [[ -d "$trajectory_dir" ]]; then
        local trajectory_file="$trajectory_dir/oracle-$(date +%Y-%m-%d).jsonl"
        local event
        event=$(jq -n \
            --arg ts "$timestamp" \
            --arg type "oracle_query" \
            --arg terms "$terms" \
            --arg matches "$matched_ids" \
            --argjson count "$(echo "$results" | jq 'length')" \
            '{
                timestamp: $ts,
                event_type: $type,
                query_terms: $terms,
                matched_ids: $matches,
                result_count: $count
            }')
        echo "$event" >> "$trajectory_file"
        echo -e "${BLUE}Query tracked in trajectory${NC}" >&2
    fi

    # Update learnings.json if it exists
    local learnings_file="$PROJECT_ROOT/grimoires/loa/a2a/compound/learnings.json"
    if [[ -f "$learnings_file" ]]; then
        # Get learning IDs from results
        local learning_ids
        learning_ids=$(echo "$results" | jq -r '[.[] | select(.type == "learning") | .id] | .[]' 2>/dev/null || true)

        for id in $learning_ids; do
            [[ -z "$id" ]] && continue

            # Update applied_count and last_applied for matching learning
            local updated
            updated=$(jq --arg id "$id" --arg ts "$timestamp" '
                .learnings = [.learnings[] |
                    if .id == $id then
                        .effectiveness.applied_count = ((.effectiveness.applied_count // 0) + 1) |
                        .effectiveness.last_applied = $ts
                    else
                        .
                    end
                ]
            ' "$learnings_file" 2>/dev/null)

            # ORACLE-M-2: Use flock for atomic file updates to prevent TOCTOU race
            if [[ -n "$updated" && "$updated" != "null" ]]; then
                (
                    flock -x 200 || { echo -e "${RED}Failed to acquire lock${NC}" >&2; exit 1; }
                    echo "$updated" > "$learnings_file.tmp"
                    mv "$learnings_file.tmp" "$learnings_file"
                ) 200>"$learnings_file.lock"
                rm -f "$learnings_file.lock"
                echo -e "${BLUE}Updated effectiveness for learning $id${NC}" >&2
            fi
        done
    fi
}

# Show index status
show_status() {
    if [[ ! -f "$INDEX_META" ]]; then
        echo -e "${YELLOW}No index found. Run 'loa-learnings-index.sh index' first.${NC}"
        return 1
    fi

    echo -e "${BOLD}${CYAN}Loa Learnings Index Status${NC}"
    echo "─────────────────────────────────────────"
    echo ""

    local indexed_at
    indexed_at=$(jq -r '.indexed_at' "$INDEX_META")
    local total
    total=$(jq -r '.total' "$INDEX_META")

    echo -e "  Last indexed: ${BLUE}$indexed_at${NC}"
    echo -e "  Total entries: ${GREEN}$total${NC}"
    echo ""
    echo "  Breakdown:"
    jq -r '.counts | to_entries | .[] | "    \(.key): \(.value)"' "$INDEX_META"
    echo ""
    echo -e "  Index location: ${CYAN}$INDEX_DIR${NC}"
    echo ""
}

# Validate learnings against schema
validate_learnings() {
    local schema_file="$PROJECT_ROOT/.claude/schemas/learnings.schema.json"

    if [[ ! -f "$schema_file" ]]; then
        echo -e "${YELLOW}Schema not found: $schema_file${NC}"
        echo "Run sprint-1 task 1.4 to create the schema."
        return 1
    fi

    echo -e "${BOLD}${CYAN}Validating Learnings${NC}"
    echo "─────────────────────────────────────────"
    echo ""

    local valid=0
    local invalid=0

    # Validate feedback files
    for file in "$PROJECT_ROOT"/grimoires/loa/feedback/*.yaml; do
        [[ -f "$file" ]] || continue

        echo -n "  Checking $(basename "$file")... "

        # Convert YAML to JSON and validate
        if command -v yq &> /dev/null && command -v ajv &> /dev/null; then
            if yq -o=json "$file" | ajv validate -s "$schema_file" -d - &> /dev/null; then
                echo -e "${GREEN}✓${NC}"
                ((valid++))
            else
                echo -e "${RED}✗${NC}"
                ((invalid++))
            fi
        else
            echo -e "${YELLOW}skipped (yq/ajv not available)${NC}"
        fi
    done

    echo ""
    echo "─────────────────────────────────────────"
    echo -e "Valid: ${GREEN}$valid${NC}, Invalid: ${RED}$invalid${NC}"
}

# Log indexing event to trajectory
log_index_event() {
    local file="$1"
    local action="$2"
    local success="$3"

    local trajectory_dir="$PROJECT_ROOT/grimoires/loa/a2a/trajectory"
    if [[ ! -d "$trajectory_dir" ]]; then
        mkdir -p "$trajectory_dir"
    fi

    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    local trajectory_file="$trajectory_dir/oracle-$(date +%Y-%m-%d).jsonl"
    local event
    event=$(jq -n \
        --arg ts "$timestamp" \
        --arg type "index_update" \
        --arg file "$file" \
        --arg action "$action" \
        --argjson success "$success" \
        '{
            timestamp: $ts,
            event_type: $type,
            file: $file,
            action: $action,
            success: $success
        }')
    echo "$event" >> "$trajectory_file"
}

# ORACLE-M-3: Validate path is within allowed directories (no traversal)
validate_path() {
    local file="$1"
    local resolved_path
    local project_root_resolved

    # Resolve to absolute path
    resolved_path=$(realpath -m "$file" 2>/dev/null || readlink -f "$file" 2>/dev/null || echo "$file")
    project_root_resolved=$(realpath -m "$PROJECT_ROOT" 2>/dev/null || readlink -f "$PROJECT_ROOT" 2>/dev/null || echo "$PROJECT_ROOT")

    # Check if resolved path is within project root
    if [[ "$resolved_path" != "$project_root_resolved"* ]]; then
        return 1
    fi

    # Additional check: no .. components in the resolved path
    if [[ "$resolved_path" == *".."* ]]; then
        return 1
    fi

    return 0
}

# Add file to index incrementally
add_to_index() {
    local file="$1"
    local validate="${2:-true}"

    if [[ ! -f "$file" ]]; then
        echo -e "${RED}File not found: $file${NC}" >&2
        return 1
    fi

    # ORACLE-M-3: Validate path traversal
    if ! validate_path "$file"; then
        echo -e "${RED}Path traversal detected or file outside project: $file${NC}" >&2
        return 1
    fi

    echo -e "${BOLD}Adding to index:${NC} $file"

    # Validate feedback files against schema if requested
    if [[ "$validate" == "true" && "$file" == *feedback*.yaml ]]; then
        echo -n "  Validating schema... "
        local schema_file="$PROJECT_ROOT/.claude/schemas/learnings.schema.json"

        if [[ -f "$schema_file" ]] && command -v yq &> /dev/null; then
            # Basic YAML syntax check
            if ! yq '.' "$file" > /dev/null 2>&1; then
                echo -e "${RED}invalid YAML${NC}"
                log_index_event "$file" "add" "false"
                return 1
            fi

            # Check required fields
            local has_schema_version
            has_schema_version=$(yq '.schema_version // ""' "$file" 2>/dev/null)
            if [[ -z "$has_schema_version" || "$has_schema_version" == "null" ]]; then
                echo -e "${YELLOW}warning: missing schema_version${NC}"
            else
                echo -e "${GREEN}valid${NC}"
            fi
        else
            echo -e "${YELLOW}skipped (yq not available)${NC}"
        fi
    fi

    # Determine type and update appropriate index
    case "$file" in
        *feedback*.yaml)
            # Re-index feedback
            echo -n "  Re-indexing feedback... "
            index_feedback > /dev/null
            echo -e "${GREEN}done${NC}"
            log_index_event "$file" "add" "true"
            ;;
        *decisions.yaml)
            echo -n "  Re-indexing decisions... "
            index_decisions > /dev/null
            echo -e "${GREEN}done${NC}"
            log_index_event "$file" "add" "true"
            ;;
        *learnings.json)
            echo -n "  Re-indexing learnings... "
            index_learnings > /dev/null
            echo -e "${GREEN}done${NC}"
            log_index_event "$file" "add" "true"
            ;;
        *.md)
            if [[ "$file" == *.claude/skills/* ]]; then
                echo -n "  Re-indexing skills... "
                index_skills > /dev/null
                echo -e "${GREEN}done${NC}"
                log_index_event "$file" "add" "true"
            else
                echo -e "${YELLOW}Unknown markdown file, skipping${NC}"
                return 1
            fi
            ;;
        *)
            echo -e "${YELLOW}Unknown file type, skipping${NC}"
            return 1
            ;;
    esac

    # Update metadata timestamp
    if [[ -f "$INDEX_META" ]]; then
        local timestamp
        timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
        jq --arg ts "$timestamp" '.last_updated = $ts' "$INDEX_META" > "$INDEX_META.tmp"
        mv "$INDEX_META.tmp" "$INDEX_META"
    fi

    echo -e "${GREEN}✓ File added to index${NC}"
}

# Check if QMD is available
qmd_available() {
    command -v qmd &> /dev/null
}

# Get default indexer from config
get_default_indexer() {
    read_config '.oracle.query.default_indexer' 'auto'
}

# Query with QMD (semantic search)
query_with_qmd() {
    local terms="$1"
    local format="${2:-text}"
    local limit="${3:-10}"

    if ! qmd_available; then
        echo -e "${RED}QMD not available. Use --index grep or install qmd.${NC}" >&2
        return 1
    fi

    local results="[]"

    # Search each indexed source with qmd
    for source_dir in "$PROJECT_ROOT/.claude/skills" "$PROJECT_ROOT/grimoires/loa/feedback" "$PROJECT_ROOT/grimoires/loa"; do
        [[ -d "$source_dir" ]] || continue

        # Run qmd search and convert to our JSON format
        local qmd_results
        qmd_results=$(qmd search "$terms" --path "$source_dir" --limit "$limit" --json 2>/dev/null || echo "[]")

        # Transform qmd results to our format
        local transformed
        transformed=$(echo "$qmd_results" | jq '[.[] | {
            type: "qmd_match",
            file: .path,
            title: .title,
            snippet: .excerpt,
            score: .score,
            weight: 1.0,
            source: "loa"
        }]' 2>/dev/null || echo "[]")

        results=$(echo "$results" | jq --argjson new "$transformed" '. + $new')
    done

    # Sort by score and limit
    results=$(echo "$results" | jq --argjson limit "$limit" 'sort_by(-.score) | .[:$limit]')

    if [[ "$format" == "json" ]]; then
        echo "$results"
    else
        format_text_results "$results"
    fi
}

# Parse query arguments
parse_query_args() {
    local terms=""
    local format="text"
    local limit="10"
    local track="false"
    local indexer=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --format)
                format="$2"
                shift 2
                ;;
            --limit)
                limit="$2"
                shift 2
                ;;
            --track)
                track="true"
                shift
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
        exit 1
    fi

    # Determine indexer to use
    if [[ -z "$indexer" ]]; then
        indexer=$(get_default_indexer)
    fi

    case "$indexer" in
        qmd)
            if ! qmd_available; then
                echo -e "${RED}Error: QMD requested but not available${NC}" >&2
                exit 1
            fi
            query_with_qmd "$terms" "$format" "$limit"
            ;;
        grep)
            query_with_grep "$terms" "$format" "$limit" "$track"
            ;;
        auto)
            if qmd_available; then
                query_with_qmd "$terms" "$format" "$limit"
            else
                query_with_grep "$terms" "$format" "$limit" "$track"
            fi
            ;;
        *)
            echo -e "${RED}Unknown indexer: $indexer${NC}" >&2
            exit 1
            ;;
    esac
}

# Main
main() {
    local command="${1:-help}"

    case "$command" in
        index)
            build_index
            ;;
        query)
            shift
            parse_query_args "$@"
            ;;
        status)
            show_status
            ;;
        validate)
            validate_learnings
            ;;
        add)
            shift
            add_to_index "$@"
            ;;
        help|--help|-h)
            cat << 'HELP'
loa-learnings-index.sh - Index and query Loa compound learnings

Usage:
  loa-learnings-index.sh index             Build/update the learnings index
  loa-learnings-index.sh query <terms>     Search indexed learnings
  loa-learnings-index.sh status            Show index status and statistics
  loa-learnings-index.sh validate          Validate learnings against schema
  loa-learnings-index.sh add <file>        Add/update a file in the index

Query Options:
  --format <text|json>    Output format: text (Recommended), json
  --limit <N>             Maximum results (default: 10)
  --track                 Track query for effectiveness metrics
  --index <auto|qmd|grep> Indexer: auto (Recommended), qmd, grep

Examples:
  loa-learnings-index.sh index
  loa-learnings-index.sh query "authentication"
  loa-learnings-index.sh query "hooks|mcp" --format json --limit 5
  loa-learnings-index.sh add grimoires/loa/feedback/2026-01-31.yaml

Sources Indexed:
  - Skills: .claude/skills/**/*.md
  - Feedback: grimoires/loa/feedback/*.yaml
  - Decisions: grimoires/loa/decisions.yaml
  - Learnings: grimoires/loa/a2a/compound/learnings.json

Environment Variables:
  LOA_INDEX_DIR    Index directory (default: ~/.loa/cache/oracle/loa)

HELP
            ;;
        *)
            echo -e "${RED}Unknown command: $command${NC}"
            echo "Run 'loa-learnings-index.sh help' for usage"
            exit 1
            ;;
    esac
}

main "$@"
