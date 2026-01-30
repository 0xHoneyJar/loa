#!/bin/bash
# =============================================================================
# extract-keywords.sh - Keyword Extraction for Pattern Detection
# =============================================================================
# Sprint 3, Task 3.1: Extract keywords from text/events for similarity matching
# Goal Contribution: G-1 (Cross-session pattern detection), G-2 (Reduce repeated work)
#
# Usage:
#   ./extract-keywords.sh [options] [text]
#   echo "text" | ./extract-keywords.sh [options]
#
# Options:
#   --min-length N   Minimum keyword length (default: 3)
#   --max-keywords N Maximum keywords to return (default: 50)
#   --stopwords FILE Custom stopwords file (one per line)
#   --technical      Prioritize technical terms (camelCase, snake_case)
#   --json           Output as JSON array
#   --help           Show this help
#
# Output:
#   Keywords separated by newlines (default) or JSON array
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default parameters
MIN_LENGTH=3
MAX_KEYWORDS=50
CUSTOM_STOPWORDS=""
TECHNICAL_MODE=false
JSON_OUTPUT=false
INPUT_TEXT=""

# Common English stopwords
STOPWORDS=(
  "a" "an" "and" "are" "as" "at" "be" "been" "being" "by" "can" "could"
  "did" "do" "does" "doing" "done" "for" "from" "had" "has" "have" "having"
  "he" "her" "here" "him" "his" "how" "i" "if" "in" "into" "is" "it" "its"
  "just" "like" "make" "may" "me" "might" "more" "most" "much" "my" "no"
  "not" "now" "of" "on" "one" "only" "or" "other" "our" "out" "over" "own"
  "same" "she" "should" "so" "some" "such" "than" "that" "the" "their"
  "them" "then" "there" "these" "they" "this" "those" "through" "to" "too"
  "under" "up" "us" "use" "used" "using" "very" "was" "way" "we" "well"
  "were" "what" "when" "where" "which" "while" "who" "will" "with" "would"
  "you" "your" "also" "but" "because" "about" "get" "got" "need" "needs"
  "try" "tried" "trying" "want" "wants" "see" "saw" "look" "looking"
  "think" "thought" "know" "knew" "let" "lets" "take" "took" "give" "gave"
)

# Technical stopwords (common but not informative in code context)
TECH_STOPWORDS=(
  "true" "false" "null" "undefined" "var" "let" "const" "return" "function"
  "class" "new" "this" "self" "import" "export" "from" "require" "module"
  "async" "await" "promise" "then" "catch" "finally" "void" "string" "number"
  "boolean" "object" "array" "type" "interface" "extends" "implements"
)

# Usage
usage() {
  sed -n '/^# Usage:/,/^# =====/p' "$0" | grep -v "^# =====" | sed 's/^# //'
  exit 0
}

# Parse arguments
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --min-length)
        MIN_LENGTH="$2"
        shift 2
        ;;
      --max-keywords)
        MAX_KEYWORDS="$2"
        shift 2
        ;;
      --stopwords)
        CUSTOM_STOPWORDS="$2"
        shift 2
        ;;
      --technical)
        TECHNICAL_MODE=true
        shift
        ;;
      --json)
        JSON_OUTPUT=true
        shift
        ;;
      --help|-h)
        usage
        ;;
      -*)
        echo "[ERROR] Unknown option: $1" >&2
        exit 1
        ;;
      *)
        INPUT_TEXT="$1"
        shift
        ;;
    esac
  done
}

# Load custom stopwords if provided
load_custom_stopwords() {
  if [[ -n "$CUSTOM_STOPWORDS" && -f "$CUSTOM_STOPWORDS" ]]; then
    while IFS= read -r word; do
      STOPWORDS+=("$word")
    done < "$CUSTOM_STOPWORDS"
  fi
}

# Check if word is a stopword
is_stopword() {
  local word="$1"
  local lower
  lower=$(echo "$word" | tr '[:upper:]' '[:lower:]')
  
  for sw in "${STOPWORDS[@]}"; do
    if [[ "$lower" == "$sw" ]]; then
      return 0
    fi
  done
  
  for sw in "${TECH_STOPWORDS[@]}"; do
    if [[ "$lower" == "$sw" ]]; then
      return 0
    fi
  done
  
  return 1
}

# Extract camelCase/PascalCase words
extract_camel_case() {
  local text="$1"
  # Insert space before uppercase letters, then extract words
  echo "$text" | sed 's/\([a-z]\)\([A-Z]\)/\1 \2/g' | tr ' ' '\n'
}

# Extract snake_case words
extract_snake_case() {
  local text="$1"
  echo "$text" | tr '_' '\n'
}

# Extract kebab-case words
extract_kebab_case() {
  local text="$1"
  echo "$text" | tr '-' '\n'
}

# Main keyword extraction
extract_keywords() {
  local text="$1"
  local keywords=()
  
  # Normalize text: lowercase, remove special chars
  local normalized
  normalized=$(echo "$text" | tr '[:upper:]' '[:lower:]')
  
  # Replace common delimiters with spaces
  normalized=$(echo "$normalized" | tr -cs '[:alnum:]_-' ' ')
  
  # Extract technical terms if in technical mode
  if [[ "$TECHNICAL_MODE" == "true" ]]; then
    # Extract camelCase terms before lowercasing
    while IFS= read -r term; do
      if [[ ${#term} -ge $MIN_LENGTH ]] && ! is_stopword "$term"; then
        keywords+=("$term")
      fi
    done < <(extract_camel_case "$text" | grep -oE '[a-zA-Z]+')
    
    # Extract snake_case terms
    while IFS= read -r term; do
      if [[ ${#term} -ge $MIN_LENGTH ]] && ! is_stopword "$term"; then
        keywords+=("$term")
      fi
    done < <(extract_snake_case "$text" | grep -oE '[a-zA-Z]+')
  fi
  
  # Extract all words
  while IFS= read -r word; do
    # Clean word
    word=$(echo "$word" | tr -d '[:punct:]' | tr -d '[:digit:]')
    word=$(echo "$word" | tr '[:upper:]' '[:lower:]')
    
    # Filter by length and stopwords
    if [[ ${#word} -ge $MIN_LENGTH ]] && ! is_stopword "$word"; then
      keywords+=("$word")
    fi
  done < <(echo "$normalized" | tr ' ' '\n' | grep -E '^[a-zA-Z]')
  
  # Deduplicate and limit
  printf '%s\n' "${keywords[@]}" | sort -u | head -n "$MAX_KEYWORDS"
}

# Output as JSON array
output_json() {
  local keywords
  keywords=$(cat)
  
  if [[ -z "$keywords" ]]; then
    echo "[]"
    return
  fi
  
  echo "$keywords" | jq -R -s 'split("\n") | map(select(length > 0))'
}

# Main
main() {
  parse_args "$@"
  load_custom_stopwords
  
  # Get input
  local text
  if [[ -n "$INPUT_TEXT" ]]; then
    text="$INPUT_TEXT"
  elif [[ ! -t 0 ]]; then
    # Read from stdin
    text=$(cat)
  else
    echo "[ERROR] No input text provided" >&2
    exit 1
  fi
  
  # Extract keywords
  local result
  result=$(extract_keywords "$text")
  
  # Output
  if [[ "$JSON_OUTPUT" == "true" ]]; then
    echo "$result" | output_json
  else
    echo "$result"
  fi
}

main "$@"
