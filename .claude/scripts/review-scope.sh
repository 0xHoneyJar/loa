#!/usr/bin/env bash
# =============================================================================
# review-scope.sh — Shared review scope filtering utility (#303)
# =============================================================================
# Version: 1.0.0
#
# Filters file lists by:
#   1. Zone detection from .loa-version.json (system/state zones excluded)
#   2. .reviewignore patterns (gitignore-style user customization)
#
# Usage:
#   echo "src/app.ts" | review-scope.sh          # Filter stdin
#   review-scope.sh --diff-files changed.txt      # Filter from file
#   review-scope.sh --no-reviewignore             # Zone detection only
#   review-scope.sh --list-excluded               # Show what was excluded
#
# Functions (sourceable):
#   detect_zones       → Load zone definitions from .loa-version.json
#   load_reviewignore  → Parse .reviewignore patterns
#   is_excluded        → Check if a single file is excluded
#   filter_files       → Filter file list (stdin → stdout)
# =============================================================================

# Only set strict mode when running directly (not when sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
fi

# === Configuration ===
REVIEW_SCOPE_VERSION="1.0.0"
LOA_VERSION_FILE="${LOA_VERSION_FILE:-.loa-version.json}"
REVIEWIGNORE_FILE="${REVIEWIGNORE_FILE:-.reviewignore}"

# Populated by detect_zones()
SYSTEM_ZONE_PATHS=()
STATE_ZONE_PATHS=()

# Populated by load_reviewignore()
REVIEWIGNORE_PATTERNS=()

# Stats
EXCLUDED_COUNT=0
PASSED_COUNT=0
EXCLUDED_FILES=()

# === Zone Detection ===

detect_zones() {
  # Read zone definitions from .loa-version.json
  if [[ ! -f "$LOA_VERSION_FILE" ]]; then
    # No Loa detected — pass everything through
    return 0
  fi

  # System zone (always a single path)
  local system_zone
  system_zone=$(jq -r '.zones.system // ".claude"' "$LOA_VERSION_FILE" 2>/dev/null) || system_zone=".claude"
  SYSTEM_ZONE_PATHS=("$system_zone")

  # State zone (array of paths)
  local state_json
  state_json=$(jq -r '.zones.state[]? // empty' "$LOA_VERSION_FILE" 2>/dev/null) || true
  if [[ -n "$state_json" ]]; then
    while IFS= read -r path; do
      [[ -n "$path" ]] && STATE_ZONE_PATHS+=("$path")
    done <<< "$state_json"
  fi
}

# === .reviewignore Parser ===

load_reviewignore() {
  local ignore_file="${1:-$REVIEWIGNORE_FILE}"

  if [[ ! -f "$ignore_file" ]]; then
    return 0
  fi

  while IFS= read -r line; do
    # Skip blank lines and comments
    line="${line%%#*}"  # Strip inline comments
    line="$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"  # Trim whitespace
    [[ -z "$line" ]] && continue

    REVIEWIGNORE_PATTERNS+=("$line")
  done < "$ignore_file"
}

# === File Exclusion Check ===

_matches_pattern() {
  local file="$1"
  local pattern="$2"

  # Directory pattern (ends with /)
  if [[ "$pattern" == */ ]]; then
    local dir_prefix="${pattern%/}"
    if [[ "$file" == "$dir_prefix"/* || "$file" == "$dir_prefix" ]]; then
      return 0
    fi
    return 1
  fi

  # Glob pattern
  # shellcheck disable=SC2254
  case "$file" in
    $pattern) return 0 ;;
  esac

  # Also try matching against basename
  local basename="${file##*/}"
  # shellcheck disable=SC2254
  case "$basename" in
    $pattern) return 0 ;;
  esac

  return 1
}

is_excluded() {
  local file="$1"
  local no_reviewignore="${2:-false}"

  # Zone exclusion: system zone
  for zone_path in "${SYSTEM_ZONE_PATHS[@]}"; do
    if [[ "$file" == "$zone_path"/* || "$file" == "$zone_path" ]]; then
      return 0  # Excluded
    fi
  done

  # Zone exclusion: state zone
  for zone_path in "${STATE_ZONE_PATHS[@]}"; do
    if [[ "$file" == "$zone_path"/* || "$file" == "$zone_path" ]]; then
      return 0  # Excluded
    fi
  done

  # .reviewignore patterns
  if [[ "$no_reviewignore" != "true" ]]; then
    for pattern in "${REVIEWIGNORE_PATTERNS[@]}"; do
      if _matches_pattern "$file" "$pattern"; then
        return 0  # Excluded
      fi
    done
  fi

  return 1  # Not excluded — passes through
}

# === File List Filter ===

filter_files() {
  local no_reviewignore="${1:-false}"

  EXCLUDED_COUNT=0
  PASSED_COUNT=0
  EXCLUDED_FILES=()

  while IFS= read -r file; do
    [[ -z "$file" ]] && continue

    if is_excluded "$file" "$no_reviewignore"; then
      EXCLUDED_COUNT=$((EXCLUDED_COUNT + 1))
      EXCLUDED_FILES+=("$file")
    else
      echo "$file"
      PASSED_COUNT=$((PASSED_COUNT + 1))
    fi
  done
}

# === Main (when run directly) ===

main() {
  local no_reviewignore="false"
  local diff_file=""
  local list_excluded="false"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --no-reviewignore)
        no_reviewignore="true"
        shift
        ;;
      --diff-files)
        diff_file="$2"
        shift 2
        ;;
      --list-excluded)
        list_excluded="true"
        shift
        ;;
      --version)
        echo "review-scope.sh v${REVIEW_SCOPE_VERSION}"
        exit 0
        ;;
      -h|--help)
        echo "Usage: review-scope.sh [--no-reviewignore] [--diff-files FILE] [--list-excluded]"
        echo "Filters file lists by Loa zone detection and .reviewignore patterns."
        echo "Reads file paths from stdin (one per line) unless --diff-files is specified."
        exit 0
        ;;
      *)
        echo "Unknown option: $1" >&2
        exit 1
        ;;
    esac
  done

  # Initialize
  detect_zones
  if [[ "$no_reviewignore" != "true" ]]; then
    load_reviewignore
  fi

  # Filter
  if [[ -n "$diff_file" ]]; then
    filter_files "$no_reviewignore" < "$diff_file"
  else
    filter_files "$no_reviewignore"
  fi

  # Report excluded count to stderr
  if [[ "$EXCLUDED_COUNT" -gt 0 ]]; then
    echo "[review-scope] Excluded $EXCLUDED_COUNT files, passed $PASSED_COUNT files" >&2
  fi

  # Optionally list excluded files
  if [[ "$list_excluded" == "true" && ${#EXCLUDED_FILES[@]} -gt 0 ]]; then
    echo "" >&2
    echo "[review-scope] Excluded files:" >&2
    for f in "${EXCLUDED_FILES[@]}"; do
      echo "  - $f" >&2
    done
  fi
}

# Only run main if not being sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
