"""File-lock based semaphore for concurrent API call limiting (SDD 4.2.4).

Uses POSIX flock(2) advisory locks for cross-process concurrency control.
Each semaphore manages N lock files (slots). A process acquires a slot by
obtaining an exclusive flock on one of the files.

Limitations:
  - Advisory locks only — not enforced by OS, relies on cooperative processes
  - Unsupported on NFS/CIFS (flock is local-only on network filesystems)
  - CI containers must use local tmpfs, not shared volumes
  - Manual unlock: rm .run/.semaphore-{name}-*.lock

Usage:
    with FLockSemaphore("google-standard", max_concurrent=5) as slot:
        # slot is the acquired slot index (0-based)
        result = call_api()
"""

from __future__ import annotations

import fcntl
import logging
import os
import time
from typing import Optional

logger = logging.getLogger("loa_cheval.providers.concurrency")


class FLockSemaphore:
    """File-lock based semaphore for limiting concurrent operations.

    Args:
        name: Semaphore name (used in lock file paths)
        max_concurrent: Maximum number of concurrent holders
        lock_dir: Directory for lock files (default: .run/)
    """

    def __init__(self, name, max_concurrent=5, lock_dir=".run", timeout=30.0):
        # type: (str, int, str, float) -> None
        self.name = name
        self.max_concurrent = max_concurrent
        self.lock_dir = lock_dir
        self.timeout = timeout
        self._held_fd = None  # type: Optional[int]
        self._held_slot = -1
        self._held_path = ""

    def __enter__(self):
        # type: () -> int
        return self.acquire(timeout=self.timeout)

    def __exit__(self, exc_type, exc_val, exc_tb):
        # type: (object, object, object) -> None
        self.release()

    def acquire(self, timeout=30.0):
        # type: (float) -> int
        """Try to acquire a semaphore slot.

        Tries each slot with LOCK_NB. If all occupied, retries with
        backoff until timeout.

        Returns the acquired slot index (0-based).
        Raises TimeoutError if all slots occupied after timeout.
        """
        os.makedirs(self.lock_dir, exist_ok=True)
        start = time.monotonic()
        attempt = 0

        while True:
            for slot in range(self.max_concurrent):
                path = self._slot_path(slot)

                # Check for stale locks
                self._check_stale_lock(path)

                try:
                    fd = os.open(path, os.O_CREAT | os.O_WRONLY, 0o644)
                    try:
                        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    except (IOError, OSError):
                        os.close(fd)
                        continue

                    # Write PID for stale-lock detection
                    os.ftruncate(fd, 0)
                    os.write(fd, ("%d\n" % os.getpid()).encode())

                    self._held_fd = fd
                    self._held_slot = slot
                    self._held_path = path

                    logger.debug(
                        "semaphore_acquired name=%s slot=%d pid=%d",
                        self.name,
                        slot,
                        os.getpid(),
                    )
                    return slot

                except OSError:
                    continue

            # All slots occupied — check timeout
            elapsed = time.monotonic() - start
            if elapsed >= timeout:
                raise TimeoutError(
                    "FLockSemaphore '%s': all %d slots occupied after %.1fs"
                    % (self.name, self.max_concurrent, timeout)
                )

            # Backoff before retry
            attempt += 1
            delay = min(0.1 * (2 ** min(attempt, 5)), 2.0)
            time.sleep(delay)

    def release(self):
        # type: () -> None
        """Release the held semaphore slot."""
        if self._held_fd is not None:
            try:
                fcntl.flock(self._held_fd, fcntl.LOCK_UN)
                os.close(self._held_fd)
            except OSError:
                pass
            logger.debug(
                "semaphore_released name=%s slot=%d pid=%d",
                self.name,
                self._held_slot,
                os.getpid(),
            )
            self._held_fd = None
            self._held_slot = -1
            self._held_path = ""

    def _slot_path(self, slot):
        # type: (int) -> str
        """Get the lock file path for a slot."""
        return os.path.join(
            self.lock_dir,
            ".semaphore-%s-%d.lock" % (self.name, slot),
        )

    def _check_stale_lock(self, path):
        # type: (str) -> None
        """Remove lock file if owning PID no longer exists."""
        if not os.path.exists(path):
            return

        try:
            with open(path, "r") as f:
                pid_str = f.read().strip()
            if not pid_str:
                return
            pid = int(pid_str)
            # Check if process exists
            os.kill(pid, 0)
        except (ValueError, IOError):
            # Can't read PID — leave lock alone
            return
        except OSError:
            # Process doesn't exist — stale lock
            try:
                os.unlink(path)
                logger.warning(
                    "semaphore_stale_lock name=%s path=%s stale_pid=%s",
                    self.name,
                    path,
                    pid_str,
                )
            except OSError:
                pass
