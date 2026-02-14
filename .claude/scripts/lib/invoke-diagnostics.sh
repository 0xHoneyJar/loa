#!/usr/bin/env bash
# invoke-diagnostics.sh — Secure error diagnostics for model-invoke calls
# Version: 1.0.0
#
# Functions:
#   setup_invoke_log     — create per-invocation temp log (mktemp + chmod 600)
#   cleanup_invoke_log   — remove log on success (via trap EXIT)
#   redact_secrets       — strip API keys and tokens from log output
#   log_invoke_failure   — print one-line error + pointer to log file
#
# Usage:
#   source "$SCRIPT_DIR/lib/invoke-diagnostics.sh"
#   INVOKE_LOG=$(setup_invoke_log "flatline-phase1")
#   trap 'cleanup_invoke_log "$INVOKE_LOG"' EXIT
#   ... run model-invoke 2>> "$INVOKE_LOG" ...
#   # On failure: log_invoke_failure "$exit_code" "$INVOKE_LOG" "$timeout_seconds"

set -euo pipefail

# =============================================================================
# redact_secrets
# =============================================================================
#
# Redact known secret patterns from stdin.
# Expanded patterns: sk-*, ghp_*, gho_*, ghs_*, ghr_*, Bearer, Authorization,
# AKIA* (AWS), eyJ* (JWT).

redact_secrets() {
  # Pattern coverage:
  #   sk-*     — OpenAI (sk-proj-*), Anthropic (sk-ant-*), generic (sk-*)
  #   ghp_*    — GitHub Personal Access Tokens
  #   gho_*    — GitHub OAuth tokens
  #   ghs_*    — GitHub App installation tokens
  #   ghr_*    — GitHub Refresh tokens
  #   Bearer   — OAuth/JWT Bearer tokens in headers
  #   Authorization — Full Authorization header values
  #   AKIA*    — AWS IAM access key IDs
  #   eyJ*     — JWT/JWS tokens (base64-encoded JSON header starting with {"...)
  #
  # Pattern Maintenance: When new model providers are added to the Hounfour
  # routing layer, add their key prefixes here (e.g., xai-* for X.AI).
  sed -E \
    -e 's/sk-[A-Za-z0-9_-]{20,}/sk-***REDACTED***/g' \
    -e 's/ghp_[A-Za-z0-9]{36}/ghp_***REDACTED***/g' \
    -e 's/gho_[A-Za-z0-9]{36}/gho_***REDACTED***/g' \
    -e 's/ghs_[A-Za-z0-9]{36}/ghs_***REDACTED***/g' \
    -e 's/ghr_[A-Za-z0-9]{36}/ghr_***REDACTED***/g' \
    -e 's/(Bearer )[A-Za-z0-9._-]+/\1***REDACTED***/g' \
    -e 's/(Authorization: )[A-Za-z0-9._: -]+/\1***REDACTED***/g' \
    -e 's/AKIA[A-Z0-9]{16}/AKIA***REDACTED***/g' \
    -e 's/eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]*/eyJ***REDACTED***/g'
}

# =============================================================================
# setup_invoke_log
# =============================================================================
#
# Create a per-invocation temp log file with secure permissions.
#
# Usage:
#   INVOKE_LOG=$(setup_invoke_log "flatline-phase1")
#   INVOKE_LOG=$(setup_invoke_log "gpt-review-call-1")
#
# Returns: Path to the created temp file.

setup_invoke_log() {
  local suffix="${1:-invoke}"
  local log_file
  log_file=$(mktemp "${TMPDIR:-/tmp}/loa-${suffix}-XXXXXX.log")
  chmod 600 "$log_file"
  echo "$log_file"
}

# =============================================================================
# cleanup_invoke_log
# =============================================================================
#
# Remove the invoke log file. Call from trap EXIT on success.
# On failure, the log is preserved for debugging.
#
# Usage:
#   trap 'cleanup_invoke_log "$INVOKE_LOG"' EXIT

cleanup_invoke_log() {
  local log_file="${1:-}"
  if [[ -n "$log_file" ]] && [[ -f "$log_file" ]]; then
    rm -f "$log_file"
  fi
}

# =============================================================================
# log_invoke_failure
# =============================================================================
#
# Print a one-line error message with pointer to the log file.
# Includes timeout context if provided.
#
# Usage:
#   log_invoke_failure "$exit_code" "$INVOKE_LOG"
#   log_invoke_failure "$exit_code" "$INVOKE_LOG" "120"

log_invoke_failure() {
  local exit_code="$1"
  local log_file="${2:-}"
  local timeout_seconds="${3:-}"

  local timeout_msg=""
  if [[ -n "$timeout_seconds" ]] && [[ "$exit_code" -eq 3 ]]; then
    timeout_msg=" (timed out after ${timeout_seconds}s)"
  fi

  echo "ERROR: model-invoke failed (exit $exit_code)${timeout_msg}." >&2
  if [[ -n "$log_file" ]] && [[ -f "$log_file" ]]; then
    echo "  Details: $log_file" >&2
  fi
}
