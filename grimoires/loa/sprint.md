# Sprint Plan: Loa Full Size (cycle-126)

**Version:** 1.0
**Date:** 2026-09-24
**Status:** Draft — autonomous run (operator instruction: *"proceed"*)
**PRD:** `grimoires/loa/prd.md` · **SDD:** `grimoires/loa/sdd.md` · **Evidence:** `grimoires/loa/reports/model-era-audit-2026-09-24.md`
**Branch:** `feature/cycle-126-full-size` · **Ledger:** cycle `cycle-126-full-size`, sprints 247–250 (= sprint-1 … sprint-4)

---

## Executive Summary

Four sprints, one lead agent, unattended. Sprint 1 removes the direct caps on the current models (cheval ceiling policy, output defaults, estimator, health probe, Bridgebuilder registry/model/timeout, Flatline caps). Sprint 2 gives every dissent a companion voice and stops findings from disappearing on schema. Sprint 3 sizes the context discipline for the 5-family and regains instruction headroom under the replay A/B gate. Sprint 4 clears the routing and governance residue, repairs the platform probe, teaches the permission checker the second grammar, writes the docs and validates the five goals end to end. Every sprint is test-first and closes through `/review-sprint` and `/audit-sprint` with cross-model dissent; every schema-rejected dissent payload is hand-triaged.

## Sprint Overview

| Sprint | Global | Theme | FR | Exit gate |
|---|---|---|---|---|
| 1 | 247 | Full-size adapters, Bridgebuilder, Flatline | FR-1 | 600K fixture passes pre-flight with `warn`; BB registry/timeout/default correct for the 5-family; all adapter + BB suites green |
| 2 | 248 | Two voices, nothing dropped | FR-2 | three fixtures → findings; two-voice run on this host; feedback section enforced |
| 3 | 249 | Context discipline and instruction diet | FR-3 | budgets green with headroom; replay A/B not worse; includes regenerated |
| 4 (Final) | 250 | Residue, registry, probes, docs, E2E | FR-4 | no 4.x id as default/current in live code; G-1..G-5 evidenced |

---

## Sprint 1: Full-size adapters, Bridgebuilder and Flatline

**Global id:** 247 · **FR:** FR-1 · **SDD:** §1.2 (D-1.1 … D-1.7)

### Sprint Goal
Every size decision for a request derives from the catalog entry actually resolved: two pre-flight invariants (I1 `estimate + max_tokens ≤ context_window` with auto-shrink; I2 the input bound — probed by default, derived after calibration or explicit opt-in with self-correction), output defaults and timeouts follow the resolved entry, Bridgebuilder's generated table, default model and reasoning class match the 5-family, and Flatline's per-voice cap is catalog-bounded — with kill switches that restore today's behaviour.

### Deliverables
- Catalog: additive `probed_ceiling`, `account_limits`, `params.beta_headers` (allowlisted), `pricing.long_context`; `loa_cheval/routing/ceiling.py` (`input_bound`); `tools/ceiling-probe-live.py --write-catalog`.
- cheval gate: I1 auto-shrink + I2 policy (probed default, `LOA_CHEVAL_UNCALIBRATED_CEILING=derived` opt-in, `LOA_CHEVAL_LEGACY_CEILING=1`, `LOA_CHEVAL_MAX_INPUT_TOKENS`), `input_ceiling` / `estimator` / `max_tokens_shrunk` envelope fields, `CEILING_UNVERIFIED_LIMIT` single retry, non-walkable context errors, `.run/ceiling-observed.json`, `calibration_needed` record, `/loa` ceiling line.
- Pricing: long-context tier in `PricingEntry` / `calculate_total_cost`; `cost-report.sh long_context_rows`.
- `base.py` / `types.py` / `anthropic_adapter.py`: output defaults for every provider, unset temperature default, read-timeout keyed on the resolved `max_tokens`, `beta_headers`, `count_tokens` near the ceiling, health probe without a literal id.
- Bridgebuilder: registry with catalog `maxOutput` and `reasoning` flag, `isReasoningClass` from the registry, default model `opus`, persona aliases, rebuilt `dist/` + manifest.
- Flatline: per-voice cap from the catalog; dead `PER_CALL_MAX_TOKENS` removed.
- `lib-multipass.sh` estimator without the OpenAI encoding for Anthropic passes.
- Tests (below), CHANGELOG `[Unreleased]` FR-1 entry, `reviewer.md` with AC Verification.

### Acceptance Criteria
- [x] `test_anthropic_catalog_floor.py` asserts, per Anthropic entry, I1 (`estimate + max_tokens ≤ context_window`, auto-shrink to the 4,096 floor) and I2 (probed bound by default; calibrated value when `calibrated_at` is set; derived bound `context_window − max_tokens` only under the opt-in or calibration) — never `max()` with the probed value.
- [x] A 600,000-token fixture request to `claude-fable-5-1`: `preempt` at the probed bound by default; `action: warn` under `LOA_CHEVAL_UNCALIBRATED_CEILING=derived` with a `low` estimate or a count-endpoint result, `preempt` with a calibration message for a `high` estimate; `preempt` at 36K in legacy transport; today's behaviour under `LOA_CHEVAL_LEGACY_CEILING=1`; a calibrated entry uses its calibrated value; a simulated provider limit above the probed bound yields one retry, `CEILING_UNVERIFIED_LIMIT`, no chain walk, an observed-bound file and `preempt` on the next call; a 170K input on a 200K entry under the 64K default shrinks `max_tokens` (recorded) instead of failing.
- [x] `calculate_total_cost` applies the long-context multipliers above the threshold; `beta_headers` values failing the allowlist regex are a config error; `LOA_CHEVAL_MAX_INPUT_TOKENS` lowers the bound.
- [x] `test_transport_matrix.py` agrees across cheval, the BB registry and the Flatline cap resolver for every (provider, transport) row.
- [x] `default_max_tokens` returns `min(cap, max_output_tokens)` for every provider with a declaration and 4,096 only without one; `temperature` is absent from the wire unless set (present at 0.7 under `LOA_CHEVAL_LEGACY_WIRE=1`).
- [x] Generated BB table: `maxOutput 32000` and `reasoning: true` for `claude-opus-5`, `claude-sonnet-5`, `claude-fable-5-1`; `deriveTimeoutMs` → 1,800,000 for the three; `DEFAULTS.model === "opus"`; `tools/check-bb-dist-fresh.sh` clean.
- [x] Flatline `call_model` passes `--max-tokens 64000` for a 128K entry and the catalog value for a smaller one.
- [x] Health probe test: models endpoint path and the `tiny`-alias fallback; no `claude-3-` literal in the adapter.
- [x] All existing adapter suites, BB `tsx --test`, fence corpus, `repo-map-gen.sh --validate`, checksums `--check` green.

### Technical Tasks
- **Task 1.1 — Failing tests first.** Catalog formula per entry; `test_input_size_consumers.py` SIZES + 600,000 / 900,000 with expected actions; `test_ceiling_policy.py` (warn / preempt / kill switch / calibrated / observed-bound downgrade / single retry + `CEILING_UNVERIFIED_LIMIT`); `test_estimator_uncertainty.py` (ASCII, CJK, emoji, tool payloads); `test_transport_matrix.py`; `test_max_tokens_defaults.py` for openai/google/xai entries; `test_temperature_default.py`; `test_count_tokens_fallback.py` (mocked endpoint); `test_health_probe.py`; BB `__tests__/truncation-registry.test.ts`, `__tests__/timeout.test.ts`, `config.test.ts` default; `tests/unit/flatline-max-tokens.bats`.
- **Task 1.2 — Ceiling policy.** `routing/ceiling.py` (`input_bound`, observed-aware); catalog fields (`probed_ceiling`, `account_limits`, `beta_headers`, `pricing.long_context`); `cheval.py` I1 auto-shrink + I2 policy + envs + envelope fields; `retry.py` `CEILING_UNVERIFIED_LIMIT` single retry and non-walkable context errors; `.run/ceiling-observed.json` writer + `calibration_needed` record; `tools/ceiling-probe-live.py --write-catalog`; `loa-status` ceiling line; `gen-adapter-maps.sh` regen.
- **Task 1.7 — Cost visibility.** `PricingEntry` long-context fields, `calculate_total_cost` multipliers, `cost-report.sh long_context_rows`, per-voice `budget_cents` plumbing hook for Sprint 2, cost table in the SDD kept current.
- **Task 1.3 — Adapter defaults and probes.** `base.py` `default_max_tokens` for all providers (`_NON_ANTHROPIC_DEFAULT_OUTPUT_CAP`), `types.py` optional temperature, adapters emit only when set, read-timeout keyed on resolved `max_tokens`, `anthropic-beta` allowlist + join + diagnostics, `count_tokens` near the bound, health probe.
- **Task 1.4 — Bridgebuilder.** `gen-bb-registry.ts` fields + `GENERATED_REASONING`; `multi-model-pipeline.ts`; `config.ts` default + `maxInputTokens 200000` + `maxOutputTokens 32000`; persona headers; `SKILL.md:98`; `npm run build`; manifest.
- **Task 1.5 — Flatline caps.** `call_model` per-voice cap from `generated-model-maps.sh`; remove the literals and the dead knob; bats.
- **Task 1.6 — Estimator, docs, record.** `lib-multipass.sh` bound; CHANGELOG entry; REPO-MAP + sidecar + checksums; `reviewer.md` with red/green record and AC Verification.

### Dependencies
None external. Task 1.1 before 1.2–1.5 and 1.7; 1.6 last.

### Security Considerations
Kill switches are env-only and default off; the count endpoint sends the same prompt the request would send (no new data path); `beta_headers` is operator-set catalog data, never derived from a request; no credential value is read.

### Risks & Mitigation
| Risk | Mitigation |
|---|---|
| OpenAI golden bodies move with the output-cap change | cap constant tested; fixtures updated deliberately, diff shown in `reviewer.md` |
| BB `dist/` drift | build + manifest in the same commit |
| Warn branch masks a real oversize | the envelope records it; `preempt` above the derived ceiling is unchanged |

### Success Metrics
KPI rows 1–5 of the PRD met; zero new red across `.claude/adapters/tests`, BB tests, fence corpus.

---

## Sprint 2: Two voices, nothing dropped

**Global id:** 248 · **FR:** FR-2 · **SDD:** §1.3 (D-2.1 … D-2.4)

### Sprint Goal
A dissent on a subscription-only host plans and succeeds with two voices from different provider families, a finding missing only `failure_mode` reaches the reviewer marked as derived, every payload that still fails is summarised in the envelope, and the reviewer and auditor contracts make triaging that list mandatory.

### Deliverables
- Fixtures `tests/fixtures/dissent-rejected/` (the three real rejected payloads, scrubbed).
- `adversarial-review.sh`: normaliser (`failure_mode` derivation, `failure_mode_derived`), `metadata.rejected_summary[]`, companion-voice planning (credential presence → `claude-headless`), parallel walk + aggregate, `metadata.companion_voice`, repair-loop model selection.
- Envelope schema additive fields; `verdict-derive.sh --envelope` check; `reviewing-code` / `auditing-security` contract text (budget-neutral).
- Tests, CHANGELOG entry, KF-004 closing evidence row, `reviewer.md`.

### Acceptance Criteria
- [x] The three fixtures produce findings with `failure_mode_derived: true` and no sidecar rows; a payload without a severity still goes to the sidecar **and** appears in `rejected_summary`.
- [x] With a stubbed cheval on a keyless host, a review dissent records `voices_planned: 2`, `voices_succeeded_ids` containing `codex-headless` and `claude-headless`, and `companion_voice.status: succeeded` with its cost; with the companion chain failing (`auth`, `quota`, `timeout` stubs), `companion_voice.failure_class` names it, `voices_dropped` records it and a `review` still completes.
- [x] `verdict-derive.sh` exits 1 for a feedback file that lacks `## Rejected dissent payloads` when the sibling envelope has a non-empty `rejected_summary`, and 0 when the section exists or the summary is empty. *(Amended in review round 1x, run 23 c2d DISS-C-004: review rounds 2–11 tightened this contract. The section needs one top-level bullet per entry, counted as max(`rejected_summary` entries, sidecar rows beside the envelope). An empty summary passes only when no sidecar row is beside it either. An unlisted sidecar, a non-regular envelope, or moved-aside `.prev` files with no current envelope (`dissent_aborted`) are violations too. See `verdict-derive.sh --help`.)*
- [x] `_repair_finding_via_model` picks `tiny` with a key present and `claude-headless` without; the repair test measures success on the fixtures.
- [x] `companion_voice: false` on the block disables the second chain; existing adversarial suites green; skill budgets unchanged or smaller.

### Technical Tasks
- **Task 2.1 — Fixtures and failing bats.** `adversarial-review-normalise.bats`, `adversarial-review-companion.bats` (stub cheval via the existing test seam), `verdict-derive.bats` section cases.
- **Task 2.2 — Normaliser and summary.** Pre-validation step, `rejected_summary`, envelope schema.
- **Task 2.3 — Companion voice.** Family detection of the primary's first success, credential presence (env → `.env.local` → `.env`) to choose the chain, companion chain in a background subshell with the same `budget_cents`, completion-based status with failure classes (`auth`, `model_unavailable`, `quota`, `timeout`, `malformed`), aggregate both, `voices_planned`, opt-out key, `.loa.config.yaml.example` note.
- **Task 2.4 — Contracts.** `verdict-derive.sh --envelope` default path + check; skill text; `docs`/reference row.
- **Task 2.5 — Repair loop and KF-004.** Model selection; `kf-write-lib.sh` evidence row; runbook line.
- **Task 2.6 — Record.** CHANGELOG, REPO-MAP + sidecar + checksums, `reviewer.md`.

### Dependencies
Sprint 1 merged into the branch (catalog helpers). Task 2.1 first.

### Security Considerations
The companion voice is a hop already in every fallback chain; credential presence only; derived `failure_mode` never raises a severity; the reviewer still decides every finding.

### Risks & Mitigation
| Risk | Mitigation |
|---|---|
| Doubled dissent wall time | parallel chains, existing per-voice timeout |
| Stricter `verdict-derive` breaks old files | check applies only when an envelope with `rejected_summary` sits beside the file |
| Noise from derived findings | marked; same severity gates |

### Success Metrics
KPI rows 6–7 of the PRD met; KF-004 evidence row recorded.

---

## Sprint 3: Context discipline and instruction diet

**Global id:** 249 · **FR:** FR-3 · **SDD:** §1.4 (D-3.1 … D-3.3)

### Sprint Goal
One context-class table drives the context discipline (long by default, standard by detection or override), the reference-grade protocols load on demand, `CLAUDE.loa.md` and the protocol budget regain headroom, and the three skills stop choreographing parallelism — all without a recall regression on the replay gold sets.

### Deliverables
- `tool-result-clearing.md` two-class table + selection rule; `context_discipline` include rewritten; ten skills regenerated; `.run/context-class` written at SessionStart; `/loa` line.
- Protocol moves to `.claude/protocols/reference/` with pointers; `tools/check-prompt-budget.sh` set updated; `CLAUDE.loa.md` trimmed.
- Three skills' parallelism blocks replaced by one sentence.
- Replay A/B report (before on `main`, after on the branch) under the sprint's a2a directory.
- Tests, CHANGELOG entry, `reviewer.md`.

### Acceptance Criteria
- [x] `generate-skill-includes.sh --check` clean; `tools/check-prompt-budget.sh`: `CLAUDE.loa.md` ≤ 9,216 B, protocols ≤ 160,000 B, every skill ≤ 16,384 B.
- [x] `tool-result-clearing.md` shows both classes; the include cites the rule; `LOA_CONTEXT_CLASS=standard` and a 200K session model select `standard`; default `long`.
- [x] Replay A/B: no gold case loses recall; report attached. — **Waived: not met as pre-registered** (ruling below; Task 4.8 is the binding condition).
  - Review ruling (round 1, 2026-10-06, Fable 5.1): the pre-registered graded gate FAILS on five cases (grader citation-parser defect, bd-ewrc); on blind adjudication one slot in 27 is lost on audit-pr-02 (D06), inside the adjudicator's borderline band, with equal real-miss totals across arms and the include ablation pointing away. Accepted with a recorded waiver — binding conditions (bd-ewrc test-first + two-arm re-baseline before the cycle PR merges; component ablation and revert if the re-run loses; a NOTES Decision Log entry and a Sprint 4 task home) in `a2a/sprint-249/engineer-feedback.md` §"Replay A/B ruling". The audit rules independently.
- [x] The three skills are smaller than before and contain no `wc -l` parallelism gate.

### Technical Tasks
- **Task 3.1 — Baseline.** Run the replay gold sets on `main` and record.
- **Task 3.2 — Context class.** Protocol table, include, regen, SessionStart hook line + `.run/context-class`, `/loa` line, bats.
- **Task 3.3 — Diet.** Move the five protocols, pointers, budget tool set, `CLAUDE.loa.md` trim, hooks-reference row.
- **Task 3.4 — Skills.** Parallelism sentence in `auditing-security`, `implementing-tasks`, `reviewing-code`.
- **Task 3.5 — Gate and record.** Replay A/B after; budgets; REPO-MAP + sidecar + checksums; CHANGELOG; `reviewer.md`.

### Dependencies
Sprints 1–2 (no code dependency; ordering for budgets). Task 3.1 before 3.3.

### Security Considerations
No enforcement text is removed — only reference material moves and choreography shrinks; fence and gate rules stay where they are.

### Risks & Mitigation
| Risk | Mitigation |
|---|---|
| Recall regression | A/B gate; revert the specific move |
| A moved protocol is loaded by a skill path | grep every reference before moving; pointers keep the path readable |

### Success Metrics
KPI row 8 of the PRD met; A/B not worse.

---

## Sprint 4 (Final): Residue, registry, probes, docs and E2E

**Global id:** 250 · **FR:** FR-4 (+ docs, E2E for G-1 … G-5) · **SDD:** §1.5 (D-4.1 … D-4.5)

### Sprint Goal
No routing alias, fallback map, regex, trust entry, example pin or probe names the previous generation as current; the implement gate's authoritative mode is reachable; the permission checker reads both rule grammars; the migration guide and CHANGELOG describe the cycle; and the five goals are validated end to end on this repository.

### Deliverables
- `cheap` → `claude-sonnet-5`; bash maps and `--help`; Flatline regexes + stub; `gen-adapter-maps.sh` regen.
- `model-permissions.yaml` 5-family entries; `test_trust_scopes.py` coverage assertion.
- Example pins and defaults updated; Gemini pins to served ids.
- `implement-gate.sh` probe recorder; `detect-platform-features.sh` truthful; `.claude/data/agent-types.yaml`; `validate-skill-capabilities.sh` reads it.
- `check-permissions.sh` second grammar (CP-11/12).
- Docs: migration guide addendum (ceiling policy, temperature default, BB default model, companion voice, context class), CHANGELOG `[Unreleased]` per FR, README line.
- Full `tests/unit/` run with ledger hashes; REPO-MAP + sidecar + checksums; `reviewer.md` with E2E table.

### Acceptance Criteria
- [ ] `grep` for `claude-opus-4-`/`claude-sonnet-4-`/`gpt-4o` used as a default or described as current in live scripts, skills and data returns nothing (catalog fallback chains and tests excepted).
- [ ] Every Anthropic catalog entry has a `model-permissions.yaml` row (pytest).
- [ ] `implement-gate.bats`: a payload carrying `tool_input.active_skill` records `active_skill_seen_at` (lead session only; a teammate role writes nothing); the gate stays heuristic without `implement_gate.mode: authoritative`; with the opt-in, the authoritative branch passes the payload fixture corpus.
- [ ] CP-11/12: `Bash(git push *)` in allow satisfies `Bash(git push:*)`, in deny denies it; CP-13: mixed forms across layers, whitespace and escaping cases, and the dangerous-shape fuzz set behave per the grammar (narrower denies never cover the generic requirement).
- [ ] Docs present; budgets green; full unit run: no new red beyond the recorded pre-existing classes; ledger hashes unchanged.

### Technical Tasks
- **Task 4.1 — Failing tests.** `model-adapter.bats` (map), `flatline-model-validation.bats` (regexes admit the 5-family), `test_trust_scopes.py` coverage, `implement-gate.bats` probe, `check-permissions.bats` CP-11/12.
- **Task 4.2 — Aliases, maps, regexes.** Catalog `cheap`, `gen-adapter-maps.sh`, `model-adapter.sh`, `flatline-orchestrator.sh`.
- **Task 4.3 — Registry and pins.** `model-permissions.yaml`, `flatline-proposal-review.sh`, `alternative-model.md`, `hitl-jury-panel`, `loa-aleph`, Gemini agent pins.
- **Task 4.4 — Probes and agent types (SKP-008 / SKP-001 shape).** Research first: does the Claude Code hooks contract provide a harness-set skill signal a model-authored `tool_input` cannot forge? Then: evidence-only recorder (lead-only, once, records the field's source), truthful detect script, a forged-`active_skill` Write payload test that must not flip the gate, `implement_gate.mode` opt-in (default heuristic) documented only if the signal is harness-provided, `tests/fixtures/pretooluse-payloads/` corpus, `/loa` evidence line, `agent-types.yaml`, validator.
- **Task 4.5 — Permission grammar (SKP-010).** Formal normalisation (`Bash(<body>)` → key, trailing `:*`/` *` removed, trimmed, exact stays exact), deny precedence unchanged; CP-11/12 both forms, CP-13 table-driven mixed layers / whitespace / escaping / dangerous-shape fuzz.
- **Task 4.6 — Docs.** Migration addendum, CHANGELOG, README.
- **Task 4.7 — Regen and full run.** REPO-MAP + sidecar + checksums; full `tests/unit/` with ledger hashes before/after.
- **Task 4.8 — Recall grader and A/B re-run (bd-ewrc; binding condition of the Sprint 3 review waiver).** Test-first in `eval-recall-grader.bats`: a leading `(` stripped from a cited path, continuation and bare `:N` citations bound to the preceding path, `anchors[]` for multi-site defects (D13 776/807, D06 57/83). Then re-run both arms (`2079e719`, the Sprint 3 head) on the fixed grader at n ≥ 9 on review-pr-02/05 and audit-pr-02/03/05, before the cycle PR merges. If any case loses by > 1 slot, or audit-pr-02's D06 loss persists, ablate the CLAUDE.loa.md trim and the constraint-rationale rewrite as separate components and revert the implicated one. Report under G-3. Audit conditions (Sprint 3 audit, 2026-10-06, Fable 5.1): (a) pre-register the adjudication rule — including how a borderline slot counts — before any re-run trial, and require the fixed grader to agree with blind adjudication within 1 slot per case; (b) preserve the ablation commit `c9b7bdc0` (a ref under `record/`) and the scratch eval scripts under `a2a/sprint-249/`; (c) the Sprint 3 A/B AC stays qualified ("Waived") until the re-run passes.

### Task 4.E2E: End-to-End Goal Validation
| Goal | Evidence to produce |
|---|---|
| G-1 | cheval dry-run envelope for a 600K fixture to `claude-fable-5-1` (`input_ceiling.action: warn`); **one real ≈250K-token streaming call above the probed ceiling through this host's path (`claude-headless` subscription hop, or the API if a key exists) — success, or the observed limit recorded by the self-correction; an unclassified failure is a stop condition**; BB registry excerpt; `deriveTimeoutMs` output; Flatline cap log line |
| G-2 | a real two-voice dissent envelope from this host (`voices_planned 2`); the three fixtures' findings; a `verdict-derive` failure/success pair |
| G-3 | budget tool output before/after; A/B report; include diff |
| G-4 | the grep evidence; registry test output |
| G-5 | fence corpus run (60/60 dangerous, ≥ 80 % benign); kill-switch tests; full unit run summary |

### Dependencies
Sprints 1–3.

### Security Considerations
The probe recorder writes one word to `.run/` atomically and reads nothing else from the payload; agent-type list is data, not code; permission grammar change is symmetric for allow and deny (no widening without the matching deny).

### Risks & Mitigation
| Risk | Mitigation |
|---|---|
| A pin change routes a flow to a model the host cannot reach | aliases resolve through the catalog with fallback chains; E2E on this host |
| Full unit run turns up load-induced flakes | classify against the cycle-125 baseline; fix or record |

### Success Metrics
KPI row 9 of the PRD met; G-1 … G-5 evidenced; PR opened with `cycle-126` in the title.

---

## Risk Register

| # | Risk | Sprint | Owner | Mitigation |
|---|---|---|---|---|
| R1 | Uncalibrated ceiling meets a provider limit at runtime | 1 | lead | warn recorded; kill switch; probe stays operator's |
| R2 | Companion voice cost/time | 2 | lead | parallel; subscription-billed hop |
| R3 | Instruction diet regression | 3 | lead | replay A/B gate |
| R4 | Dist/registry drift | 1, 4 | lead | build + manifest per commit |
| R5 | Unattended run spends quota / mutates defaults (sprint dissent SKP-001) | all | operator authorization | recorded constraints: per-dissent `budget_cents`, no publication, no merge before CI + Bridgebuilder triage; stop conditions: unclassified provider failure on the live call, eval A/B regression, any fence weakening, operator-only credential need |

## Success Metrics Summary

All nine KPI rows of the PRD; every sprint closed with review + audit approvals and dissent envelopes; budgets green with headroom; PR CI green; Bridgebuilder pass triaged; merge without publication.

## Dependencies Map

Sprint 1 → Sprint 2 (ceiling helper, catalog) → Sprint 3 (budgets after text changes) → Sprint 4 (docs and E2E over everything).

## Appendix

### A. PRD Feature Mapping

| PRD requirement | Sprint | Tasks |
|---|---|---|
| FR-1.1 ceiling policy | 1 | 1.1, 1.2 |
| FR-1.2 beta headers | 1 | 1.3 |
| FR-1.3 output defaults / temperature / read timeout | 1 | 1.1, 1.3 |
| FR-1.4 token estimation | 1 | 1.3, 1.6 |
| FR-1.5 Bridgebuilder | 1 | 1.1, 1.4 |
| FR-1.6 Flatline caps | 1 | 1.5 |
| FR-1.7 health probe | 1 | 1.3 |
| FR-1.8 transport matrix | 1 | 1.1 |
| FR-1.9 cost visibility | 1 | 1.7 |
| FR-2.1 companion voice | 2 | 2.1, 2.3 |
| FR-2.2 tolerant schema | 2 | 2.1, 2.2 |
| FR-2.3 reviewer contract | 2 | 2.4 |
| FR-2.4 repair loop | 2 | 2.5 |
| FR-3.1 context-class table | 3 | 3.2 |
| FR-3.2 instruction diet | 3 | 3.3, 3.4 |
| FR-3.3 eval gate | 3 | 3.1, 3.5 |
| FR-4.1 aliases and maps | 4 | 4.1, 4.2 |
| FR-4.2 governance registry | 4 | 4.1, 4.3 |
| FR-4.3 example pins | 4 | 4.3 |
| FR-4.4 probes | 4 | 4.1, 4.4 |
| FR-4.5 permission grammar | 4 | 4.1, 4.5 |
| G-1 … G-5 | 4 | 4.E2E |

### B. Goal Mapping

| Goal | Delivered by | Validated in |
|---|---|---|
| G-1 Full size on the wire | Sprint 1 (Tasks 1.2–1.5) | Task 4.E2E |
| G-2 Two voices, nothing dropped | Sprint 2 (Tasks 2.2–2.4) | Task 4.E2E |
| G-3 Context discipline that fits the model | Sprint 3 (Tasks 3.2–3.4) | Task 4.E2E |
| G-4 Current generation everywhere | Sprint 4 (Tasks 4.2–4.5) | Task 4.E2E |
| G-5 No safety regression | every sprint (fence corpus, kill-switch tests) | Task 4.E2E, Task 4.7 |
