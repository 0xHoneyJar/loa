# Sprint Plan: Bug Fix — Flatline content-qualified quorum

**Type**: bugfix
**Bug ID**: 20260718-i1227-cf7ca4
**Source**: /bug (triage)
**Sprint**: sprint-bug-227

---

## sprint-bug-227: Flatline content-qualified quorum

### Sprint Goal
Prevent schema-invalid model output from being counted as a successful Flatline voice, with a failing contract test proving the false green.

### Deliverables
- [ ] Failing hermetic test reproducing the 3/3 false green
- [ ] Content qualification before verdict-quality aggregation
- [ ] Read-only Cursor Q&A mode for structured inference
- [ ] Focused and existing tests pass
- [ ] Triage analysis document

### Technical Tasks

#### Task 1: Write Failing Test [G-5]
- Add a contract test with two valid review responses and one exit-0/schema-invalid prose response.
- Assert the pre-fix code admits all three and can report APPROVED.
- Test file: `tests/integration/flatline-content-qualified-quorum.bats`

**Acceptance Criteria**:
- Test fails with current code, proving the bug exists.
- Test exercises the real orchestrator qualification and aggregation functions.
- Test is hermetic and makes no provider calls.

#### Task 2: Implement Content Qualification [G-1, G-2]
- Normalize and validate each review response as `flatline-reviewer` before aggregation.
- Preserve the planned denominator independently of the qualified input count.
- Emit an auditable rejection event and aggregate only content-qualified verdict envelopes.

**Acceptance Criteria**:
- Invalid prose does not contribute to `voices_succeeded`.
- Two qualified voices in a planned cohort of three yield `voices_planned: 3`, `voices_succeeded: 2`, `chain_health: degraded`, and non-APPROVED status.
- All-valid three-voice behavior remains APPROVED.

#### Task 3: Use Cursor Q&A Mode
- Change Cursor’s read-only headless mode from `plan` to `ask`.
- Preserve `--sandbox enabled`, `--trust`, isolated cwd, stdin prompt transport, and absence of `--force`/`--yolo`.

**Acceptance Criteria**:
- Command-construction tests pin `--mode ask`.
- Existing Cursor adapter tests remain green.

#### Task 4: Verify and Review
- Run the focused Bats and Cursor adapter suites.
- Run relevant verdict aggregation and normalization regressions.
- Run the configured Fable, Cursor Grok 4.5, and Codex dissent review over the patch.

**Acceptance Criteria**:
- New regression test passes.
- No focused-suite regressions.
- Review findings are dispositioned before audit.

### Acceptance Criteria
- [ ] Bug is no longer reproducible.
- [ ] Failing test proves the fix.
- [ ] Planned quorum never shrinks because content is invalid.
- [ ] No APPROVED result is possible when any planned voice lacks valid review content.
- [ ] Cursor safety boundaries remain intact.

### Triage Reference
See: `grimoires/loa/a2a/bug-20260718-i1227-cf7ca4/triage.md`
