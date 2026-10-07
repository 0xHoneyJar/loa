# Software Design Document: Loa Full Size (cycle-126)

**Version:** 1.0
**Date:** 2026-09-24
**Status:** Draft — autonomous run (operator instruction: *"proceed"*)
**PRD:** `grimoires/loa/prd.md` (cycle-126) · **Evidence:** `grimoires/loa/reports/model-era-audit-2026-09-24.md`
**Branch:** `feature/cycle-126-full-size` from `main` `2079e719`

## Table of Contents

1. [Project Architecture](#1-project-architecture)
2. [Software Stack](#2-software-stack)
3. [Database Design](#3-database-design)
4. [UI Design](#4-ui-design)
5. [API Specifications](#5-api-specifications)
6. [Error Handling Strategy](#6-error-handling-strategy)
7. [Testing Strategy](#7-testing-strategy)
8. [Development Phases](#8-development-phases)
9. [Known Risks and Mitigation](#9-known-risks-and-mitigation)
10. [Open Questions](#10-open-questions)
11. [Appendix](#11-appendix)

## 1. Project Architecture

### 1.1 Principle

Every size-related decision (input ceiling, output default, reasoning budget, review truncation, context-discipline class) derives from the **catalog entry actually resolved** (`.claude/defaults/model-config.yaml`), through the generators the repository already has (`gen-adapter-maps.sh` → `generated-model-maps.sh`; `gen-bb-registry.ts` → `truncation.generated.ts` / `config.generated.ts`; `generate-skill-includes.sh` → skill include blocks). No new configuration key is introduced; new catalog fields are additive; every behaviour change has an env kill switch that restores the pre-cycle behaviour. The framework's own model floor (the 5-family) is the default assumption; the 200K class remains available by detection or override.

### 1.2 FR-1 — Full-size adapters, Bridgebuilder, Flatline

**1.2.1 Ceiling policy (D-1.1, rewritten after the Flatline SDD dissent).** `cheval.py`'s capability builder (`_capability_for`, around `cheval.py:570-600`) and gate (`_preflight_decide`, `:625-650`) today read one literal and `preempt` above it. Change:

- **Invariant I1 (SKP-001).** `estimate + max_tokens_on_wire ≤ context_window`. `_preflight_decide` receives the resolved `max_tokens`; when I1 fails it shrinks `max_tokens` to `context_window − estimate` (floor 4,096; envelope `max_tokens_shrunk: {from, to}`), and `preempt`s (`CONTEXT_TOO_LARGE`) only when the floor cannot fit. The probed 180,000 is **never** combined with `max()`; it is an input bound valid only within I1.
- **Invariant I2 (SKP-002 — default inverted).** Input bound = `calibrated_ceiling` when `ceiling_calibration.calibrated_at` is set; else `probed_ceiling` (180,000). The catalog-derived bound `context_window − max_tokens_on_wire` applies only (a) after calibration, or (b) under `LOA_CHEVAL_UNCALIBRATED_CEILING=derived`, in which case a request above the probed bound proceeds with `action: warn` if the count endpoint confirmed the size or the estimator uncertainty is `low` (a `high` estimate `preempt`s with a calibration message), never above the derived bound. `LOA_CHEVAL_LEGACY_CEILING=1` restores today's exact behaviour (single literal, `preempt`). The 36K `_LEGACY_TRANSPORT_INPUT_WALL` is untouched. CLI hops carry no HTTP ceiling (unchanged).
- **Catalog.** Additive fields per Anthropic HTTP entry: `probed_ceiling: 180000`, `ceiling_calibration: {source: kf_derived, calibrated_at: null, stale_after_days: 90}` (unchanged), `account_limits: {tier: unverified, itpm: null}`; `effective_input_ceiling` stays as the *calibrated-or-probed* value the v3 readers expect (so older readers keep 180,000). `tools/ceiling-probe-live.py` gains `--write-catalog` to set `calibrated_at`, the calibrated value and `account_limits` in one operator run; the catalog test asserts I1/I2 per entry from the fields.
- **Self-correction (D-1.1b, PRD SKP-001/002).** `retry.py` classifies a provider context/size error (HTTP 400 with a prompt-too-long class, 413) or a token-limit 429 on a request that proceeded above the probed bound as `CEILING_UNVERIFIED_LIMIT`: one retry at most, then the error propagates **without walking the fallback chain** (context-length errors are non-walkable — the same payload would fail the next voice too); `cheval.py` appends `{provider, model, observed_input_tokens, error_class, ts}` to `.run/ceiling-observed.json` (atomic, lead-written) and emits a `calibration_needed` trajectory record naming the probe command; `effective_ceiling()` returns the observed bound (source `observed`) for that entry until calibration. `loa-status.sh` Providers block prints `ceiling: probed 180000 (calibrate: tools/ceiling-probe-live.py)` or `observed …`.
- **Shared helper.** `loa_cheval/routing/ceiling.py` — `input_bound(entry, *, max_tokens, observed=None, policy) -> CeilingDecision(value, basis: calibrated|probed|derived|observed, calibrated: bool)` used by cheval, the Flatline cap resolver and (through the generated registry) Bridgebuilder.
- **Billable-input guard (sprint SKP-002).** `LOA_CHEVAL_MAX_INPUT_TOKENS` (env) caps the input bound below the catalog for any entry; default = the entry's bound.

**1.2.2 Long-context headers (D-1.2, amended per sprint SKP-014).** `params.beta_headers: []` per entry; `anthropic_adapter.py` validates each value against `^[a-z0-9]+(-[a-z0-9]+)*-\d{4}-\d{2}-\d{2}$`, rejects the entry (config error, exit `INVALID_CONFIG`) on a mismatch, never derives a header from a request, joins the list into one `anthropic-beta` header and logs the active list in the non-secret diagnostics. No entry sets it in this cycle; the operator's probe run fills it if the account needs one.

**1.2.3 Output defaults (D-1.3).** `default_max_tokens(provider, model_max_output)` in `base.py:168-186`: for **any** provider, when `model_max_output` is declared, return `min(transport_cap, model_max_output)` where `transport_cap` is 64,000 (streaming) / 16,000 (non-streaming) for Anthropic and 16,000 for other providers (OpenAI reasoning models accept far more but the golden request bodies for `gpt-*` fixtures must not move unexpectedly — the cap is a constant named `_NON_ANTHROPIC_DEFAULT_OUTPUT_CAP` and tested); 4,096 only when nothing is declared or under `LOA_CHEVAL_LEGACY_WIRE=1`. `types.py` `CompletionRequest.temperature` becomes `Optional[float] = None`; adapters emit `temperature` only when set (legacy wire: 0.7 as before). `_nonstreaming_read_timeout()` uses the resolved `max_tokens` (the value put on the wire), not the 4,096 literal.

**1.2.4 Token estimation (D-1.4, amended per Flatline SKP-004).** `base.estimate_tokens` gains an Anthropic path: when `provider == "anthropic"` and a key is present and `estimate ≥ 0.9 × ceiling`, call `POST /v1/messages/count_tokens` (same headers as the request) and use its `input_tokens`; on any failure fall back to the heuristic. The heuristic (`chars / 3.5`) stays, and the request envelope records `estimator: {method, chars, tokens, uncertainty}` where `uncertainty = high` when > 20 % of the bytes are non-ASCII or the request carries tool payloads (the two content classes where `chars / 3.5` underestimates), else `low`. Gate rule (SDD SKP-003): the derived bound is never exceeded on an estimate (no slack); above the probed bound — reachable only under the opt-in — a count-endpoint result is authoritative, a `low`-uncertainty heuristic warns, a `high` one `preempt`s with a calibration message. Fixtures: ASCII prose (heuristic ≥ true count), CJK-dense and emoji-dense text and a tool-payload request (heuristic < true count, flagged `high`). `lib-multipass.sh`'s `encoding_for_model('gpt-4')` is replaced by the same `chars / 3.5` bound for Anthropic passes.

**1.2.5 Bridgebuilder (D-1.5).** `scripts/gen-bb-registry.ts`: read `max_output_tokens`, `params.thinking_adaptive`, `capabilities` from each yaml entry; emit `maxOutput = min(max_output_tokens ?? providerDefault, BB_OUTPUT_CAP)` with `BB_OUTPUT_CAP = 32_000`, `maxInput = derivedCeiling − 20_000` (the ceiling helper's value, i.e. 852,000 for the 5-family — BB's own `maxInputTokens` config still bounds the payload it builds, default raised 128,000 → 200,000), and a `reasoning: boolean` per model (`thinking_adaptive === true || capabilities.includes("thinking_traces")`). `multi-model-pipeline.ts` `isReasoningClass` becomes `GENERATED_REASONING[modelId] ?? legacy regexes`. `config.ts` `DEFAULTS.model = "opus"` (resolved by the existing alias path; `SKILL.md:98` updated); persona headers use aliases. `npm run build` regenerates `dist/` and the freshness manifest.

**1.2.6 Flatline caps (D-1.6).** `flatline-orchestrator.sh`: `call_model` resolves the voice's catalog entry through `generated-model-maps.sh` and sets `--max-tokens min(64000, max_output_tokens)`; the two 16,000 literals and the dead `PER_CALL_MAX_TOKENS` are removed; a bats case asserts the value per voice.

**1.2.9 Cost visibility (D-1.9, Flatline SDD SKP-003).** `pricing.py`: `PricingEntry` gains `long_context_threshold`, `long_context_input_multiplier`, `long_context_output_multiplier` (from `pricing.long_context` in the catalog; `None` when absent); `calculate_total_cost` applies the multipliers to the whole request when `input_tokens > threshold` (the provider's published rule for 1M-window models); the 5-family entries carry the published tier as `reference` values with the same `verified: false` marker the catalog uses elsewhere; `cost-report.sh` shows `long_context_rows`. Companion voice: `adversarial-review.sh` passes the same `budget_cents` to each voice (each ≤ budget; the envelope records per-voice cost). Per-gate expected cost, catalog rates (Fable/Opus 5 $5/$25 per Mtok, Sonnet 5 $2/$10, Haiku 4.5 per catalog; premium multipliers when published):

| Gate / call | Today (per call) | After (default policy) | After (calibrated or opt-in, worst case) |
|---|---|---|---|
| Flatline review voice (Opus 5) | ≤ 180K in × $5 + 16K out × $25 ≈ $1.30 | same input; output ≤ 64K ≈ $2.50 | 872K in (premium) + 64K out ≈ $10 + premium |
| Dissent (review/audit) | 1 voice, `budget_cents` 150/200 | 2 voices, each ≤ `budget_cents` | same |
| Scorer (`cheap` → `tiny`) | Sonnet 4.6 per call | Haiku 4.5 per call (cheaper) | — |
| Bridgebuilder pass | Opus 4.7, 160K in / 8K out | Opus 5.5 (`opus` → `claude-opus-5-5`, D-4.1 amendment; BB alias budget 160K in / ≤ 32K out at $4 / $20 per MTok) ≈ $1.3 | — |

The budget enforcer's per-day cap and the breaker are unchanged and now see correct prices for large calls; the SDD records that the operator sets `cost_budget_enforcer` if daily spend must be capped.

**1.2.8 Transport matrix (D-1.8, Flatline SKP-003).** `tests/test_transport_matrix.py` builds one table over (`anthropic`, `openai`, `google`) × (`http-stream`, `http-legacy`, `cli-hop`) and asserts, through the real code paths with mocked transports, the effective input ceiling, output default, read timeout, `anthropic-beta` header and token-count method each path applies; the BB registry and the Flatline cap resolver are asserted against the same table. The catalog entry carries `account_limits: {tier: unverified, itpm: null}` for the 5-family until the operator's probe fills it.

**1.2.7 Health probe (D-1.7).** `anthropic_adapter.health_check()` calls `GET /v1/models?limit=1`; on 404 (older gateways) it sends a one-token message to the id the `tiny` alias resolves to. No literal model id remains in the adapter.

### 1.3 FR-2 — Two voices and no dropped findings

**1.3.1 Second voice (D-2.1).** `adversarial-review.sh` today walks one chain (`primary → fallback_chain | models.secondary/tertiary`) and stops at the first success; the aggregator (`loa_cheval.verdict.aggregate`) already merges N per-attempt envelopes and reports `voices_planned/succeeded`. Change: a second, independent chain — the **companion voice** — chosen by provider family: if the primary chain's first success is OpenAI-family, the companion is the Anthropic chain (`opus` → `claude-headless`); if it is Anthropic-family, the companion is the OpenAI chain (`gpt-5.5-pro` → … → `codex-headless`). Each chain walks as today; the two successful envelopes are aggregated (`voices_planned = 2`). A companion whose entire chain fails is recorded as a dropped voice (existing `voices_dropped` semantics — degraded, never blocking a `review`; `audit` keeps its degraded rules). Credential presence is checked the way `run-preflight.sh` P3 does (env → `.env.local` → `.env`, presence only) and decides only which chain to *start*; the companion's outcome comes from the actual completion (sprint SKP-004): `metadata.companion_voice: {planned, model, status: succeeded|failed, failure_class: auth|model_unavailable|quota|timeout|malformed|null, cost_cents}`; `voices_succeeded_ids` lists only completed voices. An HTTP Anthropic voice with no key is skipped straight to `claude-headless`. Opt-out: `flatline_protocol.{code_review,security_audit}.companion_voice: false` (default true; documented in `.loa.config.yaml.example` — an additive key on an existing block, not a new configuration surface, per the constraint's spirit; recorded as a decision).

**1.3.2 Tolerant schema (D-2.2).** `validate_finding` / `_validate_finding_reason` (`adversarial-review.sh:296-352`): `failure_mode` moves from required to **derivable** — before validation, a normalisation step fills a missing/empty `failure_mode` with the first sentence of `description` (≤ 200 chars) and sets `failure_mode_derived: true`; validation then proceeds unchanged for id/severity/category/description. Findings that still fail are written to the sidecar as today **and** summarised into `metadata.rejected_summary[]` (`{severity, title, anchor, reason, description_head}`) of the envelope. The envelope schema (`.claude/data/trajectory-schemas/…adversarial…`) gains the additive array.

**1.3.3 Reviewer contract (D-2.3).** `reviewing-code` and `auditing-security` SKILL.md (within budget: the text replaces the existing "rejected payloads" prose) require a `## Rejected dissent payloads` section whenever `rejected_summary` is non-empty; `verdict-derive.sh` gains a check: when the sprint's envelope has `rejected_summary.length > 0` and the feedback file lacks the section, the trailer is INCONSISTENT (exit 1) with a repair message. `adversarial-review-gate.sh` is unchanged.

**1.3.4 Repair loop (D-2.4).** `_repair_finding_via_model` resolves its model as `tiny` when an Anthropic key is present, else `claude-headless`; the KF-004 fixtures (the three real rejected payloads, scrubbed) live under `tests/fixtures/dissent-rejected/` and drive both the normaliser test (D-2.2 produces findings without the repair) and a repair-loop test with a stubbed model.

### 1.4 FR-3 — Context discipline and instruction surface

**1.4.1 Context-class table (D-3.1).** `.claude/protocols/tool-result-clearing.md` becomes a two-column table (`standard` / `long`) with the selection rule; `.claude/data/skill-includes/context_discipline.md` is rewritten to cite the class rule and the `long` numbers in one line (byte-neutral or smaller); `generate-skill-includes.sh --write` regenerates the ten skills. Class detection: `long` unless `LOA_CONTEXT_CLASS=standard` or the session model (when the harness exposes it in the SessionStart payload — `loa-run-state-surface.sh` already parses that payload) resolves to a catalog entry with `context_window ≤ 200000`; the SessionStart hook writes `.run/context-class` and the include text tells the model to read it when unsure. No hook blocks on it.

**1.4.2 Instruction diet (D-3.2).** `CLAUDE.loa.md`: the Reference Files table already points at `.claude/loa/reference/*`; the protocols named in the audit are moved under `.claude/protocols/reference/` (out of the budgeted set, still readable on demand) with a one-line pointer where they were cited; `tools/check-prompt-budget.sh` counts only the load-bearing protocols. The three skills' `wc -l` parallelism blocks become one sentence ("Parallelise (`parallel_threshold`) when the scope warrants; the lead decides"). Net: protocols ≤ 160,000 B (≥ 20 % headroom), `CLAUDE.loa.md` ≤ 9,216 B. *(Superseded for `CLAUDE.loa.md` by Sprint 4 Task 4.8: the trim was reverted under the pre-registered recall rule, and the limit is 10,240 B again; the protocol figure stands.)*

**1.4.3 Eval gate (D-3.3).** `tests/replay/run_replay.sh` with the review/audit gold sets (cycle-124 sprint-3 parity harness) runs before (baseline on `main`) and after; the report is attached under the sprint's a2a directory; a recall drop on any gold case blocks the sprint.

### 1.5 FR-4 — Routing residue, governance registry, probes

- **D-4.1** `aliases.cheap: anthropic:claude-sonnet-5`; `tier_groups.mappings.mid` follows; `jam-synthesizer` and `translating-for-executives` stay on `cheap`, `flatline-scorer` too (scoring is not latency-bound); `gen-adapter-maps.sh` regenerates the bash maps; `model-adapter.sh` `MODEL_TO_ALIAS` gains `opus → claude-opus-5`, `fable`, `claude-sonnet-5`, `claude-opus-5`, `claude-fable-5-1` and its `--help` text; `flatline-orchestrator.sh` regexes: `^claude-(opus|sonnet|haiku|fable)-[0-9]+([-.][0-9]+)?$`, `^(opus|sonnet|haiku|fable)$`, `^gpt-[0-9]+\.[0-9]+(-codex|-pro)?$`; the stub allowlist lists the 5-family.
- **D-4.2** (sprint SKP-002 checked: the registry is read only by `routing/context_filter.py` and the two migration scripts; no signature, digest or trust-store reference covers it — the signed trust store is a different artefact — so the edit needs no operator signing) `model-permissions.yaml`: entries for `anthropic:claude-opus-5`, `anthropic:claude-sonnet-5`, `anthropic:claude-fable-5-1`, `anthropic:claude-opus-4-8`, `bedrock:us.anthropic.claude-opus-4-8` copied from the 4.7 scopes; comments updated; `test_trust_scopes.py` asserts every catalog Anthropic entry has a registry row.
- **D-4.3** Pins: `flatline-proposal-review.sh` default `reviewer` alias; `alternative-model.md` example `bedrock:us.anthropic.claude-opus-4-8`; `hitl-jury-panel` / `loa-aleph` examples `opus`; `deep-thinker` / `fast-thinker` → the Gemini ids the catalog serves (`gemini-3.1-pro`, `gemini-3.1-flash` if present, else `gemini-2.5-pro` kept with a comment).
- **Amendment 2026-10-06 (Sprint 4, bead `bd-2fti`; sprint-250 review round 1, Observations 2 and 5).** D-4.1's `opus → claude-opus-5` was superseded during Sprint 4. The catalog gained a `claude-opus-5-5` entry, sourced from the vendor models and pricing pages on 2026-10-05: 1M input / 128K output, $4 / $20 per MTok, no long-context tier, and the conservative probed 180K ceiling marked `loa:shortcut`. Its `fallback_chain` is `anthropic:claude-opus-5`. `aliases.opus`, the generated maps, `MODEL_TO_ALIAS`, the BB alias table and `.loa.config.yaml.example` all resolve `opus` to `claude-opus-5-5`, pinned by RES-1/RES-2, MA-1/MA-4 and codegen T13. Effort is sent only when a caller passes one, so `opus` callers that pass none get Opus 5.5's model-side default (migration guide caveat). The D-4.3 deviation: the `loa-aleph` example stays `claude-opus-4-8` under the standing Aleph policy, since Aleph is opt-in and not edited by Loa cycles. 4.8 is still served and pinnable, so PRD FR-4.3 is met.
- **D-4.4 (amended per Flatline SKP-008)** Probe: a 12-line evidence recorder at the head of `implement-gate.sh` (no new hook) writes `{active_skill_seen_at}` to `.run/platform-features.json` atomically **only when no agent-teams teammate role is set** (lead-only `.run/` writes) and only once. `detect-platform-features.sh` drops the imaginary env var, reports the evidence, and never sets `active_skill_available: true` on its own. Authoritative mode requires `implement_gate.mode: authoritative` in `.loa.config.yaml` (an additive key; default `heuristic`; documented next to the evidence line `/loa` prints); the authoritative branch is tested against `tests/fixtures/pretooluse-payloads/` (real payload shapes with and without `active_skill`, nested `/run` dispatch) before the key is documented. `validate-skill-capabilities.sh` reads `WRITE_CAPABLE_AGENTS` from `.claude/data/agent-types.yaml` (new small data file listing the harness agent types with a `write_capable` flag: `general-purpose`, `claude`, `fork`, `loa-scout: false`, `Plan: false`, `Explore: false`, `prompt-auditor*: false`).
- **D-4.5 (sprint SKP-010).** Formal grammar: a rule `Bash(<body>)` normalises to key `<body>` with a trailing `:*` or ` *` removed and surrounding whitespace trimmed; `<body>` without a wildcard is an exact rule; no other rewriting (no glob expansion, no quoting changes). Required rules normalise the same way; a rule covers a requirement when the keys are equal or the rule's key equals the requirement's first word (base wildcard). Deny precedence is unchanged at every layer. Tests: both forms in allow and in deny, mixed forms across layers, whitespace/escaping cases, and a fuzz set of dangerous shapes (narrower denies never cover the generic requirement; generic denies cover every subcommand); CP-11/CP-12 plus a table-driven CP-13.

## 2. Software Stack

Bash 5 (scripts, hooks), Python 3 (`loa_cheval`, `.venv`), TypeScript / Node 22 (Bridgebuilder, `npm run build` → `dist/`), jq, yq (Mike Farah), bats, pytest, `tsx --test`. No new dependency.

## 3. Database Design

No database. Files touched: catalog YAML (additive fields `probed_ceiling`, `params.beta_headers`), generated maps/registry, `.run/platform-features.json` and `.run/.active-skill-probe` (existing), `.run/context-class` (new, one word), `.claude/data/agent-types.yaml` (new), dissent envelopes (additive `rejected_summary`, `input_ceiling`).

## 4. UI Design

Command-line only. New operator-visible strings: cheval WARN line `input_ceiling: derived 872000 (probed 180000, uncalibrated) — proceeding`; Bridgebuilder log names the alias-resolved model; `## Rejected dissent payloads` in feedback files; `Context class: long|standard` line in `/loa`. `--json` shapes are additive.

## 5. API Specifications

- `loa_cheval.routing.ceiling.effective_ceiling(entry: dict, *, legacy: bool = False) -> CeilingDecision(value:int, probed:int|None, calibrated:bool, source:str)`.
- `default_max_tokens(provider, model_max_output)` (unchanged signature, new semantics per D-1.3).
- `anthropic_adapter.count_tokens(request) -> int | None` (D-1.4).
- `gen-bb-registry.ts` output: `GENERATED_TOKEN_BUDGETS[model] = {maxInput, maxOutput, coefficient}` + `GENERATED_REASONING[model]: boolean`.
- `adversarial-review.sh` envelope: `metadata.rejected_summary[]`, `metadata.companion_voice: {planned, model, status}`; `verdict_quality.voices_planned` reflects both chains.
- `verdict-derive.sh --file F --gate review|audit [--envelope E]`: the envelope path defaults to the sprint's `adversarial-<gate>.json` beside the feedback file.
- `check-permissions.sh` rule grammar: `Bash(<cmd>:*)` ≡ `Bash(<cmd> *)`.

## 6. Error Handling Strategy

Fail-closed where today: `preempt` above the derived ceiling, above the 36K wall in legacy transport, and everywhere under the kill switch. Warn-and-proceed only in the one named case (uncalibrated entry, between probed and derived ceiling), always logged and recorded in the envelope. A companion voice whose chain fails degrades (recorded), never silently. Count-endpoint failures fall back to the heuristic. A finding that cannot be normalised is never dropped silently again: sidecar + `rejected_summary` + mandatory triage section.

## 7. Testing Strategy

Test-first per sprint. FR-1: `test_anthropic_catalog_floor.py` (formula per entry), `test_input_size_consumers.py` (SIZES extended to 600,000 and 900,000 with the three actions), new `test_ceiling_policy.py` (warn/preempt/kill switch), `test_max_tokens_defaults.py` (all providers), `test_temperature_default.py`, `test_count_tokens_fallback.py`, `test_health_probe.py`; BB `__tests__/truncation-registry.test.ts`, `timeout.test.ts` (`deriveTimeoutMs` for the 5-family), `config.test.ts` (default model); bats `flatline-max-tokens.bats`. FR-2: `adversarial-review-normalise.bats` (three fixtures → findings), `adversarial-review-companion.bats` (stubbed cheval: two envelopes aggregated; keyless host plans `claude-headless`), `verdict-derive.bats` (section enforcement). FR-3: `skill-includes.bats` (`--check`), `prompt-budget.bats`, replay A/B report. FR-4: `model-adapter.bats`, `flatline-model-validation.bats`, `test_trust_scopes.py`, `implement-gate.bats` (probe recorder), `check-permissions.bats` CP-11/12. Every sprint: fence corpus run, `repo-map-gen.sh --validate`, checksums `--check`, `tools/check-prompt-budget.sh`, full `tests/unit/` in the final sprint.

## 8. Development Phases

Sprint 1 FR-1 (D-1.1 … D-1.7) · Sprint 2 FR-2 (D-2.1 … D-2.4) · Sprint 3 FR-3 (D-3.1 … D-3.3) · Sprint 4 FR-4 (D-4.1 … D-4.5) + migration addendum + CHANGELOG + E2E goal validation (G-1 … G-5). Each sprint: implement → `/review-sprint` (dissent) → `/audit-sprint` (dissent) → COMPLETED; a2a under global ids; records to `record/cycle-126-a2a`.

## 9. Known Risks and Mitigation

| Risk | Mitigation |
|---|---|
| The account cannot actually take the derived bound | default policy never sends above the probed bound; opt-in path has count-token confirmation, one bounded retry, `CEILING_UNVERIFIED_LIMIT`, non-walkable context errors, observed-bound downgrade + `calibration_needed`; probe `--write-catalog` is the one-run operator step |
| Cost blast radius of larger inputs, outputs and a second voice | long-context pricing tier, per-voice `budget_cents`, `LOA_CHEVAL_MAX_INPUT_TOKENS`, cost table above; the daily enforcer is the operator's hard cap |
| BB `dist/` freshness check | rebuilt in the same commit; `tools/check-bb-dist-fresh.sh --write-manifest` |
| Golden request bodies for OpenAI fixtures move with D-1.3 | non-Anthropic cap constant tested; fixtures updated deliberately with the diff shown in the report |
| Companion voice doubles dissent wall time | headless voice runs in parallel with the primary chain (background subshell + wait), bounded by the existing per-voice timeout |
| Temperature default change | documented; legacy wire restores 0.7 |
| Instruction diet regresses recall | replay A/B gate; revert the specific protocol move |
| `verdict-derive.sh` stricter check breaks old feedback files | only applies when an envelope with `rejected_summary` exists beside the file |

## 10. Open Questions

0. Flatline dissent on the PRD, this SDD and the sprint plan is integrated (PRD appendix tables); amended decisions: D-1.1 (I1/I2, default inverted, opt-in, non-walkable context errors), D-1.1b, D-1.2 allowlist, D-1.4 no slack, D-1.9 cost, D-2.1 completion-based status, D-4.4 spoofability, D-4.5 grammar; refuted with evidence: trust-store signing of the registry; refuted as process: approval gates inside the unattended run.
1. Whether the 5-family 1M window needs an `anthropic-beta` value on this account — answered by the operator's first large call or the probe; the catalog field exists either way.
2. Whether the harness exposes the session model in the SessionStart payload — if not, class detection stays `long` by default with the env override (recorded, not blocking).
3. `companion_voice` is an additive key on an existing block; if the maintainer prefers zero new keys, the default-on behaviour stands and the key is dropped (one-line change).

## 11. Appendix

### A. Catalog values used by the ceiling formula
Fable 5.1 / Opus 5 / Sonnet 5: `context_window 1,000,000`, `max_output_tokens 128,000` → derived 872,000; Opus 5.5 (`claude-opus-5-5`, the `opus` default after the D-4.1 amendment): the same 1,000,000 / 128,000 → derived 872,000, held at the conservative `probed_ceiling` 180,000 (`loa:shortcut`) until the operator-only live probe raises it; 4.x entries: `context_window 200,000`, probed 180,000 → 180,000; Haiku 4.5: 200,000 − 64,000 = 136,000 < probed → 180,000.

### B. Byte headroom at design time
`CLAUDE.loa.md` 10,225 / 10,240; protocols 199,593 / 200,000; 12 skills within 400 B of 16,384 (audit §3).

### C. Fixtures for D-2.2
`grimoires/loa/a2a/sprint-bug-245/adversarial-rejected-audit.jsonl` rows 1–2 and the cycle-125 sprint-241 rejected review row, scrubbed of paths outside the repository.
