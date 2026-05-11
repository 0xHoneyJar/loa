#!/usr/bin/env python3
"""
T1.1 — Spawn-per-call latency benchmark for ChevalDelegateAdapter sizing.

Measures the wall-clock cost of spawning `cheval` per call (Python interp
start + module imports + config load + provider config build) under three
conditions per Sprint 1 task T1.1:

  (a) cold-cache: fresh invocations after a brief idle gap, simulating
      first call in a session
  (b) warm-cache: back-to-back invocations, OS page cache hot
  (c) concurrent: 3 parallel streams of N invocations each, mimicking BB's
      3-model concurrent review-pass shape (anthropic + openai + google)

Sprint 1 decision gate: p95 ≤ 1000ms → spawn-mode default (T1.2);
                        p95 >  1000ms → daemon-mode mandatory (T1.3).

To keep measurements pure spawn-overhead (not API round-trip), uses
`cheval ... --dry-run` which validates and resolves config but never
contacts the provider.

Invocation:
  cd <repo-root>
  python3 grimoires/loa/cycles/cycle-103-provider-unification/handoffs/spawn-vs-daemon-benchmark.py

Output:
  - Raw measurements:   spawn-vs-daemon-benchmark-results.jsonl
  - Human summary stdout (p50/p95/p99 per condition + decision)
"""

from __future__ import annotations

import concurrent.futures
import json
import os
import statistics
import subprocess
import sys
import time
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[5]
CHEVAL = REPO_ROOT / ".claude" / "adapters" / "cheval.py"
RESULTS_PATH = Path(__file__).with_name("spawn-vs-daemon-benchmark-results.jsonl")

N_PER_CONDITION = 50
N_CONCURRENT_STREAMS = 3
P95_THRESHOLD_MS = 1000

MODEL = "claude-opus-4.7"  # Anthropic alias; dry-run skips the API call, so the choice
                            # only matters for config-resolution path coverage
AGENT = "reviewing-code"


def one_call() -> float:
    """Spawn cheval --dry-run once. Returns wall-clock ms."""
    cmd = [
        "python3",
        str(CHEVAL),
        "--agent",
        AGENT,
        "--model",
        MODEL,
        "--prompt",
        "noop",
        "--dry-run",
        "--output-format",
        "json",
    ]
    t0 = time.monotonic()
    proc = subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        timeout=30,
        check=False,
    )
    elapsed_ms = (time.monotonic() - t0) * 1000
    # On non-zero exit, treat as benchmark-failure (record but flag).
    return elapsed_ms if proc.returncode == 0 else -elapsed_ms  # negative = failure marker


def percentile(values: list[float], pct: float) -> float:
    if not values:
        return 0.0
    return statistics.quantiles(sorted(values), n=100)[int(pct) - 1] if len(values) > 1 else values[0]


def summarize(label: str, samples: list[float]) -> dict:
    successes = [s for s in samples if s > 0]
    failures = [s for s in samples if s <= 0]
    if not successes:
        return {
            "condition": label,
            "n": len(samples),
            "n_failed": len(failures),
            "p50_ms": None,
            "p95_ms": None,
            "p99_ms": None,
            "mean_ms": None,
            "min_ms": None,
            "max_ms": None,
        }
    return {
        "condition": label,
        "n": len(samples),
        "n_failed": len(failures),
        "p50_ms": round(percentile(successes, 50), 2),
        "p95_ms": round(percentile(successes, 95), 2),
        "p99_ms": round(percentile(successes, 99), 2),
        "mean_ms": round(statistics.mean(successes), 2),
        "min_ms": round(min(successes), 2),
        "max_ms": round(max(successes), 2),
    }


def run_cold_cache() -> list[float]:
    """50 calls with a short sleep between each — disfavors OS page cache reuse."""
    print(f"  (a) cold-cache: {N_PER_CONDITION} calls with 200ms idle gap")
    samples = []
    for i in range(N_PER_CONDITION):
        if i > 0:
            time.sleep(0.2)
        s = one_call()
        samples.append(s)
        if (i + 1) % 10 == 0:
            print(f"      {i+1}/{N_PER_CONDITION} ({s:.1f}ms last)")
    return samples


def run_warm_cache() -> list[float]:
    """50 back-to-back calls — OS page cache fully hot, no inter-call gaps."""
    print(f"  (b) warm-cache: {N_PER_CONDITION} back-to-back calls")
    samples = []
    for i in range(N_PER_CONDITION):
        s = one_call()
        samples.append(s)
        if (i + 1) % 10 == 0:
            print(f"      {i+1}/{N_PER_CONDITION} ({s:.1f}ms last)")
    return samples


def run_concurrent_bb_shape() -> list[float]:
    """3 parallel streams × N calls each = BB-3-model-concurrent-review-pass shape."""
    total = N_PER_CONDITION * N_CONCURRENT_STREAMS
    print(f"  (c) concurrent: {N_CONCURRENT_STREAMS} parallel streams × {N_PER_CONDITION} = {total} total calls")
    samples = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=N_CONCURRENT_STREAMS) as pool:
        futures = [pool.submit(one_call) for _ in range(total)]
        for i, fut in enumerate(concurrent.futures.as_completed(futures)):
            s = fut.result()
            samples.append(s)
            if (i + 1) % 30 == 0:
                print(f"      {i+1}/{total} ({s:.1f}ms last)")
    return samples


def main() -> int:
    if not CHEVAL.exists():
        print(f"FATAL: cheval not found at {CHEVAL}", file=sys.stderr)
        return 2

    # Pre-warm: one throwaway call so the first measurement isn't dominated by
    # one-off filesystem-warming overhead unrelated to subsequent spawns.
    print("# Pre-warm (one throwaway call)")
    _ = one_call()

    print()
    print("# Cold-cache pass")
    cold = run_cold_cache()
    print()
    print("# Warm-cache pass")
    warm = run_warm_cache()
    print()
    print("# Concurrent BB-shape pass")
    conc = run_concurrent_bb_shape()

    summaries = [
        summarize("cold_cache", cold),
        summarize("warm_cache", warm),
        summarize("concurrent_bb_shape", conc),
    ]

    raw = {
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "model": MODEL,
        "agent": AGENT,
        "n_per_condition": N_PER_CONDITION,
        "n_concurrent_streams": N_CONCURRENT_STREAMS,
        "p95_threshold_ms": P95_THRESHOLD_MS,
        "samples": {
            "cold_cache": cold,
            "warm_cache": warm,
            "concurrent_bb_shape": conc,
        },
        "summaries": summaries,
    }

    with RESULTS_PATH.open("w") as fh:
        fh.write(json.dumps(raw, indent=2) + "\n")

    print()
    print("# Summary")
    print()
    print(f"{'condition':>22}  {'n':>4}  {'fail':>4}  {'p50':>8}  {'p95':>8}  {'p99':>8}  {'mean':>8}  {'min':>8}  {'max':>8}")
    print("-" * 95)
    for s in summaries:
        print(
            f"{s['condition']:>22}  "
            f"{s['n']:>4}  "
            f"{s['n_failed']:>4}  "
            f"{(s['p50_ms'] or 0):>8.2f}  "
            f"{(s['p95_ms'] or 0):>8.2f}  "
            f"{(s['p99_ms'] or 0):>8.2f}  "
            f"{(s['mean_ms'] or 0):>8.2f}  "
            f"{(s['min_ms'] or 0):>8.2f}  "
            f"{(s['max_ms'] or 0):>8.2f}"
        )

    print()
    # Decision rule per Sprint 1 T1.1
    worst_p95 = max((s["p95_ms"] or 0) for s in summaries)
    if worst_p95 <= P95_THRESHOLD_MS:
        decision = "GO spawn-mode"
        rationale = (
            f"Worst-case p95 = {worst_p95:.0f}ms ≤ {P95_THRESHOLD_MS}ms threshold. "
            f"T1.3 daemon mode is OUT OF SCOPE for Sprint 1."
        )
    else:
        decision = "GO daemon-mode"
        rationale = (
            f"Worst-case p95 = {worst_p95:.0f}ms > {P95_THRESHOLD_MS}ms threshold. "
            f"T1.3 daemon mode is MANDATORY for Sprint 1."
        )

    print(f"# Decision: {decision}")
    print(f"# {rationale}")

    raw["decision"] = decision
    raw["decision_rationale"] = rationale
    with RESULTS_PATH.open("w") as fh:
        fh.write(json.dumps(raw, indent=2) + "\n")

    return 0


if __name__ == "__main__":
    sys.exit(main())
