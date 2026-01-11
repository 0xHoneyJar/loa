#!/usr/bin/env bash
# Loa Framework: CI/CD Validation (Enterprise Grade)
# v0.9.0 Lossless Ledger Protocol - Enhanced validation
# Exit codes: 0 = success, 1 = failure
set -euo pipefail

VERSION_FILE=".loa-version.json"
CHECKSUMS_FILE=".claude/checksums.json"
CONFIG_FILE=".loa.config.yaml"
NOTES_FILE="grimoires/loa/NOTES.md"

# v0.9.0 Protocol files
PROTOCOL_DIR=".claude/protocols"
SCRIPT_DIR=".claude/scripts"

# Disable colors in CI or non-interactive mode
if [[ "${CI:-}" == "true" ]] || [[ ! -t 1 ]]; then
  RED=''; GREEN=''; YELLOW=''; NC=''
else
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
fi

log() { echo -e "${GREEN}[loa-check]${NC} $*"; }
warn() { echo -e "${YELLOW}[loa-check]${NC} $*"; }
fail() { echo -e "${RED}[loa-check]${NC} x $*"; FAILURES=$((FAILURES + 1)); }

FAILURES=0

check_mounted() {
  echo "Checking Loa installation..."
  [[ -f "$VERSION_FILE" ]] || { fail "Loa not mounted (.loa-version.json missing)"; return; }
  [[ -d ".claude" ]] || { fail "System Zone missing (.claude/ directory)"; return; }
  log "Loa mounted: v$(jq -r '.framework_version' "$VERSION_FILE")"
}

check_integrity() {
  echo "Checking System Zone integrity (sha256)..."
  [[ -f "$CHECKSUMS_FILE" ]] || { warn "No checksums file - skipping integrity check"; return; }

  local drift=false
  while IFS= read -r file; do
    local expected=$(jq -r --arg f "$file" '.files[$f]' "$CHECKSUMS_FILE")
    [[ -z "$expected" || "$expected" == "null" ]] && continue

    if [[ -f "$file" ]]; then
      local actual=$(sha256sum "$file" | cut -d' ' -f1)
      if [[ "$expected" != "$actual" ]]; then
        fail "Tampered: $file"
        drift=true
      fi
    else
      fail "Missing: $file"
      drift=true
    fi
  done < <(jq -r '.files | keys[]' "$CHECKSUMS_FILE")

  [[ "$drift" == "false" ]] && log "Integrity verified"
}

check_schema() {
  echo "Checking schema version..."
  [[ -f "$VERSION_FILE" ]] || { warn "No version file - cannot check schema"; return; }

  local current=$(jq -r '.schema_version' "$VERSION_FILE" 2>/dev/null)
  [[ -z "$current" || "$current" == "null" ]] && { fail "No schema version in manifest"; return; }
  log "Schema version: $current"
}

check_memory() {
  echo "Checking structured memory..."
  [[ -f "$NOTES_FILE" ]] || { warn "NOTES.md missing - memory not initialized"; return; }

  # Check for required sections
  local has_sections=true
  grep -q "## Active Sub-Goals" "$NOTES_FILE" || { warn "NOTES.md missing 'Active Sub-Goals' section"; has_sections=false; }
  grep -q "## Session Continuity" "$NOTES_FILE" || { warn "NOTES.md missing 'Session Continuity' section"; has_sections=false; }
  grep -q "## Decision Log" "$NOTES_FILE" || { warn "NOTES.md missing 'Decision Log' section"; has_sections=false; }

  if [[ "$has_sections" == "true" ]]; then
    log "Structured memory present and valid"
  else
    log "Structured memory present (some sections missing)"
  fi
}

check_config() {
  echo "Checking configuration..."
  [[ -f "$CONFIG_FILE" ]] || { warn "No config file (.loa.config.yaml)"; return; }

  # Check if yq is available
  if ! command -v yq &> /dev/null; then
    warn "yq not installed - skipping config validation"
    return
  fi

  # Try Go yq first, then Python yq
  local enforcement=""
  if yq --version 2>&1 | grep -q "mikefarah"; then
    # Go yq (mikefarah/yq)
    yq eval '.' "$CONFIG_FILE" > /dev/null 2>&1 || { fail "Invalid YAML in config file"; return; }
    enforcement=$(yq eval '.integrity_enforcement // "missing"' "$CONFIG_FILE" 2>/dev/null)
  else
    # Python yq (kislyuk/yq) - uses jq syntax
    yq . "$CONFIG_FILE" > /dev/null 2>&1 || { fail "Invalid YAML in config file"; return; }
    enforcement=$(yq -r '.integrity_enforcement // "missing"' "$CONFIG_FILE" 2>/dev/null)
  fi

  [[ "$enforcement" == "missing" ]] && warn "Config missing integrity_enforcement"

  log "Configuration valid (enforcement: $enforcement)"
}

check_zones() {
  echo "Checking zone structure..."

  # State zone
  [[ -d "grimoires/loa" ]] || { warn "State zone missing (grimoires/loa/)"; }
  [[ -d "grimoires/loa/a2a" ]] || { warn "A2A directory missing"; }
  [[ -d "grimoires/loa/a2a/trajectory" ]] || { warn "Trajectory directory missing"; }

  # Beads zone
  [[ -d ".beads" ]] || { warn "Beads directory missing (.beads/)"; }

  # Skills check
  local skill_count=$(find .claude/skills -maxdepth 1 -type d 2>/dev/null | wc -l)
  skill_count=$((skill_count - 1))  # Subtract the skills directory itself
  [[ $skill_count -gt 0 ]] && log "Found $skill_count skills"

  # Overrides check
  [[ -d ".claude/overrides" ]] || warn "Overrides directory missing"

  log "Zone structure checked"
}

# =============================================================================
# v0.9.0 Lossless Ledger Protocol Checks
# =============================================================================

check_v090_protocols() {
  echo "Checking v0.9.0 protocol files..."

  local protocols_ok=true
  local required_protocols=(
    "session-continuity.md"
    "synthesis-checkpoint.md"
    "grounding-enforcement.md"
    "jit-retrieval.md"
    "attention-budget.md"
  )

  for proto in "${required_protocols[@]}"; do
    local proto_path="${PROTOCOL_DIR}/${proto}"
    if [[ ! -f "$proto_path" ]]; then
      fail "v0.9.0 protocol missing: ${proto}"
      protocols_ok=false
    elif [[ ! -s "$proto_path" ]]; then
      fail "v0.9.0 protocol empty: ${proto}"
      protocols_ok=false
    fi
  done

  [[ "$protocols_ok" == "true" ]] && log "All v0.9.0 protocol files present"
}

check_v090_scripts() {
  echo "Checking v0.9.0 script files..."

  local scripts_ok=true
  local required_scripts=(
    "grounding-check.sh"
    "synthesis-checkpoint.sh"
    "self-heal-state.sh"
  )

  for script in "${required_scripts[@]}"; do
    local script_path="${SCRIPT_DIR}/${script}"
    if [[ ! -f "$script_path" ]]; then
      fail "v0.9.0 script missing: ${script}"
      scripts_ok=false
    elif [[ ! -x "$script_path" ]]; then
      fail "v0.9.0 script not executable: ${script}"
      scripts_ok=false
    elif [[ ! -s "$script_path" ]]; then
      fail "v0.9.0 script empty: ${script}"
      scripts_ok=false
    fi
  done

  # Optional: Run shellcheck if available
  if command -v shellcheck &> /dev/null; then
    for script in "${required_scripts[@]}"; do
      local script_path="${SCRIPT_DIR}/${script}"
      if [[ -f "$script_path" ]]; then
        if ! shellcheck -S error "$script_path" > /dev/null 2>&1; then
          warn "Shellcheck warnings in ${script} (non-blocking)"
        fi
      fi
    done
    log "Shellcheck passed for v0.9.0 scripts"
  else
    warn "shellcheck not installed - skipping script linting"
  fi

  [[ "$scripts_ok" == "true" ]] && log "All v0.9.0 script files present and executable"
}

check_v090_config() {
  echo "Checking v0.9.0 configuration schema..."

  [[ -f "$CONFIG_FILE" ]] || { warn "No config file - skipping v0.9.0 config validation"; return; }

  # Check if yq is available
  if ! command -v yq &> /dev/null; then
    warn "yq not installed - skipping v0.9.0 config validation"
    return
  fi

  local config_ok=true
  local grounding_threshold=""
  local grounding_enforcement=""

  # Try Go yq first, then Python yq
  if yq --version 2>&1 | grep -q "mikefarah"; then
    # Go yq (mikefarah/yq)
    grounding_threshold=$(yq eval '.grounding.threshold // "missing"' "$CONFIG_FILE" 2>/dev/null)
    grounding_enforcement=$(yq eval '.grounding.enforcement // "missing"' "$CONFIG_FILE" 2>/dev/null)
  else
    # Python yq (kislyuk/yq)
    grounding_threshold=$(yq -r '.grounding.threshold // "missing"' "$CONFIG_FILE" 2>/dev/null)
    grounding_enforcement=$(yq -r '.grounding.enforcement // "missing"' "$CONFIG_FILE" 2>/dev/null)
  fi

  # Validate grounding configuration
  if [[ "$grounding_threshold" == "missing" ]]; then
    warn "v0.9.0 config: grounding.threshold not set (using default 0.95)"
  else
    # Validate threshold is a valid number between 0 and 1
    if [[ ! "$grounding_threshold" =~ ^[0-9]*\.?[0-9]+$ ]]; then
      fail "v0.9.0 config: grounding.threshold must be a number"
      config_ok=false
    fi
  fi

  if [[ "$grounding_enforcement" == "missing" ]]; then
    warn "v0.9.0 config: grounding.enforcement not set (using default 'warn')"
  elif [[ ! "$grounding_enforcement" =~ ^(strict|warn|disabled)$ ]]; then
    fail "v0.9.0 config: grounding.enforcement must be strict|warn|disabled"
    config_ok=false
  fi

  [[ "$config_ok" == "true" ]] && log "v0.9.0 configuration schema valid (enforcement: ${grounding_enforcement:-warn}, threshold: ${grounding_threshold:-0.95})"
}

check_notes_template() {
  echo "Checking NOTES.md template compliance..."

  [[ -f "$NOTES_FILE" ]] || { warn "NOTES.md missing - cannot validate template"; return; }

  local template_ok=true

  # v0.9.0 required sections
  local required_sections=(
    "Session Continuity"
    "Decision Log"
  )

  for section in "${required_sections[@]}"; do
    if ! grep -q "## ${section}" "$NOTES_FILE"; then
      warn "NOTES.md missing required v0.9.0 section: '${section}'"
      template_ok=false
    fi
  done

  # Check for v0.9.0 format hints
  if grep -q "Lightweight Identifiers" "$NOTES_FILE"; then
    log "NOTES.md has v0.9.0 Lightweight Identifiers section"
  fi

  [[ "$template_ok" == "true" ]] && log "NOTES.md template compliant with v0.9.0"
}

check_dependencies() {
  echo "Checking dependencies..."

  local deps_ok=true
  command -v jq &> /dev/null || { warn "jq not installed (required for full functionality)"; deps_ok=false; }
  command -v yq &> /dev/null || { warn "yq not installed (required for config parsing)"; deps_ok=false; }
  command -v git &> /dev/null || { fail "git not installed (required)"; deps_ok=false; }

  [[ "$deps_ok" == "true" ]] && log "All dependencies present"
}

# === Main ===
main() {
  local verbose=false
  local strict=false
  local v090=false

  while [[ $# -gt 0 ]]; do
    case $1 in
      --verbose|-v) verbose=true; shift ;;
      --strict) strict=true; shift ;;
      --v090|--lossless-ledger) v090=true; shift ;;
      *) shift ;;
    esac
  done

  echo ""
  echo "======================================================================="
  echo "  Loa Framework Validation (Enterprise Grade)"
  echo "  v0.9.0 Lossless Ledger Protocol Support"
  echo "======================================================================="
  echo ""

  # Core checks
  check_dependencies
  check_mounted
  check_integrity
  check_schema
  check_memory
  check_config
  check_zones

  # v0.9.0 Lossless Ledger Protocol checks
  echo ""
  echo "-----------------------------------------------------------------------"
  echo "  v0.9.0 Lossless Ledger Protocol Validation"
  echo "-----------------------------------------------------------------------"
  echo ""
  check_v090_protocols
  check_v090_scripts
  check_v090_config
  check_notes_template

  echo ""
  echo "======================================================================="
  if [[ $FAILURES -gt 0 ]]; then
    echo -e "${RED}Validation FAILED with $FAILURES error(s)${NC}"
    exit 1
  else
    echo -e "${GREEN}All checks passed${NC}"
    exit 0
  fi
}

main "$@"
