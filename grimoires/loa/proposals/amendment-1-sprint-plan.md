# Sprint Plan: Amendment 1 — Close the Bridgebuilder Loop

**Parent proposal**: `grimoires/loa/proposals/close-bridgebuilder-loop.md`
**Scope**: Amendment 1 only (post-PR Bridgebuilder + auto-triage)
**Status**: PLANNED — ready for `/sprint-plan` → `/run sprint-plan` pickup
**Authorized**: HITL approval 2026-04-13 (design decisions in parent proposal)

---

## Goal

Extend `/simstim` and `post-pr-orchestrator.sh` so that after a PR is created, the Bridgebuilder runs automatically, its findings are parsed and triaged, BLOCKERs auto-dispatch `/bug` cycles (with logged reasoning), and the PR only reaches `READY_FOR_HITL` once the Bridgebuilder loop settles.

**Success measure**: A new PR goes through `/simstim` and emerges with (a) Bridgebuilder review posted + consumed, (b) any BLOCKER findings auto-triaged into follow-up sprints, (c) full trajectory log of decisions.

---

## Tasks

### T1 — Add BRIDGEBUILDER_REVIEW phase to post-pr-orchestrator.sh
**File**: `.claude/scripts/post-pr-orchestrator.sh`
- Add state constant `STATE_BRIDGEBUILDER_REVIEW`
- Add `phase_bridgebuilder_review()` function — invokes `bridge-orchestrator.sh --pr $PR`
- Wire into state machine AFTER `STATE_FLATLINE_PR`, BEFORE `STATE_READY_FOR_HITL`
- Skip-flag: `SKIP_BRIDGEBUILDER` (respects config gate)
- Timeout: 10min per invocation

### T2 — Add auto-triage subphase
**File**: `.claude/scripts/post-pr-triage.sh` (new)
- Input: `.run/bridge-reviews/*.json` (produced by bridge-orchestrator)
- Parse findings by severity
- BLOCKERS: dispatch `/bug` with finding content (programmatic `/bug` CLI or state file)
- HIGH_CONSENSUS: log decision (autonomous mode: acknowledge-and-continue with reasoning)
- PRAISE: append to `.run/bridge-lore-candidates.jsonl` for future mining
- Log all decisions to `grimoires/loa/a2a/trajectory/bridge-triage-{date}.jsonl`

### T3 — Trajectory logging schema
**File**: `.claude/data/trajectory-schemas/bridge-triage.schema.json` (new)
- Schema: `{ timestamp, pr_number, finding_id, severity, action, reasoning, auto_dispatched_bug_id? }`
- Every decision must include `reasoning` field per HITL design decision #1

### T4 — Config integration
**File**: `.loa.config.yaml.example`
- Add:
  ```yaml
  post_pr_validation:
    bridgebuilder_review:
      enabled: false  # Opt-in; default off for progressive rollout
      auto_triage_blockers: true  # Dispatch /bug for BLOCKER findings
      depth: 5  # Bridgebuilder iteration depth
  ```

### T5 — /simstim Phase 7.5 integration
**File**: `.claude/skills/simstim-workflow/SKILL.md`
- Update Phase 7.5 documentation to include Bridgebuilder sub-phase
- Add to phase sequence: `POST_PR_AUDIT → CONTEXT_CLEAR → E2E_TESTING → FLATLINE_PR → BRIDGEBUILDER_REVIEW → READY_FOR_HITL`

### T6 — Tests
**File**: `tests/unit/post-pr-bridgebuilder.bats` (new)
- Test: phase invokes bridge-orchestrator correctly
- Test: findings parser classifies severities correctly
- Test: auto-triage dispatches /bug for BLOCKERs
- Test: trajectory logs include reasoning
- Test: skip flag works
- Test: graceful failure if bridgebuilder unavailable

### T7 — Documentation
- Update `CLAUDE.md` with new phase
- Update `.claude/loa/reference/run-bridge-reference.md` with integration notes

---

## Acceptance Criteria

- [ ] `/simstim` runs end-to-end with `bridgebuilder_review.enabled: true` and produces Bridgebuilder PR comments + triage artifacts
- [ ] BLOCKER findings auto-dispatch `/bug` in autonomous mode with trajectory logs
- [ ] HIGH findings logged with reasoning but don't block in autonomous mode
- [ ] Feature flag default `false` preserves existing behavior (no regressions for users not opting in)
- [ ] All new tests pass
- [ ] Rollback plan: set `bridgebuilder_review.enabled: false` reverts to pre-amendment behavior

---

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| Bridgebuilder API cost spikes | Feature-flagged opt-in (default off); no auto-enable across repos |
| False-positive BLOCKERs auto-dispatch spam | Log reasoning + allow HITL to override via `/bug --close` |
| Loop doesn't terminate | `depth: 5` circuit breaker inherited from `/run-bridge` |
| Existing orchestrator breaks | Add new phase as additive (fall-through), never modify existing phases |

---

## Zone & Authorization

**System Zone writes required**: `.claude/scripts/`, `.claude/skills/simstim-workflow/`, `.claude/data/`.

Cycle PRD must explicitly authorize these writes. Recommend filing this as a **new cycle** (cycle-049 or later) with PRD specifying Amendment 1 scope, rather than folding into an existing cycle.

---

## Next Action

1. HITL confirms this sprint plan is accurate
2. Open new cycle with `/plan-and-analyze` (or manual cycle creation)
3. Feed this sprint plan into `/sprint-plan` for formalization
4. `/run sprint-plan` for autonomous execution
