#!/usr/bin/env bash
# release-notes-gen.sh - Generate release notes from CHANGELOG and commits
# Version: 1.0.0
#
# Extracts release notes from CHANGELOG.md for a given version,
# or generates minimal notes for bugfix releases.
#
# Usage:
#   .claude/scripts/release-notes-gen.sh --version <version> --pr <number> --type <cycle|bugfix|other>
#
# Output: Markdown to stdout
#
# Exit Codes:
#   0 - Success
#   1 - Missing required arguments
#   2 - CHANGELOG not found or version not found

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/bootstrap.sh"

# =============================================================================
# Defaults
# =============================================================================

VERSION=""
PR_NUMBER=""
PR_TYPE="other"

# =============================================================================
# Usage
# =============================================================================

usage() {
  cat <<'USAGE'
Usage: release-notes-gen.sh [OPTIONS]

Options:
  --version VERSION    Version to generate notes for (required)
  --pr NUMBER          Source PR number (required)
  --type TYPE          PR type: cycle|bugfix|other (default: other)
  --help               Show this help
USAGE
}

# =============================================================================
# CHANGELOG Extraction
# =============================================================================

# Extract the section for a specific version from CHANGELOG.md
extract_changelog_section() {
  local version="$1"
  local changelog="${PROJECT_ROOT}/CHANGELOG.md"

  if [[ ! -f "$changelog" ]]; then
    return 1
  fi

  # Extract content between "## [version]" and the next "## [" header
  local in_section=false
  local content=""

  while IFS= read -r line; do
    if [[ "$line" =~ ^##\ \[${version}\] ]]; then
      in_section=true
      continue
    fi
    if [[ "$in_section" == true && "$line" =~ ^##\ \[ ]]; then
      break
    fi
    if [[ "$in_section" == true ]]; then
      content="${content}${line}
"
    fi
  done < "$changelog"

  if [[ -z "$content" ]]; then
    return 1
  fi

  # Trim leading/trailing whitespace
  echo "$content" | sed -e 's/^[[:space:]]*//' -e '/^$/N;/^\n$/d'
}

# Count commits by type since the previous tag
count_commits() {
  local version="$1"
  local tag="v${version}"

  # Find previous tag
  local prev_tag
  prev_tag=$(git -C "$PROJECT_ROOT" tag -l 'v[0-9]*.[0-9]*.[0-9]*' --sort=-v:refname 2>/dev/null | \
    grep -A1 "^${tag}$" | tail -1)

  if [[ -z "$prev_tag" || "$prev_tag" == "$tag" ]]; then
    # No previous tag or only one tag — count all commits to tag
    prev_tag=""
  fi

  local range="${prev_tag:+${prev_tag}..}${tag}"
  local total feat_count fix_count

  total=$(git -C "$PROJECT_ROOT" rev-list "${range}" --count 2>/dev/null || echo "0")
  feat_count=$(git -C "$PROJECT_ROOT" log "${range}" --format='%s' 2>/dev/null | grep -cE '^feat' || echo "0")
  fix_count=$(git -C "$PROJECT_ROOT" log "${range}" --format='%s' 2>/dev/null | grep -cE '^fix' || echo "0")

  echo "${total} ${feat_count} ${fix_count}"
}

# =============================================================================
# Templates
# =============================================================================

# =============================================================================
# Tier 2: PR Metadata Synthesis (FR-2, cycle-016)
# =============================================================================

# Generate release notes from PR metadata when CHANGELOG entry is missing
generate_from_pr_metadata() {
  local version="$1" pr_number="$2"

  if ! command -v gh &>/dev/null; then
    return 1
  fi

  local pr_json
  pr_json=$(gh pr view "$pr_number" --json title,body,labels 2>/dev/null) || return 1

  local title body
  title=$(echo "$pr_json" | jq -r '.title // ""')
  body=$(echo "$pr_json" | jq -r '.body // ""')

  if [[ -z "$title" ]]; then
    return 1
  fi

  # Extract subtitle from conventional commit title
  # Regex stored in variable — bash [[ =~ ]] requires this for patterns with parentheses
  local subtitle="$title"
  local re_with_pr='^(feat|fix)\([^)]+\): (.+) \(#[0-9]+\)$'
  local re_simple='^(feat|fix)\([^)]+\): (.+)$'
  if [[ "$title" =~ $re_with_pr ]]; then
    subtitle="${BASH_REMATCH[2]}"
  elif [[ "$title" =~ $re_simple ]]; then
    subtitle="${BASH_REMATCH[2]}"
  fi

  echo "$subtitle"
  echo ""

  # Extract ## Summary from PR body
  local summary
  summary=$(printf '%s\n' "$body" | awk '/^## Summary/{f=1;next} /^## /{f=0} f')
  if [[ -n "$summary" ]]; then
    echo "$summary"
    echo ""
  fi

  # Categorize from conventional commit subjects
  local prev_tag
  prev_tag=$(git -C "$PROJECT_ROOT" tag -l 'v[0-9]*.[0-9]*.[0-9]*' --sort=-v:refname | \
    grep -A1 "^v${version}$" | tail -1)

  if [[ -z "$prev_tag" || "$prev_tag" == "v${version}" ]]; then
    prev_tag=""
  fi

  local range="${prev_tag:+${prev_tag}..}v${version}"

  local feat_commits fix_commits
  feat_commits=$(git -C "$PROJECT_ROOT" log "${range}" --format='%s' 2>/dev/null | grep -E '^feat' || true)
  fix_commits=$(git -C "$PROJECT_ROOT" log "${range}" --format='%s' 2>/dev/null | grep -E '^fix' || true)

  if [[ -n "$feat_commits" ]]; then
    echo "### Added"
    echo ""
    while IFS= read -r c; do
      local msg="${c#*: }"
      echo "- ${msg}"
    done <<< "$feat_commits"
    echo ""
  fi

  if [[ -n "$fix_commits" ]]; then
    echo "### Fixed"
    echo ""
    while IFS= read -r c; do
      local msg="${c#*: }"
      echo "- ${msg}"
    done <<< "$fix_commits"
    echo ""
  fi
}

# =============================================================================
# Tier 3: Commit Log Compilation (FR-2, cycle-016)
# =============================================================================

# Minimal but non-empty output from git log
generate_from_commits() {
  local version="$1"

  local prev_tag
  prev_tag=$(git -C "$PROJECT_ROOT" tag -l 'v[0-9]*.[0-9]*.[0-9]*' --sort=-v:refname | \
    grep -A1 "^v${version}$" | tail -1)

  if [[ -z "$prev_tag" || "$prev_tag" == "v${version}" ]]; then
    prev_tag=""
  fi

  local range="${prev_tag:+${prev_tag}..}v${version}"

  local commits
  commits=$(git -C "$PROJECT_ROOT" log "${range}" --format='- %s' 2>/dev/null | grep -vE '^- (Merge|chore\(release\))' | head -20)

  if [[ -z "$commits" ]]; then
    echo "Release v${version}."
    return 0
  fi

  echo "### Changes"
  echo ""
  echo "$commits"
}

# =============================================================================
# Templates (enhanced with multi-tier fallback)
# =============================================================================

generate_cycle_notes() {
  local version="$1" pr_number="$2"
  local changelog_content

  printf '## What'\''s New in v%s\n\n' "$version"

  # Tier 1: CHANGELOG extraction (existing behavior)
  if changelog_content=$(extract_changelog_section "$version"); then
    echo "$changelog_content"
  # Tier 2: PR metadata synthesis (FR-2)
  elif generate_from_pr_metadata "$version" "$pr_number" 2>/dev/null; then
    : # output already printed by function
  # Tier 3: Commit log compilation (FR-2)
  else
    generate_from_commits "$version"
  fi

  echo ""
  echo "### Source"
  echo ""
  printf -- '- PR: #%s\n' "$pr_number"

  # Try to get commit counts
  local counts
  if counts=$(count_commits "$version" 2>/dev/null); then
    local total feat_count fix_count
    read -r total feat_count fix_count <<< "$counts"
    printf -- '- Commits: %s (%s features, %s fixes)\n' "$total" "$feat_count" "$fix_count"
  fi

  echo ""
  echo "---"
  echo "Generated by Loa Post-Merge Automation"
}

generate_bugfix_notes() {
  local version="$1" pr_number="$2"

  printf '## Bug Fix Release v%s\n\n' "$version"

  # Try PR metadata for richer content
  local pr_title="" pr_body=""
  if command -v gh &>/dev/null; then
    pr_title=$(gh pr view "$pr_number" --json title --jq '.title' 2>/dev/null || true)
    pr_body=$(gh pr view "$pr_number" --json body --jq '.body' 2>/dev/null || true)
  fi

  if [[ -n "$pr_title" ]]; then
    echo "$pr_title"
    echo ""
  else
    echo "Bug fix release."
    echo ""
  fi

  # Extract ## Summary from PR body for richer description
  if [[ -n "$pr_body" ]]; then
    local summary
    summary=$(printf '%s\n' "$pr_body" | awk '/^## Summary/{f=1;next} /^## /{f=0} f')
    if [[ -n "$summary" ]]; then
      echo "$summary"
      echo ""
    fi
  fi

  echo "### Source"
  echo ""
  printf -- '- PR: #%s\n' "$pr_number"
  echo ""
  echo "---"
  echo "Generated by Loa Post-Merge Automation"
}

generate_other_notes() {
  local version="$1" pr_number="$2"

  printf '## Release v%s\n\n' "$version"

  local changelog_content
  # Same multi-tier fallback as cycle notes
  if changelog_content=$(extract_changelog_section "$version"); then
    echo "$changelog_content"
  elif generate_from_pr_metadata "$version" "$pr_number" 2>/dev/null; then
    : # output already printed
  else
    generate_from_commits "$version"
  fi

  echo ""
  echo "### Source"
  echo ""
  printf -- '- PR: #%s\n' "$pr_number"
  echo ""
  echo "---"
  echo "Generated by Loa Post-Merge Automation"
}

# =============================================================================
# Main
# =============================================================================

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --version) VERSION="$2"; shift 2 ;;
      --pr) PR_NUMBER="$2"; shift 2 ;;
      --type) PR_TYPE="$2"; shift 2 ;;
      --help|-h) usage; exit 0 ;;
      *) echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
    esac
  done

  if [[ -z "$VERSION" ]]; then
    echo "ERROR: --version is required" >&2
    exit 1
  fi

  if [[ -z "$PR_NUMBER" ]]; then
    echo "ERROR: --pr is required" >&2
    exit 1
  fi

  case "$PR_TYPE" in
    cycle) generate_cycle_notes "$VERSION" "$PR_NUMBER" ;;
    bugfix) generate_bugfix_notes "$VERSION" "$PR_NUMBER" ;;
    other|*) generate_other_notes "$VERSION" "$PR_NUMBER" ;;
  esac
}

main "$@"
