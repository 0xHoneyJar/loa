#!/usr/bin/env bash
# memory-bootstrap.sh - Deterministic observation extraction from 4 structured sources
# path-lib: uses
#
# Extracts observations from trajectory, flatline, feedback, and bridge sources.
# Applies quality gates, stages results, optionally imports through redaction pipeline.
#
# Usage: memory-bootstrap.sh [OPTIONS]
#   --import         Run redaction + merge staged into observations.jsonl
#   --source SOURCE  Bootstrap from single source only (trajectory|flatline|feedback|bridge)
#   --dry-run        Show what would be extracted without writing
#   -h, --help       Show help
#
# Exit codes: 0 = success, 1 = blocked by redaction, 2 = error

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load path-lib
# shellcheck source=path-lib.sh
source "$SCRIPT_DIR/path-lib.sh" 2>/dev/null || {
  echo "ERROR: Cannot load path-lib.sh" >&2
  exit 2
}

PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
REDACT_SCRIPT="$SCRIPT_DIR/redact-export.sh"

# === Defaults ===
IMPORT=false
SOURCE_FILTER=""
DRY_RUN=false
MIN_CONFIDENCE="0.7"
MIN_CONTENT_LENGTH=10
VALID_CATEGORIES=("fact" "decision" "learning" "error" "preference")

# === Logging ===
info() { echo "[memory-bootstrap] $*"; }
warn() { echo "[memory-bootstrap] WARNING: $*" >&2; }
err()  { echo "[memory-bootstrap] ERROR: $*" >&2; }

# === Argument Parsing ===
while [[ $# -gt 0 ]]; do
  case $1 in
    --import)    IMPORT=true; shift ;;
    --source)    SOURCE_FILTER="$2"; shift 2 ;;
    --dry-run)   DRY_RUN=true; shift ;;
    -h|--help)
      sed -n '2,/^$/p' "$0" | sed 's/^# //' | sed 's/^#//'
      exit 0 ;;
    *) warn "Unknown option: $1"; shift ;;
  esac
done

# Validate source filter
if [[ -n "$SOURCE_FILTER" ]]; then
  case "$SOURCE_FILTER" in
    trajectory|flatline|feedback|bridge) ;;
    *) err "Invalid source: $SOURCE_FILTER (must be trajectory|flatline|feedback|bridge)"; exit 2 ;;
  esac
fi

# === Resolve Directories ===
# Prefer env vars (for testing), then path-lib, then defaults
if [[ -n "${LOA_STATE_DIR:-}" ]]; then
  MEMORY_DIR="${LOA_STATE_DIR}/memory"
  TRAJ_DIR="${LOA_STATE_DIR}/trajectory"
  STATE_DIR="$LOA_STATE_DIR"
else
  MEMORY_DIR=$(get_state_memory_dir 2>/dev/null) || MEMORY_DIR="${PROJECT_ROOT}/.loa-state/memory"
  TRAJ_DIR=$(get_state_trajectory_dir 2>/dev/null) || TRAJ_DIR="${PROJECT_ROOT}/.loa-state/trajectory"
  STATE_DIR=$(get_state_dir 2>/dev/null) || STATE_DIR="${PROJECT_ROOT}/.loa-state"
fi
if [[ -n "${LOA_GRIMOIRE_DIR:-}" ]]; then
  GRIMOIRE_DIR="$LOA_GRIMOIRE_DIR"
else
  GRIMOIRE_DIR=$(get_grimoire_dir 2>/dev/null) || GRIMOIRE_DIR="${PROJECT_ROOT}/grimoires/loa"
fi

mkdir -p "$MEMORY_DIR"

STAGED_FILE="$MEMORY_DIR/observations-staged.jsonl"
OBS_FILE="$MEMORY_DIR/observations.jsonl"

# === Tracking ===
declare -A SOURCE_COUNTS
SOURCE_COUNTS=([trajectory]=0 [flatline]=0 [feedback]=0 [bridge]=0)
TOTAL_EXTRACTED=0
TOTAL_REJECTED=0
DEDUP_HASHES=()
SAMPLE_ENTRIES=()

# === Helpers ===

gen_id() {
  local date_part
  date_part=$(date +%Y%m%d)
  local hash_part
  hash_part=$(head -c 6 /dev/urandom | od -An -tx1 | tr -d ' \n')
  echo "MEM-${date_part}-${hash_part}"
}

content_hash() {
  printf '%s' "$1" | md5sum | cut -d' ' -f1
}

is_duplicate() {
  local hash="$1"
  for h in "${DEDUP_HASHES[@]+"${DEDUP_HASHES[@]}"}"; do
    [[ "$h" == "$hash" ]] && return 0
  done
  return 1
}

validate_category() {
  local cat="$1"
  for valid in "${VALID_CATEGORIES[@]}"; do
    [[ "$valid" == "$cat" ]] && return 0
  done
  return 1
}

# Emit a staged observation entry
emit_entry() {
  local source="$1" category="$2" content="$3" confidence="$4"

  # Quality gate: min content length
  if [[ ${#content} -lt $MIN_CONTENT_LENGTH ]]; then
    TOTAL_REJECTED=$((TOTAL_REJECTED + 1))
    return
  fi

  # Quality gate: min confidence
  # LOW-001 FIX: Validate confidence is numeric before awk interpolation
  # to prevent code injection via crafted trajectory entries (e.g., "0.8+system(\"id\")")
  if [[ ! "$confidence" =~ ^[0-9]+\.?[0-9]*$ ]]; then
    TOTAL_REJECTED=$((TOTAL_REJECTED + 1))
    return
  fi
  if ! awk "BEGIN{exit !($confidence >= $MIN_CONFIDENCE)}" 2>/dev/null; then
    TOTAL_REJECTED=$((TOTAL_REJECTED + 1))
    return
  fi

  # Quality gate: valid category
  if ! validate_category "$category"; then
    TOTAL_REJECTED=$((TOTAL_REJECTED + 1))
    return
  fi

  # Quality gate: dedup by content hash
  local hash
  hash=$(content_hash "$content")
  if is_duplicate "$hash"; then
    TOTAL_REJECTED=$((TOTAL_REJECTED + 1))
    return
  fi
  DEDUP_HASHES+=("$hash")

  # Build entry
  local id timestamp
  id=$(gen_id)
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  local entry
  entry=$(jq -cn \
    --arg id "$id" \
    --arg ts "$timestamp" \
    --arg cat "$category" \
    --arg content "$content" \
    --argjson confidence "$confidence" \
    --arg source "$source" \
    --arg hash "$hash" \
    '{id: $id, timestamp: $ts, category: $cat, content: $content, confidence: $confidence, source: $source, content_hash: $hash}' 2>/dev/null) || return

  if [[ "$DRY_RUN" == "false" ]]; then
    printf '%s\n' "$entry" >> "$STAGED_FILE"
  fi

  TOTAL_EXTRACTED=$((TOTAL_EXTRACTED + 1))
  SOURCE_COUNTS[$source]=$((${SOURCE_COUNTS[$source]} + 1))

  # Keep first 3 for sample
  if [[ ${#SAMPLE_ENTRIES[@]} -lt 3 ]]; then
    local truncated="${content:0:70}"
    [[ ${#content} -gt 70 ]] && truncated="${truncated}..."
    SAMPLE_ENTRIES+=("$id [$category] $truncated")
  fi
}

# =============================================================================
# Source 1: Trajectory — phase: "cite" or "learning"
# =============================================================================

extract_trajectory() {
  local traj_current="${TRAJ_DIR}/current"
  [[ -d "$traj_current" ]] || return 0

  local count=0
  while IFS= read -r -d '' f; do
    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ -z "$line" ]] && continue
      echo "$line" | jq empty 2>/dev/null || continue

      local phase
      phase=$(echo "$line" | jq -r '.phase // ""' 2>/dev/null)
      [[ "$phase" == "cite" || "$phase" == "learning" ]] || continue

      local content confidence
      content=$(echo "$line" | jq -r '(.action // .reasoning // "") | .[0:2000]' 2>/dev/null)
      confidence=$(echo "$line" | jq -r '.outcome.confidence // 0.75' 2>/dev/null)

      local category="learning"
      [[ "$phase" == "cite" ]] && category="fact"

      emit_entry "trajectory" "$category" "$content" "$confidence"
      count=$((count + 1))
    done < "$f"
  done < <(find "$traj_current" -maxdepth 1 -name "*.jsonl" -type f -print0 2>/dev/null || true)

  info "Trajectory: scanned, extracted from cite/learning phases"
}

# =============================================================================
# Source 2: Flatline — HIGH_CONSENSUS entries
# =============================================================================

extract_flatline() {
  local flatline_dir="${GRIMOIRE_DIR}/a2a/flatline"
  [[ -d "$flatline_dir" ]] || return 0

  while IFS= read -r -d '' f; do
    [[ -f "$f" ]] || continue
    jq empty "$f" 2>/dev/null || continue

    # Extract high_consensus items
    local items
    items=$(jq -r '.high_consensus[]? | .description // .title // empty' "$f" 2>/dev/null) || continue

    while IFS= read -r item; do
      [[ -z "$item" ]] && continue
      emit_entry "flatline" "decision" "$item" "0.85"
    done <<< "$items"
  done < <(find "$flatline_dir" -name "*-review.json" -type f -print0 2>/dev/null || true)

  info "Flatline: scanned for HIGH_CONSENSUS findings"
}

# =============================================================================
# Source 3: Sprint feedback — structured findings from auditor + engineer
# =============================================================================

extract_feedback() {
  local a2a_dir="${GRIMOIRE_DIR}/a2a"
  [[ -d "$a2a_dir" ]] || return 0

  while IFS= read -r -d '' f; do
    [[ -f "$f" ]] || continue

    # Skip "All good" and "APPROVED" files (no actionable findings)
    local first_line
    first_line=$(head -1 "$f" 2>/dev/null || echo "")
    [[ "$first_line" == "All good"* || "$first_line" == "APPROVED"* ]] && continue

    # Extract lines with ** (bold findings) or ## headers (sections)
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      # Strip markdown formatting
      local clean
      clean=$(echo "$line" | sed 's/^[#*| -]*//' | sed 's/\*//g' | xargs)
      [[ ${#clean} -lt $MIN_CONTENT_LENGTH ]] && continue
      # Skip table dividers and header rows
      [[ "$clean" == *"---"* || "$clean" == "Severity" || "$clean" == "Finding" ]] && continue

      emit_entry "feedback" "error" "$clean" "0.8"
    done < <(grep -E '^\*\*|^##' "$f" 2>/dev/null || true)
  done < <(find "$a2a_dir" -maxdepth 2 \( -name "auditor-*.md" -o -name "engineer-feedback.md" \) -type f -print0 2>/dev/null || true)

  info "Feedback: scanned auditor + engineer findings"
}

# =============================================================================
# Source 4: Bridge findings — CRITICAL + HIGH severity
# =============================================================================

extract_bridge() {
  local bridge_dir="${STATE_DIR}/run/bridge-reviews"
  [[ -d "$bridge_dir" ]] || return 0

  while IFS= read -r -d '' f; do
    [[ -f "$f" ]] || continue
    jq empty "$f" 2>/dev/null || continue

    # Extract findings where severity is CRITICAL or HIGH
    local items
    items=$(jq -r '.findings[]? | select(.severity == "CRITICAL" or .severity == "HIGH") | "\(.title // ""): \(.description // "")"' "$f" 2>/dev/null) || continue

    while IFS= read -r item; do
      [[ -z "$item" || "$item" == ": " ]] && continue
      emit_entry "bridge" "learning" "$item" "0.9"
    done <<< "$items"
  done < <(find "$bridge_dir" -name "*-findings.json" -type f -print0 2>/dev/null || true)

  info "Bridge: scanned for CRITICAL/HIGH findings"
}

# =============================================================================
# Main
# =============================================================================

# Clear staged file
if [[ "$DRY_RUN" == "false" ]]; then
  > "$STAGED_FILE"
fi

# Run extraction
if [[ -z "$SOURCE_FILTER" ]]; then
  extract_trajectory
  extract_flatline
  extract_feedback
  extract_bridge
else
  case "$SOURCE_FILTER" in
    trajectory) extract_trajectory ;;
    flatline)   extract_flatline ;;
    feedback)   extract_feedback ;;
    bridge)     extract_bridge ;;
  esac
fi

# === Report ===
echo ""
echo "Bootstrap complete: $TOTAL_EXTRACTED observations staged"
echo "Sources:"
printf "  %3d  trajectory\n" "${SOURCE_COUNTS[trajectory]}"
printf "  %3d  flatline\n" "${SOURCE_COUNTS[flatline]}"
printf "  %3d  feedback\n" "${SOURCE_COUNTS[feedback]}"
printf "  %3d  bridge\n" "${SOURCE_COUNTS[bridge]}"
echo ""
echo "Rejected: $TOTAL_REJECTED (low confidence, too short, duplicate, or invalid category)"

if [[ ${#SAMPLE_ENTRIES[@]} -gt 0 ]]; then
  echo ""
  echo "Sample entries (first 3):"
  for s in "${SAMPLE_ENTRIES[@]}"; do
    echo "  $s"
  done
fi

if [[ "$DRY_RUN" == "true" ]]; then
  echo ""
  echo "[DRY RUN] No files written."
  exit 0
fi

if [[ "$TOTAL_EXTRACTED" -eq 0 ]]; then
  info "No observations extracted."
  exit 0
fi

# === Import Phase ===
if [[ "$IMPORT" == "true" ]]; then
  echo ""
  info "Running import phase (redaction + merge)..."

  if [[ ! -x "$REDACT_SCRIPT" ]]; then
    err "redact-export.sh not found or not executable"
    exit 2
  fi

  # Run staged content through redaction
  AUDIT_FILE="$MEMORY_DIR/bootstrap-redaction-audit.json"
  REDACTED_FILE="$MEMORY_DIR/observations-redacted.jsonl"

  local_rc=0
  bash "$REDACT_SCRIPT" --audit-file "$AUDIT_FILE" < "$STAGED_FILE" > "$REDACTED_FILE" 2>/dev/null || local_rc=$?
  if [[ "$local_rc" -eq 1 ]]; then
    err "BLOCKED: Staged observations contain secrets. Import aborted."
    if [[ -f "$AUDIT_FILE" ]]; then
      err "Audit: $(jq -c '.findings' "$AUDIT_FILE" 2>/dev/null || echo 'unavailable')"
    fi
    rm -f "$REDACTED_FILE"
    exit 1
  elif [[ "$local_rc" -ne 0 ]]; then
    err "Redaction pipeline error (exit $local_rc)"
    rm -f "$REDACTED_FILE"
    exit 2
  fi

  # Append redacted content to observations.jsonl using append_jsonl
  import_count=0
  while IFS= read -r entry || [[ -n "$entry" ]]; do
    [[ -z "$entry" ]] && continue
    append_jsonl "$OBS_FILE" "$entry" 2>/dev/null || {
      warn "Failed to append entry, falling back to direct write"
      printf '%s\n' "$entry" >> "$OBS_FILE"
    }
    import_count=$((import_count + 1))
  done < "$REDACTED_FILE"

  rm -f "$REDACTED_FILE"
  info "Imported $import_count observations into observations.jsonl"
else
  echo ""
  echo "Run with --import to merge into observations.jsonl"
fi
