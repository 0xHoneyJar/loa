#!/bin/bash
# =============================================================================
# update-notes-learnings.sh - Update NOTES.md Learnings Section
# =============================================================================
# Sprint 8, Task 8.2: Update NOTES.md ## Learnings section with extracted skills
#
# Usage:
#   ./update-notes-learnings.sh [options]
#   cat learnings.json | ./update-notes-learnings.sh --stdin
#
# Options:
#   --stdin          Read learnings from stdin (JSON array)
#   --learnings FILE Read learnings from file
#   --dry-run        Show what would be added
#   --help           Show this help
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
NOTES_FILE="${PROJECT_ROOT}/grimoires/loa/NOTES.md"

# Parameters
READ_STDIN=false
LEARNINGS_FILE=""
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
      --learnings)
        LEARNINGS_FILE="$2"
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

# Initialize NOTES.md if needed
init_notes() {
  if [[ ! -f "$NOTES_FILE" ]]; then
    mkdir -p "$(dirname "$NOTES_FILE")"
    cat > "$NOTES_FILE" << 'EOF'
# Session Notes

## Session Continuity

*Session context will be added here.*

## Decision Log

*Decisions will be logged here.*

## Learnings

*Extracted learnings will be added here.*

EOF
    echo "[INFO] Created $NOTES_FILE"
  fi
}

# Get learnings from input
get_learnings() {
  if [[ "$READ_STDIN" == "true" ]]; then
    cat
  elif [[ -n "$LEARNINGS_FILE" && -f "$LEARNINGS_FILE" ]]; then
    cat "$LEARNINGS_FILE"
  else
    # Read from patterns.json and filter qualified
    local patterns_file="${PROJECT_ROOT}/grimoires/loa/a2a/compound/patterns.json"
    if [[ -f "$patterns_file" ]]; then
      jq '.patterns // []' "$patterns_file"
    else
      echo "[]"
    fi
  fi
}

# Format learnings for NOTES.md
format_learnings() {
  local learnings="$1"
  local count
  count=$(echo "$learnings" | jq 'length')
  
  if [[ "$count" -eq 0 ]]; then
    echo "No new learnings to add."
    return
  fi
  
  local today
  today=$(date -u +%Y-%m-%d)
  
  echo "### Learnings from $today"
  echo ""
  
  echo "$learnings" | jq -r '.[] | 
    "**\(.signature // .id // "Learning")**\n" +
    "- Type: \(.type // "pattern")\n" +
    "- Confidence: \((.confidence // 0) * 100 | floor)%\n" +
    "- Sessions: \(.sessions | if type == "array" then join(", ") else . end // "N/A")\n"
  '
}

# Check if Learnings section exists
has_learnings_section() {
  grep -q "^## Learnings" "$NOTES_FILE" 2>/dev/null
}

# Add Learnings section if missing
ensure_learnings_section() {
  if ! has_learnings_section; then
    echo "" >> "$NOTES_FILE"
    echo "## Learnings" >> "$NOTES_FILE"
    echo "" >> "$NOTES_FILE"
    echo "*Extracted learnings will be added here.*" >> "$NOTES_FILE"
    echo "" >> "$NOTES_FILE"
  fi
}

# Update NOTES.md
update_notes() {
  local learnings
  learnings=$(get_learnings)
  
  local formatted
  formatted=$(format_learnings "$learnings")
  
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[DRY-RUN] Would add to NOTES.md ## Learnings:"
    echo ""
    echo "$formatted"
    return
  fi
  
  init_notes
  ensure_learnings_section
  
  # Find the Learnings section and append after it
  # Create a temp file with the new content
  local temp_file
  temp_file=$(mktemp) || { echo "mktemp failed" >&2; return 1; }
  chmod 600 "$temp_file"  # CRITICAL-001 FIX
  
  local in_learnings=false
  local added=false
  
  while IFS= read -r line; do
    echo "$line" >> "$temp_file"
    
    if [[ "$line" =~ ^##[[:space:]]+Learnings ]]; then
      in_learnings=true
    elif [[ "$in_learnings" == "true" && "$line" =~ ^## ]]; then
      # New section started, add learnings before it
      if [[ "$added" == "false" ]]; then
        echo "" >> "$temp_file"
        echo "$formatted" >> "$temp_file"
        echo "" >> "$temp_file"
        added=true
      fi
      in_learnings=false
    fi
  done < "$NOTES_FILE"
  
  # If we never hit another section, add at end
  if [[ "$added" == "false" ]]; then
    echo "" >> "$temp_file"
    echo "$formatted" >> "$temp_file"
  fi
  
  mv "$temp_file" "$NOTES_FILE"
  echo "[INFO] Updated NOTES.md with new learnings"
}

# Main
main() {
  parse_args "$@"
  update_notes
}

main "$@"
