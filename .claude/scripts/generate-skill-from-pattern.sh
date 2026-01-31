#!/bin/bash
# =============================================================================
# generate-skill-from-pattern.sh - Generate SKILL.md from Qualified Pattern
# =============================================================================
# Sprint 6, Tasks 6.5-6.7: Generate skill files from patterns
# Goal Contribution: G-2 (Reduce repeated work), G-3 (Knowledge consolidation)
#
# Usage:
#   ./generate-skill-from-pattern.sh --pattern 'JSON' [options]
#   cat pattern.json | ./generate-skill-from-pattern.sh --stdin
#
# Options:
#   --stdin             Read pattern from stdin
#   --pattern JSON      Pattern JSON to convert
#   --output-dir DIR    Output directory (default: grimoires/loa/skills-pending)
#   --dry-run           Show what would be generated without writing
#   --help              Show this help
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TRAJECTORY_DIR="${PROJECT_ROOT}/grimoires/loa/a2a/trajectory"

# Parameters
READ_STDIN=false
PATTERN_JSON=""
OUTPUT_DIR="${PROJECT_ROOT}/grimoires/loa/skills-pending"
DRY_RUN=false

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
      --pattern)
        PATTERN_JSON="$2"
        shift 2
        ;;
      --output-dir)
        OUTPUT_DIR="$2"
        shift 2
        ;;
      --dry-run)
        DRY_RUN=true
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

# Get pattern
get_pattern() {
  if [[ "$READ_STDIN" == "true" ]]; then
    cat
  elif [[ -n "$PATTERN_JSON" ]]; then
    echo "$PATTERN_JSON"
  else
    echo "[ERROR] No pattern provided" >&2
    exit 1
  fi
}

# Generate skill name from pattern
generate_skill_name() {
  local pattern="$1"
  
  local signature
  signature=$(echo "$pattern" | jq -r '.signature // "unknown"')
  
  # Clean up signature to make a valid directory name
  local name
  name=$(echo "$signature" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '-' | sed 's/-$//' | head -c 50)
  
  # Ensure it's not empty
  [[ -z "$name" ]] && name="pattern-$(date +%s)"
  
  echo "$name"
}

# Generate skill description
generate_description() {
  local pattern="$1"
  
  local pattern_type
  pattern_type=$(echo "$pattern" | jq -r '.type // "pattern"')
  
  local signature
  signature=$(echo "$pattern" | jq -r '.signature // ""')
  
  local occurrences
  occurrences=$(echo "$pattern" | jq '.occurrence_count // 1')
  
  local sessions
  sessions=$(echo "$pattern" | jq '.sessions | length')
  
  echo "Skill extracted from $pattern_type pattern. Detected $occurrences times across $sessions session(s). Pattern: $signature"
}

# Generate trigger conditions
generate_triggers() {
  local pattern="$1"
  
  local error_keywords
  error_keywords=$(echo "$pattern" | jq -r '.error_keywords // []')
  
  if [[ "$error_keywords" != "[]" ]]; then
    echo "## Trigger Conditions"
    echo ""
    echo "This skill applies when you encounter:"
    echo ""
    echo "$error_keywords" | jq -r '.[] | "- \(.)"'
    echo ""
  fi
}

# Generate solution steps
generate_solution() {
  local pattern="$1"
  
  local solution_keywords
  solution_keywords=$(echo "$pattern" | jq -r '.solution_keywords // []')
  
  echo "## Solution"
  echo ""
  
  if [[ "$solution_keywords" != "[]" && $(echo "$solution_keywords" | jq 'length') -gt 0 ]]; then
    echo "Key approaches discovered:"
    echo ""
    echo "$solution_keywords" | jq -r '.[] | "1. \(.)"' | head -5
  else
    echo "*(Solution details to be documented)*"
  fi
  echo ""
}

# Generate provenance section
generate_provenance() {
  local pattern="$1"
  
  local first_seen last_seen sessions confidence
  first_seen=$(echo "$pattern" | jq -r '.first_seen // "unknown"')
  last_seen=$(echo "$pattern" | jq -r '.last_seen // "unknown"')
  sessions=$(echo "$pattern" | jq -r '.sessions // []')
  confidence=$(echo "$pattern" | jq '.confidence // 0')
  
  echo "## Provenance"
  echo ""
  echo "| Property | Value |"
  echo "|----------|-------|"
  echo "| First Seen | $first_seen |"
  echo "| Last Seen | $last_seen |"
  echo "| Confidence | $(awk "BEGIN {printf \"%.0f\", $confidence * 100}")% |"
  echo "| Sessions | $(echo "$sessions" | jq -r 'join(", ")') |"
  echo ""
}

# Generate verification section
generate_verification() {
  local pattern="$1"
  
  echo "## Verification"
  echo ""
  echo "To verify this skill is applied correctly:"
  echo ""
  echo "1. The original error/issue should not recur"
  echo "2. The solution should be maintainable"
  echo "3. No new issues introduced by the fix"
  echo ""
}

# Generate SKILL.md content
generate_skill_md() {
  local pattern="$1"
  local skill_name="$2"
  
  local description
  description=$(generate_description "$pattern")
  
  local pattern_type
  pattern_type=$(echo "$pattern" | jq -r '.type // "pattern"')
  
  local confidence
  confidence=$(echo "$pattern" | jq '.confidence // 0')
  
  local confidence_pct
  confidence_pct=$(awk "BEGIN {printf \"%.0f\", $confidence * 100}")
  
  # Generate frontmatter
  cat << EOF
---
name: $skill_name
type: compound-learning
source: pattern-detection
pattern_type: $pattern_type
confidence: $confidence_pct
created: $(date -u +%Y-%m-%dT%H:%M:%SZ)
status: pending
---

# $skill_name

$description

EOF

  # Generate sections
  generate_triggers "$pattern"
  generate_solution "$pattern"
  generate_provenance "$pattern"
  generate_verification "$pattern"
  
  # Add footer
  cat << 'EOF'
---

*This skill was automatically extracted by the Compound Learning System.*
*Review and approve with `/skill-audit --approve`*
EOF
}

# Log trajectory event
log_extraction_event() {
  local skill_name="$1"
  local pattern_id="$2"
  
  local today
  today=$(date -u +%Y-%m-%d)
  local timestamp
  timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  
  local log_file="${TRAJECTORY_DIR}/compound-learning-${today}.jsonl"
  
  local event
  event=$(jq -n \
    --arg ts "$timestamp" \
    --arg skill "$skill_name" \
    --arg pattern "$pattern_id" \
    '{
      timestamp: $ts,
      type: "learning_extracted",
      agent: "skill-generator",
      skill_id: $skill,
      source_pattern: $pattern
    }')
  
  echo "$event" >> "$log_file"
}

# Main
main() {
  parse_args "$@"
  
  local pattern
  pattern=$(get_pattern)
  
  # Validate pattern
  if ! echo "$pattern" | jq -e . >/dev/null 2>&1; then
    echo "[ERROR] Invalid pattern JSON" >&2
    exit 1
  fi
  
  # Generate skill name
  local skill_name
  skill_name=$(generate_skill_name "$pattern")
  
  # Generate content
  local skill_content
  skill_content=$(generate_skill_md "$pattern" "$skill_name")
  
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[DRY-RUN] Would generate skill: $skill_name"
    echo "[DRY-RUN] Output directory: $OUTPUT_DIR/$skill_name/"
    echo ""
    echo "--- SKILL.md preview ---"
    echo "$skill_content"
  else
    # Create output directory
    local skill_dir="${OUTPUT_DIR}/${skill_name}"
    mkdir -p "$skill_dir"
    
    # Write SKILL.md
    echo "$skill_content" > "${skill_dir}/SKILL.md"
    
    # Log extraction event
    local pattern_id
    pattern_id=$(echo "$pattern" | jq -r '.id // "unknown"')
    log_extraction_event "$skill_name" "$pattern_id"
    
    echo "[INFO] Generated skill: $skill_dir/SKILL.md"
  fi
}

main "$@"
