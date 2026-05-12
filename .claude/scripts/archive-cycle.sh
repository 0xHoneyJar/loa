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
RETENTION_FROM_CLI=false
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
        # Validate retention is numeric (0 is allowed: "keep all, skip cleanup")
        if [[ "$2" =~ ^[0-9]+$ ]]; then
          RETENTION="$2"
          RETENTION_FROM_CLI=true
        else
          echo "ERROR: --retention must be a non-negative integer" >&2
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
  # cycle-104 Sprint 1 T1.2 (#848 retention bug fix):
  # CLI --retention wins over yaml. Previously this function ran AFTER
  # parse_args and unconditionally overwrote whatever the operator passed
  # on the command line, which is why `--retention 5` and `--retention 50`
  # produced the same deletion set (yaml default of 5 always won).
  if [[ -f "$CONFIG_FILE" ]] && [[ "$RETENTION_FROM_CLI" != "true" ]]; then
    RETENTION=$(yq -e '.compound_learning.archive.retention_cycles // 5' "$CONFIG_FILE" 2>/dev/null || echo "5")
  fi
}

# cycle-104 Sprint 1 T1.1 (#848 per-cycle-subdir resolver):
# Find ledger entry by cycle number, tolerating both legacy short ids
# (cycle-8, cycle-103) and zero-padded modern ids (cycle-098). Returns
# the canonical .id string or empty.
_resolve_cycle_id() {
  local n="$1"
  local ledger="${GRIMOIRE_DIR}/ledger.json"
  [[ -f "$ledger" ]] || { echo ""; return; }
  local pattern="^cycle-0*${n}(-|$)"
  jq -r --arg p "$pattern" '.cycles[]? | select(.id | test($p)) | .id' "$ledger" 2>/dev/null | head -1
}

# Resolve the directory where this cycle's artifacts (prd/sdd/sprint/etc.) live.
# Precedence:
#   1. ledger.cycles[].cycle_folder (canonical for modern cycles ≥102)
#   2. dirname of ledger.cycles[].prd (covers cycles where folder isn't set but prd path is)
#   3. ${GRIMOIRE_DIR}/cycles/<cycle_id>/ if it exists on disk
#   4. ${GRIMOIRE_DIR} root (legacy fallback for cycles ≤097)
_resolve_cycle_artifact_root() {
  local cycle_id="$1"
  local ledger="${GRIMOIRE_DIR}/ledger.json"
  if [[ -z "$cycle_id" ]] || [[ ! -f "$ledger" ]]; then
    echo "$GRIMOIRE_DIR"
    return
  fi
  local resolved
  resolved=$(jq -r --arg id "$cycle_id" '
    (.cycles[]? | select(.id == $id)) as $c |
    ($c.cycle_folder // ($c.prd // "" | sub("/[^/]+$"; "")))
    | sub("/+$"; "")
  ' "$ledger" 2>/dev/null)

  # Reject the legacy grimoire root via path canonicalization so the caller's
  # downstream copies know to use the legacy a2a/compound path. Compare via
  # realpath to handle relative-vs-absolute (e.g., resolved="grimoires/loa"
  # vs GRIMOIRE_DIR="/abs/path/to/grimoires/loa").
  if [[ -n "$resolved" ]] && [[ -d "$resolved" ]]; then
    local resolved_abs grimoire_abs
    resolved_abs=$(cd "$resolved" 2>/dev/null && pwd -P) || resolved_abs=""
    grimoire_abs=$(cd "$GRIMOIRE_DIR" 2>/dev/null && pwd -P) || grimoire_abs="$GRIMOIRE_DIR"
    if [[ -n "$resolved_abs" ]] && [[ "$resolved_abs" != "$grimoire_abs" ]]; then
      echo "$resolved"
      return
    fi
  fi

  local constructed="${GRIMOIRE_DIR}/cycles/${cycle_id}"
  if [[ -d "$constructed" ]]; then
    echo "$constructed"
    return
  fi

  echo "$GRIMOIRE_DIR"
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

  # cycle-104 Sprint 1 T1.1: resolve cycle id + per-cycle-subdir source
  local cycle_id artifact_root archive_path
  cycle_id=$(_resolve_cycle_id "$cycle")
  artifact_root=$(_resolve_cycle_artifact_root "$cycle_id")

  # Archive dest preserves slug for modern cycles, falls back to numeric for legacy
  if [[ -n "$cycle_id" ]] && [[ "$cycle_id" != "cycle-${cycle}" ]]; then
    archive_path="${ARCHIVE_DIR}/${cycle_id}"
  else
    archive_path="${ARCHIVE_DIR}/cycle-${cycle}"
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[DRY-RUN] Would create archive at: $archive_path"
    echo "[DRY-RUN] Cycle id: ${cycle_id:-(not found in ledger; using legacy fallback)}"
    echo "[DRY-RUN] Artifact source: ${artifact_root}"
    echo "[DRY-RUN] Would copy:"
    [[ -f "${artifact_root}/prd.md" ]] && echo "  - ${artifact_root}/prd.md"
    [[ -f "${artifact_root}/sdd.md" ]] && echo "  - ${artifact_root}/sdd.md"
    [[ -f "${artifact_root}/sprint.md" ]] && echo "  - ${artifact_root}/sprint.md"
    [[ -f "${GRIMOIRE_DIR}/ledger.json" ]] && echo "  - ${GRIMOIRE_DIR}/ledger.json (always from root)"
    # Modern per-cycle subdirs (only when artifact_root is a per-cycle dir)
    if [[ "$artifact_root" != "$GRIMOIRE_DIR" ]]; then
      [[ -d "${artifact_root}/handoffs" ]] && echo "  - ${artifact_root}/handoffs/" || true
      [[ -d "${artifact_root}/a2a" ]] && echo "  - ${artifact_root}/a2a/" || true
      [[ -d "${artifact_root}/flatline" ]] && echo "  - ${artifact_root}/flatline/" || true
    else
      # Legacy compound state copy (cycles ≤097)
      [[ -d "${GRIMOIRE_DIR}/a2a/compound" ]] && echo "  - ${GRIMOIRE_DIR}/a2a/compound/" || true
    fi
    return 0
  fi

  mkdir -p "$archive_path"

  # Copy artifacts from per-cycle subdir (modern) or grimoire root (legacy)
  [[ -f "${artifact_root}/prd.md" ]] && cp "${artifact_root}/prd.md" "$archive_path/"
  [[ -f "${artifact_root}/sdd.md" ]] && cp "${artifact_root}/sdd.md" "$archive_path/"
  [[ -f "${artifact_root}/sprint.md" ]] && cp "${artifact_root}/sprint.md" "$archive_path/"
  # Ledger always lives at grimoire root regardless of cycle layout
  [[ -f "${GRIMOIRE_DIR}/ledger.json" ]] && cp "${GRIMOIRE_DIR}/ledger.json" "$archive_path/"

  # cycle-104 Sprint 1 T1.3: copy per-cycle subdirs (modern) OR legacy compound (legacy)
  if [[ "$artifact_root" != "$GRIMOIRE_DIR" ]]; then
    # Modern cycles ≥098: per-cycle subdir layout
    [[ -d "${artifact_root}/handoffs" ]] && cp -r "${artifact_root}/handoffs" "$archive_path/"
    [[ -d "${artifact_root}/a2a" ]] && cp -r "${artifact_root}/a2a" "$archive_path/"
    [[ -d "${artifact_root}/flatline" ]] && cp -r "${artifact_root}/flatline" "$archive_path/"
  else
    # Legacy cycles ≤097: compound state at grimoire root
    if [[ -d "${GRIMOIRE_DIR}/a2a/compound" ]]; then
      cp -r "${GRIMOIRE_DIR}/a2a/compound" "$archive_path/"
    fi
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

  # cycle-104 Sprint 1 T1.2 (#848): RETENTION=0 means "keep all, skip cleanup"
  if [[ "$RETENTION" -le 0 ]]; then
    if [[ "$DRY_RUN" == "true" ]]; then
      echo "[DRY-RUN] --retention 0 → keeping all archives, skipping cleanup"
    fi
    return
  fi

  # cycle-104 Sprint 1 T1.2: keep-newest-N semantics per SDD §5.4 (Q8 resolution).
  # Previously: sorted by version (alphabetic) and consulted yaml AFTER cli arg
  # parsing, which is why --retention 5 and --retention 50 produced the same
  # deletion set (yaml default always won). Fix: load_config now respects
  # RETENTION_FROM_CLI; this function uses mtime sort (newest first) and
  # filters anything older than position RETENTION+1.
  #
  # Archive entries include both legacy date-prefixed dirs (2026-02-01-foo)
  # and modern cycle-prefixed dirs (cycle-103-provider-unification). Both
  # patterns match the find filter.
  local archives=()
  while IFS= read -r line; do
    [[ -n "$line" ]] && archives+=("$line")
  done < <(
    find "$ARCHIVE_DIR" -maxdepth 1 -mindepth 1 -type d \
      \( -name "cycle-*" -o -name "20[0-9][0-9]-*" \) -printf '%T@\t%p\n' 2>/dev/null \
      | sort -rn -k1,1 \
      | tail -n "+$((RETENTION + 1))" \
      | cut -f2-
  )

  local count=${#archives[@]}
  if [[ "$count" -eq 0 ]]; then
    if [[ "$DRY_RUN" == "true" ]]; then
      echo "[DRY-RUN] Nothing to delete (archive count ≤ retention=$RETENTION)"
    fi
    return
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[DRY-RUN] Would delete $count old archive(s) (retention=$RETENTION, keep-newest-N):"
    printf '  %s\n' ${archives[@]+"${archives[@]}"}
    return
  fi

  # Real-path resolution for symlink-safe deletion (preserves cycle-056 HIGH-001 guard)
  local real_archive_dir
  real_archive_dir=$(cd "$ARCHIVE_DIR" 2>/dev/null && pwd -P) || {
    echo "[ERROR] Cannot resolve archive directory" >&2
    return 1
  }

  local dir real_dir
  for dir in ${archives[@]+"${archives[@]}"}; do
    if [[ "$dir" != "$ARCHIVE_DIR"/* ]]; then
      echo "[WARN] Skipping path not under archive dir: $dir" >&2
      continue
    fi
    real_dir=$(cd "$dir" 2>/dev/null && pwd -P) || {
      echo "[WARN] Cannot resolve path: $dir" >&2
      continue
    }
    if [[ "$real_dir" != "$real_archive_dir"/* ]]; then
      echo "[WARN] Path escapes archive directory (possible symlink attack): $dir" >&2
      continue
    fi
    rm -rf "$real_dir"
    echo "[INFO] Deleted old archive: $dir"
  done
}

main() {
  parse_args "$@"
  load_config
  create_archive
  cleanup_old_archives
}

main "$@"
