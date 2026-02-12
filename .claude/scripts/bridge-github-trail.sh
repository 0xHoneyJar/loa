#!/usr/bin/env bash
# bridge-github-trail.sh - GitHub interactions for bridge loop
# Version: 1.0.0
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
  comment     Post Bridgebuilder review as PR comment
  update-pr   Update PR body with iteration summary table
  vision      Post vision link as PR comment

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
# comment subcommand
# =============================================================================

cmd_comment() {
  local pr="" iteration="" review_body="" bridge_id=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --pr) pr="$2"; shift 2 ;;
      --iteration) iteration="$2"; shift 2 ;;
      --review-body) review_body="$2"; shift 2 ;;
      --bridge-id) bridge_id="$2"; shift 2 ;;
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
  local body
  body=$(cat <<EOF
${marker}
## Bridge Review — Iteration ${iteration}

**Bridge ID**: \`${bridge_id}\`

$(cat "$review_body")

---
*Bridge iteration ${iteration} of ${bridge_id}*
EOF
)

  # Check for existing comment with this marker to avoid duplicates
  local existing
  existing=$(gh pr view "$pr" --json comments --jq ".comments[].body" 2>/dev/null | grep -c "$marker" || true)

  if [[ "$existing" -gt 0 ]]; then
    echo "Skipping: comment for iteration $iteration already exists on PR #$pr"
    return 0
  fi

  echo "$body" | gh pr comment "$pr" --body-file - 2>/dev/null || {
    echo "WARNING: Failed to post comment to PR #$pr" >&2
    return 0
  }

  echo "Posted bridge review comment for iteration $iteration to PR #$pr"
}

# =============================================================================
# update-pr subcommand
# =============================================================================

cmd_update_pr() {
  local pr="" state_file=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --pr) pr="$2"; shift 2 ;;
      --state-file) state_file="$2"; shift 2 ;;
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

  local table_header="## Bridge Loop Summary\n\n| Iter | State | Score | Visions | Source |\n|------|-------|-------|---------|--------|"
  local table_rows=""

  local iter_count
  iter_count=$(jq '.iterations | length' "$state_file")

  local i
  for ((i = 0; i < iter_count; i++)); do
    local iter_num iter_state source
    iter_num=$(jq ".iterations[$i].iteration" "$state_file")
    iter_state=$(jq -r ".iterations[$i].state" "$state_file")
    source=$(jq -r ".iterations[$i].source // \"existing\"" "$state_file")
    table_rows="${table_rows}\n| ${iter_num} | ${iter_state} | — | — | ${source} |"
  done

  # Build flatline info
  local flatline_info=""
  local flatline_status
  flatline_status=$(jq -r '.flatline.consecutive_below_threshold // 0' "$state_file")
  if [[ "$flatline_status" -gt 0 ]]; then
    flatline_info="\n\n**Flatline**: ${flatline_status} consecutive iterations below threshold"
  fi

  # Metrics
  local metrics_info=""
  local total_sprints total_files total_findings total_visions
  total_sprints=$(jq '.metrics.total_sprints_executed // 0' "$state_file")
  total_files=$(jq '.metrics.total_files_changed // 0' "$state_file")
  total_findings=$(jq '.metrics.total_findings_addressed // 0' "$state_file")
  total_visions=$(jq '.metrics.total_visions_captured // 0' "$state_file")
  metrics_info="\n\n**Metrics**: ${total_sprints} sprints, ${total_files} files changed, ${total_findings} findings addressed, ${total_visions} visions captured"

  local body
  body="${table_header}${table_rows}${flatline_info}${metrics_info}\n\n**Bridge ID**: \`${bridge_id}\` | **State**: ${state} | **Depth**: ${depth}"

  # Get current PR body and append/update bridge section
  local current_body
  current_body=$(gh pr view "$pr" --json body --jq '.body' 2>/dev/null || echo "")

  # Remove old bridge summary if present
  local new_body
  if echo "$current_body" | grep -q "## Bridge Loop Summary"; then
    new_body=$(echo "$current_body" | sed '/## Bridge Loop Summary/,$d')
    new_body="${new_body}${body}"
  else
    new_body="${current_body}\n\n---\n\n${body}"
  fi

  echo -e "$new_body" | gh pr edit "$pr" --body-file - 2>/dev/null || {
    echo "WARNING: Failed to update PR #$pr body" >&2
    return 0
  }

  echo "Updated PR #$pr body with bridge loop summary"
}

# =============================================================================
# vision subcommand
# =============================================================================

cmd_vision() {
  local pr="" vision_id="" title=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --pr) pr="$2"; shift 2 ;;
      --vision-id) vision_id="$2"; shift 2 ;;
      --title) title="$2"; shift 2 ;;
      *) echo "ERROR: Unknown argument: $1" >&2; exit 2 ;;
    esac
  done

  if [[ -z "$pr" || -z "$vision_id" || -z "$title" ]]; then
    echo "ERROR: vision requires --pr, --vision-id, --title" >&2
    exit 2
  fi

  check_gh || return 0

  local body
  body=$(cat <<EOF
<!-- bridge-vision: ${vision_id} -->
### Vision Captured: ${title}

**Vision ID**: \`${vision_id}\`
**Entry**: \`grimoires/loa/visions/entries/${vision_id}.md\`

> This vision was captured during a bridge iteration. See the vision registry for details.
EOF
)

  echo "$body" | gh pr comment "$pr" --body-file - 2>/dev/null || {
    echo "WARNING: Failed to post vision link to PR #$pr" >&2
    return 0
  }

  echo "Posted vision link for ${vision_id} to PR #$pr"
}

# =============================================================================
# Main dispatch
# =============================================================================

if [[ $# -eq 0 ]]; then
  usage 2
fi

case "$1" in
  comment)    shift; cmd_comment "$@" ;;
  update-pr)  shift; cmd_update_pr "$@" ;;
  vision)     shift; cmd_vision "$@" ;;
  --help)     usage 0 ;;
  *)          echo "ERROR: Unknown subcommand: $1" >&2; usage 2 ;;
esac
