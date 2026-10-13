# Proposals: what Loa should take from Pocock's skills, and what it should not

**Date**: 2026-10-12. Companion to `comparison.md` (same evidence base, same cite tags `P:` / `W:` / `L:`). Planning only; nothing here was implemented.

Ranking is by expected value to the sanctioned path (plan → implement → review → audit) divided by effort, with the gate-risk column as a veto: nothing below may make `/review-sprint` or `/audit-sprint` bypassable, weaken the implement gate, or let a planning artifact carry execution.

Effort: **S** ≤ half a sprint, prose and config; **M** one sprint with scripts and tests; **L** a multi-sprint feature.

---

## ADOPT (import nearly as-is)

### A1. Round-based, prerequisite-ordered questioning in the discovery interview
- **Import**: the frontier rule, numbered questions with a recommended answer, "word each question so 'yes' accepts the recommendation", recompute the frontier after each round (`P:skills/productivity/grilling/SKILL.md:8-26`).
- **Loa surface**: `.claude/skills/discovering-requirements/SKILL.md` `<interview_config>` Question Pacing table (`:81-86`), Phase 0.5 Targeted Interview (`:246-252`), and Phase 2 of `planning-sprints` / `designing-architecture`. Config: `.loa.config.yaml.example:104-139` gains `pacing: rounds` (sequential | batch | rounds). Recommend `rounds` as the `thorough` default and `sequential` as the documented opt-out, mirroring Pocock's 1.2.0 flip and his supported one-at-a-time line.
- **Budget constraint**: `discovering-requirements/SKILL.md` has 80 bytes of headroom (16,304 / 16,384). The pacing text must displace something: move the Mode Behavior and Input Style tables to `resources/REFERENCE.md` behind a guarded pointer (the charging rule at `tools/check-prompt-budget.sh:12-19` does not charge guarded reads).
- **Test**: `tests/unit/prompt-budget.bats` (CI); a config-schema case for the new enum; one scripted headless transcript on a fixture context asserting ≥ 2 questions per round and no dependent pair in a round (manual rubric; no interview eval exists today, `.claude/evals/` holds only `flatline-3model.sh`).
- **Gate risk**: none; planning only.
- **Effort**: S.

### A2. Fact / decision split, and "facts are the agent's job"
- **Import**: "Finding _facts_ is your job, never the user's … dispatch a sub-agent … The _decisions_ are the user's" (`P:grilling/SKILL.md:28`).
- **Loa surface**: the Backpressure Protocol (`discovering-requirements/SKILL.md:90`) gains one sentence classifying each pending question as **fact** (look it up: `/ride` reality, repo, docs, Explore subagent) or **decision** (only the operator). Karpathy principle 1 (`karpathy-principles.md:30-35`) and `autonomous-agent/SKILL.md:66` keep "proceed on the documented assumption" for facts, and for decisions write a ledger row with `decided_by: agent` (see B2) and list them in the PR body under "Decisions taken on your behalf". This turns the wayfinder failure pattern Loa has institutionalised into an auditable one.
- **Test**: `no-history-in-rule-text.bats` still green; a PRD fixture run in unattended mode produces N `decided_by: agent` rows equal to its `[ASSUMPTION]` decisions (bats over the ledger).
- **Gate risk**: none; it adds a record, removes nothing.
- **Effort**: S for prose, M with B2.

### A3. `disable-model-invocation: true` on operator-only commands
- **Import**: the invocation invariant: a user-invoked skill is "reachable only by the human typing its name … no other skill can" call it (`P:.agents/invocation.md`); Loa already uses the flag once (`.claude/commands/gpt-review.md:4`).
- **Loa surface**: `.claude/commands/*.md` frontmatter for leaf commands. Safe today (zero references from other command or skill bodies): `loa-eject`, `toggle-gpt-review`, `permission-audit`, `loa-setup`. Needs per-reference triage first because other bodies name them (prose advice vs operative step): `update-loa` (6), `mount` (10), `contribute` (1), `feedback` (9), `deploy-production` (7), `archive-cycle` (5), `ship` (3), `run-halt` (9), `run-resume` (16). Do not flag anything an orchestrator executes as a step (`/implement`, `/review-sprint`, `/audit-sprint`, `/archive-cycle` via `/ship`).
- **Test**: a bats lint over an allowlist file asserting the flag is present, and that no other `.md` body contains an operative "Execute /name" for a flagged command.
- **Gate risk**: none; it only removes model reach. `[UNVERIFIED]` that the flag hides commands as it hides skills; verify on the live harness before relying on it.
- **Effort**: S.

### A4. Glossary convention with `_Avoid_` lists, dogfooded on Loa itself
- **Import**: `GLOSSARY.md` format and rules (`P:skills/engineering/domain-modeling/GLOSSARY-FORMAT.md:5-30`), inline updating during planning (`domain-modeling/SKILL.md:60-64`), consumer rule "proceed silently if absent" (`setup-matt-pocock-skills/domain.md:11`).
- **Loa surface**: a tracked root `GLOSSARY.md` for the framework's own vocabulary (Flatline, dissent, voice, Bridgebuilder, cheval, ICE, jack in, grimoire, lore, construct, beads, run mode, zone, Karpathy, kaironic), seeded from lore `short` fields but implementation-free; a `## Glossary` step in `discovering-requirements` Phase 1 and `designing-architecture` ("challenge against the glossary", "sharpen fuzzy language") writing the *project's* `GLOSSARY.md`; `riding-codebase` reads it as a reality input; `reviewing-code` flags new undefined terms. Keep lore separate (patterns and metaphors are not glossary entries by Pocock's own rule).
- **Test**: `validate-artifact.sh --type glossary` (format: term, one–two sentence definition, optional `_Avoid_`); a kernel check that every backticked framework term in `CLAUDE.loa.md` appears in the glossary (small allowlist).
- **Gate risk**: none. Rot risk is real (BUTTERFREEZONE is stale at v1.147.0); the kernel check is the drift gate.
- **Effort**: M.

---

## ADAPT (change for Loa's mechanics)

### B1. Decision tickets on beads: a `/chart` phase before the PRD for multi-cycle efforts
- **Pocock mechanism**: a map issue with Destination / Decisions so far / Not yet specified / Out of scope; child decision tickets typed grilling / prototype / research / task; native blocking → frontier; claim by assignee; one ticket per session; hand-off to spec (`P:skills/engineering/wayfinder/SKILL.md:19-128`).
- **Loa mapping**:
  - **Tracker**: beads, not GitHub Issues. The map is an epic bead labelled `map`; each decision is a `--type question` bead (the enum already exists and is unused; `br schema`) with one label `decision:grilling|prototype|research|unblock` (Pocock's `task` renamed so it cannot be read as a build task). Blocking edges via `br dep`, the edge-or-none rule already in `planning-sprints/SKILL.md:294-300`; frontier via `get-ready-work.sh --graph` filtered to the map; claim via `br update --status in_progress --assignee`; resolve via `br comments add` + `br close` + one line appended to the map doc.
  - **Map doc**: `grimoires/loa/maps/<slug>.md` (tracked, team surface, like `known-failures.md`) with the four sections verbatim and **no Notes override**: the map cannot carry execution. This removes Pocock's most-reported failure at the root.
  - **Ticket types**: `grilling` → a `/grill` session (B6) with rounds; `prototype` → B3; `research` → an Opus subagent writing `grimoires/loa/research/<slug>.md` with cites (the directory and README exist), the only type allowed more than one per session; `unblock` → operator checklist (Pocock's `wizard` idea in prose) or agent task that writes no App-Zone code.
  - **Hand-off**: when `br ready` for the map is empty and "Not yet specified" is empty, `/plan-and-analyze` consumes the map and the DEC rows (B2) as priority-1 context ("reality > context > interview", `discovering-requirements/SKILL.md:211-217`), so the seven phases become confirmation. `golden_detect_plan_phase` (`golden-path.sh:56-66`) gains a `charting` state when an open map exists.
  - **Anti-ceremony guard**: Pocock's rule verbatim: if the breadth-first grill surfaces no fog, stop and say the effort fits one cycle (`wayfinder/SKILL.md:112`). Chart only when the destination spans more than one cycle.
- **Gates respected**: `question` beads never carry `sprint:` labels (lint in `create-sprint-task.sh`: a `question` under a sprint epic is an error), so `/run` never implements them; App-Zone writes during a chart session have no RUNNING state, so the implement gate asks (`implement-gate.sh:446-449`); nothing on the map is reviewable code, so review/audit are untouched. Flatline may run on the cleared map before the PRD (optional, `phases.map`).
- **Record branch**: maps and the decision ledger are tracked in git, not under a2a; the record branch carries the resolution comments only if beads export does not already (`br sync --flush-only`).
- **Test**: bats for the label/type lint, the frontier filter, the hand-off context load; a fixture map walked end to end with `br --dry-run`; one real chart on the next multi-cycle effort as the acceptance run.
- **Gate risk**: low. The one new risk is a `decision:unblock` ticket drifting into build work; the gate's ask plus the no-`sprint:`-label lint hold it.
- **Effort**: L (one cycle; see `prd-brief.md`).

### B2. Build the decision ledger that was specified in February
- **Pocock mechanism**: ADRs offered only when hard to reverse, surprising and a real trade-off; template of one to three sentences (`P:domain-modeling/ADR-FORMAT.md:9-37`).
- **Loa mapping**: implement `grimoires/loa/decisions.yaml` per `docs/architecture/decision-lineage.md:23-74` (`DEC-NNNN`, timestamp, phase, summary, decision, rationale, alternatives, consequences), adding `decided_by: operator|agent|flatline|dissent`, `status: open|decided|superseded|rejected`, `source` (bead id, PR, NOTES anchor) and Pocock's three-condition filter as the bar for a row. Writer: `lib/dec-write-lib.sh` modelled on `kf-write-lib.sh` (flock, append-only verify, atomic rename, no bot auto-append). Readers already exist (`loa-learnings-index.sh:421`, `path-lib.sh:483`); `grimoire-index.sh` gains a `## decisions` section; SessionStart surfaces `status: open` rows the way `loa-kf-surface.sh` surfaces KFs. NOTES Decision Log keeps the narrative and points at `DEC-NNNN`; `docs/architecture/ADR-*.md` stay for release epochs. `status: rejected` rows with "prior requests" replace Pocock's `.out-of-scope/` files.
- **Who writes rows**: `/plan-and-analyze` and `/architect` debriefs ("Key Decisions … (not {alternative rejected})"), resolved decision tickets (B1), unattended self-answers (A2), Flatline BLOCKER overrides (`flatline-hitl-review.md:11-28`).
- **Test**: writer bats mirroring `kf-write-lib` tests (never shrinks, never drops an id); index generation; a `validate-artifact.sh --type decisions` schema check; `no-history-in-rule-text.bats` unaffected.
- **Gate risk**: none; it is a record. Secret-hygiene rule applies (`zone-state.md`: no secrets in tracked state).
- **Effort**: M.

### B3. Ungrillable questions become prototype tickets, with a spike discipline
- **Pocock mechanism**: "ungrillable" questions (look, feel, behaviour) stop the grill and route to `prototype`: throwaway, trivial to run, no persistence, captured on a throwaway branch with a pointer (`P:prototype/SKILL.md:8-26`; `W:grill-me` Grillable and ungrillable).
- **Loa mapping**: in the interview, a question the operator answers "I need to see it" (or the agent classifies as unanswerable by talking) is recorded as a `decision:prototype` bead, not an `[ASSUMPTION]`. The prototype runs HITL in a `git worktree` on a `spike/<slug>` branch that is pushed and never merged; a `grimoires/loa/spikes/` template (Question / What was built / Verdict / Pointer) replaces the one-off report format of `cycle-096-sprint-0-bedrock-contract.md`; the verdict becomes a DEC row. `planning-sprints` "High-Risk Early" (`REFERENCE.md:100-103`) points at this instead of scheduling spikes inside build sprints.
- **Gates respected**: prototype code is App-Zone code written outside `/implement`, so the implement gate asks; that is the correct friction, and HITL by definition. ICE forbids pushing to protected branches; `spike/*` is not one. No PR is opened (Pocock's research-branch rule, `wayfinder/SKILL.md:115`).
- **Test**: bats for the spikes template validator and the branch-name rule in `run-mode-ice.sh`; fence corpus case that a `spike/*` push is allowed and a merge of it is not.
- **Gate risk**: low; a spike that is later copied into `src/` must go through `/implement`, which the gate and review already require.
- **Effort**: M.

### B4. Seams-under-test in the sprint plan, checked on the spec axis
- **Pocock mechanism**: "Test only at pre-agreed seams … confirm them with the user … a one-line note on what it catches and what it misses" (`P:tdd/SKILL.md:22-24`); `to-spec` "Testing Decisions" (`to-spec/SKILL.md:59-65`).
- **Loa mapping**: `sprint-template.md` gains a per-sprint `### Seams Under Test` block (seam, catches, misses, prior art); `planning-sprints` Phase 2 asks it as a round; `validate-artifact.sh --type sprint` requires the block; `reviewing-code` spec axis checks that tests exist at each declared seam and nothing is tested only "past the interface".
- **Test**: validator bats; a review fixture with a missing seam test yields a MEDIUM finding.
- **Gate risk**: none; it adds a review check.
- **Effort**: S/M.

### B5. Red-before-green made verifiable for `/bug` micro-sprints
- **Pocock mechanism**: "Red before green" (`tdd/SKILL.md:36`) and "prove the mutation landed" (`diagnosing-bugs/SKILL.md:125`).
- **Loa mapping**: the micro-sprint requires two commits, the failing test first; `red-test-check.sh` (review-time) runs the named test at the red commit (must fail) and at HEAD (must pass); the review's AC row for "Test fails with current code" cites the script's output instead of the implementer's word. Honest framing as in `validate-ac-verification.sh:10-14`: this prevents absent evidence, not fabricated tests; the reviewer still reads the assertion.
- **Test**: bats with a fixture repo (red commit, green commit, and a trivially-passing decoy).
- **Gate risk**: none; strengthens review.
- **Effort**: M.

### B6. A stateless `/grill` entry point ahead of `/plan`
- **Pocock mechanism**: `grill-me`: loose idea, rounds, writes no files, "start it in a fresh conversation", hand the same conversation to spec (`W:grill-me`).
- **Loa mapping**: `/grill` = the grilling primitive (A1) with `write_files: false` and no artifact by default; on request, `--to-context` writes a one-page summary to `grimoires/loa/context/grill-<date>.md`, which `/plan-and-analyze` Phase 0 already ingests ("The more context provided, the fewer questions asked", `.claude/commands/plan-and-analyze.md:174`). It is the cheap test for "is this a cycle, a `/bug`, or nothing?" and the resolver for `decision:grilling` tickets (B1).
- **Test**: skill-capabilities lint (`write_files: false`, no Bash); budget gate; a transcript check that nothing is written without the flag.
- **Gate risk**: none.
- **Effort**: S (depends on A1).

### B7. Two-axis presentation inside the review feedback
- **Pocock mechanism**: `## Standards` and `## Spec`, never reranked across axes (`P:code-review/SKILL.md:76-80`).
- **Loa mapping**: `engineer-feedback.md` keeps severities and the LOA-VERDICT trailer but groups findings under `### Spec (acceptance criteria, SDD alignment)` and `### Standards (conventions, complexity, security, performance)`. The one-way rule is unchanged.
- **Test**: `verdict-derive.bats`: the new headings must not trip the forbidden-heading check (`verdict-derive.sh:7-28` rejects `## Changes Required / Findings / Issues` on approved files).
- **Gate risk**: none if the heading check is extended deliberately.
- **Effort**: S.

---

## LEARN (fold into prose or tests, no new surface)

- **L1. Pocock's `retro` classifier** ("a mechanical violation gets a deterministic check … reserve standards for judgement calls", `P:retro/SKILL.md:19`) is Loa's Mechanical Floor stated as a per-session habit. Apply it to the four prose-only NEVER/ALWAYS rows (`sources/loa-gate-evidence.md` G10: TaskCreate, `/bug` for feature work, beads creation, bug eligibility) as follow-up beads; the first two are checkable (a PostToolUse hook on TaskCreate while a sprint is active; `validate-artifact --type bug-triage` already exists and is prompted).
- **L2. "Refer by name, never by a bare id"** (`wayfinder/SKILL.md:15-17`): Loa narration is dense with `bd-ugmi`, `KF-004`, `#1275`. Debriefs and NOTES should write "agy opt-in (bd-ugmi)". Prose change in the debrief templates.
- **L3. "It's working if"** observable tells (`P:.agents/writing-docs.md`) for the five golden-path commands in README / `/loa --help`: signals the operator can check without reading a SKILL.md.
- **L4. The no-op test for generated includes.** Shared include blocks consume 21–35 % of the five core skills' budgets. Run the prompt-audit METHOD's "does it change behaviour versus the default?" question over `trajectory_logging`, `integrity_precheck`, `input_guardrails` and `prompt_enhancement_prelude`; either shrink, or exempt generated blocks from the budget charge so the budget governs authored text. Pocock's alternative (one owning skill, reached by a Skill call) costs a tool round-trip per invocation and is not obviously better.
- **L5. Merge-danger call in PR bodies** (one-way or two-way door, blast radius; `P:CHANGELOG.md` 1.3.0 `pr`): one line in `run-mode/resources/render-templates.md`.
- **L6. Pocock's honesty lines** for Loa's docs: "No instruction makes an agent comply 100 % of the time" and "there is no convergence guarantee" belong next to the run-mode loop, whose breaker arithmetic is model-executed. A follow-up bead: move the circuit-breaker counters into `run-checkpoint.sh` so the trip is computed by a script.
- **L7. Diagnosis-loop vocabulary** for `/bug` Phase 3: "no red-capable command, no fix", 3–5 ranked falsifiable hypotheses, instrument one variable at a time (`P:diagnosing-bugs/SKILL.md:66,90,100-112`). Prose in `bug-triaging/resources/analysis-steps.md`; the KF ledger stays the memory Pocock lacks.
- **L8. Expand–contract for wide refactors** (`P:to-tickets/SKILL.md:40`) as a sprint-sequencing pattern in `planning-sprints/resources/REFERENCE.md`.

---

## REJECT (with reasons)

- **R1. Dropping AskUserQuestion / harness-neutral grilling.** Loa is Claude-Code-native; structured phase gates are a feature with a `plain` opt-out (`.loa.config.yaml.example:117-124`). Pocock's reason is portability across Codex / Copilot / Cursor, which Loa does not pursue.
- **R2. Replacing the seven-phase interview with a stateless grill.** The PRD interview is grounded in `/ride` reality and produces the validated artifact the rest of the chain consumes; a grill that leaves only "a clearer version of the idea, in your own head" (`W:grill-me`) conflicts with "State Zone artifacts are the lossless ledgers" (`session-continuity.md:7`). Keep the interview; add rounds (A1) and a pre-interview grill (B6).
- **R3. `implement-spec`-style parallel implementer swarm inside `/run`.** Implementers in worktrees with a merger subagent conflict with Loa's single-writer rules (beads, `.run/`, git through the lead; `CLAUDE.loa.md` Agent Teams table) unless the lead orchestrates, which is a run-mode feature outside this review. Cycle-127 did it by hand (`NOTES.md:31`). Track as a bead; not an adoption.
- **R4. GitHub Issues as the decision-map tracker.** Beads is the single source of truth for task lifecycle (`CLAUDE.loa.md` NEVER table), has the type and the graph already, and Pocock himself notes public trackers "fill up with agent-generated planning tickets" (`W:wayfinder`).
- **R5. Pocock's `code-review` as a replacement review.** No severity, no verdict, no gate; it would weaken the one-way rule and the dissent artefact gate. Take only the presentation (B7).
- **R6. Plugin-marketplace distribution of Loa.** Loa's install contract is mount + submodule + checksums + System Zone integrity + hooks in `settings.json`; a plugin tree breaks the zone paths the fences assume, and constructs are already Loa's pack format with a registry. Revisit only if a plugin can carry hooks and integrity with the same guarantees.
- **R7. `improve-codebase-architecture` / "invest in design every day".** It contradicts Karpathy principle 3 (surgical changes) and the diff-size hook on purpose; Loa routes design evolution through Bridgebuilder and `/architect`. Deep-module *vocabulary* may still enter the glossary (A4) without the skill.
- **R8. Hard caps on question counts.** Both repos reject them; Loa's `min_confirmation_questions` is a floor, not a cap. No change.

---

## Adversarial pass: a Pocock-style grilling of Loa

Questions Loa cannot answer today, with the proposal that would make each answerable.

| # | Question | Loa today | Fix |
|---|---|---|---|
| 1 | "Which decisions in cycle-127's PRD did a human make?" | `[ASSUMPTION]` tags and a NOTES line "Design calls made without the operator" (`NOTES.md:52`); no per-decision `decided_by` | A2 + B2 |
| 2 | "List the open questions across the last four cycles and which were resolved by what." | SDD `## 10. Open Questions` tables archived per cycle; no graduation record | B1 + B2 |
| 3 | "What is a voice? a dissent? ICE?" | grep across lore, README, kernel, skills | A4 |
| 4 | "Which of your NEVER rules would actually stop me?" | answerable from `hooks-reference.md` and G10, with the caveat that the implement gate never denies | L1 |
| 5 | "When you ran the interview unattended, which answers were facts you looked up and which were decisions you took for me?" | both are `[ASSUMPTION]` | A2 |
| 6 | "What was the ungrillable question in cycle-126, and what did you build to answer it?" | the ceiling probe, as NOTES prose and a tool, no artifact type | B3 |
| 7 | "Why did you reject X last quarter?" | KF ledger (failures only), NOTES prose, closed issues | B2 `status: rejected` |
| 8 | "Can the model run `/ship` or `/update-loa` on its own?" | yes in principle; one command carries the flag | A3 |
| 9 | "Where is the seam your tests prove, and what do they miss?" | ACs with `file:line` evidence; no seam declaration | B4 |
| 10 | "Show me the test failing before the fix." | the implementer's AC row | B5 |

Adversarial pass over the proposals themselves:

- **B1 adds ceremony to a framework already heavy with it.** Mitigation: the trigger is multi-cycle only; the no-fog stop is mandatory; a chart that produces fewer than three decision tickets is deleted and the effort goes to `/plan` or `/bug`. Measure: charted efforts should show fewer `[ASSUMPTION]` rows in their PRDs, not more artifacts.
- **B1's `unblock` type is Pocock's `task`, the type that "goes wrong most often".** Mitigation: renamed, no `sprint:` label by lint, App-Zone writes ask, and the ticket body must name the decision it unblocks.
- **B2 risks double-entry with NOTES** ("Nothing is stated twice", `P:docs/productivity/writing-for-agents.md:66`). Mitigation: NOTES keeps the story and the `DEC-NNNN` pointer; the ledger keeps the record; `grimoire-index.sh` is the only place both appear.
- **A4 will rot** like BUTTERFREEZONE. Mitigation: the kernel-term check is the drift gate; the glossary is small by rule.
- **B5 can be gamed** by a decoy failing test. Mitigation: the reviewer still reads the assertion; the script raises the floor from self-report to verifiable, which is the same honest claim `validate-ac-verification.sh` makes.
- **A1 changes a default** many operators have learned. Mitigation: `sequential` stays supported and documented as Pocock documents his one-at-a-time line; the default flip is a maintainer decision, flagged in the PRD brief.

## Recommended next step

The ADOPT and ADAPT sets cohere around one theme, decision surfaces for planning, and B1 + B2 + B3 are a cycle on their own. `prd-brief.md` is the one-page input for `/plan-and-analyze`. A1, A3, B7 and the LEARN items are small enough to travel as `/bug`-sized follow-ups only where an observed failure exists; otherwise they belong in the same cycle's first sprint.
