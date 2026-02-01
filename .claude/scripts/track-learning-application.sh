#!/bin/bash
# =============================================================================
# track-learning-application.sh - Learning Application Tracker
# =============================================================================
# Sprint 10: Track when learnings are applied during implementation
# Goal Contribution: G-4 (Close apply-verify loop)
#
# Usage:
#   ./track-learning-application.sh --skill ID --task CONTEXT [options]
#
# Options:
#   --skill ID           Skill ID being applied
#   --task CONTEXT       Task context (e.g., sprint-4-task-2)
#   --type TYPE          Application type: explicit|implicit|prompted
#   --confidence N       Confidence score 0-1 (default: 0.9 for explicit)
#   --code-location LOC  Code location where applied
#   --help               Show this help
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TRAJECTORY_DIR="${PROJECT_ROOT}/grimoires/loa/a2a/trajectory"
LEARNINGS_FILE="${PROJECT_ROOT}/grimoires/loa/a2a/compound/learnings.json"

SKILL_ID=""
TASK_CONTEXT=""
APP_TYPE="explicit"
CONFIDENCE=""
CODE_LOCATION=""

usage() {
  sed -n '/^# Usage:/,/^# =====/p' "$0" | grep -v "^# =====" | sed 's/^# //'
  exit 0
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --skill) SKILL_ID="$2"; shift 2 ;;
      --task) TASK_CONTEXT="$2"; shift 2 ;;
      --type) APP_TYPE="$2"; shift 2 ;;
      --confidence) CONFIDENCE="$2"; shift 2 ;;
      --code-location) CODE_LOCATION="$2"; shift 2 ;;
      --help|-h) usage ;;
      *) shift ;;
    esac
  done
}

get_default_confidence() {
  case "$APP_TYPE" in
    explicit) echo "0.9" ;;
    prompted) echo "0.8" ;;
    implicit) echo "0.5" ;;
    *) echo "0.5" ;;
  esac
}

init_learnings_file() {
  if [[ ! -f "$LEARNINGS_FILE" ]]; then
    mkdir -p "$(dirname "$LEARNINGS_FILE")"
    cat > "$LEARNINGS_FILE" << 'EOF'
{
  "version": "1.0",
  "last_updated": null,
  "learnings": []
}
EOF
  fi
}

log_application_event() {
  local today timestamp log_file
  today=$(date -u +%Y-%m-%d)
  timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  log_file="${TRAJECTORY_DIR}/compound-learning-${today}.jsonl"
  
  local conf
  conf=${CONFIDENCE:-$(get_default_confidence)}
  
  local event
  event=$(jq -n \
    --arg ts "$timestamp" \
    --arg skill "$SKILL_ID" \
    --arg task "$TASK_CONTEXT" \
    --arg type "$APP_TYPE" \
    --argjson conf "$conf" \
    --arg loc "${CODE_LOCATION:-}" \
    '{
      timestamp: $ts,
      type: "learning_applied",
      agent: "application-tracker",
      skill_id: $skill,
      task_context: $task,
      application_type: $type,
      confidence: $conf,
      code_location: (if $loc != "" then $loc else null end)
    }')
  
  echo "$event" >> "$log_file"
  echo "[INFO] Logged learning_applied event for $SKILL_ID"
}

update_learnings_registry() {
  init_learnings_file
  
  local timestamp
  timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  
  local conf
  conf=${CONFIDENCE:-$(get_default_confidence)}
  
  # Check if learning exists
  local exists
  exists=$(jq --arg id "$SKILL_ID" '.learnings | map(select(.id == $id)) | length > 0' "$LEARNINGS_FILE")
  
  if [[ "$exists" == "true" ]]; then
    # Update existing learning
    jq --arg id "$SKILL_ID" \
       --arg ts "$timestamp" \
       --arg task "$TASK_CONTEXT" \
       --arg type "$APP_TYPE" \
       --argjson conf "$conf" \
       '
       .last_updated = $ts |
       .learnings |= map(
         if .id == $id then
           .applications += [{
             timestamp: $ts,
             task_id: $task,
             type: $type,
             confidence: $conf
           }] |
           .retrieval_count += 1 |
           .last_retrieved = $ts
         else
           .
         end
       )
       ' "$LEARNINGS_FILE" > "${LEARNINGS_FILE}.tmp"
    mv "${LEARNINGS_FILE}.tmp" "$LEARNINGS_FILE"
  else
    # Create new learning entry
    jq --arg id "$SKILL_ID" \
       --arg ts "$timestamp" \
       --arg task "$TASK_CONTEXT" \
       --arg type "$APP_TYPE" \
       --argjson conf "$conf" \
       '
       .last_updated = $ts |
       .learnings += [{
         id: $id,
         source: "tracking",
         created: $ts,
         effectiveness_score: 50,
         applications: [{
           timestamp: $ts,
           task_id: $task,
           type: $type,
           confidence: $conf
         }],
         retrieval_count: 1,
         last_retrieved: $ts
       }]
       ' "$LEARNINGS_FILE" > "${LEARNINGS_FILE}.tmp"
    mv "${LEARNINGS_FILE}.tmp" "$LEARNINGS_FILE"
  fi
  
  echo "[INFO] Updated learnings registry"
}

main() {
  parse_args "$@"
  
  if [[ -z "$SKILL_ID" || -z "$TASK_CONTEXT" ]]; then
    echo "[ERROR] --skill and --task are required" >&2
    usage
  fi
  
  mkdir -p "$TRAJECTORY_DIR"
  log_application_event
  update_learnings_registry
}

main "$@"
