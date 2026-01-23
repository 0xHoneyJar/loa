#!/usr/bin/env bash
# Upgrade Banner - Display completion message with cyberpunk flair
# Part of the Loa framework
#
# Usage: upgrade-banner.sh <old_version> <new_version> [--json]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

# Colors
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
MAGENTA='\033[0;35m'
BLUE='\033[0;34m'
DIM='\033[2m'
BOLD='\033[1m'
NC='\033[0m'

# Neuromancer/cyberpunk quotes - the Matrix is everywhere
# These rotate based on a hash of username + date for variety
QUOTES=(
    # William Gibson - Neuromancer
    "The sky above the port was the color of television, tuned to a dead channel."
    "Cyberspace. A consensual hallucination."
    "The future is already here — it's just not evenly distributed."
    "When you want to know how things really work, study them when they're coming apart."
    "Time moves in one direction, memory in another."

    # William Gibson - Other works
    "The street finds its own uses for things."
    "Before you diagnose yourself with depression or low self-esteem, first make sure you are not, in fact, surrounded by assholes."
    "Language is a virus from outer space."

    # Blade Runner / Philip K. Dick
    "All those moments will be lost in time, like tears in rain."
    "I've seen things you people wouldn't believe."
    "More human than human is our motto."
    "The light that burns twice as bright burns half as long."

    # The Matrix
    "There is no spoon."
    "Free your mind."
    "What is real? How do you define real?"
    "I know kung fu."
    "Welcome to the desert of the real."

    # Ghost in the Shell
    "Your effort to remain what you are is what limits you."
    "If we all reacted the same way, we'd be predictable."
    "We weep for a bird's cry, but not for a fish's blood."

    # Dune (proto-cyberpunk philosophy)
    "Fear is the mind-killer."
    "The mystery of life isn't a problem to solve, but a reality to experience."
    "Without change something sleeps inside us, and seldom awakens."

    # Original Loa-themed
    "The code remembers what the context forgets."
    "In the sprawl of tokens, every decision is a commit to the universe."
    "Jack in. The grimoire awaits."
    "Synthesis complete. Reality updated."
    "Your agents ride the data like Case rode the matrix."
    "The ledger is lossless. The memory persists."
)

# Get a deterministic but rotating quote based on user + week
get_quote() {
    local seed="${USER:-unknown}$(date +%Y-%W)"
    local hash=$(echo -n "$seed" | sha256sum | cut -c1-8)
    local index=$((16#$hash % ${#QUOTES[@]}))
    echo "${QUOTES[$index]}"
}

# Parse version to extract major.minor for changelog lookup
parse_version() {
    echo "$1" | sed 's/^v//' | cut -d. -f1,2
}

# Get highlights for a version from CHANGELOG or release notes
get_version_highlights() {
    local version="$1"
    local changelog="${PROJECT_ROOT}/CHANGELOG.md"
    local highlights=()

    # Try to extract from CHANGELOG.md if it exists
    if [[ -f "$changelog" ]]; then
        # Look for version section and extract bullet points
        local in_section=false
        while IFS= read -r line; do
            if [[ "$line" =~ ^##.*$version ]]; then
                in_section=true
                continue
            fi
            if [[ "$in_section" == true ]]; then
                # Stop at next version header
                if [[ "$line" =~ ^## ]]; then
                    break
                fi
                # Extract feature lines (start with - or *)
                if [[ "$line" =~ ^[[:space:]]*[-\*][[:space:]]+ ]]; then
                    # Clean up the line
                    local clean=$(echo "$line" | sed 's/^[[:space:]]*[-\*][[:space:]]*//')
                    # Only include if it looks like a feature (not a fix)
                    if [[ ! "$clean" =~ ^[Ff]ix ]]; then
                        highlights+=("$clean")
                    fi
                fi
            fi
        done < "$changelog"
    fi

    # If we found highlights, return them (max 5)
    if [[ ${#highlights[@]} -gt 0 ]]; then
        local count=0
        for h in "${highlights[@]}"; do
            echo "$h"
            ((count++))
            [[ $count -ge 5 ]] && break
        done
        return 0
    fi

    # Fallback: return empty (caller handles)
    return 1
}

# Display the banner
# Args: old_version new_version [--json] [--mount]
show_banner() {
    local old_version="$1"
    local new_version="$2"
    local json_mode=false
    local mount_mode=false

    # Parse optional flags
    shift 2
    for arg in "$@"; do
        case "$arg" in
            --json) json_mode=true ;;
            --mount) mount_mode=true ;;
        esac
    done

    local quote=$(get_quote)

    if [[ "$json_mode" == "true" ]]; then
        # JSON output
        local highlights_json="[]"
        local highlights_arr=()
        while IFS= read -r line; do
            [[ -n "$line" ]] && highlights_arr+=("$line")
        done < <(get_version_highlights "$new_version" 2>/dev/null || true)

        if [[ ${#highlights_arr[@]} -gt 0 ]]; then
            highlights_json=$(printf '%s\n' "${highlights_arr[@]}" | jq -R . | jq -s .)
        fi

        jq -n \
            --arg old "$old_version" \
            --arg new "$new_version" \
            --arg quote "$quote" \
            --argjson highlights "$highlights_json" \
            '{
                status: "success",
                old_version: $old,
                new_version: $new,
                quote: $quote,
                highlights: $highlights
            }'
        return
    fi

    # ASCII art banner
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}                                                                      ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${GREEN}${BOLD}▓█████▄  ▒█████   ███▄    █ ▓█████${NC}                                 ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${GREEN}${BOLD}▒██▀ ██▌▒██▒  ██▒ ██ ▀█   █ ▓█   ▀${NC}                                 ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${GREEN}${BOLD}░██   █▌▒██░  ██▒▓██  ▀█ ██▒▒███${NC}                                   ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${GREEN}${BOLD}░▓█▄   ▌▒██   ██░▓██▒  ▐▌██▒▒▓█  ▄${NC}                                 ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${GREEN}${BOLD}░▒████▓ ░ ████▓▒░▒██░   ▓██░░▒████▒${NC}                                ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                                                                      ${CYAN}║${NC}"
    if [[ "$mount_mode" == "true" ]]; then
        echo -e "${CYAN}║${NC}  ${BOLD}Loa Framework Successfully Mounted${NC}                                 ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${DIM}Version ${new_version}${NC}                                                           ${CYAN}║${NC}"
    else
        echo -e "${CYAN}║${NC}  ${BOLD}Loa Framework Upgrade Complete${NC}                                     ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${DIM}v${old_version} → v${new_version}${NC}                                                        ${CYAN}║${NC}"
    fi
    echo -e "${CYAN}║${NC}                                                                      ${CYAN}║${NC}"
    echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════════╣${NC}"

    # Try to show highlights
    local has_highlights=false
    local highlights=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && highlights+=("$line")
    done < <(get_version_highlights "$new_version" 2>/dev/null || true)

    if [[ ${#highlights[@]} -gt 0 ]]; then
        has_highlights=true
        echo -e "${CYAN}║${NC}                                                                      ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${YELLOW}${BOLD}What's New:${NC}                                                          ${CYAN}║${NC}"
        for h in "${highlights[@]}"; do
            # Truncate long lines
            local display="${h:0:60}"
            [[ ${#h} -gt 60 ]] && display="${display}..."
            printf "${CYAN}║${NC}  ${BLUE}•${NC} %-66s ${CYAN}║${NC}\n" "$display"
        done
        echo -e "${CYAN}║${NC}                                                                      ${CYAN}║${NC}"
    fi

    echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}                                                                      ${CYAN}║${NC}"

    # Word-wrap the quote to fit in the box (max ~62 chars per line)
    local quote_lines=()
    local current_line=""
    for word in $quote; do
        if [[ ${#current_line} -eq 0 ]]; then
            current_line="$word"
        elif [[ $((${#current_line} + ${#word} + 1)) -le 62 ]]; then
            current_line="$current_line $word"
        else
            quote_lines+=("$current_line")
            current_line="$word"
        fi
    done
    [[ -n "$current_line" ]] && quote_lines+=("$current_line")

    # Print quote lines centered-ish
    for qline in "${quote_lines[@]}"; do
        printf "${CYAN}║${NC}  ${MAGENTA}${DIM}\"%-64s\"${NC} ${CYAN}║${NC}\n" "$qline"
    done

    echo -e "${CYAN}║${NC}                                                                      ${CYAN}║${NC}"
    echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}                                                                      ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${DIM}Next steps:${NC}                                                          ${CYAN}║${NC}"
    if [[ "$mount_mode" == "true" ]]; then
        echo -e "${CYAN}║${NC}  ${BLUE}•${NC} Run ${GREEN}claude${NC} to start Claude Code                                   ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${BLUE}•${NC} Issue ${GREEN}/ride${NC} to analyze this codebase                             ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${BLUE}•${NC} Or ${GREEN}/setup${NC} for guided project configuration                      ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}                                                                      ${CYAN}║${NC}"
        echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════════╣${NC}"
        echo -e "${CYAN}║${NC}                                                                      ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${DIM}Zone structure:${NC}                                                      ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${BLUE}•${NC} ${GREEN}.claude/${NC}           System Zone (framework-managed)              ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${BLUE}•${NC} ${GREEN}.claude/overrides/${NC} Your customizations (preserved)              ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${BLUE}•${NC} ${GREEN}grimoires/loa/${NC}     State Zone (project memory)                  ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${BLUE}•${NC} ${GREEN}.beads/${NC}            Task graph (Beads)                           ${CYAN}║${NC}"
    else
        echo -e "${CYAN}║${NC}  ${BLUE}•${NC} Run ${GREEN}/help${NC} to see available commands                             ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${BLUE}•${NC} Check ${GREEN}.claude/scripts/upgrade-health-check.sh${NC} for suggestions   ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${BLUE}•${NC} View release notes: ${DIM}github.com/0xHoneyJar/loa/releases${NC}           ${CYAN}║${NC}"
    fi
    echo -e "${CYAN}║${NC}                                                                      ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Main
main() {
    local old_version="${1:-unknown}"
    local new_version="${2:-unknown}"
    shift 2 2>/dev/null || true

    # Pass remaining args (flags) to show_banner
    show_banner "$old_version" "$new_version" "$@"
}

# Only run if executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
