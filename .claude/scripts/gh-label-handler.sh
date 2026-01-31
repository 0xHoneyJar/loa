#!/usr/bin/env bash
# gh-label-handler.sh - Create GitHub issues with graceful label handling
#
# Usage:
#   gh-label-handler.sh create-issue --repo owner/repo --title "Title" --body "Body" --labels "l1,l2" [--graceful]
#
# When --graceful is set, label errors are handled by retrying without labels

set -euo pipefail

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

success() {
    echo -e "${GREEN}$*${NC}" >&2
}

usage() {
    cat << 'EOF'
gh-label-handler.sh - Create GitHub issues with graceful label handling

USAGE:
    gh-label-handler.sh create-issue [OPTIONS]

COMMANDS:
    create-issue    Create a GitHub issue with optional label fallback

OPTIONS:
    --repo <owner/repo>     Target repository (required)
    --title <title>         Issue title (required)
    --body <body>           Issue body (required)
    --labels <l1,l2,...>    Comma-separated labels to apply
    --graceful              Retry without labels if they don't exist
    --help                  Show this help message

EXAMPLES:
    # Create issue with labels (fail if labels missing)
    gh-label-handler.sh create-issue \
        --repo 0xHoneyJar/loa \
        --title "Bug report" \
        --body "Description" \
        --labels "feedback,user-report"

    # Create issue with graceful label handling
    gh-label-handler.sh create-issue \
        --repo 0xHoneyJar/loa-constructs \
        --title "Feature request" \
        --body "Description" \
        --labels "feedback,enhancement" \
        --graceful

BEHAVIOR:
    Without --graceful:
        - Fails immediately if any label doesn't exist

    With --graceful:
        - First attempts with all labels
        - On "label not found" error, retries without labels
        - Warns user that labels were skipped
        - Returns success if issue created (with or without labels)
EOF
}

# Validate repo format
# SECURITY: Stricter regex - repos cannot start with dots or dashes
validate_repo() {
    local repo="$1"
    if [[ ! "$repo" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*/[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]]; then
        error "Invalid repository format: $repo"
        error "Expected format: owner/repo (must start with alphanumeric)"
        return 1
    fi
    return 0
}

# Check gh CLI availability and auth
check_gh_auth() {
    if ! command -v gh &> /dev/null; then
        error "GitHub CLI (gh) not found"
        error "Install it: https://cli.github.com/"
        return 1
    fi

    if ! gh auth status &> /dev/null; then
        error "GitHub CLI not authenticated"
        error "Run: gh auth login"
        return 1
    fi

    return 0
}

# Create issue with labels, handling errors gracefully
create_issue_with_labels() {
    local repo="$1"
    local title="$2"
    local body="$3"
    local labels="$4"
    local graceful="$5"

    local result
    local exit_code

    # Build gh command
    local gh_args=(issue create --repo "$repo" --title "$title" --body "$body")

    # Add labels if specified
    if [[ -n "$labels" ]]; then
        gh_args+=(--label "$labels")
    fi

    # First attempt: with labels
    result=$(gh "${gh_args[@]}" 2>&1) && exit_code=$? || exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        # Success - output the issue URL
        echo "$result"
        return 0
    fi

    # Check for label error
    if [[ "$result" == *"label"*"not found"* ]] || [[ "$result" == *"'label' not found"* ]]; then
        if [[ "$graceful" == "true" ]]; then
            warn "Labels '$labels' not found in $repo, submitting without labels"

            # Retry without labels
            gh_args=(issue create --repo "$repo" --title "$title" --body "$body")
            result=$(gh "${gh_args[@]}" 2>&1) && exit_code=$? || exit_code=$?

            if [[ $exit_code -eq 0 ]]; then
                echo "$result"
                return 0
            fi
        fi
    fi

    # Other error or graceful fallback also failed
    error "$result"
    return $exit_code
}

# Main command handler
main() {
    local command="${1:-}"

    if [[ -z "$command" ]] || [[ "$command" == "--help" ]] || [[ "$command" == "-h" ]]; then
        usage
        exit 0
    fi

    case "$command" in
        create-issue)
            shift

            # Parse arguments
            local repo=""
            local title=""
            local body=""
            local labels=""
            local graceful="false"

            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --repo)
                        repo="$2"
                        shift 2
                        ;;
                    --title)
                        title="$2"
                        shift 2
                        ;;
                    --body)
                        body="$2"
                        shift 2
                        ;;
                    --labels)
                        labels="$2"
                        shift 2
                        ;;
                    --graceful)
                        graceful="true"
                        shift
                        ;;
                    --help|-h)
                        usage
                        exit 0
                        ;;
                    *)
                        error "Unknown option: $1"
                        usage >&2
                        exit 1
                        ;;
                esac
            done

            # Validate required arguments
            if [[ -z "$repo" ]]; then
                error "--repo is required"
                usage >&2
                exit 1
            fi

            if [[ -z "$title" ]]; then
                error "--title is required"
                usage >&2
                exit 1
            fi

            if [[ -z "$body" ]]; then
                error "--body is required"
                usage >&2
                exit 1
            fi

            # Validate repo format
            validate_repo "$repo" || exit 1

            # Check gh auth
            check_gh_auth || exit 1

            # Create the issue
            create_issue_with_labels "$repo" "$title" "$body" "$labels" "$graceful"
            ;;
        *)
            error "Unknown command: $command"
            usage >&2
            exit 1
            ;;
    esac
}

main "$@"
