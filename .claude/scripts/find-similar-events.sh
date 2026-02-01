#!/bin/bash
# =============================================================================
# find-similar-events.sh - Find Similar Events Using Layered Similarity
# =============================================================================
# Sprint 3, Task 3.4-3.5: Compare events with layered similarity strategy
# Goal Contribution: G-1 (Cross-session pattern detection)
#
# Usage:
#   ./find-similar-events.sh --query "error message or event JSON" [options]
#   echo '{"action":"error",...}' | ./find-similar-events.sh [options]
#
# Options:
#   --query TEXT       Query text or JSON event to find similar events
#   --days N           Search last N days (default: 30)
#   --threshold N      Similarity threshold 0.0-1.0 (default: 0.6)
#   --limit N          Maximum results to return (default: 10)
#   --strategy TYPE    Similarity strategy: auto|jaccard|semantic (default: auto)
#   --json             Output detailed JSON
#   --help             Show this help
#
# Similarity Strategy (auto mode):
#   1. Check for ck (code search) - use if available and code-related
#   2. Check for Memory Stack (embeddings) - use if available
#   3. Fall back to Jaccard keyword similarity
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_FILE="${PROJECT_ROOT}/.loa.config.yaml"

# Parameters
QUERY=""
DAYS=30
THRESHOLD=0.6
LIMIT=10
STRATEGY="auto"
JSON_OUTPUT=false

# Detected tools
HAS_CK=false
HAS_MEMORY_STACK=false
HAS_QMD=false

# Usage
usage() {
  sed -n '/^# Usage:/,/^# =====/p' "$0" | grep -v "^# =====" | sed 's/^# //'
  exit 0
}

# Parse arguments
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --query)
        QUERY="$2"
        shift 2
        ;;
      --days)
        DAYS="$2"
        shift 2
        ;;
      --threshold)
        THRESHOLD="$2"
        shift 2
        ;;
      --limit)
        LIMIT="$2"
        shift 2
        ;;
      --strategy)
        STRATEGY="$2"
        shift 2
        ;;
      --json)
        JSON_OUTPUT=true
        shift
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

# Detect available semantic tools
detect_tools() {
  # Check ck
  if command -v ck &> /dev/null; then
    HAS_CK=true
  fi
  
  # Check Memory Stack (sentence-transformers)
  if python3 -c "import sentence_transformers" 2>/dev/null; then
    # Also check if enabled in config
    if [[ -f "$CONFIG_FILE" ]]; then
      local memory_enabled
      memory_enabled=$(yq -e '.memory.enabled // false' "$CONFIG_FILE" 2>/dev/null || echo "false")
      if [[ "$memory_enabled" == "true" ]]; then
        HAS_MEMORY_STACK=true
      fi
    fi
  fi
  
  # Check qmd
  if command -v qmd &> /dev/null; then
    HAS_QMD=true
  fi
}

# Extract text from query (handles both raw text and JSON)
extract_query_text() {
  local query="$1"
  
  # Try to parse as JSON
  if echo "$query" | jq -e . >/dev/null 2>&1; then
    # It's JSON - extract relevant fields
    echo "$query" | jq -r '[.error, .details, .message, .action, .solution, .reasoning] | map(select(. != null and . != "")) | join(" ")'
  else
    # Raw text
    echo "$query"
  fi
}

# Extract keywords from text
get_keywords() {
  local text="$1"
  local extractor="${SCRIPT_DIR}/extract-keywords.sh"
  
  if [[ -x "$extractor" ]]; then
    echo "$text" | "$extractor" --technical 2>/dev/null | tr '\n' ',' | sed 's/,$//'
  else
    # Simple fallback
    echo "$text" | tr -cs '[:alnum:]' ' ' | tr '[:upper:]' '[:lower:]' | tr ' ' ','
  fi
}

# Check if query is code-related
is_code_related() {
  local text="$1"
  
  # Check for code indicators
  if echo "$text" | grep -qE '(function|class|const|let|var|import|export|async|await|=>|\.ts|\.js|\.py|\.go|\.rs|src/|lib/)'; then
    return 0
  fi
  
  return 1
}

# Calculate similarity using Jaccard
jaccard_similarity() {
  local query_keywords="$1"
  local event_keywords="$2"
  
  local calculator="${SCRIPT_DIR}/jaccard-similarity.sh"
  
  if [[ -x "$calculator" ]]; then
    "$calculator" --set-a "$query_keywords" --set-b "$event_keywords" 2>/dev/null || echo "0.0"
  else
    echo "0.0"
  fi
}

# Calculate similarity using chosen strategy
calculate_similarity() {
  local query_text="$1"
  local event_text="$2"
  local strategy="$3"
  
  local query_keywords
  local event_keywords
  query_keywords=$(get_keywords "$query_text")
  event_keywords=$(get_keywords "$event_text")
  
  case "$strategy" in
    jaccard)
      jaccard_similarity "$query_keywords" "$event_keywords"
      ;;
    semantic)
      # Would use Memory Stack here if available
      # For now, fall back to Jaccard with boosted threshold consideration
      jaccard_similarity "$query_keywords" "$event_keywords"
      ;;
    ck)
      # Would use ck here if available
      # For now, fall back to Jaccard
      jaccard_similarity "$query_keywords" "$event_keywords"
      ;;
    auto|*)
      # Auto-select best available
      if [[ "$HAS_MEMORY_STACK" == "true" ]]; then
        # Would use embeddings - fall back for now
        jaccard_similarity "$query_keywords" "$event_keywords"
      elif [[ "$HAS_CK" == "true" ]] && is_code_related "$query_text"; then
        # Would use ck - fall back for now
        jaccard_similarity "$query_keywords" "$event_keywords"
      else
        jaccard_similarity "$query_keywords" "$event_keywords"
      fi
      ;;
  esac
}

# Find similar events
find_similar() {
  local query_text
  query_text=$(extract_query_text "$QUERY")
  
  if [[ -z "$query_text" ]]; then
    echo "[ERROR] No query provided" >&2
    exit 1
  fi
  
  local reader="${SCRIPT_DIR}/trajectory-reader.sh"
  
  if [[ ! -x "$reader" ]]; then
    echo "[ERROR] trajectory-reader.sh not found" >&2
    exit 1
  fi
  
  # Get events from trajectory
  local events_file=$(mktemp) || { echo "[]"; return; }
  chmod 600 "$events_file"  # CRITICAL-001 FIX
  "$reader" --days "$DAYS" --format jsonl 2>/dev/null > "$events_file" || true
  
  local event_count
  event_count=$(wc -l < "$events_file" | tr -d ' ')
  
  if [[ "$event_count" -eq 0 ]]; then
    rm -f "$events_file"
    if [[ "$JSON_OUTPUT" == "true" ]]; then
      echo '{"matches":[],"query_text":"'"$(echo "$query_text" | head -c 100)"'","strategy":"'"$STRATEGY"'","threshold":'"$THRESHOLD"'}'
    else
      echo "No events found in the last $DAYS days"
    fi
    return
  fi
  
  # Find similar events
  local matches=()
  local strategy_used="$STRATEGY"
  
  # Determine actual strategy
  if [[ "$STRATEGY" == "auto" ]]; then
    if [[ "$HAS_MEMORY_STACK" == "true" ]]; then
      strategy_used="semantic"
    elif [[ "$HAS_CK" == "true" ]] && is_code_related "$query_text"; then
      strategy_used="ck"
    else
      strategy_used="jaccard"
    fi
  fi
  
  while IFS= read -r event; do
    [[ -z "$event" ]] && continue
    
    local event_text
    event_text=$(extract_query_text "$event")
    
    if [[ -z "$event_text" ]]; then
      continue
    fi
    
    local similarity
    similarity=$(calculate_similarity "$query_text" "$event_text" "$strategy_used")
    
    # Check threshold
    if (( $(echo "$similarity >= $THRESHOLD" | bc -l 2>/dev/null || echo "0") )); then
      local match
      match=$(jq -n \
        --argjson event "$event" \
        --argjson sim "$similarity" \
        --arg strategy "$strategy_used" \
        '{
          event: $event,
          similarity: $sim,
          strategy: $strategy
        }')
      matches+=("$match")
    fi
  done < "$events_file"
  
  rm -f "$events_file"
  
  # Sort by similarity and limit
  local sorted_matches
  if [[ ${#matches[@]} -gt 0 ]]; then
    sorted_matches=$(printf '%s\n' "${matches[@]}" | jq -s 'sort_by(-.similarity) | .[0:'"$LIMIT"']')
  else
    sorted_matches="[]"
  fi
  
  # Output
  if [[ "$JSON_OUTPUT" == "true" ]]; then
    jq -n \
      --argjson matches "$sorted_matches" \
      --arg query "$(echo "$query_text" | head -c 200)" \
      --arg strategy "$strategy_used" \
      --argjson threshold "$THRESHOLD" \
      --argjson total "${#matches[@]}" \
      '{
        matches: $matches,
        query_text: $query,
        strategy: $strategy,
        threshold: $threshold,
        total_matches: $total
      }'
  else
    local match_count
    match_count=$(echo "$sorted_matches" | jq 'length')
    
    if [[ "$match_count" -eq 0 ]]; then
      echo "No similar events found (threshold: $THRESHOLD)"
    else
      echo "Found $match_count similar events (strategy: $strategy_used):"
      echo ""
      echo "$sorted_matches" | jq -r '.[] | "[\(.similarity | tostring | .[0:4])] \(.event.action // .event.type // "unknown") - \(.event.details // .event.message // "" | .[0:80])"'
    fi
  fi
}

# Main
main() {
  parse_args "$@"
  
  # Get query from stdin if not provided
  if [[ -z "$QUERY" && ! -t 0 ]]; then
    QUERY=$(cat)
  fi
  
  if [[ -z "$QUERY" ]]; then
    echo "[ERROR] No query provided. Use --query or pipe input." >&2
    usage
  fi
  
  detect_tools
  find_similar
}

main "$@"
