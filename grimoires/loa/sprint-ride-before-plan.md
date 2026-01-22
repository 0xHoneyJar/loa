# Sprint Plan: Ground /plan-and-analyze in Codebase Reality

**Version**: 1.0.0
**PRD**: `grimoires/loa/prd-ride-before-plan.md`
**SDD**: `grimoires/loa/sdd-ride-before-plan.md`
**Issue**: [#44](https://github.com/0xHoneyJar/loa/issues/44)
**Cycle**: cycle-007

---

## Overview

| Attribute | Value |
|-----------|-------|
| Total Sprints | 2 |
| Sprint Duration | 1 day each |
| Team Size | 1 (Claude agent) |
| Total Effort | ~28 hours |

### Sprint Summary

| Sprint | Focus | Tasks | Effort |
|--------|-------|-------|--------|
| Sprint 1 | Core Integration | 6 | ~17h |
| Sprint 2 | Hardening & Docs | 5 | ~11h |

---

## Sprint 1: Core Integration

**Goal**: Implement the core codebase detection and /ride integration, achieving functional brownfield grounding.

**Success Criteria**:
- Brownfield projects automatically run /ride before PRD discovery
- Greenfield projects experience zero added latency
- Reality files loaded as highest-priority context

### Tasks

#### Task 1.1: Create detect-codebase.sh Script

**Description**: Create the codebase detection script that determines GREENFIELD vs BROWNFIELD status.

**Acceptance Criteria**:
- [ ] Script at `.claude/scripts/detect-codebase.sh`
- [ ] Outputs valid JSON with: type, files, lines, language, paths_found, reality_exists, reality_age_days
- [ ] Detects source files with extensions: ts, tsx, js, jsx, py, go, rs, java, rb, php, cs, cpp, c, h
- [ ] Excludes: node_modules, vendor, .git, dist, build, __pycache__, target, .next, .nuxt
- [ ] BROWNFIELD threshold: >10 source files OR >500 lines
- [ ] Completes in <5 seconds on typical codebases
- [ ] Handles missing directories gracefully
- [ ] Cross-platform stat command (Linux/macOS)

**Effort**: 3 hours

**Dependencies**: None

**Testing**:
- Empty directory → GREENFIELD
- 15 TypeScript files → BROWNFIELD
- node_modules with 1000 files but no src/ → GREENFIELD
- Existing reality/ directory detected with correct age

---

#### Task 1.2: Create detect-codebase.sh Unit Tests

**Description**: Create bats test suite for the detection script.

**Acceptance Criteria**:
- [ ] Test file at `.claude/scripts/tests/test-detect-codebase.bats`
- [ ] Tests for: empty dir, file threshold, line threshold, exclusions, reality detection
- [ ] All tests pass
- [ ] Uses temp directories for isolation

**Effort**: 2 hours

**Dependencies**: Task 1.1

**Testing**: `bats .claude/scripts/tests/test-detect-codebase.bats`

---

#### Task 1.3: Update plan-and-analyze.md Command

**Description**: Add codebase detection pre-flight check and reality context files.

**Acceptance Criteria**:
- [ ] Version bumped to 3.0.0
- [ ] Pre-flight check added for detect-codebase.sh with store_result
- [ ] Context files added for reality/ with priority 1:
  - grimoires/loa/reality/extracted-prd.md
  - grimoires/loa/reality/extracted-sdd.md
  - grimoires/loa/reality/component-inventory.md
  - grimoires/loa/consistency-report.md
- [ ] Existing context/ files set to priority 2
- [ ] New `--fresh` flag documented for forcing /ride re-run
- [ ] Description updated to mention automatic codebase grounding

**Effort**: 2 hours

**Dependencies**: Task 1.1

**Testing**:
- YAML validates correctly
- Pre-flight check runs without error

---

#### Task 1.4: Add Phase -0.5 to discovering-requirements Skill

**Description**: Add codebase grounding phase to the skill workflow.

**Acceptance Criteria**:
- [ ] New `<codebase_grounding>` section added after `<kernel_framework>`
- [ ] Decision tree implemented:
  - GREENFIELD → skip to Phase -1
  - BROWNFIELD + fresh reality → use cached
  - BROWNFIELD + stale/missing reality → execute /ride
- [ ] Progress feedback template defined
- [ ] /ride invocation instructions documented (skill-level, not command)
- [ ] 20-minute timeout specified

**Effort**: 4 hours

**Dependencies**: Task 1.3

**Testing**:
- Skill file validates as markdown
- Decision tree logic is clear and complete

---

#### Task 1.5: Update Phase 0 Context Synthesis

**Description**: Modify Phase 0 to present codebase understanding before user context.

**Acceptance Criteria**:
- [ ] Context priority order documented: reality > context > interview
- [ ] New presentation template for codebase understanding:
  - "What I've Learned From Your Codebase"
  - Architecture summary with [CODE:file:line] citations
  - Existing features list
  - Proposed additions
- [ ] Conflict resolution guidance: reality wins, flag for user
- [ ] Citation format: `[CODE:file:line]` for reality sources

**Effort**: 3 hours

**Dependencies**: Task 1.4

**Testing**:
- Template renders correctly
- Citation format is consistent

---

#### Task 1.6: Implement Greenfield Fast Path

**Description**: Ensure greenfield projects have zero added latency.

**Acceptance Criteria**:
- [ ] No message displayed for GREENFIELD
- [ ] No delay added
- [ ] Proceeds directly to Phase -1
- [ ] Detection result logged to trajectory but not shown to user

**Effort**: 1 hour

**Dependencies**: Task 1.4

**Testing**:
- Run /plan-and-analyze on empty repo
- Verify no codebase-related output
- Measure latency is unchanged

---

### Sprint 1 Deliverables

| Deliverable | Location |
|-------------|----------|
| detect-codebase.sh | `.claude/scripts/detect-codebase.sh` |
| Unit tests | `.claude/scripts/tests/test-detect-codebase.bats` |
| Updated command | `.claude/commands/plan-and-analyze.md` |
| Updated skill | `.claude/skills/discovering-requirements/SKILL.md` |

---

## Sprint 2: Hardening & Documentation

**Goal**: Add error recovery, configuration options, and update documentation.

**Success Criteria**:
- Error recovery flow works for /ride failures
- Configuration allows disabling/customizing feature
- All documentation reflects new behavior

### Tasks

#### Task 2.1: Implement Cached Reality Detection

**Description**: Add logic to detect and use recent /ride output, with stale warning.

**Acceptance Criteria**:
- [ ] Check reality file modification times
- [ ] If <7 days old: skip /ride, show "Using recent codebase analysis (N days old)"
- [ ] If >7 days old: use AskUserQuestion with options:
  - "Re-run /ride for fresh analysis (recommended)"
  - "Proceed with existing analysis (faster)"
- [ ] Staleness threshold configurable via .loa.config.yaml
- [ ] `--fresh` flag overrides cache and forces re-run

**Effort**: 3 hours

**Dependencies**: Sprint 1 complete

**Testing**:
- Touch reality file to 3 days ago → uses cached
- Touch reality file to 10 days ago → prompts user
- Use --fresh flag → always re-runs

---

#### Task 2.2: Implement Error Recovery Flow

**Description**: Add robust error handling for /ride failures and timeouts.

**Acceptance Criteria**:
- [ ] Capture /ride error messages
- [ ] Use AskUserQuestion with options:
  - "Retry /ride analysis"
  - "Skip and proceed without codebase grounding (not recommended)"
  - "Abort /plan-and-analyze"
- [ ] If Skip: log warning to NOTES.md blockers section
- [ ] Preserve partial results if available
- [ ] Handle 20-minute timeout gracefully

**Effort**: 3 hours

**Dependencies**: Sprint 1 complete

**Testing**:
- Simulate /ride failure → recovery prompt shown
- Select Skip → warning logged, proceeds
- Select Retry → /ride runs again
- Select Abort → exits cleanly

---

#### Task 2.3: Add Configuration Options

**Description**: Add .loa.config.yaml section for codebase grounding settings.

**Acceptance Criteria**:
- [ ] New config section:
  ```yaml
  plan_and_analyze:
    codebase_grounding:
      enabled: true
      reality_staleness_days: 7
      ride_timeout_minutes: 20
      skip_on_ride_error: false
  ```
- [ ] Config values read in skill with yq
- [ ] Defaults applied when config missing
- [ ] `enabled: false` completely disables Phase -0.5

**Effort**: 2 hours

**Dependencies**: Task 2.1

**Testing**:
- Set enabled: false → no codebase detection
- Set staleness_days: 3 → uses 3-day threshold
- Missing config → uses defaults

---

#### Task 2.4: Update CLAUDE.md Documentation

**Description**: Document the new workflow in CLAUDE.md.

**Acceptance Criteria**:
- [ ] Update `/plan-and-analyze` description in Workflow Commands table
- [ ] Add note about automatic codebase grounding for brownfield projects
- [ ] Document the `--fresh` flag
- [ ] Add config options to Configuration section
- [ ] Update Prerequisites section to remove manual /ride suggestion

**Effort**: 1.5 hours

**Dependencies**: Task 2.3

**Testing**:
- Documentation is accurate and complete
- No broken links or references

---

#### Task 2.5: Update PROCESS.md and Test

**Description**: Update PROCESS.md and perform end-to-end testing.

**Acceptance Criteria**:
- [ ] Update Phase 1 description in PROCESS.md
- [ ] Note that /ride runs automatically for brownfield
- [ ] End-to-end test on greenfield repo (zero latency)
- [ ] End-to-end test on small brownfield (<100 files)
- [ ] End-to-end test with existing recent reality
- [ ] End-to-end test with stale reality (>7 days)
- [ ] Close issue #44 with summary

**Effort**: 1.5 hours

**Dependencies**: Task 2.4

**Testing**:
- All end-to-end scenarios pass
- Issue #44 closed

---

### Sprint 2 Deliverables

| Deliverable | Location |
|-------------|----------|
| Error recovery | In skill workflow |
| Configuration | `.loa.config.yaml` schema |
| Updated CLAUDE.md | `CLAUDE.md` |
| Updated PROCESS.md | `PROCESS.md` |

---

## Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| /ride takes too long | Low | Medium | 20-min timeout, cache |
| Detection false positives | Low | Low | Conservative thresholds |
| /ride failures | Medium | Medium | Error recovery flow |
| Config parsing errors | Low | Low | Defaults fallback |

---

## Definition of Done

### Sprint 1
- [ ] All tasks completed
- [ ] Unit tests pass
- [ ] Greenfield has zero added latency
- [ ] Brownfield triggers /ride automatically

### Sprint 2
- [ ] All tasks completed
- [ ] Error recovery tested
- [ ] Configuration tested
- [ ] Documentation updated
- [ ] Issue #44 closed

### Feature Complete
- [ ] All acceptance criteria met
- [ ] No regressions in existing functionality
- [ ] Ready for v1.6.0 release

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
