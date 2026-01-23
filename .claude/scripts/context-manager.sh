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

# Default configuration values for probe-before-load
DEFAULT_MAX_EAGER_LOAD_LINES=500
DEFAULT_REQUIRE_RELEVANCE_CHECK="true"
DEFAULT_RELEVANCE_KEYWORDS='["export","class","interface","function","async","api","route","handler"]'
DEFAULT_EXCLUDE_PATTERNS='["*.test.ts","*.spec.ts","node_modules/**","dist/**","build/**",".git/**"]'

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
  recover [level] [--query <query>]  Recover context (level 1/2/3) with optional semantic search

  Probe Commands (RLM Pattern):
  probe <path>        Probe file or directory metadata without loading content
  should-load <file>  Determine if file should be fully loaded based on probe
  relevance <file>    Get relevance score (0-10) for a file

Options:
  --help, -h          Show this help message
  --json              Output as JSON (for status command)
  --dry-run           Show what would happen without making changes
  --query <query>     Semantic query for recovery (selects relevant sections)

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
  context-manager.sh recover 2 --query "authentication flow"
  context-manager.sh compact --dry-run

  Probe Examples (RLM Pattern):
  context-manager.sh probe src/                    # Probe directory
  context-manager.sh probe src/index.ts            # Probe single file
  context-manager.sh probe . --json                # JSON output
  context-manager.sh should-load src/large.ts      # Check if should load
  context-manager.sh relevance src/api.ts          # Get relevance score
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
# PROBE-BEFORE-LOAD FUNCTIONS (RLM Pattern)
#######################################

#######################################
# Probe file metadata without loading content
# Arguments:
#   $1 - file path
# Outputs:
#   JSON object with file metadata
#######################################
context_probe_file() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        jq -n --arg file "$file" '{"error": "file_not_found", "file": $file}'
        return 1
    fi

    local lines size type_info extension estimated_tokens

    # Get line count (handle empty files)
    lines=$(wc -l < "$file" 2>/dev/null | tr -d ' ' || echo "0")
    [[ -z "$lines" ]] && lines=0

    # Get file size (handle both macOS and Linux stat)
    if [[ "$(uname)" == "Darwin" ]]; then
        size=$(stat -f%z "$file" 2>/dev/null || echo "0")
    else
        size=$(stat -c%s "$file" 2>/dev/null || echo "0")
    fi
    [[ -z "$size" ]] && size=0

    # Get file type (truncate long descriptions)
    type_info=$(file -b "$file" 2>/dev/null | head -c 100 || echo "unknown")

    # Extract extension
    extension="${file##*.}"
    [[ "$extension" == "$file" ]] && extension=""

    # Estimate tokens (~4 chars per token for code)
    estimated_tokens=$((size / 4))

    jq -n \
        --arg file "$file" \
        --argjson lines "$lines" \
        --argjson size "$size" \
        --arg type "$type_info" \
        --arg ext "$extension" \
        --argjson tokens "$estimated_tokens" \
        '{file: $file, lines: $lines, size_bytes: $size, type: $type, extension: $ext, estimated_tokens: $tokens}'
}

#######################################
# Probe directory for file inventory
# Arguments:
#   $1 - directory path
#   $2 - max depth (default: 3)
#   $3 - extensions filter (default: ts,js,py,go,rs,sol,sh,md)
# Outputs:
#   JSON object with directory summary and files array
#######################################
context_probe_dir() {
    local dir="$1"
    local max_depth="${2:-3}"
    local extensions="${3:-ts,js,py,go,rs,sol,sh,md}"

    if [[ ! -d "$dir" ]]; then
        jq -n --arg dir "$dir" '{"error": "directory_not_found", "directory": $dir}'
        return 1
    fi

    # Build find command for extensions
    local find_args=()
    local first=true
    IFS=',' read -ra EXTS <<< "$extensions"
    for ext in "${EXTS[@]}"; do
        if [[ "$first" == "true" ]]; then
            find_args+=("-name" "*.$ext")
            first=false
        else
            find_args+=("-o" "-name" "*.$ext")
        fi
    done

    local total_lines=0
    local total_files=0
    local total_tokens=0
    local files_json="[]"

    # Find files, excluding common non-source directories
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue

        # Skip if in excluded directories
        case "$file" in
            */node_modules/*|*/.git/*|*/dist/*|*/build/*|*/__pycache__/*|*/vendor/*|*/.next/*)
                continue
                ;;
        esac

        local probe
        probe=$(context_probe_file "$file")

        # Check for probe error
        if echo "$probe" | jq -e '.error' &>/dev/null; then
            continue
        fi

        files_json=$(echo "$files_json" | jq --argjson p "$probe" '. + [$p]')
        total_files=$((total_files + 1))

        local file_lines file_tokens
        file_lines=$(echo "$probe" | jq -r '.lines')
        file_tokens=$(echo "$probe" | jq -r '.estimated_tokens')
        total_lines=$((total_lines + file_lines))
        total_tokens=$((total_tokens + file_tokens))

        # Cap at 100 files to prevent runaway probing
        if [[ "$total_files" -ge 100 ]]; then
            break
        fi
    done < <(find "$dir" -maxdepth "$max_depth" -type f \( "${find_args[@]}" \) 2>/dev/null | head -100)

    jq -n \
        --arg dir "$dir" \
        --argjson total_files "$total_files" \
        --argjson total_lines "$total_lines" \
        --argjson total_tokens "$total_tokens" \
        --argjson files "$files_json" \
        '{directory: $dir, total_files: $total_files, total_lines: $total_lines, estimated_tokens: $total_tokens, files: $files}'
}

#######################################
# Check file relevance using keyword patterns
# Arguments:
#   $1 - file path
# Outputs:
#   Relevance score 0-10
#######################################
context_check_relevance() {
    local file="$1"
    local score=0

    if [[ ! -f "$file" ]]; then
        echo "0"
        return 1
    fi

    # Get relevance keywords from config or use defaults
    local keywords
    keywords=$(get_config "context_management.relevance_keywords" "$DEFAULT_RELEVANCE_KEYWORDS")

    # Ensure we have valid JSON array
    if ! echo "$keywords" | jq -e '.' &>/dev/null; then
        keywords="$DEFAULT_RELEVANCE_KEYWORDS"
    fi

    # Count keyword occurrences (capped contribution per keyword)
    while IFS= read -r keyword; do
        [[ -z "$keyword" ]] && continue
        local count
        count=$(grep -c "$keyword" "$file" 2>/dev/null | tr -d '[:space:]' || echo "0")
        [[ -z "$count" || ! "$count" =~ ^[0-9]+$ ]] && count=0
        if [[ "$count" -gt 0 ]]; then
            # Cap at 2 points per keyword to prevent single-keyword dominance
            local points=$((count > 5 ? 2 : 1))
            score=$((score + points))
        fi
    done < <(echo "$keywords" | jq -r '.[]' 2>/dev/null)

    # Cap at 10
    [[ "$score" -gt 10 ]] && score=10

    echo "$score"
}

#######################################
# Determine if file should be fully loaded
# Arguments:
#   $1 - file path
#   $2 - probe result (optional, will probe if not provided)
# Returns:
#   0 if should load, 1 if should skip
# Outputs:
#   Decision JSON with reasoning
#######################################
context_should_load() {
    local file="$1"
    local probe="${2:-}"

    # Get probe if not provided
    if [[ -z "$probe" ]]; then
        probe=$(context_probe_file "$file")
    fi

    # Check for probe error
    if echo "$probe" | jq -e '.error' &>/dev/null; then
        jq -n \
            --arg file "$file" \
            --arg decision "skip" \
            --arg reason "File not found or unreadable" \
            --argjson probe "$probe" \
            '{file: $file, decision: $decision, reason: $reason, probe: $probe}'
        return 1
    fi

    # Get configuration thresholds
    local max_lines relevance_required
    max_lines=$(get_config "context_management.max_eager_load_lines" "$DEFAULT_MAX_EAGER_LOAD_LINES")
    relevance_required=$(get_config "context_management.require_relevance_check" "$DEFAULT_REQUIRE_RELEVANCE_CHECK")

    local lines
    lines=$(echo "$probe" | jq -r '.lines')

    # Decision logic
    local decision="load"
    local reason=""
    local relevance_score=""

    # Check 1: File size threshold
    if [[ "$lines" -gt "$max_lines" ]]; then
        if [[ "$relevance_required" == "true" ]]; then
            # Need relevance check for large files
            local relevance
            relevance=$(context_check_relevance "$file")
            relevance_score="$relevance"
            if [[ "$relevance" -lt 3 ]]; then
                decision="skip"
                reason="Large file ($lines lines) with low relevance score ($relevance/10)"
            elif [[ "$relevance" -lt 6 ]]; then
                decision="excerpt"
                reason="Large file ($lines lines) with medium relevance ($relevance/10) - use excerpts"
            else
                decision="load"
                reason="Large file but high relevance ($relevance/10)"
            fi
        else
            decision="excerpt"
            reason="File exceeds threshold ($lines > $max_lines lines)"
        fi
    else
        decision="load"
        reason="File within threshold ($lines <= $max_lines lines)"
    fi

    if [[ -n "$relevance_score" ]]; then
        jq -n \
            --arg file "$file" \
            --arg decision "$decision" \
            --arg reason "$reason" \
            --argjson relevance "$relevance_score" \
            --argjson probe "$probe" \
            '{file: $file, decision: $decision, reason: $reason, relevance_score: $relevance, probe: $probe}'
    else
        jq -n \
            --arg file "$file" \
            --arg decision "$decision" \
            --arg reason "$reason" \
            --argjson probe "$probe" \
            '{file: $file, decision: $decision, reason: $reason, probe: $probe}'
    fi

    # Return exit code based on decision (0 for load, 1 for skip/excerpt)
    # Use explicit return to avoid set -e issues in command substitution
    if [[ "$decision" == "load" ]]; then
        return 0
    else
        return 1
    fi
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
    if command -v br &>/dev/null; then
        local count
        count=$(br list --status=in_progress 2>/dev/null | wc -l || echo "0")
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
    if command -v br &>/dev/null; then
        local sync_status
        sync_status=$(br sync --status 2>/dev/null || echo "unknown")
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
    echo "     - Run: br list --status=in_progress"
    echo "     - Ensure current task is tracked"
    echo "     - Close completed beads: br close <id>"
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
# Check if semantic recovery is enabled
#######################################
is_semantic_recovery_enabled() {
    local enabled
    enabled=$(get_config "recursive_jit.recovery.semantic_enabled" "true")
    [[ "$enabled" == "true" ]]
}

#######################################
# Check if ck is preferred and available
#######################################
should_use_ck() {
    local prefer_ck
    prefer_ck=$(get_config "recursive_jit.recovery.prefer_ck" "true")
    [[ "$prefer_ck" == "true" ]] && command -v ck &>/dev/null
}

#######################################
# Semantic search using ck
#######################################
semantic_search_ck() {
    local query="$1"
    local file="$2"
    local max_results="${3:-5}"

    if ! command -v ck &>/dev/null; then
        return 1
    fi

    # Use ck hybrid search on the file
    ck --hybrid "$query" "$file" --limit "$max_results" 2>/dev/null || return 1
}

#######################################
# Keyword search using grep (fallback)
#######################################
keyword_search_grep() {
    local query="$1"
    local file="$2"
    local context_lines="${3:-5}"

    if [[ ! -f "$file" ]]; then
        return 1
    fi

    # Split query into keywords and search for each
    local keywords
    keywords=$(echo "$query" | tr '[:upper:]' '[:lower:]' | tr -s ' ' '\n' | grep -v '^$')

    # Build grep pattern from keywords (OR logic)
    local pattern=""
    while IFS= read -r word; do
        [[ -z "$word" ]] && continue
        if [[ -z "$pattern" ]]; then
            pattern="$word"
        else
            pattern="$pattern\\|$word"
        fi
    done <<< "$keywords"

    if [[ -z "$pattern" ]]; then
        return 1
    fi

    # Search with context
    grep -i -C "$context_lines" "$pattern" "$file" 2>/dev/null | head -50
}

#######################################
# Extract sections matching query from NOTES.md
#######################################
extract_relevant_sections() {
    local query="$1"
    local token_budget="$2"

    if [[ ! -f "$NOTES_FILE" ]]; then
        return 1
    fi

    local result=""
    local current_tokens=0

    # Get all section headers
    local sections
    sections=$(grep -n "^## " "$NOTES_FILE" 2>/dev/null | cut -d: -f1)

    # If ck available, use semantic search
    if should_use_ck; then
        print_info "Using ck for semantic section selection"
        local ck_results
        ck_results=$(semantic_search_ck "$query" "$NOTES_FILE" 10 2>/dev/null)
        if [[ -n "$ck_results" ]]; then
            result="$ck_results"
        fi
    fi

    # Fallback to keyword grep if no ck results
    if [[ -z "$result" ]]; then
        local fallback_to_positional
        fallback_to_positional=$(get_config "recursive_jit.recovery.fallback_to_positional" "true")

        if [[ "$fallback_to_positional" == "true" ]]; then
            print_info "Using keyword search fallback"
            result=$(keyword_search_grep "$query" "$NOTES_FILE" 3)
        fi
    fi

    # Trim to token budget (rough estimate: 4 chars = 1 token)
    local max_chars=$((token_budget * 4))
    echo "$result" | head -c "$max_chars"
}

#######################################
# Recover command
#######################################
cmd_recover() {
    local level="${1:-1}"
    local query=""

    # Parse remaining arguments
    shift || true
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --query) query="$2"; shift 2 ;;
            *)
                # Check if it looks like a level number that was passed after flags
                if [[ "$1" =~ ^[1-3]$ ]]; then
                    level="$1"
                    shift
                else
                    print_error "Unknown option: $1"
                    return 1
                fi
                ;;
        esac
    done

    echo ""
    echo -e "${CYAN}Context Recovery - Level $level${NC}"
    if [[ -n "$query" ]]; then
        echo -e "Query: ${YELLOW}$query${NC}"
    fi
    echo "================================"
    echo ""

    # Token budgets by level
    local token_budget
    case "$level" in
        1) token_budget=100 ;;
        2) token_budget=500 ;;
        3) token_budget=2000 ;;
        *)
            print_error "Invalid level: $level (use 1, 2, or 3)"
            return 1
            ;;
    esac

    # If query provided and semantic recovery enabled, use semantic selection
    if [[ -n "$query" ]] && is_semantic_recovery_enabled; then
        echo -e "${CYAN}Semantic Recovery (~$token_budget tokens)${NC}"
        echo ""

        local semantic_result
        semantic_result=$(extract_relevant_sections "$query" "$token_budget")

        if [[ -n "$semantic_result" ]]; then
            echo -e "${CYAN}Relevant sections for query:${NC}"
            echo ""
            echo "$semantic_result"
            echo ""
        else
            print_warning "No semantic matches found, falling back to positional recovery"
            query=""  # Fall through to positional
        fi
    fi

    # Positional recovery (default or fallback)
    if [[ -z "$query" ]]; then
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
                if command -v br &>/dev/null; then
                    echo -e "${CYAN}Active Beads:${NC}"
                    br list --status=in_progress 2>/dev/null || echo "  (none)"
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
        esac
    fi
}

#######################################
# Probe command - probe file or directory
#######################################
cmd_probe() {
    local target="${1:-.}"
    local json_output="false"

    shift || true
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json) json_output="true"; shift ;;
            *)
                print_error "Unknown option: $1"
                echo "Usage: context-manager.sh probe <path> [--json]"
                return 1
                ;;
        esac
    done

    if [[ -f "$target" ]]; then
        local result
        result=$(context_probe_file "$target")
        if [[ "$json_output" == "true" ]]; then
            echo "$result" | jq .
        else
            echo ""
            echo -e "${CYAN}File Probe Results${NC}"
            echo "==================="
            echo ""
            echo "  File:      $(echo "$result" | jq -r '.file')"
            echo "  Lines:     $(echo "$result" | jq -r '.lines')"
            echo "  Size:      $(echo "$result" | jq -r '.size_bytes') bytes"
            echo "  Type:      $(echo "$result" | jq -r '.type')"
            echo "  Extension: $(echo "$result" | jq -r '.extension')"
            echo "  Est. Tokens: $(echo "$result" | jq -r '.estimated_tokens')"
            echo ""
        fi
    elif [[ -d "$target" ]]; then
        local result
        result=$(context_probe_dir "$target")
        if [[ "$json_output" == "true" ]]; then
            echo "$result" | jq .
        else
            echo ""
            echo -e "${CYAN}Directory Probe Results${NC}"
            echo "========================"
            echo ""
            echo "  Directory:    $(echo "$result" | jq -r '.directory')"
            echo "  Total Files:  $(echo "$result" | jq -r '.total_files')"
            echo "  Total Lines:  $(echo "$result" | jq -r '.total_lines')"
            echo "  Est. Tokens:  $(echo "$result" | jq -r '.estimated_tokens')"
            echo ""

            # Show size category
            local total_lines
            total_lines=$(echo "$result" | jq -r '.total_lines')
            local category
            if [[ "$total_lines" -lt 10000 ]]; then
                category="Small (<10K lines) - Load all files"
            elif [[ "$total_lines" -lt 50000 ]]; then
                category="Medium (10K-50K lines) - Prioritized loading"
            else
                category="Large (>50K lines) - Probe + excerpts only"
            fi
            echo -e "  ${CYAN}Loading Strategy:${NC} $category"
            echo ""

            echo -e "${CYAN}Files Found (up to 10):${NC}"
            echo "$result" | jq -r '.files[:10][] | "  \(.lines) lines - \(.file)"' 2>/dev/null || echo "  (no files)"
            local file_count
            file_count=$(echo "$result" | jq -r '.total_files')
            if [[ "$file_count" -gt 10 ]]; then
                echo "  ... and $((file_count - 10)) more files"
            fi
            echo ""
        fi
    else
        print_error "Target not found: $target"
        return 1
    fi
}

#######################################
# Should-load command
#######################################
cmd_should_load() {
    local file="${1:-}"
    local json_output="false"

    if [[ -z "$file" ]]; then
        print_error "File path required"
        echo "Usage: context-manager.sh should-load <file> [--json]"
        return 1
    fi

    shift || true
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json) json_output="true"; shift ;;
            *)
                print_error "Unknown option: $1"
                return 1
                ;;
        esac
    done

    local result exit_code=0
    result=$(context_should_load "$file") || exit_code=$?

    if [[ "$json_output" == "true" ]]; then
        echo "$result" | jq .
    else
        local decision reason
        decision=$(echo "$result" | jq -r '.decision')
        reason=$(echo "$result" | jq -r '.reason')

        echo ""
        echo -e "${CYAN}Should Load Decision${NC}"
        echo "====================="
        echo ""
        echo "  File:     $file"

        case "$decision" in
            load)
                echo -e "  Decision: ${GREEN}LOAD${NC} (fully read)"
                ;;
            excerpt)
                echo -e "  Decision: ${YELLOW}EXCERPT${NC} (use grep excerpts)"
                ;;
            skip)
                echo -e "  Decision: ${RED}SKIP${NC} (don't load)"
                ;;
        esac
        echo "  Reason:   $reason"

        # Show relevance if available
        local relevance
        relevance=$(echo "$result" | jq -r '.relevance_score // empty')
        if [[ -n "$relevance" ]]; then
            echo "  Relevance: $relevance/10"
        fi
        echo ""
    fi

    return $exit_code
}

#######################################
# Relevance command
#######################################
cmd_relevance() {
    local file="${1:-}"
    local json_output="false"

    if [[ -z "$file" ]]; then
        print_error "File path required"
        echo "Usage: context-manager.sh relevance <file> [--json]"
        return 1
    fi

    shift || true
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json) json_output="true"; shift ;;
            *)
                print_error "Unknown option: $1"
                return 1
                ;;
        esac
    done

    if [[ ! -f "$file" ]]; then
        print_error "File not found: $file"
        return 1
    fi

    local score
    score=$(context_check_relevance "$file")

    if [[ "$json_output" == "true" ]]; then
        jq -n --arg file "$file" --argjson score "$score" '{file: $file, relevance_score: $score, max_score: 10}'
    else
        echo ""
        echo -e "${CYAN}Relevance Score${NC}"
        echo "================"
        echo ""
        echo "  File:  $file"
        echo "  Score: $score/10"

        # Interpretation
        local interpretation
        if [[ "$score" -lt 3 ]]; then
            interpretation="Low relevance - likely skip or excerpt"
        elif [[ "$score" -lt 6 ]]; then
            interpretation="Medium relevance - consider excerpts for large files"
        else
            interpretation="High relevance - load fully"
        fi
        echo "  Level: $interpretation"
        echo ""
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
        probe)
            check_dependencies || exit 1
            cmd_probe "$@"
            ;;
        should-load)
            check_dependencies || exit 1
            cmd_should_load "$@"
            ;;
        relevance)
            check_dependencies || exit 1
            cmd_relevance "$@"
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
