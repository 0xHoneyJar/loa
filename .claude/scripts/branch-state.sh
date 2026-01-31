#!/usr/bin/env bash
# branch-state.sh - Manage branch testing state for /update-loa
#
# Usage:
#   branch-state.sh save --testing-branch "feature/foo" --original-branch "main"
#   branch-state.sh load
#   branch-state.sh clear
#   branch-state.sh is-testing

set -euo pipefail

# SECURITY: Resolve state directory to absolute path from project root
# Find project root by looking for .loa.config.yaml or .git
find_project_root() {
    local dir="$PWD"
    while [[ "$dir" != "/" ]]; do
        if [[ -f "$dir/.loa.config.yaml" ]] || [[ -d "$dir/.git" ]]; then
            echo "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    # Fallback to current directory if no markers found
    echo "$PWD"
}

PROJECT_ROOT="$(find_project_root)"
STATE_DIR="$PROJECT_ROOT/.loa"
STATE_FILE="$STATE_DIR/branch-testing.json"

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

warn() {
    echo -e "${YELLOW}Warning: $*${NC}" >&2
}

error() {
    echo -e "${RED}Error: $*${NC}" >&2
}

usage() {
    cat << 'EOF'
branch-state.sh - Manage branch testing state for /update-loa

USAGE:
    branch-state.sh <command> [OPTIONS]

COMMANDS:
    save            Save branch testing state
    load            Load current state (outputs JSON or empty)
    clear           Clear state file
    is-testing      Check if currently in test branch (exit 0 if yes, 1 if no)

SAVE OPTIONS:
    --testing-branch <branch>   Branch being tested (required)
    --original-branch <branch>  Original branch to return to (required)
    --remote <name>             Loa remote name (default: loa)

EXAMPLES:
    # Save state before checkout
    branch-state.sh save --testing-branch "feature/foo" --original-branch "main"

    # Load current state
    branch-state.sh load
    # Output: {"testing_branch":"feature/foo","original_branch":"main",...}

    # Check if testing
    if branch-state.sh is-testing; then
        echo "Currently testing a branch"
    fi

    # Clear state after returning
    branch-state.sh clear

STATE FILE:
    Located at: .loa/branch-testing.json

    Schema:
    {
      "testing_branch": "feature/foo",
      "original_branch": "main",
      "checkout_time": "2026-02-01T00:00:00Z",
      "loa_remote": "loa"
    }
EOF
}

# Ensure state directory exists
ensure_state_dir() {
    if [[ ! -d "$STATE_DIR" ]]; then
        mkdir -p "$STATE_DIR"
    fi
}

# Save branch testing state
save_state() {
    local testing_branch=""
    local original_branch=""
    local remote="loa"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --testing-branch)
                testing_branch="$2"
                shift 2
                ;;
            --original-branch)
                original_branch="$2"
                shift 2
                ;;
            --remote)
                remote="$2"
                shift 2
                ;;
            *)
                error "Unknown option for save: $1"
                exit 1
                ;;
        esac
    done

    # Validate required arguments
    if [[ -z "$testing_branch" ]]; then
        error "--testing-branch is required"
        exit 1
    fi

    if [[ -z "$original_branch" ]]; then
        error "--original-branch is required"
        exit 1
    fi

    # Validate branch name format (alphanumeric, dash, underscore, slash)
    if [[ ! "$testing_branch" =~ ^[a-zA-Z0-9/_.-]+$ ]]; then
        error "Invalid testing branch name: $testing_branch"
        error "Only alphanumeric, dash, underscore, slash, and dot allowed"
        exit 1
    fi

    if [[ ! "$original_branch" =~ ^[a-zA-Z0-9/_.-]+$ ]]; then
        error "Invalid original branch name: $original_branch"
        error "Only alphanumeric, dash, underscore, slash, and dot allowed"
        exit 1
    fi

    ensure_state_dir

    local checkout_time
    checkout_time=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    cat > "$STATE_FILE" << EOF
{
  "testing_branch": "$testing_branch",
  "original_branch": "$original_branch",
  "checkout_time": "$checkout_time",
  "loa_remote": "$remote"
}
EOF

    echo -e "${GREEN}State saved: testing $testing_branch (return to $original_branch)${NC}" >&2
}

# Load current state
load_state() {
    if [[ -f "$STATE_FILE" ]]; then
        # Validate JSON before outputting
        if jq -e . "$STATE_FILE" > /dev/null 2>&1; then
            cat "$STATE_FILE"
        else
            warn "State file corrupted, clearing"
            rm -f "$STATE_FILE"
        fi
    fi
    # Output nothing if no state file (empty output)
}

# Clear state file
clear_state() {
    if [[ -f "$STATE_FILE" ]]; then
        rm -f "$STATE_FILE"
        echo -e "${GREEN}State cleared${NC}" >&2
    fi
}

# Check if currently in test branch
is_testing() {
    # Check if state file exists
    if [[ ! -f "$STATE_FILE" ]]; then
        return 1
    fi

    # Validate JSON
    if ! jq -e . "$STATE_FILE" > /dev/null 2>&1; then
        return 1
    fi

    # Get current branch
    local current_branch
    current_branch=$(git branch --show-current 2>/dev/null || echo "")

    if [[ -z "$current_branch" ]]; then
        return 1
    fi

    # Check if on a test/loa-* branch
    if [[ "$current_branch" =~ ^test/loa- ]]; then
        return 0
    fi

    # Also check if current branch matches the testing_branch from state
    local testing_branch
    testing_branch=$(jq -r '.testing_branch // ""' "$STATE_FILE")

    if [[ -n "$testing_branch" && "$current_branch" == "test/loa-$testing_branch" ]]; then
        return 0
    fi

    return 1
}

# Main command handler
main() {
    local command="${1:-}"

    if [[ -z "$command" ]] || [[ "$command" == "--help" ]] || [[ "$command" == "-h" ]]; then
        usage
        exit 0
    fi

    case "$command" in
        save)
            shift
            save_state "$@"
            ;;
        load)
            load_state
            ;;
        clear)
            clear_state
            ;;
        is-testing)
            is_testing
            ;;
        *)
            error "Unknown command: $command"
            usage >&2
            exit 1
            ;;
    esac
}

main "$@"
