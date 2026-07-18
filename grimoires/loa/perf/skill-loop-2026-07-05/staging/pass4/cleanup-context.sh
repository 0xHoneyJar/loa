#!/usr/bin/env bash
# cleanup-context.sh - Archive and clean discovery context for next development cycle
# Part of Run Mode v0.19.0+
#
# Usage:
#   cleanup-context.sh [--dry-run] [--verbose] [--no-archive]
#
# Called automatically by /run sprint-plan on successful completion.
# Can also be called manually before starting a new /plan-and-analyze cycle.
#
# By default, archives context to the current cycle's archive directory before cleaning.
# perf pass-4 (2026-07-05, skill-loop): change note at END of file.

set -euo pipefail

CONTEXT_DIR="${LOA_CONTEXT_DIR:-grimoires/loa/context}"
LEDGER_FILE="${LOA_LEDGER:-grimoires/loa/ledger.json}"
ARCHIVE_BASE="${LOA_ARCHIVE_BASE:-grimoires/loa/archive}"
DRY_RUN=false
VERBOSE=false
NO_ARCHIVE=false
PROMPT_MODE=false
AUTO_YES=false

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --verbose|-v)
      VERBOSE=true
      shift
      ;;
    --no-archive)
      NO_ARCHIVE=true
      shift
      ;;
    --prompt)
      PROMPT_MODE=true
      shift
      ;;
    --yes|-y)
      AUTO_YES=true
      shift
      ;;
    --help|-h)
      echo "Usage: cleanup-context.sh [--dry-run] [--verbose] [--no-archive] [--prompt] [--yes]"
      echo ""
      echo "Archive and clean discovery context directory for next development cycle."
      echo "Archives context files to the cycle's archive directory, then removes them."
      echo ""
      echo "Options:"
      echo "  --dry-run     Show what would be archived/deleted without doing it"
      echo "  --verbose     Show detailed output"
      echo "  --no-archive  Skip archiving, just delete (not recommended)"
      echo "  --prompt      Interactive mode: ask for confirmation before cleanup"
      echo "  --yes, -y     Auto-confirm in prompt mode (for scripting)"
      echo "  --help        Show this help message"
      echo ""
      echo "Archive location: {archive-path}/context/"
      echo "  - Determined from ledger.json active cycle or most recent archive"
      echo "  - Falls back to dated directory if no cycle info available"
      echo ""
      echo "Hook usage:"
      echo "  Used as PreToolUse hook for /plan-and-analyze to clean previous cycle context."
      echo "  In hook mode (--prompt), blocks execution if user declines cleanup."
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

# Check if context directory exists
if [[ ! -d "$CONTEXT_DIR" ]]; then
  echo "Context directory does not exist: $CONTEXT_DIR"
  exit 0
fi

# Count items to clean
file_count=$(find "$CONTEXT_DIR" -maxdepth 1 -type f ! -name "README.md" 2>/dev/null | wc -l)
dir_count=$(find "$CONTEXT_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)

if [[ $file_count -eq 0 && $dir_count -eq 0 ]]; then
  if [[ "$VERBOSE" == "true" ]]; then
    echo "Context directory already clean"
  fi
  exit 0
fi

# Determine archive destination
get_archive_path() {
  local archive_path=""

  # Try 1 + Try 2 consolidated (pass-4): active cycle's path, else most
  # recent archived — ONE jq read of the ledger (see end-of-file note)
  if [[ -f "$LEDGER_FILE" ]]; then
    archive_path=$(jq -r '
      def r: if type == "string" then . else tojson end;
      (try [.active_cycle // empty | r] catch [null] | .[0]) as $ac |
      (if ($ac != null and $ac != "") then
         (try [([.cycles[] | select(.id == $ac) | .archive_path // empty | r] | join("\n"))] catch [""] | .[0])
       else "" end) as $p1 |
      if $p1 != "" then $p1
      else
        (try [([.cycles[] | select(.status == "archived" and .archive_path != null)]
               | sort_by(.archived_at) | last | .archive_path // empty | r)] catch [""]
         | if length == 0 then "" else .[0] end)
      end
    ' "$LEDGER_FILE" 2>/dev/null || true)
  fi

  # Try 3: Find most recent archive directory
  if [[ -z "$archive_path" && -d "$ARCHIVE_BASE" ]]; then
    archive_path=$(find "$ARCHIVE_BASE" -maxdepth 1 -type d -name "20*" | sort -r | head -1 || true)
  fi

  # Try 4: Create dated fallback (bash strftime — local time, byte-identical
  # to the old `date +%Y-%m-%d` spawn, probe-verified)
  if [[ -z "$archive_path" ]]; then
    printf -v archive_path '%s/%(%Y-%m-%d)T-context-archive' "$ARCHIVE_BASE" -1
  fi

  echo "$archive_path"
}

archive_path=$(get_archive_path)
archive_context_dir="$archive_path/context"

echo "Context Cleanup"
echo "───────────────────────────────────────"
echo "Source: $CONTEXT_DIR"
echo "Files to process: $file_count"
echo "Directories to process: $dir_count"

if [[ "$NO_ARCHIVE" == "false" ]]; then
  echo "Archive to: $archive_context_dir"
fi
echo ""

if [[ "$VERBOSE" == "true" || "$DRY_RUN" == "true" ]]; then
  echo "Items to be processed:"

  # List files
  find "$CONTEXT_DIR" -maxdepth 1 -type f ! -name "README.md" 2>/dev/null | while read -r file; do
    echo "  [file] $(basename "$file")"
  done

  # List directories
  find "$CONTEXT_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | while read -r dir; do
    local_count=$(find "$dir" -type f 2>/dev/null | wc -l)
    echo "  [dir]  $(basename "$dir")/ ($local_count files)"
  done

  echo ""
fi

if [[ "$DRY_RUN" == "true" ]]; then
  if [[ "$NO_ARCHIVE" == "false" ]]; then
    echo "[DRY RUN] Would archive to: $archive_context_dir"
  fi
  echo "[DRY RUN] No files archived or deleted"
  exit 0
fi

# Prompt mode: ask for confirmation before proceeding
if [[ "$PROMPT_MODE" == "true" && "$AUTO_YES" == "false" ]]; then
  echo "─────────────────────────────────────────"
  echo "Previous cycle context detected."
  echo ""
  echo "Starting a new /plan-and-analyze will archive these files"
  echo "and clean the context directory for your new cycle."
  echo ""
  echo "Options:"
  echo "  [Y] Archive and proceed (recommended)"
  echo "  [n] Keep context and proceed (files will be re-used)"
  echo "  [q] Abort /plan-and-analyze"
  echo ""

  # Read from /dev/tty to get user input even when stdin is piped
  read -r -p "Archive previous context? [Y/n/q]: " response < /dev/tty 2>/dev/null || response="Y"

  case "${response,,}" in
    n|no)
      echo ""
      echo "Keeping existing context files. They will be loaded into the new PRD."
      echo "Note: This may cause confusion if context is from a different project."
      exit 0
      ;;
    q|quit|abort)
      echo ""
      echo "Aborting /plan-and-analyze. Context unchanged." >&2
      exit 2  # Exit code 2 blocks the hook
      ;;
    *)
      echo ""
      echo "Proceeding with archive and cleanup..."
      ;;
  esac
fi

# Archive context files (unless --no-archive)
if [[ "$NO_ARCHIVE" == "false" ]]; then
  echo "Archiving context files..."

  # Create archive context directory
  mkdir -p "$archive_context_dir"

  # Copy files (excluding README.md)
  find "$CONTEXT_DIR" -maxdepth 1 -type f ! -name "README.md" -exec cp {} "$archive_context_dir/" \; 2>/dev/null || true

  # Copy directories
  find "$CONTEXT_DIR" -mindepth 1 -maxdepth 1 -type d -exec cp -r {} "$archive_context_dir/" \; 2>/dev/null || true

  # Count archived items
  archived_files=$(find "$archive_context_dir" -type f 2>/dev/null | wc -l)
  echo "✓ Archived $archived_files files to $archive_context_dir"
fi

# Clean context directory
echo "Cleaning context directory..."

# Remove all files except README.md
find "$CONTEXT_DIR" -maxdepth 1 -type f ! -name "README.md" -delete

# SECURITY (MEDIUM-003): Safe directory removal with symlink protection
# Instead of find -exec rm -rf {}, iterate safely with validation
# Resolve CONTEXT_DIR to absolute path for comparison
REAL_CONTEXT_DIR=$(cd "$CONTEXT_DIR" 2>/dev/null && pwd -P) || {
    echo "ERROR: Cannot resolve context directory" >&2
    exit 1
}

for dir in "$CONTEXT_DIR"/*/; do
    # Skip if no directories match (glob returns literal pattern)
    [[ -d "$dir" ]] || continue

    # Get directory name without trailing slash
    dir="${dir%/}"

    # Resolve to real path (follows symlinks)
    real_dir=$(cd "$dir" 2>/dev/null && pwd -P) || {
        echo "WARNING: Cannot resolve path, skipping: $dir" >&2
        continue
    }

    # Verify resolved path is still within context directory
    if [[ "$real_dir" != "$REAL_CONTEXT_DIR"/* ]]; then
        echo "WARNING: Path escapes context directory (possible symlink attack), skipping: $dir" >&2
        continue
    fi

    # Safe to delete - use resolved path
    rm -rf "$real_dir"
done

echo "✓ Context cleaned - ready for next cycle"
echo ""
echo "Next steps:"
echo "  1. Add new context files for your next feature"
echo "  2. Run /plan-and-analyze to start a new development cycle"

if [[ "$NO_ARCHIVE" == "false" ]]; then
  echo ""
  echo "Previous context archived at:"
  echo "  $archive_context_dir"
fi

# =============================================================================
# perf pass-4 (2026-07-05, skill-loop): redundant-I/O elimination —
# get_archive_path read the ledger with TWO sequential jq spawns (active
# cycle id, then that cycle's archive_path) plus a THIRD on the
# most-recent-archived fallback; they collapse into ONE jq pass with the
# same selection logic and rendering (strings raw; non-string ids/paths via
# tojson — the old bash round-trip rendered those through `jq -r` and they
# match nothing / mkdir the same garbage either way; multiple id matches
# join("\n") like the old multi-line capture). Stage errors catch to "" —
# the old `|| true` empty-capture path. Accepted divergence (machine-written
# ledger, out of contract): a cycles array mixing objects with scalars used
# to keep matches printed before jq died mid-stream; now it falls through to
# the next stage. The Try-4 dated fallback uses bash strftime instead of a
# date spawn (same local-time %Y-%m-%d). Early-exit paths (missing dir /
# already clean) are untouched. This note lives at the file tail so source
# line numbers above (surfaced in bash diagnostics like the --prompt
# /dev/tty read error, captured in the pass-1 goldens) stay unchanged.
# =============================================================================
