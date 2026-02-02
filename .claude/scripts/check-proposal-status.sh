#!/usr/bin/env bash
# =============================================================================
# check-proposal-status.sh - Check and Sync Proposal Status from GitHub
# =============================================================================
# Sprint 2, Task T2.4: Check proposal status updates from GitHub Issues
# Goal Contribution: G-6 (Maintainer workflow with rejection tracking)
#
# Syncs proposal status from GitHub Issues back to local learnings:
#   1. Fetches Issue status from GitHub API
#   2. Detects state changes (open → closed, labels added)
#   3. Updates local learning proposal status
#   4. Handles rejection with 90-day cooldown
#
# Usage:
#   ./check-proposal-status.sh --learning <ID>
#   ./check-proposal-status.sh --all
#   ./check-proposal-status.sh --learning <ID> --sync
#
# Options:
#   --learning ID     Check specific learning's proposal status
#   --all             Check all learnings with submitted proposals
#   --sync            Sync status back to learnings.json
#   --json            Output as JSON
#   --help            Show this help
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_FILE="$PROJECT_ROOT/.loa.config.yaml"

# Learnings file
PROJECT_LEARNINGS_FILE="$PROJECT_ROOT/grimoires/loa/a2a/compound/learnings.json"

# Defaults (configurable via .loa.config.yaml)
TARGET_REPO="0xHoneyJar/loa"
REJECTION_COOLDOWN_DAYS=90

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

# Parameters
LEARNING_ID=""
CHECK_ALL=false
SYNC=false
JSON_OUTPUT=false

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

# Load configuration
load_config() {
    TARGET_REPO=$(read_config '.upstream_proposals.target_repo' '0xHoneyJar/loa')
    REJECTION_COOLDOWN_DAYS=$(read_config '.upstream_proposals.rejection_cooldown_days' '90')
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --learning)
                LEARNING_ID="$2"
                shift 2
                ;;
            --all)
                CHECK_ALL=true
                shift
                ;;
            --sync)
                SYNC=true
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

    if [[ -z "$LEARNING_ID" && "$CHECK_ALL" != "true" ]]; then
        echo "[ERROR] Either --learning ID or --all is required" >&2
        exit 1
    fi

    # MEDIUM-001 FIX: Validate learning ID format (alphanumeric, hyphens, underscores)
    if [[ -n "$LEARNING_ID" && ! "$LEARNING_ID" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo "[ERROR] Invalid learning ID format: must be alphanumeric with hyphens/underscores only" >&2
        exit 1
    fi
}

# Check gh CLI availability and auth
check_gh_auth() {
    if ! command -v gh &> /dev/null; then
        echo "[ERROR] GitHub CLI (gh) not found" >&2
        return 1
    fi

    if ! gh auth status &> /dev/null; then
        echo "[ERROR] GitHub CLI not authenticated" >&2
        return 1
    fi

    return 0
}

# Get learning from project learnings file
get_learning() {
    local id="$1"

    if [[ ! -f "$PROJECT_LEARNINGS_FILE" ]]; then
        echo ""
        return 1
    fi

    jq --arg id "$id" '.learnings[] | select(.id == $id)' "$PROJECT_LEARNINGS_FILE" 2>/dev/null || echo ""
}

# Get all learnings with submitted proposals
get_submitted_learnings() {
    if [[ ! -f "$PROJECT_LEARNINGS_FILE" ]]; then
        echo ""
        return 1
    fi

    jq -r '.learnings[] | select(.proposal.status == "submitted" or .proposal.status == "under_review") | .id' "$PROJECT_LEARNINGS_FILE" 2>/dev/null || echo ""
}

# Extract issue number from reference
extract_issue_number() {
    local ref="$1"

    # Handle formats: #123 or owner/repo#123
    echo "$ref" | grep -oE '[0-9]+' | tail -1
}

# Fetch Issue status from GitHub
fetch_issue_status() {
    local issue_num="$1"

    if [[ -z "$issue_num" ]]; then
        echo '{"error":"no_issue_ref"}'
        return 1
    fi

    # Fetch issue details via gh CLI
    local result
    result=$(gh issue view "$issue_num" --repo "$TARGET_REPO" --json state,labels,closedAt,title 2>/dev/null || echo '{"error":"not_found"}')

    echo "$result"
}

# Determine new status from Issue state and labels
determine_new_status() {
    local issue_data="$1"

    local state labels
    state=$(echo "$issue_data" | jq -r '.state // "unknown"')
    labels=$(echo "$issue_data" | jq -r '.labels // [] | .[].name' 2>/dev/null || echo "")

    # Check for error
    if echo "$issue_data" | jq -e '.error' &>/dev/null; then
        echo "error"
        return
    fi

    # Check state
    case "$state" in
        "OPEN")
            # Check labels for review status
            if echo "$labels" | grep -qi "under-review\|reviewing"; then
                echo "under_review"
            else
                echo "submitted"
            fi
            ;;
        "CLOSED")
            # Check if accepted or rejected
            if echo "$labels" | grep -qi "accepted\|merged\|approved"; then
                echo "accepted"
            elif echo "$labels" | grep -qi "rejected\|declined\|wontfix\|won't fix"; then
                echo "rejected"
            else
                # Default closed without explicit label = accepted
                echo "accepted"
            fi
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# Extract rejection reason from Issue
extract_rejection_reason() {
    local issue_num="$1"

    # Try to get closing comment
    local comments
    comments=$(gh issue view "$issue_num" --repo "$TARGET_REPO" --json comments --jq '.comments[-1].body // ""' 2>/dev/null || echo "")

    if [[ -n "$comments" ]]; then
        # Truncate to 500 chars
        echo "${comments:0:500}"
    else
        echo "No specific reason provided"
    fi
}

# Determine rejection reason code from labels/text
determine_rejection_code() {
    local issue_data="$1"
    local reason="$2"

    local labels
    labels=$(echo "$issue_data" | jq -r '.labels // [] | .[].name' 2>/dev/null | tr '[:upper:]' '[:lower:]' || echo "")

    # Check labels first
    if echo "$labels" | grep -q "duplicate"; then
        echo "duplicate"
    elif echo "$labels" | grep -q "too-specific\|project-specific"; then
        echo "too_specific"
    elif echo "$labels" | grep -q "insufficient-evidence\|needs-evidence"; then
        echo "insufficient_evidence"
    elif echo "$labels" | grep -q "low-quality\|needs-improvement"; then
        echo "low_quality"
    elif echo "$labels" | grep -q "out-of-scope\|wontfix"; then
        echo "out_of_scope"
    else
        # Try to infer from reason text
        local reason_lower
        reason_lower=$(echo "$reason" | tr '[:upper:]' '[:lower:]')

        if echo "$reason_lower" | grep -q "duplicate\|already exists"; then
            echo "duplicate"
        elif echo "$reason_lower" | grep -q "specific\|project-specific"; then
            echo "too_specific"
        elif echo "$reason_lower" | grep -q "evidence\|more data"; then
            echo "insufficient_evidence"
        elif echo "$reason_lower" | grep -q "quality\|improve"; then
            echo "low_quality"
        else
            echo "other"
        fi
    fi
}

# Calculate cooldown end date
calculate_cooldown_end() {
    local days="$1"

    # Calculate date N days from now
    if [[ "$(uname)" == "Darwin" ]]; then
        date -v+"${days}d" -u +"%Y-%m-%dT%H:%M:%SZ"
    else
        date -u -d "+${days} days" +"%Y-%m-%dT%H:%M:%SZ"
    fi
}

# Update learning proposal status
update_learning_status() {
    local learning_id="$1"
    local new_status="$2"
    local issue_data="$3"

    if [[ ! -f "$PROJECT_LEARNINGS_FILE" ]]; then
        return 1
    fi

    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Create temp file with restrictive permissions
    local temp_file
    temp_file=$(mktemp)
    chmod 600 "$temp_file"

    if [[ "$new_status" == "rejected" ]]; then
        # Get rejection details
        local issue_num
        issue_num=$(jq -r --arg id "$learning_id" '.learnings[] | select(.id == $id) | .proposal.issue_ref // ""' "$PROJECT_LEARNINGS_FILE")
        issue_num=$(extract_issue_number "$issue_num")

        local reason reason_code cooldown_end
        reason=$(extract_rejection_reason "$issue_num")
        reason_code=$(determine_rejection_code "$issue_data" "$reason")
        cooldown_end=$(calculate_cooldown_end "$REJECTION_COOLDOWN_DAYS")

        jq --arg id "$learning_id" \
           --arg status "$new_status" \
           --arg timestamp "$timestamp" \
           --arg reason "$reason" \
           --arg reason_code "$reason_code" \
           --arg cooldown_end "$cooldown_end" \
           '(.learnings[] | select(.id == $id)) |= . + {
               proposal: (.proposal + {
                   status: $status,
                   reviewed_at: $timestamp,
                   rejection: {
                       reason: $reason,
                       reason_code: $reason_code,
                       resubmit_blocked_until: $cooldown_end,
                       can_appeal: true
                   }
               })
           }' "$PROJECT_LEARNINGS_FILE" > "$temp_file"
    else
        jq --arg id "$learning_id" \
           --arg status "$new_status" \
           --arg timestamp "$timestamp" \
           '(.learnings[] | select(.id == $id)) |= . + {
               proposal: (.proposal + {
                   status: $status,
                   reviewed_at: $timestamp
               })
           }' "$PROJECT_LEARNINGS_FILE" > "$temp_file"
    fi

    mv "$temp_file" "$PROJECT_LEARNINGS_FILE"
}

# Check single learning's proposal status
check_learning_status() {
    local learning_id="$1"

    local learning
    learning=$(get_learning "$learning_id")

    if [[ -z "$learning" || "$learning" == "null" ]]; then
        if [[ "$JSON_OUTPUT" == "true" ]]; then
            echo '{"id":"'"$learning_id"'","error":"not_found"}'
        else
            echo -e "${RED}Learning not found: $learning_id${NC}" >&2
        fi
        return 1
    fi

    # Get proposal info
    local current_status issue_ref
    current_status=$(echo "$learning" | jq -r '.proposal.status // "none"')
    issue_ref=$(echo "$learning" | jq -r '.proposal.issue_ref // ""')

    if [[ "$current_status" == "none" || -z "$issue_ref" ]]; then
        if [[ "$JSON_OUTPUT" == "true" ]]; then
            echo '{"id":"'"$learning_id"'","current_status":"'"$current_status"'","error":"no_proposal"}'
        else
            echo -e "  ${YELLOW}No proposal found for $learning_id${NC}"
        fi
        return 0
    fi

    # Extract issue number and fetch status
    local issue_num
    issue_num=$(extract_issue_number "$issue_ref")

    local issue_data
    issue_data=$(fetch_issue_status "$issue_num")

    # Determine new status
    local new_status
    new_status=$(determine_new_status "$issue_data")

    local title
    title=$(echo "$learning" | jq -r '.title // "Untitled"')

    if [[ "$JSON_OUTPUT" == "true" ]]; then
        local status_changed="false"
        [[ "$new_status" != "$current_status" ]] && status_changed="true"

        jq -n \
            --arg id "$learning_id" \
            --arg title "$title" \
            --arg issue_ref "$issue_ref" \
            --arg current_status "$current_status" \
            --arg new_status "$new_status" \
            --argjson changed "$status_changed" \
            --argjson issue_data "$issue_data" \
            '{
                id: $id,
                title: $title,
                issue_ref: $issue_ref,
                current_status: $current_status,
                github_status: $new_status,
                status_changed: $changed,
                issue: $issue_data
            }'
    else
        echo -e "  Learning: ${BLUE}$learning_id${NC}"
        echo -e "  Title: $title"
        echo -e "  Issue: ${CYAN}$issue_ref${NC}"
        echo -e "  Current Status: $current_status"
        echo -e "  GitHub Status: $new_status"

        if [[ "$new_status" != "$current_status" ]]; then
            echo -e "  ${YELLOW}⚡ Status changed: $current_status → $new_status${NC}"
        else
            echo -e "  ${GREEN}✓ Status unchanged${NC}"
        fi
    fi

    # Sync if requested and status changed
    if [[ "$SYNC" == "true" && "$new_status" != "$current_status" && "$new_status" != "error" && "$new_status" != "unknown" ]]; then
        update_learning_status "$learning_id" "$new_status" "$issue_data"

        if [[ "$JSON_OUTPUT" != "true" ]]; then
            echo -e "  ${GREEN}✓ Synced to learnings.json${NC}"
        fi
    fi

    echo ""
}

main() {
    parse_args "$@"
    load_config

    # Check gh auth
    check_gh_auth || exit 1

    if [[ "$JSON_OUTPUT" != "true" ]]; then
        echo -e "${BOLD}${CYAN}Proposal Status Checker${NC}"
        echo "─────────────────────────────────────────"
        echo ""
    fi

    if [[ "$CHECK_ALL" == "true" ]]; then
        # Check all submitted learnings
        local learnings
        learnings=$(get_submitted_learnings)

        if [[ -z "$learnings" ]]; then
            if [[ "$JSON_OUTPUT" == "true" ]]; then
                echo '{"message":"no_submitted_proposals","count":0}'
            else
                echo -e "${YELLOW}No submitted proposals found${NC}"
            fi
            exit 0
        fi

        local results=()
        while IFS= read -r id; do
            [[ -z "$id" ]] && continue

            if [[ "$JSON_OUTPUT" == "true" ]]; then
                results+=("$(check_learning_status "$id")")
            else
                check_learning_status "$id"
            fi
        done <<< "$learnings"

        if [[ "$JSON_OUTPUT" == "true" ]]; then
            printf '%s\n' "${results[@]}" | jq -s '.'
        fi
    else
        # Check single learning
        check_learning_status "$LEARNING_ID"
    fi

    if [[ "$JSON_OUTPUT" != "true" ]]; then
        echo "─────────────────────────────────────────"
        if [[ "$SYNC" == "true" ]]; then
            echo -e "${GREEN}Sync complete${NC}"
        else
            echo -e "Use --sync to update learnings.json"
        fi
    fi
}

main "$@"
