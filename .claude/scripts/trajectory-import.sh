#!/usr/bin/env bash
# trajectory-import.sh - Import exported trajectory files
# path-lib: uses
#
# Accepts .json or .json.gz trajectory export files, validates schema,
# extracts entries into trajectory/current/.
#
# Usage: trajectory-import.sh FILE.json[.gz]
#   Exit codes: 0 = success, 1 = validation error, 2 = error

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load path-lib
# shellcheck source=path-lib.sh
source "$SCRIPT_DIR/path-lib.sh" 2>/dev/null || {
  echo "ERROR: Cannot load path-lib.sh" >&2
  exit 2
}

# === Logging ===
info() { echo "[trajectory-import] $*"; }
err()  { echo "[trajectory-import] ERROR: $*" >&2; }

# === Argument Parsing ===
if [[ $# -lt 1 || "$1" == "-h" || "$1" == "--help" ]]; then
  echo "Usage: trajectory-import.sh FILE.json[.gz]"
  echo ""
  echo "Import exported trajectory files into trajectory/current/."
  echo "Validates schema_version: 1 before importing."
  echo ""
  echo "Exit codes: 0=success, 1=validation error, 2=error"
  exit 0
fi

INPUT_FILE="$1"

if [[ ! -f "$INPUT_FILE" ]]; then
  err "File not found: $INPUT_FILE"
  exit 2
fi

# === Resolve Directories ===
TRAJ_DIR=$(get_state_trajectory_dir 2>/dev/null) || {
  PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
  TRAJ_DIR="${PROJECT_ROOT}/.loa-state/trajectory"
}
CURRENT_DIR="${TRAJ_DIR}/current"
mkdir -p "$CURRENT_DIR"

# === Decompress if needed ===
TMPFILE=$(mktemp) || { err "Failed to create temp file"; exit 2; }
cleanup() { rm -f "$TMPFILE"; }
trap cleanup EXIT

if [[ "$INPUT_FILE" == *.gz ]]; then
  if ! gzip -d -c "$INPUT_FILE" > "$TMPFILE" 2>/dev/null; then
    err "Failed to decompress: $INPUT_FILE"
    exit 2
  fi
else
  cp "$INPUT_FILE" "$TMPFILE"
fi

# === Validate JSON ===
if ! jq empty "$TMPFILE" 2>/dev/null; then
  err "Invalid JSON in: $INPUT_FILE"
  exit 1
fi

# === Validate Schema Version ===
SCHEMA_VER=$(jq -r '.schema_version // empty' "$TMPFILE" 2>/dev/null)
if [[ "$SCHEMA_VER" != "1" ]]; then
  err "Unsupported schema_version: ${SCHEMA_VER:-missing} (expected: 1)"
  exit 1
fi

# === Extract Metadata ===
CYCLE=$(jq -r '.cycle // "unknown"' "$TMPFILE" 2>/dev/null)
EXPORT_ID=$(jq -r '.export_id // "unknown"' "$TMPFILE" 2>/dev/null)
ENTRY_COUNT=$(jq '.entries | length' "$TMPFILE" 2>/dev/null || echo "0")

info "Importing: $INPUT_FILE"
info "  Export ID: $EXPORT_ID"
info "  Cycle: $CYCLE"
info "  Entries: $ENTRY_COUNT"

if [[ "$ENTRY_COUNT" -eq 0 ]]; then
  info "No entries to import"
  exit 0
fi

# === Extract Entries ===
DATE_STAMP=$(date +%Y%m%d)
OUTPUT_FILE="${CURRENT_DIR}/imported-${CYCLE}-${DATE_STAMP}.jsonl"

# Extract entries as JSONL
jq -c '.entries[]' "$TMPFILE" > "$OUTPUT_FILE" 2>/dev/null || {
  err "Failed to extract entries"
  exit 2
}

IMPORTED=$(wc -l < "$OUTPUT_FILE")
info "Imported $IMPORTED entries to: $(basename "$OUTPUT_FILE")"
