#!/bin/bash
# =============================================================================
# compound-orchestrator.sh - /compound Command Orchestrator
# =============================================================================
# Sprint 7: Main orchestrator for the /compound command
# Goal Contribution: G-1, G-2, G-3 (Complete compound learning cycle)
#
# Usage:
#   ./compound-orchestrator.sh [subcommand] [options]
#
# Subcommands:
#   (default)    Run full compound review
#   status       Show compound learning status
#   changelog    Generate cycle changelog
#   archive      Archive cycle artifacts
#
# Options:
#   --dry-run        Preview without making changes
#   --review-only    Extract without promotion
#   --no-promote     Skip skill promotion
#   --no-archive     Skip archive creation
#   --force          Skip confirmation prompts
#   --cycle N        Specify cycle number
#   --days N         Override date range
#   --help           Show this help
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_FILE="${PROJECT_ROOT}/.loa.config.yaml"
LEDGER_FILE="${PROJECT_ROOT}/grimoires/loa/ledger.json"
NOTES_FILE="${PROJECT_ROOT}/grimoires/loa/NOTES.md"
COMPOUND_DIR="${PROJECT_ROOT}/grimoires/loa/a2a/compound"
TRAJECTORY_DIR="${PROJECT_ROOT}/grimoires/loa/a2a/trajectory"
SKILLS_PENDING="${PROJECT_ROOT}/grimoires/loa/skills-pending"
SKILLS_ACTIVE="${PROJECT_ROOT}/grimoires/loa/skills"

# Parameters
SUBCOMMAND=""
DRY_RUN=false
REVIEW_ONLY=false
NO_PROMOTE=false
NO_ARCHIVE=false
FORCE=false
CYCLE_NUM=""
DAYS=""

# State
CYCLE_START=""
CYCLE_END=""
PATTERNS_FOUND=0
SKILLS_EXTRACTED=0
SKILLS_PROMOTED=0

# Usage
usage() {
  sed -n '/^# Usage:/,/^# =====/p' "$0" | grep -v "^# =====" | sed 's/^# //'
  exit 0
}

# Parse arguments
parse_args() {
  # Check for subcommand
  if [[ $# -gt 0 && ! "$1" =~ ^-- ]]; then
    SUBCOMMAND="$1"
    shift
  fi
  
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run)
        DRY_RUN=true
        shift
        ;;
      --review-only)
        REVIEW_ONLY=true
        shift
        ;;
      --no-promote)
        NO_PROMOTE=true
        shift
        ;;
      --no-archive)
        NO_ARCHIVE=true
        shift
        ;;
      --force)
        FORCE=true
        shift
        ;;
      --cycle)
        CYCLE_NUM="$2"
        shift 2
        ;;
      --days)
        DAYS="$2"
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

# Log trajectory event
log_event() {
  local event_type="$1"
  local details="$2"
  
  local today
  today=$(date -u +%Y-%m-%d)
  local timestamp
  timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  
  local log_file="${TRAJECTORY_DIR}/compound-learning-${today}.jsonl"
  
  local event
  event=$(jq -n \
    --arg ts "$timestamp" \
    --arg type "$event_type" \
    --arg agent "compound-orchestrator" \
    --arg details "$details" \
    '{timestamp: $ts, type: $type, agent: $agent, details: $details}')
  
  if [[ "$DRY_RUN" == "false" ]]; then
    echo "$event" >> "$log_file"
  fi
}

# Detect current cycle from ledger
detect_cycle() {
  if [[ ! -f "$LEDGER_FILE" ]]; then
    echo "[WARN] Ledger not found at $LEDGER_FILE"
    # Default to last 30 days
    local today
    today=$(date -u +%Y-%m-%d)
    if [[ "$(uname)" == "Darwin" ]]; then
      CYCLE_START=$(date -v-30d +%Y-%m-%d)
    else
      CYCLE_START=$(date -d "$today - 30 days" +%Y-%m-%d)
    fi
    CYCLE_END="$today"
    return
  fi
  
  # Find active or most recent cycle
  local cycle_info
  if [[ -n "$CYCLE_NUM" ]]; then
    cycle_info=$(jq -r --arg num "$CYCLE_NUM" '
      .cycles[] | select(.id == "cycle-" + $num or .number == ($num | tonumber))
    ' "$LEDGER_FILE" 2>/dev/null || echo "")
  else
    # Get most recent cycle
    cycle_info=$(jq -r '.cycles | last' "$LEDGER_FILE" 2>/dev/null || echo "")
  fi
  
  if [[ -z "$cycle_info" || "$cycle_info" == "null" ]]; then
    echo "[WARN] No cycle found in ledger, using last 30 days"
    local today
    today=$(date -u +%Y-%m-%d)
    if [[ "$(uname)" == "Darwin" ]]; then
      CYCLE_START=$(date -v-30d +%Y-%m-%d)
    else
      CYCLE_START=$(date -d "$today - 30 days" +%Y-%m-%d)
    fi
    CYCLE_END="$today"
    return
  fi
  
  CYCLE_START=$(echo "$cycle_info" | jq -r '.start_date // empty')
  CYCLE_END=$(echo "$cycle_info" | jq -r '.end_date // empty')
  
  # Use current date if end_date not set
  [[ -z "$CYCLE_END" ]] && CYCLE_END=$(date -u +%Y-%m-%d)
}

# =========================================================================
# Subcommand: status
# =========================================================================
cmd_status() {
  echo "## Compound Learning Status"
  echo ""
  
  # Cycle info
  detect_cycle
  echo "### Current Cycle"
  echo "- Date Range: $CYCLE_START to $CYCLE_END"
  
  # Patterns
  local pattern_count=0
  if [[ -f "${COMPOUND_DIR}/patterns.json" ]]; then
    pattern_count=$(jq '.patterns | length' "${COMPOUND_DIR}/patterns.json" 2>/dev/null || echo "0")
  fi
  echo "- Patterns Detected: $pattern_count"
  
  # Pending skills
  local pending_count=0
  if [[ -d "$SKILLS_PENDING" ]]; then
    pending_count=$(find "$SKILLS_PENDING" -name "SKILL.md" 2>/dev/null | wc -l | tr -d ' ')
  fi
  echo "- Skills Pending: $pending_count"
  
  # Active skills
  local active_count=0
  if [[ -d "$SKILLS_ACTIVE" ]]; then
    active_count=$(find "$SKILLS_ACTIVE" -name "SKILL.md" 2>/dev/null | wc -l | tr -d ' ')
  fi
  echo "- Skills Active: $active_count"
  
  # Recent activity
  echo ""
  echo "### Recent Trajectory Events"
  local today
  today=$(date -u +%Y-%m-%d)
  local log_file="${TRAJECTORY_DIR}/compound-learning-${today}.jsonl"
  if [[ -f "$log_file" ]]; then
    tail -5 "$log_file" | jq -r '"[\(.timestamp | split("T")[1] | split(".")[0])] \(.type)"' 2>/dev/null || echo "  (no recent events)"
  else
    echo "  (no compound events today)"
  fi
}

# =========================================================================
# Subcommand: changelog
# =========================================================================
cmd_changelog() {
  echo "[INFO] Generating changelog..."
  
  detect_cycle
  
  # This will be implemented in Sprint 9
  echo "[INFO] Changelog generation (Sprint 9)"
  echo "  Cycle: $CYCLE_START to $CYCLE_END"
  echo "  (Full implementation in Sprint 9)"
}

# =========================================================================
# Subcommand: archive
# =========================================================================
cmd_archive() {
  echo "[INFO] Creating archive..."
  
  detect_cycle
  
  # This will be implemented in Sprint 9
  echo "[INFO] Archive creation (Sprint 9)"
  echo "  Cycle: $CYCLE_START to $CYCLE_END"
  echo "  (Full implementation in Sprint 9)"
}

# =========================================================================
# Main: Run full compound review
# =========================================================================
cmd_review() {
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║           COMPOUND LEARNING - CYCLE REVIEW                   ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  echo ""
  
  # Step 1: Detect cycle
  echo "[1/6] Detecting cycle..."
  detect_cycle
  echo "  Cycle period: $CYCLE_START to $CYCLE_END"
  
  # Override with --days if specified
  if [[ -n "$DAYS" ]]; then
    local today
    today=$(date -u +%Y-%m-%d)
    if [[ "$(uname)" == "Darwin" ]]; then
      CYCLE_START=$(date -v-"${DAYS}d" +%Y-%m-%d)
    else
      CYCLE_START=$(date -d "$today - $DAYS days" +%Y-%m-%d)
    fi
    CYCLE_END="$today"
    echo "  Overridden with --days $DAYS: $CYCLE_START to $CYCLE_END"
  fi
  
  # Log start
  log_event "compound_start" "cycle=$CYCLE_START:$CYCLE_END"
  
  # Step 2: Batch retrospective
  echo ""
  echo "[2/6] Running batch retrospective..."
  local retro_args="--start $CYCLE_START --end $CYCLE_END"
  [[ "$DRY_RUN" == "true" ]] && retro_args+=" --dry-run"
  [[ "$FORCE" == "true" ]] && retro_args+=" --force"
  
  # shellcheck disable=SC2086
  "$SCRIPT_DIR/batch-retrospective.sh" $retro_args --output json > /tmp/compound-patterns.json 2>/dev/null || true
  
  # Count patterns
  if [[ -f /tmp/compound-patterns.json ]]; then
    PATTERNS_FOUND=$(jq 'length' /tmp/compound-patterns.json 2>/dev/null || echo "0")
  fi
  echo "  Found $PATTERNS_FOUND patterns"
  
  # Step 3: Quality gates
  echo ""
  echo "[3/6] Applying quality gates..."
  local qualified_patterns="[]"
  if [[ "$PATTERNS_FOUND" -gt 0 && -f /tmp/compound-patterns.json ]]; then
    qualified_patterns=$("$SCRIPT_DIR/quality-gates.sh" --patterns /tmp/compound-patterns.json --output json 2>/dev/null || echo "[]")
    local qualified_count
    qualified_count=$(echo "$qualified_patterns" | jq '[.[] | select(.passes == true)] | length')
    echo "  $qualified_count patterns passed quality gates"
  else
    echo "  No patterns to evaluate"
  fi
  
  # Step 4: Extract skills
  echo ""
  echo "[4/6] Extracting skills..."
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "  [DRY-RUN] Would extract skills"
    SKILLS_EXTRACTED=$(echo "$qualified_patterns" | jq '[.[] | select(.passes == true)] | length')
  else
    # Generate skills for qualified patterns
    echo "$qualified_patterns" | jq -c '.[] | select(.passes == true) | .pattern' | while read -r pattern; do
      [[ -z "$pattern" || "$pattern" == "null" ]] && continue
      echo "$pattern" | "$SCRIPT_DIR/generate-skill-from-pattern.sh" --stdin 2>/dev/null || true
      SKILLS_EXTRACTED=$((SKILLS_EXTRACTED + 1))
    done
    echo "  Extracted $SKILLS_EXTRACTED skills to skills-pending/"
  fi
  
  # Step 5: Consolidation (unless review-only)
  echo ""
  echo "[5/6] Consolidation..."
  if [[ "$REVIEW_ONLY" == "true" ]]; then
    echo "  Skipped (--review-only)"
  elif [[ "$DRY_RUN" == "true" ]]; then
    echo "  [DRY-RUN] Would update NOTES.md and ledger"
  else
    # Update patterns registry
    "$SCRIPT_DIR/update-patterns-registry.sh" 2>/dev/null || true
    
    # Promote skills (unless --no-promote)
    if [[ "$NO_PROMOTE" == "false" && -d "$SKILLS_PENDING" ]]; then
      prompt_skill_promotion
    fi
    
    echo "  Updated patterns.json"
  fi
  
  # Step 6: Archive (unless review-only or no-archive)
  echo ""
  echo "[6/6] Archive & Changelog..."
  if [[ "$REVIEW_ONLY" == "true" || "$NO_ARCHIVE" == "true" ]]; then
    echo "  Skipped (--review-only or --no-archive)"
  elif [[ "$DRY_RUN" == "true" ]]; then
    echo "  [DRY-RUN] Would create archive and changelog"
  else
    # Archive and changelog (Sprint 9)
    echo "  (Full implementation in Sprint 9)"
  fi
  
  # Log completion
  log_event "compound_complete" "patterns=$PATTERNS_FOUND,extracted=$SKILLS_EXTRACTED,promoted=$SKILLS_PROMOTED"
  
  # Summary
  echo ""
  echo "════════════════════════════════════════════════════════════════"
  echo "                      COMPOUND REVIEW COMPLETE"
  echo "════════════════════════════════════════════════════════════════"
  echo ""
  echo "  Patterns Found:    $PATTERNS_FOUND"
  echo "  Skills Extracted:  $SKILLS_EXTRACTED"
  echo "  Skills Promoted:   $SKILLS_PROMOTED"
  echo ""
  
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "  (Dry run - no changes made)"
  fi
  
  # Cleanup
  rm -f /tmp/compound-patterns.json
}

# Prompt for skill promotion
prompt_skill_promotion() {
  if [[ "$FORCE" == "true" ]]; then
    # Auto-promote in force mode
    promote_all_skills
    return
  fi
  
  local pending_count
  pending_count=$(find "$SKILLS_PENDING" -name "SKILL.md" 2>/dev/null | wc -l | tr -d ' ')
  
  if [[ "$pending_count" -eq 0 ]]; then
    echo "  No skills pending for promotion"
    return
  fi
  
  echo ""
  echo "  Found $pending_count skills pending promotion."
  echo "  Promote to active skills?"
  echo "    [Y] Promote all"
  echo "    [n] Skip promotion"
  echo "    [s] Select individually (not implemented)"
  echo ""
  read -r -p "  Choice [Y/n/s]: " choice
  
  case "$choice" in
    n|N)
      echo "  Promotion skipped"
      ;;
    *)
      promote_all_skills
      ;;
  esac
}

# Promote all pending skills
promote_all_skills() {
  if [[ ! -d "$SKILLS_PENDING" ]]; then
    return
  fi
  
  mkdir -p "$SKILLS_ACTIVE"
  
  for skill_dir in "$SKILLS_PENDING"/*/; do
    [[ ! -d "$skill_dir" ]] && continue
    
    local skill_name
    skill_name=$(basename "$skill_dir")
    
    # Move to active
    if [[ ! -d "${SKILLS_ACTIVE}/${skill_name}" ]]; then
      mv "$skill_dir" "$SKILLS_ACTIVE/"
      SKILLS_PROMOTED=$((SKILLS_PROMOTED + 1))
      echo "  Promoted: $skill_name"
    else
      echo "  Skipped (exists): $skill_name"
    fi
  done
}

# Main
main() {
  parse_args "$@"
  
  # Ensure directories exist
  mkdir -p "$COMPOUND_DIR" "$TRAJECTORY_DIR"
  
  case "$SUBCOMMAND" in
    status)
      cmd_status
      ;;
    changelog)
      cmd_changelog
      ;;
    archive)
      cmd_archive
      ;;
    ""|review)
      cmd_review
      ;;
    *)
      echo "[ERROR] Unknown subcommand: $SUBCOMMAND" >&2
      usage
      ;;
  esac
}

main "$@"
