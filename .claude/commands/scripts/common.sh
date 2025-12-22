#!/bin/bash
# common.sh - Common validation functions for Loa commands
# Source this file in command-specific validation scripts

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Print error message and exit
error() {
    echo -e "${RED}ERROR:${NC} $1" >&2
    exit 1
}

# Print warning message
warn() {
    echo -e "${YELLOW}WARNING:${NC} $1" >&2
}

# Print success message
success() {
    echo -e "${GREEN}OK:${NC} $1"
}

# Validate sprint ID format (sprint-N where N is positive integer)
validate_sprint_id() {
    local sprint_id="$1"
    if [[ ! "$sprint_id" =~ ^sprint-[0-9]+$ ]]; then
        error "Invalid sprint ID '$sprint_id'. Expected format: sprint-N (e.g., sprint-1, sprint-2)"
    fi
}

# Check if a file exists
check_file_exists() {
    local file="$1"
    local error_msg="${2:-Required file not found: $file}"
    if [ ! -f "$file" ]; then
        error "$error_msg"
    fi
}

# Check if a directory exists
check_dir_exists() {
    local dir="$1"
    local error_msg="${2:-Required directory not found: $dir}"
    if [ ! -d "$dir" ]; then
        error "$error_msg"
    fi
}

# Check if setup has been completed
check_setup_complete() {
    if [ ! -f ".loa-setup-complete" ]; then
        error "Loa setup has not been completed. Run /setup first."
    fi
}

# Get user type from setup marker
get_user_type() {
    if [ -f ".loa-setup-complete" ]; then
        grep -o '"user_type": *"[^"]*"' .loa-setup-complete 2>/dev/null | cut -d'"' -f4 || echo "unknown"
    else
        echo "unknown"
    fi
}

# Check if user is THJ developer
is_thj_user() {
    [ "$(get_user_type)" = "thj" ]
}

# Check if sprint exists in sprint.md
check_sprint_in_plan() {
    local sprint_id="$1"
    local sprint_file="loa-grimoire/sprint.md"

    check_file_exists "$sprint_file" "Sprint plan not found. Run /sprint-plan first."

    # Extract sprint number
    local sprint_num="${sprint_id#sprint-}"

    # Check for sprint section (various formats)
    if ! grep -qE "## ?$sprint_id|## ?Sprint $sprint_num|# ?$sprint_id|# ?Sprint $sprint_num" "$sprint_file"; then
        error "Sprint $sprint_id not found in $sprint_file"
    fi
}

# Check if sprint is already completed
check_sprint_not_completed() {
    local sprint_id="$1"
    local completed_marker="loa-grimoire/a2a/$sprint_id/COMPLETED"

    if [ -f "$completed_marker" ]; then
        error "Sprint $sprint_id is already COMPLETED. See $completed_marker for details."
    fi
}

# Check if senior lead has approved the sprint
check_senior_approval() {
    local sprint_id="$1"
    local feedback_file="loa-grimoire/a2a/$sprint_id/engineer-feedback.md"

    if [ ! -f "$feedback_file" ]; then
        error "Sprint $sprint_id has not been reviewed yet. Run /review-sprint $sprint_id first."
    fi

    if ! grep -q "All good" "$feedback_file"; then
        error "Sprint $sprint_id has not been approved by senior lead. Run /review-sprint $sprint_id first."
    fi
}

# Check if reviewer.md exists for a sprint
check_reviewer_report() {
    local sprint_id="$1"
    local report_file="loa-grimoire/a2a/$sprint_id/reviewer.md"

    check_file_exists "$report_file" "No implementation report found at $report_file. Run /implement $sprint_id first."
}

# Check if sprint directory exists
check_sprint_dir() {
    local sprint_id="$1"
    local sprint_dir="loa-grimoire/a2a/$sprint_id"

    check_dir_exists "$sprint_dir" "Sprint directory $sprint_dir not found. Run /implement $sprint_id first."
}

# Check prerequisites for implementation phase
check_implement_prerequisites() {
    check_file_exists "loa-grimoire/prd.md" "PRD not found. Run /plan-and-analyze first."
    check_file_exists "loa-grimoire/sdd.md" "SDD not found. Run /architect first."
    check_file_exists "loa-grimoire/sprint.md" "Sprint plan not found. Run /sprint-plan first."
}

# Check prerequisites for review phase
check_review_prerequisites() {
    local sprint_id="$1"
    check_implement_prerequisites
    check_sprint_dir "$sprint_id"
    check_reviewer_report "$sprint_id"
}

# Check prerequisites for audit phase
check_audit_prerequisites() {
    local sprint_id="$1"
    check_review_prerequisites "$sprint_id"
    check_senior_approval "$sprint_id"
}
