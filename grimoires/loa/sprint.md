# Sprint Plan: Cycle-112 Empirical Model Economy (Phase A)

**Version:** 1.0
**Date:** 2026-05-17
**Author:** Sprint Planner Agent (`planning-sprints` skill)
**PRD Reference:** `grimoires/loa/cycles/cycle-112-empirical-model-economy/prd.md` v1.0 (mirrored at `grimoires/loa/prd.md`)
**SDD Reference:** `grimoires/loa/cycles/cycle-112-empirical-model-economy/sdd.md` v1.0 (mirrored at `grimoires/loa/sdd.md`)
**Cycle:** `cycle-112-empirical-model-economy`
**Source Issue:** [#925](https://github.com/0xHoneyJar/loa/issues/925)
**Phase:** A of 3 (Activate → Codify → Optimize)
**Mirror:** `grimoires/loa/cycles/cycle-112-empirical-model-economy/sprint.md` (byte-identical)

---

## Executive Summary

Phase A of the three-phase Empirical Model Economy roadmap ships an operator-facing reporting layer over pre-existing model-dispatch telemetry plus a config-as-memory structure (`workload_tier_map`) protected by a CI drift gate. **No dispatch path is touched.** The deliverables are: (FR-1) `tools/model-economy-roll-up.sh` + Python aggregator, (FR-2) `/loa status --economy` wrapper, (FR-3) seeded `workload_tier_map` in `.loa.config.yaml`, (FR-4) CI drift gate, (FR-5) operator runbook.

SDD §8 enumerated 14 tasks within a single proposed sprint. To respect the planning-sprints LARGE-sprint upper bound (10 tasks), this plan splits the work across **two sprints** along a clean natural seam: Sprint 1 ships the data layer (read path + CLI surface), Sprint 2 ships the config layer (write path + drift gate + runbook + E2E). The seam matches the SDD's parallel-safe partition (T1.7+T1.8+T1.9 disjoint from T1.1+T1.2 file-wise) and the critical-path runbook dependency (runbook must reference live Sprint-1 roll-up output).

> Source: SDD §8 "Parallel-safe: T1.7+T1.8+T1.9 can run in parallel with T1.1+T1.2 since they touch disjoint files."

**Phase A.1 follow-ups** (explicitly OUT of this sprint plan per operator scope decision):

- **D-6** — Wire `calling_primitive` through dispatch entrypoints to make `(skill)` attribution non-zero. Currently 0% of envelopes carry attribution (SDD §0.3 falsification). Phase A renders `(unattributed)` honestly + discloses the coverage gap.
- **D-7** — Extend MODELINV writer + cheval providers to capture `tokens_output` post-flight. Phase A ships input-side cost only.

**Total Sprints:** 2
**Sprint Duration:** 2.5 days each
**Estimated Completion:** 2026-05-22

---

## Sprint Overview

| Sprint | Theme | Key Deliverables | Scope | Tasks | Dependencies |
|--------|-------|------------------|-------|-------|--------------|
| 1 (global #166) | Roll-up data layer (FR-1, FR-2) | JSON schema, `economy.py` aggregator, `model-economy-roll-up.sh` shim, `/loa status --economy` flag, fixtures + perf/determinism gates | LARGE | 8 | None — entry point |
| 2 (global #167) | Config layer + drift gate + runbook + E2E (FR-3, FR-4, FR-5) | `workload_tier_map` schema + seed, exhaustiveness audit tool, CI drift workflow, synthetic-PR gate tests, operator runbook, E2E goal validation | LARGE | 7 | Sprint 1 (runbook references Sprint 1 deliverables; T2.E2E validates all goals) |

> Source: SDD §8 critical path "T1.1 → T1.2 → T1.3 → T1.11 → T1.13" — Sprint 1 owns T1.1-T1.3 + T1.11-T1.12; Sprint 2 owns T1.7-T1.10 + T1.13-T1.14 + E2E.

---

## Sprint 1: Roll-up Data Layer (FR-1 + FR-2)

**Global Sprint ID:** 166
**Local Sprint ID:** sprint-1
**Cycle:** cycle-112-empirical-model-economy
**Scope:** LARGE (8 tasks)
**Duration:** 2.5 days
**Dates:** 2026-05-17 – 2026-05-19

### Sprint Goal

Ship the read-side reporting layer: an operator running `/loa status --economy` sees a 30-day roll-up of model-dispatch activity with cost-per-clean-output, p95 latency, and verdict-quality health for every `(skill, model)` cell, with coverage disclosure surfacing the SDD §0.3 attribution gap honestly.

### Deliverables

- [ ] **D1.1**: `.claude/data/schemas/model-economy-rollup.schema.json` — JSON Schema Draft 2020-12 conforming to SDD §3.2.1 (FR-1 Event-driven EARS contract)
- [ ] **D1.2**: `.claude/adapters/loa_cheval/economy.py` — Python canonical aggregator (`aggregate_economy`, `render_text`, `render_json`) re-using cycle-109 `aggregate_substrate_health` stream-parse + defaultdict pattern
- [ ] **D1.3**: `tools/model-economy-roll-up.sh` — Bash CLI shim (~80 LOC, matches `loa-substrate-health.sh` shape)
- [ ] **D1.4**: `.claude/scripts/loa-status.sh` `--economy` flag extension (~30 lines added) + `.claude/commands/loa.md` documentation update
- [ ] **D1.5**: 5 test fixtures under `tests/fixtures/model-economy/` (empty, no-attribution, fully-attributed, malformed-lines, snapshot-deterministic golden)
- [ ] **D1.6**: ~25 pytest unit tests (`tests/unit/test_economy_aggregation.py`) covering parsing, aggregation, cost calc, edge cases, NFR-Sec-1 redaction
- [ ] **D1.7**: ~10 bats integration tests (`tests/integration/test_economy_cli.bats`) plus dedicated perf + determinism bats files

### Acceptance Criteria

- [ ] `tools/model-economy-roll-up.sh --window 30d` runs against the live `.run/model-invoke.jsonl` (808 envelopes) and emits a well-formed text table including coverage disclosure (FR-1, PRD AC #1)
- [ ] `tools/model-economy-roll-up.sh --window 30d --json` emits JSON validated against `.claude/data/schemas/model-economy-rollup.schema.json` (FR-1 Event-driven EARS)
- [ ] `/loa status --economy` displays the 30d roll-up without requiring any extra args (FR-2, PRD AC #2)
- [ ] `/loa status --economy --skill <substring>` and `... --model <substring>` filter correctly (FR-1 substring semantics matching `loa_cheval.health`)
- [ ] Cost-per-clean-output formula implements `(sum cost_usd where verdict_quality.status == "APPROVED" AND verdict_quality.chain_health == "ok") / (count of same)` per row, with `null` when denominator is 0 (PRD §4 FR-1 Ubiquitous EARS; nesting correction per SDD §3.3)
- [ ] Missing-attribution envelopes bucket to `(unattributed, <model>)` rather than skip — total cost is conserved (PRD §4 FR-1 Conditional EARS; SDD §0.3)
- [ ] Footer surfaces `substrate_health_window_summary` cross-ref to cycle-109's `aggregate_substrate_health` for the same window (R-5 mitigation per SDD §9.1)
- [ ] NFR-Perf-1: roll-up over a 100K-envelope synthetic JSONL completes in < 5s wall clock
- [ ] NFR-Sec-1: a synthetic `AKIA...`-shape secret injected into `models_failed[].message_redacted` does NOT appear in any text or JSON output column
- [ ] NFR-Determinism-1: 3 consecutive runs against the same fixture produce byte-identical output modulo timestamp banner (use `--no-ts-banner` flag for the test)
- [ ] NFR-Compat-1: `git diff main..HEAD -- .claude/scripts/model-adapter.sh .claude/adapters/loa_cheval/providers/ .claude/adapters/loa_cheval/cheval.py` returns empty (no dispatch-path changes)

### Technical Tasks

<!-- Task IDs reference SDD §8 task breakdown -->

- [ ] **T1.1**: Author `.claude/data/schemas/model-economy-rollup.schema.json` per SDD §3.2.1 (~120 LOC schema) — `$schema` Draft 2020-12, `$id` set, required top-level keys (`window`, `since`, `now`, `log_path`, `coverage`, `per_skill_model`, `footer`), `additionalProperties: false` at every object level → **[G-1]**
- [ ] **T1.2**: Implement `.claude/adapters/loa_cheval/economy.py::aggregate_economy()` + `render_text()` + `render_json()` per SDD §4.1.2 (~400 LOC). Re-use stream-parse pattern from `health.py:153-309`. Cost computation uses `pricing_snapshot.input_per_mtok × capability_evaluation.estimated_input_tokens` (input-side only this cycle; D-7 follow-up). Sort by `(cost_total_usd desc, model_id asc)`. `round(x, 4)` discipline. Dual-attribution pattern: emit rows per `final_model_id` AND per `models_requested[]` with `first_try_success` vs `attempts` (R-6 mitigation) → **[G-1, G-4]**
- [ ] **T1.3**: Implement `tools/model-economy-roll-up.sh` per SDD §4.1.1 (~80 LOC). Validates args (`--window`, `--skill`, `--model`, `--json`, `--cost-snapshot`, `--log-path`, `--no-ts-banner`), shells `PYTHONPATH=.claude/adapters python -m loa_cheval.economy`, pipes through `lib/log-redactor` for defense-in-depth. Exit codes per SDD §5.1 (0/2/3/4/64) → **[G-1]**
- [ ] **T1.4**: Build 5 test fixtures (SDD §7.2): `empty.jsonl`, `no-attribution.jsonl` (100 envelopes mirroring current 0% attribution / 35% pricing / 50% VQ state), `fully-attributed.jsonl` (proves D-6 future state works), `malformed-lines.jsonl` (5 envelopes with 2 interleaved malformed lines), `snapshot-deterministic.golden` (insta-style golden) → **[G-1]**
- [ ] **T1.5**: Write `tests/unit/test_economy_aggregation.py` (~25 tests, ~500 LOC) covering: schema-conform output, cost-per-clean-output formula, conservation under bucketing, NFR-Sec-1 redaction injection, version-tolerant envelope parsing (v1.1 → v1.4), `--cost-snapshot <git-ref>` error path (R-2 mitigation), empty-log behavior → **[G-1]**
- [ ] **T1.6**: Write `tests/integration/test_economy_cli.bats` (~10 tests) + `tests/integration/test_economy_perf.bats` (NFR-Perf-1: synthetic 100K envelopes, `timeout 5`, assert exit 0) + `tests/integration/test_economy_determinism.bats` (NFR-Determinism-1: 3× run byte-identical with `--no-ts-banner`) → **[G-1, G-4]**
- [ ] **T1.7**: Extend `.claude/scripts/loa-status.sh` with `--economy` flag (`--window`, `--skill`, `--model`, `--json` forward to `tools/model-economy-roll-up.sh`); update `.claude/commands/loa.md` with usage section per SDD §4.2.3. Default `--window 30d`, text mode, all skills, all models → **[G-1]**
- [ ] **T1.8**: Add NFR-Compat-1 smoke test (`tests/integration/test_dispatch_unchanged.bats`) that exercises `model-adapter.sh` resolution for a fixed prompt and asserts the model choice is the cycle-baseline answer (validates the map is informational only; nothing this cycle bleeds into dispatch) → **[G-4]**

### Dependencies

- None (entry-point sprint).
- **External dep verification at sprint start**: confirm `.claude/defaults/model-config.yaml` has `providers.<p>.models.<m>.pricing.input_per_mtok` for every model that appears in the 30d MODELINV window. If a model is missing pricing, the roll-up buckets it to `(unknown_cost)`; sprint adds a footer warning when `cost_coverage_pct < 50%`.
- **Predecessor inheritance** (SDD §0.4): MODELINV v1.4 envelope schema (cycle-109), `aggregate_substrate_health` pattern (cycle-109 health.py:153-309), `lib/log-redactor` (cycle-099 T1.13), bash+Python split pattern (cycle-109 `loa-substrate-health.sh`).

### Security Considerations

- **Trust boundaries**: `.run/model-invoke.jsonl` is operator-trusted (MODELINV writer already runs `redact_payload_strings` per cycle-099 pipeline). The roll-up does NOT print any free-text envelope field (`models_failed[].message_redacted`, etc.) — display surface restricted to model IDs, skill names (always `(unattributed)` this cycle), integer counts, latency stats, cost numbers, enum values (NFR-Sec-1).
- **External dependencies**: zero new top-level deps. Uses `jq` (already pinned), `yq` v4.52.4+ (already SHA256-pinned via cycle-099 sprint-1A), Python `jsonschema` (already in `pyproject.toml`).
- **Sensitive data**: pricing data is non-secret. Cost numbers are derived. No API keys or credentials are read by this sprint.
- **Defense in depth**: bash shim pipes Python output through `lib/log-redactor` even though the source is already redacted — guards against future writer changes regressing the invariant.

### Risks & Mitigation

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| R-7 (SDD §9.2): `(unattributed)` 100% reality makes FR-1 surface appear useless to operators expecting #925 example output | High | Med | Header line shows `Coverage: skill attribution 0% (D-6 follow-up) · cost 35% · verdict_quality 48%` so the gap is immediately visible; Sprint 2 runbook §1 explains in depth |
| R-8 (SDD §9.2): Cost coverage at 35% (input-only) is low enough that early cost numbers may be unreliable | Med | Med | Footer shows `cost_coverage_pct` explicitly; rows without cost data render `—` not `$0.00` |
| R-2 (PRD): Stale `cost_input`/`cost_output` in `model-config.yaml` for older models | Med | Low | `--cost-snapshot <git-ref>` flag lets operator use historical pricing version; footer pins `model_config_ref` |
| R-6 (PRD): `final_model` bucketing leakage from #900 deferred work | Low | Med | Inherit cycle-109 dual-attribution pattern: emit rows per `final_model_id` AND per `models_requested[]` with `first_try_success` vs `attempts` (per SDD §0.3 third bullet) |
| NFR-Perf-1 risk: 30-day window over 100K envelopes blows past 5s budget | Low | Low | health.py achieves <2s for 24h/100K; same per-line cost; budget is 2.5× conservative |
| Schema-validation surprise: jsonschema fails on a real-log envelope edge case | Med | Low | Aggregator tolerates every payload field as optional (SDD §3.1.1); validation runs at output time only, not on each envelope input |

### Success Metrics

- `tools/model-economy-roll-up.sh --window 30d` produces output in < 5s against the live 808-envelope log
- 100% of pytest + bats tests pass (~35 tests total)
- `jsonschema.validate(output, model-economy-rollup.schema.json)` returns clean on all 5 fixture outputs
- Operator can run `/loa status --economy` and identify (a) most expensive `(skill, model)` cell, (b) any cell with `verdict_quality_healthy_pct < 90%`, (c) any model with `p95_latency_ms` above threshold within 30 seconds (G-1 success metric)
- Zero changes to dispatch path verified by post-sprint `git diff` smoke test (T1.8)

---

## Sprint 2 (Final): Config Layer + Drift Gate + Runbook + E2E (FR-3 + FR-4 + FR-5)

**Global Sprint ID:** 167
**Local Sprint ID:** sprint-2
**Cycle:** cycle-112-empirical-model-economy
**Scope:** LARGE (7 tasks including E2E)
**Duration:** 2.5 days
**Dates:** 2026-05-20 – 2026-05-22

### Sprint Goal

Ship the write-side config-as-memory layer: `workload_tier_map` seeded with empirical calibrations from operator memory, protected by a CI drift gate, documented by an operator runbook — then validate end-to-end that all PRD goals (G-1 through G-4) are achieved.

### Deliverables

- [ ] **D2.1**: `.claude/data/schemas/workload-tier-map.schema.json` — JSON Schema for the new `.loa.config.yaml::workload_tier_map` section (~60 LOC)
- [ ] **D2.2**: `.loa.config.yaml::workload_tier_map` — seeded section with 4 empirically calibrated entries + exhaustive default entries for every skill that currently dispatches a model
- [ ] **D2.3**: `tools/audit-workload-tier-map.sh` — exhaustiveness check (~50 LOC) that lists dispatching skills via `grep -lE "model-adapter|cheval" .claude/skills/**/SKILL.md` and diffs against map `entries:` keys; exit 1 on missing
- [ ] **D2.4**: `.github/workflows/workload-tier-map-drift.yml` — CI drift gate following cycle-108 schema-guard template (~120 LOC)
- [ ] **D2.5**: `tests/integration/workflow_drift_gate.bats` — 3 synthetic-PR scenarios (mutate-without-trailer fails, mutate-with-`Tier-Change-Evidence`-trailer passes, reformatting-elsewhere passes)
- [ ] **D2.6**: `grimoires/loa/runbooks/model-economy.md` — operator runbook with 5 sections from PRD §4 FR-5 + appendix on Phase A known limitations (~300 LOC)
- [ ] **D2.7**: NOTES.md Decision Log + memory observations capturing cycle close + D-6/D-7 follow-up tracker text from SDD §10.2

### Acceptance Criteria

- [ ] `workload_tier_map.entries` covers every skill that currently dispatches a model (audit script exit 0); 4 empirically calibrated entries have `evidence_ref: "memory:feedback_advisor_benchmark.md"` and remaining entries have `evidence_ref: "default"` (FR-3, PRD AC #3, #4)
- [ ] At least one calibration from memory is pinned with reference (PRD AC #4) — verified by `grep -c '^      evidence_ref: "memory:' .loa.config.yaml` ≥ 1
- [ ] Drift gate workflow rejects a synthetic PR that edits `workload_tier_map` without a `Tier-Change-Evidence:` or `Operator-Approval:` trailer (FR-4, PRD AC #5)
- [ ] Drift gate workflow allows a synthetic PR that edits `workload_tier_map` with a valid trailer
- [ ] Drift gate workflow allows a synthetic PR that edits other sections of `.loa.config.yaml` without any trailer (R-3 + R-11 false-positive mitigation per SDD §4.4.3, §9.2)
- [ ] Workflow scopes detection via `yq eval '.workload_tier_map'` projection — NOT whole-file diff (SDD §4.4.2)
- [ ] Operator runbook reviewed via `/review-sprint` + `/audit-sprint` with zero CHANGES_REQUIRED (PRD AC #6)
- [ ] Runbook includes all 5 PRD §4 FR-5 sections: how to read the roll-up, when to consider a tier change, how to justify a tier change in a PR body, what triggers the drift gate, operating principles (verbatim from #925 / PRD §8)
- [ ] Runbook appendix discloses Phase A known limitations (skill attribution = 0%, cost coverage ~35% input-only, D-6 / D-7 are explicit follow-ups)
- [ ] Zero regression: `tools/loa-status.sh --economy` output is identical pre- and post-Sprint 2 (the map is informational this cycle; consumption is Phase B) (PRD AC #7, NFR-Compat-1)

### Technical Tasks

- [ ] **T2.1**: Author `.claude/data/schemas/workload-tier-map.schema.json` per SDD §4.3.1 with `additionalProperties: false` at all levels, tier enum `[advisor, executor, headless]`, evidence_ref pattern matching `memory:|pr:|default|operator-decision:` → **[G-2]**
- [ ] **T2.2**: Write `.loa.config.yaml::workload_tier_map` section per SDD §4.3.2: 4 empirically calibrated entries (`/review-sprint`, `/audit-sprint`, `bridgebuilder-review`, `adversarial-review` — all `tier: advisor` with `evidence_ref: "memory:feedback_advisor_benchmark.md"`) + exhaustive default-tier entries (one per dispatching skill, all `tier: advisor` with `evidence_ref: "default"` per SDD §10.1 question 5 resolution) → **[G-2]**
- [ ] **T2.3**: Implement `tools/audit-workload-tier-map.sh` (~50 LOC) — enumerates dispatching skills via the AC-mandated grep, joins against map `entries:`, exits 1 on missing skills with actionable error pointing to the runbook → **[G-2]**
- [ ] **T2.4**: Author `.github/workflows/workload-tier-map-drift.yml` per SDD §4.4 — `pull_request` + `push` triggers with path filters; yq-path-aware diff of `workload_tier_map` subtree only; trailer detection (`^Tier-Change-Evidence:` OR `^Operator-Approval:` anchored regex); actionable `::error::` annotation pointing to runbook §3 on failure → **[G-3]**
- [ ] **T2.5**: Write `tests/integration/workflow_drift_gate.bats` — 3 scenarios per SDD §7.4: mutation-no-trailer fails, mutation-with-trailer passes, reformatting-elsewhere passes without trailer (R-3 + R-11 mitigation pin) → **[G-3]**
- [ ] **T2.6**: Author `grimoires/loa/runbooks/model-economy.md` per SDD §4.5 — 5 sections + Phase A limitations appendix. Cross-reference Sprint 1's roll-up output for worked examples (frozen quotes, not invented). Codify PRD §8 operating principles verbatim. Document the exact format of `Tier-Change-Evidence:` trailer + when to use `Operator-Approval:` instead → **[G-2, G-3]**
- [ ] **T2.E2E**: End-to-end goal validation across all four PRD goals (see "Task 2.E2E" detail below) → **[G-1, G-2, G-3, G-4]**

### Task 2.E2E: End-to-End Goal Validation

**Priority:** P0 (Must Complete)
**Goal Contribution:** All goals (G-1, G-2, G-3, G-4)

**Description:**
Validate that all four PRD goals are achieved by the combined Sprint 1 + Sprint 2 deliverables. This is the cycle-close gate before `/audit-sprint`.

**Validation Steps:**

| Goal ID | Goal | Validation Action | Expected Result |
|---------|------|-------------------|-----------------|
| G-1 | Operator-readable cost roll-up | Operator runs `/loa status --economy` on the live `.run/model-invoke.jsonl`. Within 30s, operator identifies (a) most expensive `(skill, model)` cell, (b) any cell with `verdict_quality_healthy_pct < 90%`, (c) any model with `p95_latency_ms > 60000` | All three items surface in output without manual jq parsing |
| G-2 | Calibration capture | Run `grep -c '^      evidence_ref: "memory:' .loa.config.yaml` and `grep -c "Tier-Change-Evidence:" .loa.config.yaml`. Run `tools/audit-workload-tier-map.sh` | First grep ≥ 1; audit-script exit 0; all 4 calibrated entries cite `feedback_advisor_benchmark.md` |
| G-3 | Drift protection | Open a synthetic test PR that demotes `/review-sprint` from `advisor` to `executor` without a `Tier-Change-Evidence:` trailer | Drift gate fails CI with actionable error pointing to `grimoires/loa/runbooks/model-economy.md` `#how-to-justify-a-tier-change` |
| G-4 | Zero behavior regression | `git diff main..HEAD -- .claude/scripts/model-adapter.sh .claude/adapters/loa_cheval/providers/ .claude/adapters/loa_cheval/cheval.py`. Run `tests/integration/test_dispatch_unchanged.bats` smoke test | Diff returns empty; smoke test exit 0; model resolution unchanged for fixed prompt |

**Acceptance Criteria:**

- [ ] Each goal validated with documented evidence (output snippets attached to closing PR description)
- [ ] G-1 validation performed by operator (not by agent — the "operator-away-for-a-week" persona check)
- [ ] G-3 synthetic-PR test landed AND deleted in the same session (don't leave a fake demotion PR open)
- [ ] G-4 zero-diff proof attached to closing PR
- [ ] No goal marked as "not achieved" without explicit justification in the close note

### Dependencies

- **Sprint 1 (#166)**: runbook §1 references actual roll-up output examples; T2.6 cannot land until T1.3 + T1.7 are merged. Drift-gate workflow file can be authored in parallel (T2.4 independent of Sprint 1), but the synthetic-PR test (T2.5) needs the workflow to be wired before running.
- **External**: cycle-108 schema-guard workflow at `.github/workflows/cycle-108-schema-guard.yml` is the architectural template for T2.4 (verified at design time per SDD §11.1).

### Security Considerations

- **Trust boundaries**: PR body content is operator-controlled but accessed by the workflow via `gh pr view --json body`. Trailer detection uses anchored regex (`^Tier-Change-Evidence:` / `^Operator-Approval:`) to prevent body-text false positives.
- **External dependencies**: GitHub Actions runner uses `actions/checkout@v4` + `actions/setup-python@v5` (matches existing pinned workflows); no new actions introduced.
- **Sensitive data**: `Operator-Approval:` trailer is a deep-name signature (same pattern as cycle-108). No tokens, no API keys.
- **Branch protection**: workflow must be added to required status checks for `main` post-merge — documented in runbook but enforcement is operator action via GitHub UI (cannot self-set via PR).
- **R-3/R-11 defense**: yq-path projection isolates `workload_tier_map` subtree; reformatting elsewhere doesn't trigger trailer requirement (tested in T2.5 third scenario).

### Risks & Mitigation

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| R-11 (SDD §9.2): `.loa.config.yaml` is hot-touched (advisor_strategy, simstim, run_mode all live there). False-positive volume from drift gate is non-trivial | Med | Low | yq-path filter scopes to `.workload_tier_map` subtree only; T2.5 pins the false-positive contract in CI |
| R-3 (PRD): Drift gate trips on harmless reformatting | Med | Low | Same mitigation (yq-path projection); third bats scenario locks this in |
| R-4 (PRD): Operator forgets to update `workload_tier_map` when adding a new skill | Low | Low | T2.3 exhaustiveness audit script gates CI on this (Phase A informational; Phase B makes load-bearing) |
| R-9 (SDD §9.2): D-6 follow-up never picked up; Phase A surface ships frozen at low utility | Med | Low | T2.7 captures concrete D-6/D-7 tracker text in NOTES.md + recommends operator file follow-up issues |
| R-10 (SDD §9.2): `.claude/data/schemas/` is technically inside System Zone | Low | Low | Verified at design time as established convention (cycle-098 L1-L7, cycle-099, cycle-110 all add schemas here); not a violation per cycle-098 precedent. Document the precedent in PR description |
| Runbook drift from reality: docs ship referencing roll-up format that changes between Sprint 1 close and Sprint 2 close | Low | Med | Runbook authoring is the last technical task (T2.6); references are quotes from frozen Sprint 1 output, not invented examples |

### Success Metrics

- `tools/audit-workload-tier-map.sh` exits 0 against the seeded map (all dispatching skills covered)
- Drift gate's 3 synthetic-PR scenarios all pass their respective assertions (bats green)
- Runbook clears `/review-sprint` + `/audit-sprint` with zero CHANGES_REQUIRED (PRD AC #6)
- Zero post-cycle regressions in dispatch behavior verified by `tests/integration/test_dispatch_unchanged.bats` (carried from Sprint 1)
- D-6 and D-7 follow-up tracker text committed to NOTES.md (proof of cycle-handoff hygiene)
- E2E validation: all 4 goals (G-1 through G-4) checked with documented evidence in cycle close

---

## Risk Register

| ID | Risk | Sprint | Probability | Impact | Mitigation | Owner |
|----|------|--------|-------------|--------|------------|-------|
| R-1 | SDD-corrected: missing skill/phase attribution on 100% of envelopes (not "older lines" as PRD claimed) | 1 | High (known) | Med | Render `(unattributed)` honestly + coverage disclosure header; D-6 follow-up text in runbook | Sprint 1 |
| R-2 | Stale cost data in `model-config.yaml` for older models | 1 | Med | Low | `--cost-snapshot <git-ref>` flag; footer pins `model_config_ref` | Sprint 1 |
| R-3 | Drift gate false-positives on `.loa.config.yaml` reformatting | 2 | Med | Low | yq-path-aware diff scoped to `workload_tier_map`; T2.5 third scenario | Sprint 2 |
| R-4 | Operator forgets to add new dispatching skill to map | 2 | Low | Low | `tools/audit-workload-tier-map.sh` exhaustiveness check; phase A is informational | Sprint 2 |
| R-5 | Substrate degradation during data window confounds roll-up | 1 | Med | Med | Footer includes `substrate_health_window_summary` cross-ref to cycle-109 | Sprint 1 |
| R-6 | `final_model` bucketing leakage from deferred #900 work | 1 | Low | Med | Dual-attribution pattern (per-`final_model_id` AND per-`models_requested[]`) | Sprint 1 |
| R-7 | `(unattributed)` 100% reality makes FR-1 surface appear useless | 1 | High | Med | Coverage header + runbook §1 explanation; D-6 teed up | Sprint 1+2 |
| R-8 | Cost coverage ~35% (input-only) makes early cost numbers unreliable | 1 | Med | Med | `cost_coverage_pct` in footer; rows without data render `—` not `$0.00` | Sprint 1 |
| R-9 | D-6 follow-up never picked up | 2 | Med | Low | T2.7 captures concrete D-6/D-7 tracker text | Sprint 2 |
| R-10 | `.claude/data/schemas/` is inside System Zone | 1+2 | Low | Low | Verified as cycle-098+ established convention; document in PR | Sprint 1+2 |
| R-11 | `.loa.config.yaml` is hot-touched; false-positive volume on every config change | 2 | Med | Low | yq-path projection; T2.5 contract | Sprint 2 |

---

## Success Metrics Summary

| Metric | Target | Measurement Method | Sprint |
|--------|--------|-------------------|--------|
| Roll-up performance | < 5s for 30d / 100K envelopes | `tests/integration/test_economy_perf.bats` with `timeout 5` | 1 |
| Test coverage (unit + integration) | ≥ 35 tests passing | `pytest` + `bats` green | 1 |
| Schema conformance | 100% of fixture outputs validate | `jsonschema.validate(output, schema)` returns clean | 1 |
| Determinism | 3× run byte-identical | `tests/integration/test_economy_determinism.bats` | 1 |
| Secret-leak | 0 secrets in any output column | `tests/unit/test_economy_aggregation.py` AKIA injection | 1 |
| Dispatch invariance | 0 lines changed in dispatch path | `git diff` against `model-adapter.sh` + cheval providers | 1+2 |
| Workload-tier-map exhaustive | 100% of dispatching skills covered | `tools/audit-workload-tier-map.sh` exit 0 | 2 |
| Empirical calibrations pinned | ≥ 1 entry with `memory:` evidence_ref | `grep -c 'evidence_ref: "memory:' .loa.config.yaml` | 2 |
| Drift gate false-positive contract | 3/3 synthetic-PR scenarios pass | `tests/integration/workflow_drift_gate.bats` green | 2 |
| Runbook quality | `/review-sprint` + `/audit-sprint` clean | Manual operator skills invocation | 2 |
| E2E goal validation | All 4 PRD goals validated | Task 2.E2E checklist complete | 2 |

---

## Dependencies Map

```
Sprint 1 (data layer)                       Sprint 2 (config + gate + docs)
─────────────────────                       ───────────────────────────────
T1.1 schema ──┐
              │
T1.2 economy.py ─┬──> T1.3 bash shim ──> T1.7 /loa --economy flag
              │  │
T1.4 fixtures ┘  │
                 │
T1.5 unit tests <┘
T1.6 integration + perf + determinism
T1.8 NFR-Compat smoke ─────────────────────────────────────────┐
                                                               │
                                                               ▼
                       T2.1 tier-map schema ───────────> T2.2 seeded map
                                                               │
                                                               ▼
                       T2.3 exhaustiveness audit  <───────────┘
                                                               │
                       T2.4 drift workflow ──────────> T2.5 bats tests
                                                               │
                                  (Sprint 1 outputs)─────────> T2.6 runbook
                                                               │
                                                               ▼
                                                  T2.E2E goal validation
```

Critical path (SDD §8): T1.1 → T1.2 → T1.3 → T1.7 → T2.6 → T2.E2E.
Parallel-safe (SDD §8): T2.1+T2.2+T2.4 disjoint from T1.1+T1.2 file-wise; can pre-author T2.4 workflow during Sprint 1 (the synthetic-PR test T2.5 still gates on Sprint-1 merge).

---

## Appendix

### A. PRD Feature Mapping

| PRD FR | Sprint | Tasks | Status |
|--------|--------|-------|--------|
| FR-1: `tools/model-economy-roll-up.sh` | Sprint 1 | T1.1, T1.2, T1.3, T1.4, T1.5, T1.6 | Planned |
| FR-2: `/loa status --economy` | Sprint 1 | T1.7 | Planned |
| FR-3: Seeded `workload_tier_map` | Sprint 2 | T2.1, T2.2, T2.3 | Planned |
| FR-4: CI drift gate | Sprint 2 | T2.4, T2.5 | Planned |
| FR-5: Operator runbook | Sprint 2 | T2.6 | Planned |
| NFR-Perf-1 (<5s) | Sprint 1 | T1.6 (perf bats) | Planned |
| NFR-Sec-1 (no leak) | Sprint 1 | T1.5 (redaction unit test) | Planned |
| NFR-Quality-1 (floor) | Sprint 2 | T2.4, T2.5 (gate is the mechanism) | Planned |
| NFR-Determinism-1 | Sprint 1 | T1.6 (byte-identical bats) | Planned |
| NFR-Compat-1 (dispatch unchanged) | Sprint 1+2 | T1.8 smoke + T2.E2E re-verification | Planned |

### B. SDD Component Mapping

| SDD §  | Component | Sprint | Task | Status |
|--------|-----------|--------|------|--------|
| §3.2.1 | Roll-up JSON schema | 1 | T1.1 | Planned |
| §4.1.2 | `economy.py` aggregator | 1 | T1.2 | Planned |
| §4.1.1 | `model-economy-roll-up.sh` shim | 1 | T1.3 | Planned |
| §7.2 | Test fixtures (5) | 1 | T1.4 | Planned |
| §7.1 | Unit + integration tests | 1 | T1.5, T1.6 | Planned |
| §4.2.1 | `loa-status.sh --economy` extension | 1 | T1.7 | Planned |
| §9.3 | NFR-Compat-1 dispatch smoke | 1 | T1.8 | Planned |
| §4.3.1 | Tier-map schema | 2 | T2.1 | Planned |
| §4.3.2 | Seeded tier-map entries | 2 | T2.2 | Planned |
| §4.3.3 | Exhaustiveness audit tool | 2 | T2.3 | Planned |
| §4.4 | Drift gate workflow | 2 | T2.4 | Planned |
| §7.4 | Drift-gate synthetic-PR tests | 2 | T2.5 | Planned |
| §4.5 | Operator runbook | 2 | T2.6 | Planned |

### C. PRD Goal Mapping

| Goal ID | Goal Description | Contributing Tasks | Validation Task |
|---------|------------------|-------------------|-----------------|
| G-1 | Operator-readable cost roll-up — `/loa status --economy` surfaces 30d roll-up by `(skill, model)` with cost-per-clean-output, p95 latency, VQ-healthy % | Sprint 1: T1.1, T1.2, T1.3, T1.4, T1.5, T1.6, T1.7 | Sprint 2: T2.E2E |
| G-2 | Calibration capture — `workload_tier_map` codifies operator-memory calibrations with `evidence_ref` provenance | Sprint 2: T2.1, T2.2, T2.3, T2.6 | Sprint 2: T2.E2E |
| G-3 | Drift protection — CI gate rejects mutations without `Tier-Change-Evidence:` or `Operator-Approval:` trailer | Sprint 2: T2.4, T2.5, T2.6 | Sprint 2: T2.E2E |
| G-4 | Zero behavior regression — existing dispatch unchanged; map is informational this cycle | Sprint 1: T1.2, T1.6, T1.8 | Sprint 2: T2.E2E |

**Goal Coverage Check:**

- [x] All 4 PRD goals have at least one contributing task
- [x] All 4 goals have a validation step in Sprint 2 Task 2.E2E
- [x] No orphan tasks — every T1.x and T2.x annotated with at least one G-N contribution

**Per-Sprint Goal Contribution:**

- **Sprint 1**: G-1 (complete: data layer + CLI surface), G-4 (partial: zero-diff verified by T1.8 smoke)
- **Sprint 2**: G-2 (complete: seeded map + audit), G-3 (complete: drift gate + bats + runbook), G-4 (complete: post-Sprint-2 zero-diff verification in T2.E2E)
- **Sprint 2 T2.E2E**: end-to-end validation of all 4 goals against documented evidence

### D. Out-of-Scope Reminder (per PRD §6 + operator scope decision)

The following are explicitly NOT in this sprint plan:

- **D-6**: Wire `calling_primitive` through dispatch entrypoints (cheval.py, BB review path, adversarial-review, red-team-model-adapter). Reason: PRD scope was "Phase A only"; SDD §10.1 question 1 resolved to defer as Phase A.1. Tracker text in SDD §10.2 for cycle-handoff hygiene.
- **D-7**: Extend MODELINV writer to capture `tokens_output` post-flight. Reason: Phase A ships input-side cost only (35% coverage); output-side enrichment is Phase A.1. Tracker text in SDD §10.2.
- **Phase B**: Skills *consume* `workload_tier_map` at dispatch time. Reason: explicit per PRD §6 and operating principle 4 (one-way doors require operator approval).
- **Phase C**: Auto-demotion/promotion proposals + regression detector. Reason: needs N cycles of empirical data from this sprint's roll-up.
- **Cost dashboards / external observability**: Reason: explicit out-of-scope per #925.

---

*Generated by Sprint Planner Agent (`planning-sprints` skill) — 2026-05-17*
