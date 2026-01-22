# Sprint Plan: Migrate Skills to ck-First Search

**Version**: 1.0.0
**PRD**: `grimoires/loa/prd-ck-migration.md`
**SDD**: `grimoires/loa/sdd-ck-migration.md`
**Cycle**: cycle-008

---

## Overview

| Attribute | Value |
|-----------|-------|
| Total Sprints | 2 |
| Total Tasks | 9 |
| Effort | ~8 hours |

### Sprint Summary

| Sprint | Focus | Tasks | Effort |
|--------|-------|-------|--------|
| Sprint 1 | Core Skill Migration | 5 | ~5h |
| Sprint 2 | Testing & Documentation | 4 | ~3h |

---

## Sprint 1: Core Skill Migration

**Goal**: Migrate all grep calls in skills to use search-orchestrator.sh.

**Success Criteria**:
- All 16 grep calls migrated (except context-output exceptions)
- Skills use hybrid/regex search types appropriately
- No breaking changes to skill behavior

### Tasks

#### Task 1.1: Migrate riding-codebase/SKILL.md

**Description**: Migrate 10 grep calls in the riding-codebase skill (1 exception kept).

**Acceptance Criteria**:
- [ ] Route extraction uses `search-orchestrator.sh hybrid`
- [ ] Model extraction uses `search-orchestrator.sh hybrid`
- [ ] Env var extraction uses `search-orchestrator.sh regex`
- [ ] TODO/FIXME detection uses `search-orchestrator.sh regex`
- [ ] Ghost feature checks use `search-orchestrator.sh hybrid`
- [ ] Export extraction uses `search-orchestrator.sh regex`
- [ ] Solidity extraction uses `search-orchestrator.sh regex`
- [ ] Single-file grep with context (`-B1 -A2`) kept as-is (exception)

**Effort**: 2 hours

**Dependencies**: None

---

#### Task 1.2: Migrate reviewing-code/impact-analysis.md

**Description**: Migrate 2 grep calls for dependency tracking.

**Acceptance Criteria**:
- [ ] Import tracking uses `search-orchestrator.sh hybrid`
- [ ] Documentation search uses `search-orchestrator.sh hybrid`

**Effort**: 30 minutes

**Dependencies**: None

---

#### Task 1.3: Migrate implementing-tasks/context-retrieval.md

**Description**: Migrate 1 grep call for context retrieval.

**Acceptance Criteria**:
- [ ] JWT/token/auth search uses `search-orchestrator.sh hybrid`

**Effort**: 20 minutes

**Dependencies**: None

---

#### Task 1.4: Migrate deploying-infrastructure/SKILL.md

**Description**: Migrate 1 grep call for secrets scanning.

**Acceptance Criteria**:
- [ ] Secrets scanning uses `search-orchestrator.sh regex`
- [ ] Pattern preserved: `password|secret|key`

**Effort**: 20 minutes

**Dependencies**: None

---

#### Task 1.5: Migrate translating-for-executives/SKILL.md

**Description**: Migrate 1 grep call for ghost feature detection.

**Acceptance Criteria**:
- [ ] Ghost feature check uses `search-orchestrator.sh hybrid`

**Effort**: 20 minutes

**Dependencies**: None

---

### Sprint 1 Deliverables

| Deliverable | Location |
|-------------|----------|
| Updated riding-codebase | `.claude/skills/riding-codebase/SKILL.md` |
| Updated reviewing-code | `.claude/skills/reviewing-code/impact-analysis.md` |
| Updated implementing-tasks | `.claude/skills/implementing-tasks/context-retrieval.md` |
| Updated deploying-infrastructure | `.claude/skills/deploying-infrastructure/SKILL.md` |
| Updated translating-for-executives | `.claude/skills/translating-for-executives/SKILL.md` |

---

## Sprint 2: Testing & Documentation

**Goal**: Verify migrations work with and without ck, update documentation.

**Success Criteria**:
- All skills pass manual testing with ck installed
- All skills pass manual testing without ck (grep fallback)
- Documentation reflects ck-first search approach

### Tasks

#### Task 2.1: Test With ck Installed

**Description**: Run manual tests of each migrated skill with ck available.

**Acceptance Criteria**:
- [ ] `/ride` completes successfully with ck
- [ ] Route extraction produces semantic results
- [ ] Model extraction produces semantic results
- [ ] Secrets scanning works with regex mode
- [ ] TODO detection works with regex mode

**Effort**: 1 hour

**Dependencies**: Sprint 1 complete

---

#### Task 2.2: Test Without ck (Fallback)

**Description**: Test skills with ck removed/unavailable to verify grep fallback.

**Acceptance Criteria**:
- [ ] Set `LOA_SEARCH_MODE=grep` or remove ck from PATH
- [ ] `/ride` completes successfully with grep fallback
- [ ] Results are equivalent (degraded accuracy acceptable)
- [ ] No errors or crashes

**Effort**: 1 hour

**Dependencies**: Task 2.1

---

#### Task 2.3: Update Documentation

**Description**: Update CLAUDE.md and protocol docs to reflect ck-first search.

**Acceptance Criteria**:
- [ ] CLAUDE.md mentions ck as preferred search method
- [ ] Add note about search-orchestrator.sh in Helper Scripts section
- [ ] Update jit-retrieval.md examples if needed

**Effort**: 30 minutes

**Dependencies**: Task 2.2

---

#### Task 2.4: Create GitHub Issue (if needed)

**Description**: Create tracking issue for this migration.

**Acceptance Criteria**:
- [ ] Issue created with summary of changes
- [ ] Links to PRD/SDD/Sprint plan
- [ ] Labels: enhancement, skills

**Effort**: 10 minutes

**Dependencies**: Task 2.3

---

### Sprint 2 Deliverables

| Deliverable | Location |
|-------------|----------|
| Test results (with ck) | Manual verification |
| Test results (without ck) | Manual verification |
| Updated CLAUDE.md | `CLAUDE.md` |
| GitHub issue | GitHub |

---

## Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| ck API changes | Low | Medium | Pin to stable version |
| Grep fallback incomplete | Low | High | Test both modes |
| Breaking skill behavior | Low | High | Compare before/after output |
| search-orchestrator bugs | Low | Medium | Existing script, tested |

---

## Definition of Done

### Sprint 1
- [ ] All 5 tasks completed
- [ ] No hardcoded grep calls remain (except documented exceptions)
- [ ] Skills use search-orchestrator.sh consistently

### Sprint 2
- [ ] Testing complete with and without ck
- [ ] Documentation updated
- [ ] GitHub issue created/closed

### Feature Complete
- [ ] All acceptance criteria met
- [ ] No regressions in skill functionality
- [ ] Ready for v1.7.0 release

---

## Next Steps

After sprint plan approval:
```
/implement sprint-1
```

After Sprint 1:
```
/review-sprint sprint-1
/implement sprint-2
```

After Sprint 2:
```
/review-sprint sprint-2
/audit-sprint sprint-2
```

---

**Sprint Plan Status**: Ready for `/implement sprint-1`
