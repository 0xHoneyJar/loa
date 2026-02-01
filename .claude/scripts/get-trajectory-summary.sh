#!/bin/bash
# =============================================================================
# get-trajectory-summary.sh - Trajectory Summary Utility
# =============================================================================
# Sprint 2, Task 2.5: Quick summary statistics for trajectory analysis
# Goal Contribution: G-1 (Cross-session pattern detection)
#
# Usage:
#   ./get-trajectory-summary.sh [options]
#
# Options:
#   --days N         Analyze last N days (default: 7)
#   --start DATE     Start date (YYYY-MM-DD)
#   --end DATE       End date (YYYY-MM-DD)
#   --detailed       Include event samples in output
#   --help           Show this help
#
# Output (JSON):
#   {
#     "total_events": 150,
#     "total_files": 5,
#     "date_range": { "start": "2025-01-23", "end": "2025-01-30" },
#     "events_by_agent": { "implementing-tasks": 80, "architect": 30 },
#     "events_by_type": { "task_started": 20, "task_completed": 18 },
#     "sessions": ["2025-01-23", "2025-01-25", "2025-01-30"]
#   }
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TRAJECTORY_DIR="${PROJECT_ROOT}/grimoires/loa/a2a/trajectory"

# Parameters
DAYS=7
START_DATE=""
END_DATE=""
DETAILED=false

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
      --detailed)
        DETAILED=true
        shift
        ;;
      --help|-h)
        sed -n '/^# Usage:/,/^# =====/p' "$0" | grep -v "^# =====" | sed 's/^# //'
        exit 0
        ;;
      *)
        echo "[ERROR] Unknown option: $1" >&2
        exit 1
        ;;
    esac
  done
}

# Calculate date range
calculate_date_range() {
  local today
  today=$(date -u +%Y-%m-%d)
  
  if [[ -n "$START_DATE" ]]; then
    [[ -z "$END_DATE" ]] && END_DATE="$today"
  else
    if [[ "$(uname)" == "Darwin" ]]; then
      START_DATE=$(date -v-"${DAYS}d" +%Y-%m-%d)
    else
      START_DATE=$(date -d "$today - $DAYS days" +%Y-%m-%d)
    fi
    END_DATE="$today"
  fi
}

# Count files in date range
count_files() {
  local count=0
  
  if [[ ! -d "$TRAJECTORY_DIR" ]]; then
    echo 0
    return
  fi
  
  while IFS= read -r -d '' file; do
    local filename
    filename=$(basename "$file")
    local file_date
    file_date=$(echo "$filename" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' || true)
    
    if [[ -n "$file_date" && ! "$file_date" < "$START_DATE" && ! "$file_date" > "$END_DATE" ]]; then
      count=$((count + 1))
    fi
  done < <(find "$TRAJECTORY_DIR" -name "*.jsonl" -type f -print0 2>/dev/null)
  
  echo "$count"
}

# Get unique session dates
get_sessions() {
  if [[ ! -d "$TRAJECTORY_DIR" ]]; then
    echo "[]"
    return
  fi
  
  local dates=()
  while IFS= read -r -d '' file; do
    local filename
    filename=$(basename "$file")
    local file_date
    file_date=$(echo "$filename" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' || true)
    
    if [[ -n "$file_date" && ! "$file_date" < "$START_DATE" && ! "$file_date" > "$END_DATE" ]]; then
      dates+=("$file_date")
    fi
  done < <(find "$TRAJECTORY_DIR" -name "*.jsonl" -type f -print0 2>/dev/null)
  
  # Unique and sort
  printf '%s\n' "${dates[@]}" | sort -u | jq -R -s 'split("\n") | map(select(length > 0))'
}

# Generate full summary using trajectory reader
generate_summary() {
  local reader="${SCRIPT_DIR}/trajectory-reader.sh"
  
  if [[ ! -x "$reader" ]]; then
    echo '{"error": "trajectory-reader.sh not found or not executable"}' >&2
    exit 1
  fi
  
  local total_files
  total_files=$(count_files)
  
  local sessions
  sessions=$(get_sessions)
  
  # Get events from reader (handle empty case)
  local events_file
  events_file=$(mktemp) || { echo '{"error":"mktemp failed"}'; return 1; }
  chmod 600 "$events_file"  # CRITICAL-001 FIX
  "$reader" --start "$START_DATE" --end "$END_DATE" --format jsonl 2>/dev/null > "$events_file" || true
  
  local event_count
  event_count=$(wc -l < "$events_file" | tr -d ' ')
  
  if [[ "$event_count" -eq 0 || ! -s "$events_file" ]]; then
    rm -f "$events_file"
    echo "{\"total_events\":0,\"total_files\":${total_files},\"date_range\":{\"start\":\"${START_DATE}\",\"end\":\"${END_DATE}\"},\"events_by_agent\":{},\"events_by_type\":{},\"sessions\":${sessions}}"
    return
  fi
  
  # Process events with jq
  local summary
  summary=$(cat "$events_file" | jq -s \
    --arg startd "$START_DATE" \
    --arg endd "$END_DATE" \
    --argjson files "$total_files" \
    --argjson sessions "$sessions" \
    '
    {
      total_events: length,
      total_files: $files,
      date_range: { 
        start: $startd, 
        end: $endd,
        first_event: (map(.timestamp) | min // null),
        last_event: (map(.timestamp) | max // null)
      },
      events_by_agent: (
        group_by(.agent // "unknown") 
        | map({key: (.[0].agent // "unknown"), value: length}) 
        | from_entries
      ),
      events_by_type: (
        group_by(.action // .type // "unknown") 
        | map({key: (.[0].action // .[0].type // "unknown"), value: length}) 
        | from_entries
      ),
      sessions: $sessions
    }
    ')
  
  # Add detailed info if requested
  if [[ "$DETAILED" == "true" ]]; then
    local samples
    samples=$(head -5 "$events_file" | jq -s '.')
    summary=$(echo "$summary" | jq --argjson samples "$samples" '. + {sample_events: $samples}')
  fi
  
  rm -f "$events_file"
  echo "$summary"
}

# Main
main() {
  parse_args "$@"
  calculate_date_range
  generate_summary
}

main "$@"
