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
CHECK_SYMLINKS=false
RECONCILE_SYMLINKS=false
SOURCE_ONLY=false

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
    --check-symlinks)
      CHECK_SYMLINKS=true
      shift
      ;;
    --reconcile)
      RECONCILE_SYMLINKS=true
      shift
      ;;
    --source-only)
      # Allow sourcing this script for its functions without running main
      SOURCE_ONLY=true
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
      echo "  --check-symlinks  Check symlink health (no changes)"
      echo "  --reconcile       Check and fix symlink health"
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

# === Memory Stack Path Utility (Task 2.3 — cycle-035 sprint-2) ===
# Returns the canonical Memory Stack path, checking both new (.loa-state/)
# and legacy (.loa/) locations. Reusable across scripts.
# Returns: path on stdout, exit 0 if found, exit 1 if no Memory Stack exists.
get_memory_stack_path() {
  local project_root="${PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

  # Priority 1: New location (.loa-state/) — post-migration
  if [[ -d "${project_root}/.loa-state" ]]; then
    echo "${project_root}/.loa-state"
    return 0
  fi

  # Priority 2: Legacy location (.loa/) — only if NOT a git submodule
  if [[ -d "${project_root}/.loa" ]]; then
    if [[ -f "${project_root}/.gitmodules" ]] && grep -q ".loa" "${project_root}/.gitmodules" 2>/dev/null; then
      # .loa/ is a submodule, not Memory Stack data
      return 1
    fi
    echo "${project_root}/.loa"
    return 0
  fi

  return 1
}

# === Memory Stack Relocation (Flatline IMP-002) ===
# Safely relocates .loa/ Memory Stack data to .loa-state/ before submodule add
relocate_memory_stack() {
  local source=".loa"
  local target=".loa-state"
  local migration_lock="${target}/.migration-lock"

  if [[ ! -d "$source" ]]; then
    return 0  # Nothing to relocate
  fi

  # Skip if it's already a git submodule
  if [[ -f ".gitmodules" ]] && grep -q "$source" .gitmodules 2>/dev/null; then
    return 0  # Already a submodule, not Memory Stack data
  fi

  step "Relocating Memory Stack from .loa/ to .loa-state/..."

  # Create target directory for lock file
  mkdir -p "$target"

  # Acquire migration lock — prefer flock, fall back to PID+timestamp (F-003)
  # flock releases automatically on process death — no PID recycling risk.
  # Fallback uses PID + epoch timestamp — 1-hour staleness threshold prevents false-positive blocks.
  if command -v flock &>/dev/null; then
    exec 200>"$migration_lock"
    if ! flock -n 200; then
      err "Memory Stack migration already in progress."
    fi
  else
    # Fallback: PID + epoch timestamp for stale detection (>1 hour = stale)
    if [[ -f "$migration_lock" ]]; then
      local lock_info lock_pid lock_time
      lock_info=$(cat "$migration_lock" 2>/dev/null || echo "")
      lock_pid="${lock_info%%:*}"
      lock_time="${lock_info##*:}"
      local now; now=$(date +%s)
      if [[ -n "$lock_pid" ]] && kill -0 "$lock_pid" 2>/dev/null; then
        if [[ -n "$lock_time" ]] && (( now - lock_time < 3600 )); then
          err "Migration in progress (PID: $lock_pid, started $(( (now - lock_time) / 60 ))m ago)."
        fi
        warn "Stale lock (PID $lock_pid, >1h old). Removing."
      fi
      rm -f "$migration_lock"
    fi
    echo "$$:$(date +%s)" > "$migration_lock"
  fi

  # Copy-then-verify-then-switch (Flatline IMP-002)
  local source_count target_count
  source_count=$(find "$source" -type f | wc -l)

  # Handle empty directory (ADV-2)
  if [[ "$source_count" -eq 0 ]]; then
    rm -rf "$source"
    rm -f "$migration_lock"
    log "Memory Stack was empty, removed .loa/"
    return 0
  fi

  if ! cp -r "$source"/. "$target"/ 2>/dev/null; then
    # Rollback: remove partial target
    rm -rf "$target"
    err "Memory Stack copy failed. Original data preserved at .loa/"
  fi

  target_count=$(find "$target" -type f -not -name ".migration-lock" | wc -l)

  if [[ "$source_count" -ne "$target_count" ]]; then
    # Rollback: remove partial target
    rm -f "$migration_lock"
    rm -rf "$target"
    err "Memory Stack verification failed (source: $source_count files, target: $target_count files). Original data preserved at .loa/"
  fi

  # Verification passed — remove source
  rm -rf "$source"
  rm -f "$migration_lock"

  log "Memory Stack relocated: .loa/ -> .loa-state/ ($source_count files)"
}

# === Auto-Init Submodule (post-clone recovery) ===
auto_init_submodule() {
  if [[ -f ".gitmodules" ]] && grep -q "$SUBMODULE_PATH" .gitmodules 2>/dev/null; then
    if [[ ! -d "$SUBMODULE_PATH/.claude" ]]; then
      step "Initializing uninitialized submodule..."
      git submodule update --init "$SUBMODULE_PATH" || {
        err "Failed to initialize submodule. Run: git submodule update --init $SUBMODULE_PATH"
      }
      log "Submodule initialized"
    fi
  fi
}

# === Pre-flight Checks ===
preflight() {
  log "Running pre-flight checks..."

  # Check we're in a git repo
  if ! git rev-parse --git-dir > /dev/null 2>&1; then
    err "Not a git repository. Initialize with 'git init' first."
  fi

  # Relocate Memory Stack if .loa/ contains non-submodule data (Flatline IMP-002)
  relocate_memory_stack

  # Auto-init submodule if already registered but not initialized
  auto_init_submodule

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
    # Allow .claude/ to exist if it contains user-owned files (overrides, config)
    # Just warn instead of erroring — create_symlinks handles merging
    warn ".claude/ directory exists and is not a symlink. Existing files will be preserved."
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

# === Authoritative Symlink Manifest (DRY — Bridgebuilder Tension 1) ===
# Sourced from shared library: lib/symlink-manifest.sh
# To add a new symlink target, change ONLY the library file — all consumers inherit.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/symlink-manifest.sh"

# === Create Symlinks ===
# Consumes get_symlink_manifest() — single source of truth for symlink topology.
create_symlinks() {
  step "Creating symlinks from .claude/ to submodule..."

  # Remove existing .claude if it's a symlink or empty
  if [[ -L ".claude" ]]; then
    rm -f ".claude"
  fi

  # Create .claude directory structure
  mkdir -p .claude .claude/skills .claude/commands .claude/loa

  # Load authoritative manifest
  get_symlink_manifest "$SUBMODULE_PATH"

  # Phase 1: Directory symlinks
  step "Linking directories..."
  for entry in "${MANIFEST_DIR_SYMLINKS[@]}"; do
    local link_path="${entry%%:*}"
    local target="${entry#*:}"
    # MED-004 FIX: Use safe_symlink with validation
    safe_symlink "$link_path" "$target"
    log "  Linked: ${link_path}/"
  done

  # Phase 2: File/nested symlinks
  step "Linking files..."
  for entry in "${MANIFEST_FILE_SYMLINKS[@]}"; do
    local link_path="${entry%%:*}"
    local target="${entry#*:}"
    local parent_dir
    parent_dir=$(dirname "$link_path")
    mkdir -p "$parent_dir"
    safe_symlink "$link_path" "$target"
    log "  Linked: ${link_path}"
  done

  # Phase 3: Per-skill symlinks (dynamic from manifest)
  step "Linking skills..."
  for entry in "${MANIFEST_SKILL_SYMLINKS[@]}"; do
    local link_path="${entry%%:*}"
    local target="${entry#*:}"
    local skill_name
    skill_name=$(basename "$link_path")
    safe_symlink "$link_path" "$target"
    log "  Linked skill: $skill_name"
  done

  # Phase 4: Per-command symlinks (dynamic from manifest)
  step "Linking commands..."
  for entry in "${MANIFEST_CMD_SYMLINKS[@]}"; do
    local link_path="${entry%%:*}"
    local target="${entry#*:}"
    local cmd_name
    cmd_name=$(basename "$link_path")
    safe_symlink "$link_path" "$target"
    log "  Linked command: $cmd_name"
  done

  # Also link settings.local.json if it exists (not in manifest — optional file)
  if [[ -f "$SUBMODULE_PATH/.claude/settings.local.json" ]]; then
    safe_symlink ".claude/settings.local.json" "../$SUBMODULE_PATH/.claude/settings.local.json"
    log "  Linked: .claude/settings.local.json"
  fi

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

  # --no-verify: Framework install commits only touch tooling (symlinks, manifests, .gitignore).
  # User pre-commit hooks (lint, typecheck, test) target app code and would fail on framework-only changes.
  git commit -m "$commit_msg" --no-verify 2>/dev/null || {
    warn "Failed to create commit"
    return 1
  }

  log "Created commit"
}

# === Update .gitignore for Submodule Mode (Task 1.6) ===
update_gitignore_for_submodule() {
  step "Updating .gitignore for submodule mode..."

  local gitignore=".gitignore"
  touch "$gitignore"

  # Symlink entries — these are created by mount-submodule.sh and should not be tracked
  local symlink_entries=(
    ".claude/scripts"
    ".claude/protocols"
    ".claude/hooks"
    ".claude/data"
    ".claude/schemas"
    ".claude/loa/CLAUDE.loa.md"
    ".claude/loa/reference"
    ".claude/loa/feedback-ontology.yaml"
    ".claude/loa/learnings"
    ".claude/settings.json"
    ".claude/checksums.json"
  )

  # State and backup entries (not symlinks but must be gitignored)
  local state_entries=(
    ".loa-state/"
    ".claude.backup.*"
  )

  # Add header if not present
  if ! grep -q "LOA SUBMODULE SYMLINKS" "$gitignore" 2>/dev/null; then
    echo "" >> "$gitignore"
    echo "# LOA SUBMODULE SYMLINKS (added by mount-submodule.sh)" >> "$gitignore"
    echo "# Symlinks to .loa/ submodule — recreated on mount" >> "$gitignore"
  fi

  # Add each entry if not already present
  for entry in "${symlink_entries[@]}" "${state_entries[@]}"; do
    grep -qxF "$entry" "$gitignore" 2>/dev/null || echo "$entry" >> "$gitignore"
  done

  # Remove .loa/ from gitignore if present (submodule must be tracked)
  if grep -q "^\.loa/$" "$gitignore" 2>/dev/null; then
    sed -i '/^\.loa\/$/d' "$gitignore"
    log "  Removed .loa/ from .gitignore (submodule must be tracked)"
  fi

  log ".gitignore updated for submodule mode"
}

# === Verify and Reconcile Symlinks (Task 2.6 — cycle-035 sprint-2) ===
# Authoritative symlink manifest. Detects dangling, removes stale, recreates from manifest.
# Uses canonical path resolver (realpath) to avoid CWD assumptions (Flatline SKP-002).
# Returns: 0 if all healthy, 1 if issues were found (and fixed in reconcile mode).
verify_and_reconcile_symlinks() {
  local reconcile="${1:-true}"  # true = fix issues, false = check only
  local repo_root
  repo_root=$(get_repo_root)

  local submodule="${SUBMODULE_PATH:-.loa}"
  local fixed=0
  local dangling=0
  local stale=0
  local ok=0

  # Load authoritative manifest (DRY — single source of truth)
  get_symlink_manifest "$submodule" "$repo_root"
  local -a all_symlinks=("${MANIFEST_DIR_SYMLINKS[@]}" "${MANIFEST_FILE_SYMLINKS[@]}" "${MANIFEST_SKILL_SYMLINKS[@]}" "${MANIFEST_CMD_SYMLINKS[@]}")

  step "Verifying ${#all_symlinks[@]} symlinks..."

  for entry in "${all_symlinks[@]}"; do
    local link_path="${entry%%:*}"
    local target="${entry#*:}"
    local full_link="${repo_root}/${link_path}"

    if [[ -L "$full_link" ]]; then
      # Check if dangling
      if [[ ! -e "$full_link" ]]; then
        dangling=$((dangling + 1))
        warn "  DANGLING: $link_path"
        if [[ "$reconcile" == "true" ]]; then
          rm -f "$full_link"
          local parent_dir
          parent_dir=$(dirname "$full_link")
          mkdir -p "$parent_dir"
          ln -sf "$target" "$full_link"
          fixed=$((fixed + 1))
          log "  FIXED: $link_path"
        fi
      else
        ok=$((ok + 1))
      fi
    elif [[ -e "$full_link" ]]; then
      # Exists but not a symlink — skip (user-owned file)
      ok=$((ok + 1))
    else
      # Missing entirely
      stale=$((stale + 1))
      warn "  MISSING: $link_path"
      if [[ "$reconcile" == "true" ]]; then
        local parent_dir
        parent_dir=$(dirname "$full_link")
        mkdir -p "$parent_dir"
        # Only create if target exists in submodule
        local resolved_target
        resolved_target=$(cd "$(dirname "$full_link")" 2>/dev/null && realpath -m "$target" 2>/dev/null || echo "")
        if [[ -n "$resolved_target" && -e "$resolved_target" ]]; then
          ln -sf "$target" "$full_link"
          fixed=$((fixed + 1))
          log "  CREATED: $link_path"
        fi
      fi
    fi
  done

  # Summary
  echo ""
  log "Symlink health: ${ok} ok, ${dangling} dangling, ${stale} missing, ${fixed} fixed"

  if [[ $((dangling + stale)) -gt 0 && "$reconcile" != "true" ]]; then
    return 1
  fi
  return 0
}

# === Check Symlinks Subcommand (Task 2.6) ===
# Standalone health check: mount-submodule.sh --check-symlinks
check_symlinks_subcommand() {
  echo ""
  log "======================================================================="
  log "  Symlink Health Check"
  log "======================================================================="
  echo ""
  verify_and_reconcile_symlinks "false"
  local result=$?
  if [[ $result -eq 0 ]]; then
    log "All symlinks healthy."
  else
    warn "Symlink issues detected. Run with --reconcile to fix."
  fi
  exit $result
}

# === Main ===
main() {
  # Route to subcommands
  if [[ "$SOURCE_ONLY" == "true" ]]; then
    return 0
  fi
  if [[ "$CHECK_SYMLINKS" == "true" ]]; then
    check_symlinks_subcommand
  fi
  if [[ "$RECONCILE_SYMLINKS" == "true" ]]; then
    echo ""
    log "Reconciling symlinks..."
    verify_and_reconcile_symlinks "true"
    exit $?
  fi

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
  update_gitignore_for_submodule
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
