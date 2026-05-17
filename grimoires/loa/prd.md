# Cycle-112 PRD — Empirical Model Economy (Phase A)

> **Version**: 1.0
> **Source issue**: [#925](https://github.com/0xHoneyJar/loa/issues/925) — `feat(empirical-model-selection): Phase A — model-economy roll-up + workload tier map seed`
> **Cycle**: cycle-112-empirical-model-economy
> **Phase of roadmap**: A of 3 (Activate → Codify → Optimize)
> **Generated**: 2026-05-17 via `/plan` golden-path → `/plan-and-analyze`
> **Discovery shortcut taken**: #925 body is proposal-grade. Skipped greenfield 7-phase interview; relied on issue body + brownfield codebase reality (cycle-109 substrate-hardening artifacts) + memory citations.

---

## 1. Problem Statement

The cost dimension of model dispatch is currently invisible to operators. All the raw telemetry exists — `MODELINV v1.3` envelopes at `.run/model-invoke.jsonl`, `verdict_quality` envelopes attached to every substrate output, `cost_input`/`cost_output` per model in `model-config.yaml` — but no consolidated view turns that telemetry into a decision-grade roll-up. Tier-selection decisions (e.g., "should `/implement` run on executor tier?", "should `/audit-sprint` stay on advisor?") are currently made on operator intuition + scattered memory notes, not on empirical roll-up data.

> Source: #925 body, "Context" section
>
> > "The *cost* side is currently invisible. We have all the raw signal (`MODELINV v1.3` envelopes at `.run/model-invoke.jsonl`, `verdict_quality` on every substrate output, `cost_input`/`cost_output` per model in `model-config.yaml`) but no consolidated view. Decisions like 'should /implement use executor tier?' or 'should /audit-sprint stay on advisor tier?' are made on operator intuition + scattered memory notes, not on empirical roll-up data."

The quality dimension was the focus of cycle-109 (substrate hardening, closed); the cost dimension is what cycle-112 makes legible.

### Why now

Two prerequisites converged in the days before cycle-112 kickoff:

1. **Substrate quality validated** (cycle-111 / today). PR #923 + #924 closed KF-010 empirically — the BB triad now runs 3/3-voice consensus on previously-failing PRs. The substrate is stable enough that cost-vs-quality tradeoffs can be measured without the measurement being confounded by primary failures.
2. **Primary-failure visibility shipped** (this session, [PR #926](https://github.com/0xHoneyJar/loa/pull/926), closes #900). Without #900's fix, fallback-rescue success silently overwrote primary-failure signal, so any cost-per-clean-output roll-up would have produced inflated quality numbers. With #900 closed, `attempts` vs `first_try_success` give the roll-up a clean foundation.

> Source: today's session handoff context + #925 "Dependencies" section
>
> > "Depends on (soft — preferable but not strict): #900 — substrate-health hides primary failures after fallback success. Without #900, roll-up data is confounded by silent fallback-promotion … The roll-up will work without #900 but with a known accuracy caveat documented in the runbook."

Cycle-112 lands AFTER #900 merged, so the caveat is no longer needed.

### Three-phase roadmap context

This cycle ships **Phase A only**:

| Phase | Goal | This cycle |
|---|---|---|
| **A — Activate what exists** | Make existing telemetry visible and usable | **YES** |
| B — Codify the tier mapping | Skills consume `workload_tier_map`; per-skill cost ceilings | Future |
| C — Closed-loop optimization | Auto-demotion proposals, auto-promotion on degradation, regression detector | Future |

> Source: #925 body, "Context" section (phase table verbatim)

Phase B+C are explicitly out of scope and have separate proposal issues (see §6).

---

## 2. Goals & Success Metrics

### Goal G-1 (primary): Operator-readable cost roll-up

Operators can run a single command and see the last 30d of model-dispatch activity broken down by `(skill, model)` with `cost-per-clean-output`, `p95 latency`, and `verdict_quality` distribution.

**Success metric**: An operator who has been away from the project for a week can run `/loa status --economy` and within 30 seconds identify (a) the most expensive skill+model combination, (b) any skill where verdict_quality_healthy_pct < 90%, (c) any model with p95 latency > some configurable threshold.

### Goal G-2: Calibration capture

The empirical calibrations currently living in operator memory (e.g., "executor tier UNSAFE for BB review", "advisor tier required for review+audit") are codified in a `workload_tier_map` in `.loa.config.yaml` with provenance references.

**Success metric**: Every entry in `workload_tier_map` either (a) cites a specific memory file or PR-comment trail, or (b) is annotated as "default, no empirical override". A `grep -c "Tier-Change-Evidence:" .loa.config.yaml` returns ≥ 1 (at least one calibration from memory is captured).

### Goal G-3: Drift protection

Future tier-map changes require empirical justification or an operator-approval marker. The CI gate rejects synthetic PRs that mutate the map without a `Tier-Change-Evidence:` trailer or operator-approval marker.

**Success metric**: A synthetic PR that edits `workload_tier_map` without a `Tier-Change-Evidence:` trailer fails CI with an actionable error message pointing to the runbook.

### Goal G-4: Zero behavior regression

Existing model dispatch behavior is unchanged this cycle. The map is *informational*. Phase B (consumption) is a separate cycle.

**Success metric**: After this cycle ships, every existing skill that dispatches a model produces the same model choice it did before the cycle. Verified by a smoke test that diffs the dispatch choice for a fixed input across pre-cycle and post-cycle `main`.

### Timeline

Single sprint, scope-defined by issue body's 5 deliverables. No external dependencies beyond the existing `MODELINV v1.3` envelope schema (shipped in cycle-109).

---

## 3. User & Stakeholder Context

### Primary user: Loa operator (single persona)

- @janitooor (deep-name) and any agent-swarm operator running Loa in autonomous or interactive mode.
- Reads CLI output, edits `.loa.config.yaml`, reviews PRs from autonomous runs.
- Cares about cost-vs-quality tradeoffs across long-running agent swarms — these add up to real spend over weeks of autonomous operation.
- Does NOT want a Grafana dashboard or external observability surface (explicit out-of-scope in #925).

> Source: #925 body, "Out of scope" section
>
> > "Cost dashboards / external observability — the goal is in-tree CLI visibility, not Grafana boards"

### Secondary stakeholder: future-self / cross-session memory

The cost roll-up and the `workload_tier_map` both serve as memory: a future session can `cat .loa.config.yaml` and learn "advisor tier is required for /audit-sprint because of empirical evidence on PR #885 A/B". Today this lives in memory files (`feedback_advisor_benchmark.md`). After this cycle, it lives in tracked config with provenance.

---

## 4. Functional Requirements

### FR-1: `tools/model-economy-roll-up.sh`

A bash CLI consolidates `.run/model-invoke.jsonl` (and any older-format MODELINV logs we want to absorb) into a tabular roll-up.

**Behavior**:
- One row per `(skill, model, cost-per-clean-output, p95-latency, verdict_quality-distribution)` tuple
- Default time window: 30 days (configurable via `--window 30d`, parses same way `loa_cheval.health` does)
- Output modes: text (human-readable table) and `--json` (machine-readable for `/loa status --economy` consumption)
- Filtering: `--skill <name>` and `--model <id>` (substring match, same semantics as today's `loa_cheval.health --model X`, gated per #900 fix)
- Reads `cost_input` / `cost_output` per model from `model-config.yaml` and joins against MODELINV `tokens_input` / `tokens_output` to compute cost-per-invocation
- "Clean output" = `verdict_quality.status == "APPROVED"` AND `chain_health == "ok"`; cost-per-clean-output divides total cost by clean-invocation count
- Skill attribution: read from MODELINV envelope's `phase` / `skill` field (cycle-109 added the phase field; verify schema)

> Source: #925 body, Deliverable 1 (verbatim)

**EARS notation** (high-precision because this is the load-bearing computation):

- **Ubiquitous**: The roll-up tool shall compute `cost_per_clean_output` as `(total_cost_usd / count_of_envelopes_where_verdict_quality.status == "APPROVED" AND chain_health == "ok")` for each `(skill, model)` tuple over the window.
- **Conditional**: If an MODELINV envelope is missing a `skill` / `phase` attribution field, the tool shall bucket it under `(unknown)` rather than skip it, so total cost is conserved.
- **Event-driven**: When invoked with `--json`, the tool shall emit a JSON document that conforms to a published schema at `.claude/data/model-economy-rollup.schema.json` (delivered with this sprint).

### FR-2: `/loa status --economy`

The `/loa` golden-path command gains an `--economy` flag that surfaces the FR-1 roll-up.

**Behavior**:
- Default window: 30d
- Default output: text table
- Suggested format (from #925 body):
  ```
  Skill              Model                   Runs   Cost/run    p95 latency   VQ-healthy %
  /implement         claude-sonnet-4-6       42     $0.18       42s           98%
  /review-sprint     claude-opus-4-7         15     $1.20       190s          93%
  /audit-sprint      gpt-5.5-pro             15     $0.95       240s          87%   ⚠ degraded twice
  ```
- Degradation marker (the `⚠ degraded twice` suffix) fires when ≥ 2 envelopes in the window had `verdict_quality.status` ∈ {DEGRADED, FAILED} for that `(skill, model)` tuple
- Implementation: shells out to `tools/model-economy-roll-up.sh` (the CLI is the canonical implementation; `/loa status --economy` is a thin wrapper that runs `--json` and pretty-prints)

### FR-3: Seeded `workload_tier_map` in `.loa.config.yaml`

A new top-level config section `workload_tier_map` maps `(skill_name) → {tier, rationale, evidence_ref}`.

**Behavior**:
- Skills covered: every skill that currently dispatches a model (identified by `grep "model-adapter\|cheval" .claude/skills/` per #925 AC)
- Tiers (initial vocabulary): `advisor` (highest quality, e.g. Opus 4.7 / GPT-5.5-pro / Gemini-3.1-pro), `executor` (efficient, e.g. Sonnet 4.6 / Haiku 4.5), `headless` (CI-tier, e.g. codex-headless / claude-headless)
- Schema: each entry has `tier`, `rationale` (free text), `evidence_ref` (a memory filename or PR URL or "default")
- Seeded entries (from operator memory + this session's adversarial-review experience):
  - `/review-sprint`: `advisor` — rationale "executor tier missed 1 HC + 60% fewer findings on PR #885 A/B"; evidence_ref `feedback_advisor_benchmark.md`
  - `/audit-sprint`: `advisor` — same rationale; evidence_ref `feedback_advisor_benchmark.md`
  - `bridgebuilder-review`: `advisor` — rationale "BB needs cross-model dissent diversity; executor tier degrades to single-model"; evidence_ref `feedback_advisor_benchmark.md`
  - `adversarial-review`: `advisor` — rationale "dissenter needs to catch reviewer blind spots; quality floor non-negotiable"; evidence_ref `feedback_advisor_benchmark.md`
- Default (no empirical override) entries are still written, marked `evidence_ref: default` — this makes the map exhaustive over the skill surface and prevents "silent absence == default" ambiguity

> Source: #925 body, Deliverable 3 (and ACs)
> Source: memory `feedback_advisor_benchmark.md` (executor unsafe for BB review)
> Source: today's session adversarial-review run on PR #885 (referenced in memory note 2026-05-16 evening)

### FR-4: CI drift gate

A GitHub Actions workflow rejects PRs that mutate `.loa.config.yaml::workload_tier_map` without providing empirical justification.

**Behavior**:
- Trigger: `pull_request` events that touch `.loa.config.yaml`
- Logic: if the PR diff contains changes to lines within the `workload_tier_map` section, the PR body must contain EITHER:
  1. A `Tier-Change-Evidence:` trailer followed by a roll-up table (markdown) showing N HEALTHY verdict_quality runs at the new tier, OR
  2. An `Operator-Approval:` trailer with a deep-name signature (same pattern as cycle-108 baseline-pin drift gate per #925)
- Failure mode: actionable error message pointing to `grimoires/loa/runbooks/model-economy.md` "How to justify a tier change" section
- Same architectural pattern as the cycle-108 baseline-pin drift gate (referenced in #925 verbatim)

> Source: #925 body, Deliverable 4 (verbatim)

### FR-5: Operator runbook at `grimoires/loa/runbooks/model-economy.md`

A standalone runbook covering five operator-facing sections:

1. **How to read the roll-up** — column meanings, how to interpret cost-per-clean-output, when "degraded twice" warrants action
2. **When to consider a tier change** — quality floors per skill (defer to operating principles), what signals justify investigating a demotion (e.g., 30+ HEALTHY runs at current tier with stable verdict_quality)
3. **How to justify a tier change in a PR body** — exact format of `Tier-Change-Evidence:` trailer, what counts as evidence, when `Operator-Approval:` is the right path instead
4. **What triggers the drift gate** — which lines, why, and how to avoid surprise failures
5. **Operating principles** — the five from #925 body, verbatim, codified so future operators don't have to rediscover them

> Source: #925 body, Deliverable 5 (verbatim)
> Source: #925 body, "Operating principles" section (verbatim)

---

## 5. Technical & Non-Functional Requirements

### NFR-Perf-1: Roll-up speed

`tools/model-economy-roll-up.sh` must complete in < 5 seconds for a 30d window over a 100K-entry `.run/model-invoke.jsonl`. Same bar as cycle-109's `aggregate_substrate_health` (NFR-Perf-3 there is < 2s for 24h / 100K — we're 7× the window so 5s is conservative).

### NFR-Sec-1: No secret leakage

The roll-up consumes MODELINV envelopes. MODELINV payloads have already been sanitized through `lib/log-redactor` (cycle-099 T1.13). The roll-up tool MUST NOT introduce new paths that bypass redactor — specifically, it must NOT print `models_failed[].message_redacted` content or any other free-text envelope field that could carry secret-shape strings. Display surface is restricted to model IDs, skill names, integer counts, latency stats, cost numbers, and verdict_quality enum values.

### NFR-Quality-1: Quality floor preservation

Per #925 operating principle 1: "Quality is a hard floor; cost is the optimization variable. Never trade a HIGH_CONSENSUS finding for cost." This sprint ships INFRASTRUCTURE for quality-floor-respecting tier decisions. The drift gate (FR-4) is the mechanism: changes to `workload_tier_map` are gated on empirical evidence, which means the gate refuses to let cost arguments override quality.

### NFR-Determinism-1: Roll-up determinism

Given an identical MODELINV log and identical `model-config.yaml`, the roll-up output must be byte-identical across runs (modulo timestamp banner). No floating-point nondeterminism in cost or rate calculations — use the same `round(..., 4)` discipline as `aggregate_substrate_health`.

### NFR-Compat-1: Existing dispatch unchanged

Per AC: "Zero regression: existing model dispatch unchanged in behavior (the map is *informational* this sprint — Phase B is when skills start consuming it)". Skills do not read `workload_tier_map`. The map exists in config for human readers and for the drift gate.

### Technical stack alignment

- **Bash** for the CLI (`tools/model-economy-roll-up.sh`) — consistent with other tools in `tools/` and with `loa_cheval.health` shim
- **Python (optional)** for the heavy aggregation if bash JSONL parsing becomes unwieldy — Python is already in tree for `loa_cheval`; precedent set
- **jq** for envelope parsing and JSON output — already a hard dep
- **YAML for config** — `workload_tier_map` lives in `.loa.config.yaml` per #925; `yq` v4 already a hard dep
- **GitHub Actions** for the drift gate — same workflow style as cycle-108 baseline-pin gate
- **No new top-level deps** — everything is already in tree

---

## 6. Scope & Prioritization

### In scope (this cycle / Phase A)

- FR-1 through FR-5 as listed above
- 5 ACs as written in #925 issue body verbatim (replicated below for traceability)

### Out of scope (explicit)

| Out of scope | Reason | Where it lives |
|---|---|---|
| Skills *consume* the `workload_tier_map` | Phase B | Separate future cycle |
| Auto-demotion / auto-promotion proposals | Phase C | Separate future cycle(s) |
| Cost dashboards / external observability | Explicit out-of-scope per #925 | Not planned |
| Per-cycle cost summaries (e.g., "cycle-110 spent $X total") | Could be added but isn't a deliverable here | Possible Phase A.1 polish |
| #919 model-tier economization (the *proposal-side* counterpart) | Already merged | n/a |
| Cleaning up the pre-existing ledger drift (cycle-109/110/111 ledger inconsistency) | Out of band; tangential to model-economy | Separate operator-led cleanup |

> Source: #925 body, "Out of scope" section (replicated verbatim)

### Acceptance Criteria (verbatim from #925)

- [ ] `tools/model-economy-roll-up.sh` runs against a real `.run/model-invoke.jsonl` and emits well-formed tabular output (text + JSON modes)
- [ ] `/loa status --economy` displays the 30d roll-up without requiring extra args
- [ ] The seeded `workload_tier_map` covers every skill that currently dispatches a model (audit by `grep "model-adapter\|cheval" .claude/skills/`)
- [ ] At least one calibration from memory is pinned in the map with a reference (e.g. `# Tier-Change-Evidence: feedback_advisor_benchmark.md — executor 6× cheaper but 1 HC missed on PR #885 A/B`)
- [ ] Drift gate is wired into CI and rejects a synthetic PR that edits the map without a `Tier-Change-Evidence:` trailer
- [ ] Operator runbook reviewed via /review-sprint + /audit-sprint
- [ ] Zero regression: existing model dispatch unchanged in behavior (the map is *informational* this sprint — Phase B is when skills start consuming it)

---

## 7. Risks & Dependencies

### Risks

| ID | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| R-1 | MODELINV envelopes are missing the `skill` / `phase` attribution field on older log lines | medium | medium | FR-1 conditional EARS: bucket missing-attribution envelopes under `(unknown)` rather than skip. Cost is conserved even when bucket attribution is partial. |
| R-2 | `cost_input` / `cost_output` per model in `model-config.yaml` is stale or wrong for older models | medium | low | Roll-up footer surfaces the model→cost table used in the run with the version pin of `model-config.yaml` for transparency. Operator can re-run with `--cost-snapshot <ref>` to use a historical version. |
| R-3 | The drift gate triggers false positives on harmless reformatting of `.loa.config.yaml` | medium | low | Drift gate scopes detection to changes WITHIN the `workload_tier_map` YAML section (using yq path-aware diff), not the whole file. Same pattern as cycle-108 baseline-pin gate. |
| R-4 | Operator forgets to update `workload_tier_map` when adding a new skill, leaving the map non-exhaustive | low | low | Defer to Phase B — that's where the map becomes load-bearing. Phase A's drift gate is informational. |
| R-5 | Per #925 operating principle 5: "Substrate-health is upstream of tier selection." If the substrate is degraded during the data-collection window, the roll-up surfaces a misleading cost-per-clean-output (because the "clean" denominator is suppressed). | medium | medium | Roll-up explicitly surfaces `substrate_health_window_summary` in the footer — operator can see if the window included a substrate degradation event and reason about confounded data. |
| R-6 | Pre-existing `final_model` bucketing leakage (deferred from #900 fix) confounds `(skill, model)` attribution when filtering by model | low | medium | NOTES.md Decision Log already documents this. Roll-up tool inherits the same scope split — uses post-`models_requested` attribution where appropriate, notes the leakage in the runbook. |

### Dependencies

| Dep | Status | Notes |
|---|---|---|
| #900 substrate-health primary-failure visibility | **Closed today** ([PR #926](https://github.com/0xHoneyJar/loa/pull/926), `602568c5`) | Was a soft-dep; closing removes the accuracy caveat from this cycle's data |
| MODELINV v1.3 envelope schema | Shipped (cycle-109) | Includes `tokens_input` / `tokens_output` / `verdict_quality` / `chain_health` — everything the roll-up needs |
| `.loa.config.yaml` `model-config` section with `cost_input` / `cost_output` per model | Already in tree | Verify in SDD phase that all dispatched models have cost entries |
| `lib/log-redactor` (cycle-099 T1.13) | Already enforced on MODELINV writes | NFR-Sec-1 inherits this |
| cycle-108 baseline-pin drift gate workflow | Shipped (PR #867) | Provides the architectural template for FR-4 |

### Unlocks (this cycle enables future work)

- **#876 real-data benchmark operator trigger gate** — the benchmark engine needs the roll-up infrastructure to compare A/B runs against. After this cycle, #876 can be activated with the roll-up as its data foundation.
- **Phase B** — straightforward once the map exists and the drift gate is in place; skills start consuming `workload_tier_map`
- **Phase C** — needs N cycles of operational data from this sprint's roll-up

---

## 8. Operating Principles (codified for runbook)

Per #925 body, these five principles govern future tier decisions and are the source-of-truth for the runbook (FR-5 §5):

1. **Quality is a hard floor; cost is the optimization variable.** Never trade a HIGH_CONSENSUS finding for cost. Memory's "executor unsafe for BB review" (6× cheaper, 1 HC missed, 60% fewer findings) is the canonical example.
2. **Different work has different quality floors.** `/implement` can tolerate lower tier than `/audit-sprint`. Codify per-skill, not globally.
3. **Empirical beats theoretical.** Don't move tiers based on intuition. Require N HEALTHY verdict_quality runs before any demotion proposal.
4. **One-way doors require operator approval.** Demotions to cheaper tier are easy to slip into and hard to detect regressing-out-of. Promotions are safer defaults.
5. **Substrate-health is upstream of tier selection.** When the substrate is degraded (chain-exhausted, malformed_response, voice-dropped), no model choice produces a clean verdict. Fix substrate first, then optimize within healthy substrate.

> Source: #925 body, "Operating principles" section (verbatim)

---

## 9. Sources & Traceability

- **Issue**: [#925](https://github.com/0xHoneyJar/loa/issues/925) — primary source, body cited verbatim throughout
- **Memory**: `feedback_advisor_benchmark.md` (executor unsafe for BB review), `project_next_priorities_2026_05_13.md` (cycle-108 close, top priorities), `feedback_substrate_validation_close_shape.md` (substrate-validation shape pattern)
- **Recent PRs**: #923 (KF-010 close, deriveTimeoutMs reasoning-class predicate), #924 (KF-010 empirical confirmation), [#926](https://github.com/0xHoneyJar/loa/pull/926) (#900 close, substrate-health primary-failure visibility)
- **Reality grounding (codebase)**: `.claude/adapters/loa_cheval/health.py` (MODELINV envelope aggregation pattern this cycle extends), `.run/model-invoke.jsonl` (raw telemetry source), `.loa.config.yaml::flatline_protocol` (existing model + budget config pattern this cycle echoes)
- **Architectural template**: cycle-108 PR #867 baseline-pin drift gate (template for FR-4 drift gate)

### Discovery shortcut justification

The /plan-and-analyze skill's default 7-phase interview was skipped because:

1. #925 body is proposal-grade — already contains problem statement, deliverables, ACs, dependencies, out-of-scope, operating principles
2. The operator explicitly authorized the shortcut in this session's hand-off
3. Brownfield grounding is already fresh: cycle-109 substrate-hardening reality at `grimoires/loa/cycles/cycle-109-substrate-hardening/sdd.md` documents the MODELINV envelope shape this cycle consumes; that work was completed by the same operator within the last 2 weeks
4. Phase 0 confirmation gate (this PRD) is the operator's review surface — interview compression at the front does not lose the operator-review gate at the back

The compressed-interview decision is captured in `grimoires/loa/NOTES.md` Decision Log (2026-05-17 entry) per cycle hygiene.
