#!/usr/bin/env bash
# =============================================================================
# Measure Token Budget — Actual token count for CLAUDE.loa.md and references
# =============================================================================
# Reports token count (not word count) for always-loaded and demand-loaded
# files. Uses heuristic tokenization: tokens ≈ words × 1.3 for prose,
# × 1.5 for code/markdown.
#
# Usage:
#   measure-token-budget.sh              # Human-readable output
#   measure-token-budget.sh --json       # Machine-readable JSON
#
# Token estimation method:
#   Heuristic based on OpenAI tiktoken research:
#   - English prose: ~1.3 tokens per word
#   - Code/markdown: ~1.5 tokens per word (more special characters)
#   - Mixed content: weighted average based on code block density
#
# Source: Bridgebuilder Deep Review Critical 4
# Part of Loa Harness Engineering (cycle-011, issue #297)
# =============================================================================

set -euo pipefail

JSON_OUTPUT=false
ALWAYS_LOADED=".claude/loa/CLAUDE.loa.md"
REFERENCE_DIR=".claude/loa/reference"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) JSON_OUTPUT=true; shift ;;
    -h|--help)
      echo "Usage: measure-token-budget.sh [--json]"
      echo ""
      echo "  --json  Machine-readable JSON output"
      echo ""
      echo "Measures token budget for CLAUDE.loa.md and reference files."
      echo "Method: heuristic (words × ratio based on content type)."
      exit 0
      ;;
    *) echo "ERROR: Unknown option: $1" >&2; exit 1 ;;
  esac
done

# ---------------------------------------------------------------------------
# Token estimation function
# ---------------------------------------------------------------------------
estimate_tokens() {
  local file="$1"

  if [[ ! -f "$file" ]]; then
    echo "0"
    return
  fi

  local words lines code_lines ratio
  words=$(wc -w < "$file" | tr -d ' ')
  lines=$(wc -l < "$file" | tr -d ' ')

  # Count code block lines (``` delimited) and HTML comment lines
  code_lines=$(grep -cE '(^```|^<!--|^\|)' "$file" 2>/dev/null || echo "0")

  # Calculate code density (0.0 to 1.0)
  local code_density="0"
  if [[ "$lines" -gt 0 ]]; then
    code_density=$(awk "BEGIN {printf \"%.2f\", $code_lines / $lines}")
  fi

  # Weighted ratio: prose=1.3, code/markdown=1.5
  ratio=$(awk "BEGIN {printf \"%.2f\", 1.3 + ($code_density * 0.2)}")

  # Estimate tokens
  local tokens
  tokens=$(awk "BEGIN {printf \"%d\", $words * $ratio}")
  echo "$tokens"
}

get_file_stats() {
  local file="$1"
  local words lines chars
  words=$(wc -w < "$file" 2>/dev/null | tr -d ' ' || echo "0")
  lines=$(wc -l < "$file" 2>/dev/null | tr -d ' ' || echo "0")
  chars=$(wc -c < "$file" 2>/dev/null | tr -d ' ' || echo "0")
  echo "$words $lines $chars"
}

# ---------------------------------------------------------------------------
# Measure always-loaded file
# ---------------------------------------------------------------------------
if [[ ! -f "$ALWAYS_LOADED" ]]; then
  echo "ERROR: $ALWAYS_LOADED not found" >&2
  exit 1
fi

always_tokens=$(estimate_tokens "$ALWAYS_LOADED")
read -r always_words always_lines always_chars <<< "$(get_file_stats "$ALWAYS_LOADED")"

# ---------------------------------------------------------------------------
# Measure demand-loaded reference files
# ---------------------------------------------------------------------------
demand_tokens=0
demand_words=0
demand_lines=0
ref_details=()

if [[ -d "$REFERENCE_DIR" ]]; then
  while IFS= read -r -d '' ref_file; do
    tokens=$(estimate_tokens "$ref_file")
    read -r words lines chars <<< "$(get_file_stats "$ref_file")"
    demand_tokens=$((demand_tokens + tokens))
    demand_words=$((demand_words + words))
    demand_lines=$((demand_lines + lines))
    basename=$(basename "$ref_file")
    ref_details+=("$basename:$tokens:$words:$lines")
  done < <(find "$REFERENCE_DIR" -name "*.md" -print0 2>/dev/null | sort -z)
fi

total_tokens=$((always_tokens + demand_tokens))

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------
if [[ "$JSON_OUTPUT" == "true" ]]; then
  # Build reference files array
  ref_json="[]"
  if [[ ${#ref_details[@]} -gt 0 ]]; then
    ref_json="["
    first=true
    for detail in "${ref_details[@]}"; do
      IFS=: read -r name tokens words lines <<< "$detail"
      if [[ "$first" == "true" ]]; then
        first=false
      else
        ref_json+=","
      fi
      ref_json+=$(jq -cn --arg n "$name" --argjson t "$tokens" --argjson w "$words" --argjson l "$lines" \
        '{name:$n, tokens:$t, words:$w, lines:$l}')
    done
    ref_json+="]"
  fi

  jq -cn \
    --argjson always_tokens "$always_tokens" \
    --argjson always_words "$always_words" \
    --argjson always_lines "$always_lines" \
    --argjson demand_tokens "$demand_tokens" \
    --argjson demand_words "$demand_words" \
    --argjson demand_lines "$demand_lines" \
    --argjson total_tokens "$total_tokens" \
    --argjson ref_files "$ref_json" \
    '{
      method: "heuristic (words × 1.3-1.5 ratio)",
      always_loaded: {
        file: ".claude/loa/CLAUDE.loa.md",
        tokens: $always_tokens,
        words: $always_words,
        lines: $always_lines
      },
      demand_loaded: {
        directory: ".claude/loa/reference/",
        tokens: $demand_tokens,
        words: $demand_words,
        lines: $demand_lines,
        files: $ref_files
      },
      total: {
        tokens: $total_tokens,
        savings_pct: (if $total_tokens > 0 then (100 - ($always_tokens * 100 / $total_tokens)) else 0 end)
      }
    }'
else
  echo "Token Budget Measurement"
  echo "========================"
  echo ""
  echo "Method: Heuristic (words × 1.3-1.5 ratio based on content type)"
  echo ""
  echo "Always-Loaded (CLAUDE.loa.md):"
  printf "  Tokens: %s | Words: %s | Lines: %s\n" "$always_tokens" "$always_words" "$always_lines"
  echo ""
  echo "Demand-Loaded (reference files):"
  printf "  Tokens: %s | Words: %s | Lines: %s\n" "$demand_tokens" "$demand_words" "$demand_lines"

  if [[ ${#ref_details[@]} -gt 0 ]]; then
    echo ""
    printf "  %-40s %8s %8s %8s\n" "File" "Tokens" "Words" "Lines"
    printf "  %-40s %8s %8s %8s\n" "----" "------" "-----" "-----"
    for detail in "${ref_details[@]}"; do
      IFS=: read -r name tokens words lines <<< "$detail"
      printf "  %-40s %8s %8s %8s\n" "$name" "$tokens" "$words" "$lines"
    done
  fi

  echo ""
  echo "Total:"
  printf "  Total tokens:    %s\n" "$total_tokens"
  printf "  Always-loaded:   %s (%.0f%%)\n" "$always_tokens" "$(awk "BEGIN {if ($total_tokens>0) printf \"%.0f\", $always_tokens*100/$total_tokens; else print 0}")"
  printf "  Demand-loaded:   %s (%.0f%%)\n" "$demand_tokens" "$(awk "BEGIN {if ($total_tokens>0) printf \"%.0f\", $demand_tokens*100/$total_tokens; else print 0}")"

  if [[ "$total_tokens" -gt 0 ]]; then
    savings=$(awk "BEGIN {printf \"%.0f\", 100 - ($always_tokens * 100 / $total_tokens)}")
    echo ""
    echo "Token savings: ${savings}% of budget is demand-loaded (only consumed when needed)"
  fi
fi
