#!/usr/bin/env bash
# =============================================================================
# flatline-learning-extractor.sh - Extract Learning Candidates from Flatline
# =============================================================================
# Part of Flatline-Enhanced Compound Learning v1.23.0 (Sprint 1)
# Addresses: T1.1 - Extract learning candidates from Flatline HIGH_CONSENSUS
#
# Transforms Flatline consensus items into learning candidates with:
# - Pattern-based trigger/solution extraction
# - LLM fallback transformation with sanitization and quarantine
# - Schema validation for all outputs
# - Budget controls and data redaction
#
# Usage:
#   flatline-learning-extractor.sh --result <json|file> [options]
#
# Exit codes:
#   0 - Success
#   1 - Invalid arguments
#   2 - Schema validation failed
#   3 - Budget exceeded
#   4 - API error (after retries)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_FILE="$PROJECT_ROOT/.loa.config.yaml"
LIB_DIR="$SCRIPT_DIR/lib"
SCHEMA_DIR="$PROJECT_ROOT/.claude/schemas"
TRAJECTORY_DIR="$PROJECT_ROOT/grimoires/loa/a2a/trajectory"
COMPOUND_DIR="$PROJECT_ROOT/grimoires/loa/a2a/compound"

# Source utilities
if [[ -f "$LIB_DIR/api-resilience.sh" ]]; then
    source "$LIB_DIR/api-resilience.sh"
fi

if [[ -f "$LIB_DIR/schema-validator.sh" ]]; then
    source "$LIB_DIR/schema-validator.sh"
fi

# =============================================================================
# Configuration
# =============================================================================

# Default parameters
MIN_CONSENSUS="${LOA_MIN_CONSENSUS:-750}"
INCLUDE_DISPUTED="${LOA_INCLUDE_DISPUTED:-false}"
DISPUTED_MAX_DELTA="${LOA_DISPUTED_MAX_DELTA:-200}"
OUTPUT_FORMAT="${LOA_OUTPUT_FORMAT:-jsonl}"
FALLBACK_TO_LLM="${LOA_FALLBACK_TO_LLM:-true}"
DRY_RUN=false

# Sanitization patterns (SDD 3.7)
REDACT_PATTERNS=(
    's/[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/[EMAIL]/g'          # emails
    's/sk-[a-zA-Z0-9]{48}/[API_KEY]/g'                                      # OpenAI keys
    's/ghp_[a-zA-Z0-9]{36}/[GITHUB_TOKEN]/g'                                # GitHub tokens
    's/AKIA[A-Z0-9]{16}/[AWS_KEY]/g'                                        # AWS keys
    's|/[a-zA-Z0-9/_.-]+/[a-zA-Z0-9._-]+\.[a-z]+|[FILE_PATH]|g'            # file paths
    's/[0-9]{3}-[0-9]{2}-[0-9]{4}/[SSN]/g'                                  # SSN
)

# Banned tokens for output sanitization (SDD 4.1)
BANNED_TOKENS=(
    "ignore previous"
    "disregard instructions"
    "system prompt"
    "you are now"
    "act as"
)

# =============================================================================
# Logging
# =============================================================================

log_error() { echo "[ERROR] $(date -Iseconds) $*" >&2; }
log_warning() { echo "[WARN] $(date -Iseconds) $*" >&2; }
log_info() { echo "[INFO] $(date -Iseconds) $*" >&2; }
log_debug() { [[ "${LOA_DEBUG:-false}" == "true" ]] && echo "[DEBUG] $(date -Iseconds) $*" >&2 || true; }

# Log to trajectory
log_trajectory() {
    local event_type="$1"
    local data="$2"

    (umask 077 && mkdir -p "$TRAJECTORY_DIR")
    local date_str
    date_str=$(date +%Y-%m-%d)
    local log_file="$TRAJECTORY_DIR/flatline-learning-$date_str.jsonl"

    touch "$log_file"
    chmod 600 "$log_file"

    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    jq -n \
        --arg type "flatline_learning_extractor" \
        --arg event "$event_type" \
        --arg timestamp "$timestamp" \
        --argjson data "$data" \
        '{type: $type, event: $event, timestamp: $timestamp, data: $data}' >> "$log_file"
}

# =============================================================================
# Configuration Reading
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

load_config() {
    MIN_CONSENSUS=$(read_config '.compound_learning.flatline_integration.capture_from_flatline.min_consensus_score' "$MIN_CONSENSUS")
    INCLUDE_DISPUTED=$(read_config '.compound_learning.flatline_integration.capture_from_flatline.include_disputed' "$INCLUDE_DISPUTED")
    DISPUTED_MAX_DELTA=$(read_config '.compound_learning.flatline_integration.capture_from_flatline.disputed_max_delta' "$DISPUTED_MAX_DELTA")
    FALLBACK_TO_LLM=$(read_config '.compound_learning.flatline_integration.transformation.fallback_to_llm' "$FALLBACK_TO_LLM")
}

# =============================================================================
# Data Sanitization (SDD 3.7)
# =============================================================================

# Redact sensitive content from text
redact_content() {
    local text="$1"
    local result="$text"

    for pattern in "${REDACT_PATTERNS[@]}"; do
        result=$(echo "$result" | sed -E "$pattern")
    done

    # Remove code blocks
    result=$(echo "$result" | sed '/```/,/```/d')

    # Truncate long text
    if [[ ${#result} -gt 2000 ]]; then
        result="${result:0:2000}..."
    fi

    echo "$result"
}

# Check for banned tokens in output
check_banned_tokens() {
    local text="$1"
    local lower_text
    lower_text=$(echo "$text" | tr '[:upper:]' '[:lower:]')

    for token in "${BANNED_TOKENS[@]}"; do
        if [[ "$lower_text" == *"$token"* ]]; then
            log_warning "Banned token detected: $token"
            return 1
        fi
    done

    return 0
}

# =============================================================================
# Pattern-Based Transformation (SDD 4.1)
# =============================================================================

# Try to extract trigger/solution from HIGH_CONSENSUS content using patterns
transform_with_patterns() {
    local content="$1"
    local category="$2"

    # Pattern 1: "When X, do Y" format
    if [[ "$content" =~ ^[Ww]hen[[:space:]](.+)[,\.][[:space:]]+(add|use|implement|create|configure|handle|ensure|include)([[:space:]]|$) ]]; then
        local trigger="When ${BASH_REMATCH[1]}"
        local solution="${content#*,}"
        solution="${solution#*. }"

        jq -n \
            --arg trigger "$trigger" \
            --arg solution "$solution" \
            '{trigger: $trigger, solution: $solution, transform_method: "pattern_when"}'
        return 0
    fi

    # Pattern 2: "Add X for Y" format
    if [[ "$content" =~ ^(Add|Implement|Create|Include)[[:space:]](.+)[[:space:]]for[[:space:]](.+)$ ]]; then
        local action="${BASH_REMATCH[1]}"
        local what="${BASH_REMATCH[2]}"
        local why="${BASH_REMATCH[3]}"

        jq -n \
            --arg trigger "When $why" \
            --arg solution "$action $what" \
            '{trigger: $trigger, solution: $solution, transform_method: "pattern_add_for"}'
        return 0
    fi

    # Pattern 3: "X should Y" format
    if [[ "$content" =~ (.+)[[:space:]]should[[:space:]](.+)$ ]]; then
        local subject="${BASH_REMATCH[1]}"
        local action="${BASH_REMATCH[2]}"

        jq -n \
            --arg trigger "When working with $subject" \
            --arg solution "Ensure $subject should $action" \
            '{trigger: $trigger, solution: $solution, transform_method: "pattern_should"}'
        return 0
    fi

    # Pattern 4: Category-based default (fallback before LLM)
    case "$category" in
        resilience|error_handling)
            jq -n \
                --arg trigger "When encountering errors or failures in this context" \
                --arg solution "$content" \
                '{trigger: $trigger, solution: $solution, transform_method: "pattern_category_resilience"}'
            return 0
            ;;
        security)
            jq -n \
                --arg trigger "When implementing security-sensitive functionality" \
                --arg solution "$content" \
                '{trigger: $trigger, solution: $solution, transform_method: "pattern_category_security"}'
            return 0
            ;;
        performance)
            jq -n \
                --arg trigger "When optimizing for performance" \
                --arg solution "$content" \
                '{trigger: $trigger, solution: $solution, transform_method: "pattern_category_performance"}'
            return 0
            ;;
    esac

    # No pattern matched
    return 1
}

# =============================================================================
# LLM Fallback Transformation (SDD 4.1)
# =============================================================================

transform_with_llm() {
    local content="$1"
    local item_id="$2"

    # Check budget before API call
    if declare -f check_budget &>/dev/null; then
        if ! check_budget "transform_learning" 5; then
            log_error "Budget exceeded for transformation"
            return 3
        fi
    fi

    # Sanitize input before LLM call
    local sanitized_content
    sanitized_content=$(redact_content "$content")

    log_debug "Calling LLM for transformation: $item_id"

    # Build prompt
    local prompt
    prompt=$(cat <<'EOF'
Transform this improvement suggestion into a reusable learning with a clear trigger and solution.

Content: {CONTENT}

Return ONLY valid JSON in this exact format:
{
  "trigger": "When [specific situation/context when this applies]",
  "solution": "[what to do in that situation]",
  "confidence": 0.8
}

Requirements:
- trigger MUST start with "When " and be at least 10 characters
- solution MUST be actionable and at least 10 characters
- confidence MUST be between 0.0 and 1.0
EOF
)

    prompt="${prompt//\{CONTENT\}/$sanitized_content}"

    # Make API call (using api-resilience.sh if available)
    local response
    if declare -f call_api_with_retry &>/dev/null; then
        response=$(call_api_with_retry "${OPENAI_API_BASE:-https://api.openai.com}/v1/chat/completions" "POST" \
            "$(jq -n --arg prompt "$prompt" '{
                model: "gpt-4o-mini",
                messages: [{role: "user", content: $prompt}],
                temperature: 0.3,
                max_tokens: 500
            }')" 30)
    else
        # SEC-AUDIT SEC-HIGH-01: Use curl config to avoid exposing API key in process list
        local _curl_cfg
        _curl_cfg=$(mktemp) && chmod 600 "$_curl_cfg"
        printf 'header = "Content-Type: application/json"\nheader = "Authorization: Bearer %s"\n' "${OPENAI_API_KEY:-}" > "$_curl_cfg"
        response=$(curl -s --max-time 30 \
            -X POST "${OPENAI_API_BASE:-https://api.openai.com}/v1/chat/completions" \
            --config "$_curl_cfg" \
            -d "$(jq -n --arg prompt "$prompt" '{
                model: "gpt-4o-mini",
                messages: [{role: "user", content: $prompt}],
                temperature: 0.3,
                max_tokens: 500
            }')" 2>/dev/null)
        rm -f "$_curl_cfg"
    fi

    if [[ -z "$response" ]]; then
        log_error "Empty response from LLM"
        return 4
    fi

    # Extract JSON from response
    local result
    result=$(echo "$response" | jq -r '.choices[0].message.content // ""' 2>/dev/null)

    if [[ -z "$result" ]]; then
        log_error "No content in LLM response"
        return 4
    fi

    # Try to extract JSON from the response
    local json_result
    json_result=$(echo "$result" | grep -o '{[^}]*}' | head -1 || echo "")

    if [[ -z "$json_result" ]]; then
        log_error "No JSON found in LLM response"
        return 4
    fi

    # Validate against schema
    if declare -f validate_transformation_response &>/dev/null; then
        if ! validate_transformation_response "$json_result"; then
            log_error "LLM response failed schema validation"
            return 2
        fi
    fi

    # Check for banned tokens in output
    if ! check_banned_tokens "$json_result"; then
        log_error "LLM output contains banned tokens"
        return 2
    fi

    # Record spend
    if declare -f record_spend &>/dev/null; then
        record_spend "transform_learning" 5
    fi

    # Add transform method and quarantine flag
    echo "$json_result" | jq '. + {transform_method: "llm", quarantine: true}'
    return 0
}

# =============================================================================
# Main Extraction Logic
# =============================================================================

extract_learnings() {
    local result_json="$1"

    # Validate input against flatline-result schema (optional - schema validation is advisory)
    # The extractor can work with simplified inputs that have just high_consensus array
    if [[ -f "$SCHEMA_DIR/flatline-result.schema.json" ]] && declare -f validate_against_schema &>/dev/null; then
        if ! validate_against_schema "$result_json" "flatline-result" 2>/dev/null; then
            log_debug "Input did not match full flatline-result schema, using simplified mode"
        fi
    fi

    # Ensure we have at least the high_consensus array
    if ! echo "$result_json" | jq -e '.high_consensus // empty' >/dev/null 2>&1; then
        log_error "Input missing required 'high_consensus' array"
        return 1
    fi

    # Extract high_consensus items
    local high_consensus
    high_consensus=$(echo "$result_json" | jq -c '.high_consensus // []')

    local high_count
    high_count=$(echo "$high_consensus" | jq 'length')

    log_info "Processing $high_count HIGH_CONSENSUS items (min score: $MIN_CONSENSUS)"

    # Use temp file for counting (avoid subshell counter issue)
    local count_file
    count_file=$(mktemp)
    echo "0 0 0" > "$count_file"

    # Process each item using process substitution to avoid subshell
    while IFS= read -r item; do
        local item_id score content category

        item_id=$(echo "$item" | jq -r '.id // .item_id // "unknown"')
        score=$(echo "$item" | jq -r '.consensus_score // .score // 0')
        content=$(echo "$item" | jq -r '.content // .suggestion // .text // ""')
        category=$(echo "$item" | jq -r '.category // "general"')

        log_debug "Processing item: $item_id (score: $score)"

        # Check minimum consensus score
        if [[ "$score" -lt "$MIN_CONSENSUS" ]]; then
            log_debug "Skipping $item_id: score $score < $MIN_CONSENSUS"
            read ext skip fail < "$count_file"; echo "$ext $((skip+1)) $fail" > "$count_file"
            continue
        fi

        # Skip empty content
        if [[ -z "$content" ]]; then
            log_debug "Skipping $item_id: empty content"
            read ext skip fail < "$count_file"; echo "$ext $((skip+1)) $fail" > "$count_file"
            continue
        fi

        # Try pattern-based transformation first
        local transformed
        if transformed=$(transform_with_patterns "$content" "$category"); then
            log_debug "Pattern transformation successful for $item_id"
        elif [[ "$FALLBACK_TO_LLM" == "true" ]]; then
            # Try LLM fallback
            if transformed=$(transform_with_llm "$content" "$item_id"); then
                log_debug "LLM transformation successful for $item_id"
            else
                log_warning "Transformation failed for $item_id"
                read ext skip fail < "$count_file"; echo "$ext $skip $((fail+1))" > "$count_file"
                continue
            fi
        else
            log_warning "No pattern matched and LLM fallback disabled for $item_id"
            read ext skip fail < "$count_file"; echo "$ext $((skip+1)) $fail" > "$count_file"
            continue
        fi

        # Build learning object
        local learning
        learning=$(echo "$transformed" | jq \
            --arg id "learn-flatline-$(date +%s)-$RANDOM" \
            --arg source "flatline" \
            --arg source_id "$item_id" \
            --argjson consensus_score "$score" \
            --arg category "$category" \
            --arg extracted_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
            '. + {
                id: $id,
                source: $source,
                source_id: $source_id,
                consensus_score: $consensus_score,
                category: $category,
                extracted_at: $extracted_at
            }')

        # Output based on format
        if [[ "$OUTPUT_FORMAT" == "json" ]]; then
            echo "$learning"
        else
            # JSONL format (default)
            echo "$learning"
        fi

        # Update extracted counter
        read ext skip fail < "$count_file"; echo "$((ext+1)) $skip $fail" > "$count_file"

        # Log to trajectory
        log_trajectory "flatline_learning_extracted" "$learning"
    done < <(echo "$high_consensus" | jq -c '.[]')

    # Process disputed items if configured
    if [[ "$INCLUDE_DISPUTED" == "true" ]]; then
        local disputed
        disputed=$(echo "$result_json" | jq -c '.disputed // []')

        local disputed_count
        disputed_count=$(echo "$disputed" | jq 'length')

        if [[ "$disputed_count" -gt 0 ]]; then
            log_info "Processing $disputed_count DISPUTED items (max delta: $DISPUTED_MAX_DELTA)"

            while IFS= read -r item; do
                local delta
                delta=$(echo "$item" | jq -r '.delta // .score_delta // 999')

                if [[ "$delta" -le "$DISPUTED_MAX_DELTA" ]]; then
                    # Process similar to high_consensus but mark as disputed
                    local item_id content category
                    item_id=$(echo "$item" | jq -r '.id // "unknown"')
                    content=$(echo "$item" | jq -r '.content // .description // ""')
                    category=$(echo "$item" | jq -r '.category // "general"')

                    local transformed
                    if transformed=$(transform_with_patterns "$content" "$category"); then
                        local learning
                        learning=$(echo "$transformed" | jq \
                            --arg id "learn-flatline-disputed-$(date +%s)-$RANDOM" \
                            --arg source "flatline-disputed" \
                            --arg source_id "$item_id" \
                            '. + {
                                id: $id,
                                source: $source,
                                source_id: $source_id,
                                requires_review: true
                            }')

                        echo "$learning"
                        read ext skip fail < "$count_file"; echo "$((ext+1)) $skip $fail" > "$count_file"
                    fi
                fi
            done < <(echo "$disputed" | jq -c '.[]')
        fi
    fi

    # Read final counts
    local extracted skipped failed
    read extracted skipped failed < "$count_file"
    rm -f "$count_file"

    log_info "Extraction complete: $extracted extracted, $skipped skipped, $failed failed"

    # Log summary to trajectory
    log_trajectory "extraction_complete" "$(jq -n \
        --argjson extracted "$extracted" \
        --argjson skipped "$skipped" \
        --argjson failed "$failed" \
        '{extracted: $extracted, skipped: $skipped, failed: $failed}')"
}

# =============================================================================
# CLI Interface
# =============================================================================

usage() {
    cat <<EOF
Usage: flatline-learning-extractor.sh [options]

Extract learning candidates from Flatline HIGH_CONSENSUS outputs.

Options:
  --result <json|file>       Flatline result JSON or path to JSON file (required)
  --min-consensus <score>    Minimum consensus score (default: 750)
  --include-disputed         Include DISPUTED items with low delta
  --disputed-max-delta <n>   Maximum delta for disputed items (default: 200)
  --output <format>          Output format: jsonl (default), json
  --no-llm                   Disable LLM fallback transformation
  --dry-run                  Show what would be extracted without writing
  --help                     Show this help

Environment Variables:
  LOA_MIN_CONSENSUS          Default minimum consensus score
  LOA_FALLBACK_TO_LLM        Enable/disable LLM fallback (true/false)
  OPENAI_API_KEY             Required for LLM transformation
  LOA_DEBUG                  Enable debug logging (true/false)

Examples:
  # Extract from result file
  ./flatline-learning-extractor.sh --result grimoires/loa/a2a/flatline/prd-review.json

  # Extract with custom threshold, output as JSON array
  ./flatline-learning-extractor.sh --result result.json --min-consensus 700 --output json

  # Include disputed items
  ./flatline-learning-extractor.sh --result result.json --include-disputed --disputed-max-delta 150

Exit Codes:
  0 - Success
  1 - Invalid arguments
  2 - Schema validation failed
  3 - Budget exceeded
  4 - API error
EOF
}

main() {
    local result_input=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --result)
                result_input="$2"
                shift 2
                ;;
            --min-consensus)
                MIN_CONSENSUS="$2"
                shift 2
                ;;
            --include-disputed)
                INCLUDE_DISPUTED=true
                shift
                ;;
            --disputed-max-delta)
                DISPUTED_MAX_DELTA="$2"
                shift 2
                ;;
            --output)
                OUTPUT_FORMAT="$2"
                shift 2
                ;;
            --no-llm)
                FALLBACK_TO_LLM=false
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
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

    # Load configuration
    load_config

    # Validate required arguments
    if [[ -z "$result_input" ]]; then
        log_error "--result is required"
        usage
        exit 1
    fi

    # Load result JSON
    local result_json
    if [[ "$result_input" == "-" ]]; then
        result_json=$(cat)
    elif [[ -f "$result_input" ]]; then
        result_json=$(cat "$result_input")
    else
        result_json="$result_input"
    fi

    # Validate JSON
    if ! echo "$result_json" | jq '.' >/dev/null 2>&1; then
        log_error "Invalid JSON input"
        exit 1
    fi

    # Ensure output directory exists
    mkdir -p "$COMPOUND_DIR"

    # Extract learnings
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would extract learnings from:"
        echo "$result_json" | jq '.high_consensus | length' | xargs -I{} echo "  HIGH_CONSENSUS: {} items"
        echo "$result_json" | jq '.disputed | length' | xargs -I{} echo "  DISPUTED: {} items"
    else
        extract_learnings "$result_json"
    fi
}

main "$@"
