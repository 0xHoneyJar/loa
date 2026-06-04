"""Tests for run_subprocess_pgkill — the process-group-killing subprocess wrapper.

This is the fix for the headless-completion hang (KF-014): the headless adapters
previously used `subprocess.run(timeout=...)`, whose timeout cleanup SIGKILLs only
the immediate child — orphaning the agentic CLI's grandchildren and presenting as
an unbounded hang with no fallthrough. `run_subprocess_pgkill` runs the child in a
new session (process group), reads with a bounded `select` loop, and on timeout
SIGKILLs the WHOLE group, re-raising `subprocess.TimeoutExpired` so callers convert
it to `ProviderUnavailableError` and the fallback chain advances.

These use real `sh`/`sleep` subprocesses (no mocks) so they prove the actual
process-group semantics. POSIX-only.
"""

from __future__ import annotations

import os
import subprocess
import sys
import time
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from loa_cheval.providers.base import (  # noqa: E402
    build_headless_subprocess_env,
    run_subprocess_pgkill,
)

pytestmark = pytest.mark.skipif(
    os.name != "posix", reason="process-group semantics are POSIX-only"
)


def test_happy_path_parity_with_subprocess_run():
    """returncode / stdout / stderr match subprocess.run(capture_output, text)."""
    r = run_subprocess_pgkill(
        ["sh", "-c", "echo hello; echo oops >&2; exit 3"],
        timeout=5,
        env=dict(os.environ),
    )
    assert isinstance(r, subprocess.CompletedProcess)
    assert r.returncode == 3
    assert r.stdout == "hello\n"
    assert r.stderr == "oops\n"


def test_stdin_input_is_pumped():
    """`input=` is written to the child's stdin (codex passes input=prompt)."""
    r = run_subprocess_pgkill(["cat"], input="PONG-via-stdin", timeout=5, env=dict(os.environ))
    assert r.returncode == 0
    assert r.stdout == "PONG-via-stdin"


def test_timeout_raises_and_kills_whole_process_group(tmp_path):
    """On timeout: raise TimeoutExpired AND kill the orphan grandchild (the fix).

    subprocess.run would SIGKILL only the immediate child, leaving the
    backgrounded grandchild alive. run_subprocess_pgkill killpg's the group.
    """
    pidfile = tmp_path / "grandchild.pid"
    # immediate child backgrounds a grandchild that records its pid then sleeps,
    # and the immediate child also sleeps -> nothing exits before the timeout.
    fake_cli = [
        "sh",
        "-c",
        f'sh -c "echo \\$\\$ > {pidfile}; exec sleep 120" & sleep 120',
    ]
    start = time.monotonic()
    with pytest.raises(subprocess.TimeoutExpired):
        run_subprocess_pgkill(fake_cli, timeout=2, env=dict(os.environ))
    elapsed = time.monotonic() - start
    assert elapsed < 8, f"timeout not honored: {elapsed:.1f}s"

    # The grandchild must be dead (process-group killed), not orphaned.
    time.sleep(0.5)
    assert pidfile.exists(), "grandchild never recorded its pid"
    gc_pid = int(pidfile.read_text().strip())
    with pytest.raises(ProcessLookupError):
        os.kill(gc_pid, 0)  # raises ProcessLookupError iff the process is gone


def test_setup_failure_does_not_orphan_the_child(tmp_path):
    """An exception in the setup window (encode of a lone surrogate) still reaps
    the already-spawned child via the finally->killpg path (no orphan)."""
    pidfile = tmp_path / "child.pid"
    fake_cli = ["sh", "-c", f"echo $$ > {pidfile}; exec sleep 60"]
    with pytest.raises(UnicodeEncodeError):
        run_subprocess_pgkill(fake_cli, input="bad\ud800surrogate", timeout=10, env=dict(os.environ))
    time.sleep(0.4)
    if pidfile.exists():
        child_pid = int(pidfile.read_text().strip())
        with pytest.raises(ProcessLookupError):
            os.kill(child_pid, 0)


def test_env_is_passed_through_and_stripped():
    """The explicit env reaches the child; auth vars are stripped by the helper."""
    parent = dict(os.environ)
    parent["OPENAI_API_KEY"] = "sk-should-be-stripped"
    r = run_subprocess_pgkill(
        ["sh", "-c", "echo ${OPENAI_API_KEY:-STRIPPED}"],
        timeout=5,
        env=build_headless_subprocess_env(parent),
    )
    assert r.stdout.strip() == "STRIPPED"


def test_missing_binary_raises_filenotfound():
    """Same contract as subprocess.run: a missing binary raises FileNotFoundError."""
    with pytest.raises(FileNotFoundError):
        run_subprocess_pgkill(
            ["/nonexistent/loa-pgkill-binary-xyz"], timeout=5, env=dict(os.environ)
        )
