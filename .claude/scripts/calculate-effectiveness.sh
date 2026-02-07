#!/bin/bash
# =============================================================================
# calculate-effectiveness.sh - Effectiveness Score Calculator
# =============================================================================
# Sprint 11: Calculate effectiveness scores for applied learnings
# Goal Contribution: G-4 (Close apply-verify loop)
#
# Usage:
#   ./calculate-effectiveness.sh --learning ID [options]
#   ./calculate-effectiveness.sh --all
#
# Options:
#   --learning ID        Calculate for specific learning
#   --all                Calculate for all learnings
#   --task ID            Add feedback for specific task
#   --signal SIGNAL      Feedback signal (task_completed|no_errors|etc)
#   --value N            Signal value (1 or -1)
#   --output FORMAT      Output format: json|summary
#   --help               Show this help
#
# Feedback Signals (from PRD):
#   task_completed    (+3)  Task marked complete
#   no_errors         (+2)  No errors during task
#   no_revert         (+2)  No revert within 24h
#   faster_completion (+1)  Faster than median
#   user_positive     (+3)  Positive user feedback
#   user_negative     (-5)  Negative user feedback
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Require bash 4.0+ (associative arrays)
# shellcheck source=bash-version-guard.sh
source "$SCRIPT_DIR/bash-version-guard.sh"

LEARNINGS_FILE="${PROJECT_ROOT}/grimoires/loa/a2a/compound/learnings.json"
TRAJECTORY_DIR="${PROJECT_ROOT}/grimoires/loa/a2a/trajectory"

LEARNING_ID=""
CALCULATE_ALL=false
TASK_ID=""
SIGNAL=""
SIGNAL_VALUE=""
OUTPUT_FORMAT="json"

# Signal weights from PRD
declare -A SIGNAL_WEIGHTS=(
  ["task_completed"]=3
  ["no_errors"]=2
  ["no_revert"]=2
  ["faster_completion"]=1
  ["user_positive"]=3
  ["user_negative"]=-5
)

usage() {
  sed -n '/^# Usage:/,/^# =====/p' "$0" | grep -v "^# =====" | sed 's/^# //'
  exit 0
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --learning) LEARNING_ID="$2"; shift 2 ;;
      --all) CALCULATE_ALL=true; shift ;;
      --task) TASK_ID="$2"; shift 2 ;;
      --signal) SIGNAL="$2"; shift 2 ;;
      --value) SIGNAL_VALUE="$2"; shift 2 ;;
      --output) OUTPUT_FORMAT="$2"; shift 2 ;;
      --help|-h) usage ;;
      *) shift ;;
    esac
  done
}

init_learnings_file() {
  if [[ ! -f "$LEARNINGS_FILE" ]]; then
    mkdir -p "$(dirname "$LEARNINGS_FILE")"
    echo '{"version":"1.0","learnings":[]}' > "$LEARNINGS_FILE"
  fi
}

add_feedback_signal() {
  if [[ -z "$LEARNING_ID" || -z "$TASK_ID" || -z "$SIGNAL" ]]; then
    return
  fi
  
  local weight=${SIGNAL_WEIGHTS[$SIGNAL]:-0}
  local value=${SIGNAL_VALUE:-1}
  local score=$((weight * value))
  
  local timestamp
  timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  
  # Update learning with feedback signal
  jq --arg id "$LEARNING_ID" \
     --arg task "$TASK_ID" \
     --arg sig "$SIGNAL" \
     --argjson score "$score" \
     --arg ts "$timestamp" \
     '
     .learnings |= map(
       if .id == $id then
         .applications |= map(
           if .task_id == $task then
             .feedback_signals = (.feedback_signals // {}) + {($sig): $score}
           else
             .
           end
         )
       else
         .
       end
     )
     ' "$LEARNINGS_FILE" > "${LEARNINGS_FILE}.tmp"
  mv "${LEARNINGS_FILE}.tmp" "$LEARNINGS_FILE"
  
  echo "[INFO] Added signal $SIGNAL ($score) for $LEARNING_ID"
}

calculate_single() {
  local learning_id="$1"
  
  local learning
  learning=$(jq --arg id "$learning_id" '.learnings[] | select(.id == $id)' "$LEARNINGS_FILE")
  
  if [[ -z "$learning" || "$learning" == "null" ]]; then
    echo '{"id":"'"$learning_id"'","error":"not found"}'
    return
  fi
  
  # Calculate effectiveness from applications
  local total_score=0
  local app_count=0
  
  # Sum all feedback signals
  local signals
  signals=$(echo "$learning" | jq -c '.applications[]?.feedback_signals // {}' 2>/dev/null || echo "{}")
  
  if [[ -n "$signals" ]]; then
    while IFS= read -r sig_obj; do
      [[ -z "$sig_obj" || "$sig_obj" == "{}" ]] && continue
      local sig_sum
      sig_sum=$(echo "$sig_obj" | jq 'to_entries | map(.value) | add // 0')
      total_score=$((total_score + sig_sum))
      app_count=$((app_count + 1))
    done <<< "$signals"
  fi
  
  # Normalize to 0-100
  local max_possible=$((app_count * 11))  # Max positive signals per app
  local effectiveness=50  # Default
  
  if [[ "$app_count" -gt 0 && "$max_possible" -gt 0 ]]; then
    effectiveness=$(awk "BEGIN {printf \"%.0f\", ($total_score / $max_possible) * 100}")
    [[ "$effectiveness" -lt 0 ]] && effectiveness=0
    [[ "$effectiveness" -gt 100 ]] && effectiveness=100
  fi
  
  # Determine tier
  local tier
  if [[ "$effectiveness" -ge 80 ]]; then
    tier="high"
  elif [[ "$effectiveness" -ge 50 ]]; then
    tier="medium"
  elif [[ "$effectiveness" -ge 20 ]]; then
    tier="low"
  else
    tier="ineffective"
  fi
  
  jq -n \
    --arg id "$learning_id" \
    --argjson score "$effectiveness" \
    --arg tier "$tier" \
    --argjson apps "$app_count" \
    --argjson raw "$total_score" \
    '{
      id: $id,
      effectiveness_score: $score,
      tier: $tier,
      applications_count: $apps,
      raw_score: $raw
    }'
}

update_effectiveness_score() {
  local learning_id="$1"
  local result
  result=$(calculate_single "$learning_id")
  
  local score
  score=$(echo "$result" | jq '.effectiveness_score')
  
  jq --arg id "$learning_id" \
     --argjson score "$score" \
     '
     .learnings |= map(
       if .id == $id then
         .effectiveness_score = $score
       else
         .
       end
     )
     ' "$LEARNINGS_FILE" > "${LEARNINGS_FILE}.tmp"
  mv "${LEARNINGS_FILE}.tmp" "$LEARNINGS_FILE"
}

log_verification_event() {
  local learning_id="$1"
  local result="$2"
  
  local today timestamp log_file
  today=$(date -u +%Y-%m-%d)
  timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  log_file="${TRAJECTORY_DIR}/compound-learning-${today}.jsonl"
  
  local event
  event=$(jq -n \
    --arg ts "$timestamp" \
    --arg id "$learning_id" \
    --argjson result "$result" \
    '{
      timestamp: $ts,
      type: "learning_verified",
      agent: "effectiveness-calculator",
      learning_id: $id,
      effectiveness: $result
    }')
  
  echo "$event" >> "$log_file"
}

calculate_all() {
  init_learnings_file
  
  local results=()
  local ids
  ids=$(jq -r '.learnings[].id' "$LEARNINGS_FILE" 2>/dev/null || echo "")
  
  if [[ -z "$ids" ]]; then
    echo "[]"
    return
  fi
  
  while IFS= read -r id; do
    [[ -z "$id" ]] && continue
    local result
    result=$(calculate_single "$id")
    update_effectiveness_score "$id"
    log_verification_event "$id" "$result"
    results+=("$result")
  done <<< "$ids"
  
  printf '%s\n' "${results[@]}" | jq -s '.'
}

main() {
  parse_args "$@"
  init_learnings_file
  
  mkdir -p "$TRAJECTORY_DIR"
  
  # Add feedback signal if provided
  if [[ -n "$SIGNAL" ]]; then
    add_feedback_signal
  fi
  
  # Calculate effectiveness
  if [[ "$CALCULATE_ALL" == "true" ]]; then
    calculate_all
  elif [[ -n "$LEARNING_ID" ]]; then
    local result
    result=$(calculate_single "$LEARNING_ID")
    update_effectiveness_score "$LEARNING_ID"
    log_verification_event "$LEARNING_ID" "$result"
    echo "$result"
  fi
}

main "$@"
