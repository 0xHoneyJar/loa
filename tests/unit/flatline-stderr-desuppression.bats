#!/usr/bin/env bats
# =============================================================================
# tests/unit/flatline-stderr-desuppression.bats
#
# cycle-102 Sprint 1 (T1.8 partial — AC-1.4) — Pipeline stderr de-suppression.
# Closes #780 Tier 1 partial.
#
# Per SDD §4.5: `flatline-orchestrator.sh` previously suppressed
# `red-team-pipeline.sh` stderr via `2>/dev/null`, masking cheval /
# model-adapter / probe-gate diagnostics during silent-degradation events.
# This test pins the de-suppression so a future refactor can't accidentally
# re-introduce the suppression.
#
# Test taxonomy:
#   T1   Orchestrator parses cleanly (no syntax regression)
#   T2   The red-team-pipeline.sh invocation NO LONGER carries `2>/dev/null`
#   T3   The de-suppression rationale comment is present (anchor)
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    ORCHESTRATOR="$PROJECT_ROOT/.claude/scripts/flatline-orchestrator.sh"

    [[ -f "$ORCHESTRATOR" ]] || { printf 'FATAL: missing %s\n' "$ORCHESTRATOR" >&2; return 1; }
}

@test "T1: flatline-orchestrator.sh parses with bash -n" {
    bash -n "$ORCHESTRATOR"
}

@test "T2: rt_pipeline invocation does NOT carry --json 2>/dev/null suppression" {
    # Look for the multi-line rt_result=$(\"\$rt_pipeline\" ... --json ...) block
    # and confirm the closing line does NOT have `--json 2>/dev/null)`.
    # We allow `--json)` on its own (de-suppressed) and we forbid the old form.
    ! grep -E '\$rt_pipeline.*2>/dev/null' "$ORCHESTRATOR"
    # Specific old-form check
    ! grep -E '^[[:space:]]+--json 2>/dev/null\) \|\|' "$ORCHESTRATOR"
}

@test "T3: de-suppression rationale comment anchored (regression guard)" {
    grep -qE "AC-1\.4.*pipeline stderr de-suppression" "$ORCHESTRATOR" || {
        printf 'FAIL: missing AC-1.4 de-suppression rationale comment\n' >&2
        printf 'A future refactor that re-introduces 2>/dev/null without this\n' >&2
        printf 'comment would silently revert vision-019 NFR — the rationale\n' >&2
        printf 'is the regression guard.\n' >&2
        return 1
    }
}
