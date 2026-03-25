#!/usr/bin/env bash
# classify-commit-zone.sh - Commit zone classification
# Version: 1.0.0
#
# Classifies git commits by which Three-Zone Model zones their files touch.
# Can be sourced as a library or executed directly.
#
# Usage (executable):
#   classify-commit-zone.sh <SHA>
#   classify-commit-zone.sh --batch --range <REF_RANGE>
#
# Usage (library):
#   source classify-commit-zone.sh
#   classify_commit_zone <SHA>
#   is_loa_repo
#
# Output zones:
#   system-only     - Only .claude/ files
#   state-only      - Only grimoires/, .beads/, .run/, .ck/ files
#   app             - Touches app-zone files (src/, lib/, etc.)
#   mixed-internal  - Both system and state, but no app
#
# Exit Codes:
#   0 - Success
#   1 - Error (invalid SHA, git failure)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Only source bootstrap if not already sourced (PROJECT_ROOT not set)
if [[ -z "${PROJECT_ROOT:-}" ]]; then
  source "$SCRIPT_DIR/bootstrap.sh"
fi

# =============================================================================
# Zone Classification
# =============================================================================

# Classify a commit by which zones its files touch
# Args: $1 = git SHA
# Output: zone name to stdout
# Returns: 0 on success, 1 on error
classify_commit_zone() {
  local sha="$1"
  local files
  files=$(git -C "$PROJECT_ROOT" diff-tree --root --no-commit-id --name-only -r "$sha" 2>/dev/null) || return 1

  local has_system=false has_state=false has_app=false

  while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    case "$file" in
      .claude/*) has_system=true ;;
      grimoires/*|.beads/*|.run/*|.ck/*) has_state=true ;;
      *) has_app=true ;;
    esac
  done <<< "$files"

  if [[ "$has_app" == "true" ]]; then
    echo "app"
  elif [[ "$has_system" == "true" && "$has_state" == "true" ]]; then
    echo "mixed-internal"
  elif [[ "$has_system" == "true" ]]; then
    echo "system-only"
  elif [[ "$has_state" == "true" ]]; then
    echo "state-only"
  else
    echo "app"  # empty commit = safe default
  fi
}

# =============================================================================
# Repo Detection
# =============================================================================

# Check if the current repo is the upstream Loa repo (not a downstream consumer)
# Returns: 0 if this IS the loa repo, 1 if it's downstream
is_loa_repo() {
  # Check 1: git remote URL contains 0xHoneyJar/loa
  local remote_url
  remote_url=$(git -C "$PROJECT_ROOT" remote get-url origin 2>/dev/null || echo "")
  if [[ "$remote_url" == *"0xHoneyJar/loa"* ]]; then
    return 0
  fi

  # Check 2: heuristic — presence of .claude/loa/CLAUDE.loa.md at repo root
  # (as opposed to in a submodule)
  if [[ -f "$PROJECT_ROOT/.claude/loa/CLAUDE.loa.md" ]]; then
    # Additional check: this file should NOT be inside a submodule
    # If .loa/ exists as a submodule directory, this is downstream
    if [[ -d "$PROJECT_ROOT/.loa" ]]; then
      return 1  # downstream with submodule
    fi
    # It's the loa repo itself (CLAUDE.loa.md at root, no submodule)
    return 0
  fi

  return 1  # downstream
}

# =============================================================================
# Batch Mode
# =============================================================================

# Output JSONL for a range of commits
# Args: $1 = ref range (e.g., "v1.0.0..HEAD")
batch_classify() {
  local range="$1"
  local shas
  shas=$(git -C "$PROJECT_ROOT" rev-list "$range" 2>/dev/null) || {
    echo "ERROR: Invalid range: $range" >&2
    return 1
  }

  while IFS= read -r sha; do
    [[ -z "$sha" ]] && continue
    local zone
    zone=$(classify_commit_zone "$sha" 2>/dev/null) || zone="error"
    local subject
    subject=$(git -C "$PROJECT_ROOT" log -1 --format='%s' "$sha" 2>/dev/null || echo "")
    # Use jq for safe JSON construction
    jq -cn \
      --arg sha "$sha" \
      --arg zone "$zone" \
      --arg subject "$subject" \
      '{sha: $sha, zone: $zone, subject: $subject}'
  done <<< "$shas"
}

# =============================================================================
# Main (executable mode)
# =============================================================================

# Only run main when executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  _main() {
    local batch=false
    local range=""
    local sha=""

    while [[ $# -gt 0 ]]; do
      case "$1" in
        --batch) batch=true; shift ;;
        --range) range="$2"; shift 2 ;;
        --help|-h)
          echo "Usage: classify-commit-zone.sh <SHA>"
          echo "       classify-commit-zone.sh --batch --range <REF_RANGE>"
          echo ""
          echo "Classifies commits by Three-Zone Model zones."
          echo ""
          echo "Zones: system-only | state-only | app | mixed-internal"
          exit 0
          ;;
        *)
          if [[ -z "$sha" ]]; then
            sha="$1"
          else
            echo "ERROR: Unexpected argument: $1" >&2
            exit 1
          fi
          shift
          ;;
      esac
    done

    if [[ "$batch" == "true" ]]; then
      if [[ -z "$range" ]]; then
        echo "ERROR: --batch requires --range <REF_RANGE>" >&2
        exit 1
      fi
      batch_classify "$range"
    elif [[ -n "$sha" ]]; then
      classify_commit_zone "$sha"
    else
      echo "ERROR: Provide a SHA or use --batch --range" >&2
      exit 1
    fi
  }

  _main "$@"
fi
