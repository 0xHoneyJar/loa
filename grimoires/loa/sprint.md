# Sprint Plan: RTFM Testing Skill

**Version**: 1.0.0
**Date**: 2026-02-09
**PRD**: grimoires/loa/prd.md
**SDD**: grimoires/loa/sdd.md
**Issue**: #236

---

## Overview

| Field | Value |
|-------|-------|
| Total Sprints | 1 |
| Sprint Duration | Single session |
| Developer | Claude (AI agent) |
| Scope | MVP (PRD Section 8, Sprint 1 items) |

---

## Sprint 1: Core `/rtfm` Skill

**Goal**: Deliver a working `/rtfm` command that spawns zero-context tester agents, parses structured gap reports, and writes test results.

### Task 1: Create SKILL.md with Tester Prompt

**File**: `.claude/skills/rtfm-testing/SKILL.md`

Create the main skill definition containing:
- Objective section
- Tester capabilities manifest (knows/does_not_know lists from PRD FR-2)
- Cleanroom tester prompt with rules, gap format, output format
- Context isolation canary check
- Task templates (6 pre-built: install, quickstart, mount, beads, gpt-review, update)
- Gap parser logic (extract [GAP] markers, count by type/severity, determine verdict)
- Report template
- 5-phase workflow (arg resolution → doc bundling → tester spawn → gap parsing → report)

**Acceptance Criteria**:
- [ ] Tester prompt is cleanroom (no verbatim text from zscole/rtfm-testing)
- [ ] Capabilities manifest explicitly lists knows and does_not_know
- [ ] Canary check embedded in prompt
- [ ] All 6 gap types defined (MISSING_STEP, MISSING_PREREQ, UNCLEAR, INCORRECT, MISSING_CONTEXT, ORDERING)
- [ ] All 3 severity levels defined (BLOCKING, DEGRADED, MINOR)
- [ ] Verdict rules: SUCCESS (0 blocking) / PARTIAL (>0 blocking, progress) / FAILURE (stuck)
- [ ] 6 task templates with default doc mappings
- [ ] Workflow phases 0-4 documented

**Estimated Effort**: Medium

### Task 2: Create index.yaml

**File**: `.claude/skills/rtfm-testing/index.yaml`

Create skill metadata following Loa conventions:
- name, version, model, color, danger_level, categories
- Triggers: `/rtfm`, `test documentation`, `validate docs usability`
- Inputs: docs (string[]), task (string)
- Outputs: report path

**Acceptance Criteria**:
- [ ] danger_level is `safe`
- [ ] model is `sonnet`
- [ ] Triggers match command invocation patterns
- [ ] Categories include `quality`

**Estimated Effort**: Low

### Task 3: Create Command File

**File**: `.claude/commands/rtfm.md`

Create command definition with:
- Arguments: docs (positional), --task, --template, --auto, --model
- Agent routing to rtfm-testing skill
- Pre-flight checks
- Output path declaration

**Acceptance Criteria**:
- [ ] All arguments from SDD Section 4.1 defined
- [ ] Routes to `skills/rtfm-testing/` agent
- [ ] Default model is sonnet
- [ ] --template accepts: install, quickstart, mount, beads, gpt-review, update

**Estimated Effort**: Low

### Task 4: Smoke Test on README.md

Run `/rtfm README.md` against Loa's actual README and verify:

**Acceptance Criteria**:
- [ ] Tester subagent spawns successfully
- [ ] Canary check passes (tester doesn't know about Loa from prior knowledge)
- [ ] Gaps are found and reported in [GAP] format
- [ ] Verdict is returned (SUCCESS, PARTIAL, or FAILURE)
- [ ] Report is written to `grimoires/loa/a2a/rtfm/report-{date}.md`
- [ ] Summary displayed to user with gap count and verdict

**Estimated Effort**: Low (validation only)

---

## Dependencies

```
Task 1 (SKILL.md) ──┐
Task 2 (index.yaml) ─┼──→ Task 4 (Smoke Test)
Task 3 (rtfm.md) ───┘
```

Tasks 1-3 are independent and can be implemented in parallel. Task 4 requires all three.

---

## Out of Scope (Phase 2)

- Baseline registry (`baselines.yaml`)
- `/review` golden path integration (`--auto`)
- Sonnet vs haiku model comparison
- Gap verdict mapping to `/validate docs`

---

## Success Criteria

Sprint is complete when:
1. All 3 files created and committed
2. `/rtfm README.md` produces a valid gap report
3. Canary check validates context isolation
4. Report written to `grimoires/loa/a2a/rtfm/`
