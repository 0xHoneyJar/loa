#!/usr/bin/env bash
# Loa Framework: Update Script with Strict Enforcement
# Follows: Fetch -> Validate -> Migrate -> Swap pattern
set -euo pipefail

# === Configuration ===
STAGING_DIR=".claude_staging"
SYSTEM_DIR=".claude"
OVERRIDES_DIR=".claude/overrides"
VERSION_FILE=".loa-version.json"
CHECKSUMS_FILE=".claude/checksums.json"
CONFIG_FILE=".loa.config.yaml"
UPSTREAM_REPO="${LOA_UPSTREAM:-https://github.com/0xHoneyJar/loa.git}"
UPSTREAM_BRANCH="${LOA_BRANCH:-main}"
LOA_REMOTE_NAME="loa-upstream"

# Version targeting - set during argument parsing
TARGET_REF=""
TARGET_TYPE=""  # branch, tag, commit, latest

# === Global Cleanup (HIGH-004: Comprehensive trap handlers) ===
# Track temp files for cleanup on interrupt
declare -a _TEMP_FILES=()
declare -a _TEMP_DIRS=()

_cleanup_on_exit() {
    local exit_code=$?
    # Clean up temp files
    for f in "${_TEMP_FILES[@]:-}"; do
        [[ -n "$f" ]] && rm -f "$f" 2>/dev/null || true
    done
    # Clean up temp directories
    for d in "${_TEMP_DIRS[@]:-}"; do
        [[ -n "$d" ]] && rm -rf "$d" 2>/dev/null || true
    done
    exit $exit_code
}

# Register cleanup for all exit signals
trap _cleanup_on_exit EXIT INT TERM

# Helper to register a temp file for cleanup
_register_temp_file() {
    _TEMP_FILES+=("$1")
}

# Helper to register a temp dir for cleanup
_register_temp_dir() {
    _TEMP_DIRS+=("$1")
}

# === Colors ===
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "${GREEN}[loa]${NC} $*"; }
warn() { echo -e "${YELLOW}[loa]${NC} $*"; }
err() { echo -e "${RED}[loa]${NC} ERROR: $*" >&2; exit 1; }
info() { echo -e "${CYAN}[loa]${NC} $*"; }

# === UX Helpers (T3.5.5) ===

# Progress indicator with spinner
_SPINNER_PID=""
start_progress() {
  local msg="${1:-Working...}"
  if [[ -t 1 ]]; then  # Only if stdout is a terminal
    (
      local spin='-\|/'
      local i=0
      while true; do
        printf "\r${CYAN}[loa]${NC} %s %c " "$msg" "${spin:i++%4:1}"
        sleep 0.1
      done
    ) &
    _SPINNER_PID=$!
    disown $_SPINNER_PID 2>/dev/null || true
  else
    log "$msg"
  fi
}

stop_progress() {
  local success="${1:-true}"
  local msg="${2:-}"
  if [[ -n "$_SPINNER_PID" ]] && kill -0 "$_SPINNER_PID" 2>/dev/null; then
    kill "$_SPINNER_PID" 2>/dev/null || true
    wait "$_SPINNER_PID" 2>/dev/null || true
    _SPINNER_PID=""
    printf "\r"  # Clear the spinner line
  fi
  if [[ "$success" == "true" && -n "$msg" ]]; then
    log "$msg"
  elif [[ "$success" == "false" && -n "$msg" ]]; then
    warn "$msg"
  fi
}

# One-liner summary of update
show_update_summary() {
  local old_version="$1"
  local new_version="$2"
  local files_changed="${3:-0}"
  local ref_type="$4"
  local ref="$5"

  echo ""
  echo -e "${GREEN}Update complete:${NC} ${old_version} -> ${new_version}"

  if [[ "$ref_type" != "latest" && "$ref_type" != "tag" ]]; then
    echo -e "  ${CYAN}Ref:${NC} ${ref} (${ref_type})"
  fi

  if [[ "$files_changed" -gt 0 ]]; then
    echo -e "  ${CYAN}Changed:${NC} ${files_changed} files"
  fi
  echo ""
}

# Check for affected overrides
check_override_conflicts() {
  local staging_dir="$1"

  if [[ ! -d "$OVERRIDES_DIR" ]]; then
    return 0
  fi

  local conflicts=()
  while IFS= read -r -d '' override_file; do
    local rel_path="${override_file#$OVERRIDES_DIR/}"
    local staging_file="${staging_dir}/${rel_path}"
    if [[ -f "$staging_file" ]]; then
      # Check if files differ
      if ! diff -q "$override_file" "$staging_file" >/dev/null 2>&1; then
        conflicts+=("$rel_path")
      fi
    fi
  done < <(find "$OVERRIDES_DIR" -type f -print0 2>/dev/null)

  if [[ ${#conflicts[@]} -gt 0 ]]; then
    warn "Your overrides may need attention after update:"
    for f in "${conflicts[@]}"; do
      echo "  - .claude/overrides/$f"
    done
    echo ""
    return 1
  fi
  return 0
}

# Offline error handling with cached version info
handle_offline_error() {
  echo ""
  warn "Could not connect to upstream repository"
  echo ""

  # Show cached version info if available
  local cache_file="${HOME}/.loa/cache/update-check.json"
  if [[ -f "$cache_file" ]]; then
    local last_check remote_version
    last_check=$(jq -r '.last_check // ""' "$cache_file" 2>/dev/null)
    remote_version=$(jq -r '.remote_version // ""' "$cache_file" 2>/dev/null)

    if [[ -n "$remote_version" ]]; then
      echo "Last known version (cached): $remote_version"
      echo "Last check: ${last_check:-unknown}"
    fi
  fi

  echo ""
  echo "Troubleshooting:"
  echo "  1. Check your internet connection"
  echo "  2. Verify remote is accessible: git ls-remote $UPSTREAM_REPO"
  echo "  3. Try again with: /update-loa --force"
  echo ""
  exit 1
}

# Auto-cleanup of stale staging directories
cleanup_stale_staging() {
  # Remove any leftover staging directories older than 1 hour
  local stale_count=0
  while IFS= read -r -d '' dir; do
    if [[ -d "$dir" ]]; then
      rm -rf "$dir" 2>/dev/null && ((stale_count++)) || true
    fi
  done < <(find . -maxdepth 1 -type d -name ".claude_staging*" -mmin +60 -print0 2>/dev/null)

  if [[ $stale_count -gt 0 ]]; then
    log "Cleaned up $stale_count stale staging directories"
  fi
}

# Show dry-run preview
show_dry_run_preview() {
  local staging_dir="$1"

  echo ""
  echo "═══════════════════════════════════════════════════════════════"
  echo "  DRY RUN - Changes that would be applied"
  echo "═══════════════════════════════════════════════════════════════"
  echo ""

  # Count new/modified/deleted files
  local new_files=0
  local modified_files=0
  local deleted_files=0

  # Check files in staging
  while IFS= read -r -d '' file; do
    local rel_path="${file#$staging_dir/}"
    local existing="${SYSTEM_DIR}/${rel_path}"

    if [[ ! -f "$existing" ]]; then
      ((new_files++))
      echo -e "  ${GREEN}+ $rel_path${NC}"
    elif ! diff -q "$file" "$existing" >/dev/null 2>&1; then
      ((modified_files++))
      echo -e "  ${YELLOW}~ $rel_path${NC}"
    fi
  done < <(find "$staging_dir" -type f -print0 2>/dev/null | head -100)

  # Check for files that would be deleted
  if [[ -d "$SYSTEM_DIR" ]]; then
    while IFS= read -r -d '' file; do
      local rel_path="${file#$SYSTEM_DIR/}"
      local staging_file="${staging_dir}/${rel_path}"

      # Skip overrides and constructs (user-authored, not framework-managed)
      [[ "$rel_path" == overrides/* ]] && continue
      [[ "$rel_path" == constructs/* ]] && continue

      if [[ ! -f "$staging_file" ]]; then
        ((deleted_files++))
        echo -e "  ${RED}- $rel_path${NC}"
      fi
    done < <(find "$SYSTEM_DIR" -type f ! -path "*/overrides/*" ! -path "*/constructs/*" -print0 2>/dev/null | head -100)
  fi

  echo ""
  echo "  Summary: ${new_files} new, ${modified_files} modified, ${deleted_files} deleted"
  echo ""
  echo "═══════════════════════════════════════════════════════════════"
  echo "  No changes applied. Run without --dry-run to apply."
  echo "═══════════════════════════════════════════════════════════════"
  echo ""
}

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

# Validate config file exists and contains valid YAML (L-003)
validate_config() {
  local config="$1"

  if [[ ! -f "$config" ]]; then
    warn "Config file not found: $config (using defaults)"
    return 1
  fi

  # Check for valid YAML using yq
  if yq --version 2>&1 | grep -q "mikefarah"; then
    if ! yq eval '.' "$config" > /dev/null 2>&1; then
      err "Invalid YAML in config: $config"
    fi
  else
    if ! yq . "$config" > /dev/null 2>&1; then
      err "Invalid YAML in config: $config"
    fi
  fi

  return 0
}

check_deps() {
  command -v jq >/dev/null || err "jq is required"
  command -v yq >/dev/null || err "yq is required"
  command -v git >/dev/null || err "git is required"
  command -v sha256sum >/dev/null || err "sha256sum is required"
}

get_version() {
  jq -r ".$1 // empty" "$VERSION_FILE" 2>/dev/null || echo ""
}

set_version() {
  local tmp
  tmp=$(mktemp) || { err "mktemp failed"; return 1; }
  chmod 600 "$tmp"  # CRITICAL-001 FIX: Restrict permissions
  _register_temp_file "$tmp"
  jq --arg k "$1" --arg v "$2" '.[$k] = $v' "$VERSION_FILE" > "$tmp" && mv "$tmp" "$VERSION_FILE"
}

set_version_int() {
  local tmp
  tmp=$(mktemp) || { err "mktemp failed"; return 1; }
  chmod 600 "$tmp"  # CRITICAL-001 FIX: Restrict permissions
  _register_temp_file "$tmp"
  jq --arg k "$1" --argjson v "$2" '.[$k] = $v' "$VERSION_FILE" > "$tmp" && mv "$tmp" "$VERSION_FILE"
}

# === Version History Management (T3.5.3) ===
# Update version history, maintaining last 10 entries
# Arguments:
#   $1 - old_version: previous framework_version
#   $2 - new_version: new framework_version
#   $3 - ref: the ref that was used (tag name, branch name, or commit)
#   $4 - type: ref type (tag, branch, commit, latest)
#   $5 - commit: the commit SHA (optional, fetched if not provided)
update_version_history() {
  local old_version="$1"
  local new_version="$2"
  local ref="$3"
  local ref_type="$4"
  local commit="${5:-}"

  local timestamp
  timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  # Get commit SHA if not provided
  if [[ -z "$commit" ]]; then
    commit=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
  fi

  local tmp
  tmp=$(mktemp) || { err "mktemp failed"; return 1; }
  chmod 600 "$tmp"
  _register_temp_file "$tmp"

  # Build the update with jq:
  # 1. Save current state to history (prepend)
  # 2. Update current state
  # 3. Trim history to 10 entries
  jq --arg ver "$new_version" \
     --arg ref "$ref" \
     --arg type "$ref_type" \
     --arg commit "$commit" \
     --arg ts "$timestamp" \
     --arg old_ver "$old_version" '
    # Create history entry from current state (if exists and different)
    . as $root |
    (
      if (.current.version // .framework_version) != null and
         (.current.version // .framework_version) != $ver then
        {
          version: (.current.version // .framework_version),
          ref: (.current.ref // ("v" + (.current.version // .framework_version))),
          type: (.current.type // "tag"),
          commit: (.current.commit // "unknown"),
          updated_at: (.current.updated_at // $ts)
        }
      else
        null
      end
    ) as $hist_entry |

    # Update current
    .current = {
      version: $ver,
      ref: $ref,
      type: $type,
      commit: $commit,
      updated_at: $ts
    } |

    # Prepend to history if entry exists, then trim to 10
    (if $hist_entry != null then
      [$hist_entry] + (.history // [])
    else
      .history // []
    end) | .[0:10] as $new_history |

    .history = $new_history |

    # Also update framework_version for backward compatibility
    .framework_version = $ver |
    .last_sync = $ts
  ' "$VERSION_FILE" > "$tmp" && mv "$tmp" "$VERSION_FILE"

  log "Updated version history (${ref_type}: ${ref})"
}

# Get current version info from .loa-version.json
get_current_version_info() {
  local field="${1:-version}"
  jq -r ".current.${field} // empty" "$VERSION_FILE" 2>/dev/null || echo ""
}

# === Cryptographic Integrity Check (Projen-Level) ===
generate_checksums() {
  log "Generating cryptographic checksums..."

  local checksums="{"
  checksums+='"generated": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",'
  checksums+='"algorithm": "sha256",'
  checksums+='"files": {'

  local first=true
  while IFS= read -r -d '' file; do
    local hash=$(sha256sum "$file" | cut -d' ' -f1)
    local relpath="${file#./}"
    [[ "$first" == "true" ]] && first=false || checksums+=','
    checksums+='"'"$relpath"'": "'"$hash"'"'
  done < <(find .claude -type f ! -name "checksums.json" ! -path "*/overrides/*" -print0 | sort -z)

  checksums+='}}'
  echo "$checksums" | jq '.' > "$CHECKSUMS_FILE"
}

check_integrity() {
  local enforcement="${1:-strict}"
  local force_restore="${2:-false}"

  if [[ ! -f "$CHECKSUMS_FILE" ]]; then
    warn "No checksums found - skipping integrity check (first run?)"
    return 0
  fi

  log "Verifying System Zone integrity (sha256)..."

  local drift_detected=false
  local drifted_files=()

  while IFS= read -r file; do
    local expected=$(jq -r --arg f "$file" '.files[$f] // empty' "$CHECKSUMS_FILE")
    [[ -z "$expected" ]] && continue

    if [[ -f "$file" ]]; then
      local actual=$(sha256sum "$file" | cut -d' ' -f1)
      if [[ "$expected" != "$actual" ]]; then
        drift_detected=true
        drifted_files+=("$file")
      fi
    else
      drift_detected=true
      drifted_files+=("$file (MISSING)")
    fi
  done < <(jq -r '.files | keys[]' "$CHECKSUMS_FILE")

  if [[ "$drift_detected" == "true" ]]; then
    echo ""
    warn "======================================================================="
    warn "  SYSTEM ZONE INTEGRITY VIOLATION"
    warn "======================================================================="
    warn ""
    warn "The following files have been modified:"
    for f in "${drifted_files[@]}"; do
      warn "  x $f"
    done
    warn ""

    if [[ "$force_restore" == "true" ]]; then
      log "Force-restoring from upstream..."
      git checkout "$LOA_REMOTE_NAME/$UPSTREAM_BRANCH" -- .claude 2>/dev/null || {
        err "Failed to restore from upstream"
      }
      generate_checksums
      log "System Zone restored"
      return 0
    fi

    case "$enforcement" in
      strict)
        err "STRICT ENFORCEMENT: Execution blocked. Use --force-restore to reset."
        ;;
      warn)
        warn "WARNING: Continuing with modified System Zone (not recommended)"
        read -p "Continue anyway? (y/N) " -n 1 -r
        echo ""
        [[ $REPLY =~ ^[Yy]$ ]] || exit 1
        ;;
      disabled)
        warn "Integrity checks disabled - proceeding"
        ;;
    esac
  else
    log "System Zone integrity verified"
  fi
}

# === Pre-flight Checks ===
preflight_check() {
  log "Running pre-flight checks..."
  local errors=0

  while IFS= read -r -d '' f; do
    # Try to validate YAML with whichever yq is installed
    if yq --version 2>&1 | grep -q "mikefarah"; then
      yq eval '.' "$f" > /dev/null 2>&1 || { warn "Invalid YAML: $f"; ((errors++)); }
    else
      yq . "$f" > /dev/null 2>&1 || { warn "Invalid YAML: $f"; ((errors++)); }
    fi
  done < <(find "$STAGING_DIR" -name "*.yaml" -print0 2>/dev/null)

  while IFS= read -r -d '' f; do
    if ! bash -n "$f" 2>/dev/null; then
      warn "Invalid shell script: $f"
      ((errors++))
    fi
  done < <(find "$STAGING_DIR" -name "*.sh" -print0 2>/dev/null)

  [[ -d "$STAGING_DIR/skills" ]] || { warn "Missing skills directory"; ((errors++)); }
  [[ -d "$STAGING_DIR/commands" ]] || { warn "Missing commands directory"; ((errors++)); }

  [[ $errors -gt 0 ]] && err "Pre-flight failed with $errors errors"
  log "Pre-flight checks passed"
}

# === Migration Gate (Copier-Level) ===
run_migrations() {
  local current_schema=$(get_version "schema_version")
  current_schema=${current_schema:-1}

  local incoming_manifest="$STAGING_DIR/.loa-version.json"
  if [[ ! -f "$incoming_manifest" ]]; then
    warn "No version manifest in upstream, skipping migrations"
    return 0
  fi

  local incoming_schema=$(jq -r '.schema_version // 1' "$incoming_manifest")

  if [[ "$incoming_schema" -gt "$current_schema" ]]; then
    log "======================================================================="
    log "  MIGRATION GATE: Schema $current_schema -> $incoming_schema"
    log "======================================================================="

    local migrations_dir="$STAGING_DIR/migrations"
    if [[ -d "$migrations_dir" ]]; then
      for migration in "$migrations_dir"/*.sh; do
        [[ -f "$migration" ]] || continue
        local mid=$(basename "$migration" .sh)

        if jq -e --arg m "$mid" '.migrations_applied | index($m)' "$VERSION_FILE" >/dev/null 2>&1; then
          log "Skipping applied migration: $mid"
          continue
        fi

        log "Running migration: $mid (BLOCKING)"
        if bash "$migration"; then
          local tmp
          tmp=$(mktemp) || { err "mktemp failed"; continue; }
          chmod 600 "$tmp"  # CRITICAL-001 FIX: Restrict permissions
          trap "rm -f '$tmp'" RETURN
          jq --arg m "$mid" '.migrations_applied += [$m]' "$VERSION_FILE" > "$tmp" && mv "$tmp" "$VERSION_FILE"
          log "Migration $mid completed"
        else
          err "Migration $mid FAILED - update blocked. Fix manually or contact support."
        fi
      done
    fi

    set_version_int "schema_version" "$incoming_schema"
    log "All migrations completed"
  else
    log "No migrations required"
  fi
}

apply_stealth_mode() {
  if ! validate_config "$CONFIG_FILE" 2>/dev/null; then return 0; fi

  local mode=$(yq_read "$CONFIG_FILE" '.persistence_mode' "standard")

  if [[ "$mode" == "stealth" ]]; then
    log "Stealth mode: adding state files to .gitignore"
    local gitignore=".gitignore"
    touch "$gitignore"

    grep -qxF 'grimoires/loa/' "$gitignore" 2>/dev/null || echo 'grimoires/loa/' >> "$gitignore"
    grep -qxF '.beads/' "$gitignore" 2>/dev/null || echo '.beads/' >> "$gitignore"
    grep -qxF '.loa-version.json' "$gitignore" 2>/dev/null || echo '.loa-version.json' >> "$gitignore"
    grep -qxF '.loa.config.yaml' "$gitignore" 2>/dev/null || echo '.loa.config.yaml' >> "$gitignore"
  fi
}

# === Version Targeting (T3.5.1) ===
# Auto-detects ref type: branch, tag, or commit
# Usage: parse_version_arg "ref"
# Sets: TARGET_REF, TARGET_TYPE
parse_version_arg() {
  local ref="$1"

  # Handle @latest explicitly
  if [[ "$ref" == "@latest" || "$ref" == "latest" ]]; then
    TARGET_REF="$UPSTREAM_BRANCH"
    TARGET_TYPE="latest"
    return 0
  fi

  # Empty ref = latest stable
  if [[ -z "$ref" ]]; then
    TARGET_REF="$UPSTREAM_BRANCH"
    TARGET_TYPE="latest"
    return 0
  fi

  # Ensure remote is fetched for detection
  git fetch "$LOA_REMOTE_NAME" --tags --quiet 2>/dev/null || {
    # Try adding remote if missing
    if ! git remote | grep -q "^${LOA_REMOTE_NAME}$"; then
      git remote add "$LOA_REMOTE_NAME" "$UPSTREAM_REPO" 2>/dev/null || true
      git fetch "$LOA_REMOTE_NAME" --tags --quiet 2>/dev/null || true
    fi
  }

  # Check if it's a tag (with or without 'v' prefix)
  if git tag -l | grep -qxE "^v?${ref}$" || \
     git ls-remote --tags "$LOA_REMOTE_NAME" 2>/dev/null | grep -qE "refs/tags/v?${ref}$"; then
    # Normalize tag name
    if git tag -l | grep -qx "v${ref}"; then
      TARGET_REF="v${ref}"
    elif git tag -l | grep -qx "${ref}"; then
      TARGET_REF="$ref"
    elif git ls-remote --tags "$LOA_REMOTE_NAME" 2>/dev/null | grep -qE "refs/tags/v${ref}$"; then
      TARGET_REF="v${ref}"
    else
      TARGET_REF="$ref"
    fi
    TARGET_TYPE="tag"
    return 0
  fi

  # Check if it's a remote branch
  if git ls-remote --heads "$LOA_REMOTE_NAME" "$ref" 2>/dev/null | grep -q "refs/heads/${ref}$"; then
    TARGET_REF="$ref"
    TARGET_TYPE="branch"
    return 0
  fi

  # Check if it looks like a commit SHA (7-40 hex chars)
  if [[ "$ref" =~ ^[0-9a-fA-F]{7,40}$ ]]; then
    # Verify commit exists
    if git cat-file -e "$ref" 2>/dev/null || \
       git fetch "$LOA_REMOTE_NAME" "$ref" --depth=1 2>/dev/null; then
      TARGET_REF="$ref"
      TARGET_TYPE="commit"
      return 0
    fi
  fi

  # Could not determine type - return error
  err "Could not resolve ref '$ref'. Not a valid branch, tag, or commit."
  return 1
}

# Get the appropriate git ref for fetching
get_fetch_ref() {
  case "$TARGET_TYPE" in
    tag)
      echo "refs/tags/${TARGET_REF}:refs/tags/${TARGET_REF}"
      ;;
    commit)
      echo "$TARGET_REF"
      ;;
    branch|latest)
      echo "${TARGET_REF}:refs/remotes/${LOA_REMOTE_NAME}/${TARGET_REF}"
      ;;
  esac
}

# Get the ref to checkout from staging
get_checkout_ref() {
  case "$TARGET_TYPE" in
    tag)
      echo "refs/tags/${TARGET_REF}"
      ;;
    commit)
      echo "$TARGET_REF"
      ;;
    branch|latest)
      echo "${LOA_REMOTE_NAME}/${TARGET_REF}"
      ;;
  esac
}

# === Version Listing (T3.5.2) ===
# Lists available tags and branches from upstream
do_list_versions() {
  local show_all="${1:-false}"
  local json_output="${2:-false}"

  log "Fetching available versions from upstream..."

  # Ensure remote exists
  if ! git remote | grep -q "^${LOA_REMOTE_NAME}$"; then
    git remote add "$LOA_REMOTE_NAME" "$UPSTREAM_REPO" 2>/dev/null || true
  fi
  git fetch "$LOA_REMOTE_NAME" --tags --quiet 2>/dev/null || {
    err "Failed to fetch from upstream"
  }

  local current_version
  current_version=$(get_version "framework_version")

  if [[ "$json_output" == "true" ]]; then
    # JSON output for scripting
    local tags branches
    tags=$(git ls-remote --tags "$LOA_REMOTE_NAME" 2>/dev/null | \
           grep -E 'refs/tags/v[0-9]' | \
           sed 's/.*refs\/tags\///' | \
           grep -v '\^{}' | \
           sort -V -r | \
           head -20)

    if [[ "$show_all" == "true" ]]; then
      branches=$(git ls-remote --heads "$LOA_REMOTE_NAME" 2>/dev/null | \
                 sed 's/.*refs\/heads\///' | \
                 sort)
    else
      branches=$(git ls-remote --heads "$LOA_REMOTE_NAME" 2>/dev/null | \
                 sed 's/.*refs\/heads\///' | \
                 grep -E '^(main|master|release/|stable)' | \
                 sort)
    fi

    echo "{"
    echo "  \"current\": \"$current_version\","
    echo "  \"tags\": ["
    local first=true
    while IFS= read -r tag; do
      [[ -z "$tag" ]] && continue
      [[ "$first" == "true" ]] && first=false || echo ","
      printf '    "%s"' "$tag"
    done <<< "$tags"
    echo ""
    echo "  ],"
    echo "  \"branches\": ["
    first=true
    while IFS= read -r branch; do
      [[ -z "$branch" ]] && continue
      [[ "$first" == "true" ]] && first=false || echo ","
      printf '    "%s"' "$branch"
    done <<< "$branches"
    echo ""
    echo "  ]"
    echo "}"
  else
    # Human-readable output
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "  Available Loa Versions"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    echo "  Current: ${current_version:-unknown}"
    echo ""
    echo "  Tags (stable releases):"
    echo "  ────────────────────────"
    git ls-remote --tags "$LOA_REMOTE_NAME" 2>/dev/null | \
      grep -E 'refs/tags/v[0-9]' | \
      sed 's/.*refs\/tags\///' | \
      grep -v '\^{}' | \
      sort -V -r | \
      head -10 | \
      while IFS= read -r tag; do
        if [[ "$tag" == "v${current_version}" ]]; then
          echo -e "    ${GREEN}→ $tag (current)${NC}"
        else
          echo "    $tag"
        fi
      done

    echo ""
    echo "  Branches:"
    echo "  ─────────"
    local branch_filter="^(main|master|release/|stable)"
    [[ "$show_all" == "true" ]] && branch_filter="."

    git ls-remote --heads "$LOA_REMOTE_NAME" 2>/dev/null | \
      sed 's/.*refs\/heads\///' | \
      grep -E "$branch_filter" | \
      sort | \
      head -20 | \
      while IFS= read -r branch; do
        echo "    $branch"
      done

    if [[ "$show_all" != "true" ]]; then
      echo ""
      echo "  Use --list --all to see all branches"
    fi
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "  Usage: update.sh <tag|branch>  or  update.sh -i"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
  fi
}

# === Interactive Version Selection (T3.5.2) ===
do_interactive_select() {
  log "Starting interactive version selection..."

  # Ensure remote exists and fetch
  if ! git remote | grep -q "^${LOA_REMOTE_NAME}$"; then
    git remote add "$LOA_REMOTE_NAME" "$UPSTREAM_REPO" 2>/dev/null || true
  fi
  git fetch "$LOA_REMOTE_NAME" --tags --quiet 2>/dev/null || {
    err "Failed to fetch from upstream"
  }

  local current_version
  current_version=$(get_version "framework_version")

  # Build version list: tags + main branches
  local versions=()
  local labels=()

  # Add @latest option
  versions+=("@latest")
  labels+=("@latest - Latest stable (recommended)")

  # Add recent tags
  while IFS= read -r tag; do
    [[ -z "$tag" ]] && continue
    versions+=("$tag")
    if [[ "$tag" == "v${current_version}" ]]; then
      labels+=("$tag (current)")
    else
      labels+=("$tag")
    fi
  done < <(git ls-remote --tags "$LOA_REMOTE_NAME" 2>/dev/null | \
           grep -E 'refs/tags/v[0-9]' | \
           sed 's/.*refs\/tags\///' | \
           grep -v '\^{}' | \
           sort -V -r | \
           head -10)

  # Add main branches
  while IFS= read -r branch; do
    [[ -z "$branch" ]] && continue
    versions+=("$branch")
    labels+=("branch: $branch")
  done < <(git ls-remote --heads "$LOA_REMOTE_NAME" 2>/dev/null | \
           sed 's/.*refs\/heads\///' | \
           grep -E '^(main|master|develop)$' | \
           sort)

  # Check for fzf
  if command -v fzf &>/dev/null; then
    # Use fzf for selection
    local selection
    selection=$(printf '%s\n' "${labels[@]}" | fzf --height=20 --reverse --prompt="Select version: ")
    if [[ -z "$selection" ]]; then
      err "No version selected"
    fi
    # Find the index and get the actual version
    for i in "${!labels[@]}"; do
      if [[ "${labels[$i]}" == "$selection" ]]; then
        version_arg="${versions[$i]}"
        break
      fi
    done
  else
    # Fall back to bash select
    echo ""
    echo "Select a version to install:"
    echo ""
    PS3="Enter number (or 'q' to quit): "
    select label in "${labels[@]}"; do
      if [[ "$REPLY" == "q" ]]; then
        err "Selection cancelled"
      fi
      if [[ -n "$label" ]]; then
        version_arg="${versions[$((REPLY-1))]}"
        break
      fi
    done
  fi

  [[ -z "$version_arg" ]] && err "No version selected"
  log "Selected: $version_arg"

  # Parse the selected version
  parse_version_arg "$version_arg"
}

# === Rollback (T3.5.3) ===
do_rollback() {
  local json_output="${1:-false}"

  # Check for history in version file
  local history_length
  history_length=$(jq -r '.history | length // 0' "$VERSION_FILE" 2>/dev/null || echo "0")

  if [[ "$history_length" -eq 0 || "$history_length" == "null" ]]; then
    if [[ "$json_output" == "true" ]]; then
      echo '{"error": "no_history", "message": "No version history available for rollback"}'
    else
      err "No version history available for rollback. Need at least one previous update."
    fi
    exit 1
  fi

  # Get previous version from history
  local prev_version prev_ref prev_type prev_commit
  prev_version=$(jq -r '.history[0].version // empty' "$VERSION_FILE" 2>/dev/null)
  prev_ref=$(jq -r '.history[0].ref // empty' "$VERSION_FILE" 2>/dev/null)
  prev_type=$(jq -r '.history[0].type // "tag"' "$VERSION_FILE" 2>/dev/null)
  prev_commit=$(jq -r '.history[0].commit // empty' "$VERSION_FILE" 2>/dev/null)

  if [[ -z "$prev_version" && -z "$prev_ref" ]]; then
    if [[ "$json_output" == "true" ]]; then
      echo '{"error": "invalid_history", "message": "Version history is corrupted"}'
    else
      err "Version history is corrupted. Cannot rollback."
    fi
    exit 1
  fi

  local current_version
  current_version=$(get_version "framework_version")

  if [[ "$json_output" == "true" ]]; then
    echo "{"
    echo "  \"action\": \"rollback\","
    echo "  \"from\": \"$current_version\","
    echo "  \"to\": \"$prev_version\","
    echo "  \"ref\": \"$prev_ref\","
    echo "  \"type\": \"$prev_type\""
    echo "}"
  else
    log "Rolling back: $current_version -> $prev_version"
    log "Using ref: $prev_ref ($prev_type)"
  fi

  # Set target for rollback
  TARGET_REF="${prev_ref:-v$prev_version}"
  TARGET_TYPE="${prev_type:-tag}"

  # Continue with normal update flow (caller should not exit)
  return 0
}

# === Version Check ===
do_version_check() {
  local json_output="${1:-false}"
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local check_script="$script_dir/check-updates.sh"

  if [[ ! -x "$check_script" ]]; then
    err "check-updates.sh not found or not executable"
  fi

  if [[ "$json_output" == "true" ]]; then
    "$check_script" --json --check --notify
  else
    "$check_script" --check --notify
  fi
}

# === Create Version Tag ===
create_version_tag() {
  local version="$1"

  # Check if auto-tag is enabled in config
  local auto_tag="true"
  if validate_config "$CONFIG_FILE" 2>/dev/null; then
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
# Creates a single atomic commit for framework upgrade
# Arguments:
#   $1 - old_version: previous version
#   $2 - new_version: new version being installed
#   $3 - no_commit: whether to skip commit (from CLI flag)
#   $4 - force: whether force mode is enabled
create_upgrade_commit() {
  local old_version="$1"
  local new_version="$2"
  local skip_commit="${3:-false}"
  local force_mode="${4:-false}"

  # Check if --no-commit flag was passed
  if [[ "$skip_commit" == "true" ]]; then
    log "Skipping commit (--no-commit)"
    return 0
  fi

  # Check stealth mode - no commits in stealth
  if validate_config "$CONFIG_FILE" 2>/dev/null; then
    local mode=$(yq_read "$CONFIG_FILE" '.persistence_mode' "standard")
    if [[ "$mode" == "stealth" ]]; then
      log "Skipping commit (stealth mode)"
      return 0
    fi
  fi

  # Check config option for auto_commit
  local auto_commit="true"
  if validate_config "$CONFIG_FILE" 2>/dev/null; then
    auto_commit=$(yq_read "$CONFIG_FILE" '.upgrade.auto_commit' "true")
  fi

  if [[ "$auto_commit" != "true" ]]; then
    log "Skipping commit (auto_commit: false in config)"
    return 0
  fi

  # Check for dirty working tree (excluding our changes)
  if ! git diff --quiet 2>/dev/null; then
    if [[ "$force_mode" != "true" ]]; then
      warn "Working tree has unstaged changes - they will NOT be included in commit"
    fi
  fi

  log "Creating upgrade commit..."

  # Stage framework files
  git add .claude .loa-version.json 2>/dev/null || true

  # Check if there are staged changes
  if git diff --cached --quiet 2>/dev/null; then
    log "No changes to commit"
    return 0
  fi

  # Build commit message
  local commit_prefix="chore"
  if validate_config "$CONFIG_FILE" 2>/dev/null; then
    commit_prefix=$(yq_read "$CONFIG_FILE" '.upgrade.commit_prefix' "chore")
  fi

  local commit_msg="${commit_prefix}(loa): upgrade framework v${old_version} -> v${new_version}

- Updated .claude/ System Zone
- Preserved .claude/overrides/
- See: https://github.com/0xHoneyJar/loa/releases/tag/v${new_version}

Generated by Loa update.sh"

  # Create commit (--no-verify to skip pre-commit hooks that might interfere)
  git commit -m "$commit_msg" --no-verify 2>/dev/null || {
    warn "Failed to create commit (git commit failed)"
    return 1
  }

  log "Created upgrade commit"

  # Create version tag
  create_version_tag "$new_version"
}

# === Help Text ===
show_help() {
  cat << 'EOF'
Loa Framework Update Script

Usage:
  update.sh [OPTIONS] [VERSION]

VERSION TARGETING:
  <branch>         Update to specified branch (e.g., main, feature/foo)
  <tag>            Update to specified tag (e.g., v1.15.0, 1.15.0)
  --commit <sha>   Update to specific commit
  @latest          Explicitly request latest stable (default)

  Auto-detects ref type: checks tags first, then branches, then commits.

OPTIONS:
  --dry-run        Preview changes without applying
  --force          Skip integrity checks
  --force-restore  Restore System Zone from upstream
  --check          Only check for updates, don't apply
  --json           Output JSON format
  --no-commit      Skip automatic git commit
  --list           Show available versions (tags and branches)
  --list --all     Show all remote branches
  -i, --interactive  Interactive version picker
  --rollback       Revert to previous version from history
  --help, -h       Show this help message

EXAMPLES:
  update.sh                    Update to latest stable
  update.sh v1.15.0            Update to tag v1.15.0
  update.sh 1.15.0             Update to tag (auto-adds v prefix if needed)
  update.sh main               Update to main branch
  update.sh feature/wip-foo    Update to feature branch
  update.sh --commit abc123f   Update to specific commit
  update.sh @latest            Explicitly update to latest stable
  update.sh --list             Show available versions
  update.sh -i                 Interactive version selection
  update.sh --rollback         Revert to previous version

ENVIRONMENT:
  LOA_UPSTREAM     Override upstream repository URL
  LOA_BRANCH       Override default branch (default: main)

EOF
}

# === Main ===
main() {
  local dry_run=false
  local force=false
  local force_restore=false
  local check_only=false
  local json_output=false
  local no_commit=false
  local list_mode=false
  local list_all=false
  local interactive_mode=false
  local rollback_mode=false
  local version_arg=""

  while [[ $# -gt 0 ]]; do
    case $1 in
      --dry-run) dry_run=true; shift ;;
      --force) force=true; shift ;;
      --force-restore) force_restore=true; shift ;;
      --check) check_only=true; shift ;;
      --json) json_output=true; shift ;;
      --no-commit) no_commit=true; shift ;;
      --list) list_mode=true; shift ;;
      --all) list_all=true; shift ;;
      -i|--interactive) interactive_mode=true; shift ;;
      --rollback) rollback_mode=true; shift ;;
      --commit)
        shift
        [[ $# -gt 0 ]] || err "--commit requires a SHA argument"
        version_arg="$1"
        TARGET_TYPE="commit"  # Force commit type
        shift
        ;;
      --help|-h) show_help; exit 0 ;;
      -*)
        warn "Unknown option: $1"
        shift
        ;;
      *)
        # Positional argument is version
        if [[ -z "$version_arg" ]]; then
          version_arg="$1"
        fi
        shift
        ;;
    esac
  done

  # Handle --check mode: just check for updates, don't perform update
  if [[ "$check_only" == "true" ]]; then
    do_version_check "$json_output"
    exit $?
  fi

  # Handle --list mode (T3.5.2 - stub for now, will be implemented)
  if [[ "$list_mode" == "true" ]]; then
    do_list_versions "$list_all" "$json_output"
    exit $?
  fi

  # Handle --interactive mode (T3.5.2 - stub for now)
  if [[ "$interactive_mode" == "true" ]]; then
    do_interactive_select
    # After selection, version_arg will be set
    # Fall through to normal update flow
  fi

  # Handle --rollback mode (T3.5.3 - stub for now)
  if [[ "$rollback_mode" == "true" ]]; then
    do_rollback "$json_output"
    exit $?
  fi

  log "======================================================================="
  log "  Loa Framework Update v1.8.0"
  log "  Fetch -> Validate -> Migrate -> Swap"
  log "======================================================================="

  check_deps

  if [[ ! -f "$VERSION_FILE" ]]; then
    cat > "$VERSION_FILE" << 'EOF'
{
  "framework_version": "0.0.0",
  "schema_version": 1,
  "last_sync": null,
  "zones": {"system": ".claude", "state": ["grimoires/loa", ".beads"], "app": ["src", "lib", "app"]},
  "migrations_applied": [],
  "integrity": {"enforcement": "strict", "last_verified": null}
}
EOF
  fi

  local current=$(get_version "framework_version")
  log "Current version: ${current:-unknown}"

  # === VERSION TARGETING (T3.5.1) ===
  # Parse version argument and determine ref type
  if [[ "$TARGET_TYPE" == "commit" ]]; then
    # --commit was used, already have type, just set ref
    TARGET_REF="$version_arg"
  else
    parse_version_arg "$version_arg"
  fi

  # Display target information
  case "$TARGET_TYPE" in
    tag)
      log "Target: tag $TARGET_REF"
      ;;
    branch)
      log "Target: branch $TARGET_REF"
      if [[ "$TARGET_REF" != "main" && "$TARGET_REF" != "master" ]]; then
        warn "Note: You're updating to a non-stable branch"
      fi
      ;;
    commit)
      log "Target: commit ${TARGET_REF:0:8}"
      warn "Note: Updating to a specific commit (not a tracked ref)"
      ;;
    latest)
      log "Target: latest stable ($TARGET_REF)"
      ;;
  esac

  # Get enforcement level from config
  local enforcement="strict"
  if validate_config "$CONFIG_FILE" 2>/dev/null; then
    enforcement=$(yq_read "$CONFIG_FILE" '.integrity_enforcement' "strict")
  fi

  # === STAGE 1: Integrity Check (BLOCKING in strict mode) ===
  if [[ "$force" != "true" ]]; then
    check_integrity "$enforcement" "$force_restore"
  else
    warn "Skipping integrity check (--force)"
  fi

  # === STAGE 1.5: Cleanup stale staging (T3.5.5) ===
  cleanup_stale_staging

  # === STAGE 2: Fetch to staging ===
  start_progress "Fetching ${TARGET_TYPE}: ${TARGET_REF}..."
  rm -rf "$STAGING_DIR"
  mkdir -p "$STAGING_DIR"

  # Fetch based on target type
  local clone_args=("--depth" "1")
  case "$TARGET_TYPE" in
    tag)
      # Clone specific tag
      clone_args+=("--branch" "$TARGET_REF")
      ;;
    branch|latest)
      # Clone specific branch
      clone_args+=("--single-branch" "--branch" "$TARGET_REF")
      ;;
    commit)
      # For commits, we need to fetch without depth limit to get the specific commit
      clone_args=()
      ;;
  esac

  if [[ "$TARGET_TYPE" == "commit" ]]; then
    # Clone repo, then checkout specific commit
    if ! git clone "$UPSTREAM_REPO" "${STAGING_DIR}_repo" 2>/dev/null; then
      stop_progress false
      handle_offline_error
    fi
    if ! (cd "${STAGING_DIR}_repo" && git checkout "$TARGET_REF" 2>/dev/null); then
      stop_progress false
      rm -rf "${STAGING_DIR}_repo"
      err "Failed to checkout commit $TARGET_REF"
    fi
  else
    if ! git clone "${clone_args[@]}" "$UPSTREAM_REPO" "${STAGING_DIR}_repo" 2>/dev/null; then
      stop_progress false
      handle_offline_error
    fi
  fi
  stop_progress true "Fetched ${TARGET_TYPE}: ${TARGET_REF}"

  cp -r "${STAGING_DIR}_repo/.claude/"* "$STAGING_DIR/" 2>/dev/null || true
  cp "${STAGING_DIR}_repo/.loa-version.json" "$STAGING_DIR/" 2>/dev/null || true
  rm -rf "${STAGING_DIR}_repo"

  # === STAGE 2.5: Already-up-to-date check (Issue #245) ===
  # Compare upstream version with current version. Skip update if identical
  # unless --force is used or targeting a specific branch/commit.
  if [[ "$force" != "true" ]]; then
    local upstream_version=""
    if [[ -f "$STAGING_DIR/.loa-version.json" ]]; then
      upstream_version=$(jq -r '.framework_version // empty' "$STAGING_DIR/.loa-version.json" 2>/dev/null || echo "")
    fi

    if [[ -n "$upstream_version" && -n "$current" && "$upstream_version" == "$current" ]]; then
      # For tags and @latest, version match means nothing to do.
      # For branches/commits, user may want latest commits even at same version.
      if [[ "$TARGET_TYPE" == "latest" || "$TARGET_TYPE" == "tag" ]]; then
        log "Already up to date (v${current})"
        rm -rf "$STAGING_DIR"
        exit 0
      else
        warn "Upstream version matches local (v${current}) but targeting ${TARGET_TYPE} '${TARGET_REF}' — continuing"
      fi
    fi
  fi

  # === STAGE 2.75: Check override conflicts (T3.5.5) ===
  check_override_conflicts "$STAGING_DIR" || true

  # === STAGE 3: Validate ===
  preflight_check

  if [[ "$dry_run" == "true" ]]; then
    show_dry_run_preview "$STAGING_DIR"
    rm -rf "$STAGING_DIR"
    exit 0
  fi

  # === STAGE 4: Migrations (BLOCKING) ===
  run_migrations

  # === STAGE 5: Atomic Swap ===
  log "Performing atomic swap..."

  local backup_name=".claude.backup.$(date +%s)"
  if [[ -d "$SYSTEM_DIR" ]]; then
    mv "$SYSTEM_DIR" "$backup_name"
  fi

  if ! mv "$STAGING_DIR" "$SYSTEM_DIR"; then
    warn "Swap failed, rolling back..."
    [[ -d "$backup_name" ]] && mv "$backup_name" "$SYSTEM_DIR"
    err "Update failed - restored previous version"
  fi

  # === STAGE 6: Restore User Content ===
  mkdir -p "$SYSTEM_DIR/overrides"
  if [[ -d "$backup_name/overrides" ]]; then
    cp -r "$backup_name/overrides/"* "$SYSTEM_DIR/overrides/" 2>/dev/null || true
    log "Restored user overrides"
  fi

  # BUG-361: Restore user-installed construct packs (not framework-managed)
  if [[ -d "$backup_name/constructs" ]]; then
    cp -r "$backup_name/constructs" "$SYSTEM_DIR/"
    log "Restored user constructs"
  fi

  # === STAGE 7: Update Manifest ===
  local new_version=$(jq -r '.framework_version // "unknown"' "$SYSTEM_DIR/.loa-version.json" 2>/dev/null || echo "unknown")

  # Get the commit SHA for history tracking
  local staging_commit=""
  if [[ "$TARGET_TYPE" == "commit" ]]; then
    staging_commit="$TARGET_REF"
  else
    # Try to get commit from the cloned repo (already deleted, so get from git)
    staging_commit=$(git ls-remote "$UPSTREAM_REPO" "$TARGET_REF" 2>/dev/null | head -1 | cut -f1)
    [[ -z "$staging_commit" ]] && staging_commit="unknown"
  fi

  # Update version history with full tracking (T3.5.3)
  update_version_history "$current" "$new_version" "$TARGET_REF" "$TARGET_TYPE" "$staging_commit"

  # Update integrity verification timestamp
  local tmp
  tmp=$(mktemp) || { err "mktemp failed"; return 1; }
  chmod 600 "$tmp"  # CRITICAL-001 FIX: Restrict permissions
  trap "rm -f '$tmp'" RETURN
  jq '.integrity.last_verified = "'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'"' "$VERSION_FILE" > "$tmp" && mv "$tmp" "$VERSION_FILE"

  # === STAGE 8: Generate New Checksums ===
  generate_checksums

  # === STAGE 9: Apply Stealth Mode ===
  apply_stealth_mode

  # === STAGE 10: Regenerate Config Snapshot ===
  if validate_config "$CONFIG_FILE" 2>/dev/null; then
    mkdir -p grimoires/loa/context
    yq_to_json "$CONFIG_FILE" > grimoires/loa/context/config_snapshot.json 2>/dev/null || true
  fi

  # Cleanup old backups (keep 3)
  # SECURITY (HIGH-007): Use atomic backup cleanup to prevent race conditions
  _cleanup_old_backups() {
    local lock_file=".claude.backup.lock"
    exec 8>"$lock_file"
    if ! flock -w 5 8; then
      warn "Could not acquire backup cleanup lock, skipping"
      exec 8>&-
      return 0
    fi
    # Read all backups into array to avoid race condition between ls and rm
    local -a backups
    mapfile -t backups < <(ls -dt .claude.backup.* 2>/dev/null)
    local count=${#backups[@]}
    if [[ $count -gt 3 ]]; then
      for ((i=3; i<count; i++)); do
        rm -rf "${backups[$i]}" 2>/dev/null || true
      done
    fi
    flock -u 8
    exec 8>&-
    rm -f "$lock_file"
  }
  _cleanup_old_backups

  # === STAGE 11: Create Atomic Commit ===
  create_upgrade_commit "$current" "$new_version" "$no_commit" "$force"

  # === STAGE 12: Check for Grimoire Migration ===
  local migrate_script="$SYSTEM_DIR/scripts/migrate-grimoires.sh"
  if [[ -x "$migrate_script" ]]; then
    if "$migrate_script" check --json 2>/dev/null | grep -q '"needs_migration": true'; then
      log ""
      log "======================================================================="
      log "  MIGRATION AVAILABLE: Grimoires Restructure"
      log "======================================================================="
      log ""
      log "Your project uses the legacy 'loa-grimoire/' path."
      log "The new structure uses 'grimoires/loa/' (private) and 'grimoires/pub/' (public)."
      log ""
      log "Run the migration:"
      log "  .claude/scripts/migrate-grimoires.sh plan    # Preview changes"
      log "  .claude/scripts/migrate-grimoires.sh run     # Execute migration"
      log ""
    fi
  fi

  # === STAGE 13: Run Upgrade Health Check ===
  local health_check_script="$SYSTEM_DIR/scripts/upgrade-health-check.sh"
  if [[ -x "$health_check_script" ]]; then
    log ""
    log "Running post-upgrade health check..."
    "$health_check_script" --quiet || {
      local exit_code=$?
      if [[ $exit_code -eq 2 ]]; then
        warn "Health check found issues - run: .claude/scripts/upgrade-health-check.sh"
      elif [[ $exit_code -eq 1 ]]; then
        log "Health check has suggestions - run: .claude/scripts/upgrade-health-check.sh"
      fi
    }
  fi

  # === STAGE 14: Show Completion Banner (T3.5.5 Enhanced) ===
  # Count files changed for summary
  local files_changed=0
  if [[ -d "$SYSTEM_DIR" ]]; then
    files_changed=$(find "$SYSTEM_DIR" -type f | wc -l | tr -d ' ')
  fi

  local banner_script="$SYSTEM_DIR/scripts/upgrade-banner.sh"
  if [[ -x "$banner_script" ]]; then
    "$banner_script" "$current" "$new_version"
  else
    # Fallback: use our one-liner summary (T3.5.5)
    show_update_summary "$current" "$new_version" "$files_changed" "$TARGET_TYPE" "$TARGET_REF"
  fi

  # Branch warning (T3.5.5)
  if [[ "$TARGET_TYPE" == "branch" && "$TARGET_REF" != "main" && "$TARGET_REF" != "master" ]]; then
    echo -e "  ${YELLOW}Note:${NC} You're on branch '${TARGET_REF}'"
    echo -e "  Run ${CYAN}/update-loa @latest${NC} to switch to stable"
    echo ""
  fi

  # Rebuild learnings index to pick up new framework learnings (v1.15.1)
  post_update_learnings
}

# Rebuild learnings index after update to include new framework learnings
post_update_learnings() {
  local learnings_index_script="$SYSTEM_DIR/scripts/loa-learnings-index.sh"

  if [[ -x "$learnings_index_script" ]]; then
    info "Rebuilding learnings index..."
    if "$learnings_index_script" index >/dev/null 2>&1; then
      # Count framework learnings
      local fw_count=0
      if [[ -d "$SYSTEM_DIR/loa/learnings" ]]; then
        fw_count=$(find "$SYSTEM_DIR/loa/learnings" -name "*.json" ! -name "index.json" -exec jq '.learnings | length' {} + 2>/dev/null | awk '{sum+=$1} END{print sum}')
      fi
      if [[ -n "$fw_count" && "$fw_count" -gt 0 ]]; then
        log "Framework learnings available: ${fw_count}"
      fi
    else
      warn "Could not rebuild learnings index"
    fi
  fi
}

main "$@"
