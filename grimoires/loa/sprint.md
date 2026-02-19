# Sprint Plan: UX Redesign — Vercel-Grade Developer Experience

> Cycle: cycle-030 | PRD: grimoires/loa/prd.md | SDD: grimoires/loa/sdd.md
> Source: [#380](https://github.com/0xHoneyJar/loa/issues/380)-[#390](https://github.com/0xHoneyJar/loa/issues/390)
> Sprints: 4 (2 completed, 2 new) | Team: 1 developer (AI-assisted)

---

## Executive Summary

| Field | Value |
|-------|-------|
| **Total Sprints** | 4 (sprint-25, sprint-26 completed; sprint-27, sprint-28 new) |
| **Phase 1 Scope** | ✅ Tier 0 bug fixes + auto-install + /plan entry fixes + /feedback visibility |
| **Phase 2 Scope** | Post-completion debrief + free-text /plan + sprint time calibration + tool hesitancy fix |
| **Success Metric** | All 3 phase SKILL.md files have `<post_completion>`; zero "2.5 days"; free-text-first /plan; smoke tests pass |

---

## Sprint 1: Bug Fixes + Auto-Install Infrastructure (COMPLETED — sprint-25)

✅ Implemented in commit `ca25a13`. See git history for details.

**Tasks completed**: Fix beads URL (#380), fix yq hint (#381), fix flock hint (#382), auto-install deps, post-mount golden path message.

---

## Sprint 2: /plan Entry Fixes + /feedback + Setup Auto-Fix (COMPLETED — sprint-26)

✅ Implemented in commits `ca25a13..d5ded9c`. See git history for details.

**Tasks completed**: "What does Loa add?" re-entry (#383), archetype truncation (#384), /loa setup auto-fix (#390), /feedback in first-time /loa (#388).

---

## Sprint 3: Post-Completion Debrief + Sprint Time Calibration + Tool Hesitancy

**Scope**: FR-7 (post_completion), FR-9 (sprint time), FR-10 (tension-driven /feedback), FR-11 (tool hesitancy)
**Scope size**: MEDIUM (6 tasks)

### Task 3.1: Add `<post_completion>` to discovering-requirements/SKILL.md (#385)

**File**: `.claude/skills/discovering-requirements/SKILL.md`
**Anchor**: After the closing `</visual_communication>` tag (end of file)

**Change**: Append the `<post_completion>` section from SDD §3.1.1 with PRD-specific values:
- artifact: "PRD", path: "grimoires/loa/prd.md"
- next_phase: "architecture"
- Includes "Adjust" flow specification (regenerate artifact, preserve context, re-debrief)

**Acceptance Criteria**:
- [ ] `<post_completion>` section exists after `</visual_communication>`
- [ ] Debrief structure: Key Decisions (3-5), Assumptions (1-3), Biggest Tradeoff (1)
- [ ] AskUserQuestion with Continue / Adjust / Stop here
- [ ] "Stop here" includes /feedback mention
- [ ] "Adjust" triggers regeneration with context preservation

### Task 3.2: Add `<post_completion>` to designing-architecture/SKILL.md (#385)

**File**: `.claude/skills/designing-architecture/SKILL.md`
**Anchor**: After the closing `</communication_style>` tag (end of file)

**Change**: Append the `<post_completion>` section with SDD-specific values:
- artifact: "SDD", path: "grimoires/loa/sdd.md"
- next_phase: "sprint planning"

**Acceptance Criteria**:
- [ ] `<post_completion>` section exists after `</communication_style>`
- [ ] Same debrief structure as Task 3.1
- [ ] AskUserQuestion with Continue / Adjust / Stop here

### Task 3.3: Add `<post_completion>` to planning-sprints/SKILL.md (#385)

**File**: `.claude/skills/planning-sprints/SKILL.md`
**Anchor**: After the closing `</visual_communication>` tag (end of file)

**Change**: Append the `<post_completion>` section with Sprint-specific values:
- artifact: "Sprint Plan", path: "grimoires/loa/sprint.md"
- next_phase: "implementation"
- "Continue" label reads "Start building" (final planning phase)

**Acceptance Criteria**:
- [ ] `<post_completion>` section exists after `</visual_communication>`
- [ ] "Continue" option label is "Start building" not "Continue"
- [ ] Same debrief structure as Tasks 3.1-3.2

### Task 3.4: Replace "2.5 days" with scope sizing in planning-sprints/SKILL.md (#387)

**File**: `.claude/skills/planning-sprints/SKILL.md`

**Change**: Find-and-replace all 7 occurrences per SDD §3.3.1:
- "2.5-day sprints" → "right-sized sprints" (2 occurrences)
- "2.5 days of work" → "10 tasks per sprint. Size as SMALL (1-3), MEDIUM (4-6), LARGE (7-10)"
- "Duration: 2.5 days with specific dates" → "Scope: SMALL / MEDIUM / LARGE"
- "feasible within 2.5 days" → "feasible as a single iteration" (2 occurrences)
- "Duration (2.5 days) with dates" → "Scope (SMALL/MEDIUM/LARGE) with task count"

**Acceptance Criteria**:
- [ ] Zero occurrences of "2.5" in planning-sprints/SKILL.md
- [ ] SMALL/MEDIUM/LARGE sizing present
- [ ] No calendar date references in sprint template output

### Task 3.5: Fix App zone + add CLI permissions in implementing-tasks/SKILL.md (#389)

**File**: `.claude/skills/implementing-tasks/SKILL.md`

**Change 1**: In `<zone_constraints>`, find the row with `src/`, `lib/`, `app/` and change "Read-only | App zone - requires user confirmation" to "Read/Write | App zone - implementation target"

**Change 2**: After closing `</zone_constraints>`, insert the `<cli_tool_permissions>` section from SDD §3.5.2 (explicit allowlist with git, gh, npm/bun, cargo read-only commands + confirmation-required list)

**Acceptance Criteria**:
- [ ] App zone shows "Read/Write" in zone table
- [ ] `<cli_tool_permissions>` section exists with explicit allowlist
- [ ] Allowlist includes git, gh, npm/bun, cargo read-only commands
- [ ] Destructive operations listed under "Require Confirmation"

### Task 3.6: Add CLI read-only permissions to planning SKILL.md files (#389)

**Files**: `discovering-requirements/SKILL.md`, `designing-architecture/SKILL.md`, `planning-sprints/SKILL.md`

**Change**: In each file's `<zone_constraints>` section, append after the zone table:
```
Agents MAY proactively run read-only CLI tools (e.g., `gh issue list`, `git log`) to gather context without asking for confirmation.
```

**Acceptance Criteria**:
- [ ] All 3 planning SKILL.md files have CLI read-only permission statement
- [ ] Statement is inside or immediately after `<zone_constraints>`

---

## Sprint 4: Free-Text-First /plan Entry + Smoke Tests

**Scope**: FR-8 (free-text /plan), FR-10 remaining tension points, automated tests
**Scope size**: MEDIUM (5 tasks)

### Task 4.1: Replace archetype selection with free-text flow in plan.md (#386)

**File**: `.claude/commands/plan.md`

**Change**: Replace the use-case qualification gate (lines ~55-109) and archetype selection (lines ~111-158) with the new flow from SDD §3.2.2:
1. First-time preamble (3 lines, non-interactive, one-time)
2. Free-text AskUserQuestion ("Tell me about your project...")
3. Input validation (reprompt if <10 chars)
4. Save to `grimoires/loa/context/user-description.md`
5. LLM-based archetype inference (silent, logged to `archetype-inference.md`)
6. Route to `/plan-and-analyze`

Also update the Examples section (lines ~206-264) to show new flow.

**LLM Archetype Inference Detail** (Flatline IMP-002, SKP-003):
- The agent reads all archetype YAML files and the user's description
- Classification prompt: "Given this project description and these archetypes, which archetype best matches? Reply with: `archetype: <filename>` and `confidence: high|medium|low`. If none fit, reply `archetype: none`."
- Confidence threshold: Only seed risks if confidence is `high` or `medium`
- Low confidence / none: Skip risk seeding silently (Phase 0 interview compensates)
- Multi-match: If description matches multiple, merge risk checklists from all
- Log format: `archetype-inference.md` contains archetype, confidence, rationale

**Privacy** (Flatline SKP-004): Add `grimoires/loa/context/user-description.md` and `archetype-inference.md` to `.gitignore` to prevent accidental commit of user input.

**Acceptance Criteria**:
- [ ] No archetype selection AskUserQuestion in plan.md
- [ ] Free-text prompt present: "Tell me about your project"
- [ ] "I have context files ready" shortcut option present
- [ ] Input <10 chars triggers reprompt
- [ ] Description saved to `grimoires/loa/context/user-description.md`
- [ ] `user-description.md` and `archetype-inference.md` in `.gitignore`
- [ ] LLM archetype inference with confidence threshold (not keyword matching)
- [ ] Inference logged to `grimoires/loa/context/archetype-inference.md`
- [ ] First-time preamble: ≤3 lines, non-interactive
- [ ] Returning users (existing PRD) see state-detection flow (no regression)

### Task 4.2: Add /feedback to doctor warnings

**File**: `.claude/commands/loa.md` (or inline in the `/loa` command's health check display logic)

**Change**: When `/loa` displays health warnings from doctor output, append:
```
Something broken? /feedback reports it directly.
```

**Acceptance Criteria**:
- [ ] /feedback message appears when health warnings are shown
- [ ] /feedback NOT shown when health is clean

### Task 4.3: Add /feedback to Flatline result display

**File**: Flatline result presentation logic (locate the block that displays HIGH_CONSENSUS auto-integration)

**Change**: After auto-integrating HIGH_CONSENSUS findings, append:
```
Multi-model review working as designed. /feedback if you disagree.
```

**Acceptance Criteria**:
- [ ] /feedback message appears after Flatline auto-integration
- [ ] Only shown when HIGH_CONSENSUS items are integrated (not on empty results)

### Task 4.4: Create automated smoke test script

**File**: `.claude/scripts/tests/test-ux-phase2.sh` (new file)

**Change**: Implement the smoke test script from SDD §5 that validates:
- `<post_completion>` exists in all 3 planning SKILL.md files
- No archetype selection UI in plan.md
- Free-text prompt exists in plan.md
- No "2.5 days" in planning-sprints/SKILL.md
- SMALL/MEDIUM/LARGE sizing present
- App zone shows "Read/Write" in implementing-tasks/SKILL.md
- `<cli_tool_permissions>` section exists

**Acceptance Criteria**:
- [ ] Script exists and is executable
- [ ] All assertions pass after Phase 2 implementation
- [ ] Script uses `((errors+=1))` not `((errors++))` (set -e safety)

### Task 4.5: Run smoke tests + manual verification

**Change**: Execute `test-ux-phase2.sh` and walk through the manual verification checklist below.

**Manual Verification Checklist** (Flatline SKP-005 — inlined, not just referenced):
1. Fresh /plan: preamble shown once, free-text prompt appears
2. /plan with context: "I have context files" routes correctly
3. Short description (<10 chars): reprompt fires
4. After PRD creation: debrief with decisions/assumptions/tradeoff shown
5. After SDD creation: debrief shown, "Continue" leads to sprint planning
6. After Sprint creation: debrief shown, "Start building" option
7. "Adjust" in debrief: regenerates artifact, preserves context, re-debriefs
8. Sprint output uses SMALL/MEDIUM/LARGE, no "2.5 days"
9. /feedback appears in "Stop here" option description
10. No /feedback in post-mount, post-setup, or generic help
11. `archetype-inference.md` created after /plan with description
12. `user-description.md` and `archetype-inference.md` are gitignored

**Acceptance Criteria**:
- [ ] All automated smoke tests pass
- [ ] All 12 manual checklist items verified

---

## Sprint Dependency Graph

```
Sprint 3 (SKILL.md modifications)
  ├── Task 3.1-3.3: post_completion (independent, can parallelize)
  ├── Task 3.4: sprint time (same file as 3.3, do after 3.3)
  ├── Task 3.5: implementing-tasks zone + CLI (independent)
  └── Task 3.6: planning SKILL.md CLI perms (can combine with 3.1-3.3)

Sprint 4 (plan.md + testing)
  ├── Task 4.1: free-text /plan (depends on Sprint 3 for context)
  ├── Task 4.2-4.3: /feedback tension points (independent)
  ├── Task 4.4: smoke tests (depends on 3.x + 4.1)
  └── Task 4.5: verification (depends on all above)
```

---

## Risk Register

| Risk | Mitigation |
|------|-----------|
| SKILL.md prompt regression | Automated smoke tests (Task 4.4) catch structural issues; manual verification catches behavioral issues |
| Free-text "Other" client inconsistency | Input validation handles empty/short input; "Describe my project" option provides non-Other path |
| LLM archetype inference cost | Classification is a single lightweight LLM call; no external API needed |
| Merge conflicts with main | All changes are on the same branch; PR will be reviewed as one unit |
