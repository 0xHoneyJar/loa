#!/usr/bin/env bash
# =============================================================================
# post-retrospective-hook.sh - Post-Retrospective Upstream Detection Hook
# =============================================================================
# Sprint 3, Task T3.1: Scan learnings after retrospective for upstream eligibility
# Goal Contribution: G-5 (Silent detection with opt-in prompt)
#
# This hook runs after /retrospective completes:
#   1. Scans recent learnings (from current session or last N days)
#   2. Evaluates upstream eligibility via upstream-score-calculator.sh
#   3. Filters by thresholds (score ≥70, applications ≥3, success ≥80%)
#   4. Presents candidates to user via stdout (for Claude to show AskUserQuestion)
#   5. Silent if no candidates qualify
#
# Usage:
#   ./post-retrospective-hook.sh
#   ./post-retrospective-hook.sh --days 7
#   ./post-retrospective-hook.sh --session-only
#
# Options:
#   --days N            Check learnings from last N days (default: 1)
#   --session-only      Only check learnings from current session
#   --json              Output as JSON for Claude to process
#   --quiet             Suppress all output if no candidates
#   --force-check       Check all learnings regardless of last_checked
#   --help              Show this help
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_FILE="$PROJECT_ROOT/.loa.config.yaml"

# Dependency scripts
UPSTREAM_SCORE_SCRIPT="$SCRIPT_DIR/upstream-score-calculator.sh"

# Learnings file
PROJECT_LEARNINGS_FILE="$PROJECT_ROOT/grimoires/loa/a2a/compound/learnings.json"

# Defaults (configurable via .loa.config.yaml)
MIN_SCORE=70
MIN_APPLICATIONS=3
MIN_SUCCESS_RATE=80
DAYS_TO_CHECK=1

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

# Parameters
CHECK_DAYS=1
SESSION_ONLY=false
JSON_OUTPUT=false
QUIET=false
FORCE_CHECK=false

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

# Check if upstream detection is enabled
is_detection_enabled() {
    local enabled
    enabled=$(read_config '.upstream_detection.enabled' 'true')
    [[ "$enabled" == "true" ]]
}

# Load configuration
load_config() {
    MIN_SCORE=$(read_config '.upstream_detection.min_upstream_score' '70')
    MIN_APPLICATIONS=$(read_config '.upstream_detection.min_occurrences' '3')
    MIN_SUCCESS_RATE=$(read_config '.upstream_detection.min_success_rate' '0.8')

    # Convert success rate to percentage if it's a decimal
    if [[ "$MIN_SUCCESS_RATE" == "0."* ]]; then
        MIN_SUCCESS_RATE=$(echo "$MIN_SUCCESS_RATE * 100" | bc | cut -d'.' -f1)
    fi
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --days)
                # MEDIUM-004 FIX: Validate numeric input
                if [[ ! "$2" =~ ^[0-9]+$ ]] || [[ "$2" -lt 1 ]] || [[ "$2" -gt 365 ]]; then
                    echo "[ERROR] --days must be a positive integer between 1 and 365" >&2
                    exit 1
                fi
                CHECK_DAYS="$2"
                shift 2
                ;;
            --session-only)
                SESSION_ONLY=true
                shift
                ;;
            --json)
                JSON_OUTPUT=true
                shift
                ;;
            --quiet)
                QUIET=true
                shift
                ;;
            --force-check)
                FORCE_CHECK=true
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

# Get recent learnings based on filters
get_recent_learnings() {
    if [[ ! -f "$PROJECT_LEARNINGS_FILE" ]]; then
        echo ""
        return
    fi

    local cutoff_date
    if [[ "$SESSION_ONLY" == "true" ]]; then
        # Use today's date
        cutoff_date=$(date -u +"%Y-%m-%dT00:00:00Z")
    else
        # Calculate cutoff date
        if [[ "$(uname)" == "Darwin" ]]; then
            cutoff_date=$(date -v-"${CHECK_DAYS}d" -u +"%Y-%m-%dT00:00:00Z")
        else
            cutoff_date=$(date -u -d "-${CHECK_DAYS} days" +"%Y-%m-%dT00:00:00Z")
        fi
    fi

    # Filter learnings by:
    # 1. Created after cutoff date OR has applications after cutoff
    # 2. No existing proposal status (or rejected with cooldown expired)
    # 3. Hasn't been checked recently (unless force)
    jq -r --arg cutoff "$cutoff_date" --argjson force "$([[ "$FORCE_CHECK" == "true" ]] && echo true || echo false)" '
        .learnings[] |
        select(
            # Check creation date or recent applications
            ((.created // "1970-01-01T00:00:00Z") >= $cutoff) or
            ((.applications // []) | map(select(.timestamp >= $cutoff)) | length > 0)
        ) |
        select(
            # No proposal or rejected with expired cooldown
            (.proposal.status == null) or
            (.proposal.status == "none") or
            (.proposal.status == "rejected" and (
                (.proposal.rejection.resubmit_blocked_until // "1970-01-01T00:00:00Z") < (now | strftime("%Y-%m-%dT%H:%M:%SZ"))
            ))
        ) |
        .id
    ' "$PROJECT_LEARNINGS_FILE" 2>/dev/null || echo ""
}

# Evaluate a single learning for eligibility
evaluate_learning() {
    local learning_id="$1"

    if [[ ! -x "$UPSTREAM_SCORE_SCRIPT" ]]; then
        echo '{"id":"'"$learning_id"'","eligible":false,"error":"calculator_not_found"}'
        return
    fi

    local result
    result=$("$UPSTREAM_SCORE_SCRIPT" --learning "$learning_id" --format json 2>/dev/null || echo '{"error":"calculation_failed"}')

    # Add learning title to result
    local title
    title=$(jq -r --arg id "$learning_id" '.learnings[] | select(.id == $id) | .title // "Untitled"' "$PROJECT_LEARNINGS_FILE" 2>/dev/null || echo "Untitled")

    echo "$result" | jq --arg title "$title" '. + {title: $title}'
}

# Format candidate for display
format_candidate() {
    local candidate="$1"

    local id title score
    id=$(echo "$candidate" | jq -r '.id')
    title=$(echo "$candidate" | jq -r '.title')
    score=$(echo "$candidate" | jq -r '.upstream_score')

    echo -e "  • ${BLUE}$id${NC}: $title"
    echo -e "    Score: ${GREEN}$score${NC}/100"
}

main() {
    parse_args "$@"

    # Check if detection is enabled
    if ! is_detection_enabled; then
        if [[ "$QUIET" != "true" && "$JSON_OUTPUT" != "true" ]]; then
            echo "[INFO] Upstream detection disabled in config" >&2
        fi
        exit 0
    fi

    load_config

    # Get recent learnings
    local learnings
    learnings=$(get_recent_learnings)

    if [[ -z "$learnings" ]]; then
        if [[ "$JSON_OUTPUT" == "true" ]]; then
            echo '{"candidates":[],"message":"no_recent_learnings"}'
        elif [[ "$QUIET" != "true" ]]; then
            echo "[INFO] No recent learnings to evaluate" >&2
        fi
        exit 0
    fi

    # Evaluate each learning
    local candidates=()
    local evaluated=0

    while IFS= read -r id; do
        [[ -z "$id" ]] && continue

        local result
        result=$(evaluate_learning "$id")

        local eligible
        eligible=$(echo "$result" | jq -r '.eligibility.eligible // false')

        if [[ "$eligible" == "true" ]]; then
            candidates+=("$result")
        fi

        ((evaluated++)) || true
    done <<< "$learnings"

    # Output results
    if [[ ${#candidates[@]} -eq 0 ]]; then
        if [[ "$JSON_OUTPUT" == "true" ]]; then
            echo '{"candidates":[],"evaluated":'"$evaluated"',"message":"no_eligible_candidates"}'
        elif [[ "$QUIET" != "true" ]]; then
            echo "[INFO] No learnings meet upstream eligibility criteria" >&2
        fi
        exit 0
    fi

    # Format output
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        printf '%s\n' "${candidates[@]}" | jq -s '{
            candidates: .,
            evaluated: '"$evaluated"',
            count: length,
            thresholds: {
                min_score: '"$MIN_SCORE"',
                min_applications: '"$MIN_APPLICATIONS"',
                min_success_rate: '"$MIN_SUCCESS_RATE"'
            }
        }'
    else
        echo ""
        echo -e "${BOLD}${CYAN}Upstream Learning Candidates Detected${NC}"
        echo "─────────────────────────────────────────"
        echo ""
        echo -e "The following learnings qualify for upstream proposal:"
        echo ""

        for candidate in "${candidates[@]}"; do
            format_candidate "$candidate"
            echo ""
        done

        echo "─────────────────────────────────────────"
        echo ""
        echo -e "To propose a learning, run:"
        echo -e "  ${GREEN}/propose-learning <learning-id>${NC}"
        echo ""
        echo -e "To preview first:"
        echo -e "  ${GREEN}/propose-learning <learning-id> --dry-run${NC}"
        echo ""
    fi
}

main "$@"
