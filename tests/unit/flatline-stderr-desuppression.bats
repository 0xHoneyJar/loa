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

@test "T2: rt_pipeline invocation block has NO fd-2-to-/dev/null redirect (FIND-007)" {
    # BB iter-2 FIND-007 (low): the prior assertion only forbade same-line
    # `$rt_pipeline.*2>/dev/null`. Equivalent forms could slip through:
    #   2> /dev/null            (space)
    #   `(\$rt_pipeline ...) 2>/dev/null`   (subshell-level)
    #   `{ ...; } 2>/dev/null`  (block-level)
    # Now we extract the rt_result=$(...) block (from `rt_result=$(` line
    # through the matching `)`-after-rt_pipeline-args) and assert NO
    # fd-2 redirect appears anywhere within it.
    block="$(awk '
        /rt_result=\$\("\$rt_pipeline"/ { in_blk=1 }
        in_blk { print }
        in_blk && /\) \|\| {/ { exit }
    ' "$ORCHESTRATOR")"
    [ -n "$block" ] || {
        printf 'FAIL: could not locate rt_result=$(...) block — anchor changed?\n' >&2
        return 1
    }
    # Forbid all flavors of fd-2 → /dev/null (with or without space).
    ! echo "$block" | grep -qE '2>[[:space:]]*/dev/null'
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
