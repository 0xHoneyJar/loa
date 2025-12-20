# Product Requirements Document: Remove Linear Audit Trail

**Version**: 1.0.0
**Date**: 2025-12-20
**Author**: PRD Architect Agent
**Status**: Draft

---

## Executive Summary

This PRD documents the removal of Linear integration from the Loa framework's build workflow. Currently, Loa creates Linear issues for every sprint task, review comment, and security audit finding—creating an audit trail that duplicates information already in the codebase and `loa-grimoire/` documents.

**The problem**: This Linear audit trail creates drift between the code (source of truth) and Linear documents, while generating noise for PMs and non-developers who use Linear for their own purposes.

**The solution**: Remove all Linear integration from build phases, keeping Linear only for:
1. Analytics tracking (stored locally, shared via `/feedback`)
2. The `/feedback` command (posts to "Loa Feedback" project)

---

## Problem Statement

### Current State

The Loa framework currently integrates with Linear throughout the development workflow:

1. **Setup Phase** (`/setup`): Creates a Linear project for the repository
2. **Sprint Planning** (`/sprint-plan`): Creates Linear sprint projects and planning issues
3. **Implementation** (`/implement`): Creates parent issues per task, sub-issues per component
4. **Review** (`/review-sprint`): Adds review findings as comments to implementation issues
5. **Security Audit** (`/audit-sprint`): Creates security finding issues with severity labels
6. **Deployment** (`/deploy-production`): Creates infrastructure tracking issues

### Problems Identified

1. **Source of Truth Conflict**: The codebase and `loa-grimoire/` documents ARE the source of truth. Linear issues duplicate this information and quickly become stale.

2. **PM/Non-Dev Noise**: Linear is used by product managers, designers, and other stakeholders. Agent-generated implementation details create noise and don't increase their understanding of what's being built.

3. **Maintenance Overhead**: Keeping Linear issues in sync with actual implementation requires constant updates that add friction without value.

4. **Unnecessary Complexity**: The Linear integration adds complexity to every agent (Phase 0.5 steps, issue creation, comment tracking) without corresponding benefit.

---

## Goals & Success Metrics

### Goals

1. **Simplify the workflow**: Remove Linear integration from all build phases
2. **Reduce noise**: Eliminate agent-generated issues that clutter Linear for non-developers
3. **Maintain feedback capability**: Keep Linear integration only for `/feedback` command
4. **Clean documentation**: Update all docs to reflect the simplified workflow

### Success Metrics

1. All agents function without Linear issue creation
2. `/feedback` command continues to work with "Loa Feedback" project
3. No references to Linear audit trail in documentation
4. Setup flow no longer creates per-project Linear projects

---

## Scope

### In Scope

| Component | Change |
|-----------|--------|
| **CLAUDE.md** | Remove "Linear Documentation Requirements" section, "Agent Linear Documentation Responsibilities" table, "Standard Label Taxonomy", "Required Documentation Content", "Querying Linear for Context" |
| **PROCESS.md** | Remove all references to Linear issue creation during build phases |
| **README.md** | Remove Linear audit trail mentions, simplify MCP section |
| **`/setup` command** | Remove project creation, only verify "Loa Feedback" project exists for `/feedback` |
| **`/implement` command** | Remove Phase 0.5 (Linear Issue Creation) |
| **`/review-sprint` command** | Remove Phase 0.5 (Linear Issue Tracking) |
| **`/audit-sprint` command** | Remove Phase 0.5 (Linear Issue Tracking) |
| **`/sprint-plan` command** | Remove Phase 0.5 (Linear Sprint Project Creation) |
| **`/deploy-production` command** | Remove Linear issue creation for infrastructure |
| **Agent definitions** | Remove Linear documentation requirements from all 8 agents |
| **`integration-context.md`** | Simplify to feedback-only configuration |
| **`analytics/usage.json`** | Remove `linear` section with project tracking fields |

### Out of Scope

| Component | Reason |
|-----------|--------|
| **`/feedback` command** | Keep as-is - this is the one legitimate use of Linear |
| **Linear MCP configuration** | Keep in settings - needed for `/feedback` |
| **Analytics system** | Keep as-is - Linear references are for feedback only |

---

## Functional Requirements

### FR-1: Remove Linear from Setup

**Current behavior**: `/setup` creates a Linear project for the repository
**New behavior**: `/setup` only verifies "Loa Feedback" project exists (for `/feedback` command)

**Changes**:
- Remove "Create Linear Project" step (Section 3.2)
- Remove Linear project creation from summary
- Update marker file to not include `linear_project_id`

### FR-2: Remove Linear from Implementation

**Current behavior**: `/implement` creates Linear issues before writing code
**New behavior**: `/implement` starts coding directly without Linear phase

**Changes**:
- Remove Phase 0.5 (Linear Issue Creation)
- Remove "Linear Issue Tracking" section from reviewer.md template
- Remove blocking check for Linear issues

### FR-3: Remove Linear from Review

**Current behavior**: `/review-sprint` adds comments to Linear issues
**New behavior**: `/review-sprint` writes feedback only to `engineer-feedback.md`

**Changes**:
- Remove Phase 0.5 (Linear Issue Tracking)
- Remove blocking check for implementation Linear issues
- Remove "Linear Issue References" from feedback template

### FR-4: Remove Linear from Security Audit

**Current behavior**: `/audit-sprint` creates Linear issues for security findings
**New behavior**: `/audit-sprint` writes findings only to `auditor-sprint-feedback.md`

**Changes**:
- Remove Phase 0.5 (Linear Issue Tracking)
- Remove blocking check for implementation Linear issues
- Remove security finding issue creation
- Remove "Linear Issue References" from feedback template

### FR-5: Remove Linear from Sprint Planning

**Current behavior**: `/sprint-plan` creates Linear sprint project
**New behavior**: `/sprint-plan` outputs only to `sprint.md`

**Changes**:
- Remove Phase 0.5 (Linear Sprint Project Creation)
- Remove "Linear Tracking" section from sprint.md template

### FR-6: Remove Linear from Deployment

**Current behavior**: `/deploy-production` creates infrastructure issues
**New behavior**: `/deploy-production` outputs only to `loa-grimoire/deployment/`

**Changes**:
- Remove Phase 0.5 (Linear Issue Creation)
- Remove infrastructure issue creation
- Remove "Linear Section" from deployment report

### FR-7: Simplify Integration Context

**Current behavior**: `integration-context.md` contains full Linear config
**New behavior**: `integration-context.md` contains only feedback project info

**Changes**:
- Remove label taxonomy (not needed without issue creation)
- Remove issue templates
- Keep only feedback project reference

### FR-8: Update Analytics Schema

**Current behavior**: `usage.json` includes `linear` section with project tracking
**New behavior**: `usage.json` excludes per-project Linear tracking

**Changes**:
- Remove `linear.team_id`, `linear.team_name`, `linear.project_id`, `linear.project_name`, `linear.project_url`
- Keep feedback submission tracking (`feedback_submissions` array)

---

## Non-Functional Requirements

### NFR-1: Backward Compatibility

Existing projects using Loa should continue to function after this update. The removal of Linear integration should not break any workflows.

### NFR-2: Documentation Completeness

All documentation (CLAUDE.md, PROCESS.md, README.md) must be updated consistently to remove Linear audit trail references.

### NFR-3: Agent Consistency

All 8 agents must be updated to remove Linear-specific phases and requirements.

---

## Technical Approach

### Files to Modify

**Documentation (3 files)**:
1. `CLAUDE.md` - Remove ~130 lines of Linear documentation
2. `PROCESS.md` - Remove Linear references throughout (~30 occurrences)
3. `README.md` - Simplify Linear mentions (~10 occurrences)

**Commands (7 files)**:
1. `.claude/commands/setup.md` - Remove project creation (~40 lines)
2. `.claude/commands/implement.md` - Remove Phase 0.5 (~100 lines)
3. `.claude/commands/review-sprint.md` - Remove Phase 0.5 (~50 lines)
4. `.claude/commands/audit-sprint.md` - Remove Phase 0.5 (~70 lines)
5. `.claude/commands/sprint-plan.md` - Remove Phase 0.5 (~40 lines)
6. `.claude/commands/deploy-production.md` - Remove Linear references (~20 lines)
7. `.claude/commands/feedback.md` - Keep as-is (this uses Linear correctly)

**Agents (8 files)**:
1. `.claude/agents/prd-architect.md` - Remove Linear references (~10 lines)
2. `.claude/agents/architecture-designer.md` - Remove Linear SDK reference (~5 lines)
3. `.claude/agents/sprint-planner.md` - Remove Phase 0.5 (~80 lines)
4. `.claude/agents/sprint-task-implementer.md` - Remove Phase 0.5 (~200 lines)
5. `.claude/agents/senior-tech-lead-reviewer.md` - Remove Phase 0.5 (~180 lines)
6. `.claude/agents/devops-crypto-architect.md` - Remove Phase 0.5 (~300 lines)
7. `.claude/agents/paranoid-auditor.md` - Remove Phase 0.5 (~250 lines)
8. `.claude/agents/devrel-translator.md` - Remove Linear mentions (~5 lines)

**Data files (2 files)**:
1. `loa-grimoire/a2a/integration-context.md` - Simplify to feedback-only
2. `loa-grimoire/analytics/usage.json` - Remove `linear` section

---

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Loss of audit trail | Medium | The codebase and loa-grimoire documents ARE the audit trail |
| Feedback command breaks | High | Test `/feedback` thoroughly after changes |
| Documentation inconsistency | Medium | Review all files for stray Linear references |

---

## Implementation Plan

### Sprint 1: Remove Linear Audit Trail

**Tasks**:
1. Update CLAUDE.md - remove Linear audit trail documentation
2. Update PROCESS.md - remove Linear integration references
3. Update README.md - remove Linear audit trail mentions
4. Update /setup command - only verify Loa Feedback project
5. Update /implement command - remove Phase 0.5
6. Update /review-sprint command - remove Phase 0.5
7. Update /audit-sprint command - remove Phase 0.5
8. Update /sprint-plan command - remove Phase 0.5
9. Update /deploy-production command - remove Linear references
10. Update all 8 agent definitions - remove Linear requirements
11. Simplify integration-context.md to feedback-only
12. Update analytics schema - remove Linear project fields
13. Test /feedback command still works
14. Final review for stray Linear references

**Acceptance Criteria**:
- [ ] No Linear issue creation in any build phase
- [ ] `/feedback` command works correctly
- [ ] All documentation updated consistently
- [ ] No "Phase 0.5: Linear" in any command or agent
- [ ] integration-context.md simplified
- [ ] analytics/usage.json schema updated

---

## Appendix

### Linear References Summary

Total Linear references found:
- **CLAUDE.md**: ~100 lines to remove
- **PROCESS.md**: ~30 references
- **README.md**: ~10 references
- **Commands**: ~350 lines to remove
- **Agents**: ~1000 lines to remove

### Files to Keep Unchanged

- `.claude/commands/feedback.md` - Legitimate Linear use
- `.claude/settings.local.json` - Keep Linear MCP for feedback
