#!/usr/bin/env bash
# =============================================================================
# flatline-proposal-review.sh - Pre-Proposal Adversarial Review
# =============================================================================
# Part of Flatline-Enhanced Compound Learning v1.23.0 (Sprint 3)
# Addresses: T3.3 - Pre-review upstream proposals with 2-call analysis
#
# Reviews learnings before upstream proposal with adversarial alignment check.
# Both models must score >= min_alignment for proposal to proceed.
#
# Usage:
#   flatline-proposal-review.sh --learning <json|file> [options]
#
# Exit codes:
#   0 - Success (passed review)
#   1 - Invalid arguments
#   2 - Failed review (below alignment threshold)
#   3 - Budget exceeded
#   4 - API error
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

if [[ -f "$LIB_DIR/context-isolation-lib.sh" ]]; then
    source "$LIB_DIR/context-isolation-lib.sh"
fi

# =============================================================================
# Configuration
# =============================================================================

MIN_ALIGNMENT="${LOA_MIN_ALIGNMENT:-600}"  # 0-1000 scale
TIMEOUT_SECONDS="${LOA_REVIEW_TIMEOUT:-60}"
OUTPUT_FORMAT="${LOA_OUTPUT_FORMAT:-json}"
DRY_RUN=false

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
    local log_file="$TRAJECTORY_DIR/proposal-review-$date_str.jsonl"

    touch "$log_file"
    chmod 600 "$log_file"

    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    jq -n \
        --arg type "proposal_review" \
        --arg event "$event_type" \
        --arg timestamp "$timestamp" \
        --argjson data "$data" \
        '{type: $type, event: $event, timestamp: $timestamp, data: $data}' >> "$log_file"
}

# =============================================================================
# Review Prompt
# =============================================================================

build_review_prompt() {
    local learning_json="$1"

    local trigger solution tags
    trigger=$(echo "$learning_json" | jq -r '.trigger')
    solution=$(echo "$learning_json" | jq -r '.solution')
    tags=$(echo "$learning_json" | jq -r '.tags // [] | join(", ")')

    # Apply context isolation wrappers (vision-003)
    if command -v isolate_content &>/dev/null; then
        trigger=$(isolate_content "$trigger" "LEARNING TRIGGER")
        solution=$(isolate_content "$solution" "LEARNING SOLUTION")
    fi

    cat <<'PROMPT_EOF'
Review this learning for inclusion in a framework learning library.

LEARNING:
PROMPT_EOF
    printf 'Trigger: %s\nSolution: %s\nTags: %s\n' "$trigger" "$solution" "$tags"
    cat <<'PROMPT_EOF'

Evaluate alignment with framework standards:
1. Generalizability: Does this apply beyond one project?
2. Accuracy: Is the technical advice correct?
3. Clarity: Is the trigger condition clear?
4. Actionability: Can a developer apply this guidance?
5. Non-triviality: Is this beyond basic documentation?

Respond with ONLY valid JSON:
{
  "score": <0-1000>,
  "alignment": true/false,
  "concerns": ["concern 1", "concern 2"],
  "suggestions": ["suggestion 1", "suggestion 2"]
}

Score guide:
- 800-1000: Excellent, ready for framework
- 600-799: Good with minor improvements needed
- 400-599: Needs significant revision
- 0-399: Not suitable for framework
PROMPT_EOF
}

# =============================================================================
# API Calls
# =============================================================================

call_gpt_review() {
    local learning_json="$1"

    local prompt
    prompt=$(build_review_prompt "$learning_json")

    # Check budget
    if declare -f check_budget &>/dev/null; then
        if ! check_budget "proposal_review_gpt" 10; then
            log_error "Budget exceeded for GPT review"
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
                max_tokens: 500
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
                max_tokens: 500
            }')" 2>/dev/null)
        rm -f "$_curl_cfg"
    fi

    if [[ -z "$response" ]]; then
        log_error "Empty response from GPT"
        return 4
    fi

    # Extract JSON from response
    local result
    result=$(echo "$response" | jq -r '.choices[0].message.content // ""' 2>/dev/null)

    local json_result
    json_result=$(echo "$result" | grep -o '{[^}]*}' | head -1 || echo "")

    if [[ -z "$json_result" ]]; then
        log_error "No JSON found in GPT response"
        return 4
    fi

    # Validate against schema
    if declare -f validate_proposal_review_response &>/dev/null; then
        if ! validate_proposal_review_response "$json_result"; then
            log_warning "GPT response failed schema validation"
        fi
    fi

    # Record spend
    if declare -f record_spend &>/dev/null; then
        record_spend "proposal_review_gpt" 10
    fi

    echo "$json_result" | jq '. + {model: "gpt"}'
}

call_opus_review() {
    local learning_json="$1"

    local prompt
    prompt=$(build_review_prompt "$learning_json")

    # Check budget
    if declare -f check_budget &>/dev/null; then
        if ! check_budget "proposal_review_opus" 15; then
            log_error "Budget exceeded for Opus review"
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
            max_tokens: 500,
            messages: [{role: "user", content: $prompt}]
        }')" 2>/dev/null)
    rm -f "$_curl_cfg"

    if [[ -z "$response" ]]; then
        log_error "Empty response from Opus"
        return 4
    fi

    # Extract JSON from response
    local result
    result=$(echo "$response" | jq -r '.content[0].text // ""' 2>/dev/null)

    local json_result
    json_result=$(echo "$result" | grep -o '{[^}]*}' | head -1 || echo "")

    if [[ -z "$json_result" ]]; then
        log_error "No JSON found in Opus response"
        return 4
    fi

    # Validate against schema
    if declare -f validate_proposal_review_response &>/dev/null; then
        if ! validate_proposal_review_response "$json_result"; then
            log_warning "Opus response failed schema validation"
        fi
    fi

    # Record spend
    if declare -f record_spend &>/dev/null; then
        record_spend "proposal_review_opus" 15
    fi

    echo "$json_result" | jq '. + {model: "opus"}'
}

# =============================================================================
# Main Review Logic
# =============================================================================

review_proposal() {
    local learning_json="$1"

    local learning_id
    learning_id=$(echo "$learning_json" | jq -r '.id // "unknown"')

    log_info "Reviewing proposal: $learning_id"

    log_trajectory "proposal_review_started" "$(jq -n --arg id "$learning_id" '{learning_id: $id}')"

    # Make API calls
    local gpt_result opus_result
    local gpt_exit=0 opus_exit=0

    if [[ "$DRY_RUN" == "true" ]]; then
        gpt_result='{"score":750,"alignment":true,"concerns":[],"suggestions":["dry run"],"model":"gpt"}'
        opus_result='{"score":780,"alignment":true,"concerns":[],"suggestions":["dry run"],"model":"opus"}'
    else
        # Call GPT
        gpt_result=$(call_gpt_review "$learning_json") || gpt_exit=$?

        # Call Opus
        opus_result=$(call_opus_review "$learning_json") || opus_exit=$?
    fi

    # Handle API failures
    if [[ $gpt_exit -ne 0 || -z "$gpt_result" ]]; then
        log_error "GPT review failed"
        log_trajectory "proposal_review_failed" "$(jq -n --arg id "$learning_id" --arg reason "gpt_api_error" '{learning_id: $id, reason: $reason}')"
        return 4
    fi

    if [[ $opus_exit -ne 0 || -z "$opus_result" ]]; then
        log_error "Opus review failed"
        log_trajectory "proposal_review_failed" "$(jq -n --arg id "$learning_id" --arg reason "opus_api_error" '{learning_id: $id, reason: $reason}')"
        return 4
    fi

    # Extract scores
    local gpt_score opus_score
    gpt_score=$(echo "$gpt_result" | jq -r '.score')
    opus_score=$(echo "$opus_result" | jq -r '.score')

    # Calculate average and determine pass/fail
    local avg_score
    avg_score=$(echo "scale=0; ($gpt_score + $opus_score) / 2" | bc)

    local passed=true
    local fail_reason=""

    if [[ "$gpt_score" -lt "$MIN_ALIGNMENT" ]]; then
        passed=false
        fail_reason="GPT score ($gpt_score) below threshold ($MIN_ALIGNMENT)"
    fi

    if [[ "$opus_score" -lt "$MIN_ALIGNMENT" ]]; then
        passed=false
        if [[ -n "$fail_reason" ]]; then
            fail_reason="$fail_reason; "
        fi
        fail_reason="${fail_reason}Opus score ($opus_score) below threshold ($MIN_ALIGNMENT)"
    fi

    # Merge concerns and suggestions
    local all_concerns all_suggestions
    all_concerns=$(jq -s '.[0].concerns + .[1].concerns | unique' <(echo "$gpt_result") <(echo "$opus_result"))
    all_suggestions=$(jq -s '.[0].suggestions + .[1].suggestions | unique' <(echo "$gpt_result") <(echo "$opus_result"))

    # Build result
    local final_result
    final_result=$(jq -n \
        --arg learning_id "$learning_id" \
        --argjson passed "$([[ "$passed" == "true" ]] && echo "true" || echo "false")" \
        --argjson gpt_score "$gpt_score" \
        --argjson opus_score "$opus_score" \
        --argjson avg_score "$avg_score" \
        --argjson min_alignment "$MIN_ALIGNMENT" \
        --argjson concerns "$all_concerns" \
        --argjson suggestions "$all_suggestions" \
        --arg fail_reason "$fail_reason" \
        --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --argjson gpt "$gpt_result" \
        --argjson opus "$opus_result" \
        '{
            learning_id: $learning_id,
            timestamp: $timestamp,
            passed: $passed,
            average_score: $avg_score,
            min_alignment: $min_alignment,
            scores: {
                gpt: $gpt_score,
                opus: $opus_score
            },
            concerns: $concerns,
            suggestions: $suggestions,
            fail_reason: (if $passed then null else $fail_reason end),
            reviews: {
                gpt: $gpt,
                opus: $opus
            }
        }')

    log_trajectory "proposal_pre_reviewed" "$final_result"

    if [[ "$passed" == "true" ]]; then
        log_info "Review passed: $learning_id (avg score: $avg_score)"
    else
        log_warning "Review failed: $learning_id - $fail_reason"
    fi

    echo "$final_result"

    # Return exit code based on pass/fail
    [[ "$passed" == "true" ]] && return 0 || return 2
}

# =============================================================================
# CLI Interface
# =============================================================================

usage() {
    cat <<EOF
Usage: flatline-proposal-review.sh [options]

Pre-review a learning before upstream proposal with adversarial alignment check.

Options:
  --learning <json|file>     Learning JSON or path (required)
  --min-alignment <score>    Minimum alignment score (default: 600, range: 0-1000)
  --timeout <seconds>        API timeout (default: 60)
  --output <format>          Output format: json (default)
  --dry-run                  Show review without making API calls
  --help                     Show this help

Environment Variables:
  OPENAI_API_KEY             Required for GPT review
  ANTHROPIC_API_KEY          Required for Opus review
  LOA_DEBUG                  Enable debug logging (true/false)

Pass/Fail Criteria:
  Both models must score >= min_alignment for proposal to pass.

Score Guide:
  800-1000: Excellent, ready for framework
  600-799: Good with minor improvements needed
  400-599: Needs significant revision
  0-399: Not suitable for framework

Exit Codes:
  0 - Passed review
  1 - Invalid arguments
  2 - Failed review (below threshold)
  3 - Budget exceeded
  4 - API error
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
            --min-alignment)
                MIN_ALIGNMENT="$2"
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

    # Review proposal
    review_proposal "$learning_json"
}

main "$@"
