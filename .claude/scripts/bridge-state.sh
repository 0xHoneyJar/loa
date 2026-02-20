#!/usr/bin/env bash
# bridge-state.sh - Bridge loop state management
# Version: 2.0.0
#
# Manages the bridge state file (.run/bridge-state.json) with schema
# validation, state transitions, iteration tracking, flatline detection,
# and metrics accumulation.
#
# All read-modify-write operations use atomic updates to prevent
# corruption from concurrent access or interrupted writes.
# Supports flock (Linux) and mkdir-based locking (macOS/POSIX fallback).
#
# Usage:
#   source "$SCRIPT_DIR/bridge-state.sh"
#
# Functions:
#   init_bridge_state       - Create initial state file
#   update_bridge_state     - Transition to new state
#   update_iteration        - Append iteration data
#   read_bridge_state       - Read and validate state file
#   update_flatline         - Track consecutive flatline count
#   update_metrics          - Accumulate totals
#   is_flatlined            - Check flatline termination condition

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/bootstrap.sh"

BRIDGE_STATE_FILE="${PROJECT_ROOT}/.run/bridge-state.json"
BRIDGE_STATE_LOCK="${PROJECT_ROOT}/.run/bridge-state.lock"
BRIDGE_SCHEMA_VERSION=1

# =============================================================================
# Valid State Transitions
# =============================================================================

# Map of valid transitions: from_state -> space-separated to_states
declare -A VALID_TRANSITIONS=(
  ["PREFLIGHT"]="JACK_IN"
  ["JACK_IN"]="ITERATING HALTED"
  ["ITERATING"]="ITERATING RESEARCHING EXPLORING FINALIZING HALTED"
  ["RESEARCHING"]="ITERATING HALTED"
  ["EXPLORING"]="FINALIZING HALTED"
  ["FINALIZING"]="JACKED_OUT HALTED"
  ["HALTED"]="ITERATING RESEARCHING JACKED_OUT"
)

# =============================================================================
# Platform-Aware Locking (FR-1: macOS + Linux)
# =============================================================================

# Detect lock strategy once at source time
if command -v flock &>/dev/null; then
  _LOCK_STRATEGY="flock"
else
  _LOCK_STRATEGY="mkdir"
fi

# Portable modification time (macOS uses -f %m, Linux uses -c %Y)
_portable_mtime() {
  stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0
}

# mkdir-based lock acquisition (POSIX fallback for macOS)
_acquire_lock_mkdir() {
  local lock_dir="${BRIDGE_STATE_LOCK}.d"
  local timeout="${1:-5}"
  local attempts=$(( timeout * 5 ))  # poll every 0.2s
  local elapsed=0

  while ! mkdir "$lock_dir" 2>/dev/null; do
    # Stale lock detection: check if holding PID still exists
    local holder_pid
    holder_pid=$(cat "$lock_dir/pid" 2>/dev/null || echo "")
    if [[ -n "$holder_pid" ]] && ! kill -0 "$holder_pid" 2>/dev/null; then
      echo "WARNING: Removing stale lock (PID $holder_pid no longer running)" >&2
      rm -rf "$lock_dir"
      # Immediately attempt mkdir after cleanup to close TOCTOU window
      if mkdir "$lock_dir" 2>/dev/null; then
        break
      fi
      # Another process grabbed it — fall through to retry loop
    fi

    # Age-based stale detection: lock older than 30s
    if [[ -d "$lock_dir" ]]; then
      local lock_mtime now_epoch lock_age
      lock_mtime=$(_portable_mtime "$lock_dir")
      now_epoch=$(date +%s)
      lock_age=$(( now_epoch - lock_mtime ))
      if (( lock_age > 30 )); then
        echo "WARNING: Removing aged lock (${lock_age}s old)" >&2
        rm -rf "$lock_dir"
        # Immediately attempt mkdir after cleanup to close TOCTOU window
        if mkdir "$lock_dir" 2>/dev/null; then
          break
        fi
        # Another process grabbed it — fall through to retry loop
      fi
    fi

    sleep 0.2
    (( elapsed++ ))
    if (( elapsed >= attempts )); then
      echo "ERROR: Lock acquisition timed out after ${timeout}s" >&2
      return 1
    fi
  done

  # Write our PID atomically for stale detection (write to temp + rename)
  local pid_tmp="$lock_dir/pid.$$"
  echo $$ > "$pid_tmp"
  mv "$pid_tmp" "$lock_dir/pid"
}

_release_lock_mkdir() {
  local lock_dir="${BRIDGE_STATE_LOCK}.d"
  rm -rf "$lock_dir" 2>/dev/null || true
}

# =============================================================================
# Atomic State Update (platform-aware)
# =============================================================================

# Perform an atomic read-modify-write on the bridge state file.
# Uses flock (Linux) or mkdir-based locking (macOS) for mutual exclusion,
# and write-to-temp + mv for crash safety.
#
# Usage:
#   atomic_state_update <jq_filter> [jq_args...]
#
# The jq filter receives the current state and must produce the new state.
# Additional arguments are passed directly to jq (e.g., --arg, --argjson).
atomic_state_update() {
  local jq_filter="$1"
  shift

  if [[ ! -f "$BRIDGE_STATE_FILE" ]]; then
    echo "ERROR: Bridge state file not found: $BRIDGE_STATE_FILE" >&2
    return 1
  fi

  case "$_LOCK_STRATEGY" in
    flock) _atomic_state_update_flock "$jq_filter" "$@" ;;
    mkdir) _atomic_state_update_mkdir "$jq_filter" "$@" ;;
  esac
}

_atomic_state_update_flock() {
  local jq_filter="$1"
  shift

  mkdir -p "$(dirname "$BRIDGE_STATE_LOCK")"

  local lock_fd
  exec {lock_fd}>"$BRIDGE_STATE_LOCK"

  # Acquire lock with 5s timeout; detect stale locks (Flatline SKP-004)
  if ! flock -w 5 "$lock_fd" 2>/dev/null; then
    echo "ERROR: Failed to acquire state lock within 5s — possible stale lock" >&2
    echo "ERROR: Lock file: $BRIDGE_STATE_LOCK" >&2
    # Clean up stale lock and retry once
    rm -f "$BRIDGE_STATE_LOCK"
    exec {lock_fd}>"$BRIDGE_STATE_LOCK"
    if ! flock -w 5 "$lock_fd" 2>/dev/null; then
      echo "ERROR: Still cannot acquire lock after cleanup — aborting" >&2
      return 1
    fi
    echo "WARNING: Recovered from stale lock" >&2
  fi

  # Write to temp file + atomic rename (crash safety)
  local tmp_file="${BRIDGE_STATE_FILE}.tmp.$$"
  if ! jq "$jq_filter" "$@" "$BRIDGE_STATE_FILE" > "$tmp_file" 2>/dev/null; then
    rm -f "$tmp_file"
    eval "exec ${lock_fd}>&-"
    echo "ERROR: jq transformation failed" >&2
    return 1
  fi

  # Atomic rename
  mv "$tmp_file" "$BRIDGE_STATE_FILE"

  # Release lock
  eval "exec ${lock_fd}>&-"
}

_atomic_state_update_mkdir() {
  local jq_filter="$1"
  shift

  mkdir -p "$(dirname "$BRIDGE_STATE_LOCK")"

  # Acquire mkdir-based lock with 5s timeout
  if ! _acquire_lock_mkdir 5; then
    return 1
  fi

  # Write to temp file + atomic rename (crash safety)
  local tmp_file="${BRIDGE_STATE_FILE}.tmp.$$"
  if ! jq "$jq_filter" "$@" "$BRIDGE_STATE_FILE" > "$tmp_file" 2>/dev/null; then
    rm -f "$tmp_file"
    _release_lock_mkdir
    echo "ERROR: jq transformation failed" >&2
    return 1
  fi

  # Atomic rename
  mv "$tmp_file" "$BRIDGE_STATE_FILE"

  # Release lock
  _release_lock_mkdir
}

# =============================================================================
# State Management Functions
# =============================================================================

init_bridge_state() {
  local bridge_id="${1:-}"
  local depth="${2:-3}"
  local per_sprint="${3:-false}"
  local flatline_threshold="${4:-0.05}"
  local branch="${5:-}"
  local repo="${6:-}"

  # Generate bridge_id if not provided
  if [[ -z "$bridge_id" ]]; then
    bridge_id="bridge-$(date +%Y%m%d)-$(openssl rand -hex 3)"
  fi

  # Validate bridge_id format: bridge-YYYYMMDD-hexhex
  if [[ ! "$bridge_id" =~ ^bridge-[0-9]{8}-[a-f0-9]{6}$ ]]; then
    echo "ERROR: Invalid bridge_id format '$bridge_id' (expected bridge-YYYYMMDD-HEXHEX)" >&2
    return 1
  fi

  mkdir -p "$(dirname "$BRIDGE_STATE_FILE")"

  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  jq -n \
    --argjson schema_version "$BRIDGE_SCHEMA_VERSION" \
    --arg bridge_id "$bridge_id" \
    --argjson depth "$depth" \
    --argjson flatline_threshold "$flatline_threshold" \
    --argjson per_sprint "$per_sprint" \
    --arg branch "$branch" \
    --arg repo "$repo" \
    --arg now "$now" \
    '{
      schema_version: $schema_version,
      bridge_id: $bridge_id,
      state: "PREFLIGHT",
      config: {
        depth: $depth,
        mode: "full",
        flatline_threshold: $flatline_threshold,
        per_sprint: $per_sprint,
        branch: $branch,
        repo: $repo
      },
      timestamps: {
        started: $now,
        last_activity: $now
      },
      iterations: [],
      flatline: {
        initial_score: 0,
        last_score: 0,
        consecutive_below_threshold: 0
      },
      metrics: {
        total_sprints_executed: 0,
        total_files_changed: 0,
        total_findings_addressed: 0,
        total_visions_captured: 0
      },
      finalization: {
        ground_truth_updated: false,
        rtfm_passed: false,
        pr_url: null
      }
    }' > "${BRIDGE_STATE_FILE}.tmp.$$"
  mv "${BRIDGE_STATE_FILE}.tmp.$$" "$BRIDGE_STATE_FILE"
  echo "Bridge state initialized: $bridge_id"
}

update_bridge_state() {
  local new_state="$1"

  if [[ ! -f "$BRIDGE_STATE_FILE" ]]; then
    echo "ERROR: Bridge state file not found: $BRIDGE_STATE_FILE" >&2
    return 1
  fi

  local current_state
  current_state=$(jq -r '.state' "$BRIDGE_STATE_FILE")

  # Validate transition
  local valid_targets="${VALID_TRANSITIONS[$current_state]:-}"
  if [[ -z "$valid_targets" ]]; then
    echo "ERROR: No transitions defined from state: $current_state" >&2
    return 1
  fi

  local is_valid=false
  for target in $valid_targets; do
    if [[ "$target" == "$new_state" ]]; then
      is_valid=true
      break
    fi
  done

  if [[ "$is_valid" != "true" ]]; then
    echo "ERROR: Invalid transition: $current_state → $new_state (valid: $valid_targets)" >&2
    return 1
  fi

  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  atomic_state_update \
    '.state = $state | .timestamps.last_activity = $now' \
    --arg state "$new_state" --arg now "$now"
}

update_iteration() {
  local iteration="$1"
  local state="$2"
  local sprint_plan_source="${3:-existing}"

  if [[ ! -f "$BRIDGE_STATE_FILE" ]]; then
    echo "ERROR: Bridge state file not found" >&2
    return 1
  fi

  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Check if iteration already exists
  local existing
  existing=$(jq --argjson iter "$iteration" '.iterations[] | select(.iteration == $iter) | .iteration' "$BRIDGE_STATE_FILE" 2>/dev/null || echo "")

  if [[ -n "$existing" ]]; then
    # Update existing iteration
    atomic_state_update \
      '.iterations |= map(
        if .iteration == $iter then
          .state = $state |
          .updated_at = $now
        else . end
      ) |
      .timestamps.last_activity = $now' \
      --argjson iter "$iteration" --arg state "$state" --arg now "$now"
  else
    # Append new iteration
    atomic_state_update \
      '.iterations += [{
        "iteration": $iter,
        "state": $state,
        "sprint_plan_source": $source,
        "sprints_executed": 0,
        "bridgebuilder": {
          "total_findings": 0,
          "by_severity": {"critical": 0, "high": 0, "medium": 0, "low": 0, "vision": 0, "praise": 0},
          "severity_weighted_score": 0,
          "pr_comment_url": null
        },
        "enrichment": {
          "persona_loaded": false,
          "persona_validation": "pending",
          "findings_format": "unknown",
          "field_fill_rates": {"faang_parallel": 0, "metaphor": 0, "teachable_moment": 0, "connection": 0},
          "praise_count": 0,
          "insights_size_bytes": 0,
          "redactions_applied": 0
        },
        "visions_captured": 0,
        "started_at": $now
      }] |
      .timestamps.last_activity = $now' \
      --argjson iter "$iteration" --arg state "$state" --arg source "$sprint_plan_source" --arg now "$now"
  fi
}

update_iteration_findings() {
  local iteration="$1"
  local findings_json="$2"

  if [[ ! -f "$BRIDGE_STATE_FILE" ]] || [[ ! -f "$findings_json" ]]; then
    echo "ERROR: Missing state file or findings file" >&2
    return 1
  fi

  atomic_state_update \
    '.iterations |= map(
      if .iteration == $iter then
        .bridgebuilder.total_findings = $f[0].total |
        .bridgebuilder.by_severity = $f[0].by_severity |
        .bridgebuilder.severity_weighted_score = $f[0].severity_weighted_score
      else . end
    )' \
    --argjson iter "$iteration" \
    --slurpfile f "$findings_json"
}

update_iteration_enrichment() {
  local iteration="$1"
  local enrichment_json="$2"

  if [[ ! -f "$BRIDGE_STATE_FILE" ]]; then
    echo "ERROR: Bridge state file not found" >&2
    return 1
  fi

  # enrichment_json should contain: persona_loaded, persona_validation,
  # findings_format, field_fill_rates, praise_count, insights_size_bytes,
  # redactions_applied
  atomic_state_update \
    '.iterations |= map(
      if .iteration == $iter then
        .enrichment = $enrich
      else . end
    )' \
    --argjson iter "$iteration" --argjson enrich "$enrichment_json"
}

read_bridge_state() {
  if [[ ! -f "$BRIDGE_STATE_FILE" ]]; then
    echo "ERROR: Bridge state file not found: $BRIDGE_STATE_FILE" >&2
    return 1
  fi

  # Validate schema version
  local schema_version
  schema_version=$(jq -r '.schema_version // 0' "$BRIDGE_STATE_FILE")
  if [[ "$schema_version" -ne "$BRIDGE_SCHEMA_VERSION" ]]; then
    echo "ERROR: Schema version mismatch (expected $BRIDGE_SCHEMA_VERSION, got $schema_version)" >&2
    return 1
  fi

  # Return the full state
  jq '.' "$BRIDGE_STATE_FILE"
}

update_flatline() {
  local current_score="$1"
  local iteration="$2"

  if [[ ! -f "$BRIDGE_STATE_FILE" ]]; then
    echo "ERROR: Bridge state file not found" >&2
    return 1
  fi

  local initial_score
  initial_score=$(jq '.flatline.initial_score' "$BRIDGE_STATE_FILE")
  local threshold
  threshold=$(jq '.config.flatline_threshold' "$BRIDGE_STATE_FILE")

  # Set initial score on first iteration
  if [[ "$iteration" -eq 1 ]]; then
    atomic_state_update \
      '.flatline.initial_score = $score |
       .flatline.last_score = $score |
       .flatline.consecutive_below_threshold = 0' \
      --argjson score "$current_score"
    return
  fi

  # Check if below threshold
  local is_below
  if [[ "$initial_score" == "0" ]] || [[ "$initial_score" == "0.0" ]]; then
    # No findings initially → immediate flatline
    is_below="true"
  else
    is_below=$(echo "$current_score $initial_score $threshold" | awk '{
      if ($2 == 0) print "true"
      else if ($1 / $2 < $3) print "true"
      else print "false"
    }')
  fi

  if [[ "$is_below" == "true" ]]; then
    atomic_state_update \
      '.flatline.last_score = $score |
       .flatline.consecutive_below_threshold += 1' \
      --argjson score "$current_score"
  else
    atomic_state_update \
      '.flatline.last_score = $score |
       .flatline.consecutive_below_threshold = 0' \
      --argjson score "$current_score"
  fi
}

is_flatlined() {
  local consecutive_required="${1:-2}"

  if [[ ! -f "$BRIDGE_STATE_FILE" ]]; then
    echo "false"
    return
  fi

  local consecutive
  consecutive=$(jq '.flatline.consecutive_below_threshold' "$BRIDGE_STATE_FILE")

  if [[ "$consecutive" -ge "$consecutive_required" ]]; then
    echo "true"
  else
    echo "false"
  fi
}

update_metrics() {
  local sprints="${1:-0}"
  local files="${2:-0}"
  local findings="${3:-0}"
  local visions="${4:-0}"

  if [[ ! -f "$BRIDGE_STATE_FILE" ]]; then
    echo "ERROR: Bridge state file not found" >&2
    return 1
  fi

  atomic_state_update \
    '.metrics.total_sprints_executed += $s |
     .metrics.total_files_changed += $f |
     .metrics.total_findings_addressed += $fi |
     .metrics.total_visions_captured += $v' \
    --argjson s "$sprints" --argjson f "$files" --argjson fi "$findings" --argjson v "$visions"
}

get_bridge_id() {
  if [[ -f "$BRIDGE_STATE_FILE" ]]; then
    jq -r '.bridge_id' "$BRIDGE_STATE_FILE"
  else
    echo ""
  fi
}

get_bridge_state() {
  if [[ -f "$BRIDGE_STATE_FILE" ]]; then
    jq -r '.state' "$BRIDGE_STATE_FILE"
  else
    echo "none"
  fi
}

get_current_iteration() {
  if [[ -f "$BRIDGE_STATE_FILE" ]]; then
    jq '.iterations | length' "$BRIDGE_STATE_FILE"
  else
    echo "0"
  fi
}
