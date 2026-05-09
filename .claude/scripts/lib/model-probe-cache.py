#!/usr/bin/env python3
"""model-probe-cache.py — cycle-102 Sprint 1 (T1.3) canonical implementation.

Per-runtime, flock-guarded probe cache that gates every model invocation on
provider liveness. Implements the SDD section 4.2 contract:

  - probe_provider(provider, model, *, ttl_seconds, timeout_seconds, probe_fn)
      -> ProbeResult with outcome in {AVAILABLE, DEGRADED, FAIL}
  - invalidate_provider(provider)
  - detect_local_network()

Storage layout (SDD section 4.2.3 Option B — per-runtime cache files):
  .run/model-probe-cache/python-<provider>.json   (mode 0600)
  .run/model-probe-cache/                         (dir mode 0700)

Locking: fcntl.flock LOCK_EX on a sidecar .lock file with a 5-second wait
(HC7). Stale-lock recovery: if the lockfile holder PID is not running,
force-acquire and emit a STALE_LOCK_RECOVERED WARN to stderr. Lock is
acquired across the entire read-modify-write atom.

Stale-while-revalidate (HC3): when TTL has expired BUT a cached entry
exists, return the cached entry immediately to the caller AND fire a
background refresh thread. Foreground caller never blocks on TTL refresh.

Fail-open vs fail-fast (HC2 / B2 closure):
  - Probe-itself-can't-reach-this-provider -> AVAILABLE outcome with WARN
    (caller proceeds; the provider may still answer the actual call).
  - Local-network failure (detect_local_network() -> False) -> FAIL outcome
    with error_class=LOCAL_NETWORK_FAILURE (caller fail-fasts; do not
    long-poll a doomed call).

The library is **probe-fn-agnostic**: the caller-supplied `probe_fn` does
the provider-specific work. The library handles caching, locking,
stale-while-revalidate, and outcome classification. This separation keeps
the library testable (mock the probe_fn) and the actual probe logic
co-located with the cheval invocation that owns provider auth.

Public API exposed via __all__ at the bottom of the file.
"""

from __future__ import annotations

import argparse
import errno
import fcntl
import json
import os
import socket
import sys
import tempfile
import threading
import time
import traceback
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any, Callable, Optional

SCHEMA_VERSION = "1.0.0"
# Per SDD section 4.2.3 Option B, each runtime maintains its own cache file
# namespace. Default RUNTIME is "python"; the bash twin and TS port set
# LOA_PROBE_RUNTIME=bash / typescript so cache writes land at
# `<runtime>-<provider>.json` and don't collide.
RUNTIME = os.environ.get("LOA_PROBE_RUNTIME", "python")
_VALID_RUNTIMES = ("python", "bash", "typescript")
if RUNTIME not in _VALID_RUNTIMES:
    sys.stderr.write(
        f"[model-probe-cache] WARN: LOA_PROBE_RUNTIME={RUNTIME!r} not in "
        f"{_VALID_RUNTIMES}; defaulting to 'python'\n"
    )
    RUNTIME = "python"
DEFAULT_TTL_SECONDS = 60
DEFAULT_TIMEOUT_SECONDS = 2.0
DEFAULT_LOCAL_NETWORK_HOST = "1.1.1.1"
DEFAULT_LOCAL_NETWORK_PORT = 53
DEFAULT_LOCAL_NETWORK_TIMEOUT = 1.0
LOCK_WAIT_SECONDS = 5
DEGRADED_LATENCY_MS = 1500
PROBE_RESULT_KEYS = (
    "provider",
    "model",
    "outcome",
    "latency_ms",
    "error_class",
    "ts_utc",
    "cached",
)
# Both values MUST be members of the model-error.schema.json enum (10
# typed classes per cycle-102 SDD §4.1). BB iter-1 FIND-002 caught a
# producer/consumer vocabulary drift here: an earlier draft emitted
# the synthetic value PROBE_LAYER_DEGRADED, which the audit envelope
# would have rejected at the schema boundary — exactly the silent-
# degradation pattern this cycle is built to prevent.
#
# DEGRADED_PARTIAL is the correct typed class for fail-open probe-layer
# outcomes (probe couldn't reach this specific provider, but invocation
# proceeds with WARN). LOCAL_NETWORK_FAILURE is a typed class in its
# own right (whole-runner-no-internet preflight, fail-fast).
ERROR_CLASS_PROBE_DEGRADED = "DEGRADED_PARTIAL"
ERROR_CLASS_LOCAL_NETWORK = "LOCAL_NETWORK_FAILURE"


# =============================================================================
# Dataclasses
# =============================================================================


@dataclass
class ProbeResult:
    """Public probe result. Mirrors SDD section 4.2.2."""

    provider: str
    model: str
    outcome: str  # AVAILABLE | DEGRADED | FAIL
    latency_ms: int
    error_class: Optional[str]
    ts_utc: str
    cached: bool

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


@dataclass
class _CacheEntry:
    """Internal per-(provider, model) cache row."""

    outcome: str
    latency_ms: int
    error_class: Optional[str]
    ts_utc: str
    ttl_until_utc: str

    def is_fresh(self, *, now_epoch: float) -> bool:
        try:
            ttl_epoch = _iso_to_epoch(self.ttl_until_utc)
        except ValueError:
            return False
        return now_epoch < ttl_epoch


@dataclass
class _CacheFile:
    """Whole-file shape for one provider's cache."""

    schema_version: str = SCHEMA_VERSION
    provider: str = ""
    last_probe_ts_utc: str = ""
    ttl_seconds: int = DEFAULT_TTL_SECONDS
    runtime: str = RUNTIME
    models_probed: dict[str, dict[str, Any]] = field(default_factory=dict)


# =============================================================================
# Internals — utilities
# =============================================================================


def _now_iso() -> str:
    """ISO-8601 UTC with microsecond precision (matches audit envelope)."""
    return time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime()) + f".{int((time.time() % 1) * 1_000_000):06d}Z"


def _iso_to_epoch(iso: str) -> float:
    """Parse ISO-8601 UTC -> epoch seconds. Tolerates microseconds + Z suffix."""
    if iso.endswith("Z"):
        iso = iso[:-1]
    if "." in iso:
        base, frac = iso.split(".", 1)
        if len(frac) > 6:
            frac = frac[:6]
        struct = time.strptime(base, "%Y-%m-%dT%H:%M:%S")
        return time.mktime((*struct[:6], 0, 0, 0)) - time.timezone + (int(frac.ljust(6, "0")) / 1_000_000)
    struct = time.strptime(iso, "%Y-%m-%dT%H:%M:%S")
    return time.mktime((*struct[:6], 0, 0, 0)) - time.timezone


def _project_root() -> Path:
    cwd = Path.cwd().resolve()
    for parent in [cwd, *cwd.parents]:
        if (parent / ".claude").is_dir():
            return parent
    return cwd


def _cache_dir() -> Path:
    """`.run/model-probe-cache/` under the project root. Created mode 0700 if absent."""
    p = _project_root() / ".run" / "model-probe-cache"
    if not p.exists():
        p.mkdir(parents=True, exist_ok=True, mode=0o700)
    else:
        # Tighten if pre-existing with looser mode (defense-in-depth).
        try:
            os.chmod(p, 0o700)
        except OSError:
            pass
    return p


def _cache_path(provider: str) -> Path:
    """Per-runtime, per-provider cache file: `.run/model-probe-cache/python-<provider>.json`."""
    if not provider or "/" in provider or ".." in provider or "\x00" in provider:
        raise ValueError(f"invalid provider name: {provider!r}")
    return _cache_dir() / f"{RUNTIME}-{provider}.json"


def _lock_path(cache_path: Path) -> Path:
    return cache_path.with_suffix(cache_path.suffix + ".lock")


def _pid_alive(pid: int) -> bool:
    if pid <= 0:
        return False
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        # Another user owns the pid; conservatively assume alive.
        return True
    return True


# =============================================================================
# Internals — locking
# =============================================================================


class _ProbeFlock:
    """Context manager for a per-provider flock with stale-lock recovery.

    Acquires LOCK_EX on `<cache_path>.lock`. Waits up to LOCK_WAIT_SECONDS;
    on timeout, inspects the holder PID written into the lockfile and:
      - if the PID is alive: raises TimeoutError
      - if the PID is dead: force-acquires (writes our PID, emits WARN)
    """

    def __init__(self, cache_path: Path) -> None:
        self.cache_path = cache_path
        self.lock_path = _lock_path(cache_path)
        self.fd: Optional[int] = None
        self.recovered_stale = False

    def __enter__(self) -> "_ProbeFlock":
        # O_NOFOLLOW defends against symlink swaps on the lockfile path.
        flags = os.O_RDWR | os.O_CREAT
        if hasattr(os, "O_NOFOLLOW"):
            flags |= os.O_NOFOLLOW
        self.fd = os.open(self.lock_path, flags, 0o600)
        deadline = time.monotonic() + LOCK_WAIT_SECONDS
        last_err: Optional[Exception] = None
        while True:
            try:
                fcntl.flock(self.fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                # Acquired. Write our PID for future stale-lock detection.
                os.lseek(self.fd, 0, os.SEEK_SET)
                os.ftruncate(self.fd, 0)
                os.write(self.fd, f"{os.getpid()}\n".encode("ascii"))
                return self
            except OSError as e:
                last_err = e
                if e.errno not in (errno.EWOULDBLOCK, errno.EAGAIN):
                    raise
                if time.monotonic() >= deadline:
                    break
                time.sleep(0.05)
        # Timeout. Inspect holder PID.
        try:
            os.lseek(self.fd, 0, os.SEEK_SET)
            existing = os.read(self.fd, 64).decode("ascii", errors="replace").strip()
            holder_pid = int(existing.split()[0]) if existing else 0
        except (OSError, ValueError):
            holder_pid = 0
        if holder_pid and _pid_alive(holder_pid):
            os.close(self.fd)
            self.fd = None
            raise TimeoutError(
                f"could not acquire {self.lock_path} within {LOCK_WAIT_SECONDS}s "
                f"(held by live PID {holder_pid})"
            ) from last_err
        # Holder is dead — force-acquire.
        sys.stderr.write(
            f"[model-probe-cache] STALE_LOCK_RECOVERED at {self.lock_path} "
            f"(dead holder PID {holder_pid or 'unknown'})\n"
        )
        # Block on flock now; the dead holder's lock should release immediately
        # because the kernel auto-released on process exit.
        fcntl.flock(self.fd, fcntl.LOCK_EX)
        os.lseek(self.fd, 0, os.SEEK_SET)
        os.ftruncate(self.fd, 0)
        os.write(self.fd, f"{os.getpid()}\n".encode("ascii"))
        self.recovered_stale = True
        return self

    def __exit__(self, *exc: Any) -> None:
        if self.fd is not None:
            try:
                fcntl.flock(self.fd, fcntl.LOCK_UN)
            finally:
                os.close(self.fd)
                self.fd = None


# =============================================================================
# Internals — cache I/O
# =============================================================================


def _load_cache(cache_path: Path) -> _CacheFile:
    if not cache_path.is_file():
        return _CacheFile(provider=cache_path.stem.split("-", 1)[1] if "-" in cache_path.stem else "")
    try:
        with cache_path.open("r", encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, json.JSONDecodeError):
        # Corrupted cache — drop to empty (audit-emit at higher layer if desired).
        return _CacheFile(provider=cache_path.stem.split("-", 1)[1] if "-" in cache_path.stem else "")
    return _CacheFile(
        schema_version=data.get("schema_version", SCHEMA_VERSION),
        provider=data.get("provider", ""),
        last_probe_ts_utc=data.get("last_probe_ts_utc", ""),
        ttl_seconds=int(data.get("ttl_seconds", DEFAULT_TTL_SECONDS)),
        runtime=data.get("runtime", RUNTIME),
        models_probed=dict(data.get("models_probed") or {}),
    )


def _store_cache(cache_path: Path, cache: _CacheFile) -> None:
    """Atomic write: tempfile in same dir + os.rename. Mode 0600."""
    payload = {
        "schema_version": cache.schema_version,
        "provider": cache.provider,
        "last_probe_ts_utc": cache.last_probe_ts_utc,
        "ttl_seconds": cache.ttl_seconds,
        "runtime": cache.runtime,
        "models_probed": cache.models_probed,
    }
    fd, tmp = tempfile.mkstemp(prefix=f".{cache_path.name}.", dir=str(cache_path.parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(payload, f, indent=2, sort_keys=True)
            f.write("\n")
        os.chmod(tmp, 0o600)
        os.rename(tmp, cache_path)
    except Exception:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


# =============================================================================
# Default probe_fn — minimal HTTP HEAD against a generic endpoint
# =============================================================================


def _default_probe_fn(provider: str, model: str, *, timeout_seconds: float) -> tuple[str, int, Optional[str]]:
    """Stdlib-only default probe.

    Returns (outcome, latency_ms, error_class). Treats DNS/connect as the
    only signals — does not attempt actual API auth. For higher-fidelity
    probes (1-token completion against the real endpoint family), the
    caller should pass their own probe_fn.

    This default exists so the library's contract surface is exercisable
    without provider auth wired up.
    """
    target = {
        "openai": ("api.openai.com", 443),
        "anthropic": ("api.anthropic.com", 443),
        "google": ("generativelanguage.googleapis.com", 443),
        "bedrock": ("bedrock-runtime.us-east-1.amazonaws.com", 443),
    }.get(provider)
    if not target:
        return ("FAIL", 0, "ROUTING_MISS")
    host, port = target
    start = time.monotonic()
    try:
        with socket.create_connection((host, port), timeout=timeout_seconds):
            pass
    except socket.timeout:
        latency = int((time.monotonic() - start) * 1000)
        return ("FAIL", latency, "TIMEOUT")
    except OSError as e:
        latency = int((time.monotonic() - start) * 1000)
        return ("FAIL", latency, "PROVIDER_OUTAGE")
    latency = int((time.monotonic() - start) * 1000)
    if latency >= DEGRADED_LATENCY_MS:
        return ("DEGRADED", latency, ERROR_CLASS_PROBE_DEGRADED)
    return ("AVAILABLE", latency, None)


# =============================================================================
# Public API
# =============================================================================


def detect_local_network(
    *,
    host: str = DEFAULT_LOCAL_NETWORK_HOST,
    port: int = DEFAULT_LOCAL_NETWORK_PORT,
    timeout: float = DEFAULT_LOCAL_NETWORK_TIMEOUT,
) -> bool:
    """Return True iff the runner can reach the wider internet.

    Default: TCP-connect to 1.1.1.1:53 (Cloudflare DNS port — almost
    always unblocked). Override host/port/timeout via env vars
    LOA_PROBE_REACHABILITY_HOST / _PORT / _TIMEOUT in production.

    Returns True on connect; False on any error. <200ms typical.
    """
    host = os.environ.get("LOA_PROBE_REACHABILITY_HOST", host)
    try:
        port = int(os.environ.get("LOA_PROBE_REACHABILITY_PORT", port))
    except ValueError:
        port = DEFAULT_LOCAL_NETWORK_PORT
    try:
        timeout = float(os.environ.get("LOA_PROBE_REACHABILITY_TIMEOUT", timeout))
    except ValueError:
        timeout = DEFAULT_LOCAL_NETWORK_TIMEOUT
    try:
        with socket.create_connection((host, port), timeout=timeout):
            pass
    except (socket.timeout, OSError):
        return False
    return True


def invalidate_provider(provider: str) -> bool:
    """Wipe this runtime's cache for `provider`. Returns True if a file was removed."""
    cache_path = _cache_path(provider)
    try:
        with _ProbeFlock(cache_path):
            if cache_path.is_file():
                cache_path.unlink()
                return True
    except FileNotFoundError:
        return False
    return False


def probe_provider(
    provider: str,
    model: str,
    *,
    ttl_seconds: int = DEFAULT_TTL_SECONDS,
    timeout_seconds: float = DEFAULT_TIMEOUT_SECONDS,
    probe_fn: Optional[Callable[..., tuple[str, int, Optional[str]]]] = None,
    swr_threadpool: Optional[Callable[[Callable[[], None]], None]] = None,
    skip_local_network_check: bool = False,
) -> ProbeResult:
    """Cache-gated probe.

    Returns ProbeResult.cached=True iff served from cache (no fresh probe).
    On TTL expiry with a cached entry present, returns cached + fires a
    background refresh thread (stale-while-revalidate, HC3).

    On detect_local_network()=False, returns FAIL with error_class=
    LOCAL_NETWORK_FAILURE without ever calling probe_fn (HC2, B2).
    """
    # (HC2) Local-network preflight. Caller can suppress for tests.
    if not skip_local_network_check and not detect_local_network():
        return ProbeResult(
            provider=provider,
            model=model,
            outcome="FAIL",
            latency_ms=0,
            error_class=ERROR_CLASS_LOCAL_NETWORK,
            ts_utc=_now_iso(),
            cached=False,
        )

    cache_path = _cache_path(provider)
    fn = probe_fn or _default_probe_fn

    # We capture the stale-revalidate signal inside the flock context but
    # FIRE the launcher OUTSIDE the context. Synchronous launchers (used in
    # tests) re-enter probe_provider / _probe_and_store, which acquire the
    # same flock — holding it across the launcher call would deadlock.
    fire_swr = False
    stale_response: Optional[ProbeResult] = None

    with _ProbeFlock(cache_path):
        cache = _load_cache(cache_path)
        cache.provider = provider
        cache.runtime = RUNTIME
        cache.ttl_seconds = ttl_seconds
        now = time.time()
        existing_raw = cache.models_probed.get(model)

        if existing_raw:
            entry = _CacheEntry(
                outcome=existing_raw.get("outcome", "FAIL"),
                latency_ms=int(existing_raw.get("latency_ms", 0)),
                error_class=existing_raw.get("error_class"),
                ts_utc=existing_raw.get("ts_utc", ""),
                ttl_until_utc=existing_raw.get("ttl_until_utc", ""),
            )
            if entry.is_fresh(now_epoch=now):
                # Cache hit, fresh.
                return ProbeResult(
                    provider=provider,
                    model=model,
                    outcome=entry.outcome,
                    latency_ms=entry.latency_ms,
                    error_class=entry.error_class,
                    ts_utc=entry.ts_utc,
                    cached=True,
                )
            # Cache exists but stale -> stale-while-revalidate.
            fire_swr = True
            stale_response = ProbeResult(
                provider=provider,
                model=model,
                outcome=entry.outcome,
                latency_ms=entry.latency_ms,
                error_class=entry.error_class,
                ts_utc=entry.ts_utc,
                cached=True,
            )

    if fire_swr and stale_response is not None:
        launcher = swr_threadpool or _default_swr_launcher
        launcher(
            lambda: _swr_refresh(
                provider=provider,
                model=model,
                ttl_seconds=ttl_seconds,
                timeout_seconds=timeout_seconds,
                probe_fn=fn,
            )
        )
        return stale_response

    # Cache miss: probe synchronously. Released the lock to avoid holding
    # it across a network call (longest hold should be <100us; the actual
    # probe is up to timeout_seconds long).
    return _probe_and_store(
        provider=provider,
        model=model,
        ttl_seconds=ttl_seconds,
        timeout_seconds=timeout_seconds,
        probe_fn=fn,
        background=False,
    )


def _probe_and_store(
    *,
    provider: str,
    model: str,
    ttl_seconds: int,
    timeout_seconds: float,
    probe_fn: Callable[..., tuple[str, int, Optional[str]]],
    background: bool,
) -> ProbeResult:
    try:
        outcome, latency_ms, error_class = probe_fn(
            provider, model, timeout_seconds=timeout_seconds
        )
    except Exception:  # noqa: BLE001 — fail-open at probe layer
        outcome = "AVAILABLE"
        latency_ms = 0
        error_class = ERROR_CLASS_PROBE_DEGRADED
        sys.stderr.write(
            f"[model-probe-cache] probe_fn raised; treating as AVAILABLE "
            f"(provider={provider} model={model}): {traceback.format_exc()}"
        )
    ts_utc = _now_iso()
    ttl_until_epoch = time.time() + ttl_seconds
    ttl_until_iso = time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(ttl_until_epoch)) + ".000000Z"
    cache_path = _cache_path(provider)
    with _ProbeFlock(cache_path):
        cache = _load_cache(cache_path)
        cache.provider = provider
        cache.runtime = RUNTIME
        cache.ttl_seconds = ttl_seconds
        cache.last_probe_ts_utc = ts_utc
        cache.models_probed[model] = {
            "outcome": outcome,
            "latency_ms": latency_ms,
            "error_class": error_class,
            "ts_utc": ts_utc,
            "ttl_until_utc": ttl_until_iso,
        }
        _store_cache(cache_path, cache)
    return ProbeResult(
        provider=provider,
        model=model,
        outcome=outcome,
        latency_ms=latency_ms,
        error_class=error_class,
        ts_utc=ts_utc,
        cached=False,
    )


def _swr_refresh(
    *,
    provider: str,
    model: str,
    ttl_seconds: int,
    timeout_seconds: float,
    probe_fn: Callable[..., tuple[str, int, Optional[str]]],
) -> None:
    try:
        _probe_and_store(
            provider=provider,
            model=model,
            ttl_seconds=ttl_seconds,
            timeout_seconds=timeout_seconds,
            probe_fn=probe_fn,
            background=True,
        )
    except Exception:  # noqa: BLE001 — background, must not raise
        sys.stderr.write(
            f"[model-probe-cache] background refresh failed silently: "
            f"{traceback.format_exc()}"
        )


def _default_swr_launcher(callback: Callable[[], None]) -> None:
    threading.Thread(target=callback, daemon=True).start()


# =============================================================================
# CLI
# =============================================================================


def _cli_probe(args: argparse.Namespace) -> int:
    result = probe_provider(
        args.provider,
        args.model,
        ttl_seconds=args.ttl,
        timeout_seconds=args.timeout,
        skip_local_network_check=args.skip_local_network_check,
    )
    print(json.dumps(result.to_dict(), indent=2 if not args.compact else None))
    return 0 if result.outcome == "AVAILABLE" else (1 if result.outcome == "FAIL" else 0)


def _cli_invalidate(args: argparse.Namespace) -> int:
    removed = invalidate_provider(args.provider)
    print(json.dumps({"provider": args.provider, "removed": removed}))
    return 0


def _cli_detect(args: argparse.Namespace) -> int:
    ok = detect_local_network(host=args.host, port=args.port, timeout=args.timeout)
    print(json.dumps({"reachable": ok}))
    return 0 if ok else 1


def main(argv: Optional[list[str]] = None) -> int:
    parser = argparse.ArgumentParser(prog="model-probe-cache")
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_probe = sub.add_parser("probe", help="probe a (provider, model) pair")
    p_probe.add_argument("--provider", required=True)
    p_probe.add_argument("--model", required=True)
    p_probe.add_argument("--ttl", type=int, default=DEFAULT_TTL_SECONDS)
    p_probe.add_argument("--timeout", type=float, default=DEFAULT_TIMEOUT_SECONDS)
    p_probe.add_argument("--skip-local-network-check", action="store_true")
    p_probe.add_argument("--compact", action="store_true")
    p_probe.set_defaults(fn=_cli_probe)

    p_inv = sub.add_parser("invalidate", help="wipe this runtime's cache for a provider")
    p_inv.add_argument("--provider", required=True)
    p_inv.set_defaults(fn=_cli_invalidate)

    p_det = sub.add_parser("detect-local-network", help="check internet reachability")
    p_det.add_argument("--host", default=DEFAULT_LOCAL_NETWORK_HOST)
    p_det.add_argument("--port", type=int, default=DEFAULT_LOCAL_NETWORK_PORT)
    p_det.add_argument("--timeout", type=float, default=DEFAULT_LOCAL_NETWORK_TIMEOUT)
    p_det.set_defaults(fn=_cli_detect)

    args = parser.parse_args(argv)
    return args.fn(args)


__all__ = [
    "ProbeResult",
    "probe_provider",
    "invalidate_provider",
    "detect_local_network",
    "SCHEMA_VERSION",
    "RUNTIME",
    "DEFAULT_TTL_SECONDS",
    "DEFAULT_TIMEOUT_SECONDS",
    "ERROR_CLASS_LOCAL_NETWORK",
    "ERROR_CLASS_PROBE_DEGRADED",
]


if __name__ == "__main__":
    sys.exit(main())
