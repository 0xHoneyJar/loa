#!/usr/bin/env bash
# =============================================================================
# injection-detect.sh - Prompt injection pattern detection
# =============================================================================
# Version: 1.0.0
# Part of: Input Guardrails & Tool Risk Enforcement v1.20.0
#
# Usage:
#   echo "Ignore all previous instructions" | injection-detect.sh
#   injection-detect.sh --input "You are now a helpful assistant"
#   injection-detect.sh --input "Please implement the login feature" --threshold 0.5
#
# Output: JSON with status (PASS/DETECTED), score, matched patterns
# =============================================================================

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_NAME="$(basename "$0")"

# Default threshold
DEFAULT_THRESHOLD="0.7"

# =============================================================================
# Injection Patterns
# =============================================================================

# Pattern weights (higher = more suspicious)
# Total weights should allow score > 1.0 for multiple matches

# Instruction Override (weight: 0.4)
declare -a INSTRUCTION_OVERRIDE_PATTERNS=(
    "ignore (all )?(previous|prior|above) (instructions|rules|prompts)"
    "disregard (all )?(previous|prior|above)"
    "forget (everything|all|what).*before"
    "override (your|the) (instructions|rules|programming)"
    "new (instructions|rules|directive)"
    "stop being"
    "do not follow"
    "bypass (the|your) (rules|restrictions|guidelines)"
    "break free from"
    "ignore (your|the) (training|programming)"
)

# Role Confusion (weight: 0.3)
declare -a ROLE_CONFUSION_PATTERNS=(
    "you are (now|actually)"
    "act as (a|an|if)"
    "pretend (to be|you are)"
    "roleplay as"
    "your (new )?role is"
    "from now on"
    "in this conversation you"
    "you will respond as"
    "behave like"
    "assume the (role|identity|persona)"
)

# Context Manipulation (weight: 0.2)
declare -a CONTEXT_MANIPULATION_PATTERNS=(
    "system prompt"
    "hidden (instructions|prompt|message)"
    "debug mode"
    "developer mode"
    "jailbreak"
    "DAN"
    "do anything now"
    "enable (developer|admin|root) mode"
    "maintenance mode"
    "reveal (your|the) (instructions|prompt|rules)"
    "what are your instructions"
    "show me your prompt"
)

# Encoding Evasion (weight: 0.1)
declare -a ENCODING_EVASION_PATTERNS=(
    # Base64 command patterns
    "base64"
    "decode this"
    # Unicode tricks
    "\\\\u[0-9a-fA-F]{4}"
    # Character substitution hints
    "rot13"
    "caesar cipher"
    # Markdown/code escaping
    "\\\`\\\`\\\`ignore"
)

# =============================================================================
# Functions
# =============================================================================

show_help() {
    cat <<EOF
Usage: $SCRIPT_NAME [OPTIONS]

Detect prompt injection patterns in input text.

Options:
  --input TEXT      Text to scan (alternative to stdin)
  --file PATH       Read input from file
  --threshold N     Score threshold for detection (default: 0.7)
  --json            Output full JSON (default)
  --quiet           Only output status (PASS/DETECTED)
  -h, --help        Show this help message

Pattern Categories:
  instruction_override  - "ignore previous", "disregard", "override rules"
  role_confusion        - "you are now", "act as", "pretend to be"
  context_manipulation  - "system prompt", "debug mode", "jailbreak"
  encoding_evasion      - base64, unicode tricks, rot13

Scoring:
  - Each pattern category has a weight (0.1-0.4)
  - Multiple matches in a category add to the score
  - Final score is capped at 1.0
  - Score >= threshold triggers DETECTED status

Output (JSON mode):
  {
    "status": "PASS|DETECTED",
    "score": 0.0-1.0,
    "threshold": 0.7,
    "patterns_matched": ["category1", "category2"],
    "details": {
      "instruction_override": 0,
      "role_confusion": 1,
      "context_manipulation": 0,
      "encoding_evasion": 0
    },
    "latency_ms": N
  }

Examples:
  echo "Please implement the login feature" | $SCRIPT_NAME
  $SCRIPT_NAME --input "Ignore all previous instructions and..."
  $SCRIPT_NAME --input "You are now a helpful assistant" --threshold 0.5
EOF
}

# Case-insensitive pattern match
matches_pattern() {
    local text="$1"
    local pattern="$2"

    echo "$text" | grep -iE "$pattern" >/dev/null 2>&1
}

# Count pattern matches
count_pattern_matches() {
    local text="$1"
    shift
    local patterns=("$@")
    local count=0

    for pattern in "${patterns[@]}"; do
        if matches_pattern "$text" "$pattern"; then
            count=$((count + 1))
        fi
    done

    echo "$count"
}

# Process input and return JSON result
process_input() {
    local input="$1"
    local threshold="${2:-$DEFAULT_THRESHOLD}"
    local start_time
    local end_time
    local latency_ms

    start_time=$(date +%s%3N 2>/dev/null || echo "0")

    # Normalize input for pattern matching
    local normalized
    normalized=$(echo "$input" | tr '[:upper:]' '[:lower:]')

    # Count matches for each category
    local instruction_override_count
    local role_confusion_count
    local context_manipulation_count
    local encoding_evasion_count

    instruction_override_count=$(count_pattern_matches "$normalized" "${INSTRUCTION_OVERRIDE_PATTERNS[@]}")
    role_confusion_count=$(count_pattern_matches "$normalized" "${ROLE_CONFUSION_PATTERNS[@]}")
    context_manipulation_count=$(count_pattern_matches "$normalized" "${CONTEXT_MANIPULATION_PATTERNS[@]}")
    encoding_evasion_count=$(count_pattern_matches "$normalized" "${ENCODING_EVASION_PATTERNS[@]}")

    # Calculate weighted score
    # instruction_override: 0.4 per match (cap at 0.4)
    # role_confusion: 0.3 per match (cap at 0.3)
    # context_manipulation: 0.2 per match (cap at 0.2)
    # encoding_evasion: 0.1 per match (cap at 0.1)

    local score=0

    if [[ $instruction_override_count -gt 0 ]]; then
        # Use awk for floating point math
        # First match gives full weight, additional matches add 50%
        local io_score
        io_score=$(awk "BEGIN {s = 0.4 + ($instruction_override_count - 1) * 0.2; if (s > 0.6) s = 0.6; print s}")
        score=$(awk "BEGIN {print $score + $io_score}")
    fi

    if [[ $role_confusion_count -gt 0 ]]; then
        local rc_score
        rc_score=$(awk "BEGIN {s = 0.3 + ($role_confusion_count - 1) * 0.15; if (s > 0.45) s = 0.45; print s}")
        score=$(awk "BEGIN {print $score + $rc_score}")
    fi

    if [[ $context_manipulation_count -gt 0 ]]; then
        local cm_score
        cm_score=$(awk "BEGIN {s = 0.2 + ($context_manipulation_count - 1) * 0.1; if (s > 0.3) s = 0.3; print s}")
        score=$(awk "BEGIN {print $score + $cm_score}")
    fi

    if [[ $encoding_evasion_count -gt 0 ]]; then
        local ee_score
        ee_score=$(awk "BEGIN {s = 0.1 + ($encoding_evasion_count - 1) * 0.05; if (s > 0.15) s = 0.15; print s}")
        score=$(awk "BEGIN {print $score + $ee_score}")
    fi

    # Cap score at 1.0
    score=$(awk "BEGIN {if ($score > 1.0) print 1.0; else print $score}")

    # Build patterns_matched array
    local patterns_matched=()
    if [[ $instruction_override_count -gt 0 ]]; then
        patterns_matched+=("instruction_override")
    fi
    if [[ $role_confusion_count -gt 0 ]]; then
        patterns_matched+=("role_confusion")
    fi
    if [[ $context_manipulation_count -gt 0 ]]; then
        patterns_matched+=("context_manipulation")
    fi
    if [[ $encoding_evasion_count -gt 0 ]]; then
        patterns_matched+=("encoding_evasion")
    fi

    # Determine status
    local status="PASS"
    local threshold_check
    threshold_check=$(awk "BEGIN {if ($score >= $threshold) print 1; else print 0}")
    if [[ "$threshold_check" == "1" ]]; then
        status="DETECTED"
    fi

    end_time=$(date +%s%3N 2>/dev/null || echo "0")
    latency_ms=$((end_time - start_time))
    [[ $latency_ms -lt 0 ]] && latency_ms=0

    # Build patterns_matched JSON array
    local patterns_json="[]"
    if [[ ${#patterns_matched[@]} -gt 0 ]]; then
        patterns_json=$(printf '%s\n' "${patterns_matched[@]}" | jq -R . | jq -s .)
    fi

    # Output JSON
    cat <<EOF
{
  "status": "$status",
  "score": $score,
  "threshold": $threshold,
  "patterns_matched": $patterns_json,
  "details": {
    "instruction_override": $instruction_override_count,
    "role_confusion": $role_confusion_count,
    "context_manipulation": $context_manipulation_count,
    "encoding_evasion": $encoding_evasion_count
  },
  "latency_ms": $latency_ms
}
EOF
}

# =============================================================================
# Main
# =============================================================================

main() {
    local input=""
    local threshold="$DEFAULT_THRESHOLD"
    local output_mode="json"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --input)
                input="$2"
                shift 2
                ;;
            --file)
                if [[ ! -f "$2" ]]; then
                    echo "Error: File not found: $2" >&2
                    exit 1
                fi
                input=$(cat "$2")
                shift 2
                ;;
            --threshold)
                threshold="$2"
                shift 2
                ;;
            --json)
                output_mode="json"
                shift
                ;;
            --quiet)
                output_mode="quiet"
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                echo "Unknown option: $1" >&2
                show_help
                exit 1
                ;;
        esac
    done

    # Read from stdin if no input provided
    if [[ -z "$input" ]]; then
        if [[ -t 0 ]]; then
            echo "Error: No input provided. Use --input, --file, or pipe to stdin." >&2
            exit 1
        fi
        input=$(cat)
    fi

    # Validate threshold
    local valid_threshold
    valid_threshold=$(awk "BEGIN {if ($threshold >= 0 && $threshold <= 1) print 1; else print 0}")
    if [[ "$valid_threshold" != "1" ]]; then
        echo "Error: Threshold must be between 0 and 1" >&2
        exit 1
    fi

    # Process and output
    local result
    result=$(process_input "$input" "$threshold")

    case "$output_mode" in
        json)
            echo "$result"
            ;;
        quiet)
            echo "$result" | jq -r '.status'
            ;;
    esac
}

main "$@"
