# SDD: UX Redesign — Vercel-Grade Developer Experience

> Cycle: cycle-030 | Author: soju + Claude
> Source PRD: `grimoires/loa/prd.md` (#380-#390)
> Design Context: `grimoires/loa/context/ux-redesign-plan.md`

---

## 1. Architecture Overview

This cycle modifies **existing scripts, commands, and SKILL.md prompt files only** — no new architectural components, no new scripts, no config schema changes.

### Phase 1 — Modified Components (COMPLETED)

```
.claude/scripts/mount-loa.sh          ← FR-1 (bug fixes) + FR-3 (auto-install) + FR-4 (post-mount msg)
.claude/scripts/loa-doctor.sh         ← FR-1 (flock hint fix)
.claude/commands/plan.md              ← FR-2 (plan entry flow fixes)
.claude/commands/loa-setup.md         ← FR-5 (auto-fix capability)
.claude/commands/loa.md               ← FR-6 (/feedback at tension points)
```

### Phase 2 — Modified Components (NEW)

```
.claude/skills/discovering-requirements/SKILL.md  ← FR-7 (post_completion) + FR-11 (CLI permissions)
.claude/skills/designing-architecture/SKILL.md    ← FR-7 (post_completion) + FR-11 (CLI permissions)
.claude/skills/planning-sprints/SKILL.md          ← FR-7 (post_completion) + FR-9 (time calibration) + FR-11 (CLI permissions)
.claude/skills/implementing-tasks/SKILL.md        ← FR-11 (zone table fix + CLI proactive-use)
.claude/commands/plan.md                          ← FR-8 (free-text-first entry)
```

### Unchanged Components

- `.loa.config.yaml` schema
- Beads, hooks, guardrails, Flatline
- Three-zone model enforcement (hooks still enforce)
- All scripts (no new scripts added)

---

## 2. Phase 1 Detailed Design (COMPLETED)

Phase 1 designs were implemented in sprint-25 and sprint-26. See git history for `ca25a13..d5ded9c`. Summary:

| FR | What Changed | Files |
|----|-------------|-------|
| FR-1 | Fixed beads URL, yq hint, flock hint | mount-loa.sh, loa-doctor.sh |
| FR-2 | Fixed "What does Loa add?" fall-through, archetype truncation | plan.md |
| FR-3 | Added `auto_install_deps()` with OS detection | mount-loa.sh |
| FR-4 | Single "Next: /plan" post-mount message | mount-loa.sh |
| FR-5 | Added auto-fix step to /loa setup | loa-setup.md |
| FR-6 | /feedback in first-time /loa + help output | loa.md |

---

## 3. Phase 2 Detailed Design (NEW)

### 3.1 FR-7: Post-Completion Debrief

Add a `<post_completion>` XML section to the end of each planning phase SKILL.md. All three follow the same template with phase-appropriate wording.

#### 3.1.1 Template (shared across all 3 skills)

```xml
<post_completion>
## Post-Completion Debrief

After saving the artifact, ALWAYS present a structured debrief before the user decides to continue.

### Debrief Structure

Present the following in this exact order:

1. **Confirmation**: "✓ {artifact} saved to {path}"

2. **Key Decisions** (3-5 items): The most impactful choices made during this phase. Each decision should be one line: "• {choice made} (not {alternative rejected})"

3. **Assumptions** (1-3 items): Things assumed true but not explicitly confirmed by the user. Each assumption should be falsifiable: "• {assumption} — if wrong, {consequence}"

4. **Biggest Tradeoff** (1 item): The most consequential either/or decision. Format: "• Chose {A} over {B} — {reason}. Risk: {what could go wrong}"

5. **Steer Prompt**: Use AskUserQuestion:

```yaml
question: "Anything to steer before {next_phase}?"
header: "Review"
options:
  - label: "Continue (Recommended)"
    description: "{next_action_description}"
  - label: "Adjust"
    description: "Tell me what to change — I'll regenerate"
  - label: "Stop here"
    description: "Save progress — resume with /plan next time. Not what you expected? /feedback helps us fix it."
multiSelect: false
```

### Constraints

- Keep decisions to 3-5 items — not an exhaustive list
- Each item is ONE line — no paragraphs
- "Continue" is always the first option (recommended)
- "Stop here" always includes /feedback mention (FR-10 tension point)
- If Flatline will run next, add a one-line banner BEFORE the steer prompt: "Next: Multi-model review (~30 seconds)"

### "Adjust" Flow (Flatline IMP-009)

When the user selects "Adjust":

1. **Prompt**: "What would you like to change?" (free-text via AskUserQuestion "Other")
2. **Scope**: Regenerate the current artifact ONLY (not rerun the entire phase)
3. **Context preserved**: All prior interview answers, context files, and phase state are retained
4. **Output**: After regeneration, re-present the debrief with updated decisions/assumptions/tradeoffs
5. **Diff awareness**: If changes are small, note what changed: "Updated: {decision that changed}"
6. **Loop limit**: Max 3 adjustment rounds before suggesting "Continue" more firmly

</post_completion>
```

#### 3.1.2 discovering-requirements/SKILL.md

**Insert after**: The closing `</visual_communication>` tag (last XML section in file)

**Phase-specific values**:
- `{artifact}`: "PRD"
- `{path}`: "grimoires/loa/prd.md"
- `{next_phase}`: "architecture"
- `{next_action_description}`: "Design the system architecture now"

#### 3.1.3 designing-architecture/SKILL.md

**Insert after**: The closing `</communication_style>` tag (last XML section in file)

**Phase-specific values**:
- `{artifact}`: "SDD"
- `{path}`: "grimoires/loa/sdd.md"
- `{next_phase}`: "sprint planning"
- `{next_action_description}`: "Create the sprint plan now"

#### 3.1.4 planning-sprints/SKILL.md

**Insert after**: The closing `</visual_communication>` tag (last XML section in file)

**Phase-specific values**:
- `{artifact}`: "Sprint Plan"
- `{path}`: "grimoires/loa/sprint.md"
- `{next_phase}`: "implementation"
- `{next_action_description}`: "Start building with /build"

**Additional note for sprint**: The steer prompt's "Continue" label should say "Start building" instead of "Continue" since this is the final planning phase.

---

### 3.2 FR-8: Free-Text-First /plan Entry

Replace the archetype-selection flow in `plan.md` with a free-text-first flow. This is the most significant change in Phase 2.

#### 3.2.1 Current Flow (plan.md:55-170)

```
Lines 55-109:  Use-case qualification gate
  - First-time check (no PRD, no completed cycles)
  - AskUserQuestion: "Let's go!" vs "What does Loa add?"
  - If "What does Loa add?": show info block, then re-ask

Lines 111-158: Archetype selection
  - Discover .claude/data/archetypes/*.yaml
  - Present top 3 as AskUserQuestion options
  - Seed NOTES.md with archetype risks
  - Write archetype context to grimoires/loa/context/archetype.md

Lines 160-169: Route to truename skill
```

#### 3.2.2 New Flow (replacement for lines 55-158)

```markdown
### 3. First-Time Preamble (One-Time)

**Condition**: No PRD exists AND no completed cycles in ledger AND no `--from` override.

Display a brief, non-interactive preamble (3 lines max):

```
Loa guides you through structured planning: requirements → architecture → sprints.
Multi-model review catches issues that single-model misses.
Cross-session memory means you never start from scratch.
```

This displays ONCE. No AskUserQuestion. No gate. No "What does Loa add?" choice.
The preamble is followed immediately by the free-text prompt.

### 4. Free-Text Project Description

**Condition**: Phase is "discovery" (no existing PRD).

Present a free-text prompt via AskUserQuestion:

```yaml
question: "Tell me about your project. What are you building, who is it for, and what problem does it solve?"
header: "Your project"
options:
  - label: "Describe my project"
    description: "Type your project description in the text box below (select Other)"
  - label: "I have context files ready"
    description: "Skip to /plan-and-analyze — I've already put docs in grimoires/loa/context/"
multiSelect: false
```

**Note**: The real input comes via the "Other" free-text option (auto-appended by AskUserQuestion). The first option's description guides users to use it.

### 5. Process Free-Text Input

When the user provides a description (via "Other" or "Describe my project"):

**Input validation** (Flatline IMP-002):
- If empty or <10 characters: reprompt with "Could you tell me more? A sentence or two about what you're building helps me plan better."
- If <30 characters: accept but log a note that context is thin — Phase 0 interview will compensate
- No entropy check needed — even "todo app" is valid input

1. **Save description** to `grimoires/loa/context/user-description.md`:
   ```markdown
   # Project Description (from /plan)
   > Auto-generated from user's initial project description.

   {user's free-text input}
   ```

2. **Infer archetype** using the LLM (not keyword matching — Flatline SKP-003):
   - Read all archetype YAML files from `.claude/data/archetypes/*.yaml`
   - Present the list of archetype names + descriptions to the LLM along with the user's description
   - Ask the LLM to classify: "Which archetype best matches this project? Reply with the filename or 'none'."
   - If match found: silently load `context.risks` into `grimoires/loa/NOTES.md` under `## Known Risks`
   - If multiple matches: merge risk checklists from all matching archetypes (Flatline IMP-003)
   - If no match or low confidence: skip risk seeding (no error, no prompt)
   - **Never show the archetype to the user** — it's internal scaffolding only
   - Log the inferred archetype to `grimoires/loa/context/archetype-inference.md` for traceability

3. **Route to** `/plan-and-analyze` — the description in context/ will be picked up by Phase 0 synthesis.

When the user selects "I have context files ready":
- Skip to `/plan-and-analyze` directly (current behavior for context-rich users).
```

#### 3.2.3 What Gets Removed

| Lines | Content | Disposition |
|-------|---------|-------------|
| 55-109 | Use-case qualification gate | **Removed**. Preamble replaces it (non-interactive) |
| 111-158 | Archetype selection UI | **Removed**. Archetype inferred silently from description |

#### 3.2.4 What Stays Unchanged

| Lines | Content | Why |
|-------|---------|-----|
| 1-53 | Header, state detection, `--from` handling | No changes needed |
| 160-169 | Route to truename skill | Same routing table |
| 170-264 | Phase chaining, arguments, examples | Examples updated to reflect new flow |

#### 3.2.5 Updated Examples (replace lines 206-264)

```markdown
## Examples

### Fresh Project
```
/plan

Loa guides you through structured planning: requirements → architecture → sprints.
Multi-model review catches issues that single-model misses.
Cross-session memory means you never start from scratch.

Tell me about your project. What are you building, who is it for,
and what problem does it solve?

> I'm building a data measurement platform for AI teams. It tracks
> model performance, experiment lineage, and team velocity...

✓ Saved description to grimoires/loa/context/user-description.md
→ Running /plan-and-analyze

[... plan-and-analyze Phase 0 synthesizes description ...]
```

### With Inline Context
```
/plan Build a REST API for user management with JWT auth and rate limiting

✓ Saved description to grimoires/loa/context/user-description.md
→ Running /plan-and-analyze with context
```

### Resume Mid-Planning
```
/plan

Detecting planning state...
  PRD: ✓ exists
  SDD: not found

Resuming from: Architecture Design
→ Running /architect
```
```

---

### 3.3 FR-9: Sprint Time Calibration

Replace all 7 occurrences of "2.5 days" in `planning-sprints/SKILL.md` with scope-based sizing.

#### 3.3.1 Replacement Table

All 7 occurrences of "2.5 days" or "2.5-day" in `planning-sprints/SKILL.md`. Use text search — do not rely on line numbers (Flatline SKP-004).

| Search String | Replacement |
|--------------|-------------|
| "actionable sprint plan with 2.5-day sprints" (appears 2x: in `<objective>` and `<kernel_framework>`) | "actionable sprint plan with right-sized sprints" |
| "DO NOT plan more than 2.5 days of work per sprint" (in sprint sizing guidance) | "DO NOT plan more than 10 tasks per sprint. Size sprints as SMALL (1-3 tasks), MEDIUM (4-6 tasks), or LARGE (7-10 tasks)" |
| "Duration: 2.5 days with specific dates" (in per-sprint output section) | "Scope: SMALL / MEDIUM / LARGE (based on task count)" |
| "Each sprint is feasible within 2.5 days" (appears 2x: in `<success_criteria>` sections) | "Each sprint is feasible as a single iteration" |
| "Duration (2.5 days) with dates" (in `<output_format>`) | "Scope (SMALL/MEDIUM/LARGE) with task count" |

#### 3.3.2 Sprint Output Format Change

Current sprint template output (L410-420 area):
```
## Sprint N: {Title}
Duration: 2.5 days
Start: YYYY-MM-DD
End: YYYY-MM-DD
```

New sprint template output:
```
## Sprint N: {Title}
Scope: {SMALL | MEDIUM | LARGE} ({N} tasks)
```

No calendar dates. If the user needs time framing, the agent can add: "Estimated AI execution: ~1-2 hours" — but this is discretionary, not template-driven.

---

### 3.4 FR-10: Tension-Driven /feedback Visibility

/feedback surfaces at 4 moments of friction only.

#### 3.4.1 Tension Point 1: Post-Completion "Stop here" (via FR-7)

Already integrated into the `<post_completion>` template (Section 3.1). The "Stop here" option description includes:
```
"Save progress — resume with /plan next time. Not what you expected? /feedback helps us fix it."
```

No additional file changes needed — FR-7 handles this.

#### 3.4.2 Tension Point 2: /loa doctor warnings

**File**: `loa.md` (already modified in Phase 1 to mention /feedback in initial state)

Add to the health check / doctor output section. When health warnings are shown, append:
```
Something broken? /feedback reports it directly.
```

**Note**: Phase 1 already added /feedback to the first-time /loa initial state. This adds it to the doctor/health path specifically.

#### 3.4.3 Tension Point 3: Flatline HIGH_CONSENSUS

**File**: Flatline result presentation (handled by flatline-result-handler.sh or the reviewing skill)

After auto-integrating HIGH_CONSENSUS findings, add:
```
Multi-model review working as designed. /feedback if you disagree.
```

This is a minor text addition to the Flatline result display logic. Implementation will locate the exact presentation point during the sprint.

#### 3.4.4 Tension Point 4: First-time /loa

Already implemented in Phase 1 (FR-6). No additional changes.

---

### 3.5 FR-11: Tool Hesitancy Fix

Three changes to reduce agent over-caution.

#### 3.5.1 Fix App Zone Permission (implementing-tasks/SKILL.md)

Locate the `<zone_constraints>` section. Find the row containing `src/`, `lib/`, `app/` in the zone table.

**Current**:
```
| `src/`, `lib/`, `app/` | Read-only | App zone - requires user confirmation |
```

**Change to**:
```
| `src/`, `lib/`, `app/` | Read/Write | App zone - implementation target |
```

**Rationale**: The implementing-tasks skill already writes code files freely via the Write tool. The zone table saying "Read-only" is vestigial and causes agent hesitancy. The hook enforcement (team-role-guard-write.sh) is the real guard — the zone table should reflect actual permissions.

#### 3.5.2 Add CLI Proactive-Use Guidance (implementing-tasks/SKILL.md)

Insert after the closing `</zone_constraints>` tag:

```xml
<cli_tool_permissions>
## CLI Tool Usage

Agents SHOULD proactively run CLI tools from the approved allowlist without asking (Flatline SKP-002):

### Approved Read-Only Allowlist

| Tool | Allowed Commands | Notes |
|------|-----------------|-------|
| `git` | `status`, `log`, `diff`, `branch`, `show` | Local only, no network |
| `gh` | `issue list`, `issue view`, `pr list`, `pr view`, `pr checks` | Use `--json` + field filtering to avoid leaking secrets from PR bodies |
| `npm`/`bun` | `test`, `run lint`, `run typecheck` | Build/check commands |
| `cargo` | `check`, `test`, `clippy` | Build/check commands |

### Require Confirmation

| Operation Type | Examples |
|---------------|----------|
| Network writes | `git push`, `gh pr create`, `gh issue create` |
| Deployments | `railway deploy`, `vercel deploy` |
| Package mutations | `npm install`, `cargo add` |
| Cloud CLIs | `aws`, `gcloud`, `az` (any operation) |
| Destructive | `rm`, `git reset`, `git checkout -- .` |

### Safety Rules

- Use `--json` output and filter fields when available to avoid printing secrets
- Never pipe CLI output to files without user confirmation
- If a CLI command requires authentication and fails, report the error — do not retry or prompt for credentials
</cli_tool_permissions>
```

#### 3.5.3 Add CLI Read-Only Permissions to Planning Skills

Add a shorter version to the zone tables of the 3 planning SKILL.md files.

**discovering-requirements/SKILL.md** — locate the zone_constraints section and append:

```
Agents MAY proactively run read-only CLI tools (e.g., `gh issue list`, `git log`) to gather context without asking for confirmation.
```

**designing-architecture/SKILL.md** — same addition to zone_constraints.

**planning-sprints/SKILL.md** — same addition to zone_constraints.

---

## 4. Data Model

No data model changes. One new file created during runtime:
- `grimoires/loa/context/user-description.md` — auto-generated from free-text input in `/plan`

---

## 5. Testing Strategy

### Automated Smoke Tests (Flatline IMP-001)

These tests can be run as a post-implementation verification script:

```bash
#!/usr/bin/env bash
# test-ux-phase2.sh — Automated smoke tests for Phase 2 changes
set -euo pipefail
errors=0

# FR-7: Post-completion sections exist
for skill in discovering-requirements designing-architecture planning-sprints; do
  if ! grep -q '<post_completion>' ".claude/skills/$skill/SKILL.md"; then
    echo "FAIL: $skill/SKILL.md missing <post_completion> section"
    ((errors+=1))
  fi
done

# FR-8: No archetype selection UI in plan.md
if grep -qi 'archetype.*selection\|select.*archetype' .claude/commands/plan.md; then
  echo "FAIL: plan.md still contains archetype selection UI"
  ((errors+=1))
fi

# FR-8: Free-text prompt exists
if ! grep -qi 'describe.*project\|tell me about' .claude/commands/plan.md; then
  echo "FAIL: plan.md missing free-text project description prompt"
  ((errors+=1))
fi

# FR-9: No "2.5 days" anywhere in sprint planning
if grep -q '2\.5.day' ".claude/skills/planning-sprints/SKILL.md"; then
  echo "FAIL: planning-sprints/SKILL.md still contains '2.5 days'"
  ((errors+=1))
fi

# FR-9: Scope sizing present
if ! grep -q 'SMALL.*MEDIUM.*LARGE\|SMALL/MEDIUM/LARGE' ".claude/skills/planning-sprints/SKILL.md"; then
  echo "FAIL: planning-sprints/SKILL.md missing scope sizing (SMALL/MEDIUM/LARGE)"
  ((errors+=1))
fi

# FR-11: Zone table corrected
if grep -q 'Read-only.*App zone' ".claude/skills/implementing-tasks/SKILL.md"; then
  echo "FAIL: implementing-tasks/SKILL.md still has Read-only App zone"
  ((errors+=1))
fi

# FR-11: CLI permissions section exists
if ! grep -q '<cli_tool_permissions>' ".claude/skills/implementing-tasks/SKILL.md"; then
  echo "FAIL: implementing-tasks/SKILL.md missing <cli_tool_permissions> section"
  ((errors+=1))
fi

echo "---"
if [ "$errors" -eq 0 ]; then
  echo "ALL SMOKE TESTS PASSED"
else
  echo "$errors TESTS FAILED"
  exit 1
fi
```

### Phase 2 Manual Tests

| Test | What | How |
|------|------|-----|
| Post-completion debrief fires | All 3 phase skills show debrief after save | Manual: run /plan through all phases, verify debrief appears |
| Steer prompt works | User can Continue, Adjust, or Stop | Manual: test each option |
| Adjust flow | Regenerates artifact, preserves context, re-debriefs | Manual: select Adjust, provide change, verify regeneration |
| Free-text-first flow | /plan shows description prompt, not archetype list | Manual: delete PRD, run /plan, verify free-text prompt |
| Short input reprompt | <10 char input triggers reprompt | Manual: enter "app" in /plan, verify reprompt |
| Archetype inference | Description with "REST API" infers rest-api archetype | Check NOTES.md for risk seeding; check archetype-inference.md log |
| Context files shortcut | "I have context files" routes to /plan-and-analyze | Manual: select option, verify routing |
| Sprint scope sizing | No "2.5 days" in sprint output | Run /sprint-plan, verify SMALL/MEDIUM/LARGE in output |
| CLI proactive usage | Agent runs `gh issue list` without asking | During /implement, verify agent queries GitHub directly |
| CLI safety | Agent asks before `gh pr create` | During /implement, verify confirmation prompt |

### Manual Verification Checklist

- [ ] Fresh /plan: preamble shown once, free-text prompt appears
- [ ] /plan with context: "I have context files" routes correctly
- [ ] Short description (<10 chars): reprompt fires
- [ ] After PRD creation: debrief with decisions/assumptions/tradeoff shown
- [ ] After SDD creation: debrief shown, "Continue" leads to sprint planning
- [ ] After Sprint creation: debrief shown, "Start building" option
- [ ] Sprint output uses SMALL/MEDIUM/LARGE, no "2.5 days"
- [ ] /feedback appears in "Stop here" option description
- [ ] No /feedback in post-mount, post-setup, or generic help
- [ ] archetype-inference.md created after /plan with description

---

## 6. Security Considerations

### SKILL.md Modification Safety

All Phase 2 changes are to prompt files (.md) in the System Zone (`.claude/`). These files:
- Are version-controlled (changes visible in PR diff)
- Don't execute code (they guide agent behavior)
- Don't access external systems
- Are reviewed by Bridgebuilder in the audit phase

### Zone Table Permission Change Risk

Changing App zone from "Read-only" to "Read/Write" in implementing-tasks SKILL.md:
- **Actual risk**: None — the skill already writes files; table just matches reality
- **Guard still active**: `team-role-guard-write.sh` hook enforces System Zone protection regardless of zone table text
- **No escalation**: Change doesn't affect discovery/architecture skills (they remain read-only for app code)

### CLI Permission Scope

The new `<cli_tool_permissions>` section explicitly distinguishes read vs write:
- Read-only operations (queries, status) — agent runs freely
- Write operations (push, deploy, install) — agent asks first
- This matches vanilla Claude Code behavior — we're removing Loa-specific over-restriction, not adding new permissions

---

## 7. Rollback Plan

All changes are to `.claude/` files (System Zone). If issues arise:

1. **Per-file rollback**: `git checkout main -- .claude/skills/{skill}/SKILL.md` reverts individual skills
2. **Full rollback**: `git checkout main -- .claude/` reverts all System Zone changes
3. **No state changes**: No `.loa.config.yaml` modifications, no data migrations
4. **Post-completion sections are additive**: Removing them restores pre-Phase-2 behavior (no debrief, agent proceeds silently)
