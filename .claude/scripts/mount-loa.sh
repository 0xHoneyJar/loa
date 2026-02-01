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
DIM='\033[2m'
BOLD='\033[1m'
NC='\033[0m'

# === Output Mode Variables ===
QUIET_MODE=false
VERBOSE_MODE=false

# === Symbols (Unicode) ===
SYM_CHECK="✓"
SYM_ARROW="›"
SYM_WARN="!"
SYM_ERR="✗"
SYM_DOT="·"

# === ANSI Escape Codes ===
CLEAR_LINE="\033[2K"
CURSOR_UP="\033[1A"
HIDE_CURSOR="\033[?25l"
SHOW_CURSOR="\033[?25h"

# === Logging Functions (quiet-aware) ===
log() { [[ "$VERBOSE_MODE" == "true" ]] && echo -e "${DIM}  $*${NC}" || true; }
warn() {
  # If spinner is running, stop it first
  if [[ -n "$SPINNER_PID" ]]; then
    kill "$SPINNER_PID" 2>/dev/null
    wait "$SPINNER_PID" 2>/dev/null || true
    SPINNER_PID=""
    printf "\r${CLEAR_LINE}"
  fi
  echo -e "${YELLOW}${SYM_WARN}${NC} $*"
}
err() { echo -e "${RED}${SYM_ERR} ERROR:${NC} $*" >&2; exit 1; }
info() { [[ "$VERBOSE_MODE" == "true" ]] && echo -e "${CYAN}$*${NC}" || true; }
step() { [[ "$VERBOSE_MODE" == "true" ]] && echo -e "${DIM}  ${SYM_ARROW} $*${NC}" || true; }

# === Spinner ===
SPINNER_PID=""
SPINNER_FRAMES=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")

spinner_start() {
  local msg="$1"
  [[ "$QUIET_MODE" == "true" ]] && return

  printf "${HIDE_CURSOR}"
  (
    local i=0
    while true; do
      printf "\r${CYAN}${SPINNER_FRAMES[$i]}${NC} %s" "$msg"
      i=$(( (i + 1) % ${#SPINNER_FRAMES[@]} ))
      sleep 0.08
    done
  ) &
  SPINNER_PID=$!
}

spinner_stop() {
  local msg="$1"
  local success="${2:-true}"

  [[ "$QUIET_MODE" == "true" ]] && { echo "$msg"; return; }

  if [[ -n "$SPINNER_PID" ]]; then
    kill "$SPINNER_PID" 2>/dev/null
    wait "$SPINNER_PID" 2>/dev/null || true
    SPINNER_PID=""
  fi

  printf "\r${CLEAR_LINE}"
  if [[ "$success" == "true" ]]; then
    printf "${GREEN}${SYM_CHECK}${NC} %s\n" "$msg"
  else
    printf "${YELLOW}${SYM_WARN}${NC} %s\n" "$msg"
  fi
  printf "${SHOW_CURSOR}"
}

# Cleanup spinner on interrupt (not normal exit)
cleanup_spinner() {
  if [[ -n "$SPINNER_PID" ]]; then
    kill "$SPINNER_PID" 2>/dev/null
    wait "$SPINNER_PID" 2>/dev/null || true
    SPINNER_PID=""
    printf "\r${CLEAR_LINE}${YELLOW}${SYM_WARN}${NC} Interrupted\n"
  fi
  printf "${SHOW_CURSOR}"
}
trap 'cleanup_spinner' INT TERM
trap 'printf "${SHOW_CURSOR}"' EXIT

# === Spinner Verb Themes ===
# Pipe-delimited for easy parsing with tr
SPINNER_THEME_DUNE="Channeling spice|Riding sandworm|Consulting mentat|Folding space|Walking rhythm|Harvesting melange|Awakening sleeper|Reading prescience"
SPINNER_THEME_GIBSON="Jacking in|Running ICE|Tracing construct|Navigating sprawl|Compiling intrusion|Parsing signal|Decrypting data|Surfing matrix"
SPINNER_THEME_LOA="Invoking loa|Mounting grimoire|Channeling agents|Binding beads|Synthesizing context|Weaving protocols|Conjuring skills|Riding codebase"

# === Configuration ===
LOA_REMOTE_URL="${LOA_UPSTREAM:-https://github.com/0xHoneyJar/loa.git}"
LOA_REMOTE_NAME="loa-upstream"
LOA_BRANCH="${LOA_BRANCH:-main}"
VERSION_FILE=".loa-version.json"
CONFIG_FILE=".loa.config.yaml"
CHECKSUMS_FILE=".claude/checksums.json"
SKIP_WIZARD=false
STEALTH_MODE=false
FORCE_MODE=false
NO_COMMIT=false
VERSION_MODE="latest"  # latest | edge | loa@vX.Y.Z
RESOLVED_VERSION=""    # Populated by fetch_latest_loa_release
FALLBACK_VERSION="1.14.1"

# === Argument Parsing ===
while [[ $# -gt 0 ]]; do
  case $1 in
    --branch)
      LOA_BRANCH="$2"
      shift 2
      ;;
    --version)
      [[ -z "${2:-}" || "$2" == -* ]] && err "--version requires a value (e.g., --version 1.14.0)"
      VERSION_MODE="loa@v$2"
      shift 2
      ;;
    --edge)
      VERSION_MODE="edge"
      shift
      ;;
    --quiet|-q)
      QUIET_MODE=true
      VERBOSE_MODE=false
      shift
      ;;
    --verbose|-v)
      VERBOSE_MODE=true
      QUIET_MODE=false
      shift
      ;;
    --stealth)
      STEALTH_MODE=true
      shift
      ;;
    --skip-beads)
      # Deprecated: beads is now installed via setup wizard
      warn "--skip-beads is deprecated. Use --skip-wizard instead."
      SKIP_WIZARD=true
      shift
      ;;
    --skip-wizard)
      SKIP_WIZARD=true
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
      echo "  --version <ver>   Install specific version (e.g., --version 1.14.0)"
      echo "  --edge            Install from main branch (bleeding edge)"
      echo "  --quiet, -q       Minimal output (numbered progress steps)"
      echo "  --verbose, -v     Full output with ASCII banner"
      echo "  --branch <name>   Loa branch to use (default: main)"
      echo "  --force, -f       Force remount without prompting"
      echo "  --stealth         Add state files to .gitignore"
      echo "  --skip-wizard     Skip the setup wizard for optional tools"
      echo "  --no-commit       Skip creating git commit after mount"
      echo "  -h, --help        Show this help message"
      echo ""
      echo "Examples:"
      echo "  # Install latest release"
      echo "  curl -fsSL https://raw.githubusercontent.com/0xHoneyJar/loa/main/.claude/scripts/mount-loa.sh | bash"
      echo ""
      echo "  # Install specific version"
      echo "  bash mount-loa.sh --version 1.13.0"
      echo ""
      echo "  # Install bleeding edge"
      echo "  bash mount-loa.sh --edge"
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

# === Version Resolution ===
# Fetches latest loa@v* release from GitHub API
# Args: mode - "latest" (default), "edge", or "loa@vX.Y.Z"
# Returns: version string to stdout, exit 1 if fallback used
fetch_latest_loa_release() {
  local mode="${1:-latest}"

  case "$mode" in
    edge)
      # Edge mode: use main branch
      echo "main"
      return 0
      ;;
    latest)
      # Fetch from GitHub API, filter loa@v* tags
      local response
      response=$(curl -sL --proto =https --tlsv1.2 \
        -H "Accept: application/vnd.github+json" \
        --max-time 5 \
        "https://api.github.com/repos/0xHoneyJar/loa/releases" 2>/dev/null) || {
        warn "Network error fetching releases"
        echo "$FALLBACK_VERSION"
        return 1
      }

      # Extract first loa@v* tag (most recent)
      local tag
      tag=$(echo "$response" | jq -r '[.[] | select(.tag_name | startswith("loa@v"))][0].tag_name // empty' 2>/dev/null)

      if [[ -n "$tag" && "$tag" != "null" ]]; then
        echo "${tag#loa@v}"  # Strip prefix, return "1.14.1"
        return 0
      fi

      # No loa@v* releases found, try any release
      tag=$(echo "$response" | jq -r '.[0].tag_name // empty' 2>/dev/null)
      if [[ -n "$tag" && "$tag" != "null" ]]; then
        echo "${tag#v}"  # Strip v prefix if present
        return 0
      fi

      # Fallback
      warn "Could not determine latest version from GitHub"
      echo "$FALLBACK_VERSION"
      return 1
      ;;
    loa@v*)
      # Specific version requested - validate format and return
      local ver="${mode#loa@v}"
      if [[ "$ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$ ]]; then
        echo "$ver"
        return 0
      else
        warn "Invalid version format: $ver"
        echo "$FALLBACK_VERSION"
        return 1
      fi
      ;;
    *)
      echo "$FALLBACK_VERSION"
      return 1
      ;;
  esac
}

# === Spinner Verbs Functions ===
# Prompts user to select a spinner theme (interactive only)
prompt_spinner_verbs() {
  # Skip if non-interactive, force mode, or quiet mode
  [[ ! -t 0 ]] && return 0
  [[ "$FORCE_MODE" == "true" ]] && return 0
  [[ "$QUIET_MODE" == "true" ]] && return 0

  echo ""
  echo -e "${BOLD}Select spinner theme${NC}"
  echo ""
  echo -e "  ${BOLD}1${NC}  Dune     ${DIM}Channeling spice, Riding sandworm...${NC}"
  echo -e "  ${BOLD}2${NC}  Gibson   ${DIM}Jacking in, Running ICE...${NC}"
  echo -e "  ${BOLD}3${NC}  Loa      ${DIM}Invoking loa, Mounting grimoire...${NC}"
  echo -e "  ${BOLD}n${NC}  Skip"
  echo ""
  read -p "Choice [1/2/3/n]: " -n 1 -r
  echo ""

  case $REPLY in
    1) apply_spinner_verbs "dune" && echo -e "${GREEN}${SYM_CHECK}${NC} Applied Dune theme" ;;
    2) apply_spinner_verbs "gibson" && echo -e "${GREEN}${SYM_CHECK}${NC} Applied Gibson theme" ;;
    3) apply_spinner_verbs "loa" && echo -e "${GREEN}${SYM_CHECK}${NC} Applied Loa theme" ;;
    *) ;;
  esac
}

# Applies selected spinner theme to .claude/settings.json
apply_spinner_verbs() {
  local theme="$1"
  local settings_file=".claude/settings.json"

  [[ ! -f "$settings_file" ]] && {
    warn "settings.json not found, skipping spinner verbs"
    return 1
  }

  # Select theme
  local verbs_str
  case "$theme" in
    dune)   verbs_str="$SPINNER_THEME_DUNE" ;;
    gibson) verbs_str="$SPINNER_THEME_GIBSON" ;;
    loa)    verbs_str="$SPINNER_THEME_LOA" ;;
    *)      return 1 ;;
  esac

  # Convert pipe-delimited string to JSON array
  local verbs_array
  verbs_array=$(echo "$verbs_str" | tr '|' '\n' | jq -R . | jq -s .)

  # Build spinnerVerbs object with mode and verbs
  local spinner_obj
  spinner_obj=$(jq -n --argjson verbs "$verbs_array" '{"mode": "replace", "verbs": $verbs}')

  # Merge into settings.json (atomic write)
  local tmp_file
  tmp_file=$(mktemp)
  chmod 600 "$tmp_file"

  if jq --argjson spinnerVerbs "$spinner_obj" '.spinnerVerbs = $spinnerVerbs' "$settings_file" > "$tmp_file" 2>/dev/null; then
    mv "$tmp_file" "$settings_file"
    log "Applied $theme spinner theme"
  else
    rm -f "$tmp_file"
    warn "Failed to update settings.json"
    return 1
  fi
}

# === Completion Message ===
show_completion() {
  local version="$1"

  if [[ "$VERBOSE_MODE" == "true" ]]; then
    # Delegate to existing upgrade-banner.sh
    local banner_script=".claude/scripts/upgrade-banner.sh"
    if [[ -x "$banner_script" ]]; then
      "$banner_script" "none" "$version" --mount
    else
      show_minimal_completion "$version"
    fi
  else
    show_minimal_completion "$version"
  fi
}

show_minimal_completion() {
  local version="$1"
  echo ""
  echo -e "${GREEN}${SYM_CHECK}${NC} ${BOLD}Loa v${version} mounted${NC}"
  echo ""
  echo -e "  Run ${CYAN}claude${NC} to start"
  echo -e "  Use ${CYAN}/loa${NC} for guided workflow"
  echo ""
}

# === Pre-flight Checks ===
preflight() {
  log "Running pre-flight checks..."

  if ! git rev-parse --git-dir > /dev/null 2>&1; then
    err "Not a git repository. Initialize with 'git init' first."
  fi

  if [[ -f "$VERSION_FILE" ]]; then
    local existing=$(jq -r '.framework_version // "unknown"' "$VERSION_FILE" 2>/dev/null)
    if [[ "$FORCE_MODE" == "true" ]]; then
      # Silent in force mode - user knows what they're doing
      log "Force mode: remounting over v$existing"
    else
      warn "Loa is already mounted (version: $existing)"
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

  # Use check-prereqs.sh in verbose mode for detailed output
  # Fall back to inline checks if script not available
  local prereqs_script=".claude/scripts/check-prereqs.sh"
  if [[ "$VERBOSE_MODE" == "true" && -x "$prereqs_script" ]]; then
    "$prereqs_script" --verbose || err "Missing required prerequisites"
  else
    # Inline checks (always run as backup)
    command -v git >/dev/null || err "git is required"
    command -v jq >/dev/null || err "jq is required (brew install jq / apt install jq)"
    command -v yq >/dev/null || err "yq is required (brew install yq / pip install yq)"
  fi

  log "Pre-flight checks passed"
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

# === Root File Sync (CLAUDE.md, PROCESS.md) ===

# Pull file from upstream and wrap in markers (for fresh installs)
pull_and_wrap_loa_file() {
  local file="$1"

  local content
  content=$(git show "$LOA_REMOTE_NAME/$LOA_BRANCH:$file" 2>/dev/null) || {
    warn "No $file in upstream, skipping..."
    return 0
  }

  cat > "$file" << EOF
<!-- LOA:BEGIN - Framework instructions (auto-managed, do not edit) -->
$content
<!-- LOA:END -->

<!-- PROJECT:BEGIN - Your customizations below (preserved across updates) -->
# Project-Specific Instructions

Add your project-specific Claude instructions here.
This section is preserved across Loa framework updates.
<!-- PROJECT:END -->
EOF

  log "Created $file with Loa framework instructions"
}

# Merge Loa content with existing user content
create_hybrid_file() {
  local file="$1"
  local backup="${file}.pre-loa.backup"

  # Backup original
  cp "$file" "$backup"
  log "Backed up original to $backup"

  # Get Loa's version
  local loa_content
  loa_content=$(git show "$LOA_REMOTE_NAME/$LOA_BRANCH:$file" 2>/dev/null) || {
    warn "Could not fetch $file from upstream - keeping original"
    rm -f "$backup"
    return 1
  }

  # Read original content
  local original_content
  original_content=$(cat "$file")

  # Create hybrid file
  cat > "$file" << EOF
<!-- LOA:BEGIN - Framework instructions (auto-managed, do not edit) -->
$loa_content
<!-- LOA:END -->

<!-- PROJECT:BEGIN - Your customizations below (preserved across updates) -->
$original_content
<!-- PROJECT:END -->
EOF

  log "Created hybrid $file (original content preserved in PROJECT section)"
}

# Update only the Loa section, preserving project section
update_loa_section() {
  local file="$1"

  # Get new Loa content
  local loa_content
  loa_content=$(git show "$LOA_REMOTE_NAME/$LOA_BRANCH:$file" 2>/dev/null) || {
    warn "Could not fetch $file from upstream - keeping current"
    return 1
  }

  # Extract everything from PROJECT:BEGIN to end of file
  local project_section
  project_section=$(sed -n '/<!-- PROJECT:BEGIN/,$p' "$file" 2>/dev/null)

  # If no project section found, preserve everything after LOA:END
  if [[ -z "$project_section" ]]; then
    project_section=$(sed -n '/<!-- LOA:END -->/,$p' "$file" | tail -n +2)
    if [[ -n "$project_section" ]]; then
      project_section="<!-- PROJECT:BEGIN - Your customizations below (preserved across updates) -->
$project_section
<!-- PROJECT:END -->"
    fi
  fi

  # Rebuild file
  cat > "$file" << EOF
<!-- LOA:BEGIN - Framework instructions (auto-managed, do not edit) -->
$loa_content
<!-- LOA:END -->

$project_section
EOF

  log "Updated Loa section in $file (project content preserved)"
}

# Pull optional files only if they don't exist
sync_optional_file() {
  local file="$1"
  local description="$2"

  if [[ -f "$file" ]]; then
    log "$file already exists, preserving..."
    return 0
  fi

  log "Pulling $file ($description)..."
  git checkout "$LOA_REMOTE_NAME/$LOA_BRANCH" -- "$file" 2>/dev/null || {
    warn "No $file in upstream, skipping..."
  }
}

# Handle CLAUDE.md with conflict detection and hybrid merge
sync_claude_md() {
  local file="CLAUDE.md"

  if [[ -f "$file" ]]; then
    if grep -q "<!-- LOA:BEGIN" "$file" 2>/dev/null; then
      log "Updating Loa section in existing $file..."
      update_loa_section "$file"
    else
      log "Existing $file found - creating hybrid..."
      create_hybrid_file "$file"
    fi
  else
    log "Pulling $file (Claude Code instructions)..."
    pull_and_wrap_loa_file "$file"
  fi
}

# Orchestrate root file synchronization
sync_root_files() {
  step "Syncing root documentation files..."

  # Required: CLAUDE.md with hybrid support
  sync_claude_md

  # Optional: Pull only if missing
  sync_optional_file "PROCESS.md" "Workflow documentation"

  log "Root files synced"
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

  # Use RESOLVED_VERSION if set (from fetch_latest_loa_release)
  # Otherwise fall back to detection from existing files
  local upstream_version="${RESOLVED_VERSION:-}"
  if [[ -z "$upstream_version" ]]; then
    if [[ -f ".loa-version.json" ]]; then
      upstream_version=$(jq -r '.framework_version // "'"$FALLBACK_VERSION"'"' .loa-version.json 2>/dev/null)
    elif [[ -f ".claude/.loa-version.json" ]]; then
      upstream_version=$(jq -r '.framework_version // "'"$FALLBACK_VERSION"'"' .claude/.loa-version.json 2>/dev/null)
    else
      upstream_version="$FALLBACK_VERSION"
    fi
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

  # Stage framework files (including root docs)
  git add .claude .loa-version.json CLAUDE.md PROCESS.md 2>/dev/null || true

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
- Added CLAUDE.md (Claude Code instructions)
- Added PROCESS.md (workflow documentation)
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
  git commit -m "$commit_msg" --no-verify --quiet 2>/dev/null || {
    warn "Failed to create commit (git commit failed)"
    return 1
  }

  log "Created upgrade commit"

  # Create version tag
  create_version_tag "$new_version"
}

# === Main ===
main() {
  # Header
  if [[ "$QUIET_MODE" != "true" ]]; then
    echo ""
    echo -e "${DIM}─────────────────────────────────────────────────${NC}"
    echo -e "  ${BOLD}Loa${NC} ${DIM}· by 0xHoneyJar${NC}"
    echo -e "  ${DIM}https://0xhoneyjar.xyz${NC}"
    echo -e "${DIM}─────────────────────────────────────────────────${NC}"
    echo ""
  fi

  # === Step 1: Resolve Version ===
  spinner_start "Fetching latest release"
  RESOLVED_VERSION=$(fetch_latest_loa_release "$VERSION_MODE") || {
    RESOLVED_VERSION="$FALLBACK_VERSION"
  }
  spinner_stop "Resolved v${RESOLVED_VERSION}"

  # Show extra info in verbose mode
  if [[ "$VERBOSE_MODE" == "true" ]]; then
    info "  Branch: $LOA_BRANCH"
    info "  Version Mode: $VERSION_MODE"
    [[ "$FORCE_MODE" == "true" ]] && info "  Mode: Force remount"
  fi

  # === Step 2: Pre-flight & Remote ===
  spinner_start "Running pre-flight checks"
  preflight
  setup_remote
  spinner_stop "Remote configured"

  # === Step 3: Sync Framework ===
  spinner_start "Syncing framework"
  sync_zones
  sync_root_files
  init_structured_memory
  spinner_stop "Framework synced"

  # === Step 4: Initialize Config ===
  spinner_start "Initializing config"
  create_config
  create_manifest
  spinner_stop "Config initialized"

  # === Step 5: Generate Checksums ===
  spinner_start "Generating checksums"
  generate_checksums
  apply_stealth
  spinner_stop "Checksums generated"

  # === Step 6: Finalize ===
  spinner_start "Finalizing"

  # Create atomic commit
  local old_version="none"
  local new_version=$(jq -r '.framework_version // "unknown"' "$VERSION_FILE" 2>/dev/null)
  create_upgrade_commit "mount" "$old_version" "$new_version"

  # Create overrides directory
  mkdir -p .claude/overrides
  [[ -f .claude/overrides/README.md ]] || cat > .claude/overrides/README.md << 'EOF'
# User Overrides
Files here are preserved across framework updates.
Mirror the .claude/ structure for any customizations.
EOF
  spinner_stop "Complete"

  # === Post-Install: Spinner Verbs ===
  prompt_spinner_verbs

  # === Step 7: Setup Wizard (optional enhancements) ===
  local wizard_ran=false
  if [[ -t 0 && "$QUIET_MODE" != "true" && "$FORCE_MODE" != "true" && "$SKIP_WIZARD" != "true" ]]; then
    local wizard_script=".claude/scripts/setup-wizard.sh"
    if [[ -x "$wizard_script" ]]; then
      "$wizard_script" "$new_version"
      wizard_ran=true
    fi
  fi

  # Show completion if wizard didn't run (wizard shows its own summary)
  if [[ "$wizard_ran" != "true" ]]; then
    show_completion "$new_version"
  fi
}

main "$@"
