#!/usr/bin/env bash
# =============================================================================
# lib-security.sh — Auth management, secret redaction, and log filtering
# =============================================================================
# Version: 1.0.0
# Cycle: cycle-033 (Codex CLI Integration for GPT Review)
#
# Used by:
#   - gpt-review-api.sh (auth + redaction for all execution backends)
#   - lib-codex-exec.sh (auth check before codex invocation)
#   - lib-curl-fallback.sh (auth check before curl invocation)
#
# Functions:
#   ensure_codex_auth             → 0 if OPENAI_API_KEY set, 1 otherwise
#   redact_secrets <content> [format] → redacted content (format: json|text)
#   redact_log_output <input>     → filtered stderr content
#   is_sensitive_file <filepath>  → 0 if file matches deny list
#
# Design decisions:
#   - Env-only auth: Never reads .env files or calls `codex login` (SDD SKP-003)
#   - jq-based JSON redaction: Only redacts string VALUES, never keys (Flatline SKP-004)
#   - Post-redaction structural diff: Verifies key count unchanged (Flatline SKP-004)
#
# IMPORTANT: This file must NOT call any function at the top level.
# It is designed to be sourced by other scripts.

# Guard against double-sourcing
if [[ "${_LIB_SECURITY_LOADED:-}" == "true" ]]; then
  return 0 2>/dev/null || true
fi
_LIB_SECURITY_LOADED="true"

# =============================================================================
# Constants
# =============================================================================

# Secret patterns for redaction (regex)
# Order: most specific first to avoid partial matches
readonly _SECRET_PATTERNS=(
  'sk-ant-api[0-9A-Za-z_-]{20,}'     # Anthropic API keys
  'sk-proj-[0-9A-Za-z_-]{20,}'        # OpenAI project keys
  'sk-[0-9A-Za-z_-]{20,}'             # OpenAI API keys (general)
  'ghp_[0-9A-Za-z]{36,}'              # GitHub personal access tokens
  'gho_[0-9A-Za-z]{36,}'              # GitHub OAuth tokens
  'ghs_[0-9A-Za-z]{36,}'              # GitHub server tokens
  'ghr_[0-9A-Za-z]{36,}'              # GitHub refresh tokens
  'AKIA[0-9A-Z]{16}'                  # AWS access key IDs
  'eyJ[0-9A-Za-z_-]{10,}\.[0-9A-Za-z_-]{10,}\.[0-9A-Za-z_-]{10,}' # JWT tokens
)

# Sensitive file patterns (deny list for output audit)
readonly SENSITIVE_FILE_PATTERNS=(
  '.env'
  '.env.*'
  '*.pem'
  '*.key'
  '*.p12'
  '*.pfx'
  'credentials.json'
  'service-account*.json'
  '.npmrc'
  '.pypirc'
  'id_rsa'
  'id_ed25519'
  'id_ecdsa'
  '.netrc'
  '.git/config'
  '.docker/config.json'
)

# Maximum pattern length (skip overlong patterns from config)
readonly _MAX_PATTERN_LENGTH=200

# =============================================================================
# Auth Management
# =============================================================================

# Check if OPENAI_API_KEY is available in the environment.
# Env-only auth: never reads .env files, never calls codex login.
# Returns: 0 if auth available, 1 otherwise
ensure_codex_auth() {
  if [[ -n "${OPENAI_API_KEY:-}" ]]; then
    return 0
  fi
  return 1
}

# =============================================================================
# Secret Redaction
# =============================================================================

# Build combined sed pattern from secret patterns array + config patterns.
# Outputs a sed script to stdout.
_build_redaction_sed() {
  local config_file="${1:-.loa.config.yaml}"

  for pattern in "${_SECRET_PATTERNS[@]}"; do
    echo "s/${pattern}/[REDACTED]/g"
  done

  # Load additional patterns from config if available
  if [[ -f "$config_file" ]] && command -v yq &>/dev/null; then
    local extra_patterns
    extra_patterns=$(yq eval '.flatline_protocol.secret_scanning.patterns[]? // empty' "$config_file" 2>/dev/null) || true
    if [[ -n "$extra_patterns" ]]; then
      while IFS= read -r pat; do
        if [[ ${#pat} -gt $_MAX_PATTERN_LENGTH ]]; then
          echo "# SKIPPED: pattern >$_MAX_PATTERN_LENGTH chars: ${pat:0:30}..." >&2
          continue
        fi
        [[ -n "$pat" ]] && echo "s/${pat}/[REDACTED]/g"
      done <<< "$extra_patterns"
    fi
  fi
}

# Redact secrets from content.
# For JSON: uses jq to redact string VALUES only (never keys).
#   Post-redaction structural diff verifies key count unchanged.
# For text: uses sed with pattern matching.
# Args: content [format] [config_file]
#   format: "json" or "text" (default: auto-detect)
#   config_file: path to .loa.config.yaml (default: .loa.config.yaml)
# Outputs: redacted content to stdout
# Returns: 0 on success, 1 on redaction corruption detected
redact_secrets() {
  local content="$1"
  local format="${2:-auto}"
  local config_file="${3:-.loa.config.yaml}"

  # Auto-detect format
  if [[ "$format" == "auto" ]]; then
    if echo "$content" | jq empty 2>/dev/null; then
      format="json"
    else
      format="text"
    fi
  fi

  if [[ "$format" == "json" ]]; then
    _redact_json "$content" "$config_file"
  else
    _redact_text "$content" "$config_file"
  fi
}

# Internal: Redact secrets from JSON content using jq.
# Only redacts string values, never keys.
# Verifies structural integrity post-redaction.
_redact_json() {
  local content="$1"
  local config_file="$2"

  # Count keys before redaction
  local pre_key_count
  pre_key_count=$(echo "$content" | jq '[paths(scalars)] | length' 2>/dev/null) || pre_key_count=0

  # Build jq filter that walks all string values and applies redaction
  # NOTE: Backslashes must be double-escaped for jq string literals
  # (jq uses JSON string escaping — only \\, \", \n, \t, \uXXXX are valid)
  local jq_filter='walk(if type == "string" then'
  for pattern in "${_SECRET_PATTERNS[@]}"; do
    local escaped="${pattern//\\/\\\\}"
    jq_filter+=" gsub(\"${escaped}\"; \"[REDACTED]\") |"
  done
  # Load extra patterns from config
  if [[ -f "$config_file" ]] && command -v yq &>/dev/null; then
    local extra_patterns
    extra_patterns=$(yq eval '.flatline_protocol.secret_scanning.patterns[]? // empty' "$config_file" 2>/dev/null) || true
    if [[ -n "$extra_patterns" ]]; then
      while IFS= read -r pat; do
        if [[ -n "$pat" && ${#pat} -le $_MAX_PATTERN_LENGTH ]]; then
          local escaped_pat="${pat//\\/\\\\}"
          jq_filter+=" gsub(\"${escaped_pat}\"; \"[REDACTED]\") |"
        fi
      done <<< "$extra_patterns"
    fi
  fi
  # Remove trailing pipe and close the walk
  jq_filter="${jq_filter%|}"
  jq_filter+=' else . end)'

  local redacted
  if ! redacted=$(echo "$content" | jq "$jq_filter" 2>/dev/null) || [[ -z "$redacted" ]]; then
    echo "[gpt-review-security] ERROR: jq redaction failed, returning original" >&2
    echo "$content"
    return 1
  fi

  # Validate JSON integrity post-redaction
  if ! echo "$redacted" | jq empty 2>/dev/null; then
    echo "[gpt-review-security] ERROR: Redaction produced invalid JSON" >&2
    echo "$content"
    return 1
  fi

  # Verify key count unchanged (structural diff)
  local post_key_count
  post_key_count=$(echo "$redacted" | jq '[paths(scalars)] | length' 2>/dev/null) || post_key_count=0

  if [[ "$pre_key_count" != "$post_key_count" ]]; then
    echo "[gpt-review-security] ERROR: Redaction changed key count ($pre_key_count → $post_key_count)" >&2
    echo "$content"
    return 1
  fi

  echo "$redacted"
}

# Internal: Redact secrets from text content using sed.
_redact_text() {
  local content="$1"
  local config_file="$2"

  local sed_script
  sed_script=$(_build_redaction_sed "$config_file")

  echo "$content" | sed -E -f <(echo "$sed_script")
}

# =============================================================================
# Log Filtering
# =============================================================================

# Filter sensitive content from log output (stderr).
# Applies same redaction patterns as redact_secrets but in text mode.
# Args: input (string to filter)
# Outputs: filtered string to stdout
redact_log_output() {
  local input="$1"
  _redact_text "$input" "${CONFIG_FILE:-.loa.config.yaml}"
}

# =============================================================================
# Sensitive File Detection
# =============================================================================

# Check if a file path matches the sensitive file deny list.
# Args: filepath
# Returns: 0 if sensitive, 1 if safe
is_sensitive_file() {
  local filepath="$1"
  local basename
  basename=$(basename "$filepath")

  for pattern in "${SENSITIVE_FILE_PATTERNS[@]}"; do
    case "$pattern" in
      *.*)
        # Glob pattern — match against basename
        # shellcheck disable=SC2254
        case "$basename" in
          $pattern) return 0 ;;
        esac
        ;;
      *)
        # Exact match — match against basename or path suffix
        if [[ "$basename" == "$pattern" ]] || [[ "$filepath" == *"/$pattern" ]]; then
          return 0
        fi
        ;;
    esac
  done

  return 1
}
