#!/usr/bin/env bash
# loa-eject.sh - Transfer full ownership of Loa framework files to user
#
# This script "ejects" from the managed Loa framework, giving the user full
# ownership of all framework files. After ejection:
# - Framework updates via /update-loa will no longer work
# - All files become user-owned and can be freely modified
# - The `loa-` prefix is removed from skills/commands (if present)
# - Magic markers and hashes are removed
# - CLAUDE.md is merged with framework instructions
#
# Usage:
#   loa-eject.sh [OPTIONS]
#
# Options:
#   --dry-run         Show what would be changed without making changes
#   --force           Skip confirmation prompt
#   --include-packs   Also eject pack-installed content from constructs
#   -h, --help        Show this help message
#
set -euo pipefail

# MED-001 FIX: Set restrictive umask for secure temp file creation
# This ensures mktemp creates files with 600 permissions atomically
umask 077

# === Colors ===
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# === Logging ===
log() { echo -e "${GREEN}[loa-eject]${NC} $*"; }
warn() { echo -e "${YELLOW}[loa-eject]${NC} WARNING: $*"; }
err() { echo -e "${RED}[loa-eject]${NC} ERROR: $*" >&2; exit 1; }
info() { echo -e "${CYAN}[loa-eject]${NC} $*"; }
step() { echo -e "${BLUE}[loa-eject]${NC} -> $*"; }

# === Configuration ===
DRY_RUN=false
FORCE=false
INCLUDE_PACKS=false
BACKUP_DIR=""
CONFIG_FILE=".loa.config.yaml"
VERSION_FILE=".loa-version.json"

# === Argument Parsing ===
while [[ $# -gt 0 ]]; do
  case $1 in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --force)
      FORCE=true
      shift
      ;;
    --include-packs)
      INCLUDE_PACKS=true
      shift
      ;;
    -h|--help)
      echo "Usage: loa-eject.sh [OPTIONS]"
      echo ""
      echo "Transfer full ownership of Loa framework files to user."
      echo "After ejection, framework updates will no longer work."
      echo ""
      echo "Options:"
      echo "  --dry-run         Show what would change without making changes"
      echo "  --force           Skip confirmation prompt"
      echo "  --include-packs   Also eject pack-installed content"
      echo "  -h, --help        Show this help message"
      echo ""
      echo "What happens on eject:"
      echo "  1. Creates timestamped backup of .claude/ directory"
      echo "  2. Removes magic markers (@loa-managed) from all files"
      echo "  3. Removes 'loa-' prefix from skill/command names (if present)"
      echo "  4. Merges .claude/loa/CLAUDE.loa.md into CLAUDE.md"
      echo "  5. Removes @ import statement from CLAUDE.md"
      echo "  6. Sets ejected: true in .loa.config.yaml"
      echo ""
      exit 0
      ;;
    *)
      warn "Unknown option: $1"
      shift
      ;;
  esac
done

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

yq_set() {
  local file="$1"
  local path="$2"
  local value="$3"

  if yq --version 2>&1 | grep -q "mikefarah"; then
    yq eval -i "${path} = ${value}" "$file" 2>/dev/null
  else
    # Python yq doesn't support in-place editing the same way
    local tmp=$(mktemp)
    yq -Y "${path} = ${value}" "$file" > "$tmp" && mv "$tmp" "$file"
  fi
}

# === Marker Detection and Removal ===

# Check if file has @loa-managed marker
has_marker() {
  local file="$1"
  # Check first 5 lines for marker
  head -5 "$file" 2>/dev/null | grep -q "@loa-managed"
}

# Check if file has pack marker (for --include-packs)
has_pack_marker() {
  local file="$1"
  head -5 "$file" 2>/dev/null | grep -q "@pack-managed"
}

# Remove marker from file based on file type
remove_marker() {
  local file="$1"
  local ext="${file##*.}"

  if [[ "$DRY_RUN" == "true" ]]; then
    step "[dry-run] Would remove marker from: $file"
    return 0
  fi

  case "$ext" in
    sh|bash)
      # Shell: Remove lines with @loa-managed and WARNING from top (after shebang)
      local tmp=$(mktemp)
      local shebang=""
      if head -1 "$file" | grep -q "^#!"; then
        shebang=$(head -1 "$file")
        tail -n +2 "$file" | grep -v "@loa-managed" | grep -v "WARNING.*managed by.*Loa" > "$tmp"
        echo "$shebang" > "$file.new"
        cat "$tmp" >> "$file.new"
        mv "$file.new" "$file"
      else
        grep -v "@loa-managed" "$file" | grep -v "WARNING.*managed by.*Loa" > "$tmp"
        mv "$tmp" "$file"
      fi
      rm -f "$tmp"
      ;;
    md)
      # Markdown: Remove HTML comment markers
      local tmp=$(mktemp)
      grep -v "<!-- @loa-managed" "$file" | grep -v "<!-- WARNING.*managed by.*Loa" > "$tmp"
      mv "$tmp" "$file"
      ;;
    yaml|yml)
      # YAML: Remove comment markers
      local tmp=$(mktemp)
      grep -v "# @loa-managed" "$file" | grep -v "# WARNING.*managed by.*Loa" > "$tmp"
      mv "$tmp" "$file"
      ;;
    json)
      # JSON: Remove _loa_marker key if present
      if grep -q "_loa_marker" "$file"; then
        local tmp=$(mktemp)
        jq 'del(._loa_marker)' "$file" > "$tmp"
        mv "$tmp" "$file"
      fi
      ;;
    *)
      # Generic: Try removing common comment patterns
      local tmp=$(mktemp)
      grep -v "@loa-managed" "$file" | grep -v "WARNING.*managed by.*Loa" > "$tmp"
      mv "$tmp" "$file"
      ;;
  esac

  step "Removed marker from: $file"
}

# === Prefix Removal ===

# Remove loa- prefix from skill directory name
remove_skill_prefix() {
  local skill_dir="$1"
  local skill_name=$(basename "$skill_dir")

  # Only process if has loa- prefix
  if [[ "$skill_name" != loa-* ]]; then
    return 0
  fi

  local new_name="${skill_name#loa-}"
  local parent_dir=$(dirname "$skill_dir")
  local new_path="${parent_dir}/${new_name}"

  if [[ -d "$new_path" ]]; then
    warn "Cannot rename $skill_name: $new_name already exists"
    return 1
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    step "[dry-run] Would rename skill: $skill_name -> $new_name"
    return 0
  fi

  mv "$skill_dir" "$new_path"
  step "Renamed skill: $skill_name -> $new_name"

  # Update index.yaml name field
  local index_file="${new_path}/index.yaml"
  if [[ -f "$index_file" ]]; then
    sed "s/^name: \"loa-/name: \"/g" "$index_file" > "${index_file}.tmp" && mv "${index_file}.tmp" "$index_file"
    sed "s/^name: loa-/name: /g" "$index_file" > "${index_file}.tmp" && mv "${index_file}.tmp" "$index_file"
  fi
}

# Remove loa- prefix from command file name
remove_command_prefix() {
  local cmd_file="$1"
  local cmd_name=$(basename "$cmd_file")

  # Only process if has loa- prefix (but not loa.md itself)
  if [[ "$cmd_name" != loa-* ]]; then
    return 0
  fi

  local new_name="${cmd_name#loa-}"
  local parent_dir=$(dirname "$cmd_file")
  local new_path="${parent_dir}/${new_name}"

  if [[ -f "$new_path" ]]; then
    warn "Cannot rename $cmd_name: $new_name already exists"
    return 1
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    step "[dry-run] Would rename command: $cmd_name -> $new_name"
    return 0
  fi

  mv "$cmd_file" "$new_path"
  step "Renamed command: $cmd_name -> $new_name"

  # Update name field in frontmatter
  sed "s/^name: loa-/name: /g" "$new_path" > "${new_path}.tmp" && mv "${new_path}.tmp" "$new_path"
}

# === CLAUDE.md Merge ===

# Merge .claude/loa/CLAUDE.loa.md into CLAUDE.md
merge_claude_md() {
  local claude_md="CLAUDE.md"
  local loa_claude_md=".claude/loa/CLAUDE.loa.md"

  if [[ ! -f "$loa_claude_md" ]]; then
    warn "No $loa_claude_md found, skipping merge"
    return 0
  fi

  if [[ ! -f "$claude_md" ]]; then
    # No CLAUDE.md, just move loa file
    if [[ "$DRY_RUN" == "true" ]]; then
      step "[dry-run] Would move $loa_claude_md to $claude_md"
    else
      mv "$loa_claude_md" "$claude_md"
      # Remove marker from the moved file
      remove_marker "$claude_md"
      step "Moved $loa_claude_md to $claude_md"
    fi
    return 0
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    step "[dry-run] Would merge $loa_claude_md into $claude_md"
    step "[dry-run] Would remove @ import line from $claude_md"
    return 0
  fi

  # Read framework content (skip marker lines)
  local framework_content=$(grep -v "<!-- @loa-managed" "$loa_claude_md" | grep -v "<!-- WARNING.*managed by.*Loa")

  # Read user CLAUDE.md, remove @ import line
  local user_content=$(grep -v "^@.claude/loa/CLAUDE.loa.md" "$claude_md" | grep -v "^@.*/CLAUDE.*\.md")

  # Create merged file: framework first, then user content
  {
    echo "# Combined Instructions (Ejected from Loa)"
    echo ""
    echo "> This file was created by loa-eject. The framework instructions have been"
    echo "> merged with your project-specific instructions. You now own all content."
    echo ""
    echo "---"
    echo ""
    echo "$framework_content"
    echo ""
    echo "---"
    echo ""
    echo "# Project-Specific Instructions"
    echo ""
    echo "$user_content"
  } > "$claude_md.new"

  mv "$claude_md.new" "$claude_md"
  step "Merged framework instructions into CLAUDE.md"

  # Remove the now-merged loa file
  rm -f "$loa_claude_md"
  step "Removed $loa_claude_md"
}

# === Backup ===

create_backup() {
  local timestamp=$(date +%Y%m%d_%H%M%S)
  BACKUP_DIR=".claude.backup.${timestamp}"

  if [[ "$DRY_RUN" == "true" ]]; then
    step "[dry-run] Would create backup at: $BACKUP_DIR"
    return 0
  fi

  if [[ -d ".claude" ]]; then
    cp -r .claude "$BACKUP_DIR"
    step "Created backup at: $BACKUP_DIR"
  fi

  # Also backup config and version files
  [[ -f "$CONFIG_FILE" ]] && cp "$CONFIG_FILE" "${BACKUP_DIR}/.loa.config.yaml.backup"
  [[ -f "$VERSION_FILE" ]] && cp "$VERSION_FILE" "${BACKUP_DIR}/.loa-version.json.backup"
}

# === Config Update ===

update_config() {
  if [[ ! -f "$CONFIG_FILE" ]]; then
    warn "No $CONFIG_FILE found, cannot mark as ejected"
    return 0
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    step "[dry-run] Would set ejected: true in $CONFIG_FILE"
    step "[dry-run] Would set ejected_at timestamp"
    return 0
  fi

  local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  # Add ejected fields using yq
  if command -v yq &> /dev/null; then
    yq_set "$CONFIG_FILE" ".ejected" "true"
    yq_set "$CONFIG_FILE" ".ejected_at" "\"${timestamp}\""
    step "Updated config: ejected: true, ejected_at: $timestamp"
  else
    # Fallback: append to file
    {
      echo ""
      echo "# Ejected from Loa framework"
      echo "ejected: true"
      echo "ejected_at: \"$timestamp\""
    } >> "$CONFIG_FILE"
    step "Updated config (appended): ejected: true"
  fi
}

# === Pre-flight Checks ===

preflight() {
  log "Running pre-flight checks..."

  # Check we're in a project with Loa
  if [[ ! -d ".claude" ]]; then
    err "No .claude/ directory found. Is Loa mounted on this project?"
  fi

  # Check if already ejected
  if [[ -f "$CONFIG_FILE" ]]; then
    local ejected=$(yq_read "$CONFIG_FILE" ".ejected" "false")
    if [[ "$ejected" == "true" ]]; then
      err "This project has already been ejected from Loa"
    fi
  fi

  # Check for required tools
  command -v grep >/dev/null || err "grep is required"
  command -v sed >/dev/null || err "sed is required"

  log "Pre-flight checks passed"
}

# === Detect Installation Mode (Task 3.5, cycle-035 sprint-3) ===

detect_installation_mode() {
  if [[ ! -f "$VERSION_FILE" ]]; then
    echo "standard"
    return
  fi
  local mode
  mode=$(jq -r '.installation_mode // "standard"' "$VERSION_FILE" 2>/dev/null) || true
  echo "${mode:-standard}"
}

# === Submodule Eject (Task 3.5, cycle-035 sprint-3) ===
# Converts submodule installation to vendored by:
# 1. Copying framework files from .loa/.claude/ into .claude/ (replacing symlinks)
# 2. Deinitializing the git submodule
# 3. Updating .loa-version.json to standard mode

eject_submodule() {
  local submodule_path
  submodule_path=$(jq -r '.submodule.path // ".loa"' "$VERSION_FILE" 2>/dev/null) || true
  submodule_path="${submodule_path:-.loa}"

  if [[ ! -d "$submodule_path/.claude" ]]; then
    err "Submodule at $submodule_path does not contain .claude/ directory. Cannot eject."
  fi

  step "Ejecting from submodule mode..."

  # === Phase 1: Replace symlinks with real copies ===
  # Uses authoritative manifest (DRY — Bridgebuilder Tension 1)
  step "Replacing symlinks with real files..."
  local replaced=0

  # Source shared symlink manifest and cross-platform compat layer
  local _script_dir
  _script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  source "${_script_dir}/lib/symlink-manifest.sh"
  source "${_script_dir}/compat-lib.sh"
  get_symlink_manifest "$submodule_path" "$(pwd)"

  # Iterate all manifest entries — replace symlinks with real copies
  for entry in "${MANIFEST_DIR_SYMLINKS[@]}" "${MANIFEST_FILE_SYMLINKS[@]}" "${MANIFEST_SKILL_SYMLINKS[@]}" "${MANIFEST_CMD_SYMLINKS[@]}"; do
    local link_path="${entry%%:*}"
    if [[ -L "$link_path" ]]; then
      # Resolve the real source path in the submodule
      local real_src
      # Use get_canonical_path() from compat-lib.sh for macOS portability (high-1)
      # readlink -f is GNU coreutils only; macOS BSD readlink lacks -f flag
      real_src=$(get_canonical_path "$link_path" 2>/dev/null || true)
      if [[ "$DRY_RUN" == "true" ]]; then
        step "[dry-run] Would replace symlink: $link_path"
      else
        rm -f "$link_path"
        if [[ -n "$real_src" && -e "$real_src" ]]; then
          cp -r "$real_src" "$link_path"
          log "  Replaced: $link_path (symlink -> real copy)"
          ((replaced++)) || true
        fi
      fi
    fi
  done

  # Also check settings.local.json (not in manifest — user-owned extension)
  if [[ -L ".claude/settings.local.json" ]]; then
    local real_src
    # Use get_canonical_path() from compat-lib.sh for macOS portability (high-1)
    real_src=$(get_canonical_path ".claude/settings.local.json" 2>/dev/null || true)
    if [[ "$DRY_RUN" == "true" ]]; then
      step "[dry-run] Would replace symlink: .claude/settings.local.json"
    else
      rm -f ".claude/settings.local.json"
      if [[ -n "$real_src" && -e "$real_src" ]]; then
        cp "$real_src" ".claude/settings.local.json"
        log "  Replaced: .claude/settings.local.json"
        ((replaced++)) || true
      fi
    fi
  fi

  log "Replaced $replaced symlinks with real files"

  # === Phase 2: Deinit submodule ===
  if [[ "$DRY_RUN" == "true" ]]; then
    step "[dry-run] Would deinit submodule: $submodule_path"
    step "[dry-run] Would remove submodule entry from .gitmodules"
  else
    step "Deinitializing submodule..."
    git submodule deinit -f "$submodule_path" 2>/dev/null || warn "submodule deinit returned non-zero"
    git rm -f "$submodule_path" 2>/dev/null || warn "git rm submodule returned non-zero"
    rm -rf ".git/modules/${submodule_path}" 2>/dev/null || true
    rm -rf "$submodule_path" 2>/dev/null || true
    # Remove .gitmodules if empty
    if [[ -f ".gitmodules" ]] && [[ ! -s ".gitmodules" ]]; then
      rm -f ".gitmodules"
    fi
    log "Submodule removed: $submodule_path"
  fi

  # === Phase 3: Update version manifest ===
  if [[ "$DRY_RUN" == "true" ]]; then
    step "[dry-run] Would update .loa-version.json to standard mode"
  else
    if [[ -f "$VERSION_FILE" ]]; then
      local tmp
      tmp=$(mktemp)
      jq '.installation_mode = "standard" | del(.submodule)' "$VERSION_FILE" > "$tmp"
      mv "$tmp" "$VERSION_FILE"
      log "Updated $VERSION_FILE: installation_mode = standard"
    fi
  fi
}

# === Main Eject Process ===

eject_files() {
  log "Starting eject process..."

  # === 0. Detect installation mode and handle submodule (Task 3.5) ===
  local install_mode
  install_mode=$(detect_installation_mode)
  if [[ "$install_mode" == "submodule" ]]; then
    step "Detected submodule installation mode"
    eject_submodule
  fi

  # === 1. Create Backup ===
  step "Creating backup..."
  create_backup

  # === 2. Remove markers from scripts ===
  step "Processing scripts..."
  local script_count=0
  if [[ -d ".claude/scripts" ]]; then
    for script in .claude/scripts/*.sh; do
      if [[ -f "$script" ]] && has_marker "$script"; then
        remove_marker "$script"
        ((script_count++)) || true
      fi
    done
    log "Processed $script_count scripts"
  fi

  # === 3. Remove markers from skills ===
  step "Processing skills..."
  local skill_count=0
  if [[ -d ".claude/skills" ]]; then
    for skill_dir in .claude/skills/*/; do
      if [[ -d "$skill_dir" ]]; then
        # Process index.yaml
        local index_file="${skill_dir}index.yaml"
        if [[ -f "$index_file" ]] && has_marker "$index_file"; then
          remove_marker "$index_file"
        fi

        # Process SKILL.md
        local skill_md="${skill_dir}SKILL.md"
        if [[ -f "$skill_md" ]] && has_marker "$skill_md"; then
          remove_marker "$skill_md"
        fi

        # Remove loa- prefix if present
        remove_skill_prefix "${skill_dir%/}"
        ((skill_count++)) || true
      fi
    done
    log "Processed $skill_count skills"
  fi

  # === 4. Remove markers from commands ===
  step "Processing commands..."
  local cmd_count=0
  if [[ -d ".claude/commands" ]]; then
    for cmd_file in .claude/commands/*.md; do
      if [[ -f "$cmd_file" ]] && has_marker "$cmd_file"; then
        remove_marker "$cmd_file"
        ((cmd_count++)) || true
      fi
      # Remove loa- prefix if present (skip loa.md itself)
      local cmd_name=$(basename "$cmd_file")
      if [[ "$cmd_name" != "loa.md" ]]; then
        remove_command_prefix "$cmd_file"
      fi
    done
    log "Processed $cmd_count commands"
  fi

  # === 5. Remove markers from protocols ===
  step "Processing protocols..."
  local proto_count=0
  if [[ -d ".claude/protocols" ]]; then
    for proto_file in .claude/protocols/*.md; do
      if [[ -f "$proto_file" ]] && has_marker "$proto_file"; then
        remove_marker "$proto_file"
        ((proto_count++)) || true
      fi
    done
    log "Processed $proto_count protocols"
  fi

  # === 6. Remove markers from schemas ===
  step "Processing schemas..."
  local schema_count=0
  if [[ -d ".claude/schemas" ]]; then
    for schema_file in .claude/schemas/*.json; do
      if [[ -f "$schema_file" ]] && has_marker "$schema_file"; then
        remove_marker "$schema_file"
        ((schema_count++)) || true
      fi
    done
    log "Processed $schema_count schemas"
  fi

  # === 7. Process pack content (if --include-packs) ===
  if [[ "$INCLUDE_PACKS" == "true" ]] && [[ -d ".claude/constructs" ]]; then
    step "Processing pack content..."
    local pack_count=0
    find .claude/constructs -type f \( -name "*.sh" -o -name "*.md" -o -name "*.yaml" -o -name "*.json" \) | while read -r file; do
      if has_pack_marker "$file" || has_marker "$file"; then
        remove_marker "$file"
        ((pack_count++)) || true
      fi
    done
    log "Processed $pack_count pack files"
  fi

  # === 8. Merge CLAUDE.md ===
  step "Merging CLAUDE.md..."
  merge_claude_md

  # === 9. Update config ===
  step "Updating configuration..."
  update_config

  log "Eject process complete!"
}

# === Confirmation ===

show_warning() {
  echo ""
  echo -e "${BOLD}${YELLOW}=======================================================================${NC}"
  echo -e "${BOLD}${YELLOW}                    LOA FRAMEWORK EJECT WARNING${NC}"
  echo -e "${BOLD}${YELLOW}=======================================================================${NC}"
  echo ""
  echo -e "This will ${BOLD}permanently${NC} transfer ownership of all Loa framework files"
  echo -e "to your project. After ejection:"
  echo ""
  echo -e "  ${RED}x${NC} Framework updates via /update-loa will ${BOLD}no longer work${NC}"
  echo -e "  ${RED}x${NC} All automatic integrity verification will be ${BOLD}disabled${NC}"
  echo -e "  ${RED}x${NC} You will be responsible for ${BOLD}all future maintenance${NC}"
  echo ""
  echo -e "  ${GREEN}+${NC} You gain ${BOLD}full control${NC} over all framework files"
  echo -e "  ${GREEN}+${NC} Magic markers and hashes will be ${BOLD}removed${NC}"
  echo -e "  ${GREEN}+${NC} All files become ${BOLD}your files${NC}"
  echo ""
  if [[ "$INCLUDE_PACKS" == "true" ]]; then
    echo -e "  ${YELLOW}!${NC} Pack-installed content will ${BOLD}also${NC} be ejected"
    echo ""
  fi
  echo -e "${YELLOW}A backup will be created at: .claude.backup.{timestamp}/${NC}"
  echo ""
  echo -e "${BOLD}${YELLOW}=======================================================================${NC}"
  echo ""
}

confirm_eject() {
  if [[ "$FORCE" == "true" ]]; then
    return 0
  fi

  show_warning

  echo -e "To confirm ejection, type '${BOLD}eject${NC}' and press Enter:"
  echo -n "> "
  read -r confirm

  if [[ "$confirm" != "eject" ]]; then
    log "Eject cancelled."
    exit 0
  fi

  echo ""
}

# === Post-Eject Instructions ===

show_post_eject_instructions() {
  echo ""
  echo -e "${GREEN}=======================================================================${NC}"
  echo -e "${GREEN}                    EJECT COMPLETE${NC}"
  echo -e "${GREEN}=======================================================================${NC}"
  echo ""
  echo "Your project is now fully independent from the Loa framework."
  echo ""
  echo "What changed:"
  echo "  - Backup created at: ${BACKUP_DIR:-'.claude.backup.{timestamp}/'}"
  echo "  - Magic markers removed from all framework files"
  echo "  - Framework instructions merged into CLAUDE.md"
  echo "  - Config updated with ejected: true"
  echo ""
  echo "Next steps:"
  echo "  1. Review CLAUDE.md to ensure instructions are as expected"
  echo "  2. Commit the changes: git add -A && git commit -m 'chore: eject from Loa'"
  echo "  3. Consider deleting the backup once verified: rm -rf ${BACKUP_DIR:-'.claude.backup.*'}"
  echo ""
  echo "If something went wrong:"
  echo "  1. Restore from backup: rm -rf .claude && cp -r ${BACKUP_DIR:-.claude.backup.*} .claude"
  echo "  2. Restore config: cp ${BACKUP_DIR:-'.claude.backup.*'}/.loa.config.yaml.backup .loa.config.yaml"
  echo ""
  echo -e "${GREEN}=======================================================================${NC}"
  echo ""
}

# === Main ===

main() {
  echo ""
  log "======================================================================="
  log "  Loa Framework Eject"
  log "======================================================================="
  [[ "$DRY_RUN" == "true" ]] && log "  Mode: Dry Run (no changes will be made)"
  [[ "$INCLUDE_PACKS" == "true" ]] && log "  Option: Including pack content"
  echo ""

  preflight

  if [[ "$DRY_RUN" != "true" ]]; then
    confirm_eject
  fi

  eject_files

  if [[ "$DRY_RUN" != "true" ]]; then
    show_post_eject_instructions
  else
    echo ""
    log "Dry run complete. No changes were made."
    log "Run without --dry-run to perform actual eject."
    echo ""
  fi
}

main "$@"
