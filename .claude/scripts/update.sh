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
  local tmp=$(mktemp)
  jq --arg k "$1" --arg v "$2" '.[$k] = $v' "$VERSION_FILE" > "$tmp" && mv "$tmp" "$VERSION_FILE"
}

set_version_int() {
  local tmp=$(mktemp)
  jq --arg k "$1" --argjson v "$2" '.[$k] = $v' "$VERSION_FILE" > "$tmp" && mv "$tmp" "$VERSION_FILE"
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
          local tmp=$(mktemp)
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
  if [[ ! -f "$CONFIG_FILE" ]]; then return 0; fi

  local mode=$(yq_read "$CONFIG_FILE" '.persistence_mode' "standard")

  if [[ "$mode" == "stealth" ]]; then
    log "Stealth mode: adding state files to .gitignore"
    local gitignore=".gitignore"
    touch "$gitignore"

    grep -qxF 'loa-grimoire/' "$gitignore" 2>/dev/null || echo 'loa-grimoire/' >> "$gitignore"
    grep -qxF '.beads/' "$gitignore" 2>/dev/null || echo '.beads/' >> "$gitignore"
    grep -qxF '.loa-version.json' "$gitignore" 2>/dev/null || echo '.loa-version.json' >> "$gitignore"
    grep -qxF '.loa.config.yaml' "$gitignore" 2>/dev/null || echo '.loa.config.yaml' >> "$gitignore"
  fi
}

# === Main ===
main() {
  local dry_run=false
  local force=false
  local force_restore=false

  while [[ $# -gt 0 ]]; do
    case $1 in
      --dry-run) dry_run=true; shift ;;
      --force) force=true; shift ;;
      --force-restore) force_restore=true; shift ;;
      *) shift ;;
    esac
  done

  log "======================================================================="
  log "  Loa Framework Update v0.6.0"
  log "  Fetch -> Validate -> Migrate -> Swap"
  log "======================================================================="

  check_deps

  if [[ ! -f "$VERSION_FILE" ]]; then
    cat > "$VERSION_FILE" << 'EOF'
{
  "framework_version": "0.0.0",
  "schema_version": 1,
  "last_sync": null,
  "zones": {"system": ".claude", "state": ["loa-grimoire", ".beads"], "app": ["src", "lib", "app"]},
  "migrations_applied": [],
  "integrity": {"enforcement": "strict", "last_verified": null}
}
EOF
  fi

  local current=$(get_version "framework_version")
  log "Current version: ${current:-unknown}"

  # Get enforcement level from config
  local enforcement="strict"
  if [[ -f "$CONFIG_FILE" ]]; then
    enforcement=$(yq_read "$CONFIG_FILE" '.integrity_enforcement' "strict")
  fi

  # === STAGE 1: Integrity Check (BLOCKING in strict mode) ===
  if [[ "$force" != "true" ]]; then
    check_integrity "$enforcement" "$force_restore"
  else
    warn "Skipping integrity check (--force)"
  fi

  # === STAGE 2: Fetch to staging ===
  log "Fetching upstream into staging..."
  rm -rf "$STAGING_DIR"
  mkdir -p "$STAGING_DIR"

  git clone --depth 1 --single-branch --branch "$UPSTREAM_BRANCH" "$UPSTREAM_REPO" "${STAGING_DIR}_repo" 2>/dev/null || {
    err "Failed to fetch upstream repository"
  }

  cp -r "${STAGING_DIR}_repo/.claude/"* "$STAGING_DIR/" 2>/dev/null || true
  cp "${STAGING_DIR}_repo/.loa-version.json" "$STAGING_DIR/" 2>/dev/null || true
  rm -rf "${STAGING_DIR}_repo"

  # === STAGE 3: Validate ===
  preflight_check

  if [[ "$dry_run" == "true" ]]; then
    log "Dry run complete - no changes applied"
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

  # === STAGE 6: Restore Overrides ===
  mkdir -p "$SYSTEM_DIR/overrides"
  if [[ -d "$backup_name/overrides" ]]; then
    cp -r "$backup_name/overrides/"* "$SYSTEM_DIR/overrides/" 2>/dev/null || true
    log "Restored user overrides"
  fi

  # === STAGE 7: Update Manifest ===
  local new_version=$(jq -r '.framework_version // "unknown"' "$SYSTEM_DIR/.loa-version.json" 2>/dev/null || echo "unknown")
  set_version "framework_version" "$new_version"
  set_version "last_sync" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  # Update integrity verification timestamp
  local tmp=$(mktemp)
  jq '.integrity.last_verified = "'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'"' "$VERSION_FILE" > "$tmp" && mv "$tmp" "$VERSION_FILE"

  # === STAGE 8: Generate New Checksums ===
  generate_checksums

  # === STAGE 9: Apply Stealth Mode ===
  apply_stealth_mode

  # === STAGE 10: Regenerate Config Snapshot ===
  if [[ -f "$CONFIG_FILE" ]]; then
    mkdir -p loa-grimoire/context
    yq_to_json "$CONFIG_FILE" > loa-grimoire/context/config_snapshot.json 2>/dev/null || true
  fi

  # Cleanup old backups (keep 3)
  ls -dt .claude.backup.* 2>/dev/null | tail -n +4 | xargs rm -rf 2>/dev/null || true

  log ""
  log "======================================================================="
  log "  Update complete: $current -> $new_version"
  log "======================================================================="
}

main "$@"
