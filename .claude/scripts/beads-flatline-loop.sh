#!/usr/bin/env bash
# beads-flatline-loop.sh - Iterative multi-model refinement of task graph
#
# Implements the "Check your beads N times, implement once" pattern.
# Runs Flatline Protocol review on beads repeatedly until improvements plateau.
#
# Usage:
#   beads-flatline-loop.sh [OPTIONS]
#
# Options:
#   --max-iterations N    Maximum iterations (default: 6)
#   --threshold N         Flatline threshold % (default: 5)
#   --dry-run             Show what would happen without changes
#   --verbose             Show detailed output
#
# Requires: beads_rust (br), jq
#
# Exit codes:
#   0 - Success (flatline detected or max iterations reached)
#   1 - Error (br not found, etc.)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source bootstrap if available
if [[ -f "$SCRIPT_DIR/bootstrap.sh" ]]; then
    source "$SCRIPT_DIR/bootstrap.sh"
fi

# =============================================================================
# Configuration
# =============================================================================

# Hard limit to prevent resource exhaustion (H3 security fix)
MAX_ITERATION_LIMIT=20

MAX_ITERATIONS="${BLF_MAX_ITERATIONS:-6}"
FLATLINE_THRESHOLD="${BLF_FLATLINE_THRESHOLD:-5}"
DRY_RUN=false
VERBOSE=false

# Temp file tracking for cleanup
TEMP_FILES_TO_CLEAN=()

# =============================================================================
# Cleanup trap for temp files (H5 security fix)
# =============================================================================

cleanup_temp_files() {
    for f in "${TEMP_FILES_TO_CLEAN[@]}"; do
        rm -f "$f" 2>/dev/null || true
    done
}

trap cleanup_temp_files EXIT INT TERM

# =============================================================================
# Argument Parsing
# =============================================================================

while [[ $# -gt 0 ]]; do
    case "$1" in
        --max-iterations)
            MAX_ITERATIONS="$2"
            # Validate numeric and enforce hard limit (H3, L7 security fix)
            if ! [[ "$MAX_ITERATIONS" =~ ^[0-9]+$ ]]; then
                echo "Error: --max-iterations must be a positive integer" >&2
                exit 1
            fi
            if [[ $MAX_ITERATIONS -gt $MAX_ITERATION_LIMIT ]]; then
                echo "Warning: MAX_ITERATIONS capped at $MAX_ITERATION_LIMIT (was $MAX_ITERATIONS)" >&2
                MAX_ITERATIONS=$MAX_ITERATION_LIMIT
            fi
            shift 2
            ;;
        --threshold)
            FLATLINE_THRESHOLD="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --help|-h)
            echo "Usage: beads-flatline-loop.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --max-iterations N  Maximum iterations (default: 6)"
            echo "  --threshold N       Flatline threshold % (default: 5)"
            echo "  --dry-run           Show what would happen"
            echo "  --verbose           Show detailed output"
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# =============================================================================
# Utilities
# =============================================================================

log() {
    echo "[BLF] $*"
}

log_verbose() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo "[BLF] $*"
    fi
}

# Count current beads
count_beads() {
    if command -v br &>/dev/null; then
        br list --json 2>/dev/null | jq 'length' 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

# Get bead structure hash for change detection
get_bead_hash() {
    if command -v br &>/dev/null; then
        br list --json 2>/dev/null | jq -S '.' 2>/dev/null | sha256sum | cut -d' ' -f1
    else
        echo "none"
    fi
}

# Get bead summary for Flatline review
get_bead_summary() {
    if command -v br &>/dev/null; then
        br list --json 2>/dev/null | jq -r '.[] | "- [\(.id)] \(.title) (priority: \(.priority // "unset"), status: \(.status // "open"))"' 2>/dev/null
    else
        echo "No beads found"
    fi
}

# =============================================================================
# Flatline Review
# =============================================================================

run_flatline_review() {
    local iteration="$1"
    local beads_json="$2"

    log "Running Flatline review (iteration $iteration)..."

    # Check if flatline-orchestrator exists
    if [[ ! -f "$SCRIPT_DIR/flatline-orchestrator.sh" ]]; then
        log_verbose "Flatline orchestrator not found, skipping review"
        return 0
    fi

    # Create temp file with beads for review (tracked for cleanup on interrupt - H5)
    local temp_file
    temp_file=$(mktemp)
    chmod 600 "$temp_file"  # SEC-AUDIT SHELL-HIGH-01
    TEMP_FILES_TO_CLEAN+=("$temp_file")
    echo "$beads_json" > "$temp_file"

    # Run Flatline review
    local result
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would run: flatline-orchestrator.sh --doc $temp_file --phase beads"
        result="{}"
    else
        result=$("$SCRIPT_DIR/flatline-orchestrator.sh" \
            --doc "$temp_file" \
            --phase beads \
            --context "task_graph_review" \
            --json 2>/dev/null) || result="{}"
    fi

    rm -f "$temp_file"

    # Extract findings count
    local high_consensus disputed blockers
    high_consensus=$(echo "$result" | jq -r '.metrics.high_consensus // 0' 2>/dev/null) || high_consensus=0
    disputed=$(echo "$result" | jq -r '.metrics.disputed // 0' 2>/dev/null) || disputed=0
    blockers=$(echo "$result" | jq -r '.metrics.blockers // 0' 2>/dev/null) || blockers=0

    log_verbose "  HIGH_CONSENSUS: $high_consensus, DISPUTED: $disputed, BLOCKERS: $blockers"

    echo "$result"
}

# Apply Flatline suggestions to beads
# NOTE: Phase 2 stub - currently logs suggestions but does not modify beads.
# Actual bead modifications (br edit, br split, etc.) will be implemented in a future release.
# See: https://github.com/0xHoneyJar/loa/issues/TBD
apply_flatline_suggestions() {
    local findings="$1"

    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would apply Flatline suggestions"
        return 0
    fi

    # Extract high consensus findings
    local suggestions
    suggestions=$(echo "$findings" | jq -r '.findings[]? | select(.consensus == "high") | .suggestion // empty' 2>/dev/null) || true

    if [[ -z "$suggestions" ]]; then
        log_verbose "  No high-consensus suggestions to apply"
        return 0
    fi

    # PHASE 2 STUB: Log suggestions for manual review
    # In Phase 2, this will parse suggestions and call br commands:
    # - "split task" -> br split <id>
    # - "merge tasks" -> br merge <id1> <id2>
    # - "reprioritize" -> br update <id> --priority <P>
    # - "add dependency" -> br link <id1> --blocks <id2>
    local logged=0
    log "  [PHASE 2 STUB] High-consensus suggestions logged for manual review:"
    while IFS= read -r suggestion; do
        [[ -z "$suggestion" ]] && continue
        log "    → $suggestion"
        ((logged++)) || true
    done <<< "$suggestions"

    log_verbose "  Logged $logged suggestions (manual application required in Phase 1)"
}

# =============================================================================
# Main Loop
# =============================================================================

main() {
    log "════════════════════════════════════════════════════════════"
    log "         FLATLINE BEADS LOOP"
    log "════════════════════════════════════════════════════════════"
    log ""
    # Enforce hard iteration limit from environment variable too (H3)
    if ! [[ "$MAX_ITERATIONS" =~ ^[0-9]+$ ]]; then
        log "ERROR: MAX_ITERATIONS must be a positive integer (got: $MAX_ITERATIONS)"
        exit 1
    fi
    if [[ $MAX_ITERATIONS -gt $MAX_ITERATION_LIMIT ]]; then
        log "Warning: MAX_ITERATIONS capped at $MAX_ITERATION_LIMIT (was $MAX_ITERATIONS)"
        MAX_ITERATIONS=$MAX_ITERATION_LIMIT
    fi

    log "Max iterations: $MAX_ITERATIONS (hard limit: $MAX_ITERATION_LIMIT)"
    log "Flatline threshold: <${FLATLINE_THRESHOLD}% change"
    log ""

    # Check for beads_rust
    if ! command -v br &>/dev/null; then
        log "WARNING: beads_rust (br) not found"
        log "Install from: https://github.com/Dicklesworthstone/beads_rust"
        log ""
        log "Proceeding without beads integration..."
        exit 0
    fi

    # Get initial state
    local initial_count=$(count_beads)
    log "Initial bead count: $initial_count"

    if [[ "$initial_count" == "0" ]]; then
        log "No beads found. Create beads first with 'br create'."
        exit 0
    fi

    local prev_hash=$(get_bead_hash)
    local iteration=1
    local consecutive_low_change=0

    while [[ $iteration -le $MAX_ITERATIONS ]]; do
        log ""
        log "═══════════════════════════════════════════════════════════"
        log " ITERATION $iteration / $MAX_ITERATIONS"
        log "═══════════════════════════════════════════════════════════"

        # Get current beads
        local beads_json
        beads_json=$(br list --json 2>/dev/null) || beads_json="[]"

        # Run Flatline review
        local findings
        findings=$(run_flatline_review "$iteration" "$beads_json")

        # Apply suggestions
        apply_flatline_suggestions "$findings"

        # Calculate change
        local new_hash=$(get_bead_hash)
        local change_pct=0

        if [[ "$prev_hash" != "$new_hash" ]]; then
            # Estimate change by comparing structure
            local new_count=$(count_beads)
            local diff=$((new_count - initial_count))
            if [[ $initial_count -gt 0 ]]; then
                change_pct=$(( (${diff#-} * 100) / initial_count ))
            fi
        fi

        log ""
        log "Change: ${change_pct}%"

        # Check for flatline
        if [[ $change_pct -lt $FLATLINE_THRESHOLD ]]; then
            ((consecutive_low_change++)) || true
            log "Low change detected ($consecutive_low_change consecutive)"

            if [[ $consecutive_low_change -ge 2 ]]; then
                log ""
                log "════════════════════════════════════════════════════════════"
                log " FLATLINE DETECTED"
                log "════════════════════════════════════════════════════════════"
                log ""
                log "Task graph has stabilized. Ready for implementation."
                break
            fi
        else
            consecutive_low_change=0
        fi

        prev_hash="$new_hash"
        ((iteration++)) || true
    done

    if [[ $iteration -gt $MAX_ITERATIONS ]]; then
        log ""
        log "Max iterations reached. Consider running more iterations if still improving."
    fi

    # Final sync
    log ""
    log "Final bead count: $(count_beads)"
    log "Iterations completed: $((iteration > MAX_ITERATIONS ? MAX_ITERATIONS : iteration))"

    if [[ "$DRY_RUN" != "true" ]] && command -v br &>/dev/null; then
        log ""
        log "Syncing beads to git..."
        br sync --flush-only 2>/dev/null || log "Note: br sync failed (may not be initialized)"
    fi

    log ""
    log "════════════════════════════════════════════════════════════"
    log " BEADS FLATLINE LOOP COMPLETE"
    log "════════════════════════════════════════════════════════════"
}

main "$@"
