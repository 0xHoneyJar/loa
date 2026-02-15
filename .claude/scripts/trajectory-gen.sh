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

# Extract recent memory observations (with freshness timestamp)
extract_memory() {
    if [[ ! -f "$OBSERVATIONS_FILE" ]] || [[ ! -s "$OBSERVATIONS_FILE" ]]; then
        echo '{"observations":[],"latest_timestamp":null}'
        return
    fi

    # Get the most recent 5 observations, extract summary + latest timestamp
    local obs latest_ts
    obs=$(tail -5 "$OBSERVATIONS_FILE" | jq -s '[.[] | {type, summary}]' 2>/dev/null || echo '[]')
    latest_ts=$(tail -1 "$OBSERVATIONS_FILE" | jq -r '.timestamp // empty' 2>/dev/null || true)

    jq -n --argjson obs "$obs" --arg ts "${latest_ts:-}" \
        '{observations: $obs, latest_timestamp: (if $ts == "" then null else $ts end)}'
}

# Extract vision registry state
extract_visions() {
    if [[ ! -f "$VISIONS_INDEX" ]]; then
        echo '{"total":0,"captured":0,"exploring":0,"implemented":0}'
        return
    fi

    local total captured exploring implemented
    # NOTE: grep -c exits with code 1 when zero matches are found (not an error —
    # it's grep's way of saying "no matches"). The `|| var=0` fallback handles this
    # by assigning 0 on exit code 1. Without the fallback, `set -e` would terminate
    # the script on a legitimate zero-match result.
    total=$(grep -c "^| vision-" "$VISIONS_INDEX" 2>/dev/null) || total=0
    captured=$(grep -c "| Captured |" "$VISIONS_INDEX" 2>/dev/null) || captured=0
    exploring=$(grep -c "| Exploring |" "$VISIONS_INDEX" 2>/dev/null) || exploring=0
    implemented=$(grep -c "| Implemented |" "$VISIONS_INDEX" 2>/dev/null) || implemented=0

    # Extract vision titles
    local titles
    titles=$(grep "^| vision-" "$VISIONS_INDEX" 2>/dev/null | sed 's/^| [^ ]* | \([^|]*\) |.*/\1/' | sed 's/^ *//;s/ *$//' | head -5)

    # Get modification time of the index as freshness proxy
    local visions_mtime=""
    if [[ -f "$VISIONS_INDEX" ]]; then
        visions_mtime=$(date -r "$VISIONS_INDEX" -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || stat -c %Y "$VISIONS_INDEX" 2>/dev/null || true)
    fi

    jq -n \
        --argjson total "$total" \
        --argjson captured "$captured" \
        --argjson exploring "$exploring" \
        --argjson implemented "$implemented" \
        --arg titles "$titles" \
        --arg last_updated "${visions_mtime:-}" \
        '{total:$total,captured:$captured,exploring:$exploring,implemented:$implemented,titles:($titles | split("\n")),last_updated:(if $last_updated == "" then null else $last_updated end)}'
}

# ─────────────────────────────────────────────────────────
# Freshness Helpers
# ─────────────────────────────────────────────────────────

# Compute human-readable age from an ISO timestamp.
# Returns: "2h ago", "3d ago", "stale (14d)" etc. Empty string if input is empty/null.
compute_age_label() {
    local ts="$1"
    if [[ -z "$ts" || "$ts" == "null" ]]; then
        echo ""
        return
    fi

    local ts_epoch now_epoch diff_seconds
    ts_epoch=$(date -d "$ts" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$ts" +%s 2>/dev/null || echo "0")
    now_epoch=$(date +%s)
    diff_seconds=$((now_epoch - ts_epoch))

    if [[ "$ts_epoch" -eq 0 || "$diff_seconds" -lt 0 ]]; then
        echo ""
        return
    fi

    local hours=$((diff_seconds / 3600))
    local days=$((diff_seconds / 86400))

    if [[ $hours -lt 1 ]]; then
        echo "<1h ago"
    elif [[ $hours -lt 24 ]]; then
        echo "${hours}h ago"
    elif [[ $days -lt 7 ]]; then
        echo "${days}d ago"
    else
        echo "stale (${days}d)"
    fi
}

# Check if a timestamp is older than N days. Returns 0 (true) or 1 (false).
is_stale() {
    local ts="$1"
    local threshold_days="${2:-7}"
    if [[ -z "$ts" || "$ts" == "null" ]]; then
        return 1  # Unknown is not "stale" — it's absent
    fi
    local ts_epoch now_epoch diff_days
    ts_epoch=$(date -d "$ts" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$ts" +%s 2>/dev/null || echo "0")
    now_epoch=$(date +%s)
    diff_days=$(( (now_epoch - ts_epoch) / 86400 ))
    [[ $diff_days -ge $threshold_days ]]
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

    # Memory section (with freshness)
    local memory_count memory_ts memory_age
    memory_count=$(echo "$memory" | jq '.observations | length')
    memory_ts=$(echo "$memory" | jq -r '.latest_timestamp // empty')
    memory_age=$(compute_age_label "$memory_ts")
    if [[ "$memory_count" -gt 0 ]]; then
        echo ""
        local memory_header="**Recent learnings**"
        if [[ -n "$memory_age" ]]; then
            memory_header="**Recent learnings** (${memory_age})"
        fi
        echo "${memory_header}:"
        echo "$memory" | jq -r '.observations[] | "- [\(.type)] \(.summary)"' 2>/dev/null
    fi

    # Visions section (with freshness)
    local vision_last_updated vision_age
    vision_last_updated=$(echo "$visions" | jq -r '.last_updated // empty')
    vision_age=$(compute_age_label "$vision_last_updated")
    if [[ "$vision_total" -gt 0 ]]; then
        echo ""
        local vision_header="**Open visions** (${vision_captured} captured, ${vision_total} total)"
        if [[ -n "$vision_age" ]]; then
            vision_header="**Open visions** (${vision_captured} captured, ${vision_total} total, ${vision_age})"
        fi
        echo "${vision_header}:"
        echo "$visions" | jq -r '.titles[] | select(length > 0) | "- \(.)"' 2>/dev/null
    fi
}

generate_condensed() {
    local ledger memory visions

    ledger=$(extract_ledger)
    memory=$(extract_memory)
    visions=$(extract_visions)

    local cycle_num total_sprints active_label vision_total
    cycle_num=$(echo "$ledger" | jq -r '.active_cycle' | sed 's/cycle-0*//')
    total_sprints=$(echo "$ledger" | jq -r '.total_sprints')
    active_label=$(echo "$ledger" | jq -r '.active_label')
    vision_total=$(echo "$visions" | jq -r '.total')

    # Check for stale sources (> 7 days old) — append warning if any
    local stale_sources=""
    local memory_ts vision_ts ledger_ts
    memory_ts=$(echo "$memory" | jq -r '.latest_timestamp // empty')
    vision_ts=$(echo "$visions" | jq -r '.last_updated // empty')
    ledger_ts=$(echo "$ledger" | jq -r '.latest_date // empty')
    if [[ -n "$ledger_ts" && "$ledger_ts" != "unknown" ]]; then
        ledger_ts="${ledger_ts}T00:00:00Z"
    fi

    if is_stale "$memory_ts" 7 2>/dev/null; then stale_sources="${stale_sources}memory,"; fi
    if is_stale "$vision_ts" 7 2>/dev/null; then stale_sources="${stale_sources}visions,"; fi
    if is_stale "$ledger_ts" 7 2>/dev/null; then stale_sources="${stale_sources}ledger,"; fi
    stale_sources="${stale_sources%,}"  # trim trailing comma

    local output="Trajectory: Cycle ${cycle_num}, ${total_sprints} sprints completed. Current: ${active_label}. ${vision_total} open visions."
    if [[ -n "$stale_sources" ]]; then
        output="${output} (stale: ${stale_sources})"
    fi
    echo "$output"
}

generate_json() {
    local ledger memory visions

    ledger=$(extract_ledger)
    memory=$(extract_memory)
    visions=$(extract_visions)

    # Compute freshness metadata
    local memory_ts vision_ts ledger_mtime
    memory_ts=$(echo "$memory" | jq -r '.latest_timestamp // empty')
    vision_ts=$(echo "$visions" | jq -r '.last_updated // empty')
    if [[ -f "$LEDGER_FILE" ]]; then
        ledger_mtime=$(date -r "$LEDGER_FILE" -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)
    fi

    jq -n \
        --argjson ledger "$ledger" \
        --argjson memory_obs "$(echo "$memory" | jq '.observations')" \
        --argjson visions "$visions" \
        --arg generated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg memory_last "${memory_ts:-}" \
        --arg visions_last "${vision_ts:-}" \
        --arg ledger_last "${ledger_mtime:-}" \
        '{
            generated_at: $generated_at,
            ledger: $ledger,
            recent_memory: $memory_obs,
            visions: $visions,
            freshness: {
                memory_last_updated: (if $memory_last == "" then null else $memory_last end),
                visions_last_updated: (if $visions_last == "" then null else $visions_last end),
                ledger_last_modified: (if $ledger_last == "" then null else $ledger_last end)
            }
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
