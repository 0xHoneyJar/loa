#!/usr/bin/env bash
# Loa Framework: Prerequisites Checker
# Validates required and optional tools with helpful guidance
set -euo pipefail

# === Colors ===
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
DIM='\033[2m'
BOLD='\033[1m'
NC='\033[0m'

# === Symbols ===
SYM_CHECK="✓"
SYM_CROSS="✗"
SYM_CIRCLE="○"
SYM_WARN="!"

# === State Tracking ===
REQUIRED_FAILED=false

# === Check Required Tool ===
# Returns 0 if found, 1 if missing
check_required() {
  local tool="$1"
  local purpose="$2"
  local install_mac="$3"
  local install_linux="$4"

  if command -v "$tool" &>/dev/null; then
    echo -e "${GREEN}${SYM_CHECK}${NC} ${BOLD}$tool${NC}"
    return 0
  else
    echo -e "${RED}${SYM_CROSS}${NC} ${BOLD}$tool${NC} - ${RED}NOT FOUND${NC}"
    echo -e "   ${DIM}What it does:${NC} $purpose"
    echo -e "   ${DIM}Install:${NC}"
    echo -e "     ${CYAN}macOS:${NC}  $install_mac"
    echo -e "     ${CYAN}Linux:${NC}  $install_linux"
    echo ""
    REQUIRED_FAILED=true
    return 1
  fi
}

# === Check Optional Tool ===
# Always returns 0, just reports status
check_optional() {
  local tool="$1"
  local purpose="$2"

  if command -v "$tool" &>/dev/null; then
    local version=$($tool --version 2>/dev/null | head -1 || echo "installed")
    echo -e "${GREEN}${SYM_CHECK}${NC} ${BOLD}$tool${NC} ${DIM}($version)${NC}"
  else
    echo -e "${SYM_CIRCLE} ${BOLD}$tool${NC} ${DIM}- not installed${NC}"
    echo -e "   ${DIM}$purpose${NC}"
  fi
}

# === Main ===
main() {
  local verbose="${1:-false}"

  echo ""
  echo -e "${BOLD}Checking Loa prerequisites...${NC}"
  echo ""

  # === Required Tools ===
  echo -e "${BOLD}Required:${NC}"
  echo ""

  check_required "git" \
    "Version control for syncing framework updates" \
    "brew install git" \
    "apt install git" || true

  check_required "jq" \
    "Reads JSON settings files and API responses" \
    "brew install jq" \
    "apt install jq" || true

  check_required "yq" \
    "Reads YAML configuration files" \
    "brew install yq" \
    "pip install yq" || true

  echo ""

  # === Optional Tools ===
  if [[ "$verbose" == "true" ]] || [[ "$verbose" == "-v" ]] || [[ "$verbose" == "--verbose" ]]; then
    echo -e "${BOLD}Optional enhancements:${NC}"
    echo ""

    check_optional "qmd" \
      "Semantic code search - makes agent searches faster and smarter"

    check_optional "br" \
      "Task tracking - remembers what you're working on across sessions"

    check_optional "bun" \
      "JavaScript runtime - required for QMD installation"

    check_optional "python3" \
      "Python runtime - required for Memory Stack"

    echo ""
  fi

  # === Summary ===
  if [[ "$REQUIRED_FAILED" == "true" ]]; then
    echo -e "${RED}${SYM_CROSS}${NC} ${BOLD}Missing required tools${NC}"
    echo -e "   Please install the missing tools above before continuing."
    echo ""
    return 1
  else
    echo -e "${GREEN}${SYM_CHECK}${NC} ${BOLD}All required tools found${NC}"
    echo ""
    return 0
  fi
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
