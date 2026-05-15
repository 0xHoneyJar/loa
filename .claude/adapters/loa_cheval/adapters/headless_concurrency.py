"""Cycle-110 sprint-2b2b1 T2.11 — cross-process N-slot semaphore for headless CLI dispatch.

Caps concurrent CLI invocations at a per-CLI safe limit per SDD §5.6 v1.1
and §1.4.4 v1.2 mandate ("always introduced" — NOT conditional on FR-8.6
stress-test outcome). Operators flip `dispatch_preference: headless` knowing
the substrate already protects against unbounded concurrency.

## Design

`AcquireSlotResult` is a context manager. Acquisition walks slot indices
0..N-1 and attempts non-blocking `flock(LOCK_EX | LOCK_NB)` on each. The
first slot whose flock succeeds becomes the holder; the fd stays open
until release. OS auto-releases on process exit (defense against stuck
holders).

When ALL slots are busy, the acquirer does a bounded wait — BB iter-1
#905 carry-in C5: wait across ALL slots, NOT just slot-0. Implementation
uses `flock(LOCK_EX)` blocking on the slot whose lock-file mtime is
oldest (best-effort fairness). Bounded by `_BLOCKING_WAIT_TIMEOUT` (10s);
on exhaustion → SemaphoreExhausted (C12 marker propagated through
MODELINV `semaphore_exhausted: true`).

## File layout

```
.run/headless-concurrency-{cli}/
├── slot-0.lock   # mode 0600, zero bytes — holder's PID written for diagnostics
├── slot-1.lock
├── ...
└── slot-{N-1}.lock
```

## Operator-tunables (model-config.yaml)

```yaml
providers:
  anthropic:
    models:
      claude-headless:
        # Per-CLI safe-N from FR-8.6 stress test. Default 50 if absent.
        headless_concurrency_limit: 50
```

`advisor_strategy.headless_concurrency_scope` (cross_process | process_only)
selects this substrate vs. `threading.Semaphore`-only mode.
"""

from __future__ import annotations

import errno
import fcntl
import logging
import os
import time
from contextlib import contextmanager
from typing import Generator, List, Optional

logger = logging.getLogger("loa_cheval.adapters.headless_concurrency")


# --- Constants ---------------------------------------------------------------

_DEFAULT_N = 50          # SDD §5.6 v1.1 default; FR-8.6 may seed per-CLI lower
_NON_BLOCKING_POLL_DELAY = 0.05  # 50ms between full-slot retries
_BLOCKING_WAIT_TIMEOUT = 10.0    # max wall-clock before SemaphoreExhausted
_DEFAULT_RUN_DIR = ".run"


class SemaphoreExhausted(RuntimeError):
    """Raised when all N slots are held longer than `_BLOCKING_WAIT_TIMEOUT`.

    Carries the CLI name so the caller can record `semaphore_exhausted: true`
    on the MODELINV envelope (C12 closure) AND emit `[CHAIN-EXHAUSTED-CONCURRENCY]`
    distinct from CHAIN_EXHAUSTED (which means chain-walk exhausted retries).
    """

    def __init__(self, cli: str, n_slots: int, waited_seconds: float):
        super().__init__(
            f"all {n_slots} headless-concurrency slots for {cli!r} busy after "
            f"{waited_seconds:.1f}s wait (cycle-110 SDD §5.6 C12 closure)"
        )
        self.cli = cli
        self.n_slots = n_slots
        self.waited_seconds = waited_seconds


# --- Slot directory helpers --------------------------------------------------


def _slot_dir(cli: str, run_dir: str) -> str:
    """`.run/headless-concurrency-{cli}/` — one directory per CLI."""
    # cli is operator-controlled config; validate to alphanumeric + hyphen
    # to prevent path-traversal at the boundary.
    if not _is_safe_cli_name(cli):
        raise ValueError(
            f"cli name {cli!r} contains forbidden characters; allowed: "
            "lowercase alphanumeric + hyphen"
        )
    return os.path.join(run_dir, f"headless-concurrency-{cli}")


def _is_safe_cli_name(cli: str) -> bool:
    if not cli or len(cli) > 64:
        return False
    return all(c.isalnum() or c == "-" for c in cli)


def _slot_path(cli: str, slot_idx: int, run_dir: str) -> str:
    return os.path.join(_slot_dir(cli, run_dir), f"slot-{slot_idx}.lock")


def _resolve_run_dir(run_dir: str) -> str:
    """BB iter-1 #908 F-004 closure (HIGH): resolve to absolute path.

    A relative `.run` default silently partitions the cross-process semaphore
    by cwd: two cheval processes running from different working directories
    would lock distinct slot files and over-allocate by 2× the intended N.
    Resolving to abspath at the boundary makes the partition deterministic
    (CWD at acquire-time pins the semaphore scope) and lets operators see
    the resolved path in DEBUG logs.
    """
    abs_path = os.path.abspath(run_dir)
    if abs_path != run_dir:
        logger.debug(
            "headless-concurrency: resolved run_dir %r → %r (cycle-110 F-004)",
            run_dir, abs_path,
        )
    return abs_path


def _ensure_slot_dir(cli: str, run_dir: str) -> None:
    """Create `.run/headless-concurrency-{cli}/` mode 0700.

    BB iter-1 #908 F-003 closure (MEDIUM): on existing-dir reuse, explicitly
    chmod to 0o700. `os.makedirs(mode=)` is a no-op on existing paths —
    matches CVE-2019-14287 / OpenSSH safe_path discipline.
    """
    path = _slot_dir(cli, run_dir)
    try:
        os.makedirs(path, mode=0o700, exist_ok=True)
        # F-003: enforce 0o700 even if the dir already existed with looser
        # perms. chmod is idempotent + cheap; protects against a previous
        # invocation that created the dir with a wider umask.
        try:
            os.chmod(path, 0o700)
        except OSError:
            pass  # best-effort; the slot-file open will still enforce 0o600
    except OSError as exc:
        raise OSError(f"failed to create slot dir {path}: {exc}") from exc


def _open_slot_file(path: str) -> int:
    """Open / create a slot file mode 0600 and return its fd.

    O_NOFOLLOW defends against TOCTOU symlink redirect at the slot path.
    """
    fd = os.open(path, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    return fd


def _try_acquire_slot(fd: int) -> bool:
    """Attempt non-blocking exclusive flock. Returns True on success."""
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        return True
    except OSError as exc:
        if exc.errno in (errno.EAGAIN, errno.EWOULDBLOCK):
            return False
        raise


def _stamp_pid(fd: int) -> None:
    """Write the holder PID into the lock file for diagnostics."""
    try:
        os.ftruncate(fd, 0)
        os.lseek(fd, 0, os.SEEK_SET)
        os.write(fd, str(os.getpid()).encode("ascii"))
    except OSError:
        pass  # diagnostic best-effort


def _release_slot(fd: int) -> None:
    try:
        fcntl.flock(fd, fcntl.LOCK_UN)
    except OSError:
        pass
    try:
        os.close(fd)
    except OSError:
        pass


# --- Public API --------------------------------------------------------------


@contextmanager
def acquire_slot(
    cli: str,
    *,
    n_slots: int = _DEFAULT_N,
    timeout_seconds: float = _BLOCKING_WAIT_TIMEOUT,
    run_dir: str = _DEFAULT_RUN_DIR,
) -> Generator[int, None, None]:
    """Acquire one of N slots for `cli`, yielding the slot index.

    Usage:

        from loa_cheval.adapters.headless_concurrency import (
            acquire_slot, SemaphoreExhausted,
        )

        try:
            with acquire_slot("claude-headless", n_slots=50):
                # subprocess.Popen(...) within the slot
                ...
        except SemaphoreExhausted as e:
            # Record semaphore_exhausted=True on MODELINV envelope (C12)
            ...

    Acquisition strategy (BB iter-1 #905 C5 closure):
    1. Walk slots 0..N-1; for each, try non-blocking flock.
    2. If a slot is acquired → yield slot index; release on context exit.
    3. If all slots busy → loop with `_NON_BLOCKING_POLL_DELAY` between sweeps
       until `timeout_seconds` elapses. On timeout → SemaphoreExhausted.
       The wait is across ALL slots; we do NOT block on slot-0 specifically
       (closes BB #905 C5: "wait-all-slots, NOT slot-0 only").

    Args:
        cli: CLI name (e.g., "claude-headless"). Validated against safe-name
            regex; raises ValueError on path-injection class characters.
        n_slots: per-CLI concurrency limit. Operator sources from
            `model-config.yaml::headless_concurrency_limit`.
        timeout_seconds: max wall-clock blocked on full slots before
            SemaphoreExhausted. Default 10s.
        run_dir: parent for `.run/headless-concurrency-{cli}/`. Test
            fixtures pass a tmp dir.

    Raises:
        ValueError: cli name invalid.
        OSError: slot-dir create or slot-file open failed (unrecoverable).
        SemaphoreExhausted: all slots busy past timeout.
    """
    if n_slots < 1 or n_slots > 1000:
        raise ValueError(
            f"n_slots must be 1..1000, got {n_slots}"
        )

    # F-004 closure: resolve run_dir to absolute path BEFORE any FS ops so
    # both _ensure_slot_dir AND _slot_path see the same canonical scope.
    run_dir = _resolve_run_dir(run_dir)
    _ensure_slot_dir(cli, run_dir)

    started_at = time.monotonic()
    deadline = started_at + timeout_seconds

    # Round-robin probe across all N slots. Re-walk after _NON_BLOCKING_POLL_DELAY
    # until either we acquire one OR the deadline passes.
    held_fd: Optional[int] = None
    held_idx: Optional[int] = None
    while True:
        for slot_idx in range(n_slots):
            path = _slot_path(cli, slot_idx, run_dir)
            try:
                fd = _open_slot_file(path)
            except OSError as exc:
                logger.warning(
                    "slot file open failed for %s slot=%d: %s",
                    cli, slot_idx, exc,
                )
                continue
            if _try_acquire_slot(fd):
                held_fd = fd
                held_idx = slot_idx
                _stamp_pid(fd)
                break
            os.close(fd)
        if held_fd is not None:
            break
        if time.monotonic() >= deadline:
            raise SemaphoreExhausted(
                cli=cli,
                n_slots=n_slots,
                waited_seconds=time.monotonic() - started_at,
            )
        time.sleep(_NON_BLOCKING_POLL_DELAY)

    logger.debug(
        "headless-concurrency: acquired %s slot=%d (waited %.3fs)",
        cli, held_idx, time.monotonic() - started_at,
    )
    try:
        yield held_idx  # type: ignore[misc]
    finally:
        _release_slot(held_fd)
        logger.debug(
            "headless-concurrency: released %s slot=%d",
            cli, held_idx,
        )


__all__ = [
    "SemaphoreExhausted",
    "acquire_slot",
]
