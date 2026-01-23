#!/usr/bin/env bash
# Loa Framework: Mount Script
# The Loa mounts your repository and rides alongside your project
set -euo pipefail

# === Colors ===
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[loa]${NC} $*"; }
warn() { echo -e "${YELLOW}[loa]${NC} $*"; }
err() { echo -e "${RED}[loa]${NC} ERROR: $*" >&2; exit 1; }
info() { echo -e "${CYAN}[loa]${NC} $*"; }
step() { echo -e "${BLUE}[loa]${NC} -> $*"; }

# === Configuration ===
LOA_REMOTE_URL="${LOA_UPSTREAM:-https://github.com/0xHoneyJar/loa.git}"
LOA_REMOTE_NAME="loa-upstream"
LOA_BRANCH="${LOA_BRANCH:-main}"
VERSION_FILE=".loa-version.json"
CONFIG_FILE=".loa.config.yaml"
CHECKSUMS_FILE=".claude/checksums.json"
SKIP_BEADS=false
STEALTH_MODE=false
FORCE_MODE=false
NO_COMMIT=false

# === Argument Parsing ===
while [[ $# -gt 0 ]]; do
  case $1 in
    --branch)
      LOA_BRANCH="$2"
      shift 2
      ;;
    --stealth)
      STEALTH_MODE=true
      shift
      ;;
    --skip-beads)
      SKIP_BEADS=true
      shift
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
      echo "Usage: mount-loa.sh [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --branch <name>   Loa branch to use (default: main)"
      echo "  --force, -f       Force remount without prompting (use for curl | bash)"
      echo "  --stealth         Add state files to .gitignore"
      echo "  --skip-beads      Don't install/initialize Beads CLI"
      echo "  --no-commit       Skip creating git commit after mount"
      echo "  -h, --help        Show this help message"
      echo ""
      echo "Recovery install (when /update is broken):"
      echo "  curl -fsSL https://raw.githubusercontent.com/0xHoneyJar/loa/main/.claude/scripts/mount-loa.sh | bash -s -- --force"
      exit 0
      ;;
    *)
      warn "Unknown option: $1"
      shift
      ;;
  esac
done

# yq compatibility (handles both mikefarah/yq and kislyuk/yq)
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

yq_to_json() {
  local file="$1"
  if yq --version 2>&1 | grep -q "mikefarah"; then
    yq eval '.' "$file" -o=json 2>/dev/null
  else
    yq . "$file" 2>/dev/null
  fi
}

# === Pre-flight Checks ===
preflight() {
  log "Running pre-flight checks..."

  if ! git rev-parse --git-dir > /dev/null 2>&1; then
    err "Not a git repository. Initialize with 'git init' first."
  fi

  if [[ -f "$VERSION_FILE" ]]; then
    local existing=$(jq -r '.framework_version // "unknown"' "$VERSION_FILE" 2>/dev/null)
    warn "Loa is already mounted (version: $existing)"
    if [[ "$FORCE_MODE" == "true" ]]; then
      log "Force mode enabled, proceeding with remount..."
    else
      # Check if stdin is a terminal (interactive mode)
      if [[ -t 0 ]]; then
        read -p "Remount/upgrade? This will reset the System Zone. (y/N) " -n 1 -r
        echo ""
        [[ $REPLY =~ ^[Yy]$ ]] || { log "Aborted."; exit 0; }
      else
        err "Loa already installed. Use --force flag to remount: curl ... | bash -s -- --force"
      fi
    fi
  fi

  command -v git >/dev/null || err "git is required"
  command -v jq >/dev/null || err "jq is required (brew install jq / apt install jq)"
  command -v yq >/dev/null || err "yq is required (brew install yq / pip install yq)"

  log "Pre-flight checks passed"
}

# === Install Beads CLI ===
install_beads() {
  if [[ "$SKIP_BEADS" == "true" ]]; then
    log "Skipping Beads installation (--skip-beads)"
    return 0
  fi

  if command -v br &> /dev/null; then
    local version=$(br --version 2>/dev/null || echo "unknown")
    log "Beads CLI already installed: $version"
    return 0
  fi

  step "Installing Beads CLI..."
  local installer_url="https://raw.githubusercontent.com/steveyegge/beads/main/scripts/install.sh"

  if curl --output /dev/null --silent --head --fail "$installer_url"; then
    curl -fsSL "$installer_url" | bash
    log "Beads CLI installed"
  else
    warn "Beads installer not available - skipping"
    return 0
  fi
}

# === Add Loa Remote ===
setup_remote() {
  step "Configuring Loa upstream remote..."

  if git remote | grep -q "^${LOA_REMOTE_NAME}$"; then
    git remote set-url "$LOA_REMOTE_NAME" "$LOA_REMOTE_URL"
  else
    git remote add "$LOA_REMOTE_NAME" "$LOA_REMOTE_URL"
  fi

  git fetch "$LOA_REMOTE_NAME" "$LOA_BRANCH" --quiet
  log "Remote configured"
}

# === Selective Sync (Three-Zone Model) ===
sync_zones() {
  step "Syncing System and State zones..."

  log "Pulling System Zone (.claude/)..."
  git checkout "$LOA_REMOTE_NAME/$LOA_BRANCH" -- .claude 2>/dev/null || {
    err "Failed to checkout .claude/ from upstream"
  }

  if [[ ! -d "grimoires/loa" ]]; then
    log "Pulling State Zone template (grimoires/loa/)..."
    git checkout "$LOA_REMOTE_NAME/$LOA_BRANCH" -- grimoires/loa 2>/dev/null || {
      warn "No grimoires/loa/ in upstream, creating empty structure..."
      mkdir -p grimoires/loa/{context,discovery,a2a/trajectory}
      touch grimoires/loa/.gitkeep
    }
  else
    log "State Zone already exists, preserving..."
  fi

  mkdir -p .beads
  touch .beads/.gitkeep

  log "Zones synced"
}

# === Initialize Structured Memory ===
init_structured_memory() {
  step "Initializing structured agentic memory..."

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
    log "Structured memory initialized"
  else
    log "Structured memory already exists"
  fi

  # Create trajectory directory for ADK-style evaluation
  mkdir -p grimoires/loa/a2a/trajectory
}

# === Create Version Manifest ===
create_manifest() {
  step "Creating version manifest..."

  local upstream_version="0.6.0"
  if [[ -f ".claude/.loa-version.json" ]]; then
    upstream_version=$(jq -r '.framework_version // "0.6.0"' .claude/.loa-version.json 2>/dev/null)
  fi

  cat > "$VERSION_FILE" << EOF
{
  "framework_version": "$upstream_version",
  "schema_version": 2,
  "last_sync": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "zones": {
    "system": ".claude",
    "state": ["grimoires/loa", ".beads"],
    "app": ["src", "lib", "app"]
  },
  "migrations_applied": ["001_init_zones"],
  "integrity": {
    "enforcement": "strict",
    "last_verified": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  }
}
EOF

  log "Version manifest created"
}

# === Generate Cryptographic Checksums ===
generate_checksums() {
  step "Generating cryptographic checksums..."

  local checksums="{"
  checksums+='"generated": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",'
  checksums+='"algorithm": "sha256",'
  checksums+='"files": {'

  local first=true
  while IFS= read -r -d '' file; do
    local hash=$(sha256sum "$file" | cut -d' ' -f1)
    local relpath="${file#./}"
    if [[ "$first" == "true" ]]; then
      first=false
    else
      checksums+=','
    fi
    checksums+='"'"$relpath"'": "'"$hash"'"'
  done < <(find .claude -type f ! -name "checksums.json" ! -path "*/overrides/*" -print0 | sort -z)

  checksums+='}}'

  echo "$checksums" | jq '.' > "$CHECKSUMS_FILE"
  log "Checksums generated"
}

# === Create Default Config ===
create_config() {
  if [[ -f "$CONFIG_FILE" ]]; then
    log "Config file already exists, preserving..."
    generate_config_snapshot
    return 0
  fi

  step "Creating default configuration..."

  cat > "$CONFIG_FILE" << 'EOF'
# Loa Framework Configuration
# This file is yours to customize - framework updates will never modify it

# =============================================================================
# Persistence Mode
# =============================================================================
# - standard: Commit grimoire and beads to repo (default)
# - stealth: Add state files to .gitignore, local-only operation
persistence_mode: standard

# =============================================================================
# Integrity Enforcement
# =============================================================================
# - strict: Block agent execution on System Zone drift (recommended)
# - warn: Warn but allow execution
# - disabled: No integrity checks (not recommended)
integrity_enforcement: strict

# =============================================================================
# Drift Resolution Policy
# =============================================================================
# - code: Update documentation to match implementation (existing codebases)
# - docs: Create beads to fix code to match documentation (greenfield)
# - ask: Always prompt for human decision
drift_resolution: code

# =============================================================================
# Agent Configuration
# =============================================================================
disabled_agents: []
# disabled_agents:
#   - auditing-security
#   - translating-for-executives

# =============================================================================
# Structured Memory
# =============================================================================
memory:
  notes_file: grimoires/loa/NOTES.md
  trajectory_dir: grimoires/loa/a2a/trajectory
  # Auto-compact trajectory logs older than N days
  trajectory_retention_days: 30

# =============================================================================
# Evaluation-Driven Development
# =============================================================================
edd:
  enabled: true
  # Require N test scenarios before marking task complete
  min_test_scenarios: 3
  # Audit reasoning trajectory for hallucination
  trajectory_audit: true

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

# =============================================================================
# Framework Upgrade Behavior
# =============================================================================
upgrade:
  # Create git commit after mount/upgrade (default: true)
  auto_commit: true
  # Create version tag after mount/upgrade (default: true)
  auto_tag: true
  # Conventional commit prefix (default: "chore")
  commit_prefix: "chore"
EOF

  generate_config_snapshot
  log "Config created"
}

generate_config_snapshot() {
  mkdir -p grimoires/loa/context
  if command -v yq &> /dev/null && [[ -f "$CONFIG_FILE" ]]; then
    yq_to_json "$CONFIG_FILE" > grimoires/loa/context/config_snapshot.json 2>/dev/null || true
  fi
}

# === Apply Stealth Mode ===
apply_stealth() {
  local mode="standard"

  # Check CLI flag first, then config file
  if [[ "$STEALTH_MODE" == "true" ]]; then
    mode="stealth"
  elif [[ -f "$CONFIG_FILE" ]]; then
    mode=$(yq_read "$CONFIG_FILE" '.persistence_mode' "standard")
  fi

  if [[ "$mode" == "stealth" ]]; then
    step "Applying stealth mode..."

    local gitignore=".gitignore"
    touch "$gitignore"

    local entries=("grimoires/loa/" ".beads/" ".loa-version.json" ".loa.config.yaml")
    for entry in "${entries[@]}"; do
      grep -qxF "$entry" "$gitignore" 2>/dev/null || echo "$entry" >> "$gitignore"
    done

    log "Stealth mode applied"
  fi
}

# === Initialize Beads ===
init_beads() {
  if [[ "$SKIP_BEADS" == "true" ]]; then
    log "Skipping Beads initialization (--skip-beads)"
    return 0
  fi

  if ! command -v br &> /dev/null; then
    warn "Beads CLI not installed, skipping initialization"
    return 0
  fi

  step "Initializing Beads task graph..."

  local stealth_flag=""
  if [[ -f "$CONFIG_FILE" ]]; then
    local mode=$(yq_read "$CONFIG_FILE" '.persistence_mode' "standard")
    [[ "$mode" == "stealth" ]] && stealth_flag="--stealth"
  fi

  if [[ ! -f ".beads/graph.jsonl" ]]; then
    br init $stealth_flag 2>/dev/null || {
      warn "Beads init failed - run 'br init' manually"
      return 0
    }
    log "Beads initialized"
  else
    log "Beads already initialized"
  fi
}

# === Create Version Tag ===
create_version_tag() {
  local version="$1"

  # Check if auto-tag is enabled in config
  local auto_tag="true"
  if [[ -f "$CONFIG_FILE" ]]; then
    auto_tag=$(yq_read "$CONFIG_FILE" '.upgrade.auto_tag' "true")
  fi

  if [[ "$auto_tag" != "true" ]]; then
    return 0
  fi

  local tag_name="loa@v${version}"

  # Check if tag already exists
  if git tag -l "$tag_name" | grep -q "$tag_name"; then
    log "Tag $tag_name already exists"
    return 0
  fi

  git tag -a "$tag_name" -m "Loa framework v${version}" 2>/dev/null || {
    warn "Failed to create tag $tag_name"
    return 1
  }

  log "Created tag: $tag_name"
}

# === Create Upgrade Commit ===
# Creates a single atomic commit for framework mount/upgrade
# Arguments:
#   $1 - commit_type: "mount" or "update"
#   $2 - old_version: previous version (or "none" for fresh mount)
#   $3 - new_version: new version being installed
create_upgrade_commit() {
  local commit_type="$1"
  local old_version="$2"
  local new_version="$3"

  # Check if --no-commit flag was passed
  if [[ "$NO_COMMIT" == "true" ]]; then
    log "Skipping commit (--no-commit)"
    return 0
  fi

  # Check stealth mode - no commits in stealth
  local mode="standard"
  if [[ "$STEALTH_MODE" == "true" ]]; then
    mode="stealth"
  elif [[ -f "$CONFIG_FILE" ]]; then
    mode=$(yq_read "$CONFIG_FILE" '.persistence_mode' "standard")
  fi

  if [[ "$mode" == "stealth" ]]; then
    log "Skipping commit (stealth mode)"
    return 0
  fi

  # Check config option for auto_commit
  local auto_commit="true"
  if [[ -f "$CONFIG_FILE" ]]; then
    auto_commit=$(yq_read "$CONFIG_FILE" '.upgrade.auto_commit' "true")
  fi

  if [[ "$auto_commit" != "true" ]]; then
    log "Skipping commit (auto_commit: false in config)"
    return 0
  fi

  # Check for dirty working tree (excluding our changes)
  # We only warn, don't block - the commit will include everything staged
  if ! git diff --quiet 2>/dev/null; then
    if [[ "$FORCE_MODE" != "true" ]]; then
      warn "Working tree has unstaged changes - they will NOT be included in commit"
    fi
  fi

  step "Creating upgrade commit..."

  # Stage framework files
  git add .claude .loa-version.json 2>/dev/null || true

  # Check if there are staged changes
  if git diff --cached --quiet 2>/dev/null; then
    log "No changes to commit"
    return 0
  fi

  # Build commit message
  local commit_prefix="chore"
  if [[ -f "$CONFIG_FILE" ]]; then
    commit_prefix=$(yq_read "$CONFIG_FILE" '.upgrade.commit_prefix' "chore")
  fi

  local commit_msg
  if [[ "$old_version" == "none" ]]; then
    commit_msg="${commit_prefix}(loa): mount framework v${new_version}

- Installed Loa framework System Zone
- Created .claude/ directory structure
- See: https://github.com/0xHoneyJar/loa/releases/tag/v${new_version}

Generated by Loa mount-loa.sh"
  else
    commit_msg="${commit_prefix}(loa): upgrade framework v${old_version} -> v${new_version}

- Updated .claude/ System Zone
- Preserved .claude/overrides/
- See: https://github.com/0xHoneyJar/loa/releases/tag/v${new_version}

Generated by Loa update.sh"
  fi

  # Create commit (--no-verify to skip pre-commit hooks that might interfere)
  git commit -m "$commit_msg" --no-verify 2>/dev/null || {
    warn "Failed to create commit (git commit failed)"
    return 1
  }

  log "Created upgrade commit"

  # Create version tag
  create_version_tag "$new_version"
}

# === Main ===
main() {
  echo ""
  log "======================================================================="
  log "  Loa Framework Mount v0.9.0"
  log "  Enterprise-Grade Managed Scaffolding"
  log "======================================================================="
  log "  Branch: $LOA_BRANCH"
  [[ "$FORCE_MODE" == "true" ]] && log "  Mode: Force remount"
  echo ""

  preflight
  install_beads
  setup_remote
  sync_zones
  init_structured_memory
  create_config
  create_manifest
  generate_checksums
  init_beads
  apply_stealth

  # === Create Atomic Commit ===
  local old_version="none"
  local new_version=$(jq -r '.framework_version // "unknown"' "$VERSION_FILE" 2>/dev/null)
  create_upgrade_commit "mount" "$old_version" "$new_version"

  mkdir -p .claude/overrides
  [[ -f .claude/overrides/README.md ]] || cat > .claude/overrides/README.md << 'EOF'
# User Overrides
Files here are preserved across framework updates.
Mirror the .claude/ structure for any customizations.
EOF

  # === Show Completion Banner ===
  local banner_script=".claude/scripts/upgrade-banner.sh"
  if [[ -x "$banner_script" ]]; then
    "$banner_script" "none" "$new_version" --mount
  else
    # Fallback: simple completion message
    echo ""
    log "======================================================================="
    log "  Loa Successfully Mounted!"
    log "======================================================================="
    echo ""
    info "Next steps:"
    info "  1. Run 'claude' to start Claude Code"
    info "  2. Issue '/ride' to analyze this codebase"
    info "  3. Or '/setup' for guided project configuration"
    echo ""
  fi

  warn "STRICT ENFORCEMENT: Direct edits to .claude/ will block agent execution."
  warn "Use .claude/overrides/ for customizations."
  echo ""
}

main "$@"
