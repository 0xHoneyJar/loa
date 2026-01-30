#!/usr/bin/env bash
# synthesis-checkpoint.sh - Pre-clear validation script
#
# Part of Loa Framework v0.9.0 Lossless Ledger Protocol
#
# Usage:
#   ./synthesis-checkpoint.sh [agent] [date]
#
# Arguments:
#   agent - Agent name (default: implementing-tasks)
#   date  - Date to check (default: today, format: YYYY-MM-DD)
#
# Exit Codes:
#   0 - All checks passed, /clear permitted
#   1 - Blocking check failed, /clear blocked
#   2 - Error in checkpoint script
#
# Configuration:
#   Reads from .loa.config.yaml if available

set -euo pipefail

# Configuration
PROJECT_ROOT="${PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
AGENT="${1:-implementing-tasks}"
DATE="${2:-$(date +%Y-%m-%d)}"
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

TRAJECTORY_DIR="${PROJECT_ROOT}/grimoires/loa/a2a/trajectory"
TRAJECTORY="${TRAJECTORY_DIR}/${AGENT}-${DATE}.jsonl"
NOTES_FILE="${PROJECT_ROOT}/grimoires/loa/NOTES.md"
CONFIG_FILE="${PROJECT_ROOT}/.loa.config.yaml"
SCRIPTS_DIR="${PROJECT_ROOT}/.claude/scripts"

# Default configuration
GROUNDING_THRESHOLD="0.95"
ENFORCEMENT_LEVEL="warn"  # strict | warn | disabled
NEGATIVE_GROUNDING_ENABLED="true"
EDD_MIN_SCENARIOS="3"

# Load configuration from .loa.config.yaml if available
load_config() {
    if [[ -f "$CONFIG_FILE" ]] && command -v yq &>/dev/null; then
        GROUNDING_THRESHOLD=$(yq -r '.grounding.threshold // .synthesis_checkpoint.grounding_threshold // "0.95"' "$CONFIG_FILE" 2>/dev/null || echo "0.95")
        ENFORCEMENT_LEVEL=$(yq -r '.grounding_enforcement // "warn"' "$CONFIG_FILE" 2>/dev/null || echo "warn")
        NEGATIVE_GROUNDING_ENABLED=$(yq -r '.grounding.negative.enabled // "true"' "$CONFIG_FILE" 2>/dev/null || echo "true")
        EDD_MIN_SCENARIOS=$(yq -r '.synthesis_checkpoint.edd.min_test_scenarios // "3"' "$CONFIG_FILE" 2>/dev/null || echo "3")
    fi
}

# Print header
print_header() {
    echo "=============================================="
    echo "        SYNTHESIS CHECKPOINT"
    echo "=============================================="
    echo "Agent: $AGENT"
    echo "Date: $DATE"
    echo "Enforcement: $ENFORCEMENT_LEVEL"
    echo "----------------------------------------------"
}

# Step 1: Grounding Verification
check_grounding() {
    echo ""
    echo "Step 1: Grounding Verification"
    echo "----------------------------------------------"

    if [[ "$ENFORCEMENT_LEVEL" == "disabled" ]]; then
        echo "  Status: SKIPPED (enforcement disabled)"
        return 0
    fi

    # Run grounding check script
    if [[ ! -x "${SCRIPTS_DIR}/grounding-check.sh" ]]; then
        echo "  ERROR: grounding-check.sh not found or not executable"
        return 2
    fi

    local result
    result=$("${SCRIPTS_DIR}/grounding-check.sh" "$AGENT" "$GROUNDING_THRESHOLD" "$DATE" 2>&1) || true

    # Parse result
    local ratio status total_claims
    ratio=$(echo "$result" | grep "grounding_ratio=" | cut -d= -f2 || echo "1.00")
    status=$(echo "$result" | grep "status=" | cut -d= -f2 || echo "pass")
    total_claims=$(echo "$result" | grep "total_claims=" | cut -d= -f2 || echo "0")

    echo "  Total claims: $total_claims"
    echo "  Grounding ratio: $ratio"
    echo "  Threshold: $GROUNDING_THRESHOLD"

    if [[ "$status" == "fail" ]]; then
        echo "  Status: FAILED"
        echo ""
        echo "  Ungrounded claims require evidence:"
        echo "$result" | grep -A100 "ungrounded_claims:" | head -15 || true

        if [[ "$ENFORCEMENT_LEVEL" == "strict" ]]; then
            echo ""
            echo "  ACTION REQUIRED:"
            echo "    - Add word-for-word code citations"
            echo "    - Or mark as [ASSUMPTION]"
            echo "    - Then retry /clear"
            return 1
        else
            echo ""
            echo "  WARNING: Grounding ratio below threshold (warn mode)"
            return 0
        fi
    else
        echo "  Status: PASSED"
        return 0
    fi
}

# Step 2: Negative Grounding (Ghost Features)
check_negative_grounding() {
    echo ""
    echo "Step 2: Negative Grounding (Ghost Features)"
    echo "----------------------------------------------"

    if [[ "$NEGATIVE_GROUNDING_ENABLED" != "true" ]]; then
        echo "  Status: SKIPPED (disabled)"
        return 0
    fi

    if [[ ! -f "$TRAJECTORY" ]]; then
        echo "  Status: SKIPPED (no trajectory file)"
        return 0
    fi

    # Count unverified ghost features
    local unverified high_ambiguity
    unverified=$(grep -c '"status":"unverified"' "$TRAJECTORY" 2>/dev/null || echo "0")
    high_ambiguity=$(grep -c '"status":"high_ambiguity"' "$TRAJECTORY" 2>/dev/null || echo "0")

    echo "  Unverified ghosts: $unverified"
    echo "  High ambiguity: $high_ambiguity"

    if [[ "$unverified" -gt 0 ]] || [[ "$high_ambiguity" -gt 0 ]]; then
        echo "  Status: ISSUES FOUND"

        if [[ "$ENFORCEMENT_LEVEL" == "strict" ]]; then
            echo ""
            echo "  Ghost Features requiring verification:"
            grep -E '"status":"(unverified|high_ambiguity)"' "$TRAJECTORY" 2>/dev/null | \
                jq -r '.claim // "Unknown claim"' 2>/dev/null | \
                head -5 | while read -r claim; do
                    echo "    - $claim"
                done

            echo ""
            echo "  ACTION REQUIRED:"
            echo "    - Run second diverse query for each ghost"
            echo "    - Or request human audit"
            return 1
        else
            echo "  WARNING: Unverified ghost features (warn mode)"
            return 0
        fi
    else
        echo "  Status: PASSED"
        return 0
    fi
}

# Step 3: Update Decision Log (NON-BLOCKING)
update_decision_log() {
    echo ""
    echo "Step 3: Update Decision Log"
    echo "----------------------------------------------"

    if [[ ! -f "$TRAJECTORY" ]]; then
        echo "  Status: SKIPPED (no trajectory file)"
        return 0
    fi

    # Count decisions to sync
    local decision_count
    decision_count=$(grep -c '"phase":"cite"' "$TRAJECTORY" 2>/dev/null || echo "0")

    if [[ "$decision_count" -eq 0 ]]; then
        echo "  Status: SKIPPED (no decisions to sync)"
        return 0
    fi

    echo "  Decisions to sync: $decision_count"

    # Append session summary to NOTES.md if it exists
    if [[ -f "$NOTES_FILE" ]]; then
        # Log that we would update (actual update done by agent)
        echo "  Status: READY (agent will update NOTES.md)"
    else
        echo "  Status: SKIPPED (NOTES.md not found)"
    fi

    return 0
}

# Step 4: Update Bead (NON-BLOCKING)
update_bead() {
    echo ""
    echo "Step 4: Update Bead"
    echo "----------------------------------------------"

    if ! command -v br &>/dev/null; then
        echo "  Status: SKIPPED (beads not available)"
        return 0
    fi

    # Check for active bead
    local active_bead
    active_bead=$(br list --status=in_progress --json 2>/dev/null | jq -r '.[0].id // empty' 2>/dev/null || echo "")

    if [[ -z "$active_bead" ]]; then
        echo "  Status: SKIPPED (no active bead)"
        return 0
    fi

    echo "  Active bead: $active_bead"
    echo "  Status: READY (agent will update bead)"

    return 0
}

# Step 5: Log Session Handoff (NON-BLOCKING)
log_session_handoff() {
    echo ""
    echo "Step 5: Log Session Handoff"
    echo "----------------------------------------------"

    # Ensure trajectory directory exists
    mkdir -p "$TRAJECTORY_DIR"

    # Get grounding ratio from earlier check
    local ratio="1.00"
    if [[ -f "$TRAJECTORY" ]]; then
        local result
        result=$("${SCRIPTS_DIR}/grounding-check.sh" "$AGENT" "$GROUNDING_THRESHOLD" "$DATE" 2>&1) || true
        ratio=$(echo "$result" | grep "grounding_ratio=" | cut -d= -f2 || echo "1.00")
    fi

    # Log handoff entry
    local handoff_entry
    handoff_entry=$(jq -n \
        --arg ts "$TIMESTAMP" \
        --arg phase "session_handoff" \
        --arg agent "$AGENT" \
        --arg ratio "$ratio" \
        '{timestamp: $ts, phase: $phase, agent: $agent, grounding_ratio: ($ratio | tonumber), checkpoint_status: "complete"}')

    echo "$handoff_entry" >> "$TRAJECTORY"

    echo "  Trajectory: $TRAJECTORY"
    echo "  Grounding ratio: $ratio"
    echo "  Status: LOGGED"

    return 0
}

# Step 6: Decay Raw Output (NON-BLOCKING)
decay_raw_output() {
    echo ""
    echo "Step 6: Decay Raw Output"
    echo "----------------------------------------------"

    # This step is advisory - actual decay happens in agent context
    echo "  Status: ADVISORY"
    echo "  Note: Agent should convert code blocks to lightweight identifiers"

    return 0
}

# Step 7: Verify EDD (NON-BLOCKING)
verify_edd() {
    echo ""
    echo "Step 7: Verify EDD (Evidence-Driven Development)"
    echo "----------------------------------------------"

    if [[ ! -f "$TRAJECTORY" ]]; then
        echo "  Status: SKIPPED (no trajectory file)"
        return 0
    fi

    # Count test scenarios
    local test_scenarios
    test_scenarios=$(grep -c '"type":"test_scenario"' "$TRAJECTORY" 2>/dev/null || echo "0")

    echo "  Test scenarios documented: $test_scenarios"
    echo "  Minimum required: $EDD_MIN_SCENARIOS"

    if [[ "$test_scenarios" -lt "$EDD_MIN_SCENARIOS" ]]; then
        echo "  Status: WARNING (below minimum)"
        echo "  Note: Document test scenarios for better quality"
    else
        echo "  Status: PASSED"
    fi

    return 0
}

# Print final result
print_result() {
    local exit_code=$1

    echo ""
    echo "=============================================="

    if [[ "$exit_code" -eq 0 ]]; then
        echo "  SYNTHESIS CHECKPOINT: PASSED"
        echo "  /clear is permitted"
    else
        echo "  SYNTHESIS CHECKPOINT: FAILED"
        echo "  /clear is BLOCKED"
        echo ""
        echo "  Resolve the issues above and retry."
    fi

    echo "=============================================="
}

# Main execution
main() {
    local exit_code=0

    # Load configuration
    load_config

    # Print header
    print_header

    # Run blocking checks first
    check_grounding || exit_code=1

    if [[ "$exit_code" -eq 0 ]]; then
        check_negative_grounding || exit_code=1
    fi

    # Run non-blocking checks (always run, don't affect exit code)
    update_decision_log || true
    update_bead || true
    log_session_handoff || true
    decay_raw_output || true
    verify_edd || true

    # Print final result
    print_result "$exit_code"

    exit "$exit_code"
}

# Run main
main
