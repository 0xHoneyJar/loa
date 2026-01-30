#!/bin/bash
# =============================================================================
# batch-retrospective.sh - Batch Retrospective Orchestrator
# =============================================================================
# Sprint 5: Implements /retrospective --batch command
# Goal Contribution: G-1 (Cross-session pattern detection)
#
# Usage:
#   ./batch-retrospective.sh [options]
#
# Options:
#   --days N              Analyze last N days (default: 7)
#   --sprint N            Analyze sprint N (overrides --days)
#   --start DATE          Start date (YYYY-MM-DD)
#   --end DATE            End date (YYYY-MM-DD)
#   --dry-run             Show findings without writing
#   --min-confidence N    Minimum pattern confidence 0-1 (default: 0.6)
#   --output FORMAT       Output format: markdown (default), json
#   --force               Skip confirmation prompts
#   --sprint-plan         Called from /run sprint-plan (Task 8.8)
#   --help                Show this help
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_FILE="${PROJECT_ROOT}/.loa.config.yaml"
TRAJECTORY_DIR="${PROJECT_ROOT}/grimoires/loa/a2a/trajectory"
COMPOUND_DIR="${PROJECT_ROOT}/grimoires/loa/a2a/compound"

# Parameters
DAYS=7
SPRINT=""
START_DATE=""
END_DATE=""
DRY_RUN=false
MIN_CONFIDENCE=0.6
OUTPUT_FORMAT="markdown"
FORCE=false
SPRINT_PLAN_MODE=false

# State
PATTERNS_FOUND=0
SKILLS_EXTRACTED=0

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
      --sprint)
        SPRINT="$2"
        shift 2
        ;;
      --start)
        START_DATE="$2"
        shift 2
        ;;
      --end)
        END_DATE="$2"
        shift 2
        ;;
      --dry-run)
        DRY_RUN=true
        shift
        ;;
      --min-confidence)
        MIN_CONFIDENCE="$2"
        shift 2
        ;;
      --output)
        OUTPUT_FORMAT="$2"
        shift 2
        ;;
      --force)
        FORCE=true
        shift
        ;;
      --sprint-plan)
        SPRINT_PLAN_MODE=true
        FORCE=true  # Auto-approve in sprint-plan mode
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

# Log trajectory event
log_trajectory_event() {
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
    --arg agent "batch-retrospective" \
    --arg details "$details" \
    '{timestamp: $ts, type: $type, agent: $agent, details: $details}')
  
  echo "$event" >> "$log_file"
}

# Calculate date range from sprint
get_sprint_date_range() {
  local sprint_num="$1"
  local ledger_file="${PROJECT_ROOT}/grimoires/loa/ledger.json"
  
  if [[ ! -f "$ledger_file" ]]; then
    echo "[WARN] Ledger not found, using --days $DAYS instead" >&2
    return 1
  fi
  
  # Extract sprint dates from ledger
  local sprint_info
  sprint_info=$(jq -r --arg num "$sprint_num" '
    .cycles[].sprints[] | select(.id == ("sprint-" + $num) or .number == ($num | tonumber))
  ' "$ledger_file" 2>/dev/null || echo "")
  
  if [[ -z "$sprint_info" ]]; then
    echo "[WARN] Sprint $sprint_num not found in ledger" >&2
    return 1
  fi
  
  START_DATE=$(echo "$sprint_info" | jq -r '.start_date // empty')
  END_DATE=$(echo "$sprint_info" | jq -r '.end_date // empty')
  
  if [[ -z "$START_DATE" || -z "$END_DATE" ]]; then
    return 1
  fi
  
  return 0
}

# Run pattern detection pipeline
run_pattern_detection() {
  echo "[INFO] Starting batch retrospective analysis..."
  
  # Log start event
  if [[ "$DRY_RUN" == "false" ]]; then
    log_trajectory_event "compound_review_start" "days=$DAYS,min_confidence=$MIN_CONFIDENCE"
  fi
  
  # Build args for trajectory reader
  local reader_args=""
  if [[ -n "$START_DATE" ]]; then
    reader_args+=" --start $START_DATE"
  fi
  if [[ -n "$END_DATE" ]]; then
    reader_args+=" --end $END_DATE"
  fi
  if [[ -z "$START_DATE" && -z "$END_DATE" ]]; then
    reader_args+=" --days $DAYS"
  fi
  
  # Step 1: Get trajectory summary
  echo "[INFO] Step 1/4: Collecting trajectory data..."
  local summary
  # shellcheck disable=SC2086
  summary=$("$SCRIPT_DIR/get-trajectory-summary.sh" $reader_args 2>/dev/null || echo '{"total_events":0}')
  
  local event_count
  event_count=$(echo "$summary" | jq '.total_events // 0')
  echo "  Found $event_count events"
  
  if [[ "$event_count" -eq 0 ]]; then
    echo "[INFO] No events found in date range"
    return 0
  fi
  
  # Step 2: Cluster events
  echo "[INFO] Step 2/4: Clustering events..."
  local clusters
  # shellcheck disable=SC2086
  clusters=$("$SCRIPT_DIR/cluster-events.sh" $reader_args --min-cluster 2 --output json 2>/dev/null || echo "[]")
  
  local cluster_count
  cluster_count=$(echo "$clusters" | jq 'length')
  echo "  Found $cluster_count clusters"
  
  # Step 3: Filter by confidence
  echo "[INFO] Step 3/4: Filtering by confidence (>= $MIN_CONFIDENCE)..."
  local qualified
  qualified=$(echo "$clusters" | jq --argjson min "$MIN_CONFIDENCE" '[.[] | select(.confidence >= $min)]')
  
  local qualified_count
  qualified_count=$(echo "$qualified" | jq 'length')
  echo "  $qualified_count patterns meet confidence threshold"
  
  PATTERNS_FOUND="$qualified_count"
  
  # Step 4: Log pattern events
  if [[ "$DRY_RUN" == "false" && "$qualified_count" -gt 0 ]]; then
    echo "[INFO] Step 4/4: Logging pattern events..."
    echo "$qualified" | jq -c '.[]' | while read -r pattern; do
      local sig
      sig=$(echo "$pattern" | jq -r '.signature')
      log_trajectory_event "pattern_detected" "signature=$sig"
    done
  else
    echo "[INFO] Step 4/4: Skipped (dry-run or no patterns)"
  fi
  
  # Output results
  echo ""
  output_results "$qualified"
}

# Output results based on format
output_results() {
  local patterns="$1"
  local count
  count=$(echo "$patterns" | jq 'length')
  
  case "$OUTPUT_FORMAT" in
    json)
      echo "$patterns"
      ;;
    markdown|*)
      output_markdown "$patterns"
      ;;
  esac
}

# Output in markdown format
output_markdown() {
  local patterns="$1"
  local count
  count=$(echo "$patterns" | jq 'length')
  
  echo "## Cross-Session Patterns Found"
  echo ""
  
  if [[ "$count" -eq 0 ]]; then
    echo "No patterns found meeting the confidence threshold ($MIN_CONFIDENCE)."
    echo ""
    echo "Try:"
    echo "- Increasing the date range with \`--days N\`"
    echo "- Lowering the confidence threshold with \`--min-confidence N\`"
    return
  fi
  
  # Group by confidence tier
  local high_patterns mid_patterns low_patterns
  high_patterns=$(echo "$patterns" | jq '[.[] | select(.confidence >= 0.8)]')
  mid_patterns=$(echo "$patterns" | jq '[.[] | select(.confidence >= 0.5 and .confidence < 0.8)]')
  low_patterns=$(echo "$patterns" | jq '[.[] | select(.confidence < 0.5)]')
  
  # High confidence
  local high_count
  high_count=$(echo "$high_patterns" | jq 'length')
  if [[ "$high_count" -gt 0 ]]; then
    echo "### 🔴 HIGH Confidence (80%+)"
    echo ""
    echo "$high_patterns" | jq -r '.[] | "**\(.signature)** (\(.pattern_type))\n- Occurred \(.event_count) times across \(.session_count) sessions\n- Sessions: \(.first_seen) to \(.last_seen)\n- Confidence: \(.confidence * 100 | floor)%\n"'
  fi
  
  # Medium confidence
  local mid_count
  mid_count=$(echo "$mid_patterns" | jq 'length')
  if [[ "$mid_count" -gt 0 ]]; then
    echo "### 🟡 MEDIUM Confidence (50-79%)"
    echo ""
    echo "$mid_patterns" | jq -r '.[] | "**\(.signature)** (\(.pattern_type))\n- Occurred \(.event_count) times across \(.session_count) sessions\n- Sessions: \(.first_seen) to \(.last_seen)\n- Confidence: \(.confidence * 100 | floor)%\n"'
  fi
  
  # Low confidence (if any passed threshold but still low)
  local low_count
  low_count=$(echo "$low_patterns" | jq 'length')
  if [[ "$low_count" -gt 0 ]]; then
    echo "### 🟢 LOW Confidence (<50%)"
    echo ""
    echo "$low_patterns" | jq -r '.[] | "**\(.signature)** (\(.pattern_type))\n- Occurred \(.event_count) times\n- Confidence: \(.confidence * 100 | floor)%\n"'
  fi
  
  # Summary
  echo "---"
  echo ""
  echo "**Summary:** Found $count patterns ($high_count high, $mid_count medium confidence)"
  
  if [[ "$DRY_RUN" == "true" ]]; then
    echo ""
    echo "*(Dry run - no changes made)*"
  fi
}

# Prompt for extraction
prompt_extraction() {
  if [[ "$FORCE" == "true" || "$DRY_RUN" == "true" ]]; then
    return
  fi
  
  if [[ "$PATTERNS_FOUND" -eq 0 ]]; then
    return
  fi
  
  echo ""
  echo "Extract patterns as skills?"
  echo "  [Y] Extract all qualified patterns"
  echo "  [n] Skip extraction"
  echo "  [s] Select specific patterns"
  echo ""
  read -r -p "Choice [Y/n/s]: " choice
  
  case "$choice" in
    n|N)
      echo "[INFO] Extraction skipped"
      ;;
    s|S)
      echo "[INFO] Selection mode not yet implemented - extracting all"
      extract_skills
      ;;
    *)
      extract_skills
      ;;
  esac
}

# Extract skills from patterns
extract_skills() {
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[DRY-RUN] Would extract $PATTERNS_FOUND skills"
    return
  fi
  
  echo "[INFO] Extracting skills..."
  
  # Update patterns registry
  "$SCRIPT_DIR/update-patterns-registry.sh" 2>/dev/null || true
  
  SKILLS_EXTRACTED="$PATTERNS_FOUND"
  
  # Log extraction events
  log_trajectory_event "learning_extracted" "count=$SKILLS_EXTRACTED"
  
  echo "[INFO] Extracted $SKILLS_EXTRACTED patterns to registry"
}

# Finalize and log completion
finalize() {
  if [[ "$DRY_RUN" == "false" ]]; then
    log_trajectory_event "compound_review_complete" "patterns=$PATTERNS_FOUND,extracted=$SKILLS_EXTRACTED"
  fi
  
  echo ""
  echo "[COMPLETE] Batch retrospective finished"
  echo "  Patterns found: $PATTERNS_FOUND"
  echo "  Skills extracted: $SKILLS_EXTRACTED"
}

# Main
main() {
  parse_args "$@"
  
  # Handle sprint mode
  if [[ -n "$SPRINT" ]]; then
    if ! get_sprint_date_range "$SPRINT"; then
      echo "[INFO] Falling back to --days $DAYS"
    fi
  fi
  
  # Ensure compound directory exists
  mkdir -p "$COMPOUND_DIR"
  
  # Run analysis
  run_pattern_detection
  
  # Prompt for extraction (unless force or dry-run)
  prompt_extraction
  
  # Finalize
  finalize
}

main "$@"
