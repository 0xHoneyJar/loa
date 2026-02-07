#!/usr/bin/env bash
# =============================================================================
# flatline-semantic-similarity.sh - Semantic Similarity via Embeddings
# =============================================================================
# Part of Flatline-Enhanced Compound Learning v1.23.0 (Sprint 3)
# Addresses: T3.1 - Model-based duplicate detection
#
# Calculates semantic similarity using:
# - Primary: OpenAI embeddings API (text-embedding-3-small)
# - Fallback: Jaccard similarity when API unavailable
# - Hybrid: (1-α)*jaccard + α*semantic
#
# Usage:
#   flatline-semantic-similarity.sh --learning <json> --framework-index <path> [options]
#
# Exit codes:
#   0 - Success
#   1 - Invalid arguments
#   2 - Index not found
#   3 - API error (fallback to Jaccard)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_FILE="$PROJECT_ROOT/.loa.config.yaml"
LIB_DIR="$SCRIPT_DIR/lib"
TRAJECTORY_DIR="$PROJECT_ROOT/grimoires/loa/a2a/trajectory"

# Default paths
DEFAULT_INDEX_PATH="$PROJECT_ROOT/.claude/loa/learnings/index.json"
DEFAULT_EMBEDDINGS_PATH="$PROJECT_ROOT/.claude/loa/learnings/embeddings.bin"

# Allowed index directories (for path validation)
ALLOWED_INDEX_DIRS=(
    "$PROJECT_ROOT/.claude/loa/learnings"
    "$PROJECT_ROOT/grimoires/loa"
)

# Source utilities
if [[ -f "$LIB_DIR/api-resilience.sh" ]]; then
    source "$LIB_DIR/api-resilience.sh"
fi

# =============================================================================
# Configuration
# =============================================================================

THRESHOLD="${LOA_SIMILARITY_THRESHOLD:-70}"
ALPHA="${LOA_SIMILARITY_ALPHA:-0.6}"  # Weight for semantic vs Jaccard
OUTPUT_FORMAT="${LOA_OUTPUT_FORMAT:-json}"
EMBEDDING_MODEL="${LOA_EMBEDDING_MODEL:-text-embedding-3-small}"
EMBEDDING_DIMENSIONS="${LOA_EMBEDDING_DIMENSIONS:-1536}"

# =============================================================================
# Logging
# =============================================================================

log_error() { echo "[ERROR] $(date -Iseconds) $*" >&2; }
log_warning() { echo "[WARN] $(date -Iseconds) $*" >&2; }
log_info() { echo "[INFO] $(date -Iseconds) $*" >&2; }
log_debug() { [[ "${LOA_DEBUG:-false}" == "true" ]] && echo "[DEBUG] $(date -Iseconds) $*" >&2 || true; }

# =============================================================================
# Path Validation (Security: HIGH-002)
# =============================================================================

# Validate that a path is within allowed directories
# Returns: 0 if valid, 1 if invalid
validate_index_path() {
    local path="$1"

    # Resolve to absolute path and canonicalize
    local resolved_path
    if [[ -f "$path" ]]; then
        resolved_path=$(cd "$(dirname "$path")" && pwd)/$(basename "$path")
    else
        # File doesn't exist yet - validate parent directory
        local parent_dir
        parent_dir=$(dirname "$path")
        if [[ -d "$parent_dir" ]]; then
            resolved_path=$(cd "$parent_dir" && pwd)/$(basename "$path")
        else
            log_error "Parent directory does not exist: $parent_dir"
            return 1
        fi
    fi

    # Check for path traversal attempts
    if [[ "$resolved_path" == *".."* ]]; then
        log_error "Path traversal detected: $path"
        return 1
    fi

    # Verify path is within allowed directories
    local allowed=false
    for allowed_dir in "${ALLOWED_INDEX_DIRS[@]}"; do
        # Resolve allowed dir to absolute
        if [[ -d "$allowed_dir" ]]; then
            local resolved_allowed
            resolved_allowed=$(cd "$allowed_dir" && pwd)
            if [[ "$resolved_path" == "$resolved_allowed"* ]]; then
                allowed=true
                break
            fi
        fi
    done

    if [[ "$allowed" != "true" ]]; then
        log_error "Path not in allowed directories: $path"
        log_error "Allowed: ${ALLOWED_INDEX_DIRS[*]}"
        return 1
    fi

    log_debug "Path validated: $resolved_path"
    return 0
}

# Log to trajectory
log_trajectory() {
    local event_type="$1"
    local data="$2"

    (umask 077 && mkdir -p "$TRAJECTORY_DIR")
    local date_str
    date_str=$(date +%Y-%m-%d)
    local log_file="$TRAJECTORY_DIR/semantic-similarity-$date_str.jsonl"

    touch "$log_file"
    chmod 600 "$log_file"

    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    jq -n \
        --arg type "semantic_similarity" \
        --arg event "$event_type" \
        --arg timestamp "$timestamp" \
        --argjson data "$data" \
        '{type: $type, event: $event, timestamp: $timestamp, data: $data}' >> "$log_file"
}

# =============================================================================
# Jaccard Similarity (Fallback)
# =============================================================================

# Calculate Jaccard similarity between two texts
calculate_jaccard() {
    local text1="$1"
    local text2="$2"

    # Tokenize: lowercase, split on non-alphanumeric
    local tokens1 tokens2
    tokens1=$(echo "$text1" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '\n' | sort -u)
    tokens2=$(echo "$text2" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '\n' | sort -u)

    # Calculate intersection and union
    local intersection union
    intersection=$(comm -12 <(echo "$tokens1") <(echo "$tokens2") | wc -l | tr -d ' ')
    union=$(cat <(echo "$tokens1") <(echo "$tokens2") | sort -u | wc -l | tr -d ' ')

    # Jaccard = intersection / union
    if [[ "$union" -eq 0 ]]; then
        echo "0"
    else
        echo "scale=4; $intersection / $union * 100" | bc
    fi
}

# =============================================================================
# Embeddings API
# =============================================================================

# Get embedding for text
get_embedding() {
    local text="$1"

    # Truncate long text
    local truncated
    truncated=$(echo "$text" | head -c 8000)

    local response
    # SEC-AUDIT SEC-HIGH-01: Use curl config to avoid exposing API key in process list
    local _curl_cfg
    _curl_cfg=$(mktemp) && chmod 600 "$_curl_cfg"
    printf 'header = "Content-Type: application/json"\nheader = "Authorization: Bearer %s"\n' "${OPENAI_API_KEY:-}" > "$_curl_cfg"
    response=$(curl -s --max-time 30 \
        -X POST "https://api.openai.com/v1/embeddings" \
        --config "$_curl_cfg" \
        -d "$(jq -n --arg text "$truncated" --arg model "$EMBEDDING_MODEL" '{
            model: $model,
            input: $text,
            dimensions: '"$EMBEDDING_DIMENSIONS"'
        }')" 2>/dev/null)
    rm -f "$_curl_cfg"

    if [[ -z "$response" ]]; then
        log_warning "Empty response from embeddings API"
        return 1
    fi

    # Check for error
    local error
    error=$(echo "$response" | jq -r '.error.message // ""')
    if [[ -n "$error" ]]; then
        log_warning "Embeddings API error: $error"
        return 1
    fi

    # Extract embedding
    echo "$response" | jq -c '.data[0].embedding'
}

# Calculate cosine similarity between two embedding vectors
calculate_cosine_similarity() {
    local vec1_json="$1"
    local vec2_json="$2"

    # Use jq for vector math (slower but portable)
    # cosine_sim = (A·B) / (||A|| * ||B||)
    local result
    result=$(jq -n --argjson v1 "$vec1_json" --argjson v2 "$vec2_json" '
        def dot: . as $pair | ($pair[0] | to_entries) | map(.value * $pair[1][.key]) | add;
        def norm: . | map(. * .) | add | sqrt;

        ([$v1, $v2] | dot) / (($v1 | norm) * ($v2 | norm)) * 100
    ' 2>/dev/null || echo "0")

    echo "$result"
}

# =============================================================================
# Index Loading
# =============================================================================

# Load framework learning index
load_index() {
    local index_path="$1"

    if [[ ! -f "$index_path" ]]; then
        log_warning "Index file not found: $index_path"
        return 1
    fi

    cat "$index_path"
}

# Get embedding from binary file
get_embedding_from_index() {
    local embeddings_path="$1"
    local offset="$2"
    local length="$3"

    if [[ ! -f "$embeddings_path" ]]; then
        log_warning "Embeddings file not found: $embeddings_path"
        return 1
    fi

    # Read binary float32 data and convert to JSON array
    # This is complex in bash - use python if available
    if command -v python3 &>/dev/null; then
        python3 -c "
import struct
import json
with open('$embeddings_path', 'rb') as f:
    f.seek($offset)
    data = struct.unpack('${length}f', f.read($length * 4))
    print(json.dumps(list(data)))
" 2>/dev/null
    else
        log_warning "Python3 not available for reading binary embeddings"
        return 1
    fi
}

# =============================================================================
# Main Similarity Calculation
# =============================================================================

calculate_similarity() {
    local learning_json="$1"
    local index_path="$2"

    # Extract trigger and solution for comparison text
    local trigger solution comparison_text
    trigger=$(echo "$learning_json" | jq -r '.trigger // ""')
    solution=$(echo "$learning_json" | jq -r '.solution // ""')
    comparison_text="$trigger $solution"

    log_debug "Calculating similarity for: $comparison_text"

    # Load index
    local index_json
    if ! index_json=$(load_index "$index_path"); then
        log_warning "Could not load index, using Jaccard only"
        # Return Jaccard-only result
        local jaccard_novelty=100
        jq -n \
            --argjson novelty "$jaccard_novelty" \
            --argjson semantic_novelty "null" \
            --argjson hybrid_novelty "$jaccard_novelty" \
            --arg method "jaccard_only" \
            '{
                novelty_score: $novelty,
                semantic_novelty: $semantic_novelty,
                jaccard_novelty: $novelty,
                hybrid_novelty: $hybrid_novelty,
                method: $method,
                max_similarity: 0,
                most_similar_learning: null
            }'
        return
    fi

    local max_jaccard=0
    local max_semantic=0
    local most_similar_id=""
    local use_semantic=false

    # Try to get embedding for input
    local input_embedding=""
    if [[ -n "${OPENAI_API_KEY:-}" ]]; then
        input_embedding=$(get_embedding "$comparison_text" 2>/dev/null || echo "")
        if [[ -n "$input_embedding" && "$input_embedding" != "null" ]]; then
            use_semantic=true
        fi
    fi

    # Compare with each learning in index
    local embeddings_path
    embeddings_path=$(dirname "$index_path")/embeddings.bin

    echo "$index_json" | jq -c '.learnings[]' 2>/dev/null | while IFS= read -r learning; do
        local learn_id learn_text
        learn_id=$(echo "$learning" | jq -r '.id')
        learn_text=$(echo "$learning" | jq -r '.text // ""')

        # Calculate Jaccard similarity
        local jaccard
        jaccard=$(calculate_jaccard "$comparison_text" "$learn_text")

        if (( $(echo "$jaccard > $max_jaccard" | bc -l) )); then
            max_jaccard=$jaccard
            most_similar_id=$learn_id
        fi

        # Calculate semantic similarity if available
        if [[ "$use_semantic" == "true" ]]; then
            local offset length indexed_embedding
            offset=$(echo "$learning" | jq -r '.embedding_offset')
            length=$(echo "$learning" | jq -r '.embedding_length // '"$EMBEDDING_DIMENSIONS"'')

            indexed_embedding=$(get_embedding_from_index "$embeddings_path" "$offset" "$length" 2>/dev/null || echo "")

            if [[ -n "$indexed_embedding" ]]; then
                local semantic
                semantic=$(calculate_cosine_similarity "$input_embedding" "$indexed_embedding")

                if (( $(echo "$semantic > $max_semantic" | bc -l) )); then
                    max_semantic=$semantic
                fi
            fi
        fi
    done

    # Calculate novelty scores (100 - max_similarity)
    local jaccard_novelty semantic_novelty hybrid_novelty
    jaccard_novelty=$(echo "scale=2; 100 - $max_jaccard" | bc)

    if [[ "$use_semantic" == "true" ]]; then
        semantic_novelty=$(echo "scale=2; 100 - $max_semantic" | bc)
        # Hybrid: (1-α)*jaccard + α*semantic
        hybrid_novelty=$(echo "scale=2; (1 - $ALPHA) * $jaccard_novelty + $ALPHA * $semantic_novelty" | bc)
    else
        semantic_novelty="null"
        hybrid_novelty=$jaccard_novelty
    fi

    # Determine method used
    local method
    if [[ "$use_semantic" == "true" ]]; then
        method="hybrid"
    else
        method="jaccard_only"
    fi

    local max_similarity
    if [[ "$use_semantic" == "true" ]]; then
        max_similarity=$(echo "scale=2; (1 - $ALPHA) * $max_jaccard + $ALPHA * $max_semantic" | bc)
    else
        max_similarity=$max_jaccard
    fi

    # Log to trajectory
    log_trajectory "semantic_similarity_calculated" "$(jq -n \
        --argjson jaccard_novelty "$jaccard_novelty" \
        --arg semantic_novelty "${semantic_novelty:-null}" \
        --argjson hybrid_novelty "$hybrid_novelty" \
        --arg method "$method" \
        '{jaccard_novelty: $jaccard_novelty, semantic_novelty: $semantic_novelty, hybrid_novelty: $hybrid_novelty, method: $method}')"

    # Return result
    jq -n \
        --argjson jaccard_novelty "$jaccard_novelty" \
        --arg semantic_novelty "${semantic_novelty:-null}" \
        --argjson hybrid_novelty "$hybrid_novelty" \
        --arg method "$method" \
        --argjson max_similarity "$max_similarity" \
        --arg most_similar "$most_similar_id" \
        '{
            novelty_score: $hybrid_novelty,
            jaccard_novelty: $jaccard_novelty,
            semantic_novelty: (if $semantic_novelty == "null" then null else ($semantic_novelty | tonumber) end),
            hybrid_novelty: $hybrid_novelty,
            method: $method,
            max_similarity: $max_similarity,
            most_similar_learning: $most_similar
        }'
}

# =============================================================================
# CLI Interface
# =============================================================================

usage() {
    cat <<EOF
Usage: flatline-semantic-similarity.sh [options]

Calculate semantic similarity between a learning and framework index.

Options:
  --learning <json|file>       Learning JSON or path (required)
  --framework-index <path>     Path to index.json (default: .claude/loa/learnings/index.json)
  --threshold <0-100>          Similarity threshold (default: 70)
  --alpha <0-1>                Weight for semantic vs Jaccard (default: 0.6)
  --output <format>            Output format: json (default)
  --help                       Show this help

Environment Variables:
  OPENAI_API_KEY               Required for semantic embeddings (falls back to Jaccard)
  LOA_EMBEDDING_MODEL          Embedding model (default: text-embedding-3-small)
  LOA_DEBUG                    Enable debug logging (true/false)

Calculation:
  Hybrid novelty = (1-α) * jaccard_novelty + α * semantic_novelty
  Returns novelty_score: 100 - max_similarity (higher = more novel)

Exit Codes:
  0 - Success
  1 - Invalid arguments
  2 - Index not found
  3 - API error (fell back to Jaccard)
EOF
}

main() {
    local learning_input=""
    local index_path="$DEFAULT_INDEX_PATH"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --learning)
                learning_input="$2"
                shift 2
                ;;
            --framework-index)
                index_path="$2"
                shift 2
                ;;
            --threshold)
                THRESHOLD="$2"
                shift 2
                ;;
            --alpha)
                ALPHA="$2"
                shift 2
                ;;
            --output)
                OUTPUT_FORMAT="$2"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done

    # Validate required arguments
    if [[ -z "$learning_input" ]]; then
        log_error "--learning is required"
        usage
        exit 1
    fi

    # Load learning JSON
    local learning_json
    if [[ "$learning_input" == "-" ]]; then
        learning_json=$(cat)
    elif [[ -f "$learning_input" ]]; then
        learning_json=$(cat "$learning_input")
    else
        learning_json="$learning_input"
    fi

    # Validate JSON
    if ! echo "$learning_json" | jq '.' >/dev/null 2>&1; then
        log_error "Invalid JSON input"
        exit 1
    fi

    # Validate index path (Security: HIGH-002 - prevent path traversal)
    if ! validate_index_path "$index_path"; then
        log_error "Index path validation failed"
        exit 1
    fi

    # Calculate similarity
    calculate_similarity "$learning_json" "$index_path"
}

main "$@"
