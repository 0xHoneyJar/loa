#!/usr/bin/env bash
# GPT 5.2/5.3 API interaction for cross-model review
#
# Usage: gpt-review-api.sh <review_type> <content_file> [options]
#
# Arguments:
#   review_type: prd | sdd | sprint | code
#   content_file: File containing content to review
#
# Options:
#   --expertise <file>     Domain expertise (system prompt - WHO GPT is)
#   --context <file>       Product/feature context (user prompt - WHAT we're reviewing)
#   --iteration <N>        Review iteration (1 = first review, 2+ = re-review)
#   --previous <file>      Previous findings JSON file (for re-review)
#
# Prompt Structure:
#   SYSTEM: [Domain Expertise] + [Review Instructions from base prompt]
#   USER:   [Product Context] + [Feature Context] + [Content to Review]
#
# Environment:
#   OPENAI_API_KEY - Required (or loaded from .env or .env.local)
#
# Exit codes:
#   0 - Success (includes SKIPPED)
#   1 - API error
#   2 - Invalid input
#   3 - Timeout
#   4 - Missing API key
#   5 - Invalid response format
#
# Response format (always valid JSON with verdict field):
#   {"verdict": "SKIPPED|APPROVED|CHANGES_REQUIRED|DECISION_NEEDED", ...}

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROMPTS_DIR="${SCRIPT_DIR}/../prompts/gpt-review/base"
CONFIG_FILE=".loa.config.yaml"
MODEL_INVOKE="$SCRIPT_DIR/model-invoke"

# Source centralized JSON normalization and diagnostics libraries
source "$SCRIPT_DIR/lib/normalize-json.sh"
source "$SCRIPT_DIR/lib/invoke-diagnostics.sh"

# Require bash 4.0+ (associative arrays)
# shellcheck source=bash-version-guard.sh
source "$SCRIPT_DIR/bash-version-guard.sh"

# Default models per review type
declare -A DEFAULT_MODELS=(
  ["prd"]="gpt-5.2"
  ["sdd"]="gpt-5.2"
  ["sprint"]="gpt-5.2"
  ["code"]="gpt-5.2-codex"
)

# Map review types to phase config keys
declare -A PHASE_KEYS=(
  ["prd"]="prd"
  ["sdd"]="sdd"
  ["sprint"]="sprint"
  ["code"]="implementation"
)

# Default timeout in seconds
DEFAULT_TIMEOUT=300

# Max retries for transient failures
MAX_RETRIES=3
RETRY_DELAY=5

# Default max iterations before auto-approve
DEFAULT_MAX_ITERATIONS=3

# Default token budget for content (rough estimate: bytes / 4)
# 30k tokens ≈ 120k chars — leaves room for system prompt + context in 128k window
DEFAULT_MAX_REVIEW_TOKENS=30000

# System zone alert (default: true for code reviews)
SYSTEM_ZONE_ALERT="${GPT_REVIEW_SYSTEM_ZONE_ALERT:-true}"

log() {
  echo "[gpt-review-api] $*" >&2
}

error() {
  echo "ERROR: $*" >&2
}

# Return SKIPPED response and exit successfully
skip_review() {
  local reason="$1"
  cat <<EOF
{
  "verdict": "SKIPPED",
  "reason": "$reason"
}
EOF
  exit 0
}

# Check if GPT review is enabled in config
# Returns: 0 if enabled, 1 if disabled
check_config_enabled() {
  local review_type="$1"
  local phase_key="${PHASE_KEYS[$review_type]}"

  # Check if config file exists
  if [[ ! -f "$CONFIG_FILE" ]]; then
    log "Config file not found, GPT review disabled by default"
    return 1
  fi

  # Check if yq is available
  if ! command -v yq &>/dev/null; then
    log "yq not available, cannot read config"
    return 1
  fi

  # Check global enabled flag
  local enabled
  enabled=$(yq eval '.gpt_review.enabled // false' "$CONFIG_FILE" 2>/dev/null || echo "false")
  if [[ "$enabled" != "true" ]]; then
    return 1
  fi

  # Check phase-specific flag
  # NOTE: yq's // operator treats boolean false as falsy, so we must NOT use it
  # Instead, check if the key exists and get its raw value
  local phase_raw phase_enabled
  # First check if the key exists (returns "true" or "false" for existence)
  local key_exists
  key_exists=$(yq eval ".gpt_review.phases | has(\"${phase_key}\")" "$CONFIG_FILE" 2>/dev/null || echo "false")
  if [[ "$key_exists" == "true" ]]; then
    # Key exists, get its actual value
    phase_raw=$(yq eval ".gpt_review.phases.${phase_key}" "$CONFIG_FILE" 2>/dev/null || echo "true")
  else
    # Key doesn't exist, default to enabled (true)
    phase_raw="true"
  fi
  # Normalize to lowercase for case-insensitive comparison
  phase_enabled=$(echo "$phase_raw" | tr '[:upper:]' '[:lower:]')
  # Check for any false-like value (false, no, off, 0)
  if [[ "$phase_enabled" == "false" || "$phase_enabled" == "no" || "$phase_enabled" == "off" || "$phase_enabled" == "0" ]]; then
    return 1
  fi

  return 0
}

# Load configuration from .loa.config.yaml if available
load_config() {
  if [[ -f "$CONFIG_FILE" ]] && command -v yq &>/dev/null; then
    local timeout_val max_iter_val
    timeout_val=$(yq eval '.gpt_review.timeout_seconds // ""' "$CONFIG_FILE" 2>/dev/null || echo "")
    if [[ -n "$timeout_val" && "$timeout_val" != "null" ]]; then
      GPT_REVIEW_TIMEOUT="${GPT_REVIEW_TIMEOUT:-$timeout_val}"
    fi

    max_iter_val=$(yq eval '.gpt_review.max_iterations // ""' "$CONFIG_FILE" 2>/dev/null || echo "")
    if [[ -n "$max_iter_val" && "$max_iter_val" != "null" ]]; then
      MAX_ITERATIONS="$max_iter_val"
    fi

    # Model overrides from config
    local doc_model code_model
    doc_model=$(yq eval '.gpt_review.models.documents // ""' "$CONFIG_FILE" 2>/dev/null || echo "")
    code_model=$(yq eval '.gpt_review.models.code // ""' "$CONFIG_FILE" 2>/dev/null || echo "")

    if [[ -n "$doc_model" && "$doc_model" != "null" ]]; then
      DEFAULT_MODELS["prd"]="$doc_model"
      DEFAULT_MODELS["sdd"]="$doc_model"
      DEFAULT_MODELS["sprint"]="$doc_model"
    fi
    if [[ -n "$code_model" && "$code_model" != "null" ]]; then
      DEFAULT_MODELS["code"]="$code_model"
    fi

    # Large diff handling config (#226)
    local max_tokens_val sza_val
    max_tokens_val=$(yq eval '.gpt_review.max_review_tokens // ""' "$CONFIG_FILE" 2>/dev/null || echo "")
    if [[ -n "$max_tokens_val" && "$max_tokens_val" != "null" ]]; then
      DEFAULT_MAX_REVIEW_TOKENS="$max_tokens_val"
    fi
    sza_val=$(yq eval '.gpt_review.system_zone_alert // ""' "$CONFIG_FILE" 2>/dev/null || echo "")
    if [[ -n "$sza_val" && "$sza_val" != "null" ]]; then
      SYSTEM_ZONE_ALERT="$sza_val"
    fi
  fi
}

# =============================================================================
# System Zone Detection (#226)
# =============================================================================
# Detects when review content contains changes to .claude/ (System Zone).
# System zone files affect framework behavior for ALL future agent sessions
# and require elevated security scrutiny.

# Detect system zone changes in diff/content
# Outputs system zone file paths to stdout (one per line)
# Returns: 0 if system zone changes detected, 1 otherwise
detect_system_zone_changes() {
  local content="$1"

  # Match diff headers referencing .claude/ paths
  local system_files
  system_files=$(printf '%s' "$content" | grep -oE '(\+\+\+ b/|diff --git a/)\.claude/[^ ]+' \
    | sed 's|^+++ b/||;s|^diff --git a/||' | sort -u) || true

  if [[ -n "$system_files" ]]; then
    echo "$system_files"
    return 0
  fi

  return 1
}

# =============================================================================
# Shared Content Processing Functions
# =============================================================================
# file_priority(), estimate_tokens(), prepare_content() are defined in
# lib-content.sh — a shared library also used by adversarial-review.sh.
# Sourced here to maintain single source of truth.
# See: Bridgebuilder Review Finding #1 (PR #235)

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-content.sh"

# Build the system prompt for first review
# Structure: [Domain Expertise] + [Review Instructions]
build_first_review_prompt() {
  local review_type="$1"
  local expertise_file="${2:-}"

  local base_prompt_file="${PROMPTS_DIR}/${review_type}-review.md"

  if [[ ! -f "$base_prompt_file" ]]; then
    error "Base prompt not found: $base_prompt_file"
    exit 2
  fi

  local system_prompt=""

  # Domain expertise goes FIRST (defines WHO GPT is)
  if [[ -n "$expertise_file" && -f "$expertise_file" ]]; then
    system_prompt+=$(cat "$expertise_file")
    system_prompt+=$'\n\n---\n\n'
  fi

  # Then review instructions (defines HOW to review)
  system_prompt+=$(cat "$base_prompt_file")

  echo "$system_prompt"
}

# Build the user prompt with context and content
# Structure: [Product Context] + [Feature Context] + [Content to Review]
build_user_prompt() {
  local context_file="$1"
  local content="$2"

  local user_prompt=""

  # Product and feature context first
  if [[ -n "$context_file" && -f "$context_file" ]]; then
    user_prompt+=$(cat "$context_file")
    user_prompt+=$'\n\n---\n\n'
  fi

  # Then the actual content to review
  user_prompt+="## Content to Review"$'\n\n'
  user_prompt+="$content"

  echo "$user_prompt"
}

# Build the system prompt for re-review (iteration 2+)
# Structure: [Domain Expertise] + [Re-review Instructions with Previous Findings]
build_re_review_prompt() {
  local iteration="$1"
  local previous_findings="$2"
  local expertise_file="${3:-}"

  local re_review_file="${PROMPTS_DIR}/re-review.md"

  if [[ ! -f "$re_review_file" ]]; then
    error "Re-review prompt not found: $re_review_file"
    exit 2
  fi

  local system_prompt=""

  # Domain expertise goes FIRST
  if [[ -n "$expertise_file" && -f "$expertise_file" ]]; then
    system_prompt+=$(cat "$expertise_file")
    system_prompt+=$'\n\n---\n\n'
  fi

  # Then re-review instructions
  local re_review_prompt
  re_review_prompt=$(cat "$re_review_file")

  # Replace placeholders
  re_review_prompt="${re_review_prompt//\{\{ITERATION\}\}/$iteration}"
  re_review_prompt="${re_review_prompt//\{\{PREVIOUS_FINDINGS\}\}/$previous_findings}"

  system_prompt+="$re_review_prompt"

  echo "$system_prompt"
}

# =============================================================================
# Hounfour Routing (SDD §4.4.2)
# =============================================================================

is_flatline_routing_enabled() {
  if [[ "${HOUNFOUR_FLATLINE_ROUTING:-}" == "true" ]]; then
    return 0
  fi
  if [[ "${HOUNFOUR_FLATLINE_ROUTING:-}" == "false" ]]; then
    return 1
  fi
  if [[ -f "$CONFIG_FILE" ]] && command -v yq &> /dev/null; then
    local value
    value=$(yq -r '.hounfour.flatline_routing // false' "$CONFIG_FILE" 2>/dev/null)
    if [[ "$value" == "true" ]]; then
      return 0
    fi
  fi
  return 1
}

# Call model-invoke instead of direct curl to OpenAI.
# Uses gpt-reviewer agent binding. Writes system/user prompts to temp files.
call_api_via_model_invoke() {
  local model="$1"
  local system_prompt="$2"
  local content="$3"
  local timeout="$4"

  log "Routing through model-invoke (gpt-reviewer agent)"

  # Write system prompt to temp file for --system
  local system_file
  system_file=$(mktemp)
  chmod 600 "$system_file"
  printf '%s' "$system_prompt" > "$system_file"

  # Write user content to temp file for --input
  local input_file
  input_file=$(mktemp)
  chmod 600 "$input_file"
  printf '%s' "$content" > "$input_file"

  # Map legacy model name to provider:model-id format
  local model_override="$model"
  case "$model" in
    gpt-5.2)       model_override="openai:gpt-5.2" ;;
    gpt-5.2-codex) model_override="openai:gpt-5.2-codex" ;;
    gpt-5.3-codex) model_override="openai:gpt-5.3-codex" ;;
  esac

  local result exit_code=0
  result=$("$MODEL_INVOKE" \
    --agent gpt-reviewer \
    --input "$input_file" \
    --system "$system_file" \
    --model "$model_override" \
    --output-format text \
    --json-errors \
    --timeout "$timeout" \
    2>/dev/null) || exit_code=$?

  rm -f "$system_file" "$input_file"

  if [[ $exit_code -ne 0 ]]; then
    error "model-invoke failed with exit code $exit_code"
    return $exit_code
  fi

  # model-invoke returns raw content text — may be JSON, fenced JSON, or prose-wrapped.
  # Normalize and validate via centralized library.
  local content_response
  content_response=$(normalize_json_response "$result" 2>/dev/null) || {
    error "Invalid JSON in model-invoke response"
    log "Raw response (first 500 chars): ${result:0:500}"
    exit 5
  }

  # Validate gpt-reviewer schema (verdict enum, required fields)
  if ! validate_agent_response "$content_response" "gpt-reviewer" 2>/dev/null; then
    error "Schema validation failed for gpt-reviewer response"
    log "Normalized response: $content_response"
    exit 5
  fi

  echo "$content_response"
}

# Call OpenAI API with retry logic
call_api() {
  local model="$1"
  local system_prompt="$2"
  local content="$3"
  local timeout="$4"

  local api_url
  local payload

  # Codex models use Responses API at /v1/responses
  # See: https://platform.openai.com/docs/guides/code-generation
  if [[ "$model" == *"codex"* ]]; then
    api_url="https://api.openai.com/v1/responses"

    # For codex: use Responses API format with 'input' field
    # Combine system prompt and content into single input
    local combined_input
    combined_input=$(printf '%s\n\n---\n\n## CONTENT TO REVIEW:\n\n%s\n\n---\n\nRespond with valid JSON only.' "$system_prompt" "$content")
    local escaped_input
    escaped_input=$(printf '%s' "$combined_input" | jq -Rs .)

    payload=$(cat <<EOF
{
  "model": "${model}",
  "input": ${escaped_input},
  "reasoning": {"effort": "medium"}
}
EOF
)
  else
    # Standard chat models use /v1/chat/completions
    api_url="https://api.openai.com/v1/chat/completions"

    # Escape for JSON using jq
    local escaped_system escaped_content
    escaped_system=$(printf '%s' "$system_prompt" | jq -Rs .)
    escaped_content=$(printf '%s' "$content" | jq -Rs .)

    payload=$(cat <<EOF
{
  "model": "${model}",
  "messages": [
    {"role": "system", "content": ${escaped_system}},
    {"role": "user", "content": ${escaped_content}}
  ],
  "temperature": 0.3,
  "response_format": {"type": "json_object"}
}
EOF
)
  fi

  local attempt=1
  local response http_code

  while [[ $attempt -le $MAX_RETRIES ]]; do
    log "API call attempt $attempt/$MAX_RETRIES (model: $model, timeout: ${timeout}s)"

    # Make API call with timeout
    # Security: Use curl config file to avoid exposing API key in process list (SHELL-001)
    local curl_config
    curl_config=$(mktemp)
    chmod 600 "$curl_config"
    cat > "$curl_config" <<'CURLCFG'
header = "Content-Type: application/json"
CURLCFG
    echo "header = \"Authorization: Bearer ${OPENAI_API_KEY}\"" >> "$curl_config"

    # Write payload to temp file to avoid bash argument size limits (SHELL-002)
    local payload_file
    payload_file=$(mktemp)
    chmod 600 "$payload_file"
    printf '%s' "$payload" > "$payload_file"

    local curl_output curl_exit
    curl_output=$(curl -s -w "\n%{http_code}" \
      --max-time "$timeout" \
      --config "$curl_config" \
      -d "@${payload_file}" \
      "$api_url" 2>&1) || {
        curl_exit=$?
        rm -f "$curl_config" "$payload_file"
        if [[ $curl_exit -eq 28 ]]; then
          error "API call timed out after ${timeout}s (attempt $attempt)"
          if [[ $attempt -lt $MAX_RETRIES ]]; then
            log "Retrying in ${RETRY_DELAY}s..."
            sleep "$RETRY_DELAY"
            ((attempt++))
            continue
          fi
          exit 3
        fi
        error "curl failed with exit code $curl_exit"
        exit 1
      }

    # Clean up curl config and payload file
    rm -f "$curl_config" "$payload_file"

    # Extract HTTP code from last line
    http_code=$(echo "$curl_output" | tail -1)
    response=$(echo "$curl_output" | sed '$d')

    # Handle different HTTP codes
    case "$http_code" in
      200)
        # Success - break out of retry loop
        break
        ;;
      401)
        error "Authentication failed - check OPENAI_API_KEY"
        exit 4
        ;;
      429)
        log "Rate limited (429) - attempt $attempt"
        if [[ $attempt -lt $MAX_RETRIES ]]; then
          local wait_time=$((RETRY_DELAY * attempt))
          log "Waiting ${wait_time}s before retry..."
          sleep "$wait_time"
          ((attempt++))
          continue
        fi
        error "Rate limit exceeded after $MAX_RETRIES attempts"
        exit 1
        ;;
      500|502|503|504)
        log "Server error ($http_code) - attempt $attempt"
        if [[ $attempt -lt $MAX_RETRIES ]]; then
          log "Retrying in ${RETRY_DELAY}s..."
          sleep "$RETRY_DELAY"
          ((attempt++))
          continue
        fi
        error "Server error after $MAX_RETRIES attempts"
        exit 1
        ;;
      *)
        error "API returned HTTP $http_code"
        log "Response: $response"
        exit 1
        ;;
    esac
  done

  # Extract content from response
  # - Chat Completions: .choices[0].message.content
  # - Responses API: .output[].content[].text (find the message with output_text)
  local content_response
  content_response=$(echo "$response" | jq -r '
    .choices[0].message.content //
    (.output[] | select(.type == "message") | .content[] | select(.type == "output_text") | .text) //
    empty
  ')

  if [[ -z "$content_response" ]]; then
    error "No content in API response"
    log "Full response: $response"
    exit 5
  fi

  # Trim leading/trailing whitespace
  content_response=$(echo "$content_response" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

  # Validate JSON response
  if ! echo "$content_response" | jq empty 2>/dev/null; then
    error "Invalid JSON in response"
    log "Response content: $content_response"
    exit 5
  fi

  # Validate required fields
  local verdict
  verdict=$(echo "$content_response" | jq -r '.verdict // empty')
  if [[ -z "$verdict" ]]; then
    error "Response missing 'verdict' field"
    log "Response content: $content_response"
    exit 5
  fi

  if [[ "$verdict" != "APPROVED" && "$verdict" != "CHANGES_REQUIRED" && "$verdict" != "DECISION_NEEDED" ]]; then
    error "Invalid verdict: $verdict (expected: APPROVED, CHANGES_REQUIRED, or DECISION_NEEDED)"
    exit 5
  fi

  echo "$content_response"
}

usage() {
  cat <<EOF
Usage: gpt-review-api.sh <review_type> <content_file> [options]

Arguments:
  review_type       Type of review: prd, sdd, sprint, code
  content_file      File containing content to review

Options:
  --expertise <file>     Domain expertise file (SYSTEM prompt - WHO GPT is)
  --context <file>       Product/feature context file (USER prompt - WHAT we're reviewing)
  --iteration <N>        Review iteration (1 = first, 2+ = re-review)
  --previous <file>      Previous findings JSON (required for iteration > 1)
  --output <file>        Write JSON response to file (in addition to stdout)

Prompt Structure:
  SYSTEM: [Domain Expertise from --expertise] + [Review Instructions]
  USER:   [Product/Feature Context from --context] + [Content to Review]

Environment:
  OPENAI_API_KEY    Required - Your OpenAI API key (or in .env / .env.local)

Exit Codes:
  0 - Success (includes SKIPPED when disabled)
  1 - API error
  2 - Invalid input
  3 - Timeout
  4 - Missing/invalid API key
  5 - Invalid response format

Response Format:
  Always returns valid JSON with 'verdict' field:
  {"verdict": "SKIPPED|APPROVED|CHANGES_REQUIRED|DECISION_NEEDED", ...}
EOF
}

main() {
  local review_type=""
  local content_file=""
  local expertise_file=""
  local context_file=""
  local iteration=1
  local previous_file=""
  local output_file=""

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --expertise)
        expertise_file="$2"
        shift 2
        ;;
      --context)
        context_file="$2"
        shift 2
        ;;
      --iteration)
        iteration="$2"
        shift 2
        ;;
      --previous)
        previous_file="$2"
        shift 2
        ;;
      --output)
        output_file="$2"
        shift 2
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      -*)
        error "Unknown option: $1"
        usage
        exit 2
        ;;
      *)
        if [[ -z "$review_type" ]]; then
          review_type="$1"
        elif [[ -z "$content_file" ]]; then
          content_file="$1"
        fi
        shift
        ;;
    esac
  done

  # Show usage if no args
  if [[ -z "$review_type" ]]; then
    usage
    exit 2
  fi

  # Validate review type
  if [[ ! "${DEFAULT_MODELS[$review_type]+exists}" ]]; then
    error "Invalid review type: $review_type"
    echo "Valid types: prd, sdd, sprint, code" >&2
    exit 2
  fi

  # NOTE: No config check here - the API always works if you have an API key.
  # The config (gpt_review.enabled) controls whether Loa *automatically* prompts
  # for GPT review, not whether manual /gpt-review invocations work.

  # Validate content file
  if [[ -z "$content_file" ]]; then
    error "Content file required"
    usage
    exit 2
  fi

  if [[ ! -f "$content_file" ]]; then
    error "Content file not found: $content_file"
    exit 2
  fi

  # ============================================
  # REQUIRE EXPERTISE AND CONTEXT FILES
  # These provide the full context GPT needs:
  #   --expertise: Domain expertise (SYSTEM prompt) - WHO GPT is
  #   --context:   Product/feature context (USER prompt) - WHAT we're reviewing
  # ============================================
  if [[ -z "$expertise_file" ]]; then
    cat >&2 <<EOF
ERROR: Missing --expertise file (required for system prompt)

The --expertise file defines WHO GPT is - the domain expert role.
You must create this file with domain expertise extracted from the PRD.

Example: /tmp/gpt-review-expertise.md
---
You are an expert in [domain from PRD]. You have deep knowledge of:
- [Key domain concept 1]
- [Key domain concept 2]
- [Relevant standards/protocols]
- [Common pitfalls in this domain]
---

Then call:
  $0 $review_type $content_file --expertise /tmp/gpt-review-expertise.md --context /tmp/gpt-review-context.md
EOF
    exit 2
  fi

  if [[ ! -f "$expertise_file" ]]; then
    error "Expertise file not found: $expertise_file"
    echo "Create the expertise file with domain knowledge from PRD before calling this script." >&2
    exit 2
  fi

  if [[ -z "$context_file" ]]; then
    cat >&2 <<EOF
ERROR: Missing --context file (required for user prompt)

The --context file provides WHAT GPT is reviewing - product and feature context.
You must create this file with context extracted from PRD/SDD/sprint.md.

Example: /tmp/gpt-review-context.md
---
## Product Context

[Product name] is [what it does] for [target users].
Critical requirements: [from PRD].

## Feature Context

**Task**: [What you're implementing]
**Acceptance Criteria**:
- [Criterion 1]
- [Criterion 2]

## What to Verify

1. [Specific verification point]
2. [Another verification point]
---

Then call:
  $0 $review_type $content_file --expertise /tmp/gpt-review-expertise.md --context /tmp/gpt-review-context.md
EOF
    exit 2
  fi

  if [[ ! -f "$context_file" ]]; then
    error "Context file not found: $context_file"
    echo "Create the context file with product/feature context before calling this script." >&2
    exit 2
  fi

  # Load from .env or .env.local if OPENAI_API_KEY not already set
  if [[ -z "${OPENAI_API_KEY:-}" ]]; then
    local env_key=""
    local env_source=""

    # Check .env first — tail -1 ensures last value wins (dedup)
    if [[ -f ".env" ]]; then
      env_key=$(grep -E "^OPENAI_API_KEY=" .env 2>/dev/null | tail -1 | cut -d'=' -f2- | sed 's/ \+#.*//' | tr -d '"' | tr -d "'" || true)
      [[ -n "$env_key" ]] && env_source=".env"
    fi

    # Check .env.local (overrides .env) — tail -1 for dedup
    if [[ -f ".env.local" ]]; then
      local local_key
      local_key=$(grep -E "^OPENAI_API_KEY=" .env.local 2>/dev/null | tail -1 | cut -d'=' -f2- | sed 's/ \+#.*//' | tr -d '"' | tr -d "'" || true)
      if [[ -n "$local_key" ]]; then
        env_key="$local_key"
        env_source=".env.local"
      fi
    fi

    # Validate non-empty and non-whitespace
    if [[ -n "$env_key" ]]; then
      local trimmed="${env_key// /}"
      if [[ -z "$trimmed" ]]; then
        log "WARNING: OPENAI_API_KEY in $env_source is empty/whitespace — ignoring"
        env_key=""
      fi
    fi

    if [[ -n "$env_key" ]]; then
      export OPENAI_API_KEY="$env_key"
      log "Loaded OPENAI_API_KEY from $env_source"
    fi
  fi

  # Check API key
  if [[ -z "${OPENAI_API_KEY:-}" ]]; then
    error "OPENAI_API_KEY environment variable not set"
    echo "Export your OpenAI API key: export OPENAI_API_KEY='sk-...'" >&2
    exit 4
  fi

  # Check for jq
  if ! command -v jq &>/dev/null; then
    error "jq is required but not installed"
    exit 2
  fi

  # Load configuration
  MAX_ITERATIONS="${DEFAULT_MAX_ITERATIONS}"
  load_config

  # Check for max iterations auto-approve
  if [[ "$iteration" -gt "$MAX_ITERATIONS" ]]; then
    log "Iteration $iteration exceeds max_iterations ($MAX_ITERATIONS) - auto-approving"
    local auto_response
    auto_response=$(cat <<EOF
{
  "verdict": "APPROVED",
  "summary": "Auto-approved after $MAX_ITERATIONS iterations (max_iterations reached)",
  "auto_approved": true,
  "iteration": $iteration,
  "note": "Review converged by iteration limit. Consider adjusting max_iterations in config if needed."
}
EOF
    )
    if [[ -n "$output_file" ]]; then
      mkdir -p "$(dirname "$output_file")"
      echo "$auto_response" > "$output_file"
      log "Findings written to: $output_file"
    fi
    echo "$auto_response"
    exit 0
  fi

  # Determine model and timeout
  local model="${GPT_REVIEW_MODEL:-${DEFAULT_MODELS[$review_type]}}"
  local timeout="${GPT_REVIEW_TIMEOUT:-$DEFAULT_TIMEOUT}"

  log "Review type: $review_type"
  log "Iteration: $iteration"
  log "Model: $model"
  log "Timeout: ${timeout}s"
  log "Content file: $content_file"
  [[ -n "$expertise_file" ]] && log "Expertise (system): $expertise_file"
  [[ -n "$context_file" ]] && log "Context (user): $context_file"
  [[ -n "$previous_file" ]] && log "Previous findings: $previous_file"

  # Build system prompt based on iteration
  # System prompt = [Domain Expertise] + [Review Instructions]
  local system_prompt
  if [[ "$iteration" -eq 1 ]]; then
    system_prompt=$(build_first_review_prompt "$review_type" "$expertise_file")
  else
    # For re-review, we need previous findings
    if [[ -z "$previous_file" || ! -f "$previous_file" ]]; then
      error "Re-review (iteration > 1) requires --previous <file> with previous findings"
      exit 2
    fi
    local previous_findings
    previous_findings=$(cat "$previous_file")
    system_prompt=$(build_re_review_prompt "$iteration" "$previous_findings" "$expertise_file")
  fi

  # Read raw content
  local raw_content
  raw_content=$(cat "$content_file")

  # ── System Zone Detection (#226) ──────────────────
  local system_zone_warning=""
  if [[ "$SYSTEM_ZONE_ALERT" == "true" ]]; then
    local system_zone_files=""
    if system_zone_files=$(detect_system_zone_changes "$raw_content"); then
      local file_list
      file_list=$(echo "$system_zone_files" | tr '\n' ', ' | sed 's/,$//')
      system_zone_warning="SYSTEM ZONE (.claude/) CHANGES DETECTED. These files affect framework behavior for ALL future agent sessions. Apply ELEVATED security scrutiny: ${file_list}"
      log "WARNING: $system_zone_warning"
    fi
  fi

  # ── Smart Content Preparation (#226) ──────────────
  local max_review_tokens="${GPT_REVIEW_MAX_TOKENS:-$DEFAULT_MAX_REVIEW_TOKENS}"
  local prepared_content
  prepared_content=$(prepare_content "$raw_content" "$max_review_tokens")

  # Prepend system zone warning to content if detected
  if [[ -n "$system_zone_warning" ]]; then
    prepared_content=">>> ${system_zone_warning}"$'\n\n'"${prepared_content}"
  fi

  # Build user prompt with context
  # User prompt = [Product Context] + [Feature Context] + [Content to Review]
  local user_prompt
  user_prompt=$(build_user_prompt "$context_file" "$prepared_content")

  # Call API — route through model-invoke or direct curl based on feature flag
  # FR-2: Runtime fallback — if model-invoke fails, fall back to direct curl
  local response
  if is_flatline_routing_enabled && [[ -x "$MODEL_INVOKE" ]]; then
    local mi_exit=0
    response=$(call_api_via_model_invoke "$model" "$system_prompt" "$user_prompt" "$timeout") || mi_exit=$?
    if [[ $mi_exit -ne 0 ]]; then
      log "WARNING: model-invoke failed (exit $mi_exit), falling back to direct API call"
      response=$(call_api "$model" "$system_prompt" "$user_prompt" "$timeout")
    fi
  else
    response=$(call_api "$model" "$system_prompt" "$user_prompt" "$timeout")
  fi

  # Add metadata to response
  local metadata_args=(--arg iter "$iteration")
  local metadata_jq='. + {iteration: ($iter | tonumber)}'

  if [[ -n "$system_zone_warning" ]]; then
    metadata_args+=(--argjson system_zone "true")
    metadata_jq+='' # system_zone added via argjson below
  fi

  response=$(echo "$response" | jq "${metadata_args[@]}" "$metadata_jq")

  # Add system_zone flag if detected
  if [[ -n "$system_zone_warning" ]]; then
    response=$(echo "$response" | jq '. + {system_zone_detected: true}')
  fi

  # Sanitize output: strip ANSI escape codes and control characters
  # Defensive measure against malicious API responses
  response=$(echo "$response" | tr -d '\033' | tr -d '\000-\010\013\014\016-\037')

  # Write to output file if --output specified (Issue #249)
  if [[ -n "$output_file" ]]; then
    local output_dir
    output_dir=$(dirname "$output_file")
    if [[ ! -d "$output_dir" ]]; then
      mkdir -p "$output_dir"
    fi
    echo "$response" > "$output_file"
    log "Findings written to: $output_file"
  fi

  # Output response to stdout (always, for backward compat)
  echo "$response"
}

main "$@"
