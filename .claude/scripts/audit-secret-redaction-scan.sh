#!/usr/bin/env bash
# =============================================================================
# audit-secret-redaction-scan.sh — cycle-098 Sprint 1.5 (#695 F8 hardening).
#
# Single-source-of-truth for the LOA_AUDIT_KEY_PASSWORD assignment-pattern
# scanner. Extracted from `.github/workflows/audit-secret-redaction.yml` so
# the allowlist + scan logic can be unit-tested
# (tests/security/audit-secret-redaction-allowlist.bats).
#
# Usage:
#   echo path1\\npath2 | audit-secret-redaction-scan.sh
#     reads repo-relative paths from stdin
#   audit-secret-redaction-scan.sh
#     no stdin → defaults to `git ls-files`
#
# Exit codes:
#   0 — no violations (clean)
#   1 — violations found (path:lineno:match printed on stdout)
#
# Pre-fix (issue #695 F8): allowlist included broad globs over agent-writable
# paths (`grimoires/loa/.*\.md$`, `*progress*\.md$`, `*-handoff*\.md$`). Agents
# write into those paths routinely during normal sprint work; broad globs make
# them redaction blind spots — exactly the GitHub 2020 path-glob class
# bridgebuilder cited.
#
# Post-fix: allowlist restricted to a small set of NAMED files that legitimately
# reference the deprecated env var assignment pattern:
#   - The workflow itself (mentions the pattern in a comment + grep arg)
#   - audit-envelope.sh / audit-signing-helper.py / audit_envelope.py
#     (intercept the deprecated env var with a stderr warning + scrub)
#   - tests/security/no-env-var-leakage.bats (security test)
#   - grimoires/loa/runbooks/audit-keys-bootstrap.md (operator runbook —
#     documents the deprecation in fenced code)
#   - grimoires/loa/sdd.md, grimoires/loa/sprint.md (architectural rationale +
#     acceptance criteria — pinned by name, not glob)
# =============================================================================

set -euo pipefail

# Allowlist regex: anchored end-of-string ($), one entry per allowed path.
# IMPORTANT (#695 F8): no broad globs over agent-writable paths
# (progress/, handoffs/, a2a/, or grimoires/loa/*.md).
ALLOWLIST='\.github/workflows/audit-secret-redaction\.yml$|\.claude/scripts/lib/audit-signing-helper\.py$|\.claude/adapters/loa_cheval/audit_envelope\.py$|\.claude/scripts/audit-envelope\.sh$|tests/security/no-env-var-leakage\.bats$|grimoires/loa/runbooks/audit-keys-bootstrap\.md$|grimoires/loa/sdd\.md$|grimoires/loa/sprint\.md$|\.claude/scripts/audit-secret-redaction-scan\.sh$|tests/security/audit-secret-redaction-allowlist\.bats$'

# Forbidden pattern: any literal `LOA_AUDIT_KEY_PASSWORD=...` assignment.
PATTERN='LOA_AUDIT_KEY_PASSWORD='

# Source: stdin if piped, else git ls-files.
if [[ -p /dev/stdin || -s /dev/stdin ]]; then
    paths_input="$(cat)"
else
    paths_input="$(git ls-files 2>/dev/null || true)"
fi

if [[ -z "${paths_input// }" ]]; then
    # Empty input → vacuously clean.
    exit 0
fi

# Filter through allowlist (-vE strips matching paths from consideration), then
# grep each remaining file for the assignment pattern. Skip nonexistent paths
# silently so test fixtures with intentional gaps don't false-positive.
#
# `|| :` on each grep swallows the non-match exit code (1) so the pipeline
# doesn't trip pipefail when:
#   - all paths are allowlisted (first grep produces no output → exit 1)
#   - a file has no assignment pattern (per-file grep exits 1)
violations="$(
    {
        printf '%s\n' "$paths_input" \
            | { grep -vE "$ALLOWLIST" || :; } \
            | while IFS= read -r p; do
                [[ -n "$p" ]] || continue
                [[ -f "$p" ]] || continue
                grep -nE "$PATTERN" "$p" 2>/dev/null \
                    | sed -e "s|^|${p}:|" || :
              done
    }
)"

if [[ -n "$violations" ]]; then
    echo "ERROR: LOA_AUDIT_KEY_PASSWORD assignment pattern found outside allowlist (issue #695 F8)" >&2
    echo "$violations"
    exit 1
fi

exit 0
