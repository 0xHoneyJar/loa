#!/usr/bin/env bash
# =============================================================================
# pipeline-self-review.sh — Detect and review changes to pipeline code
# =============================================================================
# Part of: Bridgebuilder Constellation (cycle-046, FR-3)
#
# When a PR modifies pipeline scripts (.claude/scripts/, .claude/skills/, etc.),
# this script resolves the governing SDDs and runs the Red Team code-vs-design
# gate against them. Pipeline bugs have multiplicative impact — this adds
# self-examination capability to the review infrastructure.
#
# Usage:
#   pipeline-self-review.sh --base-branch <branch> --output-dir <path>
#
# Options:
#   --base-branch <branch>   Base branch for diff (default: main)
#   --output-dir <path>      Directory for findings output (required)
#   --dry-run                List detected changes without invoking Red Team
#
# Exit codes:
#   0 - Success (findings produced or no pipeline changes)
#   1 - Error
#   2 - Invalid input
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_FILE="$PROJECT_ROOT/.loa.config.yaml"
PIPELINE_MAP="$SCRIPT_DIR/../data/pipeline-sdd-map.json"
RED_TEAM_SCRIPT="$SCRIPT_DIR/red-team-code-vs-design.sh"

# =============================================================================
# Logging
# =============================================================================

log() {
    echo "[pipeline-self-review] $*" >&2
}

error() {
    echo "[pipeline-self-review] ERROR: $*" >&2
}

# =============================================================================
# Pipeline Change Detection
# =============================================================================

# Detect files changed in .claude/ directories that are pipeline code
detect_pipeline_changes() {
    local base_branch="${1:-main}"

    git diff --name-only "$base_branch"...HEAD -- \
        '.claude/scripts/' \
        '.claude/skills/' \
        '.claude/data/' \
        '.claude/protocols/' \
        2>/dev/null || echo ""
}

# =============================================================================
# SDD Resolution
# =============================================================================

# Given a changed file, resolve its governing SDD via pipeline-sdd-map.json
resolve_pipeline_sdd() {
    local changed_file="$1"

    if [[ ! -f "$PIPELINE_MAP" ]]; then
        error "Pipeline SDD map not found: $PIPELINE_MAP"
        return 1
    fi

    # Match against glob patterns in the map
    jq -r --arg file "$changed_file" '
        .patterns[] |
        select(
            ($file | test(.glob | gsub("\\*"; ".*") | gsub("\\?"; ".")))
        ) |
        .sdd
    ' "$PIPELINE_MAP" 2>/dev/null | head -1
}

# Resolve all unique SDDs for a list of changed files
resolve_all_sdds() {
    local changes="$1"
    local sdds=()
    local seen=()

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        local sdd
        sdd=$(resolve_pipeline_sdd "$file")
        if [[ -n "$sdd" && ! " ${seen[*]:-} " =~ " $sdd " ]]; then
            if [[ -f "$PROJECT_ROOT/$sdd" ]]; then
                sdds+=("$sdd")
                seen+=("$sdd")
            else
                log "SDD not found, skipping: $sdd"
            fi
        fi
    done <<< "$changes"

    printf '%s\n' "${sdds[@]}"
}

# =============================================================================
# Main
# =============================================================================

main() {
    local base_branch="main"
    local output_dir=""
    local dry_run=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --base-branch) base_branch="$2"; shift 2 ;;
            --output-dir)  output_dir="$2"; shift 2 ;;
            --dry-run)     dry_run=true; shift ;;
            -h|--help)
                echo "Usage: pipeline-self-review.sh --base-branch <branch> --output-dir <path>"
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                exit 2
                ;;
        esac
    done

    if [[ -z "$output_dir" ]]; then
        error "Output directory required (--output-dir)"
        exit 2
    fi

    # Detect pipeline changes
    local changes
    changes=$(detect_pipeline_changes "$base_branch")

    if [[ -z "$changes" ]]; then
        log "No pipeline changes detected"
        exit 0
    fi

    local change_count
    change_count=$(echo "$changes" | wc -l)
    log "Detected $change_count pipeline file(s) changed"

    # Resolve governing SDDs
    local sdds
    sdds=$(resolve_all_sdds "$changes")

    if [[ -z "$sdds" ]]; then
        log "No governing SDDs found for changed files"
        exit 0
    fi

    local sdd_count
    sdd_count=$(echo "$sdds" | wc -l)
    log "Resolved $sdd_count governing SDD(s)"

    if [[ "$dry_run" == true ]]; then
        log "Dry run — would review against:"
        echo "$sdds" | while IFS= read -r sdd; do
            log "  SDD: $sdd"
        done
        exit 0
    fi

    # Create output directory
    mkdir -p "$output_dir"

    # Generate pipeline-only diff
    local pipeline_diff
    pipeline_diff=$(git diff "$base_branch"...HEAD -- \
        '.claude/scripts/' \
        '.claude/skills/' \
        '.claude/data/' \
        '.claude/protocols/' \
        2>/dev/null || echo "")

    if [[ -z "$pipeline_diff" ]]; then
        log "Pipeline diff is empty"
        exit 0
    fi

    # Write pipeline diff to temp file for reuse
    local diff_file
    diff_file=$(mktemp)
    trap 'rm -f "$diff_file"' EXIT
    echo "$pipeline_diff" > "$diff_file"

    # Run Red Team code-vs-design against each governing SDD
    local total_findings=0
    local sdd_index=0

    while IFS= read -r sdd; do
        [[ -z "$sdd" ]] && continue
        sdd_index=$((sdd_index + 1))
        local sdd_label
        sdd_label=$(basename "$sdd" .md)
        local output_file="$output_dir/pipeline-self-review-${sdd_label}.json"

        log "[$sdd_index/$sdd_count] Reviewing against: $sdd"

        local exit_code=0
        "$RED_TEAM_SCRIPT" \
            --sdd "$PROJECT_ROOT/$sdd" \
            --diff "$diff_file" \
            --output "$output_file" \
            --sprint "pipeline-self-review" || exit_code=$?

        if [[ $exit_code -eq 0 && -f "$output_file" ]]; then
            local findings
            findings=$(jq -r '.summary.confirmed_divergence // 0' "$output_file" 2>/dev/null || echo "0")
            total_findings=$((total_findings + findings))
            log "  → $findings divergence finding(s)"
        elif [[ $exit_code -eq 3 ]]; then
            log "  → No security sections in SDD, skipped"
        else
            log "  → Red Team gate returned exit $exit_code"
        fi
    done <<< "$sdds"

    log "Pipeline self-review complete: $total_findings total divergence finding(s) across $sdd_count SDD(s)"

    # Write summary
    jq -n \
        --argjson total_findings "$total_findings" \
        --argjson sdd_count "$sdd_count" \
        --argjson change_count "$change_count" \
        '{
            type: "pipeline_self_review",
            pipeline_files_changed: $change_count,
            sdds_reviewed: $sdd_count,
            total_divergence_findings: $total_findings
        }' > "$output_dir/pipeline-self-review-summary.json"
}

main "$@"
