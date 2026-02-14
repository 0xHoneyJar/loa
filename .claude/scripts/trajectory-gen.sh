#!/usr/bin/env bash
# trajectory-gen.sh - Trajectory Narrative Generator
#
# Synthesizes the Sprint Ledger, memory system, Vision Registry, and Ground Truth
# into a concise prose narrative for session-start context loading.
#
# Usage:
#   trajectory-gen.sh             # Prose narrative to stdout (< 500 tokens)
#   trajectory-gen.sh --json      # Machine-readable JSON output
#   trajectory-gen.sh --condensed # Short narrative (< 200 tokens) for recovery hooks
#
# Exit codes:
#   0 - Success
#   1 - Invalid arguments

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source bootstrap for PROJECT_ROOT
if [[ -f "$SCRIPT_DIR/bootstrap.sh" ]]; then
    source "$SCRIPT_DIR/bootstrap.sh"
fi

PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"

# ─────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────

LEDGER_FILE="${PROJECT_ROOT}/grimoires/loa/ledger.json"
MEMORY_DIR="${PROJECT_ROOT}/grimoires/loa/memory"
OBSERVATIONS_FILE="${MEMORY_DIR}/observations.jsonl"
VISIONS_INDEX="${PROJECT_ROOT}/grimoires/loa/visions/index.md"
GT_INDEX="${PROJECT_ROOT}/grimoires/loa/ground-truth/index.md"

OUTPUT_MODE="prose"  # prose | json | condensed

# ─────────────────────────────────────────────────────────
# Argument Parsing
# ─────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
    case "$1" in
        --json) OUTPUT_MODE="json"; shift ;;
        --condensed) OUTPUT_MODE="condensed"; shift ;;
        -h|--help)
            echo "Usage: trajectory-gen.sh [--json | --condensed]"
            echo "  --json       Machine-readable JSON output"
            echo "  --condensed  Short narrative (< 200 tokens) for recovery hooks"
            exit 0
            ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

# ─────────────────────────────────────────────────────────
# Data Extraction
# ─────────────────────────────────────────────────────────

# Extract ledger data
extract_ledger() {
    if [[ ! -f "$LEDGER_FILE" ]]; then
        echo '{"total_cycles":0,"total_sprints":0,"active_cycle":"none","active_label":"No active cycle"}'
        return
    fi

    jq -r '.active_cycle as $ac | {
        total_cycles: (.cycles | length),
        archived_cycles: ([.cycles[] | select(.status == "archived")] | length),
        total_sprints: .global_sprint_counter,
        active_cycle: ($ac // "none"),
        active_label: ((.cycles[] | select(.id == $ac) | .label) // "No active cycle"),
        bugfix_count: (.bugfix_cycles | length),
        first_date: ((.cycles[0].created_at // "unknown") | split("T")[0]),
        latest_date: ((.cycles[-1].created_at // "unknown") | split("T")[0])
    }' "$LEDGER_FILE" 2>/dev/null || echo '{"total_cycles":0,"total_sprints":0,"active_cycle":"none","active_label":"No active cycle"}'
}

# Extract recent memory observations
extract_memory() {
    if [[ ! -f "$OBSERVATIONS_FILE" ]] || [[ ! -s "$OBSERVATIONS_FILE" ]]; then
        echo '[]'
        return
    fi

    # Get the most recent 5 observations, extract summary
    tail -5 "$OBSERVATIONS_FILE" | jq -s '[.[] | {type, summary}]' 2>/dev/null || echo '[]'
}

# Extract vision registry state
extract_visions() {
    if [[ ! -f "$VISIONS_INDEX" ]]; then
        echo '{"total":0,"captured":0,"exploring":0,"implemented":0}'
        return
    fi

    local total captured exploring implemented
    total=$(grep -c "^| vision-" "$VISIONS_INDEX" 2>/dev/null) || total=0
    captured=$(grep -c "| Captured |" "$VISIONS_INDEX" 2>/dev/null) || captured=0
    exploring=$(grep -c "| Exploring |" "$VISIONS_INDEX" 2>/dev/null) || exploring=0
    implemented=$(grep -c "| Implemented |" "$VISIONS_INDEX" 2>/dev/null) || implemented=0

    # Extract vision titles
    local titles
    titles=$(grep "^| vision-" "$VISIONS_INDEX" 2>/dev/null | sed 's/^| [^ ]* | \([^|]*\) |.*/\1/' | sed 's/^ *//;s/ *$//' | head -5)

    jq -n \
        --argjson total "$total" \
        --argjson captured "$captured" \
        --argjson exploring "$exploring" \
        --argjson implemented "$implemented" \
        --arg titles "$titles" \
        '{total:$total,captured:$captured,exploring:$exploring,implemented:$implemented,titles:($titles | split("\n"))}'
}

# ─────────────────────────────────────────────────────────
# Narrative Generation
# ─────────────────────────────────────────────────────────

generate_prose() {
    local ledger memory visions

    ledger=$(extract_ledger)
    memory=$(extract_memory)
    visions=$(extract_visions)

    local total_cycles archived active_cycle active_label total_sprints first_date
    total_cycles=$(echo "$ledger" | jq -r '.total_cycles')
    archived=$(echo "$ledger" | jq -r '.archived_cycles')
    active_cycle=$(echo "$ledger" | jq -r '.active_cycle')
    active_label=$(echo "$ledger" | jq -r '.active_label')
    total_sprints=$(echo "$ledger" | jq -r '.total_sprints')
    first_date=$(echo "$ledger" | jq -r '.first_date')

    local vision_total vision_captured
    vision_total=$(echo "$visions" | jq -r '.total')
    vision_captured=$(echo "$visions" | jq -r '.captured')

    local cycle_num
    cycle_num=$(echo "$active_cycle" | sed 's/cycle-0*//')

    # Build narrative
    echo "## Trajectory"
    echo ""

    if [[ "$total_cycles" -gt 0 ]]; then
        echo "This is cycle ${cycle_num} of the Loa framework. Across ${archived} prior cycles and ${total_sprints} sprints since ${first_date}, the codebase has evolved through iterative bridge loops with adversarial review, persona-driven identity, and autonomous convergence."
    else
        echo "This is the beginning. No prior cycles recorded."
    fi

    echo ""
    echo "**Current frontier**: ${active_label}"

    # Memory section
    local memory_count
    memory_count=$(echo "$memory" | jq 'length')
    if [[ "$memory_count" -gt 0 ]]; then
        echo ""
        echo "**Recent learnings**:"
        echo "$memory" | jq -r '.[] | "- [\(.type)] \(.summary)"' 2>/dev/null
    fi

    # Visions section
    if [[ "$vision_total" -gt 0 ]]; then
        echo ""
        echo "**Open visions** (${vision_captured} captured, ${vision_total} total):"
        echo "$visions" | jq -r '.titles[] | select(length > 0) | "- \(.)"' 2>/dev/null
    fi
}

generate_condensed() {
    local ledger visions

    ledger=$(extract_ledger)
    visions=$(extract_visions)

    local cycle_num total_sprints active_label vision_total
    cycle_num=$(echo "$ledger" | jq -r '.active_cycle' | sed 's/cycle-0*//')
    total_sprints=$(echo "$ledger" | jq -r '.total_sprints')
    active_label=$(echo "$ledger" | jq -r '.active_label')
    vision_total=$(echo "$visions" | jq -r '.total')

    echo "Trajectory: Cycle ${cycle_num}, ${total_sprints} sprints completed. Current: ${active_label}. ${vision_total} open visions."
}

generate_json() {
    local ledger memory visions

    ledger=$(extract_ledger)
    memory=$(extract_memory)
    visions=$(extract_visions)

    jq -n \
        --argjson ledger "$ledger" \
        --argjson memory "$memory" \
        --argjson visions "$visions" \
        --arg generated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{
            generated_at: $generated_at,
            ledger: $ledger,
            recent_memory: $memory,
            visions: $visions
        }'
}

# ─────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────

case "$OUTPUT_MODE" in
    prose) generate_prose ;;
    condensed) generate_condensed ;;
    json) generate_json ;;
esac
