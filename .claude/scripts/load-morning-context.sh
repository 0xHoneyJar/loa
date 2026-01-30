#!/bin/bash
# =============================================================================
# load-morning-context.sh - Morning Context Loader
# =============================================================================
# Sprint 15: Load relevant learnings at session start
# Goal Contribution: G-2 (Reduce repeated investigations)
#
# Usage:
#   ./load-morning-context.sh [options]
#
# Options:
#   --task CONTEXT      Task/PRD context for relevance matching
#   --max N             Maximum learnings to load (default: 5)
#   --min-effectiveness N  Minimum effectiveness score (default: 50)
#   --output FORMAT     Output format: markdown|json
#   --help              Show this help
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LEARNINGS_FILE="${PROJECT_ROOT}/grimoires/loa/a2a/compound/learnings.json"
SKILLS_DIR="${PROJECT_ROOT}/grimoires/loa/skills"
CONFIG_FILE="${PROJECT_ROOT}/.loa.config.yaml"

TASK_CONTEXT=""
MAX_LEARNINGS=5
MIN_EFFECTIVENESS=50
OUTPUT_FORMAT="markdown"

usage() {
  sed -n '/^# Usage:/,/^# =====/p' "$0" | grep -v "^# =====" | sed 's/^# //'
  exit 0
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --task) TASK_CONTEXT="$2"; shift 2 ;;
      --max) MAX_LEARNINGS="$2"; shift 2 ;;
      --min-effectiveness) MIN_EFFECTIVENESS="$2"; shift 2 ;;
      --output) OUTPUT_FORMAT="$2"; shift 2 ;;
      --help|-h) usage ;;
      *) shift ;;
    esac
  done
}

load_config() {
  if [[ -f "$CONFIG_FILE" ]]; then
    MAX_LEARNINGS=$(yq -e '.compound_learning.morning_context.max_learnings // 5' "$CONFIG_FILE" 2>/dev/null || echo "5")
    MIN_EFFECTIVENESS=$(yq -e '.compound_learning.morning_context.min_effectiveness // 50' "$CONFIG_FILE" 2>/dev/null || echo "50")
  fi
}

# Extract keywords from task context
extract_task_keywords() {
  local context="$1"
  
  if [[ -z "$context" ]]; then
    echo ""
    return
  fi
  
  local extractor="${SCRIPT_DIR}/extract-keywords.sh"
  if [[ -x "$extractor" ]]; then
    echo "$context" | "$extractor" --technical 2>/dev/null | tr '\n' ',' | sed 's/,$//'
  else
    echo "$context" | tr -cs '[:alnum:]' ',' | tr '[:upper:]' '[:lower:]'
  fi
}

# Calculate relevance score
calculate_relevance() {
  local task_keywords="$1"
  local learning_id="$2"
  
  if [[ -z "$task_keywords" ]]; then
    echo "0.5"  # Default relevance
    return
  fi
  
  # Get skill keywords
  local skill_file="${SKILLS_DIR}/${learning_id}/SKILL.md"
  local skill_keywords=""
  
  if [[ -f "$skill_file" ]]; then
    local content
    content=$(sed '/^---$/,/^---$/d' "$skill_file")
    local extractor="${SCRIPT_DIR}/extract-keywords.sh"
    if [[ -x "$extractor" ]]; then
      skill_keywords=$(echo "$content" | "$extractor" --technical 2>/dev/null | tr '\n' ',' | sed 's/,$//')
    fi
  fi
  
  if [[ -z "$skill_keywords" ]]; then
    echo "0.3"
    return
  fi
  
  # Calculate similarity
  local calculator="${SCRIPT_DIR}/jaccard-similarity.sh"
  if [[ -x "$calculator" ]]; then
    "$calculator" --set-a "$task_keywords" --set-b "$skill_keywords" 2>/dev/null || echo "0.3"
  else
    echo "0.3"
  fi
}

# Load and rank learnings
load_learnings() {
  if [[ ! -f "$LEARNINGS_FILE" ]]; then
    echo "[]"
    return
  fi
  
  local task_keywords
  task_keywords=$(extract_task_keywords "$TASK_CONTEXT")
  
  # Get learnings meeting minimum effectiveness
  local candidates
  candidates=$(jq --argjson min "$MIN_EFFECTIVENESS" '
    [.learnings[] | select(.effectiveness_score >= $min)]
  ' "$LEARNINGS_FILE" 2>/dev/null || echo "[]")
  
  local count
  count=$(echo "$candidates" | jq 'length')
  
  if [[ "$count" -eq 0 ]]; then
    echo "[]"
    return
  fi
  
  # Calculate relevance and sort
  local ranked=()
  
  echo "$candidates" | jq -c '.[]' | while read -r learning; do
    local learning_id effectiveness
    learning_id=$(echo "$learning" | jq -r '.id')
    effectiveness=$(echo "$learning" | jq '.effectiveness_score')
    
    local relevance
    relevance=$(calculate_relevance "$task_keywords" "$learning_id")
    
    # Combined score: relevance * effectiveness
    local combined
    combined=$(awk "BEGIN {printf \"%.2f\", $relevance * ($effectiveness / 100)}")
    
    jq -n \
      --argjson learning "$learning" \
      --argjson relevance "$relevance" \
      --argjson combined "$combined" \
      '$learning + {relevance: $relevance, combined_score: $combined}'
  done | jq -s "sort_by(-.combined_score) | .[0:$MAX_LEARNINGS]"
}

# Output as markdown
output_markdown() {
  local learnings="$1"
  local count
  count=$(echo "$learnings" | jq 'length')
  
  if [[ "$count" -eq 0 ]]; then
    echo "No relevant learnings found for the current context."
    return
  fi
  
  cat << 'EOF'
📚 **Before you begin...**

Based on previous work and current context, consider these learnings:

EOF

  echo "$learnings" | jq -r '
    to_entries | .[] |
    "\(.key + 1). **[\(if .value.effectiveness_score >= 80 then "HIGH" elif .value.effectiveness_score >= 50 then "MED" else "LOW" end)]** \(.value.id)\n   → Effectiveness: \(.value.effectiveness_score)%\n"
  '
  
  echo ""
  echo "*Apply these learnings? [Y/n/select]*"
}

# Output as JSON
output_json() {
  local learnings="$1"
  
  jq -n \
    --argjson learnings "$learnings" \
    --arg context "${TASK_CONTEXT:-}" \
    --arg generated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{
      context: $context,
      generated: $generated,
      learnings: $learnings
    }'
}

main() {
  parse_args "$@"
  load_config
  
  local learnings
  learnings=$(load_learnings)
  
  case "$OUTPUT_FORMAT" in
    json) output_json "$learnings" ;;
    *) output_markdown "$learnings" ;;
  esac
}

main "$@"
