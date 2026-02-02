#!/usr/bin/env bash
# GPT 5.2 API interaction for cross-model review
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
PROMPTS_DIR="${SCRIPT_DIR}/../prompts/gpt-review/base"
CONFIG_FILE=".loa.config.yaml"

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
  fi
}

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
    local curl_output
    curl_output=$(curl -s -w "\n%{http_code}" \
      --max-time "$timeout" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer ${OPENAI_API_KEY}" \
      -d "$payload" \
      "$api_url" 2>&1) || {
        local curl_exit=$?
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

    # Check .env first
    if [[ -f ".env" ]]; then
      env_key=$(grep -E "^OPENAI_API_KEY=" .env 2>/dev/null | cut -d'=' -f2- | tr -d '"' | tr -d "'" || true)
      [[ -n "$env_key" ]] && env_source=".env"
    fi

    # Check .env.local (overrides .env)
    if [[ -f ".env.local" ]]; then
      local local_key
      local_key=$(grep -E "^OPENAI_API_KEY=" .env.local 2>/dev/null | cut -d'=' -f2- | tr -d '"' | tr -d "'" || true)
      if [[ -n "$local_key" ]]; then
        env_key="$local_key"
        env_source=".env.local"
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
    cat <<EOF
{
  "verdict": "APPROVED",
  "summary": "Auto-approved after $MAX_ITERATIONS iterations (max_iterations reached)",
  "auto_approved": true,
  "iteration": $iteration,
  "note": "Review converged by iteration limit. Consider adjusting max_iterations in config if needed."
}
EOF
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

  # Build user prompt with context
  # User prompt = [Product Context] + [Feature Context] + [Content to Review]
  local user_prompt
  user_prompt=$(build_user_prompt "$context_file" "$raw_content")

  # Call API with separated prompts
  local response
  response=$(call_api "$model" "$system_prompt" "$user_prompt" "$timeout")

  # Add iteration to response
  response=$(echo "$response" | jq --arg iter "$iteration" '. + {iteration: ($iter | tonumber)}')

  # Sanitize output: strip ANSI escape codes and control characters
  # Defensive measure against malicious API responses
  response=$(echo "$response" | tr -d '\033' | tr -d '\000-\010\013\014\016-\037')

  # Output response
  echo "$response"
}

main "$@"
