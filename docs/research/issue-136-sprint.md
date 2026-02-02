# Sprint Plan: CLAUDE.md Context Loading Optimization

**Version:** 1.0
**Date:** 2026-02-02
**Issue:** [#136](https://github.com/0xHoneyJar/loa/issues/136)
**SDD Reference:** docs/research/issue-136-sdd.md
**Research Reference:** docs/research/issue-136-claude-md-research.md

---

## Sprint Overview

| Attribute | Value |
|-----------|-------|
| Total Sprints | 3 |
| Sprint Duration | 1 week each |
| Team Size | 1 developer (agent-assisted) |
| Target Completion | 3 weeks |

### Goals Summary

| Sprint | Goal | Target Lines |
|--------|------|--------------|
| Sprint 1 | Reference Extraction | 1169 → ~750 |
| Sprint 2 | Skill Migration | ~750 → ~400 |
| Sprint 3 | Final Optimization | ~400 → ~150 |

---

## Sprint 1: Reference Extraction

**Goal**: Extract reference-only content to dedicated files
**Target**: Reduce CLAUDE.loa.md from 1169 to ~750 lines (~36% reduction)
**Risk Level**: Low

### Tasks

#### Task 1.1: Create Reference Directory Structure

**Description**: Set up the `.claude/loa/reference/` directory with README index.

**Acceptance Criteria**:
- [ ] Directory `.claude/loa/reference/` exists
- [ ] `README.md` created with index of reference files
- [ ] Directory added to `.claude/checksums.json` for integrity tracking

**Effort**: Small (1-2 hours)
**Dependencies**: None

---

#### Task 1.2: Extract YAML Config Examples

**Description**: Move all inline YAML configuration examples from CLAUDE.loa.md to a new `.loa.config.yaml.example` file.

**Acceptance Criteria**:
- [ ] New file `.loa.config.yaml.example` created
- [ ] All YAML code blocks from CLAUDE.loa.md moved
- [ ] Examples organized by feature section
- [ ] Header comment explains purpose and links to config-reference.md
- [ ] ~200 lines removed from CLAUDE.loa.md

**Effort**: Medium (2-4 hours)
**Dependencies**: Task 1.1

**Content to Move**:
- `plan_and_analyze:` examples
- `goal_traceability:` examples
- `goal_validation:` examples
- `autonomous_agent:` examples
- `effort:` examples
- `context_editing:` examples
- `memory_schema:` examples
- `skills:` examples
- `learnings:` examples
- `oracle:` examples
- `compound_learning:` examples
- `visual_communication:` examples
- `feedback:` examples
- `update_loa:` examples
- `prompt_enhancement:` examples
- `url_registry:` examples

---

#### Task 1.3: Extract Version Feature Notes

**Description**: Move version-specific feature documentation (v1.x.0 sections) to `version-features.md`.

**Acceptance Criteria**:
- [ ] New file `.claude/loa/reference/version-features.md` created
- [ ] All "(v1.x.0)" annotated sections moved
- [ ] Organized chronologically by version
- [ ] ~60 lines removed from CLAUDE.loa.md
- [ ] CLAUDE.loa.md retains single-line version mentions where needed

**Effort**: Medium (2-3 hours)
**Dependencies**: Task 1.1

**Content to Move**:
- Automatic Codebase Grounding (v1.6.0)
- Guided Workflow (v0.21.0)
- Autonomous Agent Orchestration (v1.11.0)
- Claude Code 2.1.x Features (v1.9.0)
- Effort Parameter (v1.13.0)
- Context Editing (v1.13.0)
- Memory Schema (v1.13.0)
- Skill Best Practices (v1.14.0)
- Compound Learning (v1.10.0)
- Visual Communication (v1.10.0)
- Oracle (v1.11.0) + Two-Tier Learnings (v1.15.1)
- Smart Feedback Routing (v1.11.0)
- WIP Branch Testing (v1.11.0)

---

#### Task 1.4: Extract Script Documentation

**Description**: Move helper script documentation to `scripts-reference.md`.

**Acceptance Criteria**:
- [ ] New file `.claude/loa/reference/scripts-reference.md` created
- [ ] All script tables and usage examples moved
- [ ] Organized by script category
- [ ] ~60 lines removed from CLAUDE.loa.md
- [ ] CLAUDE.loa.md retains only "See scripts-reference.md" pointer

**Effort**: Small (1-2 hours)
**Dependencies**: Task 1.1

**Content to Move**:
- Helper Scripts table
- Search Orchestration section
- Script usage examples
- Environment variable documentation

---

#### Task 1.5: Extract Protocol Documentation

**Description**: Move detailed protocol documentation to `protocols-summary.md`.

**Acceptance Criteria**:
- [ ] New file `.claude/loa/reference/protocols-summary.md` created
- [ ] Key Protocols section content moved
- [ ] Protocol file references consolidated
- [ ] ~100 lines removed from CLAUDE.loa.md
- [ ] CLAUDE.loa.md retains protocol names with file pointers only

**Effort**: Medium (2-3 hours)
**Dependencies**: Task 1.1

**Content to Move**:
- Structured Agentic Memory details
- Attention Budget Enforcement details
- Lossless Ledger Protocol details
- Recursive JIT Context details
- Feedback Loops details
- Karpathy Principles full explanation

---

#### Task 1.6: Create Context Engineering Reference

**Description**: Create `context-engineering.md` for context management documentation.

**Acceptance Criteria**:
- [ ] New file `.claude/loa/reference/context-engineering.md` created
- [ ] Context Editing section moved
- [ ] Memory Schema section moved
- [ ] Effort Parameter section moved
- [ ] ~180 lines removed from CLAUDE.loa.md

**Effort**: Medium (2-3 hours)
**Dependencies**: Task 1.1

---

#### Task 1.7: Add Reference Pointers to CLAUDE.loa.md

**Description**: Add "Quick Reference" section with pointers to moved content.

**Acceptance Criteria**:
- [ ] New "Quick Reference" section added (~20 lines)
- [ ] Links to all reference files
- [ ] Clear guidance on when to consult each file
- [ ] Skills auto-load message included

**Effort**: Small (1 hour)
**Dependencies**: Tasks 1.2-1.6

---

#### Task 1.8: Sprint 1 Validation

**Description**: Validate all changes and measure reduction.

**Acceptance Criteria**:
- [ ] `wc -l .claude/loa/CLAUDE.loa.md` shows ≤750 lines
- [ ] All reference files readable and well-organized
- [ ] No orphaned content (grep verification)
- [ ] Basic smoke test: `/plan-and-analyze`, `/implement`, `/review-sprint` work
- [ ] Checksums updated

**Effort**: Medium (2-3 hours)
**Dependencies**: All Sprint 1 tasks

---

### Sprint 1 Deliverables

| Deliverable | Status |
|-------------|--------|
| `.claude/loa/reference/README.md` | New |
| `.claude/loa/reference/protocols-summary.md` | New |
| `.claude/loa/reference/scripts-reference.md` | New |
| `.claude/loa/reference/version-features.md` | New |
| `.claude/loa/reference/context-engineering.md` | New |
| `.loa.config.yaml.example` | New |
| `.claude/loa/CLAUDE.loa.md` | Modified (~750 lines) |

### Sprint 1 Success Criteria

- [ ] Line count: 1169 → ≤750 (36% reduction)
- [ ] Character count: 43KB → ≤30KB
- [ ] All reference files created and indexed
- [ ] No functionality broken
- [ ] PR ready for review

---

## Sprint 2: Skill Migration

**Goal**: Move skill-specific documentation to respective SKILL.md files
**Target**: Reduce CLAUDE.loa.md from ~750 to ~400 lines (~47% additional reduction)
**Risk Level**: Medium (requires testing each skill)

### Tasks

#### Task 2.1: Enhance autonomous-agent/SKILL.md

**Description**: Move Autonomous Agent Orchestration documentation to skill file.

**Acceptance Criteria**:
- [ ] Autonomous Agent section moved to `.claude/skills/autonomous-agent/SKILL.md`
- [ ] 8-Phase Execution Model documentation included
- [ ] Operator Detection documentation included
- [ ] Quality Gates documentation included
- [ ] ~80 lines removed from CLAUDE.loa.md
- [ ] Skill invocation test passes

**Effort**: Medium (2-3 hours)
**Dependencies**: Sprint 1 complete

---

#### Task 2.2: Enhance run-mode/SKILL.md

**Description**: Move Run Mode documentation to skill file.

**Acceptance Criteria**:
- [ ] Run Mode section moved to `.claude/skills/run-mode/SKILL.md`
- [ ] Safety Model (4-Level Defense) included
- [ ] Circuit Breaker Triggers included
- [ ] Command table included
- [ ] ~50 lines removed from CLAUDE.loa.md
- [ ] `/run` command test passes

**Effort**: Medium (2-3 hours)
**Dependencies**: Sprint 1 complete

---

#### Task 2.3: Enhance planning-sprints/SKILL.md

**Description**: Move Goal Traceability documentation to skill file.

**Acceptance Criteria**:
- [ ] Goal Traceability section moved to `.claude/skills/planning-sprints/SKILL.md`
- [ ] Goal ID system documentation included
- [ ] Appendix C generation documentation included
- [ ] E2E Validation Task documentation included
- [ ] ~50 lines removed from CLAUDE.loa.md
- [ ] `/sprint-plan` command test passes

**Effort**: Medium (2-3 hours)
**Dependencies**: Sprint 1 complete

---

#### Task 2.4: Enhance discovering-requirements/SKILL.md

**Description**: Move Codebase Grounding documentation to skill file.

**Acceptance Criteria**:
- [ ] Codebase Grounding section moved to `.claude/skills/discovering-requirements/SKILL.md`
- [ ] Brownfield detection documentation included
- [ ] Reality caching documentation included
- [ ] ~40 lines removed from CLAUDE.loa.md
- [ ] `/plan-and-analyze` command test passes

**Effort**: Small (1-2 hours)
**Dependencies**: Sprint 1 complete

---

#### Task 2.5: Enhance enhancing-prompts/SKILL.md

**Description**: Move Prompt Enhancement documentation to skill file.

**Acceptance Criteria**:
- [ ] Prompt Enhancement section moved to `.claude/skills/enhancing-prompts/SKILL.md`
- [ ] PTCF framework documentation included
- [ ] Quality Scoring documentation included
- [ ] ~40 lines removed from CLAUDE.loa.md
- [ ] `/enhance` command test passes

**Effort**: Small (1-2 hours)
**Dependencies**: Sprint 1 complete

---

#### Task 2.6: Enhance continuous-learning/SKILL.md

**Description**: Move Compound Learning documentation to skill file.

**Acceptance Criteria**:
- [ ] Compound Learning section moved to `.claude/skills/continuous-learning/SKILL.md`
- [ ] Pattern Detection documentation included
- [ ] 4-Gate Quality Filter documentation included
- [ ] ~50 lines removed from CLAUDE.loa.md
- [ ] `/compound` command test passes

**Effort**: Medium (2-3 hours)
**Dependencies**: Sprint 1 complete

---

#### Task 2.7: Enhance riding-codebase/SKILL.md (Oracle)

**Description**: Move Oracle/Learnings documentation to skill file.

**Acceptance Criteria**:
- [ ] Two-Tier Learnings section moved to `.claude/skills/riding-codebase/SKILL.md`
- [ ] Oracle commands documentation included
- [ ] Query merging documentation included
- [ ] ~100 lines removed from CLAUDE.loa.md
- [ ] `/oracle-analyze` command test passes

**Effort**: Medium (2-3 hours)
**Dependencies**: Sprint 1 complete

---

#### Task 2.8: Enhance implementing-tasks/SKILL.md

**Description**: Move implementation-specific protocols to skill file.

**Acceptance Criteria**:
- [ ] Attention Budget section moved
- [ ] Implementation Notes section moved
- [ ] ~40 lines removed from CLAUDE.loa.md
- [ ] `/implement` command test passes

**Effort**: Small (1-2 hours)
**Dependencies**: Sprint 1 complete

---

#### Task 2.9: Sprint 2 Validation

**Description**: Comprehensive validation of all skill migrations.

**Acceptance Criteria**:
- [ ] `wc -l .claude/loa/CLAUDE.loa.md` shows ≤400 lines
- [ ] Each migrated skill tested individually
- [ ] Skills load their documentation when invoked
- [ ] No orphaned content in CLAUDE.loa.md
- [ ] Full workflow test: `/plan-and-analyze` → `/architect` → `/sprint-plan` → `/implement`

**Effort**: Medium (3-4 hours)
**Dependencies**: All Sprint 2 tasks

---

### Sprint 2 Deliverables

| Deliverable | Status |
|-------------|--------|
| `.claude/skills/autonomous-agent/SKILL.md` | Enhanced |
| `.claude/skills/run-mode/SKILL.md` | Enhanced |
| `.claude/skills/planning-sprints/SKILL.md` | Enhanced |
| `.claude/skills/discovering-requirements/SKILL.md` | Enhanced |
| `.claude/skills/enhancing-prompts/SKILL.md` | Enhanced |
| `.claude/skills/continuous-learning/SKILL.md` | Enhanced |
| `.claude/skills/riding-codebase/SKILL.md` | Enhanced |
| `.claude/skills/implementing-tasks/SKILL.md` | Enhanced |
| `.claude/loa/CLAUDE.loa.md` | Modified (~400 lines) |

### Sprint 2 Success Criteria

- [ ] Line count: ~750 → ≤400 (47% reduction)
- [ ] Character count: ~30KB → ≤18KB
- [ ] All 8 skills enhanced and tested
- [ ] Skills auto-load documentation when invoked
- [ ] No functionality broken
- [ ] PR ready for review

---

## Sprint 3: Final Optimization

**Goal**: Condense remaining content to essential-only
**Target**: Reduce CLAUDE.loa.md from ~400 to ~150 lines (62% additional reduction)
**Risk Level**: Medium (requires careful content curation)

### Tasks

#### Task 3.1: Condense Architecture Section

**Description**: Rewrite Architecture section for maximum brevity.

**Acceptance Criteria**:
- [ ] Three-Zone Model condensed to essential rules only
- [ ] Skills System condensed to overview table only
- [ ] Remove redundant explanations
- [ ] ~50 lines removed
- [ ] Core understanding preserved

**Effort**: Medium (2-3 hours)
**Dependencies**: Sprint 2 complete

---

#### Task 3.2: Consolidate Command Tables

**Description**: Merge redundant command tables into single reference.

**Acceptance Criteria**:
- [ ] Single "Workflow Commands" table
- [ ] Remove duplicate command listings
- [ ] ~30 lines removed
- [ ] All commands still documented

**Effort**: Small (1-2 hours)
**Dependencies**: Sprint 2 complete

---

#### Task 3.3: Condense Behavioral Rules

**Description**: Reduce Karpathy Principles and Git Safety to bullet points.

**Acceptance Criteria**:
- [ ] Karpathy Principles: 4 bullet points max
- [ ] Git Safety: 5 bullet points max
- [ ] Feedback Loops: 3 bullet points max
- [ ] ~40 lines removed
- [ ] Core guidance preserved

**Effort**: Small (1-2 hours)
**Dependencies**: Sprint 2 complete

---

#### Task 3.4: Remove Verbose Explanations

**Description**: Final pass to remove any remaining verbose content.

**Acceptance Criteria**:
- [ ] No section exceeds 30 lines
- [ ] Remove "NOTE:" and "IMPORTANT:" blocks (move to skills)
- [ ] Remove inline examples (reference to example file)
- [ ] ~50 lines removed

**Effort**: Medium (2-3 hours)
**Dependencies**: Tasks 3.1-3.3

---

#### Task 3.5: Add Compaction Instructions

**Description**: Add custom compaction instructions to preserve critical context.

**Acceptance Criteria**:
- [ ] Compaction section added (~10 lines)
- [ ] Specifies what to preserve during `/compact`
- [ ] Follows official Claude Code guidance

**Effort**: Small (1 hour)
**Dependencies**: Task 3.4

---

#### Task 3.6: Final Validation & Documentation

**Description**: Comprehensive final validation and documentation update.

**Acceptance Criteria**:
- [ ] `wc -l .claude/loa/CLAUDE.loa.md` shows ≤150 lines
- [ ] Below ~500 line official recommendation ✅
- [ ] Full test suite passes
- [ ] All workflows tested
- [ ] CHANGELOG.md updated with v2.0.0 notes
- [ ] Migration guide created (if needed)

**Effort**: Medium (3-4 hours)
**Dependencies**: All Sprint 3 tasks

---

### Sprint 3 Deliverables

| Deliverable | Status |
|-------------|--------|
| `.claude/loa/CLAUDE.loa.md` | Final (~150 lines) |
| `CHANGELOG.md` | Updated |
| Migration guide (optional) | New |

### Sprint 3 Success Criteria

- [ ] Line count: ~400 → ≤150 (62% reduction)
- [ ] Character count: ~18KB → ≤12KB
- [ ] Below ~500 line official recommendation ✅
- [ ] All tests pass
- [ ] All workflows functional
- [ ] Ready for release

---

## Risk Assessment

| Risk | Sprint | Impact | Mitigation |
|------|--------|--------|------------|
| Skill auto-loading unreliable | 2 | High | Test each skill; document manual invocation fallback |
| Information harder to find | 1-3 | Medium | Clear README index; pointer comments in CLAUDE.loa.md |
| Behavior regression | 2-3 | High | Incremental changes; full test suite; revert capability |
| Over-condensing loses context | 3 | Medium | Preserve essential rules; user testing before merge |

---

## Dependencies

| Dependency | Required For | Status |
|------------|--------------|--------|
| Research document approved | Sprint 1 | ✅ Complete |
| SDD approved | Sprint 1 | ✅ Complete |
| Test suite available | All sprints | Existing |
| Maintainer review capacity | Each sprint | TBD |

---

## Appendix A: Content Migration Map

| Source Section | Target Location | Sprint |
|----------------|-----------------|--------|
| YAML config examples | .loa.config.yaml.example | 1 |
| Version notes (v1.x.0) | reference/version-features.md | 1 |
| Script documentation | reference/scripts-reference.md | 1 |
| Protocol details | reference/protocols-summary.md | 1 |
| Context Editing | reference/context-engineering.md | 1 |
| Memory Schema | reference/context-engineering.md | 1 |
| Effort Parameter | reference/context-engineering.md | 1 |
| Autonomous Agent | skills/autonomous-agent/SKILL.md | 2 |
| Run Mode | skills/run-mode/SKILL.md | 2 |
| Goal Traceability | skills/planning-sprints/SKILL.md | 2 |
| Codebase Grounding | skills/discovering-requirements/SKILL.md | 2 |
| Prompt Enhancement | skills/enhancing-prompts/SKILL.md | 2 |
| Compound Learning | skills/continuous-learning/SKILL.md | 2 |
| Oracle/Learnings | skills/riding-codebase/SKILL.md | 2 |
| Attention Budget | skills/implementing-tasks/SKILL.md | 2 |

---

## Appendix B: Verification Commands

```bash
# Check line count
wc -l .claude/loa/CLAUDE.loa.md

# Check character count
wc -c .claude/loa/CLAUDE.loa.md

# Check for orphaned content (after migration)
grep -n "v1\.[0-9]\.0" .claude/loa/CLAUDE.loa.md

# Verify reference files exist
ls -la .claude/loa/reference/

# Test skill loading (manual)
# Invoke each /command and verify documentation loads
```

---

## Next Steps

After sprint plan approval:

```bash
# Start Sprint 1
/implement sprint-1
```
