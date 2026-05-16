#!/usr/bin/env bash
# =============================================================================
# .claude/hooks/pre-commit/bb-dist-check.sh
#
# cycle-104 sprint-1 T1.6 — OPTIONAL operator-side pre-commit hook that warns
# (but does NOT block) when BB dist drift is detected on a staged commit
# touching `.claude/skills/bridgebuilder-review/`. The hard gate is the
# `.github/workflows/check-bb-dist-fresh.yml` CI workflow; this hook is
# operator-side fast feedback only.
#
# Install via your preferred git hook mechanism, e.g.:
#
#   # Inline in .git/hooks/pre-commit:
#   bash .claude/hooks/pre-commit/bb-dist-check.sh || true
#
#   # Or via husky / pre-commit / lefthook config — see
#   # grimoires/loa/runbooks/cycle-archive.md for full install patterns.
#
# Behavior:
#   - Only fires when staged paths touch BB source/dist/package files.
#   - Runs `tools/check-bb-dist-fresh.sh --json`. On `outcome != "fresh"`,
#     prints a one-paragraph warning to stderr with the canonical `npm run
#     build` invocation. Exits 0 either way (soft-fail).
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Only fire when staged paths touch BB.
staged=$(git diff --cached --name-only 2>/dev/null || true)
if [[ -z "$staged" ]]; then
  exit 0
fi
if ! echo "$staged" | grep -qE '^\.claude/skills/bridgebuilder-review/(resources|dist|package\.json|package-lock\.json)'; then
  exit 0
fi

if [[ ! -x "$REPO_ROOT/tools/check-bb-dist-fresh.sh" ]]; then
  # Soft-fail: hook is advisory only. Don't block commits when the
  # checker script is unavailable for any reason.
  exit 0
fi

result=$("$REPO_ROOT/tools/check-bb-dist-fresh.sh" --json 2>&1 || true)
outcome=$(echo "$result" | jq -r '.outcome // "unknown"' 2>/dev/null || echo "unknown")

case "$outcome" in
  fresh)
    exit 0
    ;;
  stale|manifest_missing|manifest_malformed)
    cat >&2 <<MSG

[bb-dist-check] WARNING: BB dist appears ${outcome} relative to staged BB source.
                        This is operator-side fast feedback; CI will be the hard gate.

  Fix (run before pushing):
    cd .claude/skills/bridgebuilder-review
    npm run build
    git add dist/

  Bypass this warning by leaving the commit as-is — CI will catch it.

MSG
    exit 0
    ;;
  *)
    # Unknown outcome — be conservative, don't block.
    exit 0
    ;;
esac
