#!/usr/bin/env bash
# =============================================================================
# flatline-orchestrator.sh - Main orchestrator for Flatline Protocol
# =============================================================================
# Version: 1.0.0
# Part of: Flatline Protocol v1.17.0
#
# Usage:
#   flatline-orchestrator.sh --doc <path> --phase <type> [options]
#
# Options:
#   --doc <path>           Document to review (required)
#   --phase <type>         Phase type: prd, sdd, sprint (required)
#   --domain <text>        Domain for knowledge retrieval (auto-extracted if not provided)
#   --dry-run              Validate without executing reviews
#   --skip-knowledge       Skip knowledge retrieval
#   --skip-consensus       Return raw reviews without consensus
#   --timeout <seconds>    Overall timeout (default: 300)
#   --budget <cents>       Cost budget in cents (default: 300 = $3.00)
#   --json                 Output as JSON
#
# State Machine:
#   INIT -> KNOWLEDGE -> PHASE1 -> PHASE2 -> CONSENSUS -> INTEGRATE -> DONE
#
# Exit codes:
#   0 - Success
#   1 - Configuration error
#   2 - Knowledge retrieval failed (non-fatal)
#   3 - All model calls failed
#   4 - Timeout exceeded
#   5 - Budget exceeded
#   6 - Partial success (degraded mode)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_FILE="$PROJECT_ROOT/.loa.config.yaml"
TRAJECTORY_DIR="$PROJECT_ROOT/grimoires/loa/a2a/trajectory"

# Component scripts
MODEL_ADAPTER="$SCRIPT_DIR/model-adapter.sh"
SCORING_ENGINE="$SCRIPT_DIR/scoring-engine.sh"
KNOWLEDGE_LOCAL="$SCRIPT_DIR/flatline-knowledge-local.sh"

# Default configuration
DEFAULT_TIMEOUT=300
DEFAULT_BUDGET=300  # cents ($3.00)
DEFAULT_MODEL_TIMEOUT=60

# State tracking
STATE="INIT"
TOTAL_COST=0
TOTAL_TOKENS=0
START_TIME=""

# Temp directory for intermediate files
TEMP_DIR=""

# =============================================================================
# Logging
# =============================================================================

log() {
    echo "[flatline] $*" >&2
}

error() {
    echo "ERROR: $*" >&2
}

# Log to trajectory
log_trajectory() {
    local event_type="$1"
    local data="$2"

    mkdir -p "$TRAJECTORY_DIR"
    local date_str
    date_str=$(date +%Y-%m-%d)
    local log_file="$TRAJECTORY_DIR/flatline-$date_str.jsonl"

    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    jq -n \
        --arg type "flatline_protocol" \
        --arg event "$event_type" \
        --arg timestamp "$timestamp" \
        --arg state "$STATE" \
        --argjson data "$data" \
        '{type: $type, event: $event, timestamp: $timestamp, state: $state, data: $data}' >> "$log_file"
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

is_flatline_enabled() {
    local enabled
    enabled=$(read_config '.flatline_protocol.enabled' 'false')
    [[ "$enabled" == "true" ]]
}

get_model_primary() {
    read_config '.flatline_protocol.models.primary' 'opus'
}

get_model_secondary() {
    read_config '.flatline_protocol.models.secondary' 'gpt-5.2'
}

# =============================================================================
# Domain Extraction
# =============================================================================

extract_domain() {
    local doc="$1"
    local phase="$2"

    # Try to extract meaningful domain keywords from the document
    local domain=""

    case "$phase" in
        prd)
            # Look for product name and key technologies
            domain=$(grep -iE "^#|product|application|system|platform|service" "$doc" 2>/dev/null | \
                head -5 | \
                tr -cs '[:alnum:]' ' ' | \
                tr '[:upper:]' '[:lower:]' | \
                tr -s ' ' | \
                cut -d' ' -f1-5)
            ;;
        sdd)
            # Look for tech stack and architecture terms
            domain=$(grep -iE "technology|stack|framework|database|api|architecture" "$doc" 2>/dev/null | \
                head -5 | \
                tr -cs '[:alnum:]' ' ' | \
                tr '[:upper:]' '[:lower:]' | \
                tr -s ' ' | \
                cut -d' ' -f1-5)
            ;;
        sprint)
            # Look for task domains
            domain=$(grep -iE "^##|task|implement|create|build|feature" "$doc" 2>/dev/null | \
                head -5 | \
                tr -cs '[:alnum:]' ' ' | \
                tr '[:upper:]' '[:lower:]' | \
                tr -s ' ' | \
                cut -d' ' -f1-5)
            ;;
    esac

    # Default fallback
    if [[ -z "$domain" ]]; then
        domain="software development"
    fi

    echo "$domain"
}

# =============================================================================
# Budget Tracking
# =============================================================================

check_budget() {
    local additional_cost="$1"
    local budget="$2"

    local new_total=$((TOTAL_COST + additional_cost))
    if [[ $new_total -gt $budget ]]; then
        return 1
    fi
    return 0
}

add_cost() {
    local cost="$1"
    TOTAL_COST=$((TOTAL_COST + cost))
}

# =============================================================================
# State Machine
# =============================================================================

set_state() {
    local new_state="$1"
    log "State: $STATE -> $new_state"
    STATE="$new_state"
}

# =============================================================================
# Phase 1: Parallel Reviews
# =============================================================================

run_phase1() {
    local doc="$1"
    local phase="$2"
    local context_file="$3"
    local timeout="$4"
    local budget="$5"

    set_state "PHASE1"
    log "Starting Phase 1: Independent reviews (4 parallel calls)"

    local primary_model secondary_model
    primary_model=$(get_model_primary)
    secondary_model=$(get_model_secondary)

    # Create output files
    local gpt_review_file="$TEMP_DIR/gpt-review.json"
    local opus_review_file="$TEMP_DIR/opus-review.json"
    local gpt_skeptic_file="$TEMP_DIR/gpt-skeptic.json"
    local opus_skeptic_file="$TEMP_DIR/opus-skeptic.json"

    # Run 4 parallel API calls
    local pids=()

    # GPT review
    {
        "$MODEL_ADAPTER" --model "$secondary_model" --mode review \
            --input "$doc" --phase "$phase" --context "$context_file" \
            --timeout "$timeout" --json > "$gpt_review_file" 2>&1
    } &
    pids+=($!)

    # Opus review
    {
        "$MODEL_ADAPTER" --model "$primary_model" --mode review \
            --input "$doc" --phase "$phase" --context "$context_file" \
            --timeout "$timeout" --json > "$opus_review_file" 2>&1
    } &
    pids+=($!)

    # GPT skeptic
    {
        "$MODEL_ADAPTER" --model "$secondary_model" --mode skeptic \
            --input "$doc" --phase "$phase" --context "$context_file" \
            --timeout "$timeout" --json > "$gpt_skeptic_file" 2>&1
    } &
    pids+=($!)

    # Opus skeptic
    {
        "$MODEL_ADAPTER" --model "$primary_model" --mode skeptic \
            --input "$doc" --phase "$phase" --context "$context_file" \
            --timeout "$timeout" --json > "$opus_skeptic_file" 2>&1
    } &
    pids+=($!)

    # Wait for all processes
    local failed=0
    for pid in "${pids[@]}"; do
        if ! wait "$pid"; then
            ((failed++))
        fi
    done

    if [[ $failed -eq 4 ]]; then
        error "All Phase 1 model calls failed"
        return 3
    fi

    if [[ $failed -gt 0 ]]; then
        log "Warning: $failed of 4 Phase 1 calls failed (degraded mode)"
    fi

    # Aggregate costs
    for file in "$gpt_review_file" "$opus_review_file" "$gpt_skeptic_file" "$opus_skeptic_file"; do
        if [[ -f "$file" ]]; then
            local cost
            cost=$(jq -r '.cost_usd // 0' "$file" 2>/dev/null | awk '{printf "%.0f", $1 * 100}')
            add_cost "${cost:-0}"
        fi
    done

    log "Phase 1 complete. Total cost so far: $TOTAL_COST cents"

    # Output file paths for next phase
    echo "$gpt_review_file"
    echo "$opus_review_file"
    echo "$gpt_skeptic_file"
    echo "$opus_skeptic_file"
}

# =============================================================================
# Phase 2: Cross-Scoring
# =============================================================================

run_phase2() {
    local gpt_review_file="$1"
    local opus_review_file="$2"
    local phase="$3"
    local timeout="$4"

    set_state "PHASE2"
    log "Starting Phase 2: Cross-scoring (2 parallel calls)"

    local primary_model secondary_model
    primary_model=$(get_model_primary)
    secondary_model=$(get_model_secondary)

    # Extract items to score
    local gpt_items_file="$TEMP_DIR/gpt-items.json"
    local opus_items_file="$TEMP_DIR/opus-items.json"

    # Extract improvements from each review
    jq -r '.content' "$gpt_review_file" 2>/dev/null | jq '.' > "$gpt_items_file" 2>/dev/null || echo '{"improvements":[]}' > "$gpt_items_file"
    jq -r '.content' "$opus_review_file" 2>/dev/null | jq '.' > "$opus_items_file" 2>/dev/null || echo '{"improvements":[]}' > "$opus_items_file"

    # Create output files
    local gpt_scores_file="$TEMP_DIR/gpt-scores.json"
    local opus_scores_file="$TEMP_DIR/opus-scores.json"

    local pids=()

    # GPT scores Opus items
    {
        "$MODEL_ADAPTER" --model "$secondary_model" --mode score \
            --input "$opus_items_file" --phase "$phase" \
            --timeout "$timeout" --json > "$gpt_scores_file" 2>&1
    } &
    pids+=($!)

    # Opus scores GPT items
    {
        "$MODEL_ADAPTER" --model "$primary_model" --mode score \
            --input "$gpt_items_file" --phase "$phase" \
            --timeout "$timeout" --json > "$opus_scores_file" 2>&1
    } &
    pids+=($!)

    # Wait for all processes
    local failed=0
    for pid in "${pids[@]}"; do
        if ! wait "$pid"; then
            ((failed++))
        fi
    done

    if [[ $failed -eq 2 ]]; then
        log "Warning: All Phase 2 calls failed - using partial consensus"
    fi

    # Aggregate costs
    for file in "$gpt_scores_file" "$opus_scores_file"; do
        if [[ -f "$file" ]]; then
            local cost
            cost=$(jq -r '.cost_usd // 0' "$file" 2>/dev/null | awk '{printf "%.0f", $1 * 100}')
            add_cost "${cost:-0}"
        fi
    done

    log "Phase 2 complete. Total cost: $TOTAL_COST cents"

    echo "$gpt_scores_file"
    echo "$opus_scores_file"
}

# =============================================================================
# Phase 3: Consensus Calculation
# =============================================================================

run_consensus() {
    local gpt_scores_file="$1"
    local opus_scores_file="$2"
    local gpt_skeptic_file="$3"
    local opus_skeptic_file="$4"

    set_state "CONSENSUS"
    log "Calculating consensus"

    # Prepare scores files for scoring engine
    local gpt_scores_prepared="$TEMP_DIR/gpt-scores-prepared.json"
    local opus_scores_prepared="$TEMP_DIR/opus-scores-prepared.json"

    # Extract and format scores
    if [[ -f "$gpt_scores_file" ]]; then
        jq -r '.content' "$gpt_scores_file" 2>/dev/null | jq '.' > "$gpt_scores_prepared" 2>/dev/null || echo '{"scores":[]}' > "$gpt_scores_prepared"
    else
        echo '{"scores":[]}' > "$gpt_scores_prepared"
    fi

    if [[ -f "$opus_scores_file" ]]; then
        jq -r '.content' "$opus_scores_file" 2>/dev/null | jq '.' > "$opus_scores_prepared" 2>/dev/null || echo '{"scores":[]}' > "$opus_scores_prepared"
    else
        echo '{"scores":[]}' > "$opus_scores_prepared"
    fi

    # Prepare skeptic files
    local gpt_skeptic_prepared="$TEMP_DIR/gpt-skeptic-prepared.json"
    local opus_skeptic_prepared="$TEMP_DIR/opus-skeptic-prepared.json"

    if [[ -f "$gpt_skeptic_file" ]]; then
        jq -r '.content' "$gpt_skeptic_file" 2>/dev/null | jq '.' > "$gpt_skeptic_prepared" 2>/dev/null || echo '{"concerns":[]}' > "$gpt_skeptic_prepared"
    else
        echo '{"concerns":[]}' > "$gpt_skeptic_prepared"
    fi

    if [[ -f "$opus_skeptic_file" ]]; then
        jq -r '.content' "$opus_skeptic_file" 2>/dev/null | jq '.' > "$opus_skeptic_prepared" 2>/dev/null || echo '{"concerns":[]}' > "$opus_skeptic_prepared"
    else
        echo '{"concerns":[]}' > "$opus_skeptic_prepared"
    fi

    # Run scoring engine
    "$SCORING_ENGINE" \
        --gpt-scores "$gpt_scores_prepared" \
        --opus-scores "$opus_scores_prepared" \
        --include-blockers \
        --skeptic-gpt "$gpt_skeptic_prepared" \
        --skeptic-opus "$opus_skeptic_prepared" \
        --json
}

# =============================================================================
# Main
# =============================================================================

usage() {
    cat <<EOF
Usage: flatline-orchestrator.sh --doc <path> --phase <type> [options]

Required:
  --doc <path>           Document to review
  --phase <type>         Phase type: prd, sdd, sprint

Options:
  --domain <text>        Domain for knowledge retrieval (auto-extracted if not provided)
  --dry-run              Validate without executing reviews
  --skip-knowledge       Skip knowledge retrieval
  --skip-consensus       Return raw reviews without consensus
  --timeout <seconds>    Overall timeout (default: 300)
  --budget <cents>       Cost budget in cents (default: 300 = \$3.00)
  --json                 Output as JSON
  -h, --help             Show this help

State Machine:
  INIT -> KNOWLEDGE -> PHASE1 -> PHASE2 -> CONSENSUS -> DONE

Exit codes:
  0 - Success
  1 - Configuration error
  2 - Knowledge retrieval failed (non-fatal if local)
  3 - All model calls failed
  4 - Timeout exceeded
  5 - Budget exceeded
  6 - Partial success (degraded mode)

Example:
  flatline-orchestrator.sh --doc grimoires/loa/prd.md --phase prd --json
EOF
}

cleanup() {
    if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
    fi
}

main() {
    local doc=""
    local phase=""
    local domain=""
    local dry_run=false
    local skip_knowledge=false
    local skip_consensus=false
    local timeout="$DEFAULT_TIMEOUT"
    local budget="$DEFAULT_BUDGET"
    local json_output=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --doc)
                doc="$2"
                shift 2
                ;;
            --phase)
                phase="$2"
                shift 2
                ;;
            --domain)
                domain="$2"
                shift 2
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --skip-knowledge)
                skip_knowledge=true
                shift
                ;;
            --skip-consensus)
                skip_consensus=true
                shift
                ;;
            --timeout)
                timeout="$2"
                shift 2
                ;;
            --budget)
                budget="$2"
                shift 2
                ;;
            --json)
                json_output=true
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

    # Set up cleanup trap
    trap cleanup EXIT

    # Validate required arguments
    if [[ -z "$doc" ]]; then
        error "Document required (--doc)"
        exit 1
    fi

    if [[ ! -f "$doc" ]]; then
        error "Document not found: $doc"
        exit 1
    fi

    if [[ -z "$phase" ]]; then
        error "Phase required (--phase)"
        exit 1
    fi

    if [[ "$phase" != "prd" && "$phase" != "sdd" && "$phase" != "sprint" ]]; then
        error "Invalid phase: $phase (expected: prd, sdd, sprint)"
        exit 1
    fi

    # Check if Flatline is enabled (skip check in dry-run mode)
    if [[ "$dry_run" != "true" ]] && ! is_flatline_enabled; then
        log "Flatline Protocol is disabled in config"
        jq -n \
            --arg status "disabled" \
            --arg doc "$doc" \
            --arg phase "$phase" \
            '{status: $status, document: $doc, phase: $phase, reason: "flatline_protocol.enabled is false in .loa.config.yaml"}'
        exit 0
    fi

    # Create temp directory
    TEMP_DIR=$(mktemp -d)
    START_TIME=$(date +%s)

    log "Document: $doc"
    log "Phase: $phase"
    log "Timeout: ${timeout}s"
    log "Budget: ${budget} cents"

    # Dry run - validate only
    if [[ "$dry_run" == "true" ]]; then
        log "Dry run - validation passed"
        jq -n \
            --arg status "dry_run" \
            --arg doc "$doc" \
            --arg phase "$phase" \
            '{status: $status, document: $doc, phase: $phase}'
        exit 0
    fi

    # Extract domain if not provided
    if [[ -z "$domain" ]]; then
        domain=$(extract_domain "$doc" "$phase")
        log "Extracted domain: $domain"
    fi

    # Phase -0.5: Knowledge Retrieval
    local context_file="$TEMP_DIR/knowledge-context.md"
    if [[ "$skip_knowledge" != "true" ]]; then
        set_state "KNOWLEDGE"
        log "Retrieving knowledge context"

        if "$KNOWLEDGE_LOCAL" --domain "$domain" --phase "$phase" --format markdown > "$context_file" 2>/dev/null; then
            log "Knowledge retrieval complete"
        else
            log "Warning: Knowledge retrieval failed (continuing without context)"
            echo "" > "$context_file"
        fi
    else
        echo "" > "$context_file"
    fi

    # Phase 1: Independent Reviews
    local phase1_output
    phase1_output=$(run_phase1 "$doc" "$phase" "$context_file" "$DEFAULT_MODEL_TIMEOUT" "$budget")

    local gpt_review_file opus_review_file gpt_skeptic_file opus_skeptic_file
    gpt_review_file=$(echo "$phase1_output" | sed -n '1p')
    opus_review_file=$(echo "$phase1_output" | sed -n '2p')
    gpt_skeptic_file=$(echo "$phase1_output" | sed -n '3p')
    opus_skeptic_file=$(echo "$phase1_output" | sed -n '4p')

    # Check budget before Phase 2
    if ! check_budget 100 "$budget"; then
        log "Warning: Budget limit approaching, skipping Phase 2"
        skip_consensus=true
    fi

    # Phase 2: Cross-Scoring (unless skipped)
    local gpt_scores_file="" opus_scores_file=""
    if [[ "$skip_consensus" != "true" ]]; then
        local phase2_output
        phase2_output=$(run_phase2 "$gpt_review_file" "$opus_review_file" "$phase" "$DEFAULT_MODEL_TIMEOUT")

        gpt_scores_file=$(echo "$phase2_output" | sed -n '1p')
        opus_scores_file=$(echo "$phase2_output" | sed -n '2p')
    fi

    # Phase 3: Consensus Calculation
    local result
    if [[ "$skip_consensus" != "true" && -n "$gpt_scores_file" && -n "$opus_scores_file" ]]; then
        result=$(run_consensus "$gpt_scores_file" "$opus_scores_file" "$gpt_skeptic_file" "$opus_skeptic_file")
    else
        # Return raw reviews without consensus
        result=$(jq -n \
            --slurpfile gpt_review "$gpt_review_file" \
            --slurpfile opus_review "$opus_review_file" \
            '{
                consensus_summary: {
                    high_consensus_count: 0,
                    disputed_count: 0,
                    low_value_count: 0,
                    blocker_count: 0,
                    model_agreement_percent: 0
                },
                raw_reviews: {
                    gpt: $gpt_review[0],
                    opus: $opus_review[0]
                },
                note: "Consensus calculation skipped"
            }')
    fi

    set_state "DONE"

    # Calculate final metrics
    local end_time
    end_time=$(date +%s)
    local total_latency_ms=$(( (end_time - START_TIME) * 1000 ))

    # Add metadata to result
    local final_result
    final_result=$(echo "$result" | jq \
        --arg phase "$phase" \
        --arg doc "$doc" \
        --arg domain "$domain" \
        --argjson latency_ms "$total_latency_ms" \
        --argjson cost_cents "$TOTAL_COST" \
        --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '. + {
            phase: $phase,
            document: $doc,
            domain: $domain,
            timestamp: $timestamp,
            metrics: {
                total_latency_ms: $latency_ms,
                cost_cents: $cost_cents,
                cost_usd: ($cost_cents / 100)
            }
        }')

    # Log to trajectory
    log_trajectory "complete" "$final_result"

    # Output result
    echo "$final_result" | jq .

    log "Flatline Protocol complete. Cost: $TOTAL_COST cents, Latency: ${total_latency_ms}ms"
}

main "$@"
