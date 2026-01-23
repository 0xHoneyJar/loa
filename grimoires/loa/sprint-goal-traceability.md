# Sprint Plan: Goal Traceability & End-to-End Validation

**Version:** 1.0
**Date:** 2026-01-23
**Author:** Sprint Planner Agent
**PRD Reference:** `grimoires/loa/prd-goal-traceability.md`
**SDD Reference:** `grimoires/loa/sdd-goal-traceability.md`

---

## Executive Summary

Implement goal traceability features to prevent silent goal failures in Loa workflows. The implementation spans 3 sprints covering MVP core (templates + mapping), MVP complete (validation + config), and fast follow (guided workflow).

**Total Sprints:** 3
**Sprint Duration:** 2.5 days each
**Issue Reference:** https://github.com/0xHoneyJar/loa/issues/45

---

## Sprint Overview

| Sprint | Theme | Key Deliverables | Dependencies |
|--------|-------|------------------|--------------|
| 1 | Goal Foundation | PRD template, sprint template, goal mapping generation | None |
| 2 | Goal Validation | Goal validator subagent, review integration, config | Sprint 1 |
| 3 | Guided Workflow | workflow-state.sh, /loa command, documentation | Sprint 1 |

---

## Sprint 1: Goal Foundation (MVP Core)

**Duration:** 2.5 days

### Sprint Goal

Establish the goal traceability foundation by adding Goal ID support to PRD templates and goal-task mapping to sprint templates. → **[G-1, G-3]**

### Deliverables

- [x] PRD template with Goal ID column (G-1, G-2, G-3 format)
- [x] Sprint template with Appendix C (Goal Mapping)
- [x] Task annotation format for goal contributions
- [x] E2E validation task auto-generation in final sprint
- [x] Planning-sprints skill updates for goal mapping

### Acceptance Criteria

- [x] PRD template includes `| ID | Goal | Measurement | Validation Method |` table
- [x] Sprint template includes Appendix C: PRD Goal Mapping section
- [x] Tasks can be annotated with `→ **[G-1]**` format
- [x] Final sprint automatically includes E2E Goal Validation task
- [x] Goals without tasks generate warning (non-blocking)
- [x] Existing PRDs without goal IDs work unchanged (backward compatible)

### Technical Tasks

- [x] Task 1.1: Update PRD template with Goal ID column → **[G-1]**
  - File: `.claude/skills/discovering-requirements/resources/templates/prd-template.md`
  - Add ID column to Primary Goals table
  - Add Validation Method column

- [x] Task 1.2: Update sprint template with Appendix C → **[G-1, G-3]**
  - File: `.claude/skills/planning-sprints/resources/templates/sprint-template.md`
  - Add Appendix C: PRD Goal Mapping section
  - Add task annotation format documentation
  - Add per-sprint goal contribution summary

- [x] Task 1.3: Update planning-sprints skill for goal parsing → **[G-1]**
  - File: `.claude/skills/planning-sprints/SKILL.md`
  - Add goal ID extraction logic
  - Add auto-assignment for missing IDs
  - Add goal-to-task mapping generation

- [x] Task 1.4: Implement E2E validation task generation → **[G-1]**
  - File: `.claude/skills/planning-sprints/SKILL.md`
  - Auto-generate E2E task in final sprint
  - Include all goals in validation steps
  - Add warning for missing E2E task

- [x] Task 1.5: Add goal mapping warnings → **[G-1]**
  - Generate warnings for unmapped goals
  - Generate warnings for orphan tasks (optional, configurable)
  - Warnings are informational, not blocking

### Dependencies

- None (first sprint)

### Risks & Mitigation

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Template changes break existing PRDs | Low | High | Backward compatibility - ID column optional |
| Skill changes cause regressions | Medium | Medium | Test with existing sprint plans |

### Success Metrics

- PRD template includes Goal ID column
- Sprint template includes Appendix C
- E2E task generated automatically
- All existing workflows still function

---

## Sprint 2: Goal Validation (MVP Complete)

**Duration:** 2.5 days

### Sprint Goal

Implement goal validation during review phase with configurable blocking behavior. → **[G-1, G-2]**

### Deliverables

- [x] Goal validator subagent (`.claude/subagents/goal-validator.md`)
- [x] Review workflow integration (invoke goal-validator before approval)
- [x] Configuration options in `.loa.config.yaml`
- [x] NOTES.md Goal Status section
- [x] /validate goals command variant

### Acceptance Criteria

- [x] Goal validator subagent returns GOAL_ACHIEVED | GOAL_AT_RISK | GOAL_BLOCKED
- [x] Validator invoked by `/review-sprint` on final sprint
- [x] GOAL_BLOCKED blocks approval by default
- [x] GOAL_AT_RISK configurable to block or warn
- [x] Configuration options in `.loa.config.yaml` documented
- [x] NOTES.md template includes Goal Status section
- [x] `/validate goals` invokes validator manually

### Technical Tasks

- [x] Task 2.1: Create goal-validator subagent → **[G-1, G-2]**
  - File: `.claude/subagents/goal-validator.md`
  - Follow architecture-validator pattern
  - Implement verdict determination logic
  - Output report to `a2a/subagent-reports/`

- [x] Task 2.2: Integrate validator into reviewing-code skill → **[G-1]**
  - File: `.claude/skills/reviewing-code/SKILL.md`
  - Invoke goal-validator on final sprint
  - Check verdict before approval
  - Block on BLOCKED, warn on AT_RISK (configurable)

- [x] Task 2.3: Add configuration schema → **[G-1]**
  - File: `.loa.config.yaml` (documentation)
  - Add `goal_traceability` section
  - Add `goal_validation` section
  - Document all options with defaults

- [x] Task 2.4: Update NOTES.md template → **[G-3]**
  - File: `.claude/templates/NOTES.md.template`
  - Add Goal Status section after Technical Debt
  - Include status legend
  - Add update triggers

- [x] Task 2.5: Add /validate goals command variant → **[G-1]**
  - File: `.claude/commands/validate.md`
  - Add `goals` argument handling
  - Invoke goal-validator subagent directly

### Dependencies

- Sprint 1: Goal ID system and Appendix C must exist

### Risks & Mitigation

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Validator too strict | Medium | Medium | Default to warn-only for AT_RISK |
| Review workflow slowdown | Low | Low | Validator runs in parallel with other checks |

### Success Metrics

- Goal validator returns correct verdicts
- Review workflow invokes validator
- Configuration options work correctly
- NOTES.md Goal Status section available

---

## Sprint 3: Guided Workflow (Fast Follow)

**Duration:** 2.5 days

### Sprint Goal

Implement the `/loa` guided workflow command and workflow state detection. → **[G-4]**

### Deliverables

- [x] `workflow-state.sh` script for state detection
- [x] `/loa` command for guided workflow
- [x] Documentation updates (CLAUDE.md, README.md)
- [x] E2E Goal Validation task for this sprint plan

### Acceptance Criteria

- [x] `workflow-state.sh` detects all workflow states correctly
- [x] `/loa` shows workflow progress indicator
- [x] `/loa` suggests appropriate next command
- [x] `/loa` prompts user with [Y/n/exit] options
- [x] Documentation updated with new features
- [x] All Goal Traceability features documented

### Technical Tasks

- [x] Task 3.1: Create workflow-state.sh script → **[G-4]**
  - File: `.claude/scripts/workflow-state.sh`
  - Detect PRD, SDD, sprint plan existence
  - Detect current sprint status
  - Calculate progress percentage
  - Support --json output

- [x] Task 3.2: Create /loa command → **[G-4]**
  - File: `.claude/commands/loa.md`
  - Invoke workflow-state.sh
  - Display progress indicator
  - Suggest next command
  - Handle user input [Y/n/exit]

- [x] Task 3.3: Update workflow-chain.yaml → **[G-4]**
  - File: `.claude/workflow-chain.yaml`
  - Add /loa integration points
  - Ensure suggest-next-step.sh compatibility

- [x] Task 3.4: Update CLAUDE.md documentation → **[G-1, G-3, G-4]**
  - Add Goal Traceability section
  - Document goal_traceability config
  - Document goal_validation config
  - Document guided_workflow config
  - Add /loa command reference

- [x] Task 3.5: Update README.md documentation → **[G-1, G-3, G-4]**
  - Add Goal Traceability to Key Features
  - Document /loa command in workflow section
  - Update version badge

- [x] Task 3.E2E: End-to-End Goal Validation → **[G-1, G-2, G-3, G-4]**
  - Validate all PRD goals are achieved
  - Document evidence for each goal

### Dependencies

- Sprint 1: Templates and goal mapping
- Sprint 2: Goal validator (for E2E validation)

### Risks & Mitigation

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| State detection complexity | Medium | Medium | Leverage existing suggest-next-step.sh |
| /loa UX confusion | Medium | Low | Simple Y/n/exit prompts, clear messaging |

### Success Metrics

- workflow-state.sh detects all states
- /loa guides users through workflow
- Documentation complete and accurate
- All PRD goals validated

---

## Risk Register

| ID | Risk | Sprint | Probability | Impact | Mitigation | Owner |
|----|------|--------|-------------|--------|------------|-------|
| R1 | Template changes break existing PRDs | 1 | Low | High | Backward compatibility | implementing-tasks |
| R2 | Goal mapping too verbose | 1-2 | Medium | Low | Keep Appendix C concise | planning-sprints |
| R3 | Validator false positives | 2 | Medium | Medium | Default warn-only | goal-validator |
| R4 | State detection edge cases | 3 | Medium | Medium | Comprehensive testing | workflow-state.sh |

---

## Success Metrics Summary

| Metric | Target | Measurement Method | Sprint |
|--------|--------|-------------------|--------|
| Goal IDs in PRD template | 100% | Template updated | 1 |
| Appendix C in sprint template | 100% | Template updated | 1 |
| E2E task auto-generated | 100% of final sprints | Manual verification | 1 |
| Goal validator working | ACHIEVED/AT_RISK/BLOCKED | Manual test | 2 |
| /loa state detection | All states | Automated test | 3 |
| Documentation complete | 100% | CLAUDE.md review | 3 |

---

## Dependencies Map

```
Sprint 1 ──────────────▶ Sprint 2 ──────────────▶ Sprint 3
   │                        │                        │
   └─ Templates             └─ Validation            └─ Workflow
      Goal IDs                 Subagent                 /loa command
      Appendix C               Config                   Documentation
      E2E Task                 NOTES.md
```

---

## Appendix

### A. PRD Feature Mapping

| PRD Feature (FR-X) | Sprint | Status |
|--------------------|--------|--------|
| FR-1: Goal IDs | Sprint 1 | Complete |
| FR-2: Goal Mapping | Sprint 1 | Complete |
| FR-4: E2E Task | Sprint 1 | Complete |
| FR-5: Goal Validator | Sprint 2 | Complete |
| FR-7: NOTES.md Goals | Sprint 2 | Complete |
| FR-6: /loa Command | Sprint 3 | Complete |

### B. SDD Component Mapping

| SDD Component | Sprint | Status |
|---------------|--------|--------|
| PRD template | Sprint 1 | Complete |
| Sprint template | Sprint 1 | Complete |
| Goal validator subagent | Sprint 2 | Complete |
| Config schema | Sprint 2 | Complete |
| NOTES.md template | Sprint 2 | Complete |
| workflow-state.sh | Sprint 3 | Complete |
| /loa command | Sprint 3 | Complete |

### C. PRD Goal Mapping

| Goal ID | Goal Description | Contributing Tasks | Validation Task |
|---------|------------------|-------------------|-----------------|
| G-1 | Prevent silent goal failures | Sprint 1: 1.1-1.5, Sprint 2: 2.1-2.3, 2.5, Sprint 3: 3.4-3.5 | Sprint 3: Task 3.E2E |
| G-2 | Detect integration gaps automatically | Sprint 2: 2.1, 2.2 | Sprint 3: Task 3.E2E |
| G-3 | Make goal progress visible | Sprint 1: 1.2, Sprint 2: 2.4, Sprint 3: 3.4-3.5 | Sprint 3: Task 3.E2E |
| G-4 | Reduce workflow friction | Sprint 3: 3.1-3.5 | Sprint 3: Task 3.E2E |

**Goal Coverage Check:**
- [x] All PRD goals have at least one contributing task
- [x] All goals have a validation task in final sprint (Task 3.E2E)
- [x] No orphan tasks (all tasks contribute to goals)

**Per-Sprint Goal Contribution:**

Sprint 1: G-1 (partial: templates), G-3 (partial: Appendix C)
Sprint 2: G-1 (partial: validation), G-2 (complete: integration detection via validator), G-3 (partial: NOTES.md)
Sprint 3: G-1 (complete: all features), G-3 (complete: documentation), G-4 (complete: /loa command), E2E validation of all goals

---

*Generated by Sprint Planner Agent*
