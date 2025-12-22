#!/usr/bin/env bash
# Loa Framework: Mount Script
# The Loa mounts your repository and rides alongside your project
set -euo pipefail

# === Configuration ===
LOA_REMOTE_URL="${LOA_UPSTREAM:-https://github.com/0xHoneyJar/loa.git}"
LOA_REMOTE_NAME="loa-upstream"
LOA_BRANCH="${LOA_BRANCH:-main}"
VERSION_FILE=".loa-version.json"
CONFIG_FILE=".loa.config.yaml"
CHECKSUMS_FILE=".claude/checksums.json"

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
    read -p "Remount/upgrade? This will reset the System Zone. (y/N) " -n 1 -r
    echo ""
    [[ $REPLY =~ ^[Yy]$ ]] || { log "Aborted."; exit 0; }
  fi

  command -v git >/dev/null || err "git is required"
  command -v jq >/dev/null || err "jq is required (brew install jq / apt install jq)"
  command -v yq >/dev/null || err "yq is required (brew install yq / pip install yq)"

  log "Pre-flight checks passed"
}

# === Install Beads CLI ===
install_beads() {
  if command -v bd &> /dev/null; then
    local version=$(bd --version 2>/dev/null || echo "unknown")
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

  if [[ ! -d "loa-grimoire" ]]; then
    log "Pulling State Zone template (loa-grimoire/)..."
    git checkout "$LOA_REMOTE_NAME/$LOA_BRANCH" -- loa-grimoire 2>/dev/null || {
      warn "No loa-grimoire/ in upstream, creating empty structure..."
      mkdir -p loa-grimoire/{context,discovery,a2a/trajectory}
      touch loa-grimoire/.gitkeep
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

  local notes_file="loa-grimoire/NOTES.md"
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
  mkdir -p loa-grimoire/a2a/trajectory
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
    "state": ["loa-grimoire", ".beads"],
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
  notes_file: loa-grimoire/NOTES.md
  trajectory_dir: loa-grimoire/a2a/trajectory
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
EOF

  generate_config_snapshot
  log "Config created"
}

generate_config_snapshot() {
  mkdir -p loa-grimoire/context
  if command -v yq &> /dev/null && [[ -f "$CONFIG_FILE" ]]; then
    yq_to_json "$CONFIG_FILE" > loa-grimoire/context/config_snapshot.json 2>/dev/null || true
  fi
}

# === Apply Stealth Mode ===
apply_stealth() {
  if [[ ! -f "$CONFIG_FILE" ]]; then return 0; fi

  local mode=$(yq_read "$CONFIG_FILE" '.persistence_mode' "standard")

  if [[ "$mode" == "stealth" ]]; then
    step "Applying stealth mode..."

    local gitignore=".gitignore"
    touch "$gitignore"

    local entries=("loa-grimoire/" ".beads/" ".loa-version.json" ".loa.config.yaml")
    for entry in "${entries[@]}"; do
      grep -qxF "$entry" "$gitignore" 2>/dev/null || echo "$entry" >> "$gitignore"
    done

    log "Stealth mode applied"
  fi
}

# === Initialize Beads ===
init_beads() {
  if ! command -v bd &> /dev/null; then
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
    bd init $stealth_flag 2>/dev/null || {
      warn "Beads init failed - run 'bd init' manually"
      return 0
    }
    log "Beads initialized"
  else
    log "Beads already initialized"
  fi
}

# === Main ===
main() {
  echo ""
  log "======================================================================="
  log "  Loa Framework Mount v0.6.0"
  log "  Enterprise-Grade Managed Scaffolding"
  log "======================================================================="
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

  mkdir -p .claude/overrides
  [[ -f .claude/overrides/README.md ]] || cat > .claude/overrides/README.md << 'EOF'
# User Overrides
Files here are preserved across framework updates.
Mirror the .claude/ structure for any customizations.
EOF

  echo ""
  log "======================================================================="
  log "  Loa Successfully Mounted!"
  log "======================================================================="
  echo ""
  info "Next steps:"
  info "  1. Run 'claude' to start Claude Code"
  info "  2. Issue '/setup' for guided project configuration"
  info "  3. Issue '/plan-and-analyze' to begin requirements discovery"
  echo ""
  info "Zone structure:"
  info "  .claude/          -> System Zone (framework-managed, immutable)"
  info "  .claude/overrides -> Your customizations (preserved)"
  info "  loa-grimoire/     -> State Zone (project memory)"
  info "  loa-grimoire/NOTES.md -> Structured agentic memory"
  info "  .beads/           -> Task graph (Beads)"
  echo ""
  warn "STRICT ENFORCEMENT: Direct edits to .claude/ will block agent execution."
  warn "Use .claude/overrides/ for customizations."
  echo ""
}

main "$@"
