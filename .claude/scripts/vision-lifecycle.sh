#!/usr/bin/env bash
# =============================================================================
# vision-lifecycle.sh — Vision Registry Lifecycle CLI
# =============================================================================
# Version: 1.0.0
# Part of: Vision Registry Graduation (cycle-069, #486)
#
# Manage vision lifecycle transitions: promote, archive, reject, explore,
# propose, defer. Sources vision-lib.sh for shared functions.
#
# Usage:
#   vision-lifecycle.sh promote <vision-id>
#   vision-lifecycle.sh archive <vision-id> [--reason <text>]
#   vision-lifecycle.sh reject  <vision-id> --reason <text>
#   vision-lifecycle.sh explore <vision-id>
#   vision-lifecycle.sh propose <vision-id>
#   vision-lifecycle.sh defer   <vision-id> [--reason <text>]
#
# Exit codes:
#   0 - Success
#   2 - Invalid arguments
#   4 - I/O error (file not found, permission denied)
#   5 - Invalid transition (terminal state)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/bootstrap.sh"
source "$SCRIPT_DIR/vision-lib.sh"

# =============================================================================
# Configuration
# =============================================================================

VISIONS_DIR="${PROJECT_ROOT}/grimoires/loa/visions"
ENTRIES_DIR="${VISIONS_DIR}/entries"
LIFECYCLE_LOCK="${VISIONS_DIR}/.lifecycle.lock"
TRAJECTORY_DIR=$(get_trajectory_dir 2>/dev/null || echo "${PROJECT_ROOT}/grimoires/loa/a2a/trajectory")

# Terminal states — no transitions out
TERMINAL_STATES="Implemented Archived Rejected"

# =============================================================================
# Helpers
# =============================================================================

_usage() {
  echo "Usage: vision-lifecycle.sh <command> <vision-id> [options]" >&2
  echo "" >&2
  echo "Commands:" >&2
  echo "  promote <id>              Promote to lore + set Implemented" >&2
  echo "  archive <id> [--reason t] Archive vision (optional reason)" >&2
  echo "  reject  <id> --reason t   Reject vision (reason required)" >&2
  echo "  explore <id>              Mark as Exploring" >&2
  echo "  propose <id>              Mark as Proposed" >&2
  echo "  defer   <id> [--reason t] Mark as Deferred (optional reason)" >&2
  exit 2
}

_log_trajectory() {
  local event_type="$1"
  local data="$2"

  (umask 077 && mkdir -p "$TRAJECTORY_DIR")
  local date_str
  date_str=$(date +%Y-%m-%d)
  local log_file="$TRAJECTORY_DIR/vision-lifecycle-$date_str.jsonl"

  local timestamp
  timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  jq -n \
    --arg type "vision_lifecycle" \
    --arg event "$event_type" \
    --arg timestamp "$timestamp" \
    --argjson data "$data" \
    '{type:$type, event:$event, timestamp:$timestamp, data:$data}' >> "$log_file"
}

# Sanitize reason text (Flatline SKP-005)
_sanitize_reason() {
  local text="$1"
  # Strip pipe chars (break markdown tables)
  text="${text//|/-}"
  # Strip newlines (break frontmatter)
  text=$(printf '%s' "$text" | tr '\n' ' ')
  # Strip control characters
  text=$(printf '%s' "$text" | tr -d '\000-\037')
  # Trim whitespace
  text=$(printf '%s' "$text" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  printf '%s' "$text"
}

# Check if a status is terminal
_is_terminal() {
  local status="$1"
  for ts in $TERMINAL_STATES; do
    if [[ "$status" == "$ts" ]]; then
      return 0
    fi
  done
  return 1
}

# Get current vision status from entry file
_get_status() {
  local vid="$1"
  local entry_file="$ENTRIES_DIR/${vid}.md"

  if [[ ! -f "$entry_file" ]]; then
    echo "ERROR: Vision entry not found: $entry_file" >&2
    exit 4
  fi

  grep '^\*\*Status\*\*:' "$entry_file" | head -1 | sed 's/\*\*Status\*\*: *//'
}

# Add a reason field to entry frontmatter
_add_reason_field() {
  local vid="$1"
  local field_name="$2"
  local reason="$3"
  local entry_file="$ENTRIES_DIR/${vid}.md"

  local sanitized
  sanitized=$(_sanitize_reason "$reason")

  # Check if field already exists
  if grep -q "^\*\*${field_name}\*\*:" "$entry_file" 2>/dev/null; then
    # Update existing
    sed "s/^\*\*${field_name}\*\*: .*/**${field_name}**: ${sanitized}/" \
      "$entry_file" > "${entry_file}.tmp" && mv "${entry_file}.tmp" "$entry_file"
  else
    # Insert after Status line
    sed "/^\*\*Status\*\*:/a\\
**${field_name}**: ${sanitized}" \
      "$entry_file" > "${entry_file}.tmp" && mv "${entry_file}.tmp" "$entry_file"
  fi
}

# Rebuild index after lifecycle change
_rebuild_index() {
  "$SCRIPT_DIR/vision-query.sh" --rebuild-index 2>/dev/null || true
}

# Global lifecycle lock (Flatline IMP-001 — flock auto-releases on process death)
_with_lifecycle_lock() {
  mkdir -p "$(dirname "$LIFECYCLE_LOCK")"
  (
    flock -w 10 200 || {
      echo "ERROR: Could not acquire lifecycle lock after 10s" >&2
      exit 4
    }
    "$@"
  ) 200>"$LIFECYCLE_LOCK"
}

# =============================================================================
# Commands
# =============================================================================

_cmd_promote() {
  local vid="$1"

  local current_status
  current_status=$(_get_status "$vid")

  if _is_terminal "$current_status"; then
    echo "ERROR: Cannot promote $vid — already in terminal state: $current_status" >&2
    exit 5
  fi

  echo "Promoting $vid (${current_status} → Implemented)..."

  # Step 1: Generate and append lore entry (idempotent)
  if vision_append_lore_entry "$vid" "$VISIONS_DIR" 2>/dev/null; then
    echo "  Lore entry created"
  else
    echo "  WARNING: Lore append failed (may already exist or lore file missing)" >&2
  fi

  # Step 2: Update status (flock atomic)
  vision_update_status "$vid" "Implemented" "$VISIONS_DIR"
  echo "  Status updated to Implemented"

  # Step 3: Rebuild index (idempotent)
  _rebuild_index
  echo "  Index rebuilt"

  # Step 4: Log trajectory
  _log_trajectory "vision_promoted" "$(jq -n \
    --arg vid "$vid" \
    --arg from "$current_status" \
    '{vision_id:$vid, from_status:$from, to_status:"Implemented"}')"
  echo "  Trajectory logged"

  echo "Done: $vid promoted to Implemented"
}

_cmd_archive() {
  local vid="$1"
  local reason="${2:-}"

  local current_status
  current_status=$(_get_status "$vid")

  if _is_terminal "$current_status"; then
    echo "ERROR: Cannot archive $vid — already in terminal state: $current_status" >&2
    exit 5
  fi

  echo "Archiving $vid (${current_status} → Archived)..."

  # Step 1: Add reason if provided
  if [[ -n "$reason" ]]; then
    _add_reason_field "$vid" "Archived-Reason" "$reason"
    echo "  Reason added: $(_sanitize_reason "$reason")"
  fi

  # Step 2: Update status
  vision_update_status "$vid" "Archived" "$VISIONS_DIR"
  echo "  Status updated to Archived"

  # Step 3: Rebuild index
  _rebuild_index
  echo "  Index rebuilt"

  # Step 4: Log trajectory
  _log_trajectory "vision_archived" "$(jq -n \
    --arg vid "$vid" \
    --arg from "$current_status" \
    --arg reason "$reason" \
    '{vision_id:$vid, from_status:$from, to_status:"Archived", reason:$reason}')"

  echo "Done: $vid archived"
}

_cmd_reject() {
  local vid="$1"
  local reason="$2"

  if [[ -z "$reason" ]]; then
    echo "ERROR: --reason is required for reject" >&2
    exit 2
  fi

  local current_status
  current_status=$(_get_status "$vid")

  if _is_terminal "$current_status"; then
    echo "ERROR: Cannot reject $vid — already in terminal state: $current_status" >&2
    exit 5
  fi

  echo "Rejecting $vid (${current_status} → Rejected)..."

  # Step 1: Add reason
  _add_reason_field "$vid" "Rejected-Reason" "$reason"
  echo "  Reason added: $(_sanitize_reason "$reason")"

  # Step 2: Update status
  vision_update_status "$vid" "Rejected" "$VISIONS_DIR"
  echo "  Status updated to Rejected"

  # Step 3: Rebuild index
  _rebuild_index
  echo "  Index rebuilt"

  # Step 4: Log trajectory
  _log_trajectory "vision_rejected" "$(jq -n \
    --arg vid "$vid" \
    --arg from "$current_status" \
    --arg reason "$reason" \
    '{vision_id:$vid, from_status:$from, to_status:"Rejected", reason:$reason}')"

  echo "Done: $vid rejected"
}

_cmd_simple_transition() {
  local vid="$1"
  local new_status="$2"

  local current_status
  current_status=$(_get_status "$vid")

  if _is_terminal "$current_status"; then
    echo "ERROR: Cannot transition $vid — already in terminal state: $current_status" >&2
    exit 5
  fi

  echo "Transitioning $vid (${current_status} → ${new_status})..."

  vision_update_status "$vid" "$new_status" "$VISIONS_DIR"
  echo "  Status updated to $new_status"

  _rebuild_index
  echo "  Index rebuilt"

  _log_trajectory "vision_transition" "$(jq -n \
    --arg vid "$vid" \
    --arg from "$current_status" \
    --arg to "$new_status" \
    '{vision_id:$vid, from_status:$from, to_status:$to}')"

  echo "Done: $vid → $new_status"
}

_cmd_defer() {
  local vid="$1"
  local reason="${2:-}"

  local current_status
  current_status=$(_get_status "$vid")

  if _is_terminal "$current_status"; then
    echo "ERROR: Cannot defer $vid — already in terminal state: $current_status" >&2
    exit 5
  fi

  echo "Deferring $vid (${current_status} → Deferred)..."

  if [[ -n "$reason" ]]; then
    _add_reason_field "$vid" "Deferred-Reason" "$reason"
    echo "  Reason added: $(_sanitize_reason "$reason")"
  fi

  vision_update_status "$vid" "Deferred" "$VISIONS_DIR"
  echo "  Status updated to Deferred"

  _rebuild_index
  echo "  Index rebuilt"

  _log_trajectory "vision_deferred" "$(jq -n \
    --arg vid "$vid" \
    --arg from "$current_status" \
    --arg reason "$reason" \
    '{vision_id:$vid, from_status:$from, to_status:"Deferred", reason:$reason}')"

  echo "Done: $vid deferred"
}

# =============================================================================
# Main
# =============================================================================

if [[ $# -lt 2 ]]; then
  _usage
fi

COMMAND="$1"
VISION_ID="$2"
shift 2

# Validate vision ID
_vision_validate_id "$VISION_ID" || exit 2

# Parse remaining args
REASON=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --reason)
      [[ -z "${2:-}" ]] && { echo "ERROR: --reason requires a value" >&2; exit 2; }
      REASON="$2"; shift 2 ;;
    *)
      echo "ERROR: Unknown option: $1" >&2; exit 2 ;;
  esac
done

# Execute command under lifecycle lock
case "$COMMAND" in
  promote)
    _with_lifecycle_lock _cmd_promote "$VISION_ID" ;;
  archive)
    _with_lifecycle_lock _cmd_archive "$VISION_ID" "$REASON" ;;
  reject)
    _with_lifecycle_lock _cmd_reject "$VISION_ID" "$REASON" ;;
  explore)
    _with_lifecycle_lock _cmd_simple_transition "$VISION_ID" "Exploring" ;;
  propose)
    _with_lifecycle_lock _cmd_simple_transition "$VISION_ID" "Proposed" ;;
  defer)
    _with_lifecycle_lock _cmd_defer "$VISION_ID" "$REASON" ;;
  *)
    echo "ERROR: Unknown command: $COMMAND" >&2
    _usage ;;
esac
