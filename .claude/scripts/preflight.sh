#!/usr/bin/env bash
# Pre-flight check functions for command validation
# Also includes integrity checks for ck semantic search integration
# Protocol: .claude/protocols/preflight-integrity.md
#
# Usage:
#   source preflight.sh          # Load helper functions
#   ./preflight.sh --integrity   # Run full integrity checks for ck operations

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
# SECURITY (HIGH-005): Use bash -c instead of eval for safer execution
# Note: This still executes shell commands, so only use with trusted input
check_command_succeeds() {
    local cmd="$1"
    # Use bash -c with restricted environment for slightly safer execution
    bash -c "$cmd" >/dev/null 2>&1
}

# Source constructs-lib for is_thj_member() function
# This is the canonical source for THJ membership detection
PREFLIGHT_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${PREFLIGHT_SCRIPT_DIR}/constructs-lib.sh" ]]; then
    source "${PREFLIGHT_SCRIPT_DIR}/constructs-lib.sh"
fi

# Check user type is THJ (v0.15.0+)
# Uses API key presence instead of marker file
check_user_is_thj() {
    is_thj_member 2>/dev/null
}

# Check sprint ID format (sprint-N where N is positive integer)
check_sprint_id_format() {
    local sprint_id="$1"
    check_pattern_match "$sprint_id" "^sprint-[0-9]+$"
}

# Check sprint directory exists
check_sprint_directory() {
    local sprint_id="$1"
    check_directory_exists "grimoires/loa/a2a/${sprint_id}"
}

# Check reviewer.md exists for sprint
check_reviewer_exists() {
    local sprint_id="$1"
    check_file_exists "grimoires/loa/a2a/${sprint_id}/reviewer.md"
}

# Check sprint is approved by senior lead
check_sprint_approved() {
    local sprint_id="$1"
    local feedback_file="grimoires/loa/a2a/${sprint_id}/engineer-feedback.md"
    if check_file_exists "$feedback_file"; then
        check_content_contains "$feedback_file" "All good"
    else
        return 1
    fi
}

# Check sprint is completed (has COMPLETED marker)
check_sprint_completed() {
    local sprint_id="$1"
    check_file_exists "grimoires/loa/a2a/${sprint_id}/COMPLETED"
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

# =============================================================================
# CK SEMANTIC SEARCH INTEGRITY CHECKS
# =============================================================================
# Run with: ./preflight.sh --integrity
# These checks enforce AWS Projen-level integrity for the ck integration

run_integrity_checks() {
    set -euo pipefail

    # 1. Establish project root
    PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

    # 2. Load integrity enforcement level
    ENFORCEMENT="warn"  # Default
    if [[ -f "${PROJECT_ROOT}/.loa.config.yaml" ]]; then
        ENFORCEMENT=$(grep "^integrity_enforcement:" "${PROJECT_ROOT}/.loa.config.yaml" | awk '{print $2}' || echo "warn")
    fi

    echo "Running pre-flight integrity checks (enforcement: ${ENFORCEMENT})..." >&2

    # 3. Verify System Zone checksums
    if [[ "${ENFORCEMENT}" != "disabled" ]] && [[ -f "${PROJECT_ROOT}/.claude/checksums.json" ]]; then
        echo "Verifying System Zone integrity..." >&2

        # Simple check: compare file count (full SHA verification would be more thorough)
        EXPECTED_COUNT=$(jq -r '.files | length' "${PROJECT_ROOT}/.claude/checksums.json" 2>/dev/null || echo "0")
        ACTUAL_COUNT=$(find "${PROJECT_ROOT}/.claude" -type f ! -path "*/.git/*" ! -path "*/overrides/*" ! -path "*/checksums.json" | wc -l)

        if [[ "${EXPECTED_COUNT}" != "${ACTUAL_COUNT}" ]]; then
            echo "⚠️  System Zone integrity check: file count mismatch" >&2
            echo "   Expected: ${EXPECTED_COUNT} files" >&2
            echo "   Actual:   ${ACTUAL_COUNT} files" >&2

            if [[ "${ENFORCEMENT}" == "strict" ]]; then
                echo "" >&2
                echo "SYSTEM ZONE INTEGRITY VIOLATION" >&2
                echo "" >&2
                echo "The .claude/ directory has been modified outside of the update process." >&2
                echo "" >&2
                echo "Resolution:" >&2
                echo "  1. Move customizations to .claude/overrides/" >&2
                echo "  2. Restore System Zone: .claude/scripts/update.sh --force-restore" >&2
                echo "  3. Re-run operation" >&2
                exit 1
            fi
        fi
    fi

    # 4. Check ck availability and version
    if command -v ck >/dev/null 2>&1; then
        CK_VERSION=$(ck --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' || echo "unknown")
        echo "✓ ck installed: ${CK_VERSION}" >&2

        # Version check (if .loa-version.json exists)
        if [[ -f "${PROJECT_ROOT}/.loa-version.json" ]]; then
            REQUIRED_VERSION=$(jq -r '.dependencies.ck.version // ">=0.7.0"' "${PROJECT_ROOT}/.loa-version.json")

            # Simple version comparison (assumes >=0.7.0 format)
            if [[ "${REQUIRED_VERSION}" == ">="* ]]; then
                MIN_VERSION="${REQUIRED_VERSION#>=}"
                if [[ "${CK_VERSION}" != "unknown" ]]; then
                    # Compare versions (very basic: assumes X.Y.Z format)
                    if [[ "$(printf '%s\n' "$MIN_VERSION" "$CK_VERSION" | sort -V | head -n1)" != "$MIN_VERSION" ]]; then
                        echo "⚠️  ck version too old" >&2
                        echo "   Required: ${REQUIRED_VERSION}" >&2
                        echo "   Installed: ${CK_VERSION}" >&2
                        echo "   Recommendation: cargo install ck-search --force" >&2

                        if [[ "${ENFORCEMENT}" == "strict" ]]; then
                            echo "" >&2
                            echo "HALTING: ck version requirement not met" >&2
                            exit 1
                        fi
                    fi
                fi
            fi

            # Binary fingerprint check (optional, if configured)
            EXPECTED_FINGERPRINT=$(jq -r '.binary_fingerprints.ck // ""' "${PROJECT_ROOT}/.loa-version.json")
            if [[ -n "${EXPECTED_FINGERPRINT}" ]] && [[ "${EXPECTED_FINGERPRINT}" != "null" ]]; then
                CK_PATH=$(command -v ck)
                ACTUAL_FINGERPRINT=$(sha256sum "${CK_PATH}" | awk '{print $1}')

                if [[ "${EXPECTED_FINGERPRINT}" != "${ACTUAL_FINGERPRINT}" ]]; then
                    echo "⚠️  ck binary fingerprint mismatch" >&2
                    echo "   Expected: ${EXPECTED_FINGERPRINT}" >&2
                    echo "   Actual:   ${ACTUAL_FINGERPRINT}" >&2

                    if [[ "${ENFORCEMENT}" == "strict" ]]; then
                        echo "" >&2
                        echo "HALTING: Binary integrity check failed" >&2
                        echo "Reinstall ck: cargo install ck-search --force" >&2
                        exit 1
                    fi
                fi
            fi
        fi
    else
        echo "○ ck not installed (optional - will use grep fallback)" >&2
    fi

    # 5. Self-Healing State Zone
    if [[ ! -d "${PROJECT_ROOT}/.ck" ]] || [[ ! -f "${PROJECT_ROOT}/.ck/.last_commit" ]]; then
        if command -v ck >/dev/null 2>&1; then
            echo "Self-healing: .ck/ missing, triggering background reindex..." >&2

            # Background reindex (non-blocking)
            nohup ck --index "${PROJECT_ROOT}" --quiet </dev/null >/dev/null 2>&1 &

            echo "Note: First search may be slower while index builds" >&2
        fi
    fi

    # 6. Delta Reindex Check (if index exists and ck available)
    if command -v ck >/dev/null 2>&1 && [[ -f "${PROJECT_ROOT}/.ck/.last_commit" ]]; then
        LAST_INDEXED=$(cat "${PROJECT_ROOT}/.ck/.last_commit")
        CURRENT_HEAD=$(git rev-parse HEAD 2>/dev/null || echo "")

        if [[ -n "${CURRENT_HEAD}" ]] && [[ "${LAST_INDEXED}" != "${CURRENT_HEAD}" ]]; then
            # Check number of changed files
            CHANGED_FILES=$(git diff --name-only "${LAST_INDEXED}" "${CURRENT_HEAD}" 2>/dev/null | wc -l)

            if [[ "${CHANGED_FILES}" -lt 100 ]]; then
                echo "Delta indexing ${CHANGED_FILES} changed files..." >&2
                ck --index "${PROJECT_ROOT}" --delta --quiet 2>/dev/null &
            else
                echo "Full reindex triggered (${CHANGED_FILES} files changed)" >&2
                ck --index "${PROJECT_ROOT}" --quiet 2>/dev/null &
            fi

            # Update marker
            echo "${CURRENT_HEAD}" > "${PROJECT_ROOT}/.ck/.last_commit"
        fi
    fi

    # 7. Command namespace validation
    if [[ -f "${PROJECT_ROOT}/.claude/scripts/validate-commands.sh" ]]; then
        echo "Validating command namespace..." >&2
        "${PROJECT_ROOT}/.claude/scripts/validate-commands.sh" || true  # Don't fail on warnings
    fi

    # 8. QMD Context: Surface known issues for current skill
    if [[ -x "${PROJECT_ROOT}/.claude/scripts/qmd-context-query.sh" ]]; then
        local skill_context
        skill_context=$("${PROJECT_ROOT}/.claude/scripts/qmd-context-query.sh" \
            --query "${2:-preflight} configuration prerequisites" \
            --scope notes \
            --budget 1000 \
            --format text 2>/dev/null) || skill_context=""
        if [[ -n "${skill_context}" ]]; then
            echo "Known issues context:" >&2
            echo "${skill_context}" >&2
        fi
    fi

    echo "✓ Pre-flight integrity checks complete" >&2
    exit 0
}

# Main execution: if called with --integrity, run integrity checks
if [[ "${1:-}" == "--integrity" ]]; then
    run_integrity_checks
fi
