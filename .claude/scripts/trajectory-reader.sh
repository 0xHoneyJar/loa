#!/bin/bash
# =============================================================================
# trajectory-reader.sh - Streaming JSONL Trajectory Reader
# =============================================================================
# Sprint 2, Task 2.1-2.4: Streaming trajectory reader with date filtering
# Goal Contribution: G-1 (Cross-session pattern detection foundation)
#
# Usage:
#   ./trajectory-reader.sh [options]
#
# Options:
#   --start DATE     Start date (YYYY-MM-DD)
#   --end DATE       End date (YYYY-MM-DD)
#   --days N         Last N days (alternative to --start/--end)
#   --agent PATTERN  Filter by agent name pattern
#   --exclude AGENTS Comma-separated agents to exclude
#   --type TYPES     Filter by event types (comma-separated)
#   --format FORMAT  Output format: jsonl (default) | json | summary
#   --help           Show this help
#
# Examples:
#   ./trajectory-reader.sh --days 7
#   ./trajectory-reader.sh --start 2025-01-01 --end 2025-01-15
#   ./trajectory-reader.sh --days 30 --agent "implementing"
#   ./trajectory-reader.sh --days 7 --exclude "test-agent,debug"
# =============================================================================

set -euo pipefail

# Default configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TRAJECTORY_DIR="${PROJECT_ROOT}/grimoires/loa/a2a/trajectory"
CONFIG_FILE="${PROJECT_ROOT}/.loa.config.yaml"

# Parameters
START_DATE=""
END_DATE=""
DAYS=""
AGENT_FILTER=""
EXCLUDE_AGENTS=""
EVENT_TYPES=""
OUTPUT_FORMAT="jsonl"
VERBOSE=false

# Error handling
error() {
  echo "[ERROR] $*" >&2
  exit 1
}

warn() {
  echo "[WARN] $*" >&2
}

debug() {
  if [[ "$VERBOSE" == "true" ]]; then
    echo "[DEBUG] $*" >&2
  fi
}

# Usage
usage() {
  sed -n '/^# Usage:/,/^# =====/p' "$0" | grep -v "^# =====" | sed 's/^# //'
  exit 0
}

# Parse arguments
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --start)
        START_DATE="$2"
        shift 2
        ;;
      --end)
        END_DATE="$2"
        shift 2
        ;;
      --days)
        DAYS="$2"
        shift 2
        ;;
      --agent)
        AGENT_FILTER="$2"
        shift 2
        ;;
      --exclude)
        EXCLUDE_AGENTS="$2"
        shift 2
        ;;
      --type|--types)
        EVENT_TYPES="$2"
        shift 2
        ;;
      --format)
        OUTPUT_FORMAT="$2"
        shift 2
        ;;
      --verbose|-v)
        VERBOSE=true
        shift
        ;;
      --help|-h)
        usage
        ;;
      *)
        error "Unknown option: $1"
        ;;
    esac
  done
}

# Calculate date range
calculate_date_range() {
  local today
  today=$(date -u +%Y-%m-%d)
  
  if [[ -n "$DAYS" ]]; then
    # Calculate start date from N days ago
    if [[ "$(uname)" == "Darwin" ]]; then
      START_DATE=$(date -v-"${DAYS}d" +%Y-%m-%d)
    else
      START_DATE=$(date -d "$today - $DAYS days" +%Y-%m-%d)
    fi
    END_DATE="$today"
    debug "Calculated date range: $START_DATE to $END_DATE (last $DAYS days)"
  elif [[ -z "$START_DATE" ]]; then
    # Default: last 7 days
    if [[ "$(uname)" == "Darwin" ]]; then
      START_DATE=$(date -v-7d +%Y-%m-%d)
    else
      START_DATE=$(date -d "$today - 7 days" +%Y-%m-%d)
    fi
    END_DATE="$today"
    debug "Using default date range: $START_DATE to $END_DATE"
  elif [[ -z "$END_DATE" ]]; then
    END_DATE="$today"
    debug "Using end date: $END_DATE"
  fi
}

# Find trajectory files in date range
# File format: {agent}-{date}.jsonl
find_trajectory_files() {
  local files=()
  
  if [[ ! -d "$TRAJECTORY_DIR" ]]; then
    warn "Trajectory directory not found: $TRAJECTORY_DIR"
    return
  fi
  
  debug "Searching for files in $TRAJECTORY_DIR"
  debug "Date range: $START_DATE to $END_DATE"
  
  # Find all JSONL files
  while IFS= read -r -d '' file; do
    local filename
    filename=$(basename "$file")
    
    # Extract date from filename (format: {agent}-{YYYY-MM-DD}.jsonl)
    local file_date
    file_date=$(echo "$filename" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' || true)
    
    if [[ -z "$file_date" ]]; then
      debug "Skipping file without date: $filename"
      continue
    fi
    
    # Check if date is in range (string comparison works for YYYY-MM-DD format)
    if [[ ! "$file_date" < "$START_DATE" && ! "$file_date" > "$END_DATE" ]]; then
      # Check agent filter if specified
      if [[ -n "$AGENT_FILTER" ]]; then
        local agent_name
        agent_name=$(echo "$filename" | sed "s/-${file_date}\.jsonl$//")
        if [[ "$agent_name" != *"$AGENT_FILTER"* ]]; then
          debug "Skipping file (agent filter): $filename"
          continue
        fi
      fi
      
      # Check exclude list
      if [[ -n "$EXCLUDE_AGENTS" ]]; then
        local agent_name
        agent_name=$(echo "$filename" | sed "s/-${file_date}\.jsonl$//")
        local exclude_match=false
        IFS=',' read -ra excludes <<< "$EXCLUDE_AGENTS"
        for exclude in "${excludes[@]}"; do
          if [[ "$agent_name" == "$exclude" ]]; then
            exclude_match=true
            break
          fi
        done
        if [[ "$exclude_match" == "true" ]]; then
          debug "Skipping file (excluded): $filename"
          continue
        fi
      fi
      
      files+=("$file")
      debug "Including file: $filename"
    else
      debug "Skipping file (out of date range): $filename"
    fi
  done < <(find "$TRAJECTORY_DIR" -name "*.jsonl" -type f -print0 2>/dev/null | sort -z)
  
  # Output file list
  printf '%s\n' "${files[@]}"
}

# Parse a single JSONL line with error handling
parse_event() {
  local line="$1"
  local line_num="$2"
  local file="$3"
  
  # Skip empty lines
  if [[ -z "$line" || "$line" =~ ^[[:space:]]*$ ]]; then
    return 0
  fi
  
  # Validate JSON
  if ! echo "$line" | jq -e . >/dev/null 2>&1; then
    warn "Malformed JSON at line $line_num in $file"
    return 0
  fi
  
  # Apply event type filter if specified
  if [[ -n "$EVENT_TYPES" ]]; then
    local event_type
    event_type=$(echo "$line" | jq -r '.action // .type // "unknown"')
    local type_match=false
    IFS=',' read -ra types <<< "$EVENT_TYPES"
    for t in "${types[@]}"; do
      if [[ "$event_type" == "$t" || "$event_type" =~ $t ]]; then
        type_match=true
        break
      fi
    done
    if [[ "$type_match" == "false" ]]; then
      return 0
    fi
  fi
  
  # Output the event
  echo "$line"
}

# Stream events from files
stream_events() {
  local files
  files=$(find_trajectory_files)
  
  if [[ -z "$files" ]]; then
    debug "No trajectory files found in date range"
    return
  fi
  
  local total_events=0
  local malformed_events=0
  
  while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    
    debug "Processing: $file"
    local line_num=0
    
    while IFS= read -r line; do
      line_num=$((line_num + 1))
      
      local event
      event=$(parse_event "$line" "$line_num" "$file")
      
      if [[ -n "$event" ]]; then
        total_events=$((total_events + 1))
        echo "$event"
      fi
    done < "$file"
  done <<< "$files"
  
  debug "Total events streamed: $total_events"
}

# Output as JSON array
output_json() {
  echo "["
  local first=true
  while IFS= read -r event; do
    if [[ "$first" == "true" ]]; then
      first=false
    else
      echo ","
    fi
    echo "  $event"
  done
  echo "]"
}

# Output summary
output_summary() {
  local events
  events=$(stream_events)
  
  if [[ -z "$events" ]]; then
    echo '{"total_events":0,"events_by_agent":{},"events_by_type":{}}'
    return
  fi
  
  echo "$events" | jq -s '
    {
      total_events: length,
      date_range: {
        start: (map(.timestamp) | min),
        end: (map(.timestamp) | max)
      },
      events_by_agent: (group_by(.agent) | map({key: .[0].agent, value: length}) | from_entries),
      events_by_type: (group_by(.action // .type // "unknown") | map({key: (.[0].action // .[0].type // "unknown"), value: length}) | from_entries)
    }
  '
}

# Main
main() {
  parse_args "$@"
  calculate_date_range
  
  case "$OUTPUT_FORMAT" in
    jsonl)
      stream_events
      ;;
    json)
      stream_events | output_json
      ;;
    summary)
      output_summary
      ;;
    *)
      error "Unknown output format: $OUTPUT_FORMAT"
      ;;
  esac
}

main "$@"
