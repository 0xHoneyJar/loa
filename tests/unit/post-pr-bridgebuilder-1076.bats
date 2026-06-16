#!/usr/bin/env bats
# =============================================================================
# #1076 defect 4 — Bridgebuilder phase fails loud (does not silent-skip)
# =============================================================================
# When post_pr_validation.phases.bridgebuilder_review.enabled: true but the
# bare orchestrator produces no findings file (it cannot drive the SIGNAL:*
# protocol without the /run-bridge skill harness), the phase used to be marked
# 'skipped' and the run proceeded to READY_FOR_HITL — `enabled: true` silently
# did nothing.
#
# Fix contract: both the per-iteration no-findings path AND the generic bridge
# failure branch now mark the phase 'failed', HALT with a clear halt_reason,
# and return non-zero. A static contract check matches how this orchestrator's
# other invariants are pinned (see #878 mktemp-guard, post-pr-bridgebuilder.bats
# iteration test).
# =============================================================================

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    ORCH="$REPO_ROOT/.claude/scripts/post-pr-orchestrator.sh"
    STATE="$REPO_ROOT/.claude/scripts/post-pr-state.sh"
    [[ -f "$ORCH" ]] || skip "post-pr-orchestrator.sh not found"
    [[ -f "$STATE" ]] || skip "post-pr-state.sh not found"
}

@test "#1076 d4: 'failed' is a valid phase status in post-pr-state.sh" {
    grep -qE 'VALID_PHASE_STATUSES=\(.*"failed".*\)' "$STATE"
}

@test "#1076 d4: no-findings path marks the phase 'failed' (not 'skipped')" {
    # The block guarded by [[ ! -f "$iter_findings_file" ]] must mark failed + HALT.
    grep -q '_update_phase bridgebuilder_review failed' "$ORCH"
    grep -q 'halt_reason" "bridgebuilder_no_findings_requires_run_bridge_harness"' "$ORCH"
}

@test "#1076 d4: the old silent 'marking phase skipped' no-findings WARN is gone" {
    run grep -q 'produced no findings file for iter=.*marking phase skipped' "$ORCH"
    [ "$status" -ne 0 ]
}

@test "#1076 d4: generic bridge-failure branch fails loud + HALTs (not skipped)" {
    # The case '*)' branch must HALT with the bridgebuilder_failed reason.
    grep -q 'halt_reason" "bridgebuilder_failed"' "$ORCH"
    # And must not silently 'continue' past a real failure as 'skipped'.
    run grep -q 'Bridgebuilder review failed (exit: \$bridge_result), continuing' "$ORCH"
    [ "$status" -ne 0 ]
}

@test "#1076 d4: the phase doc-comment documents the /run-bridge harness requirement" {
    grep -q 'requires the /run-bridge skill harness' "$ORCH"
}
