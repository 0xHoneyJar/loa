#!/usr/bin/env bash
# check-updates.sh - Automatic version checking for Loa framework
#
# This script checks GitHub releases for available updates and notifies users.
# Designed to run on session start via SessionStart hook.
#
# Usage:
#   check-updates.sh --notify     Check and show notification (default for hooks)
#   check-updates.sh --check      Force check (bypass cache)
#   check-updates.sh --json       Output JSON (for scripting)
#   check-updates.sh --quiet      Suppress non-error output
#   check-updates.sh --help       Show usage
#
# Exit Codes:
#   0  Up to date or check disabled
#   1  Update available
#   2  Error (network, parse, etc.)
#
# Environment:
#   LOA_DISABLE_UPDATE_CHECK=1    Disable all checks
#   LOA_UPDATE_CHECK_TTL=24       Cache TTL in hours (default: 24)
#   LOA_UPSTREAM_REPO=owner/repo  GitHub repo to check
#   LOA_UPDATE_NOTIFICATION=style Notification style (banner|line|silent)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Configuration defaults
CACHE_DIR="${LOA_CACHE_DIR:-$HOME/.loa/cache}"
CACHE_FILE="$CACHE_DIR/update-check.json"
DEFAULT_TTL_HOURS=24
DEFAULT_UPSTREAM_REPO="0xHoneyJar/loa"
DEFAULT_NOTIFICATION_STYLE="banner"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

# Global state
FORCE_CHECK=false
OUTPUT_JSON=false
QUIET=false
NOTIFY_MODE=false

# =============================================================================
# Dependency Checks
# =============================================================================

check_bash_version() {
    if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
        echo -e "${RED}ERROR: bash 4.0+ required (found ${BASH_VERSION})${NC}" >&2
        echo "" >&2
        echo "Upgrade bash:" >&2
        echo "  macOS:  brew install bash" >&2
        echo "          Then add /opt/homebrew/bin/bash to /etc/shells" >&2
        echo "          And run: chsh -s /opt/homebrew/bin/bash" >&2
        exit 2
    fi
}

check_dependencies() {
    local missing=()

    if ! command -v jq &> /dev/null; then
        missing+=("jq")
    fi

    if ! command -v curl &> /dev/null; then
        missing+=("curl")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo -e "${RED}ERROR: Missing dependencies: ${missing[*]}${NC}" >&2
        echo "" >&2
        echo "Install missing dependencies:" >&2
        echo "  macOS:  brew install ${missing[*]}" >&2
        echo "  Ubuntu: sudo apt install ${missing[*]}" >&2
        exit 2
    fi
}

# =============================================================================
# Configuration Loading
# =============================================================================

load_config() {
    # Environment variables take priority
    TTL_HOURS="${LOA_UPDATE_CHECK_TTL:-}"
    UPSTREAM_REPO="${LOA_UPSTREAM_REPO:-}"
    NOTIFICATION_STYLE="${LOA_UPDATE_NOTIFICATION:-}"
    DISABLED="${LOA_DISABLE_UPDATE_CHECK:-}"
    INCLUDE_PRERELEASES="${LOA_INCLUDE_PRERELEASES:-false}"

    # Load from .loa.config.yaml if yq is available and values not set
    local config_file="$PROJECT_ROOT/.loa.config.yaml"
    if [[ -f "$config_file" ]] && command -v yq &> /dev/null; then
        [[ -z "$TTL_HOURS" ]] && TTL_HOURS=$(yq -r '.update_check.cache_ttl_hours // ""' "$config_file" 2>/dev/null || echo "")
        [[ -z "$UPSTREAM_REPO" ]] && UPSTREAM_REPO=$(yq -r '.update_check.upstream_repo // ""' "$config_file" 2>/dev/null || echo "")
        [[ -z "$NOTIFICATION_STYLE" ]] && NOTIFICATION_STYLE=$(yq -r '.update_check.notification_style // ""' "$config_file" 2>/dev/null || echo "")
        [[ -z "$DISABLED" ]] && DISABLED=$(yq -r '.update_check.enabled // "true"' "$config_file" 2>/dev/null || echo "true")
        [[ "$DISABLED" == "false" ]] && DISABLED="1"
        [[ "$DISABLED" == "true" ]] && DISABLED=""
        INCLUDE_PRERELEASES=$(yq -r '.update_check.include_prereleases // "false"' "$config_file" 2>/dev/null || echo "false")
    fi

    # Apply defaults
    TTL_HOURS="${TTL_HOURS:-$DEFAULT_TTL_HOURS}"
    UPSTREAM_REPO="${UPSTREAM_REPO:-$DEFAULT_UPSTREAM_REPO}"
    NOTIFICATION_STYLE="${NOTIFICATION_STYLE:-$DEFAULT_NOTIFICATION_STYLE}"
}

# =============================================================================
# CI/Environment Detection
# =============================================================================

is_ci_environment() {
    # GitHub Actions
    [[ -n "${GITHUB_ACTIONS:-}" ]] && return 0

    # Generic CI flag
    [[ "${CI:-}" == "true" ]] && return 0

    # GitLab CI
    [[ -n "${GITLAB_CI:-}" ]] && return 0

    # Jenkins
    [[ -n "${JENKINS_URL:-}" ]] && return 0

    # CircleCI
    [[ -n "${CIRCLECI:-}" ]] && return 0

    # Travis CI
    [[ -n "${TRAVIS:-}" ]] && return 0

    # Bitbucket Pipelines
    [[ -n "${BITBUCKET_BUILD_NUMBER:-}" ]] && return 0

    # Azure Pipelines
    [[ -n "${TF_BUILD:-}" ]] && return 0

    return 1
}

should_skip() {
    # Explicitly disabled
    [[ -n "${DISABLED:-}" ]] && return 0

    # CI environment
    is_ci_environment && return 0

    # Non-interactive terminal (but allow if --notify explicitly passed)
    if [[ ! -t 1 ]] && [[ "$NOTIFY_MODE" != "true" ]]; then
        return 0
    fi

    return 1
}

# =============================================================================
# Version Comparison (Semver)
# =============================================================================

# Compare two semver strings
# Returns: -1 (a < b), 0 (a == b), 1 (a > b)
semver_compare() {
    local a="$1" b="$2"

    # Strip 'v' prefix
    a="${a#v}"
    b="${b#v}"

    # Extract pre-release suffix
    local a_pre="" b_pre=""
    if [[ "$a" == *-* ]]; then
        a_pre="${a#*-}"
        a="${a%%-*}"
    fi
    if [[ "$b" == *-* ]]; then
        b_pre="${b#*-}"
        b="${b%%-*}"
    fi

    # Split into components
    local a_major a_minor a_patch
    local b_major b_minor b_patch

    IFS='.' read -r a_major a_minor a_patch <<< "$a"
    IFS='.' read -r b_major b_minor b_patch <<< "$b"

    # Default to 0 if empty
    a_major="${a_major:-0}"
    a_minor="${a_minor:-0}"
    a_patch="${a_patch:-0}"
    b_major="${b_major:-0}"
    b_minor="${b_minor:-0}"
    b_patch="${b_patch:-0}"

    # Compare major
    [[ $a_major -lt $b_major ]] && echo -1 && return
    [[ $a_major -gt $b_major ]] && echo 1 && return

    # Compare minor
    [[ $a_minor -lt $b_minor ]] && echo -1 && return
    [[ $a_minor -gt $b_minor ]] && echo 1 && return

    # Compare patch
    [[ $a_patch -lt $b_patch ]] && echo -1 && return
    [[ $a_patch -gt $b_patch ]] && echo 1 && return

    # Handle pre-release (none > beta > alpha)
    # A release without pre-release is greater than one with
    [[ -z "$a_pre" && -n "$b_pre" ]] && echo 1 && return
    [[ -n "$a_pre" && -z "$b_pre" ]] && echo -1 && return

    # Both have pre-release or both don't - compare alphabetically
    if [[ -n "$a_pre" && -n "$b_pre" ]]; then
        [[ "$a_pre" < "$b_pre" ]] && echo -1 && return
        [[ "$a_pre" > "$b_pre" ]] && echo 1 && return
    fi

    echo 0
}

# Check if this is a major version update
is_major_update() {
    local local_ver="$1" remote_ver="$2"

    local_ver="${local_ver#v}"
    remote_ver="${remote_ver#v}"

    local local_major remote_major
    local_major="${local_ver%%.*}"
    remote_major="${remote_ver%%.*}"

    [[ "$remote_major" -gt "$local_major" ]]
}

# =============================================================================
# Cache Management
# =============================================================================

init_cache() {
    mkdir -p "$CACHE_DIR"
}

# Get file modification time (cross-platform)
get_file_mtime() {
    local file="$1"
    # Try Linux stat first, fall back to macOS
    stat -c %Y "$file" 2>/dev/null || stat -f %m "$file" 2>/dev/null || echo 0
}

is_cache_valid() {
    if [[ "$FORCE_CHECK" == "true" ]]; then
        return 1
    fi

    if [[ ! -f "$CACHE_FILE" ]]; then
        return 1
    fi

    local cache_time
    cache_time=$(get_file_mtime "$CACHE_FILE")
    local current_time
    current_time=$(date +%s)
    local cache_age_hours=$(( (current_time - cache_time) / 3600 ))

    if [[ $cache_age_hours -ge $TTL_HOURS ]]; then
        return 1
    fi

    return 0
}

read_cache() {
    if [[ -f "$CACHE_FILE" ]]; then
        cat "$CACHE_FILE"
    else
        echo "{}"
    fi
}

write_cache() {
    local local_version="$1"
    local remote_version="$2"
    local remote_url="$3"
    local update_available="$4"
    local is_major="$5"

    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    cat > "$CACHE_FILE" << EOF
{
  "last_check": "$timestamp",
  "local_version": "$local_version",
  "remote_version": "$remote_version",
  "remote_url": "$remote_url",
  "update_available": $update_available,
  "is_major_update": $is_major,
  "ttl_hours": $TTL_HOURS
}
EOF
}

# =============================================================================
# GitHub API Integration
# =============================================================================

fetch_latest_release() {
    local owner repo
    owner="${UPSTREAM_REPO%%/*}"
    repo="${UPSTREAM_REPO##*/}"

    local api_url="https://api.github.com/repos/$owner/$repo/releases/latest"

    local response
    # HIGH-002 FIX: Enforce HTTPS and TLS 1.2+
    response=$(curl -sL --proto =https --tlsv1.2 \
        -H "Accept: application/vnd.github+json" \
        --max-time 5 \
        "$api_url" 2>/dev/null) || {
        # Network error - silent fail
        echo ""
        return 1
    }

    # Check for API errors
    if echo "$response" | jq -e '.message' &>/dev/null; then
        # API error (rate limited, not found, etc.)
        echo ""
        return 1
    fi

    echo "$response"
}

get_local_version() {
    local version_file="$PROJECT_ROOT/.loa-version.json"

    if [[ -f "$version_file" ]]; then
        jq -r '.framework_version // ""' "$version_file" 2>/dev/null || echo ""
    else
        echo ""
    fi
}

# =============================================================================
# Notification Display
# =============================================================================

show_notification() {
    local local_version="$1"
    local remote_version="$2"
    local remote_url="$3"
    local is_major="$4"

    case "$NOTIFICATION_STYLE" in
        banner)
            show_banner_notification "$local_version" "$remote_version" "$remote_url" "$is_major"
            ;;
        line)
            show_line_notification "$local_version" "$remote_version"
            ;;
        silent)
            # No output
            ;;
        *)
            show_banner_notification "$local_version" "$remote_version" "$remote_url" "$is_major"
            ;;
    esac
}

show_banner_notification() {
    local local_version="$1"
    local remote_version="$2"
    local remote_url="$3"
    local is_major="$4"

    local width=61

    echo ""
    printf "%s\n" "$(printf '%.0s─' $(seq 1 $width))"

    if [[ "$is_major" == "true" ]]; then
        printf "  ${YELLOW}Loa v%s available${NC} (current: v%s)\n" "$remote_version" "$local_version"
        printf "  ${YELLOW}MAJOR VERSION${NC} - review changelog before updating\n"
    else
        printf "  ${GREEN}Loa v%s available${NC} (current: v%s)\n" "$remote_version" "$local_version"
    fi

    printf "     Run ${CYAN}/update-loa${NC} to upgrade\n"
    printf "     %s\n" "$remote_url"
    printf "%s\n" "$(printf '%.0s─' $(seq 1 $width))"
    echo ""
}

show_line_notification() {
    local local_version="$1"
    local remote_version="$2"

    echo -e "${GREEN}Loa update:${NC} v$remote_version available (run '/update-loa' to upgrade)"
}

# =============================================================================
# JSON Output
# =============================================================================

output_json() {
    local local_version="$1"
    local remote_version="$2"
    local remote_url="$3"
    local update_available="$4"
    local is_major="$5"
    local skipped="${6:-false}"
    local skip_reason="${7:-}"

    cat << EOF
{
  "local_version": "$local_version",
  "remote_version": "$remote_version",
  "remote_url": "$remote_url",
  "update_available": $update_available,
  "is_major_update": $is_major,
  "skipped": $skipped,
  "skip_reason": "$skip_reason"
}
EOF
}

# =============================================================================
# Main Logic
# =============================================================================

show_help() {
    cat << 'HELP'
check-updates.sh - Automatic version checking for Loa framework

Usage:
  check-updates.sh [OPTIONS]

OPTIONS:
  --notify        Show notification if update available (default for hooks)
  --check         Force check (bypass cache)
  --json          Output JSON (for scripting)
  --quiet         Suppress non-error output
  --help          Show this help message

EXIT CODES:
  0  Up to date or check disabled
  1  Update available
  2  Error (network, parse, etc.)

ENVIRONMENT VARIABLES:
  LOA_DISABLE_UPDATE_CHECK=1    Disable all update checks
  LOA_UPDATE_CHECK_TTL=24       Cache TTL in hours (default: 24)
  LOA_UPSTREAM_REPO=owner/repo  GitHub repo to check (default: 0xHoneyJar/loa)
  LOA_UPDATE_NOTIFICATION=style Notification style: banner|line|silent

CONFIGURATION:
  Add to .loa.config.yaml:
    update_check:
      enabled: true
      cache_ttl_hours: 24
      notification_style: banner
      include_prereleases: false
      upstream_repo: "0xHoneyJar/loa"

HELP
}

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --notify)
                NOTIFY_MODE=true
                shift
                ;;
            --check)
                FORCE_CHECK=true
                shift
                ;;
            --json)
                OUTPUT_JSON=true
                shift
                ;;
            --quiet)
                QUIET=true
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                echo "Unknown option: $1" >&2
                show_help >&2
                exit 2
                ;;
        esac
    done

    # Run dependency checks
    check_bash_version
    check_dependencies

    # Load configuration
    load_config

    # Initialize cache directory
    init_cache

    # Check if we should skip
    if should_skip; then
        if [[ "$OUTPUT_JSON" == "true" ]]; then
            local skip_reason="disabled"
            is_ci_environment && skip_reason="ci_environment"
            output_json "" "" "" "false" "false" "true" "$skip_reason"
        fi
        exit 0
    fi

    # Get local version
    local local_version
    local_version=$(get_local_version)

    if [[ -z "$local_version" ]]; then
        [[ "$QUIET" != "true" ]] && echo "Warning: Could not determine local version" >&2
        if [[ "$OUTPUT_JSON" == "true" ]]; then
            output_json "" "" "" "false" "false" "true" "no_local_version"
        fi
        exit 0
    fi

    # Check cache
    local remote_version="" remote_url="" update_available=false is_major=false

    if is_cache_valid; then
        # Use cached data
        local cache_data
        cache_data=$(read_cache)
        remote_version=$(echo "$cache_data" | jq -r '.remote_version // ""')
        remote_url=$(echo "$cache_data" | jq -r '.remote_url // ""')
        update_available=$(echo "$cache_data" | jq -r '.update_available // false')
        is_major=$(echo "$cache_data" | jq -r '.is_major_update // false')
    else
        # Fetch from GitHub
        local release_data
        release_data=$(fetch_latest_release)

        if [[ -z "$release_data" ]]; then
            # Network error - try to use stale cache
            if [[ -f "$CACHE_FILE" ]]; then
                local cache_data
                cache_data=$(read_cache)
                remote_version=$(echo "$cache_data" | jq -r '.remote_version // ""')
                remote_url=$(echo "$cache_data" | jq -r '.remote_url // ""')
                update_available=$(echo "$cache_data" | jq -r '.update_available // false')
                is_major=$(echo "$cache_data" | jq -r '.is_major_update // false')
            fi
        else
            # Parse release data
            remote_version=$(echo "$release_data" | jq -r '.tag_name // ""')
            remote_url=$(echo "$release_data" | jq -r '.html_url // ""')
            local is_prerelease
            is_prerelease=$(echo "$release_data" | jq -r '.prerelease // false')

            # Skip pre-releases unless configured
            if [[ "$is_prerelease" == "true" && "$INCLUDE_PRERELEASES" != "true" ]]; then
                remote_version=""
            fi

            # Compare versions
            if [[ -n "$remote_version" ]]; then
                local cmp
                cmp=$(semver_compare "$local_version" "$remote_version")
                if [[ "$cmp" == "-1" ]]; then
                    update_available=true
                    is_major_update "$local_version" "$remote_version" && is_major=true || is_major=false
                fi
            fi

            # Update cache
            write_cache "$local_version" "$remote_version" "$remote_url" "$update_available" "$is_major"
        fi
    fi

    # Output results
    if [[ "$OUTPUT_JSON" == "true" ]]; then
        output_json "$local_version" "$remote_version" "$remote_url" "$update_available" "$is_major"
    elif [[ "$update_available" == "true" && "$QUIET" != "true" ]]; then
        show_notification "$local_version" "$remote_version" "$remote_url" "$is_major"
    fi

    # Exit code based on update availability
    [[ "$update_available" == "true" ]] && exit 1 || exit 0
}

main "$@"
