#!/usr/bin/env bash
# Loa Framework: CI/CD Validation (Enterprise Grade)
# Exit codes: 0 = success, 1 = failure
set -euo pipefail

VERSION_FILE=".loa-version.json"
CHECKSUMS_FILE=".claude/checksums.json"
CONFIG_FILE=".loa.config.yaml"
NOTES_FILE="loa-grimoire/NOTES.md"

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
  [[ -d "loa-grimoire" ]] || { warn "State zone missing (loa-grimoire/)"; }
  [[ -d "loa-grimoire/a2a" ]] || { warn "A2A directory missing"; }
  [[ -d "loa-grimoire/a2a/trajectory" ]] || { warn "Trajectory directory missing"; }

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

  while [[ $# -gt 0 ]]; do
    case $1 in
      --verbose|-v) verbose=true; shift ;;
      --strict) strict=true; shift ;;
      *) shift ;;
    esac
  done

  echo ""
  echo "======================================================================="
  echo "  Loa Framework Validation (Enterprise Grade)"
  echo "======================================================================="
  echo ""

  check_dependencies
  check_mounted
  check_integrity
  check_schema
  check_memory
  check_config
  check_zones

  echo ""
  if [[ $FAILURES -gt 0 ]]; then
    echo -e "${RED}Validation FAILED with $FAILURES error(s)${NC}"
    exit 1
  else
    echo -e "${GREEN}All checks passed${NC}"
    exit 0
  fi
}

main "$@"
