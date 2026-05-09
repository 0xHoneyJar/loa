#!/usr/bin/env python3
"""probe-cache-test-driver.py — bats helper for model-probe-cache tests.

The library file `model-probe-cache.py` uses hyphens in its name (per the
existing `validate-model-aliases-extra.py` / `endpoint-validator.py`
convention), which makes direct Python `import` awkward. This driver
imports it via importlib with proper sys.modules registration so unit
tests can drive the public API with mock probe_fn callbacks (no network).

Usage from bats:
    python -I tests/helpers/probe-cache-test-driver.py <scenario> [args]

Exits 0 on success, 1 on assertion failure, 64 on usage error.
Each scenario writes a JSON object to stdout describing the assertion
result so bats can grep / parse / re-emit.
"""

from __future__ import annotations

import importlib.util
import json
import os
import sys
import time
from pathlib import Path


def _import_lib():
    """Import .claude/scripts/lib/model-probe-cache.py with sys.modules pinning.

    Python 3.13 dataclass introspection requires the module be registered in
    sys.modules before exec_module. We resolve the lib path relative to the
    project root (which the test harness sets via cwd).
    """
    here = Path(__file__).resolve()
    repo_root = here.parents[2]  # tests/helpers/ -> tests/ -> repo
    lib_path = repo_root / ".claude" / "scripts" / "lib" / "model-probe-cache.py"
    spec = importlib.util.spec_from_file_location("loa_model_probe_cache", str(lib_path))
    module = importlib.util.module_from_spec(spec)
    sys.modules["loa_model_probe_cache"] = module
    spec.loader.exec_module(module)
    return module


def _setup_temp_project(tmpdir: str) -> None:
    """Make `tmpdir` look like a Loa project root so _project_root() resolves."""
    os.makedirs(os.path.join(tmpdir, ".claude"), exist_ok=True)
    os.chdir(tmpdir)


class _env_snapshot:
    """Restore os.environ on context exit.

    BB iter-1 F5 (medium): scenarios mutate os.environ directly. Safe today
    because each scenario runs in its own subprocess (one-shot CLI), but a
    future refactor to in-process iteration would silently break test
    isolation. This context manager makes the per-process assumption
    explicit and self-documenting; wrap any scenario that touches the env
    with `with _env_snapshot():`.
    """

    def __enter__(self) -> "_env_snapshot":
        self._snapshot = dict(os.environ)
        return self

    def __exit__(self, *exc: object) -> None:
        # Restore additions/modifications and re-add anything that was deleted.
        for k in list(os.environ.keys()):
            if k not in self._snapshot:
                del os.environ[k]
        for k, v in self._snapshot.items():
            if os.environ.get(k) != v:
                os.environ[k] = v


# =============================================================================
# Scenarios (one entry per test)
# =============================================================================


def s_basic_probe_then_cache(tmpdir: str) -> dict:
    _setup_temp_project(tmpdir)
    mpc = _import_lib()
    calls = {"n": 0}

    def fake_fn(provider, model, *, timeout_seconds):
        calls["n"] += 1
        return ("AVAILABLE", 100, None)

    r1 = mpc.probe_provider("openai", "gpt-5.5-pro", probe_fn=fake_fn, skip_local_network_check=True)
    r2 = mpc.probe_provider("openai", "gpt-5.5-pro", probe_fn=fake_fn, skip_local_network_check=True)
    return {
        "first_cached": r1.cached,
        "second_cached": r2.cached,
        "first_outcome": r1.outcome,
        "second_outcome": r2.outcome,
        "probe_fn_calls": calls["n"],
    }


def s_local_network_failure(tmpdir: str) -> dict:
    _setup_temp_project(tmpdir)
    with _env_snapshot():
        mpc = _import_lib()
        # detect_local_network() override via env var to a known-unreachable port
        # (port 1 on 127.0.0.1 — refused/closed).
        os.environ["LOA_PROBE_REACHABILITY_HOST"] = "127.0.0.1"
        os.environ["LOA_PROBE_REACHABILITY_PORT"] = "1"
        os.environ["LOA_PROBE_REACHABILITY_TIMEOUT"] = "0.2"

        def fake_fn(provider, model, *, timeout_seconds):
            # Should NEVER be called when local network preflight fails.
            raise AssertionError("probe_fn must not be called on local-network failure")

        r = mpc.probe_provider("openai", "gpt-5.5-pro", probe_fn=fake_fn)
        return {
            "outcome": r.outcome,
            "error_class": r.error_class,
            "cached": r.cached,
        }


def s_invalidate(tmpdir: str) -> dict:
    _setup_temp_project(tmpdir)
    mpc = _import_lib()

    def fake_fn(provider, model, *, timeout_seconds):
        return ("AVAILABLE", 50, None)

    mpc.probe_provider("openai", "gpt-5.5-pro", probe_fn=fake_fn, skip_local_network_check=True)
    cache_dir = Path(tmpdir) / ".run" / "model-probe-cache"
    files_before = sorted(p.name for p in cache_dir.iterdir() if not p.name.endswith(".lock"))
    removed = mpc.invalidate_provider("openai")
    files_after = sorted(p.name for p in cache_dir.iterdir() if not p.name.endswith(".lock"))
    return {
        "removed": removed,
        "files_before": files_before,
        "files_after": files_after,
    }


def s_probe_fn_raises_fail_open(tmpdir: str) -> dict:
    """When probe_fn raises, library should fail-open (AVAILABLE + WARN)."""
    _setup_temp_project(tmpdir)
    mpc = _import_lib()

    def fake_fn(provider, model, *, timeout_seconds):
        raise RuntimeError("simulated probe-fn failure")

    r = mpc.probe_provider("openai", "gpt-5.5-pro", probe_fn=fake_fn, skip_local_network_check=True)
    return {
        "outcome": r.outcome,
        "error_class": r.error_class,
    }


def s_provider_validation(tmpdir: str) -> dict:
    """Provider name must reject path-traversal attempts."""
    _setup_temp_project(tmpdir)
    mpc = _import_lib()
    results = {}
    for bad in ["../etc", "foo/bar", "x\x00y", ""]:
        try:
            mpc.invalidate_provider(bad)
            results[bad] = "ACCEPTED"  # bad
        except ValueError:
            results[bad] = "REJECTED"
        except Exception as e:
            results[bad] = f"ERR:{type(e).__name__}"
    return results


def s_cache_file_mode(tmpdir: str) -> dict:
    """Cache dir is 0700; file is 0600."""
    _setup_temp_project(tmpdir)
    mpc = _import_lib()

    def fake_fn(provider, model, *, timeout_seconds):
        return ("AVAILABLE", 50, None)

    mpc.probe_provider("openai", "gpt-5.5-pro", probe_fn=fake_fn, skip_local_network_check=True)
    cache_dir = Path(tmpdir) / ".run" / "model-probe-cache"
    cache_file = cache_dir / f"{mpc.RUNTIME}-openai.json"
    return {
        "dir_mode_octal": oct(cache_dir.stat().st_mode & 0o777),
        "file_mode_octal": oct(cache_file.stat().st_mode & 0o777),
    }


def s_runtime_namespacing(tmpdir: str) -> dict:
    """LOA_PROBE_RUNTIME=bash makes cache write to bash-<provider>.json."""
    _setup_temp_project(tmpdir)
    with _env_snapshot():
        os.environ["LOA_PROBE_RUNTIME"] = "bash"
        mpc = _import_lib()
        assert mpc.RUNTIME == "bash"

        def fake_fn(provider, model, *, timeout_seconds):
            return ("AVAILABLE", 50, None)

        mpc.probe_provider("openai", "gpt-5.5-pro", probe_fn=fake_fn, skip_local_network_check=True)
        cache_dir = Path(tmpdir) / ".run" / "model-probe-cache"
        files = sorted(p.name for p in cache_dir.iterdir() if not p.name.endswith(".lock"))
        return {"files": files}


def s_runtime_invalid_falls_back(tmpdir: str) -> dict:
    """LOA_PROBE_RUNTIME=quantum (invalid) falls back to python with stderr WARN."""
    _setup_temp_project(tmpdir)
    with _env_snapshot():
        os.environ["LOA_PROBE_RUNTIME"] = "quantum"
        # Capture stderr by redirecting fd 2 to a pipe before importing.
        import io

        saved = sys.stderr
        buf = io.StringIO()
        sys.stderr = buf
        try:
            mpc = _import_lib()
        finally:
            sys.stderr = saved
        return {
            "runtime": mpc.RUNTIME,
            "stderr_warned": "WARN" in buf.getvalue(),
        }


def s_stale_while_revalidate(tmpdir: str) -> dict:
    """TTL-expired cache returns immediately (cached=True) AND fires a refresh."""
    _setup_temp_project(tmpdir)
    mpc = _import_lib()

    sync_calls = {"n": 0}
    bg_calls = {"n": 0}
    bg_done = {"event": False}

    def fake_fn(provider, model, *, timeout_seconds):
        if bg_done["event"]:  # second call (background)
            bg_calls["n"] += 1
        else:
            sync_calls["n"] += 1
        return ("AVAILABLE", 50, None)

    # Use a tiny TTL so the first probe is immediately stale.
    r1 = mpc.probe_provider(
        "openai",
        "gpt-5.5-pro",
        probe_fn=fake_fn,
        ttl_seconds=0,  # everything is immediately stale
        skip_local_network_check=True,
    )
    bg_done["event"] = True

    # Capture background refresh by using a synchronous launcher.
    refresh_fired = {"flag": False}

    def sync_launcher(callback):
        refresh_fired["flag"] = True
        callback()

    r2 = mpc.probe_provider(
        "openai",
        "gpt-5.5-pro",
        probe_fn=fake_fn,
        ttl_seconds=0,
        swr_threadpool=sync_launcher,
        skip_local_network_check=True,
    )
    return {
        "first_cached": r1.cached,
        "second_cached_immediate": r2.cached,
        "swr_launcher_fired": refresh_fired["flag"],
        "bg_calls": bg_calls["n"],
    }


SCENARIOS = {
    "basic_probe_then_cache": s_basic_probe_then_cache,
    "local_network_failure": s_local_network_failure,
    "invalidate": s_invalidate,
    "probe_fn_raises_fail_open": s_probe_fn_raises_fail_open,
    "provider_validation": s_provider_validation,
    "cache_file_mode": s_cache_file_mode,
    "runtime_namespacing": s_runtime_namespacing,
    "runtime_invalid_falls_back": s_runtime_invalid_falls_back,
    "stale_while_revalidate": s_stale_while_revalidate,
}


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        sys.stderr.write(f"usage: {argv[0]} <scenario> <tmpdir>\n")
        sys.stderr.write(f"scenarios: {', '.join(SCENARIOS)}\n")
        return 64
    scenario = argv[1]
    tmpdir = argv[2]
    fn = SCENARIOS.get(scenario)
    if not fn:
        sys.stderr.write(f"unknown scenario: {scenario}\n")
        return 64
    result = fn(tmpdir)
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except AssertionError as e:
        sys.stderr.write(f"ASSERTION FAILED: {e}\n")
        sys.exit(1)
