#!/usr/bin/env bash
# =============================================================================
# lib-curl-fallback.sh — Extracted curl API call logic with retry
# =============================================================================
# Version: 1.0.0
# Cycle: cycle-033 (Codex CLI Integration for GPT Review)
#
# Extracted from gpt-review-api.sh to enable modular execution backends.
# This library provides the direct curl API path (OpenAI Chat Completions
# and Responses API) and the Hounfour model-invoke routing path.
#
# Used by:
#   - gpt-review-api.sh (curl fallback when codex unavailable)
#
# Functions:
#   call_api <model> <system_prompt> <content> <timeout>
#   call_api_via_model_invoke <model> <system_prompt> <content> <timeout>
#   is_flatline_routing_enabled
#
# Design decisions:
#   - Auth via OPENAI_API_KEY env var only (SDD SKP-003, Flatline SKP-001)
#   - curl config file technique retained for process list security (SHELL-001)
#   - Retry logic: 3 attempts with exponential backoff
#
# IMPORTANT: This file must NOT call any function at the top level.
# It is designed to be sourced by other scripts.

# Guard against double-sourcing
if [[ "${_LIB_CURL_FALLBACK_LOADED:-}" == "true" ]]; then
  return 0 2>/dev/null || true
fi
_LIB_CURL_FALLBACK_LOADED="true"

# =============================================================================
# Dependencies
# =============================================================================

# Ensure lib-security.sh is loaded (for ensure_codex_auth)
if [[ "${_LIB_SECURITY_LOADED:-}" != "true" ]]; then
  _lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # shellcheck source=lib-security.sh
  source "$_lib_dir/lib-security.sh"
  unset _lib_dir
fi

# =============================================================================
# Constants
# =============================================================================

# Retry configuration
_CURL_MAX_RETRIES="${MAX_RETRIES:-3}"
_CURL_RETRY_DELAY="${RETRY_DELAY:-5}"

# Model-invoke binary (set by caller or default)
_MODEL_INVOKE="${MODEL_INVOKE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/model-invoke}"

# Config file path (set by caller or default)
_CURL_CONFIG_FILE="${CONFIG_FILE:-.loa.config.yaml}"

# =============================================================================
# Feature Flags
# =============================================================================

# Check if Hounfour/Flatline routing is enabled.
# Checks env var first, then config file.
# Returns: 0 if enabled, 1 if disabled
is_flatline_routing_enabled() {
  if [[ "${HOUNFOUR_FLATLINE_ROUTING:-}" == "true" ]]; then
    return 0
  fi
  if [[ "${HOUNFOUR_FLATLINE_ROUTING:-}" == "false" ]]; then
    return 1
  fi
  if [[ -f "$_CURL_CONFIG_FILE" ]] && command -v yq &>/dev/null; then
    local value
    value=$(yq -r '.hounfour.flatline_routing // false' "$_CURL_CONFIG_FILE" 2>/dev/null)
    if [[ "$value" == "true" ]]; then
      return 0
    fi
  fi
  return 1
}

# =============================================================================
# Model-Invoke Routing (Hounfour)
# =============================================================================

# Call model-invoke instead of direct curl to OpenAI.
# Uses gpt-reviewer agent binding. Writes system/user prompts to temp files.
# Args: model system_prompt content timeout
# Outputs: validated JSON response to stdout
# Returns: 0 on success, non-zero on failure
call_api_via_model_invoke() {
  local model="$1"
  local system_prompt="$2"
  local content="$3"
  local timeout="$4"

  echo "[gpt-review-api] Routing through model-invoke (gpt-reviewer agent)" >&2

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
  result=$("$_MODEL_INVOKE" \
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
    echo "ERROR: model-invoke failed with exit code $exit_code" >&2
    return $exit_code
  fi

  # model-invoke returns raw content text — may be JSON, fenced JSON, or prose-wrapped.
  # Normalize and validate via centralized library.
  local content_response
  content_response=$(normalize_json_response "$result" 2>/dev/null) || {
    echo "ERROR: Invalid JSON in model-invoke response" >&2
    echo "[gpt-review-api] Raw response (first 500 chars): ${result:0:500}" >&2
    return 5
  }

  # Validate gpt-reviewer schema (verdict enum, required fields)
  if ! validate_agent_response "$content_response" "gpt-reviewer" 2>/dev/null; then
    echo "ERROR: Schema validation failed for gpt-reviewer response" >&2
    echo "[gpt-review-api] Normalized response: $content_response" >&2
    return 5
  fi

  echo "$content_response"
}

# =============================================================================
# Direct Curl API Call
# =============================================================================

# Call OpenAI API directly via curl with retry logic.
# Supports both Chat Completions API and Responses API (codex models).
# Uses curl config file for API key security (SHELL-001).
# Args: model system_prompt content timeout
# Outputs: validated JSON response to stdout
# Exit codes: 0=success, 1=API error, 3=timeout, 4=auth failure, 5=invalid response
call_api() {
  local model="$1"
  local system_prompt="$2"
  local content="$3"
  local timeout="$4"

  # Auth check — env-only (SDD SKP-003)
  if ! ensure_codex_auth; then
    echo "ERROR: OPENAI_API_KEY environment variable not set" >&2
    echo "Export your OpenAI API key: export OPENAI_API_KEY='sk-...'" >&2
    return 4
  fi

  local api_url payload

  # Codex models use Responses API at /v1/responses
  if [[ "$model" == *"codex"* ]]; then
    api_url="https://api.openai.com/v1/responses"

    local combined_input
    combined_input=$(printf '%s\n\n---\n\n## CONTENT TO REVIEW:\n\n%s\n\n---\n\nRespond with valid JSON only.' "$system_prompt" "$content")
    local escaped_input
    escaped_input=$(printf '%s' "$combined_input" | jq -Rs .)

    payload=$(printf '{"model":"%s","input":%s,"reasoning":{"effort":"medium"}}' "$model" "$escaped_input")
  else
    api_url="https://api.openai.com/v1/chat/completions"

    local escaped_system escaped_content
    escaped_system=$(printf '%s' "$system_prompt" | jq -Rs .)
    escaped_content=$(printf '%s' "$content" | jq -Rs .)

    payload=$(printf '{"model":"%s","messages":[{"role":"system","content":%s},{"role":"user","content":%s}],"temperature":0.3,"response_format":{"type":"json_object"}}' \
      "$model" "$escaped_system" "$escaped_content")
  fi

  local attempt=1
  local response http_code

  while [[ $attempt -le $_CURL_MAX_RETRIES ]]; do
    echo "[gpt-review-api] API call attempt $attempt/$_CURL_MAX_RETRIES (model: $model, timeout: ${timeout}s)" >&2

    # Security: Use curl config file to avoid exposing API key in process list (SHELL-001)
    local curl_config
    curl_config=$(mktemp)
    chmod 600 "$curl_config"
    printf 'header = "Content-Type: application/json"\n' > "$curl_config"
    printf 'header = "Authorization: Bearer %s"\n' "${OPENAI_API_KEY}" >> "$curl_config"

    # Write payload to temp file to avoid bash argument size limits (SHELL-002)
    local payload_file
    payload_file=$(mktemp)
    chmod 600 "$payload_file"
    printf '%s' "$payload" > "$payload_file"

    local curl_output curl_exit=0
    curl_output=$(curl -s -w "\n%{http_code}" \
      --max-time "$timeout" \
      --config "$curl_config" \
      -d "@${payload_file}" \
      "$api_url" 2>&1) || {
        curl_exit=$?
        rm -f "$curl_config" "$payload_file"
        if [[ $curl_exit -eq 28 ]]; then
          echo "ERROR: API call timed out after ${timeout}s (attempt $attempt)" >&2
          if [[ $attempt -lt $_CURL_MAX_RETRIES ]]; then
            echo "[gpt-review-api] Retrying in ${_CURL_RETRY_DELAY}s..." >&2
            sleep "$_CURL_RETRY_DELAY"
            ((attempt++))
            continue
          fi
          return 3
        fi
        echo "ERROR: curl failed with exit code $curl_exit" >&2
        return 1
      }

    rm -f "$curl_config" "$payload_file"

    # Extract HTTP code from last line
    http_code=$(echo "$curl_output" | tail -1)
    response=$(echo "$curl_output" | sed '$d')

    case "$http_code" in
      200)
        break
        ;;
      401)
        echo "ERROR: Authentication failed - check OPENAI_API_KEY" >&2
        return 4
        ;;
      429)
        echo "[gpt-review-api] Rate limited (429) - attempt $attempt" >&2
        if [[ $attempt -lt $_CURL_MAX_RETRIES ]]; then
          local wait_time=$((_CURL_RETRY_DELAY * attempt))
          echo "[gpt-review-api] Waiting ${wait_time}s before retry..." >&2
          sleep "$wait_time"
          ((attempt++))
          continue
        fi
        echo "ERROR: Rate limit exceeded after $_CURL_MAX_RETRIES attempts" >&2
        return 1
        ;;
      500|502|503|504)
        echo "[gpt-review-api] Server error ($http_code) - attempt $attempt" >&2
        if [[ $attempt -lt $_CURL_MAX_RETRIES ]]; then
          echo "[gpt-review-api] Retrying in ${_CURL_RETRY_DELAY}s..." >&2
          sleep "$_CURL_RETRY_DELAY"
          ((attempt++))
          continue
        fi
        echo "ERROR: Server error after $_CURL_MAX_RETRIES attempts" >&2
        return 1
        ;;
      *)
        echo "ERROR: API returned HTTP $http_code" >&2
        echo "[gpt-review-api] Response (truncated): ${response:0:200}" >&2
        return 1
        ;;
    esac
  done

  # Extract content from response
  # Chat Completions: .choices[0].message.content
  # Responses API: .output[].content[].text
  local content_response
  content_response=$(echo "$response" | jq -r '
    .choices[0].message.content //
    (.output[] | select(.type == "message") | .content[] | select(.type == "output_text") | .text) //
    empty
  ')

  if [[ -z "$content_response" ]]; then
    echo "ERROR: No content in API response" >&2
    echo "[gpt-review-api] Response (truncated): ${response:0:200}" >&2
    return 5
  fi

  # Trim whitespace
  content_response=$(echo "$content_response" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

  # Validate JSON
  if ! echo "$content_response" | jq empty 2>/dev/null; then
    echo "ERROR: Invalid JSON in response" >&2
    echo "[gpt-review-api] Response content: $content_response" >&2
    return 5
  fi

  # Validate verdict field
  local verdict
  verdict=$(echo "$content_response" | jq -r '.verdict // empty')
  if [[ -z "$verdict" ]]; then
    echo "ERROR: Response missing 'verdict' field" >&2
    echo "[gpt-review-api] Response content: $content_response" >&2
    return 5
  fi

  if [[ "$verdict" != "APPROVED" && "$verdict" != "CHANGES_REQUIRED" && "$verdict" != "DECISION_NEEDED" ]]; then
    echo "ERROR: Invalid verdict: $verdict (expected: APPROVED, CHANGES_REQUIRED, or DECISION_NEEDED)" >&2
    return 5
  fi

  echo "$content_response"
}
