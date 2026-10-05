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
  local partial trimmed nxt
  # (twenty-fifth run, b1 DISS-C-003: no room for any byte is an empty cut — BSD head refuses `-c 0`)
  if (( $2 <= 0 )); then : > "$3"; printf 'mid'; return 0; fi
  partial=$(head -c "$2" "$1")
  # twenty-third run, b1 DISS-C-001: whole lines first — a cut inside a line (a hunk header's first bytes included) drops that
  # line — then a hunk header (or the end) right after them means their last hunk is complete, and it is kept
  nxt=$(_lc_next5 "$1" "$(printf '%s' "$partial" | LC_ALL=C wc -c)"; printf x) || nxt="x"; nxt="${nxt%x}"
  if [[ -n "$nxt" && "$nxt" != $'\n'* ]]; then
    if [[ "$partial" == *$'\n'* ]]; then partial="${partial%$'\n'*}"; else partial=""; fi
    nxt=$(_lc_next5 "$1" "$(printf '%s' "$partial" | LC_ALL=C wc -c)"; printf x) || nxt="x"; nxt="${nxt%x}"
  fi
  if [[ -z "$nxt" || "$nxt" == $'\n@@ '* ]] && (( $(_lc_hunk_count "$partial") > 0 )); then
    printf '%s' "$partial" > "$3"; printf 'hunk'; return 0
  fi
  trimmed="${partial%$'\n@@ '*}"
  if [[ "$trimmed" != "$partial" && $(_lc_hunk_count "$trimmed") -gt 0 ]]; then
    printf '%s' "$trimmed" > "$3"; printf 'hunk'
  else
    # a budget that lands before the first newline holds no whole line: nothing is shown rather than a fragment (eighteenth
    # run, b1 DISS-002: `${partial%$'\n'*}` trims nothing when there is no newline)
    printf '%s' "$partial" > "$3"   # (whole lines already — twenty-third run, b1 DISS-C-001)
    printf 'mid'
  fi
}
_lc_next5() {  # <file> <bytes before> → the next five bytes, exact; nothing when only newlines are left (the chunk's own end)
  # (thirty-sixth run, b1 DISS-C-001: a substitution strips trailing newlines — five empty lines after the cut read as the end, so a
  # hunk cut before a run of suppressBlankEmpty context lines was counted whole; the caller appends a sentinel for the same reason)
  local n more
  n=$( { tail -c +"$(( $2 + 1 ))" "$1" 2>/dev/null | head -c 5; printf x; } ) || n="x"; n="${n%x}"
  # (thirty-eighth run, b1 DISS-C-001: nothing read while bytes remain — a vanished file, a failing tail — is a failed read, never
  # the chunk's end: `?` is no hunk boundary, so the caller drops the incomplete hunk rather than count it whole)
  if [[ -z "$n" ]]; then
    more=$(LC_ALL=C wc -c < "$1" 2>/dev/null) || more=""; more="${more//[!0-9]/}"
    [[ -n "$more" ]] && (( more <= $2 )) || n="?"
  fi
  if [[ -n "$n" && -z "${n//$'\n'/}" ]]; then
    more=$(tail -c +"$(( $2 + 1 ))" "$1" 2>/dev/null | LC_ALL=C tr -d '\n' | head -c 1 | LC_ALL=C wc -c) || true
    more="${more//[!0-9]/}"; (( ${more:-1} > 0 )) || n=""
  fi
  printf '%s' "$n"
}
_lc_hunk_count() {  # <text> → the number of @@ hunk headers, always one number (grep -c prints 0 AND exits 1 on none)
  # (twenty-first run, b1 DISS-C-001: the assignment itself is guarded — a plain-statement call under errexit, or a substitution
  # under inherit_errexit, must not stop on a text with no hunk header; the function always returns 0)
  local c; c=$(printf '%s\n' "$1" | grep -c '^@@ ' 2>/dev/null) || true; [[ "$c" =~ ^[0-9]+$ ]] || c=0; printf '%s' "$c"
}

# Prepare content with priority-based truncation for large diffs
# Args: $1 = raw content, $2 = max token budget
# If content fits budget, passes through unchanged.
# If over budget, parses diff into per-file sections, sorts by priority,
# includes highest-priority files first, appends summary of skipped files.
_lc_chunk_tok() {  # <temp dir> <chunk index> <outvar> → the chunk's estimate, counted once per prepare_content call: the memo is the
                  # caller's local `_lc_tok` array (twenty-sixth run, b1 DISS-C-001 — the candidate scan, the reservation scan and the
                  # include loop each re-read and re-counted every chunk); printf -v, so the memo survives (a `$(...)` would drop it)
  # a subscript is arithmetic — `$(…)` in it runs: only a number is an index (audit run 1, b1 DISS-C-001), and only a canonical
  # decimal one — `08` is invalid octal there (bd-pw7e LOW-002)
  [[ "$2" =~ ^(0|[1-9][0-9]*)$ ]] || return 1
  [[ -n "${_lc_tok[$2]:-}" ]] || _lc_tok[$2]=$(estimate_tokens "$(cat "$1/chunk_$2")")
  printf -v "$3" '%s' "${_lc_tok[$2]}"
}
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

  # manifest rows are `pri<TAB>idx<TAB>path`, read `read -r pri idx path`: the path takes the rest of the line, so a raw tab in a
  # `diff --git` header never shifts its text into the index (audit run 1, b1 DISS-C-001)
  while IFS= read -r line; do
    if [[ "$line" =~ ^diff\ --git\ a/(.+)\ b/ ]]; then
      # Save previous file section
      if [[ -n "$current_file" ]]; then
        local pri
        pri=$(file_priority "$current_file")
        printf '%d\t%d\t%s\n' "$pri" "$file_index" "$current_file" >> "$temp_dir/manifest"
        printf '%s' "$current_content" > "$temp_dir/chunk_${file_index}"
        ((file_index++)) || true
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
    printf '%d\t%d\t%s\n' "$pri" "$file_index" "$current_file" >> "$temp_dir/manifest"
    printf '%s' "$current_content" > "$temp_dir/chunk_${file_index}"
    ((file_index++)) || true
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
    while IFS=$'\t' read -r priority chunk_idx filepath; do
      [[ "$chunk_idx" =~ ^(0|[1-9][0-9]*)$ ]] || continue
      if is_excluded "$filepath"; then
        ((scope_excluded++)) || true
        rm -f "$temp_dir/chunk_${chunk_idx}"
      else
        filtered_manifest+="${priority}"$'\t'"${chunk_idx}"$'\t'"${filepath}"$'\n'
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
  local output="" current_tokens=0 included=0 inc_low=-1
  local -a skipped_files=()

  # The top-priority file that does not fit whole is shown partially, at its tier's place, within three quarters of the budget — a
  # lower-priority file never displaces the file the review is about, and a voice never reviews an incomplete diff as
  # clean without the PARTIAL marker (cycle-126 sprint-248, thirteenth run c1 C-001 / fourteenth run b C-002)
  # the candidate is the FIRST row, in priority order, whose chunk does not fit whole — not the first row (sixteenth run,
  # b1 C-002: a small P0 file ahead of a large one must not hide the large one), and not only at the top tier (nineteenth
  # run, b1 C-002: a large P1 file behind a small P0 one was dropped whole with three quarters of the budget unused); the
  # reservation below is computed against the rows at or above the candidate's own priority
  # — and not only a row larger than the WHOLE budget (twenty-first run, b1 DISS-C-002: a P0 file that fits the budget alone but
  # not beside the P0 rows ahead of it was dropped whole while a P1 file behind it was shown); the running sum below is the main
  # loop's own include rule up to its first omission
  local top_pri="" top_path="" top_idx="" top_partial_done=0 top_no_room=0 c_pri c_path c_idx c_tok c_run=0
  local -a _lc_tok=()
  while IFS=$'\t' read -r c_pri c_idx c_path; do
    [[ -n "$c_idx" && -f "$temp_dir/chunk_${c_idx}" ]] || continue
    _lc_chunk_tok "$temp_dir" "$c_idx" c_tok || continue
    if (( c_run + c_tok > max_tokens )); then top_pri="$c_pri"; top_path="$c_path"; top_idx="$c_idx"; break; fi
    c_run=$(( c_run + c_tok ))
  done <<< "$sorted_manifest"
  local top_path_log; top_path_log=$(printf '%s' "$top_path" | LC_ALL=C tr -d '\000-\037\177')   # stderr never gets a header's raw controls (bd-pw7e LOW-003)
  if [[ -n "$top_idx" ]]; then
    # the reservation is what the other files AT THE TOP PRIORITY that fit leave over, clamped to a quarter … three quarters
    # of the budget — a same-priority sibling that used to be reviewed whole is not displaced by a partial view of one large
    # file (fifteenth run, b1 C-002), and a lower-priority row never shrinks the view of the file the review is about
    # (sixteenth run, b1 C-001)
    local others=0 o_pri o_path o_idx o_tok reserve partial kept total how
    while IFS=$'\t' read -r o_pri o_idx o_path; do
      [[ -n "$o_idx" && "$o_idx" != "$top_idx" && -f "$temp_dir/chunk_${o_idx}" ]] || continue
      [[ "$o_pri" -le "$top_pri" ]] || continue
      _lc_chunk_tok "$temp_dir" "$o_idx" o_tok || continue
      # what those rows take TOGETHER, by the main loop's greedy rule — two siblings that each fit but not side by side are not
      # reserved twice (twenty-second run, b1 DISS-C-001)
      (( others + o_tok <= max_tokens )) && others=$(( others + o_tok ))
    done <<< "$sorted_manifest"
    # twentieth run, b1 DISS-C-001: no floor — a quarter-budget floor let the partial displace a row at or above its tier that
    # fits whole; what those rows leave over is all it gets (capped at three quarters), and its marker comes out of that
    # share too when there are such rows to protect (b1 DISS-001: the marker is charged to the budget)
    local marker_est
    marker_est=$(estimate_tokens "--- PARTIAL: ${top_path} shown up to the token budget (999 of 999 hunks, the last one cut mid-way; token budget: ${max_tokens}) — split the diff for a full review ---")
    reserve=$(( max_tokens - others ))
    # twenty-fourth run, b1 DISS-C-001: with rows ranked BELOW the top file, the cap bounds the VIEW at three quarters of the budget —
    # with none, the quarter went unspent and the file the review is about was shown shorter; uncapped, the marker comes out of the
    # view's own share. (Thirty-fourth run, b1 DISS-C-001: it is a cap on the view, not a quarter kept for the lower rows — the
    # siblings at its tier come first, whole, then the view; the lower rows get what both leave, nothing once the siblings take a
    # quarter or more. CMP-214 pins the order.)
    local lower=0
    while IFS=$'\t' read -r o_pri o_idx o_path; do
      [[ -n "$o_idx" && "$o_idx" != "$top_idx" && "$o_pri" -gt "$top_pri" ]] && { lower=1; break; }
    done <<< "$sorted_manifest"
    if (( lower )); then
      (( reserve > max_tokens * 3 / 4 )) && reserve=$(( max_tokens * 3 / 4 ))
      if (( others > 0 )); then reserve=$(( reserve - marker_est - 1 ))
      # (thirty-second run, b1 DISS-001: with no sibling to protect the capped view kept its whole share and its marker went on top —
      # over the budget wherever the marker outweighs the quarter left; the view and its marker never exceed the budget)
      elif (( reserve > max_tokens - marker_est - 1 )); then reserve=$(( max_tokens - marker_est - 1 )); fi
    else
      reserve=$(( reserve - marker_est - 1 ))
    fi
    (( reserve < 0 )) && reserve=0
  fi
  # twenty-first run, b1 DISS-001: the rows at or above its tier that fit leave no room for even the marker — no partial view is
  # made (a marker-only block placed first would displace a sibling that fits whole); the file is listed as omitted, like any other
  if [[ -n "$top_idx" ]] && (( others > 0 && reserve <= 0 )); then
    $_log_fn "File ${top_path_log} exceeds what the rows that fit leave over: no room for a partial view, listed as omitted"
    top_no_room=1
  elif [[ -n "$top_idx" ]]; then
    how=$(_lc_cut_partial "$temp_dir/chunk_${top_idx}" $(( reserve * 3 )) "$temp_dir/partial_${top_idx}")
    partial=$(cat "$temp_dir/partial_${top_idx}")
    total=$(_lc_hunk_count "$(cat "$temp_dir/chunk_${top_idx}")"); kept=$(_lc_hunk_count "$partial")
    local partial_block="$partial"$'\n'
    if [[ $kept -eq 0 && $total -gt 0 ]]; then   # (twentieth run, b1 C-003: not even one hunk header fit — only the marker is sent)
      partial_block="--- PARTIAL: ${top_path}: no hunk fit within the token budget (0 of ${total} hunks shown; token budget: ${max_tokens}) — split the diff for a full review ---"$'\n'
    elif [[ "$how" == "mid" && $total -gt 0 ]]; then   # (a chunk with no hunk header at all is just cut: nothing to call mid-way)
      partial_block+=$'\n'"--- PARTIAL: ${top_path} shown up to the token budget (${kept} of ${total} hunks, the last one cut mid-way; token budget: ${max_tokens}) — split the diff for a full review ---"$'\n'
    else
      partial_block+=$'\n'"--- PARTIAL: ${top_path} shown up to the token budget (${kept} of ${total} hunks; token budget: ${max_tokens}) — split the diff for a full review ---"$'\n'
    fi
    top_partial_done=1
    $_log_fn "Top-priority file ${top_path_log} exceeds the token budget: shown partially (${kept} of ${total} hunks${how:+, cut $how})"
  fi

  while IFS=$'\t' read -r priority chunk_idx filepath; do
    # (the pre-scans' guard: a row with no chunk file is never read — audit run 1, b1 DISS-C-001)
    [[ -n "$chunk_idx" && -f "$temp_dir/chunk_${chunk_idx}" ]] || continue
    # the partial view sits at its own tier's place (twentieth run, b1 DISS-C-001), charged with its marker, always shown
    if [[ $top_partial_done -eq 1 && "$chunk_idx" == "$top_idx" ]]; then
      output+="$partial_block"; current_tokens=$(( current_tokens + $(estimate_tokens "$partial_block") )); ((included++)) || true
      continue
    fi
    local chunk_content
    chunk_content=$(cat "$temp_dir/chunk_${chunk_idx}")
    local chunk_tokens
    _lc_chunk_tok "$temp_dir" "$chunk_idx" chunk_tokens || continue

    if [[ $(( current_tokens + chunk_tokens )) -le $max_tokens ]]; then
      output+="$chunk_content"$'\n'
      current_tokens=$(( current_tokens + chunk_tokens ))
      ((included++)) || true   # (twenty-fifth run, b1 DISS-C-004: every counter here is errexit-neutral — from 0 a bare ((x++)) returns 1)
      (( priority > inc_low )) && inc_low=$priority
    else
      skipped_files+=("P${priority}: ${filepath}")
    fi
  done <<< "$sorted_manifest"

  # Append summary of skipped files
  if [[ ${#skipped_files[@]} -gt 0 ]]; then
    # (twenty-third run, b1 DISS-C-002: the file dropped for want of room for a partial view is the one the review is about — the
    # footer never calls it lower-priority)
    if [[ $top_no_room -eq 1 ]] && (( inc_low < 0 || inc_low >= top_pri )); then   # (a shown file at its tier or below)
      output+=$'\n'"--- TRUNCATED: ${#skipped_files[@]} file(s) omitted, among them P${top_pri}: ${top_path} — the highest-priority file over the budget, with no room for a partial view (token budget: ${max_tokens}) — split the diff for a full review ---"$'\n'
    else
      output+=$'\n'"--- TRUNCATED: ${#skipped_files[@]} lower-priority file(s) omitted (token budget: ${max_tokens}) ---"$'\n'
    fi
    for sf in "${skipped_files[@]}"; do
      output+="  $sf"$'\n'
    done
    $_log_fn "Included $included files, skipped ${#skipped_files[@]} lower-priority files"
  fi

  rm -rf "$temp_dir"
  printf '%s' "$output"
}
