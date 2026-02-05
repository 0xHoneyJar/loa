#!/usr/bin/env bash
# =============================================================================
# pii-filter.sh - PII detection and redaction for input guardrails
# =============================================================================
# Version: 1.1.0
# Part of: Input Guardrails & Tool Risk Enforcement v1.20.0
#
# Security Fixes (v1.1.0):
#   - M-2/I-3: Input size limits to prevent ReDoS
#
# Usage:
#   echo "text with user@example.com" | pii-filter.sh
#   pii-filter.sh --input "text with sk-abc123xyz789"
#   pii-filter.sh --file input.txt
#
# Output: JSON with status, redactions count, and redacted text
# =============================================================================

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source cross-platform time utilities
# shellcheck source=time-lib.sh
source "$SCRIPT_DIR/time-lib.sh"
readonly SCRIPT_NAME="$(basename "$0")"

# Default settings
DEFAULT_MODE="redact"  # redact | anonymize

# Maximum input size (1MB) - M-2/I-3 fix for ReDoS prevention
MAX_INPUT_SIZE=${MAX_INPUT_SIZE:-1048576}

# =============================================================================
# PII Patterns
# =============================================================================

# API Keys
PATTERN_OPENAI_KEY='sk-[a-zA-Z0-9]{20,}'
PATTERN_GITHUB_TOKEN='ghp_[a-zA-Z0-9]{36}'
PATTERN_GITHUB_OAUTH='gho_[a-zA-Z0-9]{36}'
PATTERN_AWS_ACCESS='AKIA[A-Z0-9]{16}'
PATTERN_ANTHROPIC_KEY='sk-ant-[a-zA-Z0-9-]{40,}'

# Personal Information
PATTERN_EMAIL='[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}'
PATTERN_PHONE='\b[0-9]{3}[-.]?[0-9]{3}[-.]?[0-9]{4}\b'
PATTERN_SSN='\b[0-9]{3}-[0-9]{2}-[0-9]{4}\b'
PATTERN_CREDIT_CARD='\b[0-9]{4}[-\s]?[0-9]{4}[-\s]?[0-9]{4}[-\s]?[0-9]{4}\b'

# Tokens and Secrets
PATTERN_JWT='eyJ[a-zA-Z0-9_-]{10,}\.[a-zA-Z0-9_-]{10,}\.[a-zA-Z0-9_-]*'
PATTERN_PRIVATE_KEY='-----BEGIN [A-Z ]+ PRIVATE KEY-----'
PATTERN_WEBHOOK_SLACK='https://hooks\.slack\.com/[^\s]+'
PATTERN_WEBHOOK_DISCORD='https://discord\.com/api/webhooks/[^\s]+'

# File Paths (for anonymization)
PATTERN_HOME_LINUX='/home/[^/]+/'
PATTERN_HOME_MACOS='/Users/[^/]+/'

# =============================================================================
# Functions
# =============================================================================

show_help() {
    cat <<EOF
Usage: $SCRIPT_NAME [OPTIONS]

Detect and redact PII from input text.

Options:
  --input TEXT      Text to scan (alternative to stdin)
  --file PATH       Read input from file
  --mode MODE       Action mode: redact (default) or anonymize
  --json            Output full JSON (default)
  --quiet           Only output redacted text
  --stats           Only output statistics
  -h, --help        Show this help message

Patterns Detected:
  API Keys:         OpenAI (sk-*), GitHub (ghp_*, gho_*), AWS (AKIA*), Anthropic (sk-ant-*)
  Personal:         Email addresses, phone numbers, SSN, credit cards
  Tokens:           JWT tokens, private keys, webhook URLs
  Paths:            Home directories (/home/*, /Users/*)

Output (JSON mode):
  {
    "status": "PASS|WARN",
    "redactions": N,
    "patterns_found": ["email", "api_key"],
    "redacted_input": "sanitized text",
    "latency_ms": N
  }

Examples:
  echo "Contact: user@example.com" | $SCRIPT_NAME
  $SCRIPT_NAME --input "API key: sk-abc123xyz789" --mode redact
  $SCRIPT_NAME --file sensitive.txt --quiet
EOF
}

# Redact pattern with placeholder
redact_pattern() {
    local input="$1"
    local pattern="$2"
    local placeholder="$3"

    echo "$input" | sed -E "s/$pattern/$placeholder/g"
}

# Count matches for a pattern
count_pattern() {
    local input="$1"
    local pattern="$2"

    echo "$input" | grep -oE "$pattern" 2>/dev/null | wc -l | tr -d ' '
}

# Check input size limit (M-2/I-3 fix)
check_input_size() {
    local input="$1"
    local size=${#input}

    if [[ $size -gt $MAX_INPUT_SIZE ]]; then
        echo "Error: Input size ($size bytes) exceeds maximum ($MAX_INPUT_SIZE bytes)" >&2
        return 1
    fi
    return 0
}

# Process input and return JSON result
process_input() {
    local input="$1"
    local mode="${2:-$DEFAULT_MODE}"
    local start_time
    local end_time
    local latency_ms

    start_time=$(get_timestamp_ms)

    local redacted="$input"
    local total_redactions=0
    local patterns_found=()

    # API Keys
    local count
    count=$(count_pattern "$redacted" "$PATTERN_OPENAI_KEY")
    if [[ $count -gt 0 ]]; then
        redacted=$(redact_pattern "$redacted" "$PATTERN_OPENAI_KEY" "[REDACTED_OPENAI_KEY]")
        total_redactions=$((total_redactions + count))
        patterns_found+=("openai_key")
    fi

    count=$(count_pattern "$redacted" "$PATTERN_GITHUB_TOKEN")
    if [[ $count -gt 0 ]]; then
        redacted=$(redact_pattern "$redacted" "$PATTERN_GITHUB_TOKEN" "[REDACTED_GITHUB_TOKEN]")
        total_redactions=$((total_redactions + count))
        patterns_found+=("github_token")
    fi

    count=$(count_pattern "$redacted" "$PATTERN_GITHUB_OAUTH")
    if [[ $count -gt 0 ]]; then
        redacted=$(redact_pattern "$redacted" "$PATTERN_GITHUB_OAUTH" "[REDACTED_GITHUB_OAUTH]")
        total_redactions=$((total_redactions + count))
        patterns_found+=("github_oauth")
    fi

    count=$(count_pattern "$redacted" "$PATTERN_AWS_ACCESS")
    if [[ $count -gt 0 ]]; then
        redacted=$(redact_pattern "$redacted" "$PATTERN_AWS_ACCESS" "[REDACTED_AWS_KEY]")
        total_redactions=$((total_redactions + count))
        patterns_found+=("aws_key")
    fi

    count=$(count_pattern "$redacted" "$PATTERN_ANTHROPIC_KEY")
    if [[ $count -gt 0 ]]; then
        redacted=$(redact_pattern "$redacted" "$PATTERN_ANTHROPIC_KEY" "[REDACTED_ANTHROPIC_KEY]")
        total_redactions=$((total_redactions + count))
        patterns_found+=("anthropic_key")
    fi

    # Personal Information
    count=$(count_pattern "$redacted" "$PATTERN_EMAIL")
    if [[ $count -gt 0 ]]; then
        redacted=$(redact_pattern "$redacted" "$PATTERN_EMAIL" "[REDACTED_EMAIL]")
        total_redactions=$((total_redactions + count))
        patterns_found+=("email")
    fi

    count=$(count_pattern "$redacted" "$PATTERN_PHONE")
    if [[ $count -gt 0 ]]; then
        redacted=$(redact_pattern "$redacted" "$PATTERN_PHONE" "[REDACTED_PHONE]")
        total_redactions=$((total_redactions + count))
        patterns_found+=("phone")
    fi

    count=$(count_pattern "$redacted" "$PATTERN_SSN")
    if [[ $count -gt 0 ]]; then
        redacted=$(redact_pattern "$redacted" "$PATTERN_SSN" "[REDACTED_SSN]")
        total_redactions=$((total_redactions + count))
        patterns_found+=("ssn")
    fi

    count=$(count_pattern "$redacted" "$PATTERN_CREDIT_CARD")
    if [[ $count -gt 0 ]]; then
        redacted=$(redact_pattern "$redacted" "$PATTERN_CREDIT_CARD" "[REDACTED_CREDIT_CARD]")
        total_redactions=$((total_redactions + count))
        patterns_found+=("credit_card")
    fi

    # Tokens and Secrets
    count=$(count_pattern "$redacted" "$PATTERN_JWT")
    if [[ $count -gt 0 ]]; then
        redacted=$(redact_pattern "$redacted" "$PATTERN_JWT" "[REDACTED_JWT]")
        total_redactions=$((total_redactions + count))
        patterns_found+=("jwt")
    fi

    count=$(count_pattern "$redacted" "$PATTERN_PRIVATE_KEY")
    if [[ $count -gt 0 ]]; then
        redacted=$(redact_pattern "$redacted" "$PATTERN_PRIVATE_KEY" "[REDACTED_PRIVATE_KEY]")
        total_redactions=$((total_redactions + count))
        patterns_found+=("private_key")
    fi

    count=$(count_pattern "$redacted" "$PATTERN_WEBHOOK_SLACK")
    if [[ $count -gt 0 ]]; then
        redacted=$(redact_pattern "$redacted" "$PATTERN_WEBHOOK_SLACK" "[REDACTED_SLACK_WEBHOOK]")
        total_redactions=$((total_redactions + count))
        patterns_found+=("slack_webhook")
    fi

    count=$(count_pattern "$redacted" "$PATTERN_WEBHOOK_DISCORD")
    if [[ $count -gt 0 ]]; then
        redacted=$(redact_pattern "$redacted" "$PATTERN_WEBHOOK_DISCORD" "[REDACTED_DISCORD_WEBHOOK]")
        total_redactions=$((total_redactions + count))
        patterns_found+=("discord_webhook")
    fi

    # File Paths (anonymize mode)
    if [[ "$mode" == "anonymize" ]]; then
        count=$(count_pattern "$redacted" "$PATTERN_HOME_LINUX")
        if [[ $count -gt 0 ]]; then
            redacted=$(redact_pattern "$redacted" "$PATTERN_HOME_LINUX" "/home/[USER]/")
            total_redactions=$((total_redactions + count))
            patterns_found+=("home_path")
        fi

        count=$(count_pattern "$redacted" "$PATTERN_HOME_MACOS")
        if [[ $count -gt 0 ]]; then
            redacted=$(redact_pattern "$redacted" "$PATTERN_HOME_MACOS" "/Users/[USER]/")
            total_redactions=$((total_redactions + count))
            patterns_found+=("home_path")
        fi
    fi

    end_time=$(get_timestamp_ms)
    latency_ms=$((end_time - start_time))
    [[ $latency_ms -lt 0 ]] && latency_ms=0

    # Determine status
    local status="PASS"
    if [[ $total_redactions -gt 0 ]]; then
        status="WARN"
    fi

    # Build patterns array for JSON
    local patterns_json="[]"
    if [[ ${#patterns_found[@]} -gt 0 ]]; then
        patterns_json=$(printf '%s\n' "${patterns_found[@]}" | jq -R . | jq -s .)
    fi

    # Escape redacted input for JSON
    local redacted_escaped
    redacted_escaped=$(echo "$redacted" | jq -Rs .)

    # Output JSON
    cat <<EOF
{
  "status": "$status",
  "redactions": $total_redactions,
  "patterns_found": $patterns_json,
  "redacted_input": $redacted_escaped,
  "latency_ms": $latency_ms
}
EOF
}

# =============================================================================
# Main
# =============================================================================

main() {
    local input=""
    local mode="$DEFAULT_MODE"
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
            --mode)
                mode="$2"
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
            --stats)
                output_mode="stats"
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

    # Check input size limit (M-2/I-3 fix)
    if ! check_input_size "$input"; then
        exit 1
    fi

    # Validate mode
    if [[ "$mode" != "redact" && "$mode" != "anonymize" ]]; then
        echo "Error: Invalid mode: $mode. Use 'redact' or 'anonymize'." >&2
        exit 1
    fi

    # Process and output
    local result
    result=$(process_input "$input" "$mode")

    case "$output_mode" in
        json)
            echo "$result"
            ;;
        quiet)
            echo "$result" | jq -r '.redacted_input'
            ;;
        stats)
            echo "$result" | jq '{status, redactions, patterns_found, latency_ms}'
            ;;
    esac
}

main "$@"
