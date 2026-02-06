#!/usr/bin/env bash
# Synthesize to Ledger - Write decisions to NOTES.md and trajectory
# Part of the Loa framework's Continuous Synthesis system
#
# This script externalizes data to persistent ledgers at RLM trigger points,
# ensuring information survives Claude Code's automatic context summarization.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

# Allow environment variable overrides for testing
CONFIG_FILE="${CONFIG_FILE:-${PROJECT_ROOT}/.loa.config.yaml}"
NOTES_FILE="${NOTES_FILE:-${PROJECT_ROOT}/grimoires/loa/NOTES.md}"
TRAJECTORY_DIR="${TRAJECTORY_DIR:-${PROJECT_ROOT}/grimoires/loa/a2a/trajectory}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

#######################################
# Print usage information
#######################################
usage() {
    cat << 'USAGE'
Usage: synthesize-to-ledger.sh <command> [options]

Synthesize to Ledger - Write decisions to NOTES.md and trajectory

Commands:
  decision --message <msg> [--source <src>]   Write to Decision Log
  trajectory --agent <name> --action <act>    Write to trajectory JSONL
  milestone --message <msg>                   Write milestone to both

Options:
  --help, -h                    Show this help message
  --message, -m <msg>           The decision/milestone message
  --source, -s <src>            Source of decision (cache/condense/early-exit)
  --agent, -a <agent>           Agent name for trajectory
  --action <act>                Action for trajectory entry
  --quiet                       Suppress output

Configuration (.loa.config.yaml):
  recursive_jit:
    continuous_synthesis:
      enabled: true
      on_cache_set: true
      on_condense: true
      on_early_exit: true
      target: notes_decision_log
      update_bead: true        # Also add comment to active bead (requires br)

Examples:
  # Write decision from cache operation
  synthesize-to-ledger.sh decision --message "Cached auth audit: PASS" --source cache

  # Write trajectory entry
  synthesize-to-ledger.sh trajectory --agent implementing-tasks --action "Completed validation"

  # Write milestone (both decision + trajectory)
  synthesize-to-ledger.sh milestone --message "Sprint-3 security audit complete"
USAGE
}

#######################################
# Print colored output
#######################################
print_info() {
    [[ "${QUIET:-false}" == "true" ]] && return
    echo -e "${BLUE}i${NC} $1" >&2
}

print_success() {
    [[ "${QUIET:-false}" == "true" ]] && return
    echo -e "${GREEN}✓${NC} $1" >&2
}

print_warning() {
    echo -e "${YELLOW}!${NC} $1" >&2
}

print_error() {
    echo -e "${RED}✗${NC} $1" >&2
}

#######################################
# Check if synthesis is enabled
#######################################
is_synthesis_enabled() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        return 1
    fi

    # Check if yq is available
    if command -v yq &>/dev/null; then
        local enabled
        enabled=$(yq '.recursive_jit.continuous_synthesis.enabled // true' "$CONFIG_FILE" 2>/dev/null)
        [[ "$enabled" == "true" ]]
    else
        # Fallback: assume enabled if config exists
        return 0
    fi
}

#######################################
# Check if bead update is enabled
#######################################
is_bead_update_enabled() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        return 1
    fi

    # Check if br is available
    if ! command -v br &>/dev/null; then
        return 1
    fi

    # Check if .beads directory exists
    if [[ ! -d "${PROJECT_ROOT}/.beads" ]]; then
        return 1
    fi

    if command -v yq &>/dev/null; then
        local enabled
        enabled=$(yq '.recursive_jit.continuous_synthesis.update_bead // true' "$CONFIG_FILE" 2>/dev/null)
        [[ "$enabled" == "true" ]]
    else
        return 1
    fi
}

#######################################
# Get active bead ID from NOTES.md
#######################################
get_active_bead_id() {
    if [[ ! -f "$NOTES_FILE" ]]; then
        return 1
    fi

    # Look for "Last task: beads-XXXX" or similar patterns in Session Continuity
    local bead_id
    bead_id=$(grep -oE 'beads-[a-z0-9]+' "$NOTES_FILE" | head -1)

    if [[ -n "$bead_id" ]]; then
        echo "$bead_id"
        return 0
    fi

    return 1
}

#######################################
# Update active bead with decision
#######################################
update_active_bead() {
    local message="$1"

    if ! is_bead_update_enabled; then
        return 0
    fi

    local bead_id
    if ! bead_id=$(get_active_bead_id); then
        return 0  # No active bead, skip silently
    fi

    # Verify bead exists
    if ! br show "$bead_id" --json &>/dev/null; then
        return 0  # Bead not found, skip silently
    fi

    # Add comment to bead with the decision
    br comments add "$bead_id" "[Synthesis] $message" 2>/dev/null || true
    print_success "Bead updated: $bead_id"
}

#######################################
# Get current timestamp
#######################################
get_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

#######################################
# Get date for tables
#######################################
get_date() {
    date +"%Y-%m-%d"
}

#######################################
# Ensure NOTES.md exists with Decision Log section
#######################################
ensure_notes_file() {
    if [[ ! -f "$NOTES_FILE" ]]; then
        mkdir -p "$(dirname "$NOTES_FILE")"
        cat > "$NOTES_FILE" << 'EOF'
# Agent Working Memory (NOTES.md)

> This file persists agent context across sessions and compaction cycles.

## Session Continuity

Current focus: Not set
Last task: None
Status: New session

## Decisions

| Date | Decision | Rationale |
|------|----------|-----------|

## Blockers

(None)

## Technical Debt

(None)

## Learnings

(None)
EOF
        print_info "Created NOTES.md with template"
    fi
}

#######################################
# Write decision to NOTES.md Decision Log
#######################################
write_decision() {
    local message="$1"
    local source="${2:-manual}"
    local date
    date=$(get_date)

    ensure_notes_file

    # Check if Decision Log section exists
    if ! grep -q "## Decisions" "$NOTES_FILE"; then
        # Add section before Blockers or at end
        if grep -q "## Blockers" "$NOTES_FILE"; then
            sed '/## Blockers/i ## Decisions\n\n| Date | Decision | Rationale |\n|------|----------|-----------|' "$NOTES_FILE" > "${NOTES_FILE}.tmp" && mv "${NOTES_FILE}.tmp" "$NOTES_FILE"
        else
            echo -e "\n## Decisions\n\n| Date | Decision | Rationale |\n|------|----------|-----------|" >> "$NOTES_FILE"
        fi
    fi

    # Escape pipe characters in message
    local escaped_message
    escaped_message=$(echo "$message" | sed 's/|/\\|/g')

    # Insert new row after the table header
    # Find the line with |------|----------|-----------|  and insert after it
    local table_header_line
    table_header_line=$(grep -n "|------|----------|-----------|" "$NOTES_FILE" | head -1 | cut -d: -f1)

    if [[ -n "$table_header_line" ]]; then
        local new_row="| $date | $escaped_message | Source: $source |"
        sed "${table_header_line}a\\${new_row}" "$NOTES_FILE" > "${NOTES_FILE}.tmp" && mv "${NOTES_FILE}.tmp" "$NOTES_FILE"
        print_success "Decision logged to NOTES.md"

        # Also update active bead if enabled
        update_active_bead "$message"
    else
        print_warning "Could not find Decision Log table header"
    fi
}

#######################################
# Write trajectory entry
#######################################
write_trajectory() {
    local agent="$1"
    local action="$2"
    local timestamp
    timestamp=$(get_timestamp)
    local date
    date=$(date +"%Y-%m-%d")

    # Get session ID from environment (available in Claude Code 2.1.9+)
    local session_id="${CLAUDE_SESSION_ID:-unknown}"

    mkdir -p "$TRAJECTORY_DIR"

    local trajectory_file="$TRAJECTORY_DIR/${agent}-${date}.jsonl"

    local entry
    entry=$(jq -n \
        --arg ts "$timestamp" \
        --arg session_id "$session_id" \
        --arg agent "$agent" \
        --arg action "$action" \
        --arg grounding "synthesis_trigger" \
        '{
            timestamp: $ts,
            session_id: $session_id,
            agent: $agent,
            action: $action,
            grounding: {type: $grounding}
        }')

    echo "$entry" >> "$trajectory_file"
    print_success "Trajectory logged: $trajectory_file"
}

#######################################
# CMD: Write decision
#######################################
cmd_decision() {
    local message=""
    local source="manual"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --message|-m) message="$2"; shift 2 ;;
            --source|-s) source="$2"; shift 2 ;;
            --quiet) QUIET=true; shift ;;
            *)
                print_error "Unknown option: $1"
                return 1
                ;;
        esac
    done

    if [[ -z "$message" ]]; then
        print_error "Required: --message"
        return 1
    fi

    if ! is_synthesis_enabled; then
        print_info "Continuous synthesis disabled"
        return 0
    fi

    write_decision "$message" "$source"
}

#######################################
# CMD: Write trajectory
#######################################
cmd_trajectory() {
    local agent=""
    local action=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --agent|-a) agent="$2"; shift 2 ;;
            --action) action="$2"; shift 2 ;;
            --quiet) QUIET=true; shift ;;
            *)
                print_error "Unknown option: $1"
                return 1
                ;;
        esac
    done

    if [[ -z "$agent" ]] || [[ -z "$action" ]]; then
        print_error "Required: --agent, --action"
        return 1
    fi

    if ! is_synthesis_enabled; then
        print_info "Continuous synthesis disabled"
        return 0
    fi

    write_trajectory "$agent" "$action"
}

#######################################
# CMD: Write milestone (both)
#######################################
cmd_milestone() {
    local message=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --message|-m) message="$2"; shift 2 ;;
            --quiet) QUIET=true; shift ;;
            *)
                print_error "Unknown option: $1"
                return 1
                ;;
        esac
    done

    if [[ -z "$message" ]]; then
        print_error "Required: --message"
        return 1
    fi

    if ! is_synthesis_enabled; then
        print_info "Continuous synthesis disabled"
        return 0
    fi

    write_decision "$message" "milestone"
    write_trajectory "system" "Milestone: $message"
    print_success "Milestone logged to both ledgers"
}

#######################################
# Main entry point
#######################################
main() {
    if [[ $# -eq 0 ]]; then
        usage
        exit 1
    fi

    local command="$1"
    shift

    case "$command" in
        decision)
            cmd_decision "$@"
            ;;
        trajectory)
            cmd_trajectory "$@"
            ;;
        milestone)
            cmd_milestone "$@"
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
