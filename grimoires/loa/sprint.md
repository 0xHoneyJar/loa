# Sprint Plan: /ride Persistent Artifacts — Bridgebuilder Review Remediation

**Version**: 2.0.0
**Date**: 2026-02-10
**PRD**: grimoires/loa/prd.md (v1.0.0)
**SDD**: grimoires/loa/sdd.md (v1.0.0)
**Issue**: #270
**Source**: [PR #272 Bridgebuilder Review](https://github.com/0xHoneyJar/loa/pull/272)

---

## Review Findings Summary

Sprint 1 (v1.0.0) implemented FR-1, FR-3, FR-4, FR-5 — the tool access fix, write checkpoints, verification gate, architecture grounding, and staleness detection. The Bridgebuilder review identified 5 actionable findings (1 High, 2 Medium, 2 Low):

| # | Severity | Finding | FR |
|---|----------|---------|----|
| 1 | **High** | FR-2 "Context-Aware Invocation Mode" (MUST) not implemented — priority inversion | FR-2 |
| 2 | Medium | Section numbering skip in output-formats.md (6.5.8 missing) + stale budget echo | — |
| 3 | Medium | Checkpoint coverage gap — Phases 3 and 8 have no write checkpoints | FR-1 |
| 4 | Low | Trajectory table ordering — Phase 0.6 listed before Phase 0.5 | — |
| 5 | Low | Checkpoint boilerplate DRY opportunity | — |

### Requirements Traceability

| Requirement | PRD Priority | Sprint 1 | Sprint 2 |
|-------------|-------------|----------|----------|
| FR-1: Artifact Persistence | MUST | Implemented | Extended (Phase 3 checkpoint) |
| FR-2: Context-Aware Mode | MUST | **Missing** | **Resolved** (PRD update + decision doc) |
| FR-3: Architecture Grounding | SHOULD | Implemented | — |
| FR-4: Translate-Ride Compat | MUST | Implemented | — |
| FR-5: Staleness Detection | SHOULD | Implemented | — |

---

## Sprint 2: Bridgebuilder Review Remediation

**Goal**: Address all findings from the Bridgebuilder review on PR #272. Resolve the FR-2 priority inversion, fix correctness issues in output-formats.md, close checkpoint coverage gaps, and fix trajectory table ordering.

### Task 1: Resolve FR-2 priority inversion — update PRD and document deferral rationale

- **Files**: `grimoires/loa/prd.md`
- **Description**: The PRD marks FR-2 (Context-Aware Invocation Mode) as MUST, but the SDD §4.3.2 recommends deferring it: "/ride always runs FULL mode when invoked. The lightweight behavior is achieved by /plan-and-analyze not invoking /ride at all when artifacts are fresh." This is a sound architectural decision — the lightweight mode is already handled by the calling skill, not by /ride itself. The PRD should be updated to reflect this: downgrade FR-2 to SHOULD and document the architectural rationale.
- **Covers**: Bridgebuilder Finding #1 (High)
- **Acceptance Criteria**:
  - [ ] FR-2 priority changed from MUST to SHOULD in PRD
  - [ ] Rationale section added to FR-2 explaining why mode detection is deferred
  - [ ] SDD §4.3.2 "Practical Mode Detection" recommendation cited as justification
  - [ ] Note that `/plan-and-analyze` already provides lightweight behavior via staleness check
  - [ ] Future path documented: marker file or `--phase` argument if lightweight needed later

### Task 2: Fix section numbering and stale budget echo in output-formats.md

- **File**: `.claude/skills/riding-codebase/resources/references/output-formats.md`
- **Description**: Fix three issues: (a) renumber §6.5.9 → §6.5.8, §6.5.10 → §6.5.9, §6.5.11 → §6.5.10 to eliminate the gap after the new §6.5.7 insertion, (b) fix the stale echo string from `budget: 7000` to `budget: 8500` in the Token Budget Verification section, (c) update trajectory log entry `"files": 6` to `"files": 7` to reflect architecture-overview.md.
- **Covers**: Bridgebuilder Finding #2 (Medium)
- **Acceptance Criteria**:
  - [ ] Section numbers are sequential: 6.5.7, 6.5.8, 6.5.9, 6.5.10
  - [ ] Echo string reads `budget: 8500` (matches the `if` check above it)
  - [ ] Trajectory log entry shows `"files": 7` (not 6)
  - [ ] No other content modified

### Task 3: Add Phase 3 write checkpoint (CP-3) and document coverage gaps

- **File**: `.claude/skills/riding-codebase/SKILL.md`
- **Description**: Add CP-3 checkpoint after Phase 3.3 for `grimoires/loa/legacy/INVENTORY.md` — this file is critical-path for Phase 4 (drift analysis). Also add a coverage gap note after Phase 8 acknowledging that Phase 2 extractions and Phase 8 modifications are intentionally uncovered, with rationale.
- **Covers**: Bridgebuilder Finding #3 (Medium)
- **Acceptance Criteria**:
  - [ ] CP-3 checkpoint added after Phase 3.3 for `grimoires/loa/legacy/INVENTORY.md`
  - [ ] Checkpoint follows the standard template (Write → Glob verify → trajectory log)
  - [ ] Coverage gap note added after Phase 8 explaining:
    - Phase 2 extractions are intermediate working data consumed immediately
    - Phase 8 modifies existing files (not creation), so existence checks don't apply
  - [ ] Phase 10.0 Verification Gate checklist updated to include INVENTORY.md (item #11)
  - [ ] Trajectory table updated with Phase 3 checkpoint entry

### Task 4: Fix trajectory table ordering — Phase 0.5 before Phase 0.6

- **File**: `.claude/skills/riding-codebase/SKILL.md`
- **Description**: Swap the Phase 0.6 and Phase 0.5 rows in the "Phase-Specific Details" trajectory logging table so they appear in chronological execution order: 0 → 0.5 → 0.6 → 1 → ...
- **Covers**: Bridgebuilder Finding #4 (Low)
- **Acceptance Criteria**:
  - [ ] Phase 0.5 (`codebase_probe`) row appears before Phase 0.6 (`staleness_check`)
  - [ ] All other rows in correct chronological order

### Task 5: Validation — word count, numbering, and traceability audit

- **Description**: Verify all changes are internally consistent. Cross-check section numbering, verify word count remains under 5,000, confirm all MUST requirements are either implemented or explicitly deferred with rationale.
- **Acceptance Criteria**:
  - [ ] SKILL.md word count < 5,000 (currently 2,696 — expect ~2,750 after CP-3 + gap note)
  - [ ] output-formats.md sections sequential (no gaps)
  - [ ] PRD FR-2 has SHOULD priority and deferral rationale
  - [ ] Phase 10.0 checklist has 11 items (added INVENTORY.md)
  - [ ] All Bridgebuilder findings addressed: 1 resolved, 2 fixed, 2 fixed, Finding #5 (DRY) noted for v3

---

## Bridgebuilder Finding #5 (DRY — Deferred)

The checkpoint boilerplate concern (8 near-identical blocks) is acknowledged but intentionally deferred. The Bridgebuilder review itself notes: "The current approach optimizes for *reliability over elegance*, which is the right call for a skill that's been failing to write files." At 2,696 words, SKILL.md has substantial headroom before hitting the 5,000-word limit. If a future iteration pushes the word count above 4,000, the checkpoints are the first extraction candidate for `resources/references/checkpoint-protocol.md`.

---

## NFR Compliance

| NFR | Verification |
|-----|-------------|
| NFR-1: Performance | CP-3 adds <3s (single Glob check) |
| NFR-2: Token budget | No new reality files; SKILL.md stays under 5,000 words |
| NFR-3: Backward compatibility | PRD priority change is documentation-only, no behavior change |
| NFR-4: No breaking changes | All changes additive or correctness fixes |

---

## Risk Mitigations

| Risk | Mitigation |
|------|-----------|
| PRD downgrade contested | SDD §4.3.2 provides technical justification; `/plan-and-analyze` staleness already covers the use case |
| INVENTORY.md checkpoint fails | Phase 10.0 verification gate catches it; drift analysis proceeds with degraded baseline |
| Word count creep | Currently at 2,696 / 5,000 — 46% headroom |

---

*Generated from PR #272 Bridgebuilder review feedback via /sprint-plan.*
