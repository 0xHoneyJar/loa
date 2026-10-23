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
#   --cycle N          Cycle to archive (default: the ledger's active_cycle
#                      number; else the highest-numbered cycle whose status
#                      is not "archived"; exit 1 when every cycle is
#                      archived, or when the newest cycle is archived but an
#                      older one is not; 1 when there is no ledger or no
#                      cycle-N id)
#   --retention N      Keep the newest N archives (default: 0 = keep all).
#                      Precedence: --retention, then the yaml key
#                      compound_learning.archive.retention_cycles, then 0.
#   --force            Archive even when the cycle has a sprint whose
#                      status is not "completed"
#   --dry-run          Preview without creating archive or touching the ledger
#   --help             Show this help
#   Any other option is an error (exit 1, usage on stderr).
#
# Behaviour (bug 20261021-ba367a, issue #1263):
#   - Completeness gate: a cycle with any sprint not "completed" is refused
#     (exit 1, nothing written) unless --force; checked before any write.
#   - The cycle's ledger entry needs ledger-lib.sh next to this script; when
#     it is missing the run is refused (exit 1) before anything is written.
#   - A ledger cycle id must be a plain slug (^cycle-N(-[A-Za-z0-9._-]+)?$,
#     no "..") or the run is refused. The archive directory is created with
#     a non -p mkdir: an existing archive directory is refused (exit 1),
#     never overwritten. This, not a lock held across the run, is what stops
#     two concurrent runs from writing the same archive; the ledger write
#     itself is locked.
#   - After a real archive, the live ledger gets, under the ledger-lib.sh
#     lock and through _write_ledger: the cycle's status "archived",
#     archived (RFC 3339 UTC), archive_path (relative to the repo root), and
#     active_cycle null when that cycle was active. The ledger.json copied
#     into the archive is the pre-update ledger. --dry-run never writes.
#   - Retention never deletes a directory holding a git-tracked file: it is
#     kept with "[WARN] tracked archive kept: <path>; prune it with git".
#     A yq failure reading the retention key WARNs and keeps all archives.
#     Outside a git work tree (or without git) the mtime rule alone applies;
#     any other git failure (e.g. dubious ownership) keeps every archive.
#
# Exit codes:
#   0  success (including dry-run)
#   1  invalid or unknown argument, unsafe ledger cycle id, archive
#      directory already exists, no safe default cycle (every cycle archived, or the
#      newest archived with an older one open; no --cycle), incomplete cycle
#      without --force, unreadable ledger, ledger-lib.sh missing, or ledger
#      update failure (the archive directory then exists)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/bootstrap.sh"

ARCHIVE_DIR=$(get_archive_dir)
GRIMOIRE_DIR=$(get_grimoire_dir)

CYCLE_NUM=""
RETENTION=0
RETENTION_FROM_CLI=false
RETENTION_SOURCE="default"
DRY_RUN=false
FORCE=false

usage() {
  sed -n '/^# Usage:/,/^# =====/p' "$0" | grep -v "^# =====" | sed -e 's/^# //' -e 's/^#$//'
  exit "${1:-0}"
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
          RETENTION_SOURCE="cli"
        else
          echo "ERROR: --retention must be a non-negative integer" >&2
          exit 1
        fi
        shift 2
        ;;
      --dry-run) DRY_RUN=true; shift ;;
      --force) FORCE=true; shift ;;
      --help|-h) usage ;;
      *)
        # bug 20261021-ba367a: a typo (--dryrun) must not run a real archive
        echo "ERROR: unknown option: $1" >&2
        usage 1 >&2
        ;;
    esac
  done
}

load_config() {
  # cycle-104 Sprint 1 T1.2 (#848 retention bug fix):
  # CLI --retention wins over yaml. Previously this function ran AFTER
  # parse_args and unconditionally overwrote whatever the operator passed
  # on the command line, which is why `--retention 5` and `--retention 50`
  # produced the same deletion set (yaml default of 5 always won).
  # bug 20261021-ba367a: an absent key means keep-all (0), never a silent 5.
  if [[ -f "$CONFIG_FILE" ]] && [[ "$RETENTION_FROM_CLI" != "true" ]]; then
    local yaml_retention=""
    if ! yaml_retention=$(yq '.compound_learning.archive.retention_cycles // ""' "$CONFIG_FILE" 2>/dev/null); then
      echo "[WARN] could not read compound_learning.archive.retention_cycles (yq failed); keeping all archives" >&2
      yaml_retention=""
    fi
    if [[ -n "$yaml_retention" ]] && [[ "$yaml_retention" != "null" ]]; then
      if [[ ! "$yaml_retention" =~ ^[0-9]+$ ]]; then
        echo "ERROR: compound_learning.archive.retention_cycles must be a non-negative integer (got: $yaml_retention)" >&2
        exit 1
      fi
      RETENTION="$yaml_retention"
      RETENTION_SOURCE="yaml"
    fi
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

# bug 20261021-ba367a: the default cycle is the active cycle's number, else the
# highest-numbered cycle whose status is not "archived" (ids cycle-8,
# cycle-098-foo, ...); when every numbered cycle is archived, exit 1 so a
# second no-argument run never re-archives the cycle just archived; with no
# ledger or no cycle-N ids, 1. When the newest cycle is archived but an older
# one is not (a stale "active" entry), exit 1 too: picking the stale cycle
# would snapshot today's root artifacts under an old cycle's name.
# Previously `.cycles | length` — the entry count, which names no cycle once
# ids are renumbered. A ledger jq cannot read is an error, not a silent 1.
get_current_cycle() {
  local ledger="${GRIMOIRE_DIR}/ledger.json"
  if [[ ! -f "$ledger" ]]; then
    echo "1"
    return 0
  fi
  local n
  if ! n=$(jq -r '
      def cnum: capture("^cycle-(?<n>[0-9]+)") | .n | tonumber;
      if ((.active_cycle | type) == "string") and (.active_cycle | test("^cycle-[0-9]+"))
      then .active_cycle | cnum
      else
        [.cycles[]? | select((.id | type) == "string" and (.id | test("^cycle-[0-9]+")))] as $numbered
        | if ($numbered | length) == 0 then 1
          else
            [$numbered[] | {n: (.id | cnum), id: .id, open: (.status != "archived")}] as $c
            | ($c | max_by(.n)) as $newest
            | ([$c[] | select(.open)] | max_by(.n)) as $latest_open
            | if $latest_open == null then "all-archived"
              elif $latest_open.n == $newest.n then $latest_open.n
              else "stale \($newest.id) \($latest_open.id)"
              end
          end
      end' "$ledger"); then
    echo "ERROR: cannot derive the default cycle from $ledger; pass --cycle N" >&2
    return 1
  fi
  if [[ "$n" == "all-archived" ]]; then
    echo "ERROR: every cycle in the ledger is archived; pass --cycle N to re-archive one" >&2
    return 1
  fi
  if [[ "$n" == stale\ * ]]; then
    local newest_id open_id
    read -r _ newest_id open_id <<< "$n"
    echo "ERROR: the newest cycle (${newest_id}) is archived but an older cycle (${open_id}) is not; pass --cycle N" >&2
    return 1
  fi
  echo "$n"
}

# Count the cycle's sprints whose status is not "completed" (mirrors the gate
# in ledger-lib.sh archive_cycle). Prints 0 when the cycle or ledger is absent.
_count_incomplete_sprints() {
  local cycle_id="$1"
  local ledger="${GRIMOIRE_DIR}/ledger.json"
  if [[ -z "$cycle_id" ]] || [[ ! -f "$ledger" ]]; then
    echo "0"
    return 0
  fi
  jq -r --arg id "$cycle_id" \
    '[(.cycles[]? | select(.id == $id)).sprints[]? | select(type == "object") | select(.status != "completed")] | length' \
    "$ledger"
}

# Record the archive in the live ledger through ledger-lib.sh (lock +
# _write_ledger, atomic, backed up). Runs in a subshell so the lock fd is
# released on return. Args: cycle id, archive path relative to the repo root.
_update_ledger_archived() {
  local cycle_id="$1" rel_path="$2"
  (
    # shellcheck source=ledger-lib.sh
    source "$SCRIPT_DIR/ledger-lib.sh" || exit 1
    _lock_ledger_transaction || exit 1
    ledger_path=$(get_ledger_path) || exit 1
    content=$(jq --arg id "$cycle_id" --arg archived "$(now_iso)" --arg path "$rel_path" '
      (.cycles[] | select(.id == $id)) |= (.status = "archived" | .archived = $archived | .archive_path = $path)
      | if .active_cycle == $id then .active_cycle = null else . end' "$ledger_path") || exit 1
    _write_ledger "$content" || exit 1
  )
}

# Print the archive path relative to the repo root when its real path is under
# the real root; else print the given absolute path and WARN.
# Args: real archive path, real repo root, archive path as computed.
_archive_rel_path() {
  if [[ "$1" == "$2"/* ]]; then
    echo "${1#"$2"/}"
  else
    echo "[WARN] archive path is outside the repo root; the ledger records it absolute: $3" >&2
    echo "$3"
  fi
}

create_archive() {
  local cycle
  if [[ -n "$CYCLE_NUM" ]]; then
    cycle="$CYCLE_NUM"
  else
    cycle=$(get_current_cycle) || exit 1
  fi

  # SECURITY (MEDIUM-003): Validate cycle is numeric (defense in depth)
  if [[ ! "$cycle" =~ ^[0-9]+$ ]]; then
    echo "ERROR: Invalid cycle number: $cycle" >&2
    exit 1
  fi

  # cycle-104 Sprint 1 T1.1: resolve cycle id + per-cycle-subdir source
  local cycle_id artifact_root archive_path
  cycle_id=$(_resolve_cycle_id "$cycle")
  # bug 20261021-ba367a: the id becomes a path component; refuse anything but
  # a plain slug (no "/", no "..") before it is used for any path.
  if [[ -n "$cycle_id" ]] && { [[ ! "$cycle_id" =~ ^cycle-[0-9]+(-[A-Za-z0-9._-]+)?$ ]] || [[ "$cycle_id" == *..* ]]; }; then
    echo "ERROR: ledger cycle id is not a safe slug: ${cycle_id}; refusing to archive" >&2
    exit 1
  fi
  artifact_root=$(_resolve_cycle_artifact_root "$cycle_id")

  # Archive dest preserves slug for modern cycles, falls back to numeric for legacy
  if [[ -n "$cycle_id" ]] && [[ "$cycle_id" != "cycle-${cycle}" ]]; then
    archive_path="${ARCHIVE_DIR}/${cycle_id}"
  else
    archive_path="${ARCHIVE_DIR}/cycle-${cycle}"
  fi
  # Relative to the repo root, compared on pwd -P-resolved paths; an archive
  # outside the root keeps its absolute path. The dry run resolves the
  # would-be path; a real run re-resolves the directory it actually created.
  local root_real archive_dir_real rel_archive_path
  root_real=$(cd "$PROJECT_ROOT" 2>/dev/null && pwd -P) || root_real="$PROJECT_ROOT"
  archive_dir_real=$(cd "$ARCHIVE_DIR" 2>/dev/null && pwd -P) || archive_dir_real="$ARCHIVE_DIR"
  rel_archive_path=$(_archive_rel_path "${archive_dir_real}/${archive_path##*/}" "$root_real" "$archive_path")

  # bug 20261021-ba367a: completeness gate, before anything is written
  local incomplete
  if ! incomplete=$(_count_incomplete_sprints "$cycle_id"); then
    echo "ERROR: cannot read sprint status for ${cycle_id} from the ledger" >&2
    exit 1
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[DRY-RUN] Would create archive at: $archive_path"
    if [[ -e "$archive_path" ]] || [[ -L "$archive_path" ]]; then
      echo "[DRY-RUN] Archive already exists; a real run would refuse (exit 1)"
    fi
    echo "[DRY-RUN] Cycle id: ${cycle_id:-(not found in ledger; using legacy fallback)}"
    if [[ "$incomplete" -gt 0 ]]; then
      if [[ "$FORCE" == "true" ]]; then
        echo "[DRY-RUN] Completeness gate: ${incomplete} incomplete sprint(s); --force would archive anyway"
      else
        echo "[DRY-RUN] Completeness gate: ${incomplete} incomplete sprint(s); a real run would refuse (pass --force to override)"
      fi
    fi
    if [[ -n "$cycle_id" ]] && [[ ! -f "$SCRIPT_DIR/ledger-lib.sh" ]]; then
      echo "[DRY-RUN] ledger-lib.sh not found next to archive-cycle.sh; a real run would refuse"
    elif [[ -n "$cycle_id" ]]; then
      echo "[DRY-RUN] Would update ledger: ${cycle_id} status=archived, archived=<now>, archive_path=${rel_archive_path}$(jq -r --arg id "$cycle_id" 'if .active_cycle == $id then ", active_cycle=null" else "" end' "${GRIMOIRE_DIR}/ledger.json")"
    else
      echo "[DRY-RUN] Would not update ledger (cycle ${cycle} has no ledger entry)"
    fi
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

  if [[ "$incomplete" -gt 0 ]]; then
    if [[ "$FORCE" != "true" ]]; then
      echo "ERROR: Cycle ${cycle_id} has ${incomplete} incomplete sprint(s); refusing to archive (pass --force to override)" >&2
      exit 1
    fi
    echo "[WARN] Cycle ${cycle_id} has ${incomplete} incomplete sprint(s); archiving anyway (--force)" >&2
  fi
  if [[ -n "$cycle_id" ]] && [[ ! -f "$SCRIPT_DIR/ledger-lib.sh" ]]; then
    echo "ERROR: ledger-lib.sh not found next to archive-cycle.sh; cannot record the archive in the ledger" >&2
    exit 1
  fi

  # Fail closed on an existing archive: create the parent with -p, the
  # archive itself without, so a second run (or a concurrent one) can never
  # copy over an earlier archive.
  mkdir -p "$ARCHIVE_DIR"
  if ! mkdir "$archive_path" 2>/dev/null; then
    if [[ -e "$archive_path" ]] || [[ -L "$archive_path" ]]; then
      echo "ERROR: archive already exists: $archive_path; remove it (git rm if tracked) or pass another --cycle" >&2
    else
      echo "ERROR: cannot create archive directory: $archive_path" >&2
    fi
    exit 1
  fi
  local created_real
  archive_dir_real=$(cd "$ARCHIVE_DIR" && pwd -P)
  if ! created_real=$(cd "$archive_path" && pwd -P) || [[ "$created_real" != "$archive_dir_real/${archive_path##*/}" ]]; then
    rmdir "$archive_path" 2>/dev/null || true
    echo "ERROR: archive directory resolves outside ${ARCHIVE_DIR}: $archive_path; refusing" >&2
    exit 1
  fi
  rel_archive_path=$(_archive_rel_path "$created_real" "$root_real" "$archive_path")

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

  # bug 20261021-ba367a / #1263: record the archive in the live ledger
  # (after the pre-update ledger.json was copied into the archive above).
  if [[ -n "$cycle_id" ]]; then
    if ! _update_ledger_archived "$cycle_id" "$rel_archive_path"; then
      echo "ERROR: archive created at $archive_path but the ledger update for ${cycle_id} failed" >&2
      exit 1
    fi
    echo "[INFO] Ledger updated: ${cycle_id} status=archived, archive_path=${rel_archive_path}"
  else
    echo "[INFO] Cycle ${cycle} has no ledger entry; ledger not updated"
  fi
}

# bug 20261021-ba367a: true when the directory holds any git-tracked (or
# staged) file. Fail-safe: any git error other than "no match" (exit 1) counts
# as tracked, so an unverifiable directory is kept rather than deleted.
# `ls-files --error-unmatch` is used instead of `ls-files | grep -q .`
# because under pipefail an early-exiting grep can SIGPIPE git and turn a
# tracked directory into a false "untracked".
_archive_dir_tracked() {
  local rc=0
  # :(literal) so [ ] * ? in a directory name are not pathspec glob magic
  git -C "$ARCHIVE_DIR" ls-files --error-unmatch -- ":(literal)$1" >/dev/null 2>&1 || rc=$?
  [[ "$rc" -ne 1 ]]
}

cleanup_old_archives() {
  if [[ ! -d "$ARCHIVE_DIR" ]]; then
    return
  fi

  # cycle-104 Sprint 1 T1.2 (#848): RETENTION=0 means "keep all, skip cleanup"
  if [[ "$RETENTION" -le 0 ]]; then
    if [[ "$DRY_RUN" == "true" ]]; then
      case "$RETENTION_SOURCE" in
        cli)  echo "[DRY-RUN] --retention 0 → keeping all archives, skipping cleanup" ;;
        yaml) echo "[DRY-RUN] compound_learning.archive.retention_cycles: 0 → keeping all archives, skipping cleanup" ;;
        *)    echo "[DRY-RUN] retention 0 (default: no --retention, no compound_learning.archive.retention_cycles) → keeping all archives, skipping cleanup" ;;
      esac
      echo "[DRY-RUN] Nothing to delete"
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

  # bug 20261021-ba367a: never delete git-tracked history. Inside a git work
  # tree, candidates holding a tracked file are kept with a WARN; outside one
  # (or without git) the mtime rule alone applies, as before.
  # Only "git absent" or "not a git repository" fall back to the mtime rule;
  # any other git failure (dubious ownership, corrupt .git, ...) keeps all.
  local in_git=false
  if command -v git >/dev/null 2>&1; then
    local git_out git_rc=0
    git_out=$(git -C "$ARCHIVE_DIR" rev-parse --is-inside-work-tree 2>&1) || git_rc=$?
    if [[ "$git_rc" -eq 0 ]] && [[ "$git_out" == "true" ]]; then
      in_git=true
    elif [[ "$git_rc" -eq 128 ]] && [[ "$git_out" == *"not a git repository"* ]]; then
      in_git=false
    else
      echo "[WARN] git could not report whether ${ARCHIVE_DIR} is tracked (${git_out%%$'\n'*}); keeping every archive" >&2
      if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY-RUN] Nothing to delete (git state unknown)"
      fi
      return 0
    fi
  fi
  local candidates=() kept=() cand
  candidates=(${archives[@]+"${archives[@]}"})
  archives=()
  for cand in ${candidates[@]+"${candidates[@]}"}; do
    if [[ "$in_git" == "true" ]] && _archive_dir_tracked "$cand"; then
      kept+=("$cand")
    else
      archives+=("$cand")
    fi
  done
  if [[ ${#kept[@]} -gt 0 ]]; then
    if [[ "$DRY_RUN" == "true" ]]; then
      echo "[DRY-RUN] Would keep ${#kept[@]} git-tracked archive(s) past retention=$RETENTION:"
    fi
    for cand in ${kept[@]+"${kept[@]}"}; do
      echo "[WARN] tracked archive kept: $cand; prune it with git" >&2
    done
  fi

  local count=${#archives[@]}
  if [[ "$count" -eq 0 ]]; then
    if [[ "$DRY_RUN" == "true" ]]; then
      if [[ ${#kept[@]} -gt 0 ]]; then
        echo "[DRY-RUN] Nothing to delete (every archive past retention=$RETENTION is git-tracked)"
      else
        echo "[DRY-RUN] Nothing to delete (archive count ≤ retention=$RETENTION)"
      fi
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
