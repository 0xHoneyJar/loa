#!/usr/bin/env bash
# validate-constraints.sh — DRY Constraint Registry validator
# Runs 8 validation checks against constraints.json + generated sections
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/compat-lib.sh"

# Constants
readonly REGISTRY=".claude/data/constraints.json"
readonly SCHEMA=".claude/schemas/constraints.schema.json"
readonly TEMPLATE_DIR=".claude/templates/constraints"
readonly GENERATE_SCRIPT="${SCRIPT_DIR}/generate-constraints.sh"

# Section definitions (duplicated from generate-constraints.sh for freshness check)
readonly -a SECTIONS=(
  "process_compliance_never|.claude/loa/CLAUDE.loa.md|claude-loa-md-table.jq|[.constraints[] | select(.layers[] | select(.section == \"process_compliance_never\"))] | sort_by(.order)"
  "process_compliance_always|.claude/loa/CLAUDE.loa.md|claude-loa-md-table.jq|[.constraints[] | select(.layers[] | select(.section == \"process_compliance_always\"))] | sort_by(.order)"
  "task_tracking_hierarchy|.claude/loa/CLAUDE.loa.md|task-tracking.jq|[.constraints[] | select(.layers[] | select(.section == \"task_tracking_hierarchy\"))] | sort_by(.order)"
  "pre_implementation_checklist|.claude/protocols/implementation-compliance.md|protocol-checklist.jq|[\"C-PROC-008\",\"C-PROC-006\",\"C-PROC-009\",\"C-PROC-010\",\"C-GIT-001\",\"C-PROC-005\"] as \$o | [\$o[] as \$id | .constraints[] | select(.id == \$id)]"
  "autonomous_agent_constraints|.claude/skills/autonomous-agent/SKILL.md|skill-md-constraints.jq|[\"C-PHASE-001\",\"C-PHASE-003\",\"C-PHASE-004\",\"C-PHASE-006\",\"C-PROC-003\",\"C-PROC-004\",\"C-PROC-002\",\"C-PROC-006\"] as \$o | [\$o[] as \$id | .constraints[] | select(.id == \$id)]"
  "simstim_constraints|.claude/skills/simstim-workflow/SKILL.md|skill-md-constraints.jq|[\"C-PHASE-002\",\"C-PHASE-003\",\"C-PHASE-004\",\"C-PHASE-007\",\"C-PHASE-008\",\"C-PROC-005\",\"C-PHASE-005\",\"C-PROC-002\",\"C-PROC-006\"] as \$o | [\$o[] as \$id | .constraints[] | select(.id == \$id)]"
  "implementing_tasks_constraints|.claude/skills/implementing-tasks/SKILL.md|skill-md-constraints.jq|[.constraints[] | select(.layers[] | select(.target == \"skill-md\" and (.skills | index(\"implementing-tasks\"))))] | sort_by(.order)"
  "bridge_constraints|.claude/loa/CLAUDE.loa.md|claude-loa-md-table.jq|[.constraints[] | select(.layers[] | select(.section == \"bridge_constraints\"))] | sort_by(.order)"
  "merge_constraints|.claude/loa/CLAUDE.loa.md|claude-loa-md-table.jq|[.constraints[] | select(.layers[] | select(.section == \"merge_constraints\"))] | sort_by(.order)"
)

# Counters
ERRORS=0
WARNINGS=0
VERBOSE=false

# ============================================================================
# Utilities
# ============================================================================

log() { echo "[validate-constraints] $*" >&2; }
verbose() { [[ "$VERBOSE" == "true" ]] && log "$@" || true; }
pass() { echo "  PASS: $*"; }
fail() { echo "  FAIL: $*"; ERRORS=$((ERRORS + 1)); }
warn() { echo "  WARN: $*"; WARNINGS=$((WARNINGS + 1)); }

compute_section_hash() {
  printf '%s' "$1" \
    | tr -d '\r' \
    | sed 's/[[:space:]]*$//' \
    | sha256sum \
    | cut -c1-16
}

# ============================================================================
# Check 1: Registry exists and is valid JSON
# ============================================================================

check_registry_exists() {
  log "Check 1: Registry exists and is valid JSON"

  if [[ ! -f "$REGISTRY" ]]; then
    fail "Registry not found: $REGISTRY"
    return 1
  fi

  if ! jq empty "$REGISTRY" 2>/dev/null; then
    fail "Registry is not valid JSON: $REGISTRY"
    return 1
  fi

  local count
  count=$(jq '.constraints | length' "$REGISTRY")
  pass "Registry is valid JSON with $count constraints"
  return 0
}

# ============================================================================
# Check 2: Schema compliance (ajv or jq fallback)
# ============================================================================

check_schema_compliance() {
  log "Check 2: Schema compliance"

  if [[ ! -f "$SCHEMA" ]]; then
    fail "Schema not found: $SCHEMA"
    return 1
  fi

  if command -v ajv &>/dev/null; then
    if ajv validate -s "$SCHEMA" -d "$REGISTRY" --spec=draft2020 2>&1; then
      pass "Schema validation passed (ajv)"
      return 0
    else
      fail "Schema validation failed (ajv)"
      return 1
    fi
  fi

  # jq fallback: check required fields, ID patterns, enums
  local errors=0

  # Check top-level required fields
  if ! jq -e '.version and .constraints' "$REGISTRY" >/dev/null 2>&1; then
    fail "Missing required top-level fields (version, constraints)"
    return 1
  fi

  # Check version pattern
  local version
  version=$(jq -r '.version' "$REGISTRY")
  if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    fail "Invalid version format: $version"
    errors=$((errors + 1))
  fi

  # Check each constraint has required fields
  local missing
  missing=$(jq -r '
    [.constraints[] | select(
      (.id | not) or (.name | not) or (.category | not) or
      (.rule_type | not) or (.text | not) or (.why | not) or
      (.layers | not) or (.severity | not)
    ) | .id // "UNKNOWN"] | join(", ")
  ' "$REGISTRY")

  if [[ -n "$missing" ]]; then
    fail "Constraints missing required fields: $missing"
    errors=$((errors + 1))
  fi

  # Check ID pattern
  local bad_ids
  bad_ids=$(jq -r '[.constraints[] | select(.id | test("^C-[A-Z]+-[0-9]{3}$") | not) | .id] | join(", ")' "$REGISTRY")
  if [[ -n "$bad_ids" ]]; then
    fail "Invalid constraint IDs: $bad_ids"
    errors=$((errors + 1))
  fi

  # Check category enum
  local bad_cats
  bad_cats=$(jq -r '
    ["process","git_safety","beads","danger_level","flatline","guardrails","phase_sequencing","eval","bridge","merge","agent_teams","permission"] as $valid |
    [.constraints[] | select(.category | IN($valid[]) | not) | "\(.id): \(.category)"] | join(", ")
  ' "$REGISTRY")
  if [[ -n "$bad_cats" ]]; then
    fail "Invalid categories: $bad_cats"
    errors=$((errors + 1))
  fi

  # Check rule_type enum
  local bad_types
  bad_types=$(jq -r '
    ["NEVER","ALWAYS","WHEN","MUST","SHOULD","MAY"] as $valid |
    [.constraints[] | select(.rule_type | IN($valid[]) | not) | "\(.id): \(.rule_type)"] | join(", ")
  ' "$REGISTRY")
  if [[ -n "$bad_types" ]]; then
    fail "Invalid rule_types: $bad_types"
    errors=$((errors + 1))
  fi

  if [[ "$errors" -eq 0 ]]; then
    pass "Schema validation passed (jq fallback)"
  fi
  return $((errors > 0 ? 1 : 0))
}

# ============================================================================
# Check 3: No duplicate IDs
# ============================================================================

check_unique_ids() {
  log "Check 3: No duplicate IDs"

  local dupes
  dupes=$(jq -r '[.constraints[].id] | sort | group_by(.) | map(select(length > 1)) | map(.[0]) | join(", ")' "$REGISTRY")

  if [[ -n "$dupes" ]]; then
    fail "Duplicate constraint IDs: $dupes"
    return 1
  fi

  pass "All constraint IDs are unique"
  return 0
}

# ============================================================================
# Check 4: Error code cross-references valid
# ============================================================================

check_error_code_refs() {
  log "Check 4: Error code cross-references"

  local error_codes_file=".claude/data/error-codes.json"
  if [[ ! -f "$error_codes_file" ]]; then
    warn "Error codes file not found: $error_codes_file (skipping cross-reference check)"
    return 0
  fi

  # Get all error_code values from constraints
  local constraint_codes
  constraint_codes=$(jq -r '[.constraints[] | select(.error_code) | .error_code] | unique | .[]' "$REGISTRY")

  if [[ -z "$constraint_codes" ]]; then
    pass "No error code cross-references to validate"
    return 0
  fi

  local errors=0
  while IFS= read -r code; do
    if ! jq -e --arg c "$code" '.[$c] // .errors[$c] // empty' "$error_codes_file" >/dev/null 2>&1; then
      # Try alternate structure: array of objects with code field
      if ! jq -e --arg c "$code" '[.[] | select(.code == $c)] | length > 0' "$error_codes_file" >/dev/null 2>&1; then
        fail "Error code $code not found in $error_codes_file"
        errors=$((errors + 1))
      fi
    fi
  done <<< "$constraint_codes"

  if [[ "$errors" -eq 0 ]]; then
    pass "All error code cross-references valid"
  fi
  return $((errors > 0 ? 1 : 0))
}

# ============================================================================
# Check 5: Every constraint has ≥1 layer target
# ============================================================================

check_layer_coverage() {
  log "Check 5: Layer coverage"

  local no_layers
  no_layers=$(jq -r '[.constraints[] | select((.layers | length) == 0) | .id] | join(", ")' "$REGISTRY")

  if [[ -n "$no_layers" ]]; then
    fail "Constraints with no layer targets: $no_layers"
    return 1
  fi

  pass "All constraints have ≥1 layer target"
  return 0
}

# ============================================================================
# Check 6: Layer target files exist
# ============================================================================

check_target_files_exist() {
  log "Check 6: Target files exist"

  local errors=0

  # Check protocol files
  local protocol_files
  protocol_files=$(jq -r '[.constraints[].layers[] | select(.target == "protocol") | .file] | unique | .[]' "$REGISTRY")
  while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    if [[ ! -f "$file" ]]; then
      fail "Protocol file not found: $file"
      errors=$((errors + 1))
    else
      verbose "Protocol file exists: $file"
    fi
  done <<< "$protocol_files"

  # Check section target files from SECTIONS array
  local -A checked_files
  for entry in "${SECTIONS[@]}"; do
    local s_target
    IFS='|' read -r _ s_target _ _ <<< "$entry"
    if [[ -z "${checked_files[$s_target]:-}" ]]; then
      checked_files["$s_target"]=1
      if [[ ! -f "$s_target" ]]; then
        fail "Target file not found: $s_target"
        errors=$((errors + 1))
      else
        verbose "Target file exists: $s_target"
      fi
    fi
  done

  if [[ "$errors" -eq 0 ]]; then
    pass "All target files exist"
  fi
  return $((errors > 0 ? 1 : 0))
}

# ============================================================================
# Check 7: Skill names match directories
# ============================================================================

check_skill_names() {
  log "Check 7: Skill names match directories"

  local errors=0

  local skill_names
  skill_names=$(jq -r '[.constraints[].layers[] | select(.target == "skill-md") | .skills[]?] | unique | .[]' "$REGISTRY")

  while IFS= read -r skill; do
    [[ -z "$skill" ]] && continue
    if [[ ! -d ".claude/skills/$skill" ]]; then
      fail "Skill directory not found: .claude/skills/$skill"
      errors=$((errors + 1))
    else
      verbose "Skill directory exists: .claude/skills/$skill"
    fi
  done <<< "$skill_names"

  if [[ "$errors" -eq 0 ]]; then
    pass "All skill names match directories"
  fi
  return $((errors > 0 ? 1 : 0))
}

# ============================================================================
# Check 8: Generated sections are fresh (hash comparison)
# ============================================================================

check_section_freshness() {
  log "Check 8: Section freshness"

  local stale=0

  for entry in "${SECTIONS[@]}"; do
    local s_name s_target s_template s_filter
    IFS='|' read -r s_name s_target s_template s_filter <<< "$entry"

    if [[ ! -f "$s_target" ]]; then
      verbose "Skipping freshness for $s_name: target not found"
      continue
    fi

    # Check if markers exist in target
    if ! grep -q "@constraint-generated: start ${s_name}" "$s_target" 2>/dev/null; then
      verbose "Skipping freshness for $s_name: no markers in $s_target"
      continue
    fi

    # Extract stored hash from start marker
    local stored_hash
    stored_hash=$(grep "@constraint-generated: start ${s_name}" "$s_target" | sed -n 's/.*hash:\([a-f0-9]*\).*/\1/p' | head -1)

    if [[ -z "$stored_hash" ]]; then
      warn "No hash found in marker for section '$s_name' in $s_target"
      continue
    fi

    # Regenerate content
    local template_file="${TEMPLATE_DIR}/${s_template}"
    if [[ ! -f "$template_file" ]]; then
      fail "Template not found: $template_file"
      stale=$((stale + 1))
      continue
    fi

    local expected_content
    expected_content=$(jq -r "$s_filter" "$REGISTRY" | jq -r -f "$template_file")

    local expected_hash
    expected_hash=$(compute_section_hash "$expected_content")

    if [[ "$stored_hash" != "$expected_hash" ]]; then
      fail "STALE: Section '$s_name' in $s_target (stored: $stored_hash, expected: $expected_hash)"
      stale=$((stale + 1))
    else
      pass "Section '$s_name' in $s_target is fresh"
    fi
  done

  return $((stale > 0 ? 1 : 0))
}

# ============================================================================
# Warning checks (IMP-004)
# ============================================================================

check_orphan_markers() {
  log "Checking for orphan markers"

  local known_sections=""
  for entry in "${SECTIONS[@]}"; do
    local s_name
    IFS='|' read -r s_name _ _ _ <<< "$entry"
    known_sections+=" $s_name"
  done

  # Find all @constraint-generated markers across target files
  local -A checked_files
  for entry in "${SECTIONS[@]}"; do
    local s_target
    IFS='|' read -r _ s_target _ _ <<< "$entry"
    [[ -n "${checked_files[$s_target]:-}" ]] && continue
    checked_files["$s_target"]=1

    if [[ ! -f "$s_target" ]]; then continue; fi

    while IFS= read -r marker_section; do
      if [[ ! " $known_sections " =~ " $marker_section " ]]; then
        warn "Orphan marker: section '$marker_section' in $s_target not defined in SECTIONS"
      fi
    done < <(grep -o '@constraint-generated: start [a-z_]*' "$s_target" 2>/dev/null | sed 's/@constraint-generated: start //')
  done
}

check_deprecated_constraints() {
  log "Checking for deprecated constraints"

  local deprecated
  deprecated=$(jq -r '
    [.constraints[] | select(.deprecated == true) |
      { id: .id, reason: (.deprecated_reason // "no reason"), date: (.deprecated_date // "no date"),
        active_layers: [.layers[] | select(.target != "error-code") | .target] | length }
    ] | .[]
    | "\(.id) (deprecated: \(.date), reason: \(.reason), active layers: \(.active_layers))"
  ' "$REGISTRY" 2>/dev/null)

  if [[ -n "$deprecated" ]]; then
    while IFS= read -r line; do
      warn "Deprecated constraint with active layers: $line"
    done <<< "$deprecated"
  fi
}

# ============================================================================
# Main
# ============================================================================

usage() {
  cat <<'EOF'
validate-constraints.sh — DRY Constraint Registry validator

Usage: validate-constraints.sh [flags]

Flags:
  --verbose    Show detailed per-check output
  --help       Show this help

Exit codes:
  0  All checks pass
  1  One or more checks failed
  2  Registry missing
EOF
}

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --verbose)  VERBOSE=true ;;
      --help|-h)  usage; exit 0 ;;
      *)          log "Unknown flag: $1"; exit 2 ;;
    esac
    shift
  done

  log "Validating constraint registry: $REGISTRY"
  echo ""

  # Check 1 is fatal — exit 2 if registry missing
  if ! check_registry_exists; then
    log "FATAL: Registry missing or invalid"
    exit 2
  fi

  # Checks 2-8
  check_schema_compliance || true
  check_unique_ids || true
  check_error_code_refs || true
  check_layer_coverage || true
  check_target_files_exist || true
  check_skill_names || true
  check_section_freshness || true

  echo ""

  # Warning checks (non-fatal)
  check_orphan_markers
  check_deprecated_constraints

  echo ""
  log "Results: $ERRORS error(s), $WARNINGS warning(s)"

  if [[ "$ERRORS" -gt 0 ]]; then
    exit 1
  fi
  exit 0
}

main "$@"
