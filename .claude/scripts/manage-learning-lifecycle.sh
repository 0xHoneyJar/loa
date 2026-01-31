#!/bin/bash
# =============================================================================
# manage-learning-lifecycle.sh - Learning Lifecycle Management
# =============================================================================
# Sprint 12: Manage learning tiers, pruning, and monthly reports
# Goal Contribution: G-4 (Close apply-verify loop)
#
# Usage:
#   ./manage-learning-lifecycle.sh [subcommand] [options]
#
# Subcommands:
#   tiers       Show learnings by tier
#   prune       Archive ineffective learnings
#   report      Generate effectiveness report
#   review      List learnings flagged for review
#
# Options:
#   --dry-run   Preview without changes
#   --month M   Report for specific month (YYYY-MM)
#   --top N     Top N learnings (default: 5)
#   --help      Show this help
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LEARNINGS_FILE="${PROJECT_ROOT}/grimoires/loa/a2a/compound/learnings.json"
SKILLS_ARCHIVED="${PROJECT_ROOT}/grimoires/loa/skills-archived"
CONFIG_FILE="${PROJECT_ROOT}/.loa.config.yaml"

SUBCOMMAND=""
DRY_RUN=false
MONTH=""
TOP_N=5

# Tier thresholds from config
TIER_HIGH=80
TIER_MEDIUM=50
TIER_LOW=20
PRUNE_FAILURES=3

usage() {
  sed -n '/^# Usage:/,/^# =====/p' "$0" | grep -v "^# =====" | sed 's/^# //'
  exit 0
}

parse_args() {
  [[ $# -gt 0 && ! "$1" =~ ^-- ]] && { SUBCOMMAND="$1"; shift; }
  
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run) DRY_RUN=true; shift ;;
      --month) MONTH="$2"; shift 2 ;;
      --top) TOP_N="$2"; shift 2 ;;
      --help|-h) usage ;;
      *) shift ;;
    esac
  done
}

load_config() {
  if [[ -f "$CONFIG_FILE" ]]; then
    TIER_HIGH=$(yq -e '.compound_learning.effectiveness.tiers.high // 80' "$CONFIG_FILE" 2>/dev/null || echo "80")
    TIER_MEDIUM=$(yq -e '.compound_learning.effectiveness.tiers.medium // 50' "$CONFIG_FILE" 2>/dev/null || echo "50")
    TIER_LOW=$(yq -e '.compound_learning.effectiveness.tiers.low // 20' "$CONFIG_FILE" 2>/dev/null || echo "20")
    PRUNE_FAILURES=$(yq -e '.compound_learning.effectiveness.pruning.failures_before_prune // 3' "$CONFIG_FILE" 2>/dev/null || echo "3")
  fi
}

init_learnings() {
  if [[ ! -f "$LEARNINGS_FILE" ]]; then
    mkdir -p "$(dirname "$LEARNINGS_FILE")"
    echo '{"version":"1.0","learnings":[]}' > "$LEARNINGS_FILE"
  fi
}

cmd_tiers() {
  init_learnings
  
  echo "## Learning Tiers"
  echo ""
  
  # High tier
  echo "### 🟢 HIGH (${TIER_HIGH}%+) - Increased retrieval priority"
  jq -r --argjson th "$TIER_HIGH" '.learnings[] | select(.effectiveness_score >= $th) | "- \(.id): \(.effectiveness_score)%"' "$LEARNINGS_FILE" 2>/dev/null || echo "  (none)"
  echo ""
  
  # Medium tier
  echo "### 🟡 MEDIUM (${TIER_MEDIUM}-${TIER_HIGH}%) - Normal retrieval"
  jq -r --argjson hi "$TIER_HIGH" --argjson lo "$TIER_MEDIUM" '.learnings[] | select(.effectiveness_score >= $lo and .effectiveness_score < $hi) | "- \(.id): \(.effectiveness_score)%"' "$LEARNINGS_FILE" 2>/dev/null || echo "  (none)"
  echo ""
  
  # Low tier
  echo "### 🟠 LOW (${TIER_LOW}-${TIER_MEDIUM}%) - Flagged for review"
  jq -r --argjson hi "$TIER_MEDIUM" --argjson lo "$TIER_LOW" '.learnings[] | select(.effectiveness_score >= $lo and .effectiveness_score < $hi) | "- \(.id): \(.effectiveness_score)%"' "$LEARNINGS_FILE" 2>/dev/null || echo "  (none)"
  echo ""
  
  # Ineffective tier
  echo "### 🔴 INEFFECTIVE (<${TIER_LOW}%) - Queue for pruning"
  jq -r --argjson th "$TIER_LOW" '.learnings[] | select(.effectiveness_score < $th) | "- \(.id): \(.effectiveness_score)%"' "$LEARNINGS_FILE" 2>/dev/null || echo "  (none)"
}

cmd_prune() {
  init_learnings
  
  echo "[INFO] Checking for learnings to prune..."
  
  # Find ineffective learnings with enough applications
  local to_prune
  to_prune=$(jq -r --argjson th "$TIER_LOW" --argjson min "$PRUNE_FAILURES" '
    .learnings[] | 
    select(.effectiveness_score < $th and (.applications | length) >= $min) | 
    .id
  ' "$LEARNINGS_FILE" 2>/dev/null || echo "")
  
  if [[ -z "$to_prune" ]]; then
    echo "[INFO] No learnings ready for pruning"
    return
  fi
  
  echo "Learnings to prune:"
  echo "$to_prune" | while read -r id; do
    [[ -z "$id" ]] && continue
    echo "  - $id"
  done
  
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[DRY-RUN] Would archive above learnings"
    return
  fi
  
  # Archive each learning
  mkdir -p "$SKILLS_ARCHIVED"
  
  echo "$to_prune" | while read -r id; do
    [[ -z "$id" ]] && continue
    
    # Move skill directory if exists
    local skill_dir="${PROJECT_ROOT}/grimoires/loa/skills/${id}"
    if [[ -d "$skill_dir" ]]; then
      mv "$skill_dir" "$SKILLS_ARCHIVED/"
      echo "[INFO] Archived skill: $id"
    fi
    
    # Update learning status
    jq --arg id "$id" '
      .learnings |= map(if .id == $id then .status = "archived" else . end)
    ' "$LEARNINGS_FILE" > "${LEARNINGS_FILE}.tmp"
    mv "${LEARNINGS_FILE}.tmp" "$LEARNINGS_FILE"
  done
}

cmd_report() {
  init_learnings
  
  local period
  period=${MONTH:-$(date -u +%Y-%m)}
  
  echo "# Learning Effectiveness Report"
  echo ""
  echo "**Period:** $period"
  echo "**Generated:** $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo ""
  
  # Top helpful learnings
  echo "## Top $TOP_N Most Helpful Learnings"
  echo ""
  jq -r --argjson n "$TOP_N" '
    .learnings | sort_by(-.effectiveness_score) | .[0:$n] | 
    to_entries | .[] | 
    "\(.key + 1). **\(.value.id)** - \(.value.effectiveness_score)% effective"
  ' "$LEARNINGS_FILE" 2>/dev/null || echo "*(No data)*"
  echo ""
  
  # Top applied learnings
  echo "## Top $TOP_N Most Applied Learnings"
  echo ""
  jq -r --argjson n "$TOP_N" '
    .learnings | sort_by(-(.applications | length)) | .[0:$n] | 
    to_entries | .[] | 
    "\(.key + 1). **\(.value.id)** - \(.value.applications | length) applications"
  ' "$LEARNINGS_FILE" 2>/dev/null || echo "*(No data)*"
  echo ""
  
  # Summary
  echo "## Summary"
  echo ""
  local total high_count low_count
  total=$(jq '.learnings | length' "$LEARNINGS_FILE" 2>/dev/null || echo "0")
  high_count=$(jq --argjson th "$TIER_HIGH" '[.learnings[] | select(.effectiveness_score >= $th)] | length' "$LEARNINGS_FILE" 2>/dev/null || echo "0")
  low_count=$(jq --argjson th "$TIER_LOW" '[.learnings[] | select(.effectiveness_score < $th)] | length' "$LEARNINGS_FILE" 2>/dev/null || echo "0")
  
  echo "| Metric | Value |"
  echo "|--------|-------|"
  echo "| Total Learnings | $total |"
  echo "| High Effectiveness | $high_count |"
  echo "| Ready for Pruning | $low_count |"
}

cmd_review() {
  init_learnings
  
  echo "## Learnings Flagged for Review"
  echo ""
  
  jq -r --argjson hi "$TIER_MEDIUM" --argjson lo "$TIER_LOW" '
    .learnings[] | 
    select(.effectiveness_score >= $lo and .effectiveness_score < $hi) | 
    "- **\(.id)** (\(.effectiveness_score)%)\n  Applications: \(.applications | length)\n"
  ' "$LEARNINGS_FILE" 2>/dev/null || echo "*(No learnings flagged for review)*"
}

main() {
  parse_args "$@"
  load_config
  
  case "$SUBCOMMAND" in
    tiers) cmd_tiers ;;
    prune) cmd_prune ;;
    report) cmd_report ;;
    review) cmd_review ;;
    "") cmd_tiers ;;  # Default
    *) echo "[ERROR] Unknown subcommand: $SUBCOMMAND" >&2; usage ;;
  esac
}

main "$@"
