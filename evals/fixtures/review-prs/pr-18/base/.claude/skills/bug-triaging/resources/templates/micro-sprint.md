# Sprint Plan: Bug Fix — {bug_title}

**Type**: bugfix
**Bug ID**: {bug_id}
**Source**: /bug (triage)
**Sprint**: {sprint_id}

---

## {sprint_id}: {bug_title}

### Sprint Goal
Fix the reported bug with a failing test proving the fix.

### Deliverables
- [ ] Failing test that reproduces the bug
- [ ] Source code fix
- [ ] All existing tests pass (no regressions)
- [ ] Triage analysis document

### Technical Tasks

#### Task 1: Write Failing Test [G-5]
- Create {test_type} test reproducing the bug
- Verify test fails with current code
- Test file: {suggested_test_file}

**Acceptance Criteria**:
- Test fails with current code, proving the bug exists
- Test name clearly describes the bug scenario
- Test is isolated (no side effects on other tests)

#### Task 2: Implement Fix [G-1, G-2]
- Fix root cause in {suspected_files}
- Verify failing test now passes
- Run full test suite

**Acceptance Criteria**:
- Failing test now passes
- No regressions in existing tests
- Fix addresses root cause (not just symptoms)

### Acceptance Criteria
- [ ] Bug is no longer reproducible
- [ ] Failing test proves the fix
- [ ] No regressions in existing tests
- [ ] Fix addresses root cause (not just symptoms)

### Triage Reference
See: grimoires/loa/a2a/bug-{bug_id}/triage.md
