#!/usr/bin/env bash
# semver-bump.sh - Conventional commit semver parser
# Version: 1.0.0
#
# Reads git tag history and commit messages to compute the next
# semantic version based on conventional commit prefixes.
#
# Usage:
#   .claude/scripts/semver-bump.sh [--from-tag | --from-changelog]
#
# Output: JSON to stdout
#   {"current": "1.35.1", "next": "1.36.0", "bump": "minor", "commits": [...]}
#
# Exit Codes:
#   0 - Success
#   1 - No commits since last tag
#   2 - No version source found

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/bootstrap.sh"

# =============================================================================
# Bump Priority Map
# =============================================================================

# Conventional commit type → bump level
# major > minor > patch
declare -A BUMP_MAP=(
  ["feat"]=minor
  ["fix"]=patch
  ["perf"]=patch
  ["refactor"]=patch
  ["chore"]=patch
  ["docs"]=patch
  ["test"]=patch
  ["ci"]=patch
  ["style"]=patch
  ["build"]=patch
)

# Numeric priority for comparison
declare -A BUMP_PRIORITY=(
  ["patch"]=1
  ["minor"]=2
  ["major"]=3
)

# =============================================================================
# Version Utilities
# =============================================================================

# Get current version from the latest git tag matching v*.*.*
get_version_from_tag() {
  local tag
  tag=$(git -C "$PROJECT_ROOT" tag -l 'v[0-9]*.[0-9]*.[0-9]*' --sort=-v:refname 2>/dev/null | head -1)
  if [[ -n "$tag" ]]; then
    echo "${tag#v}"
    return 0
  fi
  return 1
}

# Get current version from CHANGELOG.md header
get_version_from_changelog() {
  local changelog="${PROJECT_ROOT}/CHANGELOG.md"
  if [[ -f "$changelog" ]]; then
    local version
    version=$(grep -o '## \[[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\]' "$changelog" | head -1 | sed 's/## \[//;s/\]//')
    if [[ -n "$version" ]]; then
      echo "$version"
      return 0
    fi
  fi
  return 1
}

# Bump a version string by type
bump_version() {
  local current="$1" bump="$2"
  # Validate version format (M-05)
  if ! [[ "$current" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "ERROR: Invalid version format: $current" >&2
    return 1
  fi
  IFS='.' read -r major minor patch <<< "$current"
  case "$bump" in
    major) echo "$((major + 1)).0.0" ;;
    minor) echo "${major}.$((minor + 1)).0" ;;
    patch) echo "${major}.${minor}.$((patch + 1))" ;;
    *) echo "ERROR: Unknown bump type: $bump" >&2; return 1 ;;
  esac
}

# =============================================================================
# Commit Parsing
# =============================================================================

# Parse commits since a ref and determine bump type
# Outputs JSON array of commits to stderr, returns bump type on stdout
parse_commits() {
  local since_ref="$1"
  local commits_json="[]"
  local highest_bump="patch"
  local highest_priority=0
  local has_breaking=false

  # Check for BREAKING CHANGE in commit bodies
  if git -C "$PROJECT_ROOT" log "${since_ref}..HEAD" --format='%B' 2>/dev/null | grep -q 'BREAKING CHANGE:'; then
    has_breaking=true
  fi

  # Check for ! suffix in commit subjects (e.g., feat!: or feat(scope)!:)
  if git -C "$PROJECT_ROOT" log "${since_ref}..HEAD" --format='%s' 2>/dev/null | grep -qE '^[a-z]+(\([^)]*\))?!:'; then
    has_breaking=true
  fi

  if [[ "$has_breaking" == "true" ]]; then
    highest_bump="major"
    highest_priority=3
  fi

  # Parse each commit
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue

    local hash="${line%% *}"
    local subject="${line#* }"

    # Extract conventional commit parts
    local type="" scope="" msg="$subject"
    local cc_regex='^([a-z]+)(\([^)]*\))?(!)?\: (.*)$'
    if [[ "$subject" =~ $cc_regex ]]; then
      type="${BASH_REMATCH[1]}"
      scope="${BASH_REMATCH[2]}"
      scope="${scope#(}"
      scope="${scope%)}"
      msg="${BASH_REMATCH[4]}"
    fi

    # Determine bump for this commit type
    local commit_bump="patch"
    if [[ -n "$type" && -n "${BUMP_MAP[$type]:-}" ]]; then
      commit_bump="${BUMP_MAP[$type]}"
    fi

    # Track highest bump (if not already major from breaking change)
    local priority="${BUMP_PRIORITY[$commit_bump]:-1}"
    if [[ "$priority" -gt "$highest_priority" && "$has_breaking" != "true" ]]; then
      highest_priority=$priority
      highest_bump="$commit_bump"
    fi

    # Build commit JSON entry
    local commit_entry
    commit_entry=$(jq -n \
      --arg hash "$hash" \
      --arg type "${type:-unknown}" \
      --arg scope "${scope:-}" \
      --arg subject "$msg" \
      '{hash: $hash, type: $type, scope: $scope, subject: $subject}')

    commits_json=$(echo "$commits_json" | jq --argjson entry "$commit_entry" '. + [$entry]')

  done < <(git -C "$PROJECT_ROOT" log "${since_ref}..HEAD" --format='%h %s' 2>/dev/null)

  # Output commits JSON to fd 3
  echo "$commits_json" >&3
  # Output bump type to stdout
  echo "$highest_bump"
}

# =============================================================================
# Main
# =============================================================================

main() {
  local source_mode="auto"

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --from-tag) source_mode="tag"; shift ;;
      --from-changelog) source_mode="changelog"; shift ;;
      --help|-h)
        echo "Usage: semver-bump.sh [--from-tag | --from-changelog]"
        echo "  Computes next semver from conventional commits."
        echo "  Output: JSON with current, next, bump, commits"
        exit 0
        ;;
      *) echo "ERROR: Unknown argument: $1" >&2; exit 2 ;;
    esac
  done

  # Determine current version
  local current=""
  local tag_ref=""

  case "$source_mode" in
    tag)
      current=$(get_version_from_tag) || { echo "ERROR: No version tags found" >&2; exit 2; }
      tag_ref="v${current}"
      ;;
    changelog)
      current=$(get_version_from_changelog) || { echo "ERROR: No version in CHANGELOG.md" >&2; exit 2; }
      # Try to find matching tag
      if git -C "$PROJECT_ROOT" tag -l "v${current}" | grep -q "v${current}"; then
        tag_ref="v${current}"
      else
        echo "ERROR: No tag matching v${current} found" >&2
        exit 2
      fi
      ;;
    auto)
      if current=$(get_version_from_tag); then
        tag_ref="v${current}"
      elif current=$(get_version_from_changelog); then
        if git -C "$PROJECT_ROOT" tag -l "v${current}" | grep -q "v${current}"; then
          tag_ref="v${current}"
        else
          echo "ERROR: CHANGELOG version v${current} has no matching tag" >&2
          exit 2
        fi
      else
        echo "ERROR: No version source found (no tags, no CHANGELOG)" >&2
        exit 2
      fi
      ;;
  esac

  # Check for commits since tag
  local commit_count
  commit_count=$(git -C "$PROJECT_ROOT" rev-list "${tag_ref}..HEAD" --count 2>/dev/null || echo "0")
  if [[ "$commit_count" -eq 0 ]]; then
    echo "ERROR: No commits since ${tag_ref}" >&2
    exit 1
  fi

  # Parse commits and determine bump
  local commits_json bump
  local tmpdir="${TMPDIR:-/tmp}"
  local tmpfile_commits tmpfile_bump
  tmpfile_commits=$(mktemp "${tmpdir}/semver-commits-XXXXXXXXXX.json")
  tmpfile_bump=$(mktemp "${tmpdir}/semver-bump-XXXXXXXXXX.txt")

  # Ensure cleanup on exit or error
  trap 'rm -f "$tmpfile_commits" "$tmpfile_bump"' EXIT

  # parse_commits writes commits JSON to fd 3, bump type to stdout
  # Redirect fd 3 to tmpfile_commits, stdout to tmpfile_bump
  ( parse_commits "$tag_ref" 3>"$tmpfile_commits" ) > "$tmpfile_bump"

  bump=$(cat "$tmpfile_bump" 2>/dev/null || echo "patch")
  bump="${bump%$'\n'}"  # Trim trailing newline
  commits_json=$(cat "$tmpfile_commits" 2>/dev/null || echo "[]")
  rm -f "$tmpfile_commits" "$tmpfile_bump"
  trap - EXIT

  # Calculate next version
  local next
  next=$(bump_version "$current" "$bump")

  # Output result
  jq -n \
    --arg current "$current" \
    --arg next "$next" \
    --arg bump "$bump" \
    --argjson commits "$commits_json" \
    '{current: $current, next: $next, bump: $bump, commits: $commits}'
}

main "$@"
