#!/bin/bash
# =============================================================================
# quality-gates.sh - 4-Gate Quality Filter for Pattern Qualification
# =============================================================================
# Sprint 6, Tasks 6.1-6.4: Apply quality gates to patterns before skill extraction
# Goal Contribution: G-1, G-2 (Quality control for extracted skills)
#
# Usage:
#   ./quality-gates.sh [options]
#   cat patterns.json | ./quality-gates.sh --stdin
#
# Options:
#   --stdin             Read patterns from stdin
#   --patterns FILE     Read patterns from file
#   --output FORMAT     Output format: json (default), summary
#   --verbose           Show detailed gate scores
#   --help              Show this help
#
# Quality Gates:
#   1. Discovery Depth  - Is the solution non-trivial?
#   2. Reusability      - Is the pattern generalizable?
#   3. Trigger Clarity  - Can we identify when this applies?
#   4. Verification     - Was the solution verified to work?
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_FILE="${PROJECT_ROOT}/.loa.config.yaml"

# Parameters
READ_STDIN=false
PATTERNS_FILE=""
OUTPUT_FORMAT="json"
VERBOSE=false
SOURCE_FILTER=""  # Filter by source field (v1.23.0)
SOURCE_PASSTHROUGH=true  # Preserve source field in output (v1.23.0)
WITH_FLATLINE_VALIDATION=false  # Enable Flatline validation for borderline (v1.23.0)
BORDERLINE_MIN=20  # Borderline range minimum (out of 40)
BORDERLINE_MAX=28  # Borderline range maximum (out of 40)

# Gate thresholds (from config or defaults)
DISCOVERY_DEPTH_MIN=5
REUSABILITY_MIN=5
TRIGGER_CLARITY_MIN=5
VERIFICATION_MIN=3

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
      --patterns)
        PATTERNS_FILE="$2"
        shift 2
        ;;
      --output)
        OUTPUT_FORMAT="$2"
        shift 2
        ;;
      --verbose)
        VERBOSE=true
        shift
        ;;
      --source)
        SOURCE_FILTER="$2"
        shift 2
        ;;
      --input)
        # Alias for --patterns for consistency
        PATTERNS_FILE="$2"
        shift 2
        ;;
      --with-flatline-validation)
        WITH_FLATLINE_VALIDATION=true
        shift
        ;;
      --borderline-range)
        # Format: "min,max" e.g., "20,28"
        BORDERLINE_MIN=$(echo "$2" | cut -d',' -f1)
        BORDERLINE_MAX=$(echo "$2" | cut -d',' -f2)
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

# Load config thresholds
load_config() {
  if [[ -f "$CONFIG_FILE" ]]; then
    DISCOVERY_DEPTH_MIN=$(yq -e '.compound_learning.quality_gates.discovery_depth.min_score // 5' "$CONFIG_FILE" 2>/dev/null || echo "5")
    REUSABILITY_MIN=$(yq -e '.compound_learning.quality_gates.reusability.min_score // 5' "$CONFIG_FILE" 2>/dev/null || echo "5")
    TRIGGER_CLARITY_MIN=$(yq -e '.compound_learning.quality_gates.trigger_clarity.min_score // 5' "$CONFIG_FILE" 2>/dev/null || echo "5")
    VERIFICATION_MIN=$(yq -e '.compound_learning.quality_gates.verification.min_score // 3' "$CONFIG_FILE" 2>/dev/null || echo "3")
  fi
}

# Get input patterns
get_patterns() {
  if [[ "$READ_STDIN" == "true" ]]; then
    cat
  elif [[ -n "$PATTERNS_FILE" && -f "$PATTERNS_FILE" ]]; then
    cat "$PATTERNS_FILE"
  else
    # Read from default patterns file
    local default_file="${PROJECT_ROOT}/grimoires/loa/a2a/compound/patterns.json"
    if [[ -f "$default_file" ]]; then
      jq '.patterns // []' "$default_file"
    else
      echo "[]"
    fi
  fi
}

# =========================================================================
# Gate 1: Discovery Depth
# Is the solution non-trivial? Does it contain actionable steps?
# =========================================================================
evaluate_discovery_depth() {
  local pattern="$1"
  local score=0
  
  # Check solution keywords
  local solution_keywords
  solution_keywords=$(echo "$pattern" | jq -r '.solution_keywords // [] | join(" ")')
  
  local solution_count
  solution_count=$(echo "$pattern" | jq '.solution_keywords | length')
  
  # More solution keywords = deeper discovery
  if [[ "$solution_count" -ge 5 ]]; then
    score=$((score + 4))
  elif [[ "$solution_count" -ge 3 ]]; then
    score=$((score + 3))
  elif [[ "$solution_count" -ge 1 ]]; then
    score=$((score + 2))
  fi
  
  # Check for trivial solutions (just retry/restart)
  if echo "$solution_keywords" | grep -qiE 'retry|restart|reboot|refresh'; then
    if [[ "$solution_count" -le 2 ]]; then
      score=$((score - 2))  # Penalize trivial solutions
    fi
  fi
  
  # Check for actionable verbs
  if echo "$solution_keywords" | grep -qiE 'add|create|implement|configure|update|change|fix|handle|use'; then
    score=$((score + 3))
  fi
  
  # Check occurrence count (more occurrences = more validated)
  local occurrences
  occurrences=$(echo "$pattern" | jq '.occurrence_count // 1')
  if [[ "$occurrences" -ge 5 ]]; then
    score=$((score + 3))
  elif [[ "$occurrences" -ge 3 ]]; then
    score=$((score + 2))
  elif [[ "$occurrences" -ge 2 ]]; then
    score=$((score + 1))
  fi
  
  # Clamp to 0-10
  [[ "$score" -lt 0 ]] && score=0
  [[ "$score" -gt 10 ]] && score=10
  
  echo "$score"
}

# =========================================================================
# Gate 2: Reusability
# Is the pattern generalizable beyond a single context?
# =========================================================================
evaluate_reusability() {
  local pattern="$1"
  local score=0
  
  # Check session diversity (pattern across sessions = more reusable)
  local session_count
  session_count=$(echo "$pattern" | jq '.sessions | length')
  
  if [[ "$session_count" -ge 3 ]]; then
    score=$((score + 4))
  elif [[ "$session_count" -ge 2 ]]; then
    score=$((score + 3))
  else
    score=$((score + 1))
  fi
  
  # Check for hyper-specific keywords (reduce score)
  local error_keywords
  error_keywords=$(echo "$pattern" | jq -r '.error_keywords // [] | join(" ")')
  
  # File paths or specific identifiers reduce reusability
  if echo "$error_keywords" | grep -qE '(/[a-z]+)+|[a-f0-9]{8,}'; then
    score=$((score - 2))
  fi
  
  # Common technology keywords increase reusability
  if echo "$error_keywords" | grep -qiE 'nats|redis|postgres|mysql|http|api|auth|timeout|connection'; then
    score=$((score + 3))
  fi
  
  # Pattern type affects reusability
  local pattern_type
  pattern_type=$(echo "$pattern" | jq -r '.type // "unknown"')
  
  case "$pattern_type" in
    convergent_solution)
      score=$((score + 2))  # Same solution for different problems = reusable
      ;;
    project_convention)
      score=$((score + 2))  # Conventions are inherently reusable
      ;;
    repeated_error)
      score=$((score + 1))  # Error patterns are somewhat reusable
      ;;
  esac
  
  # Clamp to 0-10
  [[ "$score" -lt 0 ]] && score=0
  [[ "$score" -gt 10 ]] && score=10
  
  echo "$score"
}

# =========================================================================
# Gate 3: Trigger Clarity
# Can we clearly identify when this pattern applies?
# =========================================================================
evaluate_trigger_clarity() {
  local pattern="$1"
  local score=0
  
  # Check error keywords (clear trigger indicators)
  local error_keywords
  error_keywords=$(echo "$pattern" | jq -r '.error_keywords // [] | join(" ")')
  
  local error_count
  error_count=$(echo "$pattern" | jq '.error_keywords | length')
  
  # More error keywords = clearer trigger
  if [[ "$error_count" -ge 5 ]]; then
    score=$((score + 4))
  elif [[ "$error_count" -ge 3 ]]; then
    score=$((score + 3))
  elif [[ "$error_count" -ge 1 ]]; then
    score=$((score + 2))
  fi
  
  # Check for specific error types
  if echo "$error_keywords" | grep -qiE 'error|exception|fail|timeout|refused|denied|invalid'; then
    score=$((score + 2))
  fi
  
  # Signature clarity
  local signature
  signature=$(echo "$pattern" | jq -r '.signature // ""')
  
  if [[ ${#signature} -ge 10 && ${#signature} -le 50 ]]; then
    score=$((score + 2))  # Good signature length
  fi
  
  # Pattern type affects clarity
  local pattern_type
  pattern_type=$(echo "$pattern" | jq -r '.type // "unknown"')
  
  if [[ "$pattern_type" == "repeated_error" ]]; then
    score=$((score + 2))  # Error patterns have clear triggers
  fi
  
  # Clamp to 0-10
  [[ "$score" -lt 0 ]] && score=0
  [[ "$score" -gt 10 ]] && score=10
  
  echo "$score"
}

# =========================================================================
# Gate 4: Verification
# Was the solution actually verified to work?
# =========================================================================
evaluate_verification() {
  local pattern="$1"
  local score=0
  
  # Check if there are resolution events
  local has_resolution
  has_resolution=$(echo "$pattern" | jq '.solution_keywords | length > 0')
  
  if [[ "$has_resolution" == "true" ]]; then
    score=$((score + 3))
  fi
  
  # Check confidence (higher confidence = more verified)
  local confidence
  confidence=$(echo "$pattern" | jq '.confidence // 0')
  
  local conf_int
  conf_int=$(awk "BEGIN {printf \"%.0f\", $confidence * 10}")
  
  if [[ "$conf_int" -ge 8 ]]; then
    score=$((score + 4))
  elif [[ "$conf_int" -ge 6 ]]; then
    score=$((score + 3))
  elif [[ "$conf_int" -ge 4 ]]; then
    score=$((score + 2))
  fi
  
  # More occurrences = more verification
  local occurrences
  occurrences=$(echo "$pattern" | jq '.occurrence_count // 1')
  
  if [[ "$occurrences" -ge 3 ]]; then
    score=$((score + 3))
  elif [[ "$occurrences" -ge 2 ]]; then
    score=$((score + 2))
  fi
  
  # Clamp to 0-10
  [[ "$score" -lt 0 ]] && score=0
  [[ "$score" -gt 10 ]] && score=10
  
  echo "$score"
}

# =========================================================================
# Evaluate all gates for a pattern
# =========================================================================
evaluate_pattern() {
  local pattern="$1"

  local depth_score reuse_score trigger_score verify_score
  depth_score=$(evaluate_discovery_depth "$pattern")
  reuse_score=$(evaluate_reusability "$pattern")
  trigger_score=$(evaluate_trigger_clarity "$pattern")
  verify_score=$(evaluate_verification "$pattern")

  # Check if all gates pass
  local passes_all=true
  [[ "$depth_score" -lt "$DISCOVERY_DEPTH_MIN" ]] && passes_all=false
  [[ "$reuse_score" -lt "$REUSABILITY_MIN" ]] && passes_all=false
  [[ "$trigger_score" -lt "$TRIGGER_CLARITY_MIN" ]] && passes_all=false
  [[ "$verify_score" -lt "$VERIFICATION_MIN" ]] && passes_all=false

  # Calculate aggregate score
  local total_score
  total_score=$((depth_score + reuse_score + trigger_score + verify_score))

  # Preserve source field if present (v1.23.0)
  local source_field
  source_field=$(echo "$pattern" | jq -r '.source // ""')

  # Build result
  local result
  result=$(jq -n \
    --argjson pattern "$pattern" \
    --argjson depth "$depth_score" \
    --argjson reuse "$reuse_score" \
    --argjson trigger "$trigger_score" \
    --argjson verify "$verify_score" \
    --argjson total "$total_score" \
    --argjson passes "$([[ "$passes_all" == "true" ]] && echo "true" || echo "false")" \
    '{
      pattern: $pattern,
      gates: {
        discovery_depth: $depth,
        reusability: $reuse,
        trigger_clarity: $trigger,
        verification: $verify
      },
      total_score: $total,
      passes: $passes
    }')

  # Add source field to top level if present (v1.23.0)
  if [[ -n "$source_field" && "$SOURCE_PASSTHROUGH" == "true" ]]; then
    result=$(echo "$result" | jq --arg source "$source_field" '. + {source: $source}')
  fi

  echo "$result"
}

# Main evaluation
evaluate_all() {
  local patterns
  patterns=$(get_patterns)

  local count
  count=$(echo "$patterns" | jq 'length')

  if [[ "$count" -eq 0 ]]; then
    echo "[]"
    return
  fi

  # Apply source filter if specified (v1.23.0)
  if [[ -n "$SOURCE_FILTER" ]]; then
    patterns=$(echo "$patterns" | jq --arg source "$SOURCE_FILTER" '[.[] | select(.source == $source)]')
    count=$(echo "$patterns" | jq 'length')

    if [[ "$count" -eq 0 ]]; then
      echo "[]"
      return
    fi
  fi

  local results=()

  echo "$patterns" | jq -c '.[]' | while read -r pattern; do
    local result
    result=$(evaluate_pattern "$pattern")
    results+=("$result")
    echo "$result"
  done | jq -s '.'
}

# =============================================================================
# Flatline Validation for Borderline Learnings (v1.23.0)
# =============================================================================

# Check if a pattern is borderline (total_score in range)
is_borderline() {
  local total_score="$1"
  [[ "$total_score" -ge "$BORDERLINE_MIN" && "$total_score" -le "$BORDERLINE_MAX" ]]
}

# Validate borderline patterns with Flatline
validate_borderline_with_flatline() {
  local results_json="$1"

  local validator_script="${SCRIPT_DIR}/flatline-validate-learning.sh"
  if [[ ! -x "$validator_script" ]]; then
    echo "[WARN] Flatline validator not found, skipping borderline validation" >&2
    echo "$results_json"
    return
  fi

  local validated_count=0
  local promoted_count=0
  local demoted_count=0
  local disputed_count=0

  # Process each result
  local updated_results="[]"

  echo "$results_json" | jq -c '.[]' | while IFS= read -r result; do
    local total_score passes source
    total_score=$(echo "$result" | jq -r '.total_score')
    passes=$(echo "$result" | jq -r '.passes')
    source=$(echo "$result" | jq -r '.source // ""')

    # Skip non-borderline or already passing
    if [[ "$passes" == "true" ]] || ! is_borderline "$total_score"; then
      echo "$result"
      continue
    fi

    # Skip Flatline-source learnings (L1 circular prevention)
    if [[ "$source" == "flatline" || "$source" == "flatline-disputed" ]]; then
      echo "[INFO] Skipping Flatline-source learning for validation" >&2
      echo "$result"
      continue
    fi

    # Build learning object for validation
    local pattern trigger solution
    pattern=$(echo "$result" | jq '.pattern')
    trigger=$(echo "$pattern" | jq -r '.trigger // .signature // ""')
    solution=$(echo "$pattern" | jq -r '.solution // .solution_keywords[0] // ""')

    if [[ -z "$trigger" || -z "$solution" ]]; then
      echo "$result"
      continue
    fi

    local learning_json
    learning_json=$(jq -n \
      --arg id "$(echo "$pattern" | jq -r '.id // "temp-" + (now | tostring)')" \
      --arg trigger "$trigger" \
      --arg solution "$solution" \
      --arg source "$source" \
      '{id: $id, trigger: $trigger, solution: $solution, source: $source}')

    # Call Flatline validator
    local validation_result
    validation_result=$("$validator_script" --learning "$learning_json" --dry-run 2>/dev/null) || {
      echo "[WARN] Flatline validation failed for borderline learning" >&2
      echo "$result"
      continue
    }

    ((validated_count++))

    # Apply validation result
    local action consensus
    action=$(echo "$validation_result" | jq -r '.action // "none"')
    consensus=$(echo "$validation_result" | jq -r '.consensus // "UNKNOWN"')

    case "$action" in
      promote)
        # Mark as passing
        result=$(echo "$result" | jq '.passes = true | .flatline_validated = true | .flatline_action = "promote"')
        ((promoted_count++))
        ;;
      demote)
        # Mark as low_value
        result=$(echo "$result" | jq '.passes = false | .flatline_validated = true | .flatline_action = "demote" | .low_value = true')
        ((demoted_count++))
        ;;
      human_review)
        # Flag for review
        result=$(echo "$result" | jq '.flatline_validated = true | .flatline_action = "human_review" | .requires_review = true')
        ((disputed_count++))
        ;;
    esac

    echo "$result"
  done | jq -s '.'
}

# Output summary
output_summary() {
  local results="$1"
  
  local total passed failed
  total=$(echo "$results" | jq 'length')
  passed=$(echo "$results" | jq '[.[] | select(.passes == true)] | length')
  failed=$((total - passed))
  
  echo "Quality Gate Summary"
  echo "===================="
  echo "Total patterns: $total"
  echo "Passed: $passed"
  echo "Failed: $failed"
  echo ""
  
  if [[ "$passed" -gt 0 ]]; then
    echo "Qualified patterns:"
    echo "$results" | jq -r '.[] | select(.passes == true) | "  ✓ \(.pattern.signature) (score: \(.total_score)/40)"'
  fi
  
  if [[ "$failed" -gt 0 ]]; then
    echo ""
    echo "Failed patterns:"
    echo "$results" | jq -r '.[] | select(.passes == false) | "  ✗ \(.pattern.signature) (D:\(.gates.discovery_depth) R:\(.gates.reusability) T:\(.gates.trigger_clarity) V:\(.gates.verification))"'
  fi
}

# Main
main() {
  parse_args "$@"
  load_config

  local results
  results=$(evaluate_all)

  # Apply Flatline validation if enabled (v1.23.0)
  if [[ "$WITH_FLATLINE_VALIDATION" == "true" ]]; then
    echo "[INFO] Running Flatline validation for borderline learnings (range: $BORDERLINE_MIN-$BORDERLINE_MAX)" >&2
    results=$(validate_borderline_with_flatline "$results")
  fi

  case "$OUTPUT_FORMAT" in
    json)
      echo "$results"
      ;;
    summary)
      output_summary "$results"
      ;;
  esac
}

main "$@"
