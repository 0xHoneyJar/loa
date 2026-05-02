#!/usr/bin/env bash
# =============================================================================
# lib-provider-parse.sh — canonical parser for "provider:model-id" strings.
#
# Cycle-096 Sprint 1 Task 1.1 (closes Flatline v1.1 SKP-006).
# Single source of truth shared across all bash callsites that split a
# provider:model-id string. Splits on the FIRST colon only — everything
# after is the literal model_id, including any further colons (required
# for Bedrock inference profile IDs like us.anthropic.claude-haiku-4-5-20251001-v1:0).
#
# This file is meant to be SOURCED, not executed directly. Sourcing has no
# side effects (no main function, no I/O at top level).
#
# SDD reference: §5.4 Centralized Parser Contract.
# =============================================================================

# Guard against double-sourcing (matches lib-security.sh pattern).
if [[ "${_LIB_PROVIDER_PARSE_LOADED:-}" == "true" ]]; then
  return 0 2>/dev/null || true
fi
_LIB_PROVIDER_PARSE_LOADED="true"

# parse_provider_model_id <input> <provider_out_var> <model_id_out_var>
#
# Splits <input> on the FIRST colon. Writes the provider half into the
# variable named by <provider_out_var> and the model_id half into the
# variable named by <model_id_out_var>.
#
# Exit codes:
#   0 — success; output variables populated
#   2 — malformed input (empty input, missing colon, empty provider, or
#       empty model_id); stderr carries an actionable message
#
# Behavior contract (cross-language test fixture in
# tests/integration/parser-cross-language.bats; per SDD §5.4):
#
#   "anthropic:claude-opus-4-7"        → ("anthropic", "claude-opus-4-7")        exit 0
#   "bedrock:us.anthropic.claude-opus-4-7" → ("bedrock", "us.anthropic.claude-opus-4-7") exit 0
#   "openai:gpt-5.5-pro"               → ("openai", "gpt-5.5-pro")               exit 0
#   "google:gemini-3.1-pro-preview"    → ("google", "gemini-3.1-pro-preview")    exit 0
#   "provider:multi:colon:value"       → ("provider", "multi:colon:value")       exit 0
#   ""                                 → error                                   exit 2
#   ":model-id"                        → error (empty provider)                  exit 2
#   "provider:"                        → error (empty model)                     exit 2
#   "no-colon-at-all"                  → error (missing colon)                   exit 2
parse_provider_model_id() {
  local input="${1-}"
  local provider_out_var="${2-}"
  local model_id_out_var="${3-}"

  if [[ -z "$provider_out_var" || -z "$model_id_out_var" ]]; then
    echo "parse_provider_model_id: usage: parse_provider_model_id <input> <provider_out_var> <model_id_out_var>" >&2
    return 2
  fi

  if [[ -z "$input" ]]; then
    echo "parse_provider_model_id: empty input" >&2
    return 2
  fi

  if [[ "$input" != *:* ]]; then
    echo "parse_provider_model_id: missing colon separator in '$input'" >&2
    return 2
  fi

  # Split on FIRST colon only. ${input%%:*} = up to first colon (provider).
  # ${input#*:} = everything after first colon (model_id, including any further colons).
  local provider="${input%%:*}"
  local model_id="${input#*:}"

  if [[ -z "$provider" ]]; then
    echo "parse_provider_model_id: empty provider in '$input'" >&2
    return 2
  fi

  if [[ -z "$model_id" ]]; then
    echo "parse_provider_model_id: empty model_id in '$input'" >&2
    return 2
  fi

  # Bash 4.2+ printf -v writes to named variable without eval.
  printf -v "$provider_out_var" '%s' "$provider"
  printf -v "$model_id_out_var" '%s' "$model_id"
  return 0
}
