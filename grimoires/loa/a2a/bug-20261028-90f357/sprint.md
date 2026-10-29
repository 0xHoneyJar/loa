# Sprint Plan: Bug Fix — post-merge publisher: release read-back fails when GitHub rewrites backslash-u control escapes in the release body (KF-064)

**Type**: bugfix
**Bug ID**: 20261028-90f357
**Source**: /bug (triage)
**Sprint**: sprint-bug-283

---

## sprint-bug-283: post-merge publisher: release read-back fails when GitHub rewrites backslash-u control escapes in the release body (KF-064)

### Sprint Goal
Fix the reported bug with a failing test proving the fix.

### Deliverables
- [ ] Failing test that reproduces the bug
- [ ] Source code fix
- [ ] All existing tests pass (no regressions)
- [ ] Triage analysis document

### Technical Tasks

#### Task 1: Write Failing Test [G-5]
- Create integration test reproducing the bug
- Verify test fails with current code
- Test file: tests/unit/post-merge-publication.bats

**Acceptance Criteria**:
- Test fails with current code, proving the bug exists
- Test name clearly describes the bug scenario
- Test is isolated (no side effects on other tests)
- Committed alone (`test(<bug_id>): failing test`) before any fix commit; SHA recorded in `reviewer.md` as `Red commit: <sha>`

#### Task 2: Implement Fix [G-1, G-2]
- Fix root cause in .claude/scripts/post-merge-orchestrator.sh (phase_release read-back, lines 1245-1256)
- Verify failing test now passes
- Run full test suite

**Acceptance Criteria**:
- Failing test now passes
- No regressions in existing tests
- Fix addresses root cause (not just symptoms)
- The fix is a later commit and does not weaken the test (`.claude/scripts/red-test-check.sh --red <Red commit> -- <test command>` exits 0)

### Acceptance Criteria
- [ ] Bug is no longer reproducible
- [ ] Failing test proves the fix
- [ ] No regressions in existing tests
- [ ] Fix addresses root cause (not just symptoms)

### Triage Reference
See: grimoires/loa/a2a/bug-20261028-90f357/triage.md
