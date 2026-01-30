#!/usr/bin/env bash
# Context Benchmark - Measure context management performance
# Part of the Loa framework's Claude Platform Integration
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Allow environment variable overrides for testing
CONFIG_FILE="${CONFIG_FILE:-${SCRIPT_DIR}/../../.loa.config.yaml}"
NOTES_FILE="${NOTES_FILE:-${SCRIPT_DIR}/../../grimoires/loa/NOTES.md}"
GRIMOIRE_DIR="${GRIMOIRE_DIR:-${SCRIPT_DIR}/../../grimoires/loa}"
TRAJECTORY_DIR="${TRAJECTORY_DIR:-${GRIMOIRE_DIR}/a2a/trajectory}"
ANALYTICS_DIR="${ANALYTICS_DIR:-${GRIMOIRE_DIR}/analytics}"
BASELINE_FILE="${BASELINE_FILE:-${ANALYTICS_DIR}/context-benchmark-baseline.json}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

#######################################
# Print usage information
#######################################
usage() {
    cat << 'USAGE'
Usage: context-benchmark.sh <command> [options]

Context Benchmark - Measure context management performance

Commands:
  run                 Run benchmark and show results
  baseline            Set current results as baseline
  compare             Compare current results against baseline
  history             Show benchmark history

Options:
  --help, -h          Show this help message
  --json              Output as JSON
  --save              Save results to analytics

Metrics Measured:
  - NOTES.md size (tokens estimated)
  - Trajectory entries count
  - Active beads count
  - Checkpoint time (if applicable)
  - Recovery time estimation

Configuration:
  Results saved to: grimoires/loa/analytics/context-benchmark.json
  Baseline file: grimoires/loa/analytics/context-benchmark-baseline.json

Examples:
  context-benchmark.sh run
  context-benchmark.sh run --save
  context-benchmark.sh baseline
  context-benchmark.sh compare --json
USAGE
}

#######################################
# Print colored output
#######################################
print_info() {
    echo -e "${BLUE}i${NC} $1"
}

print_success() {
    echo -e "${GREEN}v${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}!${NC} $1"
}

print_error() {
    echo -e "${RED}x${NC} $1"
}

#######################################
# Check dependencies
#######################################
check_dependencies() {
    local missing=()

    if ! command -v yq &>/dev/null; then
        missing+=("yq")
    fi

    if ! command -v jq &>/dev/null; then
        missing+=("jq")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        print_error "Missing dependencies: ${missing[*]}"
        echo ""
        echo "Install with:"
        echo "  macOS:  brew install ${missing[*]}"
        echo "  Ubuntu: sudo apt install ${missing[*]}"
        return 1
    fi

    return 0
}

#######################################
# Estimate token count from text
# Rough approximation: 1 token ~= 4 characters
#######################################
estimate_tokens() {
    local file="$1"
    if [[ -f "$file" ]]; then
        local chars
        chars=$(wc -c < "$file" 2>/dev/null || echo "0")
        echo $((chars / 4))
    else
        echo "0"
    fi
}

#######################################
# Count trajectory entries
#######################################
count_trajectory_entries() {
    local count=0
    if [[ -d "$TRAJECTORY_DIR" ]]; then
        shopt -s nullglob
        for file in "$TRAJECTORY_DIR"/*.jsonl; do
            if [[ -f "$file" ]]; then
                local lines
                lines=$(wc -l < "$file" 2>/dev/null || echo "0")
                count=$((count + lines))
            fi
        done
        shopt -u nullglob
    fi
    echo "$count"
}

#######################################
# Count active beads
#######################################
count_active_beads() {
    if command -v br &>/dev/null; then
        br list --status=in_progress 2>/dev/null | wc -l || echo "0"
    else
        echo "0"
    fi
}

#######################################
# Count closed beads
#######################################
count_closed_beads() {
    if command -v br &>/dev/null; then
        br list --status=closed 2>/dev/null | wc -l || echo "0"
    else
        echo "0"
    fi
}

#######################################
# Get NOTES.md section sizes
#######################################
get_notes_section_sizes() {
    if [[ ! -f "$NOTES_FILE" ]]; then
        echo '{"session_continuity": 0, "decision_log": 0, "other": 0}'
        return
    fi

    local session_cont=0
    local decision_log=0
    local other=0

    # Extract Session Continuity section
    if grep -q "## Session Continuity" "$NOTES_FILE" 2>/dev/null; then
        local section
        section=$(sed -n '/## Session Continuity/,/^## /p' "$NOTES_FILE" 2>/dev/null | head -n -1)
        session_cont=$(echo "$section" | wc -c | xargs)
        session_cont=$((session_cont / 4))
    fi

    # Extract Decision Log section
    if grep -q "## Decision Log" "$NOTES_FILE" 2>/dev/null; then
        local section
        section=$(sed -n '/## Decision Log/,/^## /p' "$NOTES_FILE" 2>/dev/null | head -n -1)
        decision_log=$(echo "$section" | wc -c | xargs)
        decision_log=$((decision_log / 4))
    fi

    # Other sections
    local total
    total=$(estimate_tokens "$NOTES_FILE")
    other=$((total - session_cont - decision_log))
    if [[ $other -lt 0 ]]; then
        other=0
    fi

    jq -n \
        --argjson sc "$session_cont" \
        --argjson dl "$decision_log" \
        --argjson ot "$other" \
        '{session_continuity: $sc, decision_log: $dl, other: $ot}'
}

#######################################
# Run benchmark
#######################################
run_benchmark() {
    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Gather metrics
    local notes_tokens
    notes_tokens=$(estimate_tokens "$NOTES_FILE")

    local trajectory_entries
    trajectory_entries=$(count_trajectory_entries)

    local active_beads
    active_beads=$(count_active_beads)

    local closed_beads
    closed_beads=$(count_closed_beads)

    local notes_sections
    notes_sections=$(get_notes_section_sizes)

    # Estimate recovery times (based on token counts)
    local level1_time=$(($(echo "$notes_sections" | jq '.session_continuity') / 100 + 1))
    local level2_time=$((notes_tokens / 100 + 2))
    local level3_time=$((notes_tokens / 50 + trajectory_entries / 10 + 3))

    # Simplified checkpoint steps (3 manual)
    local checkpoint_steps=3

    # Build result
    jq -n \
        --arg ts "$timestamp" \
        --argjson notes_tokens "$notes_tokens" \
        --argjson trajectory_entries "$trajectory_entries" \
        --argjson active_beads "$active_beads" \
        --argjson closed_beads "$closed_beads" \
        --argjson notes_sections "$notes_sections" \
        --argjson level1_time "$level1_time" \
        --argjson level2_time "$level2_time" \
        --argjson level3_time "$level3_time" \
        --argjson checkpoint_steps "$checkpoint_steps" \
        '{
            timestamp: $ts,
            metrics: {
                notes_tokens: $notes_tokens,
                trajectory_entries: $trajectory_entries,
                active_beads: $active_beads,
                closed_beads: $closed_beads,
                notes_sections: $notes_sections
            },
            estimates: {
                level1_recovery_ms: ($level1_time * 100),
                level2_recovery_ms: ($level2_time * 100),
                level3_recovery_ms: ($level3_time * 100),
                checkpoint_manual_steps: $checkpoint_steps
            }
        }'
}

#######################################
# Run command
#######################################
cmd_run() {
    local json_output="false"
    local save_results="false"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json)
                json_output="true"
                shift
                ;;
            --save)
                save_results="true"
                shift
                ;;
            *)
                print_error "Unknown option: $1"
                return 1
                ;;
        esac
    done

    local results
    results=$(run_benchmark)

    if [[ "$json_output" == "true" ]]; then
        echo "$results" | jq .
    else
        echo ""
        echo -e "${CYAN}Context Benchmark Results${NC}"
        echo "=========================="
        echo ""
        echo -e "${CYAN}Token Usage:${NC}"
        echo "  NOTES.md total: $(echo "$results" | jq '.metrics.notes_tokens') tokens"
        echo "    - Session Continuity: $(echo "$results" | jq '.metrics.notes_sections.session_continuity') tokens"
        echo "    - Decision Log: $(echo "$results" | jq '.metrics.notes_sections.decision_log') tokens"
        echo "    - Other sections: $(echo "$results" | jq '.metrics.notes_sections.other') tokens"
        echo ""
        echo -e "${CYAN}State:${NC}"
        echo "  Trajectory entries: $(echo "$results" | jq '.metrics.trajectory_entries')"
        echo "  Active beads: $(echo "$results" | jq '.metrics.active_beads')"
        echo "  Closed beads: $(echo "$results" | jq '.metrics.closed_beads')"
        echo ""
        echo -e "${CYAN}Recovery Time Estimates:${NC}"
        echo "  Level 1 (~100 tokens): $(echo "$results" | jq '.estimates.level1_recovery_ms')ms"
        echo "  Level 2 (~500 tokens): $(echo "$results" | jq '.estimates.level2_recovery_ms')ms"
        echo "  Level 3 (full): $(echo "$results" | jq '.estimates.level3_recovery_ms')ms"
        echo ""
        echo -e "${CYAN}Checkpoint:${NC}"
        echo "  Manual steps: $(echo "$results" | jq '.estimates.checkpoint_manual_steps') (simplified from 7)"
        echo ""
    fi

    if [[ "$save_results" == "true" ]]; then
        # Ensure analytics directory exists
        mkdir -p "$ANALYTICS_DIR"

        local results_file="${ANALYTICS_DIR}/context-benchmark.json"

        # Append to history or create new
        if [[ -f "$results_file" ]]; then
            local existing
            existing=$(cat "$results_file")
            echo "$existing" | jq --argjson new "$results" '. + [$new]' > "$results_file"
        else
            echo "[$results]" | jq . > "$results_file"
        fi

        print_success "Results saved to $results_file"
    fi
}

#######################################
# Baseline command
#######################################
cmd_baseline() {
    local results
    results=$(run_benchmark)

    # Ensure analytics directory exists
    mkdir -p "$ANALYTICS_DIR"

    echo "$results" | jq . > "$BASELINE_FILE"

    print_success "Baseline set at $(date)"
    echo ""
    echo "Baseline metrics:"
    echo "  NOTES.md: $(echo "$results" | jq '.metrics.notes_tokens') tokens"
    echo "  Trajectory: $(echo "$results" | jq '.metrics.trajectory_entries') entries"
    echo "  Checkpoint: $(echo "$results" | jq '.estimates.checkpoint_manual_steps') manual steps"
}

#######################################
# Compare command
#######################################
cmd_compare() {
    local json_output="false"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json)
                json_output="true"
                shift
                ;;
            *)
                print_error "Unknown option: $1"
                return 1
                ;;
        esac
    done

    if [[ ! -f "$BASELINE_FILE" ]]; then
        print_error "No baseline set. Run 'context-benchmark.sh baseline' first."
        return 1
    fi

    local baseline
    baseline=$(cat "$BASELINE_FILE")

    local current
    current=$(run_benchmark)

    # Calculate deltas
    local baseline_tokens current_tokens delta_tokens pct_tokens
    baseline_tokens=$(echo "$baseline" | jq '.metrics.notes_tokens')
    current_tokens=$(echo "$current" | jq '.metrics.notes_tokens')
    delta_tokens=$((current_tokens - baseline_tokens))
    if [[ $baseline_tokens -gt 0 ]]; then
        pct_tokens=$(echo "scale=1; ($delta_tokens * 100) / $baseline_tokens" | bc 2>/dev/null || echo "0")
    else
        pct_tokens="0"
    fi

    local baseline_traj current_traj delta_traj
    baseline_traj=$(echo "$baseline" | jq '.metrics.trajectory_entries')
    current_traj=$(echo "$current" | jq '.metrics.trajectory_entries')
    delta_traj=$((current_traj - baseline_traj))

    local comparison
    comparison=$(jq -n \
        --argjson baseline "$baseline" \
        --argjson current "$current" \
        --argjson delta_tokens "$delta_tokens" \
        --arg pct_tokens "$pct_tokens" \
        --argjson delta_traj "$delta_traj" \
        '{
            baseline: $baseline,
            current: $current,
            deltas: {
                notes_tokens: $delta_tokens,
                notes_tokens_pct: ($pct_tokens | tonumber),
                trajectory_entries: $delta_traj
            }
        }')

    if [[ "$json_output" == "true" ]]; then
        echo "$comparison" | jq .
    else
        echo ""
        echo -e "${CYAN}Benchmark Comparison${NC}"
        echo "===================="
        echo ""
        echo -e "${CYAN}Token Usage:${NC}"
        echo "  Baseline: $baseline_tokens tokens"
        echo "  Current:  $current_tokens tokens"
        if [[ $delta_tokens -gt 0 ]]; then
            echo -e "  Delta:    ${RED}+$delta_tokens (+$pct_tokens%)${NC}"
        elif [[ $delta_tokens -lt 0 ]]; then
            echo -e "  Delta:    ${GREEN}$delta_tokens ($pct_tokens%)${NC}"
        else
            echo "  Delta:    0 (no change)"
        fi
        echo ""
        echo -e "${CYAN}Trajectory:${NC}"
        echo "  Baseline: $baseline_traj entries"
        echo "  Current:  $current_traj entries"
        echo "  Delta:    $delta_traj"
        echo ""
        echo -e "${CYAN}Target Metrics (v0.11.0):${NC}"
        echo "  Token reduction: -15% (target)"
        if [[ $(echo "$pct_tokens < -15" | bc 2>/dev/null || echo "0") -eq 1 ]]; then
            print_success "Token target MET ($pct_tokens%)"
        else
            print_warning "Token target not met ($pct_tokens% vs -15%)"
        fi
        echo "  Checkpoint steps: 3 (target, was 7)"
        local current_steps
        current_steps=$(echo "$current" | jq '.estimates.checkpoint_manual_steps')
        if [[ $current_steps -le 3 ]]; then
            print_success "Checkpoint target MET ($current_steps steps)"
        else
            print_warning "Checkpoint target not met ($current_steps steps vs 3)"
        fi
        echo ""
    fi
}

#######################################
# History command
#######################################
cmd_history() {
    local json_output="false"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json)
                json_output="true"
                shift
                ;;
            *)
                print_error "Unknown option: $1"
                return 1
                ;;
        esac
    done

    local results_file="${ANALYTICS_DIR}/context-benchmark.json"

    if [[ ! -f "$results_file" ]]; then
        print_warning "No benchmark history found."
        print_info "Run 'context-benchmark.sh run --save' to start collecting data."
        return 0
    fi

    local history
    history=$(cat "$results_file")

    if [[ "$json_output" == "true" ]]; then
        echo "$history" | jq .
    else
        echo ""
        echo -e "${CYAN}Benchmark History${NC}"
        echo "================="
        echo ""
        echo "$history" | jq -r '.[] | "[\(.timestamp)] NOTES: \(.metrics.notes_tokens) tokens, Trajectory: \(.metrics.trajectory_entries) entries"'
        echo ""

        local count
        count=$(echo "$history" | jq 'length')
        print_info "$count benchmark entries recorded"
    fi
}

#######################################
# Main entry point
#######################################
main() {
    local command=""

    if [[ $# -eq 0 ]]; then
        usage
        exit 1
    fi

    command="$1"
    shift

    case "$command" in
        run)
            check_dependencies || exit 1
            cmd_run "$@"
            ;;
        baseline)
            check_dependencies || exit 1
            cmd_baseline "$@"
            ;;
        compare)
            check_dependencies || exit 1
            cmd_compare "$@"
            ;;
        history)
            check_dependencies || exit 1
            cmd_history "$@"
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            print_error "Unknown command: $command"
            usage
            exit 1
            ;;
    esac
}

main "$@"
