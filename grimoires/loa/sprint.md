# Sprint Plan: Cycle-109 Multi-Model Substrate Hardening

**Version:** 1.0
**Date:** 2026-05-13
**Author:** Sprint Planner Agent (`planning-sprints` skill)
**PRD Reference:** `grimoires/loa/cycles/cycle-109-substrate-hardening/prd.md` v1.1
**SDD Reference:** `grimoires/loa/cycles/cycle-109-substrate-hardening/sdd.md` v1.0
**Operator-approval ledger:** `grimoires/loa/cycles/cycle-109-substrate-hardening/operator-approval.md`
  (C109.OP-1 cycle scope · C109.OP-2 KF auto-link deeper · C109.OP-3 full legacy delete · C109.OP-4 PRD-Flatline-override path 1 · C109.OP-5 SDD §10 defaults autonomous · C109.OP-6 substrate-key diagnostic · C109.OP-7 SDD-gate operator-override substrate-API-blocked)
**Reality ground-truth:** `grimoires/loa/reality/multimodel-substrate.md`
**Sprint Ledger global IDs:** sprint-159 .. sprint-163 (registered at end of this document)

---

## Executive Summary

Cycle-109 hardens the multi-model substrate — Loa's flagship feature and quality-gate foundation — by closing all 13 OPEN substrate issues in `reality/multimodel-substrate.md §9` and the four diagnostic clusters identified there:

- **Cluster A** large-doc empty-content (KF-002 layer-1)
- **Cluster B** v1.157.0 activated-default regressions
- **Cluster C** degraded-substrate semantics ("clean" verdict false-positives)
- **Cluster D** carry items

The cycle ships five sequential sprints (one per FR), under the operator-mandated "iron grip" — every Loa quality gate (Flatline review on PRD/SDD/sprint-plan, per-sprint implement → review → audit with circuit breaker, Bridgebuilder review per PR, post-PR audit per cycle-053 amendment, test-first commits, beads task lifecycle, KF cross-reference) active and enforced.

**Total Sprints:** 5
**Sprint Duration:** 1 - 1.5 weeks each (depth over speed — operator-explicit: "don't cut corners")
**Total Estimate:** 4-6 weeks engineering wall time; cycle ships when launch criteria met, not on calendar pressure
**Cycle-109 Sprint Ledger Range:** sprint-159 (Sprint 1) → sprint-163 (Sprint 5)

### Substrate-aware planning note

Per C109.OP-6 / C109.OP-7, cycle-109 Flatline reviews are currently degraded due to operator-side billing issues (Anthropic credit + OpenAI Responses-API tier-access). Sprint execution does NOT depend on those resolving. Sprint 3's activation regression suite (FR-3.5) and all per-sprint test surfaces are fixture-mocked via the cycle-099 sprint-1C curl-mock harness. Any CI gate that needs live provider calls is labeled `requires-substrate-billing` and runs as an advisory job, not a required gate, until the operator-side substrate billing is restored.

### Why this sequence

| Sprint | FR | Depends on | Why this order |
|--------|----|-----------:|----------------|
| 1 | FR-1 Capability foundation | none | All other sprints read `model-config.yaml` v3 capability fields |
| 2 | FR-2 Verdict-quality envelope | FR-1 | Envelope cross-references `capability_evaluation` (FR-1.4); consumers cannot ship verdict-classifier before producer is capability-aware |
| 3 | FR-3 Legacy sunset + activation regression suite | FR-1+FR-2 | Suite tests every consumer × every role × every dispatch path under `flatline_routing: true` — requires both new capability surface AND new verdict envelope to be testable |
| 4 | FR-4 Chunked review | FR-1+FR-2+FR-3 | Chunked dispatch is triggered by FR-1.3 pre-flight gate; chunked output carries FR-2 verdict envelope; activation suite covers chunked path |
| 5 | FR-5 Carry items + observability | all prior | Substrate-health CLI is a read-only consumer of MODELINV v1.3 envelopes (Sprint 1), verdict-quality emissions (Sprint 2), and chunked annotations (Sprint 4) |

---

## Sprint Overview

| # | Local | Global (Ledger) | Theme | Scope | Key Deliverables | Dependencies | Goals |
|---|------:|----------------:|-------|-------|------------------|--------------|-------|
| 1 | sprint-1 | sprint-159 | Capability-aware substrate foundation | LARGE (11 tasks) | model-config.yaml v3 schema · pre-flight gate · MODELINV v1.3 · KF-auto-link · ceiling-probe · baseline capture | None | G-1, G-2 (foundation), G-3 (partial), G-5 |
| 2 | sprint-2 | sprint-160 | Verdict-quality envelope + consumer contracts | LARGE (10 tasks) | verdict-quality.schema v1.0 · single classifier · 7-consumer refactor train · conformance matrix · single-voice semantics | Sprint 1 | G-3 (complete), G-1 (advance), G-5 |
| 3 | sprint-3 | sprint-161 | Legacy adapter sunset + activation regression suite | LARGE (11 tasks) | Cluster B fixes at cheval path · model-adapter.sh.legacy deleted · flatline_routing flag removed · 810-cell activation matrix CI gate · CLAUDE.md rollback rewritten | Sprint 1+2 | G-4 (complete), G-1 (substantial), G-5 |
| 4 | sprint-4 | sprint-162 | Hierarchical / chunked review | LARGE (10 tasks) | chunking package · file-level chunker · aggregator with conflict resolution · cross-chunk pass · streaming-with-recovery · IMP-014 thresholds · #866/#823 fixtures | Sprint 1+2+3 | G-2 (complete), G-1 (advance), G-5 |
| 5 | sprint-5 | sprint-163 | Carry items + substrate observability + cycle close | LARGE (10 tasks) | #874/#875/#870 fixed · `loa substrate health` CLI · health thresholds · `loa substrate recalibrate` · cron journal · cycle-close baseline + E2E goal validation | All prior | G-1 (close), G-2 (close), G-5 (close) + E2E |

**Total tasks: 52** across 5 sprints (target: ≤10 per sprint; every sprint at LARGE limit because cycle is deliberately invested-in per operator). Beads task graph derives directly from SDD §5.1.3 / §5.2.3 / §5.3.3 / §5.4.5 / §5.5.4 with one additional sprint-close debrief task per sprint.

### Cycle-wide quality gates (apply to EVERY sprint — per PRD §13)

These are NOT separate tasks; they are non-negotiable per-PR / per-sprint preconditions enforced by Loa harness. Listed here so engineers see them at the top:

- [ ] `/run sprint-N` — never direct `/implement` (PRD §13.4)
- [ ] Test-first: PR commit-1 = failing tests; commit-2+ = implementation
- [ ] Bridgebuilder review on the PR; iterate until plateau (PRD §13.4)
- [ ] Post-PR audit per cycle-053 amendment (PRD §13.4, §13.5)
- [ ] Implement → review → audit cycle with circuit breaker
- [ ] Beads task lifecycle: `created → in-progress → closed`; no orphan tasks
- [ ] KF cross-reference in PR body when sprint addresses KF entry
- [ ] MODELINV v1.3 envelope emitted for every cheval call during sprint testing
- [ ] CODEOWNERS auto-assignment → @janitooor primary reviewer
- [ ] No `--no-verify`, no `--no-gpg-sign` (project safety hooks)
- [ ] Operator-approval marker `C109.OP-N` for each substrate-changing sprint (cycle-108 T3.A.OP precedent)
- [ ] Sprint debrief filed at `grimoires/loa/cycles/cycle-109-substrate-hardening/sprint-N-debrief.md`

### Circuit-breaker conditions (PRD §13.7)

- 3 consecutive sprint failures → HALT, await `/run-resume`
- Audit-gate failure → HALT, await operator review
- Substrate degradation observed during cycle execution (irony case — multi-model fails on its own audit) → HALT, fall back to single-model BB with operator notification

### Forbidden shortcuts (PRD §13.8 — "iron grip")

- ❌ Skipping Flatline review on PRD/SDD/sprint-plan
- ❌ Direct `/implement` without `/run sprint-N` wrapper
- ❌ Direct PR merge without Bridgebuilder + post-PR audit
- ❌ Committing without test-first
- ❌ Using `/bug` to bypass cycle scope on feature work
- ❌ `TaskCreate` as a replacement for beads task tracking
- ❌ Manual `.run/` edits

Violations are process incidents → record in `grimoires/loa/NOTES.md` and route through `/feedback` upstream.

---

## Sprint 1 (sprint-159): Capability-Aware Substrate Foundation

**FR:** FR-1 (PRD §5 FR-1; SDD §5.1)
**Scope:** LARGE (11 tasks)
**Operator-approval ref:** C109.OP-1 (cycle scope) + C109.OP-2 (KF auto-link deeper variant) + C109.OP-5 (SDD §10 defaults) — substrate-changing sprint; will land C109.OP-S1 sign-off marker before merge

### Sprint Goal

> Extend `model-config.yaml` with capability fields and a cheval pre-flight gate that consults them before dispatch, so every downstream sprint can read capability data and so the operator's known-failure observations flow into substrate behavior automatically.

### Deliverables

- [ ] `model-config.yaml` v3 schema with 6 new fields (`effective_input_ceiling`, `reasoning_class`, `recommended_for`, `failure_modes_observed`, `ceiling_calibration`, `streaming_recovery` reserved-for-Sprint-4) — all models migrated with IMP-008 conservative defaults
- [ ] Cheval pre-flight gate at `cheval.py::_lookup_max_input_tokens` extension — emits typed exit 7 (`ContextTooLarge`) preemptively when input > ceiling
- [ ] MODELINV v1.3 envelope additive over v1.2 — adds `capability_evaluation` field; existing v1.2 logs parse and verify-signatures unchanged
- [ ] `tools/kf-auto-link.py` — KF-ledger watcher implementing IMP-001 severity-to-downgrade mapping with IMP-002 operator overrides and IMP-005 parsing policy
- [ ] `tools/ceiling-probe.py` — binary-search empirical ceiling protocol per cycle-104 T2.10; 5 reasoning-class models calibrated at cycle-109 ship time
- [ ] `tools/cycle-baseline-capture.sh` — captures all 7 PRD §3.4 baselines to `grimoires/loa/cycles/cycle-109-substrate-hardening/baselines/`; idempotent; signed via cycle-098 audit envelope
- [ ] CI workflow `.github/workflows/kf-auto-link.yml` runs on `known-failures.md` changes; updates `model-config.yaml` and opens PR for operator review
- [ ] Codegen byte-equality preserved across bash/python/TS for v3 schema additions (cycle-099 sprint-1D cross-runtime-diff gate green)

### Acceptance Criteria

- [ ] All models in `model-config.yaml` carry the 6 new fields, populated correctly (IMP-008 defaults where empirical data absent) — verified by schema validation in CI
- [ ] Cheval pre-flight gate emits typed exit 7 for inputs > ceiling — bats coverage one case per model class (reasoning + non-reasoning) — verified by `tests/unit/cheval-preflight-gate.bats`
- [ ] MODELINV v1.3 schema lands additively over v1.2 — existing `.run/model-invoke.jsonl` entries continue parsing; hash-chain signatures verify (NFR-Rel-4) — verified by `tests/unit/modelinv-v1.3-backcompat.bats` + replay against last-30d log
- [ ] KF-auto-link integration test: seeds a fake KF-NNN referencing `claude-opus-4-7` with status `OPEN`, expects `recommended_for: []` after run; expects `failure_modes_observed: ["KF-NNN"]` populated — `tests/integration/kf-auto-link.bats`
- [ ] **[IMP-001]** Each row of the severity-to-downgrade table (`OPEN`, `RESOLVED`, `RESOLVED-VIA-WORKAROUND`, `RESOLVED-STRUCTURAL`, `LATENT`/`LAYER-N-LATENT`, `DEGRADED-ACCEPTED`) covered by ≥1 bats fixture — `tests/unit/kf-auto-link-mapping.bats`
- [ ] **[IMP-002]** Operator-override mechanism: precedence rules (override > auto-link > default), `effective_until` expiry honored, CI block on missing `authorized_by` not in `OPERATORS.md` — `tests/integration/kf-auto-link-overrides.bats`
- [ ] **[SKP-004]** Conditional-precedence rejection paths: each rejection condition (missing/expired/excessive `effective_until`, empty/invalid `kf_references[]`, OPEN CRITICAL KF without `break_glass`, `break_glass.expiry > now()+24h`, unresolvable `audit_event_id`) has a bats fixture verifying rejection + stderr warning + KF auto-decision falls through — `tests/integration/kf-override-conditional.bats`
- [ ] **[SKP-004]** Positive-control: well-formed break-glass override IS accepted; signed L4 trust event emitted; Ed25519 signature validates; hash-chain integrity holds — `tests/integration/kf-override-breakglass.bats`
- [ ] **[SKP-003]** `--ceiling-override` break-glass family: missing operator/reason/expiry → exit 9; operator not in `OPERATORS.md::acls.ceiling-override-authorized` → exit 9; expiry > now()+7d → exit 9; successful override emits signed `cheval.ceiling_override` audit event to `.run/cheval-overrides.jsonl` — `tests/integration/cheval-ceiling-override.bats`
- [ ] **[SKP-003]** OPERATORS.md `acls.ceiling-override-authorized` ACL defined as Sprint 1 deliverable; cycle-098 operator-identity primitive resolves operator slug against ACL membership — `tests/unit/operator-acl-resolution.bats`
- [ ] **[v5 SKP-004 HIGH]** `recommended_for` migration populates allow-all default `[review, audit, implementation, dissent, arbiter]` (NOT `[]`) for any model lacking explicit per-role evidence; conformance fixtures: migrated-no-evidence, kf-auto-link-removes-review, operator-restores-review, manual-empty-list (exit 8), partial-list — `tests/integration/recommended-for-semantics.bats`
- [ ] **[IMP-005]** Parsing-policy fixtures all produce documented outcome: malformed YAML → exit non-zero with line reference; unknown status → warning + skip auto-link; missing model → no-op skip; multi-model → per-model independent decisions; duplicate KF-ID → exit non-zero — `tests/unit/kf-auto-link-parsing-policy.bats`
- [ ] **[IMP-007]** Ceiling-probe protocol shipped (`tools/ceiling-probe.py`) + 5 known reasoning-class models calibrated empirically at cycle ship time (claude-opus-4.x + gpt-5.5-pro + gemini-3.1-pro + 2 operator-selected); remaining models flagged for follow-up in baselines artifact
- [ ] **[IMP-008]** Conservative-default migration applied to all models lacking empirical data; documented in Sprint 1 PR body
- [ ] Overlay-override conflict lint (IMP-002 §3.5.2 conflict-surfacing): when `.loa.config.yaml` and runtime model-config.yaml overlay disagree, lint surfaces the conflict on PRs touching either — `tests/unit/overlay-override-conflict.bats`
- [ ] Codegen byte-equality preserved across bash/python/TS for new fields — `cross-runtime-diff.yml` CI gate green
- [ ] Baseline capture run at cycle kickoff produces `baselines/*.json` files (issue-counts, kf-recurrence, clean-fp-rate, legacy-loc, modelinv-coverage, issue-rate, operator-self-rating) — TRACKED in git

### Technical Tasks

> Each task is a beads task; mirrors SDD §5.1.3 graph. Test-first: commit-1 lands failing bats; commit-2+ lands implementation.

- [ ] **Task 1.1** (T1.1): Land model-config-v3 JSON Schema (`.claude/data/schemas/model-config-v3.schema.json`) + schema-validation bats; failing first → **[G-1, G-2]**
- [ ] **Task 1.2** (T1.2): Extend `tools/migrate-model-config.py` v2→v3 + conservative defaults per IMP-008; all existing models migrated → **[G-1, G-3]**
- [ ] **Task 1.3** (T1.3): Cheval pre-flight gate extension at `cheval.py::_lookup_max_input_tokens` [CODE:cheval.py:285]; typed exit 7 emission; reasoning-class + not-recommended-for warning → **[G-1, G-3]**
- [ ] **Task 1.4** (T1.4): MODELINV envelope v1.3 additive (`capability_evaluation` field) + backwards-compat replay tests on last-30d log → **[G-1, G-3]**
- [ ] **Task 1.5** (T1.5): KF-auto-link script (`tools/kf-auto-link.py`) implementing IMP-001 severity-mapping table + IMP-005 parsing policy → **[G-1, G-2]**
- [ ] **Task 1.6** (T1.6): Operator-override schema in `.loa.config.yaml::kf_auto_link.overrides` + precedence + `.run/kf-auto-link.jsonl` audit log + CI block on missing `authorized_by` (IMP-002) → **[G-1, G-5]**
- [ ] **Task 1.7** (T1.7): Ceiling-probe protocol (`tools/ceiling-probe.py`) per cycle-104 T2.10 binary search; calibrate 5 reasoning-class models at cycle ship; flag rest for follow-up (IMP-007) → **[G-1, G-2]**
- [ ] **Task 1.8** (T1.8): Codegen regen (`gen-bb-registry.ts` + `generated-model-maps.sh`) + cross-runtime byte-equality CI gate green for v3 schema (NFR-Codegen-1) → **[G-1, G-5]**
- [ ] **Task 1.9** (T1.9): Overlay-override conflict lint (`tools/lint-overlay-override-conflict.py`) for SDD §3.5.2 conflict surfacing → **[G-1, G-5]**
- [ ] **Task 1.10** (T1.10): Baseline-capture script (`tools/cycle-baseline-capture.sh`) per PRD §3.4 — emits 7 baseline JSON files; signed via cycle-098 audit envelope → **[G-1, G-2, G-5]**
- [ ] **Task 1.11** (T1.11): Sprint-1 debrief at `grimoires/loa/cycles/cycle-109-substrate-hardening/sprint-1-debrief.md`; KF cross-reference summary; operator-approval marker C109.OP-S1 → **[G-5]**

### Dependencies

- **None** (foundation sprint)
- **Open external blockers**: none — substrate-billing degradation (C109.OP-6 / C109.OP-7) does NOT block Sprint 1; KF-auto-link CI test seeds a fake KF and runs offline; ceiling-probe at ship-time uses operator-funded budget already verified working for gpt-4o-mini + gpt-5.5 via C109.OP-6 probes

### Security Considerations

- **Trust boundaries**: `known-failures.md` is TRACKED, git-managed — KF-auto-link reads it as YAML/markdown (parsed, never eval'd) per NFR-Sec-2
- **Operator-override authorization**: `kf_auto_link.overrides[].authorized_by` MUST resolve via `OPERATORS.md` (cycle-098 operator-identity primitive); CI blocks PRs touching `overrides` block where `authorized_by` is unknown
- **External dependencies**: no new dependencies — all work uses existing Python, bash, TypeScript, yq, jq, gh tooling already in substrate
- **Sensitive data**: capability-evaluation pre-flight gate MUST NOT leak prompt content to logs — only input size, role, model-id, decision — enforced by `capability_evaluation` schema (NFR-Sec-1)
- **Audit trail**: KF-auto-link decisions logged to `.run/kf-auto-link.jsonl` with `before_state`, `after_state`, `reason`, `authorized_by`, `kf_id` (NFR-Aud-2)

### Risks & Mitigation

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Capability data is wrong (effective_input_ceiling set too high or low) (R-1) | Med | Med | Empirical probe at cycle ship time for 5 reasoning-class models; KF auto-link feedback loop self-corrects within 1 KF entry per model; Sprint 4 streaming-with-recovery defensive fallback |
| KF-auto-link over-degrades (false-positive degradation) (R-7) | Low | Med | Severity mapping documented per IMP-001; degradations reversible (KF resolves → re-upgrade); operator can manual-override in `.loa.config.yaml` (IMP-002); CI surfaces every override decision |
| Codegen drift between bash/python/TS (NFR-Codegen-1 violation) | Low | High | `cross-runtime-diff.yml` CI gate (cycle-099 sprint-1D precedent) blocks merge on any byte mismatch |
| MODELINV v1.3 break existing replay logs (R-5) | Low | High | v1.3 schema is additive only; existing field positions preserved; backwards-compat bats test replays last-30d log before merge |
| Empirical probe fails to converge for some model | Low | Med | Conservative-default (FR-1.2) used; KF entry filed for follow-up; tagged as unverified assumption in PRD §11.4 |

### Success Metrics

- All models in `model-config.yaml` declare all 6 new fields (count via `yq '.models[] | keys | contains(["effective_input_ceiling", "reasoning_class", "recommended_for", "failure_modes_observed", "ceiling_calibration"])'`)
- MODELINV envelope coverage ≥0.95 by end of Sprint 1 (NFR-Aud-1; raised from cycle-108 baseline 0.90) — measured via `tools/modelinv-coverage-audit.py --window 7d`
- Cheval pre-flight gate overhead <50ms per dispatch (NFR-Perf-1) — measured via bats microbenchmark
- 5 reasoning-class models empirically calibrated (sample_size ≥ 25 each)
- KF-auto-link script idempotent: running twice on same ledger state produces byte-identical `model-config.yaml` (NFR-Rel-3)
- 7 baseline JSON files persisted in `grimoires/loa/cycles/cycle-109-substrate-hardening/baselines/`

---

## Sprint 2 (sprint-160): Verdict-Quality Envelope + Consumer Contracts

**FR:** FR-2 (PRD §5 FR-2; SDD §5.2)
**Scope:** LARGE (10 tasks)
**Operator-approval ref:** C109.OP-1 + C109.OP-5 — substrate-changing sprint; will land C109.OP-S2 sign-off marker before merge

### Sprint Goal

> Every substrate output carries a first-class `verdict_quality` envelope describing voices succeeded/dropped, chain health, and confidence — and `status: clean | APPROVED` is **definitionally impossible** when verdict quality is degraded (NFR-Rel-1), so [ISSUE:#807] / [ISSUE:#809] class regressions cannot recur.

### Deliverables

- [ ] `.claude/data/schemas/verdict-quality.schema.json` v1.0 with classification contract (`APPROVED | DEGRADED | FAILED`) per FR-2.3
- [ ] **Single canonical classifier**: `loa_cheval.verdict.quality` Python module + bash twin (shells out — never duplicates logic; SDD §5.2.1 architecture decision)
- [ ] 7 substrate consumers refactored in dependency order per IMP-004 table: cheval → flatline-orchestrator → adversarial-review → BB cheval-delegate → flatline-readiness → red-team-pipeline → post-PR triage
- [ ] FR-2.7 consumer-contract conformance test: CI matrix has one job per consumer; emitting `clean` on `voices_succeeded < voices_planned` fails CI
- [ ] FR-2.8 operator-facing PR-comment summary surfaces verdict_quality at top of every BB / FL / RT comment
- [ ] FR-2.9 single-voice call semantics (`single_voice_call: true` flag suppresses "100% agreement of 1 voice" false-positive)
- [ ] [ISSUE:#807], [ISSUE:#809], [ISSUE:#868], [ISSUE:#805], and **cycle-109 PRD-review trajectory** (Opus voice-drop with self-report `confidence: full`) added to conformance fixture corpus as canonical "must-not-recur" regressions

### Acceptance Criteria

- [ ] Schema lands at `.claude/data/schemas/verdict-quality.schema.json` and validates against JSON Schema Draft 2020-12
- [ ] **[SKP-001]** Schema declares `status: APPROVED|DEGRADED|FAILED` as REQUIRED + `additionalProperties: false`; producer-emitted envelope WITHOUT `status` fails the schema gate at emission time — `tests/unit/verdict-quality-schema.bats`
- [ ] **[SKP-001]** Consumer-lint (`tools/lint-verdict-consumers.py`) lands in Sprint 2; greps every consumer in IMP-004 table for status-derivation logic outside the canonical classifier; CI job `verdict-consumer-lint` fails on any violation — `tests/unit/verdict-consumer-lint.bats`
- [ ] **[SKP-002]** Every `voices_dropped[]` entry carries `blocker_risk` (`unknown|low|med|high`); cycle-109 PRD-review fixture (Opus voice-drop, security-touching sprint-kind) classifies the dropped entry as `blocker_risk: med` and the envelope as `status: DEGRADED` — `tests/integration/voices-dropped-blocker-risk.bats`
- [ ] **[SKP-002]** Conformance: any envelope with `voices_dropped[].blocker_risk == "high"` and `status == "APPROVED"` is REJECTED by classifier (auto-promotes to FAILED); fixture-driven assertion — `tests/integration/blocker-risk-status-coherence.bats`
- [ ] **[SKP-002]** `--blocker-risk-override <enum>` cheval flag wired; missing reason → exit 2; override logged to MODELINV envelope (`blocker_risk_override`); operator slug recorded — `tests/integration/cheval-blocker-risk-override.bats`
- [ ] **[v5 SKP-001 CRITICAL]** `chunks_dropped > 0` promotes envelope to FAILED unless `_truncation_waiver_applied: true` (set only by §4.1.3 break-glass path); `--truncation-waiver` requires operator + ≥16-char reason + scope + ≤24h expiry; signed `cheval.truncation_waiver` audit event emitted — `tests/integration/truncation-waiver.bats`
- [ ] **[v5 SKP-002 CRITICAL]** `consensus_outcome: consensus|impossible` REQUIRED in schema (replaces private `_consensus_impossible`); classifier sets `impossible` after cross-voice contradiction analysis; producer-emitted envelope without `consensus_outcome` fails schema gate — `tests/integration/consensus-outcome.bats`
- [ ] **[v5 SKP-003 CRITICAL]** Error envelopes (§6.2; one per exit code from §6.1) ALL carry `verdict_quality.status`; `tools/lint-verdict-producers.py` greps for any emission path outside `emit_envelope_with_status` and fails CI — `tests/integration/error-envelope-status.bats` + `tests/unit/verdict-producer-lint.bats`
- [ ] **[v5 SKP-005 HIGH]** Producer-side `validate_invariants` runs BEFORE `compute_verdict_status`; rejects voices_planned<1, voices_succeeded outside [0, planned], len(voices_dropped) ≠ planned-succeeded, duplicate dropped voices; raises `EnvelopeInvariantViolation` — `tests/unit/envelope-invariants.bats`
- [ ] **[v5 SKP-002/SKP-006 HIGH]** Downward `--blocker-risk-override` requires `--override-operator` (ACL `blocker-risk-override-authorized`) + ≥16-char reason + ≤7d expiry + signed `cheval.blocker_risk_override` audit event; upward overrides unrestricted — `tests/integration/blocker-risk-override-direction.bats`
- [ ] **[v6 SKP-001 CRITICAL]** `truncation_waiver_applied: boolean` schema-declared (REQUIRED with default false); waiver path no longer relies on private fields incompatible with `additionalProperties: false` — `tests/integration/truncation-waiver-schema.bats`
- [ ] **[v6 SKP-001 CRITICAL — consensus_outcome algorithm]** §3.2.2.1 algorithm shipped: `loa_cheval.verdict.consensus.classify_consensus` Python module + bash twin; per-finding cross-voice comparison; contradiction threshold; edge cases for single-voice and structural-class findings — `tests/integration/consensus-outcome-algorithm.bats`
- [ ] **[v6 SKP-002 CRIT — blocker_risk reproducibility, operator-overridden into AC per C109.OP-10]** `loa_cheval.verdict.blocker_risk.compute()` Python canonical lands with documented input weights + golden fixtures regenerable from inputs; bash twin shells out; numeric outputs deterministic across runs — `tests/unit/blocker-risk-golden-fixtures.bats`
- [ ] **[v6 SKP-002 HIGH — §4.4 dead-code closure]** `med` blocker_risk check is REACHABLE — fixture asserts envelope with succeeded < planned AND voices_dropped contains med entry classifies as DEGRADED (not falls through to APPROVED) — `tests/unit/verdict-helper-med-reachable.bats`
- [ ] **[v6 SKP-003 CRITICAL]** `voices_succeeded_ids: string[]` schema field REQUIRED; `validate_invariants` enforces (a) len matches voices_succeeded, (b) entries unique, (c) NO overlap with voices_dropped[].voice — `tests/integration/voices-succeeded-ids.bats`
- [ ] **[v6 SKP-003 HIGH — unknown→APPROVED safety gap, operator-overridden into AC per C109.OP-10]** Sprint 2 ships `.loa.config.yaml::blocker_risk_override.unknown_treated_as_med_until_priors: <N>` toggle; when set, classifier treats `unknown` as `med` until ≥N priors exist for (voice, sprint-kind) combo — `tests/integration/blocker-risk-hardening-mode.bats`
- [ ] **[v6 SKP-005 HIGH]** Chain-walk fallthrough on `recommended_for` mismatch surfaces `voices_dropped[]` entry with `reason: NoEligibleAdapter` and `blocker_risk: med` default; classifier returns DEGRADED minimum (FAILED if dropped role was primary safety voice) — `tests/integration/chain-walk-degrade.bats`
- [ ] **[v6 SKP-006 HIGH]** `recommended_for: []` kill-switch returns exit 11 (NoEligibleAdapter), NOT exit 8 (InteractionPending); cross-checked against §6.1 exit code table — `tests/unit/exit-code-collision-check.bats`
- [ ] Every substrate output (all 7 consumers in FR-2 table) carries `verdict_quality` envelope — verified by `tests/integration/verdict-quality-coverage.bats` (one assertion per consumer)
- [ ] Conformance test: emitting `clean` / `APPROVED` on `voices_succeeded < voices_planned` **fails CI** — `tests/integration/verdict-quality-conformance.bats` (one job per consumer in IMP-004 table)
- [ ] PR-comment summary surfaces `verdict_quality` at top of comment: `✓ APPROVED — 3/3 voices, chain ok, confidence high` or `⚠ DEGRADED — 2/3 voices (gpt-5.2 dropped: empty-content), chain ok, confidence med` or `❌ FAILED — chain exhausted; verdict unsafe`
- [ ] [ISSUE:#807] / [ISSUE:#809] / [ISSUE:#868] / [ISSUE:#805] reproduction fixtures correctly classify as `DEGRADED` or `FAILED` per SDD §5.2.4 table
- [ ] **[IMP-004]** Each consumer in FR-2 table refactored in declared dependency order; per-consumer commit (or batched PR) traceable in cycle-109 git history
- [ ] **[IMP-004]** Cycle-109 PRD-review trajectory (the run that classified `confidence: full` while Opus voice dropped — `grimoires/loa/a2a/flatline/cycle-109-prd-review.json`) added to conformance fixture corpus
- [ ] NFR-Rel-1: no substrate output emits `status: clean | APPROVED` when verdict_quality is degraded — enforced by consumer-contract test
- [ ] NFR-Sec-4: verdict-quality envelope NEVER carries credentials, endpoint URLs, or API keys — schema rejects unknown fields

### Technical Tasks

> Mirrors SDD §5.2.3 beads graph.

- [ ] **Task 2.1** (T2.1): Land `verdict-quality.schema.json` v1.0 + JSON Schema validation tests (test-first) → **[G-3, G-5]**
- [ ] **Task 2.2** (T2.2): Implement `loa_cheval.verdict.quality` (Python canonical) + bash twin (`lib/verdict-quality.sh` shells out) + classification contract tests for FR-2.3 — every state-transition row covered → **[G-3]**
- [ ] **Task 2.3** (T2.3): `cheval.cmd_invoke` emits `verdict_quality` on every call (PRODUCER #1 — IMP-004 dependency order) → **[G-3, G-1]**
- [ ] **Task 2.4** (T2.4): `flatline-orchestrator.sh` consumes envelope + writes `final_consensus.json` (CONSUMER #2 — highest-volume canary) → **[G-3]**
- [ ] **Task 2.5** (T2.5): `adversarial-review.sh` consumes envelope + `adversarial-{review,audit}.json` (CONSUMER #3 — security-critical, closes #807) → **[G-3, G-1]**
- [ ] **Task 2.6** (T2.6): BB `cheval-delegate.ts` consumes + renders PR-comment header (CONSUMER #4 — operator-facing UI; ships after backend stable) → **[G-3]**
- [ ] **Task 2.7** (T2.7): `flatline-readiness.sh` (#5) + `red-team-pipeline.sh` (#6) + `post-pr-triage.sh` (#7) — finish IMP-004 table → **[G-3, G-1]**
- [ ] **Task 2.8** (T2.8): Conformance test matrix (FR-2.7) — one CI job per consumer × per failure fixture (#807 / #809 / #868 / #805 / cycle-109 PRD-review) → **[G-3, G-5]**
- [ ] **Task 2.9** (T2.9): Single-voice call semantics (FR-2.9 / IMP-010) — `single_voice_call: true` flag emitted when `voices_planned == 1`; consumers treat consensus-fields as non-applicable → **[G-3]**
- [ ] **Task 2.10** (T2.10): Sprint-2 debrief + operator-approval marker C109.OP-S2 → **[G-5]**

### Dependencies

- **Sprint 1 (FR-1)**: verdict envelope cross-references `capability_evaluation` from MODELINV v1.3; consumers cannot ship verdict-classifier before producer is capability-aware
- **External blockers**: none for sprint execution; SDD §3.2.3 IMP-004 table ordering means consumer refactors land in 6 sequential commits (or batched into 2-3 PRs)

### Security Considerations

- **Trust boundaries**: verdict-quality envelope is consumed by operator-facing PR comments — schema validation rejects unknown fields; `rationale` text is plaintext (no eval / interpolation surface)
- **Sensitive data**: NFR-Sec-4 — envelope schema rejects credentials, endpoint URLs, API keys at the schema layer; bats fixture asserts a forged envelope containing `api_key` field is rejected by validator
- **Single source of truth**: classifier logic lives ONLY in `loa_cheval.verdict.quality` Python module — bash twin shells out; consumers MUST NOT reimplement (drift = recurrence of #807 class)

### Risks & Mitigation

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Verdict-quality envelope breaks existing consumer integrations (R-3) | Low | Med | Envelope is additive; existing fields preserved; per-consumer refactor in declared IMP-004 order; conformance test catches divergence pre-merge |
| Consumer silently ignores new field (re-emits `clean` on degraded) | Med | High | FR-2.7 conformance matrix (one CI job per consumer) fails on this exact pattern — direct enforcement of NFR-Rel-1 |
| Classification semantics drift across consumers (each rolls own classifier) | Med | High | SDD §5.2.1 architecture decision: single Python canonical + bash twin shells out — drift impossible by construction |
| Cycle-109 PRD-review trajectory (Opus voice-drop) recurs with new envelope | Low | High | That exact trajectory is now a canonical regression fixture in conformance corpus per PRD AC; recurrence = CI failure |

### Success Metrics

- 7/7 consumers in IMP-004 table emit verdict_quality envelope (CI assertion)
- 5/5 failure-mode reproductions in SDD §5.2.4 table classify correctly (CI assertion)
- G-3 substrate "clean" verdict accuracy = 100% — zero `clean` emissions when `voices_succeeded < voices_planned` (replay against last-30d audit log = zero false-positives by end of Sprint 2)
- Conformance CI matrix wall-clock <10 min (one job per consumer)

---

## Sprint 3 (sprint-161): Legacy Adapter Sunset + Activation Regression Suite

**FR:** FR-3 (PRD §5 FR-3; SDD §5.3)
**Scope:** LARGE (11 tasks)
**Operator-approval ref:** C109.OP-3 (full legacy delete authorized) + C109.OP-1 + C109.OP-5 — DESTRUCTIVE substrate-changing sprint; **requires explicit per-PR operator sign-off** before merging the destructive commit D (file deletion); marker C109.OP-S3 will land in operator-approval.md immediately before Commit D

### Sprint Goal

> Fully delete `.claude/scripts/model-adapter.sh.legacy` (1,081 LOC) and all consumer branch paths conditional on `is_flatline_routing_enabled`. Build a CI-required activation regression suite (810 fixture combinations: 9 consumers × 5 roles × 6 response classes × 3 dispatch paths) so every Cluster B regression class is impossible by construction in future cycles.

### Deliverables

- [ ] Inventory of all references to `model-adapter.sh.legacy` (FR-3.1 grep pass; ~10-15 sites)
- [ ] 4 v1.157.0 Cluster B regression issues fixed AT CHEVAL PATH, not by patching legacy: #864 + #863 + #793 + #820 — each closed with PR-body KF cross-reference
- [ ] `.claude/scripts/model-adapter.sh.legacy` deleted (1,081 LOC → 0)
- [ ] All `is_flatline_routing_enabled` branches removed from consumers (`model-adapter.sh:67`, `flatline-orchestrator.sh:476`, `adversarial-review.sh` equivalent)
- [ ] `hounfour.flatline_routing` config key removed entirely from `.loa.config.yaml.example` + reading sites
- [ ] `.github/workflows/activation-regression.yml` — 810-cell CI matrix; runs in parallel <15 min wall-time; **becomes a required CI gate immediately after this sprint lands**
- [ ] `.claude/loa/CLAUDE.loa.md` Multi-Model Activation section rewritten: rollback = `git revert`, NOT runtime flag flip (FR-3.6 / FR-3.7)
- [ ] Pre-delete safety baseline archived: synthetic test at commit C records last-known-good legacy-path baseline to `baselines/legacy-final-baseline.json` for forensic comparison
- [ ] All 4 Cluster B GitHub issues closed: #864, #863, #793, #820

### Acceptance Criteria

- [ ] `git ls-files | grep model-adapter.sh.legacy` returns empty (verifies G-4: legacy LOC = 0)
- [ ] All 4 Cluster B issues closed at HEAD: `gh issue view 864 793 863 820 --json state` all return `CLOSED`
- [ ] Activation regression suite runs in CI on every PR touching substrate code: 810 cells (9 × 5 × 6 × 3); matrix-jobs parallel; <15 min full matrix
- [ ] `hounfour.flatline_routing` is REMOVED OR fully informational (audit-log-only no-runtime-effect) — SDD recommendation: removed entirely
- [ ] `CLAUDE.md` updated to reflect new rollback model: "rollback = `git revert` of cycle-109 merge commits"; no runtime-flag rollback guidance
- [ ] **[IMP-009]** All matrix dimensions explicit and tested:
  - Consumer: BB, FL, RT, /bug, /review-sprint, /audit-sprint, flatline-readiness, red-team-pipeline, post-PR triage (9)
  - Substrate role: review, dissent, audit, implementation, arbiter (5)
  - Provider response class: success, empty-content (KF-002), rate-limited, chain-exhausted, provider-disconnect (#774), context-too-large-preempt (6)
  - Dispatch path: single + chunked-2-chunk + chunked-5-chunk (3)
- [ ] Verdict-quality outcome cross-checked against expected per fixture combo: APPROVED, DEGRADED, FAILED
- [ ] Fixture-driven via cycle-099 sprint-1C curl-mock harness — labeled `requires-substrate-billing: false` (mock-only; works without Anthropic/OpenAI live access)
- [ ] Per-commit CI green: every commit in the 6-commit SDD §5.3.1 sequence (A → B → C → D → E → F) passes CI in isolation
- [ ] CI gate `activation-regression` becomes REQUIRED in branch protection rules immediately after Sprint 3 merge (operator action; tracked as task)

### Technical Tasks

> Mirrors SDD §5.3.3 beads graph and §5.3.1 commit sequence.

- [ ] **Task 3.1** (T3.1): Test scaffolding + 810-cell matrix harness lands in `tests/integration/activation-path/` (commit A; test-first; legacy still present; matrix skips until wired) → **[G-1, G-4, G-5]**
- [ ] **Task 3.2** (T3.2): Fix [ISSUE:#864] at cheval path (Cluster B legacy CLI crash) — verify cheval path handles CLI models correctly → **[G-1, G-4]**
- [ ] **Task 3.3** (T3.3): Fix [ISSUE:#863] at cheval/flatline-orchestrator level (cost-map empty, GPT/Gemini orchestrator failures) → **[G-1, G-4]**
- [ ] **Task 3.4** (T3.4): Fix [ISSUE:#793] (flatline-orchestrator validator accepts cheval-headless pin form) → **[G-1, G-4]**
- [ ] **Task 3.5** (T3.5): Fix [ISSUE:#820] (env loading, alias recommendation, scoring parser at FL level) → **[G-1, G-4]**
- [ ] **Task 3.6** (T3.6): Remove `is_flatline_routing_enabled` branches from consumers (commit C — `model-adapter.sh:67`, `flatline-orchestrator.sh:476`, `adversarial-review.sh`); legacy file still on disk but no caller invokes → **[G-4]**
- [ ] **Task 3.7** (T3.7): **DESTRUCTIVE — operator-approval marker C109.OP-S3 required first.** Delete `model-adapter.sh.legacy` (commit D — `git rm`; `tools/check-no-raw-curl.sh` exempt-list updated to remove file; pre-delete baseline archived) → **[G-4]**
- [ ] **Task 3.8** (T3.8): Remove `hounfour.flatline_routing` flag entirely (commit E — config key removed; reading sites cleaned) → **[G-4]**
- [ ] **Task 3.9** (T3.9): Update `CLAUDE.md` Multi-Model Activation section + rollback runbook at `grimoires/loa/runbooks/cycle-109-rollback.md` (commit F) → **[G-4, G-5]**
- [ ] **Task 3.10** (T3.10): Activation regression suite CI workflow file (`.github/workflows/activation-regression.yml`) + matrix orchestration + branch-protection-required toggle landed as separate ops PR → **[G-1, G-4, G-5]**
- [ ] **Task 3.11** (T3.11): Sprint-3 debrief + cycle-mid baseline recapture (`tools/cycle-baseline-capture.sh --phase mid-cycle`) + operator-approval marker C109.OP-S3 final → **[G-5]**

### Dependencies

- **Sprint 1 (FR-1)**: activation matrix tests against new capability surface (effective_input_ceiling preemption fixtures)
- **Sprint 2 (FR-2)**: activation matrix asserts verdict_quality classification per fixture; consumer-contract test re-runs as part of matrix
- **Operator-approval C109.OP-S3**: required before destructive Commit D — marker lands in `operator-approval.md` documenting that pre-delete safety baseline was captured

### Security Considerations

- **Trust boundaries**: activation regression suite uses cycle-099 sprint-1C curl-mock harness — no live provider calls; no credential exposure surface
- **Destructive change authorization**: commit D (file deletion) requires explicit operator sign-off marker per C109.OP-3 risk acknowledgment; cycle-revert is the documented rollback path (no runtime flag exists post-Sprint 3)
- **Pre-delete safety baseline**: synthetic test at commit C records last-known-good `flatline_routing: false` path baseline to `baselines/legacy-final-baseline.json` — forensic comparison artifact if rollback needed
- **CI gate elevation**: branch-protection-required toggle for `activation-regression` job is operator-permission scope; tracked as ops task post-merge

### Risks & Mitigation

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Legacy delete (FR-3.3) breaks a consumer not in inventory (R-2) | Med | High | FR-3.1 grep-pass inventory; FR-3.5 activation matrix runs on every consumer in FR-2 table — orphan consumers fail CI on commit C (BEFORE commit D destructive); per-commit CI gate green between A→B→C→D→E→F |
| Substrate becomes single-point-of-failure post-legacy-delete (R-8) | Low | High | Already true at v1.157.0 for activated default; legacy was nominal-not-real safety net; mitigation is investing in substrate quality (which is this cycle); pre-delete baseline archived for forensic rollback |
| Test substrate (curl-mock-harness, fixture provider responses) drifts from real provider behavior (R-9) | Med | Med | Fixtures versioned and reviewed; sprint-1C precedent; periodic real-provider smoke run (advisory CI job, not required, labeled `requires-substrate-billing` per C109.OP-7) |
| Commit-D destructive operation lands without operator sign-off | Low | High | C109.OP-S3 marker required in `operator-approval.md` before merge; Loa harness reads marker; absence = PR-merge-block |
| Activation matrix wall-time exceeds 15 min budget | Med | Med | Parallelization across GitHub Actions runners; matrix-job split per-consumer (9 jobs); if exceeded, shard further by response-class |

### Success Metrics

- G-4 met: `wc -l .claude/scripts/model-adapter.sh.legacy` returns "no such file"
- G-1 substantially advanced: 4 of 13 OPEN substrate issues closed (#864, #793, #863, #820 → 9 remaining for Sprints 4-5)
- Activation regression suite wall-time <15 min full matrix; 810/810 cells green
- `flatline_routing: true` activated-path test coverage: 9/9 consumers × 5/5 roles × 6/6 response classes × 3/3 dispatch paths = 810 fixtures
- Zero references to `model-adapter.sh.legacy` in `git ls-files`
- `cycle-baseline-capture.sh --phase mid-cycle` shows legacy-LOC = 0 (vs baseline 1,081)

---

## Sprint 4 (sprint-162): Hierarchical / Chunked Review for Large Inputs

**FR:** FR-4 (PRD §5 FR-4; SDD §5.4)
**Scope:** LARGE (10 tasks)
**Operator-approval ref:** C109.OP-1 + C109.OP-5 — substrate-changing sprint; will land C109.OP-S4 sign-off marker before merge

### Sprint Goal

> When input exceeds a model's `effective_input_ceiling`, cheval automatically chunks the review, aggregates findings with conflict resolution, and runs a cross-chunk pass for boundary-spanning findings — instead of empty-contenting empirically and producing KF-002-class incidents. Structurally close KF-002 layer-1 (G-2).

### Deliverables

- [ ] `loa_cheval.chunking` package: `chunk_pr_for_review`, `aggregate_findings`, `detect_boundary_findings`, `second_stage_review`, `merge_with_second_stage`
- [ ] File-level chunk boundary strategy per FR-4.1: chunk size = `effective_input_ceiling × 0.7`; shared header (PR description + affected-files-list + relevant CLAUDE.md excerpts)
- [ ] Aggregation algorithm per IMP-006: dedupe-same-anchor + cross-class-overlap-annotation + severity-escalation + cross-chunk-pass for boundary-spanning findings
- [ ] Cross-chunk pass mechanism (FR-4.3 / SDD §5.4.3): synthetic combined chunk from spanning slice; re-dispatch through cheval with `--role review`; bounded ONCE per chunked call; bounded size to `effective_input_ceiling × 0.4`
- [ ] Streaming-with-recovery (FR-4.4 / IMP-014): three thresholds (first-token deadline, empty-content detection, CoT-detection regex for reasoning-class) implemented in cheval streaming code path; per-model `streaming_recovery` config in `model-config.yaml`
- [ ] MODELINV v1.3 envelope additions: `chunked: true, chunks_reviewed: N, chunks_dropped: 0, chunks_aggregated_findings: M`, `streaming_recovery: {...}`, `cross_chunk_pass: true`
- [ ] Operator-facing PR-comment chunked annotation: chunk count + per-chunk degradation rendered distinctly from overall verdict
- [ ] [ISSUE:#866] / [ISSUE:#823] reproduction fixtures pass
- [ ] New exit code 13 `ChunkingExceeded` (input requires > `chunks_max` chunks AND truncation forbidden via flag) per SDD §6.1

### Acceptance Criteria

- [ ] >70KB FL input completes successfully against fixture providers (bats with curl-mock-harness; mocked Anthropic + OpenAI + Google responses)
- [ ] >40K reasoning-class input produces non-empty findings via chunking (bats fixture: 50K-token PR-review payload chunked + aggregated)
- [ ] Chunked-review aggregation: deduplication of `(file, line, finding_class)` + finding-anchor preservation tested — `tests/unit/chunking-aggregate.bats`
- [ ] Streaming early-abort triggers on simulated empty-content (bats with mock; first 200 tokens empty → typed exit 1 with subcode EmptyContent)
- [ ] [ISSUE:#866] (large-doc empty-content) + [ISSUE:#823] (related large-input regression) reproduction fixtures: pre-Sprint-4 fixture fails; post-Sprint-4 fixture passes
- [ ] **[IMP-006]** Each conflict-resolution case has ≥1 fixture: dedupe-same-anchor, dedupe-same-anchor-different-class, different-line-same-class, severity-escalation, cross-chunk-overlap (boundary-spanning) — `tests/unit/chunking-conflict-resolution.bats`
- [ ] **[IMP-014]** Per-model `streaming_recovery` thresholds shipped in `model-config.yaml`; bats verify abort triggers at documented thresholds; reasoning-class CoT-detection regex tested with positive AND negative controls — `tests/unit/streaming-recovery.bats`
- [ ] NFR-Perf-2: chunked review for 100KB PR completes in ≤2.5× single-dispatch baseline on same-size PR
- [ ] G-2 met: KF-002 ledger entry status updates to `RESOLVED-STRUCTURAL` (currently `LAYER-1 LATENT`); no new layer surface during 30d post-merge window (validated in Sprint 5 by re-measuring `kf-recurrence.json`)

### Technical Tasks

> Mirrors SDD §5.4.5 beads graph.

- [ ] **Task 4.1** (T4.1): `loa_cheval.chunking` package skeleton + fixture types (`ChunkFindings`, `AggregatedFindings`, `Finding`) + test-first (failing fixtures) → **[G-2, G-1]**
- [ ] **Task 4.2** (T4.2): `chunk_pr_for_review` function + file-level boundary tests + shared-header attachment → **[G-2, G-1]**
- [ ] **Task 4.3** (T4.3): `aggregate_findings` function + 5 IMP-006 conflict-resolution fixtures (dedupe-same / dedupe-different-class / different-line / severity-escalation / cross-chunk-overlap) → **[G-2]**
- [ ] **Task 4.4** (T4.4): Cross-chunk pass mechanism (`detect_boundary_findings` + `second_stage_review` + `merge_with_second_stage`) + spans-boundary fixtures (shell-injection sanitizer-and-sink in different chunks) → **[G-2]**
- [ ] **Task 4.5** (T4.5): Cheval pre-flight gate dispatches chunked path when `input > effective_input_ceiling × 0.7`; new exit code 13 `ChunkingExceeded` when chunks > `chunks_max` AND truncation forbidden → **[G-2, G-1]**
- [ ] **Task 4.6** (T4.6): Streaming-with-recovery (FR-4.4) + IMP-014 thresholds (first-token-deadline 30s/60s, empty-content-window 200 tokens, CoT-detection regex `^(thinking|let me|i'll|first[,]?\s+i)` + `<thinking>` opening tag, CoT-budget 500 tokens for reasoning-class) → **[G-2]**
- [ ] **Task 4.7** (T4.7): MODELINV envelope chunked_review + streaming_recovery + cross_chunk_pass fields (additive over v1.3 from Sprint 1) → **[G-2, G-5]**
- [ ] **Task 4.8** (T4.8): Operator-facing PR-comment chunked annotation (`chunks_reviewed: N` rendering at top of every chunked-review comment); per-chunk degradation distinct from overall verdict → **[G-2]**
- [ ] **Task 4.9** (T4.9): [ISSUE:#866] / [ISSUE:#823] reproduction fixtures pass (pre/post comparison; KF-002 cross-reference in PR body) → **[G-2, G-1]**
- [ ] **Task 4.10** (T4.10): Sprint-4 debrief + KF-002 status update to `RESOLVED-STRUCTURAL` + operator-approval marker C109.OP-S4 → **[G-2, G-5]**

### Dependencies

- **Sprint 1 (FR-1)**: chunker uses `effective_input_ceiling` from model-config.yaml v3; pre-flight gate dispatches chunked path
- **Sprint 2 (FR-2)**: chunked output carries verdict_quality envelope with per-chunk drilldown; `single_voice_call` semantics interact with chunked dispatch
- **Sprint 3 (FR-3)**: activation regression suite covers chunked path (3rd dispatch-path dimension in IMP-009); chunked-2-chunk and chunked-5-chunk fixtures in matrix

### Security Considerations

- **Trust boundaries**: chunker reads PR diff content — no eval / interpolation surface; chunk content treated as untrusted input throughout aggregation
- **Cost control**: cross-chunk pass bounded to ONCE per chunked call (no recursive cross-chunk-of-cross-chunk); second-stage size ≤ `effective_input_ceiling × 0.4`; `chunks_max` configurable per-model
- **Streaming-recovery**: typed exit 1 with subcode EmptyContent — never silent timeout (NFR-Rel-2)
- **CoT-detection regex**: tested with positive AND negative controls to avoid false-positive aborts on legitimate non-CoT output (mirrors cycle-099 sprint-1E.c.3.c Unicode-glob test-discipline)

### Risks & Mitigation

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Chunked review changes finding behavior (false positives/negatives) (R-4) | Med | Med | Deduplication tests; finding-anchor preservation tests; A/B comparison against single-dispatch baseline on representative PR corpus (Sprint 4 ACT task) |
| Cross-chunk pass over-invokes (cost explosion) | Low | Med | Bounded to once per chunked call; second-stage size capped; cost incrementally bounded per SDD §5.4.3 |
| Streaming-with-recovery aborts legitimate slow-start reasoning model | Low | Med | Per-model `streaming_recovery` config in model-config.yaml; reasoning-class first-token-deadline 60s (vs 30s non-reasoning); CoT-budget 500 tokens before abort; positive AND negative control tests |
| Chunk priority truncation drops high-signal files | Low | Med | `chunks_max` default 16; truncation emits `chunks_dropped: N` annotation in verdict_quality.rationale + warning; operator-visible |
| KF-002 LAYER-1 LATENT does not in fact close (new zoom level emerges) | Med | High | Sprint 5 30d-window observability surface monitors for new KF-002-class entries; if surfaces, file as Sprint 6 / cycle-110 priority; operator-visible via baseline re-measure |

### Success Metrics

- G-2 met: KF-002 ledger entry status = `RESOLVED-STRUCTURAL` at end of Sprint 4
- All 5 IMP-006 conflict-resolution cases have passing fixtures
- All 3 IMP-014 streaming-recovery thresholds documented per-model + bats-verified
- NFR-Perf-2 met: chunked 100KB PR ≤ 2.5× single-dispatch baseline
- 2 issues closed (#866, #823) — total cycle-109 OPEN issues: 7 remaining for Sprint 5

---

## Sprint 5 (sprint-163, FINAL): Carry Items + Substrate Observability + Cycle Close

**FR:** FR-5 (PRD §5 FR-5; SDD §5.5)
**Scope:** LARGE (10 tasks)
**Operator-approval ref:** C109.OP-1 + C109.OP-5 — substrate-changing sprint; will land C109.OP-S5 (sprint-close) and C109.OP-CLOSE (cycle-close + signed release tag) markers

### Sprint Goal

> Close cycle-108 carry items (#874 / #875 / #870) and deliver operator-facing substrate health surface (`loa substrate health`) so operators can see degradation BEFORE a session blows up. Run final cycle-close E2E goal validation against all 5 PRD goals; tag and ship cycle-109.

### Deliverables

- [ ] [ISSUE:#874] fixed: cheval.py advisor-strategy provider-peek generalized across providers (no more narrow `'anthropic'` fallback)
- [ ] [ISSUE:#875] fixed: modelinv.py `parents[4]` hardcode replaced with `_find_repo_root()` walker
- [ ] [ISSUE:#870] fixed: modelinv-rollup.sh refactored from O(N) per-line subprocess spawn to single-pass `awk`/`jq -c` parse
- [ ] `loa substrate health [--window 24h|7d|30d] [--json] [--model <id>]` CLI shipped: `.claude/scripts/loa-substrate-health.sh` + `.claude/adapters/loa_cheval/health.py` aggregator
- [ ] `loa substrate recalibrate <model-id>` CLI (FR-1.6 operator-forced reprobe trigger; synchronous with progress per C109.OP-5)
- [ ] Health-threshold warnings (FR-5.7): success_rate ≥ 80% green; 50%-80% yellow + warning; < 50% red + KF-suggest
- [ ] Cron journal: `.github/workflows/substrate-health-journal.yml` runs daily 00:00 UTC; appends to `grimoires/loa/substrate-health/YYYY-MM.md`; opens PR to `auto-journal` branch for operator-merge review (per C109.OP-5 default)
- [ ] Cycle-close baseline recapture (`tools/cycle-baseline-capture.sh --phase cycle-close`); 30d post-cycle window scheduled for re-measure
- [ ] CHANGELOG.md updated with cycle-109 entry
- [ ] Cycle-109 signed release tag via post-merge-orchestrator.sh
- [ ] All operator-approval markers complete: C109.OP-1 through C109.OP-CLOSE recorded

### Acceptance Criteria

- [ ] All 3 carry items closed: `gh issue view 874 875 870 --json state` all return `CLOSED`
- [ ] `loa substrate health` CLI ships; tested with synthetic envelope corpus (`tests/integration/substrate-health-cli.bats`)
- [ ] NFR-Perf-3 met: `loa substrate health --window 24h` completes in <2s on 100K-entry MODELINV log (bats perf assertion)
- [ ] Operator can identify a degrading model BEFORE filing a substrate issue (UC-4) — verified by manual operator walk-through documented in sprint-5-debrief.md
- [ ] Health-threshold warnings render correctly: SUCCESS, DEGRADED, FAILED bands per FR-5.7
- [ ] Cron journal entry idempotent: rerunning on same day = no-op (date-string check)
- [ ] Cron journal output format matches SDD §5.5.3 markdown schema
- [ ] NFR-Sec-3: substrate-health output piped through `lib/log-redactor.{sh,py}` before stdout — bats fixture asserts fake `AKIA` / `BEGIN PRIVATE KEY` / `Bearer` shapes are scrubbed
- [ ] **All cycle-109 launch criteria met** (PRD §10.1):
  - [ ] All 13 OPEN substrate issues from reality §9 closed (#793, #805, #807, #809, #820, #823, #863, #864, #866, #868, #870, #874, #875)
  - [ ] G-1 through G-5 met
  - [ ] All sprint acceptance criteria met (FR-1 through FR-5)
  - [ ] All NFR thresholds met
  - [ ] Activation regression suite green and required-in-CI (carryover from Sprint 3)
  - [ ] Final cycle audit passes (per /audit-sprint + /ship pattern)
  - [ ] CHANGELOG.md updated; cycle-109 tag signed; operator-approval ledger complete

### Technical Tasks

> Mirrors SDD §5.5.4 beads graph + adds dedicated E2E task per planning-sprints template.

- [ ] **Task 5.1** (T5.1): Fix [ISSUE:#874] — provider-peek generalization (walk `aliases[].provider` set, not hardcoded 'anthropic') + test → **[G-1]**
- [ ] **Task 5.2** (T5.2): Fix [ISSUE:#875] — modelinv `parents[4]` hardcode replaced with `_find_repo_root()` walker (mirrors cheval's existing approach) + test → **[G-1]**
- [ ] **Task 5.3** (T5.3): Fix [ISSUE:#870] — rollup O(N) → single-pass `awk`/`jq -c` + perf test → **[G-1]**
- [ ] **Task 5.4** (T5.4): `loa substrate health` CLI (bash entrypoint + python aggregator) + 24h-window perf test (<2s on 100K-entry log) → **[G-1, G-2, G-5]**
- [ ] **Task 5.5** (T5.5): Health-threshold warnings (FR-5.7) + redactor integration (NFR-Sec-3) → **[G-2, G-5]**
- [ ] **Task 5.6** (T5.6): `loa substrate recalibrate <model-id>` CLI (FR-1.6 trigger; synchronous-with-progress per C109.OP-5) → **[G-1, G-2]**
- [ ] **Task 5.7** (T5.7): Cron journal workflow (`.github/workflows/substrate-health-journal.yml`) — daily 00:00 UTC; commits to `auto-journal` branch; opens PR for operator merge → **[G-2, G-5]**
- [ ] **Task 5.8** (T5.8): Journal markdown formatter + idempotency check (date-string match = no-op) → **[G-2, G-5]**
- [ ] **Task 5.9** (T5.9): Cycle-close baseline recapture (`tools/cycle-baseline-capture.sh --phase cycle-close`) — all 7 PRD §3.4 baselines re-measured; comparison table in sprint-5-debrief.md → **[G-1, G-2, G-3, G-4, G-5]**
- [ ] **Task 5.10** (T5.10) — **TASK N.E2E: End-to-End Goal Validation** (P0 / Must Complete): see dedicated section below; produces cycle-close artifact; final sprint debrief; CHANGELOG entry; cycle-109 signed release tag; operator-approval markers C109.OP-S5 + C109.OP-CLOSE → **[All Goals: G-1, G-2, G-3, G-4, G-5]**

### Task 5.10 — End-to-End Goal Validation (P0)

**Priority:** P0 (Must Complete)
**Goal Contribution:** ALL goals (G-1, G-2, G-3, G-4, G-5)

**Description:**
Validate that all cycle-109 PRD goals are achieved through the complete implementation. Re-measure all 7 PRD §3.4 baselines; compare against cycle-kickoff baselines; produce comparison table in `sprint-5-debrief.md`; only declare cycle COMPLETE when every goal validated with documented evidence.

**Validation Steps:**

| Goal ID | Goal | Validation Action | Expected Result |
|---------|------|-------------------|-----------------|
| G-1 | Close all 13 OPEN substrate issues identified in reality §9 | `gh issue list --label substrate --state open` (the cycle-109 set: #793, #805, #807, #809, #820, #823, #863, #864, #866, #868, #870, #874, #875) | 0 OPEN issues (vs baseline 13); per-sprint closure traceable in `baselines/issue-counts.json` |
| G-2 | Eliminate KF-002 layer-1 recurrence (structural, not patched) | grep `KF-002` in `grimoires/loa/known-failures.md`; inspect Status field | Status = `RESOLVED-STRUCTURAL` (vs baseline `LAYER-1 LATENT`); no new layer entries; 30d-window followup deferred to cycle-110 first 30 days metric |
| G-3 | Substrate "clean" verdict accuracy = 100% | Replay last-30-day audit log; count `status: clean` outputs where `voices_succeeded < voices_planned` OR `chain_health != ok` | 0 false-positives (vs baseline: #807 demonstrated 5 BLOCKING approved) |
| G-4 | Delete legacy adapter path entirely | `git ls-files \| grep model-adapter.sh.legacy`; `wc -l` returns "no such file" | 0 references; 0 LOC (vs baseline 1,081); CI scanner enforces |
| G-5 | Cycle ships under iron-grip Loa quality gates | Inspect `.run/audit.jsonl`; verify every PR has Flatline PRD/SDD/sprint-plan reviews + BB review + post-PR audit + KF cross-reference; operator-approval ledger complete | Every cycle-109 PR has full audit trail; operator-approval.md has every C109.OP-N marker for substrate-changing sprints |

**Acceptance Criteria:**

- [ ] Each goal validated with documented evidence in `sprint-5-debrief.md` Section "Goal Validation Table"
- [ ] Integration points verified: data flows end-to-end through capability-aware substrate → verdict-quality envelope → activation regression suite → chunked review → observability surface
- [ ] No goal marked as "not achieved" without explicit operator-approval justification
- [ ] Cycle-close baseline comparison table produced: cycle-kickoff vs cycle-close measurements for all 7 PRD §3.4 metrics
- [ ] PRD §10.1 launch criteria all checkboxed
- [ ] Cycle-109 signed release tag created via post-merge-orchestrator.sh
- [ ] CHANGELOG.md updated with cycle-109 entry

### Dependencies

- **Sprint 1 (FR-1)**: substrate-health CLI reads MODELINV v1.3 envelope fields (capability_evaluation, ceiling_calibration_source)
- **Sprint 2 (FR-2)**: substrate-health CLI aggregates verdict_quality field for SUCCESS/DEGRADED/FAILED bands
- **Sprint 4 (FR-4)**: substrate-health CLI surfaces chunked annotations (chunks_reviewed, chunks_dropped) per-model

### Security Considerations

- **NFR-Sec-3**: substrate-health output piped through `lib/log-redactor.{sh,py}` (cycle-099 sprint-1E.a precedent) — reuse, do not reinvent
- **Cron journal**: writes to `auto-journal` branch via GitHub Actions bot identity; operator reviews via PR before merge (per C109.OP-5 default — no direct main commits from automation)
- **Read-only consumer**: substrate-health is a read-only consumer of `.run/model-invoke.jsonl`; no mutation surface
- **Recalibrate CLI**: `loa substrate recalibrate` is operator-gated (mirrors C109.OP-5 default Q1: `--ceiling-override` operator-only; OPERATORS.md slug verification)

### Risks & Mitigation

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Cron journal produces noisy PRs (one per day) | Low | Low | Workflow batches multiple days into single PR if not merged; `auto-journal` label enables operator-side filter |
| `loa substrate health` perf target missed for large logs | Low | Med | Single-pass file read; `defaultdict` aggregation; no DB; bats perf test enforces NFR-Perf-3 |
| Cycle-close E2E reveals a goal NOT met | Low | High | Sprint 5 has 1-week slack; if E2E surfaces a gap, sprint extends or scope-slip per PRD §11.6 (Sprint 4-5 prioritization); operator-visible via /run-halt |
| 30d post-cycle KF-002 recurrence appears after ship | Med | Med | Substrate-health observability surfaces new degradation BEFORE catastrophic (UC-4 / Flow 2); auto-routes via KF-auto-link to model degradation; cycle-110 first-30d metric is the validator |
| Carry items reveal undiscovered cluster (cluster E) | Low | Med | PRD §11.2 assumption: if fifth cluster emerges, evaluate against cycle scope; defer if feature-class; fold into Sprint 5 if hardening-class; per operator-approval autonomous discretion |

### Success Metrics

- 3 carry items closed (#874, #875, #870) — total cycle-109 OPEN issues: 0/13
- `loa substrate health --window 24h` <2s on 100K-entry MODELINV log
- Cron journal produces correctly-formatted entries (markdown-validated)
- All PRD §10.1 launch criteria checkboxed
- Cycle-109 signed release tag created; CHANGELOG.md updated
- Operator-approval ledger has every C109.OP-N marker (OP-1 through OP-CLOSE)
- All baseline metrics show documented improvement direction:
  - OPEN substrate issues: 13 → 0
  - KF-002 recurrence: LAYER-1 LATENT → RESOLVED-STRUCTURAL
  - "clean" verdict false-positive rate: T0-baseline → 0
  - Legacy adapter LOC: 1,081 → 0
  - MODELINV envelope coverage: cycle-108 baseline 0.90 → ≥0.95
  - Substrate observability surface: none → 24h rolling dashboard available
  - Operator self-rating (multi-model headspace): kickoff → cycle-close — drop expected

---

## Risk Register (Cycle-Wide)

> Aggregates PRD §11.1 risks against the sprint they materialize in.

| ID | Risk | Sprint | Probability | Impact | Mitigation | Owner |
|----|------|--------|-------------|--------|------------|-------|
| R-1 | Capability data wrong (ceiling too high/low) | 1, 4 | Med | Med | Empirical probe at ship time (T1.7); KF auto-link self-correcting feedback loop; Sprint 4 streaming-with-recovery defensive fallback | @janitooor / Sprint 1 + 4 lead |
| R-2 | Legacy delete breaks consumer not in inventory | 3 | Med | High | FR-3.1 grep-pass inventory; FR-3.5 activation matrix on every consumer; per-commit CI green between A→B→C→D→E→F; operator approves Sprint 3 PR specifically | @janitooor / Sprint 3 lead |
| R-3 | Verdict envelope breaks consumer integrations | 2 | Low | Med | Envelope is additive; per-consumer refactor in IMP-004 order; conformance test catches divergence pre-merge | @janitooor / Sprint 2 lead |
| R-4 | Chunked review changes finding behavior | 4 | Med | Med | Dedup tests; finding-anchor preservation tests; A/B comparison against single-dispatch baseline | @janitooor / Sprint 4 lead |
| R-5 | MODELINV v1.3 breaks existing replay logs | 1 | Low | High | v1.3 schema additive only; existing parsers tested for backward compat; cycle-098 audit envelope hash-chain integrity preserved | @janitooor / Sprint 1 lead |
| R-6 | Cycle scope too large; runway forces premature ship | 1-5 | Med | High | Per-sprint independent value; if 4-5 slip, 1-3 alone meaningfully harden substrate; operator-visible escape via PRD §11.3 (`git revert` only — runtime flag gone post-Sprint-3) | @janitooor |
| R-7 | KF-auto-link over-degrades models | 1 | Low | Med | Severity mapping documented per IMP-001; reversible (KF resolves → re-upgrade); operator manual-override in `.loa.config.yaml` per IMP-002 | @janitooor / Sprint 1 lead |
| R-8 | Substrate SPOF post-legacy-delete | 3+ | Low | High | Already true at v1.157.0 default; cycle investments ARE the mitigation; pre-delete baseline archived | @janitooor |
| R-9 | Test substrate drifts from real provider | 3, 4 | Med | Med | Fixtures versioned and reviewed; sprint-1C precedent; periodic real-provider smoke (advisory CI labeled `requires-substrate-billing`) | @janitooor |
| R-10 | Substrate-billing degradation (C109.OP-6/7) extends mid-cycle | 1-5 | Med | Med | Sprint plan does NOT depend on substrate billing resolving; all CI gates fixture-mocked; advisory smoke jobs labeled `requires-substrate-billing`; operator-side action tracked separately | @janitooor |
| R-11 | Sprint 4 streaming-recovery aborts legitimate slow-start reasoning model | 4 | Low | Med | Per-model `streaming_recovery` config; reasoning-class first-token-deadline 60s; CoT-budget 500 tokens; positive AND negative control tests | @janitooor / Sprint 4 lead |
| R-12 | Cycle-close E2E reveals goal NOT met | 5 | Low | High | Sprint 5 has 1-week slack; scope-slip via PRD §11.6 if surfaces; operator-visible via /run-halt | @janitooor / Sprint 5 lead |

---

## Success Metrics Summary (Cycle-109)

| Metric | Target | Measurement Method | Sprint |
|--------|--------|-------------------|--------|
| OPEN substrate issues (reality §9) | 13 → 0 | `gh issue list --label substrate --state open` | 5 (close) |
| KF-002 layer-1 recurrence count | LAYER-1 LATENT → RESOLVED-STRUCTURAL | grep `KF-002` Status in known-failures.md | 4 |
| Substrate "clean" verdict false-positive rate | 5 BLOCKING approved (#807) → 0 | replay last-30d audit log; assert `status: clean ⇒ voices_succeeded == voices_planned && chain_health == ok` | 2 |
| Legacy adapter LOC | 1,081 → 0 | `git ls-files \| grep model-adapter.sh.legacy` | 3 |
| `flatline_routing: true` activated-path coverage | unknown → 810 fixtures green | activation regression suite CI matrix | 3 |
| MODELINV v1.3 envelope coverage | ≥0.95 | `tools/modelinv-coverage-audit.py --window 30d` | 1 |
| Substrate observability surface | none → 24h rolling dashboard | `loa substrate health` CLI shipped | 5 |
| Cheval pre-flight gate overhead | <50ms (NFR-Perf-1) | bats microbenchmark | 1 |
| Chunked-review wall-time vs single-dispatch | ≤2.5× (NFR-Perf-2) | A/B comparison on 100KB PR | 4 |
| `loa substrate health` wall-time | <2s on 100K log (NFR-Perf-3) | bats perf assertion | 5 |
| Activation regression matrix wall-time | <15 min | CI job duration | 3 |
| Conformance CI matrix wall-time | <10 min | CI job duration | 2 |
| Operator self-rating (multi-model headspace) | Kickoff vs close — drop expected | operator self-rating qualitative entry | 1 + 5 |

---

## Dependencies Map

```
Sprint 1 (FR-1) ──────► Sprint 2 (FR-2) ──────► Sprint 3 (FR-3) ──────► Sprint 4 (FR-4) ──────► Sprint 5 (FR-5)
   │                       │                       │                       │                       │
   │ Capability fields     │ Verdict envelope      │ Legacy delete +       │ Chunked review        │ Carry items +
   │ + pre-flight gate     │ + classifier          │ activation matrix     │ + streaming-recovery  │ observability +
   │ + MODELINV v1.3       │ + 7-consumer refactor │ + Cluster B fixes     │ + cross-chunk pass    │ E2E goal validation
   │ + KF-auto-link        │ + conformance corpus  │ + 810 fixtures        │ + IMP-014 thresholds  │ + cycle close
   │ + baseline capture    │                       │                       │                       │
   ▼                       ▼                       ▼                       ▼                       ▼
[G-1, G-2 fnd]          [G-3 ✓]                 [G-4 ✓]                 [G-2 ✓]                 [G-1 ✓ G-5 ✓]
```

Each sprint also feeds the cycle-wide quality-gate audit trail (`.run/audit.jsonl` + `.run/model-invoke.jsonl` + `.run/activation-regression/sprint-N.json`).

---

## Appendix

### A. PRD Feature Mapping

| PRD FR | Sub-requirement | Sprint | Task(s) | Status |
|--------|-----------------|--------|---------|--------|
| FR-1.1 | model-config.yaml v3 capability fields | 1 | T1.1, T1.2 | Planned |
| FR-1.2 | Schema validation + IMP-008 conservative defaults | 1 | T1.2 | Planned |
| FR-1.3 | Cheval pre-flight gate | 1 | T1.3 | Planned |
| FR-1.4 | MODELINV v1.3 capability_evaluation field | 1 | T1.4 | Planned |
| FR-1.5 | KF-ledger auto-link script + IMP-001/-005 | 1 | T1.5, T1.6 | Planned |
| FR-1.6 | Ceiling calibration + staleness + IMP-007 | 1, 5 | T1.7, T5.6 (recalibrate CLI) | Planned |
| FR-2.1 | verdict-quality.schema.json | 2 | T2.1 | Planned |
| FR-2.2 | Substrate emits envelope on every call | 2 | T2.3 | Planned |
| FR-2.3 | Classification contract (APPROVED/DEGRADED/FAILED) | 2 | T2.2 | Planned |
| FR-2.4 | FL orchestrator refactor | 2 | T2.4 | Planned |
| FR-2.5 | adversarial-review refactor | 2 | T2.5 | Planned |
| FR-2.6 | BB cheval-delegate refactor | 2 | T2.6 | Planned |
| FR-2.6b | flatline-readiness + red-team-pipeline + post-PR triage | 2 | T2.7 | Planned |
| FR-2.7 | Consumer-contract conformance test | 2 | T2.8 | Planned |
| FR-2.8 | Operator-facing PR-comment verdict summary | 2 | T2.6 (BB), T2.4 (FL), T2.5 (RT) | Planned |
| FR-2.9 | Single-voice call semantics | 2 | T2.9 | Planned |
| FR-3.1 | Legacy reference inventory | 3 | T3.1 | Planned |
| FR-3.2 | Cluster B fixes at cheval path | 3 | T3.2, T3.3, T3.4, T3.5 | Planned |
| FR-3.3 | Delete model-adapter.sh.legacy | 3 | T3.7 (commit D) | Planned |
| FR-3.4 | Remove `is_flatline_routing_enabled` branches | 3 | T3.6 (commit C) | Planned |
| FR-3.5 | Activation regression suite | 3 | T3.1, T3.10 | Planned |
| FR-3.6 | Update rollback documentation | 3 | T3.9 (commit F) | Planned |
| FR-3.7 | CLAUDE.md Multi-Model Activation rewrite | 3 | T3.9 (commit F) | Planned |
| FR-4.1 | Chunking strategy (file-level) | 4 | T4.1, T4.2 | Planned |
| FR-4.2 | Cheval orchestrates chunked dispatch | 4 | T4.5 | Planned |
| FR-4.3 | Findings aggregation + IMP-006 | 4 | T4.3, T4.4 | Planned |
| FR-4.4 | Streaming-with-recovery + IMP-014 | 4 | T4.6 | Planned |
| FR-4.5 | MODELINV chunked annotations | 4 | T4.7 | Planned |
| FR-4.6 | Operator-facing chunked annotation | 4 | T4.8 | Planned |
| FR-4.7 | Close #866 / #823 / KF-002 layer-1 | 4 | T4.9, T4.10 | Planned |
| FR-5.1 | Fix #874 (provider-peek) | 5 | T5.1 | Planned |
| FR-5.2 | Fix #875 (modelinv parents[4]) | 5 | T5.2 | Planned |
| FR-5.3 | Fix #870 (rollup O(N)) | 5 | T5.3 | Planned |
| FR-5.4 | `loa substrate health` CLI | 5 | T5.4 | Planned |
| FR-5.5 | Output format | 5 | T5.4, T5.5 | Planned |
| FR-5.6 | Performance <2s | 5 | T5.4 | Planned |
| FR-5.7 | Health-threshold warnings | 5 | T5.5 | Planned |
| FR-5.8 | Cron journal | 5 | T5.7, T5.8 | Planned |

### B. SDD Component Mapping

| SDD Component | Sprint | Task(s) |
|---------------|--------|---------|
| §1.4.1 model-config.yaml schema v3 | 1 | T1.1, T1.2 |
| §1.4.2 Cheval pre-flight gate (extended) | 1, 4 | T1.3, T4.5 |
| §1.4.3 KF-auto-link script | 1 | T1.5, T1.6 |
| §1.4.4 Verdict-quality envelope schema | 2 | T2.1, T2.2 |
| §1.4.5 Chunked review primitive | 4 | T4.1-T4.4 |
| §1.4.6 Substrate-health CLI | 5 | T5.4, T5.5, T5.6 |
| §3.1 Schema v3 + IMP-008 defaults | 1 | T1.1, T1.2 |
| §3.2 Verdict envelope schema + classification | 2 | T2.1, T2.2 |
| §3.2.3 IMP-004 consumer dependency-ordered refactor | 2 | T2.3-T2.7 |
| §3.3 MODELINV v1.3 additive | 1, 4 | T1.4, T4.7 |
| §3.4 KF-auto-link audit log | 1 | T1.6 |
| §3.5 Operator-override precedence | 1 | T1.6, T1.9 |
| §4.2 Substrate-health CLI surface | 5 | T5.4 |
| §4.3 KF-auto-link CLI | 1 | T1.5 |
| §4.4 Verdict-quality classification helper (single source) | 2 | T2.2 |
| §4.5 Activation regression suite contract | 3 | T3.10 |
| §4.6 Cycle-098 audit envelope integration | 1 | T1.4, T1.10 |
| §5.3.1 FR-3 legacy delete sequence (6 commits) | 3 | T3.1-T3.10 |
| §5.4.2 Cross-chunk aggregation algorithm | 4 | T4.3 |
| §5.4.3 Cross-chunk pass mechanism | 4 | T4.4 |
| §5.4.4 Streaming-with-recovery + IMP-014 | 4 | T4.6 |
| §5.5.2 Substrate-health CLI implementation | 5 | T5.4, T5.5 |
| §5.5.3 Cron journal format | 5 | T5.7, T5.8 |
| §6.1 Exit codes (incl. new 13 ChunkingExceeded) | 1, 4 | T1.3, T4.5 |

### C. PRD Goal Mapping

| Goal ID | Goal Description | Contributing Tasks | Validation Task |
|---------|------------------|-------------------|-----------------|
| G-1 | Close all 13 OPEN substrate issues identified in reality §9 | T1.1, T1.2, T1.3, T1.4, T1.5, T1.6, T1.7, T1.8, T1.9, T1.10; T2.3, T2.5, T2.7; T3.1, T3.2, T3.3, T3.4, T3.5, T3.10; T4.1, T4.2, T4.5, T4.9; T5.1, T5.2, T5.3, T5.4, T5.6, T5.9 | T5.10 (E2E) |
| G-2 | Eliminate KF-002 layer-1 recurrence (structural, not patched) | T1.1, T1.5, T1.7, T1.10; T4.1-T4.10 (entire Sprint 4); T5.4, T5.5, T5.7, T5.8, T5.9 | T5.10 (E2E) + 30d post-cycle metric |
| G-3 | Substrate "clean" verdict accuracy = 100% | T1.2, T1.3, T1.4; T2.1, T2.2, T2.3, T2.4, T2.5, T2.6, T2.7, T2.8, T2.9 | T5.10 (E2E) — 30d audit replay |
| G-4 | Delete legacy adapter path entirely | T3.1, T3.6, T3.7, T3.8, T3.9, T3.10, T3.11 | T5.10 (E2E) — `git ls-files` assertion |
| G-5 | Cycle ships under iron-grip Loa quality gates | T1.6, T1.8, T1.10, T1.11; T2.1, T2.8, T2.10; T3.1, T3.9, T3.10, T3.11; T4.7, T4.10; T5.4, T5.5, T5.7, T5.8, T5.9, T5.10 | T5.10 (E2E) — audit-trail completeness check |

**Goal Coverage Check:**

- [x] All PRD goals have at least one contributing task — verified
- [x] All goals have a validation task in final sprint (Task 5.10 N.E2E)
- [x] No orphan tasks (every task annotated with goal contribution)

**Per-Sprint Goal Contribution:**

- **Sprint 1** (sprint-159): G-1 (foundation — all 13 issues touched by capability surface), G-2 (foundation — pre-flight gate is the structural lever), G-3 (partial — MODELINV envelope is the substrate for verdict-quality), G-5 (foundation — audit envelope + baselines)
- **Sprint 2** (sprint-160): G-3 (complete — verdict-quality classifier makes `clean` definitionally impossible when degraded), G-1 (advance — closes #807, #809, #868, #805), G-5 (advance — conformance corpus is the audit trail)
- **Sprint 3** (sprint-161): G-4 (complete — legacy adapter deleted), G-1 (substantial — closes 4 Cluster B issues), G-5 (advance — activation regression suite is the durable quality-gate)
- **Sprint 4** (sprint-162): G-2 (complete — KF-002 layer-1 → RESOLVED-STRUCTURAL), G-1 (advance — closes #866, #823), G-5 (advance — chunked dispatch is auditable per MODELINV v1.3)
- **Sprint 5** (sprint-163): G-1 (complete — closes #874, #875, #870 — final 3), G-2 (complete — observability surface enforces KF-002 prevention), G-5 (complete — cycle-close audit trail + signed release tag + operator-approval ledger), **E2E validation of all goals**

### D. Sprint Ledger Registration

| Local ID | Global ID | Theme | Status (at plan time) |
|----------|-----------|-------|----------------------|
| sprint-1 | sprint-159 | Capability-Aware Substrate Foundation | Planned |
| sprint-2 | sprint-160 | Verdict-Quality Envelope + Consumer Contracts | Planned |
| sprint-3 | sprint-161 | Legacy Adapter Sunset + Activation Regression Suite | Planned |
| sprint-4 | sprint-162 | Hierarchical / Chunked Review | Planned |
| sprint-5 | sprint-163 | Carry Items + Substrate Observability + Cycle Close | Planned |

The Sprint Ledger (`grimoires/loa/ledger.json`) is updated atomically with this plan: `cycles[id == "cycle-109-substrate-hardening"].sprints` extended with five entries (sprint-159..sprint-163); `next_sprint_number` advances from 159 to 164.

### E. Cycle-Wide Quality Gates Cross-Reference (PRD §13 — Iron Grip)

| Gate | Where enforced | Sprints |
|------|----------------|---------|
| 13.1 Flatline PRD review | Before /architect (already passed with C109.OP-4 override) | n/a (pre-cycle) |
| 13.2 Flatline SDD review | Before /sprint-plan (passed with C109.OP-7 override) | n/a (pre-cycle) |
| 13.3 Flatline sprint-plan review | Before /run (THIS DOCUMENT — operator-action pending) | n/a (this plan) |
| 13.4 Per-sprint implement → review → audit + circuit breaker | Every sprint | 1, 2, 3, 4, 5 |
| 13.4 Test-first commits (commit-1 red, commit-2+ green) | Every PR | 1, 2, 3, 4, 5 |
| 13.4 Bridgebuilder review on PR; iterate to plateau | Every PR | 1, 2, 3, 4, 5 |
| 13.4 Post-PR audit per cycle-053 amendment | Every PR | 1, 2, 3, 4, 5 |
| 13.4 Beads task lifecycle (created → in-progress → closed) | Every task | 1, 2, 3, 4, 5 |
| 13.4 KF cross-reference in PR body | When sprint addresses KF | 1, 2, 3, 4, 5 |
| 13.4 MODELINV v1.3 envelope reviewed at sprint close | Every sprint | 1, 2, 3, 4, 5 |
| 13.5 CODEOWNERS auto-assignment → @janitooor | Every PR | 1, 2, 3, 4, 5 |
| 13.5 No `--no-verify`, no `--no-gpg-sign` | Every commit | 1, 2, 3, 4, 5 |
| 13.6 Audit trail artifacts (.run/audit.jsonl, .run/model-invoke.jsonl, .run/activation-regression/sprint-N.json, sprint-N-debrief.md, BB review on PR) | Every sprint | 1, 2, 3, 4, 5 |
| 13.7 Circuit breaker (3 consecutive sprint failures = HALT) | Cycle-wide | 1, 2, 3, 4, 5 |
| 13.8 Forbidden shortcuts (no Flatline-skip, no direct /implement, etc.) | Cycle-wide | 1, 2, 3, 4, 5 |

### F. Substrate-Aware Sprint Execution Note

Per C109.OP-6 / C109.OP-7, the multi-model substrate is currently degraded due to operator-side billing (Anthropic credit + OpenAI Responses-API tier-access). Implications for sprint execution:

- **Flatline reviews** at the per-sprint level (Bridgebuilder + post-PR) may run substrate-degraded. When this happens, the substrate's own verdict_quality envelope (post-Sprint-2) will SURFACE the degradation rather than mask it (G-3 by construction). Until Sprint 2 ships, operator should manually verify Flatline review output is non-empty and non-degraded.
- **Sprint 3 activation regression suite** is fixture-mocked via cycle-099 sprint-1C curl-mock-harness; runs **without** any live provider call requirement; CI-required gate works in the substrate-billing-degraded state.
- **CI jobs that require live provider access** (rare; smoke jobs only) are labeled `requires-substrate-billing: true` and run as advisory, not required, until operator-side billing restored.
- **Per-cycle substrate-debug task TRACK** (C109.OP-7): operator-side investigation pending; tracked separately from sprint execution; resolution unblocks the upstream issue filing for substrate misdiagnosis of model-tier-access-denied as insufficient_quota.

### G. Glossary (cycle-109 specific terms)

| Term | Definition |
|------|------------|
| Capability surface | The set of fields on each model entry that describe its behavior (effective_input_ceiling, reasoning_class, recommended_for, failure_modes_observed, ceiling_calibration, streaming_recovery) |
| Pre-flight gate | The cheval check at `_lookup_max_input_tokens` that evaluates capability before dispatch (Sprint 1) |
| Verdict-quality envelope | The new schema describing HOW a verdict was reached (Sprint 2) |
| Single-canonical-classifier | The `loa_cheval.verdict.quality` Python module; bash twin shells out (Sprint 2) |
| Activation regression suite | The 810-cell CI matrix testing every consumer × role × response × dispatch path under `flatline_routing: true` (Sprint 3) |
| Cluster A/B/C/D | Diagnostic clusters from reality §11 (large-doc / v1.157.0 regressions / degraded semantics / carry items) |
| Substrate-billing degradation | The operator-side state captured in C109.OP-6 / C109.OP-7 |
| Iron-grip gates | Operator-mandated full quality-gate enforcement per PRD §13 |
| KF-auto-link | The script that maps `known-failures.md` entries to `model-config.yaml::recommended_for` degradation (Sprint 1, IMP-001) |

---

*Generated by Sprint Planner Agent (planning-sprints skill) for cycle-109-substrate-hardening on 2026-05-13.*
