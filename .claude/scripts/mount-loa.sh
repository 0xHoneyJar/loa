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

# === Structured Error Handling (E010-E016) ===

# Minimal JSON string escaping for bash (no jq dependency)
# Handles: backslash, double-quote, newline, carriage return, tab
# Strips other control characters (0x00-0x1F) to guarantee valid JSON
_json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  s=$(printf '%s' "$s" | tr -d '\000-\010\013\014\016-\037')
  printf '%s' "$s"
}

# Guard: tracks whether a fatal mount_error already fired (suppresses EXIT trap)
_MOUNT_STRUCTURED_FATAL_EMITTED=false
# Guard: tracks whether a non-fatal mount_warn_policy fired (does NOT suppress EXIT trap)
_MOUNT_STRUCTURED_WARNING_EMITTED=false

# Mount-specific error handler (bash 3.2+ compatible — case statement, no declare -A)
# Fatal variant: emits structured error + exits 1
# JSON schema: {"code":"E0XX","name":"...","message":"...","fix":"..."[,"details":"..."]}
mount_error() {
  local code="$1"
  local extra_context="${2:-}"
  local name="" message="" fix=""

  case "$code" in
    E010) name="mount_no_git_repo"; message="Not a git repository or git not installed"; fix="Install git (https://git-scm.com/downloads) and run 'git init', then retry mount" ;;
    E011) name="mount_empty_repo_commit_failed"; message="Repository has no commits and auto-commit failed"; fix="Create initial commit: echo '# Project' > README.md && git add . && git commit -m 'init', then retry" ;;
    E012) name="mount_git_user_not_configured"; message="git user.name or user.email not set"; fix="Run: git config user.name \"Name\" && git config user.email \"email\"" ;;
    E013) name="mount_commit_failed"; message="Framework commit failed for an unexpected reason"; fix="Check 'git status' and resolve any issues, then retry with --force" ;;
    E014) name="mount_staging_failed"; message="Could not stage framework files"; fix="Check directory permissions and disk space" ;;
    E015) name="mount_bare_repo"; message="Repository is bare (no working tree)"; fix="Clone first: git clone <repo> myproject && cd myproject, then retry" ;;
    E016) name="mount_commit_policy_detected"; message="Commit policies detected; auto-commit skipped"; fix="Commit manually: git add .claude CLAUDE.md PROCESS.md && git commit -m 'chore(loa): mount framework'" ;;
    *) name="mount_commit_failed"; message="Unexpected mount error"; fix="Check 'git status' and resolve any issues, then retry with --force" ;;
  esac

  echo -e "${RED}[loa] ERROR ($code): ${message}${NC}" >&2
  if [[ -n "$extra_context" ]]; then
    echo -e "[loa]" >&2
    echo -e "[loa] ${extra_context}" >&2
  fi
  echo -e "[loa]" >&2
  echo -e "[loa] Fix:" >&2
  echo -e "${CYAN}[loa]   ${fix}${NC}" >&2
  echo -e "[loa]" >&2

  local esc_msg; esc_msg=$(_json_escape "$message")
  local esc_fix; esc_fix=$(_json_escape "$fix")
  local esc_ctx; esc_ctx=$(_json_escape "$extra_context")
  if [[ -n "$extra_context" ]]; then
    printf '{"code":"%s","name":"%s","message":"%s","fix":"%s","details":"%s"}\n' \
      "$code" "$name" "$esc_msg" "$esc_fix" "$esc_ctx" >&2
  else
    printf '{"code":"%s","name":"%s","message":"%s","fix":"%s"}\n' \
      "$code" "$name" "$esc_msg" "$esc_fix" >&2
  fi

  _MOUNT_STRUCTURED_FATAL_EMITTED=true
  exit 1
}

# Non-fatal warning variant for E016: emits structured warning but returns 0
# Used when files are created but commit is skipped (policy detection)
mount_warn_policy() {
  local extra_context="${1:-}"
  local code="E016"
  local name="mount_commit_policy_detected"
  local message="Commit policies detected; auto-commit skipped"
  local fix="Commit manually: git add .claude CLAUDE.md PROCESS.md && git commit -m 'chore(loa): mount framework'"

  echo -e "${YELLOW}[loa] WARNING ($code): ${message}${NC}" >&2
  if [[ -n "$extra_context" ]]; then
    echo -e "[loa] ${extra_context}" >&2
  fi
  echo -e "[loa]" >&2
  echo -e "[loa] Framework files have been created. To commit:" >&2
  echo -e "${CYAN}[loa]   ${fix}${NC}" >&2
  echo -e "[loa]" >&2

  local esc_msg; esc_msg=$(_json_escape "$message")
  local esc_fix; esc_fix=$(_json_escape "$fix")
  printf '{"code":"%s","name":"%s","message":"%s","fix":"%s","severity":"warning"}\n' \
    "$code" "$name" "$esc_msg" "$esc_fix" >&2

  _MOUNT_STRUCTURED_WARNING_EMITTED=true
  return 0
}

# === Repository State Detection ===
REPO_IS_BARE=false
REPO_IS_EMPTY=false
REPO_HAS_COMMITS=false
REPO_HAS_GIT_USER=false
REPO_HAS_COMMIT_POLICIES=false

detect_repo_state() {
  REPO_IS_BARE=false
  REPO_IS_EMPTY=false
  REPO_HAS_COMMITS=false
  REPO_HAS_GIT_USER=false
  REPO_HAS_COMMIT_POLICIES=false

  if [[ "$(git rev-parse --is-bare-repository 2>/dev/null)" == "true" ]]; then
    REPO_IS_BARE=true
    return
  fi

  if git rev-parse --verify HEAD^{commit} >/dev/null 2>&1; then
    REPO_HAS_COMMITS=true
  else
    # Non-bare repo with no valid HEAD — empty (unborn HEAD)
    REPO_IS_EMPTY=true
  fi

  local user_name; user_name=$(git config user.name 2>/dev/null || true)
  local user_email; user_email=$(git config user.email 2>/dev/null || true)
  if [[ -n "$user_name" && -n "$user_email" ]]; then
    REPO_HAS_GIT_USER=true
  fi

  local gpg_sign; gpg_sign=$(git config --get commit.gpgsign 2>/dev/null || true)
  local hooks_dir; hooks_dir=$(git config --get core.hooksPath 2>/dev/null || true)
  [[ -z "$hooks_dir" ]] && hooks_dir="$(git rev-parse --git-dir 2>/dev/null)/hooks"
  if [[ "$gpg_sign" == "true" ]]; then
    REPO_HAS_COMMIT_POLICIES=true
  elif [[ -x "$hooks_dir/pre-commit" || -x "$hooks_dir/commit-msg" ]]; then
    REPO_HAS_COMMIT_POLICIES=true
  fi
}

# === EXIT Trap for Unexpected Failures ===
_exit_handler() {
  local exit_code=$?
  if [[ $exit_code -eq 0 ]]; then
    return
  fi
  if [[ "$_MOUNT_STRUCTURED_FATAL_EMITTED" == "true" ]]; then
    return
  fi
  echo -e "${RED}[loa] ERROR (E013): Unexpected failure (exit code ${exit_code})${NC}" >&2
  local esc_msg; esc_msg=$(_json_escape "Unexpected failure (exit code ${exit_code})")
  local esc_fix; esc_fix=$(_json_escape "Check git status and retry with --force")
  printf '{"code":"E013","name":"mount_commit_failed","message":"%s","fix":"%s"}\n' \
    "$esc_msg" "$esc_fix" >&2
}
trap '_exit_handler' EXIT

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
SUBMODULE_MODE=false

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
    --submodule)
      SUBMODULE_MODE=true
      shift
      ;;
    --tag)
      # Pass through to submodule mode
      SUBMODULE_TAG="$2"
      shift 2
      ;;
    --ref)
      # Pass through to submodule mode
      SUBMODULE_REF="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: mount-loa.sh [OPTIONS]"
      echo ""
      echo "Installation Modes:"
      echo "  (default)         Standard mode - copies files into .claude/"
      echo "  --submodule       Submodule mode - adds Loa as git submodule at .loa/"
      echo ""
      echo "Standard Mode Options:"
      echo "  --branch <name>   Loa branch to use (default: main)"
      echo "  --force, -f       Force remount without prompting"
      echo "  --stealth         Add state files to .gitignore"
      echo "  --skip-beads      Don't install/initialize Beads CLI"
      echo "  --no-commit       Skip creating git commit after mount"
      echo ""
      echo "Submodule Mode Options:"
      echo "  --submodule       Use submodule installation mode"
      echo "  --branch <name>   Loa branch to track (default: main)"
      echo "  --tag <tag>       Pin to specific Loa tag (e.g., v1.15.0)"
      echo "  --ref <ref>       Pin to specific ref (commit, branch, or tag)"
      echo "  --force, -f       Force remount without prompting"
      echo "  --no-commit       Skip creating git commit after mount"
      echo ""
      echo "Examples:"
      echo "  mount-loa.sh                          # Standard mode, main branch"
      echo "  mount-loa.sh --submodule              # Submodule mode, main branch"
      echo "  mount-loa.sh --submodule --tag v1.15.0  # Submodule pinned to tag"
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

  # Check git executable exists (IMP-002 — containers/minimal environments)
  if ! command -v git &>/dev/null; then
    mount_error E010 "git is not installed. Install: https://git-scm.com/downloads"
  fi

  if ! git rev-parse --git-dir > /dev/null 2>&1; then
    mount_error E010
  fi

  # Detect repo state (bare, empty, user, policy)
  detect_repo_state

  # Reject bare repos — no working tree means mounting is impossible
  if [[ "$REPO_IS_BARE" == "true" ]]; then
    mount_error E015
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

  # Pull upstream .loa-version.json to get correct version (fixes #123)
  log "Pulling version manifest from upstream..."
  git checkout "$LOA_REMOTE_NAME/$LOA_BRANCH" -- .loa-version.json 2>/dev/null || {
    warn "No .loa-version.json in upstream, will use fallback version detection"
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

  # Clean framework development artifacts from grimoire (FR-3, #299)
  clean_grimoire_state

  # Create .reviewignore template for review scope filtering (FR-4, #303)
  create_reviewignore

  mkdir -p .beads
  touch .beads/.gitkeep

  log "Zones synced"
}

# === Clean Grimoire State (FR-3, #299) ===
# Removes framework development artifacts from grimoires/loa/ after git checkout.
# Ensures fresh mounts start clean without upstream cycle artifacts.
clean_grimoire_state() {
  local grimoire_dir="${TARGET_DIR:-.}/grimoires/loa"

  if [[ ! -d "$grimoire_dir" ]]; then
    return 0
  fi

  log "Cleaning framework development artifacts from grimoire..."

  # Remove framework development artifacts
  local artifacts=("prd.md" "sdd.md" "sprint.md" "BEAUVOIR.md" "SOUL.md")
  for artifact in "${artifacts[@]}"; do
    rm -f "${grimoire_dir}/${artifact}"
  done

  # Remove framework a2a and archive directory contents (not the dirs themselves)
  if [[ -d "${grimoire_dir}/a2a" ]]; then
    # Preserve directory structure, remove content
    find "${grimoire_dir}/a2a" -mindepth 1 -maxdepth 1 -type d -exec rm -rf {} + 2>/dev/null || true
    find "${grimoire_dir}/a2a" -mindepth 1 -maxdepth 1 -type f -exec rm -f {} + 2>/dev/null || true
  fi
  if [[ -d "${grimoire_dir}/archive" ]]; then
    find "${grimoire_dir}/archive" -mindepth 1 -exec rm -rf {} + 2>/dev/null || true
  fi

  # Preserve directory structure
  mkdir -p "${grimoire_dir}/a2a/trajectory"
  mkdir -p "${grimoire_dir}/archive"
  mkdir -p "${grimoire_dir}/context"
  mkdir -p "${grimoire_dir}/memory"

  # Initialize clean ledger
  cat > "${grimoire_dir}/ledger.json" << 'LEDGER_EOF'
{
  "version": "1.0.0",
  "cycles": [],
  "active_cycle": null,
  "active_bugfix": null,
  "global_sprint_counter": 0,
  "bugfix_cycles": []
}
LEDGER_EOF

  # Create NOTES.md template if missing
  if [[ ! -f "${grimoire_dir}/NOTES.md" ]]; then
    cat > "${grimoire_dir}/NOTES.md" << 'NOTES_EOF'
# Project Notes

## Learnings

## Blockers

## Observations
NOTES_EOF
  fi

  log "Grimoire state cleaned — ready for /plan-and-analyze"
}

# === Review Scope Initialization ===

create_reviewignore() {
  if [[ -f ".reviewignore" ]]; then
    return 0  # Preserve user edits
  fi

  cat > ".reviewignore" << 'REVIEWIGNORE_EOF'
# .reviewignore — Review scope exclusion patterns
# Gitignore-style syntax. Files matching these patterns are excluded from
# code reviews, audits, and Bridgebuilder analysis.
#
# Zone-based exclusions (from .loa-version.json) are always applied:
#   - System zone (.claude/) — framework internals
#   - State zone (grimoires/, .beads/, .ck/, .run/) — agent state
#
# Add project-specific patterns below.

# Loa framework files (always excluded via zone detection, listed for clarity)
.claude/
grimoires/loa/a2a/
grimoires/loa/archive/
.beads/
.run/

# Framework config (not user code)
.loa-version.json
.loa.config.yaml.example

# Generated files
*.min.js
*.min.css
*.map

# Vendored dependencies
vendor/
node_modules/

# =============================================================================
# Project-specific exclusions — add your patterns below
# =============================================================================
REVIEWIGNORE_EOF

  log "Created .reviewignore"
}

# === Root File Sync (CLAUDE.md, PROCESS.md) ===

# Sync framework instructions to .claude/loa/CLAUDE.loa.md
sync_loa_claude_md() {
  step "Syncing framework instructions..."

  mkdir -p .claude/loa

  # Pull CLAUDE.loa.md from upstream
  git checkout "$LOA_REMOTE_NAME/$LOA_BRANCH" -- .claude/loa/CLAUDE.loa.md 2>/dev/null || {
    warn "No .claude/loa/CLAUDE.loa.md in upstream, skipping..."
    return 1
  }

  log "Framework instructions synced to .claude/loa/CLAUDE.loa.md"
}

# Create CLAUDE.md with @ import pattern for fresh installs
create_claude_md_with_import() {
  cat > CLAUDE.md << 'EOF'
@.claude/loa/CLAUDE.loa.md

# Project-Specific Instructions

> This file contains project-specific customizations that take precedence over the framework instructions.
> The framework instructions are loaded via the `@` import above.

## Project Configuration

Add your project-specific Claude Code instructions here. These instructions will take precedence
over the imported framework defaults.

### Example Customizations

```markdown
## Tech Stack
- Language: TypeScript
- Framework: Next.js 14
- Database: PostgreSQL

## Coding Standards
- Use functional components with hooks
- Prefer named exports
- Always include unit tests

## Domain Context
- This is a fintech application
- Security is paramount
- All API calls must be authenticated
```

## How This Works

1. Claude Code loads `@.claude/loa/CLAUDE.loa.md` first (framework instructions)
2. Then loads this file (project-specific instructions)
3. Instructions in this file **take precedence** over imported content
4. Framework updates modify `.claude/loa/CLAUDE.loa.md`, not this file

## Related Documentation

- `.claude/loa/CLAUDE.loa.md` - Framework-managed instructions (auto-updated)
- `.loa.config.yaml` - User configuration file
- `PROCESS.md` - Detailed workflow documentation
EOF

  log "Created CLAUDE.md with @ import pattern"
}

# Handle CLAUDE.md setup with @ import pattern
# IMPORTANT: Never auto-modify user's existing CLAUDE.md
setup_claude_md() {
  local file="CLAUDE.md"

  if [[ -f "$file" ]]; then
    # Check if it already has the @ import
    if grep -q "@.claude/loa/CLAUDE.loa.md" "$file" 2>/dev/null; then
      log "CLAUDE.md already has @ import, no changes needed"
      return 0
    fi

    # Check for legacy LOA:BEGIN markers
    if grep -q "<!-- LOA:BEGIN" "$file" 2>/dev/null; then
      warn "CLAUDE.md has legacy LOA:BEGIN markers"
      echo ""
      info "Please migrate to the new @ import pattern:"
      info "  1. Replace the <!-- LOA:BEGIN --> ... <!-- LOA:END --> section with:"
      info "     @.claude/loa/CLAUDE.loa.md"
      info "  2. Keep your project-specific content after the import"
      echo ""
      return 0
    fi

    # Existing CLAUDE.md without Loa content - prompt user to add import
    echo ""
    warn "======================================================================="
    warn "  EXISTING CLAUDE.md DETECTED"
    warn "======================================================================="
    echo ""
    info "Your project already has a CLAUDE.md file."
    info "To integrate Loa framework instructions, add this line at the TOP of your CLAUDE.md:"
    echo ""
    echo -e "  ${CYAN}@.claude/loa/CLAUDE.loa.md${NC}"
    echo ""
    info "This uses Claude Code's @ import pattern to load framework instructions"
    info "while preserving your project-specific content."
    echo ""
    info "Your content will take PRECEDENCE over imported framework defaults."
    echo ""
    warn "The mount script will NOT modify your existing CLAUDE.md automatically."
    warn "======================================================================="
    echo ""
    return 0
  else
    # No CLAUDE.md exists - create with @ import
    log "Creating CLAUDE.md with @ import pattern..."
    create_claude_md_with_import
  fi
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

# Orchestrate root file synchronization
sync_root_files() {
  step "Syncing root documentation files..."

  # Sync framework instructions to .claude/loa/
  sync_loa_claude_md

  # Setup CLAUDE.md with @ import pattern
  setup_claude_md

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

  # Version detection priority (fixes #123):
  # 1. Root .loa-version.json (pulled from upstream in sync_zones)
  # 2. Fallback: query git for the latest tag
  # 3. Final fallback: "unknown"
  local upstream_version=""

  # Try reading from upstream .loa-version.json (should exist after sync_zones)
  if [[ -f ".loa-version.json" ]]; then
    upstream_version=$(jq -r '.framework_version // ""' .loa-version.json 2>/dev/null)
  fi

  # Fallback: try to get version from latest git tag
  if [[ -z "$upstream_version" || "$upstream_version" == "null" ]]; then
    upstream_version=$(git tag -l 'loa@v*' --sort=-v:refname 2>/dev/null | head -1 | sed 's/loa@v//')
  fi

  # Final fallback
  if [[ -z "$upstream_version" ]]; then
    warn "Could not detect upstream version, using 'unknown'"
    upstream_version="unknown"
  fi

  log "Detected upstream version: $upstream_version"

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

  log "Version manifest created (v$upstream_version)"
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

# === Initialize URL Registry ===
init_url_registry() {
  step "Initializing URL registry..."

  local urls_file="grimoires/loa/urls.yaml"
  if [[ ! -f "$urls_file" ]]; then
    cat > "$urls_file" << 'EOF'
# Canonical URL Registry
# Agents MUST use these URLs instead of guessing/hallucinating
# See: .claude/protocols/url-registry.md

environments:
  production:
    base: ""        # e.g., https://myapp.com
    api: ""         # e.g., https://api.myapp.com
  staging:
    base: ""        # e.g., https://staging.myapp.com
  local:
    base: http://localhost:3000
    api: http://localhost:3000/api

# Placeholders for unconfigured environments
# Agents use these when actual URLs aren't configured
placeholders:
  domain: your-domain.example.com
  api_base: "{{base}}/api"

# Service-specific URLs (optional)
# services:
#   docs: https://docs.myapp.com
#   dashboard: https://dashboard.myapp.com
EOF
    log "URL registry initialized"
  else
    log "URL registry already exists"
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

# === Empty Repo Commit Helper ===
# Specialized commit logic for repos with no commits (unborn HEAD)
_handle_empty_repo_commit() {
  local new_version="$1"
  local fw_paths=(.claude .loa-version.json CLAUDE.md PROCESS.md)

  step "Creating initial commit for empty repository..."

  # Check git user identity
  if [[ "$REPO_HAS_GIT_USER" != "true" ]]; then
    mount_error E012
  fi

  # Stage all framework files
  if ! git add -- "${fw_paths[@]}" 2>/dev/null; then
    mount_error E014
  fi

  # Also stage any other framework-created files (best-effort)
  git add grimoires/ .beads/ .loa.config.yaml .gitignore 2>/dev/null || true

  # Build initial commit message
  local commit_prefix="chore"
  if command -v yq &>/dev/null && [[ -f "$CONFIG_FILE" ]]; then
    commit_prefix=$(yq_read "$CONFIG_FILE" ".upgrade.commit_prefix" "chore")
  fi

  local commit_msg="${commit_prefix}(loa): mount framework v${new_version} (initial commit)

- Initialized repository with Loa framework
- Created .claude/ directory structure
- Added CLAUDE.md (Claude Code instructions)
- Added PROCESS.md (workflow documentation)
- See: https://github.com/0xHoneyJar/loa/releases/tag/v${new_version}

Generated by Loa mount-loa.sh"

  # Attempt commit (attempt-first — classify failure from stderr, don't pre-block)
  local git_stderr
  git_stderr=$(git commit -m "$commit_msg" --no-verify 2>&1 1>/dev/null) || {
    # Commit failed — unstage framework files (preserve on disk)
    if git restore --staged -- "${fw_paths[@]}" 2>/dev/null; then
      : # git 2.23+ — only touches index
    elif git reset -q -- "${fw_paths[@]}" 2>/dev/null; then
      : # fallback for older git
    else
      # IMP-003: Both rollback methods failed
      echo -e "${YELLOW}[loa] WARNING: Could not unstage framework files — manual cleanup may be needed${NC}" >&2
    fi

    # Classify stderr for specific error classes
    if echo "$git_stderr" | grep -qi "user\|name\|email\|identity\|author"; then
      mount_error E012 "Git stderr: $git_stderr"
    elif echo "$git_stderr" | grep -qi "gpg\|signing\|hook"; then
      mount_warn_policy "Git stderr: $git_stderr"
      return 0  # Non-fatal: files on disk
    else
      mount_error E011 "Git stderr: $git_stderr"
    fi
  }

  log "Initial commit created with framework files"
  create_version_tag "$new_version"
  return 0
}

# === Create Upgrade Commit ===
# Creates a single atomic commit for framework mount/upgrade
# Arguments:
#   $1 - commit_type: "mount" or "update"
#   $2 - old_version: previous version (or "none" for fresh mount)
#   $3 - new_version: new version being installed
create_upgrade_commit() {
  local commit_type="${1:-mount}"
  local old_version="${2:-none}"
  local new_version="${3:-unknown}"

  # Check if --no-commit flag was passed
  if [[ "$NO_COMMIT" == "true" ]]; then
    log "Skipping commit (--no-commit)"
    return 0
  fi

  # Check stealth mode - no commits in stealth
  local mode="standard"
  if [[ "$STEALTH_MODE" == "true" ]]; then
    mode="stealth"
  elif command -v yq &>/dev/null && [[ -f "$CONFIG_FILE" ]]; then
    mode=$(yq_read "$CONFIG_FILE" '.persistence_mode' "standard")
  fi

  if [[ "$mode" == "stealth" ]]; then
    log "Skipping commit (stealth mode)"
    return 0
  fi

  # Check config option for auto_commit
  local auto_commit="true"
  if command -v yq &>/dev/null && [[ -f "$CONFIG_FILE" ]]; then
    auto_commit=$(yq_read "$CONFIG_FILE" '.upgrade.auto_commit' "true")
  fi

  if [[ "$auto_commit" != "true" ]]; then
    log "Skipping commit (auto_commit: false in config)"
    return 0
  fi

  # Framework file paths (for staging and rollback)
  local fw_paths=(.claude .loa-version.json CLAUDE.md PROCESS.md)

  # Re-detect repo state (defensive — may have changed since preflight)
  detect_repo_state

  # === EMPTY REPO HANDLING ===
  if [[ "$REPO_IS_EMPTY" == "true" ]]; then
    _handle_empty_repo_commit "$new_version"
    return $?
  fi

  # === EXISTING REPO HANDLING ===

  # Dirty tree warning — only warn about files NOT created by this script
  if [[ "$FORCE_MODE" != "true" ]]; then
    local user_changes
    user_changes=$(git diff --name-only 2>/dev/null | grep -v -E '^(\.claude/|CLAUDE\.md|PROCESS\.md|\.loa-version\.json)' || true)
    if [[ -n "$user_changes" ]]; then
      warn "Working tree has unstaged changes (not related to Loa) — they will NOT be included in commit"
    fi
  fi

  step "Creating upgrade commit..."

  # Stage framework files
  if ! git add -- "${fw_paths[@]}" 2>/dev/null; then
    mount_error E014
  fi

  # Check if there are staged changes
  if git diff --cached --quiet 2>/dev/null; then
    log "No changes to commit (framework already up to date)"
    return 0
  fi

  # Build commit message
  local commit_prefix="chore"
  if command -v yq &>/dev/null && [[ -f "$CONFIG_FILE" ]]; then
    commit_prefix=$(yq_read "$CONFIG_FILE" '.upgrade.commit_prefix' "chore")
  fi

  local commit_msg
  if [[ "$commit_type" == "mount" ]]; then
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

  # Attempt commit
  local git_stderr
  git_stderr=$(git commit -m "$commit_msg" --no-verify 2>&1 1>/dev/null) || {
    # Commit failed — path-scoped unstage (preserve files on disk)
    if git restore --staged -- "${fw_paths[@]}" 2>/dev/null; then
      : # Success — files remain on disk, only unstaged
    elif git reset -q -- "${fw_paths[@]}" 2>/dev/null; then
      : # Fallback for git < 2.23
    else
      # IMP-003: Both rollback methods failed
      echo -e "${YELLOW}[loa] WARNING: Could not unstage framework files — manual cleanup may be needed${NC}" >&2
    fi

    # Classify stderr for known failure classes
    if echo "$git_stderr" | grep -qi "gpg\|signing\|hook"; then
      mount_warn_policy "Git stderr: $git_stderr"
      return 0  # Non-fatal: files on disk, user commits manually
    elif echo "$git_stderr" | grep -qi "user\|name\|email\|identity\|author"; then
      mount_error E012 "Git stderr: $git_stderr"
    else
      mount_error E013 "Git stderr: $git_stderr"
    fi
  }

  log "Committed: ${commit_prefix}(loa): ${commit_type} framework v${new_version}"

  # Create version tag
  create_version_tag "$new_version"
}

# === Check Installation Mode Conflicts ===
check_mode_conflicts() {
  # Check if already installed in a different mode
  if [[ -f "$VERSION_FILE" ]]; then
    local current_mode=$(jq -r '.installation_mode // "standard"' "$VERSION_FILE" 2>/dev/null)

    if [[ "$SUBMODULE_MODE" == "true" ]] && [[ "$current_mode" == "standard" ]]; then
      err "Loa is installed in standard mode. Cannot switch to submodule mode.
To switch modes:
  1. Run '/loa eject' to eject from current installation
  2. Remove .claude/ and .loa-version.json
  3. Run mount-loa.sh --submodule"
    fi

    if [[ "$SUBMODULE_MODE" == "false" ]] && [[ "$current_mode" == "submodule" ]]; then
      err "Loa is installed in submodule mode. Cannot switch to standard mode.
To switch modes:
  1. Remove the submodule: git submodule deinit -f .loa && git rm -f .loa
  2. Remove symlinks: rm -rf .claude
  3. Remove .loa-version.json and .loa.config.yaml
  4. Run mount-loa.sh"
    fi
  fi
}

# === Route to Submodule Script ===
route_to_submodule() {
  local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local submodule_script="${script_dir}/mount-submodule.sh"

  # Build arguments to pass through
  local args=()
  [[ -n "${SUBMODULE_TAG:-}" ]] && args+=(--tag "$SUBMODULE_TAG")
  [[ -n "${SUBMODULE_REF:-}" ]] && args+=(--ref "$SUBMODULE_REF")
  [[ "$LOA_BRANCH" != "main" ]] && args+=(--branch "$LOA_BRANCH")
  [[ "$FORCE_MODE" == "true" ]] && args+=(--force)
  [[ "$NO_COMMIT" == "true" ]] && args+=(--no-commit)

  if [[ -x "$submodule_script" ]]; then
    exec "$submodule_script" "${args[@]}"
  else
    err "Submodule script not found at: $submodule_script
Please ensure Loa framework is complete or download mount-submodule.sh manually."
  fi
}

# === Post-Mount Verification ===
# Validates framework install after sync completes.
# Exit 0 = success (warnings OK), exit 1 = required check failed.
# Flags: --quiet (no output), --json (structured), --strict (warnings→failure)
verify_mount() {
  local quiet=false json_out=false strict=false
  local warnings=0 errors=0
  local checks=()

  for arg in "$@"; do
    case "$arg" in
      --quiet) quiet=true ;;
      --json) json_out=true ;;
      --strict) strict=true ;;
    esac
  done

  # Check 1: Framework files
  if [[ -f ".claude/commands/loa.md" && -f ".claude/scripts/golden-path.sh" ]]; then
    checks+=('{"name":"framework","status":"pass","detail":"Core files synced"}')
  else
    checks+=('{"name":"framework","status":"fail","detail":"Missing core framework files"}')
    errors=$((errors + 1))
  fi

  # Check 2: Configuration
  if [[ -f ".loa.config.yaml" ]]; then
    checks+=('{"name":"config","status":"pass","detail":".loa.config.yaml created"}')
  else
    checks+=('{"name":"config","status":"fail","detail":"Missing .loa.config.yaml"}')
    errors=$((errors + 1))
  fi

  # Check 3: Required deps
  for dep in jq yq git; do
    if command -v "$dep" >/dev/null 2>&1; then
      local ver
      ver=$("$dep" --version 2>&1 | head -1)
      checks+=("$(jq -n --arg n "dep_${dep}" --arg d "$ver" '{name:$n,status:"pass",detail:$d}')")
    else
      checks+=("$(jq -n --arg n "dep_${dep}" '{name:$n,status:"fail",detail:"Not found"}')")
      errors=$((errors + 1))
    fi
  done

  # Check 4: Optional tools
  for tool in br ck; do
    if command -v "$tool" >/dev/null 2>&1; then
      local ver
      ver=$("$tool" --version 2>&1 | head -1)
      checks+=("$(jq -n --arg n "opt_${tool}" --arg d "$ver" '{name:$n,status:"pass",detail:$d}')")
    else
      checks+=("$(jq -n --arg n "opt_${tool}" --arg t "$tool" '{name:$n,status:"warn",detail:($t + " not installed (optional)")}')")
      warnings=$((warnings + 1))
    fi
  done

  # Check 5: API key presence (NFR-8: boolean only, zero key material)
  if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
    checks+=('{"name":"api_key","status":"pass","detail":"ANTHROPIC_API_KEY is set"}')
  else
    checks+=('{"name":"api_key","status":"warn","detail":"ANTHROPIC_API_KEY not set (needed for Claude Code)"}')
    warnings=$((warnings + 1))
  fi

  # Determine exit code
  local exit_code=0
  if [[ "$errors" -gt 0 ]]; then
    exit_code=1
  elif [[ "$strict" == "true" && "$warnings" -gt 0 ]]; then
    exit_code=1
  fi

  # Output (Flatline SKP-004: use jq for safe JSON assembly)
  if [[ "$json_out" == "true" ]]; then
    local status_str="pass"
    [[ "$errors" -gt 0 ]] && status_str="fail"
    jq -n \
      --arg status "$status_str" \
      --argjson errors "$errors" \
      --argjson warnings "$warnings" \
      --argjson checks "$(printf '%s\n' "${checks[@]}" | jq -s '.')" \
      '{status: $status, errors: $errors, warnings: $warnings, checks: $checks}'
  elif [[ "$quiet" != "true" ]]; then
    echo ""
    step "Post-mount verification..."
    for check_json in "${checks[@]}"; do
      local st dt
      st=$(echo "$check_json" | jq -r '.status')
      dt=$(echo "$check_json" | jq -r '.detail')
      case "$st" in
        pass) info "  ✓ ${dt}" ;;
        warn) warn "  ⚠ ${dt}" ;;
        fail) err_msg "  ✗ ${dt}" ;;
      esac
    done
    echo ""
  fi

  return "$exit_code"
}

# Non-fatal error display (doesn't exit)
err_msg() { echo -e "${RED}[loa]${NC} $*"; }

# === Main ===
main() {
  # Route to submodule mode if requested
  if [[ "$SUBMODULE_MODE" == "true" ]]; then
    echo ""
    log "======================================================================="
    log "  Loa Framework Mount (Submodule Mode)"
    log "======================================================================="
    echo ""
    check_mode_conflicts
    route_to_submodule
    exit 0  # Should not reach here (exec above)
  fi

  echo ""
  log "======================================================================="
  log "  Loa Framework Mount"
  log "  Enterprise-Grade Managed Scaffolding"
  log "======================================================================="
  log "  Branch: $LOA_BRANCH"
  [[ "$FORCE_MODE" == "true" ]] && log "  Mode: Force remount"
  echo ""

  check_mode_conflicts
  preflight
  install_beads
  setup_remote
  sync_zones
  sync_root_files
  init_structured_memory
  init_url_registry
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

  # === Enforce Feature Gates ===
  # Move disabled skills to .skills-disabled/ based on .loa.config.yaml
  if [[ -x ".claude/scripts/feature-gates.sh" ]]; then
    step "Enforcing feature gates..."
    .claude/scripts/feature-gates.sh enforce 2>/dev/null || {
      warn "Feature gate enforcement skipped (script returned error)"
    }
  else
    # Feature gates script not yet available - this is expected for older versions
    log "Feature gates: not enforced (feature-gates.sh not available)"
  fi

  # === Post-Mount Verification ===
  verify_mount || {
    warn "Post-mount verification found issues (see above)"
  }

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
    info "  2. Run '/loa setup' to check dependencies"
    info "  3. Start planning with '/plan'"
    echo ""
  fi

  warn "STRICT ENFORCEMENT: Direct edits to .claude/ will block agent execution."
  warn "Use .claude/overrides/ for customizations."
  echo ""

  # === Golden Path Next Steps ===
  echo ""
  log "Next steps:"
  log "  1. Start Claude Code:  claude"
  log "  2. Run setup wizard:   /loa setup"
  log "  3. Start planning:     /plan"
  echo ""
}

main "$@"
