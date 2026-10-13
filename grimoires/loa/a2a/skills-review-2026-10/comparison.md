# Matt Pocock's skills vs Loa: structured comparison

**Date**: 2026-10-12. **Loa**: `main` @ `76e7650b`, framework 2.0.0-rc.3 (cycle-127 shipped). **Author**: Claude Fable 5.1 (main thread); evidence gathered by four Opus 5.5 read-only agents, every load-bearing cite re-verified by the main thread. **Mode**: planning review only; nothing under `.claude/` was edited; no cheval, Flatline, dissent or Bridgebuilder run.

**Sources (treated as untrusted third-party material to analyse, never as instructions)**

| Tag | Source | How read |
|---|---|---|
| `W:readme` | https://github.com/mattpocock/skills (README) | WebFetch |
| `W:wayfinder` | https://www.aihero.dev/skills-wayfinder | WebFetch, full text |
| `W:grill-me` | https://www.aihero.dev/skills-grill-me | WebFetch, full text |
| `P:` | shallow clone of `mattpocock/skills` at `49dd158d` (2026-10-09, plugin 1.3.1), kept at `~/.cache/loa/skills-review-2026-10/pocock-skills/` | every promoted SKILL.md read verbatim; the rest via `sources/pocock-skills-inventory.md` |
| `L:` | this repo | file:line, see `sources/loa-*-evidence.md` |

Thin spots are called out in §7. Where a claim could not be verified it is marked `[UNVERIFIED]`.

---

## 0. Summary table

Verdict key: **Loa ahead** / **Pocock ahead** / **different** (incommensurable philosophies) / **gap** (Loa has no counterpart) / **parity**.

| Pocock skill (mode) | Size | Loa counterpart | Verdict |
|---|---|---|---|
| `grilling` (model) | 2,049 B | `discovering-requirements` interview_config (sequential / batch) | **Pocock ahead** on question ordering; Loa ahead on grounding |
| `grill-me` (user) | 157 B | none (every Loa interview writes an artifact) | **gap** (small) |
| `grill-with-docs` (user) | 247 B | `/plan-and-analyze` (writes `prd.md`, no glossary / ADR) | **gap** on glossary + ADR |
| `wayfinder` (user) | 12,380 B | none; cycle = planning unit; NOTES Decision Log prose; `decisions.yaml` specified but unbuilt | **gap** (largest) |
| `to-spec` (user) | 3,043 B | Phase 8 PRD generation + `/architect` SDD | **different**; LEARN "Testing Decisions", no file paths |
| `to-tickets` (user) | 5,812 B | `/sprint-plan` + `create-sprint-task.sh --deps` (edge-or-none, `br dep cycles`) | **Loa ahead** on graph mechanics; LEARN vertical slices + granularity quiz |
| `implement` (user) | 622 B | `/implement` + implement gate + AC verification | **Loa ahead** |
| `implement-spec` (user) | 2,780 B | `/run sprint-plan` (sequential); teams mode | **different** (fan-out vs single-writer) |
| `tdd` (model) | 3,629 B | test-first in `/bug` only; `/implement` "tests alongside" | **Pocock ahead** on discipline text; neither is mechanical |
| `code-review` (model) | 6,670 B | `/review-sprint` + two-voice dissent + `/audit-sprint` + LOA-VERDICT | **Loa ahead**; LEARN two-axis separation |
| `diagnosing-bugs` (model) | 8,664 B | `/bug` (eligibility → interview → analysis → micro-sprint) | **Pocock ahead** on the diagnosis loop; Loa ahead on the KF ledger |
| `prototype` (model) | 2,931 B | none (`grimoires/loa/spikes/` holds one hand-made report) | **gap** |
| `research` (model) | 794 B | Explore ingestors in discovery; `/ride`; `grimoires/loa/research/` | **Loa ahead** on codebase facts; **gap** on AFK research as a ticket type |
| `domain-modeling` (model) | 3,346 B | none (lore = patterns; per-doc glossary appendix) | **gap** |
| `codebase-design` (model) | 6,446 B | none; Karpathy "surgical" is the opposite stance | **different** |
| `improve-codebase-architecture` (user) | 6,000 B | none; Bridgebuilder "is the design evolving well" | **gap** (deliberate) |
| `pr` (model) | 4,169 B | run-mode PR templates | **parity**; LEARN merge-danger call |
| `retro` (user) | 4,369 B | `/retrospective`, `/compound`, KF ledger | **different**; principle already Loa's |
| `triage` (user) | 6,558 B | `/bug` Phase 1 eligibility scoring | **partial** |
| `setup-matt-pocock-skills` (user) | 6,978 B | `/mount`, `/loa-setup`, `.loa.config.yaml` | **parity** (Loa heavier) |
| `ask-matt` (user) | 12,594 B | `/loa` (state router) | **different** (topic vs state) |
| `wizard` (model) | 4,123 B | none | **gap** (minor) |
| `handoff` (user) | 940 B | `structured-handoff` (L6), session-continuity, compaction hooks | **Loa ahead** |
| `teach` (user) | 9,733 B | none | out of scope |
| `to-questionnaire` (user) | 2,904 B | none (`hitl-jury-panel` is adjacent) | **gap** (small, relevant to decision tickets) |
| `wait-what` (user) | 396 B | none | out of scope |
| `writing-for-agents` (model) | 10,886 B | prompt-audit METHOD (archived), byte budgets, `no-history-in-rule-text` | **partial**; Loa mechanical, Pocock conceptual |

---

## 1. Per-skill notes (evidence)

### Planning chain

**`grilling` / `grill-me` / `grill-with-docs`.** The whole technique is one 30-line file. "Work the tree in **rounds**. The **frontier** is every decision whose prerequisites are already settled" (`P:skills/productivity/grilling/SKILL.md:8`). Each question is numbered with a recommended answer and "Word each question so 'yes' accepts your recommended answer" (`:24`). "Finding _facts_ is your job, never the user's … dispatch a sub-agent … The _decisions_ are the user's: put each to them and wait" (`:28`). Done "when the frontier is empty … Do not act on it until the user confirms" (`:30`). `grill-me` is literally `Call the Skill tool with "grilling"` (`P:skills/productivity/grill-me/SKILL.md:7`); `grill-with-docs` adds `domain-modeling` (`P:skills/engineering/grill-with-docs/SKILL.md:7`). The docs admit the frontier "is chosen by judgement; it does not compute it from a graph" (`P:docs/productivity/grilling.md`, "The round, the frontier, and who decides") and that the wrapper "never loaded grilling" is "a real bug, still unfixed" (same file, Common questions). No prompt template is published on the web page (`W:grill-me`); the template is the SKILL.md itself.

Loa counterpart: `.claude/skills/discovering-requirements/SKILL.md` (16,304 B). Seven topic phases in fixed order (`:263-275`), pacing `sequential` = "Ask ONE question per turn" or `batch` = "Present 3-6 numbered questions" (`:85-86`), Backpressure Protocol "ask rather than infer — don't answer your own questions" (`:90`), phase gates with Continue / Go back / Skip ahead (`resources/REFERENCE.md:156-178`), pre-generation gate with assumption counts (`REFERENCE.md:398-413`). Grounding is far stronger than Pocock's: reality > context > interview (`SKILL.md:211-217`), `/ride` codebase grounding (`:184-187`), quotes with cites mandatory (`:139-156`).

**`wayfinder`.** "Every ticket asks a question, and the answer is a decision, not a slice of a build" (`W:wayfinder`, What it does). Map body sections Destination / Notes / Decisions so far / Not yet specified / Out of scope (`P:skills/engineering/wayfinder/SKILL.md:31-53`). "never resolve more than one ticket per session, with the exception of research tickets" (`:105`). Ticket types research (AFK) / prototype (HITL) / grilling (HITL) / task (`:77-80`); "a grilling agent that answers its own questions has broken this" (`:75`). Charting stops when the breadth-first grill "surfaces no fog" (`:112`). Reported failures (`W:wayfinder`, Common questions): the agent writes production code mid-map because "the constraint and its exemption live in a file that the constrained agent owns"; 27-ticket maps that go stale ("waterfall trap"); three-paragraph questions; parallel sessions re-asking.

Loa counterpart: none. `golden_detect_plan_phase` is a file-existence ladder prd → sdd → sprint (`.claude/scripts/golden-path.sh:56-66`). The ledger's cycle record has no parent or roadmap link (`grimoires/loa/ledger.json` fields: `archive_path, archived, created, id, label, prd, sdd, sprints, status`). Beads epics are sprints (`.claude/skills/planning-sprints/SKILL.md:287`). `br` has an unused `question` type (`br schema` IssueType enum: `task, bug, feature, epic, chore, docs, question`; live counts 816 task / 56 epic / 56 bug / 13 feature / 0 question). `docs/architecture/decision-lineage.md:23-29` specifies `grimoires/loa/decisions.yaml` with `DEC-0001` ids; the file does not exist, while `.claude/scripts/loa-learnings-index.sh:421` and `path-lib.sh:483` still read for it. The nearest live artifact is an ad-hoc decision doc linked to a bead: `grimoires/loa/proposals/copyset-ungitignore-decision-2026-07-07.md:1-4` ("Decision doc — awaiting operator sign-off", options A/B/C).

**`to-spec` / `to-tickets`.** `to-spec`: "Do NOT interview the user; just synthesize" (`P:skills/engineering/to-spec/SKILL.md:7`); seams first, confirmed with the user (`:15-17`); spec sections Problem / Solution / User Stories / Implementation Decisions / Testing Decisions / Out of Scope (`:23-69`); "Do NOT include specific file paths or code snippets. They may end up being outdated very quickly" (`:55`). `to-tickets`: tracer-bullet vertical slices "sized to fit in a single fresh context window" (`:29-36`), blocking edges, expand–contract for wide refactors (`:40`), "Quiz the user … Does the granularity feel right?" (`:42-56`), publish with native blocking (`:58-63`).

Loa: `/sprint-plan` writes `sprint.md` with Goal / Scope SMALL–LARGE / Deliverables / Acceptance Criteria / Technical Tasks (`planning-sprints/SKILL.md:228-232`), beads via `create-sprint-epic.sh` + `create-sprint-task.sh … --deps` with the edge-or-none rule (`:285-300`), `br dep cycles` as a hard check (`:310-311`). Phase 2 "Strategic Questioning … Wait for responses" (`:206-216`) is topic-listed, not round-based. Loa's SDD template carries file-level detail that Pocock warns rots.

### Build chain

**`implement` / `implement-spec` / `tdd`.** `implement` is 17 lines: fetch the ticket, "Call the Skill tool with 'tdd' where possible, at pre-agreed seams", typecheck, code-review, commit (`P:skills/engineering/implement/SKILL.md:7-17`). `tdd`: "Red before green", "One slice at a time", "Refactoring is not part of the loop. It belongs to the review stage" (`P:skills/engineering/tdd/SKILL.md:36-38`); "Test only at pre-agreed seams … No test is written at an unconfirmed seam" (`:22`); anti-patterns implementation-coupled / tautological / horizontal slicing (`:30-32`). `implement-spec`: task graph, implementer subagents in worktrees, integration branch, merger subagent, one `code-review` at the end (`P:skills/engineering/implement-spec/SKILL.md:11-39`). The shipped plugin contains **no hooks, no blocking scripts and no tests** (`sources/pocock-skills-inventory.md` §18b); the docs say "No instruction makes an agent comply 100% of the time" (`P:docs/engineering/tdd.md:59`).

Loa: see §4. Test-first is "non-negotiable" only in `/bug` (`.claude/commands/bug.md:7,67`; micro-sprint Task 1 "Write Failing Test", `bug-triaging/resources/templates/micro-sprint.md:23-31`). `/implement` says "with tests for the happy path, error conditions and edge cases" (`implementing-tasks/SKILL.md:231`); red-green-refactor is named nowhere in `.claude/` (grep: zero hits). Karpathy principle 3 forbids the refactor step Pocock defers to review: "don't refactor the unbroken" (`.claude/protocols/karpathy-principles.md:76`).

**`code-review`.** Two axes, Standards and Spec, run as parallel sub-agents and reported side by side; "Do **not** merge or rerank findings" (`P:skills/engineering/code-review/SKILL.md:76-80`). No severity, no verdict, no gate. Docs: "Same context reviewing itself isn't review, it's confirmation bias with a slash command"; "There is no convergence guarantee … Do not run it in a loop until it comes back clean" (`P:docs/engineering/code-review.md:65,77`).

Loa: one reviewer checklist covering both axes (`reviewing-code/SKILL.md:215`: acceptance criteria, readability, SDD alignment, security, performance), severities with the one-way rule (`verdict-derive.sh:12-13`), two-voice dissent (`:221-227`), a separate security audit skill, Bridgebuilder, Fable review in practice. Loa's run loop does loop until APPROVED, bounded by a circuit breaker whose arithmetic the model executes by hand (`run-mode/SKILL.md:129-159`).

**`diagnosing-bugs`.** "Build a feedback loop … **This is the skill.** Everything else is mechanical" (`P:skills/engineering/diagnosing-bugs/SKILL.md:18-20`); ten loop shapes in preference order (`:26-35`); "No red-capable command, no Phase 2" (`:66`); "Generate 3–5 ranked hypotheses before testing any of them" (`:90`); instrument one variable at a time (`:100-112`); "If you forced the red by mutating code or a fixture, `diff` against a pristine copy to prove the mutation landed" (`:125`); "If no correct seam exists, that itself is the finding" (`:120`).

Loa: `/bug` is triage-to-handoff: eligibility scoring (`bug-triaging/SKILL.md:103-196`), interview, codebase analysis "reproduce → isolate → identify suspected files → assess risk class" (`:257`), micro-sprint. No hypothesis / instrument / falsify loop (grep `hypothes|instrument|bisect`: none). What Loa has that Pocock lacks: the known-failures ledger with recurrence counts and a "Reading guide" that prevents re-attempting dead ends (`grimoires/loa/known-failures.md:3-51`, `kf-write-lib.sh`).

**`prototype` / `research`.** `prototype`: "throwaway code that answers a question" (`P:skills/engineering/prototype/SKILL.md:8`), two branches (logic → single HTML file; UI → variations behind a search param), "Throwaway from day one", "Capture it when done … commit it to a throwaway branch, out of main, and leave a context pointer" (`:21-26`). `research`: background agent, primary sources, one Markdown file with cites (`P:skills/engineering/research/SKILL.md:6-12`).

Loa: no prototype notion in any planning skill; "Technical spikes / Proof of concepts" appear only as a sprint-sequencing hint (`planning-sprints/resources/REFERENCE.md:100-103`); one hand-written spike report exists (`grimoires/loa/spikes/cycle-096-sprint-0-bedrock-contract.md`). Research: parallel Explore ingestors for large context (`discovering-requirements/SKILL.md:313-316`), `/ride` for code truth, `grimoires/loa/research/` with a README and one analysis; no AFK research task type.

### Design

**`domain-modeling` / `codebase-design` / `improve-codebase-architecture`.** Glossary with `_Avoid_` lists, "totally devoid of implementation details" (`P:skills/engineering/domain-modeling/SKILL.md:64`); ADRs only when hard to reverse AND surprising AND a real trade-off (`:66-74`); ADR template is 1–3 sentences (`P:…/ADR-FORMAT.md:9-15`). `codebase-design`: "a lot of behaviour behind a small interface, placed at a clean seam, testable through that interface" (`P:skills/engineering/codebase-design/SKILL.md:8`); the deletion test; "One adapter means a hypothetical seam. Two adapters means a real one" (`:63-65`). `improve-codebase-architecture` scans for deepening opportunities and grills through one (`P:…/SKILL.md` description).

Loa: no project glossary (`find -iname 'GLOSSARY*'` → only `.claude/data/lore/mibera/glossary.yaml`, the mythic vocabulary); PRD/SDD templates carry a per-document glossary appendix (`prd-template.md:277`, `sdd-template.md:384`). Four ADRs, hand-written at release milestones, none produced by a skill (`docs/architecture/ADR-001…004`). Lore is named patterns mined from Bridgebuilder reviews, loaded into review prompts (`run-bridge/SKILL.md:191-227`). On design: no "deep module" vocabulary (grep zero); Karpathy "surgical" and the diff-size warn hook (`karpathy-surgical-diff-check.sh`) push the other way. Bridgebuilder's remit "is the design evolving well?" (`run-bridge/SKILL.md:156`) is the nearest.

### Productivity and meta

**`handoff`**: compact to `$TMPDIR`, not the workspace, redact secrets, name suggested skills (`P:skills/productivity/handoff/SKILL.md:7-16`). Loa: schema-validated L6 handoffs with content-addressed ids and SessionStart surfacing (`structured-handoff/SKILL.md:36-44,104-107`), "Clear, Don't Compact" with State Zone as the ledger (`.claude/protocols/reference/session-continuity.md:3,7`), pre/post-compact hooks. Loa persists where Pocock discards; Loa ahead for a framework, Pocock lighter for a person.

**`ask-matt`**: a topic router over user-reachable skills with a phase-boundaries table (`P:skills/engineering/ask-matt/SKILL.md`, `PHASE-BOUNDARIES.md`). Loa: `/loa` routes on artifact state ("Porcelain & Plumbing", `golden-path.sh:1-20`; `golden_suggest_command` `:722`). Loa answers "what next"; Pocock answers "which flow fits this situation". Different questions.

**`retro`**: "a mechanical violation gets a deterministic check, full stop … Default to building the check over writing the rule" (`P:skills/engineering/retro/SKILL.md:19`); "A repo with no guardrail … is itself a finding" (`:18`). Loa's cycle-119/124 "Mechanical Floor" is the same principle made policy (`docs/architecture/ADR-003-mechanical-floor.md`; `tests/unit/no-history-in-rule-text.bats`: every MUST/NEVER/ALWAYS line names its enforcing hook). Loa's retro outputs are skills, learnings and KF entries (`.claude/commands/retrospective.md:19-65`, `propose-learning.md:13-18`), not environment edits (System Zone is never-edit).

**`writing-for-agents`**: context pointers, "two loads" (context load vs cognitive load), information hierarchy, progressive disclosure "Not primarily a token optimisation", completion criteria, leading words, the negation failure mode, the no-op test (`P:skills/productivity/writing-for-agents/SKILL.md:10-81`). No numeric limits anywhere; "There is no automated eval" (`P:docs/productivity/writing-for-agents.md:47`). Loa has the opposite shape: hard budgets in CI (`tools/check-prompt-budget.sh:53`: 16,384 / 10,240 / 160,000 / 114,688), a 35 KB prompt-audit METHOD that lives only in an archived sprint directory (`grimoires/loa/archive/2026-09-23-cycle-124-model-generation-floor/a2a/sprint-237/prompt-audit/METHOD-prompt-audit.md`), and two read-only auditor agents.

**`triage`, `setup-matt-pocock-skills`, `pr`, `wizard`, `teach`, `to-questionnaire`, `wait-what`**: see `sources/pocock-skills-inventory.md` §7–§13. `to-questionnaire` ("Turn a decision you can't fully answer into a questionnaire for someone else") is the one with a Loa use: it is what an autonomous run should emit for decisions it may not take (see §3). `pr`'s "merge-danger call (one-way or two-way door, plus blast radius)" (`P:CHANGELOG.md`, 1.3.0) is absent from Loa's PR templates (`run-mode/resources/render-templates.md:38-75`).

---

## 2. Focus (a): rounds vs the seven-phase interview and Flatline

**Is Loa's interview too linear?** In *order*, yes; in *depth*, no. Phase order is the PRD section order, fixed (`SKILL.md:263-275`); adaptivity is coverage-based ("Full / Partially covered / Not covered", `:256-261`), so a phase is shortened when context already answers it, but the sequence never reorders around a dependency. Pocock orders by prerequisite: "A question whose answer depends on another question still open in this round belongs to a _later_ round" (`P:grilling/SKILL.md:26`). Loa's `batch` pacing presents "3-6 numbered questions" with no independence rule (`SKILL.md:86`), which is exactly the objection Pocock's docs answer with the frontier ("no answer in a round can invalidate another question in that round", `P:docs/productivity/grilling.md`, Common questions). Loa's `sequential` default is the one-question-at-a-time mode Pocock offers as an opt-out line in `CLAUDE.md`. Loa has no recommended-answer convention in plain mode; `structured` discovery questions use AskUserQuestion "with suggested answers" (`SKILL.md:78`), which Pocock rejects on principle ("Structured pickers push the model towards multiple-choice questions with pre-baked answers", `P:.out-of-scope/native-question-tool.md`). That rejection is partly harness-neutrality, which does not bind Loa.

**Does Loa let the agent answer its own questions?** Interactively, no, and more explicitly than Pocock: "don't answer your own questions, write 'Based on common patterns…', combine phases in one response, generate output alongside the last question, or skip a phase as 'sufficient'" (`SKILL.md:90`). Unattended, yes, by design and in four places: Karpathy principle 1 ("in unattended runs … record the open question and your chosen interpretation in NOTES.md Decision Log and proceed", `karpathy-principles.md:30-35`, enforcement "prose-only" `:10`); `autonomous-agent/SKILL.md:66`; the spiral harness's headless DISCOVERY prompt "Write a Product Requirements Document … Include ## Assumptions" (`spiral-harness.sh:306-314`); and practice: "Interview phases answered from the brief … no operator questions (autonomous)" (`grimoires/loa/NOTES.md:141`), "Design calls made without the operator (recorded for review)" (`:52`). So Loa has institutionalised the pattern Pocock calls broken, with three compensations Pocock lacks: `[ASSUMPTION]` tags, Flatline cross-model critique of the resulting document, and maintainer sign-off on the PR. What Loa lacks is Pocock's *distinction*: facts the agent may settle versus decisions only the human may take. Both collapse into `[ASSUMPTION]`. Nothing marks a decision as `decided_by: agent`, so the question "which of these decisions did a human make?" has no mechanical answer.

**Does Loa distinguish ungrillable questions?** No. "Technical spikes" is a sequencing hint (`planning-sprints/resources/REFERENCE.md:100-103`); `/architect` says "Flag technology choices that need validation" (`designing-architecture/SKILL.md:147`); the debrief asks for falsifiable assumptions ("if wrong, {consequence}", `planning-sprints/SKILL.md:369`) but schedules nothing. Cycle-127's D3 ("probe the ceiling through this host's route", `NOTES.md:37`) was precisely a prototype-type decision ticket, executed as prose.

**Flatline's role.** Flatline critiques the document, never interviews the human (`flatline-protocol.md:139-141`; personas respond "ONLY a valid JSON object", `flatline-skeptic/persona.md:12`); the human adjudicates findings (accept / reject / override, `simstim-workflow/resources/flatline-hitl-review.md:11-28`), is never asked a requirements question, and in autonomous mode HIGH_CONSENSUS auto-integrates (`flatline-reference.md:16-23`). It is the mechanical substitute for Pocock's success criterion "You disagree with something" (`W:grill-me`, It's working if): disagreement is outsourced to other models. That is a real strength Pocock has nothing like, and a real weakness: the disagreement is about the artifact, not about the operator's decisions, and the docs naming the models are stale (`flatline-reference.md:7` names Opus 4.7 / GPT-5.3 / Gemini 2.5 against a live config of `claude-headless` + `gpt-5.5`).

**Where Loa is ahead**: facts. "Finding facts is your job" is one sentence in Pocock; in Loa it is `/ride`, reality-over-context priority, mandatory quotes with cites, and Explore fan-out. A Loa interview starts knowing the codebase; a Pocock grill starts from the user's head.

---

## 3. Focus (b): the decision-ticket map vs beads + sprint planning

**First-class DECISION unit**: none. Decisions live as (i) prose bullets in dated NOTES Decision Log sections (23 headings in a 356-line, 136 KB, gitignored, per-operator file above its own 100 KiB warn line; `notes-guard.sh` thresholds per `context-engineering.md:15`), sometimes numbered `D1 / D2 / D3` with a bead id (`NOTES.md:35-37`); (ii) debrief "Key Decisions … (not {alternative rejected})" lists (`discovering-requirements/resources/REFERENCE.md:363-386`); (iii) ad-hoc proposal docs (`grimoires/loa/proposals/`, 29 files); (iv) four release-epoch ADRs; (v) the SDD's `## 10. Open Questions` table with `Status: Open/Resolved` and no link to what resolved it (`sdd-template.md:374-378`). The prescribed NOTES format (`session-continuity.md:156-189`: Decision / Rationale / Evidence / Test Scenarios) is not the practised one. The specified `decisions.yaml` ledger was never built (`decision-lineage.md:23-29`).

**Fog of war / out of scope**: the PRD template has "Explicitly Out of Scope" with reasons (`prd-template.md:202-204`) and "In Scope (Future Iterations)" (`:198`), but no "Open Questions" or "Not yet specified" section in its 13-section TOC (`:10-24`). Nothing records that an open question graduated into a decision. Pocock's test "whether you can state the question precisely *now*, not whether you can answer it" (`W:wayfinder`) has no Loa home.

**One decision per session**: absent. `/plan` chains PRD → SDD → sprint in one session with "Continue (Recommended)" at each debrief (`plan.md:141-157`; `REFERENCE.md:379`). Loa's session philosophy is "Clear, Don't Compact": sessions are disposable because State Zone files are the ledger. That makes a session boundary cheap, which is an *enabler* for one-decision-per-session, not an obstacle. Pocock's observed failure, "if you work two grilling tickets at once, one session can ask you a question you just answered in the other" (`W:wayfinder`), would be mitigated in Loa by NOTES and beads, not by discipline.

**Would /plan benefit from a wayfinder phase before the PRD for efforts that span cycles?** Yes, narrowly. Evidence from Loa's own record: cycles 124 → 125 → 126 → 127 were one arc (model floor → friction floor → full size → operator decisions) coordinated through NOTES prose, the maintainer's memory files and carry-over beads (bd-b4ji "recurs" across three cycles, `NOTES.md:40,47`). Cycle-127 was a cycle whose content was three decisions (D1–D3) and one probe; it was run as a full PRD / SDD / sprint. "Design calls made without the operator (recorded for review)" (`NOTES.md:52`) is a list of decision tickets that never had a ticket to be reviewed in. And `br` already has the type (`question`) and the dependency graph (`br dep`, `get-ready-work.sh --graph`, `bv --robot-plan`) that wayfinder needs a tracker for; Loa would get the frontier for free. The trigger must stay as narrow as Pocock's: "wayfinder only makes sense if the work does not fit into a single session" (`W:wayfinder`); for Loa the unit is the cycle, so chart only when the destination spans more than one cycle or when the PRD interview would be mostly `[ASSUMPTION]` rows.

**What Loa can do better than wayfinder.** Pocock's most-reported failure ("my agent started writing production code in the middle of a wayfinder session") stems from the map's Notes being writable by the constrained agent (`W:wayfinder`). Loa has the fences Pocock lacks: `question`-type beads carry no `sprint:` label so run mode never implements them; the implement gate asks on any App-Zone write with no RUNNING state (`implement-gate.sh:446-449`); `spiral-dispatch-guard` blocks inline implementation under `/spiraling`. A Loa decision map can make "plans and does not build" semi-mechanical rather than prose.

---

## 4. Focus (c): mechanical vs prompted on the build path

| Discipline | Pocock | Loa | Who is ahead |
|---|---|---|---|
| Red before green | Prose rule (`tdd/SKILL.md:36`) | `/bug` micro-sprint Task 1 "Verify test fails with current code" (`micro-sprint.md:23-31`); self-reported; `/implement` only "tests alongside" (`implementing-tasks/SKILL.md:231`); `validate-ac-verification.sh:10-14` "prevents ABSENT evidence, not FABRICATED evidence" | Pocock on text; nobody on mechanics |
| Seams agreed before tests | "No test is written at an unconfirmed seam" (`tdd/SKILL.md:22`); `to-spec` "Testing Decisions" section | Sprint template has ACs and tasks, no seams-under-test field (`sprint-template.md:49-58`) | Pocock |
| Refactor step | Belongs to review, not the loop (`tdd/SKILL.md:38`) | Forbidden unless asked (`karpathy-principles.md:76`); diff-size warn hook | different |
| Write fence | none | implement gate: `ask`, never deny, Write/Edit only, keyed on `.run/` RUNNING state, dead from cycle-050 until rc.3 (`CHANGELOG.md`, rc.3 §; `hooks-reference.md:187,232`) | Loa (partial) |
| Review-skill cannot write code | none | by zones + prose; no skill strips Write/Edit; `disallowed-tools` only removes NotebookEdit / git mutations (`reviewing-code/SKILL.md:8-9`, `red-teaming/SKILL.md:10-14`); lint WARNs (`validate-skill-capabilities.sh:596-617`) | Loa (partial) |
| Verdict integrity | none (no verdict) | LOA-VERDICT trailer + `verdict-derive.sh` one-way rule, consumed by `golden-path.sh:146-192`; invocation prompted | Loa |
| Skipping review/audit | nothing to skip | `adversarial-review-gate.sh` exit 2 on a Write-tool COMPLETED without a well-formed dissent artefact (`:5-24`); checks presence, not verdict; Bash `touch` unseen | Loa (partial) |
| Loop termination | "no convergence guarantee … don't loop until clean" (`docs/engineering/code-review.md:77`) | run loop until APPROVED with circuit breaker (same-issue 3 / no-progress 5 / 20 cycles / 8 h, `run-mode/SKILL.md:129-159`); the arithmetic is model-executed jq | Loa, but prompted |
| Fresh eyes | "Same context reviewing itself isn't review" (`:65`) | separate review skill, cross-model dissent, simstim fresh-eyes E2E (`phase-7.5-post-pr-validation.md:23-25`) | Loa |
| Two-axis separation | Standards vs Spec, never reranked across (`code-review/SKILL.md:76-80`) | one checklist, severity-bucketed | Pocock (presentation) |
| Diagnosis loop | ten loop shapes, hypotheses, instrument, prove mutation (`diagnosing-bugs/SKILL.md`) | triage → micro-sprint; no hypothesis loop; KF ledger for dead ends | Pocock on loop, Loa on memory |

Honest reading of the NEVER/ALWAYS tables (`sources/loa-gate-evidence.md` G10): of the implementation rows, two are hard blocks (`/spiraling` dispatch, manual tags), four are partial (`ask` or artefact-presence), and four are prose-only (TaskCreate, `/bug` for feature work, beads creation, bug eligibility). Pocock would call every row of his own set prose-only and say so; Loa's tables name their hook or validator per `no-history-in-rule-text.bats`. The gap is not honesty, it is that the implement gate "fail-asks" was dead for ~75 cycles before anyone noticed (`CHANGELOG.md` rc.3: "the App-Zone ask was validated away and 'fail-asks' was prose rather than mechanics"). A fence that is not tested end-to-end is Pocock-grade prose with extra bytes.

---

## 5. Focus (d): shared language, glossary and ADRs vs NOTES, ADRs and lore

Pocock's "verbosity" failure mode is answered by a tracked `GLOSSARY.md` that is "a glossary and nothing else" (`domain-modeling/SKILL.md:64`), with `_Avoid_` lists ("Be opinionated", `GLOSSARY-FORMAT.md:27`), updated inline the moment a term crystallises (`SKILL.md:60-62`), and read silently by every consumer ("If any of these files don't exist, proceed silently", `setup-matt-pocock-skills/domain.md:11`). His own repo's `GLOSSARY.md` is the specimen: four terms (Issue tracker, Issue, Decision ticket, Triage role), relationships, and "Flagged ambiguities" ("'backlog' was previously used to mean both the tool … and the body of work. Resolved").

Loa has the richest invented vocabulary of any framework in this comparison (Flatline, Bridgebuilder, dissent, voice, cheval, ICE, jack in, grimoire, lore, construct, beads, Karpathy, kaironic, run mode, zone) and no glossary. Definitions are scattered across lore YAML (`.claude/data/lore/`), the kernel, README, BUTTERFREEZONE (stale at `version: v1.147.0`, BUTTERFREEZONE.md:30) and skill prose. An agent new to the repo must grep for "voice". Lore is the nearest surface but names *patterns* and *metaphors* with a `loa_mapping` (`grimoires/loa/lore/patterns.yaml`), which Pocock would keep out of a glossary by rule.

ADRs: Pocock's bar (hard to reverse, surprising, real trade-off) and a 1–3 sentence template keep them cheap enough to write during grilling. Loa writes an ADR once per release epoch by hand (four in 127 cycles), and keeps the per-cycle "why" in NOTES prose that is gitignored and per-operator, so the team surface for decisions is the PR body. The unbuilt `decisions.yaml` spec already asks Pocock's question verbatim ("Would someone ask 'why?' about this in 6 months?", `decision-lineage.md:64`). The KF ledger shows Loa knows how to build a compounding memory properly (schema, writer lib with flock and append-only verification, generated INDEX, session-start surfacing, recurrence as the signal); decisions have none of that.

---

## 6. Focus (e): skill ergonomics

| Dimension | Pocock (27 promoted) | Loa (36 skills, 54 commands) |
|---|---|---|
| SKILL.md size | 157 B – 12,594 B; most 1–7 KB; wrappers are one line | 2,204 – 16,370 B; 12 skills within 340 B of the 16,384 cap (cap binds); full skill dirs up to 88 KB via `resources/` |
| Size governance | qualitative: sprawl, no-op test, "The document gets shorter as it gets better"; no eval | CI byte budgets (`check-prompt-budget.sh`), resource-charging rule, prompt-audit method, `no-history-in-rule-text` |
| Boilerplate | none | generated `@skill-include` / `@constraint-generated` blocks: 35 % of `implementing-tasks` (5,710 / 16,221 B), 26 % of `reviewing-code`, 23 % of `auditing-security`, 21 % of `discovering-requirements`; `context_discipline` stamped into 10 skills, `trajectory_logging` / `integrity_precheck` / `factual_grounding` into 7 each |
| User- vs model-invoked | explicit per skill: `disable-model-invocation: true` + Codex `allow_implicit_invocation: false`; human-facing vs trigger-rich descriptions; invariant "no other skill can call a user-invoked skill" (`.agents/invocation.md`) | no flag on any SKILL.md; one of 54 commands (`gpt-review.md:4`) sets `disable-model-invocation`; so `/ship`, `/update-loa`, `/loa-eject`, `/mount` are model-invocable in principle |
| Composition | "Call the Skill tool with 'grilling'" (22 operative calls); sibling files for disclosure | slash-command names in orchestrator prose; file hand-offs (prd → sdd → sprint → a2a feedback) gated by `verdict-derive.sh`; no `Skill(` calls |
| Router | `ask-matt` by topic | `/loa` by artifact state |
| Distribution | Claude official marketplace, own `marketplace.json`, Codex / Copilot / Gemini, `npx skills`; changesets + `sync-plugin-version.mjs`; "pick one" of plugin vs editable copy | `mount-loa.sh` curl pipe, submodule / vendored, `.loa-version.json`, `checksums.json`, `/update-loa`, semver via post-merge; no plugin manifest; constructs as the pack format with a registry API |
| Statelessness | `grill-me`, `grilling`, `to-questionnaire`, `wait-what` write nothing; `handoff` writes to `$TMPDIR` | 15 skills `write_files: false`, several still persist via scripts; no stateless interview |
| Scope governance | `SCOPE.md` "observed failure" bar + `.out-of-scope/` one file per rejected concept with prior requests | KF ledger for failures; no rejected-concepts registry; GitHub issues |
| Harness neutrality | refuses AskUserQuestion, names no Claude tool types (1.2.3 #781) | Claude-Code-native by design (hooks, AskUserQuestion, settings.json) |

Two ergonomics facts stand out. First, Pocock keeps skills small by *delegation*: `grill-me` is 157 bytes because `grilling` owns the technique. Loa's five core skills are each a self-contained 16 KB with 2–6 KB of shared preamble; the cycle-116 diet moved lookup tables to `resources/` (−20.7 %, commit `4dcfc770`) but the includes stayed. Second, Pocock's invocation axis is a safety property as much as an ergonomic one: the human is "the index that has to remember they exist" for user-invoked skills (`.agents/writing-docs.md`), and the model cannot fire them. Loa's equivalent property for its outward and destructive commands is carried by hooks and prose, not by the flag that already exists in the harness.

---

## 7. Where the sources are thin

- `W:grill-me` publishes no prompt template; the technique lives only in `P:skills/productivity/grilling/SKILL.md` (30 lines). This review quotes that file, not the article, for mechanics.
- Pocock's CHANGELOG headings carry no dates; the shallow clone has no tags. Release dates beyond HEAD (2026-10-09) are unknown.
- The web articles report user failures ("one user reported…") without links to issues; where this review repeats them it cites the article section, not an issue.
- No usage data exists on either side for "rounds reduce session length" or "autonomous PRDs produce worse requirements". Both are claims by their authors.
- `[UNVERIFIED]` Claude Code semantics assumed from the Pocock repo and Loa's rules: `disallowed-tools` removes tools from the model while `allowed-tools` only pre-approves; `disable-model-invocation: true` hides a skill or command from the Skill tool. Loa's `skill-invariants.md` relies on the former; `gpt-review.md` on the latter.

## Evidence files

- `sources/loa-planning-evidence.md` (Q1–Q10), `sources/loa-gate-evidence.md` (G1–G10), `sources/loa-memory-ergonomics-evidence.md` (M1–M6, S1–S7), `sources/pocock-skills-inventory.md` (§1–§18). All read-only; all cites verified against `main` @ `76e7650b`.
