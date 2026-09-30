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

# A chunk's head at a hunk boundary: the byte cut, trimmed back to drop the hunk the cut landed in — unless that
# would leave no hunk at all (cycle-126 sprint-248, thirteenth / fourteenth run)
_lc_log() { printf '%s\n' "$*" >&2; }   # prepare_content's fallback logger (b1 C-004)
_lc_cut_partial() {  # <chunk file> <max bytes> <out file> → writes the partial; prints `hunk` (cut at a hunk boundary) or `mid`
                     # (the cut fell inside the first hunk: the partial ends on a line boundary and the last hunk is incomplete —
                     # fifteenth run, b1 C-001: never mid-line, never a marker that says every hunk is whole)
  local partial trimmed
  partial=$(head -c "$2" "$1")
  trimmed="${partial%$'\n@@ '*}"
  if [[ "$trimmed" != "$partial" && $(_lc_hunk_count "$trimmed") -gt 0 ]]; then
    printf '%s' "$trimmed" > "$3"; printf 'hunk'
  else
    # a budget that lands before the first newline holds no whole line: nothing is shown rather than a fragment (eighteenth
    # run, b1 DISS-002: `${partial%$'\n'*}` trims nothing when there is no newline)
    if [[ "$partial" == *$'\n'* ]]; then printf '%s' "${partial%$'\n'*}" > "$3"; else : > "$3"; fi
    printf 'mid'
  fi
}
_lc_hunk_count() {  # <text> → the number of @@ hunk headers, always one number (grep -c prints 0 AND exits 1 on none)
  local c; c=$(printf '%s\n' "$1" | grep -c '^@@ ' 2>/dev/null); [[ "$c" =~ ^[0-9]+$ ]] || c=0; printf '%s' "$c"
}

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

  # Log function — the caller's `log` when it is a shell FUNCTION, else our own stderr writer (nineteenth run, b1 C-004: a string
  # with a redirection in it is not a redirection after expansion — `$_log_fn msg` ran `echo '>&2' msg` INTO the payload; and
  # `type log` would pick up macOS's /usr/bin/log)
  local _log_fn
  if declare -F log >/dev/null 2>&1; then _log_fn=log; else _log_fn=_lc_log; fi
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
  sorted_manifest=$(sort -s -t$'\t' -k1,1n "$temp_dir/manifest")   # (stable: ties keep the diff's order, not the path's — fifteenth run, b1 C-002)
  # Every parsed file excluded by the review scope: an empty payload and a log line, never a `cat chunk_` under errexit
  # (sixteenth run, b1 DISS-001)
  if [[ -z "$(printf '%s' "$sorted_manifest" | tr -d '[:space:]')" ]]; then
    $_log_fn "Review scope excluded every file of the diff — nothing to review"
    rm -rf "$temp_dir"
    printf ''
    return 0
  fi

  # Build output up to token budget
  local output="" current_tokens=0 included=0
  local -a skipped_files=()

  # The top-priority file that does not fit whole is shown FIRST, partially, within three quarters of the budget — a
  # lower-priority file never displaces the file the review is about, and a voice never reviews an incomplete diff as
  # clean without the PARTIAL marker (cycle-126 sprint-248, thirteenth run c1 C-001 / fourteenth run b C-002)
  # the candidate is the FIRST row, in priority order, whose chunk does not fit whole — not the first row (sixteenth run,
  # b1 C-002: a small P0 file ahead of a large one must not hide the large one), and not only at the top tier (nineteenth
  # run, b1 C-002: a large P1 file behind a small P0 one was dropped whole with three quarters of the budget unused); the
  # reservation below is computed against the rows at or above the candidate's own priority
  local top_pri="" top_path="" top_idx="" top_partial_done=0 c_pri c_path c_idx
  while IFS=$'\t' read -r c_pri c_path c_idx; do
    [[ -n "$c_idx" && -f "$temp_dir/chunk_${c_idx}" ]] || continue
    if (( $(estimate_tokens "$(cat "$temp_dir/chunk_${c_idx}")") > max_tokens )); then top_pri="$c_pri"; top_path="$c_path"; top_idx="$c_idx"; break; fi
  done <<< "$sorted_manifest"
  if [[ -n "$top_idx" ]]; then
    # the reservation is what the other files AT THE TOP PRIORITY that fit leave over, clamped to a quarter … three quarters
    # of the budget — a same-priority sibling that used to be reviewed whole is not displaced by a partial view of one large
    # file (fifteenth run, b1 C-002), and a lower-priority row never shrinks the view of the file the review is about
    # (sixteenth run, b1 C-001)
    local others=0 o_pri o_path o_idx o_tok reserve partial kept total how
    while IFS=$'\t' read -r o_pri o_path o_idx; do
      [[ -n "$o_idx" && "$o_idx" != "$top_idx" && -f "$temp_dir/chunk_${o_idx}" ]] || continue
      [[ "$o_pri" -le "$top_pri" ]] || continue
      o_tok=$(estimate_tokens "$(cat "$temp_dir/chunk_${o_idx}")")
      (( o_tok <= max_tokens )) && others=$(( others + o_tok ))
    done <<< "$sorted_manifest"
    reserve=$(( max_tokens - others ))
    (( reserve > max_tokens * 3 / 4 )) && reserve=$(( max_tokens * 3 / 4 ))
    (( reserve < max_tokens / 4 )) && reserve=$(( max_tokens / 4 ))
    how=$(_lc_cut_partial "$temp_dir/chunk_${top_idx}" $(( reserve * 3 )) "$temp_dir/partial_${top_idx}")
    partial=$(cat "$temp_dir/partial_${top_idx}")
    total=$(_lc_hunk_count "$(cat "$temp_dir/chunk_${top_idx}")"); kept=$(_lc_hunk_count "$partial")
    output+="$partial"$'\n'
    if [[ "$how" == "mid" && $total -gt 0 ]]; then   # (a chunk with no hunk header at all is just cut: nothing to call mid-way)
      output+=$'\n'"--- PARTIAL: ${top_path} shown up to the token budget (${kept} of ${total} hunks, the last one cut mid-way; token budget: ${max_tokens}) — split the diff for a full review ---"$'\n'
    else
      output+=$'\n'"--- PARTIAL: ${top_path} shown up to the token budget (${kept} of ${total} hunks; token budget: ${max_tokens}) — split the diff for a full review ---"$'\n'
    fi
    current_tokens=$(estimate_tokens "$partial"); included=1; top_partial_done=1
    $_log_fn "Top-priority file ${top_path} exceeds the token budget: shown partially (${kept} of ${total} hunks${how:+, cut $how})"
  fi

  while IFS=$'\t' read -r priority filepath chunk_idx; do
    [[ -n "$chunk_idx" ]] || continue
    [[ $top_partial_done -eq 1 && "$chunk_idx" == "$top_idx" ]] && continue
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
