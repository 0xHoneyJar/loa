#!/usr/bin/env bash
# Loa Framework: CI/CD Validation (Enterprise Grade)
# v0.9.0 Lossless Ledger Protocol - Enhanced validation
# Exit codes: 0 = success, 1 = failure
set -euo pipefail


# sprint-bug-172 / bug-911: sha256_portable from compat-lib
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/compat-lib.sh"

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
      local actual=$(sha256_portable "$file" | cut -d' ' -f1)
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

# cycle-115: Aleph owns a stronger, exact managed-tree receipt covering its
# command, skill, launcher, runtime bundle, and install lock. Delegate those
# paths to the compiled verifier instead of pretending the legacy, non-exhaustive
# checksums file proves their inventory. Loa versions without Aleph remain valid.
aleph_check_path_exists() {
  [[ -e "$1" || -L "$1" ]]
}

aleph_check_path_components_are_real() {
  local relative="$1"
  local current="."
  local part
  local -a parts=()

  [[ "$relative" != /* ]] || return 1
  IFS='/' read -r -a parts <<< "$relative"
  for part in "${parts[@]}"; do
    [[ -n "$part" && "$part" != "." && "$part" != ".." ]] || return 1
    current="${current}/${part}"
    [[ -e "$current" && ! -L "$current" ]] || return 1
  done
  return 0
}

aleph_check_managed_paths_exist() {
  aleph_check_path_exists ".claude/aleph" \
    || aleph_check_path_exists ".claude/commands/loa-aleph.md" \
    || aleph_check_path_exists ".claude/skills/loa-aleph"
}

aleph_check_node() {
  NODE_OPTIONS= NODE_PATH= node "$@"
}

aleph_check_submodule_head_is_authorized() {
  local submodule_root=".loa"
  local expected_root actual_root head gitlink

  expected_root=$(cd "$submodule_root" 2>/dev/null && pwd -P) || return 1
  actual_root=$(git -C "$submodule_root" rev-parse --show-toplevel 2>/dev/null) || return 1
  actual_root=$(cd "$actual_root" 2>/dev/null && pwd -P) || return 1
  [[ "$actual_root" == "$expected_root" ]] || return 1

  head=$(git -C "$submodule_root" rev-parse HEAD 2>/dev/null) || return 1
  gitlink=$(git ls-files --stage -- .loa 2>/dev/null \
    | awk '$1 == "160000" && $3 == "0" { print $2 }')
  [[ -n "$gitlink" && "$head" == "$gitlink" ]]
}

# Return 0 for bundle inventory in HEAD, 1 for no bundle inventory in HEAD,
# and 2 when the repository or bundle inventory is malformed. Callers must not
# infer a legacy bundle-less version from working-tree absence alone.
aleph_check_tree_bundle_state() {
  local git_root="$1"
  local bundle_relative="$2"
  local expected_root actual_root inventory

  expected_root=$(cd "$git_root" 2>/dev/null && pwd -P) || return 2
  actual_root=$(git -C "$git_root" rev-parse --show-toplevel 2>/dev/null) || return 2
  actual_root=$(cd "$actual_root" 2>/dev/null && pwd -P) || return 2
  [[ "$actual_root" == "$expected_root" ]] || return 2
  git -C "$git_root" rev-parse HEAD >/dev/null 2>&1 || return 2
  inventory=$(git -C "$git_root" ls-tree -r --name-only HEAD -- \
    "$bundle_relative" 2>/dev/null) || return 2
  [[ -n "$inventory" ]] || return 1
  return 0
}

aleph_check_bundle_is_pinned() {
  local git_root="$1"
  local bundle_relative="$2"
  local installer_relative="$3"
  local expected_root actual_root untracked symlink_path

  expected_root=$(cd "$git_root" 2>/dev/null && pwd -P) || return 1
  actual_root=$(git -C "$git_root" rev-parse --show-toplevel 2>/dev/null) || return 1
  actual_root=$(cd "$actual_root" 2>/dev/null && pwd -P) || return 1
  [[ "$actual_root" == "$expected_root" ]] || return 1

  git -C "$git_root" rev-parse HEAD >/dev/null 2>&1 || return 1
  git -C "$git_root" ls-files --error-unmatch -- \
    "${bundle_relative}/bundle.lock.json" \
    "${bundle_relative}/${installer_relative}" >/dev/null 2>&1 || return 1
  git -C "$git_root" diff --no-ext-diff --quiet HEAD -- \
    "$bundle_relative" || return 1
  untracked=$(git -C "$git_root" ls-files --others -- "$bundle_relative" 2>/dev/null) \
    || return 1
  [[ -z "$untracked" ]] || return 1
  symlink_path=$(find "${git_root}/${bundle_relative}" -type l -print -quit \
    2>/dev/null) || return 1
  [[ -z "$symlink_path" ]]
}

check_aleph_integrity() {
  echo "Checking Aleph installation integrity..."

  local target_bundle=".claude/aleph/runtime/bundle"
  local source_bundle=".loa/.claude/aleph/runtime/bundle"
  local installer_relative="runtime-js/adapters/loa/src/installer.js"
  local trusted_bundle=""
  local trusted_git_root=""
  local trusted_bundle_relative=""
  local installer=""
  local bundle_lock=""
  local expected_installer_digest=""
  local actual_installer_digest=""
  local node_version=""
  local node_major=""
  local gitlink=""
  local source_tree_state=1
  local target_tree_state=1

  gitlink=$(git ls-files --stage -- .loa 2>/dev/null \
    | awk '$1 == "160000" && $3 == "0" { print $2 }')
  if [[ -n "$gitlink" ]]; then
    if ! aleph_check_submodule_head_is_authorized; then
      fail "Aleph source is not at the parent-authorized submodule commit"
      return 0
    fi
    source_tree_state=0
    aleph_check_tree_bundle_state ".loa" \
      ".claude/aleph/runtime/bundle" \
      || source_tree_state=$?
    if [[ "$source_tree_state" -eq 2 ]]; then
      fail "Cannot establish Aleph bundle state from the parent-authorized submodule tree"
      return 0
    fi
  fi
  target_tree_state=0
  aleph_check_tree_bundle_state "." "$target_bundle" \
    || target_tree_state=$?
  if [[ "$target_tree_state" -eq 2 ]]; then
    fail "The repository HEAD contains a malformed Aleph bundle inventory"
    return 0
  fi

  if [[ "$source_tree_state" -eq 0 ]]; then
    if ! aleph_check_path_exists "$source_bundle"; then
      fail "Aleph bundle is tracked by the pinned submodule tree but missing from the working tree"
      return 0
    fi
    if [[ ! -d "$source_bundle" ]] \
      || ! aleph_check_path_components_are_real "$source_bundle"; then
      fail "Aleph source runtime bundle is not a real directory"
      return 0
    fi
    trusted_bundle="$source_bundle"
    trusted_git_root=".loa"
    trusted_bundle_relative=".claude/aleph/runtime/bundle"
  elif aleph_check_path_exists "$source_bundle"; then
    fail "Aleph source bundle exists outside the parent-authorized submodule tree"
    return 0
  elif [[ "$target_tree_state" -eq 0 ]]; then
    if ! aleph_check_path_exists "$target_bundle"; then
      fail "Aleph bundle is tracked by repository HEAD but missing from the working tree"
      return 0
    fi
    if [[ ! -d "$target_bundle" ]] \
      || ! aleph_check_path_components_are_real "$target_bundle"; then
      fail "Aleph installed runtime bundle is not a real directory"
      return 0
    fi
    trusted_bundle="$target_bundle"
    trusted_git_root="."
    trusted_bundle_relative="$target_bundle"
  elif aleph_check_path_exists "$target_bundle"; then
    fail "Aleph installed runtime bundle exists outside a trusted Git inventory"
    return 0
  elif aleph_check_managed_paths_exist; then
    fail "Aleph managed paths exist without an installed runtime bundle"
    return 0
  else
    log "Aleph runtime not bundled; integrity check not applicable"
    return 0
  fi

  if [[ ! -d "$target_bundle" || -L "$target_bundle" ]]; then
    fail "Aleph runtime is missing or symlinked"
    return 0
  fi
  installer="${trusted_bundle}/${installer_relative}"
  bundle_lock="${trusted_bundle}/bundle.lock.json"
  if ! aleph_check_bundle_is_pinned "$trusted_git_root" \
    "$trusted_bundle_relative" "$installer_relative"; then
    fail "Aleph verifier bundle differs from its pinned Git inventory"
    return 0
  fi
  if [[ ! -f "$installer" ]] \
    || ! aleph_check_path_components_are_real "$installer"; then
    fail "Aleph compiled integrity verifier is missing or symlinked"
    return 0
  fi
  if [[ ! -f "$bundle_lock" ]] \
    || ! aleph_check_path_components_are_real "$bundle_lock"; then
    fail "Aleph bundle lock is missing or symlinked"
    return 0
  fi
  # Authenticate the verifier before executing it. Otherwise a tampered
  # verifier would be trusted to report on its own tampering.
  expected_installer_digest=$(jq -r --arg path "$installer_relative" \
    '[.files[]? | select(.path == $path) | .digest] | if length == 1 then .[0] else empty end' \
    "$bundle_lock" 2>/dev/null) || expected_installer_digest=""
  actual_installer_digest=$(sha256_portable "$installer" 2>/dev/null | cut -d' ' -f1) \
    || actual_installer_digest=""
  if [[ ! "$expected_installer_digest" =~ ^sha256:[0-9a-f]{64}$ \
    || "sha256:${actual_installer_digest}" != "$expected_installer_digest" ]]; then
    fail "Aleph compiled integrity verifier does not match its bundle lock"
    return 0
  fi
  if ! command -v node >/dev/null 2>&1; then
    fail "Node.js 20+ is required to verify the Aleph installation"
    return 0
  fi
  node_version=$(aleph_check_node --version 2>/dev/null || true)
  if [[ "$node_version" =~ ^v([0-9]+)\. ]]; then
    node_major="${BASH_REMATCH[1]}"
  fi
  if [[ -z "$node_major" || "$node_major" -lt 20 ]]; then
    fail "Node.js 20+ is required to verify the Aleph installation (found ${node_version:-unknown})"
    return 0
  fi

  if aleph_check_node "$installer" verify-install --target "$(pwd)"; then
    log "Aleph installation receipt and managed tree verified"
  else
    fail "Aleph installation integrity verification failed"
  fi
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
  check_aleph_integrity
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

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
