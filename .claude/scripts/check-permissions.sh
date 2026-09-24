#!/usr/bin/env bash
set -euo pipefail

# check-permissions.sh - Pre-flight validation for Run Mode
# Verifies Claude Code has the permissions an autonomous run needs, evaluated
# the way Claude Code evaluates them (sprint-bug-246, bead bd-n7v3):
#
#   Layers (all consulted; the union of their allow rules is effective):
#     $HOME/.claude/settings.json          user-level
#     <root>/.claude/settings.json         shared project settings
#     <root>/.claude/settings.local.json   machine-local project settings (gitignored;
#                                          the file Claude Code writes when you approve a rule)
#   Deny wins: a deny rule in ANY layer that covers a required rule marks it denied,
#   whatever the allow lists say. Rules are read as JSON arrays (permissions.allow /
#   permissions.deny) — never as file text. A malformed file is skipped with a WARN
#   (it allows nothing and denies nothing). Managed/enterprise policy files are out of
#   scope (not readable by design).
#   Matching: exact rule, or the base wildcard  Bash(<cmd>:*)  covering  Bash(<cmd> <sub>:*)
#   (for allow and for deny alike; a narrower deny such as Bash(rm -rf /:*) does not
#   deny the generic Bash(rm:*) requirement).
#
# Usage:
#   check-permissions.sh                 Check all permissions (text report)
#   check-permissions.sh --json          Output as JSON (adds denied[] and settings_files[])
#   check-permissions.sh --quiet         Suppress output, exit code only
#   check-permissions.sh --root <dir>    Project root whose .claude/settings*.json to read
#                                        (default: the repository this script lives in)
#
# Exit codes:
#   0 - Every required permission is effective (allowed in some layer, denied in none)
#   1 - A required permission is missing or denied
#   2 - No settings file found in any layer (or usage error)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ROOT="$REPO_ROOT"

# ============================================================================
# REQUIRED PERMISSIONS FOR RUN MODE
# ============================================================================

# Git operations required for autonomous execution
REQUIRED_GIT_PERMISSIONS=(
  "Bash(git checkout:*)"
  "Bash(git commit:*)"
  "Bash(git push:*)"
  "Bash(git branch:*)"
  "Bash(git add:*)"
  "Bash(git status:*)"
  "Bash(git diff:*)"
  "Bash(git rev-parse:*)"
  "Bash(git show-ref:*)"
)

# GitHub CLI operations for PR creation
REQUIRED_GH_PERMISSIONS=(
  "Bash(gh:*)"
  "Bash(gh pr:*)"
)

# File operations required for implementation
REQUIRED_FILE_PERMISSIONS=(
  "Bash(mkdir:*)"
  "Bash(rm:*)"
  "Bash(cp:*)"
  "Bash(mv:*)"
)

# Shell execution required for scripts
REQUIRED_SHELL_PERMISSIONS=(
  "Bash(bash:*)"
)

# ============================================================================
# PARSING
# ============================================================================

OUTPUT_MODE="text"
QUIET=false

usage() {
  cat <<'USAGE'
check-permissions.sh - Pre-flight validation for Run Mode

Usage:
  check-permissions.sh                 Check all permissions
  check-permissions.sh --json          Output as JSON
  check-permissions.sh --quiet         Suppress output, exit code only
  check-permissions.sh --root <dir>    Project root whose .claude/settings*.json to read

Settings layers consulted (Claude Code's own): ~/.claude/settings.json,
<root>/.claude/settings.json, <root>/.claude/settings.local.json. Allow rules
are the union across the layers; a deny rule in any layer wins.

Exit codes:
  0 - All required permissions effective
  1 - Missing or denied required permissions
  2 - No settings file found in any layer
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json)
      OUTPUT_MODE="json"
      shift
      ;;
    --quiet|-q)
      QUIET=true
      shift
      ;;
    --root)
      if [[ $# -lt 2 || -z "$2" ]]; then echo "ERROR: --root requires a directory" >&2; exit 2; fi
      ROOT="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 2
      ;;
  esac
done

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

log() {
  if [[ "$QUIET" != "true" && "$OUTPUT_MODE" == "text" ]]; then
    echo "$@"
  fi
}

log_error() {
  if [[ "$OUTPUT_MODE" == "text" && "$QUIET" != "true" ]]; then
    echo "ERROR: $*" >&2
  fi
}

# rule_covers <rule> <required> — exact match, or the base wildcard of the
# required command (e.g. "Bash(git:*)" covers "Bash(git checkout:*)").
rule_covers() {
  local rule="$1" required="$2"
  [[ "$rule" == "$required" ]] && return 0
  local cmd_base base_pattern
  cmd_base=$(printf '%s' "$required" | sed -E 's/^Bash\(([^:]+):.*\)$/\1/')
  base_pattern="Bash(${cmd_base%% *}:*)"
  [[ "$rule" == "$base_pattern" ]]
}

# ============================================================================
# MAIN LOGIC
# ============================================================================

main() {
  local -a layers=() consulted=()
  layers=("${HOME:-/nonexistent}/.claude/settings.json" "$ROOT/.claude/settings.json" "$ROOT/.claude/settings.local.json")

  # rules as "rule<TAB>file" lines (tab-safe: rules never contain tabs)
  local allow_rules="" deny_rules="" f
  for f in "${layers[@]}"; do
    [[ -f "$f" ]] || continue
    if ! jq -e 'type == "object"' "$f" >/dev/null 2>&1; then
      echo "WARN: skipping malformed settings file: $f" >&2
      continue
    fi
    consulted+=("$f")
    allow_rules+="$(jq -r --arg f "$f" '(.permissions.allow // [])[]? | select(type == "string") | "\(.)\t\($f)"' "$f")"$'\n'
    deny_rules+="$(jq -r --arg f "$f" '(.permissions.deny // [])[]? | select(type == "string") | "\(.)\t\($f)"' "$f")"$'\n'
  done

  local settings_files_json="[]"
  if [[ ${#consulted[@]} -gt 0 ]]; then
    settings_files_json=$(printf '%s\n' "${consulted[@]}" | jq -R . | jq -s .)
  fi

  local any_present=false
  for f in "${layers[@]}"; do [[ -f "$f" ]] && any_present=true; done
  if [[ "$any_present" != "true" ]]; then
    if [[ "$OUTPUT_MODE" == "json" ]]; then
      jq -n --arg root "$ROOT" --argjson files "$settings_files_json" \
        '{success: false, error: "No settings file found in any layer", root: $root, settings_files: $files, settings_path: ($root + "/.claude/settings.json")}'
    else
      log_error "No settings file found: ~/.claude/settings.json, $ROOT/.claude/settings.json, $ROOT/.claude/settings.local.json"
      log_error "Run Mode requires the allow rules in one of them (approve them once and Claude Code writes .claude/settings.local.json)"
    fi
    exit 2
  fi

  local all_required=(
    "${REQUIRED_GIT_PERMISSIONS[@]}"
    "${REQUIRED_GH_PERMISSIONS[@]}"
    "${REQUIRED_FILE_PERMISSIONS[@]}"
    "${REQUIRED_SHELL_PERMISSIONS[@]}"
  )

  local -a found_permissions=() missing_permissions=() denied_lines=()
  local perm rule file line
  for perm in "${all_required[@]}"; do
    local denied_by="" denied_file=""
    while IFS=$'\t' read -r rule file; do
      [[ -n "$rule" ]] || continue
      if rule_covers "$rule" "$perm"; then denied_by="$rule"; denied_file="$file"; break; fi
    done <<< "$deny_rules"
    if [[ -n "$denied_by" ]]; then
      denied_lines+=("$perm"$'\t'"$denied_by"$'\t'"$denied_file")
      continue
    fi
    local allowed=false
    while IFS=$'\t' read -r rule file; do
      [[ -n "$rule" ]] || continue
      if rule_covers "$rule" "$perm"; then allowed=true; break; fi
    done <<< "$allow_rules"
    if [[ "$allowed" == "true" ]]; then found_permissions+=("$perm"); else missing_permissions+=("$perm"); fi
  done

  local total_required=${#all_required[@]}
  local total_found=${#found_permissions[@]}
  local total_missing=${#missing_permissions[@]}
  local total_denied=${#denied_lines[@]}

  if [[ "$OUTPUT_MODE" == "json" ]]; then
    local missing_json="[]" found_json="[]" denied_json="[]"
    if [[ $total_missing -gt 0 ]]; then
      missing_json=$(printf '%s\n' "${missing_permissions[@]}" | jq -R . | jq -s .)
    fi
    if [[ $total_found -gt 0 ]]; then
      found_json=$(printf '%s\n' "${found_permissions[@]}" | jq -R . | jq -s .)
    fi
    if [[ $total_denied -gt 0 ]]; then
      denied_json=$(printf '%s\n' "${denied_lines[@]}" | jq -R 'split("\t") | {rule: .[0], by: .[1], file: .[2]}' | jq -s .)
    fi
    local success="true"
    if [[ $total_missing -gt 0 || $total_denied -gt 0 ]]; then success="false"; fi
    jq -n \
      --argjson success "$success" \
      --argjson total_required "$total_required" \
      --argjson total_found "$total_found" \
      --argjson total_missing "$total_missing" \
      --argjson total_denied "$total_denied" \
      --argjson found "$found_json" \
      --argjson missing "$missing_json" \
      --argjson denied "$denied_json" \
      --argjson settings_files "$settings_files_json" \
      --arg settings_path "$ROOT/.claude/settings.json" \
      '{success: $success, total_required: $total_required, total_found: $total_found, total_missing: $total_missing, total_denied: $total_denied, found: $found, missing: $missing, denied: $denied, settings_files: $settings_files, settings_path: $settings_path}'
  else
    log "Run Mode Permission Check"
    log "========================="
    log ""
    log "Settings files consulted (Claude Code's layers; deny wins):"
    for f in "${consulted[@]}"; do log "  - $f"; done
    log ""
    if [[ $total_missing -eq 0 && $total_denied -eq 0 ]]; then
      log "✓ All $total_required required permissions are effective"
      log ""
      log "Categories verified:"
      log "  - Git operations: ${#REQUIRED_GIT_PERMISSIONS[@]} permissions"
      log "  - GitHub CLI: ${#REQUIRED_GH_PERMISSIONS[@]} permissions"
      log "  - File operations: ${#REQUIRED_FILE_PERMISSIONS[@]} permissions"
      log "  - Shell execution: ${#REQUIRED_SHELL_PERMISSIONS[@]} permissions"
      log ""
      log "Run Mode pre-flight check: PASSED"
    else
      log "✗ $total_found of $total_required required permissions effective ($total_missing missing, $total_denied denied)"
      if [[ $total_missing -gt 0 ]]; then
        log ""
        log "Missing permissions (allowed in no layer):"
        for perm in "${missing_permissions[@]}"; do log "  - $perm"; done
      fi
      if [[ $total_denied -gt 0 ]]; then
        log ""
        log "Denied permissions (a deny rule covers them — deny wins in any layer):"
        for line in "${denied_lines[@]}"; do
          IFS=$'\t' read -r perm rule file <<< "$line"
          log "  - $perm  denied by $rule  in $file"
        done
      fi
      log ""
      log "To fix: add the missing rules under \"permissions\".\"allow\" in .claude/settings.local.json"
      log "(machine-local) or .claude/settings.json (shared), and remove any deny rule that covers"
      log "them from the file named above. Unattended runs cannot answer a permission prompt."
      log ""
      log "Run Mode pre-flight check: FAILED"
    fi
  fi

  if [[ $total_missing -gt 0 || $total_denied -gt 0 ]]; then
    exit 1
  fi
  exit 0
}

# Only run main if script is executed (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
