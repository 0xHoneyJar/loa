#!/usr/bin/env bash
# =============================================================================
# Lint Loa Structural Invariants
# =============================================================================
# Mechanically validates Loa's structural invariants. Run during /mount,
# /run preflight, /audit-sprint, or manually.
#
# Usage:
#   lint-invariants.sh              # Human-readable output
#   lint-invariants.sh --json       # Machine-readable JSON output
#   lint-invariants.sh --fix        # Auto-fix where possible
#
# Exit codes:
#   0 = all pass
#   1 = warnings only
#   2 = errors found
#
# Part of Loa Harness Engineering (cycle-011, issue #297)
# Source: OpenAI architectural invariants + custom linter pattern
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------------
JSON_OUTPUT=false
AUTO_FIX=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) JSON_OUTPUT=true; shift ;;
    --fix) AUTO_FIX=true; shift ;;
    -h|--help)
      echo "Usage: lint-invariants.sh [--json] [--fix]"
      echo ""
      echo "  --json  Output results as JSON"
      echo "  --fix   Auto-fix where possible"
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# ---------------------------------------------------------------------------
# Counters
# ---------------------------------------------------------------------------
PASSES=0
WARNINGS=0
ERRORS=0
RESULTS=()

report() {
  local level="$1"  # PASS, WARN, ERROR
  local name="$2"
  local message="$3"

  case "$level" in
    PASS)  PASSES=$((PASSES + 1)) ;;
    WARN)  WARNINGS=$((WARNINGS + 1)) ;;
    ERROR) ERRORS=$((ERRORS + 1)) ;;
  esac

  if [[ "$JSON_OUTPUT" == "true" ]]; then
    RESULTS+=("$(jq -cn --arg l "$level" --arg n "$name" --arg m "$message" '{level:$l,name:$n,message:$m}')")
  else
    local symbol
    case "$level" in
      PASS)  symbol="PASS" ;;
      WARN)  symbol="WARN" ;;
      ERROR) symbol="ERR " ;;
    esac
    printf "  [%s] %s: %s\n" "$symbol" "$name" "$message"
  fi
}

# ---------------------------------------------------------------------------
# Invariant 1: No unexpected .claude/ modifications
# ---------------------------------------------------------------------------
check_system_zone() {
  # Skip if not in a git repo or no commits
  if ! git rev-parse HEAD &>/dev/null; then
    report "PASS" "system-zone" "Not a git repo — skipping"
    return
  fi

  # Check for .claude/ changes in staged or unstaged diff (excluding allowed paths)
  local modified
  modified=$(git diff --name-only HEAD 2>/dev/null | \
    grep '^\.claude/' | \
    grep -v '^\.claude/overrides/' | \
    grep -v '^\.claude/hooks/' | \
    grep -v '^\.claude/data/' | \
    grep -v '^\.claude/loa/reference/' || true)

  if [[ -n "$modified" ]]; then
    report "WARN" "system-zone" "System zone files modified: $(echo "$modified" | tr '\n' ', ')"
  else
    report "PASS" "system-zone" "No unexpected .claude/ modifications"
  fi
}

# ---------------------------------------------------------------------------
# Invariant 2: CLAUDE.loa.md exists and has managed header
# ---------------------------------------------------------------------------
check_claude_md() {
  local file=".claude/loa/CLAUDE.loa.md"

  if [[ ! -f "$file" ]]; then
    report "ERROR" "claude-md" "CLAUDE.loa.md not found at $file"
    return
  fi

  # Check for managed header
  if head -1 "$file" | grep -q '@loa-managed: true'; then
    report "PASS" "claude-md" "CLAUDE.loa.md has valid managed header"
  else
    report "WARN" "claude-md" "CLAUDE.loa.md missing @loa-managed header"
  fi
}

# ---------------------------------------------------------------------------
# Invariant 3: constraints.json is valid JSON
# ---------------------------------------------------------------------------
check_constraints() {
  local file=".claude/data/constraints.json"

  if [[ ! -f "$file" ]]; then
    report "WARN" "constraints" "constraints.json not found at $file"
    return
  fi

  if jq empty "$file" 2>/dev/null; then
    report "PASS" "constraints" "constraints.json is valid JSON"
  else
    report "ERROR" "constraints" "constraints.json is invalid JSON"
    if [[ "$AUTO_FIX" == "true" ]]; then
      echo "  Cannot auto-fix invalid JSON — manual repair needed"
    fi
  fi
}

# ---------------------------------------------------------------------------
# Invariant 4: Constraint-generated blocks exist in CLAUDE.loa.md
# ---------------------------------------------------------------------------
check_constraint_blocks() {
  local file=".claude/loa/CLAUDE.loa.md"

  if [[ ! -f "$file" ]]; then
    report "ERROR" "constraint-blocks" "CLAUDE.loa.md not found"
    return
  fi

  local block_count
  block_count=$(grep -c '@constraint-generated: start' "$file" 2>/dev/null || true)
  [[ -z "$block_count" ]] && block_count=0

  if [[ "$block_count" -ge 3 ]]; then
    report "PASS" "constraint-blocks" "$block_count constraint-generated blocks found"
  elif [[ "$block_count" -gt 0 ]]; then
    report "WARN" "constraint-blocks" "Only $block_count constraint-generated blocks (expected 3+)"
  else
    report "ERROR" "constraint-blocks" "No constraint-generated blocks found"
  fi

  # Check start/end pairs match
  local start_count end_count
  start_count=$(grep -c '@constraint-generated: start' "$file" 2>/dev/null || true)
  end_count=$(grep -c '@constraint-generated: end' "$file" 2>/dev/null || true)
  [[ -z "$start_count" ]] && start_count=0
  [[ -z "$end_count" ]] && end_count=0

  if [[ "$start_count" -ne "$end_count" ]]; then
    report "ERROR" "constraint-blocks" "Mismatched start/end pairs: $start_count starts, $end_count ends"
  fi
}

# ---------------------------------------------------------------------------
# Invariant 5: Required files present
# ---------------------------------------------------------------------------
check_required_files() {
  local required=(".claude/loa/CLAUDE.loa.md" ".loa-version.json" ".loa.config.yaml")
  local missing=()

  for f in "${required[@]}"; do
    if [[ ! -f "$f" ]]; then
      missing+=("$f")
    fi
  done

  if [[ ${#missing[@]} -eq 0 ]]; then
    report "PASS" "required-files" "All required files present"
  else
    for f in "${missing[@]}"; do
      report "ERROR" "required-files" "Missing: $f"
    done
  fi
}

# ---------------------------------------------------------------------------
# Invariant 6: Hook scripts are executable
# ---------------------------------------------------------------------------
check_hook_executables() {
  local hooks=(
    ".claude/hooks/pre-compact-marker.sh"
    ".claude/hooks/post-compact-reminder.sh"
    ".claude/hooks/safety/block-destructive-bash.sh"
    ".claude/hooks/safety/run-mode-stop-guard.sh"
    ".claude/hooks/audit/mutation-logger.sh"
  )
  local non_exec=()

  for h in "${hooks[@]}"; do
    if [[ -f "$h" && ! -x "$h" ]]; then
      non_exec+=("$h")
      if [[ "$AUTO_FIX" == "true" ]]; then
        chmod +x "$h"
        echo "  Fixed: chmod +x $h"
      fi
    fi
  done

  if [[ ${#non_exec[@]} -eq 0 ]]; then
    report "PASS" "hook-executables" "All hook scripts are executable"
  else
    for h in "${non_exec[@]}"; do
      report "WARN" "hook-executables" "Not executable: $h"
    done
  fi
}

# ---------------------------------------------------------------------------
# Invariant 7: settings.hooks.json is valid JSON
# ---------------------------------------------------------------------------
check_hooks_json() {
  local file=".claude/hooks/settings.hooks.json"

  if [[ ! -f "$file" ]]; then
    report "WARN" "hooks-json" "settings.hooks.json not found"
    return
  fi

  if jq empty "$file" 2>/dev/null; then
    # Verify expected hook types are registered
    local types
    types=$(jq -r '.hooks | keys[]' "$file" 2>/dev/null | sort | tr '\n' ',')
    report "PASS" "hooks-json" "Valid JSON, registered hooks: $types"
  else
    report "ERROR" "hooks-json" "settings.hooks.json is invalid JSON"
  fi
}

# ---------------------------------------------------------------------------
# Invariant 8: Safety hook tests pass
# ---------------------------------------------------------------------------
check_safety_hook_tests() {
  local test_script=".claude/scripts/test-safety-hooks.sh"

  if [[ ! -f "$test_script" ]]; then
    report "WARN" "safety-hook-tests" "Test script not found at $test_script — skipping"
    return
  fi

  if bash "$test_script" >/dev/null 2>&1; then
    report "PASS" "safety-hook-tests" "All safety hook tests pass"
  else
    report "ERROR" "safety-hook-tests" "Safety hook tests failed — run: bash $test_script"
  fi
}

# ---------------------------------------------------------------------------
# Invariant 9: Deny rules active (advisory — WARN, not ERROR)
# ---------------------------------------------------------------------------
check_deny_rules_active() {
  local verify_script=".claude/scripts/verify-deny-rules.sh"

  if [[ ! -f "$verify_script" ]]; then
    report "WARN" "deny-rules-active" "Verify script not found at $verify_script — skipping"
    return
  fi

  if [[ ! -f "$HOME/.claude/settings.json" ]]; then
    report "WARN" "deny-rules-active" "~/.claude/settings.json not found — deny rules not installed"
    return
  fi

  if bash "$verify_script" >/dev/null 2>&1; then
    report "PASS" "deny-rules-active" "All deny rules active"
  else
    report "WARN" "deny-rules-active" "Some deny rules missing — run: bash .claude/scripts/install-deny-rules.sh --auto"
  fi
}

# ===========================================================================
# Run all checks
# ===========================================================================

if [[ "$JSON_OUTPUT" != "true" ]]; then
  echo "Loa Invariant Linter"
  echo "===================="
  echo ""
fi

check_system_zone
check_claude_md
check_constraints
check_constraint_blocks
check_required_files
check_hook_executables
check_hooks_json
check_safety_hook_tests
check_deny_rules_active

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------
if [[ "$JSON_OUTPUT" == "true" ]]; then
  # Build JSON array from results
  printf '{"summary":{"pass":%d,"warn":%d,"error":%d},"results":[' "$PASSES" "$WARNINGS" "$ERRORS"
  first=true
  for r in "${RESULTS[@]}"; do
    if [[ "$first" == "true" ]]; then
      first=false
    else
      printf ','
    fi
    printf '%s' "$r"
  done
  printf ']}\n'
else
  echo ""
  echo "Summary: $PASSES pass, $WARNINGS warn, $ERRORS error"
fi

# Exit code
if [[ "$ERRORS" -gt 0 ]]; then
  exit 2
elif [[ "$WARNINGS" -gt 0 ]]; then
  exit 1
else
  exit 0
fi
