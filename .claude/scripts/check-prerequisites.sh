#!/bin/bash
# Check phase prerequisites
# Usage: ./check-prerequisites.sh --phase PHASE_NAME [--sprint SPRINT_ID]
# Returns: OK | MISSING|file1,file2,...
# Exit codes: 0=all present, 1=missing files

set -euo pipefail

check_files_exist() {
    local missing=()
    for file in "$@"; do
        if [ ! -f "$file" ]; then
            missing+=("$file")
        fi
    done

    if [ ${#missing[@]} -eq 0 ]; then
        echo "OK"
        return 0
    else
        local IFS=','
        echo "MISSING|${missing[*]}"
        return 1
    fi
}

main() {
    local phase=""
    local sprint_id=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --phase)
                phase="$2"
                shift 2
                ;;
            --sprint)
                sprint_id="$2"
                shift 2
                ;;
            *)
                echo "ERROR|Unknown argument: $1" >&2
                exit 2
                ;;
        esac
    done

    if [ -z "$phase" ]; then
        echo "ERROR|Missing --phase argument" >&2
        exit 2
    fi

    case "$phase" in
        "setup")
            # No prerequisites for setup
            echo "OK"
            ;;
        "plan"|"prd")
            # Setup must be complete
            check_files_exist ".loa-setup-complete"
            ;;
        "architect"|"sdd")
            # PRD must exist
            check_files_exist ".loa-setup-complete" "loa-grimoire/prd.md"
            ;;
        "sprint-plan")
            # PRD and SDD must exist
            check_files_exist ".loa-setup-complete" "loa-grimoire/prd.md" "loa-grimoire/sdd.md"
            ;;
        "implement")
            # PRD, SDD, and sprint.md must exist
            check_files_exist ".loa-setup-complete" "loa-grimoire/prd.md" "loa-grimoire/sdd.md" "loa-grimoire/sprint.md"
            ;;
        "review")
            # Reviewer.md must exist for the sprint
            if [ -z "$sprint_id" ]; then
                echo "ERROR|--sprint required for review phase" >&2
                exit 2
            fi
            check_files_exist "loa-grimoire/a2a/${sprint_id}/reviewer.md"
            ;;
        "audit-sprint")
            # Engineer feedback must show approval
            if [ -z "$sprint_id" ]; then
                echo "ERROR|--sprint required for audit-sprint phase" >&2
                exit 2
            fi
            local feedback="loa-grimoire/a2a/${sprint_id}/engineer-feedback.md"
            if [ ! -f "$feedback" ]; then
                echo "MISSING|${feedback}"
                exit 1
            fi
            if ! grep -q "All good" "$feedback"; then
                echo "MISSING|Senior lead approval (engineer-feedback.md must contain 'All good')"
                exit 1
            fi
            echo "OK"
            ;;
        "deploy")
            # Basic requirements
            check_files_exist ".loa-setup-complete" "loa-grimoire/prd.md" "loa-grimoire/sdd.md"
            ;;
        *)
            echo "ERROR|Unknown phase: $phase" >&2
            exit 2
            ;;
    esac
}

main "$@"
