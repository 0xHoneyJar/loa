#!/usr/bin/env bash
# mount-submodule.sh - Install Loa as a git submodule
# path-lib: exempt
#
# Note: This script bootstraps the project BEFORE path-lib.sh exists.
# It must use hardcoded default paths to create the initial structure.
#
# This script installs Loa as a git submodule at .loa/, then creates symlinks
# from the standard .claude/ locations to the submodule content. This provides:
# - Version isolation (pin to specific commit/tag)
# - Easy version switching (git submodule update)
# - Clean separation of framework from project code
#
# Usage:
#   mount-submodule.sh [OPTIONS]
#
# Options:
#   --branch <name>   Loa branch to use (default: main)
#   --tag <tag>       Loa tag to pin to (e.g., v1.15.0)
#   --ref <ref>       Loa ref to pin to (commit, branch, or tag)
#   --force           Force remount without prompting
#   --no-commit       Skip creating git commit after mount
#   -h, --help        Show this help message
#
set -euo pipefail

# MED-001 FIX: Set restrictive umask for secure temp file creation
umask 077

# === Colors ===
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

# === Logging ===
log() { echo -e "${GREEN}[loa-submodule]${NC} $*"; }
warn() { echo -e "${YELLOW}[loa-submodule]${NC} WARNING: $*"; }
err() { echo -e "${RED}[loa-submodule]${NC} ERROR: $*" >&2; exit 1; }
info() { echo -e "${CYAN}[loa-submodule]${NC} $*"; }
step() { echo -e "${BLUE}[loa-submodule]${NC} -> $*"; }

# === Configuration ===
LOA_REMOTE_URL="${LOA_UPSTREAM:-https://github.com/0xHoneyJar/loa.git}"
LOA_BRANCH="main"
LOA_TAG=""
LOA_REF=""
SUBMODULE_PATH=".loa"
VERSION_FILE=".loa-version.json"
CONFIG_FILE=".loa.config.yaml"
FORCE_MODE=false
NO_COMMIT=false

# === Argument Parsing ===
while [[ $# -gt 0 ]]; do
  case $1 in
    --branch)
      LOA_BRANCH="$2"
      shift 2
      ;;
    --tag)
      LOA_TAG="$2"
      shift 2
      ;;
    --ref)
      LOA_REF="$2"
      shift 2
      ;;
    --force|-f)
      FORCE_MODE=true
      shift
      ;;
    --no-commit)
      NO_COMMIT=true
      shift
      ;;
    -h|--help)
      echo "Usage: mount-submodule.sh [OPTIONS]"
      echo ""
      echo "Install Loa as a git submodule with symlinks."
      echo ""
      echo "Options:"
      echo "  --branch <name>   Loa branch to use (default: main)"
      echo "  --tag <tag>       Loa tag to pin to (e.g., v1.15.0)"
      echo "  --ref <ref>       Loa ref to pin to (commit, branch, or tag)"
      echo "  --force, -f       Force remount without prompting"
      echo "  --no-commit       Skip creating git commit after mount"
      echo "  -h, --help        Show this help message"
      echo ""
      echo "Examples:"
      echo "  mount-submodule.sh                    # Latest main"
      echo "  mount-submodule.sh --tag v1.15.0      # Specific tag"
      echo "  mount-submodule.sh --branch feature/x # Specific branch"
      echo ""
      exit 0
      ;;
    *)
      warn "Unknown option: $1"
      shift
      ;;
  esac
done

# Determine effective ref
get_effective_ref() {
  if [[ -n "$LOA_REF" ]]; then
    echo "$LOA_REF"
  elif [[ -n "$LOA_TAG" ]]; then
    echo "$LOA_TAG"
  else
    echo "$LOA_BRANCH"
  fi
}

# === yq compatibility ===
yq_read() {
  local file="$1"
  local path="$2"
  local default="${3:-}"

  if yq --version 2>&1 | grep -q "mikefarah"; then
    yq eval "${path} // \"${default}\"" "$file" 2>/dev/null
  else
    yq -r "${path} // \"${default}\"" "$file" 2>/dev/null
  fi
}

# === Pre-flight Checks ===
preflight() {
  log "Running pre-flight checks..."

  # Check we're in a git repo
  if ! git rev-parse --git-dir > /dev/null 2>&1; then
    err "Not a git repository. Initialize with 'git init' first."
  fi

  # Check if standard mount already exists
  if [[ -f "$VERSION_FILE" ]]; then
    local mode=$(jq -r '.installation_mode // "standard"' "$VERSION_FILE" 2>/dev/null)
    if [[ "$mode" == "standard" ]]; then
      err "Loa is installed in standard mode. Cannot switch to submodule mode."
    fi
    if [[ "$mode" == "submodule" ]]; then
      warn "Loa submodule already installed"
      if [[ "$FORCE_MODE" != "true" ]]; then
        read -p "Remount/update? (y/N) " -n 1 -r
        echo ""
        [[ $REPLY =~ ^[Yy]$ ]] || { log "Aborted."; exit 0; }
      fi
    fi
  fi

  # Check for existing .claude directory (non-symlink)
  if [[ -d ".claude" ]] && [[ ! -L ".claude" ]]; then
    err ".claude/ directory exists and is not a symlink. Run mount-loa.sh for standard mode."
  fi

  # Check for required tools
  command -v git >/dev/null || err "git is required"
  command -v jq >/dev/null || err "jq is required"
  command -v ln >/dev/null || err "ln is required"

  log "Pre-flight checks passed"
}

# === Add Submodule ===
add_submodule() {
  local ref=$(get_effective_ref)
  step "Adding Loa as git submodule at $SUBMODULE_PATH..."

  # Remove existing if force mode
  if [[ -d "$SUBMODULE_PATH" ]] || [[ -f ".gitmodules" ]] && grep -q "$SUBMODULE_PATH" .gitmodules 2>/dev/null; then
    if [[ "$FORCE_MODE" == "true" ]]; then
      step "Removing existing submodule..."
      git submodule deinit -f "$SUBMODULE_PATH" 2>/dev/null || true
      git rm -f "$SUBMODULE_PATH" 2>/dev/null || true
      rm -rf ".git/modules/$SUBMODULE_PATH" 2>/dev/null || true
      rm -rf "$SUBMODULE_PATH" 2>/dev/null || true
    else
      err "Submodule already exists. Use --force to remount."
    fi
  fi

  # Add submodule
  git submodule add -b "$LOA_BRANCH" "$LOA_REMOTE_URL" "$SUBMODULE_PATH"

  # If specific tag or ref specified, checkout to it
  if [[ -n "$LOA_TAG" ]] || [[ -n "$LOA_REF" ]]; then
    step "Checking out ref: $ref..."
    (cd "$SUBMODULE_PATH" && git checkout "$ref")
  fi

  log "Submodule added at $SUBMODULE_PATH"
}

# === MED-004 FIX: Symlink Target Validation ===
# Validate that symlink targets don't escape repository bounds

# Get the repository root directory (absolute path)
get_repo_root() {
  git rev-parse --show-toplevel 2>/dev/null || pwd
}

# Validate that a path is within the repository bounds
# Args: $1 - target path to validate
# Returns: 0 if safe, 1 if escapes bounds
validate_symlink_target() {
  local target="$1"
  local repo_root
  repo_root=$(get_repo_root)

  # Resolve the target to an absolute path
  local resolved_target
  if [[ -e "$target" ]]; then
    resolved_target=$(cd "$(dirname "$target")" && pwd)/$(basename "$target")
  else
    # For not-yet-existing paths, resolve the parent
    local parent_dir
    parent_dir=$(dirname "$target")
    if [[ -d "$parent_dir" ]]; then
      resolved_target=$(cd "$parent_dir" && pwd)/$(basename "$target")
    else
      # Cannot resolve, allow but warn
      warn "Cannot resolve symlink target: $target"
      return 0
    fi
  fi

  # Normalize paths (remove trailing slashes, resolve ..)
  repo_root=$(realpath "$repo_root" 2>/dev/null || echo "$repo_root")
  resolved_target=$(realpath "$resolved_target" 2>/dev/null || echo "$resolved_target")

  # Check if resolved target starts with repo root
  if [[ "$resolved_target" != "$repo_root"* ]]; then
    err "Security: Symlink target escapes repository bounds: $target"
    err "  Target resolves to: $resolved_target"
    err "  Repository root: $repo_root"
    return 1
  fi

  return 0
}

# Create symlink with security validation
# Args: $1 - source (symlink file), $2 - target (what symlink points to)
safe_symlink() {
  local source="$1"
  local target="$2"

  # Validate target is within repository
  if ! validate_symlink_target "$target"; then
    return 1
  fi

  ln -sf "$target" "$source"
}

# === Create Symlinks ===
create_symlinks() {
  step "Creating symlinks from .claude/ to submodule..."

  # Remove existing .claude if it's a symlink or empty
  if [[ -L ".claude" ]]; then
    rm -f ".claude"
  fi

  # Create .claude directory structure
  mkdir -p .claude

  # === Skills Symlinks ===
  step "Linking skills..."
  mkdir -p .claude/skills
  if [[ -d "$SUBMODULE_PATH/.claude/skills" ]]; then
    for skill_dir in "$SUBMODULE_PATH"/.claude/skills/*/; do
      if [[ -d "$skill_dir" ]]; then
        local skill_name=$(basename "$skill_dir")
        # MED-004 FIX: Use safe_symlink with validation
        safe_symlink ".claude/skills/$skill_name" "../../$SUBMODULE_PATH/.claude/skills/$skill_name"
        log "  Linked skill: $skill_name"
      fi
    done
  fi

  # === Commands Symlinks ===
  step "Linking commands..."
  mkdir -p .claude/commands
  if [[ -d "$SUBMODULE_PATH/.claude/commands" ]]; then
    for cmd_file in "$SUBMODULE_PATH"/.claude/commands/*.md; do
      if [[ -f "$cmd_file" ]]; then
        local cmd_name=$(basename "$cmd_file")
        # MED-004 FIX: Use safe_symlink with validation
        safe_symlink ".claude/commands/$cmd_name" "../../$SUBMODULE_PATH/.claude/commands/$cmd_name"
        log "  Linked command: $cmd_name"
      fi
    done
  fi

  # === Scripts Directory Symlink ===
  step "Linking scripts directory..."
  if [[ -d "$SUBMODULE_PATH/.claude/scripts" ]]; then
    # MED-004 FIX: Use safe_symlink with validation
    safe_symlink ".claude/scripts" "../$SUBMODULE_PATH/.claude/scripts"
    log "  Linked: .claude/scripts/"
  fi

  # === Protocols Directory Symlink ===
  step "Linking protocols directory..."
  if [[ -d "$SUBMODULE_PATH/.claude/protocols" ]]; then
    # MED-004 FIX: Use safe_symlink with validation
    safe_symlink ".claude/protocols" "../$SUBMODULE_PATH/.claude/protocols"
    log "  Linked: .claude/protocols/"
  fi

  # === Schemas Directory Symlink ===
  step "Linking schemas directory..."
  if [[ -d "$SUBMODULE_PATH/.claude/schemas" ]]; then
    # MED-004 FIX: Use safe_symlink with validation
    safe_symlink ".claude/schemas" "../$SUBMODULE_PATH/.claude/schemas"
    log "  Linked: .claude/schemas/"
  fi

  # === Loa Directory (CLAUDE.loa.md) ===
  step "Linking loa directory..."
  mkdir -p .claude/loa
  if [[ -f "$SUBMODULE_PATH/.claude/loa/CLAUDE.loa.md" ]]; then
    # MED-004 FIX: Use safe_symlink with validation
    safe_symlink ".claude/loa/CLAUDE.loa.md" "../../$SUBMODULE_PATH/.claude/loa/CLAUDE.loa.md"
    log "  Linked: .claude/loa/CLAUDE.loa.md"
  fi

  # === Settings and other root files ===
  step "Linking settings files..."
  for config_file in settings.json settings.local.json checksums.json; do
    if [[ -f "$SUBMODULE_PATH/.claude/$config_file" ]]; then
      # MED-004 FIX: Use safe_symlink with validation
      safe_symlink ".claude/$config_file" "../$SUBMODULE_PATH/.claude/$config_file"
      log "  Linked: .claude/$config_file"
    fi
  done

  # === Create overrides directory (user-owned) ===
  mkdir -p .claude/overrides
  if [[ ! -f .claude/overrides/README.md ]]; then
    cat > .claude/overrides/README.md << 'EOF'
# User Overrides

Files here override the symlinked framework content.
This directory is NOT a symlink - you own these files.

To override a skill, copy it from .loa/.claude/skills/{name}/ to here.
To override a command, copy from .loa/.claude/commands/{name}.md.
EOF
    log "  Created: .claude/overrides/README.md"
  fi

  log "Symlinks created"
}

# === Create CLAUDE.md ===
create_claude_md() {
  local file="CLAUDE.md"

  if [[ -f "$file" ]]; then
    # Check if already has import
    if grep -q "@.claude/loa/CLAUDE.loa.md" "$file" 2>/dev/null; then
      log "CLAUDE.md already has @ import"
      return 0
    fi
    warn "CLAUDE.md exists without Loa import"
    info "Add this line at the top of CLAUDE.md:"
    echo ""
    echo -e "  ${CYAN}@.claude/loa/CLAUDE.loa.md${NC}"
    echo ""
    return 0
  fi

  step "Creating CLAUDE.md with @ import..."
  cat > "$file" << 'EOF'
@.claude/loa/CLAUDE.loa.md

# Project-Specific Instructions

> This file contains project-specific customizations that take precedence over the framework instructions.
> The framework instructions are loaded via the `@` import above.

## Project Configuration

Add your project-specific Claude Code instructions here.
EOF

  log "Created CLAUDE.md with @ import pattern"
}

# === Create Config ===
create_config() {
  if [[ -f "$CONFIG_FILE" ]]; then
    log "Config file already exists"
    return 0
  fi

  step "Creating configuration file..."

  cat > "$CONFIG_FILE" << 'EOF'
# Loa Framework Configuration (Submodule Mode)
# This file is yours to customize - framework updates will never modify it

# Installation mode (DO NOT CHANGE - use mount-loa.sh to switch to standard)
installation_mode: submodule

# Submodule settings
submodule:
  path: .loa
  # ref: main  # Uncomment to track specific ref

# =============================================================================
# Persistence Mode
# =============================================================================
persistence_mode: standard

# =============================================================================
# Integrity Enforcement
# =============================================================================
# Note: Submodule mode uses git submodule integrity instead of checksums
integrity_enforcement: warn

# =============================================================================
# Agent Configuration
# =============================================================================
disabled_agents: []

# =============================================================================
# Structured Memory
# =============================================================================
memory:
  notes_file: grimoires/loa/NOTES.md
  trajectory_dir: grimoires/loa/a2a/trajectory
  trajectory_retention_days: 30

# =============================================================================
# Context Hygiene
# =============================================================================
compaction:
  enabled: true
  threshold: 5

# =============================================================================
# Integrations
# =============================================================================
integrations:
  - github
EOF

  log "Created config file"
}

# === Create Version Manifest ===
create_manifest() {
  step "Creating version manifest..."

  local ref=$(get_effective_ref)
  local submodule_commit=""
  local framework_version=""

  # Get submodule commit
  if [[ -d "$SUBMODULE_PATH" ]]; then
    submodule_commit=$(cd "$SUBMODULE_PATH" && git rev-parse HEAD)
    framework_version=$(cd "$SUBMODULE_PATH" && git describe --tags --always 2>/dev/null || echo "$ref")
  fi

  cat > "$VERSION_FILE" << EOF
{
  "framework_version": "$framework_version",
  "schema_version": 2,
  "installation_mode": "submodule",
  "submodule": {
    "path": "$SUBMODULE_PATH",
    "ref": "$ref",
    "commit": "$submodule_commit"
  },
  "last_sync": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "zones": {
    "system": ".claude",
    "submodule": "$SUBMODULE_PATH/.claude",
    "state": ["grimoires/loa", ".beads"],
    "app": ["src", "lib", "app"]
  }
}
EOF

  log "Version manifest created"
}

# === Initialize State Zone ===
init_state_zone() {
  step "Initializing State Zone..."

  # Create grimoires structure
  mkdir -p grimoires/loa/{context,discovery,a2a/trajectory}
  touch grimoires/loa/.gitkeep

  # Create NOTES.md if missing
  local notes_file="grimoires/loa/NOTES.md"
  if [[ ! -f "$notes_file" ]]; then
    cat > "$notes_file" << 'EOF'
# Agent Working Memory (NOTES.md)

> This file persists agent context across sessions and compaction cycles.
> Updated automatically by agents. Manual edits are preserved.

## Active Sub-Goals
<!-- Current objectives being pursued -->

## Discovered Technical Debt
<!-- Issues found during implementation that need future attention -->

## Blockers & Dependencies
<!-- External factors affecting progress -->

## Session Continuity
<!-- Key context to restore on next session -->
| Timestamp | Agent | Summary |
|-----------|-------|---------|

## Decision Log
<!-- Major decisions with rationale -->
EOF
    log "Created NOTES.md"
  fi

  # Create .beads directory
  mkdir -p .beads
  touch .beads/.gitkeep

  log "State Zone initialized"
}

# === Create Commit ===
create_commit() {
  if [[ "$NO_COMMIT" == "true" ]]; then
    log "Skipping commit (--no-commit)"
    return 0
  fi

  step "Creating git commit..."

  local ref=$(get_effective_ref)

  git add .gitmodules "$SUBMODULE_PATH" .claude CLAUDE.md "$CONFIG_FILE" "$VERSION_FILE" grimoires 2>/dev/null || true

  if git diff --cached --quiet 2>/dev/null; then
    log "No changes to commit"
    return 0
  fi

  local commit_msg="chore(loa): mount framework as submodule (ref: $ref)

- Added Loa as git submodule at $SUBMODULE_PATH
- Created .claude/ symlinks to submodule content
- Created CLAUDE.md with @ import pattern
- Initialized State Zone (grimoires/loa/)

Installation mode: submodule
To update: git submodule update --remote $SUBMODULE_PATH

Generated by Loa mount-submodule.sh"

  git commit -m "$commit_msg" --no-verify 2>/dev/null || {
    warn "Failed to create commit"
    return 1
  }

  log "Created commit"
}

# === Main ===
main() {
  echo ""
  log "======================================================================="
  log "  Loa Framework Mount (Submodule Mode)"
  log "======================================================================="
  log "  Submodule: $SUBMODULE_PATH"
  log "  Ref: $(get_effective_ref)"
  echo ""

  preflight
  add_submodule
  create_symlinks
  create_claude_md
  create_config
  create_manifest
  init_state_zone
  create_commit

  echo ""
  log "======================================================================="
  log "  Loa Successfully Mounted (Submodule Mode)"
  log "======================================================================="
  echo ""
  info "Installation: $SUBMODULE_PATH (git submodule)"
  info "Symlinks: .claude/ -> $SUBMODULE_PATH/.claude/"
  info "Config: $CONFIG_FILE"
  echo ""
  info "To update Loa:"
  echo "  git submodule update --remote $SUBMODULE_PATH"
  echo ""
  info "To pin to specific version:"
  echo "  cd $SUBMODULE_PATH && git checkout v1.15.0 && cd .."
  echo "  git add $SUBMODULE_PATH && git commit -m 'Pin Loa to v1.15.0'"
  echo ""
  info "Next steps:"
  info "  1. Run 'claude' to start Claude Code"
  info "  2. Issue '/ride' to analyze this codebase"
  info "  3. Or '/loa' for guided workflow"
  echo ""
}

main "$@"
