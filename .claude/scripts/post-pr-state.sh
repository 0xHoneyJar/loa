#!/usr/bin/env bash
# post-pr-state.sh - State management for Post-PR Validation Loop
# Part of Loa Framework v1.25.0
#
# Usage:
#   post-pr-state.sh init --pr-url <url> [--pr-number <n>] [--branch <name>] [--mode <mode>]
#   post-pr-state.sh get <field>              # Supports dot notation: phases.post_pr_audit
#   post-pr-state.sh update-phase <phase> <status>
#   post-pr-state.sh set <field> <value>
#   post-pr-state.sh cleanup
#
# Exit codes:
#   0 - Success
#   1 - Invalid arguments
#   2 - State file not found
#   3 - Lock acquisition failed
#   4 - Validation failed

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

# Resolve STATE_DIR to absolute path
_state_dir="${STATE_DIR:-.run}"
if [[ "$_state_dir" != /* ]]; then
  _state_dir="$(pwd)/$_state_dir"
fi
readonly STATE_DIR="$_state_dir"
readonly STATE_FILE="${STATE_DIR}/post-pr-state.json"
readonly LOCK_DIR="${STATE_DIR}/.post-pr-lock"
readonly BACKUP_DIR="${STATE_DIR}/backups"
readonly LOCK_TIMEOUT="${LOCK_TIMEOUT:-30}"
readonly LOCK_STALE_SECONDS="${LOCK_STALE_SECONDS:-300}"

# Schema version
readonly SCHEMA_VERSION=1

# Valid states
readonly VALID_STATES=(
  "PR_CREATED"
  "POST_PR_AUDIT"
  "FIX_AUDIT"
  "CONTEXT_CLEAR"
  "E2E_TESTING"
  "FIX_E2E"
  "FLATLINE_PR"
  "READY_FOR_HITL"
  "HALTED"
)

# Valid phase statuses
readonly VALID_PHASE_STATUSES=("pending" "in_progress" "completed" "skipped")

# ============================================================================
# Utility Functions
# ============================================================================

log_info() {
  echo "[INFO] $*" >&2
}

log_error() {
  echo "[ERROR] $*" >&2
}

log_debug() {
  if [[ "${DEBUG:-}" == "true" ]]; then
    echo "[DEBUG] $*" >&2
  fi
}

# Generate post-PR ID in format: post-pr-YYYYMMDD-xxxxxxxx
generate_id() {
  local date_part
  date_part=$(date +%Y%m%d)
  local random_part
  # Use multiple fallbacks for hex generation
  if command -v xxd &>/dev/null; then
    random_part=$(head -c 4 /dev/urandom | xxd -p)
  elif command -v od &>/dev/null; then
    random_part=$(head -c 4 /dev/urandom | od -An -tx1 | tr -d ' \n')
  else
    # Fallback using $RANDOM
    random_part=$(printf '%08x' "$((RANDOM * RANDOM))")
  fi
  echo "post-pr-${date_part}-${random_part}"
}

# Get current ISO 8601 timestamp
timestamp() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# ============================================================================
# Locking (Atomic mkdir + PID)
# ============================================================================

acquire_lock() {
  local timeout="${1:-$LOCK_TIMEOUT}"
  local start_time
  start_time=$(date +%s)

  while true; do
    # Try atomic mkdir
    if mkdir "$LOCK_DIR" 2>/dev/null; then
      # Write PID for staleness detection
      echo $$ > "${LOCK_DIR}/pid"
      log_debug "Lock acquired (PID: $$)"
      return 0
    fi

    # Check for stale lock
    if [[ -f "${LOCK_DIR}/pid" ]]; then
      local lock_pid
      lock_pid=$(cat "${LOCK_DIR}/pid" 2>/dev/null || echo "")

      if [[ -n "$lock_pid" ]]; then
        # Check if process is still running
        if ! kill -0 "$lock_pid" 2>/dev/null; then
          log_info "Removing stale lock (dead PID: $lock_pid)"
          rm -rf "$LOCK_DIR"
          continue
        fi

        # Check for staleness by time
        local lock_mtime
        lock_mtime=$(stat -c %Y "${LOCK_DIR}/pid" 2>/dev/null || stat -f %m "${LOCK_DIR}/pid" 2>/dev/null || echo "0")
        local current_time
        current_time=$(date +%s)

        if (( current_time - lock_mtime > LOCK_STALE_SECONDS )); then
          log_info "Removing stale lock (expired after ${LOCK_STALE_SECONDS}s)"
          rm -rf "$LOCK_DIR"
          continue
        fi
      fi
    fi

    # Check timeout
    local current_time
    current_time=$(date +%s)
    if (( current_time - start_time > timeout )); then
      log_error "Lock acquisition timed out after ${timeout}s"
      return 3
    fi

    log_debug "Lock held, waiting..."
    sleep 0.5
  done
}

release_lock() {
  if [[ -d "$LOCK_DIR" ]]; then
    rm -rf "$LOCK_DIR"
    log_debug "Lock released"
  fi
}

# Ensure lock is released on exit
cleanup_on_exit() {
  release_lock
}

# ============================================================================
# Backup Management
# ============================================================================

create_backup() {
  if [[ ! -f "$STATE_FILE" ]]; then
    return 0
  fi

  mkdir -p "$BACKUP_DIR"
  local backup_file="${BACKUP_DIR}/post-pr-state.$(date +%Y%m%d-%H%M%S).json"
  cp "$STATE_FILE" "$backup_file"
  chmod 600 "$backup_file"
  log_debug "Backup created: $backup_file"

  # Keep only last 10 backups
  local count
  count=$(find "$BACKUP_DIR" -name "post-pr-state.*.json" 2>/dev/null | wc -l)
  if (( count > 10 )); then
    find "$BACKUP_DIR" -name "post-pr-state.*.json" -type f | \
      sort | head -n $((count - 10)) | xargs rm -f
  fi
}

# ============================================================================
# Validation
# ============================================================================

validate_state() {
  local state="$1"
  for valid in "${VALID_STATES[@]}"; do
    if [[ "$state" == "$valid" ]]; then
      return 0
    fi
  done
  return 1
}

validate_phase_status() {
  local status="$1"
  for valid in "${VALID_PHASE_STATUSES[@]}"; do
    if [[ "$status" == "$valid" ]]; then
      return 0
    fi
  done
  return 1
}

validate_pr_url() {
  local url="$1"
  if [[ "$url" =~ ^https://github\.com/[^/]+/[^/]+/pull/[0-9]+$ ]]; then
    return 0
  fi
  return 1
}

validate_id_format() {
  local id="$1"
  if [[ "$id" =~ ^post-pr-[0-9]{8}-[a-f0-9]{8}$ ]]; then
    return 0
  fi
  return 1
}

# Validate entire state file against schema
validate_state_file() {
  local file="$1"

  if [[ ! -f "$file" ]]; then
    log_error "State file not found: $file"
    return 2
  fi

  # Check required fields
  local required_fields=("post_pr_id" "schema_version" "state" "pr_url" "pr_number" "branch" "phases" "timestamps")
  for field in "${required_fields[@]}"; do
    if ! jq -e ".$field" "$file" >/dev/null 2>&1; then
      log_error "Missing required field: $field"
      return 4
    fi
  done

  # Validate ID format
  local id
  id=$(jq -r '.post_pr_id' "$file")
  if ! validate_id_format "$id"; then
    log_error "Invalid post_pr_id format: $id"
    return 4
  fi

  # Validate schema version
  local version
  version=$(jq -r '.schema_version' "$file")
  if [[ "$version" != "$SCHEMA_VERSION" ]]; then
    log_error "Unsupported schema version: $version (expected: $SCHEMA_VERSION)"
    return 4
  fi

  # Validate state
  local state
  state=$(jq -r '.state' "$file")
  if ! validate_state "$state"; then
    log_error "Invalid state: $state"
    return 4
  fi

  return 0
}

# ============================================================================
# Commands
# ============================================================================

cmd_init() {
  local pr_url=""
  local pr_number=""
  local branch=""
  local mode="autonomous"

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --pr-url)
        pr_url="$2"
        shift 2
        ;;
      --pr-number)
        pr_number="$2"
        shift 2
        ;;
      --branch)
        branch="$2"
        shift 2
        ;;
      --mode)
        mode="$2"
        shift 2
        ;;
      *)
        log_error "Unknown option: $1"
        return 1
        ;;
    esac
  done

  # Validate required arguments
  if [[ -z "$pr_url" ]]; then
    log_error "Missing required argument: --pr-url"
    return 1
  fi

  if ! validate_pr_url "$pr_url"; then
    log_error "Invalid PR URL format: $pr_url"
    return 1
  fi

  # Extract PR number from URL if not provided
  if [[ -z "$pr_number" ]]; then
    pr_number=$(echo "$pr_url" | grep -oE '[0-9]+$')
  fi

  # Get branch name if not provided
  if [[ -z "$branch" ]]; then
    branch=$(git branch --show-current 2>/dev/null || echo "unknown")
  fi

  # Validate mode
  if [[ "$mode" != "autonomous" && "$mode" != "hitl" ]]; then
    log_error "Invalid mode: $mode (must be 'autonomous' or 'hitl')"
    return 1
  fi

  # Acquire lock
  acquire_lock || return $?
  trap cleanup_on_exit EXIT

  # Create state directory
  mkdir -p "$STATE_DIR"

  # Generate ID
  local post_pr_id
  post_pr_id=$(generate_id)

  # Create state file
  local ts
  ts=$(timestamp)

  cat > "$STATE_FILE" << EOF
{
  "post_pr_id": "${post_pr_id}",
  "schema_version": ${SCHEMA_VERSION},
  "state": "PR_CREATED",
  "pr_url": "${pr_url}",
  "pr_number": ${pr_number},
  "branch": "${branch}",
  "mode": "${mode}",
  "phases": {
    "post_pr_audit": "pending",
    "context_clear": "pending",
    "e2e_testing": "pending",
    "flatline_pr": "pending"
  },
  "audit": {
    "iteration": 0,
    "max_iterations": 5,
    "findings": [],
    "finding_identities": []
  },
  "e2e": {
    "iteration": 0,
    "max_iterations": 3,
    "failures": [],
    "failure_identities": []
  },
  "timestamps": {
    "started": "${ts}",
    "last_activity": "${ts}"
  },
  "markers": []
}
EOF

  chmod 600 "$STATE_FILE"

  # Validate created file
  if ! validate_state_file "$STATE_FILE"; then
    log_error "State file validation failed after creation"
    rm -f "$STATE_FILE"
    return 4
  fi

  log_info "State initialized: $post_pr_id"
  echo "$post_pr_id"
}

cmd_get() {
  local field="${1:-}"

  if [[ -z "$field" ]]; then
    # Return entire state
    if [[ -f "$STATE_FILE" ]]; then
      cat "$STATE_FILE"
    else
      log_error "State file not found"
      return 2
    fi
    return 0
  fi

  if [[ ! -f "$STATE_FILE" ]]; then
    log_error "State file not found"
    return 2
  fi

  # Support dot notation (e.g., phases.post_pr_audit)
  local jq_path=".$field"
  jq_path=$(echo "$jq_path" | sed 's/\././g')

  local value
  value=$(jq -r "$jq_path" "$STATE_FILE" 2>/dev/null)

  if [[ "$value" == "null" ]]; then
    log_error "Field not found: $field"
    return 1
  fi

  echo "$value"
}

cmd_set() {
  local field="${1:-}"
  local value="${2:-}"

  if [[ -z "$field" ]] || [[ -z "$value" ]]; then
    log_error "Usage: post-pr-state.sh set <field> <value>"
    return 1
  fi

  if [[ ! -f "$STATE_FILE" ]]; then
    log_error "State file not found"
    return 2
  fi

  # Acquire lock
  acquire_lock || return $?
  trap cleanup_on_exit EXIT

  # Create backup
  create_backup

  # Update field (H-2 fix: use --arg for safe value injection)
  local jq_path=".$field"
  local ts
  ts=$(timestamp)

  # Use jq --arg for safe string interpolation (prevents jq injection)
  # Determine if value is a number or boolean for proper JSON typing
  if [[ "$value" =~ ^-?[0-9]+$ ]]; then
    # Numeric value - use --argjson for proper JSON number
    jq --argjson val "$value" --arg ts "$ts" "$jq_path = \$val | .timestamps.last_activity = \$ts" "$STATE_FILE" > "${STATE_FILE}.tmp"
  elif [[ "$value" == "true" ]] || [[ "$value" == "false" ]]; then
    # Boolean value - use --argjson for proper JSON boolean
    jq --argjson val "$value" --arg ts "$ts" "$jq_path = \$val | .timestamps.last_activity = \$ts" "$STATE_FILE" > "${STATE_FILE}.tmp"
  else
    # String value - use --arg for safe string injection
    jq --arg val "$value" --arg ts "$ts" "$jq_path = \$val | .timestamps.last_activity = \$ts" "$STATE_FILE" > "${STATE_FILE}.tmp"
  fi
  mv "${STATE_FILE}.tmp" "$STATE_FILE"
  chmod 600 "$STATE_FILE"

  log_debug "Set $field = $value"
}

cmd_update_phase() {
  local phase="${1:-}"
  local status="${2:-}"

  if [[ -z "$phase" ]] || [[ -z "$status" ]]; then
    log_error "Usage: post-pr-state.sh update-phase <phase> <status>"
    return 1
  fi

  # Validate phase name
  local valid_phases=("post_pr_audit" "context_clear" "e2e_testing" "flatline_pr")
  local phase_valid=false
  for p in "${valid_phases[@]}"; do
    if [[ "$phase" == "$p" ]]; then
      phase_valid=true
      break
    fi
  done

  if [[ "$phase_valid" != "true" ]]; then
    log_error "Invalid phase: $phase"
    return 1
  fi

  # Validate status
  if ! validate_phase_status "$status"; then
    log_error "Invalid status: $status"
    return 1
  fi

  if [[ ! -f "$STATE_FILE" ]]; then
    log_error "State file not found"
    return 2
  fi

  # Acquire lock
  acquire_lock || return $?
  trap cleanup_on_exit EXIT

  # Create backup
  create_backup

  # Update phase status atomically
  local ts
  ts=$(timestamp)

  jq ".phases.${phase} = \"${status}\" | .timestamps.last_activity = \"$ts\"" "$STATE_FILE" > "${STATE_FILE}.tmp"
  mv "${STATE_FILE}.tmp" "$STATE_FILE"
  chmod 600 "$STATE_FILE"

  log_info "Phase $phase updated to: $status"
}

cmd_cleanup() {
  # Acquire lock
  acquire_lock || return $?
  trap cleanup_on_exit EXIT

  # Remove state file
  if [[ -f "$STATE_FILE" ]]; then
    rm -f "$STATE_FILE"
    log_info "State file removed"
  fi

  # Remove marker files
  rm -f "${STATE_DIR}/.PR-AUDITED"
  rm -f "${STATE_DIR}/.PR-E2E-PASSED"
  rm -f "${STATE_DIR}/.PR-VALIDATED"

  # Remove backups
  if [[ -d "$BACKUP_DIR" ]]; then
    rm -rf "$BACKUP_DIR"
    log_info "Backups removed"
  fi

  log_info "Cleanup complete"
}

cmd_validate() {
  if [[ ! -f "$STATE_FILE" ]]; then
    log_error "State file not found"
    return 2
  fi

  if validate_state_file "$STATE_FILE"; then
    log_info "State file is valid"
    return 0
  else
    return $?
  fi
}

cmd_add_marker() {
  local marker="${1:-}"

  if [[ -z "$marker" ]]; then
    log_error "Usage: post-pr-state.sh add-marker <marker-name>"
    return 1
  fi

  if [[ ! -f "$STATE_FILE" ]]; then
    log_error "State file not found"
    return 2
  fi

  # Acquire lock
  acquire_lock || return $?
  trap cleanup_on_exit EXIT

  # Create backup
  create_backup

  # Create marker file
  local marker_file="${STATE_DIR}/.${marker}"
  local ts
  ts=$(timestamp)

  cat > "$marker_file" << EOF
{
  "marker": "${marker}",
  "created": "${ts}",
  "post_pr_id": "$(jq -r '.post_pr_id' "$STATE_FILE")"
}
EOF
  chmod 600 "$marker_file"

  # Update state file markers array
  jq ".markers += [\"${marker}\"] | .timestamps.last_activity = \"$ts\"" "$STATE_FILE" > "${STATE_FILE}.tmp"
  mv "${STATE_FILE}.tmp" "$STATE_FILE"
  chmod 600 "$STATE_FILE"

  log_info "Marker created: $marker"
}

# ============================================================================
# Main
# ============================================================================

main() {
  local cmd="${1:-}"

  if [[ -z "$cmd" ]]; then
    echo "Usage: post-pr-state.sh <command> [args...]"
    echo ""
    echo "Commands:"
    echo "  init          Initialize state file"
    echo "  get           Get state field (supports dot notation)"
    echo "  set           Set state field"
    echo "  update-phase  Update phase status"
    echo "  add-marker    Create marker file"
    echo "  validate      Validate state file"
    echo "  cleanup       Remove state files"
    return 1
  fi

  shift

  case "$cmd" in
    init)
      cmd_init "$@"
      ;;
    get)
      cmd_get "$@"
      ;;
    set)
      cmd_set "$@"
      ;;
    update-phase)
      cmd_update_phase "$@"
      ;;
    add-marker)
      cmd_add_marker "$@"
      ;;
    validate)
      cmd_validate
      ;;
    cleanup)
      cmd_cleanup
      ;;
    *)
      log_error "Unknown command: $cmd"
      return 1
      ;;
  esac
}

main "$@"
