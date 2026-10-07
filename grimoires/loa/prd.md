# Product Requirements Document: Loa Full Size (cycle-126)

**Version:** 1.0
**Date:** 2026-09-24
**Status:** Draft — autonomous run (operator instruction: *"proceed"*, after the model-era assessment)
**Author:** Loa lead agent (Fable 5.1) for Jani (maintainer)
**Branch:** `feature/cycle-126-full-size` from `main` `2079e719` (`v2.0.0-rc.2` + cycle-125 follow-ups)

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

> Sources: document structure per `discovering-requirements` Phase 8 template (`prd-template.md`).

## Executive Summary

Loa's own floor is the Claude 5 generation (Opus 5, Sonnet 5, Fable 5.1: 1M-token context, 128K output, adaptive thinking), yet the framework still runs those models through constants and code paths sized for the 200K-context / 4K-output / non-thinking generation. The model-era audit of 2026-09-24 found nine direct caps (a 180K input ceiling on 1M-context entries, an 8K Bridgebuilder output table on 128K models, a reasoning-class test that excludes Fable 5.1 and Sonnet 5, 16K Flatline caps shared with thinking, a 4K default for non-Anthropic hops, an OpenAI-encoding token estimator that gates Anthropic requests, a retired probe id), a cross-model review that plans one voice and silently drops schema-rejected findings (three of five were real defects this week), a skills-wide context discipline that tells a 1M-context model to stop at 15K tokens, instruction budgets at their ceilings, and routing/governance tables that still name the previous generation as current. This cycle removes those limits, test-first, without weakening any safety property, and lands as the next release candidate without publishing it.

> Sources: `grimoires/loa/reports/model-era-audit-2026-09-24.md` §1–§7 (verified `file:line` findings and measurements); `grimoires/loa/context/cycle-126-brief.md` (operator prompt); maintainer instruction "proceed" 2026-09-24.

## Problem Statement

### The Problem

The framework caps the current models below their size, reviews them with one voice while dropping findings, and instructs them with 200K-era context rules.

### User Pain Points

1. **cheval refuses inputs above 180K tokens** to models declared at 1,000,000 (`effective_input_ceiling: 180000`, exit 7), so `/ride`, red-team and jam flows cannot use the context the models have; the ceiling was probed on the previous generation and never re-probed (`calibrated_at: null`).
2. **Bridgebuilder reviews run on `claude-opus-4-7` by default, truncated to 8,192 output tokens, and on the 120–300 s timeout ladder for Fable 5.1 and Sonnet 5** because the truncation table is a codegen literal and `isReasoningClass` matches only `/opus/`.
3. **Flatline voices are capped at 16K tokens including thinking**, on models with 128K output.
4. **Every non-Anthropic hop defaults to 4,096 output tokens**, the dataclass default temperature is dropped with a warning on every thinking model, and Anthropic requests can be rejected pre-flight on an OpenAI-encoding token estimate.
5. **Cross-model review plans one voice** (12 of 12 dissents in the last 24 h: `voices_planned: 1`, `codex-headless` only) because the configured Anthropic voice needs an API key this host does not have, and **five dissent findings were rejected on a missing `failure_mode` and written to a sidecar the reviewer never sees** — three were real defects, caught only by hand.
6. **The context discipline baked into ten skills** (2K/5K/3K tokens, "session total 15,000 → STOP and synthesize to NOTES.md") forces lossy round-trips through NOTES for work that fits in a 1M context; the protocol and `CLAUDE.loa.md` budgets sit at 99.8 % and 99.9 %, so nothing can be added without deleting.
7. **Routing and governance residue**: `cheap` → Sonnet 4.6 feeds three roles; the bash fallback map sends `opus` to 4.7; Flatline's forward-compat regexes reject every 5-family id; `model-permissions.yaml` has no 5-family entries and calls 4.7 "current default"; the platform-feature probe always reports `active_skill_available: false`, so the implement gate's authoritative mode is dead code.

### Current State

Adapters emit adaptive thinking, effort, structured outputs and one cache breakpoint correctly (cycle-124), fences are precise (cycle-125), and the enforcer measures the day it certifies (sprint-bug-245). The remaining gap is *size*: ceilings, caps, defaults, tables and thresholds that predate the 5-family, plus a review pipeline that does not use the second voice it could have.

### Desired State

A request to a 1M-context model is limited by the catalog, not by a probed 4.x constant; Bridgebuilder, Flatline and cheval defaults derive from the catalog entry actually resolved; every dissent on a subscription-only host has two voices and no finding disappears without the reviewer seeing it; skills' context guidance scales with the session model's context class; budgets have headroom again; every routing and governance table names the current generation.

> Sources: audit §1 table C1–C9 (`.claude/defaults/model-config.yaml:376`, `cheval.py` ceiling gate, `truncation.generated.ts:20-34`, `config.ts:168`, `multi-model-pipeline.ts:52-71`, `flatline-orchestrator.sh:127-128`, `base.py:163-186`, `base.py:837-861`, `anthropic_adapter.py:562`); audit §2 (12 dissent envelopes, `adversarial-rejected-*.jsonl`, KF-004 rec 31); audit §3 (`tool-result-clearing.md:9-12`, budgets); audit §4–§5.

## Goals & Success Metrics

### Primary Goals

- **G-1 Full size on the wire.** A streaming request of 600K input tokens to `claude-fable-5-1` passes cheval's pre-flight; Bridgebuilder's generated table carries the catalog output for the 5-family; Fable 5.1 and Sonnet 5 receive the reasoning timeout budget; Flatline per-voice caps derive from the catalog. **Live evidence (Flatline SKP-001):** the final sprint makes one real large call (≈ 250K tokens) through the path this host has — the `claude-headless` subscription hop (which carries no HTTP ceiling gate) or the API when a key exists — and its result is the G-1 evidence for that path; the HTTP-path ceiling stays at the probed bound until the operator's probe calibrates it (the safe default chosen after the dissent); a failure that the self-correction does not classify is a stop condition.
- **G-2 Two voices, nothing dropped.** On this host (no Anthropic API key) a dissent plans and succeeds with two voices; the three real rejected payloads of this week become findings; every remaining rejected payload is summarised in the envelope and triaged in the feedback file.
- **G-3 Context discipline that fits the model.** One threshold table keyed by context class; the 1M class is the default for the framework's floor; the instruction surface regains headroom under the eval gate.
- **G-4 Current generation everywhere.** No routing alias, fallback map, regex, trust entry, example pin or probe names the previous generation as current.
- **G-5 No safety regression.** Every fence, gate and refusal that exists today still fires; kill switches restore the previous behaviour; the live ceiling probe remains the operator's evidence step.

### Key Performance Indicators (KPIs)

| KPI | Baseline (2026-09-24) | Target |
|-----|---|---|
| Effective input ceiling, `claude-fable-5-1`, streaming | 180,000 (preempt), no path to more | probed bound by default; derived (≥ 800,000) unlocked by calibration or explicit opt-in with self-correction; I1 shrink instead of blind preempt |
| Bridgebuilder `maxOutput`, 5-family | 8,192 | catalog `max_output_tokens` bounded by BB config (≥ 32,000) |
| Bridgebuilder default model | `claude-opus-4-7` | `opus` alias (→ `claude-opus-5`) |
| Reasoning budget for `claude-fable-5-1` / `claude-sonnet-5` | 120–300 s | 1,800 s |
| Flatline per-voice cap on a 128K model | 16,000 | ≥ 64,000 (catalog-bounded) |
| Dissent `voices_planned` on this host | 1 | 2 |
| Real findings lost to schema rejection (this week's three fixtures) | 3 of 3 dropped | 0 dropped |
| `CLAUDE.loa.md` / protocols headroom | 15 B / 407 B | ≥ 1,024 B / ≥ 20 % |
| Routing/governance references to a 4.x model as "current" | 9 files | 0 |

### Constraints

Unattended run; no publication; no credential use beyond the configured dissent voice; `.claude/` edits under the framework marker with REPO-MAP + sidecar + checksums regenerated together; push only via `run-mode-ice.sh`; a2a records to `record/cycle-126-a2a`; budgets net-negative; test-first; review + audit with dissent per sprint, rejected payloads hand-triaged; Aleph untouched; the live probe is not run here.

> Sources: brief §3 constraints; audit §7 ranking; KPI baselines from audit §1–§5 measurements.

## User Personas & Use Cases

### Primary Persona: The maintainer-operator

Runs Loa on the current models with a subscription (Claude Code) and an OpenAI key, sometimes without an Anthropic API key. Wants the framework to get out of the way of the model and to be told the truth by its reviewers.

### Secondary Persona: The unattended run agent

Executes `/run sprint-plan`; needs the second voice to exist without a key, needs rejected findings surfaced, and needs context guidance that does not make it dump a 1M context into NOTES at 15K tokens.

### Tertiary Persona: A downstream fleet operator

Mounts Loa in another repository; upgrades in place; expects `opus`/`cheap` to mean the current generation and Bridgebuilder to run on it.

### Use Cases

- **UC-1** A `/ride` over a large codebase sends 400K tokens to Fable 5.1 through cheval and gets a reply instead of exit 7.
- **UC-2** A Bridgebuilder pass on a 60-file PR runs on Opus 5 with a 32K output budget and the 30-minute reasoning budget.
- **UC-3** `/review-sprint` on a keyless host records two voices; a dissent finding without `failure_mode` reaches the reviewer with `failure_mode_derived: true`; a payload that is still unparseable appears under `## Rejected dissent payloads` in the feedback file.
- **UC-4** A skill working in a 1M-context session reads three 20K-token files without being told to stop and synthesize.
- **UC-5** An operator sets `flatline_protocol.models.primary: claude-sonnet-5` in a mount whose generated map is stale and is not rejected by a regex.
- **UC-6** `implement-gate.sh` sees `active_skill` in a real hook payload and switches to its authoritative mode.

> Sources: audit §1–§5; cycle-125 PRD personas (`grimoires/loa/cycles/cycle-125-friction-floor/prd.md`), reused unchanged.

## Functional Requirements

### FR-1: Full-size adapters, Bridgebuilder and Flatline (audit C1–C9)

- **FR-1.1 Ceiling policy (amended per Flatline SDD SKP-001/SKP-002, sprint SKP-002).** Two pre-flight invariants replace the single literal: **I1** `estimate + max_tokens_on_wire ≤ context_window` — when it fails, cheval first shrinks `max_tokens` down to a floor of 4,096 (recorded in the envelope as `max_tokens_shrunk`), and only then `preempt`s (`CONTEXT_TOO_LARGE`); **I2** the input bound: a **calibrated** entry uses its calibrated value; an **uncalibrated** entry uses `probed_ceiling` (180,000, the last measured value) — the safe default, so nothing changes on the wire until the account is measured; the catalog-derived value (`context_window − max_tokens_on_wire`) is unlocked either by calibration (`tools/ceiling-probe-live.py --write-catalog` writes `calibrated_at`, so the operator's one run flips the policy without a code change) or by the explicit env opt-in `LOA_CHEVAL_UNCALIBRATED_CEILING=derived`, under which a request above the probed bound proceeds with `action: warn` **only if** the count endpoint confirmed the size (a key exists) or the estimator uncertainty is `low`, never above the derived bound, and with the self-correction below. `LOA_CHEVAL_LEGACY_CEILING=1` keeps today's exact behaviour. The non-streaming transport keeps the 36K wall. **Self-correction:** a request that proceeded above the probed bound and fails with a provider context/size error (400 prompt-too-long class, 413) or a token-limit 429 is classified `CEILING_UNVERIFIED_LIMIT`, retried at most once, **never walked to the next voice with the same payload** (context-length errors are non-walkable across the fallback chain), recorded as an observed bound in `.run/ceiling-observed.json` that pre-flight uses for that entry until calibration, and emitted as a `calibration_needed` trajectory record naming the probe command. The catalog test asserts I1 and I2 per entry.
- **FR-1.2 Long-context headers (amended per sprint SKP-014).** A per-entry catalog field `params.beta_headers` (list) is emitted as `anthropic-beta`; default empty; each value must match a provider-specific allowlist regex (`^[a-z0-9]+(-[a-z0-9]+)*-\d{4}-\d{2}-\d{2}$`), is never derived from a request, and active headers are logged in the non-secret diagnostics.
- **FR-1.3 Output defaults.** `default_max_tokens()` returns the catalog `max_output_tokens` bounded by the transport cap (64K streaming / 16K non-streaming) for any provider whose entry declares it; the 4,096 literal applies only to entries with no declaration. The request dataclass default temperature becomes "unset" (omitted on the wire unless a caller sets it; `LOA_CHEVAL_LEGACY_WIRE=1` restores 0.7). The non-streaming read-timeout heuristic keys on the resolved `max_tokens`.
- **FR-1.4 Token estimation.** An Anthropic request within 10 % of its ceiling is counted with the provider's count endpoint when a key is present. Otherwise the existing heuristic (`chars / 3.5`, which overestimates ASCII prose and underestimates CJK/emoji-dense text) is used, and (Flatline SKP-004) the envelope records `estimator: {method: count_endpoint | heuristic, chars, tokens, uncertainty: low | high}` — `high` whenever more than 20 % of the bytes are outside ASCII or the request carries tool payloads; a `high`-uncertainty estimate above the probed bound `preempt`s with a calibration message (SDD SKP-003: the derived bound is never exceeded on an estimate; a count-endpoint result is authoritative). Adversarial fixtures (Unicode-dense, tool-payload-heavy, ASCII prose) pin the direction of error per content type.
- **FR-1.5 Bridgebuilder.** `gen-bb-registry.ts` derives `maxOutput` from the catalog `max_output_tokens` (bounded by `config.maxOutputTokens`, whose default rises to 32,000), `maxInput` from the derived ceiling minus 20,000, and a `reasoning` flag from the entry (`params.thinking_adaptive` or `thinking_traces` capability); `isReasoningClass` consults the generated flag; the built-in default model is the `opus` alias; persona model lines resolve through aliases; `dist/` is rebuilt and the freshness manifest updated.
- **FR-1.6 Flatline caps.** `FLATLINE_REVIEW_MAX_TOKENS` / `FLATLINE_SCORE_MAX_TOKENS` become per-voice values from the resolved entry's `max_output_tokens` bounded by 64,000; the dead `PER_CALL_MAX_TOKENS` knob is removed with a CHANGELOG line.
- **FR-1.7 Health probe.** The Anthropic health check calls the models endpoint when available and otherwise a one-token message on the `tiny` alias; no retired snapshot id remains in the adapter.
- **FR-1.9 Cost visibility (Flatline SDD SKP-003).** The pricing ladder learns the long-context premium: a per-entry `pricing.long_context: {threshold_tokens, input_multiplier, output_multiplier}` applied by `calculate_total_cost` when input exceeds the threshold (5-family entries carry the provider's published tier as reference values; `null` where none), so `cost-report.sh` and the budget enforcer price large calls correctly; the companion dissent voice is bounded by the same per-dissent `budget_cents` as the primary (each voice ≤ budget); a per-request billable-input guard `LOA_CHEVAL_MAX_INPUT_TOKENS` (env; default = the entry's input bound) exists independent of catalog size; the SDD carries a before/after cost table per gate; `cheap` is decided per role (the Flatline scorer moves to `tiny`, the writing roles to `claude-sonnet-5`).
- **FR-1.8 Transport matrix (Flatline SKP-003).** One table test asserts, per (provider, transport ∈ {http-stream, http-legacy, cli-hop}), the effective input ceiling, output default, read timeout, beta headers and token-count method that the actual invocation path applies, so cheval, Bridgebuilder and Flatline cannot disagree about the same entry; the catalog entry records `account_limits: unverified` until the operator's probe fills it (tier, input-tokens-per-minute).
- **Acceptance:** unit tests for each item (catalog ceiling formula per entry; 600K fixture request to `claude-fable-5-1` passes pre-flight in streaming mode with `action: warn`, is refused at 36K in legacy transport, and is refused at 180K with `LOA_CHEVAL_LEGACY_CEILING=1`; a simulated provider limit above the probed ceiling produces one retry, `CEILING_UNVERIFIED_LIMIT`, an observed-bound file and a `preempt` on the next call; the transport matrix test; generated table carries 128,000-derived values and `reasoning: true` for the 5-family; `deriveTimeoutMs` returns 1,800,000 for `claude-fable-5-1`, `claude-sonnet-5`, `claude-opus-5`; Flatline cap test; health-probe test with a mocked endpoint); existing adapter suites green.

> Sources: audit §1 C1–C9; `.claude/defaults/model-config.yaml:366-380` (ceiling rationale, `tools/ceiling-probe-live.py` as the calibration step); `truncation.generated.ts:1-16` (codegen contract); `multi-model-pipeline.ts:45-72`; `flatline-orchestrator.sh:112-132`; `base.py:163-186`.

### FR-2: Two voices and no dropped findings (audit §2)

- **FR-2.1 Second voice without a key (amended per sprint SKP-004).** When the primary Anthropic voice resolves to an HTTP entry and no Anthropic credential is present (env or `.env*`, presence only), `adversarial-review.sh` plans `claude-headless` as a voice in its own right (multi-voice mode, `voices_planned = 2` alongside the OpenAI voice), not merely as a failure fallback. Presence only decides which chain to start; **two-voice success is recorded from actual completions** (`voices_succeeded_ids`), and a companion that fails is recorded with a failure class (`auth`, `model_unavailable`, `quota`, `timeout`, `malformed`) in `metadata.companion_voice`, never as a planned-and-assumed success.
- **FR-2.2 Tolerant finding schema.** A finding with a missing or empty `failure_mode` but a valid id, severity, category and description is accepted with `failure_mode` derived from the first sentence of `description` and `failure_mode_derived: true`; findings that are still invalid go to the sidecar **and** to `metadata.rejected_summary[]` (severity, title, anchor, reason, ≤ 300 chars of description).
- **FR-2.3 Reviewer contract.** `reviewing-code` and `auditing-security` require a `## Rejected dissent payloads` section in the feedback file whenever the envelope's `rejected_summary` is non-empty (each row: accepted → finding recorded, or refuted → one sentence); `verdict-derive.sh` fails the trailer check when the section is missing in that case.
- **FR-2.4 Repair loop.** `_repair_finding_via_model` uses the `tiny` alias when a key exists, else the `claude-headless` hop; `repair_succeeded` is measured on the KF-004 fixtures.
- **Acceptance:** the three real rejected payloads of 2026-09-23/24 (fence bypass, row-supplied pricing authority, negative token counts) are fixtures and produce findings; a two-voice run on this host; a bats case where a rejected row forces the feedback section; KF-004 gets its closing evidence row.

> Sources: audit §2; `adversarial-review.sh:296-352` (`validate_finding`, `_validate_finding_reason`), `:1850-1905` (chain building), `:406-530` (repair loop); `grimoires/loa/a2a/sprint-bug-245/adversarial-rejected-audit.jsonl`; `grimoires/loa/known-failures.md` KF-004.

### FR-3: Context discipline and instruction surface sized for the current generation (audit §3)

- **FR-3.1 Context-class table.** `.claude/protocols/tool-result-clearing.md` carries one table with two classes: `standard` (≤ 200K contexts: today's 2K/5K/3K/15K) and `long` (≥ 1M contexts: 20K/50K/30K/150K); the class is `long` by default (the framework's model floor is the 5-family) and `standard` when the session model is a 200K entry or `LOA_CONTEXT_CLASS=standard`. The `context_discipline` include is regenerated from that table; the "never load a >1,000-line file" edge case becomes class-scoped.
- **FR-3.2 Instruction diet.** Reference-grade protocols (`helper-scripts`, `constructs-integration`, `trajectory-evaluation`, `recommended-hooks`, the reference half of `session-continuity`) move to on-demand loading behind one-line pointers; `CLAUDE.loa.md` regains ≥ 1 KB; the protocol budget regains ≥ 20 %; the `wc -l`-gated parallelism choreography in `auditing-security`, `implementing-tasks` and `reviewing-code` becomes one sentence.
- **FR-3.3 Eval gate.** The existing eval harness A/B (review and audit gold sets) runs before and after; no recall regression is accepted.
- **Acceptance:** `tools/check-prompt-budget.sh` green with the stated headroom; include regenerated (`generate-skill-includes.sh --check`); A/B report attached to the sprint; the three skills shrink.

> Sources: audit §3; `.claude/protocols/tool-result-clearing.md:5-34`; `.claude/data/skill-includes/context_discipline.md`; `tools/check-prompt-budget.sh` output 2026-09-24; cycle-124 sprint-3 parity harness (`grimoires/loa/cycles/…` and `tests/replay/`).

### FR-4: Routing residue, governance registry, probes (audit §4–§5)

- **FR-4.1 Aliases and maps.** `cheap` → `anthropic:claude-sonnet-5` (roles that want the smallest model use `tiny`, decided per role in the SDD); `model-adapter.sh` fallback map and `--help` learn the 5-family and stop naming 4.7; Flatline's `VALID_MODEL_PATTERNS` and stub allowlist admit `claude-<family>-N`, `claude-fable-N-N`, `fable`, `gpt-N.N-pro`.
- **FR-4.2 Governance registry.** `model-permissions.yaml` gains entries for `claude-opus-5`, `claude-sonnet-5`, `claude-fable-5-1` (and Bedrock forms where present) mirroring the 4.7 trust scopes, and its comments stop calling 4.7 current.
- **FR-4.3 Example pins and defaults.** `flatline-proposal-review.sh` default, `alternative-model.md`, `hitl-jury-panel/SKILL.md`, `loa-aleph/SKILL.md` examples, and the two Gemini agent pins move to ids the catalog serves.
- **FR-4.4 Probes (amended per Flatline SKP-008).** `detect-platform-features.sh` records **evidence only** (`active_skill_seen_at`) the first time a real PreToolUse payload carries `tool_input.active_skill`; the recorder runs only in the lead session (skipped when an agent-teams teammate role is set) and writes one atomic file. Authoritative mode of `implement-gate.sh` is **never flipped by a probe**: it requires an explicit opt-in (`implement_gate.mode: authoritative`, default `heuristic`) and a fixture corpus of real PreToolUse payloads (with and without `active_skill`, nested `/run` dispatch) that the authoritative branch is tested against before the opt-in is documented; `/loa` shows the evidence so the operator can decide. `validate-skill-capabilities.sh` reads write-capable agent types from one documented list that includes the agent types the harness ships today. **Spoofability (sprint SKP-001):** the recorder stores the field's *source* (`tool_input` vs a harness-provided context field); authoritative mode is documented only if Task 4.4's research against the Claude Code hooks contract shows a harness-provided skill signal that a model-authored `tool_input` cannot forge, and a test proves a forged `active_skill` in a Write payload does not flip the gate; otherwise the gate stays heuristic and the evidence line says why.
- **FR-4.5 Permission grammar (amended per sprint SKP-010).** `check-permissions.sh` normalises `Bash(<cmd>:*)` and `Bash(<cmd> *)` to one key (`<cmd>`, whitespace-trimmed, no other transformation; an exact `Bash(<cmd>)` rule stays exact) for allow and deny alike; deny keeps precedence at every layer; tests cover both forms, mixed forms across layers, whitespace and escaping cases, and a fuzz set of dangerous shapes (narrower denies for specific dangerous forms never cover the generic requirement; generic denies cover every subcommand).
- **Acceptance:** tests per item; `grep` for a 4.x id used as a default or "current" in live scripts returns nothing; preflight and `/loa` unchanged for operators.

> Sources: audit §4–§5; `model-config.yaml:894`; `model-adapter.sh:111-121,344`; `flatline-orchestrator.sh:555,565-577`; `model-permissions.yaml:145-201`; `detect-platform-features.sh:53-74`; `implement-gate.sh:98-190`; `validate-skill-capabilities.sh:108`.

## Non-Functional Requirements

### Performance
No new per-call latency in hooks; the count endpoint is consulted only near the ceiling; Bridgebuilder budgets rise without new truncation passes.

### Scalability
Ceilings and caps track the catalog so the next generation needs a catalog edit, not code.

### Security
No fence weakened; the executing dissent voice is a hop the framework already trusts; kill switches (`LOA_CHEVAL_LEGACY_CEILING`, `LOA_CHEVAL_LEGACY_WIRE`) are env-only; no credential values ever read (presence only).

### Reliability
Warn-and-proceed above the probed ceiling is visible in the envelope and in cost/trajectory records; a provider refusal still surfaces as today's error class.

### Compliance
Prompt budgets end green with headroom; REPO-MAP, sidecar and checksums regenerated together; CHANGELOG `[Unreleased]` entries per FR; migration guide addendum for behaviour changes (temperature default, ceiling policy, Bridgebuilder model default).

> Sources: brief §3; audit §5 (hook timings 45 ms / ≈ 2 s); cycle-124 kill-switch conventions (`docs/migration/v2.0-model-generation-floor.md`).

## User Experience

### Key User Flows
1. Operator runs a large `/ride`; cheval logs `input_ceiling: catalog_derived, action: warn` and proceeds.
2. Operator runs Bridgebuilder with no model set; the log names `claude-opus-5`.
3. Reviewer opens `engineer-feedback.md`; a `## Rejected dissent payloads` section lists what the dissenter said that the schema refused, each accepted or refuted.
4. A skill in a 1M session reads big files; the context-discipline line says the `long` numbers.

### Interaction Patterns
No new commands; two new envelope fields; one new feedback section; kill switches documented next to the existing ones.

### Accessibility Requirements
Text-only outputs; no colour-only signals; existing `--json` shapes stay backward compatible (additive fields only).

> Sources: audit §6 (feature inventory); cycle-125 PRD UX section conventions.

## Technical Considerations

- The ceiling policy is deliberately two-tier (calibrated → preempt; catalog-derived → warn) because the live probe needs a key this host lacks; the operator's `ceiling-probe-live.py` run later sets `calibrated_at` and flips the action without a code change.
- Bridgebuilder's registry is TypeScript generated from the catalog; `dist/` is tracked and guarded by `tools/check-bb-dist-fresh.sh`, so every registry change rebuilds `dist/`.
- The second voice reuses the multi-voice aggregate that already exists in `adversarial-review.sh` (`verdict_quality.voices_*`); the change is in planning, not aggregation.
- Context class detection prefers the session model when the harness exposes it; the default is the framework floor.
- All catalog edits go through `gen-adapter-maps.sh` so the generated bash maps and the BB registry stay in lock-step.

> Sources: `tools/ceiling-probe-live.py` header; `truncation.generated.ts` header; `adversarial-review.sh` multi-voice metadata (`verdict_quality`); `gen-adapter-maps.sh`.

## Scope & Prioritization

### In scope (this cycle)
FR-1 … FR-4 as specified; docs (migration addendum, CHANGELOG, skill/protocol text touched by FR-3); an end-to-end goal validation in the final sprint.

### Out of scope (deferred, evidence recorded)
Running the live ceiling probe (needs a key); Batch API, `strict` tools, extra cache breakpoints (audit §6, cost levers); shrinking the shared allow list (operator policy); publishing a release candidate; any Aleph change.

### MVP definition
FR-1.1, FR-1.5, FR-2.1, FR-2.2, FR-3.1 — the five changes that stop the current models being capped, reviewed on one voice, or told to stop at 15K tokens.

> Sources: audit §6–§7; brief §2 and §5.

## Success Criteria

- G-1: the 600K fixture passes pre-flight; BB table and reasoning flag correct for the 5-family; Flatline caps catalog-derived.
- G-2: two voices on this host; the three fixtures produce findings; the feedback section is enforced.
- G-3: budgets green with headroom; A/B not worse; include regenerated. **Outcome 2026-10-07 (Bridgebuilder PR #1274 BB-015):** budgets green (`CLAUDE.loa.md` 10,225 / 10,240 B; protocols 131,189 B, down from 199,593 B); the A/B gate held only after the pre-registered revert of the `CLAUDE.loa.md` trim (Sprint 4 Task 4.8, `bf988a43`), so the headroom goal is met for the protocols and not for `CLAUDE.loa.md`, whose Sprint 3 "≤ 9,216 B" criterion was given up for recall (sprint.md Sprint 3 ACs; `a2a/sprint-250/replay-ab-rerun.md`).
- G-4: no 4.x id as default or "current" in live code; registry has the 5-family.
- G-5: fence corpus 100 % dangerous / ≥ 80 % benign unchanged; every existing suite green; kill switches tested.

> Sources: KPI table above; `tests/fixtures/fence-corpus/baseline.json`.

## Risks & Mitigation

| Risk | Impact | Mitigation |
|---|---|---|
| Raising the ceiling without a probe surfaces a provider limit at runtime | a large call fails late | warn-and-proceed is visible in the envelope; one bounded retry, `CEILING_UNVERIFIED_LIMIT`, observed-bound downgrade and a `calibration_needed` event (no blind loops); kill switch restores 180K; the E2E live call and the probe tool are the evidence steps |
| Bridgebuilder `dist/` drift | CI freshness check red | rebuild in the same commit; the manifest tool runs in the sprint |
| A second voice doubles dissent cost and time | slower sprints | the headless hop is subscription-billed; time bounded by existing timeouts |
| Deriving `failure_mode` admits weaker findings | reviewer noise | derived findings are marked and go to the same severity gates; the reviewer still decides |
| Instruction diet regresses review recall | quality loss | A/B gate is mandatory; revert per protocol if red |
| Temperature default change alters non-thinking outputs | behaviour change | documented; `LOA_CHEVAL_LEGACY_WIRE=1` restores 0.7 |

> Sources: audit §1 (KF-002 history), cycle-124 risk register conventions, brief §5 stop conditions.

## Timeline & Milestones

Four sprints, unattended: Sprint 1 FR-1 · Sprint 2 FR-2 · Sprint 3 FR-3 · Sprint 4 FR-4 + docs + E2E. Then draft PR (`cycle-126` in the title), CI green, one Bridgebuilder pass triaged, merge (the pipeline prepares the next rc; no publication).

> Sources: brief §4.

## Appendix

### Assumptions recorded (autonomous run)
- The 5-family's 1M context is available to this account's transport without a beta header; the per-entry `beta_headers` field exists so an operator can add one without a code change.
- `claude-headless` is an acceptable second dissent voice on subscription hosts (it is already a trusted hop in every fallback chain).
- The framework's model floor (5-family) justifies `long` as the default context class.

### Evidence pointers
`grimoires/loa/reports/model-era-audit-2026-09-24.md`; the 12 dissent envelopes under `grimoires/loa/a2a/sprint-24{1,2,3,4}/` and `sprint-bug-24{5,6}/`; `tools/check-prompt-budget.sh` 2026-09-24; hook-chain timing in the audit §5.

### Flatline dissent on this PRD (2026-09-24, voices codex-headless + claude-headless; cross-scoring degraded, blockers integrated)
| Item | Disposition |
|---|---|
| SKP-001 CRITICAL/HIGH — 1M capability unverified; late failures; 600K retries | integrated: self-correcting ceiling (bounded single retry, `CEILING_UNVERIFIED_LIMIT`, observed-bound downgrade, `calibration_needed` event), E2E live ≈250K call as G-1 evidence and stop condition, `account_limits: unverified` in the catalog |
| SKP-002 HIGH — no deterministic recovery for provider limits | integrated into FR-1.1 (same mechanism) |
| SKP-003 HIGH — no per-provider/transport validation | integrated as FR-1.8 transport matrix test |
| SKP-004 HIGH — bytes-based bound under-specified | integrated into FR-1.4 (`estimator` envelope object, uncertainty rule, adversarial fixtures) |
| SKP-008 HIGH — probe flip activates a dead fence mode; teammate writes to `.run/` | integrated into FR-4.4 (evidence-only recorder, lead-only, explicit opt-in, payload fixture corpus) |
| 41 medium-value Phase-1 items | cross-scoring degraded (`scoring_degraded: true`); the raw reviews were not exported with titles — not integrated, recorded here |

### Flatline dissent on the SDD and sprint plan (2026-09-24/25, same voices; both degraded on cross-scoring)
| Item | Disposition |
|---|---|
| SDD SKP-001 CRITICAL — `max(probed, cw − mot)` breaks I1 for 200K entries once the output default is 64K | **accepted, formula replaced**: I1 `estimate + max_tokens ≤ context_window` with auto-shrink to a 4,096 floor; no `max()` with the probed value |
| SDD SKP-002 HIGH / sprint SKP-002 HIGH / PRD SKP-001 — 4.8× default-on without measurement; `warn` is not a mitigation unattended; context errors walked across the chain | **accepted, default inverted**: uncalibrated entries keep the probed bound; derived unlocks by calibration or explicit env opt-in with count-token confirmation; context-length errors non-walkable; probe `--write-catalog` in Sprint 1 |
| SDD SKP-003 HIGH — no cost analysis; long-context premium; `cheap` cost; breaker | **accepted** as FR-1.9 (pricing tier, cost table, per-voice budget, billable-input guard, `cheap` per role) |
| SDD SKP-003 HIGH — 105 % slack on estimates | **accepted**: derived bound never exceeded on an estimate |
| sprint SKP-004 HIGH — credential presence ≠ callable | **accepted** in FR-2.1 (status from completions, failure classes) |
| sprint SKP-001 HIGH — `active_skill` spoofable | **accepted** in FR-4.4 (source recorded; authoritative only with a harness-provided signal proven by research + forged-payload test) |
| sprint SKP-010 CRITICAL — permission grammar ambiguity | **accepted** in FR-4.5 (formal normalisation, precedence, whitespace/escaping, fuzz) |
| sprint SKP-014 HIGH — `beta_headers` injection | **accepted** in FR-1.2 (allowlist regex, never request-derived, logged) |
| sprint SKP-001 CRITICAL — unattended run lacks approval gates | **refuted as process**: the maintainer's standing instruction authorises the unattended cycle under the recorded constraints (no publication, no merge before CI + Bridgebuilder triage, per-dissent budgets, stop conditions in the brief); recorded, not changed |
| sprint SKP-002 HIGH — `model-permissions.yaml` is signed | **refuted with evidence**: the file is consumed only by `context_filter.py` and the migration scripts; no signature, digest or trust-store reference covers it; edit stays in Sprint 4 with the coverage test |
| 27 + 26 medium-value items | not exported with titles; recorded |

### Glossary
**Ceiling** — the largest input cheval will send; **calibrated** — measured by `ceiling-probe-live.py` on a real account; **voice** — one model's independent dissent; **context class** — `standard` (≤ 200K) or `long` (≥ 1M).

> Sources: this document.
