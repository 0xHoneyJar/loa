# Sprint Plan: Amendment 1 — Close the Bridgebuilder Loop

**Cycle**: cycle-053-close-bridgebuilder-loop
**PRD**: grimoires/loa/proposals/close-bridgebuilder-loop.md (approved, HITL design decisions captured)
**Source sprint outline**: grimoires/loa/proposals/amendment-1-sprint-plan.md
**Branch**: feat/cycle-053-close-bridgebuilder-loop
**Issue**: 0xHoneyJar/loa#464 Part B
**Date**: 2026-04-13

---

## Cycle Summary

Close the observability/action gap between the Bridgebuilder (external PR reviewer) and the Loa framework's internal workflow. Post-PR, the Bridgebuilder will run automatically, its findings will be parsed and triaged with logged reasoning, and BLOCKER findings will auto-dispatch `/bug` cycles. HIGH findings log decisions in autonomous mode (no HITL gate) per design decision. Feature-flagged for progressive rollout.

## Sprint 1: Amendment 1 — Post-PR Bridgebuilder Orchestration

**Scope**: MEDIUM (7 tasks)
**FRs**: FR-A1 (post-PR phase), FR-A2 (auto-triage), FR-A3 (reasoning log), FR-A4 (feature flag), FR-A5 (simstim integration), FR-A6 (tests), FR-A7 (docs)
**Goal**: Add BRIDGEBUILDER_REVIEW phase to `post-pr-orchestrator.sh` with auto-triage of findings, full trajectory logging, feature-flagged default OFF, progressive rollout path.

### Tasks

| ID | Task | File(s) | FR | Goal |
|----|------|---------|-----|------|
| T1 | Add `STATE_BRIDGEBUILDER_REVIEW` constant + `phase_bridgebuilder_review()` function. Wire into state machine after `STATE_FLATLINE_PR`, before `STATE_READY_FOR_HITL`. Honor `SKIP_BRIDGEBUILDER` flag. 10min timeout per invocation. | `.claude/scripts/post-pr-orchestrator.sh` | FR-A1 | G-1 |
| T2 | Create auto-triage script. Parse `.run/bridge-reviews/*.json`. BLOCKER → dispatch `/bug`. HIGH → log reasoning + continue (autonomous mode). PRAISE → `.run/bridge-lore-candidates.jsonl`. All decisions logged to trajectory. | `.claude/scripts/post-pr-triage.sh` (new) | FR-A2, FR-A3 | G-1 |
| T3 | JSON schema for bridge-triage trajectory entries: `{ timestamp, pr_number, finding_id, severity, action, reasoning, auto_dispatched_bug_id? }`. Reasoning field mandatory per HITL design decision. | `.claude/data/trajectory-schemas/bridge-triage.schema.json` (new) | FR-A3 | G-1 |
| T4 | Add `post_pr_validation.bridgebuilder_review` config section to `.loa.config.yaml.example`: `enabled: false` (default), `auto_triage_blockers: true`, `depth: 5`. | `.loa.config.yaml.example` | FR-A4 | G-1 |
| T5 | Update `/simstim` Phase 7.5 doc to include Bridgebuilder sub-phase. Add to sequence: `POST_PR_AUDIT → CONTEXT_CLEAR → E2E_TESTING → FLATLINE_PR → BRIDGEBUILDER_REVIEW → READY_FOR_HITL`. | `.claude/skills/simstim-workflow/SKILL.md` | FR-A5 | G-2 |
| T6 | BATS tests: phase invokes bridge-orchestrator correctly; findings classifier tested; auto-triage dispatches /bug; trajectory logs include reasoning; skip flag works; graceful failure on bridgebuilder unavailable. | `tests/unit/post-pr-bridgebuilder.bats` (new) | FR-A6 | G-3 |
| T7 | Update `CLAUDE.md` with new phase. Update `.claude/loa/reference/run-bridge-reference.md` with integration notes. | `CLAUDE.md`, `.claude/loa/reference/run-bridge-reference.md` | FR-A7 | G-4 |

### Acceptance Criteria

- [ ] `post-pr-orchestrator.sh` includes `BRIDGEBUILDER_REVIEW` phase after `FLATLINE_PR`
- [ ] `post-pr-triage.sh` parses findings and classifies BLOCKER/HIGH/DISPUTED/PRAISE correctly
- [ ] BLOCKER findings auto-dispatch `/bug` in autonomous mode with trajectory log entries
- [ ] Every triage decision emits a trajectory entry with mandatory `reasoning` field
- [ ] HIGH findings logged with reasoning but don't gate in autonomous mode (per HITL decision #1)
- [ ] Feature flag `post_pr_validation.bridgebuilder_review.enabled: false` preserves existing behavior (rollback path)
- [ ] BATS tests pass
- [ ] Documentation updated
- [ ] No regressions in existing `post-pr-*` scripts

### Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| Bridgebuilder API cost spikes | Feature-flagged opt-in (default off) |
| False-positive BLOCKERs auto-dispatch spam | Log reasoning + allow HITL override via `/bug --close` |
| Loop doesn't terminate | Circuit breaker inherited from `/run-bridge` (depth: 5) |
| Existing orchestrator breaks | Add new phase as additive (fall-through), never modify existing phases |

### Goals

- **G-1**: Closed-loop automation — Bridgebuilder findings become actionable
- **G-2**: Autonomous-first — HITL not a blocker per design decision #1
- **G-3**: Zero regression — opt-in, existing flows unchanged
- **G-4**: Documented rollout — feature flag + docs support progressive enablement

### Dependencies

- PR #463 (multi-model Bridgebuilder) — MERGED (cycle-052/multi-model)
- PR #465 (A1+A2+A3 follow-ups) — MERGED (this session)
- Issue #464 Part B — IN PROGRESS (this sprint)

### Zone & Authorization

**System Zone writes required**: `.claude/scripts/`, `.claude/skills/simstim-workflow/`, `.claude/data/`, `CLAUDE.md`, `.claude/loa/reference/`.

Cycle-level authorization: this cycle-053 sprint plan authorizes System Zone writes for Amendment 1 scope (post-PR orchestration). Changes are additive (new phase, new script, new config section) — no modification to existing quality gates.

---

*1 sprint, 7 tasks, FR-A1 through FR-A7, closes Issue #464 Part B*
