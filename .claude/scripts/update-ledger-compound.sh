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

# The compound ledger also supports its original v1 schema, so validate its
# actual contract here rather than imposing the Sprint Ledger's schema.
validate_content() {
  jq -e -s 'length == 1 and (.[0] | type == "object" and
    (.cycles | type == "array") and all(.cycles[]; type == "object"))' >/dev/null
}

# The caller holds the lock across the read, transformation and replacement.
update_ledger() {
  local now content cycle_num
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  if [[ -e "$LEDGER_FILE" ]]; then
    content=$(cat "$LEDGER_FILE") || return 1
  else
    content=$(jq -n --arg ts "$now" \
      '{version:"1.0", project:"compound-learning", created:$ts, cycles:[]}') || return 1
  fi
  if ! printf '%s\n' "$content" | validate_content; then
    echo "[ERROR] Ledger must contain exactly one object with a cycles array" >&2
    return 1
  fi
  cycle_num="${CYCLE_NUM:-}"
  if [[ -z "$cycle_num" ]]; then
    cycle_num=$(printf '%s\n' "$content" | jq '.cycles | length | if . == 0 then 1 else . end') || return 1
  fi

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
  
  local updated tmp
  updated=$(printf '%s\n' "$content" | jq -a --arg num "$cycle_num" \
    --arg ts "$now" --argjson update "$update_json" '
      def matches: .number == ($num | tonumber) or .id == ("cycle-" + $num);
      if any(.cycles[]; matches) then
        .cycles |= map(if matches then . + $update else . end)
      else
        .cycles += [({id: ("cycle-" + $num), number: ($num | tonumber), created_at: $ts} + $update)]
      end') || return 1
  if ! printf '%s\n' "$updated" | validate_content; then
    echo "[ERROR] Refusing invalid or empty ledger update" >&2
    return 1
  fi
  tmp=$(mktemp "${LEDGER_FILE}.tmp.XXXXXXXX") || return 1
  if ! printf '%s\n' "$updated" > "$tmp" || ! mv "$tmp" "$LEDGER_FILE"; then
    rm -f "$tmp"
    return 1
  fi
  echo "[INFO] Updated cycle $cycle_num in ledger"
}

# Main
main() {
  parse_args "$@"
  if [[ -n "$CYCLE_NUM" && ! "$CYCLE_NUM" =~ ^[1-9][0-9]*$ ]]; then
    echo "[ERROR] --cycle must be a positive integer" >&2
    return 1
  fi
  local count
  for count in "$LEARNINGS" "$PATTERNS" "$SKILLS_PROMOTED"; do
    if [[ ! "$count" =~ ^(0|[1-9][0-9]*)$ ]]; then
      echo "[ERROR] Metrics must be non-negative integers" >&2
      return 1
    fi
  done
  if [[ "$DRY_RUN" == true ]]; then
    update_ledger
  else
    mkdir -p "$(dirname "$LEDGER_FILE")"
    (
      flock -w 5 9 || { echo "[ERROR] Ledger lock timeout" >&2; exit 1; }
      update_ledger
    ) 9>"${LEDGER_FILE}.lock"
  fi
}

main "$@"
