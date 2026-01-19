#!/usr/bin/env bash
# cleanup-context.sh - Clean discovery context directory for next development cycle
# Part of Run Mode v0.18.0+
#
# Usage:
#   cleanup-context.sh [--dry-run] [--verbose]
#
# Called automatically by /run sprint-plan on successful completion.
# Can also be called manually before starting a new /plan-and-analyze cycle.

set -euo pipefail

CONTEXT_DIR="${LOA_CONTEXT_DIR:-grimoires/loa/context}"
DRY_RUN=false
VERBOSE=false

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
    --help|-h)
      echo "Usage: cleanup-context.sh [--dry-run] [--verbose]"
      echo ""
      echo "Clean discovery context directory for next development cycle."
      echo "Removes all files and subdirectories except README.md."
      echo ""
      echo "Options:"
      echo "  --dry-run   Show what would be deleted without deleting"
      echo "  --verbose   Show detailed output"
      echo "  --help      Show this help message"
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

echo "Context Cleanup"
echo "───────────────────────────────────────"
echo "Directory: $CONTEXT_DIR"
echo "Files to remove: $file_count"
echo "Directories to remove: $dir_count"
echo ""

if [[ "$VERBOSE" == "true" || "$DRY_RUN" == "true" ]]; then
  echo "Items to be cleaned:"

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
  echo "[DRY RUN] No files deleted"
  exit 0
fi

# Perform cleanup
# Remove all files except README.md
find "$CONTEXT_DIR" -maxdepth 1 -type f ! -name "README.md" -delete

# Remove all subdirectories
find "$CONTEXT_DIR" -mindepth 1 -maxdepth 1 -type d -exec rm -rf {} \;

echo "✓ Context cleaned - ready for next cycle"
echo ""
echo "Next steps:"
echo "  1. Add new context files for your next feature"
echo "  2. Run /plan-and-analyze to start a new development cycle"
