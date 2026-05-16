# Cycle-109 PRD — Multi-Model Substrate Hardening

> **Version**: 1.4 (Flatline SDD-review v3/v4/v5/v6 BLOCKERs closed-or-overridden per C109.OP-8/9/10. v6 closures: truncation_waiver_applied schema field; consensus_outcome algorithm spec §3.2.2.1; voices_succeeded_ids schema field; §4.4 dead-code fix; chain-walk → DEGRADED surface; exit-code collision corrected. 3 residual operator-overridden per C109.OP-10 absorbed into Sprint 2 AC.)
> **Status**: Draft — PRD gate PASSED-WITH-OPERATOR-OVERRIDE per C109.OP-4/8/9/10 precedent; ready for `/run sprint-1`
> **Cycle**: cycle-109-substrate-hardening
> **Created**: 2026-05-13 (v1.0); v1.1 Flatline integrate; v1.2/1.3 v3/v4/v5 SKP closures; v1.4 v6 SKP closures + C109.OP-10 operator-override absorbed into Sprint 2 AC
> **Author**: Claude (cycle-109 kickoff via `/plan-and-analyze`, autonomous mode under operator delegation)
> **Predecessor**: cycle-108-advisor-strategy (PR #867 merged at `6e76582d`, substrate-validation close per decision-fork c')
> **Operator**: @janitooor
> **Approval ledger**: `grimoires/loa/cycles/cycle-109-substrate-hardening/operator-approval.md`
> **Flatline trajectory**: `grimoires/loa/a2a/flatline/cycle-109-prd-review.json` — substrate self-reported `confidence: full` while Opus voice effectively dropped (1/14 findings); operator-override recorded as cycle-109 evidence per C109.OP-4
> **Reality ground-truth**: `grimoires/loa/reality/multimodel-substrate.md` (fresh /ride 2026-05-13 against HEAD `6e76582d`)
> **Known-failures ground-truth**: `grimoires/loa/known-failures.md` (KF-001 through KF-010)

---

## Source citations

This PRD is grounded against three classes of source:

- **[CODE:file:line]** — direct citations to substrate code at HEAD `6e76582d`
- **[REALITY:multimodel-substrate.md:§N]** — ride-extracted substrate facts
- **[ISSUE:#N]** — GitHub issues verified OPEN at HEAD via `gh issue list` 2026-05-13
- **[KF-NNN]** — `grimoires/loa/known-failures.md` ledger entries
- **[OPERATOR:date]** — operator instructions in the /plan-and-analyze session

Ungrounded inference is tagged `[ASSUMPTION]` and is explicitly listed in §11.4.

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Problem Statement](#2-problem-statement)
3. [Goals & Success Metrics](#3-goals--success-metrics)
4. [User Personas & Use Cases](#4-user-personas--use-cases)
5. [Functional Requirements](#5-functional-requirements)
6. [Non-Functional Requirements](#6-non-functional-requirements)
7. [User Experience](#7-user-experience)
8. [Technical Considerations](#8-technical-considerations)
9. [Scope & Prioritization](#9-scope--prioritization)
10. [Success Criteria](#10-success-criteria)
11. [Risks & Mitigation](#11-risks--mitigation)
12. [Timeline & Milestones](#12-timeline--milestones)
13. [Quality Gates & Loa Process Conformance](#13-quality-gates--loa-process-conformance)
14. [Appendix](#14-appendix)

---

## 1. Executive Summary

The multi-model substrate is Loa's flagship feature and the foundation of its
quality-control system. Cycles 103-108 unified the substrate architecturally
behind `cheval.py` and activated it as the default at v1.157.0. **The
activation has succeeded structurally and is now failing operationally**:
13 OPEN substrate issues, 5 with recurrence ≥ 3 in `known-failures.md`,
12 of 13 classified as degradation-under-real-workloads rather than
missing-capability. [REALITY:multimodel-substrate.md:§11]

The operator's framing — *"used to work well with the older models"* —
identifies the load-bearing diagnostic: the substrate was built on the
assumption that providers/models are interchangeable behind the chain-walker.
Newer reasoning-class models invalidate that assumption. They burn output
budget on internal CoT; they have heterogeneous empty-content failure modes;
they fail at smaller effective input ceilings than their advertised context
windows. [KF-002][KF-003] The substrate has no first-class concept of *which
models fail at what*, so it dispatches blind and discovers failures
empirically — leaking those failures into operator-facing "clean" verdicts
[ISSUE:#807][ISSUE:#809] and timing out 70KB+ FL calls [ISSUE:#866].

Cycle-109 is a five-sprint substrate-hardening cycle scoped to fix the
**cause**, not the symptoms. It introduces a capability-aware model
descriptor (Sprint 1), a verdict-quality envelope (Sprint 2), sunsets the
1,081-LOC legacy adapter that drifts from cheval (Sprint 3), ships
hierarchical/chunked review for inputs exceeding model capability
(Sprint 4), and closes carry items + delivers operator-facing substrate
observability (Sprint 5). The cycle ships under iron-grip Loa quality gates:
Flatline at PRD/SDD/sprint-plan, implement → review → audit per sprint,
Bridgebuilder + post-PR audit for every PR, circuit-breaker on /run.
[OPERATOR:2026-05-13]

Expected outcome: substrate health is observable and operator-honest;
KF-002-class recurrence is structurally closed (not pushed one zoom level
deeper); the 5 BLOCKING-class false-positives [ISSUE:#807] become
impossible by construction; runway pressure on the operator's main mission
is removed because multi-model stops consuming headspace, tokens, money,
and time disproportionate to its value.

---

## 2. Problem Statement

### 2.1 The Problem

Multi-model is operationally broken in v1.157.0 in four distinct but
related failure modes (the "four clusters"):

**Cluster A — Large-document degradation (KF-002 next-zoom recurrence)**
- [ISSUE:#866] FL orchestrator degrades on documents >70KB — five
  consecutive observations during cycle-108
- [ISSUE:#823] `claude-opus-4-7` empty-content failure on review-type
  prompts at >40K-input scale (vision-024 fractal recursion at next
  zoom level)
- [KF-002] Layer 1 (reasoning-budget exhaustion) still latent; layers 2+3
  closed by cycle-103 streaming substrate; **recurrence 5 = structural**

**Cluster B — v1.157.0 milestone regressions (activation exposed defects)**
- [ISSUE:#864] Flatline substrate broken in v1.157.0: legacy adapter
  crashes on CLI models + config knob ignored + scoring engine empty on
  prefer-api
- [ISSUE:#863] `/flatline-review` 3 regressions (cost-map, scoring engine
  empty, GPT/Gemini orchestrator fail)
- [ISSUE:#793] flatline-orchestrator validator rejects cheval-headless
  pin form (`<provider>-headless:<model_id>`)
- [ISSUE:#820] flatline-orchestrator + flatline-readiness 3 issues (env
  loading, alias recommendation, scoring parser)

**Cluster C — Degraded-state semantics (substrate misleads operators)**
- [ISSUE:#807] Multi-model adversarial review fallback approves issues
  single-model misses — **5 BLOCKING incl. shell-injection** approved
- [ISSUE:#809] flatline-dissenter consistently returns 10-token empty
  findings → operator-misleading `status: clean` semantics
- [ISSUE:#868] Adversarial review/audit fallback chain (gpt-5.2 →
  gemini-2.5-pro) fails on both phases — chain exhausts, audit forced
  to DEGRADED
- [ISSUE:#805] `/run-bridge` multi-model claim misleading: BB TS app is
  single-model two-pass; Pass 2 fails ~80% on real PRs

**Cluster D — Cycle-108 carry items**
- [ISSUE:#874] cheval.py advisor-strategy provider-peek narrow 'anthropic'
  fallback (C-S2-1)
- [ISSUE:#875] modelinv.py parents[4] hardcode (C2 from sprint-1)
- [ISSUE:#870] modelinv-rollup.sh strip-attack scanner O(N) with per-line
  subprocess spawn

### 2.2 The Meta-Root-Cause

> The substrate was built assuming providers/models are interchangeable
> behind the chain-walker. They are not.

Three concrete consequences of this incorrect abstraction:

1. **Capability blindness**. `model-config.yaml` declares models by
   `provider:model_id` only [CODE:.claude/defaults/model-config.yaml]. It
   has no field for `effective_input_ceiling` (where empty-content starts,
   which is *less* than the API-advertised context window), no field for
   `reasoning_class` (true = burns output on CoT, distinct from
   classical completion models), no link to the KF ledger. So cheval
   dispatches with no way to predict that `claude-opus-4-7` at 40K+ will
   empty-content [ISSUE:#823] — it discovers the failure empirically and
   walks the chain.

2. **Verdict-quality blindness**. Substrate outputs carry findings, but
   no first-class verdict envelope describing *how the verdict was
   reached*. Consumers infer "clean" from finding count, so 0 findings
   from healthy voices and 0 findings from voice-drop look identical
   [ISSUE:#807][ISSUE:#809]. The substrate emits voice-drop trajectory
   events [CODE:.claude/scripts/flatline-orchestrator.sh:304
   `emit_voice_dropped`] but the consumer-facing summary loses this
   signal.

3. **Two-code-path drift**. The substrate has cheval (canonical) AND
   `model-adapter.sh.legacy` (1,081 LOC, `flatline_routing: false`
   rollback path). The activation flip exposed defects in the legacy
   path that hadn't surfaced because tests covered routing-OFF less than
   routing-ON [ISSUE:#864]. Maintaining both costs more than the rollback
   path is worth, given cheval has now operated as default for a release
   cycle.

### 2.3 User Pain Points (operator-stated, 2026-05-13)

- **Headspace consumption**: "consuming alot of our budget in terms of
  headspace, tokens, money and time" — multi-model is a tax on every
  other initiative
- **Regression from prior state**: "used to work well with the older
  models so this is really painful" — substrate worked under prior model
  generation; current pain is regression, not absence
- **Mission-blocking**: "stopping us from advancing in our main mission
  which are the things which will bring revenue as we are significantly
  running out of runway" — substrate failures have downstream runway impact

### 2.4 Current State

Substrate works when:
- Inputs are small (<30K for reasoning-class models)
- Routing is `flatline_routing: false` (legacy path) AND prior to v1.157.0
- All three voices succeed (no chain-walk required for FL)

Substrate fails when:
- Large inputs (>40K reasoning-class, >70KB FL) → empty content,
  silent timeouts, chain exhaustion [Cluster A]
- `flatline_routing: true` (the activated default) hits any of four
  specific defects [Cluster B]
- Voices drop or chain exhausts → consumer reports "clean" or "APPROVED"
  anyway [Cluster C]

### 2.5 Desired State

Substrate **knows its models** (capability-aware), **tells the truth
about its verdicts** (verdict-quality envelope), **has one code path**
(legacy deleted), **handles big inputs structurally** (hierarchical/
chunked review), and is **operated as an SRE'd system** (observability
+ KF-ledger feedback loop).

A consumer asking "did this PR pass review?" receives an answer of the
form `{status: APPROVED | DEGRADED | FAILED, voices_planned: N,
voices_succeeded: M, confidence_floor: high|med|low, chain_health: ok|
degraded|exhausted}`. `APPROVED` is *definitionally impossible* when
`voices_succeeded < voices_planned` OR `chain_health != ok`. The
substrate cannot lie by construction.

---

## 3. Goals & Success Metrics

### 3.1 Primary Goals

| ID | Goal | Measurement | Validation Method |
|----|------|-------------|-------------------|
| G-1 | Close all 13 OPEN substrate issues identified in reality file §9 | `gh issue list` count drops to 0 for the cycle-109 issue set | Per-sprint issue closure tracked; cycle-close audit verifies |
| G-2 | Eliminate KF-002 layer-1 recurrence (structural, not patched) | KF-002 status field updates to `RESOLVED-STRUCTURAL` (currently `LAYER-1 LATENT`); no new layer surfaces in cycle-110 first 30 days | KF ledger inspection; production-FL telemetry from Sprint-5 observability |
| G-3 | Substrate "clean" verdict accuracy = 100% | Zero instances of `status: clean` emitted when `voices_succeeded < voices_planned` OR `chain_health != ok` | bats unit + integration tests; production audit log replay |
| G-4 | Delete legacy adapter path entirely | `git ls-files` reports zero references to `model-adapter.sh.legacy`; the file is removed | CI scanner enforces; final cycle audit verifies |
| G-5 | Cycle ships under iron-grip Loa quality gates | Every PR has Flatline PRD/SDD/sprint-plan reviews + BB review + post-PR audit + KF cross-reference recorded | `.run/audit.jsonl` audit; cycle-close verification |

### 3.2 Key Performance Indicators (KPIs)

| Metric | Current Baseline | Target | Timeline | Goal ID |
|--------|------------------|--------|----------|---------|
| OPEN substrate issues (per reality §9) | 13 | 0 | end of Sprint 5 | G-1 |
| KF-002 recurrence count | 5 (LATENT layer 1) | 0 new recurrences cycle-110 first 30d | 30d post-merge | G-2 |
| Substrate "clean" verdict false-positive rate | unknown (currently un-measurable; #807 demonstrated 5 BLOCKING approved) | 0 (impossible by construction) | end of Sprint 2 | G-3 |
| LOC in legacy adapter path | 1,081 | 0 | end of Sprint 3 | G-4 |
| `flatline_routing: true` activated-path test coverage | unknown (insufficient to catch #863/#864) | every consumer × every substrate role × representative provider responses covered in CI | end of Sprint 3 | G-1, G-4 |
| MODELINV v1.2 envelope coverage | per cycle-108 T2.M baseline | ≥0.95 (raised from 0.90 strict-threshold) | end of Sprint 1 | G-3 |
| Substrate observability surface | none (operators learn of degradation when a session blows up) | 24h rolling dashboard: voices succeeded/dropped/by-model | end of Sprint 5 | G-2 |

### 3.3 Constraints

- **No new providers, models, transports, or feature flags** in cycle scope
  (see §9 explicit out-of-scope). Cycle is substrate-internal only.
- **No replacement of the substrate with an external aggregator
  (OpenRouter etc.)**. Operator-evaluated 2026-05-13 and rejected:
  routing is not the failure surface; three of four clusters are not
  routing problems. [OPERATOR:2026-05-13]
- **Codegen byte-equality preserved**. Any change to `model-config.yaml`
  schema must regenerate `generated-model-maps.sh` and the TS port
  byte-identically across runtimes. [REALITY:multimodel-substrate.md:§1]
- **MODELINV envelope continuity**. v1.2 → v1.3 (cycle-109) must be
  additive-only; existing fields preserved; existing replay logs remain
  parseable. [REALITY:multimodel-substrate.md:§5]
- **Iron-grip quality gates**: see §13.

### 3.4 Baseline Measurement Methodology [IMP-003]

Several success criteria (§3.2 KPIs, §10.1-10.3 launch criteria, §11.3
rollback decision threshold) compare against a "pre-cycle baseline".
This subsection defines how that baseline is measured, when, and where
results land — so rollback / escape-hatch / launch eval decisions are
verifiable rather than vibes.

**Baseline measurement protocol** (executed at cycle-109 kickoff, BEFORE
Sprint 1 lands):

| Metric | Measurement method | Source | Cadence | Persistence |
|--------|--------------------|--------|---------|-------------|
| OPEN substrate issue count | `gh issue list --label substrate --state open` | GitHub | One-shot at kickoff + per-sprint-close + cycle-close | `grimoires/loa/cycles/cycle-109-substrate-hardening/baselines/issue-counts.json` |
| KF-002 recurrence count | grep `KF-002` rows in `known-failures.md` Attempts table | Repo | Same cadence | `baselines/kf-recurrence.json` |
| "clean" verdict false-positive rate | Replay last-30-day MODELINV log; count outputs where `status: clean` AND `voices_succeeded < voices_planned` | `.run/model-invoke.jsonl` | One-shot at kickoff (no production telemetry exists yet — establishes T0); post-Sprint-5 re-measure on 30d window | `baselines/clean-fp-rate.json` |
| LOC in legacy adapter | `wc -l .claude/scripts/model-adapter.sh.legacy` | Repo | One-shot at kickoff (baseline = 1,081); end-of-Sprint-3 (target = 0) | `baselines/legacy-loc.json` |
| MODELINV envelope coverage | `tools/modelinv-coverage-audit.py --window 30d` (cycle-108 T2.M) | `.run/model-invoke.jsonl` | One-shot at kickoff + per-sprint-close | `baselines/modelinv-coverage.json` |
| Substrate-issue-filing rate | `gh issue list --label substrate --created` since cycle-108 close | GitHub | One-shot at kickoff (baseline window: 2026-05-09 to 2026-05-13) + post-Sprint-5 30d window | `baselines/issue-rate.json` |
| Operator-attention-tax (qualitative) | Operator self-rating on cycle-109 kickoff vs cycle-109 close ("how much headspace does multi-model consume right now, 1-10") | Operator | Kickoff + cycle-close | `baselines/operator-self-rating.md` |

**Storage**: all baseline measurements land at
`grimoires/loa/cycles/cycle-109-substrate-hardening/baselines/` —
TRACKED in git so they persist across cycles and allow cycle-110
to retrospectively compare cycle-109 outcomes against the baseline.

**Sprint 1 deliverable**: write `tools/cycle-baseline-capture.sh` —
a single CLI that reads the current state and emits the
`baselines/*.json` files. Runs at cycle kickoff + each sprint close
+ cycle close + 30d post-cycle. Idempotent; signed via cycle-098 audit
envelope.

**Decision thresholds** (referenced from §11.3 rollback):
- **Rollback triggered** if cycle-109 introduces a regression where
  any baseline metric worsens by >20% (e.g., substrate issue count
  rises above 16 from baseline 13)
- **Launch criteria met** (§10.1) only when ALL baselines have moved in
  the documented direction beyond the documented threshold

This makes §10.2/§10.3 "engagement signal" / "headspace reduction"
metrics measurable rather than aspirational.

---

## 4. User Personas & Use Cases

### 4.1 Primary Persona: The Operator (`@janitooor`)

**Demographics:**
- Role: Repository maintainer; runs autonomous Loa cycles; consumes
  multi-model verdicts to gate PR merges
- Technical Proficiency: Expert (writes the framework)
- Goals: Ship revenue-bearing work without multi-model imposing a tax;
  trust verdicts; reduce headspace consumption of substrate operations

**Behaviors:**
- Invokes `/run sprint-plan` autonomously; expects to be paged only when
  intervention is required
- Reads MODELINV audit envelopes when diagnosing substrate degradation
- Consults `known-failures.md` before triaging
- Files `gh issue` against substrate when degradation observed

**Pain Points:**
- Cannot trust `status: clean` because [ISSUE:#807][ISSUE:#809] proved
  it can be empty-string-with-no-findings rather than actual approval
- Cannot predict when substrate will degrade (no observability surface);
  finds out when a session blows up
- Has to triage repeated KF-002-class failures at each new zoom level;
  the pattern recurs because the fix is at the wrong layer

### 4.2 Secondary Persona: The Agent (substrate consumer)

**Demographics:**
- Role: A Loa skill (BB, FL, RT, /bug, /review-sprint, /audit-sprint)
  that consumes substrate verdicts as part of its workflow
- Technical Proficiency: N/A (programmatic consumer)

**Behaviors:**
- Calls substrate via cheval HTTP boundary [REALITY:§2 diagram]
- Receives JSON; routes based on findings count, status field
- Today: cannot distinguish "approved by N healthy voices" from
  "approved because voices dropped"

**Pain Points:**
- Inherits substrate's verdict-quality blindness; emits
  operator-misleading PR comments and reviews
- Has no typed-exit path to "verdict-unsafe-to-trust"

### 4.3 Tertiary Persona: Revenue-Bearing Work (downstream beneficiary)

The operator's "main mission" — work that brings revenue, runway-bearing,
and is currently blocked because multi-model consumes disproportionate
headspace. Not a direct user of the substrate, but the primary
beneficiary of this cycle's success: removing substrate as a tax on
forward velocity. [OPERATOR:2026-05-13]

### 4.4 Use Cases

#### UC-1: Operator runs autonomous /run sprint-plan and trusts the verdict

**Actor:** Operator
**Preconditions:** Sprint plan exists; multi-model substrate is the default review path
**Flow:**
1. Operator invokes `/run sprint-plan`
2. Substrate executes implement → review → audit cycle per sprint
3. At each phase, FL/RT emit verdicts with explicit `verdict_quality` envelope
4. Operator receives final PR with verdict summary; can read at a glance:
   `APPROVED — 3/3 voices, chain ok, confidence high` OR
   `DEGRADED — 2/3 voices (gpt-5.2 dropped: empty-content), chain ok, confidence med` OR
   `FAILED — chain exhausted; verdict unsafe`
5. Operator merges only when `APPROVED`; intervenes when `DEGRADED`+; never sees a misleading `clean`

**Postconditions:** Operator trusts substrate output; merge decisions correlate to actual verdict quality
**Acceptance Criteria:**
- [ ] Every substrate output carries `verdict_quality` envelope (Sprint 2)
- [ ] `APPROVED` is definitionally impossible when voices dropped or chain degraded (Sprint 2)
- [ ] Operator-facing summary surfaces `verdict_quality` prominently (Sprint 2)

#### UC-2: Substrate gracefully handles a >70KB PR without operator intervention

**Actor:** Substrate (cheval)
**Preconditions:** A large PR triggers FL review; total input size exceeds the model's `effective_input_ceiling`
**Flow:**
1. Cheval pre-flight: looks up effective_input_ceiling for target model
2. If input > ceiling, cheval invokes hierarchical/chunked review (Sprint 4) — not raw dispatch
3. Chunks reviewed independently; findings aggregated; deduplicated
4. Output emitted with `chunked: true, chunks_reviewed: N, chunks_dropped: 0` annotation
5. If chunk exceeds ceiling individually (rare), cheval emits typed exit `ContextTooLarge` (code 7) preemptively — does NOT dispatch and wait for empty-content

**Postconditions:** Large-doc reviews succeed; operator no longer sees [ISSUE:#866]-class timeouts; KF-002 layer 1 is structurally closed
**Acceptance Criteria:**
- [ ] All models in `model-config.yaml` declare `effective_input_ceiling` (Sprint 1)
- [ ] Cheval pre-flight gate invokes chunked path or fails fast (Sprint 4)
- [ ] No silent timeouts on >70KB FL inputs in 30-day production telemetry (Sprint 5 observability)

#### UC-3: A new KF entry auto-degrades the affected model

**Actor:** Operator (logs KF) and Substrate (consumes the ledger)
**Preconditions:** Operator observes a substrate failure, files a new `KF-NNN` entry referencing model `X`
**Flow:**
1. Operator appends entry to `known-failures.md` (existing process)
2. KF-ledger watcher (Sprint 1) parses entry; finds model reference `X`
3. Substrate updates `model-config.yaml::models.X.failure_modes_observed[]` (or equivalent runtime overlay) with KF-NNN reference
4. Substrate `recommended_for` for model `X` is downgraded per KF severity
5. Future dispatches to model `X` either avoid that role OR proceed with degraded-confidence flag

**Postconditions:** Operator-logged knowledge propagates to substrate behavior automatically; no manual model-pinning required
**Acceptance Criteria:**
- [ ] `failure_modes_observed` populated from KF ledger via deterministic script (Sprint 1)
- [ ] `recommended_for` downgrade follows documented mapping (Sprint 1)
- [ ] Substrate decisions reference KF entries in MODELINV envelope (Sprint 1)

#### UC-4: Operator inspects substrate health for the past 24h

**Actor:** Operator
**Preconditions:** Substrate has been running; some calls succeeded, some degraded, some failed
**Flow:**
1. Operator runs `loa substrate health --window 24h` (new — Sprint 5)
2. Output: per-model success rate, voice-drop rate, chain-exhaustion rate, p95 latency, total cost
3. Operator identifies any model with deteriorating health BEFORE it costs a sprint
4. Operator either updates KF ledger (triggers UC-3) or files a substrate issue

**Postconditions:** Substrate operated as SRE'd system; degradation visible before catastrophic
**Acceptance Criteria:**
- [ ] CLI surface `loa substrate health` exists and reads from `.run/model-invoke.jsonl` (Sprint 5)
- [ ] 24h window query completes in <2s for typical log volumes (Sprint 5)
- [ ] Output is operator-readable AND machine-readable (`--json` flag) (Sprint 5)

---

## 5. Functional Requirements

Each functional requirement maps to a sprint. Sprint identifiers are the
top-level FR numbers (FR-1 = Sprint 1, etc.).

### FR-1: Capability-Aware Substrate Foundation (Sprint 1)

**Priority:** Must Have
**Description:** Extend `model-config.yaml` with capability fields and add a
cheval pre-flight gate that consults them before dispatch.

**Sub-requirements:**

- **FR-1.1**: Add fields to each model entry in `model-config.yaml`:
  - `effective_input_ceiling` (int, tokens) — where empty-content starts;
    distinct from API-advertised context window
  - `reasoning_class` (bool) — true = burns output budget on CoT
  - `recommended_for` (list of role tags, e.g., `[review, dissent, audit,
    implementation]`) — informational, not load-bearing yet
  - `failure_modes_observed` (list of KF-IDs) — pointer to ledger entries
  - `ceiling_calibration` (object) — provenance + staleness for
    `effective_input_ceiling`:
    ```yaml
    ceiling_calibration:
      source: empirical_probe | kf_derived | operator_set | conservative_default
      calibrated_at: "2026-05-13T00:00:00Z"
      sample_size: 25  # null if not empirical
      stale_after_days: 30
      reprobe_trigger: "first KF entry referencing model OR 30d elapsed OR operator-forced"
    ```
- **FR-1.2**: Schema validation — `migrate-model-config.py` updated to v3
  schema; existing v2 entries migrated.
  **[IMP-008] Conservative defaults policy** at migration time when no
  empirical data exists yet:
  - `effective_input_ceiling` = `min(50% × api_context_window, 30000)` —
    matches the 30K knee observed in KF-002/003
  - `reasoning_class`: defaults to `false`; documented opt-in list flips
    known reasoning-class models (claude-opus-4.x, gpt-5.5-pro,
    gemini-3.1-pro) to `true`
  - `recommended_for`: defaults to `[]` (informational; load-bearing
    semantics only land after Sprint 2 FR-2.3 classification contract)
  - `failure_modes_observed`: empty; populated by FR-1.5 on next CI run
  - `ceiling_calibration.source: conservative_default`
- **FR-1.3**: Cheval pre-flight gate at `cheval.py::_lookup_max_input_tokens`
  [CODE:cheval.py:285] extended:
  - If input > `effective_input_ceiling`, emit typed exit 7 (ContextTooLarge)
    preemptively
  - If model `reasoning_class: true` AND requested role in
    `not-recommended-for`, emit warning to MODELINV envelope
- **FR-1.4**: MODELINV v1.3 envelope adds `capability_evaluation` field:
  ```jsonc
  "capability_evaluation": {
    "effective_input_ceiling": 40000,
    "input_size_observed": 38000,
    "preflight_decision": "dispatch | preempt | warn",
    "reasoning_class": false,
    "recommended_for_role": true,
    "ceiling_calibration_source": "empirical_probe",
    "ceiling_stale": false
  }
  ```
- **FR-1.5**: KF-ledger auto-link script — `tools/kf-auto-link.py`:
  - Parses `known-failures.md` for `model: <id>` references in active KF entries
  - Updates `failure_modes_observed` in `model-config.yaml`
  - Downgrades `recommended_for` per the severity-to-downgrade mapping below
  - Runs in CI on changes to `known-failures.md`
  - **OPERATOR-AUTHORIZED**: per operator-approval C109.OP-2

  **[IMP-001 HIGH_CONSENSUS] Severity-to-downgrade mapping** (canonical
  spec, not deferred to SDD):

  | KF status | Effect on referenced model |
  |---|---|
  | `OPEN` (new entry, no resolution) | Remove all roles from `recommended_for`; substrate dispatches with warning emitted to MODELINV |
  | `RESOLVED` | No degradation; substrate may use freely |
  | `RESOLVED-VIA-WORKAROUND` | Remove only the specific role mentioned in KF (e.g., "review" if KF describes review-prompt failure); other roles retained |
  | `RESOLVED-STRUCTURAL` | No degradation |
  | `LATENT` / `LAYER-N-LATENT` | Remove role(s) referenced in the latent layer; emit warning on dispatch |
  | `DEGRADED-ACCEPTED` | No automated change (operator explicitly chose to accept); informational only |

  The mapping is the canonical spec; ambiguous KF status strings fail-loud
  per IMP-005 below.

  **[IMP-002 + SKP-004 hardening] Manual operator override** for KF-auto-link decisions:
  - Schema in `.loa.config.yaml`:
    ```yaml
    kf_auto_link:
      enabled: true  # default
      overrides:
        - model: claude-opus-4-7
          role: review
          decision: force_retain                     # or: force_remove
          reason: "operator-validated cycle-110 sprint-2"
          effective_until: "2026-08-01T00:00:00Z"    # REQUIRED (no null/permanent); max now()+90d
          kf_references: [KF-002, KF-009]            # REQUIRED non-empty; entries must exist in known-failures.md
          authorized_by: "@janitooor"                # OPERATORS.md slug
          break_glass:                               # REQUIRED iff any kf_references is OPEN CRITICAL
            operator_slug: "@janitooor"
            reason: "production incident — must dispatch despite CRITICAL KF"
            expiry: "2026-05-15T00:00:00Z"           # ≤ now() + 24h
            audit_event_id: "..."                    # hash from cycle-098 signed audit event
    ```
  - **Precedence (SKP-004 closure — Flatline SDD-review v3 HIGH BLOCKER)**:
    operator override > KF auto-link > FR-1.2 default — BUT **conditional**, not unconditional. Override is REJECTED (KF auto-decision applies, stderr warning emitted) when:
    - `effective_until` is missing, in the past, or > `now() + 90d`
    - `kf_references[]` is empty OR contains an entry not present in `known-failures.md`
    - `authorized_by` does not resolve via OPERATORS.md
    - Any referenced KF is OPEN CRITICAL AND `break_glass` is missing or invalid (operator_slug mismatch, reason < 16 chars, expiry > now()+24h, audit_event_id unresolvable)
  - **Rationale**: pre-cycle-109, "operator overrides win unconditionally over KF-derived downgrades, including CRITICAL open failures" — the Flatline reviewer caught this. Operator intent CAN be wrong (calibration drift, hot-fix copy-paste, stale config entries muting a fresh KF). The break-glass path remains available for genuine emergencies; the default override path is no longer the break-glass path.
  - **Audit**: every override evaluation (accept OR reject) emitted to
    `.run/kf-auto-link.jsonl` with `before_state`, `after_state`,
    `reason`, `authorized_by`, `kf_id_overridden`, `decision_outcome`
    (`accepted` | `rejected:<failure-mode>`). Break-glass decisions
    ALSO emit a signed L4 trust event to `.run/audit/kf-override-break-glass.jsonl` per cycle-098 audit envelope.
  - **Expiry**: `effective_until` honored at every dispatch; on expiry, auto-link resumes immediately (no grace period beyond 60s clock-skew window).
  - **CI**: PR touching `kf_auto_link.overrides` blocks on ANY of the rejection conditions above (CI failure surfaces the specific rejection reason). `authorized_by` resolution still gated by cycle-098 operator-identity primitive.

  **[IMP-005] Parsing policy for malformed/ambiguous KF entries**
  (deterministic, fail-loud, never auto-degrade on parse failure):
  - Unrecognized `Status:` value → log warning + skip auto-link (no
    downgrade), surface in CI report
  - Empty or missing `model:` reference → skip entry (no-op)
  - Malformed YAML/markdown in KF entry → exit non-zero with line
    reference; CI fails; operator must repair KF entry
  - Multiple model references in one KF → process each independently
    (per-model decision)
  - Duplicate KF IDs → exit non-zero; CI fails

- **FR-1.6**: Ceiling calibration + staleness detection (IMP-007):
  - **Initial population** (per model): empirical probe (preferred,
    binary-search method per cycle-104 T2.10 precedent) OR KF-derived
    (read existing KF entries) OR conservative-default (FR-1.2)
  - **Probe protocol**: 5 prompts × 5 input sizes (10K, 20K, 30K, 40K,
    50K tokens); ceiling = lowest size with empty-content rate > 5%
  - **Staleness detection**: cheval consults `ceiling_calibration.calibrated_at`
    + `stale_after_days`; if stale, emit warning to MODELINV envelope
    (`ceiling_stale: true`) and route through chunked path (FR-4) as
    defensive default
  - **Re-calibration trigger**: any of (a) new KF entry referencing model,
    (b) stale_after_days elapsed, (c) operator-forced via `loa substrate
    recalibrate <model>` CLI

**Acceptance Criteria:**
- [ ] All models in `model-config.yaml` carry the 5 new fields (4 capability + ceiling_calibration), populated correctly
- [ ] Cheval pre-flight gate emits typed exit 7 for inputs > ceiling (bats coverage)
- [ ] MODELINV v1.3 schema lands additively over v1.2 (existing logs parse)
- [ ] KF-auto-link script runs in CI; integration test seeds a fake KF and verifies model degradation per the severity-to-downgrade mapping
- [ ] **[IMP-001]** Severity-to-downgrade mapping table specified in this PRD (above); each row covered by at least one bats fixture
- [ ] **[IMP-002]** Operator-override mechanism shipped with precedence rules + audit trail; integration test verifies precedence + expiry + CI block on missing `authorized_by`
- [ ] **[SKP-004]** Override precedence is **conditional**: rejection conditions (missing/expired/excessive `effective_until`, empty/invalid `kf_references[]`, OPEN CRITICAL KF without `break_glass`) each have a bats fixture demonstrating the rejection path + stderr warning + KF auto-decision falling through; positive-control bats fixture verifies a well-formed break-glass override IS accepted
- [ ] **[SKP-004]** Break-glass overrides emit a signed L4 trust event per cycle-098 audit envelope; conformance test loads the JSONL and verifies Ed25519 signature validates + hash-chain integrity holds
- [ ] **[SKP-003]** `--ceiling-override` requires `--override-operator` + `--override-reason` (≥16 chars) + optional `--override-expiry` (default `now()+24h`, cap `now()+7d`); missing or invalid credential → exit 9; operator must appear in `OPERATORS.md::acls.ceiling-override-authorized`; successful override emits signed `cheval.ceiling_override` audit event to `.run/cheval-overrides.jsonl`
- [ ] **[IMP-005]** Parsing-policy fixtures: malformed YAML, unknown status, missing model, multi-model, duplicate KF id — each produces the documented outcome
- [ ] **[IMP-007]** Ceiling calibration: probe protocol shipped + 5 known models calibrated empirically at cycle-109 ship time; remaining models flagged for follow-up
- [ ] **[IMP-008]** Conservative-default migration applied to all models lacking empirical data; documented in PR body
- [ ] Codegen byte-equality preserved across bash/python/TS for new fields

**Dependencies:** None (foundation sprint)

**System Zone Authorization** [per `.claude/rules/zone-system.md`]:
- Modifies `.claude/defaults/model-config.yaml` (schema additions)
- Modifies `.claude/adapters/cheval.py` (pre-flight gate extension)
- Modifies `.claude/data/schemas/` (MODELINV v1.3)
- Modifies `.claude/scripts/lib/model-config-migrate.py` (v3 migration)
- Adds `.claude/scripts/lib/kf-auto-link.py`
- Modifies `.claude/scripts/generated-model-maps.sh` (codegen output)
- All authorized by this PRD.

---

### FR-2: Verdict-Quality Envelope + Consumer Contracts (Sprint 2)

**Priority:** Must Have
**Description:** Every substrate output carries a first-class verdict-quality
envelope. Consumers refactored to surface it. `status: clean | APPROVED` is
definitionally impossible when verdict quality is degraded.

**Sub-requirements:**

- **FR-2.1**: Define verdict-quality envelope schema
  (`.claude/data/schemas/verdict-quality.schema.json` v1.0):
  ```jsonc
  {
    "status": "APPROVED | DEGRADED | FAILED",        // SKP-001 v3/v4 — REQUIRED canonical
    "consensus_outcome": "consensus | impossible",   // SKP-002 v5 — REQUIRED (replaces unrepresentable private _consensus_impossible)
    "voices_planned": 3,                              // ≥1 enforced by schema
    "voices_succeeded": 2,
    "voices_dropped": [
      {
        "voice": "gpt-5.2",
        "reason": "EmptyContent",
        "exit_code": 1,
        "blocker_risk": "unknown | low | med | high" // SKP-002 v3/v4 — REQUIRED per drop entry
      }
    ],
    "chain_health": "ok | degraded | exhausted",
    "confidence_floor": "high | med | low",
    "rationale": "human-readable explanation of the floor",
    "chunks_reviewed": 0,                            // SKP-001 v5 — chunked-review counters load-bearing
    "chunks_dropped": 0
  }
  ```

  **[SKP-001 closure — Flatline SDD-review v3 CRITICAL BLOCKER]** The
  `status` field is REQUIRED and is the **sole** classification surface
  consumers may read. Re-deriving status from sub-fields is forbidden
  (lints in CI via `tools/lint-verdict-consumers.py`). The cycle-109
  PRD-review trajectory — where `confidence: full` was emitted while a
  voice effectively dropped — recreates exactly here if `status` is
  optional or computed at the consumer; refusing both is the load-bearing
  invariant FR-2 exists to enforce.

  **[SKP-002 closure — Flatline SDD-review v3 HIGH BLOCKER]** Every
  entry in `voices_dropped[]` MUST carry a `blocker_risk` classifier
  output (`unknown | low | med | high`). Computed by the canonical
  `compute_verdict_status()` at envelope-emission time from (a) dropped-
  voice role weight in the cohort, (b) sprint-kind risk band, (c) KF
  priors for `(voice, sprint-kind)`. Operator may override per-call
  via `--blocker-risk-override <enum>` (acceptance criterion).

- **FR-2.2**: Substrate emits envelope on every call — cheval.cmd_invoke
  output extended; FL/RT/BB consumers receive it
- **FR-2.3**: Define classification contract (single canonical function
  `compute_verdict_status` in `cheval.py`; bash twins shell out for
  byte-identical output):
  - `APPROVED` requires: `voices_succeeded == voices_planned`
    AND `chain_health == ok` AND every `voices_dropped[].blocker_risk
    ∈ {unknown, low}` AND no dropped voice findings would have been
    BLOCKER class
  - `DEGRADED` requires: `0 < voices_succeeded < voices_planned` AND
    remaining voices reached consensus AND no dropped voice carries
    `blocker_risk == "high"`
  - `FAILED` requires: `voices_succeeded == 0` OR `chain_health ==
    exhausted` OR consensus impossible OR any
    `voices_dropped[].blocker_risk == "high"` (auto-promotes from
    DEGRADED to FAILED)

**[IMP-004] Consumer inventory + dependency-ordered refactor plan.**
Additive envelope changes still fail if downstream consumers silently
ignore the new field. Enumerated consumers (per reality §3 + grep pass
2026-05-13), refactored in this order:

| # | Consumer | Path | Refactor | Migration order rationale |
|---|----------|------|----------|---------------------------|
| 1 | cheval (canonical emitter) | `.claude/adapters/cheval.py` | Emit envelope on every call | Producer first — all consumers read this |
| 2 | flatline-orchestrator | `.claude/scripts/flatline-orchestrator.sh` | Consume + surface in `final_consensus.json` | Highest-volume consumer; canary |
| 3 | adversarial-review | `.claude/scripts/adversarial-review.sh` | Consume + surface in adversarial-{review,audit}.json | Security-critical (closes #807) |
| 4 | BB cheval-delegate adapter | `.claude/skills/bridgebuilder-review/resources/adapters/cheval-delegate.ts` | Consume + render in PR-comment summary | Operator-facing UI; ships after backend stable |
| 5 | flatline-readiness | `.claude/scripts/flatline-readiness.sh` | Read envelope; gate readiness on `chain_health` | Downstream of FL (#2) |
| 6 | red-team-pipeline | `.claude/scripts/red-team-pipeline.sh` | Consume + log degraded paths | Lowest-volume; lowest priority |
| 7 | post-PR triage | `post-pr-triage.sh` + cycle-053 amendment | Consume in classifier; degraded findings auto-route to next-bug-queue | Independent track; ships after #1-4 |

Consumer-contract conformance (FR-2.7) runs against EVERY consumer in
the table. CI matrix has one job per consumer.

- **FR-2.4**: Refactor FL orchestrator to compute and surface envelope
  [CODE:flatline-orchestrator.sh — existing `emit_voice_dropped` extended
  + `compute_grounding_stats` extended] — consumer #2 in table above
- **FR-2.5**: Refactor adversarial-review to compute and surface envelope
  [CODE:adversarial-review.sh — `assemble_dissent_context` +
  `invoke_dissenter` extended] — consumer #3
- **FR-2.6**: Refactor BB cheval-delegate adapter (TS) to consume envelope
  and surface in PR comment summary
  [CODE:.claude/skills/bridgebuilder-review/resources/adapters/cheval-delegate.ts]
  — consumer #4
- **FR-2.6b**: Refactor consumers #5-7 (flatline-readiness, red-team-pipeline,
  post-PR triage) per dependency order
- **FR-2.7**: Consumer-contract test: a consumer that emits `clean` /
  `APPROVED` on a degraded envelope **fails CI** — enforced by a new
  conformance test pack, one job per consumer in the table above
- **FR-2.8**: Operator-facing PR-comment summary includes verdict_quality
  line at top: `✓ APPROVED — 3/3 voices, chain ok, confidence high`
- **FR-2.9**: Single-voice call semantics (IMP-010 reference) —
  consensus-oriented telemetry fields (`model_agreement_percent`,
  `voices_succeeded`) are emitted with `single_voice_call: true` flag
  when only 1 voice is planned (e.g., BB single-pass review). Consumers
  reading these fields treat them as non-applicable rather than
  inferring degradation from "100% agreement of 1 voice"

**Acceptance Criteria:**
- [ ] Schema lands at `.claude/data/schemas/verdict-quality.schema.json`
- [ ] Every substrate output (all 7 consumers in FR-2 table) carries verdict-quality envelope
- [ ] Conformance test: emitting `clean` on `voices_succeeded < voices_planned`
      fails CI; current [ISSUE:#807] / [ISSUE:#809] fixtures are added to suite
- [ ] PR comment summary surfaces verdict_quality at top of comment
- [ ] [ISSUE:#807] / [ISSUE:#809] / [ISSUE:#868] / [ISSUE:#805] reproductions
      now correctly classify as DEGRADED or FAILED
- [ ] **[IMP-004]** Each consumer in the FR-2 table is refactored in declared dependency order; per-consumer PR (or labeled commit in single-PR variant) traceable in cycle-109 history
- [ ] **[IMP-004]** Cycle-109 PRD-review trajectory (the run that just classified `confidence: full` while Opus voice dropped) is added to the conformance fixture corpus as the canonical "must-not-recur" regression
- [ ] **[SKP-001]** `status: APPROVED|DEGRADED|FAILED` is REQUIRED in the schema (`additionalProperties: false` + required-list enforcement); envelope-emitted without `status` fails the producer-side schema gate AND the consumer-side conformance test
- [ ] **[SKP-001]** Consumer-lint (`tools/lint-verdict-consumers.py`) ships in Sprint 2 and grep-detects any consumer that derives status locally instead of reading the canonical field; lint runs in CI and fails on violation
- [ ] **[SKP-002]** Every `voices_dropped[]` entry carries a `blocker_risk` classifier output (`unknown|low|med|high`); schema requires the field; consumer-contract test asserts emit + correct classification on the cycle-109 PRD-review fixture (Opus drop on security-touching sprint-kind → `blocker_risk = med`)
- [ ] **[SKP-002]** Operator `--blocker-risk-override <enum>` flag wired on `cheval invoke`; override is logged to MODELINV envelope (`blocker_risk_override: <enum>`) with operator slug + reason; missing reason = exit 2

**Dependencies:** FR-1 (envelope cross-references capability_evaluation)

**System Zone Authorization**:
- Adds `.claude/data/schemas/verdict-quality.schema.json`
- Modifies `.claude/adapters/cheval.py`
- Modifies `.claude/scripts/flatline-orchestrator.sh`
- Modifies `.claude/scripts/adversarial-review.sh`
- Modifies `.claude/skills/bridgebuilder-review/resources/adapters/cheval-delegate.ts`
- All authorized by this PRD.

---

### FR-3: Legacy Adapter Sunset + Activation Regression Suite (Sprint 3)

**Priority:** Must Have
**Description:** Fully delete `model-adapter.sh.legacy` (1,081 LOC) and
all consumer branch paths. Build a CI suite that runs every substrate
consumer with `flatline_routing: true` against fixture provider responses.

**Sub-requirements:**

- **FR-3.1**: Inventory all references to `model-adapter.sh.legacy` (grep
  pass; expected: ~10-15 sites across FL/RT/cycles tests)
- **FR-3.2**: Fix the four v1.157.0 regression issues at the cheval path
  (not by patching legacy):
  - [ISSUE:#864] — root-cause legacy CLI crash; verify cheval path
    handles CLI models correctly; close issue when legacy is deleted
  - [ISSUE:#863] — cost-map, scoring engine empty, GPT/Gemini orchestrator
    fail; each fixed at cheval/flatline-orchestrator level
  - [ISSUE:#793] — flatline-orchestrator validator accepts cheval-headless
    pin form
  - [ISSUE:#820] — env loading, alias recommendation, scoring parser
    each fixed at FL level
- **FR-3.3**: Delete `model-adapter.sh.legacy` (1,081 LOC) — operator authorized
  (C109.OP-3)
- **FR-3.4**: Delete or refactor all consumer branches conditional on
  `is_flatline_routing_enabled` returning false [CODE:model-adapter.sh:67,
  flatline-orchestrator.sh:476] — the flag becomes informational-only
  (audit logging) or is removed entirely
- **FR-3.5**: Build activation regression suite
  (`tests/integration/activation-path/`):
  - **[IMP-009] Matrix dimensions** (explicit):
    1. **Consumer**: BB, FL, RT, /bug, /review-sprint, /audit-sprint,
       flatline-readiness, red-team-pipeline, post-PR triage (the FR-2
       table)
    2. **Substrate role**: review, dissent, audit, implementation,
       arbiter (per `recommended_for` taxonomy)
    3. **Provider response class**: success, empty-content (KF-002),
       rate-limited (KF-001-class), chain-exhausted, provider-disconnect
       (#774), context-too-large preempt
    4. **Dispatch path** (IMP-009 dimension): single-dispatch AND
       chunked-dispatch (FR-4) — every consumer × every response class
       executed against BOTH paths; chunked path tested with 2-chunk
       and 5-chunk fixtures
    5. **Verdict-quality outcome**: APPROVED, DEGRADED, FAILED
       (cross-checked against expected for each fixture combo)
  - Fixture-driven; uses cycle-099 sprint-1C curl-mock-harness
  - Runs in CI on every PR touching substrate code; matrix-jobs run in
    parallel (target: <15 min wall-time for full matrix)
- **FR-3.6**: Update rollback documentation: cycle-109 rollback is a `git
  revert` of merge commits, NOT a runtime flag flip (per
  operator-approval C109.OP-3 risk acknowledgment)
- **FR-3.7**: Update `CLAUDE.md` Multi-Model Activation section to remove
  legacy-fallback rollback path; replace with "rollback = revert" guidance

**Acceptance Criteria:**
- [ ] `git ls-files` reports zero references to `model-adapter.sh.legacy`
- [ ] All 4 Cluster B issues closed (#864, #863, #793, #820)
- [ ] Activation regression suite runs in CI with all matrices passing
- [ ] `hounfour.flatline_routing` config key is removed OR fully informational
- [ ] CLAUDE.md updated to reflect new rollback model

**Dependencies:** FR-1 + FR-2 (the suite tests against capability + verdict envelopes)

**System Zone Authorization**:
- Deletes `.claude/scripts/model-adapter.sh.legacy`
- Modifies `.claude/scripts/model-adapter.sh` (remove flag-gated branches)
- Modifies `.claude/scripts/flatline-orchestrator.sh` (remove flag-gated branches)
- Adds `tests/integration/activation-path/` suite
- Modifies `.claude/loa/CLAUDE.loa.md` rollback section
- All authorized by this PRD.

---

### FR-4: Hierarchical / Chunked Review for Large Inputs (Sprint 4)

**Priority:** Must Have
**Description:** When input exceeds a model's `effective_input_ceiling`,
cheval automatically chunks the review and aggregates findings, rather
than dispatching and discovering empty-content empirically.

**Sub-requirements:**

- **FR-4.1**: Define chunking strategy for diff/PR review (the primary
  large-input case):
  - Chunk boundary: file-level (preserve coherent review units)
  - Per-chunk size: max `effective_input_ceiling * 0.7` (headroom for
    prompt overhead)
  - Cross-chunk context: shared header (PR description, affected files
    list) prepended to each chunk
- **FR-4.2**: Cheval orchestrates chunked dispatch when pre-flight gate
  (FR-1.3) determines input > ceiling
- **FR-4.3**: Findings aggregation: dedupe by (file, line, finding-class);
  preserve grounded anchors.

  **[IMP-006] Conflict resolution policy** for cross-chunk findings:
  - **Same (file, line, finding-class)** → dedupe, keep highest-severity
    instance + union of evidence anchors
  - **Same (file, line) but different finding-class** → keep both; emit
    `cross_chunk_overlap: true` annotation for operator review
  - **Same finding-class but different line** within same file → keep
    both (different sites)
  - **Conflicting severities** for the same logical finding (rare;
    cross-chunk reviewer disagreement) → escalate to higher severity +
    annotate `severity_escalated_from: <lower>` in finding payload
  - **Finding spans chunk boundary** (e.g., shell injection where
    sanitizer + sink in different chunks) → cross-chunk pass: cheval
    re-runs review on adjacent-chunk pairs that triggered overlap
    annotations; this is a second-stage aggregation
- **FR-4.4**: Streaming-with-recovery (defensive): for non-chunked calls
  where pre-flight gate passed but model still empty-contents within
  first N tokens, abort early with typed exit (not silent timeout)
  — this protects against capability data being wrong/stale.

  **[IMP-014] Specific thresholds** (per-model, override via
  `model-config.yaml::models.<id>.streaming_recovery`):
  - **First-token-deadline**: 30s default; per-model override
    (reasoning-class models may need 60s for CoT prelude)
  - **Empty-content detection**: first 200 tokens of output content
    examined; if zero non-whitespace tokens AND `reasoning_class: false`,
    OR if zero non-CoT tokens AND `reasoning_class: true`, treat as
    empty-content
  - **CoT-detection heuristic** (for `reasoning_class: true`): tokens
    matching `^(thinking|let me|i'll|first[,]? i)` regex (loose) plus
    XML-like `<thinking>` opening tags counted as CoT, not content
  - **Abort emission**: typed exit code 1 with subcode `EmptyContent`
    (matches cycle-103 taxonomy); MODELINV envelope records
    `streaming_recovery: {triggered: true, tokens_before_abort: N,
    reason: "no_content_in_first_200_tokens"}`
  - **Per-model thresholds** lives in `model-config.yaml` (additive to
    Sprint 1 schema):
    ```yaml
    streaming_recovery:
      first_token_deadline_seconds: 60  # reasoning_class default
      empty_detection_window_tokens: 200
      cot_token_budget: 500  # reasoning_class only; abort if CoT consumes more
    ```
- **FR-4.5**: MODELINV envelope records `chunked: true, chunks_reviewed:
  N, chunks_dropped: 0, chunks_aggregated_findings: M`
- **FR-4.6**: Operator-facing summary on chunked review: surfaces chunk
  count and any per-chunk degradation distinctly from overall verdict
- **FR-4.7**: References [ISSUE:#791] (cycle-101 BB hierarchical review
  pipeline) as the design lineage; closes [ISSUE:#866] / [ISSUE:#823] /
  [KF-002 layer-1 structural]

**Acceptance Criteria:**
- [ ] >70KB FL input completes successfully against fixture providers (bats)
- [ ] >40K reasoning-class input produces non-empty findings via chunking
- [ ] Chunked-review aggregation: deduplication + finding-anchor preservation tested
- [ ] Streaming early-abort triggers on simulated empty-content (bats with mock)
- [ ] [ISSUE:#866] / [ISSUE:#823] reproduction fixtures pass
- [ ] **[IMP-006]** Each conflict-resolution case has at least one fixture: dedupe-same, dedupe-different-class, different-line, severity-escalation, cross-chunk-overlap
- [ ] **[IMP-014]** Per-model `streaming_recovery` thresholds shipped in `model-config.yaml`; bats verify abort triggers at the documented thresholds; reasoning-class CoT-detection regex tested with positive AND negative controls

**Dependencies:** FR-1 (uses `effective_input_ceiling`), FR-2 (chunked
output carries verdict envelope with per-chunk drilldown), FR-3
(activation regression suite covers chunked path)

**System Zone Authorization**:
- Modifies `.claude/adapters/cheval.py` (chunking orchestration)
- Modifies `.claude/scripts/flatline-orchestrator.sh` (chunked-review aggregation)
- Adds chunking helper module under `.claude/adapters/`
- All authorized by this PRD.

---

### FR-5: Carry Items + Substrate Observability (Sprint 5)

**Priority:** Should Have (carry items) + Must Have (observability)
**Description:** Close cycle-108 carry items and deliver operator-facing
substrate health surface.

**Sub-requirements:**

**Carry items:**
- **FR-5.1**: [ISSUE:#874] — cheval.py advisor-strategy provider-peek
  narrow 'anthropic' fallback (C-S2-1) — generalize peek across providers
- **FR-5.2**: [ISSUE:#875] — modelinv.py parents[4] hardcode (C2 from
  sprint-1) — replace with path resolution against repo root marker
- **FR-5.3**: [ISSUE:#870] — modelinv-rollup.sh O(N) per-line subprocess
  spawn — refactor to single-pass parse

**Observability:**
- **FR-5.4**: CLI surface: `loa substrate health [--window 24h] [--json]`
  — reads `.run/model-invoke.jsonl` (MODELINV envelope log); aggregates
  per-model success/drop/exhaustion/p95/cost
- **FR-5.5**: Output format:
  ```
  Substrate health, last 24h:
    claude-opus-4-7:    SUCCESS 87% (N=234) | drop 8% | exhaust 5% | p95 12s | $4.21
    gpt-5.2:            SUCCESS 92% (N=189) | drop 6% | exhaust 2% | p95 8s | $2.84
    gemini-2.5-pro:     DEGRADED 45% (N=92) | drop 41% | exhaust 14% | p95 18s | $0.91
  ⚠ gemini-2.5-pro health DEGRADED: file a KF or restrict role
  ```
- **FR-5.6**: Performance: <2s for 24h window on typical log volumes
- **FR-5.7**: Health-threshold warnings: model below 80% success_rate
  emits a warning line; below 50% emits an error and suggests filing
  a KF entry (closes the UC-3 feedback loop)
- **FR-5.8**: Optional: scheduled job (cron) that runs `loa substrate
  health` daily and writes to a journal file (`grimoires/loa/substrate-health/YYYY-MM.md`)

**Acceptance Criteria:**
- [ ] All 3 carry items closed (#874, #875, #870)
- [ ] `loa substrate health` CLI ships; tested with synthetic envelope corpus
- [ ] Performance target met (<2s 24h window)
- [ ] Operator can identify a degrading model BEFORE filing a substrate issue (UC-4)

**Dependencies:** FR-1 (envelope fields), FR-2 (verdict-quality), FR-4
(chunked annotations) — observability surface reads everything prior
sprints emit.

**System Zone Authorization**:
- Modifies `.claude/adapters/cheval.py` (FR-5.1)
- Modifies `.claude/scripts/lib/modelinv*.{py,sh}` (FR-5.2, FR-5.3)
- Adds CLI subcommand under `.claude/scripts/` for FR-5.4
- All authorized by this PRD.

---

## 6. Non-Functional Requirements

### 6.1 Performance

- **NFR-Perf-1**: Cheval pre-flight gate adds <50ms overhead per dispatch
  (capability lookup is in-memory after first load)
- **NFR-Perf-2**: Chunked review for a 100KB PR completes in ≤2.5× the
  time of a single dispatch on a same-size PR (with chunking overhead
  budgeted)
- **NFR-Perf-3**: `loa substrate health --window 24h` completes in <2s
  on a 100K-entry MODELINV log

### 6.2 Reliability

- **NFR-Rel-1**: No substrate output may emit `status: clean | APPROVED`
  when verdict_quality is degraded (enforced by FR-2.7 consumer-contract test)
- **NFR-Rel-2**: Cheval pre-flight gate exits with typed code 7
  (ContextTooLarge) — never silent timeout — when capability is breached
- **NFR-Rel-3**: KF-auto-link script (FR-1.5) is idempotent and
  deterministic — running twice on the same ledger state produces
  byte-identical `model-config.yaml`
- **NFR-Rel-4**: MODELINV envelope hash-chain integrity preserved across
  v1.2 → v1.3 migration (additive only; no field removals; existing
  signatures verify)

### 6.3 Security

- **NFR-Sec-1**: Capability-evaluation pre-flight gate MUST NOT leak
  prompt content to logs (input size only — already gate-controlled)
- **NFR-Sec-2**: KF-auto-link script reads `known-failures.md` (TRACKED,
  git-managed) only — no arbitrary file inputs; no shell injection
  surface (parsed as YAML/markdown, not eval'd)
- **NFR-Sec-3**: `loa substrate health` output redacts secrets per
  existing redactor (`lib/log-redactor.{sh,py}` — cycle-099 sprint-1E.a);
  reuse, do not reinvent
- **NFR-Sec-4**: Verdict-quality envelope NEVER carries credentials,
  endpoint URLs, or API keys — schema validation rejects unknown fields

### 6.4 Maintainability

- **NFR-Maint-1**: Substrate code path is **single-pathed** — no legacy
  fallback after Sprint 3
- **NFR-Maint-2**: Substrate-affecting changes carry KF cross-reference
  in commit message or PR body (enforced by post-PR audit)
- **NFR-Maint-3**: `model-config.yaml` schema v3 is forward-compatible:
  v3 → v4 transitions follow the v1 → v2 migration precedent
  (`tools/migrate-model-config.py`)

### 6.5 Auditability

- **NFR-Aud-1**: Every substrate dispatch produces a MODELINV v1.3
  envelope in `.run/model-invoke.jsonl` — coverage ≥0.95 (raised from
  cycle-108 baseline 0.90)
- **NFR-Aud-2**: KF-auto-link decisions logged to
  `.run/kf-auto-link.jsonl` with `before_state`, `after_state`, `kf_id`
- **NFR-Aud-3**: Activation regression suite (FR-3.5) emits per-run
  artifact summaries to `.run/activation-regression/` for cycle-close audit

### 6.6 Codegen Byte-Equality

- **NFR-Codegen-1**: Any change to `model-config.yaml` schema MUST
  regenerate `generated-model-maps.sh` AND the TS port AND remain
  byte-identical across runtimes (cycle-099 sprint-1D precedent —
  enforced by `cross-runtime-diff.yml` CI gate)

---

## 7. User Experience

### 7.1 Operator Flows

#### Flow 1: Trusting a verdict

```
operator: /run sprint-plan
substrate (post-cycle-109):
  → implement (sprint-N)
  → review: BB cheval-delegate
    → emits PR comment header:
      "✓ APPROVED — 3/3 voices, chain ok, confidence high"
  → audit: FL multi-model
    → emits audit summary header:
      "✓ APPROVED — 3/3 voices, chain ok, confidence high"
  → CI green; merge enabled
operator: merge with confidence
```

Compare to current state:
```
operator: /run sprint-plan
substrate (current):
  → review: BB single-model two-pass; Pass 2 fails ~80% (#805)
  → audit: 2/3 voices dropped silently; output says "status: clean" (#807)
operator: merges; ships shell-injection to production (#807 actual incident class)
```

#### Flow 2: Substrate degradation surfaces before catastrophe

```
operator: loa substrate health
substrate:
  → reads 24h MODELINV log
  → reports per-model rates
  → flags gemini-2.5-pro at 45% success (DEGRADED)
operator: files KF-NNN against gemini-2.5-pro
KF-auto-link script:
  → parses new KF entry
  → updates model-config.yaml::gemini-2.5-pro.recommended_for
  → drops gemini-2.5-pro from primary-review roles
substrate (next dispatch):
  → routes to anthropic primary; cites KF-NNN in MODELINV envelope
```

### 7.2 Interaction Patterns

- **Verdict-first summaries**: every substrate output leads with a single
  unambiguous line — `APPROVED | DEGRADED | FAILED` + voice/chain/
  confidence; full findings list follows
- **Fail-loud over fail-silent**: when the substrate cannot complete a
  call, it emits a typed exit code with rationale, not a silent timeout
  or an empty success
- **KF ledger as feedback loop**: operator observations flow into
  substrate behavior through the existing `known-failures.md` mechanism;
  no separate "model preferences" UI

### 7.3 Accessibility

- All output is plaintext / JSON; no GUI dependencies
- `loa substrate health --json` enables tooling integrations (dashboards,
  alerting)

---

## 8. Technical Considerations

### 8.1 Architecture Notes

The substrate's architectural shape per ADR-002 [REALITY:multimodel-substrate.md:§2]
is **preserved**, not replaced. Cycle-109 fills in capability awareness
*inside* the existing cheval-canonical-HTTP-boundary shape; it does not
introduce a new boundary, a new aggregator (OpenRouter rejected), or a
new top-level component.

Concretely:

- Pre-flight gate (FR-1.3) is added inside `cheval.py::cmd_invoke`
  before adapter dispatch
- Verdict-quality envelope (FR-2.1) extends the existing JSON output
  schema — additive, not replacement
- Legacy delete (FR-3.3) simplifies the shape by removing a parallel
  path, not by introducing one
- Chunked review (FR-4) is orchestrated inside cheval, not as a new
  consumer
- Observability surface (FR-5.4) is a read-only consumer of the existing
  MODELINV log

### 8.2 Integrations

| System | Integration Type | Purpose |
|--------|------------------|---------|
| `model-config.yaml` | Schema extension | New capability fields (FR-1) |
| `known-failures.md` | Watcher | KF-auto-link script (FR-1.5) |
| `.run/model-invoke.jsonl` | Read-only consumer | Substrate health CLI (FR-5.4) |
| Cycle-099 curl-mock-harness | Test fixture provider | Activation regression suite (FR-3.5) |
| Cycle-098 audit envelope | Hash-chain extension | MODELINV v1.3 additive |
| `verdict-quality.schema.json` | Schema definition | Consumer-contract enforcement (FR-2) |

### 8.3 Dependencies

- **No new external dependencies** — all work uses existing Python,
  bash, TypeScript, yq, jq, gh tooling already in the substrate
- **Internal dependencies**: FR-2 depends on FR-1; FR-3 depends on FR-1+2;
  FR-4 depends on FR-1+2+3; FR-5 depends on all prior (read-only consumer
  of their emissions)

### 8.4 Technical Constraints

- **Codegen byte-equality** [NFR-Codegen-1] — every schema change must
  regenerate across runtimes
- **MODELINV envelope continuity** — v1.2 → v1.3 must be additive only;
  signatures preserve
- **Test-first** [CLAUDE.md `/bug` precedent extended to all cycle-109
  sprints] — every sprint's PR carries failing tests in the first
  commit, passing tests in the implementing commit
- **Iron-grip quality gates** — see §13

### 8.5 Out-of-Scope Architectural Decisions (Explicit)

- **No OpenRouter (or similar aggregator) integration** — analyzed and
  rejected 2026-05-13. Three of four clusters are not routing problems;
  integration would add a dependency layer without addressing root causes.
- **No new providers / transports** — substrate-internal only
- **No new feature flags** — `hounfour.flatline_routing` is being removed
  (FR-3.4); no replacement
- **No new model entries added during the cycle** — capability fields
  are added to existing entries; new model additions are post-cycle work

---

## 9. Scope & Prioritization

### 9.1 In Scope (Cycle-109)

**Sprint 1** (FR-1) — Capability-aware substrate foundation
**Sprint 2** (FR-2) — Verdict-quality envelope + consumer contracts
**Sprint 3** (FR-3) — Legacy adapter sunset + activation regression suite
**Sprint 4** (FR-4) — Hierarchical / chunked review for large inputs
**Sprint 5** (FR-5) — Carry items + substrate observability

### 9.2 Explicitly Out of Scope

| Item | Reason |
|------|--------|
| OpenRouter / aggregator integration | Routing is not the failure surface (operator-rejected 2026-05-13) |
| New providers (Mistral, Cohere, etc.) | Substrate-internal hardening cycle only |
| New transports (additional CLI integrations) | Substrate-internal hardening cycle only |
| Cycle-108 advisor-strategy adoption (decision-fork c' → a/b) | Behind `enabled: false`; separate cycle when triggers met (`rollout-policy.md`) |
| Multi-model UI/dashboard (beyond CLI surface) | Out of cycle scope; CLI is sufficient operator surface |
| Changes to BB skill output format beyond verdict-quality surfacing | Scope-creep risk; existing format preserved |

### 9.3 Future Iterations (Post-Cycle-109)

- **Cycle-110+**: Advisor-strategy adoption (cycle-108 decision-fork c' → a/b)
  if production telemetry meets `rollout-policy.md` triggers
- **Cycle-110+**: Substrate cost-optimization (per-call routing by cost)
- **Cycle-110+**: New provider integrations IF substrate health
  demonstrably stable for 30+ days post-cycle-109

### 9.4 Priority Matrix

| Sprint | Priority | Effort | Impact | Risk if skipped |
|--------|----------|--------|--------|-----------------|
| FR-1 (Capability) | P0 | M | High | All other sprints depend on it |
| FR-2 (Verdict envelope) | P0 | M | High | Trust crisis unaddressed (#807-class continues) |
| FR-3 (Legacy sunset) | P0 | L | High | Cluster B regenerates next release |
| FR-4 (Chunked review) | P0 | L | High | KF-002 next-zoom in cycle-110 |
| FR-5 (Carry + observability) | P1 | M | Medium | Carry items deferred; degradation invisible |

---

## 10. Success Criteria

### 10.1 Launch Criteria (End of Cycle-109)

- [ ] All 13 OPEN substrate issues from reality §9 closed (#793, #805, #807,
      #809, #820, #823, #863, #864, #866, #868, #870, #874, #875)
- [ ] G-1 through G-5 met (see §3.1)
- [ ] All sprint acceptance criteria met (§5 FR-1 through FR-5)
- [ ] All NFR thresholds met (§6)
- [ ] Activation regression suite is green and required-in-CI
- [ ] Final cycle audit passes (per /audit-sprint + /ship pattern)
- [ ] CHANGELOG.md updated; cycle-109 tag signed; operator-approval ledger
      complete

### 10.2 Post-Launch Success (30 days)

- [ ] Zero new KF-002-class entries (large-doc empty-content)
- [ ] Zero `status: clean` false positives in production audit log replay
- [ ] Substrate observability (`loa substrate health`) used by operator
      ≥3 times (engagement signal)
- [ ] Operator headspace reduction observable: ratio of multi-model issue
      filings to revenue-work commits drops materially

### 10.3 Long-term Success (90 days)

- [ ] Substrate becomes "boring infrastructure" — operator does not
      mention multi-model when describing pain points in cycle reviews
- [ ] Advisor-strategy decision-fork c' → a/b unblocked by sustained
      substrate health
- [ ] Cycle-110+ work proceeds without substrate as a tax

---

## 11. Risks & Mitigation

### 11.1 Risk Register

| ID | Risk | Probability | Impact | Mitigation |
|----|------|-------------|--------|------------|
| R-1 | Capability data is wrong (effective_input_ceiling set too high or low) | Med | Med | FR-4.4 streaming-with-recovery defensive fallback; FR-1.5 KF auto-link feedback loop self-corrects |
| R-2 | Legacy delete (FR-3) breaks a consumer not in our inventory | Med | High | FR-3.1 inventory pass; FR-3.5 activation regression suite catches before merge; per-sprint Bridgebuilder review; operator approves Sprint 3 PR specifically |
| R-3 | Verdict-quality envelope breaks existing consumer integrations | Low | Med | FR-2 envelope is additive; existing fields preserved; per-consumer refactor (FR-2.4-2.6) explicit; conformance test (FR-2.7) catches divergence |
| R-4 | Chunked review (FR-4) changes finding behavior (false positives/negatives) | Med | Med | Deduplication tests; finding-anchor preservation tests; A/B comparison against single-dispatch baseline on representative PR corpus |
| R-5 | MODELINV envelope v1.3 break existing replay logs | Low | High | v1.3 schema is additive only (NFR-Aud-1); existing parsers tested for backward compatibility |
| R-6 | Cycle scope is too large; runway pressure forces premature ship | Med | High | Per-sprint independent value; if Sprint 4-5 slips, Sprints 1-3 alone meaningfully harden substrate; operator-visible escape via §11.3 |
| R-7 | KF-auto-link (FR-1.5) over-degrades models (false-positive degradation) | Low | Med | Severity-mapping documented; degradations reversible (KF resolves → re-upgrade); operator can manual-override in `.loa.config.yaml` |
| R-8 | Substrate becomes single-point-of-failure after legacy delete | Low | High | This was already true at v1.157.0 for the activated default; legacy was nominal-not-real safety net; mitigation is investing in substrate quality (which is what the cycle does) |
| R-9 | Test substrate (curl-mock-harness, fixture provider responses) drifts from real provider behavior | Med | Med | Fixtures versioned and reviewed; sprint-1C precedent established; periodic real-provider smoke run |

### 11.2 Assumptions

- **[ASSUMPTION]** OpenAI API quota restored 2026-05-13 [OPERATOR:2026-05-13]
  — adversarial review can use OpenAI again; this unblocks portions of
  Cluster B+C testing. If quota lapses again mid-cycle, fall back to
  fixture-only testing per cycle-099 sprint-1C harness.
- **[ASSUMPTION]** No new substrate-class issues surface that fundamentally
  change the four-cluster diagnosis. If a fifth cluster emerges mid-cycle
  (e.g., transport-layer failure not captured by current clusters),
  evaluate against cycle scope: defer if feature-class, fold into Sprint 5
  if hardening-class.
- **[ASSUMPTION]** `effective_input_ceiling` can be determined empirically
  for each model (probing or prior-KF data). If a model has no signal
  yet, default conservatively (50% of advertised context window) and let
  the KF feedback loop tune.
- **[ASSUMPTION]** Existing cycle-098 audit envelope hash-chain semantics
  apply unchanged to MODELINV v1.3 (additive-only preserves the chain).
- **[ASSUMPTION]** Cycle-110 will exist and is the appropriate destination
  for any cycle-109 scope-slip; no calendar dependency forces cycle-109
  to absorb scope it should defer.

### 11.3 Escape Hatch (operator-visible rollback)

If cycle-109 introduces a regression that materially worsens substrate
health vs the pre-cycle baseline, the rollback procedure is:

1. `git revert` of the cycle-109 merge commits
2. Operator approval recorded in cycle-109 operator-approval.md as `C109.OP-N-ROLLBACK`
3. Substrate reverts to v1.157.0 + cycle-108 baseline
4. Post-mortem KF entry recorded
5. **Not via `flatline_routing: false`** — after FR-3.3, the legacy path
   no longer exists, so the runtime flag is not a rollback option
6. Acknowledged risk per operator-approval C109.OP-3

### 11.4 Unverified Assumptions (Tagged for Future Verification)

- ~~[ASSUMPTION] KF-auto-link severity mapping deferred~~ — **RESOLVED in v1.1
  per IMP-001 HIGH_CONSENSUS**; canonical table now in FR-1.5
- [ASSUMPTION] §6.1 NFR-Perf-1 50ms overhead target — to be measured
  in Sprint 1 against pre-flight-gate-disabled baseline
- [ASSUMPTION] §5 FR-4.1 file-level chunking is the right boundary for
  PR review — alternative (token-budget greedy packing) to be evaluated
  in Sprint 4 SDD
- ~~[ASSUMPTION] §10.2 30-day metric "ratio of multi-model issue filings
  to revenue-work commits"~~ — **RESOLVED in v1.1 per IMP-003**; defined
  in §3.4 baseline methodology table
- [ASSUMPTION] §3.4 baseline measurement protocol assumes 30d of MODELINV
  log data available for "clean false-positive rate" baseline; if log
  history is shorter, baseline window adjusts to available data and is
  noted in `baselines/clean-fp-rate.json` metadata
- [ASSUMPTION] FR-1.6 empirical-probe binary-search reliably converges
  on `effective_input_ceiling` within ~5 trials per model; if convergence
  fails for a model, conservative-default (FR-1.2) is used and KF entry
  filed for follow-up

### 11.5 Dependencies on External Factors

- **OpenAI API access** for adversarial review testing (per operator
  funding 2026-05-13)
- **`gh` API access** for issue lifecycle tracking (existing dependency)
- **No upstream model behavior changes** that invalidate
  `effective_input_ceiling` values mid-cycle (if Anthropic/OpenAI/Google
  changes model behavior under the hood, KF feedback loop captures it)

---

## 12. Timeline & Milestones

| Milestone | Target | Deliverables |
|-----------|--------|--------------|
| PRD complete | 2026-05-13 (today) | This document; operator-approval C109.OP-1 |
| Flatline PRD review | 2026-05-14 | Flatline review passes (multi-model adversarial check; ironic — uses the substrate it audits) |
| SDD complete | 2026-05-15 | `/architect` produces SDD for all 5 sprints |
| Sprint plan complete | 2026-05-16 | `/sprint-plan` produces task graph in beads |
| Sprint 1 (Capability) | ~1 week | FR-1 shipped; G-1 partial; G-2 foundation |
| Sprint 2 (Verdict envelope) | ~1 week | FR-2 shipped; G-3 met |
| Sprint 3 (Legacy sunset) | ~1.5 weeks | FR-3 shipped; G-4 met; G-1 substantially advanced |
| Sprint 4 (Chunked review) | ~1 week | FR-4 shipped; G-2 met |
| Sprint 5 (Carry + observability) | ~1 week | FR-5 shipped; cycle launch criteria met |
| Cycle close + tag | end of cycle | Cycle-109 archived; CHANGELOG; signed release tag; operator-approval complete |

**Total estimate**: 4-6 weeks engineering time; cycle ships when criteria met, not on calendar pressure (operator-explicit: "don't cut corners").

---

## 13. Quality Gates & Loa Process Conformance

This section is the **iron-grip enforcement** the operator mandated.

### 13.1 PRD Gate (this document)

- [ ] **Flatline PRD review** before `/architect` — must pass HIGH_CONSENSUS or have explicit operator override (per cycle-108 precedent)
- [ ] Operator-approval entry C109.OP-1 in place — done
- [ ] Cited against reality + KF ledger — done

### 13.2 SDD Gate

- [ ] `/architect` produces SDD for all 5 sprints
- [ ] **Flatline SDD review** before `/sprint-plan` — must pass HIGH_CONSENSUS or operator override
- [ ] SDD addresses all FR / NFR / risks from this PRD
- [ ] SDD specifies test-first patches for every sprint

### 13.3 Sprint Plan Gate

- [ ] `/sprint-plan` produces beads task graph
- [ ] **Flatline sprint-plan review** before `/run` — must pass HIGH_CONSENSUS or operator override
- [ ] Every sprint has explicit acceptance criteria mapped to FR-N + AC list
- [ ] Sprint Ledger updated; cycle-109 sprints registered with global IDs

### 13.4 Per-Sprint Gates

For every sprint:

- [ ] **`/run sprint-N`** — never direct `/implement` (per CLAUDE.md NEVER rule)
- [ ] **implement → review → audit cycle** — full cycle, no skipping
- [ ] **Test-first**: PR's first commit lands failing tests; second commit makes them pass
- [ ] **Bridgebuilder review** on the PR; iterate until plateau
- [ ] **Post-PR audit** ((`post_pr_validation.phases.bridgebuilder_review.enabled: true`) — process per cycle-053 amendment
- [ ] **Beads task lifecycle**: every task transitions `created → in-progress → closed`; orphan tasks investigated
- [ ] **KF cross-reference** in PR body when sprint addresses a KF entry
- [ ] **MODELINV v1.3 envelope** emitted for every cheval call during sprint testing — `.run/model-invoke.jsonl` reviewed at sprint close

### 13.5 Per-PR Gates

- [ ] `auto_push: false` (or operator-explicit push approval)
- [ ] CODEOWNERS auto-assignment → @janitooor primary reviewer
- [ ] CI green (all activation regression matrix + unit + integration)
- [ ] Bridgebuilder review posted as PR comment
- [ ] Post-PR triage classified findings (CRITICAL/BLOCKER → next-bug-queue; HIGH → logged; PRAISE → lore candidate per cycle-053)
- [ ] No commit skips hooks (no `--no-verify`, no `--no-gpg-sign`) per project safety hooks

### 13.6 Audit Trail

Every sprint produces:

- `grimoires/loa/cycles/cycle-109-substrate-hardening/sprint-N-debrief.md` — handoff per cycle-109 sprint structure
- `.run/audit.jsonl` entries (mutation logger hook)
- `.run/model-invoke.jsonl` envelopes (substrate dispatches)
- `.run/activation-regression/sprint-N.json` (after FR-3.5 lands)
- Bridgebuilder review on PR
- Operator-approval entry for any substrate-changing sprint (per cycle-108 precedent)

### 13.7 Circuit Breaker

`/run sprint-plan` circuit-breaker remains active throughout cycle-109.
Tripping conditions (per existing `run-mode` design):

- 3 consecutive sprint failures → HALT, await `/run-resume`
- Audit-gate failure → HALT, await operator review
- Substrate degradation observed during cycle execution (irony case —
  if multi-model fails on its own audit) → HALT, fall back to
  single-model BB with operator notification

Operator may /run-halt at any time; /run-resume requires the halt
reason addressed.

### 13.8 Escape from Quality Gates (NOT permitted in cycle-109)

Per operator instruction "iron grip", the following shortcuts are
**forbidden** during cycle-109:

- ❌ Skipping Flatline review on PRD/SDD/sprint-plan
- ❌ Direct `/implement` without `/run sprint-N` wrapper
- ❌ Direct PR merge without Bridgebuilder + post-PR audit
- ❌ Committing without test-first
- ❌ Using `/bug` to bypass cycle scope on feature work
- ❌ TaskCreate as a replacement for beads task tracking
- ❌ Manual `.run/` edits (lead-only in Agent Teams mode; mutation logger captures)

Violations of any of these constitute a process incident; record in
NOTES.md and route through `/feedback` to upstream Loa.

---

## 14. Appendix

### A. Stakeholder Insights

**Operator (2026-05-13)**:

- "this is our flagship feature and is the foundation to our entire
  approach and quality control" — substrate is load-bearing infrastructure
- "used to work well with the older models so this is really painful" —
  diagnostic clue: substrate regressed with newer reasoning-class models
- "this is now consuming alot of our budget in terms of headspace, tokens,
  money and time" — substrate has crossed from asset to liability
- "stopping us from advancing in our main mission which are the things
  which will bring revenue as we are significantly running out of runway"
  — runway pressure is the operational context for this cycle
- "i want us to invest in getting this right sooner then later. don't cut
  corners i don't mind investing, but lets get this right" — depth over
  speed; root cause over symptom
- "i defer to you on implementation details providing we're following loa
  process and quality control / gates / loops with an iron grip" —
  autonomous authorization with iron-grip quality constraint

### B. Competitive Analysis

**OpenRouter and similar aggregators**: evaluated as substitute for the
cheval substrate; rejected. Analysis (2026-05-13):

| Cluster | Substrate failure mode | OpenRouter addresses? |
|---------|------------------------|------------------------|
| A — Large-doc | Model returns empty content at >40K input | No — same model, same failure |
| B — v1.157.0 regressions | Defects in our code (legacy adapter, scoring) | No — our code, not their layer |
| C — Degraded semantics | Consumer-side classification logic | No — our logic, not theirs |
| D — Carry items | Substrate code paths | No — our code |

OpenRouter would consolidate chain-walking (which cheval already does)
while adding a dependency layer, lacking CLI transports (claude-code,
codex-headless, gemini-cli), and not addressing the actual failure
surface. Substrate stays.

### C. Bibliography

**Internal Resources:**
- Reality file: `grimoires/loa/reality/multimodel-substrate.md`
- Known-failures ledger: `grimoires/loa/known-failures.md`
- Cycle-108 PRD/SDD/sprint: `grimoires/loa/cycles/cycle-108-advisor-strategy/`
- ADR-002: `docs/architecture/ADR-002-multimodel-cheval-substrate.md` (referenced from reality §2)
- Operator-approval ledger: `grimoires/loa/cycles/cycle-109-substrate-hardening/operator-approval.md`
- CLAUDE.md framework instructions: `.claude/loa/CLAUDE.loa.md`

**GitHub Issues (cycle-109 inputs, OPEN at HEAD 6e76582d):**
- #793, #805, #807, #809, #820, #823, #863, #864, #866, #868, #870, #874, #875

**KF Ledger Entries (substrate-class):**
- KF-001 (RESOLVED), KF-002 (LAYER-1 LATENT — cycle-109 target), KF-003
  (RESOLVED), KF-004 (RESOLVED), KF-005 (RESOLVED-VIA-WORKAROUND), KF-006
  (RESOLVED), KF-007 (RESOLVED), KF-008 (RESOLVED), KF-009
  (DEGRADED-ACCEPTED), KF-010 (status per ledger)

### D. Glossary

| Term | Definition |
|------|------------|
| Substrate | The multi-model dispatch layer: cheval.py + supporting bash/TS components |
| Cheval | Canonical Python HTTP boundary for model dispatch [REALITY:§2] |
| Voice | A model called as part of a consensus / dissent / arbitration pattern |
| Voice-drop | When a voice's chain exhausts and the substrate proceeds without it (cycle-104 T2.8) |
| Chain-walk | Cheval's within-company fallback chain traversal on retryable errors |
| Effective input ceiling | The input size at which a model starts empty-contenting, distinct from API-advertised context window |
| Reasoning class | Models that burn output budget on internal CoT (newer Opus, GPT-5.5-pro, etc.) |
| Verdict quality | The new envelope describing HOW a verdict was reached (FR-2) |
| KF ledger | `grimoires/loa/known-failures.md` — append-only log of observed degradation patterns |
| Activation regression suite | New CI suite (FR-3.5) testing every consumer × every role under `flatline_routing: true` |
| MODELINV envelope | Audit record per dispatch in `.run/model-invoke.jsonl` (v1.3 in cycle-109) |
| Decision-fork c' | Cycle-108 close pattern: ship substrate, defer adoption pending empirical data |

---

### E. Flatline Integration Log (v1.0 → v1.1)

Run: `grimoires/loa/a2a/flatline/cycle-109-prd-review.json` (2026-05-13)
Gate decision: PASSED-WITH-DEGRADED-EVIDENCE; operator-override path 1 per C109.OP-4.

**Substrate degradation observed during this very review** (the meta-finding):
- 3 models nominally active (opus + gpt-5.5-pro + gemini-3.1-pro-preview)
- Opus produced 1 of 14 review items; all 13 DISPUTED findings had `opus_score: 0`
- Model agreement: 7%
- Substrate self-report: `degraded: false, confidence: full, tertiary_status: active`
- Cost reported: 0 cents (cost-map defect, separate manifestation of #863)
- **Conclusion**: substrate operated at ~1.5 voices of 3 while self-reporting full confidence — the exact failure mode FR-2 (verdict-quality envelope) addresses. Recorded as the canonical regression fixture for FR-2.7 conformance test (per acceptance criterion in FR-2).

**Findings integrated into v1.1:**

| ID | Avg Score | Where integrated | Status |
|----|-----------|------------------|--------|
| IMP-001 | 885 (HIGH_CONSENSUS) | FR-1.5 severity-to-downgrade mapping table | ✓ Integrated |
| IMP-002 | 895 | FR-1.5 operator-override schema + precedence + audit | ✓ Integrated |
| IMP-003 | 930 | §3.4 baseline measurement methodology | ✓ Integrated |
| IMP-004 | 805 | FR-2 consumer inventory + dependency ordering table | ✓ Integrated |
| IMP-005 | 735 | FR-1.5 parsing policy for malformed KF entries | ✓ Integrated |
| IMP-007 | 820 | FR-1.6 ceiling calibration + staleness detection | ✓ Integrated |
| IMP-008 | 760 | FR-1.2 conservative defaults policy | ✓ Integrated |
| IMP-009 | 705 | FR-3.5 matrix dimensions (chunked path as explicit dimension) | ✓ Integrated |
| IMP-014 | ~745 | FR-4.4 streaming-recovery thresholds (per-model) | ✓ Integrated |

**Findings deferred to SDD or sprint-plan absorption:**

| ID | Avg Score | Rationale for deferral |
|----|-----------|------------------------|
| IMP-006 | 690 | Conflict resolution: integrated lightly in FR-4.3; SDD will expand into algorithm spec |
| IMP-010 | 650 | Single-voice telemetry semantics: light-touch in FR-2.9; SDD finalizes |
| IMP-011 | 625 | Explicit consumer list: superseded by IMP-004 integration (FR-2 table) |
| IMP-012 | 575 | Success metric definition: largely absorbed by §3.4 IMP-003 integration |
| IMP-013 | 505 | JSONL backward compat: NFR-Rel-4 (v1.2→v1.3 additive only) already enforces this; SDD adds explicit compat test |

**Process note**: The Flatline review's HIGH_CONSENSUS finding (IMP-001) was about the same gap the operator delegated to autonomous mode via C109.OP-2 (KF-ledger auto-linking deeper variant). The substrate independently identified what the operator had already authorized. Convergence between independent operator judgment and adversarial multi-model review is a positive signal even when one of the voices in that review effectively dropped.

---

*Generated by `/plan-and-analyze` (discovering-requirements skill) for
cycle-109-substrate-hardening, 2026-05-13. Source-cited against fresh
`/ride` reality file + known-failures ledger + 13 verified OPEN GitHub
issues + operator instructions. Awaiting Flatline PRD review before
`/architect`.*
