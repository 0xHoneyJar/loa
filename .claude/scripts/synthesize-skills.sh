#!/bin/bash
# =============================================================================
# synthesize-skills.sh - Skill Synthesis Engine
# =============================================================================
# Sprint 14: Generate merged skills from skill clusters
# Goal Contribution: G-3 (Automate knowledge consolidation)
#
# Usage:
#   ./synthesize-skills.sh [subcommand] [options]
#
# Subcommands:
#   scan      Scan for synthesis candidates (default)
#   propose   Generate merge proposals
#   apply     Apply approved proposal
#
# Options:
#   --cluster ID        Specific cluster to process
#   --proposal ID       Proposal ID to apply
#   --dry-run           Preview without changes
#   --help              Show this help
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SKILLS_DIR="${PROJECT_ROOT}/grimoires/loa/skills"
SKILLS_PENDING="${PROJECT_ROOT}/grimoires/loa/skills-pending"
SKILLS_ARCHIVED="${PROJECT_ROOT}/grimoires/loa/skills-archived"
SYNTHESIS_FILE="${PROJECT_ROOT}/grimoires/loa/a2a/compound/synthesis-queue.json"
TRAJECTORY_DIR="${PROJECT_ROOT}/grimoires/loa/a2a/trajectory"
CONFIG_FILE="${PROJECT_ROOT}/.loa.config.yaml"

SUBCOMMAND="scan"
CLUSTER_ID=""
PROPOSAL_ID=""
DRY_RUN=false

usage() {
  sed -n '/^# Usage:/,/^# =====/p' "$0" | grep -v "^# =====" | sed 's/^# //'
  exit 0
}

parse_args() {
  [[ $# -gt 0 && ! "$1" =~ ^-- ]] && { SUBCOMMAND="$1"; shift; }
  
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --cluster) CLUSTER_ID="$2"; shift 2 ;;
      --proposal) PROPOSAL_ID="$2"; shift 2 ;;
      --dry-run) DRY_RUN=true; shift ;;
      --help|-h) usage ;;
      *) shift ;;
    esac
  done
}

init_synthesis_file() {
  if [[ ! -f "$SYNTHESIS_FILE" ]]; then
    mkdir -p "$(dirname "$SYNTHESIS_FILE")"
    echo '{"version":"1.0","proposals":[]}' > "$SYNTHESIS_FILE"
  fi
}

log_event() {
  local event_type="$1"
  local details="$2"
  
  local today timestamp log_file
  today=$(date -u +%Y-%m-%d)
  timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  log_file="${TRAJECTORY_DIR}/compound-learning-${today}.jsonl"
  
  local event
  event=$(jq -n \
    --arg ts "$timestamp" \
    --arg type "$event_type" \
    --arg details "$details" \
    '{timestamp: $ts, type: $type, agent: "synthesis-engine", details: $details}')
  
  mkdir -p "$TRAJECTORY_DIR"
  echo "$event" >> "$log_file"
}

# Extract content from SKILL.md
get_skill_content() {
  local skill_name="$1"
  local skill_file="${SKILLS_DIR}/${skill_name}/SKILL.md"
  
  if [[ -f "$skill_file" ]]; then
    cat "$skill_file"
  fi
}

# Generate merged skill name
generate_merged_name() {
  local skills="$1"
  
  # Extract common prefix or use generic name
  local first_skill
  first_skill=$(echo "$skills" | jq -r '.[0]')
  
  local prefix
  prefix=$(echo "$first_skill" | cut -d'-' -f1)
  
  echo "${prefix}-best-practices"
}

# Generate merged SKILL.md content
generate_merged_skill() {
  local skills="$1"
  local merged_name="$2"
  
  local skill_count
  skill_count=$(echo "$skills" | jq 'length')
  
  local skill_list
  skill_list=$(echo "$skills" | jq -r '.[]')
  
  # Collect triggers and solutions from all skills
  local triggers=""
  local solutions=""
  
  while IFS= read -r skill_name; do
    [[ -z "$skill_name" ]] && continue
    local content
    content=$(get_skill_content "$skill_name")
    
    # Extract trigger section
    local skill_triggers
    skill_triggers=$(echo "$content" | sed -n '/## Trigger/,/^## /p' | head -n -1)
    [[ -n "$skill_triggers" ]] && triggers+="$skill_triggers\n"
    
    # Extract solution section
    local skill_solutions
    skill_solutions=$(echo "$content" | sed -n '/## Solution/,/^## /p' | head -n -1)
    [[ -n "$skill_solutions" ]] && solutions+="$skill_solutions\n"
  done <<< "$skill_list"
  
  # Generate merged SKILL.md
  cat << EOF
---
name: $merged_name
type: compound-learning
source: synthesis
merged_from: $(echo "$skills" | jq -c '.')
created: $(date -u +%Y-%m-%dT%H:%M:%SZ)
status: pending
---

# $merged_name

Consolidated skill merged from $skill_count related skills for improved maintainability.

## Merged From

$(echo "$skills" | jq -r '.[] | "- \(.)"')

## Trigger Conditions

$(echo -e "$triggers" | head -20)

## Solution

$(echo -e "$solutions" | head -30)

## Verification

To verify this consolidated skill is applied correctly:

1. The original issues covered by source skills should not recur
2. The solution should be maintainable
3. Consider archiving source skills if fully subsumed

---

*This skill was automatically synthesized by the Compound Learning System.*
*Review and approve with \`/skill-audit --approve\`*
EOF
}

cmd_scan() {
  echo "[INFO] Scanning for synthesis candidates..."
  
  local clusters
  clusters=$("$SCRIPT_DIR/cluster-skills.sh" --output json 2>/dev/null || echo "[]")
  
  local count
  count=$(echo "$clusters" | jq 'length')
  
  if [[ "$count" -eq 0 ]]; then
    echo "[INFO] No synthesis candidates found"
    return
  fi
  
  echo "[INFO] Found $count potential clusters:"
  echo ""
  echo "$clusters" | jq -r '.[] | "Cluster: \(.cluster_id)\n  Skills: \(.skills | join(", "))\n"'
}

cmd_propose() {
  init_synthesis_file
  
  echo "[INFO] Generating synthesis proposals..."
  
  local clusters
  clusters=$("$SCRIPT_DIR/cluster-skills.sh" --output json 2>/dev/null || echo "[]")
  
  local count
  count=$(echo "$clusters" | jq 'length')
  
  if [[ "$count" -eq 0 ]]; then
    echo "[INFO] No clusters to propose"
    return
  fi
  
  local timestamp
  timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  
  echo "$clusters" | jq -c '.[]' | while read -r cluster; do
    local cluster_id skills skill_count
    cluster_id=$(echo "$cluster" | jq -r '.cluster_id')
    skills=$(echo "$cluster" | jq '.skills')
    skill_count=$(echo "$cluster" | jq '.skill_count')
    
    # Skip if specific cluster requested and not matching
    [[ -n "$CLUSTER_ID" && "$cluster_id" != "$CLUSTER_ID" ]] && continue
    
    local merged_name
    merged_name=$(generate_merged_name "$skills")
    
    local proposal_id
    proposal_id="synth-$(date +%Y%m%d%H%M%S)-$(echo "$cluster_id" | md5sum | cut -c1-6)"
    
    local merged_content
    merged_content=$(generate_merged_skill "$skills" "$merged_name")
    
    if [[ "$DRY_RUN" == "true" ]]; then
      echo "[DRY-RUN] Would create proposal: $proposal_id"
      echo "  Merged name: $merged_name"
      echo "  Source skills: $(echo "$skills" | jq -r 'join(", ")')"
      echo ""
      echo "--- Preview ---"
      echo "$merged_content" | head -30
      echo "..."
    else
      # Add to synthesis queue
      jq --arg id "$proposal_id" \
         --arg ts "$timestamp" \
         --argjson skills "$skills" \
         --arg name "$merged_name" \
         --arg content "$merged_content" \
         '
         .proposals += [{
           id: $id,
           status: "pending",
           created: $ts,
           source_skills: $skills,
           merged_skill_name: $name,
           content: $content
         }]
         ' "$SYNTHESIS_FILE" > "${SYNTHESIS_FILE}.tmp"
      mv "${SYNTHESIS_FILE}.tmp" "$SYNTHESIS_FILE"
      
      log_event "synthesis_proposed" "id=$proposal_id,skills=$(echo "$skills" | jq -c '.')"
      
      echo "[INFO] Created proposal: $proposal_id"
    fi
  done
}

cmd_apply() {
  if [[ -z "$PROPOSAL_ID" ]]; then
    echo "[ERROR] --proposal ID required" >&2
    return 1
  fi
  
  init_synthesis_file
  
  local proposal
  proposal=$(jq --arg id "$PROPOSAL_ID" '.proposals[] | select(.id == $id)' "$SYNTHESIS_FILE")
  
  if [[ -z "$proposal" || "$proposal" == "null" ]]; then
    echo "[ERROR] Proposal not found: $PROPOSAL_ID" >&2
    return 1
  fi
  
  local merged_name content source_skills
  merged_name=$(echo "$proposal" | jq -r '.merged_skill_name')
  content=$(echo "$proposal" | jq -r '.content')
  source_skills=$(echo "$proposal" | jq '.source_skills')
  
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[DRY-RUN] Would apply proposal: $PROPOSAL_ID"
    echo "  Create: skills-pending/$merged_name/SKILL.md"
    echo "  Archive: $(echo "$source_skills" | jq -r 'join(", ")')"
    return
  fi
  
  # Create merged skill
  local merged_dir="${SKILLS_PENDING}/${merged_name}"
  mkdir -p "$merged_dir"
  echo "$content" > "${merged_dir}/SKILL.md"
  echo "[INFO] Created merged skill: $merged_dir"
  
  # Optionally archive source skills
  local archive_sources
  archive_sources=$(yq -e '.compound_learning.synthesis.archive_on_synthesis // false' "$CONFIG_FILE" 2>/dev/null || echo "false")
  
  if [[ "$archive_sources" == "true" ]]; then
    mkdir -p "$SKILLS_ARCHIVED"
    echo "$source_skills" | jq -r '.[]' | while read -r skill; do
      local skill_dir="${SKILLS_DIR}/${skill}"
      if [[ -d "$skill_dir" ]]; then
        mv "$skill_dir" "$SKILLS_ARCHIVED/"
        echo "[INFO] Archived source skill: $skill"
      fi
    done
  fi
  
  # Update proposal status
  jq --arg id "$PROPOSAL_ID" '
    .proposals |= map(if .id == $id then .status = "applied" else . end)
  ' "$SYNTHESIS_FILE" > "${SYNTHESIS_FILE}.tmp"
  mv "${SYNTHESIS_FILE}.tmp" "$SYNTHESIS_FILE"
  
  log_event "synthesis_approved" "id=$PROPOSAL_ID,merged=$merged_name"
  
  echo "[INFO] Applied proposal: $PROPOSAL_ID"
}

main() {
  parse_args "$@"
  
  case "$SUBCOMMAND" in
    scan) cmd_scan ;;
    propose) cmd_propose ;;
    apply) cmd_apply ;;
    *) echo "[ERROR] Unknown subcommand: $SUBCOMMAND" >&2; usage ;;
  esac
}

main "$@"
