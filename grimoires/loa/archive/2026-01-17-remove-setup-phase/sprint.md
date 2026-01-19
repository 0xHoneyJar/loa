# Sprint Plan: Remove Setup Phase

**Version**: 1.0.0
**Status**: Ready
**Author**: Claude (Agent)
**Date**: 2026-01-17
**PRD Reference**: `grimoires/loa/remove-setup-phase-prd.md`
**SDD Reference**: `grimoires/loa/remove-setup-phase-sdd.md`
**Feature Branch**: `feature/remove-setup-phase`

---

## Sprint Overview

| Attribute | Value |
|-----------|-------|
| **Sprint Number** | 3 (single sprint) |
| **Duration** | 1 day |
| **Total Effort** | ~10 hours |
| **Team Size** | 1 (Claude agent) |
| **Goal** | Remove /setup phase, implement API key-based THJ detection |

> **Note**: Sprints 1-2 were used for the Auto-Update Check feature (completed and merged as v0.14.0).

### Sprint Goals

1. Remove `/setup` and `/mcp-config` commands
2. Implement `is_thj_member()` based on `LOA_CONSTRUCTS_API_KEY`
3. Update all phase commands to remove setup pre-flight checks
4. Update documentation to reflect new workflow
5. Create comprehensive tests for new detection mechanism

### Success Criteria

- [ ] All phase commands work without `.loa-setup-complete`
- [ ] THJ detection works via API key presence
- [ ] `/feedback` command properly gates on API key
- [ ] All tests pass
- [ ] Documentation updated

---

## Sprint 3: Remove Setup Phase

### Task 3.1: Core THJ Detection Implementation

**Priority**: P0 (Critical)
**Effort**: 1.5 hours
**Dependencies**: None

**Description**: Implement the new `is_thj_member()` function in constructs-lib.sh and create the check-thj-member.sh helper script for pre-flight checks.

**Files to Modify**:
- `.claude/scripts/constructs-lib.sh` - Add `is_thj_member()` function

**Files to Create**:
- `.claude/scripts/check-thj-member.sh` - Pre-flight script for THJ-only commands

**Acceptance Criteria**:
- [ ] `is_thj_member()` returns 0 when `LOA_CONSTRUCTS_API_KEY` is set and non-empty
- [ ] `is_thj_member()` returns 1 when `LOA_CONSTRUCTS_API_KEY` is unset or empty
- [ ] `check-thj-member.sh` is executable and sources constructs-lib.sh
- [ ] No network calls made during detection

**Testing Requirements**:
- Manual test: `export LOA_CONSTRUCTS_API_KEY="test" && source .claude/scripts/constructs-lib.sh && is_thj_member && echo "THJ" || echo "OSS"`
- Manual test: `unset LOA_CONSTRUCTS_API_KEY && source .claude/scripts/constructs-lib.sh && is_thj_member && echo "THJ" || echo "OSS"`

---

### Task 3.2: Update Analytics Script

**Priority**: P0 (Critical)
**Effort**: 0.5 hours
**Dependencies**: Task 3.1

**Description**: Update analytics.sh to use the new `is_thj_member()` function instead of reading from the marker file.

**Files to Modify**:
- `.claude/scripts/analytics.sh` - Update `get_user_type()` and `should_track_analytics()`

**Acceptance Criteria**:
- [ ] `get_user_type()` returns "thj" when API key is set, "oss" otherwise
- [ ] `should_track_analytics()` uses `is_thj_member()` directly
- [ ] No references to `.loa-setup-complete` in file
- [ ] Analytics still written to correct location for THJ users

**Testing Requirements**:
- Manual test with API key set: verify analytics tracking works
- Manual test without API key: verify no analytics overhead

---

### Task 3.3: Delete Setup and MCP-Config Commands

**Priority**: P0 (Critical)
**Effort**: 0.5 hours
**Dependencies**: None

**Description**: Remove the setup wizard and mcp-config commands that are no longer needed.

**Files to Delete**:
- `.claude/commands/setup.md`
- `.claude/commands/mcp-config.md`

**Acceptance Criteria**:
- [ ] Both files deleted
- [ ] No broken symlinks or references
- [ ] Git shows files as deleted in staging

**Testing Requirements**:
- Verify files no longer exist: `ls .claude/commands/setup.md` should fail
- Verify `/setup` command no longer recognized (will error on invoke)

---

### Task 3.4: Update Check-Prerequisites Script

**Priority**: P0 (Critical)
**Effort**: 0.5 hours
**Dependencies**: None

**Description**: Remove `.loa-setup-complete` from all phase prerequisite checks.

**Files to Modify**:
- `.claude/scripts/check-prerequisites.sh` - Remove marker from all case statements

**Changes Required**:
| Phase | Before | After |
|-------|--------|-------|
| `setup` | No prereqs | REMOVE CASE |
| `plan\|prd` | `.loa-setup-complete` | No prereqs (echo "OK") |
| `architect\|sdd` | marker + prd.md | prd.md only |
| `sprint-plan` | marker + prd + sdd | prd + sdd only |
| `implement` | marker + prd + sdd + sprint | prd + sdd + sprint |
| `deploy` | marker + prd + sdd | prd + sdd only |

**Acceptance Criteria**:
- [ ] No references to `.loa-setup-complete` in file
- [ ] `setup` case removed entirely
- [ ] All other phases work without marker
- [ ] Script still validates appropriate file prerequisites

**Testing Requirements**:
- `./check-prerequisites.sh --phase plan` returns "OK" without marker
- `./check-prerequisites.sh --phase architect` fails only if prd.md missing

---

### Task 3.5: Update Preflight Script

**Priority**: P1 (High)
**Effort**: 0.5 hours
**Dependencies**: Task 3.1

**Description**: Remove `check_setup_complete()` and update `check_user_is_thj()` to use the new detection mechanism.

**Files to Modify**:
- `.claude/scripts/preflight.sh` - Remove/update functions

**Acceptance Criteria**:
- [ ] `check_setup_complete()` function removed
- [ ] `check_user_is_thj()` uses `is_thj_member()` from constructs-lib.sh
- [ ] No references to `.loa-setup-complete` in file

**Testing Requirements**:
- Source preflight.sh and verify functions work correctly

---

### Task 3.6: Update Git-Safety Script

**Priority**: P1 (High)
**Effort**: 0.5 hours
**Dependencies**: None

**Description**: Remove cached detection layer that reads from marker file.

**Files to Modify**:
- `.claude/scripts/git-safety.sh` - Remove `check_cached_detection()` and `is_detection_disabled()`

**Acceptance Criteria**:
- [ ] `check_cached_detection()` function removed
- [ ] `is_detection_disabled()` function removed
- [ ] `detect_template()` updated to skip cached detection layer
- [ ] Template detection still works via origin URL and GitHub API

**Testing Requirements**:
- `detect_template` function still works in template repository
- Function returns appropriate detection method

---

### Task 3.7: Remove Setup Pre-flight from Phase Commands

**Priority**: P0 (Critical)
**Effort**: 1.5 hours
**Dependencies**: None

**Description**: Remove the setup pre-flight check from all phase commands.

**Files to Modify** (remove setup check from YAML frontmatter):
1. `.claude/commands/plan-and-analyze.md` - Remove setup check entirely
2. `.claude/commands/architect.md` - Remove setup check
3. `.claude/commands/sprint-plan.md` - Remove setup check
4. `.claude/commands/implement.md` - Remove setup check
5. `.claude/commands/review-sprint.md` - Remove setup check
6. `.claude/commands/audit-sprint.md` - Remove setup check
7. `.claude/commands/deploy-production.md` - Remove setup check
8. `.claude/commands/ride.md` - Remove setup check (if present)
9. `.claude/commands/mount.md` - Remove setup check (if present)

**Pattern**: Remove this block from each file:
```yaml
pre_flight:
  - check: "file_exists"
    path: ".loa-setup-complete"
    error: "Loa setup has not been completed. Run /setup first."
```

**Acceptance Criteria**:
- [ ] No phase command references `.loa-setup-complete` in pre_flight
- [ ] Commands retain other necessary pre-flight checks (prd.md, sdd.md, etc.)
- [ ] `/plan-and-analyze` can be run immediately after clone

**Testing Requirements**:
- Run each command without marker and verify no "setup required" error

---

### Task 3.8: Update Feedback Command

**Priority**: P1 (High)
**Effort**: 0.5 hours
**Dependencies**: Task 3.1

**Description**: Update `/feedback` command to use script-based THJ detection instead of marker file check.

**Files to Modify**:
- `.claude/commands/feedback.md` - Update pre-flight section

**Before**:
```yaml
pre_flight:
  - check: "file_exists"
    path: ".loa-setup-complete"
    error: "Loa setup has not been completed. Run /setup first."

  - check: "content_contains"
    path: ".loa-setup-complete"
    pattern: '"user_type":\s*"thj"'
    error: |
      The /feedback command is only available for THJ team members.
```

**After**:
```yaml
pre_flight:
  - check: "script"
    script: ".claude/scripts/check-thj-member.sh"
    error: |
      The /feedback command is only available for THJ team members.

      For OSS users, please submit feedback via:
      https://github.com/0xHoneyJar/loa/issues

      THJ members: Set LOA_CONSTRUCTS_API_KEY to enable this command.
```

**Acceptance Criteria**:
- [ ] `/feedback` works with API key set
- [ ] `/feedback` shows helpful error without API key
- [ ] Error message points to GitHub Issues for OSS users

**Testing Requirements**:
- Manual test with API key: should proceed to feedback wizard
- Manual test without API key: should show helpful error

---

### Task 3.9: Update Configuration Files

**Priority**: P2 (Medium)
**Effort**: 0.25 hours
**Dependencies**: None

**Description**: Update .gitignore to remove the .loa-setup-complete entry.

**Files to Modify**:
- `.gitignore` - Remove `.loa-setup-complete` entry (or mark as legacy)

**Acceptance Criteria**:
- [ ] `.loa-setup-complete` no longer explicitly listed (or marked as legacy comment)

**Note**: We're not requiring the file to be tracked - just cleaning up the gitignore. The entry can be left with a "# Legacy - no longer created" comment for clarity.

---

### Task 3.10: Update Documentation

**Priority**: P1 (High)
**Effort**: 1.5 hours
**Dependencies**: Tasks 3.1-1.9

**Description**: Update all documentation to reflect the new workflow without setup.

**Files to Modify**:

1. **README.md**:
   - Remove `/setup` from Quick Start
   - Remove Phase 0 from workflow table
   - Update clone instructions to go straight to `/plan-and-analyze`

2. **CLAUDE.md**:
   - Remove Phase 0 from workflow table
   - Update Prerequisites section
   - Add note about THJ detection via API key

3. **PROCESS.md**:
   - Remove setup documentation section
   - Update workflow diagram
   - Remove references to `.loa-setup-complete`

4. **CHANGELOG.md**:
   - Add 0.15.0 entry documenting breaking change
   - Include migration instructions

**Acceptance Criteria**:
- [ ] No documentation references `/setup` as required step
- [ ] Quick Start shows direct workflow entry
- [ ] THJ detection documented as API key-based
- [ ] CHANGELOG has proper breaking change notice

**Testing Requirements**:
- Review documentation for consistency
- Verify no broken internal links

---

### Task 3.11: Write Unit Tests

**Priority**: P1 (High)
**Effort**: 1 hour
**Dependencies**: Tasks 3.1, 1.2

**Description**: Create comprehensive unit tests for the new THJ detection mechanism.

**Files to Create**:
- `tests/unit/thj-detection.bats`

**Test Cases**:
```bash
# is_thj_member() tests
- "is_thj_member: returns 0 when API key is set"
- "is_thj_member: returns 1 when API key is empty"
- "is_thj_member: returns 1 when API key is unset"
- "is_thj_member: handles whitespace-only key as non-empty"

# get_user_type() tests
- "get_user_type: returns 'thj' when API key set"
- "get_user_type: returns 'oss' when API key unset"

# should_track_analytics() tests
- "should_track_analytics: returns 0 when THJ"
- "should_track_analytics: returns 1 when OSS"

# check-thj-member.sh tests
- "check-thj-member.sh: exits 0 with API key"
- "check-thj-member.sh: exits 1 without API key"
```

**Acceptance Criteria**:
- [ ] All unit tests pass
- [ ] Tests cover all edge cases from PRD
- [ ] Tests are self-contained (no external dependencies)

---

### Task 3.12: Write Integration Tests

**Priority**: P1 (High)
**Effort**: 1 hour
**Dependencies**: Tasks 3.3-1.8

**Description**: Create integration tests verifying commands work without setup marker.

**Files to Create**:
- `tests/integration/setup-removal.bats`

**Test Cases**:
```bash
# Prerequisite checks without marker
- "plan-and-analyze: works without .loa-setup-complete"
- "architect: works without .loa-setup-complete (needs prd.md)"
- "sprint-plan: works without .loa-setup-complete (needs prd.md, sdd.md)"
- "implement: works without .loa-setup-complete"

# Feedback command
- "feedback: works with API key set"
- "feedback: fails gracefully without API key"

# Git safety
- "git-safety: detects template without marker"

# Edge cases
- "old marker ignored when present"
```

**Acceptance Criteria**:
- [ ] All integration tests pass
- [ ] Tests verify backward compatibility with old markers
- [ ] Tests run in isolated environment

---

### Task 3.13: Run Full Test Suite and Manual Verification

**Priority**: P0 (Critical)
**Effort**: 1 hour
**Dependencies**: All previous tasks

**Description**: Run complete test suite and perform manual verification of the complete workflow.

**Activities**:
1. Run all unit tests: `bats tests/unit/`
2. Run all integration tests: `bats tests/integration/`
3. Manual workflow test (OSS user):
   - Clone fresh copy
   - Run `/plan-and-analyze` immediately
   - Verify no setup errors
4. Manual workflow test (THJ user):
   - Set `LOA_CONSTRUCTS_API_KEY`
   - Run `/plan-and-analyze`
   - Run `/feedback` and verify it works
5. Backward compatibility test:
   - Create old `.loa-setup-complete` file
   - Verify commands still work and ignore marker

**Acceptance Criteria**:
- [ ] All automated tests pass
- [ ] Manual OSS workflow succeeds
- [ ] Manual THJ workflow succeeds
- [ ] Backward compatibility verified
- [ ] No regressions in existing functionality

---

## Task Summary

| Task | Priority | Effort | Dependencies |
|------|----------|--------|--------------|
| 3.1 Core THJ Detection | P0 | 1.5h | None |
| 3.2 Update Analytics | P0 | 0.5h | 3.1 |
| 3.3 Delete Commands | P0 | 0.5h | None |
| 3.4 Update Prerequisites | P0 | 0.5h | None |
| 3.5 Update Preflight | P1 | 0.5h | 3.1 |
| 3.6 Update Git-Safety | P1 | 0.5h | None |
| 3.7 Remove Pre-flights | P0 | 1.5h | None |
| 3.8 Update Feedback | P1 | 0.5h | 3.1 |
| 3.9 Update Config | P2 | 0.25h | None |
| 3.10 Update Docs | P1 | 1.5h | 3.1-3.9 |
| 3.11 Unit Tests | P1 | 1h | 3.1, 3.2 |
| 3.12 Integration Tests | P1 | 1h | 3.3-3.8 |
| 3.13 Verification | P0 | 1h | All |
| **TOTAL** | | **~10h** | |

---

## Execution Order (Optimized)

### Phase A: Parallel Foundation (Tasks without dependencies)
Can be done in parallel:
- Task 3.1: Core THJ Detection
- Task 3.3: Delete Commands
- Task 3.4: Update Prerequisites
- Task 3.6: Update Git-Safety
- Task 3.9: Update Config

### Phase B: Dependent Updates (After Phase A)
After 3.1 completes:
- Task 3.2: Update Analytics
- Task 3.5: Update Preflight
- Task 3.8: Update Feedback

### Phase C: Command Updates (Can start with Phase A)
- Task 3.7: Remove Pre-flights from commands

### Phase D: Documentation (After all code changes)
- Task 3.10: Update Documentation

### Phase E: Testing (After code complete)
Can be done in parallel:
- Task 3.11: Unit Tests
- Task 3.12: Integration Tests

### Phase F: Final Verification
- Task 3.13: Full Test Suite and Manual Verification

---

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| Commands fail without marker | Thorough testing of each command |
| THJ users confused | Clear CHANGELOG and documentation |
| Analytics disruption | Test analytics flow with API key |
| Git safety broken | Verify template detection via URL works |

---

## Definition of Done

- [ ] All 13 tasks completed
- [ ] All tests pass (unit + integration)
- [ ] Documentation updated
- [ ] Manual verification complete
- [ ] Code reviewed (via `/review-sprint sprint-3`)
- [ ] Security reviewed (via `/audit-sprint sprint-3`)
- [ ] Ready for version bump to 0.15.0

---

*Sprint plan generated by Loa planning-sprints agent*
*Next step: `/implement sprint-3` to begin implementation*
