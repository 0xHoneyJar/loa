#!/usr/bin/env bash
# =============================================================================
# lib-content.sh — Shared content processing functions
# =============================================================================
# Version: 1.0.0
# Extracted from gpt-review-api.sh to avoid eval+sed import fragility.
# See: Bridgebuilder Review Finding #1 (PR #235)
#
# Used by:
#   - gpt-review-api.sh (original home of these functions)
#   - adversarial-review.sh (cross-model dissent)
#
# Functions:
#   file_priority <filepath>       → 0-3 (P0=security-critical, P3=docs)
#   estimate_tokens <content>      → approximate token count
#   prepare_content <content> <budget> → priority-truncated content
#
# Design decision: These functions were originally in gpt-review-api.sh.
# adversarial-review.sh needed them but couldn't `source` gpt-review-api.sh
# because it calls main() on the last line. The eval+sed workaround
# (stripping main via sed before eval) was brittle — if gpt-review-api.sh
# changed its last line format, the import would silently execute main().
# Extracting into a shared library is the Google/Chromium pattern for
# shell function reuse. — Bridgebuilder Review, Finding #1
#
# IMPORTANT: This file must NOT call any function at the top level.
# It is designed to be sourced by other scripts.

# Guard against double-sourcing
if [[ "${_LIB_CONTENT_LOADED:-}" == "true" ]]; then
  return 0 2>/dev/null || true
fi
_LIB_CONTENT_LOADED="true"

# =============================================================================
# File Priority Classification
# =============================================================================
# Priority levels for diff content ordering:
# P0: Security-critical (auth, crypto, middleware, shell scripts, .claude/)
# P1: Business logic (source files, excluding tests)
# P2: Config and CI (YAML, JSON, Dockerfiles)
# P3: Docs and tests (markdown, test files, assets)

file_priority() {
  local filepath="$1"

  # System zone is always P0
  if [[ "$filepath" == .claude/* ]]; then
    echo 0; return
  fi

  case "$filepath" in
    # P0: Security-critical
    *.sh|*/auth/*|*/security/*|*/crypto/*|*.env*|*/api/routes/*|*/middleware/*)
      echo 0 ;;
    # P1: Business logic (but tests drop to P3)
    *.ts|*.js|*.tsx|*.jsx|*.py|*.go|*.rs)
      if [[ "$filepath" == *test* || "$filepath" == *spec* || "$filepath" == *__tests__* ]]; then
        echo 3
      else
        echo 1
      fi
      ;;
    # P2: Config and CI
    *.yml|*.yaml|*.json|*.toml|*.lock|Dockerfile*|*.Dockerfile)
      echo 2 ;;
    # P3: Docs, assets, styles
    *.md|*.txt|*.svg|*.png|*.jpg|*.css|*.scss)
      echo 3 ;;
    *)
      echo 2 ;;
  esac
}

# =============================================================================
# Token Estimation
# =============================================================================
# Code-aware estimation: bytes/3 for code content (diffs, source files).
# Code has shorter tokens than prose due to special characters, operators,
# and short identifiers. The industry standard is ~3.5 bytes/token for code
# vs ~4 bytes/token for English prose.
#
# Design decision: Using bytes/3 (conservative) rather than bytes/4 (optimistic)
# because underestimating tokens causes silent truncation at the API layer,
# while overestimating just leaves unused headroom. Combined with the 80%
# safety margin (D-009), this gives reliable budget enforcement.
# — Bridgebuilder Review, Finding #5

estimate_tokens() {
  local content="$1"
  local bytes
  bytes=$(printf '%s' "$content" | wc -c)
  echo $(( bytes / 3 ))
}

# =============================================================================
# Priority-Based Content Preparation
# =============================================================================
# For large diffs, splits by file, sorts by priority, truncates at token budget.
# This prevents silent token-limit truncation by the API and ensures
# security-critical files are always reviewed first.

# Prepare content with priority-based truncation for large diffs
# Args: $1 = raw content, $2 = max token budget
# If content fits budget, passes through unchanged.
# If over budget, parses diff into per-file sections, sorts by priority,
# includes highest-priority files first, appends summary of skipped files.
prepare_content() {
  local raw_content="$1"
  local max_tokens="${2:-30000}"

  local token_count
  token_count=$(estimate_tokens "$raw_content")

  # If content fits, return as-is
  if [[ $token_count -le $max_tokens ]]; then
    printf '%s' "$raw_content"
    return 0
  fi

  # Log function — use caller's log if available, otherwise stderr
  local _log_fn="echo >&2"
  if type log &>/dev/null; then
    _log_fn="log"
  fi
  $_log_fn "Content exceeds token budget (${token_count} > ${max_tokens}). Applying priority-based truncation."

  # Parse diff into per-file sections at "diff --git" boundaries
  local temp_dir
  temp_dir=$(mktemp -d)
  chmod 700 "$temp_dir"

  local current_file="" current_content="" file_index=0

  while IFS= read -r line; do
    if [[ "$line" =~ ^diff\ --git\ a/(.+)\ b/ ]]; then
      # Save previous file section
      if [[ -n "$current_file" ]]; then
        local pri
        pri=$(file_priority "$current_file")
        printf '%d\t%s\t%d\n' "$pri" "$current_file" "$file_index" >> "$temp_dir/manifest"
        printf '%s' "$current_content" > "$temp_dir/chunk_${file_index}"
        ((file_index++))
      fi
      current_file="${BASH_REMATCH[1]}"
      current_content="$line"
    else
      current_content+=$'\n'"$line"
    fi
  done <<< "$raw_content"

  # Save last file section
  if [[ -n "$current_file" ]]; then
    local pri
    pri=$(file_priority "$current_file")
    printf '%d\t%s\t%d\n' "$pri" "$current_file" "$file_index" >> "$temp_dir/manifest"
    printf '%s' "$current_content" > "$temp_dir/chunk_${file_index}"
    ((file_index++))
  fi

  # If no diff structure found (not a diff file), truncate raw content
  if [[ ! -f "$temp_dir/manifest" ]]; then
    rm -rf "$temp_dir"
    $_log_fn "No diff structure detected. Truncating raw content to budget."
    printf '%s' "$raw_content" | head -c $(( max_tokens * 3 ))
    return 0
  fi

  # Review scope filtering — exclude files that are out of scope (#303)
  local scope_excluded=0
  local review_scope_script
  review_scope_script="$(dirname "${BASH_SOURCE[0]}")/review-scope.sh"
  if [[ -f "$review_scope_script" ]]; then
    # Source the review-scope functions
    source "$review_scope_script"
    detect_zones
    load_reviewignore

    # Filter manifest: remove excluded files
    local filtered_manifest=""
    while IFS=$'\t' read -r priority filepath chunk_idx; do
      if is_excluded "$filepath"; then
        ((scope_excluded++))
        rm -f "$temp_dir/chunk_${chunk_idx}"
      else
        filtered_manifest+="${priority}"$'\t'"${filepath}"$'\t'"${chunk_idx}"$'\n'
      fi
    done < "$temp_dir/manifest"
    printf '%s' "$filtered_manifest" > "$temp_dir/manifest"

    if [[ $scope_excluded -gt 0 ]]; then
      $_log_fn "Review scope: excluded $scope_excluded out-of-scope files"
    fi
  fi

  # Sort by priority (lowest number = highest importance)
  local sorted_manifest
  sorted_manifest=$(sort -t$'\t' -k1,1n "$temp_dir/manifest")

  # Build output up to token budget
  local output="" current_tokens=0 included=0
  local -a skipped_files=()

  while IFS=$'\t' read -r priority filepath chunk_idx; do
    local chunk_content
    chunk_content=$(cat "$temp_dir/chunk_${chunk_idx}")
    local chunk_tokens
    chunk_tokens=$(estimate_tokens "$chunk_content")

    if [[ $(( current_tokens + chunk_tokens )) -le $max_tokens ]]; then
      output+="$chunk_content"$'\n'
      current_tokens=$(( current_tokens + chunk_tokens ))
      ((included++))
    else
      skipped_files+=("P${priority}: ${filepath}")
    fi
  done <<< "$sorted_manifest"

  # Append summary of skipped files
  if [[ ${#skipped_files[@]} -gt 0 ]]; then
    output+=$'\n'"--- TRUNCATED: ${#skipped_files[@]} lower-priority file(s) omitted (token budget: ${max_tokens}) ---"$'\n'
    for sf in "${skipped_files[@]}"; do
      output+="  $sf"$'\n'
    done
    $_log_fn "Included $included files, skipped ${#skipped_files[@]} lower-priority files"
  fi

  rm -rf "$temp_dir"
  printf '%s' "$output"
}
