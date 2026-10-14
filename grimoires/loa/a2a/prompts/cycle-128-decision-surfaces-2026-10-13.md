# PRD brief: decision surfaces for Loa planning

**Status**: brief for `/plan-and-analyze` input; not a PRD; no cycle opened. **Date**: 2026-10-12. **Source**: `comparison.md` and `proposals.md` in this directory (Pocock skills review). Drop a copy into `grimoires/loa/context/` to seed Phase 0.

## Problem

Loa plans build slices well and decisions badly. The planning unit is one cycle (one PRD, SDD, sprint plan); efforts that span cycles (the 124 → 127 arc) are coordinated through gitignored NOTES prose, carry-over beads and operator memory. Decisions have no trackable unit: they live as `[ASSUMPTION]` tags, debrief bullets, 29 ad-hoc proposal docs and four hand-written ADRs, while the `decisions.yaml` ledger specified in `docs/architecture/decision-lineage.md` was never built (two scripts still read for it). Unattended runs answer the interview's own questions by design (`karpathy-principles.md:30-35`), with no record of which answers were facts and which were decisions taken on the operator's behalf. Questions that cannot be settled by talking have no prototype route and become assumptions. The discovery interview asks in a fixed topic order, one question per turn, with no prerequisite ordering and no recommended answers. The framework's own vocabulary has no glossary.

## Goals

Make every decision Loa takes during planning findable, attributable and reviewable; give multi-cycle efforts a map that plans and cannot build; let the interview ask in rounds; keep the sanctioned path exactly as gated today.

## Functional requirements

- **FR-1 Rounds.** `interview.pacing: rounds`: each round is the whole frontier of questions whose prerequisites are settled, numbered, each with a recommended answer phrased so "yes" accepts it; the frontier is recomputed after every round. `sequential` and `batch` remain. (`discovering-requirements`, `planning-sprints`, `designing-architecture`; `.loa.config.yaml.example`.)
- **FR-2 Fact / decision split.** The Backpressure Protocol classifies each pending question as a fact (the agent looks it up) or a decision (the operator only). Unattended runs may settle facts; every self-answered decision becomes a ledger row with `decided_by: agent` and is listed in the PR body.
- **FR-3 Decision ledger.** `grimoires/loa/decisions.yaml` (`DEC-NNNN`; phase, summary, decision, rationale, alternatives, consequences, `decided_by`, `status: open|decided|superseded|rejected`, `source`) with an append-only writer library modelled on `kf-write-lib.sh`, a `## decisions` section in `grimoires/loa/INDEX.md`, SessionStart surfacing of open rows, and Pocock's three-condition bar (hard to reverse, surprising, real trade-off) as the row filter. NOTES Decision Log points at rows; release-epoch ADRs are unchanged.
- **FR-4 Decision map (`/chart`).** For efforts spanning more than one cycle: a `map` epic bead plus `--type question` child beads labelled `decision:grilling|prototype|research|unblock`, blocking edges via `br dep`, frontier via `get-ready-work.sh`, claim by assignee, one decision resolved per session (research excepted), a tracked map doc at `grimoires/loa/maps/<slug>.md` with Destination / Decisions so far / Not yet specified / Out of scope and no execution override. Charting stops when the breadth-first grill finds no fog. A cleared map is priority-1 context for `/plan-and-analyze`; `golden_detect_plan_phase` reports `charting` while a map is open.
- **FR-5 Prototype tickets and spikes.** An ungrillable question becomes a `decision:prototype` bead. The prototype runs HITL in a worktree on a `spike/<slug>` branch, pushed, never merged, no PR; `grimoires/loa/spikes/` gets a template; the verdict becomes a `DEC` row.
- **FR-6 Glossary.** A tracked root `GLOSSARY.md` format (term, one–two sentences, `_Avoid_`), seeded for Loa's own vocabulary; planning skills challenge and update the project glossary inline; a kernel-term drift check.
- **FR-7 Seams and red tests.** Sprint plans declare seams under test (seam, catches, misses, prior art), validated by `validate-artifact --type sprint` and checked on the review's spec axis; `/bug` micro-sprints commit the failing test first and `red-test-check.sh` verifies red-then-green at review time.
- **FR-8 Operator-only commands.** `disable-model-invocation: true` on leaf operator commands with a lint that no other body executes them as a step.

## Non-goals

No change to `/review-sprint`, `/audit-sprint`, the LOA-VERDICT one-way rule, the dissent artefact gate or the implement gate's decisions. No GitHub Issues tracker for decisions. No plugin-marketplace distribution. No parallel implementer swarm inside `/run`. No removal of AskUserQuestion or of `sequential` pacing. No question caps. No "invest in design every day" skill. No decision rows for trivial choices (the three-condition bar is the filter).

## Success criteria

- Every `[ASSUMPTION]` that is a decision in an unattended PRD has a `DEC` row with `decided_by: agent`; the PR body lists them (bats over a fixture run).
- A `question` bead can never carry a `sprint:` label or enter a sprint epic (lint, CI).
- On a charted effort, the PRD interview asks fewer questions and produces fewer `[ASSUMPTION]` rows than the previous uncharted multi-cycle PRD (cycle-126 as the baseline).
- A fixture interview in `rounds` mode averages ≥ 2 questions per round with no dependent pair in a round (scripted transcript, manual rubric).
- `grimoire-index.sh` emits a `## decisions` section; SessionStart surfaces open decisions when enabled.
- Every backticked framework term in `CLAUDE.loa.md` resolves in `GLOSSARY.md`.
- `check-prompt-budget.sh` green on every touched skill; `discovering-requirements` stays ≤ 16,384 B.
- A spike branch push is allowed and its merge is refused by ICE (fence corpus case).
- No regression in `tests/unit/implement-gate.bats`, `verdict-derive.bats`, `skill-capabilities.bats`.

## Open questions for the interview

Default pacing flip to `rounds` (maintainer decision). Whether `decisions.yaml` lives at `grimoires/loa/` or `docs/architecture/`. Whether research tickets may run on hosts without an Opus route. Whether `/chart` is a golden-path command or a truename only.

## Shape

One cycle, three sprints: (1) FR-1, FR-2, FR-3, FR-8; (2) FR-4, FR-5; (3) FR-6, FR-7, docs and the acceptance chart on the next real multi-cycle effort. Subagents Opus 5.5; review and audit on Fable 5.1; ≤ 3 dissent runs per sprint.
