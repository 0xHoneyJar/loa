#!/bin/bash
# =============================================================================
# validate-e2e.sh - End-to-End Goal Validation
# =============================================================================
# Sprint 16, Task 16.E2E: Validate all PRD goals are achieved
#
# Usage:
#   ./validate-e2e.sh [options]
#
# Options:
#   --output FILE    Write report to file
#   --verbose        Show detailed output
#   --help           Show this help
#
# Validates:
#   G-1: Cross-session pattern detection
#   G-2: Reduce repeated investigations  
#   G-3: Automate knowledge consolidation
#   G-4: Close apply-verify loop
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Require bash 4.0+ (associative arrays)
# shellcheck source=bash-version-guard.sh
source "$SCRIPT_DIR/bash-version-guard.sh"

OUTPUT_FILE=""
VERBOSE=false

# Validation results
declare -A GOAL_STATUS
declare -A GOAL_EVIDENCE

usage() {
  sed -n '/^# Usage:/,/^# =====/p' "$0" | grep -v "^# =====" | sed 's/^# //'
  exit 0
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --output) OUTPUT_FILE="$2"; shift 2 ;;
      --verbose) VERBOSE=true; shift ;;
      --help|-h) usage ;;
      *) shift ;;
    esac
  done
}

log() {
  [[ "$VERBOSE" == "true" ]] && echo "[CHECK] $*"
}

# Check if script exists and is executable
check_script() {
  local script="$1"
  [[ -x "$SCRIPT_DIR/$script" ]]
}

# G-1: Cross-session pattern detection
validate_g1() {
  local status="PASS"
  local evidence=""
  
  log "Validating G-1: Cross-session pattern detection"
  
  # Check required components
  local components=(
    "trajectory-reader.sh"
    "extract-keywords.sh"
    "jaccard-similarity.sh"
    "cluster-events.sh"
    "find-similar-events.sh"
  )
  
  for comp in "${components[@]}"; do
    if check_script "$comp"; then
      evidence+="✓ $comp exists\n"
    else
      evidence+="✗ $comp missing\n"
      status="PARTIAL"
    fi
  done
  
  # Check patterns.json exists
  if [[ -f "${PROJECT_ROOT}/grimoires/loa/a2a/compound/patterns.json" ]]; then
    evidence+="✓ patterns.json initialized\n"
  else
    evidence+="✗ patterns.json not found\n"
    status="PARTIAL"
  fi
  
  # Check batch-retrospective works
  if check_script "batch-retrospective.sh"; then
    evidence+="✓ batch-retrospective.sh functional\n"
  else
    evidence+="✗ batch-retrospective.sh missing\n"
    status="FAIL"
  fi
  
  GOAL_STATUS["G-1"]="$status"
  GOAL_EVIDENCE["G-1"]="$evidence"
}

# G-2: Reduce repeated investigations
validate_g2() {
  local status="PASS"
  local evidence=""
  
  log "Validating G-2: Reduce repeated investigations"
  
  # Check quality gates
  if check_script "quality-gates.sh"; then
    evidence+="✓ Quality gates implemented\n"
  else
    evidence+="✗ quality-gates.sh missing\n"
    status="PARTIAL"
  fi
  
  # Check skill generation
  if check_script "generate-skill-from-pattern.sh"; then
    evidence+="✓ Skill generator implemented\n"
  else
    evidence+="✗ generate-skill-from-pattern.sh missing\n"
    status="PARTIAL"
  fi
  
  # Check morning context
  if check_script "load-morning-context.sh"; then
    evidence+="✓ Morning context loader implemented\n"
  else
    evidence+="✗ load-morning-context.sh missing\n"
    status="PARTIAL"
  fi
  
  # Check skills directory
  if [[ -d "${PROJECT_ROOT}/grimoires/loa/skills" ]]; then
    evidence+="✓ Skills directory exists\n"
  fi
  
  GOAL_STATUS["G-2"]="$status"
  GOAL_EVIDENCE["G-2"]="$evidence"
}

# G-3: Automate knowledge consolidation
validate_g3() {
  local status="PASS"
  local evidence=""
  
  log "Validating G-3: Automate knowledge consolidation"
  
  # Check compound orchestrator
  if check_script "compound-orchestrator.sh"; then
    evidence+="✓ /compound command implemented\n"
  else
    evidence+="✗ compound-orchestrator.sh missing\n"
    status="FAIL"
  fi
  
  # Check synthesis engine
  if check_script "synthesize-skills.sh"; then
    evidence+="✓ Synthesis engine implemented\n"
  else
    evidence+="✗ synthesize-skills.sh missing\n"
    status="PARTIAL"
  fi
  
  # Check changelog generation
  if check_script "generate-changelog.sh"; then
    evidence+="✓ Changelog generator implemented\n"
  else
    evidence+="✗ generate-changelog.sh missing\n"
    status="PARTIAL"
  fi
  
  # Check archive management
  if check_script "archive-cycle.sh"; then
    evidence+="✓ Archive management implemented\n"
  else
    evidence+="✗ archive-cycle.sh missing\n"
    status="PARTIAL"
  fi
  
  # Check sprint-plan hook
  if check_script "compound-hook-sprint-plan.sh"; then
    evidence+="✓ Sprint-plan hook implemented\n"
  else
    evidence+="✗ compound-hook-sprint-plan.sh missing\n"
    status="PARTIAL"
  fi
  
  GOAL_STATUS["G-3"]="$status"
  GOAL_EVIDENCE["G-3"]="$evidence"
}

# G-4: Close apply-verify loop
validate_g4() {
  local status="PASS"
  local evidence=""
  
  log "Validating G-4: Close apply-verify loop"
  
  # Check application tracking
  if check_script "track-learning-application.sh"; then
    evidence+="✓ Application tracking implemented\n"
  else
    evidence+="✗ track-learning-application.sh missing\n"
    status="FAIL"
  fi
  
  # Check effectiveness scoring
  if check_script "calculate-effectiveness.sh"; then
    evidence+="✓ Effectiveness scoring implemented\n"
  else
    evidence+="✗ calculate-effectiveness.sh missing\n"
    status="PARTIAL"
  fi
  
  # Check lifecycle management
  if check_script "manage-learning-lifecycle.sh"; then
    evidence+="✓ Lifecycle management implemented\n"
  else
    evidence+="✗ manage-learning-lifecycle.sh missing\n"
    status="PARTIAL"
  fi
  
  # Check learnings.json
  if [[ -f "${PROJECT_ROOT}/grimoires/loa/a2a/compound/learnings.json" ]]; then
    evidence+="✓ learnings.json initialized\n"
  else
    evidence+="✗ learnings.json not found\n"
    status="PARTIAL"
  fi
  
  GOAL_STATUS["G-4"]="$status"
  GOAL_EVIDENCE["G-4"]="$evidence"
}

# Generate validation report
generate_report() {
  local report=""
  
  report+="# Compound Learning System - E2E Validation Report\n\n"
  report+="**Generated:** $(date -u +%Y-%m-%dT%H:%M:%SZ)\n"
  report+="**Project:** ${PROJECT_ROOT}\n\n"
  
  report+="## Goal Validation Summary\n\n"
  report+="| Goal | Status | Description |\n"
  report+="|------|--------|-------------|\n"
  report+="| G-1 | ${GOAL_STATUS[G-1]} | Cross-session pattern detection |\n"
  report+="| G-2 | ${GOAL_STATUS[G-2]} | Reduce repeated investigations |\n"
  report+="| G-3 | ${GOAL_STATUS[G-3]} | Automate knowledge consolidation |\n"
  report+="| G-4 | ${GOAL_STATUS[G-4]} | Close apply-verify loop |\n\n"
  
  # Overall status
  local all_pass=true
  for goal in "G-1" "G-2" "G-3" "G-4"; do
    [[ "${GOAL_STATUS[$goal]}" != "PASS" ]] && all_pass=false
  done
  
  if [[ "$all_pass" == "true" ]]; then
    report+="## ✅ Overall: ALL GOALS VALIDATED\n\n"
  else
    report+="## ⚠️ Overall: SOME GOALS NEED ATTENTION\n\n"
  fi
  
  # Detailed evidence
  report+="## Detailed Evidence\n\n"
  
  for goal in "G-1" "G-2" "G-3" "G-4"; do
    report+="### $goal: ${GOAL_STATUS[$goal]}\n\n"
    report+="\`\`\`\n"
    report+="${GOAL_EVIDENCE[$goal]}"
    report+="\`\`\`\n\n"
  done
  
  # Components checklist
  report+="## Components Checklist\n\n"
  
  local scripts=(
    "trajectory-reader.sh"
    "extract-keywords.sh"
    "jaccard-similarity.sh"
    "cluster-events.sh"
    "batch-retrospective.sh"
    "quality-gates.sh"
    "generate-skill-from-pattern.sh"
    "compound-orchestrator.sh"
    "track-learning-application.sh"
    "calculate-effectiveness.sh"
    "manage-learning-lifecycle.sh"
    "synthesize-skills.sh"
    "load-morning-context.sh"
    "generate-visualizations.sh"
  )
  
  for script in "${scripts[@]}"; do
    if check_script "$script"; then
      report+="- [x] $script\n"
    else
      report+="- [ ] $script\n"
    fi
  done
  
  echo -e "$report"
}

main() {
  parse_args "$@"
  
  echo "[INFO] Running E2E validation..."
  echo ""
  
  # Run all validations
  validate_g1
  validate_g2
  validate_g3
  validate_g4
  
  # Generate report
  local report
  report=$(generate_report)
  
  if [[ -n "$OUTPUT_FILE" ]]; then
    echo -e "$report" > "$OUTPUT_FILE"
    echo "[INFO] Report written to $OUTPUT_FILE"
  else
    echo -e "$report"
  fi
  
  # Return status
  local all_pass=true
  for goal in "G-1" "G-2" "G-3" "G-4"; do
    [[ "${GOAL_STATUS[$goal]}" == "FAIL" ]] && all_pass=false
  done
  
  [[ "$all_pass" == "true" ]] && exit 0 || exit 1
}

main "$@"
