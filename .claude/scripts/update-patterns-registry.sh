#!/bin/bash
# =============================================================================
# update-patterns-registry.sh - Update Patterns Registry
# =============================================================================
# Sprint 4, Task 4.4: Update patterns.json with new pattern candidates
# Goal Contribution: G-1 (Cross-session pattern detection)
#
# Usage:
#   ./update-patterns-registry.sh [options]
#   cat clusters.json | ./update-patterns-registry.sh --stdin
#
# Options:
#   --stdin             Read clusters from stdin (JSON array)
#   --clusters FILE     Read clusters from file
#   --dry-run           Show what would be updated without writing
#   --max-age N         Filter patterns older than N days (default: 90)
#   --min-occurrences N Filter patterns with fewer than N occurrences (default: 2)
#   --help              Show this help
#
# Output:
#   Updated patterns.json with new/merged patterns
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PATTERNS_FILE="${PROJECT_ROOT}/grimoires/loa/a2a/compound/patterns.json"
CONFIG_FILE="${PROJECT_ROOT}/.loa.config.yaml"

# Parameters
READ_STDIN=false
CLUSTERS_FILE=""
DRY_RUN=false
MAX_AGE=90
MIN_OCCURRENCES=2

# Usage
usage() {
  sed -n '/^# Usage:/,/^# =====/p' "$0" | grep -v "^# =====" | sed 's/^# //'
  exit 0
}

# Parse arguments
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --stdin)
        READ_STDIN=true
        shift
        ;;
      --clusters)
        CLUSTERS_FILE="$2"
        shift 2
        ;;
      --dry-run)
        DRY_RUN=true
        shift
        ;;
      --max-age)
        MAX_AGE="$2"
        shift 2
        ;;
      --min-occurrences)
        MIN_OCCURRENCES="$2"
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

# Load config values
load_config() {
  if [[ -f "$CONFIG_FILE" ]]; then
    local cfg_max_age
    local cfg_min_occ
    cfg_max_age=$(yq -e '.compound_learning.pattern_detection.max_age_days // 90' "$CONFIG_FILE" 2>/dev/null || echo "90")
    cfg_min_occ=$(yq -e '.compound_learning.pattern_detection.min_occurrences // 2' "$CONFIG_FILE" 2>/dev/null || echo "2")
    
    [[ "$MAX_AGE" == "90" ]] && MAX_AGE="$cfg_max_age"
    [[ "$MIN_OCCURRENCES" == "2" ]] && MIN_OCCURRENCES="$cfg_min_occ"
  fi
}

# Initialize patterns file if needed
init_patterns_file() {
  if [[ ! -f "$PATTERNS_FILE" ]]; then
    mkdir -p "$(dirname "$PATTERNS_FILE")"
    cat > "$PATTERNS_FILE" << 'EOF'
{
  "$schema": "patterns.schema.json",
  "version": "1.0",
  "last_updated": null,
  "description": "Cross-session pattern registry for compound learning",
  "patterns": []
}
EOF
  fi
}

# Get input clusters
get_clusters() {
  if [[ "$READ_STDIN" == "true" ]]; then
    cat
  elif [[ -n "$CLUSTERS_FILE" && -f "$CLUSTERS_FILE" ]]; then
    cat "$CLUSTERS_FILE"
  else
    # Run clustering if no input provided
    local clusterer="${SCRIPT_DIR}/cluster-events.sh"
    if [[ -x "$clusterer" ]]; then
      "$clusterer" --output json 2>/dev/null || echo "[]"
    else
      echo "[]"
    fi
  fi
}

# Generate pattern ID
generate_pattern_id() {
  local signature="$1"
  local timestamp
  timestamp=$(date -u +%Y%m%d%H%M%S)
  local hash
  hash=$(echo "$signature" | md5sum | cut -c1-8)
  echo "pat-${timestamp}-${hash}"
}

# Find existing pattern by signature
find_existing_pattern() {
  local signature="$1"
  local patterns="$2"
  
  # Look for pattern with similar signature (Jaccard > 0.7)
  local idx=0
  echo "$patterns" | jq -c '.[]' | while read -r pattern; do
    local pat_sig
    pat_sig=$(echo "$pattern" | jq -r '.signature // ""')
    
    if [[ -n "$pat_sig" ]]; then
      local similarity
      similarity=$("$SCRIPT_DIR/jaccard-similarity.sh" \
        --set-a "$(echo "$signature" | tr '-' ',')" \
        --set-b "$(echo "$pat_sig" | tr '-' ',')" 2>/dev/null || echo "0.0")
      
      local is_match
      is_match=$(awk "BEGIN {print ($similarity >= 0.7) ? 1 : 0}")
      
      if [[ "$is_match" == "1" ]]; then
        echo "$idx"
        return
      fi
    fi
    
    idx=$((idx + 1))
  done
  
  echo "-1"
}

# Filter old patterns
filter_by_age() {
  local patterns="$1"
  local today
  today=$(date -u +%Y-%m-%d)
  
  echo "$patterns" | jq --arg today "$today" --arg max "$MAX_AGE" '
    map(select(
      .last_seen == null or
      (($today | split("-") | .[0] | tonumber) * 365 + 
       ($today | split("-") | .[1] | tonumber) * 30 +
       ($today | split("-") | .[2] | tonumber)) -
      ((.last_seen | split("-") | .[0] | tonumber) * 365 +
       (.last_seen | split("-") | .[1] | tonumber) * 30 +
       (.last_seen | split("-") | .[2] | tonumber)) <= ($max | tonumber)
    ))
  '
}

# Filter by minimum occurrences
filter_by_occurrences() {
  local patterns="$1"
  
  echo "$patterns" | jq --arg min "$MIN_OCCURRENCES" '
    map(select(.occurrence_count >= ($min | tonumber)))
  '
}

# Convert cluster to pattern
cluster_to_pattern() {
  local cluster="$1"
  local existing_id="$2"
  
  local cluster_id sig ptype first_seen last_seen count sessions confidence keywords
  
  cluster_id=$(echo "$cluster" | jq -r '.cluster_id')
  sig=$(echo "$cluster" | jq -r '.signature')
  ptype=$(echo "$cluster" | jq -r '.pattern_type')
  first_seen=$(echo "$cluster" | jq -r '.first_seen')
  last_seen=$(echo "$cluster" | jq -r '.last_seen')
  count=$(echo "$cluster" | jq -r '.event_count')
  sessions=$(echo "$cluster" | jq -r '.session_count')
  confidence=$(echo "$cluster" | jq -r '.confidence')
  keywords=$(echo "$cluster" | jq -c '.centroid_keywords // []')
  
  # Get unique session dates from events
  local session_dates
  session_dates=$(echo "$cluster" | jq -c '[.events[].timestamp | split("T")[0]] | unique')
  
  # Extract error and solution keywords
  local error_kw solution_kw
  error_kw=$(echo "$cluster" | jq -c '[.events[] | select(.action | test("error|fail"; "i")) | .details // .message // ""] | map(split(" ") | .[]) | unique | .[0:10]' 2>/dev/null || echo '[]')
  solution_kw=$(echo "$cluster" | jq -c '[.events[] | select(.action | test("fix|resolve|success"; "i")) | .details // .message // ""] | map(split(" ") | .[]) | unique | .[0:10]' 2>/dev/null || echo '[]')
  
  # Generate or use existing ID
  local pattern_id
  if [[ -n "$existing_id" && "$existing_id" != "null" ]]; then
    pattern_id="$existing_id"
  else
    pattern_id=$(generate_pattern_id "$sig")
  fi
  
  jq -n \
    --arg id "$pattern_id" \
    --arg type "$ptype" \
    --arg sig "$sig" \
    --arg first "$first_seen" \
    --arg last "$last_seen" \
    --argjson count "$count" \
    --argjson sessions_arr "$session_dates" \
    --argjson keywords "$keywords" \
    --argjson err_kw "$error_kw" \
    --argjson sol_kw "$solution_kw" \
    --argjson confidence "$confidence" \
    '{
      id: $id,
      type: $type,
      signature: $sig,
      first_seen: $first,
      last_seen: $last,
      occurrence_count: $count,
      sessions: $sessions_arr,
      error_keywords: $err_kw,
      solution_keywords: $sol_kw,
      confidence: $confidence,
      extracted_to_skill: null,
      status: "active"
    }'
}

# Main update function
update_registry() {
  init_patterns_file
  load_config
  
  # Get input clusters
  local clusters
  clusters=$(get_clusters)
  
  local cluster_count
  cluster_count=$(echo "$clusters" | jq 'length')
  
  if [[ "$cluster_count" -eq 0 ]]; then
    echo "[INFO] No clusters to process"
    return
  fi
  
  echo "[INFO] Processing $cluster_count clusters..."
  
  # Load existing patterns
  local existing_patterns
  existing_patterns=$(jq '.patterns // []' "$PATTERNS_FILE")
  
  # Process each cluster
  local new_patterns=()
  local updated_count=0
  local added_count=0
  
  echo "$clusters" | jq -c '.[]' | while read -r cluster; do
    local sig
    sig=$(echo "$cluster" | jq -r '.signature')
    
    # Check for existing pattern
    local existing_idx
    existing_idx=$(find_existing_pattern "$sig" "$existing_patterns")
    
    if [[ "$existing_idx" != "-1" && "$existing_idx" -ge 0 ]]; then
      # Update existing pattern
      local existing
      existing=$(echo "$existing_patterns" | jq ".[$existing_idx]")
      local existing_id
      existing_id=$(echo "$existing" | jq -r '.id')
      
      # Merge occurrence counts
      local old_count new_count total_count
      old_count=$(echo "$existing" | jq -r '.occurrence_count // 0')
      new_count=$(echo "$cluster" | jq -r '.event_count')
      total_count=$((old_count + new_count))
      
      # Update pattern
      local updated_pattern
      updated_pattern=$(cluster_to_pattern "$cluster" "$existing_id")
      updated_pattern=$(echo "$updated_pattern" | jq --argjson total "$total_count" '.occurrence_count = $total')
      
      new_patterns+=("$updated_pattern")
      updated_count=$((updated_count + 1))
    else
      # Add new pattern
      local new_pattern
      new_pattern=$(cluster_to_pattern "$cluster" "")
      new_patterns+=("$new_pattern")
      added_count=$((added_count + 1))
    fi
  done
  
  # Merge with existing patterns (keeping those not updated)
  local final_patterns
  if [[ ${#new_patterns[@]} -gt 0 ]]; then
    final_patterns=$(printf '%s\n' "${new_patterns[@]}" | jq -s '.')
  else
    final_patterns="$existing_patterns"
  fi
  
  # Apply filters
  final_patterns=$(filter_by_age "$final_patterns")
  final_patterns=$(filter_by_occurrences "$final_patterns")
  
  # Update timestamp
  local now
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  
  # Build final JSON
  local final_json
  final_json=$(jq -n \
    --arg schema "patterns.schema.json" \
    --arg version "1.0" \
    --arg updated "$now" \
    --arg desc "Cross-session pattern registry for compound learning" \
    --argjson patterns "$final_patterns" \
    '{
      "$schema": $schema,
      version: $version,
      last_updated: $updated,
      description: $desc,
      patterns: $patterns
    }')
  
  # Output or write
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[DRY-RUN] Would update patterns.json:"
    echo "$final_json" | jq '.patterns | length' | xargs -I {} echo "  Total patterns: {}"
    echo "  Updated: $updated_count"
    echo "  Added: $added_count"
    echo ""
    echo "Patterns:"
    echo "$final_json" | jq -r '.patterns[] | "  [\(.confidence)] \(.type): \(.signature)"'
  else
    echo "$final_json" > "$PATTERNS_FILE"
    echo "[INFO] Updated $PATTERNS_FILE"
    echo "  Total patterns: $(echo "$final_json" | jq '.patterns | length')"
  fi
}

# Main
main() {
  parse_args "$@"
  update_registry
}

main "$@"
