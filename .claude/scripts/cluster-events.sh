#!/bin/bash
# =============================================================================
# cluster-events.sh - Event Clustering for Pattern Detection
# =============================================================================
# Sprint 4, Tasks 4.1-4.3: Cluster similar events into pattern groups
# Goal Contribution: G-1 (Cross-session pattern detection)
#
# Usage:
#   ./cluster-events.sh [options]
#
# Options:
#   --days N            Analyze last N days (default: 30)
#   --threshold N       Similarity threshold 0.0-1.0 (default: 0.6)
#   --min-cluster N     Minimum events per cluster (default: 2)
#   --output FORMAT     Output format: json (default), summary
#   --help              Show this help
#
# Algorithm:
#   O(n²) naive clustering - for each event, find existing cluster
#   with similarity > threshold. If found, add to cluster; else create new.
#
# Output:
#   Clusters with pattern candidates and confidence scores
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_FILE="${PROJECT_ROOT}/.loa.config.yaml"

# Parameters
DAYS=30
THRESHOLD=0.6
MIN_CLUSTER=2
OUTPUT_FORMAT="json"

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
      --threshold)
        THRESHOLD="$2"
        shift 2
        ;;
      --min-cluster)
        MIN_CLUSTER="$2"
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

# Get threshold from config if available
get_config_threshold() {
  if [[ -f "$CONFIG_FILE" ]]; then
    local cfg_threshold
    cfg_threshold=$(yq -e '.compound_learning.similarity.fallback.jaccard_threshold // 0.6' "$CONFIG_FILE" 2>/dev/null || echo "0.6")
    echo "$cfg_threshold"
  else
    echo "$THRESHOLD"
  fi
}

# Extract keywords from event
get_event_keywords() {
  local event="$1"
  local extractor="${SCRIPT_DIR}/extract-keywords.sh"
  
  # Extract all text fields
  local text
  text=$(echo "$event" | jq -r '[.error, .details, .message, .action, .solution, .reasoning] | map(select(. != null and . != "")) | join(" ")')
  
  if [[ -x "$extractor" && -n "$text" ]]; then
    echo "$text" | "$extractor" --technical 2>/dev/null | tr '\n' ',' | sed 's/,$//'
  else
    echo ""
  fi
}

# Calculate similarity between two events
event_similarity() {
  local event_a_keywords="$1"
  local event_b_keywords="$2"
  
  local calculator="${SCRIPT_DIR}/jaccard-similarity.sh"
  
  if [[ -x "$calculator" && -n "$event_a_keywords" && -n "$event_b_keywords" ]]; then
    "$calculator" --set-a "$event_a_keywords" --set-b "$event_b_keywords" 2>/dev/null || echo "0.0"
  else
    echo "0.0"
  fi
}

# Generate cluster centroid (common keywords)
get_cluster_centroid() {
  local keywords_list="$1"
  
  # Count keyword occurrences across all events in cluster
  echo "$keywords_list" | tr ',' '\n' | sort | uniq -c | sort -rn | head -10 | awk '{print $2}' | tr '\n' ','  | sed 's/,$//'
}

# Calculate confidence score based on cluster properties
calculate_confidence() {
  local cluster_size="$1"
  local session_diversity="$2"
  local recency_days="$3"
  
  # Base confidence from occurrence count
  local base_confidence
  if [[ "$cluster_size" -ge 5 ]]; then
    base_confidence=0.9
  elif [[ "$cluster_size" -ge 3 ]]; then
    base_confidence=0.7
  else
    base_confidence=0.5
  fi
  
  # Boost for session diversity (patterns across sessions = higher confidence)
  local diversity_boost=0
  if [[ "$session_diversity" -ge 3 ]]; then
    diversity_boost=0.1
  elif [[ "$session_diversity" -ge 2 ]]; then
    diversity_boost=0.05
  fi
  
  # Recency adjustment (recent patterns score higher)
  local recency_factor
  if [[ "$recency_days" -le 7 ]]; then
    recency_factor=1.0
  elif [[ "$recency_days" -le 30 ]]; then
    recency_factor=0.9
  else
    recency_factor=0.8
  fi
  
  # Calculate final confidence
  local confidence
  confidence=$(awk "BEGIN {printf \"%.2f\", ($base_confidence + $diversity_boost) * $recency_factor}")
  
  # Clamp to 1.0 max
  if (( $(awk "BEGIN {print ($confidence > 1.0) ? 1 : 0}") )); then
    confidence="1.0"
  fi
  
  echo "$confidence"
}

# Determine pattern type from cluster
determine_pattern_type() {
  local cluster_events="$1"
  
  # Check for error-related keywords
  local has_error
  has_error=$(echo "$cluster_events" | jq -r '.[].action // .[].type // ""' | grep -ciE 'error|fail|exception' || echo "0")
  
  local has_solution
  has_solution=$(echo "$cluster_events" | jq -r '.[].action // .[].type // ""' | grep -ciE 'fix|resolve|success|complete' || echo "0")
  
  if [[ "$has_error" -gt 0 && "$has_solution" -gt 0 ]]; then
    echo "convergent_solution"
  elif [[ "$has_error" -gt 0 ]]; then
    echo "repeated_error"
  else
    echo "project_convention"
  fi
}

# Main clustering function
cluster_events() {
  local reader="${SCRIPT_DIR}/trajectory-reader.sh"
  
  if [[ ! -x "$reader" ]]; then
    echo "[ERROR] trajectory-reader.sh not found" >&2
    exit 1
  fi
  
  # Get events
  local events_file=$(mktemp) || { echo "[]"; return; }
  chmod 600 "$events_file"  # CRITICAL-001 FIX
  "$reader" --days "$DAYS" --format jsonl 2>/dev/null > "$events_file" || true
  
  local event_count
  event_count=$(wc -l < "$events_file" | tr -d ' ')
  
  if [[ "$event_count" -eq 0 ]]; then
    rm -f "$events_file"
    echo "[]"
    return
  fi
  
  # Pre-compute keywords for all events
  local keywords_file=$(mktemp) || { rm -f "$events_file"; echo "[]"; return; }
  chmod 600 "$keywords_file"  # CRITICAL-001 FIX
  local idx=0
  while IFS= read -r event; do
    [[ -z "$event" ]] && continue
    local keywords
    keywords=$(get_event_keywords "$event")
    echo "$idx:$keywords" >> "$keywords_file"
    idx=$((idx + 1))
  done < "$events_file"
  
  # Clustering: assign each event to a cluster
  # clusters[i] = cluster_id for event i
  # cluster_members[cluster_id] = "idx1,idx2,..."
  declare -A clusters
  declare -A cluster_members
  declare -A cluster_keywords
  local next_cluster=0
  
  idx=0
  while IFS= read -r event; do
    [[ -z "$event" ]] && continue
    
    # Get keywords for this event
    local kw_line
    kw_line=$(grep "^$idx:" "$keywords_file" | cut -d: -f2-)
    
    if [[ -z "$kw_line" ]]; then
      idx=$((idx + 1))
      continue
    fi
    
    # Find best matching cluster
    local best_cluster=-1
    local best_similarity=0
    
    for cid in "${!cluster_keywords[@]}"; do
      local sim
      sim=$(event_similarity "$kw_line" "${cluster_keywords[$cid]}")
      
      local is_better
      is_better=$(awk "BEGIN {print ($sim > $best_similarity && $sim >= $THRESHOLD) ? 1 : 0}")
      
      if [[ "$is_better" == "1" ]]; then
        best_similarity="$sim"
        best_cluster="$cid"
      fi
    done
    
    if [[ "$best_cluster" -ge 0 ]]; then
      # Add to existing cluster
      clusters[$idx]="$best_cluster"
      cluster_members[$best_cluster]="${cluster_members[$best_cluster]},$idx"
      # Update cluster keywords (merge)
      cluster_keywords[$best_cluster]="${cluster_keywords[$best_cluster]},$kw_line"
    else
      # Create new cluster
      clusters[$idx]="$next_cluster"
      cluster_members[$next_cluster]="$idx"
      cluster_keywords[$next_cluster]="$kw_line"
      next_cluster=$((next_cluster + 1))
    fi
    
    idx=$((idx + 1))
  done < "$events_file"
  
  # Build output clusters (filter by min size)
  local output_clusters=()
  
  for cid in "${!cluster_members[@]}"; do
    local member_indices="${cluster_members[$cid]}"
    local member_count
    member_count=$(echo "$member_indices" | tr ',' '\n' | grep -c . || echo "0")
    
    if [[ "$member_count" -lt "$MIN_CLUSTER" ]]; then
      continue
    fi
    
    # Collect member events
    local member_events=()
    local sessions=()
    
    IFS=',' read -ra indices <<< "$member_indices"
    for midx in "${indices[@]}"; do
      [[ -z "$midx" ]] && continue
      local ev
      ev=$(sed -n "$((midx + 1))p" "$events_file")
      if [[ -n "$ev" ]]; then
        member_events+=("$ev")
        # Extract session date
        local sdate
        sdate=$(echo "$ev" | jq -r '.timestamp // ""' | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1)
        [[ -n "$sdate" ]] && sessions+=("$sdate")
      fi
    done
    
    # Calculate cluster properties
    local centroid
    centroid=$(get_cluster_centroid "${cluster_keywords[$cid]}")
    
    local unique_sessions
    unique_sessions=$(printf '%s\n' "${sessions[@]}" | sort -u | wc -l | tr -d ' ')
    
    local first_date
    local last_date
    first_date=$(printf '%s\n' "${sessions[@]}" | sort | head -1)
    last_date=$(printf '%s\n' "${sessions[@]}" | sort | tail -1)
    
    # Calculate recency
    local today
    today=$(date -u +%Y-%m-%d)
    local recency_days=0
    if [[ -n "$last_date" ]]; then
      recency_days=$(( ($(date -d "$today" +%s) - $(date -d "$last_date" +%s 2>/dev/null || echo "0")) / 86400 ))
      [[ "$recency_days" -lt 0 ]] && recency_days=0
    fi
    
    # Calculate confidence
    local confidence
    confidence=$(calculate_confidence "$member_count" "$unique_sessions" "$recency_days")
    
    # Determine pattern type
    local events_json
    events_json=$(printf '%s\n' "${member_events[@]}" | jq -s '.')
    
    local pattern_type
    pattern_type=$(determine_pattern_type "$events_json")
    
    # Generate pattern signature
    local signature
    signature=$(echo "$centroid" | tr ',' '-' | head -c 50)
    
    # Build cluster JSON
    local cluster_json
    cluster_json=$(jq -n \
      --arg id "cluster-$cid" \
      --arg type "$pattern_type" \
      --arg sig "$signature" \
      --arg centroid "$centroid" \
      --argjson count "$member_count" \
      --argjson sessions "$unique_sessions" \
      --arg first "$first_date" \
      --arg last "$last_date" \
      --argjson confidence "$confidence" \
      --argjson events "$events_json" \
      '{
        cluster_id: $id,
        pattern_type: $type,
        signature: $sig,
        centroid_keywords: ($centroid | split(",") | map(select(length > 0))),
        event_count: $count,
        session_count: $sessions,
        first_seen: $first,
        last_seen: $last,
        confidence: $confidence,
        events: $events
      }')
    
    output_clusters+=("$cluster_json")
  done
  
  # Cleanup
  rm -f "$events_file" "$keywords_file"
  
  # Output
  if [[ ${#output_clusters[@]} -eq 0 ]]; then
    echo "[]"
    return
  fi
  
  case "$OUTPUT_FORMAT" in
    json)
      printf '%s\n' "${output_clusters[@]}" | jq -s 'sort_by(-.confidence)'
      ;;
    summary)
      local cluster_count=${#output_clusters[@]}
      echo "Found $cluster_count clusters (min size: $MIN_CLUSTER)"
      echo ""
      printf '%s\n' "${output_clusters[@]}" | jq -r '"[\(.confidence)] \(.pattern_type): \(.signature) (\(.event_count) events, \(.session_count) sessions)"'
      ;;
  esac
}

# Main
main() {
  parse_args "$@"
  
  # Use config threshold if not explicitly set
  if [[ "$THRESHOLD" == "0.6" ]]; then
    THRESHOLD=$(get_config_threshold)
  fi
  
  cluster_events
}

main "$@"
