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

set -euo pipefail

CONTEXT_DIR="${LOA_CONTEXT_DIR:-grimoires/loa/context}"
LEDGER_FILE="${LOA_LEDGER:-grimoires/loa/ledger.json}"
ARCHIVE_BASE="${LOA_ARCHIVE_BASE:-grimoires/loa/archive}"
DRY_RUN=false
VERBOSE=false
NO_ARCHIVE=false

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
    --help|-h)
      echo "Usage: cleanup-context.sh [--dry-run] [--verbose] [--no-archive]"
      echo ""
      echo "Archive and clean discovery context directory for next development cycle."
      echo "Archives context files to the cycle's archive directory, then removes them."
      echo ""
      echo "Options:"
      echo "  --dry-run     Show what would be archived/deleted without doing it"
      echo "  --verbose     Show detailed output"
      echo "  --no-archive  Skip archiving, just delete (not recommended)"
      echo "  --help        Show this help message"
      echo ""
      echo "Archive location: {archive-path}/context/"
      echo "  - Determined from ledger.json active cycle or most recent archive"
      echo "  - Falls back to dated directory if no cycle info available"
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

  # Try 1: Get from active cycle's archive_path in ledger
  if [[ -f "$LEDGER_FILE" ]]; then
    local active_cycle
    active_cycle=$(jq -r '.active_cycle // empty' "$LEDGER_FILE" 2>/dev/null || true)

    if [[ -n "$active_cycle" ]]; then
      archive_path=$(jq -r --arg c "$active_cycle" '
        .cycles[] | select(.id == $c) | .archive_path // empty
      ' "$LEDGER_FILE" 2>/dev/null || true)
    fi

    # Try 2: Get most recent archived cycle's path
    if [[ -z "$archive_path" ]]; then
      archive_path=$(jq -r '
        [.cycles[] | select(.status == "archived" and .archive_path != null)] |
        sort_by(.archived_at) | last | .archive_path // empty
      ' "$LEDGER_FILE" 2>/dev/null || true)
    fi
  fi

  # Try 3: Find most recent archive directory
  if [[ -z "$archive_path" && -d "$ARCHIVE_BASE" ]]; then
    archive_path=$(find "$ARCHIVE_BASE" -maxdepth 1 -type d -name "20*" | sort -r | head -1 || true)
  fi

  # Try 4: Create dated fallback
  if [[ -z "$archive_path" ]]; then
    archive_path="$ARCHIVE_BASE/$(date +%Y-%m-%d)-context-archive"
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

# Remove all subdirectories
find "$CONTEXT_DIR" -mindepth 1 -maxdepth 1 -type d -exec rm -rf {} \;

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
