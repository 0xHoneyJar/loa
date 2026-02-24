#!/usr/bin/env bash
# migrate-state-layout.sh - Consolidate scattered State Zone into .loa-state/
# path-lib: exempt
#
# Migrates .beads/, .ck/, .run/, grimoires/loa/memory/ into unified .loa-state/
# directory using copy-verify-switch pattern with journal-based crash recovery.
#
# Usage:
#   migrate-state-layout.sh [--dry-run|--apply] [--compat-mode MODE]
#
# Options:
#   --dry-run       Preview migration plan without changes (default)
#   --apply         Execute migration with verification
#   --compat-mode   auto|resolution|symlink|copy (default: auto)
#   --force         Override stale lock without prompting
#   --quiet         Suppress non-error output
#   -h, --help      Show help
#
set -uo pipefail

# === Constants ===
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
VERSION_FILE="${PROJECT_ROOT}/.loa-version.json"
LOCK_FILE="${PROJECT_ROOT}/.loa-migration.lock"

# === Colors ===
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# === Logging ===
QUIET=false
log() { [[ "$QUIET" == "true" ]] || echo -e "${GREEN}[migrate]${NC} $*"; }
warn() { echo -e "${YELLOW}[migrate]${NC} WARNING: $*" >&2; }
err() { echo -e "${RED}[migrate]${NC} ERROR: $*" >&2; exit 1; }
info() { [[ "$QUIET" == "true" ]] || echo -e "${CYAN}[migrate]${NC} $*"; }

# === Defaults ===
MODE="dry-run"
COMPAT_MODE="auto"
FORCE=false

# === Source path-lib for state-dir resolution ===
# shellcheck source=bootstrap.sh
if [[ -f "${SCRIPT_DIR}/bootstrap.sh" ]]; then
  source "${SCRIPT_DIR}/bootstrap.sh"
fi

# === Argument Parsing ===
while [[ $# -gt 0 ]]; do
  case $1 in
    --dry-run) MODE="dry-run"; shift ;;
    --apply)   MODE="apply"; shift ;;
    --compat-mode)
      COMPAT_MODE="$2"
      if [[ ! "$COMPAT_MODE" =~ ^(auto|resolution|symlink|copy)$ ]]; then
        err "Invalid compat mode: $COMPAT_MODE (expected: auto|resolution|symlink|copy)"
      fi
      shift 2 ;;
    --force)   FORCE=true; shift ;;
    --quiet)   QUIET=true; shift ;;
    -h|--help)
      echo "Usage: migrate-state-layout.sh [--dry-run|--apply] [--compat-mode MODE]"
      echo ""
      echo "Consolidate scattered State Zone (.beads/, .ck/, .run/, memory/) into .loa-state/"
      echo ""
      echo "Options:"
      echo "  --dry-run        Preview migration plan (default)"
      echo "  --apply          Execute migration"
      echo "  --compat-mode    auto|resolution|symlink|copy (default: auto)"
      echo "  --force          Override stale lock"
      echo "  --quiet          Suppress non-error output"
      echo ""
      echo "Compat modes:"
      echo "  auto        Detect platform capabilities (default)"
      echo "  resolution  Remove old dirs after migration (cleanest)"
      echo "  symlink     Replace old dirs with symlinks (backward-compat)"
      echo "  copy        Keep both locations (safest, dual-write)"
      echo ""
      exit 0 ;;
    *) warn "Unknown option: $1"; shift ;;
  esac
done

# === Migration Source Map ===
# Format: source_dir:target_subdir
declare -a MIGRATION_SOURCES=(
  ".beads:beads"
  ".ck:ck"
  ".run:run"
  "grimoires/loa/memory:memory"
)

# === State Directory ===
get_target_dir() {
  if command -v get_state_dir &>/dev/null; then
    get_state_dir
  else
    echo "${PROJECT_ROOT}/.loa-state"
  fi
}

# === Platform Detection ===
detect_compat_mode() {
  if [[ "$COMPAT_MODE" != "auto" ]]; then
    echo "$COMPAT_MODE"
    return
  fi

  # Test symlink support in a temp dir
  local test_dir
  test_dir=$(mktemp -d) || { echo "copy"; return; }
  local test_target="${test_dir}/target"
  local test_link="${test_dir}/link"
  mkdir -p "$test_target"

  if ln -s "$test_target" "$test_link" 2>/dev/null; then
    rm -rf "$test_dir"
    echo "resolution"
  else
    rm -rf "$test_dir"
    echo "copy"
  fi
}

# === Locking ===
acquire_lock() {
  if [[ -f "$LOCK_FILE" ]]; then
    local lock_pid lock_host lock_time
    lock_pid=$(jq -r '.pid // ""' "$LOCK_FILE" 2>/dev/null) || lock_pid=""
    lock_host=$(jq -r '.hostname // ""' "$LOCK_FILE" 2>/dev/null) || lock_host=""
    lock_time=$(jq -r '.timestamp // ""' "$LOCK_FILE" 2>/dev/null) || lock_time=""
    local current_host
    current_host=$(hostname 2>/dev/null || echo "unknown")

    # Check if lock holder is still alive
    if [[ -n "$lock_pid" && "$lock_host" == "$current_host" ]]; then
      if kill -0 "$lock_pid" 2>/dev/null; then
        err "Migration already in progress (PID: $lock_pid, host: $lock_host, started: $lock_time)"
      fi
    fi

    # Stale lock
    if [[ "$FORCE" == "true" ]]; then
      warn "Removing stale lock (PID: $lock_pid, host: $lock_host)"
      rm -f "$LOCK_FILE"
    else
      warn "Stale lock detected (PID: $lock_pid not running)"
      warn "Use --force to override"
      err "Cannot acquire migration lock"
    fi
  fi

  # Write lock with metadata
  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  cat > "$LOCK_FILE" <<EOF
{
  "pid": $$,
  "hostname": "$(hostname 2>/dev/null || echo "unknown")",
  "timestamp": "$timestamp"
}
EOF
}

release_lock() {
  rm -f "$LOCK_FILE"
}

# === Journal ===
JOURNAL_FILE=""

init_journal() {
  local target_dir="$1"
  JOURNAL_FILE="${target_dir}/.migration-journal.json"

  # Check for existing journal (crash recovery)
  if [[ -f "$JOURNAL_FILE" ]]; then
    log "Found existing migration journal — resuming from last checkpoint"
    return 0
  fi

  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  cat > "$JOURNAL_FILE" <<EOF
{
  "started": "$timestamp",
  "pid": $$,
  "sources": {
    "beads": "pending",
    "ck": "pending",
    "run": "pending",
    "memory": "pending"
  }
}
EOF
}

journal_update() {
  local source_name="$1"
  local status="$2"
  if [[ -f "$JOURNAL_FILE" ]]; then
    local tmp="${JOURNAL_FILE}.tmp.$$"
    jq --arg src "$source_name" --arg st "$status" \
      '.sources[$src] = $st' "$JOURNAL_FILE" > "$tmp" && mv "$tmp" "$JOURNAL_FILE"
  fi
}

journal_status() {
  local source_name="$1"
  if [[ -f "$JOURNAL_FILE" ]]; then
    jq -r --arg src "$source_name" '.sources[$src] // "pending"' "$JOURNAL_FILE" 2>/dev/null
  else
    echo "pending"
  fi
}

remove_journal() {
  rm -f "$JOURNAL_FILE"
}

# === Maintenance Marker ===
set_maintenance() {
  local target_dir="$1"
  date +%s > "${target_dir}/.maintenance"
}

clear_maintenance() {
  local target_dir="$1"
  rm -f "${target_dir}/.maintenance"
}

# === Verification ===
# Returns: 0 on match, 1 on mismatch
verify_copy() {
  local source_dir="$1"
  local target_dir="$2"

  # Quick check: file count
  local source_count target_count
  source_count=$(find "$source_dir" -type f 2>/dev/null | wc -l)
  target_count=$(find "$target_dir" -type f 2>/dev/null | wc -l)

  if [[ "$source_count" -ne "$target_count" ]]; then
    warn "File count mismatch: source=$source_count, target=$target_count"
    return 1
  fi

  # Deep check: sha256 checksums
  local source_checksums target_checksums
  source_checksums=$(cd "$source_dir" && find . -type f -print0 | sort -z | xargs -0 sha256sum 2>/dev/null)
  target_checksums=$(cd "$target_dir" && find . -type f -print0 | sort -z | xargs -0 sha256sum 2>/dev/null)

  if [[ "$source_checksums" != "$target_checksums" ]]; then
    warn "Checksum mismatch between source and target"
    return 1
  fi

  # Permission check
  local source_perms target_perms
  source_perms=$(cd "$source_dir" && find . -type f -print0 | sort -z | xargs -0 stat -c '%n %a' 2>/dev/null) || true
  target_perms=$(cd "$target_dir" && find . -type f -print0 | sort -z | xargs -0 stat -c '%n %a' 2>/dev/null) || true

  if [[ -n "$source_perms" && "$source_perms" != "$target_perms" ]]; then
    warn "Permission mismatch between source and target"
    return 1
  fi

  return 0
}

# Verify SQLite database integrity
verify_sqlite() {
  local db_file="$1"
  if [[ ! -f "$db_file" ]]; then
    return 0  # No DB to check
  fi
  if ! command -v sqlite3 &>/dev/null; then
    warn "sqlite3 not available — skipping integrity check for $(basename "$db_file")"
    return 0
  fi
  local result
  result=$(sqlite3 "$db_file" "PRAGMA integrity_check;" 2>/dev/null)
  if [[ "$result" != "ok" ]]; then
    warn "SQLite integrity check failed for $db_file: $result"
    return 1
  fi
  return 0
}

# === Dry Run ===
dry_run_report() {
  local target_dir
  target_dir=$(get_target_dir)
  local resolved_compat
  resolved_compat=$(detect_compat_mode)

  echo ""
  log "======================================================================="
  log "  State Layout Migration — DRY RUN"
  log "======================================================================="
  echo ""
  info "Target directory: $target_dir"
  info "Compat mode: $resolved_compat"
  echo ""

  local total_files=0
  local total_size=0

  for entry in "${MIGRATION_SOURCES[@]}"; do
    local source_rel="${entry%%:*}"
    local target_sub="${entry#*:}"
    local source_abs="${PROJECT_ROOT}/${source_rel}"

    if [[ -d "$source_abs" ]]; then
      local count size
      count=$(find "$source_abs" -type f 2>/dev/null | wc -l)
      size=$(du -sh "$source_abs" 2>/dev/null | cut -f1)
      total_files=$((total_files + count))
      info "  ${source_rel}/ → ${target_sub}/"
      info "    Files: $count, Size: $size"

      # Check for SQLite files
      local db_files
      db_files=$(find "$source_abs" -name "*.db" -type f 2>/dev/null)
      if [[ -n "$db_files" ]]; then
        while IFS= read -r db; do
          local db_name
          db_name=$(basename "$db")
          if command -v sqlite3 &>/dev/null; then
            local integrity
            integrity=$(sqlite3 "$db" "PRAGMA integrity_check;" 2>/dev/null || echo "error")
            info "    SQLite ($db_name): integrity=$integrity"
          else
            info "    SQLite ($db_name): integrity=skipped (no sqlite3)"
          fi
        done <<< "$db_files"
      fi
    else
      info "  ${source_rel}/ → (not present, skipping)"
    fi
  done

  echo ""
  info "Total files to migrate: $total_files"
  echo ""

  # Check version file
  local current_layout=0
  if [[ -f "$VERSION_FILE" ]]; then
    current_layout=$(jq -r '.state_layout_version // 0' "$VERSION_FILE" 2>/dev/null) || current_layout=0
  fi
  info "Current layout version: $current_layout"
  info "Target layout version: 2"
  echo ""

  if [[ "$total_files" -eq 0 ]]; then
    log "Nothing to migrate — no source directories with files found."
  else
    log "To execute: migrate-state-layout.sh --apply"
  fi
  echo ""
}

# === Apply Migration ===
apply_migration() {
  local target_dir
  target_dir=$(get_target_dir)
  local resolved_compat
  resolved_compat=$(detect_compat_mode)

  echo ""
  log "======================================================================="
  log "  State Layout Migration — APPLY"
  log "======================================================================="
  echo ""
  info "Target: $target_dir"
  info "Compat mode: $resolved_compat"
  echo ""

  # Phase 0: Create target structure
  log "Phase 0: Creating target structure..."
  if command -v ensure_state_structure &>/dev/null; then
    ensure_state_structure || err "Failed to create state structure"
  else
    mkdir -p "${target_dir}/beads" "${target_dir}/ck" "${target_dir}/run/bridge-reviews" "${target_dir}/run/mesh-cache"
    mkdir -p "${target_dir}/memory/archive" "${target_dir}/memory/sessions"
    mkdir -p "${target_dir}/trajectory/current" "${target_dir}/trajectory/archive"
  fi

  # Phase 1: Acquire lock
  log "Phase 1: Acquiring migration lock..."
  acquire_lock

  # Phase 2: Set maintenance marker
  log "Phase 2: Setting maintenance mode..."
  set_maintenance "$target_dir"

  # Phase 3: Initialize journal
  log "Phase 3: Initializing migration journal..."
  init_journal "$target_dir"

  # Phase 4: Migrate each source
  local migrated=0
  local skipped=0
  local failed=0

  for entry in "${MIGRATION_SOURCES[@]}"; do
    local source_rel="${entry%%:*}"
    local target_sub="${entry#*:}"
    local source_abs="${PROJECT_ROOT}/${source_rel}"
    local target_abs="${target_dir}/${target_sub}"

    if [[ ! -d "$source_abs" ]]; then
      info "  Skipping ${source_rel}/ (not present)"
      journal_update "$target_sub" "skipped"
      skipped=$((skipped + 1))
      continue
    fi

    local file_count
    file_count=$(find "$source_abs" -type f 2>/dev/null | wc -l)
    if [[ "$file_count" -eq 0 ]]; then
      info "  Skipping ${source_rel}/ (empty)"
      journal_update "$target_sub" "skipped"
      skipped=$((skipped + 1))
      continue
    fi

    # Check journal for resume
    local journal_st
    journal_st=$(journal_status "$target_sub")
    if [[ "$journal_st" == "migrated" ]]; then
      info "  Already migrated: ${source_rel}/ (resuming)"
      migrated=$((migrated + 1))
      continue
    fi
    if [[ "$journal_st" == "verified" ]]; then
      info "  Already verified: ${source_rel}/ — applying compat mode"
      # Jump to compat mode application
      _apply_compat_mode "$source_abs" "$target_abs" "$resolved_compat" "$source_rel" "$target_sub"
      migrated=$((migrated + 1))
      continue
    fi

    log "  Migrating ${source_rel}/ → ${target_sub}/ ($file_count files)..."

    # 4a: Record copying state
    journal_update "$target_sub" "copying"

    # 4b: Stage copy to temp staging area
    local staging_dir="${target_dir}/.migration-staging/${target_sub}"
    mkdir -p "$staging_dir"

    if ! cp -rp "$source_abs"/. "$staging_dir"/ 2>/dev/null; then
      warn "Copy failed for ${source_rel}/"
      rm -rf "${target_dir}/.migration-staging/${target_sub}"
      journal_update "$target_sub" "failed"
      failed=$((failed + 1))
      continue
    fi

    # 4c: Verify
    if ! verify_copy "$source_abs" "$staging_dir"; then
      warn "Verification failed for ${source_rel}/ — rolling back staged copy"
      rm -rf "$staging_dir"
      journal_update "$target_sub" "failed"
      failed=$((failed + 1))
      continue
    fi

    # 4d: SQLite integrity check
    local db_files
    db_files=$(find "$staging_dir" -name "*.db" -type f 2>/dev/null)
    if [[ -n "$db_files" ]]; then
      while IFS= read -r db; do
        if ! verify_sqlite "$db"; then
          warn "SQLite integrity check failed for $db — rolling back"
          rm -rf "$staging_dir"
          journal_update "$target_sub" "failed"
          failed=$((failed + 1))
          continue 2  # Continue outer loop
        fi
      done <<< "$db_files"
    fi

    # 4e: Record verified
    journal_update "$target_sub" "verified"

    # 4f: Atomic cutover — move staged content into place
    # If target already has content from ensure_state_structure, merge
    if [[ -d "$target_abs" ]]; then
      # Move staged files into existing target
      cp -rp "$staging_dir"/. "$target_abs"/ 2>/dev/null || {
        warn "Cutover failed for ${source_rel}/ — rolling back"
        rm -rf "$staging_dir"
        journal_update "$target_sub" "failed"
        failed=$((failed + 1))
        continue
      }
    else
      mv "$staging_dir" "$target_abs" 2>/dev/null || {
        warn "Cutover failed for ${source_rel}/ — rolling back"
        rm -rf "$staging_dir"
        journal_update "$target_sub" "failed"
        failed=$((failed + 1))
        continue
      }
    fi
    rm -rf "$staging_dir"

    # Final verification after cutover
    if ! verify_copy "$source_abs" "$target_abs"; then
      warn "Post-cutover verification failed for ${source_rel}/"
      journal_update "$target_sub" "failed"
      failed=$((failed + 1))
      continue
    fi

    # 4g: Apply compat mode
    _apply_compat_mode "$source_abs" "$target_abs" "$resolved_compat" "$source_rel" "$target_sub"

    migrated=$((migrated + 1))
  done

  # Clean up staging dir
  rm -rf "${target_dir}/.migration-staging"

  # Phase 5: Update version file
  if [[ "$failed" -eq 0 ]]; then
    log "Phase 5: Updating version file..."
    _update_version_file
  fi

  # Phase 6: Remove journal
  if [[ "$failed" -eq 0 ]]; then
    log "Phase 6: Cleaning up journal..."
    remove_journal
  fi

  # Phase 7: Clear maintenance
  log "Phase 7: Clearing maintenance mode..."
  clear_maintenance "$target_dir"

  # Phase 8: Release lock
  log "Phase 8: Releasing lock..."
  release_lock

  # Summary
  echo ""
  log "======================================================================="
  log "  Migration Complete"
  log "======================================================================="
  info "  Migrated: $migrated"
  info "  Skipped:  $skipped"
  info "  Failed:   $failed"
  echo ""

  if [[ "$failed" -gt 0 ]]; then
    warn "Some sources failed migration. Run again to retry."
    return 1
  fi

  return 0
}

# === Compat Mode Application ===
_apply_compat_mode() {
  local source_abs="$1"
  local target_abs="$2"
  local compat="$3"
  local source_rel="$4"
  local target_sub="$5"

  case "$compat" in
    resolution)
      # Remove original source
      rm -rf "$source_abs"
      info "    Removed original: ${source_rel}/"
      ;;
    symlink)
      # Replace source with symlink to target
      rm -rf "$source_abs"
      ln -sf "$target_abs" "$source_abs"
      info "    Created symlink: ${source_rel}/ → ${target_abs}"
      ;;
    copy)
      # Keep both locations
      info "    Kept original: ${source_rel}/ (dual-write mode)"
      ;;
  esac
  journal_update "$target_sub" "migrated"
}

# === Version File Update ===
_update_version_file() {
  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  if [[ -f "$VERSION_FILE" ]]; then
    local tmp="${VERSION_FILE}.tmp.$$"
    jq --arg ts "$timestamp" \
      '.state_layout_version = 2 | .last_migration = $ts' \
      "$VERSION_FILE" > "$tmp" && mv "$tmp" "$VERSION_FILE"
  else
    # Create new version file
    cat > "$VERSION_FILE" <<EOF
{
  "state_layout_version": 2,
  "created": "$timestamp",
  "last_migration": "$timestamp"
}
EOF
  fi
}

# === Cleanup Trap ===
_cleanup() {
  local exit_code=$?
  if [[ "$MODE" == "apply" ]]; then
    local target_dir
    target_dir=$(get_target_dir)
    # Clean up staging dir if exists
    rm -rf "${target_dir}/.migration-staging" 2>/dev/null || true
    # Clear maintenance marker
    clear_maintenance "$target_dir" 2>/dev/null || true
    # Release lock
    release_lock 2>/dev/null || true
  fi
  exit "$exit_code"
}
trap '_cleanup' EXIT

# === Main ===
main() {
  case "$MODE" in
    dry-run)
      dry_run_report
      ;;
    apply)
      apply_migration
      ;;
  esac
}

main "$@"
