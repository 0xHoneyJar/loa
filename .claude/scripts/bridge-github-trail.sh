#!/usr/bin/env bash
# bridge-github-trail.sh - GitHub interactions for bridge loop
# Version: 2.0.0
#
# Handles PR comments, PR body updates, and vision link posting
# for each bridge iteration. Gracefully degrades when gh is unavailable.
#
# Subcommands:
#   comment    - Post Bridgebuilder review as PR comment
#   update-pr  - Update PR body with iteration summary table
#   vision     - Post vision link as PR comment
#
# Usage:
#   bridge-github-trail.sh comment --pr 295 --iteration 2 --review-body review.md --bridge-id bridge-xxx
#   bridge-github-trail.sh update-pr --pr 295 --state-file .run/bridge-state.json
#   bridge-github-trail.sh vision --pr 295 --vision-id vision-001 --title "Cross-repo GT hub"
#
# Exit Codes:
#   0 - Success (or graceful degradation)
#   2 - Missing arguments

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/bootstrap.sh"

# =============================================================================
# Usage
# =============================================================================

usage() {
  cat <<'USAGE'
Usage: bridge-github-trail.sh <subcommand> [OPTIONS]

Subcommands:
  comment        Post Bridgebuilder review as PR comment
  update-pr      Update PR body with iteration summary table
  vision         Post vision link as PR comment
  vision-sprint  Post architectural proposals from vision sprint

Options (comment):
  --pr N              PR number (required)
  --iteration N       Iteration number (required)
  --review-body FILE  Path to review markdown (required)
  --bridge-id ID      Bridge ID (required)

Options (update-pr):
  --pr N              PR number (required)
  --state-file FILE   Bridge state JSON (required)

Options (vision):
  --pr N              PR number (required)
  --vision-id ID      Vision entry ID (required)
  --title TEXT        Vision title (required)

Exit Codes:
  0  Success (or graceful degradation)
  2  Missing arguments
USAGE
  exit "${1:-0}"
}

# =============================================================================
# Helpers
# =============================================================================

check_gh() {
  if ! command -v gh &>/dev/null; then
    echo "WARNING: gh CLI not available — skipping GitHub trail" >&2
    return 1
  fi
  return 0
}

# =============================================================================
# Redaction (SDD 3.5.2, Flatline SKP-006)
# =============================================================================

# Gitleaks-inspired patterns for realistic secret detection
# Each pattern: name|regex
REDACT_PATTERNS=(
  'aws_access_key|AKIA[0-9A-Z]{16}'
  'github_pat|ghp_[A-Za-z0-9]{36}'
  'github_oauth|gho_[A-Za-z0-9]{36}'
  'github_app|ghs_[A-Za-z0-9]{36}'
  'github_refresh|ghr_[A-Za-z0-9]{36}'
  'jwt_token|eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}'
  'generic_secret|(api_key|api_secret|apikey|secret_key|access_token|auth_token|private_key)[[:space:]]*[=:][[:space:]]*["'"'"'][A-Za-z0-9+/=_-]{16,}'
)

# Allowlist patterns — known-safe strings that match redaction patterns
# These are checked BEFORE redaction to avoid false positives
ALLOWLIST_PATTERNS=(
  'sha256:[a-f0-9]{64}'
  'hash:[[:space:]]*[a-f0-9]{64}'
  '<!-- @[a-z-]*:[^>]*hash:[a-f0-9]'
  'https://mermaid\.ink/img/[A-Za-z0-9+/=_-]+'
  'data:image/[a-z]+;base64,'
)

# Redact security content from a string
# Reads from stdin, writes redacted content to stdout
# Returns 0 always (redaction is best-effort)
redact_security_content() {
  local content
  content=$(cat; echo x)
  content="${content%x}"

  # Protect allowlisted content with sentinel tokens before redaction
  # Use random salt to prevent collision with real content (BB-015)
  local sentinel_salt
  sentinel_salt=$(head -c 8 /dev/urandom | od -An -tx1 | tr -d ' \n')
  local sentinel_idx=0
  declare -A sentinel_map
  for pattern in "${ALLOWLIST_PATTERNS[@]}"; do
    while IFS= read -r match; do
      if [[ -n "$match" ]]; then
        local sentinel="__ALLOWLIST_${sentinel_salt}_${sentinel_idx}__"
        sentinel_map["$sentinel"]="$match"
        content="${content//$match/$sentinel}"
        sentinel_idx=$((sentinel_idx + 1))
      fi
    done < <(printf '%s' "$content" | grep -oE "$pattern" 2>/dev/null || true)
  done

  # Build combined sed expression for all redaction patterns (single invocation)
  local sed_expr=""
  for entry in "${REDACT_PATTERNS[@]}"; do
    local name="${entry%%|*}"
    local regex="${entry#*|}"
    sed_expr="${sed_expr}s/${regex}/[REDACTED:${name}]/g;"
  done

  if [[ -n "$sed_expr" ]]; then
    content=$(printf '%s' "$content" | sed -E "$sed_expr" 2>/dev/null || printf '%s' "$content")
  fi

  # Restore allowlisted content from sentinels
  for sentinel in "${!sentinel_map[@]}"; do
    content="${content//$sentinel/${sentinel_map[$sentinel]}}"
  done

  printf '%s' "$content"
}

# Post-redaction safety check (Flatline SKP-006)
# Scans for known secret prefixes that should have been caught
# Returns 0 if safe, 1 if secrets detected (blocks posting)
post_redaction_safety_check() {
  local content="$1"
  local unsafe_patterns='(ghp_[A-Za-z0-9]{4}|gho_[A-Za-z0-9]{4}|ghs_[A-Za-z0-9]{4}|ghr_[A-Za-z0-9]{4}|AKIA[0-9A-Z]{4}|eyJ[A-Za-z0-9_-]{8,}\.eyJ)'

  local line_num=0
  local found=false
  while IFS= read -r line; do
    line_num=$((line_num + 1))
    if printf '%s' "$line" | grep -qE "$unsafe_patterns" 2>/dev/null; then
      echo "SECURITY: Post-redaction safety check FAILED at line $line_num" >&2
      found=true
    fi
  done <<< "$content"

  if [[ "$found" == "true" ]]; then
    echo "SECURITY: Blocking PR comment — unredacted secrets detected after redaction pass" >&2
    return 1
  fi
  return 0
}

# =============================================================================
# Size Enforcement (SDD 3.5.1)
# =============================================================================

# Size limits in bytes
SIZE_LIMIT_TRUNCATE=66560    # 65KB - truncate preserving findings JSON
SIZE_LIMIT_FINDINGS_ONLY=262144  # 256KB - findings-only fallback

# Save full review to .run/ with restricted permissions (Flatline SKP-009)
save_full_review() {
  local bridge_id="$1" iteration="$2" content="$3"
  local review_dir="${PROJECT_ROOT:-.}/.run/bridge-reviews"
  mkdir -p "$review_dir"
  local review_file="${review_dir}/${bridge_id}-iter${iteration}-full.md"
  printf '%s' "$content" > "$review_file"
  chmod 0600 "$review_file"
  echo "Full review saved to $review_file" >&2
}

# Enforce size limits on comment body
# Reads full body from stdin, writes enforced body to stdout
# Args: $1 = truncation strategy ("truncate" or "findings-only")
enforce_size_limit() {
  local content
  content=$(cat; echo x)
  content="${content%x}"
  local size=${#content}

  if [[ "$size" -le "$SIZE_LIMIT_TRUNCATE" ]]; then
    printf '%s' "$content"
    return 0
  fi

  # Extract findings block once for reuse in all size branches
  local findings_block=""
  findings_block=$(printf '%s' "$content" | sed -n '/<!-- bridge-findings-start -->/,/<!-- bridge-findings-end -->/p' 2>/dev/null || true)

  if [[ "$size" -gt "$SIZE_LIMIT_FINDINGS_ONLY" ]]; then
    # 256KB emergency fallback — findings-only
    if [[ -n "$findings_block" ]]; then
      echo "WARNING: Review exceeds 256KB ($size bytes) — posting findings-only" >&2
      printf '%s' "$findings_block"
      return 0
    fi
    # No findings block found — truncate instead
    echo "WARNING: Review exceeds 256KB ($size bytes) but no findings block found — truncating" >&2
  else
    echo "WARNING: Review exceeds 65KB ($size bytes) — truncating with findings preserved" >&2
  fi

  if [[ -n "$findings_block" ]]; then
    # Calculate how much prose we can keep
    local findings_size=${#findings_block}
    local budget=$((SIZE_LIMIT_TRUNCATE - findings_size - 200))  # 200 bytes for truncation notice
    if [[ "$budget" -lt 500 ]]; then
      budget=500
    fi
    # Take prose before findings block, truncate, append findings
    local before_findings
    before_findings=$(printf '%s' "$content" | sed '/<!-- bridge-findings-start -->/,$d' 2>/dev/null || true)
    local truncated_prose="${before_findings:0:$budget}"
    printf '%s\n\n> **Note**: Review truncated from %d bytes to fit 65KB limit. Full review saved to .run/\n\n%s' \
      "$truncated_prose" "$size" "$findings_block"
  else
    # No findings block — simple truncation
    local budget=$((SIZE_LIMIT_TRUNCATE - 100))
    printf '%s\n\n> **Note**: Review truncated from %d bytes to fit 65KB limit. Full review saved to .run/' \
      "${content:0:$budget}" "$size"
  fi
}

# =============================================================================
# Retention Policy (Flatline SKP-009)
# =============================================================================

# Clean up bridge reviews older than 30 days
cleanup_old_reviews() {
  local review_dir="${PROJECT_ROOT:-.}/.run/bridge-reviews"
  if [[ ! -d "$review_dir" ]]; then
    return 0
  fi
  local deleted=0
  while IFS= read -r -d '' file; do
    rm -f "$file"
    deleted=$((deleted + 1))
  done < <(find "$review_dir" -name "*.md" -mtime +30 -print0 2>/dev/null)
  if [[ "$deleted" -gt 0 ]]; then
    echo "Cleaned up $deleted bridge reviews older than 30 days" >&2
  fi
}

# =============================================================================
# comment subcommand
# =============================================================================

cmd_comment() {
  local pr="" iteration="" review_body="" bridge_id="" repo=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --pr) pr="$2"; shift 2 ;;
      --iteration) iteration="$2"; shift 2 ;;
      --review-body) review_body="$2"; shift 2 ;;
      --bridge-id) bridge_id="$2"; shift 2 ;;
      --repo) repo="$2"; shift 2 ;;
      *) echo "ERROR: Unknown argument: $1" >&2; exit 2 ;;
    esac
  done

  if [[ -z "$pr" || -z "$iteration" || -z "$review_body" || -z "$bridge_id" ]]; then
    echo "ERROR: comment requires --pr, --iteration, --review-body, --bridge-id" >&2
    exit 2
  fi

  if [[ ! -f "$review_body" ]]; then
    echo "ERROR: Review body file not found: $review_body" >&2
    exit 2
  fi

  check_gh || return 0

  # Build comment with dedup marker
  local marker="<!-- bridge-iteration: ${bridge_id}:${iteration} -->"
  local review_content
  review_content=$(cat "$review_body"; echo x)
  review_content="${review_content%x}"
  local body="${marker}
## Bridge Review — Iteration ${iteration}

**Bridge ID**: \`${bridge_id}\`

${review_content}

---
*Bridge iteration ${iteration} of ${bridge_id}*"

  # Always save full review before any transformation (Flatline SKP-009)
  save_full_review "$bridge_id" "$iteration" "$body"

  # Redact security content (SDD 3.5.2, Flatline SKP-006)
  body=$(printf '%s' "$body" | redact_security_content)

  # Post-redaction safety check — block posting if secrets remain
  if ! post_redaction_safety_check "$body"; then
    echo "ERROR: Comment blocked by post-redaction safety check for iteration $iteration on PR #$pr" >&2
    return 0
  fi

  # Enforce size limits (SDD 3.5.1)
  body=$(printf '%s' "$body" | enforce_size_limit)

  # Check for existing comment with this marker to avoid duplicates
  local existing
  local repo_flag=()
  [[ -n "${repo:-}" ]] && repo_flag=(--repo "$repo")

  existing=$(gh pr view "$pr" "${repo_flag[@]}" --json comments --jq "[.comments[].body | select(contains(\"$marker\"))] | length" 2>/dev/null || echo "0")

  if [[ "$existing" -gt 0 ]]; then
    echo "Skipping: comment for iteration $iteration already exists on PR #$pr"
    return 0
  fi

  printf '%s' "$body" | gh pr comment "$pr" "${repo_flag[@]}" --body-file - 2>/dev/null || {
    echo "WARNING: Failed to post comment to PR #$pr" >&2
    return 0
  }

  echo "Posted bridge review comment for iteration $iteration to PR #$pr"
}

# =============================================================================
# update-pr subcommand
# =============================================================================

cmd_update_pr() {
  local pr="" state_file="" repo=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --pr) pr="$2"; shift 2 ;;
      --state-file) state_file="$2"; shift 2 ;;
      --repo) repo="$2"; shift 2 ;;
      *) echo "ERROR: Unknown argument: $1" >&2; exit 2 ;;
    esac
  done

  if [[ -z "$pr" || -z "$state_file" ]]; then
    echo "ERROR: update-pr requires --pr, --state-file" >&2
    exit 2
  fi

  if [[ ! -f "$state_file" ]]; then
    echo "ERROR: State file not found: $state_file" >&2
    exit 2
  fi

  check_gh || return 0

  # Build summary table from state file
  local bridge_id depth state
  bridge_id=$(jq -r '.bridge_id' "$state_file")
  depth=$(jq '.config.depth' "$state_file")
  state=$(jq -r '.state' "$state_file")

  # Build iteration table rows using single jq invocation
  local table_rows
  table_rows=$(jq -r '.iterations[] | "| \(.iteration) | \(.state) | \(.bridgebuilder.severity_weighted_score // "—") | \(.visions_captured // "—") | \(.sprint_plan_source // "existing") |"' "$state_file" 2>/dev/null || true)

  local flatline_status
  flatline_status=$(jq -r '.flatline.consecutive_below_threshold // 0' "$state_file")

  local total_sprints total_files total_findings total_visions
  total_sprints=$(jq '.metrics.total_sprints_executed // 0' "$state_file")
  total_files=$(jq '.metrics.total_files_changed // 0' "$state_file")
  total_findings=$(jq '.metrics.total_findings_addressed // 0' "$state_file")
  total_visions=$(jq '.metrics.total_visions_captured // 0' "$state_file")

  # Build body using printf for readable template
  local body
  body=$(printf '## Bridge Loop Summary\n\n| Iter | State | Score | Visions | Source |\n|------|-------|-------|---------|--------|\n%s' "$table_rows")

  if [[ "$flatline_status" -gt 0 ]]; then
    body=$(printf '%s\n\n**Flatline**: %s consecutive iterations below threshold' "$body" "$flatline_status")
  fi

  body=$(printf '%s\n\n**Metrics**: %s sprints, %s files changed, %s findings addressed, %s visions captured' \
    "$body" "$total_sprints" "$total_files" "$total_findings" "$total_visions")

  body=$(printf '%s\n\n**Bridge ID**: `%s` | **State**: %s | **Depth**: %s\n<!-- bridge-summary-end -->' \
    "$body" "$bridge_id" "$state" "$depth")

  # Get current PR body and append/update bridge section
  local repo_flag=()
  [[ -n "${repo:-}" ]] && repo_flag=(--repo "$repo")
  local current_body
  current_body=$(gh pr view "$pr" "${repo_flag[@]}" --json body --jq '.body' 2>/dev/null || echo "")

  # Remove old bridge summary if present (between markers)
  local new_body
  if echo "$current_body" | grep -q "## Bridge Loop Summary"; then
    if echo "$current_body" | grep -q "<!-- bridge-summary-end -->"; then
      new_body=$(echo "$current_body" | sed '/## Bridge Loop Summary/,/<!-- bridge-summary-end -->/d')
    else
      new_body=$(echo "$current_body" | sed '/## Bridge Loop Summary/,$d')
    fi
    new_body="${new_body}${body}"
  else
    new_body=$(printf '%s\n\n---\n\n%s' "$current_body" "$body")
  fi

  printf '%s' "$new_body" | gh pr edit "$pr" "${repo_flag[@]}" --body-file - 2>/dev/null || {
    echo "WARNING: Failed to update PR #$pr body" >&2
    return 0
  }

  echo "Updated PR #$pr body with bridge loop summary"
}

# =============================================================================
# vision subcommand
# =============================================================================

cmd_vision() {
  local pr="" vision_id="" title="" repo=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --pr) pr="$2"; shift 2 ;;
      --vision-id) vision_id="$2"; shift 2 ;;
      --title) title="$2"; shift 2 ;;
      --repo) repo="$2"; shift 2 ;;
      *) echo "ERROR: Unknown argument: $1" >&2; exit 2 ;;
    esac
  done

  if [[ -z "$pr" || -z "$vision_id" || -z "$title" ]]; then
    echo "ERROR: vision requires --pr, --vision-id, --title" >&2
    exit 2
  fi

  check_gh || return 0

  local body
  body=$(printf '%s\n%s\n\n%s\n%s\n\n%s' \
    "<!-- bridge-vision: ${vision_id} -->" \
    "### Vision Captured: ${title}" \
    "**Vision ID**: \`${vision_id}\`" \
    "**Entry**: \`grimoires/loa/visions/entries/${vision_id}.md\`" \
    "> This vision was captured during a bridge iteration. See the vision registry for details.")

  local repo_flag=()
  [[ -n "${repo:-}" ]] && repo_flag=(--repo "$repo")

  printf '%s' "$body" | gh pr comment "$pr" "${repo_flag[@]}" --body-file - 2>/dev/null || {
    echo "WARNING: Failed to post vision link to PR #$pr" >&2
    return 0
  }

  echo "Posted vision link for ${vision_id} to PR #$pr"
}

# =============================================================================
# vision-sprint subcommand (v1.39.0)
# =============================================================================

cmd_vision_sprint() {
  local pr="" bridge_id="" proposal_file="" repo=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --pr) pr="$2"; shift 2 ;;
      --bridge-id) bridge_id="$2"; shift 2 ;;
      --proposal-file) proposal_file="$2"; shift 2 ;;
      --repo) repo="$2"; shift 2 ;;
      *) echo "ERROR: Unknown argument: $1" >&2; exit 2 ;;
    esac
  done

  if [[ -z "$pr" || -z "$bridge_id" || -z "$proposal_file" ]]; then
    echo "ERROR: vision-sprint requires --pr, --bridge-id, --proposal-file" >&2
    exit 2
  fi

  if [[ ! -f "$proposal_file" ]]; then
    echo "WARNING: Proposal file not found: $proposal_file" >&2
    return 0
  fi

  check_gh || return 0

  # Read proposal content with size enforcement (32KB max)
  local proposal_content
  proposal_content=$(head -c 32768 "$proposal_file")

  local marker="<!-- bridge-vision-sprint: ${bridge_id} -->"
  local body
  body=$(printf '%s\n## Vision Sprint — Architectural Proposals\n\n**Bridge**: `%s`\n**Source**: Post-flatline exploration of captured visions\n\n---\n\n%s\n\n---\n\n> This vision sprint was generated after bridge convergence. Proposals are architectural sketches, not implementation commitments.' \
    "$marker" "$bridge_id" "$proposal_content")

  local repo_flag=()
  [[ -n "${repo:-}" ]] && repo_flag=(--repo "$repo")

  # Check for existing vision sprint comment
  local existing
  existing=$(gh pr view "$pr" "${repo_flag[@]}" --json comments --jq "[.comments[].body | select(contains(\"$marker\"))] | length" 2>/dev/null || echo "0")

  if [[ "$existing" -gt 0 ]]; then
    echo "Skipping: vision sprint comment already exists on PR #$pr"
    return 0
  fi

  printf '%s' "$body" | gh pr comment "$pr" "${repo_flag[@]}" --body-file - 2>/dev/null || {
    echo "WARNING: Failed to post vision sprint to PR #$pr" >&2
    return 0
  }

  echo "Posted vision sprint proposals to PR #$pr"
}

# =============================================================================
# Main dispatch
# =============================================================================

if [[ $# -eq 0 ]]; then
  usage 2
fi

case "$1" in
  comment)        shift; cmd_comment "$@" ;;
  update-pr)      shift; cmd_update_pr "$@" ;;
  vision)         shift; cmd_vision "$@" ;;
  vision-sprint)  shift; cmd_vision_sprint "$@" ;;
  --help)         usage 0 ;;
  *)              echo "ERROR: Unknown subcommand: $1" >&2; usage 2 ;;
esac
