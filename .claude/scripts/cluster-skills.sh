#!/bin/bash
# =============================================================================
# cluster-skills.sh - Skill Clustering for Synthesis
# =============================================================================
# Sprint 13: Cluster related skills by semantic similarity
# Goal Contribution: G-3 (Automate knowledge consolidation)
#
# Usage:
#   ./cluster-skills.sh [options]
#
# Options:
#   --min-cluster N     Minimum skills per cluster (default: 3)
#   --threshold N       Similarity threshold 0-1 (default: 0.4)
#   --output FORMAT     Output format: json|summary
#   --help              Show this help
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Require bash 4.0+ (associative arrays)
# shellcheck source=bash-version-guard.sh
source "$SCRIPT_DIR/bash-version-guard.sh"
SKILLS_DIR="${PROJECT_ROOT}/grimoires/loa/skills"
SYNTHESIS_FILE="${PROJECT_ROOT}/grimoires/loa/a2a/compound/synthesis-queue.json"
CONFIG_FILE="${PROJECT_ROOT}/.loa.config.yaml"

MIN_CLUSTER=3
THRESHOLD=0.4
OUTPUT_FORMAT="json"

usage() {
  sed -n '/^# Usage:/,/^# =====/p' "$0" | grep -v "^# =====" | sed 's/^# //'
  exit 0
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --min-cluster) MIN_CLUSTER="$2"; shift 2 ;;
      --threshold) THRESHOLD="$2"; shift 2 ;;
      --output) OUTPUT_FORMAT="$2"; shift 2 ;;
      --help|-h) usage ;;
      *) shift ;;
    esac
  done
}

load_config() {
  if [[ -f "$CONFIG_FILE" ]]; then
    MIN_CLUSTER=$(yq -e '.compound_learning.synthesis.min_cluster_size // 3' "$CONFIG_FILE" 2>/dev/null || echo "3")
    THRESHOLD=$(yq -e '.compound_learning.synthesis.cluster_similarity_threshold // 0.4' "$CONFIG_FILE" 2>/dev/null || echo "0.4")
  fi
}

# Extract keywords from SKILL.md
extract_skill_keywords() {
  local skill_file="$1"
  
  if [[ ! -f "$skill_file" ]]; then
    echo ""
    return
  fi
  
  # Extract text content (skip frontmatter)
  local content
  content=$(sed '/^---$/,/^---$/d' "$skill_file" | tr -cs '[:alnum:]' ' ' | tr '[:upper:]' '[:lower:]')
  
  # Use extract-keywords if available
  local extractor="${SCRIPT_DIR}/extract-keywords.sh"
  if [[ -x "$extractor" ]]; then
    echo "$content" | "$extractor" --technical 2>/dev/null | tr '\n' ',' | sed 's/,$//'
  else
    echo "$content" | tr ' ' ','
  fi
}

# Calculate similarity between two skills
skill_similarity() {
  local kw_a="$1"
  local kw_b="$2"
  
  local calculator="${SCRIPT_DIR}/jaccard-similarity.sh"
  if [[ -x "$calculator" && -n "$kw_a" && -n "$kw_b" ]]; then
    "$calculator" --set-a "$kw_a" --set-b "$kw_b" 2>/dev/null || echo "0.0"
  else
    echo "0.0"
  fi
}

# Cluster skills
cluster_skills() {
  if [[ ! -d "$SKILLS_DIR" ]]; then
    echo "[]"
    return
  fi
  
  # Collect skills and their keywords
  local skills=()
  local keywords=()
  
  while IFS= read -r skill_dir; do
    [[ ! -d "$skill_dir" ]] && continue
    local skill_name
    skill_name=$(basename "$skill_dir")
    local skill_file="${skill_dir}/SKILL.md"
    
    if [[ -f "$skill_file" ]]; then
      skills+=("$skill_name")
      local kw
      kw=$(extract_skill_keywords "$skill_file")
      keywords+=("$kw")
    fi
  done < <(find "$SKILLS_DIR" -maxdepth 1 -type d | tail -n +2)
  
  local skill_count=${#skills[@]}
  
  if [[ "$skill_count" -lt "$MIN_CLUSTER" ]]; then
    echo "[]"
    return
  fi
  
  # Naive clustering
  declare -A cluster_map
  declare -A clusters
  local next_cluster=0
  
  for ((i=0; i<skill_count; i++)); do
    local skill_i="${skills[$i]}"
    local kw_i="${keywords[$i]}"
    
    # Find matching cluster
    local best_cluster=-1
    local best_sim=0
    
    for cid in "${!clusters[@]}"; do
      # Get representative skill
      local rep_idx=${clusters[$cid]%%,*}
      local kw_rep="${keywords[$rep_idx]}"
      
      local sim
      sim=$(skill_similarity "$kw_i" "$kw_rep")
      
      local is_better
      is_better=$(awk "BEGIN {print ($sim > $best_sim && $sim >= $THRESHOLD) ? 1 : 0}")
      
      if [[ "$is_better" == "1" ]]; then
        best_sim="$sim"
        best_cluster="$cid"
      fi
    done
    
    if [[ "$best_cluster" -ge 0 ]]; then
      cluster_map[$i]="$best_cluster"
      clusters[$best_cluster]="${clusters[$best_cluster]},$i"
    else
      cluster_map[$i]="$next_cluster"
      clusters[$next_cluster]="$i"
      next_cluster=$((next_cluster + 1))
    fi
  done
  
  # Build output clusters (filter by min size)
  local output_clusters=()
  
  for cid in "${!clusters[@]}"; do
    local member_indices="${clusters[$cid]}"
    local member_list=()
    
    IFS=',' read -ra indices <<< "$member_indices"
    for idx in "${indices[@]}"; do
      [[ -z "$idx" ]] && continue
      member_list+=("${skills[$idx]}")
    done
    
    local member_count=${#member_list[@]}
    
    if [[ "$member_count" -ge "$MIN_CLUSTER" ]]; then
      local cluster_json
      cluster_json=$(jq -n \
        --arg cid "cluster-$cid" \
        --argjson count "$member_count" \
        --argjson members "$(printf '%s\n' "${member_list[@]}" | jq -R -s 'split("\n") | map(select(length > 0))')" \
        '{
          cluster_id: $cid,
          skill_count: $count,
          skills: $members
        }')
      
      output_clusters+=("$cluster_json")
    fi
  done
  
  if [[ ${#output_clusters[@]} -eq 0 ]]; then
    echo "[]"
  else
    printf '%s\n' "${output_clusters[@]}" | jq -s '.'
  fi
}

main() {
  parse_args "$@"
  load_config
  
  local result
  result=$(cluster_skills)
  
  case "$OUTPUT_FORMAT" in
    summary)
      local count
      count=$(echo "$result" | jq 'length')
      echo "Found $count skill clusters (min size: $MIN_CLUSTER)"
      echo "$result" | jq -r '.[] | "- \(.cluster_id): \(.skills | join(", "))"'
      ;;
    *)
      echo "$result"
      ;;
  esac
}

main "$@"
