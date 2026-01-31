#!/usr/bin/env bash
#
# collect-trace.sh - Gather execution traces for feedback submission
#
# Usage:
#   ./collect-trace.sh [--scope <execution|full|failure-window>] [--output <file>]
#
# Exit codes:
#   0 - Success
#   1 - Configuration disabled or missing
#   2 - Required files missing (graceful degradation, still outputs)
#   3 - jq not available (warning, continues with basic output)

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

CONFIG_FILE="$PROJECT_ROOT/.claude/settings.local.json"
GRIMOIRE_PATH="$PROJECT_ROOT/grimoires/loa"

# Default values
DEFAULT_SCOPE="execution"
DEFAULT_FAILURE_WINDOW=10
MAX_TRAJECTORY_ENTRIES=100
MAX_PLAN_SIZE=10240  # 10KB
MAX_TOTAL_SIZE=51200 # 50KB

# =============================================================================
# Helpers
# =============================================================================

log_info() {
    echo "[INFO] $*" >&2
}

log_warn() {
    echo "[WARN] $*" >&2
}

log_error() {
    echo "[ERROR] $*" >&2
}

show_help() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Gather execution traces for feedback submission with automatic secret redaction.

Options:
  --scope <scope>     Trace scope: execution (default), full, failure-window
  --output <file>     Output file (default: stdout)
  --window-size <n>   Failure window size in turns (default: 10)
  -h, --help          Show this help message

Trace Scopes:
  execution       Plan, ledger, full trajectory (most common)
  full            Everything + NOTES.md + session context
  failure-window  Plan, ledger, ±N turns around failure point

Exit Codes:
  0  Success
  1  Configuration disabled or not found
  2  Some required files missing (partial output)
  3  jq not available (basic output)

Example:
  ./collect-trace.sh --scope execution
  ./collect-trace.sh --scope failure-window --window-size 15 --output trace.json
EOF
}

# =============================================================================
# Configuration Reading
# =============================================================================

get_config_value() {
    local key="$1"
    local default="$2"

    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "$default"
        return
    fi

    if command -v jq &>/dev/null; then
        local value
        value=$(jq -r ".feedback.$key // \"$default\"" "$CONFIG_FILE" 2>/dev/null)
        if [[ "$value" == "null" ]]; then
            echo "$default"
        else
            echo "$value"
        fi
    else
        # Basic fallback without jq
        echo "$default"
    fi
}

check_trace_enabled() {
    local enabled
    enabled=$(get_config_value "collectTraces" "false")

    if [[ "$enabled" != "true" ]]; then
        log_error "Trace collection is not enabled"
        log_info "To enable, create $CONFIG_FILE with:"
        log_info '  {"feedback": {"collectTraces": true}}'
        return 1
    fi
    return 0
}

# =============================================================================
# Secret Redaction
# =============================================================================

REDACTION_COUNT=0
PATTERNS_MATCHED=()

redact_secrets() {
    local content="$1"
    local redacted="$content"
    local original_length=${#content}

    # -------------------------------------------------------------------------
    # Anthropic API keys (sk-ant-*, sk-*)
    # -------------------------------------------------------------------------
    if echo "$redacted" | grep -qE 'sk-ant-[a-zA-Z0-9-]{32,}'; then
        redacted=$(echo "$redacted" | sed -E 's/sk-ant-[a-zA-Z0-9-]{32,}/[REDACTED:ANTHROPIC_KEY]/g')
        PATTERNS_MATCHED+=("sk-ant-*")
    fi
    if echo "$redacted" | grep -qE 'sk-[a-zA-Z0-9]{32,}'; then
        redacted=$(echo "$redacted" | sed -E 's/sk-[a-zA-Z0-9]{32,}/[REDACTED:ANTHROPIC_KEY]/g')
        PATTERNS_MATCHED+=("sk-*")
    fi

    # -------------------------------------------------------------------------
    # OpenAI API keys (sk-proj-*, sk-admin-*, legacy sk-*)
    # -------------------------------------------------------------------------
    if echo "$redacted" | grep -qE 'sk-proj-[a-zA-Z0-9]{48,}'; then
        redacted=$(echo "$redacted" | sed -E 's/sk-proj-[a-zA-Z0-9]{48,}/[REDACTED:OPENAI_KEY]/g')
        PATTERNS_MATCHED+=("sk-proj-*")
    fi
    if echo "$redacted" | grep -qE 'sk-admin-[a-zA-Z0-9]{48,}'; then
        redacted=$(echo "$redacted" | sed -E 's/sk-admin-[a-zA-Z0-9]{48,}/[REDACTED:OPENAI_ADMIN_KEY]/g')
        PATTERNS_MATCHED+=("sk-admin-*")
    fi

    # -------------------------------------------------------------------------
    # AWS keys
    # -------------------------------------------------------------------------
    if echo "$redacted" | grep -qE 'AKIA[0-9A-Z]{16}'; then
        redacted=$(echo "$redacted" | sed -E 's/AKIA[0-9A-Z]{16}/[REDACTED:AWS_ACCESS_KEY]/g')
        PATTERNS_MATCHED+=("AKIA*")
    fi

    # -------------------------------------------------------------------------
    # GitHub tokens (ghp_*, gho_*, ghs_*, ghr_*)
    # -------------------------------------------------------------------------
    if echo "$redacted" | grep -qE 'ghp_[a-zA-Z0-9]{36}'; then
        redacted=$(echo "$redacted" | sed -E 's/ghp_[a-zA-Z0-9]{36}/[REDACTED:GITHUB_PAT]/g')
        PATTERNS_MATCHED+=("ghp_*")
    fi
    if echo "$redacted" | grep -qE 'gho_[a-zA-Z0-9]{36}'; then
        redacted=$(echo "$redacted" | sed -E 's/gho_[a-zA-Z0-9]{36}/[REDACTED:GITHUB_OAUTH]/g')
        PATTERNS_MATCHED+=("gho_*")
    fi
    if echo "$redacted" | grep -qE 'ghs_[a-zA-Z0-9]{36}'; then
        redacted=$(echo "$redacted" | sed -E 's/ghs_[a-zA-Z0-9]{36}/[REDACTED:GITHUB_APP]/g')
        PATTERNS_MATCHED+=("ghs_*")
    fi
    if echo "$redacted" | grep -qE 'ghr_[a-zA-Z0-9]{36}'; then
        redacted=$(echo "$redacted" | sed -E 's/ghr_[a-zA-Z0-9]{36}/[REDACTED:GITHUB_REFRESH]/g')
        PATTERNS_MATCHED+=("ghr_*")
    fi

    # -------------------------------------------------------------------------
    # Stripe keys (sk_live_*, pk_live_*, sk_test_*, pk_test_*)
    # -------------------------------------------------------------------------
    if echo "$redacted" | grep -qE '[sp]k_(live|test)_[a-zA-Z0-9]{24,}'; then
        redacted=$(echo "$redacted" | sed -E 's/sk_(live|test)_[a-zA-Z0-9]{24,}/[REDACTED:STRIPE_SECRET]/g')
        redacted=$(echo "$redacted" | sed -E 's/pk_(live|test)_[a-zA-Z0-9]{24,}/[REDACTED:STRIPE_PUBLIC]/g')
        PATTERNS_MATCHED+=("stripe_*")
    fi

    # -------------------------------------------------------------------------
    # Slack tokens (xox[baprs]-*)
    # -------------------------------------------------------------------------
    if echo "$redacted" | grep -qE 'xox[baprs]-[a-zA-Z0-9-]+'; then
        redacted=$(echo "$redacted" | sed -E 's/xox[baprs]-[a-zA-Z0-9-]+/[REDACTED:SLACK_TOKEN]/g')
        PATTERNS_MATCHED+=("xox*")
    fi

    # -------------------------------------------------------------------------
    # Linear API keys (lin_api_*)
    # -------------------------------------------------------------------------
    if echo "$redacted" | grep -qE 'lin_api_[a-zA-Z0-9]+'; then
        redacted=$(echo "$redacted" | sed -E 's/lin_api_[a-zA-Z0-9]+/[REDACTED:LINEAR_KEY]/g')
        PATTERNS_MATCHED+=("lin_api_*")
    fi

    # -------------------------------------------------------------------------
    # SendGrid keys (SG.*)
    # -------------------------------------------------------------------------
    if echo "$redacted" | grep -qE 'SG\.[a-zA-Z0-9_-]{22}\.[a-zA-Z0-9_-]{43}'; then
        redacted=$(echo "$redacted" | sed -E 's/SG\.[a-zA-Z0-9_-]{22}\.[a-zA-Z0-9_-]{43}/[REDACTED:SENDGRID_KEY]/g')
        PATTERNS_MATCHED+=("SG.*")
    fi

    # -------------------------------------------------------------------------
    # JWT tokens (eyJ*.eyJ*.*)
    # -------------------------------------------------------------------------
    if echo "$redacted" | grep -qE 'eyJ[a-zA-Z0-9_-]*\.eyJ[a-zA-Z0-9_-]*\.[a-zA-Z0-9_-]*'; then
        redacted=$(echo "$redacted" | sed -E 's/eyJ[a-zA-Z0-9_-]*\.eyJ[a-zA-Z0-9_-]*\.[a-zA-Z0-9_-]*/[REDACTED:JWT]/g')
        PATTERNS_MATCHED+=("jwt")
    fi

    # -------------------------------------------------------------------------
    # Database connection strings (postgres://, mongodb://, mysql://, redis://)
    # -------------------------------------------------------------------------
    if echo "$redacted" | grep -qE 'postgres(ql)?://[^:]+:[^@]+@'; then
        redacted=$(echo "$redacted" | sed -E 's|(postgres(ql)?://)[^:]+:[^@]+@|\1[REDACTED]@|g')
        PATTERNS_MATCHED+=("postgres_uri")
    fi
    if echo "$redacted" | grep -qE 'mongodb(\+srv)?://[^:]+:[^@]+@'; then
        redacted=$(echo "$redacted" | sed -E 's|(mongodb(\+srv)?://)[^:]+:[^@]+@|\1[REDACTED]@|g')
        PATTERNS_MATCHED+=("mongodb_uri")
    fi
    if echo "$redacted" | grep -qE 'mysql://[^:]+:[^@]+@'; then
        redacted=$(echo "$redacted" | sed -E 's|(mysql://)[^:]+:[^@]+@|\1[REDACTED]@|g')
        PATTERNS_MATCHED+=("mysql_uri")
    fi
    if echo "$redacted" | grep -qE 'redis://:[^@]+@'; then
        redacted=$(echo "$redacted" | sed -E 's|(redis://):[^@]+@|\1[REDACTED]@|g')
        PATTERNS_MATCHED+=("redis_uri")
    fi

    # -------------------------------------------------------------------------
    # Private keys (PEM format)
    # -------------------------------------------------------------------------
    if echo "$redacted" | grep -qE '-----BEGIN[^-]*PRIVATE KEY-----'; then
        redacted=$(echo "$redacted" | sed -E 's/-----BEGIN[^-]*PRIVATE KEY-----[^-]*-----END[^-]*PRIVATE KEY-----/[REDACTED:PRIVATE_KEY]/g')
        PATTERNS_MATCHED+=("private_key")
    fi

    # -------------------------------------------------------------------------
    # HIGH-003 FIX: OpenSSH private keys (different format from PEM)
    # -------------------------------------------------------------------------
    if echo "$redacted" | grep -qE '-----BEGIN OPENSSH PRIVATE KEY-----'; then
        redacted=$(echo "$redacted" | sed -E 's/-----BEGIN OPENSSH PRIVATE KEY-----[^-]*-----END OPENSSH PRIVATE KEY-----/[REDACTED:OPENSSH_KEY]/g')
        PATTERNS_MATCHED+=("openssh_key")
    fi

    # -------------------------------------------------------------------------
    # HIGH-003 FIX: Hex private keys (64-char hex strings that look like keys)
    # Common in Ethereum/Web3 contexts: 0x followed by 64 hex chars
    # -------------------------------------------------------------------------
    if echo "$redacted" | grep -qE '0x[a-fA-F0-9]{64}'; then
        redacted=$(echo "$redacted" | sed -E 's/0x[a-fA-F0-9]{64}/[REDACTED:HEX_KEY]/g')
        PATTERNS_MATCHED+=("hex_private_key")
    fi

    # -------------------------------------------------------------------------
    # HIGH-003 FIX: Base64-encoded secrets (high-entropy long strings)
    # Target: 40+ chars of base64 that end with = or ==
    # -------------------------------------------------------------------------
    if echo "$redacted" | grep -qE '[A-Za-z0-9+/]{40,}={1,2}'; then
        redacted=$(echo "$redacted" | sed -E 's/[A-Za-z0-9+/]{60,}={1,2}/[REDACTED:BASE64_SECRET]/g')
        PATTERNS_MATCHED+=("base64_secret")
    fi

    # -------------------------------------------------------------------------
    # HIGH-003 FIX: OAuth refresh tokens (long alphanumeric strings)
    # Common pattern: 1//{long_alphanumeric} or ya29.{long_alphanumeric}
    # -------------------------------------------------------------------------
    if echo "$redacted" | grep -qE '1//[a-zA-Z0-9_-]{40,}'; then
        redacted=$(echo "$redacted" | sed -E 's/1\/\/[a-zA-Z0-9_-]{40,}/[REDACTED:OAUTH_REFRESH]/g')
        PATTERNS_MATCHED+=("oauth_refresh")
    fi
    if echo "$redacted" | grep -qE 'ya29\.[a-zA-Z0-9_-]{50,}'; then
        redacted=$(echo "$redacted" | sed -E 's/ya29\.[a-zA-Z0-9_-]{50,}/[REDACTED:GOOGLE_ACCESS]/g')
        PATTERNS_MATCHED+=("google_access_token")
    fi

    # -------------------------------------------------------------------------
    # Generic key/token patterns in environment variables
    # -------------------------------------------------------------------------
    if echo "$redacted" | grep -qiE '\b(key|token|secret|password|api_key|apikey|auth)=[^[:space:]]+'; then
        redacted=$(echo "$redacted" | sed -E 's/\b([Kk]ey|[Tt]oken|[Ss]ecret|[Pp]assword|[Aa]pi_?[Kk]ey|[Aa]uth)=[^[:space:]]+/\1=[REDACTED]/gi')
        PATTERNS_MATCHED+=("env_var_assignment")
    fi

    # -------------------------------------------------------------------------
    # Home directories - Linux and macOS
    # -------------------------------------------------------------------------
    if echo "$redacted" | grep -qE '/home/[^/]+/'; then
        redacted=$(echo "$redacted" | sed -E 's|/home/[^/]+/|~/|g')
        PATTERNS_MATCHED+=("home_dir_linux")
    fi
    if echo "$redacted" | grep -qE '/Users/[^/]+/'; then
        redacted=$(echo "$redacted" | sed -E 's|/Users/[^/]+/|~/|g')
        PATTERNS_MATCHED+=("home_dir_macos")
    fi

    # Count redactions by comparing lengths (rough estimate)
    local new_length=${#redacted}
    if [[ $original_length -ne $new_length ]]; then
        ((REDACTION_COUNT++))
    fi

    echo "$redacted"
}

# =============================================================================
# Source Collection
# =============================================================================

collect_plan() {
    local plan_file="$GRIMOIRE_PATH/plan.md"
    local content=""
    local size=0
    local truncated="false"

    if [[ -f "$plan_file" ]]; then
        content=$(cat "$plan_file")
        size=${#content}

        # Truncate if too large
        if [[ $size -gt $MAX_PLAN_SIZE ]]; then
            content="${content:0:$MAX_PLAN_SIZE}"
            content="$content\n\n[TRUNCATED: Plan exceeded ${MAX_PLAN_SIZE} bytes]"
            truncated="true"
        fi

        content=$(redact_secrets "$content")
    else
        log_warn "Plan file not found: grimoires/loa/plan.md"
    fi

    if command -v jq &>/dev/null; then
        jq -n \
            --arg path "grimoires/loa/plan.md" \
            --arg content "$content" \
            --argjson size "$size" \
            --argjson truncated "$truncated" \
            '{path: $path, content: $content, size_bytes: $size, truncated: $truncated}'
    else
        echo "{\"path\": \"grimoires/loa/plan.md\", \"content\": \"$content\", \"size_bytes\": $size, \"truncated\": $truncated}"
    fi
}

collect_ledger() {
    local ledger_file="$GRIMOIRE_PATH/ledger.json"
    local content=""
    local size=0

    if [[ -f "$ledger_file" ]]; then
        content=$(cat "$ledger_file")
        size=${#content}
        content=$(redact_secrets "$content")
    else
        log_warn "Ledger file not found: grimoires/loa/ledger.json"
    fi

    if command -v jq &>/dev/null; then
        jq -n \
            --arg path "grimoires/loa/ledger.json" \
            --argjson content "$content" \
            --argjson size "$size" \
            '{path: $path, content: $content, size_bytes: $size}'
    else
        echo "{\"path\": \"grimoires/loa/ledger.json\", \"size_bytes\": $size}"
    fi
}

collect_trajectory() {
    local scope="$1"
    local window_size="$2"
    local trajectory_dir="$GRIMOIRE_PATH/a2a/trajectory"
    local entries=()
    local total_entries=0
    local included_entries=0
    local truncated="false"
    local trajectory_file=""

    # Find most recent trajectory file
    if [[ -d "$trajectory_dir" ]]; then
        trajectory_file=$(find "$trajectory_dir" -name "*.jsonl" -type f 2>/dev/null | sort -r | head -1)
    fi

    if [[ -n "$trajectory_file" && -f "$trajectory_file" ]]; then
        total_entries=$(wc -l < "$trajectory_file" | tr -d ' ')

        case "$scope" in
            execution|full)
                # Get all entries, limited to MAX_TRAJECTORY_ENTRIES
                if [[ $total_entries -gt $MAX_TRAJECTORY_ENTRIES ]]; then
                    entries=$(tail -n "$MAX_TRAJECTORY_ENTRIES" "$trajectory_file")
                    truncated="true"
                    included_entries=$MAX_TRAJECTORY_ENTRIES
                else
                    entries=$(cat "$trajectory_file")
                    included_entries=$total_entries
                fi
                ;;
            failure-window)
                # Get ±window_size entries around the last entry (presumed failure)
                local start_line=$((total_entries - window_size))
                if [[ $start_line -lt 1 ]]; then
                    start_line=1
                fi
                entries=$(sed -n "${start_line},\$p" "$trajectory_file")
                included_entries=$(echo "$entries" | wc -l | tr -d ' ')
                ;;
        esac

        # Redact secrets in entries
        entries=$(redact_secrets "$entries")
    else
        log_warn "No trajectory files found in grimoires/loa/a2a/trajectory/"
    fi

    if command -v jq &>/dev/null; then
        local entries_json="[]"
        if [[ -n "$entries" ]]; then
            # Convert JSONL to JSON array
            entries_json=$(echo "$entries" | jq -s '.' 2>/dev/null || echo "[]")
        fi

        jq -n \
            --arg path "${trajectory_file:-unknown}" \
            --argjson entries "$entries_json" \
            --argjson total "$total_entries" \
            --argjson included "$included_entries" \
            --argjson truncated "$truncated" \
            '{path: $path, entries: $entries, total_entries: $total, included_entries: $included, truncated: $truncated}'
    else
        echo "{\"path\": \"${trajectory_file:-unknown}\", \"total_entries\": $total_entries, \"included_entries\": $included_entries, \"truncated\": $truncated}"
    fi
}

collect_notes() {
    local notes_file="$GRIMOIRE_PATH/NOTES.md"
    local content=""
    local size=0

    if [[ -f "$notes_file" ]]; then
        content=$(cat "$notes_file")
        size=${#content}
        content=$(redact_secrets "$content")
    else
        log_warn "NOTES.md not found: grimoires/loa/NOTES.md"
    fi

    if command -v jq &>/dev/null; then
        jq -n \
            --arg path "grimoires/loa/NOTES.md" \
            --arg content "$content" \
            --argjson size "$size" \
            '{path: $path, content: $content, size_bytes: $size}'
    else
        echo "{\"path\": \"grimoires/loa/NOTES.md\", \"size_bytes\": $size}"
    fi
}

# =============================================================================
# Version Detection
# =============================================================================

get_framework_version() {
    local version_file="$PROJECT_ROOT/.loa-version.json"

    if [[ -f "$version_file" ]] && command -v jq &>/dev/null; then
        jq -r '.version // "unknown"' "$version_file" 2>/dev/null
    else
        echo "unknown"
    fi
}

# =============================================================================
# Main Output Generation
# =============================================================================

generate_output() {
    local scope="$1"
    local window_size="$2"

    local version
    version=$(get_framework_version)
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Collect sources based on scope
    local plan_json
    local ledger_json
    local trajectory_json
    local notes_json=""

    plan_json=$(collect_plan)
    ledger_json=$(collect_ledger)
    trajectory_json=$(collect_trajectory "$scope" "$window_size")

    if [[ "$scope" == "full" ]]; then
        notes_json=$(collect_notes)
    fi

    # Deduplicate patterns matched
    local unique_patterns
    unique_patterns=$(printf '%s\n' "${PATTERNS_MATCHED[@]}" | sort -u | tr '\n' ',' | sed 's/,$//')

    # Generate final JSON
    if command -v jq &>/dev/null; then
        local sources_obj
        sources_obj=$(jq -n \
            --argjson plan "$plan_json" \
            --argjson ledger "$ledger_json" \
            --argjson trajectory "$trajectory_json" \
            '{plan: $plan, ledger: $ledger, trajectory: $trajectory}')

        if [[ -n "$notes_json" ]]; then
            sources_obj=$(echo "$sources_obj" | jq --argjson notes "$notes_json" '. + {notes: $notes}')
        fi

        jq -n \
            --arg version "1.0.0" \
            --arg collected_at "$timestamp" \
            --arg scope "$scope" \
            --arg framework_version "$version" \
            --argjson sources "$sources_obj" \
            --argjson redaction_count "$REDACTION_COUNT" \
            --arg patterns_matched "$unique_patterns" \
            '{
                version: $version,
                collected_at: $collected_at,
                scope: $scope,
                framework_version: $framework_version,
                sources: $sources,
                redactions: {
                    count: $redaction_count,
                    patterns_matched: ($patterns_matched | split(",") | map(select(. != "")))
                }
            }'
    else
        log_warn "jq not available, outputting basic JSON"
        cat << EOF
{
  "version": "1.0.0",
  "collected_at": "$timestamp",
  "scope": "$scope",
  "framework_version": "$version",
  "sources": {},
  "redactions": {"count": $REDACTION_COUNT, "patterns_matched": []}
}
EOF
    fi
}

# =============================================================================
# Main
# =============================================================================

main() {
    local scope="$DEFAULT_SCOPE"
    local window_size="$DEFAULT_FAILURE_WINDOW"
    local output_file=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --scope)
                scope="$2"
                shift 2
                ;;
            --output)
                output_file="$2"
                shift 2
                ;;
            --window-size)
                window_size="$2"
                shift 2
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # Validate scope
    case "$scope" in
        execution|full|failure-window)
            ;;
        *)
            log_error "Invalid scope: $scope"
            log_info "Valid scopes: execution, full, failure-window"
            exit 1
            ;;
    esac

    # Validate window-size is a positive integer (FT-004)
    if ! [[ "$window_size" =~ ^[0-9]+$ ]]; then
        log_error "window-size must be a positive integer, got: $window_size"
        exit 1
    fi
    if [[ "$window_size" -eq 0 ]]; then
        log_error "window-size must be greater than 0"
        exit 1
    fi
    if [[ "$window_size" -gt 1000 ]]; then
        log_warn "window-size capped at 1000 (was: $window_size)"
        window_size=1000
    fi

    # Check if trace collection is enabled
    if ! check_trace_enabled; then
        exit 1
    fi

    # Check for jq (warn but continue)
    if ! command -v jq &>/dev/null; then
        log_warn "jq not installed - output will be limited"
    fi

    # Get configured scope from settings if not specified on command line
    local config_scope
    config_scope=$(get_config_value "traceScope" "$DEFAULT_SCOPE")
    if [[ "$scope" == "$DEFAULT_SCOPE" && "$config_scope" != "$DEFAULT_SCOPE" ]]; then
        scope="$config_scope"
        log_info "Using configured scope: $scope"
    fi

    # Get configured window size
    local config_window
    config_window=$(get_config_value "failureWindowSize" "$DEFAULT_FAILURE_WINDOW")
    if [[ "$window_size" == "$DEFAULT_FAILURE_WINDOW" && "$config_window" != "$DEFAULT_FAILURE_WINDOW" ]]; then
        # Validate config window size
        if [[ "$config_window" =~ ^[0-9]+$ ]] && [[ "$config_window" -gt 0 ]]; then
            window_size="$config_window"
        else
            log_warn "Invalid failureWindowSize in config, using default: $DEFAULT_FAILURE_WINDOW"
        fi
    fi

    log_info "Collecting traces with scope: $scope"

    # Generate output
    local output
    output=$(generate_output "$scope" "$window_size")

    # Output result
    if [[ -n "$output_file" ]]; then
        echo "$output" > "$output_file"
        log_info "Trace written to: $output_file"
    else
        echo "$output"
    fi

    log_info "Collection complete. Redactions: $REDACTION_COUNT"
}

main "$@"
