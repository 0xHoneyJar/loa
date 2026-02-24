#!/bin/bash
# =============================================================================
# archive-cycle.sh - Cycle Archive Management
# =============================================================================
# Sprint 9, Task 9.4-9.7: Archive cycle artifacts
#
# Usage:
#   ./archive-cycle.sh [options]
#
# Options:
#   --cycle N          Cycle to archive (default: current)
#   --retention N      Keep last N archives (default: 5)
#   --dry-run          Preview without creating archive
#   --help             Show this help
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/bootstrap.sh"

ARCHIVE_DIR=$(get_archive_dir)
GRIMOIRE_DIR=$(get_grimoire_dir)

CYCLE_NUM=""
RETENTION=5
DRY_RUN=false

usage() {
  sed -n '/^# Usage:/,/^# =====/p' "$0" | grep -v "^# =====" | sed 's/^# //'
  exit 0
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --cycle)
        # SECURITY (HIGH-001): Validate cycle is numeric only to prevent path traversal
        if [[ "$2" =~ ^[0-9]+$ ]]; then
          CYCLE_NUM="$2"
        else
          echo "ERROR: --cycle must be a positive integer" >&2
          exit 1
        fi
        shift 2
        ;;
      --retention)
        # Validate retention is numeric
        if [[ "$2" =~ ^[0-9]+$ ]]; then
          RETENTION="$2"
        else
          echo "ERROR: --retention must be a positive integer" >&2
          exit 1
        fi
        shift 2
        ;;
      --dry-run) DRY_RUN=true; shift ;;
      --help|-h) usage ;;
      *) shift ;;
    esac
  done
}

load_config() {
  if [[ -f "$CONFIG_FILE" ]]; then
    RETENTION=$(yq -e '.compound_learning.archive.retention_cycles // 5' "$CONFIG_FILE" 2>/dev/null || echo "5")
  fi
}

get_current_cycle() {
  local ledger="${GRIMOIRE_DIR}/ledger.json"
  if [[ -f "$ledger" ]]; then
    jq '.cycles | length' "$ledger" 2>/dev/null || echo "1"
  else
    echo "1"
  fi
}

create_archive() {
  local cycle
  cycle=${CYCLE_NUM:-$(get_current_cycle)}

  # SECURITY (MEDIUM-003): Validate cycle is numeric (defense in depth)
  if [[ ! "$cycle" =~ ^[0-9]+$ ]]; then
    echo "ERROR: Invalid cycle number: $cycle" >&2
    exit 1
  fi

  local archive_path="${ARCHIVE_DIR}/cycle-${cycle}"

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[DRY-RUN] Would create archive at: $archive_path"
    echo "[DRY-RUN] Would copy:"
    [[ -f "${GRIMOIRE_DIR}/prd.md" ]] && echo "  - prd.md"
    [[ -f "${GRIMOIRE_DIR}/sdd.md" ]] && echo "  - sdd.md"
    [[ -f "${GRIMOIRE_DIR}/sprint.md" ]] && echo "  - sprint.md"
    [[ -d "${GRIMOIRE_DIR}/a2a/compound" ]] && echo "  - a2a/compound/"
    return
  fi
  
  mkdir -p "$archive_path"
  
  # Copy artifacts
  [[ -f "${GRIMOIRE_DIR}/prd.md" ]] && cp "${GRIMOIRE_DIR}/prd.md" "$archive_path/"
  [[ -f "${GRIMOIRE_DIR}/sdd.md" ]] && cp "${GRIMOIRE_DIR}/sdd.md" "$archive_path/"
  [[ -f "${GRIMOIRE_DIR}/sprint.md" ]] && cp "${GRIMOIRE_DIR}/sprint.md" "$archive_path/"
  [[ -f "${GRIMOIRE_DIR}/ledger.json" ]] && cp "${GRIMOIRE_DIR}/ledger.json" "$archive_path/"
  
  # Copy compound state
  if [[ -d "${GRIMOIRE_DIR}/a2a/compound" ]]; then
    cp -r "${GRIMOIRE_DIR}/a2a/compound" "$archive_path/"
  fi
  
  # Generate changelog
  "$SCRIPT_DIR/generate-changelog.sh" --cycle "$cycle" --file "${archive_path}/CHANGELOG.md" 2>/dev/null || true

  # Export trajectory at cycle boundary (non-blocking)
  local traj_git_flag=""
  if [[ -f "$CONFIG_FILE" ]] && command -v yq >/dev/null 2>&1; then
    local traj_git_commit
    traj_git_commit=$(yq eval '.trajectory.archive.git_commit // false' "$CONFIG_FILE" 2>/dev/null || echo "false")
    [[ "$traj_git_commit" == "true" ]] && traj_git_flag="--git-commit"
  fi
  "$SCRIPT_DIR/trajectory-export.sh" --cycle "cycle-$(printf '%03d' "$cycle")" ${traj_git_flag:+$traj_git_flag} 2>/dev/null || {
    echo "[WARN] Trajectory export failed (non-blocking)" >&2
  }
  
  # Write archive metadata
  cat > "${archive_path}/.archive-meta.json" << EOF
{
  "cycle": $cycle,
  "archived_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "version": "1.0"
}
EOF
  
  echo "[INFO] Created archive: $archive_path"
}

cleanup_old_archives() {
  if [[ ! -d "$ARCHIVE_DIR" ]]; then
    return
  fi

  local archives
  archives=$(find "$ARCHIVE_DIR" -maxdepth 1 -type d -name "cycle-*" | sort -V)

  local count
  count=$(echo "$archives" | grep -c . || echo "0")

  if [[ "$count" -gt "$RETENTION" ]]; then
    local to_delete=$((count - RETENTION))

    if [[ "$DRY_RUN" == "true" ]]; then
      echo "[DRY-RUN] Would delete $to_delete old archives:"
      echo "$archives" | head -n "$to_delete"
    else
      echo "$archives" | head -n "$to_delete" | while read -r dir; do
        # SECURITY (HIGH-001): Validate path before rm -rf
        # 1. Check path is within ARCHIVE_DIR (no path traversal)
        # 2. Check path matches expected pattern (cycle-N)
        # 3. Resolve symlinks to prevent symlink attacks

        # Ensure path starts with ARCHIVE_DIR
        if [[ "$dir" != "$ARCHIVE_DIR"/cycle-* ]]; then
          echo "[WARN] Skipping invalid path: $dir" >&2
          continue
        fi

        # Resolve to real path (follows symlinks)
        local real_dir
        real_dir=$(cd "$dir" 2>/dev/null && pwd -P) || {
          echo "[WARN] Cannot resolve path: $dir" >&2
          continue
        }

        # Resolve ARCHIVE_DIR to real path for comparison
        local real_archive_dir
        real_archive_dir=$(cd "$ARCHIVE_DIR" 2>/dev/null && pwd -P) || {
          echo "[ERROR] Cannot resolve archive directory" >&2
          return 1
        }

        # Verify resolved path is still within archive directory
        if [[ "$real_dir" != "$real_archive_dir"/cycle-* ]]; then
          echo "[WARN] Path escapes archive directory (possible symlink attack): $dir" >&2
          continue
        fi

        # Safe to delete
        rm -rf "$real_dir"
        echo "[INFO] Deleted old archive: $dir"
      done
    fi
  fi
}

main() {
  parse_args "$@"
  load_config
  create_archive
  cleanup_old_archives
}

main "$@"
