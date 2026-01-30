#!/bin/bash
# =============================================================================
# update-ledger-compound.sh - Update Ledger with Compound Completion
# =============================================================================
# Sprint 8, Task 8.1: Update ledger.json when compound review completes
#
# Usage:
#   ./update-ledger-compound.sh [options]
#
# Options:
#   --cycle N            Cycle number to update
#   --learnings N        Number of learnings extracted
#   --patterns N         Number of patterns detected
#   --skills-promoted N  Number of skills promoted
#   --dry-run            Show what would be updated
#   --help               Show this help
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LEDGER_FILE="${PROJECT_ROOT}/grimoires/loa/ledger.json"

# Parameters
CYCLE_NUM=""
LEARNINGS=0
PATTERNS=0
SKILLS_PROMOTED=0
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
      --cycle)
        CYCLE_NUM="$2"
        shift 2
        ;;
      --learnings)
        LEARNINGS="$2"
        shift 2
        ;;
      --patterns)
        PATTERNS="$2"
        shift 2
        ;;
      --skills-promoted)
        SKILLS_PROMOTED="$2"
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

# Initialize ledger if needed
init_ledger() {
  if [[ ! -f "$LEDGER_FILE" ]]; then
    mkdir -p "$(dirname "$LEDGER_FILE")"
    cat > "$LEDGER_FILE" << 'EOF'
{
  "version": "1.0",
  "project": "compound-learning",
  "created": null,
  "cycles": []
}
EOF
    # Set created timestamp
    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    jq --arg ts "$now" '.created = $ts' "$LEDGER_FILE" > "${LEDGER_FILE}.tmp"
    mv "${LEDGER_FILE}.tmp" "$LEDGER_FILE"
  fi
}

# Get current cycle number
get_current_cycle() {
  if [[ -n "$CYCLE_NUM" ]]; then
    echo "$CYCLE_NUM"
    return
  fi
  
  local count
  count=$(jq '.cycles | length' "$LEDGER_FILE" 2>/dev/null || echo "0")
  
  if [[ "$count" -eq 0 ]]; then
    echo "1"
  else
    echo "$count"
  fi
}

# Update ledger with compound completion
update_ledger() {
  local cycle_num
  cycle_num=$(get_current_cycle)
  
  local now
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  
  # Build update
  local update_json
  update_json=$(jq -n \
    --arg ts "$now" \
    --argjson learnings "$LEARNINGS" \
    --argjson patterns "$PATTERNS" \
    --argjson promoted "$SKILLS_PROMOTED" \
    '{
      compound_completed_at: $ts,
      compound_metrics: {
        patterns_detected: $patterns,
        learnings_extracted: $learnings,
        skills_promoted: $promoted
      }
    }')
  
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[DRY-RUN] Would update cycle $cycle_num in ledger:"
    echo "$update_json" | jq .
    return
  fi
  
  # Check if cycle exists
  local cycle_exists
  cycle_exists=$(jq --arg num "$cycle_num" '
    .cycles | map(select(.number == ($num | tonumber) or .id == "cycle-" + $num)) | length > 0
  ' "$LEDGER_FILE")
  
  if [[ "$cycle_exists" == "true" ]]; then
    # Update existing cycle
    jq --arg num "$cycle_num" --argjson update "$update_json" '
      .cycles |= map(
        if .number == ($num | tonumber) or .id == "cycle-" + $num then
          . + $update
        else
          .
        end
      )
    ' "$LEDGER_FILE" > "${LEDGER_FILE}.tmp"
    mv "${LEDGER_FILE}.tmp" "$LEDGER_FILE"
    echo "[INFO] Updated cycle $cycle_num in ledger"
  else
    # Create new cycle entry
    local new_cycle
    new_cycle=$(jq -n \
      --arg num "$cycle_num" \
      --arg ts "$now" \
      --argjson update "$update_json" \
      '{
        id: "cycle-" + $num,
        number: ($num | tonumber),
        created_at: $ts
      } + $update')
    
    jq --argjson cycle "$new_cycle" '.cycles += [$cycle]' "$LEDGER_FILE" > "${LEDGER_FILE}.tmp"
    mv "${LEDGER_FILE}.tmp" "$LEDGER_FILE"
    echo "[INFO] Created cycle $cycle_num in ledger"
  fi
}

# Main
main() {
  parse_args "$@"
  init_ledger
  update_ledger
}

main "$@"
