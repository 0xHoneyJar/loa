#!/usr/bin/env bash
# =============================================================================
# flatline-validate-learning.sh - Single-Learning Validator via Flatline
# =============================================================================
# Part of Flatline-Enhanced Compound Learning v1.23.0 (Sprint 2)
# Addresses: T2.1 - Create single-learning validator using 2-call review
#
# Validates borderline learnings (score 20-28/40) with multi-model review.
# Implements 3-layer circular prevention (SDD 7.1):
#   L1: Skip if source: flatline
#   L2: Check validation history
#   L3: Rate limit (30s default)
#
# Usage:
#   flatline-validate-learning.sh --learning <json|file> [options]
#
# Exit codes:
#   0 - Success (validation complete)
#   1 - Invalid arguments
#   2 - Skipped (circular prevention)
#   3 - Budget exceeded
#   4 - API error
#   5 - Schema validation failed
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_FILE="$PROJECT_ROOT/.loa.config.yaml"
LIB_DIR="$SCRIPT_DIR/lib"
SCHEMA_DIR="$PROJECT_ROOT/.claude/schemas"
TRAJECTORY_DIR="$PROJECT_ROOT/grimoires/loa/a2a/trajectory"

# Source utilities
if [[ -f "$LIB_DIR/api-resilience.sh" ]]; then
    source "$LIB_DIR/api-resilience.sh"
fi

if [[ -f "$LIB_DIR/schema-validator.sh" ]]; then
    source "$LIB_DIR/schema-validator.sh"
fi

if [[ -f "$LIB_DIR/validation-history.sh" ]]; then
    source "$LIB_DIR/validation-history.sh"
fi

# =============================================================================
# Configuration
# =============================================================================

TIMEOUT_SECONDS="${LOA_VALIDATION_TIMEOUT:-60}"
OUTPUT_FORMAT="${LOA_OUTPUT_FORMAT:-json}"
DRY_RUN=false
SKIP_CIRCULAR_CHECK=false

# API configuration
GPT_MODEL="${LOA_GPT_MODEL:-gpt-4o}"
OPUS_MODEL="${LOA_OPUS_MODEL:-claude-3-opus-20240229}"

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
    local log_file="$TRAJECTORY_DIR/flatline-validation-$date_str.jsonl"

    touch "$log_file"
    chmod 600 "$log_file"

    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    jq -n \
        --arg type "flatline_validation" \
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

get_max_validations() {
    read_config '.compound_learning.flatline_integration.validation.max_validations_per_cycle' '10'
}

get_rate_limit() {
    read_config '.compound_learning.flatline_integration.validation.rate_limit_seconds' '30'
}

# =============================================================================
# Circular Prevention (SDD 7.1)
# =============================================================================

# Layer 1: Check source field
check_l1_source() {
    local learning_json="$1"

    local source
    source=$(echo "$learning_json" | jq -r '.source // ""')

    if [[ "$source" == "flatline" || "$source" == "flatline-disputed" ]]; then
        log_info "L1: Skipping Flatline-derived learning (source: $source)"
        return 0  # Skip
    fi

    return 1  # OK to proceed
}

# Layer 2: Check validation history
check_l2_history() {
    local learning_id="$1"

    if declare -f check_validation_history &>/dev/null; then
        if check_validation_history "$learning_id"; then
            log_info "L2: Skipping already-validated learning: $learning_id"
            return 0  # Skip
        fi
    fi

    return 1  # OK to proceed
}

# Layer 3: Check rate limit
check_l3_rate_limit() {
    local learning_id="$1"

    if declare -f check_rate_limit &>/dev/null; then
        if check_rate_limit "$learning_id"; then
            log_info "L3: Rate limited for learning: $learning_id"
            return 0  # Skip
        fi
    fi

    return 1  # OK to proceed
}

# =============================================================================
# Data Redaction (SDD 3.7)
# =============================================================================

redact_learning() {
    local learning_json="$1"

    # Redact sensitive patterns from trigger and solution
    echo "$learning_json" | jq '
        .trigger |= gsub("[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}"; "[EMAIL]") |
        .trigger |= gsub("sk-[a-zA-Z0-9]{48}"; "[API_KEY]") |
        .trigger |= gsub("/[a-zA-Z0-9/_.-]+/[a-zA-Z0-9._-]+\\.[a-z]+"; "[PATH]") |
        .solution |= gsub("[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}"; "[EMAIL]") |
        .solution |= gsub("sk-[a-zA-Z0-9]{48}"; "[API_KEY]") |
        .solution |= gsub("/[a-zA-Z0-9/_.-]+/[a-zA-Z0-9._-]+\\.[a-z]+"; "[PATH]")
    '
}

# =============================================================================
# API Calls
# =============================================================================

# Build validation prompt
build_validation_prompt() {
    local learning_json="$1"

    local trigger solution
    trigger=$(echo "$learning_json" | jq -r '.trigger')
    solution=$(echo "$learning_json" | jq -r '.solution')

    cat <<EOF
Evaluate this learning for inclusion in a framework learning library.

TRIGGER: $trigger
SOLUTION: $solution

Assess whether this learning is:
1. Generalizable (applies beyond a single project)
2. Actionable (provides clear guidance)
3. Accurate (technically correct)
4. Non-trivial (not obvious to experienced developers)

Respond with ONLY valid JSON:
{
  "vote": "approve" or "reject",
  "confidence": 0.0 to 1.0,
  "reasoning": "Brief explanation (max 100 words)"
}
EOF
}

# Call GPT for validation
call_gpt_validation() {
    local learning_json="$1"

    local prompt
    prompt=$(build_validation_prompt "$learning_json")

    # Check budget
    if declare -f check_budget &>/dev/null; then
        if ! check_budget "validate_learning_gpt" 10; then
            log_error "Budget exceeded for GPT validation"
            return 3
        fi
    fi

    local response
    if declare -f call_api_with_retry &>/dev/null; then
        response=$(call_api_with_retry "${OPENAI_API_BASE:-https://api.openai.com}/v1/chat/completions" "POST" \
            "$(jq -n --arg prompt "$prompt" --arg model "$GPT_MODEL" '{
                model: $model,
                messages: [{role: "user", content: $prompt}],
                temperature: 0.2,
                max_tokens: 300
            }')" "$TIMEOUT_SECONDS")
    else
        # SEC-AUDIT SEC-HIGH-01: Use curl config to avoid exposing API key in process list
        local _curl_cfg
        _curl_cfg=$(mktemp) && chmod 600 "$_curl_cfg"
        printf 'header = "Content-Type: application/json"\nheader = "Authorization: Bearer %s"\n' "${OPENAI_API_KEY:-}" > "$_curl_cfg"
        response=$(curl -s --max-time "$TIMEOUT_SECONDS" \
            -X POST "${OPENAI_API_BASE:-https://api.openai.com}/v1/chat/completions" \
            --config "$_curl_cfg" \
            -d "$(jq -n --arg prompt "$prompt" --arg model "$GPT_MODEL" '{
                model: $model,
                messages: [{role: "user", content: $prompt}],
                temperature: 0.2,
                max_tokens: 300
            }')" 2>/dev/null)
        rm -f "$_curl_cfg"
    fi

    if [[ -z "$response" ]]; then
        log_error "Empty response from GPT"
        return 4
    fi

    # Extract and validate response
    local result
    result=$(echo "$response" | jq -r '.choices[0].message.content // ""' 2>/dev/null)

    # Try to extract JSON
    local json_result
    json_result=$(echo "$result" | grep -o '{[^}]*}' | head -1 || echo "")

    if [[ -z "$json_result" ]]; then
        log_error "No JSON found in GPT response"
        return 4
    fi

    # Validate against schema
    if declare -f validate_vote_response &>/dev/null; then
        if ! validate_vote_response "$json_result"; then
            log_warning "GPT response failed schema validation, using raw"
        fi
    fi

    # Record spend
    if declare -f record_spend &>/dev/null; then
        record_spend "validate_learning_gpt" 10
    fi

    echo "$json_result" | jq '. + {model: "gpt"}'
}

# Call Opus for validation (via Anthropic API)
call_opus_validation() {
    local learning_json="$1"

    local prompt
    prompt=$(build_validation_prompt "$learning_json")

    # Check budget
    if declare -f check_budget &>/dev/null; then
        if ! check_budget "validate_learning_opus" 15; then
            log_error "Budget exceeded for Opus validation"
            return 3
        fi
    fi

    local response
    # SEC-AUDIT SEC-HIGH-01: Use curl config to avoid exposing API key in process list
    local _curl_cfg
    _curl_cfg=$(mktemp) && chmod 600 "$_curl_cfg"
    printf 'header = "Content-Type: application/json"\nheader = "x-api-key: %s"\nheader = "anthropic-version: 2023-06-01"\n' "${ANTHROPIC_API_KEY:-}" > "$_curl_cfg"
    response=$(curl -s --max-time "$TIMEOUT_SECONDS" \
        -X POST "https://api.anthropic.com/v1/messages" \
        --config "$_curl_cfg" \
        -d "$(jq -n --arg prompt "$prompt" --arg model "$OPUS_MODEL" '{
            model: $model,
            max_tokens: 300,
            messages: [{role: "user", content: $prompt}]
        }')" 2>/dev/null)
    rm -f "$_curl_cfg"

    if [[ -z "$response" ]]; then
        log_error "Empty response from Opus"
        return 4
    fi

    # Extract and validate response
    local result
    result=$(echo "$response" | jq -r '.content[0].text // ""' 2>/dev/null)

    # Try to extract JSON
    local json_result
    json_result=$(echo "$result" | grep -o '{[^}]*}' | head -1 || echo "")

    if [[ -z "$json_result" ]]; then
        log_error "No JSON found in Opus response"
        return 4
    fi

    # Validate against schema
    if declare -f validate_vote_response &>/dev/null; then
        if ! validate_vote_response "$json_result"; then
            log_warning "Opus response failed schema validation, using raw"
        fi
    fi

    # Record spend
    if declare -f record_spend &>/dev/null; then
        record_spend "validate_learning_opus" 15
    fi

    echo "$json_result" | jq '. + {model: "opus"}'
}

# =============================================================================
# Consensus Mapping
# =============================================================================

# Map votes to consensus result
# approve + approve = APPROVE → promote
# reject + reject = REJECT → demote
# mixed = DISPUTED → human_review
map_consensus() {
    local gpt_vote="$1"
    local opus_vote="$2"
    local gpt_confidence="$3"
    local opus_confidence="$4"

    local consensus action

    if [[ "$gpt_vote" == "approve" && "$opus_vote" == "approve" ]]; then
        consensus="APPROVE"
        action="promote"
    elif [[ "$gpt_vote" == "reject" && "$opus_vote" == "reject" ]]; then
        consensus="REJECT"
        action="demote"
    else
        consensus="DISPUTED"
        action="human_review"
    fi

    # Calculate average confidence
    local avg_confidence
    avg_confidence=$(echo "scale=2; ($gpt_confidence + $opus_confidence) / 2" | bc)

    jq -n \
        --arg consensus "$consensus" \
        --arg action "$action" \
        --arg gpt_vote "$gpt_vote" \
        --arg opus_vote "$opus_vote" \
        --argjson gpt_conf "$gpt_confidence" \
        --argjson opus_conf "$opus_confidence" \
        --argjson avg_conf "$avg_confidence" \
        '{
            consensus: $consensus,
            action: $action,
            votes: {
                gpt: {vote: $gpt_vote, confidence: $gpt_conf},
                opus: {vote: $opus_vote, confidence: $opus_conf}
            },
            average_confidence: $avg_conf
        }'
}

# =============================================================================
# Main Validation Logic
# =============================================================================

validate_learning() {
    local learning_json="$1"

    # Get learning ID
    local learning_id
    learning_id=$(echo "$learning_json" | jq -r '.id // "unknown"')

    log_info "Validating learning: $learning_id"

    # 3-Layer Circular Prevention (unless skipped)
    if [[ "$SKIP_CIRCULAR_CHECK" != "true" ]]; then
        # L1: Check source
        if check_l1_source "$learning_json"; then
            jq -n --arg id "$learning_id" --arg reason "flatline_source" \
                '{skipped: true, learning_id: $id, reason: $reason}'
            return 2
        fi

        # L2: Check history
        if check_l2_history "$learning_id"; then
            jq -n --arg id "$learning_id" --arg reason "already_validated" \
                '{skipped: true, learning_id: $id, reason: $reason}'
            return 2
        fi

        # L3: Check rate limit
        if check_l3_rate_limit "$learning_id"; then
            jq -n --arg id "$learning_id" --arg reason "rate_limited" \
                '{skipped: true, learning_id: $id, reason: $reason}'
            return 2
        fi
    fi

    # Check max validations per cycle
    if declare -f get_validation_count &>/dev/null; then
        local current_count max_validations
        current_count=$(get_validation_count)
        max_validations=$(get_max_validations)

        if [[ "$current_count" -ge "$max_validations" ]]; then
            log_warning "Max validations per cycle reached ($current_count/$max_validations)"
            jq -n --arg id "$learning_id" --arg reason "budget_limit" \
                '{skipped: true, learning_id: $id, reason: $reason}'
            return 3
        fi
    fi

    # Redact sensitive content before API calls
    local redacted_learning
    redacted_learning=$(redact_learning "$learning_json")

    log_trajectory "validation_started" "$(jq -n --arg id "$learning_id" '{learning_id: $id}')"

    # Make parallel API calls (GPT + Opus)
    local gpt_result opus_result
    local gpt_exit=0 opus_exit=0

    if [[ "$DRY_RUN" == "true" ]]; then
        gpt_result='{"vote":"approve","confidence":0.8,"reasoning":"dry run","model":"gpt"}'
        opus_result='{"vote":"approve","confidence":0.85,"reasoning":"dry run","model":"opus"}'
    else
        # Call GPT
        gpt_result=$(call_gpt_validation "$redacted_learning") || gpt_exit=$?

        # Call Opus
        opus_result=$(call_opus_validation "$redacted_learning") || opus_exit=$?
    fi

    # Handle API failures
    if [[ $gpt_exit -ne 0 || -z "$gpt_result" ]]; then
        log_error "GPT validation failed"
        log_trajectory "validation_failed" "$(jq -n --arg id "$learning_id" --arg reason "gpt_api_error" '{learning_id: $id, reason: $reason}')"
        return 4
    fi

    if [[ $opus_exit -ne 0 || -z "$opus_result" ]]; then
        log_error "Opus validation failed"
        log_trajectory "validation_failed" "$(jq -n --arg id "$learning_id" --arg reason "opus_api_error" '{learning_id: $id, reason: $reason}')"
        return 4
    fi

    # Extract votes
    local gpt_vote gpt_conf opus_vote opus_conf
    gpt_vote=$(echo "$gpt_result" | jq -r '.vote')
    gpt_conf=$(echo "$gpt_result" | jq -r '.confidence')
    opus_vote=$(echo "$opus_result" | jq -r '.vote')
    opus_conf=$(echo "$opus_result" | jq -r '.confidence')

    # Map to consensus
    local consensus_result
    consensus_result=$(map_consensus "$gpt_vote" "$opus_vote" "$gpt_conf" "$opus_conf")

    # Record in history
    if declare -f record_validation &>/dev/null; then
        local action
        action=$(echo "$consensus_result" | jq -r '.action')
        record_validation "$learning_id" "$action"
    fi

    # Build final result
    local final_result
    final_result=$(jq -n \
        --arg learning_id "$learning_id" \
        --argjson consensus "$consensus_result" \
        --argjson gpt "$gpt_result" \
        --argjson opus "$opus_result" \
        --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{
            learning_id: $learning_id,
            timestamp: $timestamp,
            consensus: $consensus.consensus,
            action: $consensus.action,
            average_confidence: $consensus.average_confidence,
            votes: {
                gpt: $gpt,
                opus: $opus
            }
        }')

    log_trajectory "borderline_validation_complete" "$final_result"

    log_info "Validation complete: $learning_id → $(echo "$consensus_result" | jq -r '.consensus')"

    echo "$final_result"
}

# =============================================================================
# CLI Interface
# =============================================================================

usage() {
    cat <<EOF
Usage: flatline-validate-learning.sh [options]

Validate a single learning using multi-model review (GPT + Opus).

Options:
  --learning <json|file>     Learning JSON or path to JSON file (required)
  --timeout <seconds>        API timeout (default: 60)
  --output <format>          Output format: json (default)
  --skip-circular-check      Skip 3-layer circular prevention
  --dry-run                  Show validation without making API calls
  --help                     Show this help

Environment Variables:
  OPENAI_API_KEY             Required for GPT validation
  ANTHROPIC_API_KEY          Required for Opus validation
  LOA_DEBUG                  Enable debug logging (true/false)
  LOA_VALIDATION_RATE_LIMIT  Rate limit seconds (default: 30)

Circular Prevention (SDD 7.1):
  L1: Skip if source: flatline (prevent validating Flatline-derived learnings)
  L2: Check validation history (prevent re-validation in same cycle)
  L3: Rate limit (prevent rapid successive validations)

Consensus Mapping:
  approve + approve = APPROVE → promote to qualified
  reject + reject = REJECT → demote to low_value
  mixed = DISPUTED → flag for human_review

Exit Codes:
  0 - Success
  1 - Invalid arguments
  2 - Skipped (circular prevention)
  3 - Budget exceeded
  4 - API error
  5 - Schema validation failed
EOF
}

main() {
    local learning_input=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --learning)
                learning_input="$2"
                shift 2
                ;;
            --timeout)
                TIMEOUT_SECONDS="$2"
                shift 2
                ;;
            --output)
                OUTPUT_FORMAT="$2"
                shift 2
                ;;
            --skip-circular-check)
                SKIP_CIRCULAR_CHECK=true
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

    # Validate learning
    validate_learning "$learning_json"
}

main "$@"
