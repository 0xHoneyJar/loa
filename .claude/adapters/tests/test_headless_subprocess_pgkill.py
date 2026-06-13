"""Tests for run_subprocess_pgkill — process-group kill on headless completion path.

Issue #982 / sprint-bug-196: the three headless completion adapters used
subprocess.run(timeout=...) which, on timeout, kills only the immediate child.
The agentic CLI's grandchildren survive as orphans AND hold the stdout/stderr
pipe write-ends — so subprocess.run's post-kill communicate() drain blocks
until every grandchild exits (the observed unbounded multi-minute hang with
no fallback-chain advance).

Failing-first proof (current code): the three adapter integration tests below
bound wall-clock at well under the fake grandchild's lifetime; with
subprocess.run the call returns only when the grandchild dies (~15s), and the
grandchild outlives the timeout. Post-fix both assertions hold: return within
timeout + epsilon, grandchild process-group-killed.

All tests are POSIX-only (process groups), hermetic (fake bash CLIs, no
network), and clean up any spawned PIDs even on assertion failure.
"""

from __future__ import annotations

import os
import signal
import subprocess
import sys
import time
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

pytestmark = pytest.mark.skipif(os.name != "posix", reason="process groups are POSIX-only")

from loa_cheval.types import (
    CompletionRequest,
    ModelConfig,
    ProviderConfig,
    ProviderUnavailableError,
)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Fake grandchild lifetime. Must be far above the 1.5s test timeout so a
# surviving grandchild is unambiguous, and far below the suite's patience.
GRANDCHILD_SLEEP = 15


def _write_cli(tmp_path: Path, name: str, body: str) -> str:
    script = tmp_path / name
    script.write_text("#!/usr/bin/env bash\n" + body)
    script.chmod(0o755)
    return str(script)


def _hang_cli(tmp_path: Path) -> str:
    """Spawn a backgrounded grandchild (pipes inherited), record its PID, hang."""
    return _write_cli(
        tmp_path,
        "fake-hanging-cli",
        f"sleep {GRANDCHILD_SLEEP} &\n"
        'echo $! > "$PGKILL_TEST_PIDFILE"\n'
        f"exec sleep {GRANDCHILD_SLEEP}\n",
    )


def _pid_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    return True


def _read_pidfile(path: Path, timeout: float = 5.0) -> int:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if path.exists():
            content = path.read_text().strip()
            if content:
                return int(content)
        time.sleep(0.05)
    raise AssertionError(f"pidfile {path} never written — fake CLI did not start")


def _wait_dead(pid: int, timeout: float = 8.0) -> bool:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if not _pid_alive(pid):
            return True
        time.sleep(0.1)
    return False


@pytest.fixture
def reaper():
    """Kill any registered leftover PIDs so a failing test never leaks sleeps."""
    pids: list = []
    yield pids
    for pid in pids:
        try:
            os.kill(pid, signal.SIGKILL)
        except (ProcessLookupError, PermissionError):
            pass


def _import_helper():
    from loa_cheval.providers.base import run_subprocess_pgkill

    return run_subprocess_pgkill


# ---------------------------------------------------------------------------
# Helper-level: orphan reaping + prompt return on timeout
# ---------------------------------------------------------------------------


class TestOrphanReaping:
    def test_timeout_kills_grandchild_and_returns_promptly(self, tmp_path, reaper):
        run_subprocess_pgkill = _import_helper()
        cli = _hang_cli(tmp_path)
        pidfile = tmp_path / "grandchild.pid"
        env = dict(os.environ, PGKILL_TEST_PIDFILE=str(pidfile))

        start = time.monotonic()
        with pytest.raises(subprocess.TimeoutExpired):
            run_subprocess_pgkill([cli], timeout=1.5, env=env)
        elapsed = time.monotonic() - start

        grandchild = _read_pidfile(pidfile)
        reaper.append(grandchild)
        assert elapsed < 6.0, (
            f"helper took {elapsed:.1f}s — blocked on orphaned grandchild "
            f"instead of process-group kill at the 1.5s deadline"
        )
        assert _wait_dead(grandchild), (
            f"grandchild {grandchild} survived the timeout — process group "
            f"was not killed (the #982 orphan bug)"
        )


# ---------------------------------------------------------------------------
# Helper-level: subprocess.run contract parity
# ---------------------------------------------------------------------------


class TestRunContractParity:
    def test_success_returns_completed_process(self, tmp_path):
        run_subprocess_pgkill = _import_helper()
        cli = _write_cli(tmp_path, "ok-cli", "echo out-line\necho err-line >&2\nexit 0\n")
        proc = run_subprocess_pgkill([cli], timeout=10, env=dict(os.environ))
        assert isinstance(proc, subprocess.CompletedProcess)
        assert proc.returncode == 0
        assert proc.stdout == "out-line\n"
        assert proc.stderr == "err-line\n"
        assert proc.args == [cli]

    def test_nonzero_exit_code_preserved(self, tmp_path):
        run_subprocess_pgkill = _import_helper()
        cli = _write_cli(tmp_path, "fail-cli", "echo boom >&2\nexit 42\n")
        proc = run_subprocess_pgkill([cli], timeout=10, env=dict(os.environ))
        assert proc.returncode == 42
        assert "boom" in proc.stderr

    def test_missing_binary_raises_file_not_found(self):
        run_subprocess_pgkill = _import_helper()
        with pytest.raises(FileNotFoundError):
            run_subprocess_pgkill(
                ["/nonexistent/loa-pgkill-test-bin"], timeout=5, env=dict(os.environ)
            )

    def test_large_input_no_deadlock(self, tmp_path):
        # 2 MiB through `cat` exceeds the ~64 KiB pipe buffer: a naive
        # write-all-then-read implementation deadlocks. The stdin writer
        # thread must keep the read loop draining.
        run_subprocess_pgkill = _import_helper()
        cli = _write_cli(tmp_path, "cat-cli", "exec cat\n")
        payload = "x" * (2 * 1024 * 1024)
        proc = run_subprocess_pgkill(
            [cli], input=payload, timeout=30, env=dict(os.environ)
        )
        assert proc.returncode == 0
        assert proc.stdout == payload

    def test_env_passed_through_untouched(self, tmp_path):
        run_subprocess_pgkill = _import_helper()
        cli = _write_cli(tmp_path, "env-cli", 'echo "marker=$PGKILL_TEST_MARKER"\n')
        env = dict(os.environ, PGKILL_TEST_MARKER="sprint-bug-196")
        proc = run_subprocess_pgkill([cli], timeout=10, env=env)
        assert "marker=sprint-bug-196" in proc.stdout


# ---------------------------------------------------------------------------
# Helper-level: byte-capped streaming read (never communicate())
# ---------------------------------------------------------------------------


class TestByteCap:
    def test_flood_above_cap_raises_not_truncated_success(self, tmp_path):
        # Iter-1 B2 (cross-model BLOCKING): a capped-but-successful return let
        # a truncated JSONL prefix parse as a valid, silently incomplete model
        # answer. Exceeding the cap must raise after the group is killed.
        from loa_cheval.providers.base import SubprocessOutputCapExceeded

        run_subprocess_pgkill = _import_helper()
        cli = _write_cli(
            tmp_path,
            "flood-cli",
            "head -c 1048576 /dev/zero | tr '\\0' 'x'\nexit 0\n",
        )
        with pytest.raises(SubprocessOutputCapExceeded, match="stdout exceeded"):
            run_subprocess_pgkill(
                [cli], timeout=15, env=dict(os.environ), max_bytes=1024
            )

    def test_output_below_cap_unaffected(self, tmp_path):
        run_subprocess_pgkill = _import_helper()
        cli = _write_cli(tmp_path, "small-cli", "printf 'abc'\nexit 0\n")
        proc = run_subprocess_pgkill(
            [cli], timeout=15, env=dict(os.environ), max_bytes=1024
        )
        assert proc.returncode == 0
        assert proc.stdout == "abc"

    def test_adapters_convert_cap_exceeded_to_provider_unavailable(
        self, monkeypatch
    ):
        # Iter-1 B2 wiring: the chain-walk advances only on
        # ProviderUnavailableError — each adapter must convert.
        import importlib

        from loa_cheval.providers.base import SubprocessOutputCapExceeded

        for module_path, class_name, ptype, model, _ in [
            p.values for p in ADAPTER_CASES
        ]:
            module = importlib.import_module(module_path)
            adapter_cls = getattr(module, class_name)

            def _boom(*args, **kwargs):
                raise SubprocessOutputCapExceeded("stdout exceeded the 1-byte cap")

            monkeypatch.setattr(module, "run_subprocess_pgkill", _boom)
            adapter = adapter_cls(_provider_config(ptype, ptype, model))
            with pytest.raises(ProviderUnavailableError, match="exceeded"):
                adapter.complete(_request(model))


class TestStdinWriterRaces:
    def test_writer_swallows_closed_file_valueerror(self):
        # Iter-1 item 3: the finally block closes proc.stdin while the daemon
        # writer may be mid-write — ValueError("I/O operation on closed
        # file") must not escape as an unhandled daemon-thread traceback.
        from types import SimpleNamespace

        from loa_cheval.providers.base import _pgkill_stdin_writer

        class ClosedStdin:
            def write(self, data):
                raise ValueError("I/O operation on closed file")

            def close(self):
                raise ValueError("I/O operation on closed file")

        _pgkill_stdin_writer(SimpleNamespace(stdin=ClosedStdin()), "payload")


# ---------------------------------------------------------------------------
# Helper-level: setup-window hardening
# ---------------------------------------------------------------------------


class TestSetupWindowTeardown:
    def test_exception_before_read_loop_still_kills_group(
        self, tmp_path, reaper, monkeypatch
    ):
        # Any exception between Popen and the read loop must route through
        # the process-group kill — otherwise the just-spawned CLI is orphaned.
        run_subprocess_pgkill = _import_helper()
        import loa_cheval.providers.base as base_mod

        def _boom(*args, **kwargs):
            time.sleep(0.7)  # let the fake CLI spawn its grandchild first
            raise RuntimeError("injected setup failure")

        monkeypatch.setattr(base_mod, "_pgkill_capture", _boom)

        cli = _hang_cli(tmp_path)
        pidfile = tmp_path / "grandchild.pid"
        env = dict(os.environ, PGKILL_TEST_PIDFILE=str(pidfile))

        with pytest.raises(RuntimeError, match="injected setup failure"):
            run_subprocess_pgkill([cli], timeout=10, env=env)

        grandchild = _read_pidfile(pidfile)
        reaper.append(grandchild)
        assert _wait_dead(grandchild), (
            f"grandchild {grandchild} survived a setup-window exception — "
            f"teardown must kill the process group on every exit path"
        )


# ---------------------------------------------------------------------------
# Adapter integration ×3 — the failing-first proof against current code
# ---------------------------------------------------------------------------


def _provider_config(name: str, ptype: str, model: str) -> ProviderConfig:
    return ProviderConfig(
        name=name,
        type=ptype,
        endpoint="",
        auth="",
        connect_timeout=10.0,
        read_timeout=600.0,
        models={model: ModelConfig(context_window=200000)},
    )


def _request(model: str) -> CompletionRequest:
    return CompletionRequest(
        messages=[{"role": "user", "content": "hi"}],
        model=model,
        max_tokens=64,
    )


ADAPTER_CASES = [
    pytest.param(
        "loa_cheval.providers.codex_headless_adapter",
        "CodexHeadlessAdapter",
        "codex-headless",
        "gpt-5.5",
        "CODEX_HEADLESS_BIN",
        id="codex",
    ),
    pytest.param(
        "loa_cheval.providers.gemini_headless_adapter",
        "GeminiHeadlessAdapter",
        "gemini-headless",
        "gemini-3.1-pro",
        "GEMINI_HEADLESS_BIN",
        id="gemini",
    ),
    pytest.param(
        "loa_cheval.providers.claude_headless_adapter",
        "ClaudeHeadlessAdapter",
        "claude-headless",
        "claude-opus-4-7",
        "CLAUDE_HEADLESS_BIN",
        id="claude",
    ),
]


class TestAdapterTimeoutReapsTree:
    @pytest.mark.parametrize(
        "module_path, class_name, ptype, model, bin_env_var", ADAPTER_CASES
    )
    def test_timeout_converts_and_reaps_grandchild(
        self, tmp_path, reaper, monkeypatch, module_path, class_name, ptype, model, bin_env_var
    ):
        import importlib

        module = importlib.import_module(module_path)
        adapter_cls = getattr(module, class_name)

        cli = _hang_cli(tmp_path)
        pidfile = tmp_path / "grandchild.pid"
        monkeypatch.setenv(bin_env_var, cli)
        # The fake CLI reads the pidfile path from env; adapters build the
        # subprocess env from os.environ (auth vars stripped, rest passes).
        monkeypatch.setenv("PGKILL_TEST_PIDFILE", str(pidfile))
        monkeypatch.setattr(adapter_cls, "_compute_timeout", lambda self: 1.5)

        adapter = adapter_cls(_provider_config(ptype, ptype, model))

        start = time.monotonic()
        with pytest.raises(ProviderUnavailableError, match="timed out"):
            adapter.complete(_request(model))
        elapsed = time.monotonic() - start

        grandchild = _read_pidfile(pidfile)
        reaper.append(grandchild)
        assert elapsed < 8.0, (
            f"{ptype} completion took {elapsed:.1f}s for a 1.5s timeout — "
            f"subprocess.run blocked draining pipes held by the orphaned "
            f"grandchild (the #982 unbounded-hang / no-fallthrough bug)"
        )
        assert _wait_dead(grandchild), (
            f"{ptype}: grandchild {grandchild} survived the timeout — "
            f"process tree not killed (the #982 orphan bug)"
        )


# ---------------------------------------------------------------------------
# sprint-bug-201 (#1011): three deltas salvaged from PR #983 (@notzerker)
# ---------------------------------------------------------------------------


class TestSalvagedDeltas:
    def test_lone_surrogate_input_raises_fast_and_reaps_child(self, tmp_path, reaper):
        # Pre-fix: encode happened inside the daemon writer and
        # UnicodeEncodeError (a ValueError subclass) was swallowed — stdin
        # never closed, a stdin-reading CLI waited for EOF, and the call
        # burned the FULL timeout with a misleading TimeoutExpired.
        run_subprocess_pgkill = _import_helper()
        cli = _write_cli(
            tmp_path, "stdin-cli",
            'echo $$ > "$PGKILL_TEST_PIDFILE"\nexec cat\n',
        )
        pidfile = tmp_path / "child.pid"
        env = dict(os.environ, PGKILL_TEST_PIDFILE=str(pidfile))

        start = time.monotonic()
        with pytest.raises(UnicodeEncodeError):
            run_subprocess_pgkill(
                [cli], input="x\ud800y", timeout=10, env=env
            )
        elapsed = time.monotonic() - start

        assert elapsed < 3.0, (
            f"took {elapsed:.1f}s — encode error was swallowed in the "
            f"writer thread and the call burned toward the 10s timeout"
        )
        # The teardown usually SIGKILLs the child before bash even writes
        # the pidfile — an absent pidfile after a short grace IS proof of
        # prompt reaping. If it did get written, the child must be dead.
        deadline = time.monotonic() + 1.0
        while time.monotonic() < deadline and not pidfile.exists():
            time.sleep(0.05)
        content = pidfile.read_text().strip() if pidfile.exists() else ""
        if content:
            child = int(content)
            reaper.append(child)
            assert _wait_dead(child), (
                f"child {child} survived the encode failure — setup-window "
                f"teardown must reap on every exit path"
            )

    def test_killpg_eperm_falls_back_to_proc_kill(self, tmp_path, reaper, monkeypatch):
        # Pre-fix: PermissionError from os.killpg replaced the in-flight
        # TimeoutExpired with an exception no adapter branch handles.
        import loa_cheval.providers.base as base_mod

        run_subprocess_pgkill = _import_helper()

        def _eperm(pgid, sig):
            raise PermissionError("simulated EPERM (setuid descendant)")

        monkeypatch.setattr(base_mod.os, "killpg", _eperm)

        cli = _write_cli(
            tmp_path, "hang-cli",
            'echo $$ > "$PGKILL_TEST_PIDFILE"\nexec sleep 15\n',
        )
        pidfile = tmp_path / "child.pid"
        env = dict(os.environ, PGKILL_TEST_PIDFILE=str(pidfile))

        with pytest.raises(subprocess.TimeoutExpired):
            run_subprocess_pgkill([cli], timeout=1.0, env=env)

        child = _read_pidfile(pidfile)
        reaper.append(child)
        assert _wait_dead(child), (
            f"child {child} survived — proc.kill() fallback did not fire "
            f"after the killpg EPERM"
        )

    def test_timeout_expired_carries_partial_output(self, tmp_path, reaper):
        # Pre-fix: all TimeoutExpired raises discarded the in-scope buffers;
        # partial stderr often carries the CLI's throttle/error message.
        run_subprocess_pgkill = _import_helper()
        cli = _write_cli(
            tmp_path, "partial-cli",
            'echo "partial-stdout-marker"\n'
            'echo "partial-stderr-marker" >&2\n'
            'echo $$ > "$PGKILL_TEST_PIDFILE"\n'
            "exec sleep 15\n",
        )
        pidfile = tmp_path / "child.pid"
        env = dict(os.environ, PGKILL_TEST_PIDFILE=str(pidfile))

        with pytest.raises(subprocess.TimeoutExpired) as exc_info:
            run_subprocess_pgkill([cli], timeout=1.5, env=env)

        child = _read_pidfile(pidfile)
        reaper.append(child)
        assert exc_info.value.output is not None
        assert b"partial-stdout-marker" in exc_info.value.output
        assert b"partial-stderr-marker" in exc_info.value.stderr


# ---------------------------------------------------------------------------
# sprint-bug-209 (#966 review fix 5): cwd kwarg passthrough.
# The additive cwd kwarg landed with f4c00c19 for the cursor adapter's
# isolated-workspace defense; only an adapter-level mock asserted the kwarg
# was PASSED. These pin the helper-level contract: the child actually runs
# in the requested directory, and omitting cwd inherits the parent's.
# ---------------------------------------------------------------------------


class TestCwdPassthrough:
    def test_cwd_kwarg_child_runs_in_requested_dir(self, tmp_path):
        run_subprocess_pgkill = _import_helper()
        result = run_subprocess_pgkill(
            [sys.executable, "-c", "import os; print(os.getcwd())"],
            timeout=30,
            cwd=str(tmp_path),
        )
        assert result.returncode == 0
        assert Path(result.stdout.strip()).resolve() == tmp_path.resolve()

    def test_cwd_omitted_inherits_parent_dir(self, tmp_path, monkeypatch):
        run_subprocess_pgkill = _import_helper()
        monkeypatch.chdir(tmp_path)
        result = run_subprocess_pgkill(
            [sys.executable, "-c", "import os; print(os.getcwd())"],
            timeout=30,
        )
        assert result.returncode == 0
        assert Path(result.stdout.strip()).resolve() == tmp_path.resolve()
