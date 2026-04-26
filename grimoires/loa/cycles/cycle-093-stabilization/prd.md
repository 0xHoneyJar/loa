# Loa Stabilization & Model-Currency Architecture — PRD

> **Cycle**: cycle-093-stabilization
> **Date**: 2026-04-24
> **Status**: Discovery → Architecture
> **Branch base**: `main` (stack on cycle-092 if PR #603 merges after start)
> **Artifact isolation**: all cycle artifacts under `grimoires/loa/cycles/cycle-093-stabilization/` to avoid clobbering cycle-092's in-flight PR #603

## Executive Summary

This is a stabilization meta-sprint for the Loa framework itself. Three Tier-1 silent failures (#605, #607, #618) are eroding operator trust in the framework's config surface; model-currency maintenance has emerged as a recurring source of stability defects (#574, #602); and the Gemini default is two months stale. The cycle addresses all of these with a keystone architectural change — a **provider-side health-probe pattern** — that converts model-availability from a maintained-by-hand list into a probed invariant.

## 1. Problem Statement

Five independently-filed issues reveal a shared pattern: **trust between configured capability and runtime behavior is maintained by hand, and hand-maintenance has failed**.

### Silent failures (operator-trust damage)

- **#605** — `/spiraling` harness `_gate_review`/`_gate_audit` bypass `flatline_protocol.code_review.enabled` / `flatline_protocol.security_audit.enabled`. Operators configure 3-model adversarial code review; harness runs single-model Opus-only. Evidence: `.run/cycles/cycle-096/evidence/` lacks `adversarial-review.json` / `adversarial-audit.json` despite both config flags being on. Validated across cycle-093, cycle-094, cycle-096.

- **#607** — `bridgebuilder-review` skill ships with `dist/core/multi-model-pipeline.js` **missing** from the shipped bundle. `dist/main.js:7` imports the module; result is `ERR_MODULE_NOT_FOUND` before any network/API call. Skill is completely unusable from submodule consumers.

- **#618** — Flatline dissenter hallucinates literal `{{DOCUMENT_CONTENT}}` tokens in ampersand-adjacent bash/TS contexts at 50% rate, emitting BLOCKING findings that never existed. 14 findings observed across 3 sprints; 7 hallucinated, always in `&&` / `&` / `2>&1` contexts. Operator burns ~10 min/review on triage.

### Model-currency drift

- **#602** — Gemini 3.1 Pro Preview has been live on v1beta since 2026-02-19 ([Google AI docs](https://ai.google.dev/gemini-api/docs/models/gemini-3.1-pro-preview)); Loa's bash adapter (`model-adapter.sh:117`), YAML defaults (`model-config.yaml:61-63`), and Flatline allowlist (`flatline-orchestrator.sh:302`) are stale because Gemini 3 was phantom at time of prune (#574).

- **#574** (closed) — Traced to lack of provider-side availability validation. Same class of defect will recur every time a provider adds or removes a model. GPT-5.5 shipping imminently (announced 2026-04-23, API "very soon") is the next scheduled instance.

The root pattern across all five: **what operators configure ≠ what runs, and the framework has no mechanism to notice**.

## 2. Vision & Mission

**Vision**: Loa's config surface is an honest contract. What operators configure is what runs. Model-availability is *detected*, not declared.

**Mission for this cycle**:
1. Close the three Tier-1 silent failures (#605, #607, #618).
2. Re-add Gemini 3.1 Pro Preview as a first-class supported model.
3. Ship a **provider health-probe pattern** (keystone) that makes availability a probed invariant — so the next model transition is handled architecturally rather than reactively.

> **Lore context**: The health-probe pattern is the same idea as the "Route Table as General-Purpose Skill Router" captured in vision-008 — reality is queried, not declared. Applied to model-availability here; extensible to other provider-declared capabilities later.

## 3. Goals & Success Metrics

| # | Goal | Measurable Criterion |
|---|------|---------------------|
| G1 | Close #605 | `/spiraling` harness-dispatched cycle with `flatline_protocol.code_review.enabled: true` produces `adversarial-review.json` in evidence dir; verified on a live test cycle |
| G2 | Close #607 | `bridgebuilder-review` skill runs end-to-end from a submodule consumer (`.loa/.claude/skills/bridgebuilder-review/resources/entry.sh --dry-run`), prints `{ reviewed, skipped, errors }` JSON summary |
| G3 | Close #618 | Zero BLOCKING hallucinations on a synthetic diff containing `&&`, `&`, `2>&1` across 20 adversarial review runs (pre-check filter verified) |
| G4 | Gemini 3.1 Pro Preview routable | `.claude/scripts/model-adapter.sh --model gemini-3.1-pro --mode review ...` returns 200; `flatline_tertiary_model: gemini-3.1-pro-preview` validates; red-team adapter resolves provider:model-id |
| G5 | Health-probe invariant | CI gate fails with actionable message when any configured model returns NOT_FOUND from its provider; newly-available models added to `.loa.config.yaml` auto-probe on config-load with 24h TTL |
| G6 | GPT-5.5 readiness | Registry entry exists behind `probe_required: true`; probe auto-enables it when OpenAI `/v1/models` returns `gpt-5.5` |

## 4. Users & Stakeholders

| Persona | Role | What they need | Signal of success |
|---------|------|----------------|-------------------|
| **Framework Operator** | Runs `/spiraling`, `/run sprint-plan` | Config flags behave as documented | `flatline_protocol.code_review.enabled: true` in harness cycle produces adversarial artifact |
| **Submodule Consumer** | Embeds Loa via git submodule | Shipped skills work without local rebuild | `bridgebuilder-review` smoke test passes in submodule context |
| **Framework Maintainer** | Lands PRs to Loa | Model-availability caught at PR CI, not runtime | Provider health-probe CI gate gates PRs touching model config |
| **AI Operator** | Autonomous agent dispatched via harness | Predictable cost; no paying for silent no-ops | Budget line items match configured review depth |

## 5. Functional Requirements

### Tier 1 — Silent-failure fixes

**T1.1 — Harness adversarial wiring (#605)**
The spiral harness `_gate_review` and `_gate_audit` MUST invoke the `reviewing-code` and `auditing-security` skills (respectively), which already honor `flatline_protocol.code_review.enabled` / `security_audit.enabled` config and emit `adversarial-{review,audit}.json` artifacts via `adversarial-review.sh`. Existing `adversarial-review-gate.sh` hook (v1.94.0) will then structurally enforce artifact presence before gate PASS. Alternative (if skill-invocation ergonomics block): harness wraps its own `claude -p` runs with a post-hoc `flatline_protocol.*.enabled`-gated call to `adversarial-review.sh`, producing the expected evidence files.

*File surface*: `.claude/scripts/spiral-harness.sh` `_gate_review` and `_gate_audit`. Related: `adversarial-review.sh`, `adversarial-review-gate.sh`.

**T1.2 — Bridgebuilder dist completeness (#607)**
Build pipeline MUST emit `dist/core/multi-model-pipeline.js` alongside the other 11 `dist/core/*.js` files. Root cause investigation: tsconfig exclude glob in `.claude/skills/bridgebuilder-review/resources/tsconfig.json`, or a `files`/`prepack` filter in `.claude/skills/bridgebuilder-review/package.json`.

CI smoke test MUST verify `node dist/main.js --help` exits 0 as a pack-release gate.

*Fixture-submodule CI test (per Flatline IMP-007)*: Because the defect specifically manifests in **submodule consumers** (not local dev), the acceptance gate MUST include a fixture repo at `.claude/tests/fixtures/submodule-consumer/` with a CI job that:
1. Adds this loa repo as a git submodule under `.loa/`
2. Invokes `.loa/.claude/skills/bridgebuilder-review/resources/entry.sh --dry-run`
3. Asserts exit 0 AND `{ reviewed, skipped, errors }` JSON summary present in stdout

Without this fixture test, the defect class (submodule-specific dist-emission gaps) will recur and only be caught by external users.

*File surface*: `.claude/skills/bridgebuilder-review/resources/tsconfig.json`, `.claude/skills/bridgebuilder-review/package.json`, build/prepack scripts, `.claude/tests/fixtures/submodule-consumer/`, `.github/workflows/bridgebuilder-submodule-smoke.yml`.

**T1.3 — Dissenter hallucination filter (#618)**

*Core filter*: `adversarial-review.sh` MUST add a deterministic pre-check with **bidirectional token matching** (per Flatline IMP-003):

| Diff contains token | Finding contains token | Action |
|---|---|---|
| No | Yes | **Downgrade** to ADVISORY + tag `MODEL_ARTEFACT_SUSPECTED` |
| No | No | No-op |
| Yes | Yes | No-op (legitimate — docs, templates) |
| Yes | No | No-op |

When downgrading: set `severity: ADVISORY`, `category: MODEL_ARTEFACT_SUSPECTED`, prefix description with `[downgraded: dissenter-output contained {{DOCUMENT_CONTENT}} token that is absent from the diff]`.

*Normalization rules*: The filter MUST handle common escape/variant forms that models emit:
- Escaped: `\{\{DOCUMENT_CONTENT\}\}`
- Spaced: `{{ DOCUMENT_CONTENT }}` / `{{  DOCUMENT_CONTENT  }}`
- Case variants: `{{document_content}}`, `{{Document_Content}}`
- Partial: bare `DOCUMENT_CONTENT` token outside braces

Bats tests MUST cover: clean diff + synthetic all-hallucinated findings → all downgraded; clean diff + mixed findings → only hallucinated downgraded; diff-with-legitimate-token → pre-check does not fire; each normalization variant → detected and downgraded; diff with token in comments only (non-code context) → still considered "present" (no downgrade).

*File surface*: `.claude/scripts/adversarial-review.sh`, new bats tests in `.claude/tests/unit/`.

### Tier 2 — Model currency + forward-compat architecture

**T2.1 — Gemini 3.1 Pro Preview re-add**
- `.claude/defaults/model-config.yaml` `providers.google.models` MUST include `gemini-3.1-pro-preview` with: `capabilities: [chat, thinking_traces]`, `context_window: 1048576`, pricing per Google published rates, and `extra.thinking_level: high` (Gemini 3 uses string `thinkingLevel`, not integer `thinkingBudget` — Python adapter `google_adapter.py:476` already handles this split).
- Aliases section MUST restore `deep-thinker: google:gemini-3.1-pro-preview`.
- `.claude/scripts/model-adapter.sh` MODEL_TO_PROVIDER_ID bash map MUST include `["gemini-3.1-pro"]="google:gemini-3.1-pro-preview"` and `["gemini-3.1-pro-preview"]="google:gemini-3.1-pro-preview"`.
- `.claude/scripts/flatline-orchestrator.sh:302` `VALID_FLATLINE_MODELS` MUST include `gemini-3.1-pro` and `gemini-3.1-pro-preview`.
- `.claude/scripts/red-team-model-adapter.sh:55` MODEL_TO_PROVIDER_ID MUST include the same mapping.
- Python adapter `google_adapter.py:476` already handles `gemini-3*` `thinking_level` — NO Python change needed.

**T2.2 — Provider health-probe scaffolding** *(keystone — significantly expanded after Flatline PRD review)*

New script `.claude/scripts/model-health-probe.sh`. All sub-requirements below are REQUIRED; each addresses a Flatline finding (tag in parens).

*Availability state machine* (per SKP-001 / IMP-002). The probe MUST emit one of three explicit states per model, never conflating them:

| State | Meaning | Runtime behavior |
|-------|---------|------------------|
| `AVAILABLE` | Provider confirms model exists and is callable | Allow use; cache positive |
| `UNAVAILABLE` | Provider returned hard-404 or explicit not-found for the literal model ID | Block at CI; fail-fast at runtime; actionable error |
| `UNKNOWN` | Probe failed for transient reasons (timeout, 429, 5xx, auth-missing, network) | Warn, don't block; runtime uses cached last-known-good; log to trajectory |

*Provider-specific correctness rules* (per SKP-001):

| Provider | Availability signal | Pagination | Scope gotchas |
|---|---|---|---|
| **OpenAI** | `GET /v1/models` → model ID present in `data[].id` across all pages | Follow pagination; aggregate before asserting | Account-scoped: model may not appear for a restricted account even if generally available. Auth error (401/403) → `UNKNOWN`, not `UNAVAILABLE` |
| **Google** | `GET /v1beta/models` → model ID present in `models[].name` **OR** minimal `generateContent` succeeds with 200 | Handle pagination if page_size used | Region-scoped: listings differ by API region. `generateContent` NOT_FOUND with specific error message `"models/X is not found for API version Y"` → `UNAVAILABLE`. Other 404s → `UNKNOWN` |
| **Anthropic** | Minimal `POST /v1/messages` with `max_tokens: 1` → 200 OK **OR** 400 `invalid_request_error` for model field specifically | — | **REJECT ambiguous 4xx**: any 4xx that doesn't explicitly reference the model field → `UNKNOWN`, not `AVAILABLE`. Previous behavior "any non-404 4xx = available" is the exact defect Flatline flagged |

*Error taxonomy* (per SKP-002 #2):

| HTTP signal | Classification | Action |
|---|---|---|
| 200 | Available | Cache positive, 24h TTL |
| 404 (hard, model-specific error body) | Unavailable | Cache negative, 1h TTL; fail CI; fail runtime |
| 400 w/ model-field error | Unavailable | Same as hard-404 |
| 401 / 403 | Unknown (auth issue) | Warn; mark UNKNOWN; do not change cache |
| 408 / 429 / 5xx / network error | Unknown (transient) | Exponential backoff retry (3 attempts max); if still failing, mark UNKNOWN; do not change cache; preserve last-known-good |
| 404 generic (no model-specific error) | Unknown (probe-level issue) | Same as transient |

*Cache design* (per SKP-002 #1, IMP-005):

| Aspect | Specification |
|---|---|
| Positive cache TTL | 24 hours (operator-configurable) |
| **Negative cache TTL** | **1 hour** (shorter — unavailability is volatile; positive-availability is stable-enough) |
| Unknown cache TTL | **0 (do not cache)** — always re-probe next request |
| Concurrency | `flock` guard around read/modify/write operations on `.run/model-health-cache.json` |
| Schema versioning | `{"schema_version": "1.0", "entries": {...}}`; version mismatch → discard + re-probe |
| Corruption recovery | Invalid JSON → log warning, auto-rebuild; not fatal |
| Runtime synchronous recheck | On first model use after a provider error, force immediate re-probe (bypass cache) |
| Manual invalidation | `.claude/scripts/model-health-probe.sh --invalidate [model-id]` — clear single entry or full cache |

*Resilience layer* (per SKP-004):

| Feature | Specification |
|---|---|
| **Feature flag** | `.loa.config.yaml` `model_health_probe.enabled: true` (default). Setting to `false` disables probe entirely; framework reverts to hand-maintained allowlist |
| **Graceful degradation** | On probe infrastructure failure, `.loa.config.yaml` `model_health_probe.degraded_ok: true` permits proceeding with last-known-good cache + warning |
| **Circuit breaker** | After N consecutive probe failures for a provider (default: 5), open circuit for that provider: mark all its models as UNKNOWN, stop probing for `reset_timeout_seconds` (default 300). Aligned with `.claude/defaults/model-config.yaml` routing.circuit_breaker |
| **Operator override** | `LOA_PROBE_BYPASS=1` env var → skip probe at runtime, trust registry. Emits audit log entry `{"action":"probe_bypass","by":"$USER","reason":"$LOA_PROBE_BYPASS_REASON"}` to `.run/audit.jsonl` |
| **CI override label** | PR label `override-probe-outage` → CI workflow skips probe gate for that PR; emits audit log to workflow summary + `.run/audit.jsonl` |
| **Retry/backoff** | Exponential with jitter: 1s, 2s, 4s, 8s, 16s; max 3 attempts per call (within a single probe invocation) |

*Probe budgets* (per IMP-001):

| Aspect | Default |
|---|---|
| Max probe calls per run | 10 (one per configured model + headroom) |
| Per-run cost budget | 5 cents ($0.05) — probes are cheap, budget is a safety net |
| Timeout per call | 30 seconds |
| Total invocation timeout | 120 seconds |

*Endpoint overrides* (per IMP-006):

| Mechanism | Spec |
|---|---|
| Config-file override | `.loa.config.yaml` `model_health_probe.endpoint_overrides.{openai,google,anthropic}` per-provider URL |
| Env-var override | `LOA_PROBE_ENDPOINT_OPENAI`, `LOA_PROBE_ENDPOINT_GOOGLE`, `LOA_PROBE_ENDPOINT_ANTHROPIC` |
| Proxy support | Respects `HTTPS_PROXY` / `NO_PROXY` — no custom proxy config |
| Enterprise/offline | When all overrides unset and no network, probe returns UNKNOWN with degraded_ok-respecting behavior |

*CI policy* (per SKP-003, IMP-009):

| Trigger | Behavior |
|---|---|
| **Primary** | PR changes to `model-config.yaml`, `.loa.config.yaml.example`, `model-adapter.sh`, `flatline-orchestrator.sh`, `red-team-model-adapter.sh` |
| **Expanded scope** | Also trigger on any PR that modifies a file in `.claude/adapters/` or `.claude/scripts/` that imports/sources the above — via dependency-graph scan (`grep -l "model-adapter.sh"`) |
| **Scheduled drift check** | Daily cron on `main` branch — catches drift introduced through paths not caught by per-PR triggers; failures open an auto-issue labeled `model-health-drift` |
| **Fork PRs** | Run in **listing-only mode**: skip auth-required `generateContent`/`messages` probes; only probe listing endpoints that succeed with minimal/no auth. Missing secrets → UNKNOWN (warn, do not fail). Explicit workflow doc clarifies this policy |
| **Override mechanism** | Label `override-probe-outage` bypasses the gate (audit-logged) |

*Secrets discipline* (per SKP-005):

| Requirement | Spec |
|---|---|
| **Mandatory log redaction** | `curl --config` pattern + `set +x` discipline around secret operations; output filters to replace API keys with `[REDACTED]` |
| **No artifact upload** | Probe response payloads MUST NOT be uploaded as CI artifacts (may contain rate-limit headers, org IDs, etc.) |
| **Secret-scanning test** | Bats test that runs probe, captures stdout/stderr, asserts no pattern matching `(sk-|AIza|ghp_|-----BEGIN)` appears in output |
| **Fail-path redaction** | On probe error, error handler MUST redact any request body before logging (API keys are sometimes embedded in misconfigured auth headers) |

*Integration points*:

- **A (CI)** — `.github/workflows/model-health-probe.yml`: triggers per CI policy above; fails PR on UNAVAILABLE findings; posts findings as PR comment; respects override label
- **B (Runtime)** — `model-adapter.sh` and `model-invoke` config-load path: cache hit → 0ms overhead; cache miss → background re-probe if stale, block-with-fail-fast if known-unavailable
- **C (Registry latency probe)** — For `probe_required: true` registry entries (e.g., GPT-5.5 latent), probe auto-enables them when availability transitions from UNKNOWN → AVAILABLE

*New file surface*: `.claude/scripts/model-health-probe.sh`, `.github/workflows/model-health-probe.yml`, `.github/workflows/model-health-drift-daily.yml`, bats + pytest test coverage.

**T2.3 — GPT-5.5 latent registry entry**
Add `gpt-5.5` and `gpt-5.5-pro` to `.claude/defaults/model-config.yaml` `providers.openai.models` with:
- Context window: 400000 (pending confirmation on release)
- Pricing: standard $5/$30 per MTok (input/output), Pro $30/$180 — published 2026-04-23
- Capabilities: `[chat, tools, function_calling, code]` (`thinking_traces` pending confirmation)
- Flag `probe_required: true` — health-probe treats entry as latent until provider `/v1/models` confirms

Health-probe's CI gate auto-enables once the model appears in the OpenAI listing; no manual registry flip required.

### Tier 3 — Dissenter currency audit (de-scope candidate)

**T3.1 — Dissenter default audit**
Verification task (no code change expected unless discrepancy found):
- Confirm `.loa.config.yaml.example` `flatline_protocol.code_review.model` and `security_audit.model` are `gpt-5.3-codex` ✅ (already verified 2026-04-24)
- Confirm `adversarial-review.sh:74,102` fallback default is `gpt-5.3-codex` ✅ (already verified 2026-04-24)
- Grep all `.claude/` for remaining `gpt-5.2` hard defaults — document any found as follow-up bug
- Add operator-advisory to `.loa.config.yaml.example` comments: *"If you have `gpt-5.2` pinned in your `.loa.config.yaml`, consider migrating to `gpt-5.3-codex` — the earlier model exhibits a `{{DOCUMENT_CONTENT}}` hallucination pattern (#618) that T1.3 pre-check defends against but does not eliminate at source."*

## 6. Technical & Non-Functional

| Constraint | Requirement |
|-----------|-------------|
| **Zone-system** | All writes target `.claude/` (System Zone). This PRD authorizes writes per `.claude/rules/zone-system.md` for cycle-093 scope only. |
| **Latency** | Health-probe cache TTL ≥ 24h default; config-load adds ≤ 50ms on cache hit |
| **Secrets handling** | Probe uses `curl --config <tempfile>` + `chmod 600` + `mktemp` pattern per shell-conventions. No CLI key exposure. No probe output logs API keys. |
| **Backward compat** | No breaking changes to `.loa.config.yaml` schema. Legacy aliases (`claude-opus-4.6` → `4.7`, etc.) preserved. Operators with existing configs have zero migration burden. |
| **CI discipline** | Health-probe CI gate runs on PR changes to `model-config.yaml`, `.loa.config.yaml.example`, `model-adapter.sh`, `flatline-orchestrator.sh`, `red-team-model-adapter.sh` — NOT on every build (avoids rate-limit burn). |
| **Parallel-cycle isolation** | This cycle's artifacts under `grimoires/loa/cycles/cycle-093-stabilization/`. Rebase plan: when PR #603 merges, new branch `feature/cycle-093-stabilization` created from fresh `main`, PRD/SDD/sprint copied over. |
| **Testing** | Each T-req MUST include: bats for bash layer; pytest for Python touches; integration test for full health-probe flow against live providers (CI secret-gated). |
| **Observability** | Probe failures MUST be surfaced via trajectory log + NOTES.md decision log, not only stderr. |

## 7. Scope / MVP / Out-of-Scope

**In-scope (this cycle, all 7 T-reqs):** T1.1, T1.2, T1.3, T2.1, T2.2, T2.3, T3.1

**Out-of-scope (explicit defer, tracked):**
- **#601** — Parallel-cycle doctrine, stacked-PR drift alerts, slug-named reviewer dirs, verdict-shaped exit codes — structural multi-agent cycle in its own right
- **#443** — Cross-compaction amnesia, passive memory for freeform work — architectural, needs standalone design
- **#606** — Self-Refine / Reflexion micro-loop redesign — research-grade exploration
- **#598 / #599 / #600** — Already in-flight as cycle-092 PR #603 (READY_FOR_HITL); do not duplicate
- **Gemma 4, GPT-5.3-Codex-Spark, Gemini 3.1 Flash-Lite Preview, Nano Banana 2** — not urgent; add via health-probe mechanism in follow-up cycles as demand emerges

## 8. Risks & Dependencies

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| **Probe-correctness false pos/neg** across providers (Flatline SKP-001) | Medium | **CRITICAL** | State machine with explicit UNKNOWN state; provider-specific correctness rules per T2.2; Anthropic rejects ambiguous 4xx; secret-scanning test |
| **Probe infra creates new SPOF** (Flatline SKP-004) | Low-Med | **CRITICAL** | Feature flag `model_health_probe.enabled`; graceful degradation via `degraded_ok`; circuit breaker per provider; `LOA_PROBE_BYPASS=1` operator override with audit log; `override-probe-outage` PR label |
| Gemini 3.1 Pro Preview has residual v1beta instability (rate-limits, intermittent NOT_FOUND) | Medium | Medium | Health-probe (T2.2) handles this class; error taxonomy distinguishes transient (UNKNOWN) from hard (UNAVAILABLE) |
| Provider outage blocks unrelated PRs (Flatline SKP-002 #2) | Medium | Medium | Error taxonomy: 429/5xx → UNKNOWN not UNAVAILABLE; last-known-good fallback; override label |
| Stale cache window masks new unavailability (Flatline SKP-002 #1) | Medium | Medium | Split TTL: 24h positive, 1h negative, 0 unknown; synchronous recheck on first runtime provider error |
| `gpt-5.3-codex` exhibits same `{{DOCUMENT_CONTENT}}` pattern as `gpt-5.2` | Low-Med | Medium | T1.3 pre-check (bidirectional + normalized) is safety net |
| PR #603 (cycle-092) changes `spiral-harness.sh` — conflicts with T1.1 | Medium | Low | Branch from fresh `main` after #603 merges; T1.1 scope (gates) is distinct from cycle-092 scope (observability) |
| CI trigger misses drift via indirect paths (Flatline SKP-003) | Medium | Medium | Dependency-graph scope in CI trigger; scheduled daily probe on `main` |
| [ASSUMPTION] GPT-5.5 API ships within this cycle window with the announced model IDs | High | Low | Pricing known from announcement; `probe_required: true` flag keeps entry latent until probe confirms; config update is single-line if IDs differ |
| [ASSUMPTION] Existing `adversarial-review-gate.sh` hook (v1.94.0) is compatible with harness-invoked skill path | Medium | Low | Verify during T1.1 implementation; fallback to alternative wiring (harness-wrapped `adversarial-review.sh`) if skill-invoke ergonomics block |
| [ASSUMPTION] Google v1beta's `ListModels` endpoint surfaces `gemini-3.1-pro-preview` by exact ID | Low | Medium | Probe parser handles paginated + aliased results; explicit `generateContent` fallback signal |

**External dependencies:**
- Anthropic Opus 4.7 (current default, stable, released 2026-04-16)
- OpenAI GPT-5.3-codex (current dissenter default, stable, released 2026-02-05)
- Google Gemini API v1beta (Gemini 3.1 Pro Preview, live since 2026-02-19)

**Internal dependencies:**
- Cycle-092 PR #603 (independent scope; rebase if needed, not a blocker)
- `adversarial-review-gate.sh` hook (v1.94.0 — already landed)

## 9. Sprint Shape Recommendation

*(For `/architect` and `/sprint-plan` phases to refine.)*

| Sprint | Theme | T-reqs | Size | Depends on |
|--------|-------|--------|------|------------|
| sprint-1 | Harness adversarial wiring | T1.1 | M — structural change to harness gates | — |
| sprint-2 | Bridgebuilder dist + dissenter filter | T1.2 + T1.3 | S+S — single-file build fix + filter script | — |
| sprint-3 | Provider health-probe scaffolding *(keystone)* | T2.2 | L — architectural spike, new script + CI + cache | — |
| sprint-4 | Model registry currency | T2.1 + T2.3 + T3.1 | M — wires new models behind probe + audit | sprint-3 |

Sprints 1, 2, 3 are independent and can run in parallel or sequentially.
Sprint 4 depends on sprint-3's probe being operational.

## 10. Sources

- Open issues: [#605](https://github.com/0xHoneyJar/loa/issues/605), [#607](https://github.com/0xHoneyJar/loa/issues/607), [#618](https://github.com/0xHoneyJar/loa/issues/618), [#602](https://github.com/0xHoneyJar/loa/issues/602), #574 (closed, informative)
- Related in-flight: PR #603 (cycle-092, READY_FOR_HITL, addresses #598/#599/#600)
- `grimoires/loa/NOTES.md` — cycle-082 model defaults migration; cycle-092 recent state
- `.claude/defaults/model-config.yaml:1-266` — canonical model registry (audit 2026-04-24)
- `.claude/scripts/flatline-orchestrator.sh:302` — VALID_FLATLINE_MODELS allowlist
- `.claude/scripts/model-adapter.sh:96-177` — MODEL_TO_PROVIDER_ID bash map
- `.claude/scripts/red-team-model-adapter.sh:43-58` — role/model mappings
- `.claude/scripts/adversarial-review.sh:74,102` — dissenter fallback default
- `.claude/skills/bridgebuilder-review/dist/main.js:7` — broken import (#607 root)
- `.claude/adapters/loa_cheval/providers/google_adapter.py:476` — Python `gemini-3*` thinking_level handler (already correct)
- Provider docs:
  - [Gemini 3.1 Pro Preview](https://ai.google.dev/gemini-api/docs/models/gemini-3.1-pro-preview)
  - [Gemini 3 Developer Guide](https://ai.google.dev/gemini-api/docs/gemini-3)
  - [Introducing GPT-5.5 — OpenAI](https://openai.com/index/introducing-gpt-5-5/)
  - [Introducing GPT-5.3-Codex — OpenAI](https://openai.com/index/introducing-gpt-5-3-codex/)
  - [Claude Opus 4.7 — Anthropic](https://www.anthropic.com/claude/opus)

---

> **Sources**: Phase 0 codebase analysis 2026-04-24, open issues #605/#607/#618/#602, user brief "Loa Stabilization & Model-Currency Architecture", NOTES.md cycle-082 + cycle-092 context. Confirmed in pre-generation gate: artifact path A (cycle-isolated), cycle name `cycle-093-stabilization`, branch `main` (stack if #603 merges late), interview mode minimal.
>
> **Flatline integration (2026-04-24T04:02Z)**: 3-model review (Opus + GPT-5.3-codex + Gemini 2.5 Pro) produced 100% agreement, HIGH=7 BLOCKER=6, full confidence. All 6 BLOCKERS concentrated on T2.2 keystone; integrated into this PRD revision. Integration doc: `grimoires/loa/cycles/cycle-093-stabilization/flatline-prd-integration.md`. Major changes: T1.2 added fixture-submodule CI test; T1.3 added bidirectional + normalization; T2.2 expanded with state machine (AVAILABLE/UNAVAILABLE/UNKNOWN), provider-specific correctness rules, error taxonomy, split TTL cache with flock + versioning, resilience layer (feature flag + circuit breaker + operator override), expanded CI scope + daily drift check, secrets discipline with secret-scanning test; Section 8 added SKP-001 and SKP-004 as CRITICAL risks.
