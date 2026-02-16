#!/usr/bin/env bash
# generate-constraints.sh — DRY Constraint Registry generator
# Reads constraints.json, renders via jq templates, updates target files
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bash-version-guard.sh
source "$SCRIPT_DIR/bash-version-guard.sh"
source "${SCRIPT_DIR}/compat-lib.sh"

# Constants
readonly REGISTRY=".claude/data/constraints.json"
readonly SCHEMA=".claude/schemas/constraints.schema.json"
readonly TEMPLATE_DIR=".claude/templates/constraints"
readonly MARKER_UTILS="${SCRIPT_DIR}/marker-utils.sh"

# Section definitions: section_name|target_file|template|filter_jq
readonly -a SECTIONS=(
  "process_compliance_never|.claude/loa/CLAUDE.loa.md|claude-loa-md-table.jq|[.constraints[] | select(.layers[] | select(.section == \"process_compliance_never\"))] | sort_by(.order)"
  "process_compliance_always|.claude/loa/CLAUDE.loa.md|claude-loa-md-table.jq|[.constraints[] | select(.layers[] | select(.section == \"process_compliance_always\"))] | sort_by(.order)"
  "task_tracking_hierarchy|.claude/loa/CLAUDE.loa.md|task-tracking.jq|[.constraints[] | select(.layers[] | select(.section == \"task_tracking_hierarchy\"))] | sort_by(.order)"
  "pre_implementation_checklist|.claude/protocols/implementation-compliance.md|protocol-checklist.jq|[\"C-PROC-008\",\"C-PROC-006\",\"C-PROC-009\",\"C-PROC-010\",\"C-GIT-001\",\"C-PROC-005\"] as \$o | [\$o[] as \$id | .constraints[] | select(.id == \$id)]"
  "autonomous_agent_constraints|.claude/skills/autonomous-agent/SKILL.md|skill-md-constraints.jq|[\"C-PHASE-001\",\"C-PHASE-003\",\"C-PHASE-004\",\"C-PHASE-006\",\"C-PROC-003\",\"C-PROC-004\",\"C-PROC-002\",\"C-PROC-006\"] as \$o | [\$o[] as \$id | .constraints[] | select(.id == \$id)]"
  "simstim_constraints|.claude/skills/simstim-workflow/SKILL.md|skill-md-constraints.jq|[\"C-PHASE-002\",\"C-PHASE-003\",\"C-PHASE-004\",\"C-PHASE-007\",\"C-PHASE-008\",\"C-PROC-005\",\"C-PHASE-005\",\"C-PROC-002\",\"C-PROC-006\"] as \$o | [\$o[] as \$id | .constraints[] | select(.id == \$id)]"
  "implementing_tasks_constraints|.claude/skills/implementing-tasks/SKILL.md|skill-md-constraints.jq|[.constraints[] | select(.layers[] | select(.target == \"skill-md\" and (.skills | index(\"implementing-tasks\"))))] | sort_by(.order)"
  "bridge_constraints|.claude/loa/CLAUDE.loa.md|claude-loa-md-table.jq|[.constraints[] | select(.layers[] | select(.section == \"bridge_constraints\"))] | sort_by(.order)"
  "permission_grants|.claude/loa/CLAUDE.loa.md|claude-loa-md-table.jq|[.constraints[] | select(.layers[] | select(.section == \"permission_grants\"))] | sort_by(.order)"
  "merge_constraints|.claude/loa/CLAUDE.loa.md|claude-loa-md-table.jq|[.constraints[] | select(.layers[] | select(.section == \"merge_constraints\"))] | sort_by(.order)"
)

# Flags
DRY_RUN=false
VERBOSE=false
VALIDATE_ONLY=false
BOOTSTRAP=false
BOOTSTRAP_CONFIRM=false
SECTION_FILTER=""

# ============================================================================
# Utilities
# ============================================================================

log() { echo "[generate-constraints] $*" >&2; }
verbose() { [[ "$VERBOSE" == "true" ]] && log "$@" || true; }
die() { log "ERROR: $*"; exit 2; }

compute_section_hash() {
  # SHA-256, first 16 chars, LF-normalized, trailing whitespace trimmed
  printf '%s' "$1" \
    | tr -d '\r' \
    | sed 's/[[:space:]]*$//' \
    | sha256sum \
    | cut -c1-16
}

# ============================================================================
# Registry validation
# ============================================================================

validate_registry() {
  if [[ ! -f "$REGISTRY" ]]; then
    die "Registry not found: $REGISTRY"
  fi

  if ! jq empty "$REGISTRY" 2>/dev/null; then
    die "Registry is not valid JSON: $REGISTRY"
  fi

  # Check for duplicate IDs
  local dupes
  dupes=$(jq -r '[.constraints[].id] | sort | group_by(.) | map(select(length > 1)) | length' "$REGISTRY")
  if [[ "$dupes" -gt 0 ]]; then
    die "Registry has duplicate constraint IDs"
  fi

  verbose "Registry validated: $(jq '.constraints | length' "$REGISTRY") constraints"
}

# ============================================================================
# Rendering
# ============================================================================

render_section() {
  local section_name="$1"
  local template="$2"
  local filter_jq="$3"

  local template_file="${TEMPLATE_DIR}/${template}"
  if [[ ! -f "$template_file" ]]; then
    die "Template not found: $template_file"
  fi

  jq -r "$filter_jq" "$REGISTRY" | jq -r -f "$template_file"
}

# ============================================================================
# Section insertion
# ============================================================================

insert_generated_section() {
  local file="$1"
  local section="$2"
  local content="$3"

  local hash
  hash=$(compute_section_hash "$content")

  local start_marker="<!-- @constraint-generated: start ${section} | hash:${hash} -->"
  local end_marker="<!-- @constraint-generated: end ${section} -->"
  local warning="<!-- DO NOT EDIT — generated from .claude/data/constraints.json -->"

  if grep -q "@constraint-generated: start ${section}" "$file"; then
    # Replace content between existing markers
    local tmp="${file}.gen-tmp"
    awk -v start="@constraint-generated: start ${section}" \
        -v end="@constraint-generated: end ${section}" \
        -v new_start="$start_marker" \
        -v new_warning="$warning" \
        -v new_content="$content" \
        -v new_end="$end_marker" \
        '
        $0 ~ start { print new_start; print new_warning; printf "%s\n", new_content; skip=1; next }
        $0 ~ end   { print new_end; skip=0; next }
        !skip       { print }
        ' "$file" > "$tmp"
    mv "$tmp" "$file"
  else
    log "ERROR: Missing markers in ${file} for section '${section}'. Run with --bootstrap --confirm to insert."
    return 1
  fi
}

# ============================================================================
# Bootstrap: insert markers into target files
# ============================================================================

# Anchor patterns: section_name|start_regex|end_regex
readonly -a ANCHORS=(
  "process_compliance_never|^### NEVER Rules$|^### |^---$"
  "process_compliance_always|^### ALWAYS Rules$|^### |^---$"
  "task_tracking_hierarchy|^### Task Tracking Hierarchy$|^$|^---$"
  "pre_implementation_checklist|^## Pre-Implementation Checklist$|^## |^---$"
  "autonomous_agent_constraints|AUTONOMOUS_SKILL_ANCHOR|AUTONOMOUS_SKILL_END"
  "simstim_constraints|SIMSTIM_SKILL_ANCHOR|SIMSTIM_SKILL_END"
  "implementing_tasks_constraints|IMPLEMENTING_SKILL_ANCHOR|IMPLEMENTING_SKILL_END"
)

bootstrap_section() {
  local file="$1"
  local section="$2"
  local content="$3"

  local hash
  hash=$(compute_section_hash "$content")

  local start_marker="<!-- @constraint-generated: start ${section} | hash:${hash} -->"
  local end_marker="<!-- @constraint-generated: end ${section} -->"
  local warning="<!-- DO NOT EDIT — generated from .claude/data/constraints.json -->"

  if grep -q "@constraint-generated: start ${section}" "$file"; then
    verbose "Section ${section} already has markers in ${file}, skipping bootstrap"
    return 0
  fi

  # Find anchor for this section
  local anchor_start="" anchor_end=""
  for anchor in "${ANCHORS[@]}"; do
    local a_section a_start a_end
    IFS='|' read -r a_section a_start a_end <<< "$anchor"
    if [[ "$a_section" == "$section" ]]; then
      anchor_start="$a_start"
      anchor_end="$a_end"
      break
    fi
  done

  if [[ -z "$anchor_start" ]]; then
    log "WARNING: No anchor defined for section ${section}, skipping"
    return 0
  fi

  # For skill-md sections, use <constraints> tags
  if [[ "$anchor_start" == *"SKILL_ANCHOR"* ]]; then
    verbose "Skill section ${section}: markers will be inserted inside <constraints> block during generation"
    return 0
  fi

  # Find the anchor line and insert markers after the table header
  local matches
  matches=$(grep -c "$anchor_start" "$file" 2>/dev/null || echo "0")
  if [[ "$matches" -ne 1 ]]; then
    log "ERROR: Anchor '${anchor_start}' matches ${matches} times in ${file} (expected 1)"
    return 1
  fi

  # Find the section: locate header, keep table header+separator, wrap data rows with markers
  local tmp="${file}.bootstrap-tmp"
  local end_pat1="${anchor_end%%|*}"
  local end_pat2="${anchor_end#*|}"
  awk -v anchor="$anchor_start" \
      -v end_pat1="$end_pat1" \
      -v end_pat2="$end_pat2" \
      -v start_m="$start_marker" \
      -v warning_m="$warning" \
      -v end_m="$end_marker" \
      -v content_m="$content" \
      '
      BEGIN { state="looking"; sep_seen=0 }
      state == "looking" && $0 ~ anchor {
        print; state="in_header"; next
      }
      state == "in_header" {
        # Print everything until we see the separator row (|---|)
        print
        if ($0 ~ /^\|[-|: ]+\|$/) {
          sep_seen=1
          print start_m
          print warning_m
          printf "%s\n", content_m
          state="skipping"
        }
        next
      }
      state == "skipping" {
        if ($0 ~ end_pat1 || $0 ~ end_pat2) {
          print end_m
          if ($0 !~ /^$/) print
          state="done"
          next
        }
        # Skip original data rows (replaced by generated content)
        next
      }
      state != "skipping" { print }
      END {
        if (state == "skipping") print end_m
      }
      ' "$file" > "$tmp"

  if [[ "$DRY_RUN" == "true" ]] && [[ "$BOOTSTRAP_CONFIRM" != "true" ]]; then
    diff -u "$file" "$tmp" || true
    rm -f "$tmp"
  else
    mv "$tmp" "$file"
    log "Bootstrapped markers for section '${section}' in ${file}"
  fi
}

# ============================================================================
# Main generation pipeline
# ============================================================================

generate_all_sections() {
  # Phase 0: Build target -> sections map
  declare -A target_sections
  declare -A section_data  # section -> "target|template|filter"

  for entry in "${SECTIONS[@]}"; do
    local s_name s_target s_template s_filter
    IFS='|' read -r s_name s_target s_template s_filter <<< "$entry"

    if [[ -n "$SECTION_FILTER" ]] && [[ "$s_name" != "$SECTION_FILTER" ]]; then
      continue
    fi

    if [[ ! -f "$s_target" ]]; then
      log "WARNING: Target file not found: $s_target, skipping"
      continue
    fi

    target_sections["$s_target"]+="${s_name} "
    section_data["$s_name"]="${s_target}|${s_template}|${s_filter}"
  done

  if [[ ${#target_sections[@]} -eq 0 ]]; then
    log "No sections to generate"
    return 0
  fi

  # Phase 1: Create staged copies
  declare -A staged_files
  trap 'for tmp in "${staged_files[@]}"; do rm -f "$tmp"; done' EXIT

  for target in "${!target_sections[@]}"; do
    local tmp
    tmp=$(mktemp "${target}.constraint-XXXXXX")
    cp "$target" "$tmp"
    staged_files["$target"]="$tmp"
  done

  # Phase 2: Render and apply all sections to staged copies
  for target in "${!target_sections[@]}"; do
    local tmp="${staged_files[$target]}"
    for section in ${target_sections[$target]}; do
      local s_data="${section_data[$section]}"
      local s_target s_template s_filter
      IFS='|' read -r s_target s_template s_filter <<< "$s_data"

      verbose "Rendering section: $section"
      local content
      content=$(render_section "$section" "$s_template" "$s_filter")

      if [[ "$BOOTSTRAP" == "true" ]]; then
        bootstrap_section "$tmp" "$section" "$content"
      else
        if ! insert_generated_section "$tmp" "$section" "$content"; then
          log "ERROR: Generation failed for section '${section}' — no files modified"
          return 1
        fi
      fi
    done
  done

  # Phase 3: Diff or commit
  if [[ "$DRY_RUN" == "true" ]] && [[ "$BOOTSTRAP_CONFIRM" != "true" ]]; then
    for target in "${!target_sections[@]}"; do
      log "Diff for ${target}:"
      diff -u "$target" "${staged_files[$target]}" || true
    done
    for tmp in "${staged_files[@]}"; do rm -f "$tmp"; done
    trap - EXIT
    return 0
  fi

  # Commit with rollback
  declare -A backup_files
  for target in "${!target_sections[@]}"; do
    local bak="${target}.constraint-bak"
    cp "$target" "$bak"
    backup_files["$target"]="$bak"
  done

  local commit_failed=false
  local committed=()
  for target in "${!target_sections[@]}"; do
    if mv "${staged_files[$target]}" "$target"; then
      committed+=("$target")
    else
      commit_failed=true
      break
    fi
  done

  if [[ "$commit_failed" == "true" ]]; then
    local rollback_ok=true
    for t in "${committed[@]}"; do
      if ! cp -f "${backup_files[$t]}" "$t"; then
        rollback_ok=false
      fi
    done
    for tmp in "${staged_files[@]}"; do rm -f "$tmp"; done
    if [[ "$rollback_ok" == "true" ]]; then
      for bak in "${backup_files[@]}"; do rm -f "$bak"; done
      log "ERROR: Commit failed — all targets rolled back"
    else
      log "ERROR: Commit failed — rollback partially failed, .constraint-bak files preserved"
    fi
    trap - EXIT
    return 1
  fi

  # Success: clean up backups and update @loa-managed hashes
  for bak in "${backup_files[@]}"; do rm -f "$bak"; done
  trap - EXIT

  # Phase 4: Update @loa-managed hashes (IMP-002)
  for target in "${!target_sections[@]}"; do
    if bash "$MARKER_UTILS" has-marker "$target" | grep -q "true"; then
      verbose "Updating @loa-managed hash for ${target}"
      bash "$MARKER_UTILS" update-hash "$target"
    fi
  done

  log "Generation complete: ${#target_sections[@]} target(s) updated"
}

# ============================================================================
# Argument parsing
# ============================================================================

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run)     DRY_RUN=true ;;
      --verbose)     VERBOSE=true ;;
      --validate-only) VALIDATE_ONLY=true ;;
      --section)     shift; SECTION_FILTER="${1:-}"; [[ -z "$SECTION_FILTER" ]] && die "--section requires a name" ;;
      --bootstrap)   BOOTSTRAP=true; DRY_RUN=true ;;
      --confirm)     BOOTSTRAP_CONFIRM=true; DRY_RUN=false ;;
      --help|-h)     usage; exit 0 ;;
      *)             die "Unknown flag: $1" ;;
    esac
    shift
  done

  # --bootstrap --confirm: bootstrap with actual writes
  if [[ "$BOOTSTRAP" == "true" ]] && [[ "$BOOTSTRAP_CONFIRM" == "true" ]]; then
    DRY_RUN=false
  fi
}

usage() {
  cat <<'EOF'
generate-constraints.sh — DRY Constraint Registry generator

Usage: generate-constraints.sh [flags]

Flags:
  --dry-run          Print diff to stdout, don't write files
  --verbose          Print per-section rendering details
  --validate-only    Check staleness without writing
  --section NAME     Regenerate only the named section
  --bootstrap        Show where markers would be inserted (implies --dry-run)
  --confirm          Used with --bootstrap to actually write markers
  --help             Show this help

Exit codes:
  0  Success
  1  Validation error
  2  Registry error
EOF
}

# ============================================================================
# Main
# ============================================================================

main() {
  parse_args "$@"

  if [[ "$VALIDATE_ONLY" == "true" ]]; then
    exec bash "${SCRIPT_DIR}/validate-constraints.sh"
  fi

  validate_registry
  generate_all_sections
}

main "$@"
