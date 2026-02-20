#!/usr/bin/env bash
# =============================================================================
# flatline-orchestrator.sh - Main orchestrator for Flatline Protocol
# =============================================================================
# Version: 1.1.0
# Part of: Flatline Protocol v1.17.0, Autonomous Flatline v1.22.0
#
# Usage:
#   flatline-orchestrator.sh --doc <path> --phase <type> [options]
#
# Options:
#   --doc <path>           Document to review (required)
#   --phase <type>         Phase type: prd, sdd, sprint, beads (required)
#   --domain <text>        Domain for knowledge retrieval (auto-extracted if not provided)
#   --interactive          Force interactive mode (overrides auto-detection)
#   --autonomous           Force autonomous mode (overrides auto-detection)
#   --run-id <id>          Run ID for manifest tracking (autonomous mode)
#   --dry-run              Validate without executing reviews
#   --skip-knowledge       Skip knowledge retrieval
#   --skip-consensus       Return raw reviews without consensus
#   --timeout <seconds>    Overall timeout (default: 300)
#   --budget <cents>       Cost budget in cents (default: 300 = $3.00)
#   --json                 Output as JSON
#
# Mode Detection Precedence:
#   1. CLI flags (--interactive, --autonomous)
#   2. Environment variable (LOA_FLATLINE_MODE)
#   3. Config file (autonomous_mode.enabled)
#   4. Auto-detection (strong AI signals only)
#   5. Default (interactive)
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
source "$SCRIPT_DIR/bootstrap.sh"
source "$SCRIPT_DIR/lib/normalize-json.sh"
source "$SCRIPT_DIR/lib/invoke-diagnostics.sh"

# Note: bootstrap.sh already handles PROJECT_ROOT canonicalization via realpath
TRAJECTORY_DIR=$(get_trajectory_dir)

# Component scripts
MODEL_ADAPTER="$SCRIPT_DIR/model-adapter.sh"
MODEL_INVOKE="$SCRIPT_DIR/model-invoke"
SCORING_ENGINE="$SCRIPT_DIR/scoring-engine.sh"
KNOWLEDGE_LOCAL="$SCRIPT_DIR/flatline-knowledge-local.sh"
NOTEBOOKLM_QUERY="$PROJECT_ROOT/.claude/skills/flatline-knowledge/resources/notebooklm-query.py"

# Default configuration
DEFAULT_TIMEOUT=300
DEFAULT_BUDGET=300  # cents ($3.00)
DEFAULT_MODEL_TIMEOUT=120

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

# Strip markdown code blocks from JSON content (some models wrap JSON in ```json ... ```)
strip_markdown_json() {
    local content="$1"
    # Handle multi-line markdown blocks:
    # 1. Remove leading ```json or ``` (with optional newline)
    # 2. Remove trailing ``` (with optional preceding newline)
    echo "$content" | sed -E '
        # Remove opening code fence with language tag
        s/^```(json)?[[:space:]]*\n?//
        # Remove closing code fence
        s/\n?```[[:space:]]*$//
    '
}

# Extract and parse JSON content from model response
# Uses centralized normalize_json_response() from lib/normalize-json.sh
extract_json_content() {
    local file="$1"
    local default="$2"
    local agent="${3:-}"

    if [[ ! -f "$file" ]]; then
        echo "$default"
        return
    fi

    local content
    content=$(jq -r '.content // ""' "$file" 2>/dev/null)

    if [[ -z "$content" || "$content" == "null" ]]; then
        echo "$default"
        return
    fi

    # Normalize via centralized library (handles BOM, fences, prose wrapping)
    local normalized
    normalized=$(normalize_json_response "$content" 2>/dev/null) || {
        log "WARNING: JSON normalization failed for $file — using default"
        echo "$default"
        return
    }

    # Per-agent schema validation if agent specified
    if [[ -n "$agent" ]]; then
        if ! validate_agent_response "$normalized" "$agent" 2>/dev/null; then
            log "WARNING: Schema validation failed for agent '$agent' in $file"
        fi
    fi

    echo "$normalized"
}

# Log to trajectory
log_trajectory() {
    local event_type="$1"
    local data="$2"

    # Security: Create log directory with restrictive permissions
    (umask 077 && mkdir -p "$TRAJECTORY_DIR")
    local date_str
    date_str=$(date +%Y-%m-%d)
    local log_file="$TRAJECTORY_DIR/flatline-$date_str.jsonl"

    # Ensure log file has restrictive permissions
    touch "$log_file"
    chmod 600 "$log_file"

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

# FR-3: Optional tertiary model for 3-model Flatline (e.g., Gemini 3 Pro)
# Returns empty string when not configured (2-model mode preserved)
get_model_tertiary() {
    read_config '.hounfour.flatline_tertiary_model' ''
}

# Valid model names accepted by model-adapter.sh.legacy MODEL_PROVIDERS registry.
# Keep in sync with MODEL_PROVIDERS in model-adapter.sh.legacy (line ~69).
VALID_FLATLINE_MODELS=(opus gpt-5.2 gpt-5.2-codex gpt-5.3-codex claude-opus-4.6 claude-opus-4.5 gemini-2.0 gemini-2.5-flash gemini-2.5-pro gemini-3-flash gemini-3-pro)

validate_model() {
    local model="$1"
    local config_key="$2"  # e.g., "primary" or "secondary"

    if [[ -z "$model" ]]; then
        error "Flatline model '$config_key' is empty. Set flatline_protocol.models.$config_key in .loa.config.yaml"
        error "Valid models: ${VALID_FLATLINE_MODELS[*]}"
        return 1
    fi

    local valid=false
    for valid_model in "${VALID_FLATLINE_MODELS[@]}"; do
        if [[ "$model" == "$valid_model" ]]; then
            valid=true
            break
        fi
    done

    if [[ "$valid" != "true" ]]; then
        error "Unknown flatline model: '$model' (from flatline_protocol.models.$config_key in .loa.config.yaml)"
        error "Valid models: ${VALID_FLATLINE_MODELS[*]}"
        error "Note: '$model' may be an agent alias, not a model name. Check .claude/defaults/model-config.yaml for alias mappings."
        return 1
    fi

    return 0
}

is_notebooklm_enabled() {
    local enabled
    enabled=$(read_config '.flatline_protocol.knowledge.notebooklm.enabled' 'false')
    [[ "$enabled" == "true" ]]
}

get_notebooklm_notebook_id() {
    read_config '.flatline_protocol.knowledge.notebooklm.notebook_id' ''
}

get_notebooklm_timeout() {
    read_config '.flatline_protocol.knowledge.notebooklm.timeout_ms' '30000'
}

# =============================================================================
# Hounfour Routing (SDD §4.4.2)
# =============================================================================

# Feature flag: when true, call model-invoke directly instead of model-adapter.sh
is_flatline_routing_enabled() {
    if [[ "${HOUNFOUR_FLATLINE_ROUTING:-}" == "true" ]]; then
        return 0
    fi
    if [[ "${HOUNFOUR_FLATLINE_ROUTING:-}" == "false" ]]; then
        return 1
    fi
    local value
    value=$(read_config '.hounfour.flatline_routing' 'false')
    [[ "$value" == "true" ]]
}

# Mode → Agent mapping for model-invoke routing
declare -A MODE_TO_AGENT=(
    ["review"]="flatline-reviewer"
    ["skeptic"]="flatline-skeptic"
    ["score"]="flatline-scorer"
    ["dissent"]="flatline-dissenter"
)

# Legacy model name → provider:model-id for model-invoke --model override
declare -A MODEL_TO_PROVIDER_ID=(
    ["gpt-5.2"]="openai:gpt-5.2"
    ["gpt-5.2-codex"]="openai:gpt-5.2-codex"
    ["opus"]="anthropic:claude-opus-4-6"
    ["claude-opus-4.6"]="anthropic:claude-opus-4-6"
    ["gemini-2.0"]="google:gemini-2.0-flash"
    ["gemini-2.5-flash"]="google:gemini-2.5-flash"
    ["gemini-2.5-pro"]="google:gemini-2.5-pro"
    ["gemini-3-flash"]="google:gemini-3-flash"
    ["gemini-3-pro"]="google:gemini-3-pro"
)

# Unified model call: routes through model-invoke (direct) or model-adapter.sh (legacy)
# Usage: call_model <model> <mode> <input> <phase> [context] [timeout]
call_model() {
    local model="$1"
    local mode="$2"
    local input="$3"
    local phase="$4"
    local context="${5:-}"
    local timeout="${6:-$DEFAULT_MODEL_TIMEOUT}"

    if is_flatline_routing_enabled && [[ -x "$MODEL_INVOKE" ]]; then
        # Direct model-invoke path (SDD §4.4.2)
        local agent="${MODE_TO_AGENT[$mode]:-}"
        local model_override="${MODEL_TO_PROVIDER_ID[$model]:-$model}"

        if [[ -z "$agent" ]]; then
            log "ERROR: Unknown mode for model-invoke: $mode"
            return 2
        fi

        local -a args=(
            --agent "$agent"
            --input "$input"
            --model "$model_override"
            --output-format json
            --json-errors
            --timeout "$timeout"
        )

        if [[ -n "$context" && -f "$context" ]]; then
            args+=(--system "$context")
        fi

        # Per-invocation diagnostic log (unique suffix for parallel calls)
        local invoke_log
        invoke_log=$(setup_invoke_log "flatline-${mode}-${model}")

        local result exit_code=0
        # Synchronous stderr capture — avoids process substitution race condition
        # where >(redact_secrets) may not finish writing before log is read
        result=$("$MODEL_INVOKE" "${args[@]}" 2>"${invoke_log}.raw") || exit_code=$?
        if [[ -s "${invoke_log}.raw" ]]; then
            redact_secrets < "${invoke_log}.raw" >> "$invoke_log"
        fi
        rm -f "${invoke_log}.raw"

        if [[ $exit_code -ne 0 ]]; then
            log_invoke_failure "$exit_code" "$invoke_log" "$timeout"
            return $exit_code
        fi

        # Clean up on success
        cleanup_invoke_log "$invoke_log"

        # Translate output to legacy format for downstream compatibility
        echo "$result" | jq \
            --arg model "$model" \
            --arg mode "$mode" \
            --arg phase "$phase" \
            '{
                content: .content,
                tokens_input: (.usage.input_tokens // 0),
                tokens_output: (.usage.output_tokens // 0),
                latency_ms: (.latency_ms // 0),
                retries: 0,
                model: $model,
                mode: $mode,
                phase: $phase,
                cost_usd: 0
            }'
    else
        # Legacy path: model-adapter.sh (or shim)
        "$MODEL_ADAPTER" --model "$model" --mode "$mode" \
            --input "$input" --phase "$phase" \
            ${context:+--context "$context"} \
            --timeout "$timeout" --json
    fi
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
        beads)
            # Look for task graph keywords from JSON
            domain=$(jq -r '[.[]? | .title // .description // empty] | join(" ")' "$doc" 2>/dev/null | \
                tr -cs '[:alnum:]' ' ' | \
                tr '[:upper:]' '[:lower:]' | \
                tr -s ' ' | \
                cut -d' ' -f1-5 || echo "task graph")
            ;;
    esac

    # Default fallback
    if [[ -z "$domain" ]]; then
        domain="software development"
    fi

    echo "$domain"
}

# =============================================================================
# NotebookLM Integration (Tier 2 Knowledge)
# =============================================================================

query_notebooklm() {
    local domain="$1"
    local phase="$2"
    local output_file="$3"

    # Check if NotebookLM is enabled
    if ! is_notebooklm_enabled; then
        log "NotebookLM: disabled (skipping)"
        return 0
    fi

    # Check if Python script exists
    if [[ ! -f "$NOTEBOOKLM_QUERY" ]]; then
        log "NotebookLM: query script not found (skipping)"
        return 0
    fi

    # Check if Python is available
    if ! command -v python3 &> /dev/null; then
        log "NotebookLM: Python3 not available (skipping)"
        return 0
    fi

    local notebook_id
    notebook_id=$(get_notebooklm_notebook_id)

    local timeout_ms
    timeout_ms=$(get_notebooklm_timeout)

    log "NotebookLM: querying for domain '$domain' phase '$phase'"

    local nlm_result
    local nlm_args=(
        --domain "$domain"
        --phase "$phase"
        --timeout "$timeout_ms"
        --json
    )

    if [[ -n "$notebook_id" ]]; then
        nlm_args+=(--notebook "$notebook_id")
    fi

    # Run NotebookLM query (with timeout protection)
    local timeout_sec=$((timeout_ms / 1000 + 5))  # Add 5s buffer
    if nlm_result=$(timeout "${timeout_sec}s" python3 "$NOTEBOOKLM_QUERY" "${nlm_args[@]}" 2>/dev/null); then
        local status
        status=$(echo "$nlm_result" | jq -r '.status // "error"')

        case "$status" in
            success)
                log "NotebookLM: query successful"
                # Extract content and append to output
                local content
                content=$(echo "$nlm_result" | jq -r '.results[0].content // ""')
                if [[ -n "$content" && "$content" != "null" ]]; then
                    echo "" >> "$output_file"
                    echo "## NotebookLM Knowledge (Tier 2)" >> "$output_file"
                    echo "" >> "$output_file"
                    echo "$content" >> "$output_file"
                    echo "" >> "$output_file"
                    echo "_Source: NotebookLM (weight: 0.8)_" >> "$output_file"

                    local latency
                    latency=$(echo "$nlm_result" | jq -r '.latency_ms // 0')
                    log "NotebookLM: retrieved in ${latency}ms"
                fi
                return 0
                ;;
            auth_expired)
                log "Warning: NotebookLM authentication expired (skipping)"
                log "  Run: python3 $NOTEBOOKLM_QUERY --setup-auth"
                return 0
                ;;
            dry_run)
                log "NotebookLM: dry run mode"
                return 0
                ;;
            timeout)
                log "Warning: NotebookLM query timed out (skipping)"
                return 0
                ;;
            *)
                local error_msg
                error_msg=$(echo "$nlm_result" | jq -r '.error // "Unknown error"')
                log "Warning: NotebookLM query failed: $error_msg (skipping)"
                return 0
                ;;
        esac
    else
        log "Warning: NotebookLM query timed out or failed (skipping)"
        return 0
    fi
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

# =============================================================================
# Inquiry Mode (FR-4): Collaborative Multi-Model Architectural Inquiry
# =============================================================================
# Runs 3 parallel collaborative queries with distinct prompts:
#   1. Structural — isomorphisms, patterns, design parallels
#   2. Historical — precedents, evolution, prior art
#   3. Governance — constraints, policies, Ostrom-like rules
# Results are synthesized into a unified JSON output.

run_inquiry() {
    local doc="$1"
    local phase="$2"
    local context_file="$3"
    local timeout="$4"
    local budget="${5:-500}"

    set_state "PHASE1"
    log "Starting Inquiry Mode: 3 parallel collaborative queries"

    local primary_model secondary_model tertiary_model
    primary_model=$(get_model_primary)
    secondary_model=$(get_model_secondary)
    tertiary_model=$(get_model_tertiary)

    # Assign models to perspectives (rotating for diversity)
    local structural_model="$primary_model"
    local historical_model="$secondary_model"
    local governance_model="${tertiary_model:-$primary_model}"

    # Read document content
    local doc_content
    doc_content=$(cat "$doc" 2>/dev/null | head -2000) || doc_content=""

    # Read context if available
    local extra_context=""
    if [[ -n "$context_file" && -f "$context_file" && -s "$context_file" ]]; then
        extra_context=$(cat "$context_file" 2>/dev/null | head -500) || extra_context=""
    fi

    # Build inquiry prompts
    local structural_prompt="You are conducting a structural architectural inquiry.

Analyze the following document for structural patterns, isomorphisms, and design parallels.
Look for:
- Recurring structural patterns across components
- Isomorphisms between seemingly different subsystems
- Design patterns that could be generalized or extracted
- Architectural symmetries and asymmetries

Document (${phase}):
${doc_content}

${extra_context:+Additional context:
${extra_context}
}
Output your findings as JSON with this schema:
{\"perspective\": \"structural\", \"findings\": [{\"pattern\": \"...\", \"description\": \"...\", \"confidence\": 0.0-1.0, \"connections\": [\"...\"]}]}"

    local historical_prompt="You are conducting a historical architectural inquiry.

Analyze the following document for historical precedents, evolutionary patterns, and prior art.
Look for:
- Historical software engineering precedents for the patterns used
- How the architecture has evolved or could evolve
- FAANG-scale parallels from industry practice
- Anti-patterns that history has shown to fail

Document (${phase}):
${doc_content}

${extra_context:+Additional context:
${extra_context}
}
Output your findings as JSON with this schema:
{\"perspective\": \"historical\", \"findings\": [{\"pattern\": \"...\", \"precedent\": \"...\", \"confidence\": 0.0-1.0, \"lesson\": \"...\"}]}"

    local governance_prompt="You are conducting a governance architectural inquiry.

Analyze the following document for governance structures, constraint patterns, and policy design.
Look for:
- Ostrom-like governance principles in the architecture
- Constraint enforcement mechanisms and their completeness
- Trust boundaries and their implications
- Policy patterns that could be formalized or improved

Document (${phase}):
${doc_content}

${extra_context:+Additional context:
${extra_context}
}
Output your findings as JSON with this schema:
{\"perspective\": \"governance\", \"findings\": [{\"pattern\": \"...\", \"description\": \"...\", \"confidence\": 0.0-1.0, \"principle\": \"...\"}]}"

    # Write prompts to temp files for model invocation
    local structural_input="$TEMP_DIR/inquiry-structural.txt"
    local historical_input="$TEMP_DIR/inquiry-historical.txt"
    local governance_input="$TEMP_DIR/inquiry-governance.txt"
    echo "$structural_prompt" > "$structural_input"
    echo "$historical_prompt" > "$historical_input"
    echo "$governance_prompt" > "$governance_input"

    # Output files
    local structural_output="$TEMP_DIR/inquiry-structural-result.json"
    local historical_output="$TEMP_DIR/inquiry-historical-result.json"
    local governance_output="$TEMP_DIR/inquiry-governance-result.json"

    # Launch 3 parallel queries
    local pids=() labels=()

    call_model "$structural_model" "review" "$structural_input" "$phase" "$context_file" "$timeout" > "$structural_output" 2>/dev/null &
    pids+=($!); labels+=("structural($structural_model)")

    call_model "$historical_model" "review" "$historical_input" "$phase" "$context_file" "$timeout" > "$historical_output" 2>/dev/null &
    pids+=($!); labels+=("historical($historical_model)")

    call_model "$governance_model" "review" "$governance_input" "$phase" "$context_file" "$timeout" > "$governance_output" 2>/dev/null &
    pids+=($!); labels+=("governance($governance_model)")

    # Wait for all queries
    local failures=0
    for i in "${!pids[@]}"; do
        if ! wait "${pids[$i]}" 2>/dev/null; then
            log "WARNING: Inquiry query failed: ${labels[$i]}"
            failures=$((failures + 1))
        else
            log "Inquiry query complete: ${labels[$i]}"
        fi
    done

    # Require at least 2 successful queries
    local success_count=$(( ${#pids[@]} - failures ))
    if [[ $success_count -lt 2 ]]; then
        log "ERROR: Only $success_count of 3 inquiry queries succeeded (minimum 2 required)"
        jq -n '{error: "insufficient_queries", success_count: '"$success_count"', required: 2}'
        return 1
    fi

    # Aggregate costs
    for f in "$structural_output" "$historical_output" "$governance_output"; do
        if [[ -f "$f" && -s "$f" ]]; then
            local cost
            cost=$(jq '.cost_usd // 0' "$f" 2>/dev/null) || cost=0
            TOTAL_COST=$(echo "$TOTAL_COST + ($cost * 100)" | bc 2>/dev/null || echo "$TOTAL_COST")
        fi
    done

    set_state "CONSENSUS"

    # Synthesize results
    local structural_content="" historical_content="" governance_content=""
    if [[ -f "$structural_output" && -s "$structural_output" ]]; then
        structural_content=$(jq -r '.content // ""' "$structural_output" 2>/dev/null) || structural_content=""
    fi
    if [[ -f "$historical_output" && -s "$historical_output" ]]; then
        historical_content=$(jq -r '.content // ""' "$historical_output" 2>/dev/null) || historical_content=""
    fi
    if [[ -f "$governance_output" && -s "$governance_output" ]]; then
        governance_content=$(jq -r '.content // ""' "$governance_output" 2>/dev/null) || governance_content=""
    fi

    # Try to parse JSON from each response content
    local structural_json historical_json governance_json
    structural_json=$(echo "$structural_content" | jq '.' 2>/dev/null) || structural_json='{"perspective":"structural","findings":[],"raw":true}'
    historical_json=$(echo "$historical_content" | jq '.' 2>/dev/null) || historical_json='{"perspective":"historical","findings":[],"raw":true}'
    governance_json=$(echo "$governance_content" | jq '.' 2>/dev/null) || governance_json='{"perspective":"governance","findings":[],"raw":true}'

    # Build unified synthesis
    jq -n \
        --argjson structural "$structural_json" \
        --argjson historical "$historical_json" \
        --argjson governance "$governance_json" \
        --argjson queries_launched "${#pids[@]}" \
        --argjson queries_succeeded "$success_count" \
        --arg structural_model "$structural_model" \
        --arg historical_model "$historical_model" \
        --arg governance_model "$governance_model" \
        '{
            mode: "inquiry",
            perspectives: {
                structural: $structural,
                historical: $historical,
                governance: $governance
            },
            models: {
                structural: $structural_model,
                historical: $historical_model,
                governance: $governance_model
            },
            summary: {
                queries_launched: $queries_launched,
                queries_succeeded: $queries_succeeded,
                structural_findings: (($structural.findings // []) | length),
                historical_findings: (($historical.findings // []) | length),
                governance_findings: (($governance.findings // []) | length),
                total_findings: ((($structural.findings // []) | length) + (($historical.findings // []) | length) + (($governance.findings // []) | length))
            }
        }'
}

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

    # Validate model names before making any API calls
    if ! validate_model "$primary_model" "primary"; then
        return 3
    fi
    if ! validate_model "$secondary_model" "secondary"; then
        return 3
    fi

    # FR-3: Optional tertiary model for 3-model Flatline
    local tertiary_model
    tertiary_model=$(get_model_tertiary)
    local has_tertiary=false
    if [[ -n "$tertiary_model" ]]; then
        if ! validate_model "$tertiary_model" "tertiary"; then
            log "Warning: tertiary model '$tertiary_model' invalid, continuing with 2-model mode"
            tertiary_model=""
        else
            has_tertiary=true
        fi
    fi

    local total_calls=4
    [[ "$has_tertiary" == "true" ]] && total_calls=6

    # Create output files
    local gpt_review_file="$TEMP_DIR/gpt-review.json"
    local opus_review_file="$TEMP_DIR/opus-review.json"
    local gpt_skeptic_file="$TEMP_DIR/gpt-skeptic.json"
    local opus_skeptic_file="$TEMP_DIR/opus-skeptic.json"
    local tertiary_review_file="$TEMP_DIR/tertiary-review.json"
    local tertiary_skeptic_file="$TEMP_DIR/tertiary-skeptic.json"

    # Stderr capture files for diagnosis on failure
    local gpt_review_stderr="$TEMP_DIR/gpt-review-stderr.log"
    local opus_review_stderr="$TEMP_DIR/opus-review-stderr.log"
    local gpt_skeptic_stderr="$TEMP_DIR/gpt-skeptic-stderr.log"
    local opus_skeptic_stderr="$TEMP_DIR/opus-skeptic-stderr.log"
    local tertiary_review_stderr="$TEMP_DIR/tertiary-review-stderr.log"
    local tertiary_skeptic_stderr="$TEMP_DIR/tertiary-skeptic-stderr.log"

    # Run parallel API calls with stagger to avoid same-provider rate-limit contention.
    # Review calls launch first, then skeptic calls after a 2s delay.
    local pids=()
    local pid_labels=()

    # Wave 1: Review calls (all models concurrently)
    {
        call_model "$secondary_model" review "$doc" "$phase" "$context_file" "$timeout" \
            > "$gpt_review_file" 2>"$gpt_review_stderr"
    } &
    pids+=($!)
    pid_labels+=("gpt-review")

    {
        call_model "$primary_model" review "$doc" "$phase" "$context_file" "$timeout" \
            > "$opus_review_file" 2>"$opus_review_stderr"
    } &
    pids+=($!)
    pid_labels+=("opus-review")

    if [[ "$has_tertiary" == "true" ]]; then
        {
            call_model "$tertiary_model" review "$doc" "$phase" "$context_file" "$timeout" \
                > "$tertiary_review_file" 2>"$tertiary_review_stderr"
        } &
        pids+=($!)
        pid_labels+=("tertiary-review")
    fi

    # Stagger: 2s delay before skeptic calls to avoid rate-limit contention
    sleep 2

    # Wave 2: Skeptic calls (all models concurrently)
    {
        call_model "$secondary_model" skeptic "$doc" "$phase" "$context_file" "$timeout" \
            > "$gpt_skeptic_file" 2>"$gpt_skeptic_stderr"
    } &
    pids+=($!)
    pid_labels+=("gpt-skeptic")

    {
        call_model "$primary_model" skeptic "$doc" "$phase" "$context_file" "$timeout" \
            > "$opus_skeptic_file" 2>"$opus_skeptic_stderr"
    } &
    pids+=($!)
    pid_labels+=("opus-skeptic")

    if [[ "$has_tertiary" == "true" ]]; then
        {
            call_model "$tertiary_model" skeptic "$doc" "$phase" "$context_file" "$timeout" \
                > "$tertiary_skeptic_file" 2>"$tertiary_skeptic_stderr"
        } &
        pids+=($!)
        pid_labels+=("tertiary-skeptic")
    fi

    # Wait for all processes and track failures
    local failed=0
    local failed_labels=()
    for i in "${!pids[@]}"; do
        if ! wait "${pids[$i]}"; then
            ((failed++))
            failed_labels+=("${pid_labels[$i]}")
        fi
    done

    if [[ $failed -eq $total_calls ]]; then
        error "All Phase 1 model calls failed"
        # Log stderr from all failed calls for diagnosis
        for label in "${failed_labels[@]}"; do
            local stderr_file="$TEMP_DIR/${label}-stderr.log"
            if [[ -s "$stderr_file" ]]; then
                log "  $label stderr: $(head -5 "$stderr_file")"
            fi
        done
        return 3
    fi

    if [[ $failed -gt 0 ]]; then
        log "Warning: $failed of $total_calls Phase 1 calls failed (degraded mode)"
        # Log stderr from failed calls for diagnosis
        for label in "${failed_labels[@]}"; do
            local stderr_file="$TEMP_DIR/${label}-stderr.log"
            if [[ -s "$stderr_file" ]]; then
                log "  $label stderr: $(head -5 "$stderr_file")"
            fi
        done
    fi

    # Aggregate costs
    local cost_files=("$gpt_review_file" "$opus_review_file" "$gpt_skeptic_file" "$opus_skeptic_file")
    [[ "$has_tertiary" == "true" ]] && cost_files+=("$tertiary_review_file" "$tertiary_skeptic_file")
    for file in "${cost_files[@]}"; do
        if [[ -f "$file" ]]; then
            local cost
            cost=$(jq -r '.cost_usd // 0' "$file" 2>/dev/null | awk '{printf "%.0f", $1 * 100}')
            add_cost "${cost:-0}"
        fi
    done

    log "Phase 1 complete ($total_calls calls). Total cost so far: $TOTAL_COST cents"

    # Output file paths for next phase
    echo "$gpt_review_file"
    echo "$opus_review_file"
    echo "$gpt_skeptic_file"
    echo "$opus_skeptic_file"
    # FR-3: Output tertiary file paths only when configured (avoids empty paths)
    if [[ "$has_tertiary" == "true" ]]; then
        echo "$tertiary_review_file"
        echo "$tertiary_skeptic_file"
    fi
}

# =============================================================================
# Phase 2: Cross-Scoring
# =============================================================================

run_phase2() {
    local gpt_review_file="$1"
    local opus_review_file="$2"
    local phase="$3"
    local timeout="$4"
    local tertiary_review_file="${5:-}"

    set_state "PHASE2"

    local primary_model secondary_model tertiary_model
    primary_model=$(get_model_primary)
    secondary_model=$(get_model_secondary)
    tertiary_model=$(get_model_tertiary)

    local has_tertiary=false
    [[ -n "$tertiary_model" && -n "$tertiary_review_file" && -s "$tertiary_review_file" ]] && has_tertiary=true

    local total_calls=2
    [[ "$has_tertiary" == "true" ]] && total_calls=6

    log "Starting Phase 2: Cross-scoring ($total_calls parallel calls)"

    # Extract items to score
    local gpt_items_file="$TEMP_DIR/gpt-items.json"
    local opus_items_file="$TEMP_DIR/opus-items.json"
    local tertiary_items_file="$TEMP_DIR/tertiary-items.json"

    # Extract improvements from each review (handles markdown-wrapped JSON)
    extract_json_content "$gpt_review_file" '{"improvements":[]}' > "$gpt_items_file"
    extract_json_content "$opus_review_file" '{"improvements":[]}' > "$opus_items_file"
    if [[ "$has_tertiary" == "true" ]]; then
        extract_json_content "$tertiary_review_file" '{"improvements":[]}' > "$tertiary_items_file"
    fi

    # Create output files
    local gpt_scores_file="$TEMP_DIR/gpt-scores.json"
    local opus_scores_file="$TEMP_DIR/opus-scores.json"
    local tertiary_scores_opus_file="$TEMP_DIR/tertiary-scores-opus.json"
    local tertiary_scores_gpt_file="$TEMP_DIR/tertiary-scores-gpt.json"
    local gpt_scores_tertiary_file="$TEMP_DIR/gpt-scores-tertiary.json"
    local opus_scores_tertiary_file="$TEMP_DIR/opus-scores-tertiary.json"

    local pids=()

    # GPT scores Opus items
    {
        call_model "$secondary_model" score "$opus_items_file" "$phase" "" "$timeout" \
            > "$gpt_scores_file" 2>/dev/null
    } &
    pids+=($!)

    # Opus scores GPT items
    {
        call_model "$primary_model" score "$gpt_items_file" "$phase" "" "$timeout" \
            > "$opus_scores_file" 2>/dev/null
    } &
    pids+=($!)

    # FR-3: 3-way triangular cross-scoring when tertiary configured
    if [[ "$has_tertiary" == "true" ]]; then
        # Tertiary scores Opus items
        {
            call_model "$tertiary_model" score "$opus_items_file" "$phase" "" "$timeout" \
                > "$tertiary_scores_opus_file" 2>/dev/null
        } &
        pids+=($!)

        # Tertiary scores GPT items
        {
            call_model "$tertiary_model" score "$gpt_items_file" "$phase" "" "$timeout" \
                > "$tertiary_scores_gpt_file" 2>/dev/null
        } &
        pids+=($!)

        # GPT scores Tertiary items
        {
            call_model "$secondary_model" score "$tertiary_items_file" "$phase" "" "$timeout" \
                > "$gpt_scores_tertiary_file" 2>/dev/null
        } &
        pids+=($!)

        # Opus scores Tertiary items
        {
            call_model "$primary_model" score "$tertiary_items_file" "$phase" "" "$timeout" \
                > "$opus_scores_tertiary_file" 2>/dev/null
        } &
        pids+=($!)
    fi

    # Wait for all processes
    local failed=0
    for pid in "${pids[@]}"; do
        if ! wait "$pid"; then
            ((failed++))
        fi
    done

    if [[ $failed -eq $total_calls ]]; then
        log "Warning: All Phase 2 calls failed - using partial consensus"
    fi

    # Aggregate costs
    local cost_files=("$gpt_scores_file" "$opus_scores_file")
    if [[ "$has_tertiary" == "true" ]]; then
        cost_files+=("$tertiary_scores_opus_file" "$tertiary_scores_gpt_file"
                     "$gpt_scores_tertiary_file" "$opus_scores_tertiary_file")
    fi
    for file in "${cost_files[@]}"; do
        if [[ -f "$file" ]]; then
            local cost
            cost=$(jq -r '.cost_usd // 0' "$file" 2>/dev/null | awk '{printf "%.0f", $1 * 100}')
            add_cost "${cost:-0}"
        fi
    done

    log "Phase 2 complete ($total_calls calls). Total cost: $TOTAL_COST cents"

    echo "$gpt_scores_file"
    echo "$opus_scores_file"
    # FR-3: Output tertiary scoring files when configured (consumed by consensus)
    if [[ "$has_tertiary" == "true" ]]; then
        echo "$tertiary_scores_opus_file"
        echo "$tertiary_scores_gpt_file"
        echo "$gpt_scores_tertiary_file"
        echo "$opus_scores_tertiary_file"
    fi
}

# =============================================================================
# Phase 3: Consensus Calculation
# =============================================================================

run_consensus() {
    local gpt_scores_file="$1"
    local opus_scores_file="$2"
    local gpt_skeptic_file="$3"
    local opus_skeptic_file="$4"
    # FR-3: Optional tertiary scoring files for 3-model consensus
    local tertiary_scores_opus="${5:-}"
    local tertiary_scores_gpt="${6:-}"
    local gpt_scores_tertiary="${7:-}"
    local opus_scores_tertiary="${8:-}"
    local tertiary_skeptic_file="${9:-}"

    set_state "CONSENSUS"
    log "Calculating consensus"

    # Prepare scores files for scoring engine (handles markdown-wrapped JSON)
    local gpt_scores_prepared="$TEMP_DIR/gpt-scores-prepared.json"
    local opus_scores_prepared="$TEMP_DIR/opus-scores-prepared.json"

    # Extract and format scores using extract_json_content (handles markdown wrapping)
    extract_json_content "$gpt_scores_file" '{"scores":[]}' > "$gpt_scores_prepared"
    extract_json_content "$opus_scores_file" '{"scores":[]}' > "$opus_scores_prepared"

    # Prepare skeptic files (handles markdown-wrapped JSON)
    local gpt_skeptic_prepared="$TEMP_DIR/gpt-skeptic-prepared.json"
    local opus_skeptic_prepared="$TEMP_DIR/opus-skeptic-prepared.json"

    extract_json_content "$gpt_skeptic_file" '{"concerns":[]}' > "$gpt_skeptic_prepared"
    extract_json_content "$opus_skeptic_file" '{"concerns":[]}' > "$opus_skeptic_prepared"

    # FR-3: Prepare tertiary scoring and skeptic files when available
    local tertiary_args=()
    if [[ -n "$tertiary_scores_opus" && -s "$tertiary_scores_opus" ]]; then
        local tertiary_scores_opus_prepared="$TEMP_DIR/tertiary-scores-opus-prepared.json"
        local tertiary_scores_gpt_prepared="$TEMP_DIR/tertiary-scores-gpt-prepared.json"
        local gpt_scores_tertiary_prepared="$TEMP_DIR/gpt-scores-tertiary-prepared.json"
        local opus_scores_tertiary_prepared="$TEMP_DIR/opus-scores-tertiary-prepared.json"

        extract_json_content "$tertiary_scores_opus" '{"scores":[]}' > "$tertiary_scores_opus_prepared"
        extract_json_content "$tertiary_scores_gpt" '{"scores":[]}' > "$tertiary_scores_gpt_prepared"
        extract_json_content "$gpt_scores_tertiary" '{"scores":[]}' > "$gpt_scores_tertiary_prepared"
        extract_json_content "$opus_scores_tertiary" '{"scores":[]}' > "$opus_scores_tertiary_prepared"

        tertiary_args=(
            --tertiary-scores-opus "$tertiary_scores_opus_prepared"
            --tertiary-scores-gpt "$tertiary_scores_gpt_prepared"
            --gpt-scores-tertiary "$gpt_scores_tertiary_prepared"
            --opus-scores-tertiary "$opus_scores_tertiary_prepared"
        )
        log "Including tertiary model scores in consensus (3-model mode)"
    fi

    # FR-3: Prepare tertiary skeptic file when available
    local tertiary_skeptic_args=()
    if [[ -n "$tertiary_skeptic_file" && -s "$tertiary_skeptic_file" ]]; then
        local tertiary_skeptic_prepared="$TEMP_DIR/tertiary-skeptic-prepared.json"
        extract_json_content "$tertiary_skeptic_file" '{"concerns":[]}' > "$tertiary_skeptic_prepared"
        tertiary_skeptic_args=(--skeptic-tertiary "$tertiary_skeptic_prepared")
        log "Including tertiary model skeptic concerns in consensus"
    fi

    # Run scoring engine
    "$SCORING_ENGINE" \
        --gpt-scores "$gpt_scores_prepared" \
        --opus-scores "$opus_scores_prepared" \
        --include-blockers \
        --skeptic-gpt "$gpt_skeptic_prepared" \
        --skeptic-opus "$opus_skeptic_prepared" \
        "${tertiary_args[@]}" \
        "${tertiary_skeptic_args[@]}" \
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
  --phase <type>         Phase type: prd, sdd, sprint, beads

Options:
  --mode <type>          Mode: review (default), red-team
  --domain <text>        Domain for knowledge retrieval (auto-extracted if not provided)
  --dry-run              Validate without executing reviews
  --skip-knowledge       Skip knowledge retrieval
  --skip-consensus       Return raw reviews without consensus
  --timeout <seconds>    Overall timeout (default: 300)
  --budget <cents>       Cost budget in cents (default: 300 = \$3.00)
  --json                 Output as JSON
  -h, --help             Show this help

Red Team Options (--mode red-team):
  --focus <categories>   Comma-separated attack surface categories
  --surface <name>       Target specific surface from registry
  --depth <N>            Attack-counter_design iterations (default: 1)
  --execution-mode <m>   Cost tier: quick, standard (default), deep

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
  flatline-orchestrator.sh --doc grimoires/loa/sdd.md --phase sdd --mode red-team --json
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
    local mode_flag=""
    local run_id=""
    local orchestrator_mode="review"
    local rt_focus=""
    local rt_surface=""
    local rt_depth=1
    local rt_execution_mode="standard"

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
            --mode)
                orchestrator_mode="$2"
                shift 2
                ;;
            --focus)
                rt_focus="$2"
                shift 2
                ;;
            --surface)
                rt_surface="$2"
                shift 2
                ;;
            --depth)
                rt_depth="$2"
                shift 2
                ;;
            --execution-mode)
                rt_execution_mode="$2"
                shift 2
                ;;
            --interactive)
                mode_flag="--interactive"
                shift
                ;;
            --autonomous)
                mode_flag="--autonomous"
                shift
                ;;
            --run-id)
                run_id="$2"
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

    # Security: Validate document path is within project directory (prevent path traversal)
    local realpath_doc
    realpath_doc=$(realpath "$doc" 2>/dev/null) || {
        error "Cannot resolve document path: $doc"
        exit 1
    }
    if [[ ! "$realpath_doc" == "$PROJECT_ROOT"* ]]; then
        error "Document must be within project directory: $doc"
        error "Resolved to: $realpath_doc (outside $PROJECT_ROOT)"
        exit 1
    fi

    if [[ -z "$phase" ]]; then
        error "Phase required (--phase)"
        exit 1
    fi

    if [[ "$phase" != "prd" && "$phase" != "sdd" && "$phase" != "sprint" && "$phase" != "beads" && "$phase" != "spec" ]]; then
        error "Invalid phase: $phase (expected: prd, sdd, sprint, beads, spec)"
        exit 1
    fi

    # Validate orchestrator mode
    if [[ "$orchestrator_mode" != "review" && "$orchestrator_mode" != "red-team" && "$orchestrator_mode" != "inquiry" ]]; then
        error "Invalid mode: $orchestrator_mode (expected: review, red-team, inquiry)"
        exit 1
    fi

    # Validate red-team execution mode
    if [[ "$orchestrator_mode" == "red-team" ]]; then
        if [[ "$rt_execution_mode" != "quick" && "$rt_execution_mode" != "standard" && "$rt_execution_mode" != "deep" ]]; then
            error "Invalid execution mode: $rt_execution_mode (expected: quick, standard, deep)"
            exit 1
        fi
        # Apply token budget per execution mode (separate from cost budget used in review mode)
        local rt_token_budget
        case "$rt_execution_mode" in
            quick)    rt_token_budget=$(yq '.red_team.budgets.quick_max_tokens // 50000' "$CONFIG_FILE" 2>/dev/null || echo 50000) ;;
            standard) rt_token_budget=$(yq '.red_team.budgets.standard_max_tokens // 200000' "$CONFIG_FILE" 2>/dev/null || echo 200000) ;;
            deep)     rt_token_budget=$(yq '.red_team.budgets.deep_max_tokens // 500000' "$CONFIG_FILE" 2>/dev/null || echo 500000) ;;
        esac
        log "Red team mode: execution=$rt_execution_mode, depth=$rt_depth, token_budget=$rt_token_budget"
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

    # Detect execution mode (interactive vs autonomous)
    local mode_detect_script="$SCRIPT_DIR/flatline-mode-detect.sh"
    local execution_mode="interactive"
    local mode_reason="default"

    if [[ -x "$mode_detect_script" ]]; then
        local mode_result
        if mode_result=$("$mode_detect_script" $mode_flag --json 2>/dev/null); then
            execution_mode=$(echo "$mode_result" | jq -r '.mode // "interactive"')
            mode_reason=$(echo "$mode_result" | jq -r '.reason // "unknown"')
            log "Execution mode: $execution_mode (reason: $mode_reason)"
        else
            log "Warning: Mode detection failed, defaulting to interactive"
        fi
    else
        log "Warning: Mode detection script not found, defaulting to interactive"
    fi

    log "Document: $doc"
    log "Phase: $phase"
    log "Mode: $execution_mode"
    log "Timeout: ${timeout}s"
    log "Budget: ${budget} cents"

    # Dry run - validate only
    if [[ "$dry_run" == "true" ]]; then
        log "Dry run - validation passed"
        jq -n \
            --arg status "dry_run" \
            --arg doc "$doc" \
            --arg phase "$phase" \
            --arg mode "$execution_mode" \
            --arg mode_reason "$mode_reason" \
            '{status: $status, document: $doc, phase: $phase, mode: $mode, mode_reason: $mode_reason}'
        exit 0
    fi

    # Extract domain if not provided
    if [[ -z "$domain" ]]; then
        domain=$(extract_domain "$doc" "$phase")
        log "Extracted domain: $domain"
    fi

    # Phase -0.5: Knowledge Retrieval (Two-Tier)
    local context_file="$TEMP_DIR/knowledge-context.md"
    if [[ "$skip_knowledge" != "true" ]]; then
        set_state "KNOWLEDGE"
        log "Retrieving knowledge context (two-tier)"

        # Tier 1: Local knowledge (framework + project learnings)
        log "Tier 1: Local knowledge retrieval"
        if "$KNOWLEDGE_LOCAL" --domain "$domain" --phase "$phase" --format markdown > "$context_file" 2>/dev/null; then
            log "Tier 1: Local knowledge retrieval complete"
        else
            log "Warning: Tier 1 knowledge retrieval failed (continuing)"
            echo "" > "$context_file"
        fi

        # Tier 2: NotebookLM (optional, appends to context)
        log "Tier 2: NotebookLM knowledge retrieval"
        query_notebooklm "$domain" "$phase" "$context_file"

        log "Knowledge retrieval complete (two-tier)"
    else
        echo "" > "$context_file"
    fi

    # Mode dispatch: red-team mode uses separate pipeline
    if [[ "$orchestrator_mode" == "red-team" ]]; then
        local rt_pipeline="$SCRIPT_DIR/red-team-pipeline.sh"
        if [[ ! -x "$rt_pipeline" ]]; then
            error "Red team pipeline not found: $rt_pipeline"
            exit 1
        fi

        local rt_run_id
        rt_run_id="rt-$(date +%s)-$(head -c 4 /dev/urandom | od -An -tx1 | tr -d ' \n')"

        local rt_result
        rt_result=$("$rt_pipeline" \
            --doc "$doc" \
            --phase "$phase" \
            --context-file "$context_file" \
            --execution-mode "$rt_execution_mode" \
            --depth "$rt_depth" \
            --run-id "$rt_run_id" \
            --timeout "$timeout" \
            --budget "$rt_token_budget" \
            ${rt_focus:+--focus "$rt_focus"} \
            ${rt_surface:+--surface "$rt_surface"} \
            --json 2>/dev/null) || {
            local rt_exit=$?
            error "Red team pipeline failed (exit $rt_exit)"
            exit $rt_exit
        }

        set_state "DONE"

        # Add metadata to result
        local end_time
        end_time=$(date +%s)
        local total_latency_ms=$(( (end_time - START_TIME) * 1000 ))

        local final_result
        final_result=$(echo "$rt_result" | jq \
            --arg phase "$phase" \
            --arg doc "$doc" \
            --arg domain "$domain" \
            --arg mode "$execution_mode" \
            --arg mode_reason "$mode_reason" \
            --arg run_id "$rt_run_id" \
            --arg orch_mode "red-team" \
            --arg exec_mode "$rt_execution_mode" \
            --argjson latency_ms "$total_latency_ms" \
            --argjson cost_cents "$TOTAL_COST" \
            --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
            '. + {
                phase: $phase,
                document: $doc,
                mode: $orch_mode,
                execution_mode: $exec_mode,
                execution: {
                    mode: $mode,
                    mode_reason: $mode_reason,
                    run_id: $run_id
                },
                timestamp: $timestamp,
                metrics: (.metrics // {}) + {
                    total_latency_ms: $latency_ms,
                    cost_cents: $cost_cents
                }
            }')

        log_trajectory "complete" "$final_result"
        echo "$final_result" | jq .
        log "Red team complete. Run ID: $rt_run_id, Cost: $TOTAL_COST cents"
        exit 0
    fi

    # Mode dispatch: inquiry mode uses collaborative multi-model queries (FR-4)
    if [[ "$orchestrator_mode" == "inquiry" ]]; then
        local inq_run_id
        inq_run_id="inq-$(date +%s)-$(head -c 4 /dev/urandom | od -An -tx1 | tr -d ' \n')"

        local inq_budget
        inq_budget=$(read_config '.flatline_protocol.inquiry.budget_cents' '500')

        local inq_result
        inq_result=$(run_inquiry "$doc" "$phase" "$context_file" "$DEFAULT_MODEL_TIMEOUT" "$inq_budget") || {
            local inq_exit=$?
            error "Inquiry mode failed (exit $inq_exit)"
            exit $inq_exit
        }

        set_state "DONE"

        local end_time
        end_time=$(date +%s)
        local total_latency_ms=$(( (end_time - START_TIME) * 1000 ))

        local final_result
        final_result=$(echo "$inq_result" | jq \
            --arg phase "$phase" \
            --arg doc "$doc" \
            --arg domain "$domain" \
            --arg mode "$execution_mode" \
            --arg mode_reason "$mode_reason" \
            --arg run_id "$inq_run_id" \
            --arg orch_mode "inquiry" \
            --argjson latency_ms "$total_latency_ms" \
            --argjson cost_cents "$TOTAL_COST" \
            --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
            '. + {
                phase: $phase,
                document: $doc,
                domain: $domain,
                orchestrator_mode: $orch_mode,
                execution: {
                    mode: $mode,
                    mode_reason: $mode_reason,
                    run_id: $run_id
                },
                timestamp: $timestamp,
                metrics: (.metrics // {}) + {
                    total_latency_ms: $latency_ms,
                    cost_cents: $cost_cents,
                    cost_usd: ($cost_cents / 100)
                }
            }')

        # Save to output directory
        local output_dir="$PROJECT_ROOT/grimoires/loa/a2a/flatline"
        mkdir -p "$output_dir"
        echo "$final_result" | jq . > "$output_dir/${phase}-inquiry.json"

        log_trajectory "complete" "$final_result"
        echo "$final_result" | jq .
        log "Inquiry complete. Run ID: $inq_run_id, Cost: $TOTAL_COST cents"
        exit 0
    fi

    # Phase 1: Independent Reviews (review mode)
    local phase1_output
    phase1_output=$(run_phase1 "$doc" "$phase" "$context_file" "$DEFAULT_MODEL_TIMEOUT" "$budget")

    local gpt_review_file opus_review_file gpt_skeptic_file opus_skeptic_file
    local tertiary_review_file="" tertiary_skeptic_file=""
    gpt_review_file=$(echo "$phase1_output" | sed -n '1p')
    opus_review_file=$(echo "$phase1_output" | sed -n '2p')
    gpt_skeptic_file=$(echo "$phase1_output" | sed -n '3p')
    opus_skeptic_file=$(echo "$phase1_output" | sed -n '4p')
    # FR-3: Tertiary paths are lines 5-6 when present
    tertiary_review_file=$(echo "$phase1_output" | sed -n '5p')
    tertiary_skeptic_file=$(echo "$phase1_output" | sed -n '6p')

    # Check budget before Phase 2
    if ! check_budget 100 "$budget"; then
        log "Warning: Budget limit approaching, skipping Phase 2"
        skip_consensus=true
    fi

    # Phase 2: Cross-Scoring (unless skipped)
    local gpt_scores_file="" opus_scores_file=""
    local tertiary_scores_opus="" tertiary_scores_gpt="" gpt_scores_tertiary="" opus_scores_tertiary=""
    if [[ "$skip_consensus" != "true" ]]; then
        local phase2_output
        phase2_output=$(run_phase2 "$gpt_review_file" "$opus_review_file" "$phase" "$DEFAULT_MODEL_TIMEOUT" "$tertiary_review_file")

        gpt_scores_file=$(echo "$phase2_output" | sed -n '1p')
        opus_scores_file=$(echo "$phase2_output" | sed -n '2p')
        # FR-3: Tertiary scoring files are lines 3-6 when present
        tertiary_scores_opus=$(echo "$phase2_output" | sed -n '3p')
        tertiary_scores_gpt=$(echo "$phase2_output" | sed -n '4p')
        gpt_scores_tertiary=$(echo "$phase2_output" | sed -n '5p')
        opus_scores_tertiary=$(echo "$phase2_output" | sed -n '6p')
    fi

    # Phase 3: Consensus Calculation
    local result
    if [[ "$skip_consensus" != "true" && -n "$gpt_scores_file" && -n "$opus_scores_file" ]]; then
        result=$(run_consensus "$gpt_scores_file" "$opus_scores_file" "$gpt_skeptic_file" "$opus_skeptic_file" \
            "$tertiary_scores_opus" "$tertiary_scores_gpt" "$gpt_scores_tertiary" "$opus_scores_tertiary" \
            "$tertiary_skeptic_file")
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
        --arg mode "$execution_mode" \
        --arg mode_reason "$mode_reason" \
        --arg run_id "${run_id:-}" \
        --argjson latency_ms "$total_latency_ms" \
        --argjson cost_cents "$TOTAL_COST" \
        --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '. + {
            phase: $phase,
            document: $doc,
            domain: $domain,
            execution: {
                mode: $mode,
                mode_reason: $mode_reason,
                run_id: (if $run_id == "" then null else $run_id end)
            },
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
