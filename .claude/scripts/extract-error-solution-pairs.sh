#!/bin/bash
# =============================================================================
# extract-error-solution-pairs.sh - Extract Error-Solution Pairs from Trajectory
# =============================================================================
# Sprint 3, Task 3.3: Extract error-solution pairs from trajectory events
# Goal Contribution: G-1 (Cross-session pattern detection)
#
# Usage:
#   ./extract-error-solution-pairs.sh [options]
#
# Options:
#   --days N         Analyze last N days (default: 7)
#   --start DATE     Start date (YYYY-MM-DD)
#   --end DATE       End date (YYYY-MM-DD)
#   --max-gap N      Max events between error and solution (default: 10)
#   --output FORMAT  Output format: json (default), jsonl, summary
#   --help           Show this help
#
# Output (JSON):
#   [{
#     "error": { ... },
#     "solution": { ... },
#     "session_date": "2025-01-30",
#     "gap_events": 3,
#     "confidence": 0.8
#   }]
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Parameters
DAYS=7
START_DATE=""
END_DATE=""
MAX_GAP=10
OUTPUT_FORMAT="json"

# Error patterns (action or type containing these)
ERROR_PATTERNS=(
  "error"
  "fail"
  "exception"
  "crash"
  "timeout"
  "refused"
  "denied"
  "invalid"
  "missing"
  "not_found"
  "broken"
)

# Solution patterns
SOLUTION_PATTERNS=(
  "fix"
  "resolve"
  "solution"
  "workaround"
  "success"
  "complete"
  "working"
  "corrected"
  "updated"
  "patched"
)

# Usage
usage() {
  sed -n '/^# Usage:/,/^# =====/p' "$0" | grep -v "^# =====" | sed 's/^# //'
  exit 0
}

# Parse arguments
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --days)
        DAYS="$2"
        shift 2
        ;;
      --start)
        START_DATE="$2"
        shift 2
        ;;
      --end)
        END_DATE="$2"
        shift 2
        ;;
      --max-gap)
        MAX_GAP="$2"
        shift 2
        ;;
      --output)
        OUTPUT_FORMAT="$2"
        shift 2
        ;;
      --help|-h)
        usage
        ;;
      *)
        echo "[ERROR] Unknown option: $1" >&2
        exit 1
        ;;
    esac
  done
}

# Build reader args
build_reader_args() {
  local args=""
  
  if [[ -n "$START_DATE" ]]; then
    args+=" --start $START_DATE"
  fi
  
  if [[ -n "$END_DATE" ]]; then
    args+=" --end $END_DATE"
  fi
  
  if [[ -z "$START_DATE" && -z "$END_DATE" ]]; then
    args+=" --days $DAYS"
  fi
  
  echo "$args"
}

# Check if event is an error
is_error_event() {
  local event="$1"
  local action
  local event_type
  local details
  
  action=$(echo "$event" | jq -r '.action // ""' | tr '[:upper:]' '[:lower:]')
  event_type=$(echo "$event" | jq -r '.type // ""' | tr '[:upper:]' '[:lower:]')
  details=$(echo "$event" | jq -r '.details // .error // .message // ""' | tr '[:upper:]' '[:lower:]')
  
  for pattern in "${ERROR_PATTERNS[@]}"; do
    if [[ "$action" == *"$pattern"* ]] || \
       [[ "$event_type" == *"$pattern"* ]] || \
       [[ "$details" == *"$pattern"* ]]; then
      return 0
    fi
  done
  
  return 1
}

# Check if event is a solution
is_solution_event() {
  local event="$1"
  local action
  local event_type
  local details
  
  action=$(echo "$event" | jq -r '.action // ""' | tr '[:upper:]' '[:lower:]')
  event_type=$(echo "$event" | jq -r '.type // ""' | tr '[:upper:]' '[:lower:]')
  details=$(echo "$event" | jq -r '.details // .solution // .message // ""' | tr '[:upper:]' '[:lower:]')
  
  for pattern in "${SOLUTION_PATTERNS[@]}"; do
    if [[ "$action" == *"$pattern"* ]] || \
       [[ "$event_type" == *"$pattern"* ]] || \
       [[ "$details" == *"$pattern"* ]]; then
      return 0
    fi
  done
  
  return 1
}

# Calculate confidence score for a pair
calculate_confidence() {
  local gap="$1"
  local error_keywords="$2"
  local solution_keywords="$3"
  
  # Base confidence on gap (closer = higher confidence)
  local gap_factor
  gap_factor=$(awk "BEGIN {printf \"%.2f\", 1.0 - ($gap / ($MAX_GAP * 2))}")
  
  # Check if solution mentions error context
  local context_match=0
  if [[ -n "$error_keywords" && -n "$solution_keywords" ]]; then
    # Simple keyword overlap check
    local overlap
    overlap=$("$SCRIPT_DIR/jaccard-similarity.sh" \
      --set-a "$error_keywords" \
      --set-b "$solution_keywords" 2>/dev/null || echo "0.0")
    
    if (( $(echo "$overlap > 0.1" | bc -l 2>/dev/null || echo "0") )); then
      context_match=1
    fi
  fi
  
  # Calculate final confidence
  local confidence
  if [[ "$context_match" -eq 1 ]]; then
    confidence=$(awk "BEGIN {printf \"%.2f\", $gap_factor * 1.2}")
  else
    confidence="$gap_factor"
  fi
  
  # Clamp to 0-1
  if (( $(echo "$confidence > 1.0" | bc -l 2>/dev/null || echo "0") )); then
    confidence="1.0"
  fi
  
  echo "$confidence"
}

# Extract error keywords
extract_error_keywords() {
  local event="$1"
  local text
  text=$(echo "$event" | jq -r '[.error, .details, .message, .action] | map(select(. != null)) | join(" ")')
  
  if [[ -n "$text" && -x "$SCRIPT_DIR/extract-keywords.sh" ]]; then
    echo "$text" | "$SCRIPT_DIR/extract-keywords.sh" --technical 2>/dev/null | tr '\n' ',' | sed 's/,$//'
  fi
}

# Extract solution keywords
extract_solution_keywords() {
  local event="$1"
  local text
  text=$(echo "$event" | jq -r '[.solution, .details, .message, .action] | map(select(. != null)) | join(" ")')
  
  if [[ -n "$text" && -x "$SCRIPT_DIR/extract-keywords.sh" ]]; then
    echo "$text" | "$SCRIPT_DIR/extract-keywords.sh" --technical 2>/dev/null | tr '\n' ',' | sed 's/,$//'
  fi
}

# Get session date from event
get_session_date() {
  local event="$1"
  local timestamp
  timestamp=$(echo "$event" | jq -r '.timestamp // ""')
  
  if [[ -n "$timestamp" ]]; then
    echo "$timestamp" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1
  fi
}

# Main extraction
extract_pairs() {
  local reader="${SCRIPT_DIR}/trajectory-reader.sh"
  local reader_args
  reader_args=$(build_reader_args)
  
  if [[ ! -x "$reader" ]]; then
    echo "[ERROR] trajectory-reader.sh not found" >&2
    exit 1
  fi
  
  # Get all events
  local events_file=$(mktemp) || { echo "[]"; return; }
  chmod 600 "$events_file"  # CRITICAL-001 FIX
  # shellcheck disable=SC2086
  "$reader" $reader_args --format jsonl 2>/dev/null > "$events_file" || true
  
  local event_count
  event_count=$(wc -l < "$events_file" | tr -d ' ')
  
  if [[ "$event_count" -eq 0 ]]; then
    rm -f "$events_file"
    echo "[]"
    return
  fi
  
  # Find error-solution pairs
  local pairs=()
  local line_num=0
  local pending_errors=()
  
  while IFS= read -r event; do
    line_num=$((line_num + 1))
    
    # Skip empty lines
    [[ -z "$event" ]] && continue
    
    # Check for error event
    if is_error_event "$event"; then
      pending_errors+=("$line_num:$event")
    fi
    
    # Check for solution event
    if is_solution_event "$event"; then
      # Try to match with pending errors
      local matched=false
      
      for i in "${!pending_errors[@]}"; do
        local error_entry="${pending_errors[$i]}"
        local error_line="${error_entry%%:*}"
        local error_event="${error_entry#*:}"
        local gap=$((line_num - error_line))
        
        if [[ "$gap" -le "$MAX_GAP" ]]; then
          # Found a potential pair
          local session_date
          session_date=$(get_session_date "$error_event")
          
          local error_keywords
          local solution_keywords
          error_keywords=$(extract_error_keywords "$error_event")
          solution_keywords=$(extract_solution_keywords "$event")
          
          local confidence
          confidence=$(calculate_confidence "$gap" "$error_keywords" "$solution_keywords")
          
          # Create pair JSON
          local pair
          pair=$(jq -n \
            --argjson error "$error_event" \
            --argjson solution "$event" \
            --arg session "$session_date" \
            --argjson gap "$gap" \
            --argjson conf "$confidence" \
            --arg err_kw "$error_keywords" \
            --arg sol_kw "$solution_keywords" \
            '{
              error: $error,
              solution: $solution,
              session_date: $session,
              gap_events: $gap,
              confidence: $conf,
              error_keywords: ($err_kw | split(",") | map(select(length > 0))),
              solution_keywords: ($sol_kw | split(",") | map(select(length > 0)))
            }')
          
          pairs+=("$pair")
          
          # Remove matched error
          unset 'pending_errors[$i]'
          matched=true
          break
        fi
      done
      
      # Cleanup old pending errors
      local new_pending=()
      for entry in "${pending_errors[@]}"; do
        local err_line="${entry%%:*}"
        local age=$((line_num - err_line))
        if [[ "$age" -le "$MAX_GAP" ]]; then
          new_pending+=("$entry")
        fi
      done
      pending_errors=("${new_pending[@]}")
    fi
  done < "$events_file"
  
  rm -f "$events_file"
  
  # Output
  case "$OUTPUT_FORMAT" in
    json)
      printf '%s\n' "${pairs[@]}" | jq -s '.'
      ;;
    jsonl)
      printf '%s\n' "${pairs[@]}"
      ;;
    summary)
      local count=${#pairs[@]}
      echo "Found $count error-solution pairs"
      if [[ "$count" -gt 0 ]]; then
        printf '%s\n' "${pairs[@]}" | jq -s '
          {
            total_pairs: length,
            avg_confidence: (map(.confidence) | add / length),
            sessions: (map(.session_date) | unique),
            top_error_keywords: (map(.error_keywords) | flatten | group_by(.) | map({key: .[0], count: length}) | sort_by(-.count) | .[0:5])
          }
        '
      fi
      ;;
  esac
}

# Main
main() {
  parse_args "$@"
  extract_pairs
}

main "$@"
