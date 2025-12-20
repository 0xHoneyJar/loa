# Sprint Plan: Remove Linear Audit Trail

**Version**: 1.0.0
**Date**: 2025-12-20
**Author**: Sprint Planner Agent

---

## Sprint Overview

| Field | Value |
|-------|-------|
| Sprint | Sprint 1 |
| Goal | Remove Linear audit trail integration from all build phases |
| Duration | Single sprint (removal work) |
| Developer | 1 (AI agent) |
| Total Tasks | 14 |
| Estimated Lines Removed | ~1,570 |

---

## Sprint 1: Remove Linear Audit Trail

### Goal

Remove all Linear integration from Loa's build workflow while preserving the `/feedback` command functionality.

### Success Criteria

- [x] `grep -r "Phase 0.5" .claude/` returns 0 results ✅
- [x] `grep -r "mcp__linear__" .claude/commands/ | grep -v feedback.md` returns 0 results ✅
- [x] `grep -r "mcp__linear__" .claude/agents/` returns 0 results ✅
- [x] `/feedback` command works correctly ✅
- [x] All documentation updated consistently ✅

---

## Tasks

### Task 1.1: Update CLAUDE.md ✅

**Description**: Remove Linear audit trail documentation sections from CLAUDE.md

**Files**: `CLAUDE.md`

**Changes**:
- Remove "Linear Documentation Requirements" section (~100 lines)
- Remove "Agent Linear Documentation Responsibilities" table
- Remove "Standard Label Taxonomy" section
- Remove "Required Documentation Content" section
- Remove "Querying Linear for Context" section
- Update "MCP Server Integrations" to not mention audit trail
- Update "Repository Structure" to simplify integration-context.md description

**Acceptance Criteria**:
- [ ] No "Linear Documentation Requirements" section exists
- [ ] No references to creating Linear issues during build phases
- [ ] Linear MCP mentioned only in context of feedback
- [ ] `grep -c "Linear" CLAUDE.md` shows significantly fewer matches

**Estimated Effort**: Medium

---

### Task 1.2: Update PROCESS.md ✅

**Description**: Remove Linear integration references from process documentation

**Files**: `PROCESS.md`

**Changes**:
- Remove all Phase 0.5 references
- Remove Linear project creation from setup section
- Remove Linear tracking mentions from each phase
- Keep Linear reference only in `/feedback` section
- Update command table descriptions

**Acceptance Criteria**:
- [ ] No "Phase 0.5" references
- [ ] No "Linear issue" or "Linear project" mentions except in feedback
- [ ] `/feedback` section unchanged

**Estimated Effort**: Medium

---

### Task 1.3: Update README.md ✅

**Description**: Simplify Linear mentions in README

**Files**: `README.md`

**Changes**:
- Simplify MCP section (Linear for feedback only)
- Update repository structure (simplify integration-context.md line)
- Keep feedback command description

**Acceptance Criteria**:
- [ ] Linear MCP described as "Issue tracking for feedback"
- [ ] No mentions of Linear audit trail
- [ ] `/feedback` description preserved

**Estimated Effort**: Small

---

### Task 1.4: Update /setup Command ✅

**Description**: Remove Linear project creation from setup

**Files**: `.claude/commands/setup.md`

**Changes**:
- Remove Section 3.2 (Create Linear Project)
- Remove Linear project from summary output
- Remove "Set up Linear project tracking" from setup messages
- Keep Linear MCP in detection list (needed for feedback)

**Acceptance Criteria**:
- [ ] No `mcp__linear__create_project` calls
- [ ] No "Linear Project: Created" in summary
- [ ] Linear MCP still detected (for feedback)

**Estimated Effort**: Small

---

### Task 1.5: Update /implement Command ✅

**Description**: Remove Phase 0.5 (Linear Issue Creation) from implement command

**Files**: `.claude/commands/implement.md`

**Changes**:
- Remove entire Phase 0.5 section
- Remove "Linear Issue Tracking" from reviewer.md template
- Remove blocking check for Linear issues
- Remove Linear references in setup check message
- Update phase numbering if needed

**Acceptance Criteria**:
- [ ] No "Phase 0.5" section
- [ ] No `mcp__linear__` calls
- [ ] No "Linear Issue Tracking" in report template
- [ ] Command functions without Linear

**Estimated Effort**: Medium

---

### Task 1.6: Update /review-sprint Command ✅

**Description**: Remove Phase 0.5 (Linear Issue Tracking) from review command

**Files**: `.claude/commands/review-sprint.md`

**Changes**:
- Remove Phase 0.5 section
- Remove Linear blocking check
- Remove "Linear Issue References" from feedback template
- Remove Linear from setup check message

**Acceptance Criteria**:
- [ ] No "Phase 0.5" section
- [ ] No `mcp__linear__` calls
- [ ] No "Linear Issue References" in template

**Estimated Effort**: Small

---

### Task 1.7: Update /audit-sprint Command ✅

**Description**: Remove Phase 0.5 (Linear Issue Tracking) from audit command

**Files**: `.claude/commands/audit-sprint.md`

**Changes**:
- Remove Phase 0.5 section
- Remove security finding issue creation
- Remove Linear blocking check
- Remove "Linear Issue References" from feedback template

**Acceptance Criteria**:
- [ ] No "Phase 0.5" section
- [ ] No `mcp__linear__create_issue` calls
- [ ] No security finding issue creation

**Estimated Effort**: Medium

---

### Task 1.8: Update /sprint-plan Command ✅

**Description**: Remove Phase 0.5 (Linear Sprint Project Creation) from sprint-plan command

**Files**: `.claude/commands/sprint-plan.md`

**Changes**:
- Remove Phase 0.5 section
- Remove Linear sprint project creation
- Remove "Linear Tracking" from sprint.md template

**Acceptance Criteria**:
- [ ] No "Phase 0.5" section
- [ ] No `mcp__linear__create_project` calls
- [ ] No "Linear Tracking" in template

**Estimated Effort**: Small

---

### Task 1.9: Update /deploy-production Command ✅

**Description**: Remove Linear references from deployment command

**Files**: `.claude/commands/deploy-production.md`

**Changes**:
- Remove Linear issue creation references
- Remove "Set up Linear project tracking" from setup check message
- Keep feedback suggestion (uses Linear correctly)

**Acceptance Criteria**:
- [ ] No infrastructure issue creation references
- [ ] Feedback suggestion preserved

**Estimated Effort**: Small

---

### Task 1.10: Update Agent Definitions (8 files) ✅

**Description**: Remove Linear documentation requirements from all agents

**Files**:
- `.claude/agents/prd-architect.md`
- `.claude/agents/architecture-designer.md`
- `.claude/agents/sprint-planner.md`
- `.claude/agents/sprint-task-implementer.md`
- `.claude/agents/senior-tech-lead-reviewer.md`
- `.claude/agents/devops-crypto-architect.md`
- `.claude/agents/paranoid-auditor.md`
- `.claude/agents/devrel-translator.md`

**Changes per agent**:

| Agent | Lines to Remove | Key Sections |
|-------|-----------------|--------------|
| prd-architect | ~10 | Linear knowledge source references |
| architecture-designer | ~5 | Linear SDK reference |
| sprint-planner | ~80 | Phase 0.5 (Linear Sprint Project) |
| sprint-task-implementer | ~200 | Phase 0.5 (Linear Issue Creation) |
| senior-tech-lead-reviewer | ~180 | Phase 0.5 (Linear Review Docs) |
| devops-crypto-architect | ~300 | Phase 0.5 (Linear Issue Creation), webhooks |
| paranoid-auditor | ~250 | Linear Issue Creation section |
| devrel-translator | ~5 | Linear mentions in examples |

**Acceptance Criteria**:
- [ ] No "Phase 0.5" in any agent
- [ ] No `mcp__linear__` calls in any agent
- [ ] No Linear issue creation instructions
- [ ] `grep -r "mcp__linear__" .claude/agents/` returns 0 results

**Estimated Effort**: Large (8 files, ~1,000 lines)

---

### Task 1.11: Simplify integration-context.md ✅

**Description**: Rewrite integration-context.md to feedback-only configuration

**Files**: `loa-grimoire/a2a/integration-context.md`

**Changes**:
- Remove label taxonomy
- Remove issue templates
- Remove commit message template
- Keep only feedback project reference (~20 lines)

**New Content**:
```markdown
# Integration Context

This file provides configuration for Loa integrations.

## Feedback Configuration

Feedback submissions are posted to the **Loa Feedback** project in Linear.

The `/feedback` command:
1. Searches for existing issue by project name
2. Creates new issue or adds comment to existing
3. Includes analytics data from `loa-grimoire/analytics/usage.json`

No additional configuration required - the feedback command discovers
the project dynamically via `mcp__linear__list_projects`.
```

**Acceptance Criteria**:
- [ ] File is ~20 lines
- [ ] No label taxonomy
- [ ] No issue templates
- [ ] Feedback configuration preserved

**Estimated Effort**: Small

---

### Task 1.12: Update analytics/usage.json Schema ✅

**Description**: Remove Linear project tracking fields from analytics

**Files**: `loa-grimoire/analytics/usage.json`

**Changes**:
- Remove entire `linear` section:
  - `linear.team_id`
  - `linear.team_name`
  - `linear.project_id`
  - `linear.project_name`
  - `linear.project_url`
- Keep `feedback_submissions` array

**Acceptance Criteria**:
- [ ] No `linear` key in usage.json
- [ ] `feedback_submissions` array preserved
- [ ] JSON is valid

**Estimated Effort**: Small

---

### Task 1.13: Validate /feedback Command ✅

**Description**: Test that /feedback command still works after changes

**Validation Steps**:
1. Verify feedback.md was NOT modified
2. Check Linear MCP is still configured
3. Run `/feedback` if possible, or verify code paths

**Acceptance Criteria**:
- [ ] `.claude/commands/feedback.md` unchanged
- [ ] Linear MCP in settings.local.json
- [ ] No broken references to removed code

**Estimated Effort**: Small

---

### Task 1.14: Final Validation ✅

**Description**: Run validation tests to ensure complete removal

**Validation Commands**:
```bash
# No Phase 0.5 references
grep -r "Phase 0.5" .claude/

# No Linear calls in commands (except feedback)
grep -r "mcp__linear__" .claude/commands/ | grep -v feedback.md

# No Linear calls in agents
grep -r "mcp__linear__" .claude/agents/

# Count remaining Linear references (should be minimal)
grep -ri "linear" CLAUDE.md PROCESS.md README.md | wc -l
```

**Acceptance Criteria**:
- [ ] All grep commands return expected results
- [ ] Linear references only in feedback context
- [ ] No stray "Phase 0.5" anywhere

**Estimated Effort**: Small

---

## Task Dependency Graph

```
Task 1.1 (CLAUDE.md) ─┐
Task 1.2 (PROCESS.md) ├─ Documentation (can run in parallel)
Task 1.3 (README.md) ─┘
         │
         ▼
Task 1.4 (setup) ────┐
Task 1.5 (implement) │
Task 1.6 (review) ───├─ Commands (can run in parallel)
Task 1.7 (audit) ────│
Task 1.8 (sprint) ───│
Task 1.9 (deploy) ───┘
         │
         ▼
Task 1.10 (agents) ─── Agents (largest task)
         │
         ▼
Task 1.11 (integration-context) ─┐
Task 1.12 (usage.json) ──────────├─ Data files (can run in parallel)
         │
         ▼
Task 1.13 (validate feedback) ─┐
Task 1.14 (final validation) ──┴─ Validation
```

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Breaking /feedback | Low | High | Don't touch feedback.md, validate after |
| Incomplete removal | Medium | Medium | Use grep validation, systematic approach |
| Doc inconsistency | Low | Low | Update all 3 docs in sequence |

---

## Notes

- **DO NOT MODIFY**: `.claude/commands/feedback.md`
- **PRESERVE**: Linear MCP in `.claude/settings.local.json`
- **Order**: Docs → Commands → Agents → Data → Validation
- Use git to track changes for easy rollback if needed
