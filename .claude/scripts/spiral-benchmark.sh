#!/usr/bin/env bash
# =============================================================================
# spiral-benchmark.sh — Flight Recorder Comparison Tool
# =============================================================================
# Version: 1.0.0
# Part of: Spiral Cost Optimization (cycle-072)
#
# Compares two flight recorder JSONL files and produces a Markdown comparison
# table. Handles missing data gracefully (e.g., raw-Claude runs with no
# flight recorder produce "N/A" for all dimensions).
#
# Usage:
#   spiral-benchmark.sh --a .run/cycles/run-A/flight-recorder.jsonl \
#                       --b .run/cycles/run-B/flight-recorder.jsonl \
#                       [--label-a "Sonnet"] [--label-b "Opus"]
#
# Output: Markdown comparison to stdout
# =============================================================================

set -euo pipefail

# =============================================================================
# Arguments
# =============================================================================

FILE_A=""
FILE_B=""
LABEL_A="Run A"
LABEL_B="Run B"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --a) FILE_A="$2"; shift 2 ;;
        --b) FILE_B="$2"; shift 2 ;;
        --label-a) LABEL_A="$2"; shift 2 ;;
        --label-b) LABEL_B="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: spiral-benchmark.sh --a <recorder.jsonl> --b <recorder.jsonl> [--label-a X] [--label-b Y]"
            exit 0
            ;;
        *) echo "ERROR: Unknown option: $1" >&2; exit 2 ;;
    esac
done

[[ -z "$FILE_A" || -z "$FILE_B" ]] && { echo "ERROR: --a and --b required" >&2; exit 2; }

# =============================================================================
# Helpers
# =============================================================================

_extract_metric() {
    local file="$1" jq_expr="$2" default="${3:-N/A}"
    [[ ! -f "$file" ]] && { echo "$default"; return; }
    jq -s "$jq_expr" "$file" 2>/dev/null || echo "$default"
}

_extract_phases() {
    local file="$1"
    [[ ! -f "$file" ]] && { echo "N/A"; return; }
    jq -s '[.[] | select(.action == "invoke")] | length' "$file" 2>/dev/null || echo "N/A"
}

_extract_total_cost() {
    local file="$1"
    [[ ! -f "$file" ]] && { echo "N/A"; return; }
    jq -s '[.[].cost_usd // 0] | add // 0' "$file" 2>/dev/null || echo "N/A"
}

_extract_total_duration() {
    local file="$1"
    [[ ! -f "$file" ]] && { echo "N/A"; return; }
    jq -s '[.[].duration_ms // 0] | add // 0 | . / 1000 | floor' "$file" 2>/dev/null || echo "N/A"
}

_extract_verdict() {
    local file="$1" phase="$2"
    [[ ! -f "$file" ]] && { echo "N/A"; return; }
    jq -rs "[.[] | select(.phase == \"GATE_${phase}\") | .verdict // \"N/A\"] | last // \"N/A\"" "$file" 2>/dev/null || echo "N/A"
}

_extract_profile() {
    local file="$1"
    [[ ! -f "$file" ]] && { echo "N/A"; return; }
    jq -rs '[.[] | select(.phase == "CONFIG" and .action == "profile") | .verdict] | last // "N/A"' "$file" 2>/dev/null || echo "N/A"
}

_extract_failures() {
    local file="$1"
    [[ ! -f "$file" ]] && { echo "N/A"; return; }
    jq -s '[.[] | select(.action == "FAILED")] | length' "$file" 2>/dev/null || echo "N/A"
}

_extract_flatline() {
    local file="$1" phase="$2"
    [[ ! -f "$file" ]] && { echo "N/A"; return; }
    jq -rs "[.[] | select(.phase == \"GATE_${phase}\" and .actor == \"flatline-orchestrator\") | .verdict] | last // \"N/A\"" "$file" 2>/dev/null || echo "N/A"
}

_extract_skipped() {
    local file="$1"
    [[ ! -f "$file" ]] && { echo "N/A"; return; }
    jq -s '[.[] | select(.action == "skipped")] | length' "$file" 2>/dev/null || echo "N/A"
}

# =============================================================================
# Generate Report
# =============================================================================

file_a_exists="yes"
file_b_exists="yes"
[[ ! -f "$FILE_A" ]] && file_a_exists="no"
[[ ! -f "$FILE_B" ]] && file_b_exists="no"

cat << HEADER
# Spiral Benchmark Comparison

**Generated**: $(date -u +%Y-%m-%dT%H:%M:%SZ)
**Run A**: $LABEL_A (${file_a_exists} flight recorder)
**Run B**: $LABEL_B (${file_b_exists} flight recorder)

---

## Summary

| Dimension | $LABEL_A | $LABEL_B |
|-----------|$(printf -- '-%.0s' {1..20})|$(printf -- '-%.0s' {1..20})|
| Profile | $(_extract_profile "$FILE_A") | $(_extract_profile "$FILE_B") |
| Total Cost (USD) | \$$(_extract_total_cost "$FILE_A") | \$$(_extract_total_cost "$FILE_B") |
| Total Duration (sec) | $(_extract_total_duration "$FILE_A") | $(_extract_total_duration "$FILE_B") |
| Claude -p Invocations | $(_extract_phases "$FILE_A") | $(_extract_phases "$FILE_B") |
| Failures | $(_extract_failures "$FILE_A") | $(_extract_failures "$FILE_B") |
| Skipped Gates | $(_extract_skipped "$FILE_A") | $(_extract_skipped "$FILE_B") |

## Flatline Gates

| Gate | $LABEL_A | $LABEL_B |
|------|$(printf -- '-%.0s' {1..20})|$(printf -- '-%.0s' {1..20})|
| PRD | $(_extract_flatline "$FILE_A" "prd") | $(_extract_flatline "$FILE_B" "prd") |
| SDD | $(_extract_flatline "$FILE_A" "sdd") | $(_extract_flatline "$FILE_B" "sdd") |
| Sprint | $(_extract_flatline "$FILE_A" "sprint") | $(_extract_flatline "$FILE_B" "sprint") |

## Quality Gate Verdicts

| Gate | $LABEL_A | $LABEL_B |
|------|$(printf -- '-%.0s' {1..20})|$(printf -- '-%.0s' {1..20})|
| Review | $(_extract_verdict "$FILE_A" "REVIEW") | $(_extract_verdict "$FILE_B" "REVIEW") |
| Audit | $(_extract_verdict "$FILE_A" "AUDIT") | $(_extract_verdict "$FILE_B" "AUDIT") |

## Evidence Artifacts

| Dimension | $LABEL_A | $LABEL_B |
|-----------|$(printf -- '-%.0s' {1..20})|$(printf -- '-%.0s' {1..20})|
| Flight Recorder | $([[ "$file_a_exists" == "yes" ]] && echo "Present" || echo "**ABSENT**") | $([[ "$file_b_exists" == "yes" ]] && echo "Present" || echo "**ABSENT**") |
| Flatline Reviews | $([[ "$file_a_exists" == "yes" ]] && _extract_metric "$FILE_A" '[.[] | select(.actor == "flatline-orchestrator")] | length' "0" || echo "**ABSENT**") | $([[ "$file_b_exists" == "yes" ]] && _extract_metric "$FILE_B" '[.[] | select(.actor == "flatline-orchestrator")] | length' "0" || echo "**ABSENT**") |
| Independent Review | $(_extract_verdict "$FILE_A" "REVIEW") | $(_extract_verdict "$FILE_B" "REVIEW") |
| Independent Audit | $(_extract_verdict "$FILE_A" "AUDIT") | $(_extract_verdict "$FILE_B" "AUDIT") |
| Bridgebuilder | $([[ "$file_a_exists" == "yes" ]] && _extract_metric "$FILE_A" '[.[] | select(.phase == "GATE_BRIDGEBUILDER")] | length' "0" || echo "**ABSENT**") | $([[ "$file_b_exists" == "yes" ]] && _extract_metric "$FILE_B" '[.[] | select(.phase == "GATE_BRIDGEBUILDER")] | length' "0" || echo "**ABSENT**") |
HEADER
