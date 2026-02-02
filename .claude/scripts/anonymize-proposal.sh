#!/usr/bin/env bash
# =============================================================================
# anonymize-proposal.sh - PII Redaction for Upstream Proposals
# =============================================================================
# Sprint 2, Task T2.1: Anonymize learning proposals before upstream submission
# Goal Contribution: G-4 (Define proposal schema), G-6 (Maintainer workflow)
#
# Redacts personally identifiable information (PII) patterns:
#   - API keys (sk-*, ghp_*, gho_*, key-*, token-*)
#   - File paths (/home/*, /Users/*, C:\Users\*)
#   - Domain names (specific project domains)
#   - Usernames (@mentions, git author)
#   - IP addresses
#   - Email addresses
#
# Usage:
#   ./anonymize-proposal.sh --input <file>
#   ./anonymize-proposal.sh --stdin
#   echo "content" | ./anonymize-proposal.sh --stdin
#
# Options:
#   --input FILE      Input file to anonymize
#   --stdin           Read from stdin
#   --output FILE     Output file (default: stdout)
#   --validate        Validate completeness after anonymization
#   --strict          Fail if validation finds potential PII
#   --json            Output as JSON with metadata
#   --help            Show this help
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_FILE="$PROJECT_ROOT/.loa.config.yaml"

# Parameters
INPUT_FILE=""
READ_STDIN=false
OUTPUT_FILE=""
VALIDATE=false
STRICT=false
JSON_OUTPUT=false

# Placeholder values
PLACEHOLDER_PATH="[REDACTED_PATH]"
PLACEHOLDER_API_KEY="[REDACTED_API_KEY]"
PLACEHOLDER_TOKEN="[REDACTED_TOKEN]"
PLACEHOLDER_DOMAIN="[REDACTED_DOMAIN]"
PLACEHOLDER_USERNAME="[REDACTED_USER]"
PLACEHOLDER_EMAIL="[REDACTED_EMAIL]"
PLACEHOLDER_IP="[REDACTED_IP]"
PLACEHOLDER_WEBHOOK="[REDACTED_WEBHOOK]"
PLACEHOLDER_JWT="[REDACTED_JWT]"
PLACEHOLDER_PRIVATE_KEY="[REDACTED_PRIVATE_KEY]"
PLACEHOLDER_DB_CREDS="[REDACTED_CREDENTIALS]"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

usage() {
    sed -n '/^# Usage:/,/^# =====/p' "$0" | grep -v "^# =====" | sed 's/^# //'
    exit 0
}

# Read config value with yq, fallback to default
read_config() {
    local path="$1"
    local default="$2"
    if [[ -f "$CONFIG_FILE" ]] && command -v yq &> /dev/null; then
        local value
        value=$(yq -r "$path // \"\"" "$CONFIG_FILE" 2>/dev/null)
        if [[ -n "$value" && "$value" != "null" ]]; then
            echo "$value"
            return
        fi
    fi
    echo "$default"
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --input)
                INPUT_FILE="$2"
                shift 2
                ;;
            --stdin)
                READ_STDIN=true
                shift
                ;;
            --output)
                OUTPUT_FILE="$2"
                shift 2
                ;;
            --validate)
                VALIDATE=true
                shift
                ;;
            --strict)
                STRICT=true
                VALIDATE=true
                shift
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

    if [[ -z "$INPUT_FILE" && "$READ_STDIN" != "true" ]]; then
        echo "[ERROR] Either --input FILE or --stdin is required" >&2
        exit 1
    fi
}

# Get input content
get_input() {
    if [[ "$READ_STDIN" == "true" ]]; then
        cat
    elif [[ -f "$INPUT_FILE" ]]; then
        cat "$INPUT_FILE"
    else
        echo "[ERROR] File not found: $INPUT_FILE" >&2
        exit 1
    fi
}

# Redact API keys (sk-*, ghp_*, gho_*, key-*, token-*)
redact_api_keys() {
    local content="$1"

    # Anthropic API keys
    content=$(echo "$content" | sed -E 's/sk-ant-[a-zA-Z0-9_-]+/'"$PLACEHOLDER_API_KEY"'/g')
    content=$(echo "$content" | sed -E 's/sk-[a-zA-Z0-9_-]{20,}/'"$PLACEHOLDER_API_KEY"'/g')

    # GitHub tokens
    content=$(echo "$content" | sed -E 's/ghp_[a-zA-Z0-9]{36}/'"$PLACEHOLDER_TOKEN"'/g')
    content=$(echo "$content" | sed -E 's/gho_[a-zA-Z0-9]{36}/'"$PLACEHOLDER_TOKEN"'/g')
    content=$(echo "$content" | sed -E 's/ghs_[a-zA-Z0-9]{36}/'"$PLACEHOLDER_TOKEN"'/g')
    content=$(echo "$content" | sed -E 's/ghr_[a-zA-Z0-9]{36}/'"$PLACEHOLDER_TOKEN"'/g')

    # Generic keys and tokens
    content=$(echo "$content" | sed -E 's/[a-zA-Z_]*[Kk]ey[a-zA-Z_]*[=:]["'\''"]?[a-zA-Z0-9_-]{16,}["'\''"]?/'"$PLACEHOLDER_API_KEY"'/g')
    content=$(echo "$content" | sed -E 's/[a-zA-Z_]*[Tt]oken[a-zA-Z_]*[=:]["'\''"]?[a-zA-Z0-9_-]{16,}["'\''"]?/'"$PLACEHOLDER_TOKEN"'/g')

    # AWS keys
    content=$(echo "$content" | sed -E 's/AKIA[A-Z0-9]{16}/'"$PLACEHOLDER_API_KEY"'/g')

    # HIGH-001 FIX: Additional credential patterns

    # Slack webhooks (https://hooks.slack.com/services/T.../B.../...)
    content=$(echo "$content" | sed -E 's|https://hooks\.slack\.com/services/[A-Za-z0-9/]+|'"$PLACEHOLDER_WEBHOOK"'|g')

    # JWT tokens (three base64-encoded sections separated by dots)
    content=$(echo "$content" | sed -E 's/eyJ[A-Za-z0-9_-]*\.eyJ[A-Za-z0-9_-]*\.[A-Za-z0-9_-]*/'"$PLACEHOLDER_JWT"'/g')

    # Bearer tokens in Authorization headers
    content=$(echo "$content" | sed -E 's/[Bb]earer [A-Za-z0-9_.-]{20,}/Bearer '"$PLACEHOLDER_TOKEN"'/g')

    # Database connection strings with credentials (postgresql://, mysql://, mongodb://, redis://)
    content=$(echo "$content" | sed -E 's|://[^:]+:[^@]+@|://'"$PLACEHOLDER_DB_CREDS"'@|g')

    # Discord webhooks
    content=$(echo "$content" | sed -E 's|https://discord\.com/api/webhooks/[0-9]+/[A-Za-z0-9_-]+|'"$PLACEHOLDER_WEBHOOK"'|g')

    # Stripe keys
    content=$(echo "$content" | sed -E 's/sk_live_[a-zA-Z0-9]{24,}/'"$PLACEHOLDER_API_KEY"'/g')
    content=$(echo "$content" | sed -E 's/pk_live_[a-zA-Z0-9]{24,}/'"$PLACEHOLDER_API_KEY"'/g')
    content=$(echo "$content" | sed -E 's/sk_test_[a-zA-Z0-9]{24,}/'"$PLACEHOLDER_API_KEY"'/g')
    content=$(echo "$content" | sed -E 's/pk_test_[a-zA-Z0-9]{24,}/'"$PLACEHOLDER_API_KEY"'/g')

    echo "$content"
}

# Redact file paths
redact_paths() {
    local content="$1"

    # Unix home directories
    content=$(echo "$content" | sed -E 's|/home/[a-zA-Z0-9_-]+/|'"$PLACEHOLDER_PATH"'/|g')
    content=$(echo "$content" | sed -E 's|/Users/[a-zA-Z0-9_-]+/|'"$PLACEHOLDER_PATH"'/|g')
    content=$(echo "$content" | sed -E 's|~/|'"$PLACEHOLDER_PATH"'/|g')

    # Windows paths
    content=$(echo "$content" | sed -E 's|C:\\Users\\[a-zA-Z0-9_-]+\\|'"$PLACEHOLDER_PATH"'\\|g')
    content=$(echo "$content" | sed -E 's|C:/Users/[a-zA-Z0-9_-]+/|'"$PLACEHOLDER_PATH"'/|g')

    echo "$content"
}

# Redact domain names (but preserve common domains like github.com, anthropic.com)
redact_domains() {
    local content="$1"

    # Get project-specific domain from urls.yaml if exists
    local project_domain=""
    local urls_file="$PROJECT_ROOT/grimoires/loa/urls.yaml"
    if [[ -f "$urls_file" ]] && command -v yq &> /dev/null; then
        project_domain=$(yq -r '.environments.production.base // ""' "$urls_file" 2>/dev/null | sed 's|https\?://||' | cut -d'/' -f1)
    fi

    # Redact project domain if found
    if [[ -n "$project_domain" && "$project_domain" != "your-domain.example.com" ]]; then
        content=$(echo "$content" | sed "s|$project_domain|$PLACEHOLDER_DOMAIN|g")
    fi

    # Redact localhost with ports (may contain project info)
    content=$(echo "$content" | sed -E 's|localhost:[0-9]+|localhost|g')

    # Redact internal/staging domains
    content=$(echo "$content" | sed -E 's|https?://[a-zA-Z0-9_-]+\.internal\.[a-zA-Z.]+|'"$PLACEHOLDER_DOMAIN"'|g')
    content=$(echo "$content" | sed -E 's|https?://staging\.[a-zA-Z0-9_.-]+|'"$PLACEHOLDER_DOMAIN"'|g')
    content=$(echo "$content" | sed -E 's|https?://dev\.[a-zA-Z0-9_.-]+|'"$PLACEHOLDER_DOMAIN"'|g')

    echo "$content"
}

# Redact usernames
redact_usernames() {
    local content="$1"

    # @mentions (GitHub, etc.)
    content=$(echo "$content" | sed -E 's/@[a-zA-Z0-9_-]{3,}/'"$PLACEHOLDER_USERNAME"'/g')

    # Git author format "Name <email>"
    content=$(echo "$content" | sed -E 's/[A-Z][a-z]+ [A-Z][a-z]+ <[^>]+>/'"$PLACEHOLDER_USERNAME <$PLACEHOLDER_EMAIL>"'/g')

    # Remove git user config references
    content=$(echo "$content" | sed -E 's/user\.(name|email)\s*=\s*[^\n]+/user.\1 = '"$PLACEHOLDER_USERNAME"'/g')

    echo "$content"
}

# Redact email addresses
redact_emails() {
    local content="$1"

    # Standard email pattern
    content=$(echo "$content" | sed -E 's/[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/'"$PLACEHOLDER_EMAIL"'/g')

    echo "$content"
}

# Redact IP addresses
redact_ips() {
    local content="$1"

    # IPv4
    content=$(echo "$content" | sed -E 's/\b([0-9]{1,3}\.){3}[0-9]{1,3}\b/'"$PLACEHOLDER_IP"'/g')

    # IPv6 (simplified)
    content=$(echo "$content" | sed -E 's/\b([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}\b/'"$PLACEHOLDER_IP"'/g')

    echo "$content"
}

# HIGH-001 FIX: Redact private key blocks
redact_private_keys() {
    local content="$1"

    # PEM-encoded private keys (RSA, EC, DSA, OPENSSH, etc.)
    # Match -----BEGIN ... PRIVATE KEY----- ... -----END ... PRIVATE KEY-----
    # Using sed with multiline support via loop
    content=$(echo "$content" | sed -E ':a;N;$!ba;s/-----BEGIN[^-]*PRIVATE KEY-----[^-]*-----END[^-]*PRIVATE KEY-----/'"$PLACEHOLDER_PRIVATE_KEY"'/g')

    # SSH private key markers (OpenSSH format)
    content=$(echo "$content" | sed -E ':a;N;$!ba;s/-----BEGIN OPENSSH PRIVATE KEY-----[^-]*-----END OPENSSH PRIVATE KEY-----/'"$PLACEHOLDER_PRIVATE_KEY"'/g')

    # Certificates (may contain private data)
    content=$(echo "$content" | sed -E ':a;N;$!ba;s/-----BEGIN CERTIFICATE-----[^-]*-----END CERTIFICATE-----/[REDACTED_CERTIFICATE]/g')

    echo "$content"
}

# Run all redactions
anonymize() {
    local content="$1"

    content=$(redact_api_keys "$content")
    content=$(redact_paths "$content")
    content=$(redact_domains "$content")
    content=$(redact_usernames "$content")
    content=$(redact_emails "$content")
    content=$(redact_ips "$content")
    content=$(redact_private_keys "$content")

    echo "$content"
}

# Validate that anonymization is complete
validate_anonymization() {
    local content="$1"
    local issues=()

    # Check for remaining potential PII patterns

    # Potential API keys (long alphanumeric strings)
    if echo "$content" | grep -qE '[a-zA-Z0-9_-]{32,}' 2>/dev/null; then
        # Exclude already-redacted placeholders
        if echo "$content" | grep -vE '\[REDACTED' | grep -qE '[a-zA-Z0-9_-]{32,}' 2>/dev/null; then
            issues+=("Potential API key detected")
        fi
    fi

    # Potential file paths
    if echo "$content" | grep -qE '/[a-z]+/[a-z]+/' 2>/dev/null; then
        if echo "$content" | grep -vE '\[REDACTED' | grep -vE '^(/usr/|/var/|/etc/|/tmp/)' | grep -qE '/[a-z]+/[a-z]+/' 2>/dev/null; then
            issues+=("Potential file path detected")
        fi
    fi

    # Potential email still present
    if echo "$content" | grep -vE '\[REDACTED' | grep -qE '@[a-zA-Z]+\.' 2>/dev/null; then
        issues+=("Potential email address detected")
    fi

    # Check for remaining IPs
    if echo "$content" | grep -vE '\[REDACTED' | grep -qE '\b[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\b' 2>/dev/null; then
        issues+=("Potential IP address detected")
    fi

    echo "${issues[*]:-}"
}

# Count redactions performed
count_redactions() {
    local content="$1"
    local count=0

    count=$((count + $(echo "$content" | grep -o '\[REDACTED_PATH\]' | wc -l)))
    count=$((count + $(echo "$content" | grep -o '\[REDACTED_API_KEY\]' | wc -l)))
    count=$((count + $(echo "$content" | grep -o '\[REDACTED_TOKEN\]' | wc -l)))
    count=$((count + $(echo "$content" | grep -o '\[REDACTED_DOMAIN\]' | wc -l)))
    count=$((count + $(echo "$content" | grep -o '\[REDACTED_USER\]' | wc -l)))
    count=$((count + $(echo "$content" | grep -o '\[REDACTED_EMAIL\]' | wc -l)))
    count=$((count + $(echo "$content" | grep -o '\[REDACTED_IP\]' | wc -l)))
    # HIGH-001 FIX: Count new redaction types
    count=$((count + $(echo "$content" | grep -o '\[REDACTED_WEBHOOK\]' | wc -l)))
    count=$((count + $(echo "$content" | grep -o '\[REDACTED_JWT\]' | wc -l)))
    count=$((count + $(echo "$content" | grep -o '\[REDACTED_PRIVATE_KEY\]' | wc -l)))
    count=$((count + $(echo "$content" | grep -o '\[REDACTED_CREDENTIALS\]' | wc -l)))
    count=$((count + $(echo "$content" | grep -o '\[REDACTED_CERTIFICATE\]' | wc -l)))

    echo "$count"
}

main() {
    parse_args "$@"

    # Get input
    local input
    input=$(get_input)

    # Anonymize
    local output
    output=$(anonymize "$input")

    # Validate if requested
    local validation_issues=""
    local validation_passed=true
    if [[ "$VALIDATE" == "true" ]]; then
        validation_issues=$(validate_anonymization "$output")
        if [[ -n "$validation_issues" ]]; then
            validation_passed=false
            if [[ "$STRICT" == "true" ]]; then
                echo "[ERROR] Validation failed: $validation_issues" >&2
                exit 1
            else
                echo "[WARNING] Validation issues: $validation_issues" >&2
            fi
        fi
    fi

    # Output
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        local redaction_count
        redaction_count=$(count_redactions "$output")

        jq -n \
            --arg content "$output" \
            --argjson redactions "$redaction_count" \
            --argjson validated "$([[ "$VALIDATE" == "true" ]] && echo true || echo false)" \
            --argjson passed "$([[ "$validation_passed" == "true" ]] && echo true || echo false)" \
            --arg issues "$validation_issues" \
            '{
                anonymized_content: $content,
                metadata: {
                    redactions_performed: $redactions,
                    validation: {
                        performed: $validated,
                        passed: $passed,
                        issues: (if $issues == "" then null else $issues end)
                    }
                }
            }'
    else
        if [[ -n "$OUTPUT_FILE" ]]; then
            echo "$output" > "$OUTPUT_FILE"
            echo "[INFO] Anonymized content written to: $OUTPUT_FILE" >&2
        else
            echo "$output"
        fi
    fi
}

main "$@"
