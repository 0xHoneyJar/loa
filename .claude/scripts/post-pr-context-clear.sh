#!/usr/bin/env bash
# post-pr-context-clear.sh - Context Clear for Post-PR Validation Loop
# Part of Loa Framework v1.25.0
#
# Prepares for fresh-eyes E2E testing by:
# 1. Writing checkpoint to NOTES.md Session Continuity
# 2. Logging to trajectory JSONL
# 3. Preserving state for resume
# 4. Displaying /clear instructions
#
# Usage:
#   post-pr-context-clear.sh [--notes-file <path>] [--trajectory-dir <path>]
#
# Exit codes:
#   0 - Success
#   1 - Error

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly STATE_SCRIPT="${SCRIPT_DIR}/post-pr-state.sh"

# Default paths (can be overridden by .loa.config.yaml)
NOTES_FILE="${NOTES_FILE:-grimoires/loa/NOTES.md}"
TRAJECTORY_DIR="${TRAJECTORY_DIR:-grimoires/loa/a2a/trajectory}"

# ============================================================================
# Utility Functions
# ============================================================================

log_info() {
  echo "[INFO] $*" >&2
}

log_error() {
  echo "[ERROR] $*" >&2
}

timestamp() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# Load config values if available
load_config() {
  if command -v yq &>/dev/null && [[ -f ".loa.config.yaml" ]]; then
    local notes
    notes=$(yq '.memory.notes_file // ""' .loa.config.yaml 2>/dev/null || echo "")
    if [[ -n "$notes" ]]; then
      NOTES_FILE="$notes"
    fi

    local traj
    traj=$(yq '.memory.trajectory_dir // ""' .loa.config.yaml 2>/dev/null || echo "")
    if [[ -n "$traj" ]]; then
      TRAJECTORY_DIR="$traj"
    fi
  fi
}

# ============================================================================
# Checkpoint Functions
# ============================================================================

# Write checkpoint to NOTES.md Session Continuity section
write_notes_checkpoint() {
  local post_pr_id="$1"
  local pr_url="$2"
  local pr_number="$3"
  local current_state="$4"

  if [[ ! -f "$NOTES_FILE" ]]; then
    log_info "Creating NOTES.md"
    mkdir -p "$(dirname "$NOTES_FILE")"
    cat > "$NOTES_FILE" << 'EOF'
# Session Notes

## Session Continuity

<!-- Checkpoints for session recovery -->

## Decision Log

<!-- Key decisions made during this session -->

## Learnings

<!-- Insights discovered during implementation -->
EOF
  fi

  local checkpoint_content
  checkpoint_content=$(cat << EOF

### Post-PR Validation Checkpoint
- **ID:** ${post_pr_id}
- **PR:** [#${pr_number}](${pr_url})
- **State:** ${current_state}
- **Timestamp:** $(timestamp)
- **Next Phase:** E2E_TESTING
- **Resume:** Run \`/clear\` then \`/simstim --resume\` or \`post-pr-orchestrator.sh --resume --pr-url ${pr_url}\`
EOF
)

  # Check if Session Continuity section exists
  if grep -q "## Session Continuity" "$NOTES_FILE"; then
    # Insert after the section header
    local temp_file
    temp_file=$(mktemp)

    awk -v checkpoint="$checkpoint_content" '
      /^## Session Continuity/ {
        print
        getline
        print
        print checkpoint
        next
      }
      { print }
    ' "$NOTES_FILE" > "$temp_file"

    mv "$temp_file" "$NOTES_FILE"
  else
    # Append section
    cat >> "$NOTES_FILE" << EOF

## Session Continuity

$checkpoint_content
EOF
  fi

  log_info "Checkpoint written to $NOTES_FILE"
}

# Write trajectory entry
write_trajectory_entry() {
  local post_pr_id="$1"
  local pr_url="$2"
  local current_state="$3"

  mkdir -p "$TRAJECTORY_DIR"

  local trajectory_file="${TRAJECTORY_DIR}/post-pr-$(date +%Y%m%d).jsonl"

  local entry
  entry=$(jq -n \
    --arg id "$post_pr_id" \
    --arg pr "$pr_url" \
    --arg state "$current_state" \
    --arg ts "$(timestamp)" \
    --arg event "context_clear" \
    '{
      timestamp: $ts,
      event: $event,
      post_pr_id: $id,
      pr_url: $pr,
      state: $state,
      phase: "CONTEXT_CLEAR",
      action: "checkpoint_written",
      message: "Context clear checkpoint - ready for /clear and resume"
    }')

  echo "$entry" >> "$trajectory_file"

  log_info "Trajectory entry written to $trajectory_file"
}

# Display context clear instructions
display_instructions() {
  local pr_url="$1"

  cat << EOF

==========================================
       CONTEXT CLEAR CHECKPOINT
==========================================

Your progress has been saved. To continue with fresh-eyes E2E testing:

  1. Run:  /clear
  2. Then: /simstim --resume
     OR:   post-pr-orchestrator.sh --resume --pr-url ${pr_url}

The next phase (E2E_TESTING) will run with fresh context,
simulating a new reviewer looking at your changes.

State preserved in:
  - .run/post-pr-state.json
  - ${NOTES_FILE} (Session Continuity)
  - ${TRAJECTORY_DIR}/

==========================================

EOF
}

# ============================================================================
# Main
# ============================================================================

main() {
  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --notes-file)
        NOTES_FILE="$2"
        shift 2
        ;;
      --trajectory-dir)
        TRAJECTORY_DIR="$2"
        shift 2
        ;;
      --help|-h)
        echo "Usage: post-pr-context-clear.sh [--notes-file <path>] [--trajectory-dir <path>]"
        exit 0
        ;;
      *)
        log_error "Unknown option: $1"
        exit 1
        ;;
    esac
  done

  # Load config
  load_config

  # Get state information
  if [[ ! -x "$STATE_SCRIPT" ]]; then
    log_error "State script not found: $STATE_SCRIPT"
    exit 1
  fi

  local post_pr_id pr_url pr_number current_state

  post_pr_id=$("$STATE_SCRIPT" get post_pr_id 2>/dev/null || echo "unknown")
  pr_url=$("$STATE_SCRIPT" get pr_url 2>/dev/null || echo "")
  pr_number=$("$STATE_SCRIPT" get pr_number 2>/dev/null || echo "0")
  current_state=$("$STATE_SCRIPT" get state 2>/dev/null || echo "CONTEXT_CLEAR")

  if [[ -z "$pr_url" ]]; then
    log_error "Could not get PR URL from state"
    exit 1
  fi

  log_info "Writing context clear checkpoint..."

  # 1. Write NOTES.md checkpoint
  write_notes_checkpoint "$post_pr_id" "$pr_url" "$pr_number" "$current_state"

  # 2. Write trajectory entry
  write_trajectory_entry "$post_pr_id" "$pr_url" "$current_state"

  # 3. State is already preserved by the orchestrator

  # 4. Display instructions
  display_instructions "$pr_url"

  log_info "Context clear complete"
  exit 0
}

main "$@"
