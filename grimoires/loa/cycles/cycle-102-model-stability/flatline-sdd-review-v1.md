# Flatline Review — cycle-102 SDD v1.0 (manual synthesis 2026-05-09)

> Manual Flatline run after orchestrator's auto-trigger silently degraded (third
> consecutive demonstration of vision-019 axiom 3 in this session). 3 of 4 manual
> direct calls succeeded; opus-skeptic failed empty-content × 3 on SDD (NEW
> adapter bug A7 — opus is not reasoning-class, so budget-starvation theory
> doesn't fully apply).

## Coverage

| Voice | Status | Findings |
|---|---|---|
| opus-review | ✅ legacy direct | 10 improvements (6 HIGH + 4 MED) |
| **opus-skeptic** | ❌ legacy: empty content × 3 → exit 5 | A7 NEW BUG — opus on SDD-class prompt in skeptic mode |
| gemini-review | ✅ legacy direct | 10 improvements (5 HIGH + 4 MED + 1 LOW) |
| gemini-skeptic | ✅ legacy direct | 10 concerns (2 CRIT + 4 HIGH + 3 MED + 1 LOW) |

**Coverage gap**: only 1 of 2 skeptics succeeded. Single skeptic source means we can't claim HIGH_CONSENSUS via independent skeptic agreement on the SDD. Cross-checking gemini-skeptic findings against opus-review surfaces overlap on probe semantics, schema migration, and operator-facing surfaces.

## Critical Findings (BLOCKER class — must address before /sprint-plan)

### B1. Cross-runtime locking mechanism mismatch (CRIT 900)

> "The SDD specifies bash uses `flock`, Python uses `fcntl.flock`, and TS uses `proper-lockfile`. `proper-lockfile` uses directory/file creation for locking, NOT POSIX advisory locks (`fcntl`). The TS runtime will completely ignore Python/Bash locks, leading to race conditions and corrupted JSON cache files." — gemini-skeptic SKP-001 (CRIT 900)

**Recommendation**: Standardize on POSIX `fcntl.flock` across all three runtimes. TS uses native `fs.constants.O_EXCL` + `fcntl` ioctl via `node:fs` or write a tiny native binding. **Alternative**: change probe-cache architecture to NOT require cross-runtime mutex — each runtime maintains its own cache file (`{runtime}-{provider}.json`), accepting first-probe duplication for cache-miss simplicity.

**SDD amendment**: §4.2.3 (flock contract) — pick one approach; eliminate cross-runtime locking confusion.

### B2. Bedrock authentication complexity vastly underestimated (CRIT 850)

> "Assuming Bedrock slots in as a 'peer provider' with just an `endpoint_family` ignores AWS SigV4 signing, region requirements, and boto3/credential-chain dependencies. A simple Bearer token (like OpenAI/Anthropic) will not work, breaking the unified adapter pattern." — gemini-skeptic SKP-002 (CRIT 850)

**Recommendation**: Per-provider auth-strategy field in registry: `auth: bearer_env | sigv4_aws | apikey_env`. Schema additions for `region`, `iam_role_arn` or `iam_profile`. cycle-096 #652 plugin contract referenced explicitly in SDD §3.3 + AC-2.2.

**SDD amendment**: §3.3 + [ASSUMPTION-2] — concrete Bedrock auth-strategy spec.

## High Consensus / High-confidence findings

| ID | Finding | Source | Severity | SDD section |
|---|---|---|---|---|
| HC1 | Shadow pricing exhausts real budget if not separated | gemini SKP-003 (HIGH 750) | HIGH | §3.3 + §9.4 — separate `shadow_cost_micro_usd` from `cost_micro_usd`; budget gate uses real cost only |
| HC2 | Fail-open + local network down = thread starvation (full LLM timeout × concurrent) | gemini SKP-004 (HIGH 700) | HIGH | §4.2.2 — fail-fast on `LOCAL_NETWORK_FAILURE`; fail-open ONLY on probe-itself-can't-reach-specific-provider |
| HC3 | Thundering herd on probe cache expiry — multiple callers redundant-probe at TTL | gemini SKP-005 (HIGH 680) + opus IMP-003 (HIGH 0.85) | HIGH | §4.2.3 — stale-while-revalidate pattern |
| HC4 | Weekly smoke-fleet too infrequent for "active alerting" claim | gemini SKP-006 (HIGH 650) | HIGH | §9.1 — bump to hourly OR clarify HC6 alerting routes through per-invocation events, not smoke-fleet |
| HC5 | DEGRADED probe outcome (vs binary OK/FAIL) | gemini IMP-001 (HIGH 0.95) | HIGH | §4.2.2 — ternary OK / DEGRADED / FAIL |
| HC6 | Bedrock auth abstraction in `probe_provider` | gemini IMP-002 (HIGH 0.95) | HIGH | §4.2.2 — composes with B2 |
| HC7 | Lock acquisition timeouts + stale lock recovery | gemini IMP-003 (HIGH 0.9) | HIGH | §4.2.3 — `flock -w 5`; stale-lock detection |
| HC8 | Audit emission contract during `LOA_FORCE_LEGACY_MODELS=1` | gemini IMP-004 (HIGH 0.9) | HIGH | §6.2 — `kill_switch_active: true` field in event |
| HC9 | Smoke-fleet GH Actions secret masking | gemini IMP-009 (HIGH 0.9) | HIGH | §9.1 — `::add-mask::` workflow steps for API keys |
| HC10 | [ASSUMPTION-3] (audit primitive_id) MUST resolve BEFORE Sprint 1, not during | opus IMP-001 (HIGH 0.9) | HIGH | §4.4 + §6.1 — pin Option A or B; if B, schema bump task lands first |
| HC11 | Schema migration mechanics for v1.x → v2.0.0 concretely | opus IMP-004 (HIGH 0.85) | HIGH | §3.3 — migrate script path, idempotence, dry-run mode |
| HC12 | Smoke-fleet secrets-management + key-isolation spec | opus IMP-002 (HIGH 0.85) | HIGH | §9 — read-only/limited keys, separate from production |
| HC13 | Contract test corpus AC-4.4a concrete (enumerate legacy code paths) | opus IMP-006 (HIGH 0.85) | HIGH | §8.2 quarantine block |
| HC14 | tier_groups → capability_classes derivation contract | opus IMP-008 (HIGH 0.8) | HIGH | §3.1 — explicit derivation order, edit precedence |

## Medium Findings

| ID | Finding | Severity |
|---|---|---|
| MC1 | Drift regex brittle for new naming (o1, o3, nova) | gemini SKP-007 (MED 550) |
| MC2 | Cycle detection aborts vs skips — should skip+WARN+continue | gemini SKP-008 (MED 500) |
| MC3 | Unbounded audit log growth — add size cap | gemini SKP-009 (MED 450) |
| MC4 | Operator-visible header behavior under degraded outputs (max line length) | opus IMP-005 (MED 0.75) |
| MC5 | Regression-detection beyond "two-consecutive-failure" | opus IMP-007 (MED 0.8) |
| MC6 | Probe-cache cross-CI-runner behavior | opus IMP-009 (MED 0.75) |
| MC7 | Observability/debugging surface ("why did this call route to X?") | opus IMP-010 (MED 0.8) |
| MC8 | Parallel cache-check/probing for fallback chain | gemini IMP-005 (MED 0.85) |
| MC9 | Split `total_latency_ms` into `probe_latency_ms` + `invocation_latency_ms` | gemini IMP-006 (MED 0.85) |
| MC10 | Float-point serialization rules for cross-runtime parity | gemini IMP-007 (MED 0.8) |
| MC11 | Cross-reference validation for `model_aliases_extra` dynamic | gemini IMP-008 (MED 0.85) |

## Low Findings

| ID | Finding |
|---|---|
| LC1 | Shadow pricing accumulation in audit `cost_micro_usd` (gemini IMP-010 LOW 0.75) |
| LC2 | Legacy quarantine false rollback-safety sense (gemini SKP-010 LOW 350) |

## Adapter bugs uncovered DURING this Flatline run

| ID | Surface | Evidence |
|---|---|---|
| **A7 NEW** | claude-opus-4-7 in **skeptic mode** returns empty content × 3 on SDD-class prompt (~50KB). Opus is NOT reasoning-class; budget-starvation theory doesn't fully apply. Possible causes: skeptic system prompt + large input triggers a model-side anomaly; large-context Anthropic API edge case; or the legacy adapter's anthropic call has a different bug here. | `flatline-sdd-direct/opus-skeptic.stderr` |
| **A6 reproduced** | Orchestrator parallel dispatch failed 3 of 6 calls AGAIN on SDD (same pattern as PRD run) | `flatline-sdd.log` |
| **A1+A2 reproduced** | gpt-5.5-pro empty content; gemini reasoning eventually-recovers — same as PRD run | (orchestrator stderrs not preserved) |

## Disposition

**B1 (Cross-runtime locking) and B2 (Bedrock auth) MUST land as SDD amendments before /sprint-plan.** Sprint 1+2 design contracts depend on resolution.

**HC1-HC14** integrated as SDD amendments OR Sprint-plan task hints (some are too detailed for SDD; sprint plan absorbs).

**MEDIUM/LOW** captured in this synthesis for sprint-plan reference; not bloating SDD.

**A7 adapter bug**: file as #794 follow-up comment OR new issue under Sprint 1 anchor scope.

Iter-2 NOT gated for same reason as PRD iter-1: fixing the adapter substrate is itself the cycle's deliverable. /sprint-plan SDD-iter-2 happens after Sprint 1 lands.
