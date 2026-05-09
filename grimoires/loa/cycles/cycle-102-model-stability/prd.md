---
cycle_id: cycle-102-model-stability
title: Loa Model-Integration FAANG-Grade Stabilization
date_created: 2026-05-09
status: discovery_complete
prior_cycle: cycle-099-model-registry (closed; subsumed)
follow_on: cycle-101 (#791) hierarchical review pipeline
schema_version: "1.0"
---

# PRD — cycle-102: Loa Model-Integration FAANG-Grade Stabilization

> **Sources**: `grimoires/loa/visions/entries/vision-019.md` (primary architectural input);
> issues #710, #789, #780, #746, #757, #791;
> `grimoires/loa/NOTES.md` 2026-05-08 sprint-bug-143 archaeology entry;
> `.claude/scripts/model-adapter.sh.legacy` (1018 LOC, current rollback substrate);
> `.claude/defaults/model-config.yaml` (existing partial registry);
> 2026-05-09 PRD interview Phases 1-7.

## 0. Cycle Relationship & Decisions Locked

> Sources: Phase 0 + Phase 1 confirmation.

This cycle **closes cycle-099-model-registry** by absorbing its `#710` endgame
(single-source-of-truth + extension mechanism) and the still-open Sprint 4
deliverables. The active `ledger.json` cycle is updated at cycle-102 kickoff.
Cycle-099's existing artifacts (`generated-model-maps.sh`, `model-resolver.sh`,
`model-config.yaml` schema partials) carry forward.

**Operator decisions locked at discovery time** (not re-litigated during planning/implementation):

| # | Decision | Source |
|---|---|---|
| L1 | Strict failure-as-non-zero applies ONLY to chain exhaustion. **Successful fallback** (primary failed, fallback worked) = exit 0 + WARN + operator-visible header (per AC-1.6). **Chain exhaustion** (primary AND all fallbacks failed) = exit non-zero + typed BLOCKER (`BUDGET_EXHAUSTED` / `ROUTING_MISS` / `FALLBACK_EXHAUSTED` / `PROVIDER_OUTAGE`). Refactored from initial "any degradation = non-zero" after Flatline review v1 BLOCKER B1 (gemini SKP-001 CRIT 900 + opus SKP-003 HIGH 700). | Pre-discovery briefing + Flatline review v1 |
| L2 | `model_aliases_extra` extension mechanism lands WITH capability-class registry in Sprint 2 (one PR) | Pre-discovery briefing |
| L3 | cycle-100 sprint-4 (CI gate + smoke-test PR + cycle ship) runs IN PARALLEL with cycle-102 | Pre-discovery briefing |
| L4 | cycle-101 hierarchical review pipeline (#791) is OUT of scope | Pre-discovery briefing |
| L5 | Cycle-099 closes; cycle-102 is its continuation | Phase 0 Q1 |
| L6 | Thesis stands as written: silent degradation is the bug | Phase 0 Q2 |
| L7 | Soft migration BC policy (raw model IDs resolve via implicit capability-class lookup with WARN; `LOA_FORCE_LEGACY_MODELS=1` kill switch) | Phase 3 Q1 |
| L8 | `model_aliases_extra` is register-only — collisions on `id` reject at load time | Phase 3 Q2 |
| L9 | Audit redaction: reuse cycle-099 `lib/log-redactor.sh` on `error.message_redacted`; provider identity (`openai/anthropic/google`) stays plaintext | Phase 5 Q1 |
| L10 | Total probe failure (zero healthy providers) → typed `BUDGET_EXHAUSTED` BLOCKER, abort gate | Phase 5 Q2 |
| L11 | Smoke-fleet results storage: append-only JSONL at `grimoires/loa/a2a/smoke-fleet/{date}.jsonl` + NOTES.md tail summary | Phase 5 Q3 |
| L12 | Sprint 4 deletes `model-adapter.sh.legacy` in the closing PR | Phase 6 Q1 |
| L13 | BB TS codegen-from-SoT IS in scope (Sprint 4) | Phase 4 Q2 |
| L14 | Subscription shadow-pricing IS in scope (#746 deferral, Sprint 4) | Phase 4 Q2 |
| L15 | Smoke-fleet IS in scope (Sprint 5) | Phase 4 Q2 |

## 1. Problem & Vision

> Sources: `vision-019.md:12-30` (full Insight section); NOTES.md 2026-05-08 sprint-bug-143
> entry; issues #710, #789, #787 (closed by sprint-bug-143), #780, #774 (closed by PR #781);
> Phase 1 confirmation.

### 1.1 The problem

The model-integration layer is the **foundation beneath every Loa flagship feature**:
Bridgebuilder review, Flatline cross-model dissent, `/review-sprint` and `/audit-sprint`
adversarial gates, Red Team adversarial design, persona-routed cheval calls.

> "When this layer wobbles, every quality-gate claim wobbles with it."
> — vision-019.md:14

Sprint-bug-143 surfaced the load-bearing failure pattern: the `flatline_protocol.code_review`
+ `.security_audit` rollback from `gpt-5.5-pro → claude-opus-4-7` (commit `cd4abc1f`) silently
reduced every `/review-sprint` and `/audit-sprint` adversarial pass to *single-model
claude-opus-4-7* for ~6 hours. The operator noticed only because they read a footnote in
the Bridgebuilder review header.

### 1.2 The thesis (cycle-102 contract)

> **Silent degradation is the bug.** Every model failure must be (typed →
> operator-visible → graceful-fallback-with-WARN). Rollback is a workaround
> with a deadline, not a resolution.

### 1.3 The three axioms (vision-019)

| Axiom | Principle | Operationalization in cycle-102 |
|---|---|---|
| **Reframe** | Bug is rarely where the issue title says. | Sprint-bug-143 capture-fixture-first pattern codified in `.claude/protocols/rollback-discipline.md` (Sprint 5). |
| **Rollback Half-Life** | Every rollback comment has a deadline nobody enforces. | CI sentinel `tools/check-rollback-discipline.sh` fails on rollback comments older than 7 days without tracking issue (Sprint 5). |
| **Visible-Failure** | Graceful is not the same as silent. Graceful is visible. | Typed-error taxonomy + per-call probe + operator-visible PR-comment header (Sprints 1-3). |

### 1.4 Why now

Three issues filed within 30 days follow the **same shape** (vision-019.md:34-44 table):

- **#787** — title said "jq parsing"; root was missing `max_output_tokens`.
- **#774** — title said "connection-loss on large docs"; root was bare `except Exception` masking typed `RemoteProtocolError`.
- **#782** — title said "gpt-5.5-pro routing"; root was substring `*"codex"*` heuristic.

The next vendor model release (gpt-5.6, gemini-3.5, claude-opus-5) will produce the same
failure shape unless the structural fix lands. Cycle-102 is that fix.

## 2. Goals & Success Metrics

> Sources: Phase 2 confirmation; vision-019.md:78-95 sprint sketch.

### 2.1 Cycle-exit invariants (M1-M8 — all must hold at ship)

| ID | Metric | Threshold | Verification |
|---|---|---|---|
| **M1** | Multi-model runs that silently degrade | 0 in 30-day window | Audit envelope query: `models_failed[].error_class != null` AND no operator-visible WARN line |
| **M2** | Adapter divergence count | 0 by Sprint 4 ship | Drift-CI: any `model.id` outside `model-config.yaml` registry = fail |
| **M3** | Rollback-comment age in `.loa.config.yaml` | 0 comments older than 7 days without tracking issue | CI sentinel `tools/check-rollback-discipline.sh` |
| **M4** | Capability-class fallback chain coverage | 100% of declared classes have ≥2-deep chain | Schema validation in `.claude/data/model-config.schema.json` |
| **M5** | Smoke-fleet detection latency on vendor regression | <24h between vendor breakage and operator surfacing | Manual injection test in cycle-ship review |
| **M6** | Probe-gate per-call overhead | <500ms added latency, <2s per provider | Sprint 1 benchmark in AC-1.2 |
| **M7** | Operator-visible degradation indication | 100% of degraded multi-model runs produce header line in PR comment / status check | BB pipeline integration test |
| **M8** | Registry extension end-to-end | Operator-only `.loa.config.yaml::model_aliases_extra` edit makes new model usable across BB + Flatline + Red Team without System Zone touch | Sprint 2 AC end-to-end test |

### 2.2 Timeline

Open-ended (Phase 2 Q2). Gate on M1-M8, not wall-clock — BUT with **per-sprint ship/no-ship decision points** (Flatline HC1 / opus SKP-004):

- After each sprint's PR ship, evaluate: (a) sprint AC met? (b) does this sprint's surface independently materially close one of M1-M8 or unblock the next sprint? (c) any new BLOCKER findings from sprint's own review/audit/BB pass?
- If (a) AND (b): proceed to next sprint
- If NOT (a) or NOT (b): pause, scope sprint follow-up bugfix, decide ship/no-ship
- M1's 30-day silent-degradation window is a **post-cycle-ship invariant**, not a pre-ship gate (otherwise the cycle could not ship for 30 days after final sprint). M1 verification window starts at cycle-ship; if M1 trips during the window, file a hotfix-cycle (cycle-102 stays "shipped"; the regression gets its own cycle).
- Hard ceiling: 12 calendar weeks from kickoff. If any sprint takes >2 weeks, scope-cut at sprint review.

### 2.3 M1 verification methodology (Flatline HC10 / opus IMP-004)

M1 ("0 silent degradations in 30-day window") audit query:

```bash
.claude/scripts/lib/audit-query.sh \
  --event-type "model.invoke.complete" \
  --since "$(date -u -d '30 days ago' +%FT%TZ)" \
  --filter '.payload.models_failed != null and .payload.operator_visible_warn != true' \
  --output count
```

Data source: cycle-098 audit envelope chain at `.run/audit/model.invoke.complete.jsonl` (canonical) or hash-chained equivalents per primitive retention policy. Per-primitive retention via `.claude/data/audit-retention-policy.yaml`. M1 trip = **count > 0**.

## 3. Users & Stakeholders

> Sources: CLAUDE.md "primary maintainer @janitooor"; `.claude/scripts/mount-loa.sh` install
> pattern; Phase 3 confirmation.

| Persona | Role in cycle-102 | Cycle-102 surface |
|---|---|---|
| **Primary maintainer (@janitooor)** | Designs, implements, ships. Daily configurator. | Drives capability-class taxonomy decisions; reviews `model_aliases_extra` schema. |
| **Downstream Loa operators** | Inherit defaults; expect upgrades not to break their config. | Soft-migration policy (L7); `LOA_FORCE_LEGACY_MODELS=1` kill switch; migration guide. |
| **Subsystem consumers** (BB, Flatline, Red Team, /review-sprint, /audit-sprint, persona-cheval) | Code calling model-invocation paths. | Refactored to call typed-error contract + capability-class lookup (Sprint 1-3). |
| **Future operators** | Get new defaults. | No migration concern. |

## 4. Functional Requirements

> Sources: vision-019.md:78-95 sprint sketch; Phase 4 AC review (accepted as-is) + scope edges.

Five sprints. Each sprint corresponds to a numbered AC group. Sprint plan (deferred to
`/sprint-plan`) breaks AC into beads tasks.

### 4.1 Sprint 1 — Anti-silent-degradation

> Closes #789b (probe gate), #780 (red-team routing + suppressed stderr), F12 REFRAME
> finding from PR #790 BB iter-3.

| AC | Description | Source |
|---|---|---|
| **AC-1.1** | Typed error taxonomy: every adapter failure carries one of `{TIMEOUT, PROVIDER_DISCONNECT, BUDGET_EXHAUSTED, ROUTING_MISS, CAPABILITY_MISS, DEGRADED_PARTIAL, FALLBACK_EXHAUSTED, PROVIDER_OUTAGE, UNKNOWN}`. UNKNOWN logs full original exception for triage. **JSON Schema** at `.claude/data/trajectory-schemas/model-error.schema.json` with explicit field types, required keys, severity enum (per Flatline HC9 / opus IMP-003). `FALLBACK_EXHAUSTED` (chain ran out without quota issue) and `PROVIDER_OUTAGE` (503/network) are distinct from `BUDGET_EXHAUSTED` (402/quota) — addresses Flatline HC5 / gemini SKP-004 mislabeling concern. | vision-019.md:64-66; PR #781 (cheval typed-classification precedent); Flatline HC5+HC9 |
| **AC-1.2** | Invoke-time probe gate: before any multi-model run, ping each provider with `<2s` budget; failed providers excluded with surfaced WARN. **Probe semantics**: explicit per-provider endpoint (must use SAME inference endpoint as actual call, not a separate health endpoint), auth (same key as inference), rate-limit bucket (probes count against the same bucket; 60s cache amortizes). **Probe cache backend**: file-based with `flock` at `.run/model-probe-cache/{provider}.json`; cross-runtime contract via `lib/model-probe-cache.{sh,py,ts}` mirroring cycle-099 cross-runtime parity pattern. **Fail-open for probe-itself failure**: if the probe layer ITSELF fails (network down, rate-limit on probe), invocation proceeds with WARN — probe is advisory at that level (NOT a self-inflicted outage). **Payload-size sanity** is checked at invocation time, not probe time — probe is fast-fail for hard-down providers, NOT a payload-suitability check. **Local-network failure** (no internet) detected separately via reliable-IP ping; reports as `LOCAL_NETWORK_FAILURE` not as all-providers-down. (Addresses Flatline B2 cluster: gemini SKP-002+003+IMP-001+006, opus SKP-001+IMP-002.) | #789b; M6; Flatline B2 cluster |
| **AC-1.3** | `red-team-model-adapter.sh --role attacker` routes to dedicated `flatline-attacker` agent. Contract test pins attacker output schema. | #780 Tier 2 |
| **AC-1.4** | Stop suppressing pipeline stderr (`flatline-orchestrator.sh:1709 2>/dev/null` removed). | #780 Tier 1 |
| **AC-1.5** | Strict failure semantics (refactored per Flatline B1): **chain exhaustion** (primary AND every fallback failed) → exit non-zero + typed BLOCKER (`BUDGET_EXHAUSTED` / `ROUTING_MISS` / `FALLBACK_EXHAUSTED` / `PROVIDER_OUTAGE`). **Successful fallback** (primary failed, fallback worked) → exit 0 + WARN + operator-visible header listing the fallback hop (`fallback_from`, `fallback_to`, `reason`). `degraded_model=both` (zero healthy providers in dissent quorum) is the typed BLOCKER `BUDGET_EXHAUSTED` (per L10) regardless of fallback. | L1 (refactored); Flatline B1 |
| **AC-1.6** | Operator-visible header: every multi-model run produces a one-line header in PR comment / status check listing `models_succeeded[]` + `models_failed[]{model, error_class}`. | M7 |
| **AC-1.7** | Audit envelope event `model.invoke.complete` with `models_requested[], models_succeeded[], models_failed[]{model, error_class, message_redacted}`. Composes with cycle-098 `audit_emit`. | vision-019.md:64-69; CLAUDE.md audit-envelope constraints |

### 4.2 Sprint 2 — Capability-class registry + extension mechanism

> Closes #710 SoT half. Per L2: registry + extension together in one PR.

| AC | Description | Source |
|---|---|---|
| **AC-2.1** | `.claude/defaults/model-config.yaml` is the only registry. Capability classes are defined by **capability properties** (context window range, reasoning depth, vision support, tool support, latency tier, cost tier) — NOT by vendor lineage — so the taxonomy survives vendor reorgs (Flatline HC4 / opus SKP-002). Concrete classes (with property bundles): `top-reasoning, top-non-reasoning, top-stable-frontier, top-preview-frontier, headless-subscription` — each can have multiple vendor primary candidates. Vendor-specific aliases (`top-reasoning-openai` etc.) become *resolved* class instances, not first-class taxonomy. **Quarterly review AC**: at each cycle ship, validate every class still has ≥2-deep fallback per current vendor catalog. Subscription set folds in #746 deferrals. | #710 §"Proposed direction §1"; vision-019.md:67-70; Flatline HC4 |
| **AC-2.2** | Per-model required fields: `provider, api_id, endpoint_family, capabilities, context.{max_input,max_output,truncation_coefficient}, params.temperature_supported, per_call_timeout_seconds, fallback_chain, pricing.{input_per_mtok,output_per_mtok}`. JSON Schema in `.claude/data/model-config.schema.json`. Existing `probe_required` (load-time) retained alongside invoke-time probe (AC-1.2). | model-config.yaml current state; vision-019.md:67-70 |
| **AC-2.3** | `.loa.config.yaml::model_aliases_extra` extension knob. Register-only; collisions on `id` = load-time exit 2 with structured error. Mirrors `protected_classes_extra` precedent. | #710 §"Proposed direction §2"; L8 |
| **AC-2.4** | Each capability class declares `fallback_chain: [model_id, ...]` of `≥2-deep`. Schema validation enforces. | M4 |
| **AC-2.5** | Resolver helper `.claude/scripts/lib/model-resolver.sh::resolve_capability_class` returns ordered list `(primary, fallback_1, fallback_2, ...)`. **Cycle detection** (Flatline HC7 / gemini IMP-002): resolver detects and breaks fallback cycles (A → B → A) via visited-set; fail-fast on cycle with `ROUTING_MISS`. **Cross-reference validation** (gemini IMP-004): at config load, every `fallback_chain` entry verified to exist in registry; missing references = exit 2 with structured error. **Cross-provider semantics** (Flatline HC11 / opus IMP-006): when fallback chain crosses providers AND target also fails probe, walker continues to next fallback; only chain exhaustion = BLOCKER. | cycle-099 sprint-1B `model-resolver.sh` precedent; Flatline HC7+HC11 |

### 4.3 Sprint 3 — Graceful fallback contract

> Closes #710 fallback-walk half + drift-CI gate.

| AC | Description | Source |
|---|---|---|
| **AC-3.1** | Gates declare capability-class, not model id: `flatline_protocol.code_review.class: top-reasoning-anthropic`. Raw `model: gpt-5.5-pro` resolves via implicit capability-class lookup with WARN (per L7). | vision-019.md:67-70; L7 |
| **AC-3.2** | Fallback walk: primary fails → try fallback chain in order; each hop emits typed WARN with `{fallback_from, fallback_to, reason}`; chain exhaustion → typed BLOCKER differentiated by cause: `BUDGET_EXHAUSTED` (402/quota), `PROVIDER_OUTAGE` (503/network), `FALLBACK_EXHAUSTED` (no remaining valid models), `ROUTING_MISS` (config error). Successful fallback → exit 0 + WARN (per AC-1.5 refactor). Total probe failure = abort with `PROVIDER_OUTAGE` (per L10, refined). | vision-019.md:64-66; L10; Flatline B1+HC5 |
| **AC-3.3** | Drift-CI gate scoped to **specific path globs** (Flatline HC3 / opus SKP-005): scans `.claude/scripts/**/*.sh`, `.claude/skills/**/*.{ts,js,py}`, `.loa.config.yaml*`, `.loa.config.local.yaml*` (config + gate definitions). EXPLICITLY excluded by default: `**/*.md`, `**/tests/fixtures/**`, `**/archive/**`. Regex `claude-[0-9]\|gpt-[0-9]\|gemini-[0-9]\|opus\|sonnet\|haiku` outside scoped paths + designated allowlist = CI fail. Allowlist governance (Flatline HC10/AC-3.5): every allowlist entry MUST cite rationale comment + sunset-review cadence. Mirrors cycle-099 sprint-1E.c.3 `tools/check-no-raw-curl.sh` pattern. | M2; cycle-099 raw-curl precedent; Flatline HC3 |
| **AC-3.4** | `LOA_FORCE_LEGACY_MODELS=1` kill switch — bypasses capability-class lookup; restores raw-id resolution. | L7 |
| **AC-3.5** | Soft-migration sunset cadence (Flatline HC8 / opus IMP-001): raw-model-id WARN escalates from `INFO` (cycles 1-2) → `WARN` (cycles 3-4) → `ERROR` (cycle 5+) → CI fail at deprecation deadline (12 cycles post-ship). `LOA_FORCE_LEGACY_MODELS=1` operators see CI WARN every cycle (R6 mitigation); flag itself sunsets at the same deadline. | L7; Flatline HC8 |

### 4.4 Sprint 4 — Adapter unification + retirement

> Closes #757, #746, #710 retirement half. Per L13/L14/L15.

| AC | Description | Source |
|---|---|---|
| **AC-4.1** | Adapter-divergence audit doc at `grimoires/loa/cycles/cycle-102-model-stability/adapter-divergence.md` — surfaces every difference across (cheval Python, legacy bash, BB TS, red-team-model-adapter). | #710 §"Where models are hardcoded"; vision-019.md:80-81 |
| **AC-4.2** | Canonical path = cheval Python. `model-adapter.sh.legacy` is **quarantined to `.claude/archive/legacy-bash-adapter/` for ≥1 cycle post-ship** before deletion (revised per Flatline HC2 / opus SKP-006 — irreversible deletion is premature; needs operator-validated kill-switch shim coverage first). Quarantine PR runs the test corpus AC-4.4a verifying `LOA_FORCE_LEGACY_MODELS=1` shim covers 100% of legacy code paths. Deletion happens in cycle-103 ship-prep. `hounfour.flatline_routing` defaults to `true` in Sprint 4; flag removed when archived legacy adapter is deleted. | L12 (revised); Flatline HC2 |
| **AC-4.3** | BB TS reads SoT via build-time codegen — `truncation.ts` + `config.ts` regenerated from `model-config.yaml`. Drift-CI fails on stale codegen output. | L13; #710 §"Proposed direction §3" |
| **AC-4.4** | Red-team-model-adapter consolidates into cheval (or thin wrapper) — single resolver path. | #780; #710 |
| **AC-4.4a** | Kill-switch shim coverage test corpus (precondition for AC-4.2 quarantine): for every legacy adapter code path, a contract test exercises it via `LOA_FORCE_LEGACY_MODELS=1` and verifies bit-equivalent behavior to pre-cycle-102. Coverage tracked in `tests/cycle-102/legacy-shim-coverage.bats`. | Flatline HC2 |
| **AC-4.5b** | Reframe Principle codification (Flatline MC8 / opus IMP-010): `.claude/protocols/rollback-discipline.md` includes **falsification test** — given a sprint-bug-style failure, the protocol must produce a different first-hypothesis-vs-empirical-root-cause table that the patch author signs. | vision-019.md:48-58 |
| **AC-4.5c** | Adapter parallel-dispatch concurrency audit (NEW; revealed by this PRD's own Flatline run — A6): when 3 reviewer + 3 skeptic calls run concurrently against a 12-30K-token PRD, ≥3 of 6 fail with empty-content (legacy) or PROVIDER_DISCONNECT (cheval). Fix in Sprint 4 via per-provider rate-limit/connection-pool tuning + sequential-fallback strategy when parallelism degrades >50%. | A6 from flatline-prd-review-v1.md |
| **AC-4.5d** | `max_output_tokens` adequacy for reasoning-class models (NEW; A1+A2): legacy adapter's hardcoded `max_output_tokens=8000` (sprint-bug-143) is insufficient on prompts >~10K tokens for gpt-5.5-pro and Gemini reasoning models. Sprint 4's cheval-canonical migration reads `max_output_tokens` from `model-config.yaml` per-model; Sprint 1 also explicitly bumps the legacy hardcode to a per-model lookup as defense-in-depth before deletion. | A1, A2 from flatline-prd-review-v1.md |
| **AC-4.5e** | Cheval long-prompt PROVIDER_DISCONNECT (#774, A3): characterize failure threshold via fixture-replay (different prompt sizes 5K/10K/20K/30K/50K), determine if upstream httpx connection-pool tuning, request streaming, or chunking is the right fix; deliver upstream PR or characterize as vendor-side bug with deterministic mitigation in cheval. | A3 from flatline-prd-review-v1.md; #774 |
| **AC-4.5** | #757: codex-headless long-prompt stdin diagnosis + fix. Test against ≥50KB prompt; subprocess invocation handles graceful failure or success. | #757 §"Suggested investigation" |
| **AC-4.6** | #746 shadow-pricing: subscription-billed providers declare `shadow_pricing.{input_per_mtok,output_per_mtok}` so L2 cost gate has quota signal. Existing `pricing: { input_per_mtok: 0 }` resolved. | L14; #746 §"pricing-zero-blinds-cost-gate" |
| **AC-4.7** | #746 flag-injection: `--` separator pre-pended before prompts in headless adapters; OR adapter rejects prompts starting with `-`. | #746 §"flag-injection-via-prompt" |

### 4.5 Sprint 5 — Rollback-discipline + smoke fleet

> Closes vision-019 axioms 2 + 3 operationalization. Per L15.

| AC | Description | Source |
|---|---|---|
| **AC-5.1** | `.claude/protocols/rollback-discipline.md` codifies: every rollback comment in `.loa.config.yaml` MUST cite `(tracking-issue, fix-forward-gate, deadline_iso)`. Includes the Reframe Principle capture-fixture-first pattern. | vision-019.md:48-58; sprint-bug-143 archaeology |
| **AC-5.2** | CI sentinel `tools/check-rollback-discipline.sh` scans `.loa.config.yaml` + `.loa.config.yaml.example` for `# Restore … after #` patterns; fails when comment age >7 days OR missing tracking-issue ref. | M3 |
| **AC-5.3** | Smoke-fleet workflow `.github/workflows/model-smoke-fleet.yml` — weekly cron; pings every (provider, model) combo in registry with tiny prompt; degradation deltas → `grimoires/loa/a2a/smoke-fleet/{date}.jsonl` (with `flock` to prevent concurrent-write corruption per Flatline MC2 / gemini IMP-005); top-line summary appended to NOTES.md tail. **Active alerting** (Flatline HC6 / gemini IMP-003): degradation delta auto-creates a GitHub issue (or pings configured webhook) so M5 24h SLA is met without operator polling. **Budget+abort policy** (Flatline MC5 / opus IMP-007): per-run cost cap (default 50¢, configurable); abort if any provider returns 429 N=3 times within run; quarterly review of cost ceiling. Per L11. | L11; M5; vision-019.md:90-92; Flatline HC6+MC2+MC5 |
| **AC-5.4** | Smoke-fleet vendor-regression detection: M5 (24h latency) verified via manual injection test in cycle-ship review. False-alarm dampener: 2-consecutive-failure threshold before surfacing (R4). | M5; R4 |
| **AC-5.5** | `.loa.config.yaml.example` migration: every reference to raw model id replaced with capability-class. Migration guide at `docs/migration/cycle-102-model-stability.md`. Mirrors v1.130 release migration-guide pattern. | L7; v1.130 release precedent |

## 5. Technical & Non-Functional Requirements

> Sources: cycle-098 audit envelope; cycle-095 endpoint-validator + redactor; cycle-099
> codegen toolchain; Phase 5 confirmation.

### 5.1 Performance

- **NFR-Perf-1** Probe-gate per-call overhead: <500ms added latency, <2s per provider (M6).
- **NFR-Perf-2** Probe results cached 60s — same multi-model run within 60s reuses cached probe.
- **NFR-Perf-3** Smoke-fleet weekly cron — single-digit-minutes wall clock for full registry sweep.

### 5.2 Security & Redaction

- **NFR-Sec-1** Reuse cycle-099 sprint-1E.a `lib/log-redactor.sh` on `error.message_redacted` field of `model.invoke.complete` audit event (L9).
- **NFR-Sec-2** Provider identity (`openai`, `anthropic`, `google`) NOT redacted — needed for triage (L9).
- **NFR-Sec-3** No API keys / tokens in audit payloads — redactor removes these classes (cycle-099 inheritance).
- **NFR-Sec-4** `model_aliases_extra` operator-supplied content runs through endpoint-validator (cycle-099 sprint-1E.b) on any URL fields.

### 5.3 Audit & Observability

- **NFR-Aud-1** Every multi-model invocation emits `model.invoke.complete` envelope event via `audit_emit` (CLAUDE.md cycle-098 audit-envelope constraints).
- **NFR-Aud-2** Smoke-fleet emits `smoke.fleet.run` envelope event with `runs[]{provider, model, outcome, latency_ms, error_class}`.
- **NFR-Aud-3** Drift-CI gate logs structured event on every CI run (pass or fail).

### 5.4 Backwards Compatibility

- **NFR-BC-1** Soft migration: raw model IDs in `.loa.config.yaml` continue to resolve via implicit capability-class lookup, emitting WARN (L7).
- **NFR-BC-2** `LOA_FORCE_LEGACY_MODELS=1` kill switch restores raw-id resolution; intended as multi-cycle escape hatch with documented sunset trigger (R6).
- **NFR-BC-3** Schema-version field on `model-config.yaml` and `.loa.config.yaml` — change requires migration helper (cycle-099 sprint-1E.a precedent).

### 5.5 Drift Detection

- **NFR-Drift-1** Hardcoded-model-id scanner mirrors `tools/check-no-raw-curl.sh` semantics: heredoc-state, word-boundary, suppression marker, cross-runtime allowlist sync.
- **NFR-Drift-2** Codegen drift gate (`generated-model-maps.sh` + BB `truncation.ts/config.ts`): byte-equality check between fresh codegen and committed output.

### 5.6 Composability with Existing Primitives

- **L1 Jury-Panel** — capability-class resolution emits `class.resolved` audit event compatible with jury-panel adjudication (cycle-098 §5.5).
- **L2 Cost-Budget Enforcer** — multi-model invocations call `cost_check_budget` BEFORE invocation; subscription providers contribute via shadow-pricing (AC-4.6).
- **L3 Scheduled-Cycle** — smoke-fleet workflow MAY use L3 chassis in future (Sprint 5 ships standalone GH Actions cron).
- **L5 Cross-Repo Status Reader** — `gh api` patterns reused in smoke-fleet workflow.
- **L6 Structured-Handoff** — cycle-102 ship handoff via `handoff_write` to operator.

## 6. Scope & Prioritization

> Sources: Phase 6 confirmation.

### 6.1 In scope (cycle-102)

All five sprints' AC as captured in §4. Five sprints land before cycle ships.

### 6.2 Explicit OUT of scope

| Item | Why out | Tracked where |
|---|---|---|
| Hierarchical review pipeline (BB chunking + cross-seam digest + prompt cache) | Architectural follow-on; needs stability foundation first | #791 → cycle-103 candidate |
| External smoke-fleet dashboard (Grafana/datadog/Honeycomb) | Infra dependency; JSONL + NOTES.md tail is sufficient signal | Sprint-5 follow-up; not blocking |
| Hot-reload of model registry (without restart) | Restart-on-config-edit acceptable | Future enhancement |
| Multi-tenant model isolation (per-operator API key scoping) | Not a current operator pattern | Not tracked |
| `/review-sprint` adversarial gate model rotation policy | Lives in `autonomous_arbiter.rotation` config; pre-existing surface | Pre-existing |

### 6.3 Phasing

- **Sprint 1** delivers operator-visible degradation surfacing (highest-priority — closes vision-019 Axiom 3 violation).
- **Sprint 2-3** delivers structural fix (capability-class registry + fallback contract).
- **Sprint 4** retires legacy adapter — safe to do once SoT is canonical.
- **Sprint 5** locks in process discipline (rollback comments) + ongoing detection (smoke fleet).

## 7. Risks & Dependencies

> Sources: Phase 7 confirmation.

### 7.1 Risks

| ID | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| **R1** | Vendor API regression mid-cycle (new endpoint shape, etc.) | M | H | Capture-and-replay fixtures (sprint-bug-143 pattern); smoke fleet detects |
| **R2** | Sprint 4 retirement breaks downstream operator flows | M | M | `LOA_FORCE_LEGACY_MODELS=1` kill switch; soft-migration period; migration guide (AC-5.5) |
| **R3** | Probe-gate adds noticeable latency to small operations | L | M | Per-call probe results cached 60s; <2s budget enforced (M6/NFR-Perf-1) |
| **R4** | Smoke-fleet false alarms (vendor blip vs real regression) | H | L | Two-consecutive-failure threshold before surfacing (AC-5.4) |
| **R5** | Capability-class registry schema changes mid-cycle | L | M | Schema-version field; migration helper (cycle-099 sprint-1E.a precedent) |
| **R6** | `LOA_FORCE_LEGACY_MODELS=1` operators stay forever, blocking eventual full deletion | M | L | Sentinel CI WARN every cycle when flag is set; documented sunset trigger (~6 months post-ship) |
| **R7** | Probe-gate masks transient flakes that *should* be retried | M | M | Retry budget within probe (e.g., 2 attempts in 2s) before declaring DEGRADED |
| **R8** | Reframe Principle violation — first hypothesis on a sprint bug is wrong, wastes hours | M | M | Sprint-bug-143 capture-fixture-first pattern codified in `.claude/protocols/rollback-discipline.md` (AC-5.1) |

### 7.2 Dependencies

- **cycle-098 audit envelope** — `audit_emit` for `model.invoke.complete` events. Composes via existing API.
- **cycle-095 endpoint-validator + redactor** — `lib/log-redactor.sh` reused for `error.message_redacted` (NFR-Sec-1).
- **cycle-099 codegen toolchain** — yq v4.52.4 pinned; tsx ^4.21.0; `model-resolver.sh`. No new deps; cycle-102 absorbs cycle-099 work.
- **cycle-100 jailbreak-corpus (parallel, per L3)** — sprint-4 smoke-test PR consumes our smoke-fleet workflow. No blocking merge order.
- **External: `gh` API** — same auth surface as L5 cross-repo status reader.
- **External: provider APIs** — risk acknowledged via R1.

## 8. Assumptions

> Tagged for audit at sprint-plan + implementation time. Each is falsifiable.

- **[A1]** cycle-099 closes cleanly when its in-flight #710 work is subsumed by cycle-102 — no phantom open issues left dangling. **If wrong**: leaves an open ledger cycle that needs manual reconciliation.
- **[A2]** Capability classes share one fallback-walk policy. **If wrong**: per-class `on_fallback_exhaust` config keys added in Sprint 3 follow-up.
- **[A3]** BB TypeScript build pipeline accommodates a codegen step (yq → ts → bundle). **If wrong**: BB stays on manually-edited `truncation.ts`; AC-4.3 deferred to follow-up.
- **[A4]** Smoke-fleet cron stays under vendor rate-limits + billing tolerance with tiny prompts × ~12 (provider, model) combos × weekly cadence. **If wrong**: cadence drops to bi-weekly OR per-provider key rotation.
- **[A5]** `LOA_FORCE_LEGACY_MODELS=1` kill switch restores legacy behavior via resolver shim, not by un-deleting `model-adapter.sh.legacy`. **If wrong**: legacy file lingers through Sprint 5 ship-prep instead of deleting in Sprint 4.

## 9. Flatline Review Iter-1 (manual synthesis 2026-05-09)

> The orchestrator's auto-trigger Flatline pass on this PRD failed twice with
> silent-degradation pattern that vision-019 Axiom 3 names. Adapter bugs A1-A6
> uncovered during the run are themselves cycle-102 anchor evidence (see
> `flatline-prd-review-v1.md` for full A-list). Manual Flatline run with 4 of 6
> voices succeeding produced sufficient HIGH_CONSENSUS signal to amend this PRD.

**Coverage (4 of 6 voices succeeded; 2 gpt-5.5-pro failures = adapter bug, not vendor outage)**:
- ✅ opus-review (10 improvements, 5 HIGH + 5 MED)
- ✅ opus-skeptic (7 concerns, 1 CRIT + 5 HIGH + 1 MED)
- ✅ gemini-review (6+ improvements, 3 HIGH + 3 MED)
- ✅ gemini-skeptic (5 concerns, 2 CRIT + 2 HIGH + 1 MED)
- ❌ gpt-review + gpt-skeptic (legacy adapter `max_output_tokens=8000` insufficient on this PRD; cheval transport disconnects on >26KB prompts)

**BLOCKER findings integrated**:

- **B1**: L1 strict semantics contradicted AC-3.2 graceful fallback. **Refactored**: L1 + AC-1.5 + AC-3.2 distinguish successful-fallback (exit 0 + WARN) from chain-exhaustion (exit non-zero + typed BLOCKER). Sources: gemini SKP-001 (CRIT 900) + opus SKP-003 (HIGH 700).
- **B2**: Probe gate semantics underspecified. **AC-1.2 expanded**: explicit per-provider endpoint/auth/rate-limit-bucket; cache backend (file+flock at `.run/model-probe-cache/`); fail-open for probe-itself failure; payload-size sanity at invocation time, not probe time; local-network-failure detection. Sources: gemini SKP-002 (CRIT 850) + opus SKP-001 (CRIT 850) + gemini SKP-003 (HIGH 750) + opus IMP-002 + gemini IMP-001+006.

**HIGH_CONSENSUS findings integrated** (HC1-HC11 in `flatline-prd-review-v1.md`):

- HC1 → §2.2 per-sprint ship/no-ship decision points + 12-week ceiling
- HC2 → AC-4.2 quarantine instead of delete; AC-4.4a kill-switch shim coverage test corpus
- HC3 → AC-3.3 path-glob scoped drift-CI, with allowlist governance
- HC4 → AC-2.1 capability-property-based taxonomy
- HC5 → AC-1.1 + AC-3.2 typed `FALLBACK_EXHAUSTED` and `PROVIDER_OUTAGE` distinct from `BUDGET_EXHAUSTED`
- HC6 → AC-5.3 active alerting via webhook/auto-issue
- HC7 → AC-2.5 fallback-resolver cycle detection
- HC8 → AC-3.5 soft-migration sunset cadence
- HC9 → AC-1.1 explicit JSON Schema sketch path
- HC10 → §2.3 M1 audit query precision
- HC11 → AC-2.5 cross-provider fallback semantics

**MEDIUM findings**: kept as Sprint-plan task hints in `flatline-prd-review-v1.md`; not bloating PRD.

**Adapter bugs A1-A6 (uncovered during this run, integrated as Sprint anchor AC)**:

- AC-4.5c (NEW) → A6 parallel-dispatch concurrency audit
- AC-4.5d (NEW) → A1+A2 max_output_tokens adequacy fix (Sprint 1 + Sprint 4)
- AC-4.5e (NEW) → A3 cheval long-prompt PROVIDER_DISCONNECT (#774) characterization
- AC-4.5b (NEW) → MC8 Reframe Principle falsification test

**Disposition**: PRD amended in place. Iter-2 Flatline run is **not gated** — the iter-1 dogfooding revealed the adapter bugs that Sprint 1 + Sprint 4 will fix, and re-running on the same broken adapter substrate would surface the same pattern. Iter-2 will run after Sprint 1 lands (the typed-error + probe-gate work), validating the cycle-102 thesis on its own SDD.

## 10. Coda

> Vision-019 Coda — "The Bridgebuilder's Lament" — describes a Bridgebuilder running on
> a degraded triad and unable to tell the operator. It captures *why* this cycle matters in
> a register the technical sections don't reach. The lament is reproduced in
> `vision-019.md:113-128`; its operative line is the design contract:
>
> > "When I am degraded, I tell you. In the place you read me — not in a stderr log nobody reads.
> > With the typed-class name of what failed. With the next-best I fell back to. With a one-line
> > invitation to re-run if it matters."
>
> Cycle-102 builds the system that lets the Bridgebuilder say so.

---

*Discovery interview conducted 2026-05-09 across 7 phases. Skill: `discovering-requirements`.
Next: `/architect` (with Flatline auto-trigger on PRD per `.loa.config.yaml::flatline_protocol.phases.prd: true`).*
