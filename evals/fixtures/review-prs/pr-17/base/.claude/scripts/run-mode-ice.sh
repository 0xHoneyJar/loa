#!/usr/bin/env bash
set -euo pipefail

# run-mode-ice.sh - ICE (Intrusion Countermeasures Electronics)
# Git safety wrapper for Run Mode - enforces branch protection
#
# This script wraps git operations to prevent accidental pushes to protected
# branches. Protection is HARD-CODED and cannot be configured or bypassed.
#
# Usage:
#   run-mode-ice.sh <command> [args...]
#
# Commands:
#   is-protected <branch>     Check if branch is protected
#   validate                  Verify current branch is safe
#   ensure-branch <name>      Create/checkout feature branch
#   checkout <branch>         Safe checkout (blocks protected)
#   push [remote] [branch]    Safe push (blocks protected)
#   push-upstream <r> <b>     Safe push with -u flag
#   merge                     ALWAYS BLOCKED
#   pr-merge                  ALWAYS BLOCKED
#   branch-delete             ALWAYS BLOCKED
#   pr-create <title> <body>  Create draft PR only
#
# Exit codes:
#   0 - Success
#   1 - Blocked by ICE (protected branch or forbidden operation)
#   2 - Usage error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# ============================================================================
# PROTECTED BRANCHES - HARD-CODED, NOT CONFIGURABLE
# ============================================================================

# Exact branch names that are always protected
PROTECTED_BRANCHES=(
  "main"
  "master"
  "staging"
  "develop"
  "development"
  "production"
  "prod"
)

# Glob patterns for protected branches
PROTECTED_PATTERNS=(
  "release/*"
  "release-*"
  "hotfix/*"
  "hotfix-*"
)

# ============================================================================
# LOGGING
# ============================================================================

log_ice_block() {
  local operation="$1"
  local target="${2:-}"
  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  echo "ICE BLOCK [$timestamp]: $operation ${target:+on $target}" >&2

  # Log to trajectory if .run directory exists
  if [[ -d "$REPO_ROOT/.run" ]]; then
    echo "{\"timestamp\":\"$timestamp\",\"event\":\"ice_block\",\"operation\":\"$operation\",\"target\":\"$target\"}" >> "$REPO_ROOT/.run/ice.log"
  fi
}

# ============================================================================
# CORE FUNCTIONS
# ============================================================================

# Check if a branch name matches protected list
# Returns: 0 if protected, 1 if not protected
# SECURITY (HIGH-006): Use glob matching instead of regex to prevent metacharacter bypass
is_protected_branch() {
  local branch="$1"

  # Check exact matches first (safest)
  for protected in "${PROTECTED_BRANCHES[@]}"; do
    if [[ "$branch" == "$protected" ]]; then
      echo "true"
      return 0
    fi
  done

  # Check pattern matches using bash glob-style matching
  # This is safer than regex because we control the patterns
  for pattern in "${PROTECTED_PATTERNS[@]}"; do
    # Use bash extended globbing for safe pattern matching
    # The pattern from PROTECTED_PATTERNS is trusted (hard-coded)
    # We use [[ with == to do glob matching (not regex)
    case "$branch" in
      $pattern)
        echo "true"
        return 0
        ;;
    esac
  done

  echo "false"
  return 1
}

# Get current branch name
get_current_branch() {
  git rev-parse --abbrev-ref HEAD 2>/dev/null || echo ""
}

# Validate that current branch is safe for operations
# Returns: 0 if safe, 1 if on protected branch
validate_working_branch() {
  local current
  current=$(get_current_branch)

  if [[ -z "$current" ]]; then
    echo "ERROR: Not in a git repository" >&2
    return 1
  fi

  if [[ $(is_protected_branch "$current") == "true" ]]; then
    echo "ERROR: Currently on protected branch '$current'" >&2
    echo "ICE: Switch to a feature branch before proceeding" >&2
    log_ice_block "validate" "$current"
    return 1
  fi

  echo "OK: On safe branch '$current'"
  return 0
}

# Create or checkout a feature branch
# Args: target_name [prefix]
ensure_feature_branch() {
  local target="$1"
  local prefix="${2:-feature/}"
  local branch_name="${prefix}${target}"
  local current
  current=$(get_current_branch)

  # Already on the target branch
  if [[ "$current" == "$branch_name" ]]; then
    echo "Already on branch '$branch_name'"
    return 0
  fi

  # Check if branch exists
  if git show-ref --verify --quiet "refs/heads/$branch_name" 2>/dev/null; then
    # Branch exists, checkout
    echo "Checking out existing branch '$branch_name'"
    git checkout "$branch_name"
  else
    # Create new branch
    echo "Creating new branch '$branch_name'"
    git checkout -b "$branch_name"
  fi

  return 0
}

# ============================================================================
# SAFE OPERATIONS
# ============================================================================

# Safe checkout - blocks checkout to protected branches
safe_checkout() {
  local target="$1"

  if [[ $(is_protected_branch "$target") == "true" ]]; then
    echo "ICE: Cannot checkout to protected branch '$target'" >&2
    echo "Protected branches: ${PROTECTED_BRANCHES[*]}" >&2
    echo "Protected patterns: ${PROTECTED_PATTERNS[*]}" >&2
    log_ice_block "checkout" "$target"
    return 1
  fi

  git checkout "$target"
}

# Safe push - blocks push to protected branches
safe_push() {
  local remote="${1:-origin}"
  local branch="${2:-$(get_current_branch)}"

  if [[ -z "$branch" ]]; then
    echo "ERROR: Could not determine branch to push" >&2
    return 1
  fi

  if [[ $(is_protected_branch "$branch") == "true" ]]; then
    echo "ICE: Cannot push to protected branch '$branch'" >&2
    echo "Protected branches: ${PROTECTED_BRANCHES[*]}" >&2
    log_ice_block "push" "$branch"
    return 1
  fi

  git push "$remote" "$branch"
}

# Safe push with upstream tracking
safe_push_set_upstream() {
  local remote="$1"
  local branch="$2"

  if [[ $(is_protected_branch "$branch") == "true" ]]; then
    echo "ICE: Cannot push to protected branch '$branch'" >&2
    log_ice_block "push-upstream" "$branch"
    return 1
  fi

  git push -u "$remote" "$branch"
}

# Safe merge - ALWAYS BLOCKED
# Run Mode never merges. Humans merge PRs.
safe_merge() {
  echo "ICE: Merge operations are BLOCKED in Run Mode" >&2
  echo "Human intervention required to merge pull requests" >&2
  log_ice_block "merge" "any"
  return 1
}

# Safe PR merge - ALWAYS BLOCKED
safe_pr_merge() {
  echo "ICE: PR merge operations are BLOCKED in Run Mode" >&2
  echo "Human intervention required to merge pull requests" >&2
  log_ice_block "pr-merge" "any"
  return 1
}

# Safe branch delete - ALWAYS BLOCKED
safe_branch_delete() {
  local branch="${1:-}"
  echo "ICE: Branch deletion is BLOCKED in Run Mode" >&2
  echo "Human intervention required to delete branches" >&2
  log_ice_block "branch-delete" "$branch"
  return 1
}

# Safe force push - ALWAYS BLOCKED
safe_force_push() {
  echo "ICE: Force push is BLOCKED in Run Mode" >&2
  echo "Force pushing can cause data loss and is not permitted" >&2
  log_ice_block "force-push" "any"
  return 1
}

# Determine push mode based on config and optional override flag
# Args: override_flag (optional) - "local", "prompt", or ""
# Output: LOCAL, PROMPT, or AUTO
# Returns: 0 always (output indicates mode)
should_push() {
  local override_flag="${1:-}"

  # CLI flags take highest priority
  if [[ "$override_flag" == "local" ]]; then
    echo "LOCAL"
    return 0
  fi

  if [[ "$override_flag" == "prompt" ]]; then
    echo "PROMPT"
    return 0
  fi

  # Read from config if available
  if [[ -f "$REPO_ROOT/.loa.config.yaml" ]] && command -v yq &>/dev/null; then
    local config_value
    config_value=$(yq eval '.run_mode.git.auto_push // "true"' "$REPO_ROOT/.loa.config.yaml" 2>/dev/null || echo "true")

    case "$config_value" in
      true|"true")
        echo "AUTO"
        return 0
        ;;
      false|"false")
        echo "LOCAL"
        return 0
        ;;
      prompt|"prompt")
        echo "PROMPT"
        return 0
        ;;
      *)
        echo "ICE: Unknown auto_push value '$config_value', defaulting to AUTO" >&2
        echo "AUTO"
        return 0
        ;;
    esac
  fi

  # Default to AUTO for backwards compatibility (no config or no yq)
  echo "AUTO"
}

# Safe PR create - creates DRAFT PRs only
safe_pr_create() {
  local title="$1"
  local body="$2"
  local base="${3:-main}"
  local head="${4:-$(get_current_branch)}"

  if [[ -z "$head" ]]; then
    echo "ERROR: Could not determine head branch" >&2
    return 1
  fi

  # Verify we're not creating PR from protected branch
  if [[ $(is_protected_branch "$head") == "true" ]]; then
    echo "ICE: Cannot create PR from protected branch '$head'" >&2
    log_ice_block "pr-create" "$head"
    return 1
  fi

  echo "Creating DRAFT pull request..." >&2
  echo "  Title: $title" >&2
  echo "  Base: $base" >&2
  echo "  Head: $head" >&2

  # Always create as draft
  gh pr create \
    --draft \
    --title "$title" \
    --body "$body" \
    --base "$base" \
    --head "$head"
}

# ============================================================================
# CLI INTERFACE
# ============================================================================

show_usage() {
  cat << 'EOF'
run-mode-ice.sh - ICE (Git Safety Wrapper for Run Mode)

Usage: run-mode-ice.sh <command> [args...]

Commands:
  is-protected <branch>     Check if branch is protected (outputs true/false)
  validate                  Verify current branch is safe for operations
  ensure-branch <name>      Create or checkout a feature branch
  checkout <branch>         Safe checkout (blocks protected branches)
  push [remote] [branch]    Safe push (blocks protected branches)
  push-upstream <r> <b>     Safe push with -u flag
  merge                     ALWAYS BLOCKED - humans merge PRs
  pr-merge                  ALWAYS BLOCKED - humans merge PRs
  branch-delete [branch]    ALWAYS BLOCKED - humans delete branches
  force-push                ALWAYS BLOCKED - dangerous operation
  pr-create <title> <body>  Create DRAFT pull request only
  should-push [override]    Determine push mode (LOCAL, PROMPT, or AUTO)

Protected Branches (immutable, not configurable):
  main, master, staging, develop, development, production, prod
  release/*, release-*, hotfix/*, hotfix-*

Exit Codes:
  0 - Success
  1 - ICE block (protected branch or forbidden operation)
  2 - Usage error

Examples:
  run-mode-ice.sh is-protected main           # outputs: true
  run-mode-ice.sh is-protected feature/test   # outputs: false
  run-mode-ice.sh validate                    # check current branch
  run-mode-ice.sh ensure-branch sprint-7      # create feature/sprint-7
  run-mode-ice.sh push origin feature/test    # push to feature branch
  run-mode-ice.sh pr-create "Title" "Body"    # create draft PR
EOF
}

main() {
  if [[ $# -lt 1 ]]; then
    show_usage
    exit 2
  fi

  local command="$1"
  shift

  case "$command" in
    is-protected)
      if [[ $# -lt 1 ]]; then
        echo "Usage: run-mode-ice.sh is-protected <branch>" >&2
        exit 2
      fi
      is_protected_branch "$1"
      # Return 0 if protected (true), 1 if not (false)
      [[ $(is_protected_branch "$1") == "true" ]]
      ;;

    validate)
      validate_working_branch
      ;;

    ensure-branch)
      if [[ $# -lt 1 ]]; then
        echo "Usage: run-mode-ice.sh ensure-branch <name> [prefix]" >&2
        exit 2
      fi
      ensure_feature_branch "$@"
      ;;

    checkout)
      if [[ $# -lt 1 ]]; then
        echo "Usage: run-mode-ice.sh checkout <branch>" >&2
        exit 2
      fi
      safe_checkout "$1"
      ;;

    push)
      safe_push "${1:-origin}" "${2:-}"
      ;;

    push-upstream)
      if [[ $# -lt 2 ]]; then
        echo "Usage: run-mode-ice.sh push-upstream <remote> <branch>" >&2
        exit 2
      fi
      safe_push_set_upstream "$1" "$2"
      ;;

    merge)
      safe_merge
      ;;

    pr-merge)
      safe_pr_merge
      ;;

    branch-delete)
      safe_branch_delete "${1:-}"
      ;;

    force-push)
      safe_force_push
      ;;

    pr-create)
      if [[ $# -lt 2 ]]; then
        echo "Usage: run-mode-ice.sh pr-create <title> <body> [base] [head]" >&2
        exit 2
      fi
      safe_pr_create "$@"
      ;;

    should-push)
      should_push "${1:-}"
      ;;

    help|--help|-h)
      show_usage
      exit 0
      ;;

    *)
      echo "Unknown command: $command" >&2
      show_usage
      exit 2
      ;;
  esac
}

# Only run main if script is executed (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
