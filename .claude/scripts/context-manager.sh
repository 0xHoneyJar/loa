#!/usr/bin/env bash
# Context Manager - Manage context compaction and session continuity
# Part of the Loa framework's Claude Platform Integration
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Allow environment variable overrides for testing
CONFIG_FILE="${CONFIG_FILE:-${SCRIPT_DIR}/../../.loa.config.yaml}"
NOTES_FILE="${NOTES_FILE:-${SCRIPT_DIR}/../../grimoires/loa/NOTES.md}"
GRIMOIRE_DIR="${GRIMOIRE_DIR:-${SCRIPT_DIR}/../../grimoires/loa}"
TRAJECTORY_DIR="${TRAJECTORY_DIR:-${GRIMOIRE_DIR}/a2a/trajectory}"
PROTOCOLS_DIR="${PROTOCOLS_DIR:-${SCRIPT_DIR}/../protocols}"

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
Usage: context-manager.sh <command> [options]

Context Manager - Manage context compaction and session continuity

Commands:
  status              Show current context state and preservation status
  rules               Show preservation rules (what's preserved vs compactable)
  preserve [section]  Check if critical sections exist (default: all critical)
  compact             Run compaction pre-check (what would be compacted)
  checkpoint          Run simplified checkpoint (3 manual steps)
  recover [level]     Recover context (level 1/2/3)

Options:
  --help, -h          Show this help message
  --json              Output as JSON (for status command)
  --dry-run           Show what would happen without making changes

Preservation Rules:
  ALWAYS preserved:
    - NOTES.md Session Continuity section
    - NOTES.md Decision Log
    - Trajectory entries (external files)
    - Active bead references

  COMPACTABLE:
    - Tool results (after use)
    - Thinking blocks (after logged to trajectory)
    - Verbose debug output

Configuration (in .loa.config.yaml):
  context_management.client_compaction      Enable client-side compaction (default: true)
  context_management.preserve_notes_md      Always preserve NOTES.md (default: true)
  context_management.simplified_checkpoint  Use 3-step checkpoint (default: true)
  context_management.auto_trajectory_log    Auto-log thinking to trajectory (default: true)

Examples:
  context-manager.sh status
  context-manager.sh status --json
  context-manager.sh checkpoint
  context-manager.sh recover 2
  context-manager.sh compact --dry-run
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
# Get configuration value
#######################################
get_config() {
    local key="$1"
    local default="${2:-}"

    if [[ -f "$CONFIG_FILE" ]] && command -v yq &>/dev/null; then
        local exists
        exists=$(yq -r ".$key | type" "$CONFIG_FILE" 2>/dev/null || echo "null")
        if [[ "$exists" != "null" ]]; then
            local value
            value=$(yq -r ".$key" "$CONFIG_FILE" 2>/dev/null || echo "")
            if [[ "$value" != "null" ]]; then
                echo "$value"
                return 0
            fi
        fi
    fi

    echo "$default"
}

#######################################
# Check if client compaction is enabled
#######################################
is_compaction_enabled() {
    local enabled
    enabled=$(get_config "context_management.client_compaction" "true")
    [[ "$enabled" == "true" ]]
}

#######################################
# Check if simplified checkpoint is enabled
#######################################
is_simplified_checkpoint() {
    local enabled
    enabled=$(get_config "context_management.simplified_checkpoint" "true")
    [[ "$enabled" == "true" ]]
}

#######################################
# Check if NOTES.md preservation is enabled
#######################################
is_notes_preserved() {
    local enabled
    enabled=$(get_config "context_management.preserve_notes_md" "true")
    [[ "$enabled" == "true" ]]
}

#######################################
# Get preservation rules (configurable)
#######################################
get_preservation_rules() {
    # Returns JSON with preservation rules
    local rules='{"always_preserve": [], "compactable": []}'

    # ALWAYS preserved items (hard-coded defaults + config overrides)
    local always_preserve='["notes_session_continuity", "notes_decision_log", "trajectory_entries", "active_beads"]'

    # Check for config overrides
    if [[ -f "$CONFIG_FILE" ]] && command -v yq &>/dev/null; then
        local config_always
        config_always=$(yq -r '.context_management.preservation_rules.always_preserve // empty' "$CONFIG_FILE" 2>/dev/null || echo "")
        if [[ -n "$config_always" ]]; then
            always_preserve=$(echo "$config_always" | jq -c '.')
        fi
    fi

    # COMPACTABLE items (can be compressed/summarized)
    local compactable='["tool_results", "thinking_blocks", "verbose_debug", "redundant_file_reads", "intermediate_outputs"]'

    # Check for config overrides
    if [[ -f "$CONFIG_FILE" ]] && command -v yq &>/dev/null; then
        local config_compactable
        config_compactable=$(yq -r '.context_management.preservation_rules.compactable // empty' "$CONFIG_FILE" 2>/dev/null || echo "")
        if [[ -n "$config_compactable" ]]; then
            compactable=$(echo "$config_compactable" | jq -c '.')
        fi
    fi

    # Combine into rules object
    jq -n \
        --argjson always "$always_preserve" \
        --argjson compact "$compactable" \
        '{always_preserve: $always, compactable: $compact}'
}

#######################################
# Check if a specific item should be preserved
#######################################
should_preserve() {
    local item="$1"
    local rules
    rules=$(get_preservation_rules)

    echo "$rules" | jq -e --arg item "$item" '.always_preserve | contains([$item])' >/dev/null 2>&1
}

#######################################
# Check if a specific item is compactable
#######################################
is_compactable() {
    local item="$1"
    local rules
    rules=$(get_preservation_rules)

    echo "$rules" | jq -e --arg item "$item" '.compactable | contains([$item])' >/dev/null 2>&1
}

#######################################
# Get preservation status for all items
#######################################
get_preservation_status() {
    local status='{}'

    # Check each always-preserved item
    local session_cont="false"
    local decision_log="false"
    local trajectory="false"
    local beads="false"

    if has_session_continuity; then
        session_cont="true"
    fi

    if has_decision_log; then
        decision_log="true"
    fi

    local traj_count
    traj_count=$(count_today_trajectory_entries)
    if [[ "$traj_count" -gt 0 ]]; then
        trajectory="true"
    fi

    local beads_count
    beads_count=$(get_active_beads_count)
    if [[ "$beads_count" -gt 0 ]]; then
        beads="true"
    fi

    jq -n \
        --argjson session_cont "$session_cont" \
        --argjson decision_log "$decision_log" \
        --argjson trajectory "$trajectory" \
        --argjson beads "$beads" \
        --argjson traj_count "$traj_count" \
        --argjson beads_count "$beads_count" \
        '{
            notes_session_continuity: {present: $session_cont, required: true},
            notes_decision_log: {present: $decision_log, required: true},
            trajectory_entries: {present: $trajectory, count: $traj_count, required: true},
            active_beads: {present: $beads, count: $beads_count, required: true}
        }'
}

#######################################
# Get NOTES.md sections
#######################################
get_notes_sections() {
    if [[ ! -f "$NOTES_FILE" ]]; then
        echo "[]"
        return 0
    fi

    grep -E "^## " "$NOTES_FILE" 2>/dev/null | sed 's/## //' | jq -R . | jq -s . 2>/dev/null || echo "[]"
}

#######################################
# Check if Session Continuity section exists
#######################################
has_session_continuity() {
    if [[ ! -f "$NOTES_FILE" ]]; then
        return 1
    fi
    grep -q "## Session Continuity" "$NOTES_FILE" 2>/dev/null
}

#######################################
# Check if Decision Log section exists
#######################################
has_decision_log() {
    if [[ ! -f "$NOTES_FILE" ]]; then
        return 1
    fi
    grep -q "## Decision Log" "$NOTES_FILE" 2>/dev/null
}

#######################################
# Count trajectory entries from today
#######################################
count_today_trajectory_entries() {
    local today
    today=$(date +%Y-%m-%d)
    
    if [[ ! -d "$TRAJECTORY_DIR" ]]; then
        echo "0"
        return 0
    fi

    local count=0
    shopt -s nullglob
    for file in "$TRAJECTORY_DIR"/*-"$today".jsonl; do
        if [[ -f "$file" ]]; then
            local lines
            lines=$(wc -l < "$file" 2>/dev/null || echo "0")
            count=$((count + lines))
        fi
    done
    shopt -u nullglob

    echo "$count"
}

#######################################
# Get active beads count
#######################################
get_active_beads_count() {
    if command -v bd &>/dev/null; then
        local count
        count=$(bd list --status=in_progress 2>/dev/null | wc -l || echo "0")
        echo "$count"
    else
        echo "0"
    fi
}

#######################################
# Status command
#######################################
cmd_status() {
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

    # Gather status information
    local compaction_enabled notes_preserved simplified_checkpoint
    compaction_enabled=$(is_compaction_enabled && echo "true" || echo "false")
    notes_preserved=$(is_notes_preserved && echo "true" || echo "false")
    simplified_checkpoint=$(is_simplified_checkpoint && echo "true" || echo "false")

    local session_continuity decision_log
    session_continuity=$(has_session_continuity && echo "true" || echo "false")
    decision_log=$(has_decision_log && echo "true" || echo "false")

    local trajectory_entries active_beads
    trajectory_entries=$(count_today_trajectory_entries)
    active_beads=$(get_active_beads_count)

    local notes_sections
    notes_sections=$(get_notes_sections)

    if [[ "$json_output" == "true" ]]; then
        jq -n \
            --argjson compaction_enabled "$compaction_enabled" \
            --argjson notes_preserved "$notes_preserved" \
            --argjson simplified_checkpoint "$simplified_checkpoint" \
            --argjson session_continuity "$session_continuity" \
            --argjson decision_log "$decision_log" \
            --argjson trajectory_entries "$trajectory_entries" \
            --argjson active_beads "$active_beads" \
            --argjson notes_sections "$notes_sections" \
            '{config: {compaction_enabled: $compaction_enabled, notes_preserved: $notes_preserved, simplified_checkpoint: $simplified_checkpoint}, preservation: {session_continuity: $session_continuity, decision_log: $decision_log, trajectory_entries_today: $trajectory_entries, active_beads: $active_beads}, notes_sections: $notes_sections}'
    else
        echo ""
        echo -e "${CYAN}Context Manager Status${NC}"
        echo "=================================="
        echo ""
        echo -e "${CYAN}Configuration:${NC}"
        if [[ "$compaction_enabled" == "true" ]]; then
            echo -e "  Client Compaction:     ${GREEN}enabled${NC}"
        else
            echo -e "  Client Compaction:     ${YELLOW}disabled${NC}"
        fi
        if [[ "$notes_preserved" == "true" ]]; then
            echo -e "  NOTES.md Preserved:    ${GREEN}yes${NC}"
        else
            echo -e "  NOTES.md Preserved:    ${YELLOW}no${NC}"
        fi
        if [[ "$simplified_checkpoint" == "true" ]]; then
            echo -e "  Simplified Checkpoint: ${GREEN}yes${NC}"
        else
            echo -e "  Simplified Checkpoint: ${YELLOW}no${NC}"
        fi
        echo ""
        echo -e "${CYAN}Preservation Status:${NC}"
        if [[ "$session_continuity" == "true" ]]; then
            print_success "Session Continuity section present"
        else
            print_warning "Session Continuity section missing"
        fi
        if [[ "$decision_log" == "true" ]]; then
            print_success "Decision Log section present"
        else
            print_warning "Decision Log section missing"
        fi
        echo "  Trajectory entries (today): $trajectory_entries"
        echo "  Active beads: $active_beads"
        echo ""
        echo -e "${CYAN}NOTES.md Sections:${NC}"
        echo "$notes_sections" | jq -r '.[] | "  - " + .' 2>/dev/null || echo "  (none)"
        echo ""
    fi
}

#######################################
# Rules command - show preservation rules
#######################################
cmd_rules() {
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

    local rules
    rules=$(get_preservation_rules)

    if [[ "$json_output" == "true" ]]; then
        echo "$rules" | jq .
    else
        echo ""
        echo -e "${CYAN}Preservation Rules${NC}"
        echo "==================="
        echo ""
        echo -e "${GREEN}ALWAYS Preserved (survives compaction):${NC}"
        echo "$rules" | jq -r '.always_preserve[]' | while read -r item; do
            case "$item" in
                notes_session_continuity)
                    echo "  ✓ NOTES.md Session Continuity section"
                    ;;
                notes_decision_log)
                    echo "  ✓ NOTES.md Decision Log"
                    ;;
                trajectory_entries)
                    echo "  ✓ Trajectory entries (external files)"
                    ;;
                active_beads)
                    echo "  ✓ Active bead references"
                    ;;
                *)
                    echo "  ✓ $item"
                    ;;
            esac
        done
        echo ""
        echo -e "${YELLOW}COMPACTABLE (can be summarized/removed):${NC}"
        echo "$rules" | jq -r '.compactable[]' | while read -r item; do
            case "$item" in
                tool_results)
                    echo "  ~ Tool results (after processing)"
                    ;;
                thinking_blocks)
                    echo "  ~ Thinking blocks (after trajectory logging)"
                    ;;
                verbose_debug)
                    echo "  ~ Verbose debug output"
                    ;;
                redundant_file_reads)
                    echo "  ~ Redundant file reads"
                    ;;
                intermediate_outputs)
                    echo "  ~ Intermediate computation outputs"
                    ;;
                *)
                    echo "  ~ $item"
                    ;;
            esac
        done
        echo ""
        echo -e "${CYAN}Configuration:${NC}"
        echo "  Rules can be customized in .loa.config.yaml:"
        echo "    context_management:"
        echo "      preservation_rules:"
        echo "        always_preserve: [...]"
        echo "        compactable: [...]"
        echo ""
    fi
}

#######################################
# Preserve command
#######################################
cmd_preserve() {
    local section="${1:-all}"

    print_info "Checking preservation status..."

    case "$section" in
        all|critical)
            local missing=()
            
            if ! has_session_continuity; then
                missing+=("Session Continuity")
            fi
            
            if ! has_decision_log; then
                missing+=("Decision Log")
            fi

            if [[ ${#missing[@]} -eq 0 ]]; then
                print_success "All critical sections present in NOTES.md"
            else
                print_warning "Missing sections: ${missing[*]}"
                echo ""
                echo "Add missing sections to NOTES.md:"
                for m in "${missing[@]}"; do
                    echo "  ## $m"
                done
            fi
            ;;
        *)
            print_error "Unknown section: $section"
            echo "Available sections: all, critical"
            return 1
            ;;
    esac
}

#######################################
# Compact command (pre-check)
#######################################
cmd_compact() {
    local dry_run="false"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                dry_run="true"
                shift
                ;;
            *)
                print_error "Unknown option: $1"
                return 1
                ;;
        esac
    done

    if ! is_compaction_enabled; then
        print_warning "Client compaction is disabled"
        return 0
    fi

    print_info "Analyzing context for compaction..."
    echo ""

    echo -e "${CYAN}Would be PRESERVED:${NC}"
    print_success "NOTES.md Session Continuity section"
    print_success "NOTES.md Decision Log"
    print_success "Trajectory entries ($(count_today_trajectory_entries) today)"
    print_success "Active beads ($(get_active_beads_count))"
    echo ""

    echo -e "${CYAN}Would be COMPACTED:${NC}"
    echo "  - Tool results after processing"
    echo "  - Thinking blocks after trajectory logging"
    echo "  - Verbose debug output"
    echo "  - Redundant file reads"
    echo ""

    if [[ "$dry_run" == "true" ]]; then
        print_info "Dry run - no changes made"
    else
        print_info "Use Claude Code's /compact command for actual compaction"
        print_info "This script validates preservation rules only"
    fi
}

#######################################
# Checkpoint command (simplified 3-step)
#######################################
cmd_checkpoint() {
    local dry_run="false"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                dry_run="true"
                shift
                ;;
            *)
                print_error "Unknown option: $1"
                return 1
                ;;
        esac
    done

    echo ""
    echo -e "${CYAN}Simplified Checkpoint Process${NC}"
    echo "=============================="
    echo ""

    echo -e "${CYAN}Automated Checks:${NC}"
    
    local auto_pass=0
    local auto_total=4

    # 1. Trajectory logged
    local today_entries
    today_entries=$(count_today_trajectory_entries)
    if [[ "$today_entries" -gt 0 ]]; then
        print_success "[AUTO] Trajectory logged ($today_entries entries today)"
        auto_pass=$((auto_pass + 1))
    else
        print_warning "[AUTO] No trajectory entries today - consider logging decisions"
    fi

    # 2. Session Continuity section exists
    if has_session_continuity; then
        print_success "[AUTO] Session Continuity section present"
        auto_pass=$((auto_pass + 1))
    else
        print_warning "[AUTO] Session Continuity section missing"
    fi

    # 3. Decision Log exists
    if has_decision_log; then
        print_success "[AUTO] Decision Log section present"
        auto_pass=$((auto_pass + 1))
    else
        print_warning "[AUTO] Decision Log section missing"
    fi

    # 4. Beads synced (if available)
    if command -v bd &>/dev/null; then
        local sync_status
        sync_status=$(bd sync --status 2>/dev/null || echo "unknown")
        if [[ "$sync_status" != *"behind"* ]]; then
            print_success "[AUTO] Beads synchronized"
            auto_pass=$((auto_pass + 1))
        else
            print_warning "[AUTO] Beads may need sync"
        fi
    else
        print_info "[AUTO] Beads not installed - skipping"
        auto_pass=$((auto_pass + 1))
    fi

    echo ""
    echo "Automated: $auto_pass/$auto_total passed"
    echo ""

    echo -e "${CYAN}Manual Steps (Verify Before Compaction):${NC}"
    echo ""
    echo -e "  1. ${YELLOW}Verify Decision Log updated${NC}"
    echo "     - Check NOTES.md has today's key decisions"
    echo "     - Each decision should have rationale and grounding"
    echo ""
    echo -e "  2. ${YELLOW}Verify Bead updated${NC}"
    echo "     - Run: bd list --status=in_progress"
    echo "     - Ensure current task is tracked"
    echo "     - Close completed beads: bd close <id>"
    echo ""
    echo -e "  3. ${YELLOW}Verify EDD test scenarios${NC}"
    echo "     - At least 3 test scenarios per decision"
    echo "     - Run tests if applicable"
    echo ""

    if [[ "$dry_run" == "true" ]]; then
        print_info "Dry run complete"
    else
        echo -e "${CYAN}When all steps verified:${NC}"
        echo "  - Use Claude Code /compact command"
        echo "  - Or /clear if context needs reset"
    fi
}

#######################################
# Recover command
#######################################
cmd_recover() {
    local level="${1:-1}"

    echo ""
    echo -e "${CYAN}Context Recovery - Level $level${NC}"
    echo "================================"
    echo ""

    case "$level" in
        1)
            echo -e "${CYAN}Level 1: Minimal Recovery (~100 tokens)${NC}"
            echo ""
            echo "Read only:"
            echo "  1. NOTES.md Session Continuity section"
            echo ""
            if [[ -f "$NOTES_FILE" ]]; then
                echo -e "${CYAN}Session Continuity content:${NC}"
                sed -n '/## Session Continuity/,/^## /p' "$NOTES_FILE" 2>/dev/null | head -20
            else
                print_warning "NOTES.md not found"
            fi
            ;;
        2)
            echo -e "${CYAN}Level 2: Standard Recovery (~500 tokens)${NC}"
            echo ""
            echo "Read:"
            echo "  1. NOTES.md Session Continuity"
            echo "  2. NOTES.md Decision Log (recent)"
            echo "  3. Active beads"
            echo ""
            if command -v bd &>/dev/null; then
                echo -e "${CYAN}Active Beads:${NC}"
                bd list --status=in_progress 2>/dev/null || echo "  (none)"
            fi
            ;;
        3)
            echo -e "${CYAN}Level 3: Full Recovery (~2000 tokens)${NC}"
            echo ""
            echo "Read:"
            echo "  1. Full NOTES.md"
            echo "  2. All active beads"
            echo "  3. Today's trajectory entries"
            echo "  4. sprint.md current sprint"
            echo ""
            echo "Trajectory entries today: $(count_today_trajectory_entries)"
            ;;
        *)
            print_error "Invalid level: $level (use 1, 2, or 3)"
            return 1
            ;;
    esac
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
        status)
            check_dependencies || exit 1
            cmd_status "$@"
            ;;
        rules)
            check_dependencies || exit 1
            cmd_rules "$@"
            ;;
        preserve)
            check_dependencies || exit 1
            cmd_preserve "$@"
            ;;
        compact)
            check_dependencies || exit 1
            cmd_compact "$@"
            ;;
        checkpoint)
            check_dependencies || exit 1
            cmd_checkpoint "$@"
            ;;
        recover)
            check_dependencies || exit 1
            cmd_recover "$@"
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
