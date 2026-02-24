#!/usr/bin/env bash
# trajectory-export.sh - Export trajectory JSONL to portable format with redaction
# path-lib: uses
#
# Collects JSONL from trajectory/current/, runs through redact-export.sh (fail-closed),
# builds portable export with schema metadata, compresses by default.
#
# Usage: trajectory-export.sh --cycle CYCLE_ID [OPTIONS]
#   --cycle ID        Required: cycle identifier (e.g., cycle-038)
#   --git-commit      Stage output file for git commit
#   --no-compress     Skip gzip compression
#   --dry-run         Show what would be exported without executing
#   --quiet           Suppress non-error output
#   -h, --help        Show help
#
# Output: .loa-state/trajectory/archive/{cycle_id}.json[.gz]
# Exit codes: 0 = success, 1 = blocked by redaction, 2 = error

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load path-lib for state directory resolution
# shellcheck source=path-lib.sh
source "$SCRIPT_DIR/path-lib.sh" 2>/dev/null || {
  echo "ERROR: Cannot load path-lib.sh" >&2
  exit 2
}

PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
CONFIG_FILE="${PROJECT_ROOT}/.loa.config.yaml"
REDACT_SCRIPT="$SCRIPT_DIR/redact-export.sh"

# === Defaults ===
CYCLE_ID=""
GIT_COMMIT=false
COMPRESS=true
DRY_RUN=false
QUIET=false
MAX_EXPORT_SIZE_MB=50
LFS_WARN_SIZE_MB=5

# Load config
if [[ -f "$CONFIG_FILE" ]] && command -v yq >/dev/null 2>&1; then
  raw_max=$(yq eval '.trajectory.archive.max_export_size_mb // 50' "$CONFIG_FILE" 2>/dev/null || echo "50")
  if [[ "$raw_max" =~ ^[0-9]+$ ]] && [[ "$raw_max" -ge 1 ]] && [[ "$raw_max" -le 500 ]]; then
    MAX_EXPORT_SIZE_MB="$raw_max"
  fi
fi

# === Logging ===
info() { [[ "$QUIET" == "true" ]] || echo "[trajectory-export] $*"; }
warn() { echo "[trajectory-export] WARNING: $*" >&2; }
err()  { echo "[trajectory-export] ERROR: $*" >&2; }

# === Argument Parsing ===
while [[ $# -gt 0 ]]; do
  case $1 in
    --cycle)
      CYCLE_ID="$2"
      shift 2 ;;
    --git-commit)   GIT_COMMIT=true; shift ;;
    --no-compress)  COMPRESS=false; shift ;;
    --dry-run)      DRY_RUN=true; shift ;;
    --quiet)        QUIET=true; shift ;;
    -h|--help)
      sed -n '2,/^$/p' "$0" | sed 's/^# //' | sed 's/^#//'
      exit 0 ;;
    *) warn "Unknown option: $1"; shift ;;
  esac
done

# === Validate ===
if [[ -z "$CYCLE_ID" ]]; then
  err "Missing required --cycle parameter"
  exit 2
fi

# Validate cycle ID format (prevent path traversal)
if [[ ! "$CYCLE_ID" =~ ^[a-zA-Z0-9_-]+$ ]]; then
  err "Invalid cycle ID format: $CYCLE_ID (alphanumeric, hyphens, underscores only)"
  exit 2
fi

if [[ ! -x "$REDACT_SCRIPT" ]]; then
  err "redact-export.sh not found or not executable: $REDACT_SCRIPT"
  exit 2
fi

# === Resolve Directories ===
TRAJ_DIR=$(get_state_trajectory_dir 2>/dev/null) || TRAJ_DIR="${PROJECT_ROOT}/.loa-state/trajectory"
CURRENT_DIR="${TRAJ_DIR}/current"
ARCHIVE_DIR="${TRAJ_DIR}/archive"

if [[ ! -d "$CURRENT_DIR" ]]; then
  err "Trajectory current directory does not exist: $CURRENT_DIR"
  exit 2
fi

# === Collect JSONL Files ===
JSONL_FILES=()
while IFS= read -r -d '' f; do
  JSONL_FILES+=("$f")
done < <(find "$CURRENT_DIR" -maxdepth 1 -name "*.jsonl" -type f -print0 2>/dev/null || true)

if [[ ${#JSONL_FILES[@]} -eq 0 ]]; then
  info "No JSONL files found in $CURRENT_DIR"
  exit 0
fi

info "Found ${#JSONL_FILES[@]} JSONL files"

# === Dry Run ===
if [[ "$DRY_RUN" == "true" ]]; then
  total_bytes=0
  total_entries=0
  for f in "${JSONL_FILES[@]}"; do
    bytes=$(wc -c < "$f")
    entries=$(wc -l < "$f")
    total_bytes=$((total_bytes + bytes))
    total_entries=$((total_entries + entries))
    info "  $(basename "$f"): ${entries} entries, $((bytes / 1024))KB"
  done
  info "Total: ${total_entries} entries, $((total_bytes / 1024))KB"
  info "Would export to: ${ARCHIVE_DIR}/${CYCLE_ID}.json${COMPRESS:+.gz}"
  exit 0
fi

# === Ensure Directories ===
mkdir -p "$ARCHIVE_DIR"

# === Concatenate All JSONL ===
TMPDIR_EXPORT=$(mktemp -d) || { err "Failed to create temp directory"; exit 2; }
cleanup() { rm -rf "$TMPDIR_EXPORT"; }
trap cleanup EXIT

COMBINED="$TMPDIR_EXPORT/combined.jsonl"
> "$COMBINED"

TOTAL_ENTRIES=0
VALID_ENTRIES=0
INVALID_ENTRIES=0
AGENTS=()
PHASES=()
DATE_MIN=""
DATE_MAX=""

for f in "${JSONL_FILES[@]}"; do
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" ]] && continue

    # Validate JSON
    if ! echo "$line" | jq empty 2>/dev/null; then
      INVALID_ENTRIES=$((INVALID_ENTRIES + 1))
      continue
    fi

    TOTAL_ENTRIES=$((TOTAL_ENTRIES + 1))

    # Validate required fields: ts, agent, phase, action
    local_ts=$(echo "$line" | jq -r '.ts // empty' 2>/dev/null)
    local_agent=$(echo "$line" | jq -r '.agent // empty' 2>/dev/null)
    local_phase=$(echo "$line" | jq -r '.phase // empty' 2>/dev/null)
    local_action=$(echo "$line" | jq -r '.action // empty' 2>/dev/null)

    if [[ -z "$local_ts" || -z "$local_agent" || -z "$local_phase" || -z "$local_action" ]]; then
      INVALID_ENTRIES=$((INVALID_ENTRIES + 1))
      warn "Entry missing required fields (ts/agent/phase/action), skipping"
      continue
    fi

    # Track metadata
    VALID_ENTRIES=$((VALID_ENTRIES + 1))
    printf '%s\n' "$line" >> "$COMBINED"

    # Track agents
    found=false
    for a in "${AGENTS[@]+"${AGENTS[@]}"}"; do
      [[ "$a" == "$local_agent" ]] && found=true && break
    done
    [[ "$found" == "false" ]] && AGENTS+=("$local_agent")

    # Track phases
    found=false
    for p in "${PHASES[@]+"${PHASES[@]}"}"; do
      [[ "$p" == "$local_phase" ]] && found=true && break
    done
    [[ "$found" == "false" ]] && PHASES+=("$local_phase")

    # Track date range
    local_date="${local_ts%%T*}"
    if [[ -z "$DATE_MIN" || "$local_date" < "$DATE_MIN" ]]; then
      DATE_MIN="$local_date"
    fi
    if [[ -z "$DATE_MAX" || "$local_date" > "$DATE_MAX" ]]; then
      DATE_MAX="$local_date"
    fi
  done < "$f"
done

if [[ "$VALID_ENTRIES" -eq 0 ]]; then
  info "No valid entries found to export"
  exit 0
fi

info "Entries: ${VALID_ENTRIES} valid, ${INVALID_ENTRIES} invalid"

# === Redaction ===
AUDIT_FILE="$TMPDIR_EXPORT/redaction-audit.json"
REDACTED="$TMPDIR_EXPORT/redacted.jsonl"

COMBINED_SIZE=$(wc -c < "$COMBINED")
MAX_BYTES=$((MAX_EXPORT_SIZE_MB * 1024 * 1024))

# Check if streaming mode needed
if [[ "$COMBINED_SIZE" -gt "$MAX_BYTES" ]]; then
  info "Large export (${COMBINED_SIZE} bytes > ${MAX_EXPORT_SIZE_MB}MB) — using streaming redaction"
  # Process per-entry through redaction
  > "$REDACTED"
  BLOCK_FOUND=false
  while IFS= read -r entry; do
    redacted_entry=$(printf '%s' "$entry" | bash "$REDACT_SCRIPT" --quiet 2>/dev/null) || {
      rc=$?
      if [[ $rc -eq 1 ]]; then
        BLOCK_FOUND=true
        err "BLOCKED: Entry contains secrets, aborting export"
        break
      fi
      # rc=2 (error) — skip this entry
      warn "Redaction error on entry, skipping"
      continue
    }
    printf '%s\n' "$redacted_entry" >> "$REDACTED"
  done < "$COMBINED"

  if [[ "$BLOCK_FOUND" == "true" ]]; then
    exit 1
  fi
else
  # Small export: run entire content through redaction
  local_rc=0
  bash "$REDACT_SCRIPT" --audit-file "$AUDIT_FILE" < "$COMBINED" > "$REDACTED" 2>/dev/null || local_rc=$?
  if [[ "$local_rc" -eq 1 ]]; then
    err "BLOCKED: Trajectory content contains secrets. Export aborted."
    if [[ -f "$AUDIT_FILE" ]]; then
      err "Redaction audit: $(jq -c '.findings' "$AUDIT_FILE" 2>/dev/null || echo 'unavailable')"
    fi
    exit 1
  elif [[ "$local_rc" -ne 0 ]]; then
    err "Redaction pipeline error (exit $local_rc)"
    exit 2
  fi
fi

info "Redaction passed"

# === Build Export ===
EXPORT_FILE="$TMPDIR_EXPORT/export.json"

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EXPORT_ID="traj-export-$(date +%Y%m%d)-$(head -c 6 /dev/urandom | od -An -tx1 | tr -d ' \n')"
SOURCE_REPO=$(git remote get-url origin 2>/dev/null | sed 's|.*[:/]||;s|\.git$||' || echo "unknown")

# Build agents JSON array
AGENTS_JSON="[]"
if [[ ${#AGENTS[@]} -gt 0 ]]; then
  AGENTS_JSON=$(printf '%s\n' "${AGENTS[@]}" | jq -R . | jq -s . 2>/dev/null || echo "[]")
fi

# Build phases JSON array
PHASES_JSON="[]"
if [[ ${#PHASES[@]} -gt 0 ]]; then
  PHASES_JSON=$(printf '%s\n' "${PHASES[@]}" | jq -R . | jq -s . 2>/dev/null || echo "[]")
fi

# Build entries JSON array from redacted JSONL
ENTRIES_JSON=$(jq -s '.' "$REDACTED" 2>/dev/null || echo "[]")

# Build redaction report
REDACTION_REPORT='{}'
if [[ -f "$AUDIT_FILE" ]]; then
  REDACTION_REPORT=$(jq -c '.' "$AUDIT_FILE" 2>/dev/null || echo '{}')
fi

# Assemble export
jq -n \
  --argjson schema_version 1 \
  --arg export_id "$EXPORT_ID" \
  --arg source_repo "$SOURCE_REPO" \
  --arg cycle "$CYCLE_ID" \
  --arg exported_at "$TIMESTAMP" \
  --argjson total_entries "$VALID_ENTRIES" \
  --arg date_min "${DATE_MIN:-unknown}" \
  --arg date_max "${DATE_MAX:-unknown}" \
  --argjson agents "$AGENTS_JSON" \
  --argjson phases "$PHASES_JSON" \
  --argjson file_count "${#JSONL_FILES[@]}" \
  --argjson entries "$ENTRIES_JSON" \
  --argjson redaction_report "$REDACTION_REPORT" \
  '{
    schema_version: $schema_version,
    export_id: $export_id,
    source_repo: $source_repo,
    cycle: $cycle,
    exported_at: $exported_at,
    summary: {
      total_entries: $total_entries,
      date_range: [$date_min, $date_max],
      agents: $agents,
      phases: $phases,
      file_count: $file_count
    },
    entries: $entries,
    redaction_report: $redaction_report
  }' > "$EXPORT_FILE"

# === Output ===
OUTPUT_NAME="${CYCLE_ID}.json"
if [[ "$COMPRESS" == "true" ]]; then
  gzip -6 -c "$EXPORT_FILE" > "${ARCHIVE_DIR}/${OUTPUT_NAME}.gz"
  OUTPUT_PATH="${ARCHIVE_DIR}/${OUTPUT_NAME}.gz"
else
  cp "$EXPORT_FILE" "${ARCHIVE_DIR}/${OUTPUT_NAME}"
  OUTPUT_PATH="${ARCHIVE_DIR}/${OUTPUT_NAME}"
fi

OUTPUT_SIZE=$(wc -c < "$OUTPUT_PATH")
info "Exported to: $OUTPUT_PATH ($((OUTPUT_SIZE / 1024))KB)"

# === Move Processed Files ===
EXPORTED_DIR="${CURRENT_DIR}/exported-${CYCLE_ID}"
mkdir -p "$EXPORTED_DIR"
for f in "${JSONL_FILES[@]}"; do
  mv "$f" "$EXPORTED_DIR/"
done
info "Moved ${#JSONL_FILES[@]} source files to exported-${CYCLE_ID}/"

# === Git Commit (opt-in) ===
if [[ "$GIT_COMMIT" == "true" ]]; then
  OUTPUT_SIZE_MB=$((OUTPUT_SIZE / 1024 / 1024))
  if [[ "$OUTPUT_SIZE_MB" -gt "$LFS_WARN_SIZE_MB" ]]; then
    warn "Export is ${OUTPUT_SIZE_MB}MB — consider using Git LFS for large files"
  fi
  git add "$OUTPUT_PATH" 2>/dev/null || warn "git add failed for $OUTPUT_PATH"
  info "Staged for git commit: $OUTPUT_PATH"
fi

info "Export complete: ${VALID_ENTRIES} entries from ${#JSONL_FILES[@]} files"
