---
title: T1.1 spawn-per-call latency benchmark — spawn-mode vs daemon-mode decision
sprint: sprint-1
cycle: cycle-103-provider-unification
ac_routed: T1.1 decision gate (spawn vs daemon)
related: [T1.2, T1.3]
date: 2026-05-11
status: complete
decision: GO spawn-mode
---

# T1.1 — Spawn-vs-Daemon Benchmark (D1.1)

## Decision

**GO spawn-mode.** Worst-case p95 = **126ms** (concurrent BB-shape
condition), ~10× margin under the 1000ms threshold per Sprint 1 T1.1.

**T1.3 daemon-mode is OUT OF SCOPE for Sprint 1.** The complexity tax —
UDS server, length-prefixed JSON framing, idle-timeout reaper, PID-file
orphan cleanup, daemon-shim wiring in `cheval-delegate.ts`,
`LOA_CHEVAL_DAEMON=1` activation env, plus the test surface for all of
the above — is not justified for the ~120ms-per-call savings at BB's
6–15 calls-per-PR-review workload (≲ 2s saved per PR).

## Method

Reproducibility: the harness lives at
`grimoires/loa/cycles/cycle-103-provider-unification/handoffs/spawn-vs-daemon-benchmark.py`.
Raw measurements at sibling `spawn-vs-daemon-benchmark-results.jsonl`.

| Variable | Value |
|----------|-------|
| Command | `python3 .claude/adapters/cheval.py --agent reviewing-code --model claude-opus-4.7 --prompt noop --dry-run --output-format json` |
| Measurement | Wall-clock from `subprocess.run()` call to return |
| Mode | `--dry-run` — validates input + resolves config + builds provider config, but never opens a socket to the provider |
| What this measures | Python interp startup + cheval module imports + persona load + provider-config build + model-resolver lookup |
| What this does NOT measure | API round-trip, TLS handshake, response parsing |
| N per condition | 50 (cold + warm); 150 (concurrent, 3 streams × 50) |
| Pre-warm | 1 throwaway call before measurement begins |

Conditions:

- **(a) cold cache** — 200ms idle gap between calls. Approximates first
  call in a session after the OS page cache may have drifted.
- **(b) warm cache** — back-to-back calls, no gaps. Steady-state.
- **(c) concurrent BB-shape** — 3 parallel streams (anthropic +
  openai + google review-pass shape), 50 calls per stream, 150 total.

`--dry-run` exits 0 with a small JSON config-resolution summary on
stdout (no network); the chosen model alias is `claude-opus-4.7` which
exercises the Anthropic provider-config path.

## Results

| Condition | n | failed | p50 (ms) | p95 (ms) | p99 (ms) | mean (ms) | min (ms) | max (ms) |
|-----------|---|--------|----------|----------|----------|-----------|----------|----------|
| cold_cache | 50 | 0 | 96.1 | 107.1 | 112.0 | 95.0 | 78.5 | 110.5 |
| warm_cache | 50 | 0 | 91.2 | 97.0 | 97.6 | 89.3 | 77.2 | 97.5 |
| concurrent_bb_shape | 150 | 0 | 99.8 | 125.8 | 131.8 | 101.8 | 82.8 | 133.1 |

Threshold (Sprint 1 T1.1): **p95 ≤ 1000ms → spawn-mode**.

## Interpretation

### Spawn overhead is small and tight-banded

p50–p99 spread is < 40ms in every condition. There is no long-tail
behavior in the measured range (200 cold + warm samples + 150 concurrent
samples = 400 total observations, zero failures). The benchmark window
of 30s `subprocess.run` timeout was never approached (max observed:
133ms).

### Concurrency adds modest overhead, not exponential

Concurrent p95 (126ms) is ~30% higher than warm p95 (97ms). This is
consistent with mild filesystem / page-cache contention from three
parallel Python interpreter spinups, not GIL or kernel-resource
exhaustion. BB's real review pass is 3-way concurrent by design, so this
is the load shape that matters for production.

### Cold-cache penalty is small (~10ms over warm)

The 200ms-gap "cold-cache" condition is only ~10ms p95 slower than
warm. This is below the per-call noise floor. In practice, OS page
caches for `cheval.py`, `python3`, and the cheval module tree stay
warm across BB invocations because they're called frequently — the
true "cold start" cost only matters for the very first call in a
fresh shell session.

### What this does NOT measure

Out of scope for the T1.1 decision but worth flagging:

1. **API round-trip cost.** Real cheval invocations include
   handshake + streamed response, typically 1–60s. Spawn overhead is a
   constant ~100ms baseline on top of that. Daemon-mode would save
   that 100ms baseline; not the API time.
2. **Memory residency.** Daemon-mode would hold the Python interp +
   cheval module tree resident (~40–80MB RSS). Spawn-mode pays no
   steady-state memory cost; each invocation allocates + frees.
3. **Crash recovery.** Spawn-mode is inherently isolated — a crash in
   one call cannot poison subsequent calls. Daemon-mode would need
   restart-on-failure semantics + crash-loop circuit breaker.
4. **Streaming-first calls.** cheval Sprint 4A introduced
   streaming-default transport (`http_post_stream`). The relevant
   spawn-cost is unchanged; streaming affects API-side latency, not
   process-start.

### Why this strengthens the spawn-mode case beyond pure latency

Spawn-mode is the **simpler operational model**: no PID file, no
orphan reaper, no socket-cleanup-on-crash, no version-skew between
daemon process and adapter shim. Sprint 1's goal (per prd.md §0) is
"every multi-model surface in Loa goes through the same hardened
cheval substrate" — the simpler substrate is also the more hardened
one. Daemon mode added latent failure surfaces (race-on-socket-removal,
orphan PIDs across SIGKILLs, stale-fd-after-restart) that spawn mode
does not have to specify or test.

## Effect on Sprint 1 task graph

| Task | Effect |
|------|--------|
| **T1.2** `ChevalDelegateAdapter` (TS) | **Proceed, spawn-mode only.** Drop the `mode?: "spawn" \| "daemon"` constructor option; the adapter is spawn-only. The shape of the option in SDD §5.3 stays in the type system (door open for cycle-104+) but T1.2 implements `mode === "spawn"` exclusively. |
| **T1.3** Cheval daemon mode (Python) | **OUT OF SCOPE for Sprint 1.** Defer to a follow-on cycle if a workload demands it (none currently does). |
| **T1.4** Retire `anthropic/openai/google.ts` | **No effect.** Migrates to spawn-mode delegate. |
| **T1.11** `LOA_BB_FORCE_LEGACY_FETCH=1` escape hatch | **No effect.** Hatch surfaces a guided rollback message; daemon-mode flag is not part of the hatch surface. |
| Sprint 1 scope | **Reduced by ~1 task.** T1.3's daemon-mode implementation (described as the largest single piece of Sprint 1 contingent work) is descoped. Roughly 4–8 engineering hours saved. |

## Verification

Reproduce locally:

```bash
cd <repo-root>
python3 grimoires/loa/cycles/cycle-103-provider-unification/handoffs/spawn-vs-daemon-benchmark.py
```

No API key required — all calls are `--dry-run`. Total runtime: ~25–40s.
Total cost: zero (no provider API contacted).

## Caveats and revisit triggers

This decision is reversible if any of the following hold in a later
cycle:

1. **BB starts making 20+ provider calls per review.** At that scale,
   per-call spawn overhead × call count starts to dominate. p95 = 126ms
   × 20 calls = 2.5s per PR review, still acceptable; but the threshold
   moves.
2. **Spawn overhead grows.** If cheval's import surface expands
   (e.g., heavy new dependencies), p95 could approach the 1000ms gate.
   Re-benchmark before any Python dep that adds >100MB to the import
   tree.
3. **Cross-platform regression on macOS / Windows.** This benchmark ran
   on Linux. Python interp startup is ~2–3× slower on macOS; if Loa
   gains macOS production runners, re-measure.

## Cross-references

- PRD § 8.5.1 IMP-002 (the analysis question this answers)
- SDD § 5.2 (the daemon UDS protocol — left in spec but undeployed)
- SDD § 5.3 (`mode?: "spawn" | "daemon"` constructor option — type kept,
  implementation spawn-only)
- `sprint.md` T1.1 / D1.1 (the task and deliverable)
