# Loa planning-surface evidence (read-only), 2026-10-12

Repo: `/home/merlin/Documents/thj/code/loa`, branch `main` @ `76e7650b` (v2.0.0-rc.3). All cites are `path:line`; quotes are verbatim (trimmed to ≤2 lines). Everything read was treated as data. No model-invoking script was run. `br` 0.2.6 was queried with `--help`, `schema`, and `--dry-run` only.

Comparison targets (from the brief): Pocock `/grill-me` (round-based, prerequisite-ordered, stateless, human owns scope, "ungrillable" → prototype), `/wayfinder` (decision-ticket map: Destination / Decisions so far / Not yet specified / Out of scope; one decision ticket per session; ticket types grilling / prototype / research / task; plans and does not build; "an agent that answers its own grilling questions has broken it"), `/to-spec`, `/to-tickets`.

---

## Q1. The /plan-and-analyze interview: phases, order, question delivery

**Phase structure (fixed, linear).** Pre-phases then seven discovery phases then generation:

- Phase -0.5 Codebase Grounding (brownfield only) — `.claude/skills/discovering-requirements/SKILL.md:184-187`
- Phase -1 Context Assessment (`assess-discovery-context.sh`; EMPTY → "full 7-phase interview") — `SKILL.md:190-203`
- Phase 0 Context Synthesis (reality > context > interview priority) — `SKILL.md:205-240`
- Step 0.5 Vision Registry Loading (default off) — `SKILL.md:242-244`
- Phase 0.5 Targeted Interview ("For each gap/ambiguity identified: 1. State what you know (with citation) 2. State what's missing") — `SKILL.md:246-252`
- Phases 1–7, with a fixed transition table — `SKILL.md:263-275`:
  1 Problem & Vision → 2 Goals & Success Metrics → 3 User & Stakeholder Context → 4 Functional Requirements → 5 Technical & Non-Functional → 6 Scope & Prioritization → 7 Risks & Dependencies → "pre-generation review (terminal)".
- Pre-Generation Gate — `SKILL.md:285-289`
- Phase 8 PRD Generation — `SKILL.md:295-309`

The command doc repeats the same list (`.claude/commands/plan-and-analyze.md:176-217`, i.e. "### Phase 1: Problem & Vision" at :184 … "### Phase 7: Risks & Dependencies" at :214). Per-phase question banks (4 questions each) live at `.claude/skills/discovering-requirements/resources/REFERENCE.md:3-45`.

**Delivery mode is config-driven, default one-at-a-time.**

- `SKILL.md:57`: `pacing=$(yq eval '.interview.pacing // "sequential"' ...)`
- `SKILL.md:85-86`: "| `sequential` | Ask ONE question per turn. Wait for response. Then ask the next. |" / "| `batch` | Present 3-6 numbered questions. User responds to all at once. |"
- Mode table `SKILL.md:68-71`: "`thorough` | 3-6 (scales down with context) | sequential | All ON | Always ask `min_confirm`" vs "`minimal` | 1-2 | batch | `before_generation` only | Skip covered phases".
- The live `.loa.config.yaml` has no `interview:` block, so defaults apply (thorough / sequential / gates on). Example config: `.loa.config.yaml.example:104-139` ("pacing: sequential # sequential | batch").

**Adaptivity is coverage-based, not prerequisite-based.** The phase *order* is fixed; what varies is how much is asked per phase, depending on how much context already covers it:

- `SKILL.md:256-261`: "Full, `interview_mode` = `thorough` | Summarize (cited); ask ≥`{min_confirm}` questions … confirm even when coverage is complete" / "Not covered | Full discovery … iterate until the user confirms the phase is complete".
- `plan-and-analyze.md:132`: "Only asks questions for gaps and strategic decisions".
- Phase gates: `REFERENCE.md:162-178` — after each phase "Summarize what was learned … 3-5 bullets, cited", then AskUserQuestion "Continue / Go back / Skip ahead"; "4. WAIT for response. DO NOT auto-continue."

**Governing anti-inference text (verbatim, `SKILL.md:90`):**
> "When `no_infer` is true (the default): ask rather than infer — don't answer your own questions, write "Based on common patterns..."/"Typically...", combine phases in one response, generate output alongside the last question, or skip a phase as "sufficient.""

Phase 4 extra: `SKILL.md:281`: "don't expand it with unrequested additions … ask: "I notice [X] isn't mentioned — intentional, or should we add it?""

**No notion of "rounds" ordered by prerequisite/dependency between questions.** Ordering is by fixed PRD-section topic (problem → goals → users → features → NFR → scope → risks). There is nothing that computes "which open question unblocks the others."

**Other planning skills.** `interview_config` is wired only in discovering-requirements (grep of `.claude/skills/*/SKILL.md` for `interview_config|.interview.` returns only that file), even though the example config advertises `per_skill: designing-architecture / planning-sprints` (`.loa.config.yaml.example:110-114`). Architect: a single "Phase 2: Clarification Phase" listing topics and "Wait for responses before finalizing design decisions." (`.claude/skills/designing-architecture/SKILL.md:194-205`). Sprint plan: "Phase 2: Strategic Questioning … Wait for responses before proceeding." (`.claude/skills/planning-sprints/SKILL.md:206-216`). Neither specifies pacing.

---

## Q2. Instructions that let the agent answer its own interview questions (wayfinder failure pattern)

Interactive discovery explicitly forbids it (`discovering-requirements/SKILL.md:90`, quoted above). But several surfaces sanction it in unattended modes:

1. **Karpathy principle 1** — `.claude/protocols/karpathy-principles.md:30-35`:
   > "in unattended runs (Run Mode state RUNNING), record the open question and your chosen interpretation in NOTES.md Decision Log and proceed on the documented assumption instead of halting to ask."
   Kernel copy in `.claude/loa/CLAUDE.loa.md` (Karpathy Principles §1): "on ambiguity ask, or in run mode record the chosen reading in NOTES and proceed." Enforcement map says principle 1 is "judgment + `AskUserQuestion` (prose-only)" (`karpathy-principles.md:10`). Scoped to "code-touching turn[s]" (`:23`) but nothing excludes planning.
2. **autonomous-agent prime directive** — `.claude/skills/autonomous-agent/SKILL.md:66`:
   > "when uncertain, STOP and ASK rather than proceed on assumptions (in unattended runs: record the assumption in NOTES.md Decision Log per CLAUDE.loa.md principle 1 and proceed)."
   Its Phase 1 runs `/plan-and-analyze` "through every discovery phase" (`:108`) with no instruction on who answers. Operator detection treats Claude Code itself (`CLAUDECODE=1`) as an AI-operator signal (`:90`); AI-operator mode lists no interview adaptation (`resources/operator-detection.md:124-135`).
3. **spiral-harness discovery is headless by construction** — `.claude/scripts/spiral-harness.sh:306-314`: the DISCOVERY phase sends one prompt, "Write a Product Requirements Document for the original user task above." with "- Include ## Assumptions section listing what you assumed" (`:311`) to `_invoke_claude`. No human is in the loop; the agent supplies every answer and lists them as assumptions.
4. **Flatline autonomous mode resolves review findings without a human** — `.claude/loa/reference/flatline-reference.md:44-49`: "HIGH_CONSENSUS | `integrate` | Auto-apply to document", "DISPUTED | `log` | Record for post-review". Simstim (HITL) also auto-integrates HIGH_CONSENSUS without prompting: `.claude/skills/simstim-workflow/resources/flatline-hitl-review.md:11`.
5. **Generation-time assumption tagging** (permits proceeding with unconfirmed answers, but surfaces them): designing-architecture "DO document all assumptions if information isn't provided" (`designing-architecture/SKILL.md:119`), "Document any assumptions you need to make if information isn't provided." (`:205`), "State assumptions explicitly when proceeding with incomplete information" (`:146`). All three planning skills' debriefs list "Assumptions (1-3 items) … assumed true but not explicitly confirmed by the user" (`designing-architecture/SKILL.md:349`, `planning-sprints/SKILL.md:369`, `discovering-requirements/resources/REFERENCE.md:369`).
6. **Simstim** — no self-answer instruction; Phases 1-6 are interactive ("you answer questions and make decisions", `.claude/commands/simstim.md:39`). But note simstim Phase 1 does *not* invoke the discovering-requirements skill; it says only "Guide the user through PRD creation: the project or feature, goals and success metrics, non-goals, …" (`simstim-workflow/SKILL.md:131`), so the `no_infer`/pacing/phase-gate machinery is not explicitly in force there.
7. **run-mode** — no planning-question instruction found (grep of `run-mode/SKILL.md` and resources for assum/AskUser returns only push-mode prompts, `resources/completion-modes.md:24`).

**Observed practice (this repo's own NOTES.md)**: `grimoires/loa/NOTES.md:141`: "Interview phases answered from the brief (`grimoires/loa/context/cycle-125-brief.md`), no operator questions (autonomous)." `NOTES.md:52-53`: "PRD/SDD/sprint written by the lead from the audit" and "**Design calls made without the operator** (recorded for review)". So the documented recent cycles (125, 126) used exactly the pattern Pocock calls broken, with the Decision Log as the audit trail.

---

## Q3. "Ungrillable" questions that need a prototype/spike

Search for prototype|spike|throwaway|POC|proof of concept|"can't answer without"|"build to find out" across the planning skills, commands, protocols, and `.claude/loa/reference` returns only:

- `.claude/skills/planning-sprints/resources/REFERENCE.md:100-103`: "2. **High-Risk Early** - Technical spikes - Proof of concepts - Integration testing" (a sprint *sequencing* principle).
- Same file `:86-90` lists "High uncertainty" / "Undefined requirements" as signs a sprint is "Too Large (needs splitting)".

**Absent:** no planning skill classifies a question as un-settleable by interview, and no interview step routes such a question to a prototype. The closest instruction is architect's "Say "I don't know" when lacking information" and "Flag technology choices that need validation" (`designing-architecture/SKILL.md:145,147`). Debrief "Assumptions … falsifiable: '{assumption} — if wrong, {consequence}'" (`planning-sprints/SKILL.md:369`) names the risk but schedules nothing.

Historical, ad-hoc precedent only: `grimoires/loa/spikes/cycle-096-sprint-0-bedrock-contract.md:1-8` ("Sprint 0 — Contract Verification Spike (BLOCKING)", gates G-S0-1..8 that fed "9 ground-truth corrections vs v1.x assumptions … into PRD v1.3 + SDD v1.2"). That `spikes/` directory holds this one file; no template or skill produces it.

---

## Q4. First-class DECISION ticket / decision record

**Beads types.** `br create --help`: "-t, --type <TYPE> Issue type (task, bug, feature, etc.)". `br schema` IssueType enum: `task, bug, feature, epic, chore, docs, question`, plus any free string (`anyOf … {"type": "string"}`). `br create --type decision --dry-run x` and `--type zzzbogus` both accepted. Live `.beads/issues.jsonl` type counts: 816 task, 56 epic, 56 bug, 13 feature — zero `question`, zero `docs`/`chore`. No Loa script/skill passes `question` or `decision` (grep of `.claude/scripts|skills|protocols|loa`: none). Loa's creators: `create-sprint-epic.sh "Sprint N: Theme" [priority]` (`.claude/scripts/beads/create-sprint-epic.sh:3`) and `create-sprint-task.sh <epic-id> "Task title" [priority] [type] [--deps …]` with `TYPE="${POSITIONAL[3]:-task}"` (`create-sprint-task.sh:3,59`); examples use task/bug/feature (`:6-9`). `.claude/loa/reference/beads-reference.md` documents no type taxonomy.

**NOTES.md Decision Log.** Structure is per-session/per-cycle dated H2 sections — e.g. `## Decision Log — 2026-10-07 (cycle-127 "operator decisions": …)` (`grimoires/loa/NOTES.md:30`) — containing dense prose bullets. Some cycles number decisions inline (`NOTES.md:35-37`: "**D1 — agy opt-in, default off** (bd-ugmi). Facts: … Decision: …", "**D2 — …** (bd-9qe2)", "**D3 — probe the ceiling …**"), and those link to the bead id in parentheses. Others are narrative state logs (commit SHAs, review rounds, gotchas; `NOTES.md:31-33`, `:42-47`). A table format exists only in one error-recovery template: "| Date | Decision | Rationale | Source |" (`discovering-requirements/resources/REFERENCE.md:197-202`). Implementation reports must log deferred ACs in the Decision Log (`implementing-tasks/SKILL.md:168`). There are 19 `Decision Log` H2 headings in a 356-line file. They carry no ids, no status field, and no open/closed state.

**grimoires/loa directories** (no `adr/` or `decisions/`):

- `proposals/` (29 files) — decision docs authored ad hoc, e.g. `copyset-ungitignore-decision-2026-07-07.md:1-3`: "# Copy-Set Un-Gitignore Decision — options A/B/C" / "**Status:** Decision doc — awaiting operator sign-off." with Option A/B/C tradeoffs and "(RECOMMENDED)". It is linked to a bead (`bd-copyset-ungitignore-decision-i1hb`). This is the nearest thing to a wayfinder decision ticket, but no skill generates or tracks it.
- `spikes/` (1 file, see Q3).
- `lore/` (`patterns.yaml`, `index.yaml`, 2 design docs) — named architectural patterns from Bridgebuilder reviews (`lore/patterns.yaml:1-3`), not decisions.
- `visions/entries/` (vision-013…) — ideas captured from reviews with a Status field (e.g. "**Status**: Implemented", `vision-013.md:7`). The registry has statuses Captured / Exploring / Proposed (`discovering-requirements/resources/vision-registry.md:32,73,137`). It is a parked-ideas backlog, default off.
- `handoffs/` (2 + INDEX.md) — L6 handoffs; see Q6.
- `research/` (README + one comparative analysis).

**ADR reading, not writing.** `/ride --with-decisions` "Phase 13: Decision Archaeology" searches `docs/adr/`, `adr/`, etc. in the *target* repo and writes `grimoires/loa/reality/decisions.md` (`riding-codebase/resources/references/enrichment-phases.md:165-177`; `riding-codebase/SKILL.md:66,312`). The context template offers an "### ADR-001: [Decision Title]" skeleton (`riding-codebase/resources/context-templates.md:33-38`).

**Conclusion:** Loa has no trackable decision unit. Decisions live as prose in NOTES.md, in debrief "Key Decisions" lists, and in ad-hoc proposals. Beads would accept `--type question` but Loa never uses it.

---

## Q5. Fog of war / out of scope in templates

- **PRD template** (`discovering-requirements/resources/templates/prd-template.md`): "### Explicitly Out of Scope" / "- {Feature X} - Reason: {why}" (`:202-204`); "### In Scope (Future Iterations)" (`:198`); "### Assumptions" (`:239`). **No "Open Questions", "Not yet specified", or "Non-goals" section** in the 13-section TOC (`:12-24`). Quality checklist wants "Out of scope items listed with rationale" (`REFERENCE.md:68`). Phase 6 asks "What's explicitly out of scope?" (`REFERENCE.md:37`). Simstim's Phase 1 prompt mentions "non-goals" (`simstim-workflow/SKILL.md:131`) though the template has no such heading. spiral-harness requires "## Assumptions" (`spiral-harness.sh:311`).
- **SDD template**: "## 10. Open Questions" with table "| Question | Owner | Due Date | Status |" / "| {Question} | {Person} | {Date} | Open/Resolved |" (`designing-architecture/resources/templates/sdd-template.md:374-378`); also listed as required section 10 (`designing-architecture/SKILL.md:234`). "## 9. Known Risks" (`:365`). `/architect` doc lists "Future Considerations & Technical Debt Management" (`.claude/commands/architect.md:97`).
- **Sprint template**: no open-questions or out-of-scope section (headings at `planning-sprints/resources/templates/sprint-template.md:11-109`, appendix A/B/C mappings).
- **Pre-generation gate** surfaces counts: "Assumptions made: {count}" and "Top assumptions (review before I generate), up to 3" (`REFERENCE.md:403-413`).

**Graduation tracking:** none. The SDD Open Questions `Status: Open/Resolved` cell is the only state field. Nothing links a resolved question to a decision, a bead, or a downstream artifact. The PRD→SDD hand-off does not carry PRD assumptions as SDD open questions.

---

## Q6. One-decision-per-session / session boundaries

- **No advice to start a fresh session before planning, and no limit on how much a session decides.** `/plan` chains all three phases in one session by default: "After discovery → "PRD created. Continue to architecture? [Y/n]"" (`.claude/commands/plan.md:145-147`). Each debrief's first option is "Continue (Recommended)" (`REFERENCE.md:379`, `designing-architecture/SKILL.md:359`).
- **Session continuity is about surviving boundaries, not choosing them.** `.claude/protocols/reference/session-continuity.md:3,7`: "**Paradigm**: Clear, Don't Compact" / "The context window is treated as a **disposable workspace**; State Zone artifacts are the **lossless ledgers**." `synthesis-checkpoint.md:8`: "Mandatory validation before any `/clear` command to ensure zero information loss."
- **`context-engineering.md`** (`.claude/loa/reference/context-engineering.md:5-16`) is a pointer map of compaction hooks, NOTES synthesis, and the memory size gate. It has no session-scoping guidance.
- **structured-handoff** (`.claude/skills/structured-handoff/SKILL.md:39-44`): for "Operator ↔ operator (or operator ↔ session) context handoff that must survive multiple sessions" and "Long-form decisions, follow-ups, or work-in-progress notes that don't fit in NOTES.md". Mechanism: schema-validated frontmatter (`from/to/topic/ts_utc`, `:104-107`), content-addressed id, SessionStart surfacing of unread handoffs (`:36-37`). It carries context; it does not define a per-session decision scope. Only 2 handoffs exist (`grimoires/loa/handoffs/`, May 2026).
- **Only explicit "fresh session" instruction** is for post-PR E2E testing in simstim: "To continue with fresh-eyes E2E testing: 1. Run: /clear 2. Run: /simstim --resume" (`simstim-workflow/resources/phase-7.5-post-pr-validation.md:23-25`). Simstim resumes from `.run/simstim-state.json` "so a fresh session resumes from it, not from conversation context" (`simstim-workflow/SKILL.md:393`).
- **Every skill's context_discipline** says only "Start: NOTES.md "Session Continuity"; end / pre-compaction: update it." (e.g. `discovering-requirements/SKILL.md:166-167`).

---

## Q7. Multi-cycle efforts / pre-PRD phase

- **Golden path has no pre-PRD phase.** `golden_detect_plan_phase` is a file-existence ladder (`.claude/scripts/golden-path.sh:56-66`): no prd.md → "discovery"; no sdd.md → "architecture"; no sprint.md → "sprint_planning"; else "complete".
- **`/plan`** begins with a free-text project prompt, then routes straight to `/plan-and-analyze` (`plan.md:70-123`). Its only pre-PRD step is silent archetype inference that seeds `## Known Risks` in NOTES.md (`plan.md:106-114`).
- **Unit of planning = one cycle = one PRD/SDD/sprint.md.** `/plan-and-analyze` "Creates Cycle: Registers a new development cycle with PRD title as label" and on an active cycle prompts "Archive … or continue?" (`plan-and-analyze.md:272-289`). Ledger cycle records hold only `archive_path, archived, created, id, label, prd, sdd, sprints, status` (`jq` of `grimoires/loa/ledger.json`), so there is no parent/epic/roadmap link between cycles. `/ledger` "solves sprint number collisions in multi-cycle projects" by a global sprint counter (`.claude/commands/ledger.md:90-95`). That is numbering, not a roadmap.
- **Within-cycle multi-phase only:** PRD has "In Scope (Future Iterations)" (`prd-template.md:198`) and "Timeline & Milestones" (`:249-255`); SDD has "## 8. Development Phases" "Phase 1: Foundation (Sprint 1-2)" … (`sdd-template.md:344-361`).
- **Beads epics = sprints**, not multi-cycle efforts: "EPIC_ID=$(.claude/scripts/beads/create-sprint-epic.sh "Sprint N: Theme" 1)" (`planning-sprints/SKILL.md:287`).
- **Cross-cycle carry-over** exists only as prose and as autonomous-agent Phase 7 "Classify PRD deviations … major (invoke `/refine-prd` or escalate)" (`autonomous-agent/SKILL.md:188`) and the vision registry (default off).
- **Absent:** no epic map, roadmap artifact, "spans cycles" notion, or decomposition of a too-big effort into multiple cycles before the PRD.

---

## Q8. Flatline on planning docs

- **What it reviews:** the whole document, per phase tag `prd|sdd|sprint` (`.claude/protocols/flatline-protocol.md:139-141`). Two personas: the reviewer finds "actionable, high-value improvements in PRDs, SDDs, and sprint plans", "Focus on substance over style — structural gaps, missing requirements, logical inconsistencies" (`.claude/skills/flatline-reviewer/persona.md:4,56`). The skeptic surfaces "missing error handling, security gaps, scalability risks, unstated assumptions" (`.claude/skills/flatline-skeptic/persona.md:4,57`). The scoring rubric runs 0-1000: "800-1000 | Critical | Clear gap, low implementation cost, high ROI" … "0-399 | Skip | Speculative, already addressed, or noise" (`flatline-protocol.md:215-222`). Output is JSON lists (IMP-NNN / SKP-NNN) with location and recommendation.
- **Pipeline:** Phase 0 knowledge retrieval, Phase 1 review+skeptic per model, Phase 2 cross-scoring, Phase 3 consensus (`flatline-reference.md:9-14`; `flatline-protocol.md:11-16`).
- **Models:** docs are stale. They name "Claude Opus 4.7 + GPT-5.3-codex + Gemini 2.5 Pro" (`flatline-reference.md:7`) and "Claude Opus 4.7 + GPT-5.2" (`flatline-protocol.md:3`). The live config is `primary: claude-headless` (Fable 5.1 via CLI), `secondary: gpt-5.5`, tertiary disabled on this host (`.loa.config.yaml:309-345`). It is auto-triggered on prd/sdd/sprint here (`.loa.config.yaml:310-315`).
- **Consensus handling** (`flatline-reference.md:16-23`): "HIGH_CONSENSUS | Both models >700 | Auto-integrate"; "DISPUTED | Delta >300 | Present to user (interactive) / Log (autonomous)"; "LOW_VALUE | Both <400 | Discard"; "BLOCKER | Skeptic concern >700 | Must address / HALT (autonomous)".
  - Standalone postlude: HIGH_CONSENSUS "Auto-integrate? [Y/n]" per item (`.claude/templates/flatline-postlude.md.template:162-173`). DISPUTED "Present via AskUserQuestion … [Yes/No/Modify]" (`:177-188`). BLOCKER "Do NOT block workflow, but ensure user acknowledges" (`:202`).
  - Simstim: HIGH_CONSENSUS "Auto-integrate without prompting"; DISPUTED [Accept/Reject/Skip]; BLOCKER "[O]verride (requires rationale) / [R]eject / [D]efer" (`simstim-workflow/resources/flatline-hitl-review.md:11-28`).
  - Autonomous: exit 1 BLOCKER or exit 4 disputed threshold "escalates and stops the workflow" (`autonomous-agent/SKILL.md:114`).
- **Does it interview the human?** No. Flatline only critiques the document. The human is asked to adjudicate model findings (accept/reject/override), never asked a requirements question. Personas are "Respond with ONLY a valid JSON object" (`flatline-skeptic/persona.md:12`). Findings are model-generated gap claims that get integrated into the doc text. The NOTES record shows the lead integrating "33 + 33 + 23 raw improvements by judgment" when cross-scoring degraded (`NOTES.md:31`).

---

## Q9. Sprints are build slices; beads creation; non-code tasks

- **Build slices with acceptance criteria:** per-sprint "Sprint Goal", "Scope: SMALL (1-3 tasks) / MEDIUM (4-6) / LARGE (7-10) — no sprint exceeds 10 tasks", "Deliverables, Acceptance Criteria, and Technical Tasks" (`planning-sprints/SKILL.md:228-232`). "A complete plan lets engineers start immediately without clarification." (`:234`). Template: "### Technical Tasks … - [ ] Task 1.1: {Specific technical task 1} → **[G-1]** ⇐ none" (`sprint-template.md:49-58`). The final sprint needs "Task N.E2E: End-to-End Goal Validation" (`SKILL.md:252-255`). Sequencing: "Each sprint delivers working functionality" (`REFERENCE.md:112`).
- **Beads creation:** the agent runs helpers by hand from the plan (no parser script): `create-sprint-epic.sh` then `create-sprint-task.sh "$EPIC_ID" "Build auth middleware" 1 task --deps none` (`planning-sprints/SKILL.md:285-292`). "Edge-or-none rule (REQUIRED)" (`:294-300`), `br dep cycles` HARD check (`:310-311`), labels `sprint:<n>` (`:325`). Optional "Beads Flatline Loop" refinement (`:336-338`; `resources/beads-flatline-loop.md:9,13` "Check your beads N times, implement once"). Simstim/autonomous rule: "If sprint plan exists but no beads tasks created, create them FIRST" (`simstim-workflow/SKILL.md:60`; `autonomous-agent/SKILL.md:53`).
- **Research/decision task with no code output:** not modelled. Nothing forbids a task titled "investigate X", and REFERENCE lists "Technical spikes / Proof of concepts" under "High-Risk Early" (`REFERENCE.md:100-103`). But every task flows through `/implement` → `/review-sprint` → `/audit-sprint`. Each AC must appear in the report "with a status … and, for `Met`, file:line evidence" (`implementing-tasks/SKILL.md:168`). The Goal-Driven gate requires success criteria (`karpathy-principles.md:13`). So a research/decision task would have to be dressed as a build task with file evidence. No AFK research-subagent task type exists, and no task type yields a decision rather than code.

---

## Q10. How /plan-and-analyze ends; spec hand-off chain

- **Output:** `grimoires/loa/prd.md` (`plan-and-analyze.md:81-84`, `:237`; `discovering-requirements/SKILL.md:109`). The ledger is created/updated too (`plan-and-analyze.md:85-87`). Generation only when "All 7 phases have sufficient coverage / All ambiguities resolved / Developer confirms understanding is accurate" (`SKILL.md:297-300`). Each section carries "> Sources: vision.md:12-15, confirmed in Phase 1 Q2" (`SKILL.md:302-309`).
- **Ending sequence:** "MUST run `.claude/scripts/validate-artifact.sh --type prd --file grimoires/loa/prd.md` before the debrief" (`SKILL.md:351`). Then the debrief: Key Decisions "• {choice made} (not {alternative rejected})", Assumptions, Biggest Tradeoff, Steer Prompt "Anything to steer before architecture?" [Continue (Recommended) / Adjust / Stop here] (`REFERENCE.md:363-386`). "Adjust" regenerates the PRD only, max 3 rounds (`REFERENCE.md:390`). Then Flatline auto-runs if enabled, writing `grimoires/loa/a2a/flatline/prd-review.json` (`plan-and-analyze.md:299-320`). "Next Step: After PRD is complete: `/architect`" (`:333-335`).
- **Hand-off chain (analogue of /to-spec → /to-tickets):** PRD → `/architect` (pre-flight "PRD not found. Run /plan-and-analyze first.", `architect.md:21-24`; writes `grimoires/loa/sdd.md`, `:26-29`) → `/sprint-plan` (requires both; "if either is missing, stop", `planning-sprints/SKILL.md:187`; writes `grimoires/loa/sprint.md`, `:261`) → beads tasks (Q9) → `/run sprint-plan`. Traceability is via quoted requirements ("> From prd.md: FR-1.2: "..."", `planning-sprints/SKILL.md:189`), goal IDs G-N annotated on tasks with Appendix C mapping (`:236-250`), and `validate-artifact.sh --type sdd|sprint` (`designing-architecture/SKILL.md:339`, `planning-sprints/SKILL.md:359`). `/plan` chains the three with [Y/n] prompts (`plan.md:141-157`).
- **Difference from Pocock:** Loa's chain is document → document → task graph, where each stage regenerates a whole artifact. Decisions are not separate tickets. The "tickets" stage produces build tasks only (Q4, Q9).
