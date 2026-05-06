#!/usr/bin/env python3
"""Latency measurement instrumentation for cycle-099 NFR-Perf-1 (SDD §7.5.1).

Runs N iterations of the model-overlay-hook against a fixed reference
fixture, measuring with `time.perf_counter_ns()` for canonical resolution.
Emits p50/p95/p99/stddev as JSON.

Usage:
    measure.py --hook <path> --sot <path> --operator <path> --merged <path> \\
               --lockfile <path> --state <path> --schema <path> \\
               --iterations <int> --warmup <int> --mode {warm|cold}

  warm: regen the merged file once, then time N cache-hit invocations
        (p95 ≤50ms target per NFR-Perf-1)
  cold: time N invocations after deleting merged.sh between each
        (p95 ≤500ms target per SDD §7.5.1)

Output: JSON to stdout with keys:
    p50_ms, p95_ms, p99_ms, stddev_ms, iterations, mode, platform

Exit codes:
    0 — success (caller checks JSON for budget compliance)
    1 — measurement failure (one or more iterations exited non-zero)
    64 — usage error
"""

from __future__ import annotations

import argparse
import json
import math
import os
import platform
import statistics
import subprocess
import sys
import time
from pathlib import Path


def _percentile(sorted_values: list[float], p: float) -> float:
    """Linear-interpolation percentile. p in [0, 100]."""
    if not sorted_values:
        return 0.0
    if len(sorted_values) == 1:
        return sorted_values[0]
    k = (len(sorted_values) - 1) * (p / 100.0)
    f = math.floor(k)
    c = math.ceil(k)
    if f == c:
        return sorted_values[int(k)]
    return sorted_values[f] + (sorted_values[c] - sorted_values[f]) * (k - f)


_HOOK_MODULE = None


def _load_hook_module(hook_path: str):
    """Load the hook module once for in-process timing; subsequent calls
    reuse the cached module. Mirrors the cheval startup pattern (single
    interpreter, single import).
    """
    global _HOOK_MODULE
    if _HOOK_MODULE is not None:
        return _HOOK_MODULE
    import importlib.util
    spec = importlib.util.spec_from_file_location("loa_overlay_hook_perf", hook_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"could not load {hook_path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules["loa_overlay_hook_perf"] = module
    spec.loader.exec_module(module)
    _HOOK_MODULE = module
    return module


def _invoke_hook(args: argparse.Namespace) -> tuple[int, float]:
    """Single invocation; returns (rc, elapsed_seconds).

    `--invoke-mode in-process` (default): import the hook once and call
    run_hook() directly. This is the canonical NFR-Perf-1 measurement —
    cheval invokes the hook in-process at startup, NOT via subprocess.

    `--invoke-mode subprocess`: fork a python3 subprocess per iteration.
    Pays the Python startup cost; useful as upper-bound smoke test but
    NOT the canonical NFR-Perf-1 measurement.
    """
    if args.invoke_mode == "in-process":
        module = _load_hook_module(args.hook)
        paths = module.HookPaths(
            sot=Path(args.sot),
            operator=Path(args.operator),
            merged=Path(args.merged),
            lockfile=Path(args.lockfile),
            state=Path(args.state),
            schema=Path(args.schema),
        )
        t0 = time.perf_counter_ns()
        rc = module.run_hook(paths)
        t1 = time.perf_counter_ns()
        return rc, (t1 - t0) / 1e9
    else:
        cmd = [
            sys.executable, args.hook,
            "--sot", args.sot,
            "--operator", args.operator,
            "--merged", args.merged,
            "--lockfile", args.lockfile,
            "--state", args.state,
            "--schema", args.schema,
        ]
        t0 = time.perf_counter_ns()
        result = subprocess.run(cmd, capture_output=True, text=True, check=False)
        t1 = time.perf_counter_ns()
        return result.returncode, (t1 - t0) / 1e9


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="measure.py")
    parser.add_argument("--hook", required=True)
    parser.add_argument("--sot", required=True)
    parser.add_argument("--operator", required=True)
    parser.add_argument("--merged", required=True)
    parser.add_argument("--lockfile", required=True)
    parser.add_argument("--state", required=True)
    parser.add_argument("--schema", required=True)
    parser.add_argument("--iterations", type=int, default=1000)
    parser.add_argument("--warmup", type=int, default=50)
    parser.add_argument("--mode", choices=["warm", "cold"], required=True)
    parser.add_argument(
        "--invoke-mode",
        choices=["in-process", "subprocess"],
        default="in-process",
        help="in-process (default) for canonical NFR-Perf-1 measurement; "
             "subprocess for upper-bound smoke test (pays Python startup cost).",
    )
    args = parser.parse_args(argv)

    # Warm-up phase (not measured)
    if args.mode == "warm":
        # Single cold regen to populate the cache, then measure cache hits
        rc, _ = _invoke_hook(args)
        if rc != 0:
            sys.stderr.write(f"warm-up cold-regen failed: rc={rc}\n")
            return 1

    durations: list[float] = []
    for i in range(args.warmup):
        if args.mode == "cold":
            # delete merged file to force regen
            try:
                os.unlink(args.merged)
            except FileNotFoundError:
                pass
        rc, _ = _invoke_hook(args)
        if rc != 0:
            sys.stderr.write(f"warmup iteration {i} failed: rc={rc}\n")
            return 1

    # Measured phase
    failures = 0
    for i in range(args.iterations):
        if args.mode == "cold":
            try:
                os.unlink(args.merged)
            except FileNotFoundError:
                pass
        rc, elapsed = _invoke_hook(args)
        if rc != 0:
            failures += 1
            continue
        durations.append(elapsed * 1000.0)  # → ms

    if failures > 0:
        sys.stderr.write(f"{failures}/{args.iterations} iterations failed\n")
        return 1
    if not durations:
        sys.stderr.write("no successful iterations\n")
        return 1

    sorted_d = sorted(durations)
    p50 = _percentile(sorted_d, 50)
    p95 = _percentile(sorted_d, 95)
    p99 = _percentile(sorted_d, 99)
    stddev = statistics.stdev(durations) if len(durations) > 1 else 0.0

    output = {
        "p50_ms": round(p50, 3),
        "p95_ms": round(p95, 3),
        "p99_ms": round(p99, 3),
        "stddev_ms": round(stddev, 3),
        "iterations": len(durations),
        "mode": args.mode,
        "platform": f"{platform.system().lower()}-{platform.machine()}",
    }
    print(json.dumps(output, sort_keys=True, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
