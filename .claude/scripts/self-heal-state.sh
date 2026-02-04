#!/usr/bin/env bash
# self-heal-state.sh - State Zone recovery script
#
# Part of Loa Framework v0.9.0 Lossless Ledger Protocol
#
# Usage:
#   ./self-heal-state.sh [--check-only] [--verbose]
#
# Arguments:
#   --check-only  Only check for issues, don't repair
#   --verbose     Show detailed progress
#
# Exit Codes:
#   0 - State Zone healthy or healed successfully
#   1 - State Zone unhealthy and could not be fully healed
#   2 - Error in script
#
# Recovery Priority:
#   1. Git history (git show HEAD:...)
#   2. Git checkout (tracked files)
#   3. Template reconstruction
#   4. Delta reindex (.ck/ only)

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/bootstrap.sh"

CHECK_ONLY="${CHECK_ONLY:-false}"
VERBOSE="${VERBOSE:-false}"
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# State Zone paths (use path-lib)
NOTES_FILE=$(get_notes_path)
BEADS_DIR=$(get_beads_dir)
CK_DIR="${PROJECT_ROOT}/.ck"
TRAJECTORY_DIR=$(get_trajectory_dir)
GRIMOIRE_DIR=$(get_grimoire_dir)

# Templates
NOTES_TEMPLATE='# Agent Working Memory (NOTES.md)

> This file persists agent context across sessions and compaction cycles.
> Updated automatically by agents. Manual edits are preserved.

## Active Sub-Goals
<!-- Current objectives being pursued -->

## Discovered Technical Debt
<!-- Issues found during implementation that need future attention -->

## Blockers & Dependencies
<!-- External factors affecting progress -->

## Session Continuity
<!-- Key context to restore on next session -->
| Timestamp | Agent | Summary |
|-----------|-------|---------|

## Decision Log
<!-- Major decisions with rationale -->
'

# Parse arguments
for arg in "$@"; do
    case $arg in
        --check-only)
            CHECK_ONLY="true"
            ;;
        --verbose)
            VERBOSE="true"
            ;;
        *)
            echo "Unknown argument: $arg"
            exit 2
            ;;
    esac
done

# Logging functions
log() {
    echo "[SELF-HEAL] $*"
}

log_verbose() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo "[SELF-HEAL] $*"
    fi
}

log_error() {
    echo "[SELF-HEAL ERROR] $*" >&2
}

# Check if we're in a git repository
check_git() {
    if ! git rev-parse --git-dir &>/dev/null; then
        log_error "Not in a git repository. Self-healing requires git."
        return 1
    fi
    return 0
}

# Recovery: Try git show HEAD:path
recover_from_git_history() {
    local path="$1"
    local relative_path="${path#$PROJECT_ROOT/}"

    log_verbose "Attempting git history recovery for: $relative_path"

    if git show "HEAD:${relative_path}" &>/dev/null; then
        if [[ "$CHECK_ONLY" == "true" ]]; then
            log "  Can recover from git history: $relative_path"
            return 0
        fi

        local dir
        dir=$(dirname "$path")
        mkdir -p "$dir"
        git show "HEAD:${relative_path}" > "$path"
        log "  Recovered from git history: $relative_path"
        return 0
    fi

    return 1
}

# Recovery: Try git checkout
recover_from_git_checkout() {
    local path="$1"
    local relative_path="${path#$PROJECT_ROOT/}"

    log_verbose "Attempting git checkout recovery for: $relative_path"

    # Check if file is tracked
    if git ls-files --error-unmatch "$relative_path" &>/dev/null; then
        if [[ "$CHECK_ONLY" == "true" ]]; then
            log "  Can recover from git checkout: $relative_path"
            return 0
        fi

        git checkout HEAD -- "$relative_path" 2>/dev/null
        log "  Recovered from git checkout: $relative_path"
        return 0
    fi

    return 1
}

# Recovery: Create from template
recover_from_template() {
    local path="$1"
    local template="$2"

    log_verbose "Attempting template recovery for: $path"

    if [[ "$CHECK_ONLY" == "true" ]]; then
        log "  Will create from template: $path"
        return 0
    fi

    local dir
    dir=$(dirname "$path")
    mkdir -p "$dir"
    echo "$template" > "$path"
    log "  Created from template: $path"
    return 0
}

# Check and heal NOTES.md
heal_notes() {
    log "Checking: NOTES.md"

    if [[ -f "$NOTES_FILE" ]]; then
        # Check if file is not empty
        if [[ -s "$NOTES_FILE" ]]; then
            log_verbose "  NOTES.md exists and is not empty"
            return 0
        else
            log "  NOTES.md exists but is empty"
        fi
    else
        log "  NOTES.md is missing"
    fi

    # Try recovery methods in priority order
    if recover_from_git_history "$NOTES_FILE"; then
        return 0
    fi

    if recover_from_git_checkout "$NOTES_FILE"; then
        return 0
    fi

    # Fallback to template
    recover_from_template "$NOTES_FILE" "$NOTES_TEMPLATE"
    return 0
}

# Check and heal .beads/ directory
heal_beads() {
    log "Checking: .beads/"

    if [[ -d "$BEADS_DIR" ]]; then
        # Check if directory has content
        if [[ -n "$(ls -A "$BEADS_DIR" 2>/dev/null)" ]]; then
            log_verbose "  .beads/ exists and has content"
            return 0
        else
            log "  .beads/ exists but is empty"
        fi
    else
        log "  .beads/ is missing"
    fi

    # Try recovery from git
    if git ls-files --error-unmatch ".beads/" &>/dev/null 2>&1; then
        if [[ "$CHECK_ONLY" == "true" ]]; then
            log "  Can recover .beads/ from git"
            return 0
        fi

        git checkout HEAD -- ".beads/" 2>/dev/null || true
        log "  Recovered .beads/ from git"
        return 0
    fi

    # Create empty directory if nothing to recover
    if [[ "$CHECK_ONLY" != "true" ]]; then
        mkdir -p "$BEADS_DIR"
        log "  Created empty .beads/ directory"
    else
        log "  Will create empty .beads/ directory"
    fi

    return 0
}

# Check and heal .ck/ directory (index)
heal_ck() {
    log "Checking: .ck/ (search index)"

    if [[ -d "$CK_DIR" ]]; then
        # Check for index files
        if [[ -f "${CK_DIR}/index.db" ]] || [[ -f "${CK_DIR}/config.yaml" ]]; then
            log_verbose "  .ck/ index exists"
            return 0
        else
            log "  .ck/ exists but may be corrupted"
        fi
    else
        log "  .ck/ is missing (search index)"
    fi

    # Check if ck is available
    if ! command -v ck &>/dev/null; then
        log_verbose "  ck not available, skipping index recovery"
        return 0
    fi

    # Determine reindex strategy
    local changed_files=0
    if check_git; then
        # Count files changed since last index
        if [[ -f "${CK_DIR}/.last_indexed" ]]; then
            local last_indexed
            last_indexed=$(cat "${CK_DIR}/.last_indexed" 2>/dev/null || echo "")
            if [[ -n "$last_indexed" ]]; then
                changed_files=$(git diff --name-only "$last_indexed" HEAD 2>/dev/null | wc -l || echo "0")
            fi
        fi
    fi

    if [[ "$CHECK_ONLY" == "true" ]]; then
        if [[ "$changed_files" -lt 100 ]]; then
            log "  Will perform delta reindex ($changed_files files)"
        else
            log "  Will perform full reindex ($changed_files files)"
        fi
        return 0
    fi

    # Perform reindex
    if [[ "$changed_files" -lt 100 ]] && [[ "$changed_files" -gt 0 ]]; then
        log "  Performing delta reindex ($changed_files files)"
        ck index --delta "$PROJECT_ROOT" 2>/dev/null || true
    else
        log "  Performing full reindex"
        ck index "$PROJECT_ROOT" 2>/dev/null &
        log "  Full reindex started in background"
    fi

    return 0
}

# Check and heal trajectory directory
heal_trajectory() {
    log "Checking: trajectory/"

    if [[ -d "$TRAJECTORY_DIR" ]]; then
        log_verbose "  trajectory/ exists"
        return 0
    else
        log "  trajectory/ is missing"
    fi

    if [[ "$CHECK_ONLY" != "true" ]]; then
        mkdir -p "$TRAJECTORY_DIR"
        log "  Created trajectory/ directory"
    else
        log "  Will create trajectory/ directory"
    fi

    return 0
}

# Check and heal grimoire directory
heal_grimoire() {
    # Get relative path for git operations and logging
    local grimoire_rel="${GRIMOIRE_DIR#$PROJECT_ROOT/}"
    log "Checking: $grimoire_rel/"

    if [[ -d "$GRIMOIRE_DIR" ]]; then
        log_verbose "  $grimoire_rel/ exists"
        return 0
    else
        log "  $grimoire_rel/ is missing"
    fi

    # Try recovery from git
    if git ls-files --error-unmatch "$grimoire_rel/" &>/dev/null 2>&1; then
        if [[ "$CHECK_ONLY" == "true" ]]; then
            log "  Can recover $grimoire_rel/ from git"
            return 0
        fi

        git checkout HEAD -- "$grimoire_rel/" 2>/dev/null || true
        log "  Recovered $grimoire_rel/ from git"
        return 0
    fi

    # Create directory structure using ensure_grimoire_structure from path-lib
    if [[ "$CHECK_ONLY" != "true" ]]; then
        ensure_grimoire_structure
        log "  Created $grimoire_rel/ directory structure"
    else
        log "  Will create $grimoire_rel/ directory structure"
    fi

    return 0
}

# Log recovery to trajectory
log_recovery() {
    if [[ "$CHECK_ONLY" == "true" ]]; then
        return 0
    fi

    mkdir -p "$TRAJECTORY_DIR"

    local recovery_entry
    recovery_entry=$(jq -n \
        --arg ts "$TIMESTAMP" \
        --arg phase "self_heal" \
        --arg status "complete" \
        '{timestamp: $ts, phase: $phase, status: $status, message: "State Zone self-healing completed"}')

    echo "$recovery_entry" >> "${TRAJECTORY_DIR}/system-$(date +%Y-%m-%d).jsonl"
}

# Print summary
print_summary() {
    local issues="$1"

    echo ""
    echo "=============================================="
    echo "  SELF-HEALING SUMMARY"
    echo "=============================================="

    if [[ "$CHECK_ONLY" == "true" ]]; then
        echo "  Mode: Check only (no changes made)"
    else
        echo "  Mode: Heal"
    fi

    echo "  Timestamp: $TIMESTAMP"

    if [[ "$issues" -eq 0 ]]; then
        echo "  Status: State Zone is healthy"
    else
        if [[ "$CHECK_ONLY" == "true" ]]; then
            echo "  Status: $issues issues found"
            echo "  Run without --check-only to repair"
        else
            echo "  Status: $issues issues healed"
        fi
    fi

    echo "=============================================="
}

# Main execution
main() {
    local issues=0

    log "Starting State Zone health check..."
    log "Project root: $PROJECT_ROOT"
    echo ""

    # Check git availability
    if ! check_git; then
        log_error "Git is required for self-healing"
        exit 2
    fi

    # Heal each component
    heal_grimoire || ((issues++)) || true
    heal_notes || ((issues++)) || true
    heal_beads || ((issues++)) || true
    heal_trajectory || ((issues++)) || true
    heal_ck || true  # .ck/ is optional, don't count as issue

    # Log recovery
    log_recovery

    # Print summary
    print_summary "$issues"

    # Exit code
    if [[ "$issues" -gt 0 ]] && [[ "$CHECK_ONLY" == "true" ]]; then
        exit 1
    fi

    exit 0
}

# Run main
main
