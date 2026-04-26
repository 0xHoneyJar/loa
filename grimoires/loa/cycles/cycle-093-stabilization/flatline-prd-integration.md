# Flatline Integration — cycle-093 PRD

> **Document**: `grimoires/loa/cycles/cycle-093-stabilization/prd.md`
> **Phase**: prd
> **Timestamp**: 2026-04-24T04:02:48Z
> **Models**: 3-model (opus + gpt-5.3-codex + gemini-2.5-pro)
> **Agreement**: 100% (HIGH=7, DISPUTED=0, LOW=0, BLOCKER=6)
> **Confidence**: full
> **Cost/Latency**: 155s total, 45 cents

## Summary

The multi-model review found the PRD directionally sound (100% agreement on all 7 high-consensus improvements) but flagged the keystone T2.2 (Provider health-probe) as **underspecified in six concrete ways**. All six blockers concentrate on T2.2 — the other T-reqs were not contested.

**This is exactly the signal that justified running Flatline.** A single-model review would have approved the PRD. The tertiary skeptic (Gemini 2.5 Pro) specifically surfaced provider-correctness and CI-resilience concerns that Opus + GPT-5.3-codex did not lead with.

## Blockers (6) — must resolve before architecture

### SKP-001 (CRITICAL, 910) — Health-probe correctness across providers

| Field | Value |
|-------|-------|
| **Concern** | OpenAI/Google model listings are account-, region-, and rollout-dependent; Anthropic probe accepting any non-404 4xx as "available" is flawed |
| **Why matters** | Can mark unavailable models as healthy OR healthy models as unavailable — undermining the core invariant |
| **Location** | T2.2 |
| **Recommendation** | Define provider-specific correctness rules (auth errors vs availability errors), pagination handling, region/account scope behavior, **normalized availability state machine with explicit UNKNOWN state** |

### SKP-004 (CRITICAL, 865) — Probe failure creates new single point of failure

| Field | Value |
|-------|-------|
| **Concern** | Keystone change introduces new SPOF in CI and runtime gating. Probe infra flakiness → deploy velocity or runtime stability collapse |
| **Why matters** | The thing meant to prevent silent failures becomes the thing that causes them |
| **Location** | T2.2 Integrations A/B, Section 8 Risks |
| **Recommendation** | Feature flag, graceful degradation policy, retry/backoff with circuit breaker, operator override with audit logging |

### SKP-002 #1 (HIGH, 760) — 24h cache TTL creates stale window

| Field | Value |
|-------|-------|
| **Concern** | Model can be removed minutes after successful probe; runtime trusts cache for up to 24h |
| **Why matters** | Conflicts with "probed invariant" promise; recreates silent trust failures |
| **Recommendation** | Negative-cache TTL shorter than positive TTL, force synchronous recheck on first model use after provider errors, emergency cache busting |

### SKP-002 #2 (HIGH, 720) — Provider outage ≠ config error

| Field | Value |
|-------|-------|
| **Concern** | Transient provider outage or rate-limit → PRs blocked with "UNAVAILABLE" findings unrelated to the PR |
| **Why matters** | Converts provider reliability into Loa CI reliability |
| **Recommendation** | Distinguish hard-404 (fail PR) from transient errors (warn, don't block); CI override mechanism; last-known-good cache for fallback |

### SKP-005 (HIGH, 740) — Secrets handling incomplete

| Field | Value |
|-------|-------|
| **Concern** | curl config + chmod 600 is good locally, but PRD doesn't cover: log redaction, workflow artifact retention, secret-echo in failure paths |
| **Recommendation** | Mandatory log redaction, disable shell tracing (`set +x`) around secret ops, prohibit artifact upload of probe payloads, secret-scanning tests for workflow output |

### SKP-003 (HIGH, 705) — CI trigger scope too narrow

| Field | Value |
|-------|-------|
| **Concern** | Model behavior can change via adapters, shared scripts, packaging, env defaults not in path filters. Drift can ship without probe gate firing |
| **Recommendation** | Expand to dependency-graph detection OR run lightweight probe on all PRs with rate-limited mode. **Scheduled daily probe checks on main** |

## High Consensus (7) — auto-integrate

### IMP-001 (avg 855) — Probe cost/throttling budgets
Live CI probe without explicit request/cost budgets and back-off is a source of throttling, spend leakage, flaky gates.

### IMP-002 (avg 900) — Probe failure vs model unavailability distinction
Critical clarification. Acceptance criteria must explicitly distinguish "probe failed" from "model unavailable." (This overlaps with SKP-001's state machine — resolve both together.)

### IMP-003 (avg 815) — T1.3 filter robustness
Literal-token filtering is brittle; variants/escaping are common model behaviors. Add bidirectional checks and normalization rules.

### IMP-005 (avg 740) — Cache file concurrency
Shared cache files in CI/local parallel runs can race. Locking/versioning/recovery semantics needed.

### IMP-006 (avg 810) — Probe endpoint overrides
Hard-coded endpoints fail in enterprise/offline/proxy setups. Override/bypass mechanisms needed.

### IMP-007 (avg 730) — Fixture-submodule CI test
Defect manifests in submodule consumers (#607). Fixture-submodule CI test is the most credible acceptance gate for T1.2.

### IMP-009 (avg 795) — CI secret policy
Secret availability differences (especially fork PRs) can break or silently bypass checks. Explicit policy and fallback behavior required.

## PRD Changes Made

### T2.2 — Expanded substantially
- Added **provider-specific correctness rules** (OpenAI: pagination + auth/404 distinction; Google: account-scoped/region-dependent handling; Anthropic: explicit success signal, reject ambiguous 4xx)
- Added **availability state machine** with `AVAILABLE | UNAVAILABLE | UNKNOWN` states
- Split cache TTL: **24h positive, 1h negative**; synchronous recheck on runtime provider error; `--invalidate` cache-bust
- Added **resilience layer**: feature flag `model_health_probe.enabled`; circuit breaker (N consecutive failures → open); operator override `LOA_PROBE_BYPASS=1` with audit log
- Transient vs permanent error taxonomy: hard-404 fails; timeouts/429/5xx warn + UNKNOWN
- **CI override** label: `override-probe-outage` with audit trail
- **Scheduled daily probe** on main (catches drift outside path-scoped triggers)
- Dependency-graph scope for CI trigger (fallback: rate-limited probe on all PRs)
- Probe budgets: max 10 per run, exponential backoff with jitter, 5-cent per-run cap
- Secrets: `set +x` discipline, mandatory log redaction, no artifact upload of probe payloads, secret-scanning test

### T2.2 cache layer (new sub-requirement)
- `flock`-guarded cache read/modify/write
- Schema versioning (v1.0); version mismatch → discard + re-probe
- Corrupted cache → auto-rebuild (not fatal)

### T2.2 endpoint overrides (new sub-requirement)
- `.loa.config.yaml` `model_health_probe.endpoint_overrides` map per provider
- Env vars `LOA_PROBE_ENDPOINT_OPENAI`, `LOA_PROBE_ENDPOINT_GOOGLE`, `LOA_PROBE_ENDPOINT_ANTHROPIC`
- Respects `HTTPS_PROXY` / `NO_PROXY`
- Fork-PR mode: probe runs in "listing-only" mode (no auth-required probes); missing secrets warn + UNKNOWN (don't fail)

### T1.3 — Filter robustness
- **Bidirectional** checks: diff-contains-token vs finding-contains-token (4 quadrants)
- **Normalization**: handle common escapes (`\{\{`, `{{ `, `}}`) and variants

### T1.2 — Fixture-submodule CI test
- Added to acceptance criteria: `.claude/tests/fixtures/submodule-consumer/` fixture repo
- CI job exercises bridgebuilder-review via submodule path
- Asserts end-to-end JSON summary output

### Section 8 Risks — Expanded
- Added SKP-004 risk: probe SPOF (mitigated by resilience layer above)
- Added SKP-001 risk: provider-specific false positive/negative (mitigated by state machine)

## Agreement detail

| Finding | Opus | GPT-5.3-codex | Gemini-2.5-pro | Delta | Avg |
|---------|-----:|--------------:|---------------:|------:|----:|
| IMP-001 | 820  | 890           | 950            | 70    | 855 |
| IMP-002 | 880  | 920           | 980            | 40    | 900 |
| IMP-003 | 810  | 820           | 920            | 10    | 815 |
| IMP-005 | 750  | 730           | 880            | 20    | 740 |
| IMP-006 | 860  | 760           | 960            | 100   | 810 |
| IMP-007 | 720  | 740           | 820            | 20    | 730 |
| IMP-009 | 780  | 810           | 850            | 30    | 795 |

**Observation**: Gemini 2.5 Pro consistently scored findings higher than Opus and GPT-5.3-codex, and was the sole source of all 6 BLOCKERS via the `tertiary_skeptic` role. This is strong evidence for the 3-model mode and for Gemini's specific value in planning-document skepticism. When we re-add Gemini 3.1 Pro as part of this cycle's T2.1, the tertiary leg should upgrade naturally.

## Next step

PRD updated in place. Recommendation: **re-run Flatline once on the updated PRD** to verify the integration is clean (cheap, ~45 cents, <3 min), then proceed to `/architect`. Alternative: skip re-flatline and go straight to `/architect` since the findings were concrete and mechanical.

User decision gate before `/architect` invocation.
