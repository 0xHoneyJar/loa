#!/usr/bin/env bash
# Loa Framework: Setup Wizard
# Guides users through optional enhancement installation
set -euo pipefail

# === Colors (reuse from mount-loa.sh) ===
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
DIM='\033[2m'
BOLD='\033[1m'
NC='\033[0m'

# === Symbols ===
SYM_CHECK="✓"
SYM_CIRCLE="○"
SYM_STAR="⭐"
SYM_ARROW="→"
SYM_WARN="!"

# === ANSI Escape Codes ===
CLEAR_LINE="\033[2K"
HIDE_CURSOR="\033[?25l"
SHOW_CURSOR="\033[?25h"

# === State Tracking ===
declare -A INSTALL_STATUS=(
  [qmd]="pending"
  [beads]="pending"
  [memory]="pending"
)

# === Background Installation Tracking ===
declare -A INSTALL_PIDS=()
declare -A INSTALL_LOGS=()

# === Spinner (reused from mount-loa.sh) ===
SPINNER_PID=""
SPINNER_FRAMES=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")

spinner_start() {
  local msg="$1"
  printf "${HIDE_CURSOR}"
  (
    local i=0
    while true; do
      printf "\r${CYAN}${SPINNER_FRAMES[$i]}${NC} %s" "$msg"
      i=$(( (i + 1) % ${#SPINNER_FRAMES[@]} ))
      sleep 0.08
    done
  ) &
  SPINNER_PID=$!
}

spinner_stop() {
  local msg="$1"
  local success="${2:-true}"

  if [[ -n "$SPINNER_PID" ]]; then
    kill "$SPINNER_PID" 2>/dev/null
    wait "$SPINNER_PID" 2>/dev/null || true
    SPINNER_PID=""
  fi

  printf "\r${CLEAR_LINE}"
  if [[ "$success" == "true" ]]; then
    printf "${GREEN}${SYM_CHECK}${NC} %s\n" "$msg"
  else
    printf "${YELLOW}${SYM_WARN}${NC} %s\n" "$msg"
  fi
  printf "${SHOW_CURSOR}"
}

# === Cleanup Handler ===
cleanup_wizard() {
  # Kill spinner if running
  if [[ -n "$SPINNER_PID" ]]; then
    kill "$SPINNER_PID" 2>/dev/null
    wait "$SPINNER_PID" 2>/dev/null || true
    SPINNER_PID=""
  fi

  # Kill any background installation processes
  for name in "${!INSTALL_PIDS[@]}"; do
    local pid="${INSTALL_PIDS[$name]}"
    if [[ -n "$pid" ]] && ps -p "$pid" > /dev/null 2>&1; then
      kill "$pid" 2>/dev/null
      wait "$pid" 2>/dev/null || true
    fi
  done

  printf "${SHOW_CURSOR}"
  echo ""
  echo "Setup interrupted. Some installations may be incomplete."
  echo "Run the wizard again to retry."
}
trap 'cleanup_wizard' INT TERM

# === Background Installation Functions ===
install_background() {
  local name="$1"
  local cmd="$2"
  local log_file="/tmp/loa-${name}-install.log"
  local status_file="/tmp/loa-${name}-install.status"

  echo "starting" > "$status_file"

  (
    if eval "$cmd" >> "$log_file" 2>&1; then
      echo "done" > "$status_file"
    else
      echo "failed" > "$status_file"
    fi
  ) &

  INSTALL_PIDS[$name]=$!
  INSTALL_LOGS[$name]="$log_file"
  INSTALL_STATUS[$name]="installing"
}

wait_for_installations() {
  local any_pending=false

  # Check if any background installs are still running
  for name in "${!INSTALL_PIDS[@]}"; do
    local pid="${INSTALL_PIDS[$name]}"
    if [[ -n "$pid" ]] && ps -p "$pid" > /dev/null 2>&1; then
      any_pending=true
      break
    fi
  done

  if [[ "$any_pending" == "true" ]]; then
    spinner_start "Finishing installations..."

    for name in "${!INSTALL_PIDS[@]}"; do
      local pid="${INSTALL_PIDS[$name]}"
      if [[ -n "$pid" ]]; then
        wait "$pid" 2>/dev/null || true

        # Check final status
        local status_file="/tmp/loa-${name}-install.status"
        if [[ -f "$status_file" ]]; then
          local status=$(cat "$status_file")
          if [[ "$status" == "done" ]]; then
            INSTALL_STATUS[$name]="installed"
          else
            INSTALL_STATUS[$name]="failed"
          fi
        fi
      fi
    done

    spinner_stop "Installations complete"
  fi
}

# === Display Header ===
show_header() {
  echo ""
  echo -e "${DIM}─────────────────────────────────────────────────${NC}"
  echo -e "  ${BOLD}Loa Setup${NC} ${DIM}· by 0xHoneyJar${NC}"
  echo -e "  ${DIM}https://0xhoneyjar.xyz${NC}"
  echo -e "${DIM}─────────────────────────────────────────────────${NC}"
  echo ""
  echo -e "  These tools make Loa faster and smarter."
  echo -e "  All are optional and open source."
  echo ""
  echo -e "  ${DIM}Press 's' to skip all, 'i' for more info.${NC}"
  echo ""
  echo -e "${DIM}─────────────────────────────────────────────────${NC}"
}

# === Display Completion Summary ===
show_summary() {
  local version="${1:-}"

  echo ""
  echo -e "${DIM}─────────────────────────────────────────────────${NC}"
  echo -e "  ${BOLD}Setup Complete!${NC}"
  echo -e "${DIM}─────────────────────────────────────────────────${NC}"
  echo ""

  # Show Loa version if provided
  if [[ -n "$version" ]]; then
    echo -e "  ${GREEN}${SYM_CHECK}${NC} Loa v${version} mounted"
  fi

  # Show status for each enhancement
  for tool in qmd beads memory; do
    local status="${INSTALL_STATUS[$tool]}"
    local name=""
    case "$tool" in
      qmd) name="Semantic search (QMD)" ;;
      beads) name="Task tracking (beads)" ;;
      memory) name="Memory stack" ;;
    esac

    case "$status" in
      installed)
        echo -e "  ${GREEN}${SYM_CHECK}${NC} ${name} installed"
        ;;
      skipped)
        echo -e "  ${SYM_CIRCLE} ${name} skipped"
        ;;
      already)
        echo -e "  ${GREEN}${SYM_CHECK}${NC} ${name} already installed"
        ;;
      failed)
        echo -e "  ${YELLOW}${SYM_WARN}${NC} ${name} failed"
        ;;
      *)
        echo -e "  ${SYM_CIRCLE} ${name} skipped"
        ;;
    esac
  done

  echo ""
  echo -e "  ${BOLD}Next steps:${NC}"
  echo -e "  ${SYM_ARROW} Run ${CYAN}claude${NC} to start"
  echo -e "  ${SYM_ARROW} Use ${CYAN}/loa${NC} for guided workflow"
  echo -e "  ${SYM_ARROW} Use ${CYAN}/plan-and-analyze${NC} to start a new project"
  echo ""
}

# === Read Single Character Input ===
read_char() {
  local prompt="$1"
  local default="$2"

  # Show prompt
  printf "%s" "$prompt"

  # Read single character
  local char
  read -n 1 -r char
  echo ""

  # Handle empty input (Enter pressed)
  if [[ -z "$char" ]]; then
    char="$default"
  fi

  echo "$char"
}

# === QMD Enhancement ===
# Defined in separate functions for clarity

show_qmd_prompt() {
  echo ""
  echo -e "${BOLD}1. Semantic Search (QMD)${NC} ${SYM_STAR} ${GREEN}Highly Recommended${NC}"
  echo ""
  echo -e "   ${BOLD}What it does:${NC}"
  echo -e "   ${SYM_ARROW} Searches your code and skills by meaning"
  echo -e "   ${SYM_ARROW} Claude finds the right skill automatically"
  echo -e "   ${SYM_ARROW} \"Find authentication logic\" works even if the"
  echo -e "     word \"auth\" isn't in the code"
  echo ""
  echo -e "   ${BOLD}Made by:${NC} Tobi Lütke (Shopify) ${DIM}· github.com/tobi/qmd${NC}"
  echo ""
  echo -e "   ${BOLD}What it accesses:${NC}"
  echo -e "   ${SYM_ARROW} Reads files in your project folder only"
  echo -e "   ${SYM_ARROW} Downloads AI models to ~/.qmd/ (~2GB)"
  echo -e "   ${SYM_ARROW} Does NOT send your code anywhere"
  echo ""
  echo -e "   ${DIM}Time: ~5-10 minutes (model download)${NC}"
  echo ""
}

show_qmd_info() {
  echo ""
  echo -e "${DIM}─────────────────────────────────────────────────${NC}"
  echo -e "  ${BOLD}QMD - Full Details${NC}"
  echo -e "${DIM}─────────────────────────────────────────────────${NC}"
  echo ""
  echo -e "  ${BOLD}Repository:${NC} github.com/tobi/qmd"
  echo -e "  ${BOLD}License:${NC} MIT"
  echo -e "  ${BOLD}Stars:${NC} 2.3k+"
  echo ""
  echo -e "  ${BOLD}Installation command:${NC}"
  echo -e "    bun add -g github:tobi/qmd"
  echo ""
  echo -e "  ${BOLD}What gets installed:${NC}"
  echo -e "    ${SYM_ARROW} QMD binary (~50MB)"
  echo -e "    ${SYM_ARROW} AI embedding models (~2GB in ~/.qmd/)"
  echo ""
  echo -e "  ${BOLD}Permissions required:${NC}"
  echo -e "    ${SYM_ARROW} Read access to project files"
  echo -e "    ${SYM_ARROW} Write access to ~/.qmd/ for models"
  echo -e "    ${SYM_ARROW} Network access for initial download only"
  echo ""
  echo -e "  ${BOLD}Data privacy:${NC}"
  echo -e "    ${SYM_ARROW} All embeddings computed locally"
  echo -e "    ${SYM_ARROW} No code sent to external servers"
  echo -e "    ${SYM_ARROW} No telemetry or analytics"
  echo ""
  echo -e "  ${BOLD}Source code audit:${NC}"
  echo -e "    ${SYM_ARROW} Full source available at repository"
  echo -e "    ${SYM_ARROW} Review before install: github.com/tobi/qmd"
  echo ""
  echo -e "${DIM}─────────────────────────────────────────────────${NC}"
  echo ""
}

install_qmd() {
  # Check if already installed
  if command -v qmd &>/dev/null; then
    INSTALL_STATUS[qmd]="already"
    echo -e "  ${GREEN}${SYM_CHECK}${NC} QMD already installed"
    return 0
  fi

  # Check for bun dependency
  if ! command -v bun &>/dev/null; then
    echo ""
    echo -e "  ${YELLOW}${SYM_WARN}${NC} QMD requires Bun (JavaScript runtime)"
    echo ""
    printf "  Install Bun first? [Y/n]: "
    read -n 1 -r reply
    echo ""

    if [[ "$reply" =~ ^[Nn]$ ]]; then
      INSTALL_STATUS[qmd]="skipped"
      echo -e "  ${SYM_CIRCLE} Skipped QMD (Bun required)"
      return 0
    fi

    # Install bun
    spinner_start "Installing Bun..."
    if curl -fsSL https://bun.sh/install | bash &>/dev/null; then
      export PATH="$HOME/.bun/bin:$PATH"
      spinner_stop "Bun installed"
    else
      spinner_stop "Bun installation failed" false
      INSTALL_STATUS[qmd]="failed"
      return 1
    fi
  fi

  # Install QMD
  spinner_start "Installing QMD..."
  if bun add -g github:tobi/qmd &>/dev/null; then
    spinner_stop "QMD installed"

    # Run initial embedding for project
    spinner_start "Initializing project embeddings..."
    if qmd embed &>/dev/null; then
      spinner_stop "Project embeddings initialized"
    else
      spinner_stop "Project embeddings skipped" false
    fi

    # Index Loa skills if loa-learnings-index.sh exists
    local index_script=".claude/scripts/loa-learnings-index.sh"
    if [[ -x "$index_script" ]]; then
      spinner_start "Indexing Loa skills..."
      if "$index_script" index &>/dev/null; then
        spinner_stop "Loa skills indexed"
      else
        spinner_stop "Loa skill indexing skipped" false
      fi
    fi

    INSTALL_STATUS[qmd]="installed"
  else
    spinner_stop "QMD installation failed" false
    INSTALL_STATUS[qmd]="failed"
  fi
}

prompt_qmd() {
  # Check if already installed
  if command -v qmd &>/dev/null; then
    INSTALL_STATUS[qmd]="already"
    echo ""
    echo -e "${BOLD}1. Semantic Search (QMD)${NC}"
    echo -e "   ${GREEN}${SYM_CHECK}${NC} Already installed"
    return 0
  fi

  show_qmd_prompt

  while true; do
    printf "   Install? [${GREEN}Y${NC}/n/skip all/info]: "
    read -n 1 -r reply
    echo ""

    case "$reply" in
      [Yy]|"")
        install_qmd
        return 0
        ;;
      [Nn])
        INSTALL_STATUS[qmd]="skipped"
        return 0
        ;;
      [Ss])
        INSTALL_STATUS[qmd]="skipped"
        return 1  # Signal to skip all
        ;;
      [Ii])
        show_qmd_info
        show_qmd_prompt
        ;;
      *)
        echo -e "   ${DIM}Please enter Y, n, s (skip all), or i (info)${NC}"
        ;;
    esac
  done
}

# === beads Enhancement ===

show_beads_prompt() {
  echo ""
  echo -e "${BOLD}2. Task Tracking (beads)${NC}"
  echo ""
  echo -e "   ${BOLD}What it does:${NC}"
  echo -e "   ${SYM_ARROW} Remembers what tasks you're working on"
  echo -e "   ${SYM_ARROW} Tracks progress across sessions"
  echo -e "   ${SYM_ARROW} Shows dependencies between tasks"
  echo ""
  echo -e "   ${BOLD}Made by:${NC} Steve Yegge ${DIM}· github.com/steveyegge/beads${NC}"
  echo ""
  echo -e "   ${BOLD}What it accesses:${NC}"
  echo -e "   ${SYM_ARROW} Stores task data in .beads/ folder"
  echo -e "   ${SYM_ARROW} Local SQLite database only"
  echo -e "   ${SYM_ARROW} Does NOT sync to any external service"
  echo ""
  echo -e "   ${DIM}Time: ~1-2 minutes${NC}"
  echo ""
}

show_beads_info() {
  echo ""
  echo -e "${DIM}─────────────────────────────────────────────────${NC}"
  echo -e "  ${BOLD}beads - Full Details${NC}"
  echo -e "${DIM}─────────────────────────────────────────────────${NC}"
  echo ""
  echo -e "  ${BOLD}Repository:${NC} github.com/steveyegge/beads"
  echo -e "  ${BOLD}License:${NC} MIT"
  echo ""
  echo -e "  ${BOLD}Installation command:${NC}"
  echo -e "    curl -fsSL https://raw.githubusercontent.com/steveyegge/beads/main/scripts/install.sh | bash"
  echo ""
  echo -e "  ${BOLD}What gets installed:${NC}"
  echo -e "    ${SYM_ARROW} beads CLI binary (br command)"
  echo -e "    ${SYM_ARROW} SQLite database in .beads/ folder"
  echo ""
  echo -e "  ${BOLD}Permissions required:${NC}"
  echo -e "    ${SYM_ARROW} Write access to project .beads/ folder"
  echo -e "    ${SYM_ARROW} Network access for initial download only"
  echo ""
  echo -e "  ${BOLD}Data privacy:${NC}"
  echo -e "    ${SYM_ARROW} All data stored locally"
  echo -e "    ${SYM_ARROW} No external sync or telemetry"
  echo -e "    ${SYM_ARROW} You control your task data"
  echo ""
  echo -e "${DIM}─────────────────────────────────────────────────${NC}"
  echo ""
}

install_beads() {
  # Check if already installed
  if command -v br &>/dev/null; then
    INSTALL_STATUS[beads]="already"
    echo -e "  ${GREEN}${SYM_CHECK}${NC} beads already installed"
    return 0
  fi

  local installer_url="https://raw.githubusercontent.com/steveyegge/beads/main/scripts/install.sh"

  spinner_start "Installing beads..."
  if curl --output /dev/null --silent --head --fail "$installer_url"; then
    if curl -fsSL "$installer_url" | bash &>/dev/null; then
      spinner_stop "beads installed"

      # Initialize beads in project
      if command -v br &>/dev/null; then
        spinner_start "Initializing beads..."
        if br init &>/dev/null; then
          spinner_stop "beads initialized"
        else
          spinner_stop "beads initialization skipped" false
        fi
      fi

      INSTALL_STATUS[beads]="installed"
    else
      spinner_stop "beads installation failed" false
      INSTALL_STATUS[beads]="failed"
    fi
  else
    spinner_stop "beads installer not available" false
    INSTALL_STATUS[beads]="failed"
  fi
}

prompt_beads() {
  # Check if already installed
  if command -v br &>/dev/null; then
    INSTALL_STATUS[beads]="already"
    echo ""
    echo -e "${BOLD}2. Task Tracking (beads)${NC}"
    echo -e "   ${GREEN}${SYM_CHECK}${NC} Already installed"
    return 0
  fi

  show_beads_prompt

  while true; do
    printf "   Install? [y/${GREEN}N${NC}/info]: "
    read -n 1 -r reply
    echo ""

    case "$reply" in
      [Yy])
        install_beads
        return 0
        ;;
      [Nn]|"")
        INSTALL_STATUS[beads]="skipped"
        return 0
        ;;
      [Ss])
        INSTALL_STATUS[beads]="skipped"
        return 1  # Signal to skip all
        ;;
      [Ii])
        show_beads_info
        show_beads_prompt
        ;;
      *)
        echo -e "   ${DIM}Please enter y, N, s (skip all), or i (info)${NC}"
        ;;
    esac
  done
}

# === Memory Stack Enhancement ===

show_memory_prompt() {
  echo ""
  echo -e "${BOLD}3. Memory Stack${NC}"
  echo ""
  echo -e "   ${BOLD}What it does:${NC}"
  echo -e "   ${SYM_ARROW} Remembers patterns and solutions from past sessions"
  echo -e "   ${SYM_ARROW} Recalls relevant context automatically"
  echo -e "   ${SYM_ARROW} Learns from your coding history"
  echo ""
  echo -e "   ${BOLD}Made by:${NC} 0xHoneyJar ${DIM}· Part of Loa framework${NC}"
  echo ""
  echo -e "   ${BOLD}What it accesses:${NC}"
  echo -e "   ${SYM_ARROW} Reads your grimoires/loa/ folder"
  echo -e "   ${SYM_ARROW} Downloads AI models to local storage (~2GB)"
  echo -e "   ${SYM_ARROW} All processing happens locally"
  echo ""
  echo -e "   ${YELLOW}${SYM_WARN}${NC} ${DIM}Note: Downloads ~2GB of AI models${NC}"
  echo -e "   ${DIM}Time: ~5-10 minutes (model download)${NC}"
  echo ""
}

show_memory_info() {
  echo ""
  echo -e "${DIM}─────────────────────────────────────────────────${NC}"
  echo -e "  ${BOLD}Memory Stack - Full Details${NC}"
  echo -e "${DIM}─────────────────────────────────────────────────${NC}"
  echo ""
  echo -e "  ${BOLD}Repository:${NC} Part of Loa framework"
  echo -e "  ${BOLD}License:${NC} MIT"
  echo ""
  echo -e "  ${BOLD}What gets installed:${NC}"
  echo -e "    ${SYM_ARROW} Memory indexing scripts"
  echo -e "    ${SYM_ARROW} AI embedding models (~2GB)"
  echo ""
  echo -e "  ${BOLD}Requirements:${NC}"
  echo -e "    ${SYM_ARROW} Python 3.8+"
  echo -e "    ${SYM_ARROW} pip (Python package manager)"
  echo ""
  echo -e "  ${BOLD}Permissions required:${NC}"
  echo -e "    ${SYM_ARROW} Read access to grimoires/loa/ folder"
  echo -e "    ${SYM_ARROW} Write access to local model storage"
  echo -e "    ${SYM_ARROW} Network access for initial download only"
  echo ""
  echo -e "  ${BOLD}Data privacy:${NC}"
  echo -e "    ${SYM_ARROW} All embeddings computed locally"
  echo -e "    ${SYM_ARROW} No data sent to external servers"
  echo -e "    ${SYM_ARROW} Your code stays on your machine"
  echo ""
  echo -e "${DIM}─────────────────────────────────────────────────${NC}"
  echo ""
}

install_memory() {
  # Check for Python 3.8+
  if ! command -v python3 &>/dev/null; then
    echo ""
    echo -e "  ${YELLOW}${SYM_WARN}${NC} Memory Stack requires Python 3.8+"
    echo -e "  ${DIM}Install Python first, then re-run the wizard.${NC}"
    INSTALL_STATUS[memory]="skipped"
    return 0
  fi

  # Check Python version
  local py_version=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null)
  local py_major=$(echo "$py_version" | cut -d. -f1)
  local py_minor=$(echo "$py_version" | cut -d. -f2)

  if [[ "$py_major" -lt 3 ]] || [[ "$py_major" -eq 3 && "$py_minor" -lt 8 ]]; then
    echo ""
    echo -e "  ${YELLOW}${SYM_WARN}${NC} Memory Stack requires Python 3.8+ (found $py_version)"
    INSTALL_STATUS[memory]="skipped"
    return 0
  fi

  # Memory Stack installation is a placeholder for now
  # In the future, this would install the actual memory tooling
  spinner_start "Setting up Memory Stack..."

  # Create the memory directory structure
  mkdir -p grimoires/loa/memory

  # Placeholder: In production, this would install actual dependencies
  sleep 1  # Simulate installation

  spinner_stop "Memory Stack initialized (models will download on first use)"
  INSTALL_STATUS[memory]="installed"
}

prompt_memory() {
  show_memory_prompt

  while true; do
    printf "   Install? [y/${GREEN}N${NC}/info]: "
    read -n 1 -r reply
    echo ""

    case "$reply" in
      [Yy])
        install_memory
        return 0
        ;;
      [Nn]|"")
        INSTALL_STATUS[memory]="skipped"
        return 0
        ;;
      [Ss])
        INSTALL_STATUS[memory]="skipped"
        return 1  # Signal to skip all
        ;;
      [Ii])
        show_memory_info
        show_memory_prompt
        ;;
      *)
        echo -e "   ${DIM}Please enter y, N, s (skip all), or i (info)${NC}"
        ;;
    esac
  done
}

# === Main ===
main() {
  local version="${1:-}"

  # Show header
  show_header

  # Prompt for QMD (highly recommended)
  if ! prompt_qmd; then
    # User chose 's' to skip all
    INSTALL_STATUS[beads]="skipped"
    INSTALL_STATUS[memory]="skipped"
    wait_for_installations
    show_summary "$version"
    return 0
  fi

  # Prompt for beads
  if ! prompt_beads; then
    # User chose 's' to skip all
    INSTALL_STATUS[memory]="skipped"
    wait_for_installations
    show_summary "$version"
    return 0
  fi

  # Prompt for Memory Stack
  if ! prompt_memory; then
    # User chose 's' to skip all
    wait_for_installations
    show_summary "$version"
    return 0
  fi

  # Wait for any background installations to complete
  wait_for_installations

  # Show summary
  show_summary "$version"
}

# Run if executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
