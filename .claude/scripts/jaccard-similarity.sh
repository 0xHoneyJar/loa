#!/bin/bash
# =============================================================================
# jaccard-similarity.sh - Jaccard Similarity Calculator
# =============================================================================
# Sprint 3, Task 3.2: Calculate Jaccard similarity between keyword sets
# Goal Contribution: G-1 (Cross-session pattern detection), G-2 (Reduce repeated work)
#
# Usage:
#   ./jaccard-similarity.sh --set-a "word1,word2,word3" --set-b "word2,word3,word4"
#   ./jaccard-similarity.sh --file-a keywords1.txt --file-b keywords2.txt
#   ./jaccard-similarity.sh --text-a "some text" --text-b "other text"
#
# Options:
#   --set-a WORDS    Comma-separated keywords for set A
#   --set-b WORDS    Comma-separated keywords for set B
#   --file-a FILE    File with keywords (one per line) for set A
#   --file-b FILE    File with keywords (one per line) for set B
#   --text-a TEXT    Raw text to extract keywords for set A
#   --text-b TEXT    Raw text to extract keywords for set B
#   --threshold N    Return 1 if similarity >= threshold, 0 otherwise
#   --json           Output as JSON with details
#   --help           Show this help
#
# Output:
#   Similarity score 0.0-1.0 (or JSON with intersection/union details)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Parameters
SET_A=""
SET_B=""
FILE_A=""
FILE_B=""
TEXT_A=""
TEXT_B=""
THRESHOLD=""
JSON_OUTPUT=false

# Usage
usage() {
  sed -n '/^# Usage:/,/^# =====/p' "$0" | grep -v "^# =====" | sed 's/^# //'
  exit 0
}

# Parse arguments
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --set-a)
        SET_A="$2"
        shift 2
        ;;
      --set-b)
        SET_B="$2"
        shift 2
        ;;
      --file-a)
        FILE_A="$2"
        shift 2
        ;;
      --file-b)
        FILE_B="$2"
        shift 2
        ;;
      --text-a)
        TEXT_A="$2"
        shift 2
        ;;
      --text-b)
        TEXT_B="$2"
        shift 2
        ;;
      --threshold)
        THRESHOLD="$2"
        shift 2
        ;;
      --json)
        JSON_OUTPUT=true
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

# Get keywords from comma-separated string
keywords_from_set() {
  local set="$1"
  echo "$set" | tr ',' '\n' | tr '[:upper:]' '[:lower:]' | sort -u
}

# Get keywords from file
keywords_from_file() {
  local file="$1"
  if [[ -f "$file" ]]; then
    cat "$file" | tr '[:upper:]' '[:lower:]' | sort -u
  fi
}

# Get keywords from text using extract-keywords.sh
keywords_from_text() {
  local text="$1"
  local extractor="${SCRIPT_DIR}/extract-keywords.sh"
  
  if [[ -x "$extractor" ]]; then
    echo "$text" | "$extractor" --technical
  else
    # Fallback: simple word extraction
    echo "$text" | tr -cs '[:alnum:]' '\n' | tr '[:upper:]' '[:lower:]' | sort -u | grep -E '^[a-z]{3,}' || true
  fi
}

# Build keyword set A
build_set_a() {
  if [[ -n "$SET_A" ]]; then
    keywords_from_set "$SET_A"
  elif [[ -n "$FILE_A" ]]; then
    keywords_from_file "$FILE_A"
  elif [[ -n "$TEXT_A" ]]; then
    keywords_from_text "$TEXT_A"
  fi
}

# Build keyword set B
build_set_b() {
  if [[ -n "$SET_B" ]]; then
    keywords_from_set "$SET_B"
  elif [[ -n "$FILE_B" ]]; then
    keywords_from_file "$FILE_B"
  elif [[ -n "$TEXT_B" ]]; then
    keywords_from_text "$TEXT_B"
  fi
}

# Calculate Jaccard similarity
# J(A,B) = |A ∩ B| / |A ∪ B|
calculate_jaccard() {
  local set_a_file=$(mktemp) || { echo "mktemp failed" >&2; return 1; }
  chmod 600 "$set_a_file"  # CRITICAL-001 FIX
  local set_b_file=$(mktemp) || { rm -f "$set_a_file"; echo "mktemp failed" >&2; return 1; }
  chmod 600 "$set_b_file"  # CRITICAL-001 FIX
  
  build_set_a > "$set_a_file"
  build_set_b > "$set_b_file"
  
  local count_a
  local count_b
  count_a=$(wc -l < "$set_a_file" | tr -d ' ')
  count_b=$(wc -l < "$set_b_file" | tr -d ' ')
  
  # Handle empty sets
  if [[ "$count_a" -eq 0 && "$count_b" -eq 0 ]]; then
    rm -f "$set_a_file" "$set_b_file"
    if [[ "$JSON_OUTPUT" == "true" ]]; then
      echo '{"similarity":1.0,"intersection":0,"union":0,"set_a_size":0,"set_b_size":0}'
    else
      echo "1.0"
    fi
    return
  fi
  
  if [[ "$count_a" -eq 0 || "$count_b" -eq 0 ]]; then
    rm -f "$set_a_file" "$set_b_file"
    if [[ "$JSON_OUTPUT" == "true" ]]; then
      echo "{\"similarity\":0.0,\"intersection\":0,\"union\":$((count_a + count_b)),\"set_a_size\":$count_a,\"set_b_size\":$count_b}"
    else
      echo "0.0"
    fi
    return
  fi
  
  # Calculate intersection and union
  local intersection_file=$(mktemp) || { rm -f "$set_a_file" "$set_b_file"; return 1; }
  chmod 600 "$intersection_file"  # CRITICAL-001 FIX
  local union_file=$(mktemp) || { rm -f "$set_a_file" "$set_b_file" "$intersection_file"; return 1; }
  chmod 600 "$union_file"  # CRITICAL-001 FIX
  
  comm -12 "$set_a_file" "$set_b_file" > "$intersection_file"
  sort -u "$set_a_file" "$set_b_file" > "$union_file"
  
  local intersection_count
  local union_count
  intersection_count=$(wc -l < "$intersection_file" | tr -d ' ')
  union_count=$(wc -l < "$union_file" | tr -d ' ')
  
  # Calculate similarity
  local similarity
  if [[ "$union_count" -eq 0 ]]; then
    similarity="0.0"
  else
    # Use awk for floating point division
    similarity=$(awk "BEGIN {printf \"%.4f\", $intersection_count / $union_count}")
  fi
  
  # Output
  if [[ "$JSON_OUTPUT" == "true" ]]; then
    local intersection_words
    intersection_words=$(cat "$intersection_file" | jq -R -s 'split("\n") | map(select(length > 0))')
    
    jq -n \
      --argjson sim "$similarity" \
      --argjson int "$intersection_count" \
      --argjson uni "$union_count" \
      --argjson sza "$count_a" \
      --argjson szb "$count_b" \
      --argjson words "$intersection_words" \
      '{
        similarity: $sim,
        intersection: $int,
        union: $uni,
        set_a_size: $sza,
        set_b_size: $szb,
        intersection_words: $words
      }'
  else
    echo "$similarity"
  fi
  
  # Cleanup
  rm -f "$set_a_file" "$set_b_file" "$intersection_file" "$union_file"
}

# Apply threshold if specified
apply_threshold() {
  local similarity="$1"
  
  if [[ -n "$THRESHOLD" ]]; then
    local passes
    passes=$(awk "BEGIN {print ($similarity >= $THRESHOLD) ? 1 : 0}")
    echo "$passes"
  else
    echo "$similarity"
  fi
}

# Main
main() {
  parse_args "$@"
  
  # Validate input
  local has_a=false
  local has_b=false
  
  [[ -n "$SET_A" || -n "$FILE_A" || -n "$TEXT_A" ]] && has_a=true
  [[ -n "$SET_B" || -n "$FILE_B" || -n "$TEXT_B" ]] && has_b=true
  
  if [[ "$has_a" == "false" || "$has_b" == "false" ]]; then
    echo "[ERROR] Both set A and set B must be specified" >&2
    usage
  fi
  
  # Calculate similarity
  local result
  result=$(calculate_jaccard)
  
  # Apply threshold if needed (only for non-JSON output)
  if [[ "$JSON_OUTPUT" == "false" && -n "$THRESHOLD" ]]; then
    local sim
    sim=$(echo "$result" | tr -d '\n')
    apply_threshold "$sim"
  else
    echo "$result"
  fi
}

main "$@"
