# Cycle-108 PRD — Advisor-Strategy Benchmark + Role→Tier Routing

> **Version**: 1.1 (post-Flatline integration)
> **Status**: draft (awaiting /architect — Flatline PRD gate passed with voice-drop)
> **Cycle**: cycle-108-advisor-strategy
> **Created**: 2026-05-13 (v1.0); revised 2026-05-13 (v1.1)
> **Author**: Claude (cycle-108 kickoff, full Loa pipeline autonomous)
> **Predecessor**: cycle-107 multi-model activation (PR #862 merged at e1032b76, v1.157.0)
> **Operator**: @janitooor
> **Source**: operator-asked the budgetary question — "can we use the best models for planning/reviews and cheaper models for implementation? quality and getting work done are paramount, but part of quality is sustainable funding/runway"
> **Reference**: [Anthropic's Advisor Strategy blog](https://claude.com/blog/the-advisor-strategy)

---

## 0. Read-FIRST operational ledger

Per `grimoires/loa/known-failures.md` (read at session start per CLAUDE.md context-intake discipline):

| KF | Status | Relevance to cycle-108 |
|----|--------|------------------------|
| KF-001 | RESOLVED 2026-05-10 (Node 20 Happy Eyeballs) | BB cross-model dissent is the load-bearing review gate — operationally healthy entering this cycle |
| KF-002 | LAYERS-2-3-RESOLVED-STRUCTURAL 2026-05-12 | adversarial-review.sh substrate stable; layer-1 latent (manual misconfig) still possible — **observed once during cycle-108 PRD Flatline pass** (Opus voice empty-content; gpt+gemini consensus held — non-blocking) |
| KF-005 | RESOLVED-VIA-WORKAROUND cycle-105 | beads tracking healthy; sprint task lifecycle viable |
| KF-008 | RESOLVED-architectural-complete cycle-104 | BB Google provider stable on large bodies via cheval httpx |

No active failure class blocks cycle-108. Substrate is in the best operational shape it has been all year.

---

## 1. Problem statement

**The runway problem.** Loa's quality gates (multi-model Flatline, Bridgebuilder, Red Team, /review-sprint, /audit-sprint) consume top-tier model tokens (Opus 4.7, GPT-5.5-pro, Gemini 3.1-pro). These gates are load-bearing — they catch the bugs that single-agent review misses. But the **bulk** of token spend in a typical cycle is the **implementation phase** (`/implement`, `/bug` fix phase), where a top-tier model writes code, runs tests, iterates on failures.

> Operator framing: "i am concerned about not realising some of our grand visions due to budgetary concerns wrt token costs … part of quality control is ensuring people are able to build E2E without running out of tokens/money/runway/funds"

**The advisor-strategy hypothesis.** Implementation quality may hold at lower-tier models **when**:

1. The plan + acceptance criteria are produced by a top-tier model (Advisor produces the spec)
2. Code review + audit are performed by top-tier models (Advisor verifies the work)
3. The executor follows a tight specification with verifiable acceptance criteria

Anthropic's "advisor strategy" pattern: strong model for high-leverage thinking, cheaper model for high-volume work, with the strong model verifying outputs. Loa's existing skill taxonomy already maps cleanly to this split — what's missing is the **measurement** to prove the hypothesis holds (or doesn't, or holds conditionally) for our specific workload.

**The dogfooding opportunity.** Cycle-107 just shipped multi-model routing activation. The substrate (cheval.py + fallback chains + MODELINV v1.1 + voice-drop) is at its strongest. We can run a scientifically-defensible benchmark using the very infrastructure the cycle is meant to economize.

**The risk if we don't measure.** Two failure modes if we ad-hoc adopt cheaper executors:
- **False economy**: cheaper executor produces subtly worse code; review/audit findings compound across sprints; total tokens (review + rework) end up higher
- **Quality tail risk**: executor degrades non-uniformly — averages mask catastrophic failures on cryptographic / parser / audit-envelope sprint kinds

Without stratified benchmark data, every adoption decision is a gut call. With it, we can route by sprint-kind with explicit guardrails.

> **Sources**: operator framing (this session, 2026-05-13); `feedback_advisor_benchmark.md` (auto-memory — Sonnet ≈ Opus on spiral-harness simple tasks); cycle-107 release commits e1032b76, ea12e236; [Advisor Strategy blog](https://claude.com/blog/the-advisor-strategy)

---

## 2. Vision

> Loa cycles become **2–5x cheaper** to run end-to-end **without measurable quality regression** on routine sprint kinds, **with explicit guardrails** on tail-risk sprint kinds. Operators can choose their tier explicitly per cycle, per skill, or per sprint — defaults are conservative; aggressive cost-savings is opt-in.

Loa already has the substrate. This cycle gives it the **data**, the **routing**, and the **policy**.

---

## 3. Goals & success metrics

### Primary goals

| ID | Goal | Measurable outcome |
|----|------|-------------------|
| G-1 | Validate or refute the advisor-strategy hypothesis empirically for Loa-style sprints | Benchmark report stratified by sprint kind, ≥3 sprints per stratum, with confidence intervals |
| G-2 | Ship operator-controlled role→tier routing | `.loa.config.yaml` schema + cheval routing extension; single config flip rolls back to advisor-everywhere |
| G-3 | Make MODELINV cost data actionable | Per-sprint, per-tier, per-role, per-stratum cost rollup tool — runs against `.run/model-invoke.jsonl` |
| G-4 | Catalogue failure modes by sprint kind | Documented matrix: which sprint kinds DO degrade at executor tier, what the early-warning signal is |

### Success criteria (quantitative — PRE-REGISTERED, see FR-Baseline)

| ID | Metric | Target | Stretch |
|----|--------|--------|---------|
| SC-1 | Audit-sprint pass rate at executor tier vs advisor-tier baseline | ≥95% relative pass rate | ≥98% |
| SC-2 | Review-sprint findings density delta (executor vs advisor) | ≤ +20% relative findings density | ≤ +10% |
| SC-3 | BB iteration count to plateau, executor vs advisor | ≤ +1 iteration on average | parity |
| SC-4 | Cost per sprint reduction (advisor still runs review/audit) | ≥40% reduction | ≥60% |
| SC-5 | Wall-clock per sprint | ≤ +30% slower | parity |
| SC-6 | Stratification coverage | ≥4 sprint kinds × ≥3 replays each = ≥12 benchmark runs | ≥6 kinds × ≥5 replays |

**[Flatline IMP-001 integration]** Targets above are PRE-REGISTERED in Sprint 2 before any executor replays are run. `tools/advisor-benchmark.sh` MUST refuse to run replays until the baseline-thresholds file is committed and signed by a recorded git SHA. This closes the retrospective-threshold-fitting attack class.

### Pass/Fail/Inconclusive decision rules

**[Flatline IMP-002 integration]** Each sprint kind's executor-tier outcome is classified per the following statistical methodology:

| Outcome | Rule |
|---------|------|
| **PASS** | ≥3 replays AND all SC-1..SC-3 within target AND 95% CI upper bound for SC-1 ≥ target |
| **FAIL** | ≥3 replays AND any SC-1..SC-3 below "DO NOT USE" threshold (SC-1 <85%, SC-2 >+40%, SC-3 >+3 iterations) AND 95% CI excludes target |
| **INCONCLUSIVE** | Fewer than 3 replays OR CI overlaps target boundary OR ≥2σ variance flagged by harness |
| **OPT-IN-ONLY** | ≥3 replays AND meets target on SC-1 but misses on SC-2 or SC-3 (good enough with operator awareness) |

CIs computed via paired bootstrap (n=10000 resamples) over per-sprint score deltas. Methodology lives in SDD §X (TBD); referenced here so the rollout decision is mechanical, not discretionary.

### Non-goals (explicit)

- **NOT** building auto-routing that picks tier per-sprint (operator decides; we surface data + recommendations)
- **NOT** replacing Opus everywhere even if benchmark is positive (advisor tier remains default for planning/review)
- **NOT** benchmarking Haiku 4.5 as planner (out-of-scope; planning quality at sub-Sonnet is a separate study)
- **NOT** modifying Bridgebuilder or Red Team tier (always advisor — these ARE the verification layer)
- **NOT** modifying Flatline's PRD/SDD/Sprint-Plan review tier (these are the highest-leverage gates)

> **Sources**: operator framing this session; `feedback_advisor_benchmark.md`; Flatline IMP-001 + IMP-002 (cycle-108 PRD pass)

---

## 4. Users & stakeholders

### Primary persona: Loa operator (e.g., @janitooor)

- **Job to be done**: ship cycles end-to-end without burning runway
- **Pain point today**: every cycle defaults to top-tier across all skills; no visibility into where the cost goes; no policy to dial cost vs quality
- **What they need**: data they trust + a config knob they understand + a rollback they're confident in

### Secondary persona: framework contributor

- **Job to be done**: extend Loa skills without each new skill burning advisor tokens for tasks a Sonnet could do
- **Pain point today**: no convention for declaring "this skill is implementation-tier"; defaults inherited from CLAUDE.md run everything Opus-default
- **What they need**: a stable role→tier contract they can target when authoring new skills

### Tertiary persona: future agent in an autonomous swarm

- **Job to be done**: run a long task under a token budget without operator intervention
- **Pain point today**: budget exhaustion mid-run is a hard halt
- **What they need**: a tier-routing config that survives session resume + makes its policy legible in `.run/model-invoke.jsonl`

> **Sources**: operator framing + auto-memory `feedback_operator_collaboration_pattern.md` (how @janitooor collaborates) + `feedback_autonomous_run_mode.md` (autonomous swarm context)

---

## 5. Functional requirements

### FR-1: Role→tier configuration schema

The `.loa.config.yaml` MUST gain a section that declares which skill (or skill-role) runs at which tier:

```yaml
advisor_strategy:
  enabled: true                          # master switch; default false (opt-in)
  tier_resolution: static                # static | dynamic — see FR-9 (IMP-009 resolution)
  defaults:
    planning: advisor                    # /plan-and-analyze, /architect, /sprint-plan
    review: advisor                      # /review-sprint, /audit-sprint, Flatline, BB, RT
    implementation: executor             # /implement, /bug implementation phase
  tier_aliases:
    advisor:
      anthropic: claude-opus-4-7
      openai: gpt-5.5-pro
      google: gemini-3.1-pro-preview
    executor:
      anthropic: claude-sonnet-4-6
      openai: gpt-5.3-codex
      google: gemini-3.1-flash         # [ASSUMPTION-A1] — SDD validates Gemini executor candidate
  per_skill_overrides:                   # operator can pin any skill to any tier
    implement: executor
    bug: executor
    review-sprint: advisor               # explicit even though default
```

**Acceptance**:
- Schema validated by JSON Schema at config load time
- Unknown skills in `per_skill_overrides` → fail-closed with explicit error (not silent)
- `advisor_strategy.enabled: false` → all consumers behave identically to today (advisor-everywhere)
- Schema-version field + migration path documented
- **[Flatline IMP-003]** **NFR-Sec1 enforcement at config-loader layer**: schema MUST reject any `per_skill_overrides` entry that sets a `review` or `audit` skill to a non-advisor tier. Loader emits exit code 78 (EX_CONFIG) on rejection. Backed by unit test `tests/unit/advisor-strategy-loader.bats` that asserts rejection on a poisoned config fixture.

### FR-2: cheval routing extension

`cheval.py` MUST accept a `role` parameter (planning / review / implementation) and resolve the tier from the config:

- If `advisor_strategy.enabled: false` → ignore role param entirely; route as today
- If `enabled: true` → resolve `role → tier → model-id` via config, with fallback-chain semantics preserved within the resolved tier
- Audit log MUST record `role`, `tier`, `tier_source` (default vs override) in MODELINV v1.1 envelope (additive — backward-compatible)

**Acceptance**:
- Round-trip test: same role + same config produces same model selection across bash + python + ts entry points
- MODELINV envelope schema bumped or extended with three new optional fields
- Existing callers without `role` param keep working unchanged

### FR-3: Skill annotation contract

Every skill MUST declare its **default role** in SKILL.md frontmatter:

```yaml
---
name: implement
role: implementation       # NEW field — one of: planning | review | implementation
primary_role: implementation  # NEW (multi-role only) — explicit tiebreaker
...
---
```

**Acceptance**:
- Validator `.claude/scripts/validate-skill-capabilities.sh` extended to require `role` field
- Migration script populates `role` for all 53+ existing skills based on category mapping
- Skills without `role` → CI fails (fail-closed)
- **[Flatline IMP-012]** **Multi-role tiebreaker rules**: when a skill declares more than one role (e.g., `/run-bridge` is both planning + review), it MUST declare `primary_role`. Resolution rule when `primary_role` absent: **advisor wins ties** (most-restrictive). Migration script flags multi-role skills for manual review.

### FR-4: Benchmark harness

A new tool `tools/advisor-benchmark.sh` MUST:

1. Accept a list of historical sprints (PR numbers or sprint-IDs) as input
2. For each sprint, replay `/implement` twice:
   - **Baseline**: advisor tier (today's behavior)
   - **Treatment**: executor tier (with role→tier config)
3. Capture per-replay: token cost (from MODELINV), wall-clock, audit-sprint outcome, review-sprint finding count, BB iter count to plateau
4. Stratify results by sprint kind (taxonomy in Appendix A; SDD finalizes)
5. Emit a scored comparison report at `grimoires/loa/cycles/cycle-108-advisor-strategy/benchmark-report.md`

**[Flatline IMP-005] Replay-semantics definition** (load-bearing — affects interpretation):

| Replay type | Definition | When used |
|-------------|------------|-----------|
| **fresh-run** | Re-execute the sprint from `git checkout pre-sprint-SHA` in an isolated worktree; LLM generates everything from prompts | Cycle-108 benchmark — measures actual implementation quality at executor tier |
| **recorded-replay** | Cached prompts + cached responses; deterministic; verifies harness plumbing only | Smoke testing the harness; NOT a quality signal |

The Sprint-3 benchmark MUST use **fresh-run** replays. The report MUST state replay type next to every metric. Recorded-replay results MUST NOT appear in the headline scorecard.

**[Flatline IMP-004] Variance-handling protocol**:

- ≥3 fresh-run replays per (sprint, tier) pair (minimum N for paired comparison)
- Paired-bootstrap (Sprint × replay-index pairing) over per-replay deltas
- Variance flag: if any (sprint, tier) pair shows >2σ across its 3 replays, that pair is **flagged for re-run** with 2 additional replays; if variance persists, that sprint is **dropped** from stratum aggregate (recorded separately as "harness-defect candidate")
- Temperature pinning is necessary but not sufficient: temperature, top_p, system prompt SHA, and tool definitions all pinned per the replay manifest

**[Flatline IMP-013] Chain-exhaustion classification**:

| Event | Classification | Effect on benchmark report |
|-------|----------------|---------------------------|
| All models in chain returned content | OK | Counted in stratum aggregate |
| Primary failed, fallback succeeded | OK-with-fallback | Counted; flagged in detail report |
| Chain exhausted (all failed) | **INCONCLUSIVE** | NOT counted as pass or fail; reported under "inconclusive runs" |
| Operator manually aborted | EXCLUDED | Not counted at all |

**Acceptance**:
- Replay is **hermetic**: runs in a worktree, doesn't touch main, doesn't commit
- Replay uses the **same PRD/SDD/sprint-plan** as the original — only the executor tier varies (controls all other inputs)
- Report has explicit confidence intervals (≥3 replays per stratum × ≥4 strata)
- Report fails-closed if any replay produces non-determinism > 2σ — flagging benchmark-harness defect
- **[Flatline IMP-011] Pre-run cost cap**: harness MUST emit a cost estimate before any replays start (sum of `expected_cost_usd` over all planned replays, derived from per-model `pricing` in `model-config.yaml` × historical median tokens per sprint kind). MUST abort if estimate exceeds `advisor_strategy.benchmark.max_cost_usd` (default $50). Operator can override per-run via `--cost-cap-usd N`. Estimate vs actual reported in benchmark-report.md.

### FR-5: MODELINV cost aggregator

A new tool `tools/modelinv-rollup.sh` MUST roll up `.run/model-invoke.jsonl` by:
- Per cycle (group by `payload.cycle_id` or git-branch heuristic)
- Per skill (group by `payload.skill_name`)
- Per role (group by `payload.role`)
- Per tier (group by `payload.tier`)
- Per model_id (group by `payload.final_model_id`)
- **[Flatline IMP-014]** **Per stratum** (group by `payload.sprint_kind` — populated by FR-4 stratifier)

**Acceptance**:
- Reads `.run/model-invoke.jsonl` (READ-ONLY — does not mutate audit log)
- Emits JSON + Markdown
- Validated against MODELINV hash-chain integrity before reporting
- **[Flatline IMP-008] Hash-chain failure behavior**: if integrity check fails, tool MUST exit non-zero with explicit error identifying the failing record's `primitive_id` + line offset. MUST NOT emit a "partial" report — fail-closed prevents misleading cost claims. Recovery via `audit_recover_chain` (per CLAUDE.md L1 envelope rules) is the documented next step.
- Report includes per-stratum cost reduction (not just aggregate) — closes IMP-014.

### FR-6: Rollout policy doc

A new doc `grimoires/loa/cycles/cycle-108-advisor-strategy/rollout-policy.md` MUST capture:

- Thresholds for when an executor tier is "safe to default" (meets SC-1..SC-3 on ≥3 sprints in a stratum)
- Thresholds for when an executor tier is "operator opt-in only" (meets ≥2 of SC-1..SC-3)
- Thresholds for when an executor tier is "DO NOT USE" (fails ≥1 of SC-1..SC-3)
- Per-sprint-kind recommended defaults derived from benchmark results
- A "what to do on regression" section: if production cycle X under executor tier produces audit failures, how does the operator triage?
- **Net-negative branch**: explicit decision-flow for what happens if benchmark shows executor tier is worse across all strata — see §7 Sprint 4 explicit decision-fork.

### FR-7: Rollback semantics

A **single config flip** (`advisor_strategy.enabled: false`) MUST restore advisor-everywhere behavior, honored by ALL consumers:

- /implement, /bug implementation phase
- /review-sprint, /audit-sprint
- /plan-and-analyze, /architect, /sprint-plan
- Flatline (`flatline-orchestrator.sh`)
- Bridgebuilder (`adversarial-review.sh` / `entry.sh`)
- Red Team

**Acceptance**:
- **[Flatline IMP-010] Trace-comparison integration test**: integration test runs a full mini-cycle (PRD → SDD → 1 sprint → review → audit → BB) under `enabled: false` and asserts MODELINV envelopes show advisor model IDs at ALL six consumers. Trace comparison vs golden file; deviation fails CI.
- Kill-switch env var `LOA_ADVISOR_STRATEGY_DISABLE=1` available for emergency override
- **[Flatline IMP-007] In-flight kill-switch semantics**: flipping `enabled: false` (or setting `LOA_ADVISOR_STRATEGY_DISABLE=1`) during an in-flight sprint behaves as follows:
  - Currently-running cheval invocation completes at its current tier (no mid-call swap — would invalidate the call's audit envelope)
  - Subsequent cheval invocations within the same sprint read the new config (re-evaluated per invocation, not cached per sprint)
  - `.run/sprint-plan-state.json` records the tier transition in a `tier_transitions` array with timestamps
  - Operator-visible warning emitted on the first invocation after the flip
  - Behavior is **eventually consistent**, not transactional — operator MUST understand the boundary if they flip mid-sprint

### FR-8: Pre-registered baselines (NEW — IMP-001)

**[Flatline IMP-001 dedicated FR]** Before any executor-tier replays in Sprint 3, a baseline-thresholds file MUST be committed:

`grimoires/loa/cycles/cycle-108-advisor-strategy/baselines.json`

Contents:
- Per-stratum **advisor-tier baseline** for SC-1..SC-5 (computed from existing audit-sprint + review-sprint history; the LAST 12 sprints across the 4 strata — historical record, not freshly computed)
- Per-stratum **executor-tier targets** for SC-1..SC-5 derived from §3 SC table × baseline (e.g., target audit-pass = 0.95 × baseline-audit-pass)
- Git SHA + timestamp + signed by `audit_emit_signed` (L1 envelope)

**Acceptance**:
- `tools/advisor-benchmark.sh` REFUSES to run replays if baselines.json is missing or modified-since-signing (hash mismatch)
- Baseline data is read-only post-signing; any update requires a new signed file + rationale in commit message
- This is the IMP-001 closure — retrospective threshold-fitting is mechanically prevented

### FR-9: Tier alias resolution policy (NEW — IMP-009 / OQ-1 closure)

**[Flatline IMP-009 / OQ-1 resolution]** `advisor_strategy.tier_resolution` controls whether tier aliases are pinned-at-cycle-start or moving-targets:

| Mode | Semantics | When to use |
|------|-----------|-------------|
| `static` (DEFAULT) | Tier alias resolves to the model ID **as of `.loa.config.yaml` commit time**. Resolution is reproducible from git-SHA alone. Cycle-108 benchmark MUST use static. | Cycle benchmarks; production runs with measured baselines |
| `dynamic` | Tier alias re-resolves on every invocation. If `advisor:anthropic` is later updated to `claude-opus-5-0`, all invocations pick that up automatically. Trades reproducibility for ergonomics. | Long-running production after a tier is validated; quick experiments |

**Acceptance**:
- Resolution mode logged in MODELINV envelope under `payload.tier_resolution`
- Switching `static` → `dynamic` mid-cycle emits an operator-visible warning + audit log entry (informs cross-replay variance interpretation)
- Benchmark replays MUST be in `static` mode — closed by FR-4 acceptance criteria check

---

## 6. Non-functional requirements

### NFR-Security

- **NFR-Sec1 (config tamper)** — strengthened per IMP-003: an attacker who plants a malicious `.loa.config.yaml` (via PR / poisoned branch) MUST NOT be able to downgrade the review/audit tier silently. Review/audit tier is schema-pinned to advisor; any attempt to override review/audit to executor MUST fail at the **config-loader layer** (exit 78 EX_CONFIG, not silent fallback). Verified by unit test fixture + Red Team gate.
- **NFR-Sec2 (audit-log integrity)**: MODELINV envelope new fields (`role`, `tier`, `tier_source`, `tier_resolution`, `sprint_kind`) MUST be hash-chained per L1 envelope spec. Backward-compat: existing entries without these fields remain valid; new entries with them are validated against new schema.
- **NFR-Sec3 (kill-switch)**: `LOA_ADVISOR_STRATEGY_DISABLE=1` MUST take precedence over config. Honored by all six consumers.

### NFR-Reliability

- **NFR-R1**: benchmark harness MUST be re-runnable; replays MUST NOT leak state into main; failures of one replay MUST NOT corrupt other replays
- **NFR-R2**: cheval role-routing MUST preserve all existing fallback-chain + voice-drop + within-company-chain-walk behavior — additive, not replacement
- **NFR-R3**: if executor tier's primary + fallback chain ALL fail, behavior is the same as today (chain-exhaustion → operator-visible error; no silent advisor-substitution unless config explicitly permits it)

### NFR-Observability

- **NFR-O1**: every MODELINV envelope post-cycle-108 MUST include `role` field even if `advisor_strategy.enabled: false` (records intent, even when policy is uniform)
- **NFR-O2**: benchmark report MUST be reproducible from `.run/model-invoke.jsonl` + git-SHAs alone (no other state)

### NFR-Performance

- **NFR-P1**: config load + role resolution adds ≤5ms to any cheval invocation (lookup is O(1) once parsed)
- **NFR-P2**: benchmark harness completes ≥12 replays in ≤6 wall-clock hours (≤30 min per replay on average)
- **NFR-P3 (NEW — IMP-011)**: benchmark harness MUST emit cost estimate before replays start; MUST abort if estimate > operator-configured cap (default $50; per-run override `--cost-cap-usd N`). Estimate-vs-actual reported in benchmark-report.md.

### NFR-Compliance

- **NFR-C1**: every Loa quality gate (PRD/SDD/sprint Flatline; SDD Red Team; post-PR BB) MUST run on cycle-108 itself. Cycle-108 dogfoods the safety net it depends on. **[Confirmed in flight]** — this Flatline PRD pass IS that compliance check; SDD Flatline + Red Team + sprint-plan Flatline follow.
- **NFR-C2**: NEVER bypass quality gates "to save time on the benchmark" — the benchmark is meaningful BECAUSE the safety net is intact

---

## 7. Scope & prioritization

### Sprint 1 — Routing substrate (MUST)

- FR-1 (config schema + IMP-003 loader-layer enforcement) — definition + JSON Schema + loader + unit test
- FR-2 (cheval role param) — additive routing extension
- FR-3 (skill annotation + IMP-012 multi-role tiebreaker) — `role` + `primary_role` frontmatter + validator + migration
- FR-7 (rollback + IMP-007 in-flight semantics + IMP-010 trace-comparison test) — kill-switch + full-cycle trace test
- FR-9 (tier alias resolution mode — IMP-009)

Out: benchmark harness, cost aggregator, rollout policy.

### Sprint 2 — Measurement substrate (MUST)

- FR-4 (benchmark harness) — `tools/advisor-benchmark.sh` with IMP-004 (variance protocol), IMP-005 (replay-semantics), IMP-011 (cost cap), IMP-013 (chain-exhaustion classification)
- FR-5 (cost aggregator + IMP-008 hash-chain abort + IMP-014 per-stratum) — `tools/modelinv-rollup.sh`
- FR-8 (baselines.json + IMP-001 sign-and-refuse-on-tamper)
- Sprint-kind taxonomy finalized in SDD (stub in Appendix A)

Out: actual benchmark runs (Sprint 3).

### Sprint 3 — Empirical benchmark (MUST)

- Sign + commit `baselines.json` from historical sprint data (FR-8)
- Select ≥12 historical sprints across ≥4 sprint kinds (taxonomy from Sprint 2)
- Run benchmark replays (≥3 per stratum × ≥4 strata) — fresh-run only
- Produce `benchmark-report.md` with stratified scoring + 95% bootstrap CIs + pass/fail/inconclusive classification per stratum
- Identify which sprint kinds passed SC-1..SC-5 at executor tier; which failed; which are inconclusive

### Sprint 4 — Rollout policy + explicit decision-fork (MUST)

- FR-6 (rollout policy doc) — derived from Sprint 3 data
- Update `.loa.config.yaml.example` with documented defaults
- Migration guide for operators
- **Decision fork** — exactly one path taken based on Sprint 3 data:
  - **(a) Default-on-for-passing-strata**: Sprint 3 produced ≥1 PASS stratum AND zero FAIL strata. Ship `advisor_strategy.enabled: true` as default with per-stratum opt-out for any non-PASS strata. Document the strata recommendations.
  - **(b) Opt-in only**: Sprint 3 produced mixed outcomes (some PASS, some FAIL/INCONCLUSIVE). Ship with `enabled: false` default; rollout-policy doc captures per-stratum guidance for operators who turn it on.
  - **(c) Shelve**: Sprint 3 produced ALL FAIL or majority INCONCLUSIVE. Decision: ship FR-1..FR-9 substrate (no harm — it's behind a default-off flag) + benchmark report + rollout-policy doc that records "DO NOT ADOPT" with full data trail. Cycle still considered successful — we ran the measurement; the answer was "no". Re-evaluate in 6 months as model capabilities evolve.

The fork MUST be made mechanically from baselines.json + benchmark-report.md, not discretionarily. The rollout-policy doc MUST cite the data points driving the decision.

### Out of scope (explicit)

- **OOS-1**: auto-selection of tier per-sprint by an inference model (future work; cycle-108 is operator-decision-support)
- **OOS-2**: Haiku-tier executor experiments (Sonnet is the first executor candidate; Haiku is a separate study)
- **OOS-3**: advisor-tier reduction (we don't lower Opus to Sonnet for review/audit in this cycle)
- **OOS-4**: cross-provider tier mixing (e.g., Opus advisor + GPT-5.3 executor on same sprint) — within-provider tier-pairs only in cycle-108

---

## 8. Risks & dependencies

| ID | Risk | Likelihood | Impact | Mitigation |
|----|------|------------|--------|------------|
| R-1 | Executor tier degrades on a sprint kind we didn't stratify | Medium | High | Stratification taxonomy in Appendix A + SDD; "DO NOT USE" recommendations per kind; opt-in default |
| R-2 | Benchmark replays are not actually hermetic — pollute main | Low | High | Worktree isolation; CI verification that replays don't touch tracked refs |
| R-3 | Cost data from MODELINV is incomplete (some skills don't emit envelope) | Medium | Medium | Audit MODELINV coverage in Sprint 2 before running benchmark; flag gaps |
| R-4 | Non-determinism between replays inflates apparent quality variance | High | Medium | FR-4 variance protocol (IMP-004): ≥3 replays + paired-bootstrap + >2σ re-run-then-drop; pin temperature + top_p + system-prompt SHA + tool defs |
| R-5 | Operator declines to adopt even with positive benchmark — political risk | Low | Low | This is operator's call; cycle delivers data, not mandate |
| R-6 | Cheaper model fails mid-implementation; chain-exhaustion under load triggers KF-002 again | Medium | Medium | KF-002 layer-2-3 RESOLVED; chain-walk handles transient errors; IMP-013 classifies chain-exhaustion as INCONCLUSIVE not FAIL |
| R-7 | Schema-version drift across consumers (cheval, hooks, skills) | Medium | Medium | Single source of truth: `.loa.config.yaml` schema versioned; consumers read via shared loader |
| R-8 | NFR-Sec1 bypassed: PR plants `per_skill_overrides.audit-sprint: executor` to silently weaken audit | Medium | Critical | IMP-003: loader-layer hard failure (exit 78); unit test fixture; CODEOWNERS protection on schema file; Red Team validates |
| R-9 (NEW — IMP-011) | Benchmark itself burns 5x runway on top of normal cycle costs, undermining the very runway-savings goal | Medium | High | NFR-P3: pre-run cost estimate + $50 cap default; estimate-vs-actual reported |
| R-10 (NEW) | Opus voice degradation (as observed in this PRD's Flatline pass) recurs on SDD or sprint-plan Flatline | High | Medium | Voice-drop semantics handle it; track recurrence in known-failures.md; treat 2-voice consensus as sufficient when third voice degrades |
| R-11 (NEW — IMP-005) | Recorded-replay results leak into headline scorecard, misleading the rollout decision | Low | Critical | FR-4 acceptance: Sprint-3 MUST use fresh-run; report MUST state replay-type next to every metric |

### Dependencies (upstream)

- cheval.py + within-company fallback chain (cycle-104 — DONE)
- MODELINV v1.1 envelope (cycle-104 T2.6 — DONE)
- voice-drop semantics (cycle-104 — DONE) — operationally proven in this PRD's Flatline pass
- `flatline_routing: true` default (cycle-107 — DONE, foundation for this cycle)
- model-resolver.sh alias resolution (cycle-099 — DONE)

### Dependencies (downstream — what this enables)

- Future autonomous swarms with budget caps (vision-XXX TBD)
- Operator dashboards on token spend (out-of-scope this cycle)
- Per-cycle budget enforcement primitive L2 (already exists as L2 in agent-network; cycle-108 makes it actionable)

---

## 9. Open questions & assumptions

### Resolved during Flatline pass

- **OQ-1 → RESOLVED via FR-9**: advisor tier is **pinned (static) at cycle-start by default**; `dynamic` mode is operator opt-in with audit-logged warning on transition.

### [ASSUMPTION] tags — falsifiable before SDD lock

- **[ASSUMPTION-A1]**: Gemini executor candidate is `gemini-3.1-flash` (or whatever Google's mid-tier is). **If wrong**: SDD picks the right Gemini mid-tier; benchmark stratifies Anthropic + OpenAI even if Google executor is excluded
- **[ASSUMPTION-A2]**: Historical sprints suitable for replay exist (≥12 across ≥4 kinds). **If wrong**: Sprint 3 may need to commission synthetic benchmark sprints — adds time
- **[ASSUMPTION-A3]**: Sprint replay can be hermetic via git worktree + reset-to-pre-sprint-SHA. **If wrong**: replay may need a containerized sandbox — adds complexity
- **[ASSUMPTION-A4]**: MODELINV envelope coverage is >90% of cycle token spend. **If wrong**: Sprint 2 ships a coverage-improvement task first
- **[ASSUMPTION-A5]**: Executor-tier failures are observable via existing audit-sprint + review-sprint signals. **If wrong**: SDD adds a new defect-detection signal (e.g., test-pass-rate, lint-pass-rate)

### Remaining open questions (Red Team + SDD-Flatline to surface more)

- **OQ-2**: How do we handle cycles that mix `/implement` and `/bug` — same tier or differential?
- **OQ-3**: What's the right granularity for `role` — skill-level (`implement`) or phase-level (`implement.write_code` vs `implement.run_tests`)?
- **OQ-4**: Should benchmark-report.md become a living document that re-runs on every cycle-N+1 to catch tier-quality drift?

---

## 10. Acceptance criteria (cycle-level)

This cycle is **complete** when:

- [ ] All 4 sprints shipped with /implement → /review-sprint → /audit-sprint clean
- [ ] FR-1..FR-9 all delivered + tested
- [ ] NFR-Sec1 (review/audit tier pinning at loader layer) verified by Red Team review + unit test fixture
- [ ] Baselines.json signed + committed before Sprint 3 replays (FR-8 closure)
- [ ] Benchmark report (≥12 replays, ≥4 strata, 95% bootstrap CIs) committed
- [ ] Rollout policy doc committed with explicit decision-fork outcome (a/b/c per §7 Sprint 4)
- [ ] Operator (@janitooor) has reviewed benchmark report + rollout policy
- [ ] Decision recorded: ship as opt-in / default-for-strata / shelve
- [ ] `feedback_advisor_benchmark.md` auto-memory updated with new datapoints (replaces or supplements current spiral-harness-only data)
- [ ] Post-PR Bridgebuilder loop closed (no CRITICAL/HIGH findings)
- [ ] Flatline ran on PRD ✓ (this pass), SDD, sprint-plan
- [ ] Red Team ran on SDD
- [ ] `/run-bridge` excellence loop ran post-merge (≥1 iteration, plateau or kaironic termination)

---

## 11. Sources

| Section | Source |
|---------|--------|
| Problem framing | operator (this session, 2026-05-13); [Advisor Strategy blog](https://claude.com/blog/the-advisor-strategy) |
| Prior datapoint | `feedback_advisor_benchmark.md` (auto-memory — Sonnet ≈ Opus, spiral-harness simple tasks, ~5x cheaper) |
| Substrate references | `.claude/scripts/lib/cheval.py`; `.claude/scripts/lib/model-resolver.sh`; `.claude/defaults/model-config.yaml`; `.run/model-invoke.jsonl` (233 envelopes as of cycle start) |
| Cycle-107 launching pad | recent commits ea12e236, e1032b76, d1e5afd4 — multi-model activation merged |
| Known-failures relevance | `grimoires/loa/known-failures.md` (KF-001, KF-002, KF-005, KF-008) |
| Reality grounding | `grimoires/loa/reality/` (Loa v1.110.1 snapshot 2026-05-04; 9 days stale but substrate-stable) |
| Operator preferences | `feedback_autonomous_run_mode.md`, `feedback_operator_collaboration_pattern.md`, `feedback_loa_monkeypatch_always_upstream.md` |
| Pricing baseline | `.claude/defaults/model-config.yaml` (gpt-5.3-codex $1.75/$14 vs gpt-5.2 $10/$30 = ~5.7x input / 2.1x output cheaper) |
| v1.1 amendments | Flatline pass `grimoires/loa/a2a/flatline/prd-review.json` (IMP-001..IMP-014; gpt-5.5-pro + gemini-3.1-pro consensus; opus voice degraded — non-blocking via voice-drop) |

---

## Appendix A: Sprint-kind taxonomy (stub — IMP-006)

**[Flatline IMP-006 integration]** SDD will finalize. Initial candidate strata for stratification (≥4 required by SC-6):

| Stratum | Description | Examples from Loa history |
|---------|-------------|---------------------------|
| **glue / wiring** | Connect existing components; thin adapters; configuration plumbing | cycle-099 sprint-2A schema wiring; cycle-103 provider unification helpers |
| **parser / serialization** | Input parsing, format conversion, canonicalization | cycle-098 JCS canonicalization; cycle-099 endpoint-validator URL canonicalization |
| **cryptographic / audit-envelope** | Hash chains, signatures, schema-validated envelopes, trust ledgers | cycle-098 L1 audit envelope; L4 trust ledger; L7 SOUL frontmatter |
| **testing / harness** | Test infrastructure, fixtures, golden files, smoke tests | cycle-099 cross-runtime parity tests; cycle-098 trust ledger contract tests |
| **infrastructure / orchestration** | Cron, scheduling, dispatch contracts, retry/timeout logic | cycle-098 L3 scheduled-cycle-template; flatline-orchestrator |
| **frontend / TUI** | Terminal UI, Bubbletea, Lipgloss, layout work | n/a in Loa core; reserved for future cycles |

Sprint 3 selects ≥3 historical sprints per stratum to cover ≥4 of these. The SDD's responsibility: define **stratum-assignment rules** (how a new sprint is classified) and **feature-extraction heuristics** (so classification is mechanical, not discretionary).

---

## Appendix B: Flatline v1 → v1.1 changelog

| Finding | Score (gpt/gemini) | Integration |
|---------|---------------------|-------------|
| IMP-001 (baseline pre-registration) | 920/900 | FR-8 added; SC table now notes pre-registration; `tools/advisor-benchmark.sh` refuses replays without signed baselines.json |
| IMP-002 (CI + decision rules) | 910/850 | §3 pass/fail/inconclusive table; paired-bootstrap methodology cited |
| IMP-003 (NFR-Sec1 loader hard-fail) | 950/950 | NFR-Sec1 strengthened; FR-1 acceptance now requires loader-layer enforcement + unit test |
| IMP-004 (variance protocol) | 850/800 | FR-4 variance-handling subsection added |
| IMP-005 (replay semantics) | 835/880 | FR-4 replay-semantics table added; fresh-run mandated for Sprint 3 |
| IMP-006 (taxonomy stub) | 690/650 | Appendix A added |
| IMP-007 (in-flight kill-switch) | 770/700 | FR-7 in-flight-semantics subsection added |
| IMP-008 (hash-chain failure behavior) | 790/750 | FR-5 acceptance strengthened (fail-closed, no partial reports) |
| IMP-009 (advisor pinned vs moving alias) | 705/600 | FR-9 added; OQ-1 resolved |
| IMP-010 (trace-comparison rollback test) | 635/820 | FR-7 acceptance now includes full-cycle MODELINV-trace integration test |
| IMP-011 (benchmark cost cap) | 765/850 | NFR-P3 added; FR-4 acceptance includes cost-estimate gate |
| IMP-012 (multi-role tiebreaker) | 725/780 | FR-3 `primary_role` field + advisor-wins-ties rule |
| IMP-013 (chain-exhaustion classification) | 660/720 | FR-4 chain-exhaustion table added |
| IMP-014 (per-stratum cost reporting) | 715/680 | FR-5 grouping extended with per-stratum |

Flatline voice status: opus DEGRADED (empty-content; KF-002 layer-1 signature) — non-blocking via voice-drop; gpt-5.5-pro + gemini-3.1-pro substantively agreed across all 14 items.

---

> **Next gate**: `/architect` consumes this PRD to produce the SDD. SDD then gets Flatline + Red Team passes before sprint-plan.
