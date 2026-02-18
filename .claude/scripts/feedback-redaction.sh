#!/usr/bin/env bash
# =============================================================================
# feedback-redaction.sh - Content redaction for external feedback submissions
# =============================================================================
# Version: 1.0.0
# Cycle: cycle-025 (Cross-Codebase Feedback Routing)
# Source: grimoires/loa/sdd.md §2.2
#
# Strips sensitive content from feedback before filing on external repos.
# Two-pass approach: regex patterns first, entropy scan second.
#
# Usage:
#   feedback-redaction.sh --input <file> [--config <yaml>] [--preview]
#   echo "content" | feedback-redaction.sh --input -
#
# Exit codes:
#   0 - Redaction successful
#   1 - Invalid input (missing --input, unreadable file)
#   2 - Redaction produced empty output (input was entirely sensitive)
#
# Output:
#   stdout: redacted text
#   --preview: shows redaction summary to stderr, redacted text to stdout
#
# Redaction output contract:
#   - Redacted text on stdout (exit 0)
#   - Original content NEVER appears in stdout when redaction succeeds
#   - Preview mode writes diff info to stderr only
#   - Empty output after redaction triggers exit code 2
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Argument parsing ---

INPUT_FILE=""
CONFIG_FILE=".loa.config.yaml"
PREVIEW_MODE=false

usage() {
    cat << 'USAGE_EOF'
feedback-redaction.sh - Redact sensitive content from feedback

USAGE:
    feedback-redaction.sh --input <file> [--config <yaml>] [--preview]
    echo "content" | feedback-redaction.sh --input -

OPTIONS:
    --input <file>    Input file to redact (use - for stdin)
    --config <file>   Configuration file (default: .loa.config.yaml)
    --preview         Show redaction summary to stderr
    --help            Show this help message

EXIT CODES:
    0 - Redaction successful
    1 - Invalid input
    2 - Empty output after redaction
USAGE_EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --input)
            if [[ $# -lt 2 ]]; then
                echo "Error: --input requires a value" >&2
                exit 1
            fi
            INPUT_FILE="$2"
            shift 2
            ;;
        --config)
            if [[ $# -lt 2 ]]; then
                echo "Error: --config requires a value" >&2
                exit 1
            fi
            CONFIG_FILE="$2"
            shift 2
            ;;
        --preview)
            PREVIEW_MODE=true
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "Error: Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

# Validate required argument
if [[ -z "$INPUT_FILE" ]]; then
    echo "Error: --input is required" >&2
    usage >&2
    exit 1
fi

# Read input
INPUT=""
if [[ "$INPUT_FILE" == "-" ]]; then
    INPUT=$(cat)
elif [[ -f "$INPUT_FILE" ]]; then
    INPUT=$(cat "$INPUT_FILE")
else
    echo "Error: Input file not found: $INPUT_FILE" >&2
    exit 1
fi

if [[ -z "$INPUT" ]]; then
    echo "Error: Input is empty" >&2
    exit 1
fi

# --- Read configuration toggles ---

INCLUDE_SNIPPETS="false"
INCLUDE_FILE_REFS="true"
INCLUDE_ENVIRONMENT="false"

if [[ -f "$CONFIG_FILE" ]] && command -v yq &>/dev/null; then
    INCLUDE_SNIPPETS=$(yq '.feedback.routing.construct_routing.redaction.include_snippets // false' "$CONFIG_FILE" 2>/dev/null || echo "false")
    INCLUDE_FILE_REFS=$(yq '.feedback.routing.construct_routing.redaction.include_file_refs // true' "$CONFIG_FILE" 2>/dev/null || echo "true")
    INCLUDE_ENVIRONMENT=$(yq '.feedback.routing.construct_routing.redaction.include_environment // false' "$CONFIG_FILE" 2>/dev/null || echo "false")
fi

# --- Pass 1: Regex-based redaction ---

REDACTED="$INPUT"
REDACTION_COUNT=0

# Helper: apply sed pattern and count replacements
apply_redaction() {
    local pattern="$1"
    local replacement="$2"
    local before="$REDACTED"
    REDACTED=$(printf '%s' "$REDACTED" | sed -E "$pattern" 2>/dev/null || printf '%s' "$REDACTED")
    if [[ "$REDACTED" != "$before" ]]; then
        REDACTION_COUNT=$((REDACTION_COUNT + 1))
    fi
}

# AWS keys: AKIA followed by 16 uppercase alphanumeric chars
apply_redaction 's/AKIA[0-9A-Z]{16}/<redacted-aws-key>/g' ""

# GitHub tokens: ghp_, ghs_, gho_, ghr_, github_pat_
apply_redaction 's/gh[psort]_[A-Za-z0-9_]{36,}/<redacted-github-token>/g' ""
apply_redaction 's/github_pat_[A-Za-z0-9_]{22,}/<redacted-github-pat>/g' ""

# JWT tokens: eyJ followed by base64
apply_redaction 's/eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+(\.[A-Za-z0-9_-]+)?/<redacted-jwt>/g' ""

# Generic secrets: key=value patterns (skip already-redacted values starting with <)
apply_redaction 's/(password|secret|token|api_key|apikey|api-key)[[:space:]]*[=:][[:space:]]*[^<[:space:]"][^[:space:]"]*/\1=<redacted>/gi' ""

# Absolute paths: /home/*, /Users/*, /tmp/*
apply_redaction 's|/home/[^[:space:]/]+/|<redacted-path>/|g' ""
apply_redaction 's|/Users/[^[:space:]/]+/|<redacted-path>/|g' ""
apply_redaction 's|/tmp/[^[:space:]]+|<redacted-tmp-path>|g' ""

# Home directory references
apply_redaction 's|~/\.[^[:space:]]+|~/<redacted>|g' ""
apply_redaction 's|\$HOME/\.[^[:space:]]+|\$HOME/<redacted>|g' ""

# SSH and credential paths
apply_redaction 's|~/.ssh/[^[:space:]]*|<redacted-credential-path>|g' ""
apply_redaction 's|~/.gnupg/[^[:space:]]*|<redacted-credential-path>|g' ""
apply_redaction 's|~/.aws/[^[:space:]]*|<redacted-credential-path>|g' ""
apply_redaction 's|~/.claude/[^[:space:]]*|~/.claude/<redacted>|g' ""

# Git credentials in URLs
apply_redaction 's|https://[^@[:space:]]+@|https://<redacted>@|g' ""

# Environment variable assignments (in env-like context)
apply_redaction 's/^([A-Z_]{3,})=(.+)$/\1=<redacted>/gm' ""

# --- User toggle: strip code blocks ---

if [[ "$INCLUDE_SNIPPETS" != "true" ]]; then
    # Remove fenced code blocks (``` ... ```)
    REDACTED=$(printf '%s' "$REDACTED" | awk '
        /^```/ { in_block = !in_block; next }
        !in_block { print }
    ')
    REDACTION_COUNT=$((REDACTION_COUNT + 1))
fi

# --- User toggle: strip environment section ---

if [[ "$INCLUDE_ENVIRONMENT" != "true" ]]; then
    # Remove "Environment" or "System Info" sections
    REDACTED=$(printf '%s' "$REDACTED" | awk '
        /^##[[:space:]]+(Environment|System Info|System Information)/ { skip = 1; next }
        /^##[[:space:]]+/ && skip { skip = 0 }
        !skip { print }
    ')
fi

# --- User toggle: redact file paths in references ---

if [[ "$INCLUDE_FILE_REFS" == "true" ]]; then
    # Keep file references but ensure paths are relative
    apply_redaction 's|([^[:space:]]*/)?([^[:space:]]+\.[a-zA-Z]{1,5}):([0-9]+)|\2:\3|g' ""
fi

# --- Pass 2: Entropy-based scan ---
# Flag strings > 20 chars with Shannon entropy > 4.5 bits/char
# Uses awk for portable entropy calculation

entropy_scan() {
    local text="$1"

    printf '%s' "$text" | awk '
    function entropy(s,    i, n, freq, c, h, p) {
        n = length(s)
        if (n == 0) return 0
        delete freq
        for (i = 1; i <= n; i++) {
            c = substr(s, i, 1)
            freq[c]++
        }
        h = 0
        for (c in freq) {
            p = freq[c] / n
            if (p > 0) h -= p * (log(p) / log(2))
        }
        return h
    }

    function is_allowlisted(token) {
        # SHA256 hashes (64 hex chars)
        if (token ~ /^[a-f0-9]{64}$/) return 1
        # UUIDs
        if (token ~ /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/) return 1
        # Already redacted
        if (token ~ /^<redacted/) return 1
        # URL-like strings
        if (token ~ /^https?:\/\//) return 1
        return 0
    }

    {
        line = $0
        split(line, words, /[[:space:]]+/)
        for (i in words) {
            w = words[i]
            if (length(w) > 20 && !is_allowlisted(w)) {
                h = entropy(w)
                if (h > 4.5) {
                    gsub(w, "<high-entropy-redacted>", line)
                }
            }
        }
        print line
    }
    '
}

BEFORE_ENTROPY="$REDACTED"
REDACTED=$(entropy_scan "$REDACTED")
if [[ "$REDACTED" != "$BEFORE_ENTROPY" ]]; then
    REDACTION_COUNT=$((REDACTION_COUNT + 1))
fi

# --- Check for empty output ---

TRIMMED=$(printf '%s' "$REDACTED" | sed '/^[[:space:]]*$/d')
if [[ -z "$TRIMMED" ]]; then
    echo "Error: Redaction produced empty output (input was entirely sensitive)" >&2
    exit 2
fi

# --- Preview mode output ---

if [[ "$PREVIEW_MODE" == "true" ]]; then
    echo "=== Redaction Summary ===" >&2
    echo "Redaction passes applied: $REDACTION_COUNT" >&2
    echo "Input length: ${#INPUT} chars" >&2
    echo "Output length: ${#REDACTED} chars" >&2

    if [[ "$INCLUDE_SNIPPETS" != "true" ]]; then
        echo "Code blocks: STRIPPED" >&2
    else
        echo "Code blocks: KEPT" >&2
    fi

    if [[ "$INCLUDE_ENVIRONMENT" != "true" ]]; then
        echo "Environment section: STRIPPED" >&2
    else
        echo "Environment section: KEPT" >&2
    fi

    if [[ "$INCLUDE_FILE_REFS" == "true" ]]; then
        echo "File references: KEPT (paths redacted)" >&2
    else
        echo "File references: STRIPPED" >&2
    fi

    echo "=========================" >&2
fi

# --- Output redacted content ---

printf '%s\n' "$REDACTED"
