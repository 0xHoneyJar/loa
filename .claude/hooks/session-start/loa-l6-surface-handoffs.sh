#!/usr/bin/env bash
# =============================================================================
# loa-l6-surface-handoffs.sh — SessionStart hook (cycle-098 Sprint 6C).
#
# At session start, identify the current operator (via git config user.email
# → OPERATORS.md slug match), then surface any unread L6 handoffs addressed
# to them. Body content is sanitized via context-isolation-lib's
# sanitize_for_session_start("L6", body) before reaching session context.
#
# This hook is silent (exit 0 with no stdout) when:
#   - structured_handoff.enabled is not true in .loa.config.yaml
#   - operator slug cannot be resolved (no git config user.email match)
#   - no unread handoffs for this operator
# =============================================================================

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${HOOK_DIR}/../../.." && pwd)"
LIB="${REPO_ROOT}/.claude/scripts/lib/structured-handoff-lib.sh"
[[ -f "$LIB" ]] || exit 0

# Gate on config.
if command -v yq >/dev/null 2>&1 && [[ -f "${REPO_ROOT}/.loa.config.yaml" ]]; then
    enabled="$(yq '.structured_handoff.enabled // false' "${REPO_ROOT}/.loa.config.yaml" 2>/dev/null || echo false)"
    [[ "$enabled" == "true" ]] || exit 0
else
    # No config → silent (the primitive is opt-in).
    exit 0
fi

# Resolve current operator slug from git config.
git_email="$(git -C "$REPO_ROOT" config user.email 2>/dev/null || echo "")"
[[ -n "$git_email" ]] || exit 0

# Source operator-identity to map email → slug. Fall back: skip surfacing.
OI="${REPO_ROOT}/.claude/scripts/operator-identity.sh"
[[ -f "$OI" ]] || exit 0
# shellcheck source=/dev/null
source "$OI" 2>/dev/null || exit 0

# Find an operator whose declared git_email matches.
OPERATORS_FILE="${LOA_OPERATORS_FILE:-${REPO_ROOT}/grimoires/loa/operators.md}"
[[ -f "$OPERATORS_FILE" ]] || exit 0
operator_slug="$(_oi_parse_yaml_to_json "$OPERATORS_FILE" \
    | jq -r --arg em "$git_email" \
        '.operators[]? | select(.git_email == $em) | .id' \
    | head -n 1)"
[[ -n "$operator_slug" ]] || exit 0

# shellcheck source=/dev/null
source "$LIB" 2>/dev/null || exit 0

surface_unread_handoffs "$operator_slug" 2>/dev/null || true
exit 0
