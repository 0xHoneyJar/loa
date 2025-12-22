#!/bin/bash
# Pre-flight check functions for command validation
# Used to validate prerequisites before command execution

# Check if a file exists
check_file_exists() {
    local path="$1"
    [ -f "$path" ]
}

# Check if a file does NOT exist
check_file_not_exists() {
    local path="$1"
    [ ! -f "$path" ]
}

# Check if a directory exists
check_directory_exists() {
    local path="$1"
    [ -d "$path" ]
}

# Check if file contains a pattern
check_content_contains() {
    local path="$1"
    local pattern="$2"
    grep -qE "$pattern" "$path" 2>/dev/null
}

# Check if value matches a pattern
check_pattern_match() {
    local value="$1"
    local pattern="$2"
    echo "$value" | grep -qE "$pattern"
}

# Check if a command succeeds
check_command_succeeds() {
    local cmd="$1"
    eval "$cmd" >/dev/null 2>&1
}

# Check setup is complete
check_setup_complete() {
    check_file_exists ".loa-setup-complete"
}

# Check user type is THJ
check_user_is_thj() {
    if check_setup_complete; then
        check_content_contains ".loa-setup-complete" '"user_type":\s*"thj"'
    else
        return 1
    fi
}

# Check sprint ID format (sprint-N where N is positive integer)
check_sprint_id_format() {
    local sprint_id="$1"
    check_pattern_match "$sprint_id" "^sprint-[0-9]+$"
}

# Check sprint directory exists
check_sprint_directory() {
    local sprint_id="$1"
    check_directory_exists "loa-grimoire/a2a/${sprint_id}"
}

# Check reviewer.md exists for sprint
check_reviewer_exists() {
    local sprint_id="$1"
    check_file_exists "loa-grimoire/a2a/${sprint_id}/reviewer.md"
}

# Check sprint is approved by senior lead
check_sprint_approved() {
    local sprint_id="$1"
    local feedback_file="loa-grimoire/a2a/${sprint_id}/engineer-feedback.md"
    if check_file_exists "$feedback_file"; then
        check_content_contains "$feedback_file" "All good"
    else
        return 1
    fi
}

# Check sprint is completed (has COMPLETED marker)
check_sprint_completed() {
    local sprint_id="$1"
    check_file_exists "loa-grimoire/a2a/${sprint_id}/COMPLETED"
}

# Check git working tree is clean
check_git_clean() {
    [ -z "$(git status --porcelain 2>/dev/null)" ]
}

# Check remote exists
check_remote_exists() {
    local remote_name="$1"
    git remote -v 2>/dev/null | grep -qE "^${remote_name}\s"
}

# Check loa or upstream remote is configured
check_upstream_configured() {
    check_remote_exists "loa" || check_remote_exists "upstream"
}

# Run a pre-flight check and return result
# Args: $1=check_type, $2=arg1, $3=arg2 (optional)
run_preflight_check() {
    local check_type="$1"
    local arg1="$2"
    local arg2="$3"

    case "$check_type" in
        "file_exists")
            check_file_exists "$arg1"
            ;;
        "file_not_exists")
            check_file_not_exists "$arg1"
            ;;
        "directory_exists")
            check_directory_exists "$arg1"
            ;;
        "content_contains")
            check_content_contains "$arg1" "$arg2"
            ;;
        "pattern_match")
            check_pattern_match "$arg1" "$arg2"
            ;;
        "command_succeeds")
            check_command_succeeds "$arg1"
            ;;
        *)
            echo "Unknown check type: $check_type" >&2
            return 1
            ;;
    esac
}
