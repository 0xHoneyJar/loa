# Product Requirements Document: Decision Surfaces (cycle-128)

**Version:** 1.0
**Date:** 2026-10-13
**Author:** PRD Architect Agent (Claude Fable 5.1, unattended)
**Status:** Draft — autonomous run (maintainer standing instruction 2026-10-13: *"proceed with admin preapproval deliver end to end"*; the interview phases were answered from the brief, no operator questions; every decision taken on the operator's behalf is listed in Appendix E with `decided_by: agent`, which is the discipline FR-2 makes mechanical)
**Brief:** `grimoires/loa/context/cycle-128-brief.md` (copy of `grimoires/loa/a2a/skills-review-2026-10/prd-brief.md`)
**Branch:** `feature/cycle-128-decision-surfaces` from `main` `76e7650b` (v2.0.0-rc.3)

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Problem Statement](#problem-statement)
3. [Goals & Success Metrics](#goals--success-metrics)
4. [User Personas & Use Cases](#user-personas--use-cases)
5. [Functional Requirements](#functional-requirements)
6. [Non-Functional Requirements](#non-functional-requirements)
7. [User Experience](#user-experience)
8. [Technical Considerations](#technical-considerations)
9. [Scope & Prioritization](#scope--prioritization)
10. [Success Criteria](#success-criteria)
11. [Risks & Mitigation](#risks--mitigation)
12. [Timeline & Milestones](#timeline--milestones)
13. [Appendix](#appendix)

> Sources: discovering-requirements/resources/templates/prd-template.md:10-24 (section order)

---

## Executive Summary

Loa plans build slices well and decisions badly. The 2026-10-12 review of Matt Pocock's skills against Loa (`grimoires/loa/a2a/skills-review-2026-10/comparison.md`) found that the framework has no trackable unit for a decision, no record of which planning answers a human gave and which the agent took on the operator's behalf, no route for a question that talking cannot settle, a discovery interview that asks one question per turn in fixed topic order, and no glossary for the richest invented vocabulary of any framework compared. The task tracker already carries an unused `question` issue type, and a decision ledger (`DEC-NNNN`) was specified in `docs/architecture/decision-lineage.md` in February 2026 but never built while two scripts still read for it.

This cycle adds the missing decision surfaces without touching the sanctioned build path: round-based questioning with a fact/decision split (FR-1, FR-2); the decision ledger (FR-3); a `/chart` phase that maps a multi-cycle effort as decision tickets on beads and cannot carry execution (FR-4); prototype tickets and a spike discipline for ungrillable questions (FR-5); a glossary convention dogfooded on Loa itself (FR-6); declared test seams and a verifiable red-before-green check for bug micro-sprints (FR-7); and the harness flag that keeps operator-only commands out of the model's reach (FR-8).

Expected impact: every decision Loa takes during planning becomes findable and attributable; multi-cycle efforts stop living in notes prose; the interview gets shorter in turns without getting shallower; and the review gains two verifiable checks it currently takes on the implementer's word.

> Sources: cycle-128-brief.md:1-40, skills-review-2026-10/comparison.md §2–§6, skills-review-2026-10/proposals.md ADOPT/ADAPT

---

## Problem Statement

### The Problem
Loa's planning chain (PRD → SDD → sprint plan → beads) produces build tasks with acceptance criteria and nothing else. Decisions, open questions and their resolution are prose in `grimoires/loa/NOTES.md` (140 KB, gitignored, per-operator, above its own 100 KiB warn line), in debrief bullets, in 29 ad-hoc files under `grimoires/loa/proposals/`, and in four release-epoch ADRs. The SDD's `## 10. Open Questions` table carries `Status: Open/Resolved` with no link to what resolved a question. Nothing graduates a fog-of-war item into a decision.

### User Pain Points
- Cycles 124 → 127 were one arc coordinated by NOTES prose, memory files and a carry-over bead (`bd-b4ji`) that recurred across three cycles; cycle-127 was three decisions run as a full PRD/SDD/sprint (`NOTES.md` Decision Log 2026-10-07, D1–D3).
- Unattended planning answers its own interview (`karpathy-principles.md:30-35`, `autonomous-agent/SKILL.md:66`, NOTES.md cycle-125 kickoff: "no operator questions (autonomous)"); facts the agent looked up and decisions it took for the operator both become `[ASSUMPTION]`, so "which of these did a human decide?" has no mechanical answer (NOTES.md cycle-126 kickoff: "Design calls made without the operator").
- A question that cannot be settled by talking (cycle-127 D3, the ceiling probe) has no artifact type; it is scheduled as prose and executed by hand.
- The interview asks one question per turn in fixed PRD-section order (`discovering-requirements/SKILL.md:85,263-275`); `batch` pacing presents 3–6 questions with no independence rule, so a batch can contain a question whose answer another question in the same batch invalidates.
- Reviewers take "test fails before the fix" and "tests exist at the right seam" on the implementer's word (`validate-ac-verification.sh:10-14` "prevents ABSENT evidence, not FABRICATED evidence").
- An agent new to the repo must grep for "voice", "dissent", "ICE", "jack in"; definitions are scattered across lore YAML, the kernel, README and skill prose; `BUTTERFREEZONE.md` is stale at v1.147.0.
- One of 54 commands carries `disable-model-invocation` (`gpt-review.md:4`); `/ship`, `/update-loa`, `/loa-eject`, `/mount` are model-invocable in principle.

### Current State
Decisions: prose, unlinked, per-operator. Multi-cycle efforts: no map; the ledger's cycle record has no parent link. Beads: `task`/`epic`/`bug`/`feature` only (816/56/56/13 live), `question` unused. Interview: seven fixed phases, `sequential` default. Prototypes: one hand-written spike report (`grimoires/loa/spikes/cycle-096-sprint-0-bedrock-contract.md`), no template. Glossary: none (only the lore mythic glossary). Test discipline: prompted in `/implement`, "non-negotiable" prose in `/bug`.

### Desired State
A decision is a first-class, tracked, attributable record. A multi-cycle effort is a map of decision tickets on beads that the run loop cannot implement. The interview asks the whole settled frontier per round with a recommended answer. An ungrillable question is a prototype ticket with a spike branch and a verdict row. The framework and each project have a small opinionated glossary. Review verifies seams and red-before-green from artefacts, not self-report. Operator-only commands are unreachable to the model.

> Sources: comparison.md §2 (a), §3 (b), §4 (c), §5 (d), §6 (e); sources/loa-planning-evidence.md Q2, Q4, Q5, Q7; sources/loa-gate-evidence.md G1, G10; sources/loa-memory-ergonomics-evidence.md M1–M3, S3

---

## Goals & Success Metrics

### Primary Goals

| ID | Goal | Measurement | Validation Method |
|----|------|-------------|-------------------|
| G-1 | Every decision taken during planning is recorded with who decided it | `DEC-NNNN` rows in `grimoires/loa/decisions.yaml` with `decided_by`; unattended PRD assumptions that are decisions each have a row; the PR body lists them | bats over a fixture unattended run; `validate-artifact.sh --type decisions` |
| G-2 | A multi-cycle effort has a decision map that plans and cannot build | `question` beads under a `map` epic never carry `sprint:` labels; run mode never selects them | lint in `create-sprint-task.sh` + bats; `br --dry-run` fixture map |
| G-3 | The interview asks in prerequisite-ordered rounds | fixture transcript in `rounds` mode: ≥ 2 questions per round on average, no pair in a round where one depends on the other | scripted headless transcript, manual rubric (no interview eval exists) |
| G-4 | Ungrillable questions become prototype tickets with a spike discipline | `decision:prototype` beads; `spike/<slug>` branches; a validated spike report; a `DEC` verdict row | validator bats; fence corpus case (spike push allowed, merge refused) |
| G-5 | Shared vocabulary exists and does not rot | root `GLOSSARY.md`; every backticked framework term in `CLAUDE.loa.md` resolves to an entry | kernel-term drift check in CI |
| G-6 | Review verifies test discipline from artefacts | sprint plans declare seams under test; `/bug` micro-sprints show red-then-green by commit | `validate-artifact --type sprint`; `red-test-check.sh` bats with a decoy |
| G-7 | Operator-only commands are unreachable to the model | leaf operator commands carry `disable-model-invocation: true`; no other body executes them as a step | bats lint over an allowlist |

### Key Performance Indicators (KPIs)

| Metric | Current Baseline | Target | Timeline | Goal ID |
|--------|------------------|--------|----------|---------|
| Decision rows with `decided_by` for unattended planning decisions | 0 (prose only) | 100 % of `[ASSUMPTION]` decisions in this cycle's own PRD/SDD | Sprint 1 | G-1 |
| `question` beads with a `sprint:` label | n/a (type unused) | 0, enforced | Sprint 2 | G-2 |
| Questions per round in `rounds` mode (fixture) | 1 (`sequential`) | ≥ 2 average | Sprint 1 | G-3 |
| Framework terms in the kernel without a glossary entry | all (no glossary) | 0 | Sprint 3 | G-5 |
| `/bug` red-before-green evidence | self-reported AC row | script-verified | Sprint 3 | G-6 |
| Commands with `disable-model-invocation` | 1 of 54 | every zero-reference leaf operator command | Sprint 1 | G-7 |
| Prototype-class questions recorded as `[ASSUMPTION]` | n/a (no class) | 0; spike reports validating 100 % | Sprint 2 | G-4 |
| `[ASSUMPTION]` rows in a multi-cycle PRD (baseline cycle-126 PRD: measured at plan time, see Appendix F) | cycle-126 count | fewer on the next charted effort | 30 days | G-2 |

### Constraints
- The sanctioned path is untouched: `/review-sprint`, `/audit-sprint`, the LOA-VERDICT one-way rule, the dissent artefact gate and the implement gate's decisions do not change.
- Every touched `SKILL.md` stays ≤ 16,384 B under `tools/check-prompt-budget.sh`; `discovering-requirements/SKILL.md` has 80 B of headroom today.
- `.claude/` edits are framework self-development under the cycle zone marker (created 2026-10-13, expires 2026-10-20); tests follow the existing bats/pytest suites.
- Subagents Opus 5.5 only; review and audit on Fable 5.1; ≤ 3 dissent runs per sprint.

> Sources: cycle-128-brief.md §Goals, §Success criteria; comparison.md §6 (budget headroom); sources/loa-planning-evidence.md Q4 (bead type counts)

---

## User Personas & Use Cases

### Primary Persona: Loa maintainer running unattended cycles

**Demographics:**
- Role: sole maintainer and operator of a self-developing framework; delegates whole cycles with standing preapproval
- Technical Proficiency: expert; reads diffs, trailers and ledgers, not transcripts
- Goals: know which decisions were made for them, by whom, and why, without reading NOTES prose

**Behaviors:**
- Reviews PRs and release notes; signs off on "weighted decisions" after the fact
- Carries multi-cycle arcs in memory files and carry-over beads

**Pain Points:**
- Decisions made without them are a sentence in a gitignored file
- A cycle's open questions vanish into the archive with the SDD

### Secondary Persona: Operator planning a feature interactively

**Demographics:**
- Role: developer using `/plan` on their own project
- Technical Proficiency: intermediate to expert
- Goals: a sharp PRD in few turns; a way to say "I need to see it" without faking an answer

### Use Cases

#### UC-1: Unattended planning records its decisions
**Actor:** Maintainer (absent) / agent
**Preconditions:** a brief in `grimoires/loa/context/`; run unattended
**Flow:**
1. The interview classifies each pending question as fact or decision
2. Facts are looked up (`/ride` reality, repo, Explore subagent); decisions are answered on the documented assumption
3. Each self-answered decision writes a `DEC` row with `decided_by: agent` and appears in the PRD appendix and the PR body
**Postconditions:** the maintainer can list every decision taken on their behalf
**Acceptance Criteria:**
- [ ] Rows exist for every decision-class `[ASSUMPTION]`
- [ ] The PR body section "Decisions taken on your behalf" matches the rows

#### UC-2: Charting a multi-cycle effort
**Actor:** Operator / agent
**Preconditions:** a loose idea whose destination spans more than one cycle
**Flow:**
1. `/chart` names the destination (a grilling round), then grills breadth-first for fog
2. If no fog surfaces, it stops and says the effort fits one cycle
3. Otherwise it creates the `map` epic, the specifiable `question` beads with labels and `br dep` edges, the map doc, and dispatches research subagents
4. Later sessions resolve one ticket each; the map doc's "Decisions so far" grows; fog graduates into tickets
5. When the frontier and the fog are empty, `/plan-and-analyze` consumes the map as priority-1 context
**Postconditions:** a PRD whose interview was mostly confirmation; a ledger of `DEC` rows linked to beads
**Acceptance Criteria:**
- [ ] No `question` bead ever carries a `sprint:` label
- [ ] `golden_detect_plan_phase` reports `charting` while the map is open

#### UC-3: An ungrillable question
**Actor:** Operator / agent
**Preconditions:** an interview question about look, feel or behaviour
**Flow:**
1. The operator answers "I need to see it", or the agent classifies the question as unanswerable by talking
2. A `decision:prototype` bead is created instead of an `[ASSUMPTION]`
3. The prototype is built HITL in a worktree on `spike/<slug>`, pushed, never merged, no PR
4. The spike report records question, what was built, verdict and pointer; the verdict becomes a `DEC` row
**Postconditions:** the decision is recorded; main carries only the decision
**Acceptance Criteria:**
- [ ] The spike report validates
- [ ] ICE allows the `spike/*` push and refuses its merge

#### UC-4: A `/bug` fix with verifiable red-before-green
**Actor:** Implementer / reviewer
**Flow:**
1. The micro-sprint commits the failing test first, then the fix
2. `red-test-check.sh` runs the named test at the red commit (fails) and at HEAD (passes)
3. The review cites the script's output for the "test fails with current code" criterion
**Acceptance Criteria:**
- [ ] A decoy that passes at both commits is rejected

> Sources: cycle-128-brief.md §Problem, §FR-2, §FR-4, §FR-5, §FR-7; proposals.md A2, B1, B3, B5; NOTES.md Decision Log 2026-09-24 and 2026-09-23 (observed unattended practice)

---

## Functional Requirements

### FR-1: Round-based, prerequisite-ordered questioning
**Priority:** Must Have
**Description:** Add `interview.pacing: rounds` to the discovery interview and the clarification phases of `/architect` and `/sprint-plan`; one `interview.pacing` key governs all three, `interview.per_skill` overrides remain, `minimal` mode keeps `batch`. A round is the whole frontier: every question whose prerequisites are already settled, numbered, each with a recommended answer phrased so that "yes" accepts it; a question that depends on another still open in the round belongs to a later round; the frontier is recomputed after each round. Answer semantics: a bare "yes" accepts every recommendation in the round; a numbered answer overrides that question; unanswered numbers default to the recommendation only after the agent restates them and the operator confirms. Each round carries a machine-readable comment block (`<!-- round: N; questions: [{id, depends_on: [...]}] -->`) so independence is checkable. `sequential` and `batch` remain; `rounds` becomes the default for `thorough`; `sequential` is documented as the one-at-a-time opt-out. The `discovering-requirements/SKILL.md` Mode Behavior and Input Style tables move to `resources/REFERENCE.md` behind a guarded pointer to make room.

**Acceptance Criteria:**
- [ ] `.loa.config.yaml.example` documents `pacing: rounds` with the frontier rule, the answer semantics, the key's scope and the `sequential` opt-out
- [ ] `discovering-requirements/SKILL.md` ≤ 16,384 B after the change (`check-prompt-budget.sh`)
- [ ] A fixture transcript in `rounds` mode carries the round comment blocks; `tools/check-round-independence.sh` finds no question whose `depends_on` names a question in the same round and reports ≥ 2 questions per round on average (bats over the fixture)
- [ ] `planning-sprints` Phase 2 and `designing-architecture` Phase 2 reference the same pacing rule

**Dependencies:** none

### FR-2: Fact / decision split and attribution
**Priority:** Must Have
**Description:** The Backpressure Protocol classifies each pending question as a **fact** (the agent must look it up: reality files, repo, docs, an Explore subagent) or a **decision** (the operator only). Every assumption tag names its class: `[ASSUMPTION fact]` or `[ASSUMPTION decision]`; the bare tag is a validator WARN for one release. Karpathy principle 1 and the autonomous-agent prime directive keep "record and proceed" for facts; for decisions in unattended runs the agent writes a `DEC` row (FR-3) that lands `status: proposed` with `decided_by: agent` regardless of any flag, and stays so until the operator confirms through the operator-only `/decisions` command. An implementer in a linked worktree writes a per-sprint pending file that the lead imports. In interactive runs, a decision the operator takes that passes the FR-3 row filter is written as `decided_by: operator`. The completion PR body gains a "Decisions taken on your behalf" section rendered by `dec-write-lib.sh list --not-decided-by operator --cycle <cycle> --format md` (agent, Flatline and dissent rows, with a Voice column), never hand-filled. The PRD and SDD templates gain the same appendix, populated from the ledger.

**Acceptance Criteria:**
- [ ] `discovering-requirements/SKILL.md:90` (Backpressure Protocol) states the fact/decision rule and the tag classes in ≤ 3 lines
- [ ] `karpathy-principles.md` §1 and `autonomous-agent/SKILL.md` prime directive name the `DEC` row as the unattended record for decisions
- [ ] `run-mode/resources/render-templates.md`, `prd-template.md` and `sdd-template.md` carry the section, rendered from the ledger by the `list` subcommand
- [ ] `validate-artifact.sh --type prd` fails when a `[ASSUMPTION decision]` tag has no `DEC` row whose `source` names the PRD (unattended cycles only; interactive cycles WARN)
- [ ] A fixture unattended PRD produces N `decided_by: agent` rows equal to its `[ASSUMPTION decision]` tags (bats)

**Dependencies:** FR-3

### FR-3: Decision ledger
**Priority:** Must Have
**Description:** Build `grimoires/loa/decisions.yaml` per `docs/architecture/decision-lineage.md` (`id: DEC-NNNN`, `phase`, `category`, `summary`, `decision`, `rationale`, `alternatives_considered`, `consequences`), adding provenance and lifecycle fields: `decided_by: operator|agent|flatline|dissent` (null while `open`; in an unattended context every write lands `proposed` with `agent` regardless of flags; `operator` is possible only interactively and only through the operator-only `/decisions` command; `flatline` and `dissent` rows cite an artifact path whose sha256 is recorded), optional `decided_by_ref` with an enforced grammar, `recorded_by` (skill or command plus session id), `created_at`, `updated_at`, `commit` (HEAD at write), `source` (bead id, PR, NOTES anchor, spike path, with a line or anchor), `supersedes`, `status: open|proposed|decided|superseded|rejected`, and `transitions: [{at, from, to, by, evidence}]`. Rows are append-only: content fields are immutable after creation (alternatives and consequences may be set at decide time), status changes append a transition with `by` and `evidence`, `supersede` creates a new row, `reject` records a rejection rationale and a follow-up (bead id or NOTES anchor) so corrections propagate to beads, maps and plans; superseding or rejecting a `decided` operator row is itself an operator act (an agent may only propose it). Attribution is tamper-evident (hash, commit, append-only transitions), not cryptographically signed; signing is a future iteration. Row filter: every unattended agent decision gets a row; interactive rows need Pocock's three conditions (hard to reverse, surprising without context, a real trade-off; all three). Writer: `.claude/scripts/lib/dec-write-lib.sh` (`new`, `decide`, `confirm`, `reject`, `supersede`, `import`, `list`, `context`) modelled on `kf-write-lib.sh` (a portable lock, `flock` when present, append-only verify, atomic rename), checking `jq` and Mike Farah `yq` v4 (a new hard dependency for the ledger) and failing closed; in a linked worktree it writes `grimoires/loa/a2a/sprint-<N>/decisions-pending.yaml` with provisional ids and the lead imports it in the main checkout, which is the only place real ids are allocated; hook- or CI-driven writes exit 1 mechanically (`CI`, `GITHUB_ACTIONS` or a hook marker). The unattended context is read from the run-state markers, an unattended marker carrying the session id and a TTL, the autonomous Flatline mode and the PRD Status line, so the writer and the PRD validator agree. `grimoire-index.sh` gains a `## decisions` section; a SessionStart hook surfaces `status: proposed|open` rows behind `decisions.surface_at_session_start` (default false). `.gitignore:149` is negated so the ledger is tracked; `validate-gitignore-state.sh` gains the row. `validate-artifact.sh --type decisions` checks the schema, duplicate ids, the transition invariants, the ref grammars and hashes, and `decided_by` consistency (an `operator` row in an unattended cycle is a violation). The operator-only command `.claude/commands/decisions.md` (`/decisions confirm|reject|supersede|list`, `disable-model-invocation: true`) is the only path for operator transitions and joins the FR-8 flagged set. Backfill is forward-only except cycle-127 D1–D3 (NOTES Decision Log 2026-10-07); every seed row, those three included, lands `proposed` because the standing admin preapproval is not per-row confirmation; the operator confirms with `/decisions confirm`. NOTES Decision Log entries point at rows; release-epoch ADRs are unchanged. `status: rejected` rows carry `prior_requests` (issue or request references) and replace a rejected-concepts registry. The SDD `## 10. Open Questions` table gains a `DEC` column; `validate-artifact --type sdd` WARNs when a Resolved row has none.

**Acceptance Criteria:**
- [ ] `dec-write-lib.sh new|decide|confirm|reject|supersede|import|list|context` with evidence required on `decide` and `confirm`, rationale and follow-up required on `reject`; bats mirror the kf-write-lib suite (never shrinks, never drops an id, lock held, failed write leaves the file intact, missing `jq`/`yq` fails closed, a hostile-string corpus round-trips, a linked worktree writes the pending file and `import` allocates real ids)
- [ ] In an unattended context every write lands `proposed` with `decided_by: agent` whatever the flags (bats with each unattended signal); `confirm`, `context --clear` and `supersede` of a `decided` row are reachable only through `/decisions` (no skill's `allowed-tools` grants them; bats over the frontmatter)
- [ ] `grimoires/loa/decisions.yaml` tracked; `validate-gitignore-state.sh` passes
- [ ] `grimoire-index.sh` emits `## decisions` with ID / status / decided_by / summary / source; the SessionStart surface prints nothing when the key is off
- [ ] `validate-artifact.sh --type decisions` passes on the live file and fails on a missing `decided_by`, a content edit to an existing row, or a `rejected` row without a follow-up
- [ ] `loa-learnings-index.sh` and `path-lib.sh` readers resolve the live file without change or with a one-line fix

**Dependencies:** none

### FR-4: Decision map (`/chart`)
**Priority:** Must Have
**Description:** A truename command `/chart` with skill `charting-decisions` for efforts whose destination spans more than one cycle; it is HITL and refuses in unattended mode with a clear message. Charting: name the destination by a grilling round; grill breadth-first for fog; stop with "fits one cycle" if none surfaces; else create a `map` epic bead (label `map`), one `--type question` child bead per specifiable decision labelled exactly one of `decision:grilling|prototype|research|unblock`, `br dep` edges in a second pass, a tracked map doc `grimoires/loa/maps/<slug>.md` with Destination / Decisions so far / Not yet specified / Out of scope and **no execution override**, and research subagents (Opus, read-only repo plus WebFetch, writing only `grimoires/loa/research/<slug>.md` with cites, no `br` or ledger writes; the charting session closes the ticket after reading the report). Write order on every ticket: `DEC` row (`status: open`, `source` = bead id) → bead → map doc, so a partial failure leaves an open row pointing at what exists and a re-run is idempotent by `source`. Working: load the map doc, take the user's ticket or the first frontier ticket (`get-ready-work.sh --graph` filtered to the map), claim it (`br update --status in_progress`), resolve it as its label's type, record the resolution (`br comments add`, `br close`, `dec-write-lib.sh decide` on the open row, one line in Decisions so far), graduate fog, rule out of scope; never more than one ticket per session except research. A `decision:unblock` ticket may run read-only probes and throwaway worktrees only; it never writes App-Zone code and its body names the decision it unblocks. Lifecycle: a map closes when `/plan-and-analyze` consumes it (the map doc gains `## Closed` with the cycle id and the epic is closed) or by `/chart close <map>`; a chart that yields fewer than three tickets is closed as won't-do with a reason comment; with more than one open map `/plan` asks interactively which to consume and refuses unattended; maps open more than 30 days are listed by the SessionStart surface. Hand-off: when the frontier and fog are empty, `/plan-and-analyze` consumes the map doc and its `DEC` rows as priority-1 context; `golden_detect_plan_phase` returns `charting` while a `map` epic is open and `discovery` again once it is closed. Lint: `create-sprint-task.sh` and `validate-artifact --type sprint` reject a `question` bead under a sprint epic or with a `sprint:` label, and run-mode work selection (`get-ready-work.sh` and the implement path) excludes `question` beads regardless of labels.

**Acceptance Criteria:**
- [ ] `/chart` with a one-cycle idea stops without creating beads; `/chart` in an unattended context refuses (fixtures)
- [ ] A fixture map creates the epic, children, labels, edges and open `DEC` rows (`br --dry-run`) and the map doc validates (`validate-artifact --type map`)
- [ ] A `question` bead with a `sprint:` label or under a sprint epic is rejected by the lint, and `get-ready-work.sh` never returns a `question` bead (bats)
- [ ] `golden-path.sh` returns `charting` with an open map, `discovery` without, and `discovery` again after `## Closed` (bats)
- [ ] `charting-decisions/SKILL.md` ≤ 16,384 B; capability frontmatter passes `validate-skill-capabilities.sh`; `write_files: true` scoped to `grimoires/loa/maps`, `grimoires/loa/research`, `grimoires/loa/decisions.yaml`, `.beads`

**Dependencies:** FR-1 (rounds), FR-3 (ledger)

### FR-5: Prototype tickets and spikes
**Priority:** Must Have
**Description:** In an interactive interview, a question the operator answers "I need to see it", or one the agent proposes as unanswerable by talking and the operator confirms, becomes a `decision:prototype` bead, never an `[ASSUMPTION]`. In an unattended run the agent creates the `decision:prototype` bead, writes a `DEC` row with `status: open`, marks the dependent requirement deferred in the PRD with a pointer to the bead, and continues (`interview.unattended_prototype: defer|halt`, default `defer`). The prototype runs HITL in a `git worktree` on `spike/<slug>`, pushed, never merged, no PR; `run-mode-ice.sh` allows `spike/*` pushes, refuses merging a `spike/*` branch into any other branch, and allows merging or rebasing `main` into a spike branch; a spike branch may be deleted once its verdict row is `decided`. The spike report (`grimoires/loa/spikes/TEMPLATE.md`: Question / What was built / Verdict / Pointer / Decided by) and the verdict `DEC` row are written and committed on the working branch, never on `spike/*`. `validate-artifact.sh --type spike` checks the report. `planning-sprints/resources/REFERENCE.md` "High-Risk Early" points at prototype tickets instead of scheduling spikes inside build sprints.

**Acceptance Criteria:**
- [ ] The interview rule is present in `discovering-requirements`, `designing-architecture`, `planning-sprints` (≤ 2 lines each) and the unattended behaviour is config-gated
- [ ] `validate-artifact --type spike` passes the template and fails on a missing verdict
- [ ] Fence corpus: `spike/x` push allowed; merging `spike/x` into another branch refused by ICE; merging `main` into `spike/x` allowed (bats)
- [ ] The verdict row is written through `dec-write-lib.sh decide` with `source` = the spike path and is present on the working branch after the spike is pushed (fixture)

**Dependencies:** FR-3

### FR-6: Glossary convention
**Priority:** Should Have
**Description:** Two glossaries, one format (context line, `## Language`, `**Term**:` one–two sentence definition, optional `_Avoid_` and `_Aliases_` lines, implementation-free). The framework glossary ships at `.claude/loa/GLOSSARY.md` (mounted into every project) and seeds Loa's vocabulary (Flatline, voice, dissent, Bridgebuilder, cheval, ICE, jack in, grimoire, lore, construct, beads, run mode, zone, Karpathy principles, kaironic, implement gate, verdict trailer, known failure, decision ticket, map epic, seam, spike, the four `decision:` labels). A project glossary lives at the project root `GLOSSARY.md`, created lazily; in this repo it holds the repo-development terms (record branch, zone marker, cycle). `discovering-requirements` Phase 1 and `designing-architecture` challenge terms against both and update the project glossary inline; `riding-codebase` reads them as reality inputs; `reviewing-code` flags new undefined terms as LOW. `validate-artifact.sh --type glossary` checks the format. `tools/check-glossary-terms.sh` asserts every backticked framework term in `CLAUDE.loa.md` resolves to a framework-glossary entry: tokens containing `/`, `.`, `--`, `:` or `(` or starting with `/` are excluded (paths, scripts, flags, commands, config keys), matching is case-insensitive with plural `s`/`es` and `_Aliases_` entries, and `.claude/data/glossary-allowlist.txt` holds at most 30 entries. The check runs in this repo's CI only. Lore stays separate.

**Acceptance Criteria:**
- [ ] `.claude/loa/GLOSSARY.md` validates and covers every kernel term (drift check green in CI; allowlist ≤ 30)
- [ ] Planning skills carry the challenge/update rule (≤ 3 lines each; budgets green)
- [ ] `reviewing-code` checklist row for undefined new terms

**Dependencies:** none

### FR-7: Seams under test and verifiable red-before-green
**Priority:** Should Have
**Description:** `sprint-template.md` gains a per-sprint `### Seams Under Test` block (seam, catches, misses, prior art); `planning-sprints` Phase 2 asks it as a round; `validate-artifact.sh --type sprint` requires the block for plans whose header `Date` is on or after 2026-10-13 (older and undated plans WARN only; cycle-128's own plan carries the block at plan time); `reviewing-code` spec axis checks that tests exist at each declared seam. The `/bug` micro-sprint template requires two commits (failing test first); `.claude/scripts/red-test-check.sh --red <commit> [--green <rev>] [--test-file <path>] [--setup <cmd>] [--timeout <s>] -- <test command...>` runs the test command at the red commit in a detached temporary worktree (dependency directories symlinked from the live tree or prepared by `--setup`; must fail) and at the green commit (must pass), prints the red output, exits 3 when the test passes at the red commit (decoy), 4 when the named test file is absent at the red commit or the red run is a collection, compile or import error rather than an assertion failure where the runner's output shows the difference, and reports `TIMEOUT` when a run exceeds the limit (`timeout` or `gtimeout`, else a bash wrapper); `reviewing-code` cites its output for the "test fails with current code" criterion.

**Acceptance Criteria:**
- [ ] Sprint validator fails on a missing Seams block for a plan dated on or after 2026-10-13 and still passes the archived cycle-127 plan and the undated fixtures; this cycle's `sprint.md` carries one per sprint
- [ ] `red-test-check.sh` bats: red+green passes; a decoy passing at both commits exits 3; a test file missing at the red commit exits 4; the red output is printed
- [ ] `micro-sprint.md` Task 1 requires the separate red commit

**Dependencies:** none

### FR-8: Operator-only commands unreachable to the model
**Priority:** Should Have
**Description:** `disable-model-invocation: true` on leaf operator commands. The first task of Sprint 1 verifies on the live harness that the flag hides a command from the Skill tool; if it does not, FR-8 becomes a lint-only convention and the lint still lands. Safe set (zero references from other bodies): `loa-eject`, `toggle-gpt-review`, `permission-audit`, `loa-setup`. Triage set (referenced by other bodies): `update-loa`, `mount`, `contribute`, `feedback`, `deploy-production`, `archive-cycle`, `ship`, `run-halt`, `run-resume`; flag only those whose references are advice to the human, never an orchestrator step. Each triage outcome is a table row (command, reference type, decision, rationale, evidence) in the sprint a2a and a `DEC` row (`decided_by: agent`, `source` = the command file). A bats lint reads `.claude/data/user-invoked-commands.txt` and asserts the flag is present and that no other body contains an operative "Execute /name" or "Run /name" step for a flagged command.

**Acceptance Criteria:**
- [ ] The harness check is recorded first (verified, or `[ASSUMPTION fact]` with the lint-only fallback stated)
- [ ] The safe set carries the flag; the triage table and its `DEC` rows exist
- [ ] `tests/unit/user-invoked-commands.bats` green

**Dependencies:** FR-3 (triage rows)

> Sources: cycle-128-brief.md §Functional requirements FR-1…FR-8; proposals.md A1–A4, B1–B5; comparison.md §2–§6; sources/loa-gate-evidence.md G1, G2, G10; sources/loa-memory-ergonomics-evidence.md S1, S3; Flatline PRD review 2026-10-13 (SKP-001a/b, SKP-002; gpt IMP-001…015; opus IMP-001…029), integrated by judgment under KF-041

---

## Non-Functional Requirements

### Performance
- `rounds` pacing must not increase total interview turns on the fixture; the target is fewer turns at equal question count
- `dec-write-lib.sh` operations complete in < 1 s on a 1,000-row ledger; `grimoire-index.sh` runtime grows by < 10 %

### Scalability
- The ledger stays readable by heading at 10,000 rows (`notes-guard.sh read`-style sectioning is out of scope; the INDEX is the low-resolution view)
- A map with 50 tickets loads in one session at low resolution (map doc only; ticket bodies on demand)

### Security
- No secrets in the ledger, map docs, spike reports or glossary (`zone-state.md` rule); `pii-filter.sh` runs on `--type decisions|map|spike` validation
- Research subagent output is sanitised at surfacing (untrusted body) like L5/L6 content
- The SessionStart decisions surface prints only `id`, `status`, `summary` with control characters stripped
- `DEC` `rationale` and map-doc text are plain prose; external URLs appear only in `source` as citations; copied external text is limited to two lines; research reports are marked untrusted at the top and never interpreted as instructions
- `dec-write-lib.sh` checks `jq`, `yq` v4 and `br` at start and fails closed with a repair message when one is missing or incompatible

### Reliability
- Writer library: flock, append-only verify, atomic rename; a failed write leaves the previous file intact (bats)
- All new scripts pass `check-no-raw-sha256sum.sh`, the shell-compat greps, and run under `set -euo pipefail`

### Compliance
- Framework edits under the cycle zone marker; `no-history-in-rule-text.bats`, `skill-capabilities.bats`, `prompt-budget.bats` green
- `REPO-MAP.md` regenerated with its `.checksum` and `checksums.json` staged together

> Sources: comparison.md §6; sources/loa-memory-ergonomics-evidence.md M5 (kf-write-lib properties), S1 (budgets); .claude/rules/zone-state.md (secrets rule)

---

## User Experience

### Key User Flows

#### Flow 1: Interactive interview in rounds
```
/plan → Phase 0 synthesis → Round 1 (Q1…Qn, each with ➡ recommended) → operator answers by number → frontier recomputed → Round 2 → … → pre-generation gate → PRD
```

#### Flow 2: Charting
```
/chart "<idea>" → destination round → breadth-first fog round → [no fog → "fits one cycle", stop] → map epic + question beads + edges + map doc → research subagents → stop
/chart <map> → load map → claim frontier ticket → resolve by type → DEC row + close + Decisions so far → graduate fog → stop
```

#### Flow 3: Ungrillable question
```
interview question → "I need to see it" → decision:prototype bead → worktree on spike/<slug> → look → one-line answer → spike report + DEC row
```

### Interaction Patterns
- Questions numbered, titled, with the recommended answer on its own line; "yes" accepts the recommendation
- Decisions referred to by name with the id in parentheses, never by a bare id
- `sequential` remains one line of config away

### Accessibility Requirements
- Plain-text rounds render in any terminal; structured AskUserQuestion gates remain configurable (`input_style`)
- Round size is bounded by the frontier, not by a cap; the operator may say "wrap up"

> Sources: cycle-128-brief.md §FR-1, §FR-4, §FR-5; P:skills/productivity/grilling/SKILL.md:8-30 (round format, quoted in comparison.md §1)

---

## Technical Considerations

### Architecture Notes
Everything new is State Zone data plus thin System Zone surfaces: one new skill (`charting-decisions`), one new command (`/chart`), one writer library (`dec-write-lib.sh`), one review-time script (`red-test-check.sh`), one CI check (`check-glossary-terms.sh`), one SessionStart surface, validator types (`decisions`, `map`, `spike`, `glossary`), small prose edits to four planning skills and the kernel protocol. The beads graph is the tracker; no new storage. The sanctioned path is untouched.

### Integrations
| System | Integration Type | Purpose |
|--------|------------------|---------|
| beads (`br` 0.2.6) | CLI (`create --type question`, `dep`, `update`, `comments add`, `close`) | decision tickets, frontier, claim |
| `grimoire-index.sh` / `loa-kf-surface.sh` pattern | generated INDEX section + SessionStart hook | surfacing decisions |
| `golden-path.sh` | new phase `charting` | `/plan` routing |
| `run-mode-ice.sh` | branch rule | `spike/*` push allowed, merge refused |
| `validate-artifact.sh` | new types | decisions, map, spike, glossary |
| `tools/check-prompt-budget.sh` | CI | skill budgets |

### Dependencies
- `br` 0.2.6 with `question` type and `dep` (present)
- `yq` (Mike Farah flavour) for the ledger writer; `jq` for INDEX
- Opus 5.5 route for research subagents (Agent tool `model: opus`)

### Technical Constraints
- `discovering-requirements/SKILL.md` headroom 80 B: tables must move to `resources/REFERENCE.md` first
- `.gitignore:149` ignores `grimoires/loa/decisions.yaml`; a negation and a `validate-gitignore-state.sh` row are required
- `disallowed-tools` is tool-granular; the charting skill's path scope is by zones and the implement gate's ask, not by tool removal

> Sources: sources/loa-memory-ergonomics-evidence.md M5, S1, S3; sources/loa-gate-evidence.md G2, G4; git check-ignore output 2026-10-13 (`.gitignore:149`)

---

## Scope & Prioritization

### In Scope (MVP)
- FR-1 rounds; FR-2 fact/decision split; FR-3 decision ledger; FR-4 `/chart`; FR-5 prototype tickets and spikes; FR-6 glossary; FR-7 seams and red-test check; FR-8 operator-only command flag

### In Scope (Future Iterations)
- Two-axis (Spec / Standards) presentation inside review feedback (proposals.md B7)
- Merge-danger line in PR templates (L5); expand–contract sequencing pattern (L8); "It's working if" tells in `/loa --help` (L3)
- Circuit-breaker arithmetic moved into `run-checkpoint.sh` (L6)
- Checks for the four prose-only NEVER/ALWAYS rows (L1)

### Explicitly Out of Scope
- Any change to `/review-sprint`, `/audit-sprint`, `verdict-derive.sh`, `adversarial-review-gate.sh` or the implement gate's decisions - Reason: the sanctioned path must not move while decision surfaces are added
- GitHub Issues as the decision tracker - Reason: beads is the single source of truth for task lifecycle
- Plugin-marketplace distribution - Reason: conflicts with mount, zone and integrity contracts
- Parallel implementer swarm inside `/run` - Reason: single-writer rules; a run-mode feature
- Removing AskUserQuestion or `sequential` pacing; question caps - Reason: configurable by design; both repos reject caps
- An "invest in design every day" skill - Reason: contradicts Karpathy principle 3 on purpose

### Priority Matrix

| Feature | Priority | Effort | Impact |
|---------|----------|--------|--------|
| FR-3 Decision ledger | P0 | M | High |
| FR-2 Fact/decision split | P0 | S | High |
| FR-4 `/chart` | P0 | L | High |
| FR-1 Rounds | P0 | S | Med |
| FR-5 Prototype tickets | P0 | M | Med |
| FR-7 Seams + red test | P1 | M | Med |
| FR-6 Glossary | P1 | M | Med |
| FR-8 Command flag | P1 | S | Med |

> Sources: cycle-128-brief.md §Non-goals; proposals.md REJECT R1–R8, LEARN L1–L8

---

## Success Criteria

### Launch Criteria
- [ ] All eight FRs' acceptance criteria met with `file:line` evidence in the sprint reports
- [ ] This cycle's own PRD and SDD decisions exist as `DEC` rows with `decided_by: agent` (Appendix E)
- [ ] `check-prompt-budget.sh` (including `charting-decisions/SKILL.md`), `skill-capabilities.bats`, `no-history-in-rule-text.bats`, `implement-gate.bats`, `verdict-derive.bats`, `validate-gitignore-state.sh`, `tools/check-glossary-terms.sh` and the bats for the four new `validate-artifact` types green
- [ ] CI green on the PR; one Bridgebuilder pass triaged; review and audit APPROVED per sprint

### Post-Launch Success (30 days)
- [ ] The next multi-cycle effort is charted; every decision taken without the operator is a `DEC` row and its PRD carries no more `[ASSUMPTION decision]` tags than the cycle-126 kickoff list in Appendix F (9)
- [ ] At least one `rounds` interview run by the maintainer with the opt-out not needed

### Long-term Success (90 days)
- [ ] NOTES Decision Log entries point at `DEC` rows rather than restating them
- [ ] The glossary drift check has blocked at least one undefined kernel term

> Sources: cycle-128-brief.md §Success criteria; comparison.md §3 (cycle-126 baseline)

---

## Risks & Mitigation

| Risk | Probability | Impact | Mitigation Strategy |
|------|-------------|--------|---------------------|
| `/chart` adds ceremony to an already heavy framework | Med | Med | Multi-cycle trigger only; mandatory no-fog stop; a chart under three tickets is deleted |
| `decision:unblock` drifts into build work (Pocock's `task` failure) | Med | High | Renamed; no `sprint:` label by lint; App-Zone writes ask; body must name the decision it unblocks |
| Ledger double-entry with NOTES | Med | Low | NOTES keeps narrative + `DEC` pointer; INDEX is the only place both appear |
| Glossary rots like BUTTERFREEZONE | High | Low | Kernel-term drift check in CI; glossary small by rule |
| `red-test-check.sh` gamed by a decoy | Low | Low | Reviewer reads the assertion; the script raises the floor from self-report to verifiable |
| Default pacing flip surprises operators | Med | Low | `sequential` documented as the opt-out; CHANGELOG entry; config example |
| Budget: `discovering-requirements` at 16,304 B | High | Med | Move two tables to `resources/REFERENCE.md` first; budget gate in CI |
| `disable-model-invocation` on a command an orchestrator needs | Low | High | Triage every referenced command; lint for operative references |
| Flatline cross-scoring degraded (KF-041) | High | Low | Integrate raw reviews by judgment; record the degradation |

### Assumptions
- [ASSUMPTION] `disable-model-invocation: true` hides a command from the Skill tool as it hides a skill; verified manually in Sprint 1 — if wrong, FR-8 becomes a lint-only convention
- [ASSUMPTION] `br` accepts `--type question` with labels and deps exactly like `task` (dry-run confirmed 2026-10-12 for type; labels/deps confirmed in Sprint 2)
- [ASSUMPTION] A SessionStart hook may be added under the cycle zone marker without a settings.json schema change beyond the existing hook list

### Dependencies on External Factors
- Mike Farah `yq` v4 on every host that writes the decision ledger (new hard dependency, D20)
- The cycle zone marker (framework self-development authorization) was granted 2026-10-13 after the maintainer enabled the required permission mode (KF-042 records the earlier denial)
- Opus 5.5 route available for research subagents and implementers

> Sources: proposals.md §Adversarial pass; KF-041 and KF-042 Reading guides (grimoires/loa/known-failures.md); comparison.md §6

---

## Timeline & Milestones

| Milestone | Target Date | Deliverables |
|-----------|-------------|--------------|
| Plan committed | 2026-10-13 | PRD, SDD, sprint plan validated; Flatline integrated; ledger and beads |
| Sprint 1 (global 252) | 2026-10-14 | FR-1, FR-2, FR-3, FR-8 |
| Sprint 2 (global 253) | 2026-10-15 | FR-4, FR-5 |
| Sprint 3 (global 254) | 2026-10-16 | FR-6, FR-7, E2E validation, docs, CHANGELOG |
| PR, Bridgebuilder, merge, rc | 2026-10-17 | next release candidate prepared and published as pre-release; cycle archived |

> Sources: cycle-128-brief.md §Shape; NOTES.md Decision Log 2026-10-07 (cycle-127 cadence)

---

## Appendix

### A. Stakeholder Insights
The maintainer's instruction (2026-10-13): "proceed with admin preapproval deliver end to end", following the review's exec summary (three imports, one rejection, next step). The review itself was requested on 2026-10-12 as planning only.

### B. Competitive Analysis
Matt Pocock's skills (plugin 1.3.1, 27 promoted skills, prose-only, no hooks): grilling rounds, wayfinder decision maps, prototype, to-spec/to-tickets, tdd, code-review, domain-modeling with GLOSSARY.md and one-paragraph ADRs. Loa is ahead on grounding, gates, cross-model review and memory; behind on decision surfaces and interview shape. Full comparison in `grimoires/loa/a2a/skills-review-2026-10/comparison.md`.

### C. Bibliography

**Internal Resources:**
- `grimoires/loa/a2a/skills-review-2026-10/comparison.md`, `proposals.md`, `prd-brief.md`, `sources/*.md`
- `docs/architecture/decision-lineage.md` (the unbuilt ledger spec)
- `grimoires/loa/known-failures.md` KF-041, KF-042, KF-037, KF-004

**External Resources:**
- https://github.com/mattpocock/skills (clone `49dd158d`, 2026-10-09)
- https://www.aihero.dev/skills-wayfinder, https://www.aihero.dev/skills-grill-me

### D. Glossary
| Term | Definition |
|------|------------|
| Decision ticket | A `question`-type bead under a `map` epic whose resolution is a decision, not a build slice |
| Map | The epic bead plus `grimoires/loa/maps/<slug>.md` indexing an effort's destination, decisions, fog and exclusions |
| Frontier | The open, unblocked, unclaimed decision tickets; also, in an interview, the questions whose prerequisites are settled |
| Fog of war | Decisions you can tell are coming but cannot yet phrase sharply; the map's "Not yet specified" section |
| Round | One frontier of interview questions asked together and answered together |
| Ungrillable | A question that talking cannot settle; resolved by a prototype |
| Spike | A throwaway prototype on a `spike/<slug>` branch answering one question |
| DEC row | One entry in `grimoires/loa/decisions.yaml` |
| Map epic | The `epic`-type bead labelled `map` that parents an effort's decision tickets |
| Seam | The public boundary a test exercises; declared per sprint under Seams Under Test |
| `decision:grilling` | A ticket settled by a HITL grilling round |
| `decision:prototype` | A ticket settled by a throwaway spike the operator reacts to |
| `decision:research` | A ticket settled AFK by a read-only research subagent's report |
| `decision:unblock` | A ticket that performs read-only or throwaway work so a decision can be made; never a build slice |
| Prior requests | On a `rejected` row, the issue or request references that asked for the rejected concept |

### E. Decisions taken on the operator's behalf (unattended planning)
Recorded here now and as `DEC` rows once FR-3 lands; each is `decided_by: agent` under the standing instruction.

| # | Decision | Alternatives | Why |
|---|----------|--------------|-----|
| D1 | `rounds` becomes the default pacing for `thorough`; `sequential` stays as the documented opt-out | keep `sequential` default, add `rounds` as opt-in | the brief recommended it; Pocock's 1.2.0 made the same flip with a supported opt-out |
| D2 | `decisions.yaml` lives at `grimoires/loa/decisions.yaml` and is tracked | `docs/architecture/decisions.yaml` | the original spec and two existing readers point there; team surface like `known-failures.md` |
| D3 | `/chart` is a truename command, not a golden-path porcelain command; `/plan` reports `charting` | add to the five porcelain commands | narrow trigger; Pocock calls wayfinder a situational on-ramp |
| D4 | Research tickets run as Opus subagents via the Agent tool, not cheval | cheval route | host-local, no provider dependency |
| D5 | Pocock's `task` type is named `decision:unblock` | keep `task` | the type that "goes wrong most often"; the name must not read as a build task |
| D6 | Spike branches are `spike/<slug>`, pushed, never merged, no PR | local-only worktrees | a pushed branch is the pointer the spike report needs; no PR keeps it off review |
| D7 | `GLOSSARY.md` at the repo root, tracked; Loa dogfoods it | `grimoires/loa/glossary.md` | root is where humans and Pocock's consumer rule look; the kernel drift check needs one path |
| D8 | FR-8 safe set = zero-reference leaves; the referenced set is triaged per reference | flag all operator commands | a flagged command an orchestrator executes as a step would break `/ship` |
| D9 | B7 two-axis presentation and the LEARN items are future iterations, not this cycle | fold into Sprint 3 | simplicity first; the eight FRs are the brief's scope |
| D10 | Two glossaries: the framework glossary ships at `.claude/loa/GLOSSARY.md` (drift-checked against the kernel in this repo's CI); the project glossary is the root `GLOSSARY.md` (amends D7) | one root file for both | consumer projects need the framework terms mounted, and their own terms must not live in the System Zone (Flatline opus IMP-009) |
| D11 | Unattended prototype-class questions defer by default (`interview.unattended_prototype: defer`): open `DEC` row, `decision:prototype` bead, requirement marked deferred; the run continues | halt the run | a halt on every look-and-feel question would stall unattended planning; the deferred requirement is visible in the PRD and the ledger (Flatline gpt IMP-004, opus IMP-004) |
| D12 | `/chart` refuses in unattended mode; research tickets are the only AFK work in a map | allow the agent to answer destination and fog rounds | a charted map whose questions the agent answered is the wayfinder failure pattern by construction (Flatline opus IMP-020) |
| D13 | Agent decisions are `status: proposed` until `dec-write-lib.sh confirm` by the operator; the standing admin preapproval authorises shipping, not confirmation of each row | treat the PR merge as confirmation | confirmation must be explicit and auditable per row (Flatline SKP-001a) |
| D14 | `decided_by` is derived by the writer from run context; `operator` needs an `--answer-ref` | caller argument | self-reported attribution is unfalsifiable (Flatline SKP-001b) |
| D15 | Rows are append-only with status transitions; content edits are rejected; `supersede` creates a new row | editable rows | a decision history that can be rewritten is not a record (Flatline SKP-002) |
| D16 | Backfill is forward-only except cycle-127 D1–D3, seeded like every other seed row as `proposed` | backfill all NOTES decisions; seed them `decided` | three rows give the validator a live fixture without a migration project, and no seed can claim a confirmation the operator has not given per row (Flatline gpt IMP-001, opus IMP-027; SDD review SKP-001) |
| D17 | Operator transitions (`confirm`, `reject` or `supersede` of a decided row, clearing the unattended marker) exist only behind the operator-only `/decisions` command; no skill may call them | a writer flag any caller may pass | an agent that can clear its own unattended marker or confirm its own rows makes attribution meaningless (SDD review SKP-002) |
| D18 | Implementers in linked worktrees write a per-sprint pending file with provisional ids; the lead imports it in the main checkout, the only place real ids are allocated | let every worktree append to the live ledger | an append-only tracked YAML is unmergeable across branches and max+1 ids collide (SDD review SKP-003) |
| D19 | Attribution is tamper-evident (artifact hashes, HEAD commit, append-only transitions), not signed; signing through the existing signed audit chain is a future iteration | require signatures now | proportionate to a planning ledger; the signing infrastructure exists and can be attached later (SDD review SKP-002) |
| D20 | Mike Farah yq v4 becomes a hard dependency for the ledger writer; the lock is portable (`flock` or a `mkdir` lock); `timeout` falls back to `gtimeout` or a bash wrapper | shell-only YAML handling | hand-rolled YAML is the corruption risk the review named; macOS and BSD hosts are supported (SDD review SKP-004) |

### F. Baselines measured at plan time (2026-10-13)

| Artifact | `[ASSUMPTION]` tags | Decisions taken without the operator | Note |
|---|---|---|---|
| cycle-126 PRD (`grimoires/loa/archive/cycle-126-full-size/prd.md`) | 0 | recorded only as the NOTES.md 2026-09-24 kickoff bullet "Design calls made without the operator" (ceiling policy, derived bound, I1 auto-shrink, context-length errors, kill switch, temperature, companion voice, context class, `cheap` alias: 9 calls) | the PRD carried no tags; the 30-day comparison for G-2 is therefore "every such call is a `DEC` row" and "`[ASSUMPTION decision]` tags ≤ 9" on the next charted effort |
| cycle-127 PRD (`grimoires/loa/archive/cycle-127-operator-decisions/prd.md`) | 0 | 3 (D1–D3 in NOTES.md 2026-10-07) | the backfill seed for the ledger (D16) |
| cycle-128 PRD (this document) | see the validator INFO line at plan commit | 20 (Appendix E D1–D20) | the first cycle whose decisions become `proposed` rows |

### G. Flatline review integration (2026-10-13)

Two voices (codex-headless as `gpt-5.5`, claude-headless), Phase 2 cross-scoring degraded (KF-041, exit 6); integrated by judgment. Integrated: SKP-001a (confirm/reject workflow, D13), SKP-001b (derived `decided_by`, D14), SKP-002 (provenance and append-only transitions, D15); gpt IMP-001…015 and opus IMP-001…029 into FR-1…FR-8, the KPIs, NFR Security, Launch Criteria and Appendix D (details in the FR text). Declined: none. Narrowed: opus IMP-015 (SDD `DEC` column) lands as a validator WARN, not a failure, in this cycle.

The sprint-plan review (4 blockers) and the SDD review (7 blockers) were integrated the same day: the ledger single-writer rule became the pending-file import mechanism (D18), operator transitions moved behind the operator-only `/decisions` command (D17), every seed row became `proposed` (D16 amended), attribution is stated as tamper-evident rather than signed (D19), and the writer's dependencies and portability were fixed (D20); the red-test CLI and the harness check were reshaped per the SDD. Details in `sprint.md` Appendix D and `sdd.md` §11.

> Sources: skills-review-2026-10/proposals.md (ADOPT/ADAPT/LEARN/REJECT, adversarial pass); prd-brief.md §Open questions; NOTES.md Decision Log 2026-10-07 (precedent for Appendix E)

---

*Generated by PRD Architect Agent*
