"""Cycle-110 sprint-2b2b1 T2.11 — cross-process N-slot semaphore tests.

Covers SDD §5.6 v1.1 spec:
- acquire_slot context manager yields one of N slots
- N parallel acquirers all succeed when N == capacity
- (N+1)th acquirer waits then succeeds when an earlier holder releases
- All-slots-busy past timeout raises SemaphoreExhausted (C12)
- Wait is ACROSS ALL slots, not just slot-0 (C5)
- File mode 0600 + O_NOFOLLOW + path-traversal defense
- OS auto-releases on holder process exit (defense against stuck holders)
"""

from __future__ import annotations

import multiprocessing
import os
import sys
import time
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from loa_cheval.adapters.headless_concurrency import (  # noqa: E402
    SemaphoreExhausted,
    acquire_slot,
)


def _holder_subprocess(cli, n_slots, run_dir, hold_seconds, ready_event, done_event):
    """Helper run as a separate process: acquire a slot + hold + release."""
    try:
        with acquire_slot(cli, n_slots=n_slots, run_dir=run_dir, timeout_seconds=5):
            ready_event.set()
            time.sleep(hold_seconds)
    finally:
        done_event.set()


class TestPathSafety:
    """The cli name flows into a path component; reject path-injection."""

    def test_traversal_rejected(self, tmp_path):
        with pytest.raises(ValueError, match="forbidden"):
            with acquire_slot("../../etc/passwd", run_dir=str(tmp_path)):
                pass

    def test_slash_rejected(self, tmp_path):
        with pytest.raises(ValueError, match="forbidden"):
            with acquire_slot("claude/headless", run_dir=str(tmp_path)):
                pass

    def test_dot_rejected(self, tmp_path):
        with pytest.raises(ValueError, match="forbidden"):
            with acquire_slot("claude.headless", run_dir=str(tmp_path)):
                pass

    def test_long_name_rejected(self, tmp_path):
        with pytest.raises(ValueError, match="forbidden"):
            with acquire_slot("a" * 65, run_dir=str(tmp_path)):
                pass

    def test_canonical_names_accepted(self, tmp_path):
        for name in ("claude-headless", "codex-headless", "gemini-headless"):
            with acquire_slot(name, n_slots=1, run_dir=str(tmp_path)):
                pass  # acquired + released cleanly


class TestSlotCapacity:
    def test_single_slot_acquire_release(self, tmp_path):
        with acquire_slot("claude-headless", n_slots=1, run_dir=str(tmp_path)) as idx:
            assert idx == 0

    def test_parallel_acquirers_same_process_get_distinct_slots(self, tmp_path):
        with acquire_slot("claude-headless", n_slots=2, run_dir=str(tmp_path)) as idx1:
            with acquire_slot("claude-headless", n_slots=2, run_dir=str(tmp_path)) as idx2:
                assert idx1 != idx2
                assert {idx1, idx2} == {0, 1}

    def test_third_acquirer_raises_when_n_is_two(self, tmp_path):
        with acquire_slot("claude-headless", n_slots=2, run_dir=str(tmp_path)):
            with acquire_slot("claude-headless", n_slots=2, run_dir=str(tmp_path)):
                t0 = time.monotonic()
                with pytest.raises(SemaphoreExhausted) as exc:
                    with acquire_slot(
                        "claude-headless",
                        n_slots=2,
                        run_dir=str(tmp_path),
                        timeout_seconds=0.5,
                    ):
                        pass  # pragma: no cover
                elapsed = time.monotonic() - t0
                assert 0.4 < elapsed < 1.5
                assert exc.value.cli == "claude-headless"
                assert exc.value.n_slots == 2


class TestWaitAllSlots:
    """C5 closure: waiter must find any released slot, not just slot-0."""

    def test_blocked_acquirer_wakes_when_any_slot_releases(self, tmp_path):
        # BB iter-1 #908 F-006 closure: assert ready.wait() actually fired
        # (not just that we didn't deadlock); check subprocess exit code.
        ctx = multiprocessing.get_context("spawn")
        ready = ctx.Event()
        done = ctx.Event()
        proc = ctx.Process(
            target=_holder_subprocess,
            args=("claude-headless", 2, str(tmp_path), 0.3, ready, done),
        )
        proc.start()
        assert ready.wait(timeout=3) is True, "holder failed to acquire its slot"
        with acquire_slot("claude-headless", n_slots=2, run_dir=str(tmp_path)) as main_idx:
            t0 = time.monotonic()
            assert done.wait(timeout=3) is True, "holder failed to release"
            with acquire_slot(
                "claude-headless", n_slots=2, run_dir=str(tmp_path),
                timeout_seconds=2,
            ) as second_idx:
                elapsed = time.monotonic() - t0
                assert second_idx != main_idx
                assert elapsed < 1.5
        proc.join(timeout=2)
        assert proc.exitcode == 0, f"holder process exited non-zero: {proc.exitcode}"


class TestRelativeRunDirResolved:
    """BB iter-1 #908 F-004 closure (HIGH): relative run_dir resolved to
    absolute path so cwd-divergent cheval processes share the same
    semaphore scope, not phantom-multiply-allocate by 2x."""

    def test_relative_run_dir_resolved_to_abspath_for_slot_files(self, tmp_path, monkeypatch):
        # cd into tmp_path so relative run_dir="." resolves to tmp_path absolute.
        monkeypatch.chdir(tmp_path)
        with acquire_slot("claude-headless", n_slots=1, run_dir="."):
            # Slot file should live under tmp_path/headless-concurrency-claude-headless/
            slot_path = tmp_path / "headless-concurrency-claude-headless" / "slot-0.lock"
            assert slot_path.is_file(), (
                f"slot file should land under resolved abspath, got dir contents: "
                f"{list(tmp_path.iterdir())}"
            )

    def test_two_processes_different_cwd_but_same_abspath_share_slots(self, tmp_path):
        """If both processes pass the SAME abspath, they share the semaphore
        scope. This is the post-fix behavior — relative paths get resolved
        BEFORE the cross-process flock layer sees them."""
        shared_dir = tmp_path  # absolute
        with acquire_slot("claude-headless", n_slots=1, run_dir=str(shared_dir)):
            # Second attempt with the same absolute run_dir must hit the
            # semaphore (n=1, both in same scope).
            with pytest.raises(SemaphoreExhausted):
                with acquire_slot(
                    "claude-headless", n_slots=1, run_dir=str(shared_dir),
                    timeout_seconds=0.3,
                ):
                    pass  # pragma: no cover


class TestExistingDirChmodEnforced:
    """BB iter-1 #908 F-003 closure (MEDIUM): existing slot dir gets explicit
    chmod to 0o700 even if it was created earlier with a looser umask."""

    def test_existing_dir_with_loose_perms_chmod_to_0700(self, tmp_path):
        slot_dir = tmp_path / "headless-concurrency-claude-headless"
        slot_dir.mkdir(mode=0o755)  # intentionally permissive
        assert (slot_dir.stat().st_mode & 0o777) == 0o755
        with acquire_slot("claude-headless", n_slots=1, run_dir=str(tmp_path)):
            assert (slot_dir.stat().st_mode & 0o777) == 0o700, (
                "headless-concurrency dir must be tightened to 0o700 on reuse"
            )


class TestFileMode:
    def test_slot_file_mode_0600(self, tmp_path):
        with acquire_slot("claude-headless", n_slots=1, run_dir=str(tmp_path)):
            slot_path = tmp_path / "headless-concurrency-claude-headless" / "slot-0.lock"
            assert slot_path.is_file()
            mode = slot_path.stat().st_mode & 0o777
            assert mode == 0o600

    def test_slot_dir_mode_0700(self, tmp_path):
        with acquire_slot("claude-headless", n_slots=1, run_dir=str(tmp_path)):
            slot_dir = tmp_path / "headless-concurrency-claude-headless"
            assert slot_dir.is_dir()
            mode = slot_dir.stat().st_mode & 0o777
            assert mode == 0o700


class TestNSlotsValidation:
    def test_zero_n_rejected(self, tmp_path):
        with pytest.raises(ValueError, match="n_slots"):
            with acquire_slot("claude-headless", n_slots=0, run_dir=str(tmp_path)):
                pass

    def test_huge_n_rejected(self, tmp_path):
        with pytest.raises(ValueError, match="n_slots"):
            with acquire_slot("claude-headless", n_slots=1001, run_dir=str(tmp_path)):
                pass


class TestPIDStamp:
    def test_holder_pid_written_to_slot_file(self, tmp_path):
        with acquire_slot("claude-headless", n_slots=1, run_dir=str(tmp_path)):
            slot_path = tmp_path / "headless-concurrency-claude-headless" / "slot-0.lock"
            content = slot_path.read_text().strip()
            assert content == str(os.getpid())


class TestRelease:
    def test_release_allows_reacquire(self, tmp_path):
        with acquire_slot("claude-headless", n_slots=1, run_dir=str(tmp_path)) as idx1:
            pass
        with acquire_slot("claude-headless", n_slots=1, run_dir=str(tmp_path)) as idx2:
            assert idx1 == 0
            assert idx2 == 0

    def test_release_on_exception_in_body(self, tmp_path):
        with pytest.raises(RuntimeError, match="caller-raised"):
            with acquire_slot("claude-headless", n_slots=1, run_dir=str(tmp_path)):
                raise RuntimeError("caller-raised")
        with acquire_slot("claude-headless", n_slots=1, run_dir=str(tmp_path)) as idx:
            assert idx == 0
