#!/usr/bin/env bash
# =============================================================================
# guardrails-orchestrator.sh - Coordinate all guardrail checks
# =============================================================================
# Version: 1.0.0
# Part of: Input Guardrails & Tool Risk Enforcement v1.20.0
#
# Usage:
#   guardrails-orchestrator.sh --skill implementing-tasks --input "Implement feature X"
#   guardrails-orchestrator.sh --skill deploying-infrastructure --input "Deploy to prod" --mode autonomous
#   guardrails-orchestrator.sh --skill implementing-tasks --file input.txt --allow-high
#
# Output: JSON with final action and all check results
# =============================================================================

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_NAME="$(basename "$0")"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly CONFIG_FILE="$PROJECT_ROOT/.loa.config.yaml"

# Source cross-platform time utilities
# shellcheck source=time-lib.sh
source "$SCRIPT_DIR/time-lib.sh"

# Scripts
readonly PII_FILTER="$SCRIPT_DIR/pii-filter.sh"
readonly INJECTION_DETECT="$SCRIPT_DIR/injection-detect.sh"
readonly DANGER_LEVEL="$SCRIPT_DIR/danger-level-enforcer.sh"
readonly GUARDRAIL_LOGGER="$SCRIPT_DIR/guardrail-logger.sh"

# Defaults
DEFAULT_MODE="interactive"

# =============================================================================
# Functions
# =============================================================================

show_help() {
    cat <<EOF
Usage: $SCRIPT_NAME [OPTIONS]

Orchestrate all guardrail checks for a skill invocation.

Required Options:
  --skill NAME      Skill identifier
  --input TEXT      Input text to validate (or use --file)
  --file PATH       Read input from file

Optional:
  --mode MODE       Execution mode: interactive (default) or autonomous
  --allow-high      Allow high-risk skills in autonomous mode
  --session-id ID   Session ID for trajectory correlation
  --no-log          Skip trajectory logging
  --parallel NAME   Run specific check in parallel mode
  -h, --help        Show this help message

Guardrail Checks (in order):
  1. danger_level    - Check skill risk level against mode
  2. pii_filter      - Detect and redact sensitive data (blocking)
  3. injection       - Detect prompt injection patterns (blocking)

Output (JSON):
  {
    "action": "PROCEED|WARN|BLOCK",
    "skill": "skill-name",
    "mode": "interactive|autonomous",
    "checks": [...],
    "redacted_input": "sanitized text",
    "latency_ms": N
  }

Examples:
  $SCRIPT_NAME --skill implementing-tasks --input "Implement feature X"
  $SCRIPT_NAME --skill deploying-infrastructure --input "Deploy" --mode autonomous
  $SCRIPT_NAME --skill implementing-tasks --file task.txt --allow-high
EOF
}

# Read config value with default
get_config() {
    local key="$1"
    local default="$2"

    if [[ -f "$CONFIG_FILE" ]]; then
        local value
        value=$(yq -r "$key // \"$default\"" "$CONFIG_FILE" 2>/dev/null || echo "$default")
        if [[ "$value" == "null" ]]; then
            echo "$default"
        else
            echo "$value"
        fi
    else
        echo "$default"
    fi
}

# Check if guardrails are enabled
is_enabled() {
    local enabled
    enabled=$(get_config ".guardrails.input.enabled" "true")
    [[ "$enabled" == "true" ]]
}

# Check if specific guardrail is enabled
is_check_enabled() {
    local check="$1"
    local enabled
    enabled=$(get_config ".guardrails.input.${check}.enabled" "true")
    [[ "$enabled" == "true" ]]
}

# Get check mode (blocking/parallel/advisory)
get_check_mode() {
    local check="$1"
    get_config ".guardrails.input.${check}.mode" "blocking"
}

# Get injection threshold
get_injection_threshold() {
    get_config ".guardrails.input.injection_detection.threshold" "0.7"
}

# Run PII filter
run_pii_filter() {
    local input="$1"

    if ! is_check_enabled "pii_filter"; then
        echo '{"name":"pii_filter","status":"SKIP","mode":"disabled"}'
        return
    fi

    local mode
    mode=$(get_check_mode "pii_filter")

    local result
    result=$(echo "$input" | "$PII_FILTER" 2>/dev/null || echo '{"status":"ERROR","redactions":0}')

    local status
    status=$(echo "$result" | jq -r '.status')
    local redactions
    redactions=$(echo "$result" | jq -r '.redactions')
    local latency
    latency=$(echo "$result" | jq -r '.latency_ms')

    # Map WARN -> PASS (PII filter redacts but allows)
    if [[ "$status" == "WARN" ]]; then
        status="PASS"
    fi

    cat <<EOF
{
  "name": "pii_filter",
  "status": "$status",
  "mode": "$mode",
  "redactions": $redactions,
  "latency_ms": $latency
}
EOF
}

# Run injection detection
run_injection_detection() {
    local input="$1"

    if ! is_check_enabled "injection_detection"; then
        echo '{"name":"injection_detection","status":"SKIP","mode":"disabled"}'
        return
    fi

    local mode
    mode=$(get_check_mode "injection_detection")
    local threshold
    threshold=$(get_injection_threshold)

    local result
    result=$("$INJECTION_DETECT" --input "$input" --threshold "$threshold" 2>/dev/null || echo '{"status":"ERROR","score":0}')

    local status
    status=$(echo "$result" | jq -r '.status')
    local score
    score=$(echo "$result" | jq -r '.score')
    local patterns
    patterns=$(echo "$result" | jq -c '.patterns_matched')
    local latency
    latency=$(echo "$result" | jq -r '.latency_ms')

    # Map DETECTED -> FAIL for blocking mode
    if [[ "$status" == "DETECTED" && "$mode" == "blocking" ]]; then
        status="FAIL"
    fi

    cat <<EOF
{
  "name": "injection_detection",
  "status": "$status",
  "mode": "$mode",
  "score": $score,
  "threshold": $threshold,
  "patterns_matched": $patterns,
  "latency_ms": $latency
}
EOF
}

# Run danger level check
run_danger_level() {
    local skill="$1"
    local mode="$2"
    local allow_high="$3"

    local args=("--skill" "$skill" "--mode" "$mode")
    if [[ "$allow_high" == "true" ]]; then
        args+=("--allow-high")
    fi

    local result
    result=$("$DANGER_LEVEL" "${args[@]}" 2>/dev/null || echo '{"action":"BLOCK","reason":"error"}')

    local action
    action=$(echo "$result" | jq -r '.action')
    local level
    level=$(echo "$result" | jq -r '.level')
    local reason
    reason=$(echo "$result" | jq -r '.reason')

    # Map to status
    local status="PASS"
    if [[ "$action" == "BLOCK" ]]; then
        status="FAIL"
    elif [[ "$action" == "WARN" ]]; then
        status="WARN"
    fi

    cat <<EOF
{
  "name": "danger_level",
  "status": "$status",
  "level": "$level",
  "mode": "$mode",
  "reason": "$reason"
}
EOF
}

# Determine final action from all checks
determine_final_action() {
    local checks="$1"

    # Check for any FAIL status
    local has_fail
    has_fail=$(echo "$checks" | jq '[.[] | select(.status == "FAIL")] | length')
    if [[ "$has_fail" -gt 0 ]]; then
        echo "BLOCK"
        return
    fi

    # Check for any WARN status
    local has_warn
    has_warn=$(echo "$checks" | jq '[.[] | select(.status == "WARN")] | length')
    if [[ "$has_warn" -gt 0 ]]; then
        echo "WARN"
        return
    fi

    echo "PROCEED"
}

# Get blocking reason from failed checks
get_block_reason() {
    local checks="$1"

    local failed
    failed=$(echo "$checks" | jq -r '[.[] | select(.status == "FAIL")] | .[0].name // "unknown"')

    case "$failed" in
        danger_level)
            echo "$checks" | jq -r '[.[] | select(.name == "danger_level")] | .[0].reason'
            ;;
        injection_detection)
            echo "Prompt injection detected"
            ;;
        pii_filter)
            echo "PII filter blocked input"
            ;;
        *)
            echo "Guardrail check failed"
            ;;
    esac
}

# =============================================================================
# Main
# =============================================================================

main() {
    local skill=""
    local input=""
    local mode="$DEFAULT_MODE"
    local allow_high="false"
    local session_id="${CLAUDE_SESSION_ID:-}"
    local do_log="true"
    local start_time

    start_time=$(get_timestamp_ms)

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --skill)
                skill="$2"
                shift 2
                ;;
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
            --allow-high)
                allow_high="true"
                shift
                ;;
            --session-id)
                session_id="$2"
                shift 2
                ;;
            --no-log)
                do_log="false"
                shift
                ;;
            --parallel)
                # For future parallel mode support
                shift 2
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

    # Validate required arguments
    if [[ -z "$skill" ]]; then
        echo "Error: --skill is required" >&2
        exit 1
    fi

    if [[ -z "$input" ]]; then
        echo "Error: --input or --file is required" >&2
        exit 1
    fi

    # Check if guardrails are enabled
    if ! is_enabled; then
        cat <<EOF
{
  "action": "PROCEED",
  "skill": "$skill",
  "mode": "$mode",
  "checks": [],
  "reason": "guardrails disabled in config",
  "latency_ms": 0
}
EOF
        exit 0
    fi

    # Run all checks
    local checks=()
    local redacted_input="$input"

    # 1. Danger level check
    local danger_result
    danger_result=$(run_danger_level "$skill" "$mode" "$allow_high")
    checks+=("$danger_result")

    # Check if danger level blocked
    local danger_status
    danger_status=$(echo "$danger_result" | jq -r '.status')
    if [[ "$danger_status" == "FAIL" ]]; then
        local reason
        reason=$(echo "$danger_result" | jq -r '.reason')

        local end_time
        end_time=$(get_timestamp_ms)
        local latency_ms=$((end_time - start_time))
        [[ $latency_ms -lt 0 ]] && latency_ms=0

        # Log if enabled
        if [[ "$do_log" == "true" ]]; then
            "$GUARDRAIL_LOGGER" --type input_guardrail --skill "$skill" --action BLOCK \
                --checks "[$(echo "$danger_result" | jq -c .)]" \
                --session-id "$session_id" --latency-ms "$latency_ms" --quiet 2>/dev/null || true
        fi

        cat <<EOF
{
  "action": "BLOCK",
  "skill": "$skill",
  "mode": "$mode",
  "checks": [$(echo "$danger_result" | jq -c .)],
  "reason": "$reason",
  "latency_ms": $latency_ms
}
EOF
        exit 0
    fi

    # 2. PII filter
    local pii_result
    pii_result=$(run_pii_filter "$input")
    checks+=("$pii_result")

    # Get redacted input from PII filter
    local pii_redactions
    pii_redactions=$(echo "$pii_result" | jq -r '.redactions // 0')
    if [[ "$pii_redactions" -gt 0 ]]; then
        redacted_input=$(echo "$input" | "$PII_FILTER" --quiet 2>/dev/null || echo "$input")
    fi

    # 3. Injection detection (on redacted input)
    local injection_result
    injection_result=$(run_injection_detection "$redacted_input")
    checks+=("$injection_result")

    # Build checks array
    local checks_json="["
    local first=true
    for check in "${checks[@]}"; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            checks_json+=","
        fi
        checks_json+=$(echo "$check" | jq -c .)
    done
    checks_json+="]"

    # Determine final action
    local action
    action=$(determine_final_action "$checks_json")

    local reason=""
    if [[ "$action" == "BLOCK" ]]; then
        reason=$(get_block_reason "$checks_json")
    fi

    local end_time
    end_time=$(get_timestamp_ms)
    local latency_ms=$((end_time - start_time))
    [[ $latency_ms -lt 0 ]] && latency_ms=0

    # Log if enabled
    if [[ "$do_log" == "true" ]]; then
        local input_size=${#input}
        "$GUARDRAIL_LOGGER" --type input_guardrail --skill "$skill" --action "$action" \
            --checks "$checks_json" --input-size "$input_size" \
            --session-id "$session_id" --latency-ms "$latency_ms" --quiet 2>/dev/null || true
    fi

    # Build output
    local output
    if [[ -n "$reason" ]]; then
        output=$(cat <<EOF
{
  "action": "$action",
  "skill": "$skill",
  "mode": "$mode",
  "checks": $checks_json,
  "reason": "$reason",
  "latency_ms": $latency_ms
}
EOF
)
    else
        local redacted_escaped
        redacted_escaped=$(echo "$redacted_input" | jq -Rs .)
        output=$(cat <<EOF
{
  "action": "$action",
  "skill": "$skill",
  "mode": "$mode",
  "checks": $checks_json,
  "redacted_input": $redacted_escaped,
  "latency_ms": $latency_ms
}
EOF
)
    fi

    echo "$output" | jq .
}

main "$@"
