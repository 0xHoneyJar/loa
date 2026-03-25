#!/usr/bin/env bash
# generate-release-summary.sh - User-friendly release summaries
# Version: 1.0.0
#
# Generates emoji-decorated, user-facing release summaries by parsing
# CHANGELOG.md and filtering out internal-only changes.
#
# Usage:
#   generate-release-summary.sh --from VERSION --to VERSION [--changelog PATH] [--json]
#
# Exit Codes:
#   0 - Success (user-facing changes found)
#   1 - No user-facing changes
#   2 - Error

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/bootstrap.sh"
source "$SCRIPT_DIR/classify-commit-zone.sh"

# =============================================================================
# Configuration
# =============================================================================

FROM_VERSION=""
TO_VERSION=""
CHANGELOG_PATH=""
JSON_OUTPUT=false
MAX_LINES=5

# Emoji map for conventional commit types
declare -A EMOJI_MAP=(
  [feat]="✨"
  [fix]="🔧"
  [docs]="📝"
  [security]="🔒"
  [perf]="🚀"
)

# Sort priority: lower = first
declare -A SORT_PRIORITY=(
  [breaking]=0
  [feat]=1
  [security]=2
  [perf]=3
  [fix]=4
  [docs]=5
)

# =============================================================================
# Argument Parsing
# =============================================================================

while [[ $# -gt 0 ]]; do
  case "$1" in
    --from) FROM_VERSION="$2"; shift 2 ;;
    --to) TO_VERSION="$2"; shift 2 ;;
    --changelog) CHANGELOG_PATH="$2"; shift 2 ;;
    --json) JSON_OUTPUT=true; shift ;;
    --help|-h)
      echo "Usage: generate-release-summary.sh --from VERSION --to VERSION [--changelog PATH] [--json]"
      echo ""
      echo "Generates user-friendly release summaries with emoji decorations."
      echo ""
      echo "Options:"
      echo "  --from VERSION    Previous version (e.g., 1.38.0)"
      echo "  --to VERSION      New version (e.g., 1.39.0)"
      echo "  --changelog PATH  Path to CHANGELOG.md (default: PROJECT_ROOT/CHANGELOG.md)"
      echo "  --json            Output structured JSON"
      echo ""
      echo "Exit Codes:"
      echo "  0 - Success (user-facing changes)"
      echo "  1 - No user-facing changes"
      echo "  2 - Error"
      exit 0
      ;;
    *) echo "ERROR: Unknown argument: $1" >&2; exit 2 ;;
  esac
done

# Validate required args
if [[ -z "$FROM_VERSION" || -z "$TO_VERSION" ]]; then
  echo "ERROR: --from and --to are required" >&2
  exit 2
fi

# Default changelog path
if [[ -z "$CHANGELOG_PATH" ]]; then
  CHANGELOG_PATH="${PROJECT_ROOT}/CHANGELOG.md"
fi

# =============================================================================
# CHANGELOG Parsing
# =============================================================================

# Extract bullet points between two version headers in CHANGELOG.md
# Returns lines like: "type|title|description"
parse_changelog() {
  local from="$1" to="$2" changelog="$3"

  if [[ ! -f "$changelog" ]]; then
    return 1
  fi

  local in_section=false
  local current_section=""
  local entries=()

  while IFS= read -r line; do
    # Detect start of target version section
    if [[ "$line" =~ ^##\ \[${to}\] ]]; then
      in_section=true
      continue
    fi

    # Detect end (next version header or start of previous version)
    if [[ "$in_section" == "true" && "$line" =~ ^##\ \[ ]]; then
      break
    fi

    if [[ "$in_section" == "true" ]]; then
      # Detect section headers (### Added, ### Fixed, etc.)
      if [[ "$line" =~ ^###\ (.+) ]]; then
        current_section="${BASH_REMATCH[1]}"
        continue
      fi

      # Detect bullet points
      if [[ "$line" =~ ^-\ (.+) ]]; then
        local bullet="${BASH_REMATCH[1]}"
        local type=""
        case "$current_section" in
          Added)    type="feat" ;;
          Fixed)    type="fix" ;;
          Changed)  type="feat" ;;
          Security) type="security" ;;
          *)        type="feat" ;;
        esac
        entries+=("${type}|${bullet}")
      fi
    fi
  done < "$changelog"

  if [[ ${#entries[@]} -eq 0 ]]; then
    return 1
  fi

  printf '%s\n' "${entries[@]}"
}

# =============================================================================
# Git Log Fallback
# =============================================================================

# Parse conventional commits when no CHANGELOG available
parse_git_log() {
  local from="$1" to="$2"
  local from_ref="v${from}" to_ref="v${to}"
  local entries=()

  # Check if tags exist
  if ! git -C "$PROJECT_ROOT" tag -l "$from_ref" | grep -q "$from_ref" 2>/dev/null; then
    return 1
  fi

  local range="${from_ref}..${to_ref}"
  # If to_ref tag doesn't exist, use HEAD
  if ! git -C "$PROJECT_ROOT" tag -l "$to_ref" | grep -q "$to_ref" 2>/dev/null; then
    range="${from_ref}..HEAD"
  fi

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    local hash="${line%% *}"
    local subject="${line#* }"

    # Extract conventional commit type
    local type="" msg="$subject"
    local cc_regex='^([a-z]+)(\([^)]*\))?(!)?\: (.*)$'
    local is_breaking=false
    if [[ "$subject" =~ $cc_regex ]]; then
      type="${BASH_REMATCH[1]}"
      [[ "${BASH_REMATCH[3]}" == "!" ]] && is_breaking=true
      msg="${BASH_REMATCH[4]}"
    else
      type="feat"  # default for non-conventional
      msg="$subject"
    fi

    # Zone classification — skip internal-only commits
    local zone
    zone=$(classify_commit_zone "$hash" 2>/dev/null) || zone="app"
    case "$zone" in
      system-only|state-only|mixed-internal) continue ;;
    esac

    if [[ "$is_breaking" == "true" ]]; then
      entries+=("breaking|${msg}")
    else
      entries+=("${type}|${msg}")
    fi
  done < <(git -C "$PROJECT_ROOT" log "$range" --format='%h %s' 2>/dev/null)

  if [[ ${#entries[@]} -eq 0 ]]; then
    return 1
  fi

  printf '%s\n' "${entries[@]}"
}

# =============================================================================
# Commit Association & Zone Filtering
# =============================================================================

# Try to find the commit SHA for a changelog bullet by searching git log
find_commit_for_bullet() {
  local bullet="$1" from="$2" to="$3"
  local from_ref="v${from}" to_ref="v${to}"

  local range="${from_ref}..${to_ref}"
  if ! git -C "$PROJECT_ROOT" tag -l "$to_ref" | grep -q "$to_ref" 2>/dev/null; then
    range="${from_ref}..HEAD"
  fi

  # Extract key words from bullet for matching
  # Remove markdown bold and scope prefixes
  local search_text
  search_text=$(echo "$bullet" | sed 's/\*\*[^*]*\*\*: //' | sed 's/\*\*[^*]*\*\*//')

  # Search commit subjects for a match
  local sha
  sha=$(git -C "$PROJECT_ROOT" log "$range" --format='%h %s' 2>/dev/null | \
    grep -iF "$search_text" 2>/dev/null | head -1 | cut -d' ' -f1)

  if [[ -n "$sha" ]]; then
    echo "$sha"
    return 0
  fi

  # No match found — return empty (commit is unresolvable)
  return 1
}

# Filter entries by zone classification
# Input: lines of "type|description"
# Output: filtered lines (only app-zone commits)
filter_by_zone() {
  local from="$1" to="$2"
  local filtered=()

  while IFS= read -r entry; do
    [[ -z "$entry" ]] && continue
    local type="${entry%%|*}"
    local desc="${entry#*|}"

    # Try to find commit and classify
    local sha
    sha=$(find_commit_for_bullet "$desc" "$from" "$to" 2>/dev/null) || sha=""

    if [[ -n "$sha" ]]; then
      local zone
      zone=$(classify_commit_zone "$sha" 2>/dev/null) || zone="app"
      case "$zone" in
        system-only|state-only|mixed-internal) continue ;;
      esac
    fi
    # If no commit found, include by default (benefit of the doubt)
    filtered+=("$entry")
  done

  if [[ ${#filtered[@]} -eq 0 ]]; then
    return 1
  fi

  printf '%s\n' "${filtered[@]}"
}

# =============================================================================
# Formatting
# =============================================================================

# Sort entries by priority and format with emojis
format_entries() {
  local entries=()
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    entries+=("$line")
  done

  if [[ ${#entries[@]} -eq 0 ]]; then
    return 1
  fi

  # Sort by type priority
  local sorted=()
  for priority_type in breaking feat security perf fix docs; do
    for entry in "${entries[@]}"; do
      local type="${entry%%|*}"
      if [[ "$type" == "$priority_type" ]]; then
        sorted+=("$entry")
      fi
    done
  done
  # Add any unmatched types at the end
  for entry in "${entries[@]}"; do
    local type="${entry%%|*}"
    local matched=false
    for pt in breaking feat security perf fix docs; do
      [[ "$type" == "$pt" ]] && matched=true && break
    done
    [[ "$matched" == "false" ]] && sorted+=("$entry")
  done

  # Cap at MAX_LINES and format
  local count=0
  for entry in "${sorted[@]}"; do
    [[ "$count" -ge "$MAX_LINES" ]] && break
    local type="${entry%%|*}"
    local desc="${entry#*|}"
    local emoji="${EMOJI_MAP[$type]:-✨}"

    # For breaking changes, use a special emoji
    if [[ "$type" == "breaking" ]]; then
      emoji="💥"
    fi

    echo "  ${emoji} ${desc}"
    count=$((count + 1))
  done
}

# =============================================================================
# JSON Output
# =============================================================================

format_json() {
  local entries=()
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    entries+=("$line")
  done

  if [[ ${#entries[@]} -eq 0 ]]; then
    jq -n --arg from "$FROM_VERSION" --arg to "$TO_VERSION" \
      '{from: $from, to: $to, entries: [], count: 0}'
    return 1
  fi

  local json_entries="[]"
  local count=0
  for entry in "${entries[@]}"; do
    [[ "$count" -ge "$MAX_LINES" ]] && break
    local type="${entry%%|*}"
    local desc="${entry#*|}"
    local emoji="${EMOJI_MAP[$type]:-✨}"
    [[ "$type" == "breaking" ]] && emoji="💥"

    json_entries=$(echo "$json_entries" | jq \
      --arg type "$type" \
      --arg desc "$desc" \
      --arg emoji "$emoji" \
      '. + [{type: $type, description: $desc, emoji: $emoji}]')
    count=$((count + 1))
  done

  jq -n \
    --arg from "$FROM_VERSION" \
    --arg to "$TO_VERSION" \
    --argjson entries "$json_entries" \
    --argjson count "$count" \
    '{from: $from, to: $to, entries: $entries, count: $count}'
}

# =============================================================================
# Main
# =============================================================================

main() {
  local raw_entries=""
  local use_changelog=true

  # Try CHANGELOG first
  if [[ -f "$CHANGELOG_PATH" ]]; then
    raw_entries=$(parse_changelog "$FROM_VERSION" "$TO_VERSION" "$CHANGELOG_PATH" 2>/dev/null) || use_changelog=false
  else
    use_changelog=false
  fi

  # Fallback to git log
  if [[ "$use_changelog" == "false" || -z "$raw_entries" ]]; then
    raw_entries=$(parse_git_log "$FROM_VERSION" "$TO_VERSION" 2>/dev/null) || {
      if [[ "$JSON_OUTPUT" == "true" ]]; then
        jq -n --arg from "$FROM_VERSION" --arg to "$TO_VERSION" \
          '{from: $from, to: $to, entries: [], count: 0}'
      fi
      exit 1
    }
  fi

  # Filter by zone (only for changelog-sourced entries that need commit association)
  local filtered_entries=""
  if [[ "$use_changelog" == "true" ]]; then
    filtered_entries=$(echo "$raw_entries" | filter_by_zone "$FROM_VERSION" "$TO_VERSION" 2>/dev/null) || {
      # All entries filtered out — no user-facing changes
      if [[ "$JSON_OUTPUT" == "true" ]]; then
        jq -n --arg from "$FROM_VERSION" --arg to "$TO_VERSION" \
          '{from: $from, to: $to, entries: [], count: 0}'
      fi
      exit 1
    }
  else
    # Git log fallback already filters by zone
    filtered_entries="$raw_entries"
  fi

  if [[ -z "$filtered_entries" ]]; then
    if [[ "$JSON_OUTPUT" == "true" ]]; then
      jq -n --arg from "$FROM_VERSION" --arg to "$TO_VERSION" \
        '{from: $from, to: $to, entries: [], count: 0}'
    fi
    exit 1
  fi

  # Output
  if [[ "$JSON_OUTPUT" == "true" ]]; then
    echo "$filtered_entries" | format_json
  else
    echo "$filtered_entries" | format_entries
  fi
}

main
