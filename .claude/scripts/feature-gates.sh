#!/usr/bin/env bash
# Loa Framework: Feature Gates Utility
# Dynamic skill filtering based on configuration
#
# Usage:
#   source feature-gates.sh
#   is_feature_enabled "security_audit"
#   should_load_skill ".claude/skills/loa-auditing-security"
#   list_skill_gates
#   enforce_feature_gates

set -euo pipefail

# =============================================================================
# Constants
# =============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly CONFIG_FILE="$PROJECT_ROOT/.loa.config.yaml"
readonly SKILLS_DIR="$PROJECT_ROOT/.claude/skills"
readonly DISABLED_DIR="$PROJECT_ROOT/.claude/.skills-disabled"
readonly GITIGNORE_FILE="$PROJECT_ROOT/.gitignore"

# Require bash 4.0+ (associative arrays)
# shellcheck source=bash-version-guard.sh
source "$SCRIPT_DIR/bash-version-guard.sh"

# Feature gate to config path mapping
declare -A GATE_CONFIG_PATHS=(
  ["security_audit"]="preferences.require_security_audit"
  ["deployment"]="integrations"
  ["run_mode"]="run_mode.enabled"
  ["constructs"]="registry.enabled"
  ["prompt_enhancement"]="prompt_enhancement.enabled"
  ["continuous_learning"]="continuous_learning.enabled"
  ["executive_translation"]="visual_communication.enabled"
)

# =============================================================================
# Config Reading (with yq fallback)
# =============================================================================

# Read a value from config file
# Usage: read_config "path.to.value" "default"
read_config() {
  local path="${1:-}"
  local default="${2:-true}"

  if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "$default"
    return 0
  fi

  local value=""

  # Try yq first
  if command -v yq &>/dev/null; then
    value=$(yq -r ".$path // \"$default\"" "$CONFIG_FILE" 2>/dev/null || echo "$default")
  else
    # Fallback to grep/sed for simple paths
    local key="${path##*.}"
    value=$(grep -E "^\s*${key}:" "$CONFIG_FILE" 2>/dev/null | head -1 | sed 's/.*:\s*//' | tr -d '"' || echo "$default")
  fi

  # Normalize boolean values
  case "$value" in
    true|True|TRUE|yes|Yes|YES|1) echo "true" ;;
    false|False|FALSE|no|No|NO|0) echo "false" ;;
    null|"") echo "$default" ;;
    *) echo "$value" ;;
  esac
}

# =============================================================================
# Feature Gate Functions
# =============================================================================

# Check if a feature is enabled
# Usage: is_feature_enabled "feature_name"
# Returns: 0 if enabled, 1 if disabled
is_feature_enabled() {
  local feature="${1:-}"

  if [[ -z "$feature" ]]; then
    return 1
  fi

  # Check environment override first (LOA_FEATURES_<NAME>=true|false)
  local env_var="LOA_FEATURES_${feature^^}"
  env_var="${env_var//-/_}"
  local env_value="${!env_var:-}"

  if [[ -n "$env_value" ]]; then
    case "$env_value" in
      true|True|TRUE|yes|Yes|YES|1) return 0 ;;
      false|False|FALSE|no|No|NO|0) return 1 ;;
    esac
  fi

  # Look up config path for this feature
  local config_path="${GATE_CONFIG_PATHS[$feature]:-}"

  if [[ -z "$config_path" ]]; then
    # Unknown feature, default to enabled
    return 0
  fi

  local value=""
  value=$(read_config "$config_path" "true")

  [[ "$value" == "true" ]]
}

# Check if a skill should be loaded based on its feature gate
# Usage: should_load_skill "/path/to/skill/dir"
# Returns: 0 if should load, 1 if should skip
should_load_skill() {
  local skill_dir="${1:-}"

  if [[ -z "$skill_dir" ]] || [[ ! -d "$skill_dir" ]]; then
    return 1
  fi

  local index_file="$skill_dir/index.yaml"

  if [[ ! -f "$index_file" ]]; then
    # No index.yaml, assume always load
    return 0
  fi

  # Extract feature_gate from index.yaml
  local gate=""

  if command -v yq &>/dev/null; then
    gate=$(yq -r '.feature_gate // ""' "$index_file" 2>/dev/null || echo "")
  else
    gate=$(grep -E "^\s*feature_gate:" "$index_file" 2>/dev/null | head -1 | sed 's/.*:\s*//' | tr -d '"' || echo "")
  fi

  # No gate means always load
  if [[ -z "$gate" ]]; then
    return 0
  fi

  is_feature_enabled "$gate"
}

# List all skills with their gate status
# Usage: list_skill_gates
list_skill_gates() {
  local format="${1:-table}"

  echo "Skill Feature Gates"
  echo "==================="
  echo ""

  if [[ "$format" == "json" ]]; then
    echo "["
  fi

  local first=true

  for skill_dir in "$SKILLS_DIR"/*/; do
    [[ -d "$skill_dir" ]] || continue

    local skill_name=""
    skill_name=$(basename "$skill_dir")
    local index_file="$skill_dir/index.yaml"
    local gate=""
    local status=""

    if [[ -f "$index_file" ]]; then
      if command -v yq &>/dev/null; then
        gate=$(yq -r '.feature_gate // ""' "$index_file" 2>/dev/null || echo "")
      else
        gate=$(grep -E "^\s*feature_gate:" "$index_file" 2>/dev/null | head -1 | sed 's/.*:\s*//' | tr -d '"' || echo "")
      fi
    fi

    if [[ -z "$gate" ]]; then
      status="CORE"
    elif is_feature_enabled "$gate"; then
      status="ENABLED"
    else
      status="DISABLED"
    fi

    if [[ "$format" == "json" ]]; then
      [[ "$first" == "true" ]] || echo ","
      first=false
      printf '  {"skill": "%s", "gate": "%s", "status": "%s"}' "$skill_name" "${gate:-none}" "$status"
    else
      printf "%-40s %-25s %s\n" "$skill_name" "${gate:-[core]}" "$status"
    fi
  done

  if [[ "$format" == "json" ]]; then
    echo ""
    echo "]"
  fi
}

# Calculate metadata budget usage
# Usage: calculate_metadata_budget
calculate_metadata_budget() {
  local total=0
  local budget=15000

  echo "Metadata Budget Analysis"
  echo "========================"
  echo ""

  for skill_dir in "$SKILLS_DIR"/*/; do
    [[ -d "$skill_dir" ]] || continue

    local skill_name=""
    skill_name=$(basename "$skill_dir")
    local skill_md="$skill_dir/SKILL.md"

    if [[ -f "$skill_md" ]]; then
      # Count frontmatter (between --- markers)
      local frontmatter_size=0
      frontmatter_size=$(sed -n '/^---$/,/^---$/p' "$skill_md" 2>/dev/null | wc -c || echo "0")
      total=$((total + frontmatter_size))

      printf "%-40s %6d chars\n" "$skill_name" "$frontmatter_size"
    fi
  done

  echo ""
  echo "----------------------------------------"
  local percent=$((total * 100 / budget))
  printf "Total: %d / %d chars (%d%%)\n" "$total" "$budget" "$percent"

  if [[ $percent -ge 80 ]]; then
    echo ""
    echo "⚠️  WARNING: Approaching metadata budget limit!"
    echo "   Consider disabling optional features via .loa.config.yaml"
  fi
}

# Ensure .gitignore has entry for disabled skills
# Usage: ensure_gitignore_entry
ensure_gitignore_entry() {
  local entry=".claude/.skills-disabled/"

  if [[ ! -f "$GITIGNORE_FILE" ]]; then
    echo "$entry" > "$GITIGNORE_FILE"
    echo "Created .gitignore with disabled skills entry"
    return 0
  fi

  if ! grep -q "^${entry}$" "$GITIGNORE_FILE" 2>/dev/null; then
    echo "" >> "$GITIGNORE_FILE"
    echo "# Loa disabled skills (feature-gated)" >> "$GITIGNORE_FILE"
    echo "$entry" >> "$GITIGNORE_FILE"
    echo "Added disabled skills entry to .gitignore"
  fi
}

# Enforce feature gates by moving disabled skills
# Usage: enforce_feature_gates [--dry-run]
enforce_feature_gates() {
  local dry_run=false

  if [[ "${1:-}" == "--dry-run" ]]; then
    dry_run=true
    echo "[DRY RUN] Would perform the following actions:"
    echo ""
  fi

  ensure_gitignore_entry

  # Create disabled directory if needed
  if [[ "$dry_run" == "false" ]]; then
    mkdir -p "$DISABLED_DIR"
  fi

  local moved=0
  local restored=0

  # Check each skill
  for skill_dir in "$SKILLS_DIR"/*/; do
    [[ -d "$skill_dir" ]] || continue

    local skill_name=""
    skill_name=$(basename "$skill_dir")

    # Skip non-loa skills
    [[ "$skill_name" == loa-* ]] || continue

    if should_load_skill "$skill_dir"; then
      # Check if it's in disabled dir and should be restored
      if [[ -d "$DISABLED_DIR/$skill_name" ]]; then
        if [[ "$dry_run" == "true" ]]; then
          echo "RESTORE: $skill_name (feature now enabled)"
        else
          mv "$DISABLED_DIR/$skill_name" "$SKILLS_DIR/"
          echo "Restored: $skill_name"
        fi
        ((restored++)) || true
      fi
    else
      # Should be disabled
      if [[ "$dry_run" == "true" ]]; then
        echo "DISABLE: $skill_name"
      else
        mv "$skill_dir" "$DISABLED_DIR/"
        echo "Disabled: $skill_name"
      fi
      ((moved++)) || true
    fi
  done

  # Check disabled dir for skills that should be restored
  if [[ -d "$DISABLED_DIR" ]]; then
    for skill_dir in "$DISABLED_DIR"/*/; do
      [[ -d "$skill_dir" ]] || continue

      local skill_name=""
      skill_name=$(basename "$skill_dir")

      if should_load_skill "$skill_dir"; then
        if [[ "$dry_run" == "true" ]]; then
          echo "RESTORE: $skill_name (feature now enabled)"
        else
          mv "$skill_dir" "$SKILLS_DIR/"
          echo "Restored: $skill_name"
        fi
        ((restored++)) || true
      fi
    done
  fi

  echo ""
  echo "Summary: Disabled $moved skills, Restored $restored skills"
}

# =============================================================================
# CLI Interface
# =============================================================================

main() {
  local cmd="${1:-help}"
  shift || true

  case "$cmd" in
    is-enabled|is_enabled)
      if is_feature_enabled "$@"; then
        echo "true"
        return 0
      else
        echo "false"
        return 1
      fi
      ;;
    should-load|should_load)
      if should_load_skill "$@"; then
        echo "true"
        return 0
      else
        echo "false"
        return 1
      fi
      ;;
    list)
      list_skill_gates "${1:-table}"
      ;;
    budget)
      calculate_metadata_budget
      ;;
    enforce)
      enforce_feature_gates "$@"
      ;;
    help|--help|-h)
      cat <<EOF
Loa Feature Gates Utility

Usage: feature-gates.sh <command> [args]

Commands:
  is-enabled <feature>     Check if feature is enabled (exit 0=yes, 1=no)
  should-load <skill_dir>  Check if skill should be loaded
  list [json]              List all skills with gate status
  budget                   Calculate metadata budget usage
  enforce [--dry-run]      Move disabled skills to .skills-disabled/

Features:
  security_audit           Auditing security skill
  deployment               Infrastructure deployment
  run_mode                 Autonomous run mode
  constructs               Registry/constructs browsing
  prompt_enhancement       Prompt enhancement skill
  continuous_learning      Skill extraction from debugging
  executive_translation    Executive translation

Environment Overrides:
  LOA_FEATURES_<NAME>=true|false

Examples:
  feature-gates.sh is-enabled security_audit
  feature-gates.sh list json
  feature-gates.sh enforce --dry-run
EOF
      ;;
    *)
      echo "Unknown command: $cmd" >&2
      echo "Run 'feature-gates.sh help' for usage" >&2
      return 1
      ;;
  esac
}

# Only run main if executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
