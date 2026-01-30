# Sprint Plan: {Project Name}

**Version:** 1.0
**Date:** {DATE}
**Author:** Sprint Planner Agent
**PRD Reference:** grimoires/loa/prd.md
**SDD Reference:** grimoires/loa/sdd.md

---

## Executive Summary

{Brief overview of MVP scope, total sprint count, and expected timeline}

**Total Sprints:** {N}
**Sprint Duration:** 2.5 days each
**Estimated Completion:** {DATE}

---

## Sprint Overview

| Sprint | Theme | Key Deliverables | Dependencies |
|--------|-------|------------------|--------------|
| 1 | {Theme} | {Deliverables} | None |
| 2 | {Theme} | {Deliverables} | Sprint 1 |
| ... | ... | ... | ... |

---

## Sprint 1: {Descriptive Sprint Theme}

**Duration:** 2.5 days
**Dates:** {Start Date} - {End Date}

### Sprint Goal
{Clear, concise statement of what this sprint achieves toward MVP}

### Deliverables
- [ ] {Specific deliverable 1 with measurable outcome}
- [ ] {Specific deliverable 2 with measurable outcome}
- [ ] {Additional deliverables...}

### Acceptance Criteria
- [ ] {Testable criterion 1}
- [ ] {Testable criterion 2}
- [ ] {Additional criteria...}

### Technical Tasks

<!-- Annotate each task with contributing goal(s): → **[G-1]** or → **[G-1, G-2]** -->

- [ ] Task 1.1: {Specific technical task 1} → **[G-1]**
- [ ] Task 1.2: {Specific technical task 2} → **[G-1, G-2]**
- [ ] {Additional tasks...} → **[G-N]**

### Dependencies
- {Any dependencies on previous sprints or external factors}
- None (first sprint)

### Risks & Mitigation
| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| {Risk 1} | Med | High | {Strategy} |

### Success Metrics
- {Quantifiable metric 1}
- {Quantifiable metric 2}

---

## Sprint N (Final): {Descriptive Sprint Theme}

<!-- Final sprint should include E2E Goal Validation task -->

**Duration:** 2.5 days
**Dates:** {Start Date} - {End Date}

### Sprint Goal
Complete implementation and validate all PRD goals are achieved end-to-end.

### Task N.E2E: End-to-End Goal Validation

**Priority:** P0 (Must Complete)
**Goal Contribution:** All goals (G-1, G-2, G-3, ...)

**Description:**
Validate that all PRD goals are achieved through the complete implementation.

**Validation Steps:**

| Goal ID | Goal | Validation Action | Expected Result |
|---------|------|-------------------|-----------------|
| G-1 | {From PRD} | {Specific test/check} | {Pass criteria} |
| G-2 | {From PRD} | {Specific test/check} | {Pass criteria} |
| G-3 | {From PRD} | {Specific test/check} | {Pass criteria} |

**Acceptance Criteria:**
- [ ] Each goal validated with documented evidence
- [ ] Integration points verified (data flows end-to-end)
- [ ] No goal marked as "not achieved" without explicit justification

---

## Sprint 2: {Descriptive Sprint Theme}

**Duration:** 2.5 days
**Dates:** {Start Date} - {End Date}

### Sprint Goal
{Clear, concise statement of what this sprint achieves toward MVP}

### Deliverables
- [ ] {Specific deliverable 1}
- [ ] {Specific deliverable 2}

### Acceptance Criteria
- [ ] {Testable criterion 1}
- [ ] {Testable criterion 2}

### Technical Tasks
- [ ] {Specific technical task 1}
- [ ] {Specific technical task 2}

### Dependencies
- Sprint 1: {Specific dependency}

### Risks & Mitigation
| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| {Risk 1} | Low | Med | {Strategy} |

### Success Metrics
- {Quantifiable metric 1}
- {Quantifiable metric 2}

---

## Risk Register

| ID | Risk | Sprint | Probability | Impact | Mitigation | Owner |
|----|------|--------|-------------|--------|------------|-------|
| R1 | {Risk} | 1-2 | High | High | {Strategy} | {Team} |
| R2 | {Risk} | 3 | Med | Med | {Strategy} | {Team} |

---

## Success Metrics Summary

| Metric | Target | Measurement Method | Sprint |
|--------|--------|-------------------|--------|
| {Metric 1} | {Target} | {How to measure} | {N} |
| {Metric 2} | {Target} | {How to measure} | {N} |

---

## Dependencies Map

```
Sprint 1 ──────────────▶ Sprint 2 ──────────────▶ Sprint 3
   │                        │                        │
   └─ Foundation            └─ Core Features         └─ Polish
```

---

## Appendix

### A. PRD Feature Mapping

| PRD Feature (FR-X) | Sprint | Status |
|--------------------|--------|--------|
| FR-1.1 | Sprint 1 | Planned |
| FR-1.2 | Sprint 2 | Planned |

### B. SDD Component Mapping

| SDD Component | Sprint | Status |
|---------------|--------|--------|
| Database Schema | Sprint 1 | Planned |
| API Layer | Sprint 2 | Planned |

### C. PRD Goal Mapping

| Goal ID | Goal Description | Contributing Tasks | Validation Task |
|---------|------------------|-------------------|-----------------|
| G-1 | {From PRD Goals section} | Sprint 1: Task 1.1, Task 1.2 | Sprint N: Task N.E2E |
| G-2 | {From PRD Goals section} | Sprint 2: Task 2.1 | Sprint N: Task N.E2E |
| G-3 | {From PRD Goals section} | Sprint 1: Task 1.3, Sprint 2: Task 2.2 | Sprint N: Task N.E2E |

**Goal Coverage Check:**
- [ ] All PRD goals have at least one contributing task
- [ ] All goals have a validation task in final sprint
- [ ] No orphan tasks (tasks not contributing to any goal)

**Per-Sprint Goal Contribution:**

Sprint 1: G-1 (partial: foundation), G-3 (partial: setup)
Sprint 2: G-1 (complete: integration), G-2 (complete), G-3 (complete: validation)
Sprint N: E2E validation of all goals

---

*Generated by Sprint Planner Agent*
