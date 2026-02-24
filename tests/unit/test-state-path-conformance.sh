#!/usr/bin/env bash
# test-state-path-conformance.sh - Verify scripts use path-lib.sh state resolution
# Part of: cycle-038 Sprint 1 (Organizational Memory Sovereignty)
#
# This test establishes the conformance BASELINE. Existing scripts that predate
# the state-dir resolution layer are reported as advisory warnings.
# Only scripts that source path-lib.sh but still use raw hardcoded paths
# are treated as hard failures (they should know better).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

FAIL=0
WARN=0
TOTAL_VIOLATIONS=0

echo "State Path Conformance Test"
echo "==========================="
echo ""

# Scan directories
scan_dirs=(
  "$PROJECT_ROOT/.claude/scripts"
  "$PROJECT_ROOT/.claude/hooks"
)

# Files that legitimately reference raw state paths
EXCLUDE_ARGS=(
  --exclude="path-lib.sh"
  --exclude="migrate-state-layout.sh"
  --exclude="bootstrap.sh"
)

# Combined regex for hardcoded state path patterns
PATTERN='\.beads[/"]|\.run[/"]|\.ck[/"]'

echo "Phase 1: Baseline scan (advisory)"
echo "-----------------------------------"

for dir in "${scan_dirs[@]}"; do
  [[ -d "$dir" ]] || continue

  while IFS= read -r match; do
    line_content="${match#*:*:}"
    # Skip comment lines
    if [[ "$line_content" =~ ^[[:space:]]*# ]]; then
      continue
    fi
    ((TOTAL_VIOLATIONS++)) || true
  done < <(grep -rnE "$PATTERN" "${EXCLUDE_ARGS[@]}" --include="*.sh" "$dir" 2>/dev/null || true)
done

echo "  Found $TOTAL_VIOLATIONS hardcoded state path references across all scripts."
echo "  (These will be migrated in Sprint 2+)"

echo ""
echo "Phase 2: Hard check — scripts sourcing path-lib with raw paths"
echo "--------------------------------------------------------------"

for dir in "${scan_dirs[@]}"; do
  [[ -d "$dir" ]] || continue
  while IFS= read -r -d '' file; do
    local_basename=$(basename "$file")
    # Skip allowlisted
    case "$local_basename" in
      path-lib.sh|migrate-state-layout.sh|bootstrap.sh|test-*|beads-health.sh|update-beads-state.sh|check-beads.sh|migrate-to-br.sh) continue ;;
    esac

    # Only check scripts that explicitly source path-lib (not just bootstrap)
    if grep -q 'source.*path-lib' "$file" 2>/dev/null; then
      # Check if it uses raw state refs that should be getters
      raw_refs=$(grep -nE '\$\{?PROJECT_ROOT\}?/\.beads|\$\{?PROJECT_ROOT\}?/\.run|\$\{?PROJECT_ROOT\}?/\.ck' "$file" 2>/dev/null | grep -v '^\s*#' || true)
      if [[ -n "$raw_refs" ]]; then
        ((FAIL++)) || true
        echo "  FAIL: $local_basename sources path-lib but uses raw paths:"
        echo "$raw_refs" | while IFS= read -r line; do
          echo "    $line"
        done
      fi
    fi
  done < <(find "$dir" -name "*.sh" -print0 2>/dev/null)
done

echo ""
echo "Results:"
echo "  Baseline violations: $TOTAL_VIOLATIONS (advisory — migration tracked)"
echo "  Hard failures: $FAIL (scripts sourcing path-lib with raw paths)"
echo ""

if [[ $FAIL -gt 0 ]]; then
  echo "Fix hard failures: Use get_state_*() getters instead of raw paths in scripts that source path-lib."
  exit 1
fi

echo "All path-lib-aware scripts conform. Baseline established for migration."
exit 0
