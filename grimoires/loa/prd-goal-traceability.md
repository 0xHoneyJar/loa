# Product Requirements Document: Goal Traceability & End-to-End Validation

**Version:** 1.0
**Date:** 2026-01-23
**Author:** PRD Architect Agent
**Status:** Draft
**Issue Reference:** https://github.com/0xHoneyJar/loa/issues/45

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Problem Statement](#problem-statement)
3. [Goals & Success Metrics](#goals--success-metrics)
4. [User Personas & Use Cases](#user-personas--use-cases)
5. [Functional Requirements](#functional-requirements)
6. [Non-Functional Requirements](#non-functional-requirements)
7. [User Experience](#user-experience)
8. [Technical Considerations](#technical-considerations)
9. [Scope & Prioritization](#scope--prioritization)
10. [Success Criteria](#success-criteria)
11. [Risks & Mitigation](#risks--mitigation)
12. [Appendix](#appendix)

---

## Executive Summary

This PRD addresses a critical gap in the Loa workflow: **PRD goals can be defined but not achieved** even when all sprint tasks complete successfully. The root cause is a missing traceability layer between high-level goals and implementation tasks.

The proposed solution adds explicit goal IDs, goal-to-task mapping in sprint plans, goal achievement validation during reviews, integration dependency detection, and an automatic end-to-end validation task. Additionally, a guided `/loa` command will help users navigate the complete workflow.

**Evidence**: In a real-world case (Score API V8), timing columns were stored but never connected to actual score calculations because no task explicitly validated that "scoring MVs use new timing columns" - the original goal.

---

## Problem Statement

### The Problem

Loa's workflow successfully traces **Features → Tasks → Implementation** but lacks traceability from **Goals → Features → Achieved Outcomes**. This creates a gap where all tasks complete but PRD goals remain unachieved.

### User Pain Points

1. **Silent Goal Failure**: All tasks marked complete, but actual goal not achieved
2. **Missing Integration Detection**: New data columns/APIs created but not used by consuming code
3. **No Goal Validation Step**: Reviews check "did we build correctly?" not "did we achieve the goal?"
4. **Manual Workflow Navigation**: Users must remember command sequence without guidance
5. **No Goal Progress Visibility**: Can't see which sprints contribute to which goals

### Current State

```
PRD Goals (prose)
    ↓ (implicit, manual mapping)
PRD Features (FR-1, FR-2)
    ↓ (explicit mapping in Appendix A)
Sprint Tasks (Task 1.1, 1.2)
    ↓ (acceptance criteria)
Implementation
    ↓ (checkbox verification)
Review ✓
    ✗ No goal achievement validation
```

**Traceability Gap**: 50% of the chain exists (Feature → Task → Code). The other 50% (Goal → Feature → Achieved) is implicit or missing.

### Desired State

```
PRD Goals (G-1, G-2 with IDs)
    ↓ (explicit mapping in Appendix C)
PRD Features (FR-1, FR-2)
    ↓ (explicit mapping in Appendix A)
Sprint Tasks (Task 1.1 → G-1)
    ↓ (goal-tagged implementation)
Implementation
    ↓ (goal metric measurement)
Review + Goal Validator ✓
    ↓ (E2E validation task)
Goal Achievement Verified ✓
```

---

## Goals & Success Metrics

### Primary Goals

| ID | Goal | Measurement |
|----|------|-------------|
| **G-1** | Prevent silent goal failures | 100% of PRD goals have explicit validation tasks |
| **G-2** | Detect integration gaps automatically | Integration dependencies flagged before review |
| **G-3** | Make goal progress visible | Goal status trackable per sprint |
| **G-4** | Reduce workflow friction | Single command for guided workflow |

### Key Performance Indicators (KPIs)

| Metric | Current Baseline | Target | Timeline |
|--------|------------------|--------|----------|
| Goals with explicit validation | 0% | 100% | Per PRD |
| Integration gaps caught pre-review | 0% | >80% | Per sprint |
| Manual command errors | ~20% (wrong sequence) | <5% | After /loa |
| Goal achievement verified | 0% (manual only) | 100% automated | Per sprint |

### Constraints

- Must be backward compatible with existing PRDs (no breaking changes)
- Optional features should degrade gracefully
- No additional external dependencies
- Goal IDs should be opt-in (system works without them)

---

## User Personas & Use Cases

### Primary Persona: Developer Using Loa

**Demographics:**
- Role: Solo developer or small team lead
- Technical Proficiency: High
- Goals: Ship features that actually solve the stated problems

**Behaviors:**
- Follows Loa workflow phases
- Trusts "All good" approval means work is complete
- Moves to next sprint after review approval

**Pain Points:**
- Discovers post-deployment that feature doesn't achieve original goal
- Manual tracking of which goals are addressed by which sprints
- Forgetting command sequence during long projects

### Use Cases

#### UC-1: Goal-Traced Sprint Planning

**Actor:** Developer
**Preconditions:** PRD exists with goals defined
**Flow:**
1. Developer runs `/sprint-plan`
2. System parses PRD goals and assigns G-IDs if missing
3. Sprint plan includes Appendix C: Goal Mapping
4. Each sprint lists which goals it advances
5. Final sprint includes E2E validation task

**Postconditions:** Every goal has at least one sprint task addressing it
**Acceptance Criteria:**
- [ ] Goals without tasks flagged as warning
- [ ] E2E validation task auto-generated for final sprint

#### UC-2: Integration Dependency Detection

**Actor:** Implementing agent
**Preconditions:** Sprint includes data model changes (new columns, APIs)
**Flow:**
1. Agent implements new timing columns in database
2. System detects data flow: `store_timing()` creates data
3. System searches for consumers: `calculate_score()` should read data
4. No consumer found → Integration gap flagged
5. Agent notified to add integration task or document intentional gap

**Postconditions:** Integration gaps visible before review
**Acceptance Criteria:**
- [ ] Data producers without consumers flagged
- [ ] API endpoints without callers flagged
- [ ] False positives can be marked as intentional

#### UC-3: Goal Achievement Review

**Actor:** Reviewing agent
**Preconditions:** Implementation complete, ready for review
**Flow:**
1. Reviewer checks acceptance criteria (existing)
2. Reviewer invokes goal-validator subagent
3. Subagent checks: "Does implementation achieve G-1?"
4. Subagent measures goal KPIs if defined
5. Verdict: GOAL_ACHIEVED | GOAL_AT_RISK | GOAL_BLOCKED

**Postconditions:** Goal achievement status documented
**Acceptance Criteria:**
- [ ] Goal validator integrated into review workflow
- [ ] GOAL_AT_RISK blocks approval (configurable)
- [ ] Goal status logged to trajectory

#### UC-4: Guided Workflow Command

**Actor:** Developer new to Loa
**Preconditions:** Repository with Loa mounted
**Flow:**
1. Developer runs `/loa`
2. System detects current state (no PRD, has PRD, in sprint, etc.)
3. System suggests next command with explanation
4. Developer confirms or skips
5. Command executes, returns to step 2

**Postconditions:** Developer completes full workflow without documentation
**Acceptance Criteria:**
- [ ] `/loa` detects workflow state accurately
- [ ] Suggestions are contextually appropriate
- [ ] Can exit guided mode at any time

---

## Functional Requirements

### FR-1: Goal Identification System

**Priority:** Must Have
**Description:** Add explicit goal IDs to PRD template and parsing

**Acceptance Criteria:**
- [ ] PRD template includes Goal ID column (G-1, G-2, etc.)
- [ ] Goals without IDs auto-assigned during sprint planning
- [ ] Goal IDs referenced in sprint task descriptions
- [ ] Goal IDs used in trajectory logging

**Dependencies:** PRD template update, sprint planning skill update

### FR-2: Goal-to-Task Mapping (Appendix C)

**Priority:** Must Have
**Description:** Sprint plan includes explicit mapping from goals to tasks

**Acceptance Criteria:**
- [ ] Sprint template includes Appendix C: Goal Mapping
- [ ] Each task lists contributing goals
- [ ] Goals without tasks flagged as warning
- [ ] Multi-sprint goals show cumulative progress

**Dependencies:** FR-1, sprint template update

### FR-3: Integration Dependency Detection

**Priority:** Should Have
**Description:** Detect when new data/APIs lack consumers

**Acceptance Criteria:**
- [ ] Detect new database columns/tables
- [ ] Search for read operations on new data
- [ ] Flag producer-without-consumer patterns
- [ ] Support marking gaps as intentional

**Dependencies:** Implementation skill update, code analysis patterns

### FR-4: E2E Validation Task Generation

**Priority:** Must Have
**Description:** Auto-generate final sprint task validating all PRD goals

**Acceptance Criteria:**
- [ ] Final sprint includes "E2E Goal Validation" task
- [ ] Task lists all PRD goals with verification steps
- [ ] Task requires demonstrating goal achievement
- [ ] Skipping task requires explicit justification

**Dependencies:** FR-1, FR-2, sprint planning skill

### FR-5: Goal Validator Subagent

**Priority:** Should Have
**Description:** Subagent that validates goal achievement during review

**Acceptance Criteria:**
- [ ] Subagent defined in `.claude/subagents/`
- [ ] Invoked by `/review-sprint` before approval
- [ ] Returns GOAL_ACHIEVED | GOAL_AT_RISK | GOAL_BLOCKED
- [ ] GOAL_AT_RISK logs reason, doesn't block (default)
- [ ] Configurable to block on GOAL_AT_RISK

**Dependencies:** FR-1, subagent framework

### FR-6: Guided Workflow Command (/loa)

**Priority:** Should Have
**Description:** Interactive command that guides through workflow

**Acceptance Criteria:**
- [ ] `/loa` detects current workflow state
- [ ] Suggests appropriate next command
- [ ] Explains what each phase accomplishes
- [ ] Allows skip/exit at any point
- [ ] Shows progress through phases

**Dependencies:** State detection script, command routing

### FR-7: Goal Status in NOTES.md

**Priority:** Nice to Have
**Description:** Track goal status across sprints in structured memory

**Acceptance Criteria:**
- [ ] NOTES.md template includes "Goal Status" section
- [ ] Goals tracked with current status per sprint
- [ ] Goal blockers documented separately
- [ ] Session continuity includes goal state

**Dependencies:** FR-1, NOTES.md template update

---

## Non-Functional Requirements

### Performance

- Goal parsing adds <100ms to sprint planning
- Integration detection completes in <30s for codebases <100k lines
- Goal validator subagent completes in <60s

### Compatibility

- Existing PRDs without goal IDs work unchanged
- Goal features degrade gracefully when disabled
- No changes to existing command interfaces

### Maintainability

- Goal IDs use simple G-N format (parseable, human-readable)
- All goal tracking in State Zone (grimoires/)
- No new external dependencies

---

## User Experience

### Key User Flows

#### Flow 1: Goal-Traced Development

```
/plan-and-analyze → PRD with G-1, G-2, G-3
       ↓
/sprint-plan → Sprint 1 (G-1, G-2), Sprint 2 (G-2, G-3), Sprint 3 (E2E: all)
       ↓
/implement sprint-1 → Tasks tagged with goal contributions
       ↓
/review-sprint sprint-1 → Goal validator checks G-1, G-2 progress
       ↓
... repeat ...
       ↓
/implement sprint-3 → E2E validation task verifies all goals
       ↓
/review-sprint sprint-3 → Final goal achievement verification
```

#### Flow 2: Guided Workflow

```
/loa → "No PRD found. Run /plan-and-analyze? [Y/n]"
       ↓ Y
/plan-and-analyze → Creates prd.md
       ↓
/loa → "PRD created. Run /architect? [Y/n]"
       ↓ Y
/architect → Creates sdd.md
       ↓
/loa → "SDD created. Run /sprint-plan? [Y/n]"
       ...
```

### Interaction Patterns

- Goal warnings are non-blocking by default (configurable)
- Integration gaps shown as INFO, not ERROR
- E2E validation task clearly marked in sprint plan
- `/loa` uses Y/n prompts (Y default for flow, n to skip)

---

## Technical Considerations

### Architecture Notes

Goal traceability integrates with existing infrastructure:

1. **PRD Template**: Add Goal ID column to Goals section
2. **Sprint Template**: Add Appendix C for goal mapping
3. **Skill Updates**: discovering-requirements, planning-sprints, reviewing-code
4. **New Subagent**: goal-validator.md
5. **New Command**: /loa wizard
6. **State Detection**: Script to determine workflow phase

### Component Changes

| Component | Change Type | Impact |
|-----------|-------------|--------|
| `prd-template.md` | Add Goal ID column | Low |
| `sprint-template.md` | Add Appendix C | Low |
| `planning-sprints/SKILL.md` | Goal mapping logic | Medium |
| `reviewing-code/SKILL.md` | Goal validator invocation | Medium |
| `implementing-tasks/SKILL.md` | Integration detection | Medium |
| `.claude/subagents/goal-validator.md` | New file | New |
| `.claude/commands/loa.md` | New file | New |
| `.claude/scripts/workflow-state.sh` | New file | New |
| `NOTES.md.template` | Add Goal Status section | Low |

### Integration Detection Patterns

```
# Pattern: New data without consumer
grep "CREATE TABLE\|ALTER TABLE.*ADD" → new_columns
grep "SELECT.*${new_column}" → consumers
if consumers.empty:
    flag "Data stored but never read: ${new_column}"

# Pattern: New API without caller
grep "@Post\|@Get.*${new_endpoint}" → new_apis
grep "fetch.*${new_endpoint}\|axios.*${new_endpoint}" → callers
if callers.empty:
    flag "API created but never called: ${new_endpoint}"
```

### Technical Constraints

- Goal IDs must be unique within PRD (G-1, G-2, not duplicates)
- Integration detection requires semantic understanding (use ck if available)
- Workflow state detection reads grimoires/ directory structure

---

## Scope & Prioritization

### In Scope (MVP)

1. **Goal ID System** (FR-1) - Explicit goal identification
2. **Goal-Task Mapping** (FR-2) - Appendix C in sprint plans
3. **E2E Validation Task** (FR-4) - Auto-generated final task
4. **Goal Validator Subagent** (FR-5) - Review-time validation

### In Scope (Fast Follow)

5. **Integration Detection** (FR-3) - Producer-consumer analysis
6. **Guided Workflow** (FR-6) - /loa command
7. **Goal Status in NOTES.md** (FR-7) - Cross-sprint tracking

### Explicitly Out of Scope

- Automatic goal achievement scoring (too subjective)
- Goal dependency graph (complexity vs value)
- Multi-project goal tracking (single project focus)
- CI/CD integration for goal validation (future consideration)

### Priority Matrix

| Feature | Priority | Effort | Impact |
|---------|----------|--------|--------|
| FR-1: Goal IDs | P0 | S | High |
| FR-2: Goal Mapping | P0 | M | High |
| FR-4: E2E Task | P0 | S | High |
| FR-5: Goal Validator | P1 | M | High |
| FR-3: Integration Detection | P1 | L | Medium |
| FR-6: /loa Command | P2 | M | Medium |
| FR-7: NOTES.md Goals | P2 | S | Low |

---

## Success Criteria

### Launch Criteria

- [ ] PRD template updated with Goal ID column
- [ ] Sprint template updated with Appendix C
- [ ] planning-sprints skill generates goal mappings
- [ ] E2E validation task auto-generated for final sprint
- [ ] Goal validator subagent implemented
- [ ] All existing workflows continue to function

### Post-Launch Success

- [ ] Zero PRD goals without validation tasks (100% coverage)
- [ ] Goal validator invoked on every review
- [ ] Integration gaps caught in >50% of cases where applicable
- [ ] Positive user feedback on traceability visibility

---

## Risks & Mitigation

| Risk | Probability | Impact | Mitigation Strategy |
|------|-------------|--------|---------------------|
| Goal validation too subjective | Medium | Medium | Clear criteria, human override |
| Integration detection false positives | High | Low | Mark as intentional option |
| Breaks existing PRDs | Low | High | Backward compatibility, optional IDs |
| /loa command complexity | Medium | Low | Simple Y/n flow, easy exit |
| Over-engineering | Medium | Medium | MVP scope strict, fast follow separate |

### Assumptions

- Users want goal traceability (validated by issue #45)
- Existing PRD/sprint structure is adequate base
- Goal IDs don't need to be globally unique (per-PRD is fine)

---

## Appendix

### A. Issue #45 Feedback Summary

**Original Issue**: Score API V8 - timing columns stored but never used in score calculations

**User Feedback Points**:
1. Goal traceability needed - PRD goals should map to acceptance criteria
2. Review phase needs "Goal Achievement Check"
3. Integration task detection needed when new data added
4. E2E validation task should be auto-generated
5. `/loa` guided workflow command requested

**Quote**: "Something like a guided /loa is kind of silly but probably needed for a better DX"

### B. Current Workflow Gap Analysis

| Aspect | Current | After Implementation |
|--------|---------|---------------------|
| Goal identification | Prose in section 3 | G-1, G-2, G-3 IDs |
| Goal-to-task mapping | Implicit | Explicit Appendix C |
| Goal validation | Manual review | Goal validator subagent |
| E2E verification | Not required | Auto-generated task |
| Integration detection | Manual | Automated flagging |
| Workflow guidance | Read docs | /loa command |

### C. Example Goal Mapping (Appendix C)

```markdown
### C. PRD Goal Mapping

| Goal ID | Goal Description | Contributing Sprints | Validation Task |
|---------|------------------|---------------------|-----------------|
| G-1 | Scoring uses timing data | Sprint 1 (store), Sprint 2 (integrate) | Sprint 3 Task 3.5 |
| G-2 | API returns timing info | Sprint 1 (endpoint) | Sprint 3 Task 3.5 |
| G-3 | Dashboard shows timing | Sprint 2 (UI) | Sprint 3 Task 3.5 |

**Sprint 1 Goal Contribution**: G-1 (partial: storage), G-2 (complete: endpoint)
**Sprint 2 Goal Contribution**: G-1 (complete: integration), G-3 (complete: UI)
**Sprint 3 Goal Contribution**: E2E validation of G-1, G-2, G-3
```

### D. Glossary

| Term | Definition |
|------|------------|
| Goal ID | Unique identifier for PRD goal (G-1, G-2, etc.) |
| Goal Traceability | Ability to trace from goal definition to implementation validation |
| E2E Validation | End-to-end verification that stated goals are achieved |
| Integration Gap | New data/API created but not consumed by intended code |
| Goal Validator | Subagent that verifies goal achievement during review |

---

*Generated by PRD Architect Agent*
