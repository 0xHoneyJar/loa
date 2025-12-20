# Software Design Document: Remove Linear Audit Trail

**Version**: 1.0.0
**Date**: 2025-12-20
**Author**: Architecture Designer Agent
**Status**: Draft

---

## Executive Summary

This SDD describes the technical approach for removing Linear audit trail integration from the Loa framework. This is a refactoring task focused on removing existing functionality rather than building new features.

**Scope**: Remove ~1,500 lines of Linear-related code across 20 files while preserving the `/feedback` command functionality.

**Approach**: Systematic removal using search-and-remove patterns, followed by validation testing.

---

## System Architecture

### Current Architecture (Before)

```
┌─────────────────────────────────────────────────────────────────┐
│                        Loa Framework                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐        │
│  │ /setup   │  │/implement│  │ /review  │  │ /audit   │        │
│  │          │  │          │  │          │  │          │        │
│  │ Creates  │  │ Creates  │  │ Adds     │  │ Creates  │        │
│  │ Linear   │  │ Linear   │  │ Linear   │  │ Linear   │        │
│  │ Project  │  │ Issues   │  │ Comments │  │ Issues   │        │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘        │
│       │             │             │             │               │
│       └─────────────┴─────────────┴─────────────┘               │
│                           │                                      │
│                           ▼                                      │
│                    ┌─────────────┐                              │
│                    │   Linear    │                              │
│                    │   (MCP)     │                              │
│                    └─────────────┘                              │
│                                                                  │
│  ┌──────────┐                                                   │
│  │/feedback │───────────────────────────────────────────────────┤
│  │          │  Posts to "Loa Feedback" project                  │
│  └──────────┘                                                   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Target Architecture (After)

```
┌─────────────────────────────────────────────────────────────────┐
│                        Loa Framework                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐        │
│  │ /setup   │  │/implement│  │ /review  │  │ /audit   │        │
│  │          │  │          │  │          │  │          │        │
│  │ Init     │  │ Write    │  │ Write    │  │ Write    │        │
│  │ Analytics│  │ Code     │  │ Feedback │  │ Feedback │        │
│  │ Only     │  │ Only     │  │ to A2A   │  │ to A2A   │        │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘        │
│                                                                  │
│       (No Linear interaction in build phases)                   │
│                                                                  │
│  ┌──────────┐                                                   │
│  │/feedback │───────────────────────────────────────────────────┤
│  │          │  Posts to "Loa Feedback" project (UNCHANGED)      │
│  └──────────┘                                                   │
│                           │                                      │
│                           ▼                                      │
│                    ┌─────────────┐                              │
│                    │   Linear    │                              │
│                    │   (MCP)     │                              │
│                    └─────────────┘                              │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Technology Stack

No new technologies required. This is a removal task.

**Preserved**:
- Linear MCP (for `/feedback` only)
- All other MCPs (GitHub, Vercel, Discord, web3-stats)
- Markdown document structure
- Analytics JSON schema (simplified)

---

## Component Design

### Component 1: Documentation Files

| File | Action | Sections to Remove |
|------|--------|-------------------|
| `CLAUDE.md` | Edit | "Linear Documentation Requirements", "Agent Linear Documentation Responsibilities", "Standard Label Taxonomy", "Required Documentation Content", "Querying Linear for Context" |
| `PROCESS.md` | Edit | All Phase 0.5 references, Linear tracking mentions |
| `README.md` | Edit | Linear audit trail mentions in MCP section, repository structure |

### Component 2: Command Definitions

| File | Action | Content to Remove |
|------|--------|-------------------|
| `.claude/commands/setup.md` | Edit | Section 3.2 (Create Linear Project), Linear project in summary |
| `.claude/commands/implement.md` | Edit | Phase 0.5 (Linear Issue Creation), "Linear Issue Tracking" template section |
| `.claude/commands/review-sprint.md` | Edit | Phase 0.5 (Linear Issue Tracking), Linear blocking check |
| `.claude/commands/audit-sprint.md` | Edit | Phase 0.5 (Linear Issue Tracking), security issue creation |
| `.claude/commands/sprint-plan.md` | Edit | Phase 0.5 (Linear Sprint Project Creation) |
| `.claude/commands/deploy-production.md` | Edit | Linear issue creation references |
| `.claude/commands/feedback.md` | **PRESERVE** | No changes - this is the legitimate Linear use |

### Component 3: Agent Definitions

| File | Action | Content to Remove |
|------|--------|-------------------|
| `.claude/agents/prd-architect.md` | Edit | Linear knowledge source references |
| `.claude/agents/architecture-designer.md` | Edit | Linear SDK reference |
| `.claude/agents/sprint-planner.md` | Edit | Phase 0.5 (Linear Sprint Project Creation) |
| `.claude/agents/sprint-task-implementer.md` | Edit | Phase 0.5 (Linear Issue Creation), all `mcp__linear__` calls |
| `.claude/agents/senior-tech-lead-reviewer.md` | Edit | Phase 0.5 (Linear Review Documentation), blocking checks |
| `.claude/agents/devops-crypto-architect.md` | Edit | Phase 0.5 (Linear Issue Creation), webhook references |
| `.claude/agents/paranoid-auditor.md` | Edit | Linear Issue Creation section, finding issue creation |
| `.claude/agents/devrel-translator.md` | Edit | Linear mentions in examples |

### Component 4: Data Files

| File | Action | Content to Remove |
|------|--------|-------------------|
| `loa-grimoire/a2a/integration-context.md` | Rewrite | Keep only feedback project reference |
| `loa-grimoire/analytics/usage.json` | Edit | Remove `linear` section |

---

## Data Architecture

### Current Schema (usage.json)

```json
{
  "schema_version": "1.0.0",
  "linear": {
    "team_id": "...",
    "team_name": "...",
    "project_id": "...",
    "project_name": "...",
    "project_url": "..."
  },
  "feedback_submissions": []
}
```

### Target Schema (usage.json)

```json
{
  "schema_version": "1.0.0",
  "feedback_submissions": []
}
```

**Note**: The `linear` section is removed entirely. Feedback submissions continue to work as the `/feedback` command queries Linear directly using the "Loa Feedback" project name.

### integration-context.md Simplified

**Current** (~100 lines):
- Team ID, Project ID
- Label taxonomy (agent labels, type labels, priority labels, sprint labels)
- Issue templates
- Commit message template

**Target** (~20 lines):
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

---

## Implementation Strategy

### Phase 1: Documentation (3 files)

**Order**: CLAUDE.md → PROCESS.md → README.md

**CLAUDE.md Removal Targets**:
1. Lines 346-448: "Linear Documentation Requirements" section
2. Lines 710: integration-context.md reference update
3. Various MCP section edits

**PROCESS.md Removal Targets**:
1. All "Linear" mentions except in feedback section
2. Phase 0.5 references
3. Linear project creation in setup section

**README.md Removal Targets**:
1. Line 183-188: Linear MCP description (simplify, don't remove)
2. Line 207: integration-context.md description update
3. Line 92: Feedback description (keep)

### Phase 2: Commands (6 files)

**Order**: setup.md → implement.md → review-sprint.md → audit-sprint.md → sprint-plan.md → deploy-production.md

**Pattern for removal**:
1. Search for "Phase 0.5" sections
2. Search for "Linear" references
3. Search for `mcp__linear__` calls
4. Remove entire sections, not just individual lines
5. Update section numbering if needed

### Phase 3: Agents (8 files)

**Order by complexity** (most changes first):
1. `devops-crypto-architect.md` (~300 lines)
2. `paranoid-auditor.md` (~250 lines)
3. `sprint-task-implementer.md` (~200 lines)
4. `senior-tech-lead-reviewer.md` (~180 lines)
5. `sprint-planner.md` (~80 lines)
6. `prd-architect.md` (~10 lines)
7. `architecture-designer.md` (~5 lines)
8. `devrel-translator.md` (~5 lines)

**Pattern for removal**:
1. Search for "Phase 0.5" or "Linear" sections
2. Remove entire phases/sections
3. Update phase numbering
4. Remove `mcp__linear__` call examples
5. Remove Linear from troubleshooting sections

### Phase 4: Data Files (2 files)

**integration-context.md**: Complete rewrite to simplified version
**usage.json**: Remove `linear` object (keep `feedback_submissions`)

---

## Validation Strategy

### Test 1: No Linear References in Build Phases

```bash
# Should return 0 matches (excluding feedback.md)
grep -r "mcp__linear__" .claude/commands/ | grep -v feedback.md
grep -r "mcp__linear__" .claude/agents/
```

### Test 2: Phase 0.5 Removed

```bash
# Should return 0 matches
grep -r "Phase 0.5" .claude/
grep -r "Phase 0\.5" .claude/
```

### Test 3: Feedback Command Still Works

1. Run `/feedback` command
2. Verify it successfully posts to Linear
3. Verify analytics are included

### Test 4: Documentation Consistency

```bash
# Count Linear references - should be minimal (only in feedback context)
grep -ri "linear" CLAUDE.md PROCESS.md README.md | wc -l
# Review each match to ensure it's feedback-related only
```

### Test 5: Build Workflow Functions

1. Run `/setup` - should not create Linear project
2. Run `/implement sprint-1` - should not create Linear issues
3. Run `/review-sprint sprint-1` - should not add Linear comments
4. Run `/audit-sprint sprint-1` - should not create Linear issues

---

## Risk Mitigation

### Risk 1: Breaking /feedback

**Mitigation**:
- Do NOT modify `.claude/commands/feedback.md`
- Test `/feedback` after all changes
- The feedback command uses project name search, not stored IDs

### Risk 2: Incomplete Removal

**Mitigation**:
- Use grep to find all Linear references
- Review each file systematically
- Run validation tests after each phase

### Risk 3: Documentation Drift

**Mitigation**:
- Update all three docs (CLAUDE.md, PROCESS.md, README.md) in same sprint
- Cross-reference to ensure consistency

---

## Rollback Plan

If issues are discovered after removal:

1. **Git revert**: All changes are in a single branch
2. **Selective restore**: Individual files can be restored from git history
3. **No data loss**: Linear issues still exist in Linear (just not referenced)

---

## Success Criteria

- [ ] `grep -r "Phase 0.5" .claude/` returns 0 results
- [ ] `grep -r "mcp__linear__" .claude/commands/ | grep -v feedback.md` returns 0 results
- [ ] `grep -r "mcp__linear__" .claude/agents/` returns 0 results
- [ ] `/feedback` command works correctly
- [ ] `/setup` does not create Linear project
- [ ] All documentation updated consistently
- [ ] `integration-context.md` simplified to ~20 lines
- [ ] `usage.json` has no `linear` section

---

## Appendix: File Change Summary

| Category | Files | Est. Lines Removed |
|----------|-------|-------------------|
| Documentation | 3 | ~140 |
| Commands | 6 | ~350 |
| Agents | 8 | ~1,000 |
| Data Files | 2 | ~80 |
| **Total** | **19** | **~1,570** |

**Files Unchanged**:
- `.claude/commands/feedback.md`
- `.claude/settings.local.json`
- All other MCP configurations
