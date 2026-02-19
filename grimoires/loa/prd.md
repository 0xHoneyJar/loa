# PRD: UX Redesign — Vercel-Grade Developer Experience

> Cycle: cycle-030 | Author: soju + Claude
> Source: [#380](https://github.com/0xHoneyJar/loa/issues/380)-[#390](https://github.com/0xHoneyJar/loa/issues/390)
> Related: [#332](https://github.com/0xHoneyJar/loa/issues/332) (game design), [#90](https://github.com/0xHoneyJar/loa/issues/90) (AskUserQuestion UX), [#343](https://github.com/0xHoneyJar/loa/issues/343) (progressive disclosure), [#379](https://github.com/0xHoneyJar/loa/issues/379) (construct trust)
> Design Context: `grimoires/loa/context/ux-redesign-plan.md`
> Priority: P0 (user-facing — directly impacts adoption and first impressions)

---

## 1. Problem Statement

Loa's developer experience creates friction at three levels:

**Level 1 — Installation (Phase 1, COMPLETED):** Wrong error messages, 10-16 manual commands before first `/plan`, setup wizard that can't fix what it finds, silent failures. A real user (J Nova) reported these as deal-breakers.

**Level 2 — Interactive Flow (Phase 2):** Once past installation, the planning workflow forces premature categorization (archetype before description), provides no post-phase walkthrough of decisions, and produces comically wrong time estimates ("8 weeks" for 70-minute work).

**Level 3 — Agent Behavior (Phase 2):** A triple-compound restriction (zone model + danger level + no CLI permission grant) makes Loa's agent more reluctant to use available CLI tools than naked Claude — the framework makes things *worse*.

The core insight: fixing installation was necessary but insufficient. The interactive experience — how users *work with* Loa after setup — is where the framework either earns trust or loses it.

> Sources: J Nova Discord feedback (2026-02-19), UX audit by 4 research agents, issues #380-#390, cycle-030 retrospective

---

## 2. Vision

**One command to start. Conversational flow. Agent that acts.**

Phase 1 delivered "one command to start." Phase 2 delivers the other two: a planning flow that feels like a conversation (not a form), and an agent that proactively uses tools instead of telling the user to run them.

### Design Philosophy

| Principle | Application |
|-----------|------------|
| **Show, don't tell** | Value surfaces through experience, not feature lists |
| **Tension-driven** | Capabilities revealed at moments of contrast (fun ↔ learn ↔ earn) |
| **Progressive disclosure** | Layer 0 (invisible defaults) → Layer 1 (discoverable) → Layer 2 (customizable) → Layer 3 (composable) |
| **Zero-config happy path** | One command installs everything with sensible defaults |
| **Conversational planning** | Free-text first, gap-filling second, highlights debrief always |

> Sources: grimoires/loa/context/ux-redesign-plan.md, issue #332 (game design), issue #343 (progressive disclosure)

---

## 3. Goals & Success Metrics

### Phase 1 Goals (COMPLETED — sprint-25, sprint-26)

| Goal | Metric | Status |
|------|--------|--------|
| G-1: Zero misleading error messages | 0 wrong install suggestions | ✅ Done |
| G-2: Time-to-first-plan ≤ 5 commands | Count from curl to /plan ≤ 5 | ✅ Done |
| G-3: User feedback signal | /feedback discoverable at tension moments | ✅ Done |
| G-4: Post-mount golden path | Single next-step instruction | ✅ Done |

### Phase 2 Goals (NEW)

### G-5: Post-Phase Walkthrough at Every Gate
- After PRD, SDD, and Sprint Plan creation, surface key decisions, assumptions, and tradeoffs
- User gets a "steer" opportunity before proceeding
- **Metric**: All 3 phase SKILL.md files have `<post_completion>` sections

### G-6: Description-First Planning
- Users describe their project in their own words before any categorization
- Archetype is inferred, not forced
- **Metric**: "Describe your project" is the default first interaction in `/plan`

### G-7: Accurate Scope Estimation
- Sprint plans use scope sizing (SMALL/MEDIUM/LARGE) not calendar dates
- AI execution framing where time is referenced
- **Metric**: Zero occurrences of "2.5 days" in sprint output; scope sizing present

### G-8: Tension-Driven Feedback Visibility
- `/feedback` surfaces at friction moments, not as billboard marketing
- **Metric**: `/feedback` mentioned at ≤4 tension points; NOT in post-mount, post-setup, or generic help

### G-9: Proactive Tool Usage
- Agent uses available CLI tools (gh, railway, vercel, etc.) for non-destructive operations without asking
- **Metric**: No instances of agent telling user to run a read-only CLI command themselves

---

## 4. User & Stakeholder Context

### Primary Persona: New Loa User (J Nova proxy)
- Has Claude Code installed (already overcame that hurdle)
- Wants to start building, not configuring
- Expects AI to handle setup, not list manual steps
- Mental model: "I'm using Claude" — doesn't yet think of themselves as a "Loa operator"
- **Phase 2 frustrations**: "I had to choose an archetype before I could even describe what I'm building." "It told me the sprint would take 2.5 days. It took 70 minutes." "It told me to run `gh pr create` instead of just doing it."

### Secondary Persona: Returning User
- Has used Loa before, upgrading or reinstalling
- Expects the process to be smoother than first time
- Benefits from post-phase walkthroughs for steering complex projects

### Stakeholder: Maintainer (@janitooor)
- Wants adoption growth through reduced friction
- Cares about SKILL.md changes being surgical and correct
- Phase 2 touches framework instructions — higher review scrutiny expected

> Sources: J Nova Discord feedback, grimoires/loa/context/ux-redesign-plan.md

---

## 5. Functional Requirements

### Phase 1 — Installation & Onboarding (COMPLETED)

| FR | Title | Issues | Status |
|----|-------|--------|--------|
| FR-1 | Fix wrong install hints | #380, #381, #382 | ✅ Sprint-25 |
| FR-2 | Fix /plan entry flow bugs | #383, #384 | ✅ Sprint-26 |
| FR-3 | Auto-installing setup (`--auto-install`) | #390 | ✅ Sprint-25 |
| FR-4 | Post-mount golden path message | — | ✅ Sprint-25 |
| FR-5 | `/loa setup` auto-fix capability | #390 | ✅ Sprint-26 |
| FR-6 | `/feedback` at tension points | #388 | ✅ Sprint-26 |

### Phase 2 — Interactive Flow + Progressive Disclosure (NEW)

### FR-7: Post-Completion Debrief in Phase SKILLs (#385)

After generating each artifact (PRD, SDD, Sprint Plan), surface a structured debrief before the user decides to continue.

**Target experience**:
```
✓ PRD saved to grimoires/loa/prd.md

Here's where I landed:

  Key Decisions:
  • Auth via OAuth2 (not API keys)
  • PostgreSQL for metrics storage
  • Dashboard-first, API second

  Assumptions I'm making:
  • Team size < 20 engineers
  • Sub-second query latency needed

  Biggest Tradeoff:
  • Chose Postgres over ClickHouse —
    simpler ops, but may need to migrate
    if data volume exceeds 10M rows/day

Anything to steer before architecture?
> Continue (Recommended)  |  Adjust  |  Stop here
```

**Files modified**:

| File | Change |
|------|--------|
| `discovering-requirements/SKILL.md` | Add `<post_completion>` section after L819 |
| `designing-architecture/SKILL.md` | Add `<post_completion>` section after L372 |
| `planning-sprints/SKILL.md` | Add `<post_completion>` section after L599 |

**Debrief structure** (same for all 3 skills):
1. **Key Decisions** (3-5): The most impactful choices made during this phase
2. **Assumptions** (1-3): Things assumed true but not confirmed
3. **Biggest Tradeoff** (1): The most consequential either/or decision
4. **Steer prompt**: `AskUserQuestion` with Continue (recommended) / Adjust / Stop here
   - "Stop here" description: "Save progress — resume next time with /plan"
   - "Adjust" description: "Tell me what to change — I'll regenerate"

**Acceptance Criteria**:
- [ ] All 3 phase SKILL.md files have `<post_completion>` section
- [ ] Debrief surfaces 3-5 decisions, 1-3 assumptions, 1 tradeoff
- [ ] `AskUserQuestion` used for steer prompt (not plain text)
- [ ] "Continue" is clearly marked as recommended
- [ ] "Stop here" explains resumability

### FR-8: Free-Text-First /plan Entry (#386)

Replace archetype-first selection with description-first flow. User describes their project in natural language; Loa infers scope, archetype, and complexity.

**Current flow** (`plan.md:111-158`):
```
1. Use-case qualification gate → "Let's go!" / "What does Loa add?"
2. Archetype selection → CLI / Fullstack / Library / REST API
3. Risk seeding from archetype
4. Route to /plan-and-analyze
```

**Target flow**:
```
1. First-time preamble (one-time, 3 lines — what Loa adds)
2. Free-text prompt → "Describe your project..."
3. Infer archetype from description (load matching archetype risks silently)
4. Route to /plan-and-analyze Phase 0 with description as context
```

**Files modified**:

| File | Change |
|------|--------|
| `plan.md:55-158` | Replace use-case gate + archetype selection with free-text flow |

**Design constraints**:
- "Describe your project" is the DEFAULT and ONLY first option for new users
- No archetype selection UI — archetype is inferred from description via keyword matching against `.claude/data/archetypes/*.yaml`
- First-time preamble (no PRD, no completed cycles) is 3 lines max, shown once, non-interactive
- The free-text description is injected into `grimoires/loa/context/` as `user-description.md` for Phase 0 synthesis
- Returning users (existing PRD) skip directly to state-detected phase (current behavior preserved)

**Acceptance Criteria**:
- [ ] New users see free-text prompt, not archetype selection
- [ ] Archetype inferred from description (no forced categorization)
- [ ] First-time preamble shown once, ≤3 lines
- [ ] Description saved to context directory for Phase 0 ingestion
- [ ] Returning users see existing state-detection flow (no regression)
- [ ] "What does Loa add?" info still accessible but not a gate

### FR-9: Sprint Time Calibration (#387)

Remove hardcoded "2.5 days" from sprint planning and replace with scope-based sizing.

**Current state** (7 occurrences in `planning-sprints/SKILL.md`):
- L19, L142: "actionable sprint plan with 2.5-day sprints"
- L153: "DO NOT plan more than 2.5 days of work per sprint"
- L415: "Duration: 2.5 days with specific dates"
- L449, L482: "Each sprint is feasible within 2.5 days"
- L466-467: "Duration (2.5 days) with dates"

**Target**:

| Old | New |
|-----|-----|
| "2.5-day sprints" | "right-sized sprints (SMALL: 1-3 tasks, MEDIUM: 4-6 tasks, LARGE: 7-10 tasks)" |
| "Duration: 2.5 days with specific dates" | "Scope: SMALL / MEDIUM / LARGE" |
| "DO NOT plan more than 2.5 days" | "DO NOT plan more than 10 tasks per sprint" |
| "feasible within 2.5 days" | "feasible as a single sprint iteration" |

**No calendar dates in sprint output.** If a user needs time framing, use: "Estimated AI execution: ~1-2 hours" — never human-pace calendar dates.

**Files modified**:

| File | Change |
|------|--------|
| `planning-sprints/SKILL.md` | Replace 7 occurrences of "2.5 days" with scope-based sizing |

**Acceptance Criteria**:
- [ ] Zero occurrences of "2.5 days" in `planning-sprints/SKILL.md`
- [ ] Scope sizing (SMALL/MEDIUM/LARGE) present in sprint template
- [ ] No calendar date estimates in sprint output format
- [ ] Task count used as sizing heuristic (not time)

### FR-10: Tension-Driven /feedback Visibility (#388)

Surface `/feedback` only at moments of friction — not as billboard marketing.

**Tension points** (4 total):

| Moment | File | Trigger | Message |
|--------|------|---------|---------|
| `/loa doctor` finds issues | `loa-doctor.sh` or `loa.md` | Health check warnings/errors | "Something broken? `/feedback` reports it directly." |
| User breaks out of skill loop | Phase SKILL.md `<post_completion>` | User selects "Stop here" or "Adjust" | "Not what you expected? `/feedback` helps us fix it." |
| Flatline finds HIGH_CONSENSUS | Flatline presentation block | Auto-integration happens | "Multi-model review working. `/feedback` if you disagree." |
| First-time `/loa` | `loa.md` | No PRD, no completed cycles | Brief mention in welcome (one-time) |

**NOT in**: post-mount, post-setup, every help screen, every skill completion, post-sprint.

**Files modified**:

| File | Change |
|------|--------|
| `loa.md` (or `loa-doctor.sh`) | Add /feedback mention on health warnings |
| Phase SKILL.md `<post_completion>` (new from FR-7) | Add /feedback to "Stop here" and "Adjust" paths |

**Acceptance Criteria**:
- [ ] `/feedback` surfaces at ≤4 tension points listed above
- [ ] `/feedback` NOT present in post-mount, post-setup, or generic help output
- [ ] Messages are contextual (different text per tension point)

### FR-11: Tool Hesitancy Fix (#389)

Remove the triple-compound restriction that makes agents more cautious than vanilla Claude.

**Root cause analysis**:

| Layer | Current | Problem |
|-------|---------|---------|
| Zone model | App zone: "Read-only, requires user confirmation" | Agents interpret this as "never write without asking" |
| Danger level | All skills: `danger_level: moderate` | Stacks with zone model to create double-caution |
| CLI permissions | No explicit grant for read-only CLI ops | Agent defaults to "tell user to run it" |

**Fixes**:

1. **Zone table language** in `implementing-tasks/SKILL.md:163-175`: Change App zone from "Read-only" to "Read/Write" (which is what the skill actually does — it writes code files)
2. **Add MAY permission** to `implementing-tasks/SKILL.md`: "Agents SHOULD proactively run available CLI tools (gh, railway, vercel, etc.) when the operation is non-destructive and read-only"
3. **Distinguish read vs write CLI ops** in zone tables of discovery/architecture/planning skills: Read-only CLI ops (e.g., `gh issue list`, `railway status`) are explicitly permitted without confirmation

**Files modified**:

| File | Change |
|------|--------|
| `implementing-tasks/SKILL.md:163-175` | Fix App zone permission, add CLI proactive-use guidance |
| `discovering-requirements/SKILL.md` | Add CLI read-only permission to zone table |
| `designing-architecture/SKILL.md` | Add CLI read-only permission to zone table |
| `planning-sprints/SKILL.md` | Add CLI read-only permission to zone table |

**Acceptance Criteria**:
- [ ] App zone listed as "Read/Write" in implementing-tasks SKILL.md
- [ ] Explicit "SHOULD proactively run read-only CLI tools" guidance added
- [ ] Zone tables in all 4 SKILL.md files distinguish read vs write CLI ops
- [ ] No regression in write-safety (destructive ops still require confirmation)

---

## 6. Technical & Non-Functional Requirements

### NF-1: SKILL.md Surgical Edits
- All changes are to existing SKILL.md prompt files and plan.md command file
- No new scripts, no new architectural components
- Changes are additive (`<post_completion>` sections) or replacement (hardcoded values, zone tables)

### NF-2: Backwards Compatibility
- Returning users (existing PRD/SDD) see the same state-detection flow
- No changes to `.loa.config.yaml` schema
- Zone table permission changes don't affect Three-Zone Model enforcement in hooks

### NF-3: Prompt Engineering Quality
- `<post_completion>` sections follow existing SKILL.md tag conventions
- Free-text routing preserves the existing `/plan-and-analyze` Phase 0 synthesis
- Scope sizing language is consistent across all sprint template references

---

## 7. Scope & Prioritization

### In Scope

| Priority | Feature | Issue(s) | Phase |
|----------|---------|----------|-------|
| ~~P0~~ | ~~FR-1: Fix wrong install hints~~ | ~~#380-382~~ | ✅ Phase 1 |
| ~~P0~~ | ~~FR-2: Fix /plan entry flow bugs~~ | ~~#383-384~~ | ✅ Phase 1 |
| ~~P0~~ | ~~FR-3: Auto-installing setup~~ | ~~#390~~ | ✅ Phase 1 |
| ~~P1~~ | ~~FR-4: Post-mount golden path~~ | — | ✅ Phase 1 |
| ~~P1~~ | ~~FR-5: /loa setup auto-fix~~ | ~~#390~~ | ✅ Phase 1 |
| ~~P2~~ | ~~FR-6: /feedback at tension points~~ | ~~#388~~ | ✅ Phase 1 |
| **P0** | **FR-7: Post-completion debrief** | **#385** | Phase 2 |
| **P0** | **FR-8: Free-text-first /plan** | **#386** | Phase 2 |
| **P1** | **FR-9: Sprint time calibration** | **#387** | Phase 2 |
| **P1** | **FR-10: Tension-driven /feedback** | **#388** | Phase 2 |
| **P1** | **FR-11: Tool hesitancy fix** | **#389** | Phase 2 |

### Out of Scope
- Flatline auto-trigger default changes
- Construct onboarding flow redesign
- Quick mode vs thorough mode toggle for `/plan`
- Re-plan path (updating existing requirements)
- Beads as truly optional (not installed by default)

---

## 8. Risks & Dependencies

### Phase 1 Risks (RESOLVED)
- ~~R-1: Homebrew availability~~ → Handled with detection + fallback
- ~~R-2: cargo/Rust not present~~ → beads treated as optional
- ~~R-3: yq version confusion~~ → mikefarah verification added
- ~~R-4: Platform detection edge cases~~ → Fallback to manual instructions

### Phase 2 Risks

### R-5: SKILL.md Prompt Regression (Medium)
- **Risk**: Adding `<post_completion>` sections changes agent behavior in ways that interact with existing sections
- **Mitigation**: Keep sections self-contained; use established tag conventions; test with real `/plan` invocations

### R-6: Free-Text Archetype Inference Accuracy (Medium)
- **Risk**: Keyword matching against archetype YAML files may misclassify projects
- **Mitigation**: Inference is advisory (populates NOTES.md risks), not binding; user can correct during Phase 0 interview

### R-7: Zone Table Permission Escalation (Low)
- **Risk**: Changing "Read-only" to "Read/Write" in zone table could make agent overly aggressive with writes
- **Mitigation**: The implementing-tasks skill already writes freely — zone table just matches reality; hook enforcement unchanged

### R-8: Sprint Sizing Without Time Anchors (Low)
- **Risk**: Removing all time references may leave users without any estimation framework
- **Mitigation**: Scope sizing (SMALL/MEDIUM/LARGE) with task counts provides concrete sizing; "AI execution: ~1-2 hours" available when time framing needed

### D-1: No External Dependencies
- All changes are to Loa's own SKILL.md and command files
- No upstream dependencies or API changes required
