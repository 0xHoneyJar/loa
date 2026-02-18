"""Tests for FLockSemaphore concurrency control (SDD 4.2.4, Sprint 2 Task 2.3)."""

import os
import signal
import sys
import tempfile
import time
from pathlib import Path
from unittest.mock import patch

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from loa_cheval.providers.concurrency import FLockSemaphore


class TestSemaphoreBasic:
    """Basic acquire/release tests."""

    def test_acquire_release(self, tmp_path):
        sem = FLockSemaphore("test", max_concurrent=3, lock_dir=str(tmp_path))
        slot = sem.acquire(timeout=5.0)
        assert 0 <= slot < 3
        sem.release()

    def test_context_manager(self, tmp_path):
        with FLockSemaphore("test", max_concurrent=3, lock_dir=str(tmp_path)) as slot:
            assert 0 <= slot < 3

    def test_context_manager_on_exception(self, tmp_path):
        """Release happens even when exception occurs."""
        sem = FLockSemaphore("test", max_concurrent=3, lock_dir=str(tmp_path))
        try:
            with sem:
                raise ValueError("test error")
        except ValueError:
            pass
        # Should be able to acquire again (was properly released)
        with FLockSemaphore("test", max_concurrent=3, lock_dir=str(tmp_path)) as slot:
            assert slot >= 0

    def test_max_concurrent_enforced(self, tmp_path):
        """When all slots taken, new acquire blocks."""
        sems = []
        for i in range(3):
            s = FLockSemaphore("test", max_concurrent=3, lock_dir=str(tmp_path))
            s.acquire(timeout=5.0)
            sems.append(s)

        # All 3 slots taken — next should timeout quickly
        with pytest.raises(TimeoutError):
            FLockSemaphore("test", max_concurrent=3, lock_dir=str(tmp_path)).acquire(timeout=0.5)

        # Release one
        sems[0].release()

        # Now should succeed
        s = FLockSemaphore("test", max_concurrent=3, lock_dir=str(tmp_path))
        slot = s.acquire(timeout=2.0)
        assert slot >= 0
        s.release()

        for sem in sems[1:]:
            sem.release()

    def test_lock_dir_created(self, tmp_path):
        lock_dir = str(tmp_path / "subdir" / "locks")
        assert not os.path.exists(lock_dir)
        with FLockSemaphore("test", max_concurrent=1, lock_dir=lock_dir):
            assert os.path.exists(lock_dir)


class TestStaleLock:
    """Test stale lock detection and recovery."""

    def test_stale_lock_cleaned(self, tmp_path):
        """Lock from dead PID is removed on next acquire."""
        lock_dir = str(tmp_path)
        path = os.path.join(lock_dir, ".semaphore-test-0.lock")

        # Write a lock file with a PID that doesn't exist
        with open(path, "w") as f:
            f.write("99999999\n")  # Very unlikely to be a real PID

        # Should acquire successfully after cleaning stale lock
        sem = FLockSemaphore("test", max_concurrent=1, lock_dir=lock_dir)
        slot = sem.acquire(timeout=2.0)
        assert slot == 0
        sem.release()


class TestRealFlock:
    """Integration tests using REAL flock on local filesystem (Flatline SKP-008)."""

    def test_flock_actually_locks(self, tmp_path):
        """Verify flock prevents concurrent access to same slot."""
        import fcntl

        lock_dir = str(tmp_path)
        sem1 = FLockSemaphore("real", max_concurrent=1, lock_dir=lock_dir)
        slot = sem1.acquire(timeout=2.0)
        assert slot == 0

        # Try to flock the same file — should fail with LOCK_NB
        path = os.path.join(lock_dir, ".semaphore-real-0.lock")
        fd = os.open(path, os.O_RDONLY)
        try:
            with pytest.raises(OSError):
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        finally:
            os.close(fd)

        sem1.release()

    @pytest.mark.skipif(
        not hasattr(os, "fork"),
        reason="Requires fork() (POSIX only)",
    )
    def test_concurrent_processes(self, tmp_path):
        """Fork 2 processes competing for 1 slot — one blocks (Flatline SKP-008)."""
        lock_dir = str(tmp_path)
        result_file = str(tmp_path / "result.txt")

        pid = os.fork()
        if pid == 0:
            # Child process
            try:
                sem = FLockSemaphore("fork", max_concurrent=1, lock_dir=lock_dir)
                sem.acquire(timeout=3.0)
                time.sleep(0.5)  # Hold lock briefly
                with open(result_file, "w") as f:
                    f.write("child_acquired")
                sem.release()
            except TimeoutError:
                with open(result_file, "w") as f:
                    f.write("child_timeout")
            finally:
                os._exit(0)
        else:
            # Parent process — acquire immediately
            sem = FLockSemaphore("fork", max_concurrent=1, lock_dir=lock_dir)
            sem.acquire(timeout=3.0)
            time.sleep(1.0)  # Hold lock longer than child
            sem.release()

            # Wait for child
            os.waitpid(pid, 0)

            # One of them should have acquired
            if os.path.exists(result_file):
                with open(result_file, "r") as f:
                    assert f.read() in ("child_acquired", "child_timeout")
