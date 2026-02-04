#!/usr/bin/env bash
# bootstrap.sh - Workspace context initialization
# Version: 1.0.0
#
# Sourced by all Loa scripts before any other operations.
# Establishes PROJECT_ROOT and sources path-lib.sh.
#
# Usage:
#   source "$SCRIPT_DIR/bootstrap.sh"
#
# Environment Variables Set:
#   PROJECT_ROOT - Canonical workspace root path
#   CONFIG_FILE  - Path to .loa.config.yaml
#
# Detection Priority:
#   1. Existing PROJECT_ROOT (inheritance from parent script)
#   2. git rev-parse --show-toplevel (git repo root)
#   3. Walk up to find .claude/ directory
#   4. Walk up to find .loa.config.yaml file
#   5. Fallback to current directory (with warning)

set -euo pipefail

# =============================================================================
# PROJECT_ROOT Detection
# =============================================================================

_detect_project_root() {
  # Strategy 1: Git repository root (handles worktrees and submodules)
  if command -v git &>/dev/null; then
    local git_root
    # --show-toplevel works with worktrees
    # For submodules, it returns the submodule root, which is correct
    git_root=$(git rev-parse --show-toplevel 2>/dev/null) || true
    if [[ -n "$git_root" && -d "$git_root" ]]; then
      echo "$git_root"
      return 0
    fi
  fi

  # Strategy 2: Walk up looking for .claude/ directory
  local dir="$PWD"
  while [[ "$dir" != "/" ]]; do
    if [[ -d "$dir/.claude" ]]; then
      echo "$dir"
      return 0
    fi
    dir=$(dirname "$dir")
  done

  # Strategy 3: Walk up looking for .loa.config.yaml
  dir="$PWD"
  while [[ "$dir" != "/" ]]; do
    if [[ -f "$dir/.loa.config.yaml" ]]; then
      echo "$dir"
      return 0
    fi
    dir=$(dirname "$dir")
  done

  # Fallback: current directory (may be wrong)
  echo "WARNING: Could not detect PROJECT_ROOT, using current directory" >&2
  echo "$PWD"
  return 1
}

# Only initialize if not already set (allows inheritance from parent script)
if [[ -z "${PROJECT_ROOT:-}" ]]; then
  PROJECT_ROOT=$(_detect_project_root)
fi

# Canonicalize PROJECT_ROOT to absolute path
# Use realpath for consistency across all scripts
if command -v realpath &>/dev/null; then
  PROJECT_ROOT=$(realpath "$PROJECT_ROOT")
else
  # Fallback for systems without realpath (rare)
  PROJECT_ROOT=$(cd "$PROJECT_ROOT" && pwd)
fi
export PROJECT_ROOT

# Config file location
CONFIG_FILE="${PROJECT_ROOT}/.loa.config.yaml"
export CONFIG_FILE

# =============================================================================
# Source Path Library
# =============================================================================

# Determine script directory (may differ from PROJECT_ROOT/.claude/scripts if symlinked)
_BOOTSTRAP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source path-lib.sh if it exists
if [[ -f "$_BOOTSTRAP_DIR/path-lib.sh" ]]; then
  source "$_BOOTSTRAP_DIR/path-lib.sh"
fi

# Cleanup internal variable
unset _BOOTSTRAP_DIR
