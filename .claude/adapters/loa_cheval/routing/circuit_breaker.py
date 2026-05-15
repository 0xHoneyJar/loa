"""File-based circuit breaker per (provider, auth_type) bucket.

Cycle-110 FR-0: state file key widened from `provider` to `(provider, auth_type)`.

State machine: CLOSED → OPEN → HALF_OPEN → CLOSED.
State persisted in `.run/circuit-breaker-{provider}-{auth_type}.json`.

A legacy file at `.run/circuit-breaker-{provider}.json` (pre-cycle-110) is
migrated on first access — its state is preserved into the `http_api` bucket
and CLOSED-default buckets are seeded for the other auth_types. A transitional
symlink `.run/circuit-breaker-{provider}.json -> circuit-breaker-{provider}-http_api.json`
is created so pre-cycle-110 direct-read scripts continue to work; the symlink
is removed in cycle-111.
"""

from __future__ import annotations

import errno
import fcntl
import json
import logging
import os
import time
from typing import Any, Dict, Iterable, Optional

logger = logging.getLogger("loa_cheval.routing.circuit_breaker")

# States
CLOSED = "CLOSED"
OPEN = "OPEN"
HALF_OPEN = "HALF_OPEN"

# Auth-type buckets (closed enum per [PRD:FR-2.2])
AUTH_TYPE_HEADLESS = "headless"
AUTH_TYPE_HTTP_API = "http_api"
AUTH_TYPE_AWS_IAM = "aws_iam"
AUTH_TYPES: tuple = (AUTH_TYPE_HEADLESS, AUTH_TYPE_HTTP_API, AUTH_TYPE_AWS_IAM)

# Legacy state preserves into the http_api bucket (HTTP-path was prior tripping
# surface; conservative choice per SDD §3.3 migration semantics).
LEGACY_AUTH_TYPE = AUTH_TYPE_HTTP_API

# Default config values (match model-config.yaml)
DEFAULT_FAILURE_THRESHOLD = 5
DEFAULT_RESET_TIMEOUT = 60  # seconds
DEFAULT_HALF_OPEN_MAX_PROBES = 1
DEFAULT_COUNT_WINDOW = 300  # seconds

# Migration lock + timing (SDD §5.3 lock-contention semantics)
MIGRATION_LOCK_NAME = "circuit-breaker-migration.lock"
MIGRATION_LOCK_TIMEOUT_SECONDS = 10
# Tempfile cleanup threshold for janitor (cycle-110 C8 closure).
TEMPFILE_PREFIX = "tmp-redaction-"
TEMPFILE_MAX_AGE_SECONDS = 3600  # 1h


class CircuitBreakerMigrationTimeout(RuntimeError):
    """Raised when the migration lock cannot be acquired within timeout."""

    def __init__(self, holder_pid: int, timeout_seconds: float) -> None:
        super().__init__(
            f"circuit-breaker migration lock held by pid={holder_pid} "
            f"after {timeout_seconds:.1f}s wait"
        )
        self.holder_pid = holder_pid
        self.timeout_seconds = timeout_seconds


# ---------------------------------------------------------------------------
# Path helpers
# ---------------------------------------------------------------------------


def _validate_auth_type(auth_type: str) -> None:
    """Reject auth_type values outside the closed enum ([PRD:FR-2.2])."""
    if auth_type not in AUTH_TYPES:
        raise ValueError(
            f"auth_type must be one of {AUTH_TYPES}, got {auth_type!r}"
        )


def _state_file_path(
    provider: str,
    auth_type: str,
    run_dir: str = ".run",
) -> str:
    """Compute state file path for a (provider, auth_type) bucket.

    Cycle-110 FR-0: file naming is `circuit-breaker-{provider}-{auth_type}.json`.
    """
    _validate_auth_type(auth_type)
    return os.path.join(run_dir, f"circuit-breaker-{provider}-{auth_type}.json")


def _legacy_state_file_path(provider: str, run_dir: str = ".run") -> str:
    """Pre-cycle-110 path (also the transitional-symlink path)."""
    return os.path.join(run_dir, f"circuit-breaker-{provider}.json")


def _migration_lock_path(run_dir: str = ".run") -> str:
    return os.path.join(run_dir, MIGRATION_LOCK_NAME)


def _journal_path(run_dir: str = ".run") -> str:
    """Substrate-health journal that receives `[L4-MIGRATION-CORRUPT]` markers
    when a corrupted legacy file forces a cold-start fail-open."""
    return os.path.join(run_dir, "substrate-health-journal.jsonl")


# ---------------------------------------------------------------------------
# Atomic file IO (tempfile + rename + fsync)
# ---------------------------------------------------------------------------


def _atomic_write_json(path: str, data: Dict[str, Any]) -> None:
    """Write JSON atomically: tempfile in same dir, fsync, rename.

    Mode is 0600 per Flatline SKP-005 HIGH-735 closure (cycle-110 T0.3 spirit).
    """
    target_dir = os.path.dirname(path) or "."
    os.makedirs(target_dir, exist_ok=True)
    # mktemp under same dir for cross-filesystem-safe atomic rename.
    pid = os.getpid()
    tmp_name = f"{os.path.basename(path)}.tmp.{pid}.{int(time.time() * 1e6)}"
    tmp_path = os.path.join(target_dir, tmp_name)

    payload = json.dumps(data, indent=2).encode("utf-8")
    fd = os.open(tmp_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    try:
        os.write(fd, payload)
        os.fsync(fd)
    finally:
        os.close(fd)
    os.replace(tmp_path, path)


# ---------------------------------------------------------------------------
# State read / default / write
# ---------------------------------------------------------------------------


def _default_state(provider: str, auth_type: str) -> Dict[str, Any]:
    """Return default CLOSED state for a (provider, auth_type) bucket."""
    return {
        "provider": provider,
        "auth_type": auth_type,
        "state": CLOSED,
        "failure_count": 0,
        "last_failure_ts": None,
        "opened_at": None,
        "half_open_probes": 0,
    }


def _state_file_is_symlink(path: str) -> bool:
    """Wrapper kept separate so tests / callers can stub it.

    C13 closure: migration scanner MUST exclude symlinks (the transitional
    symlink would otherwise be re-migrated into itself).
    """
    return os.path.islink(path)


def _read_state(
    provider: str,
    auth_type: str,
    run_dir: str = ".run",
) -> Dict[str, Any]:
    """Read circuit breaker state for (provider, auth_type).

    Auto-migrates on first read if a legacy file is present (FR-0.2).
    Returns default CLOSED state if file doesn't exist or is corrupted.

    Read-modify-write atomicity: _read_state() and _write_state() acquire
    locks independently. record_failure/record_success may race; missed
    counts are self-correcting on next failure (best-effort counting is
    appropriate for circuit breakers).
    """
    _validate_auth_type(auth_type)

    # First-read auto-migration of pre-cycle-110 state file.
    _migrate_legacy_state_if_present(provider, run_dir=run_dir)

    path = _state_file_path(provider, auth_type, run_dir)
    if not os.path.exists(path):
        return _default_state(provider, auth_type)

    try:
        with open(path, "r") as f:
            data = json.load(f)
        if data.get("provider") != provider or "state" not in data:
            return _default_state(provider, auth_type)
        # auth_type may be absent in a hand-rolled file; treat as match.
        if data.get("auth_type", auth_type) != auth_type:
            return _default_state(provider, auth_type)
        # Backfill auth_type for files written before this revision.
        data.setdefault("auth_type", auth_type)
        return data
    except (json.JSONDecodeError, OSError):
        return _default_state(provider, auth_type)


def _write_state(state: Dict[str, Any], run_dir: str = ".run") -> None:
    """Atomically write circuit breaker state to file."""
    provider = state["provider"]
    auth_type = state.get("auth_type", LEGACY_AUTH_TYPE)
    _validate_auth_type(auth_type)
    path = _state_file_path(provider, auth_type, run_dir)
    os.makedirs(run_dir, exist_ok=True)

    # Use flock-protected truncate-and-write (matches pre-cycle-110 semantics
    # for compatibility with concurrent readers that don't see a partial
    # write window).
    fd = os.open(path, os.O_RDWR | os.O_CREAT, 0o644)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        os.lseek(fd, 0, os.SEEK_SET)
        os.ftruncate(fd, 0)
        os.write(fd, json.dumps(state, indent=2).encode("utf-8"))
    finally:
        fcntl.flock(fd, fcntl.LOCK_UN)
        os.close(fd)


# ---------------------------------------------------------------------------
# Migration helper (FR-0.2)
# ---------------------------------------------------------------------------


def _emit_journal_marker(
    run_dir: str,
    marker: str,
    detail: Dict[str, Any],
) -> None:
    """Append a one-line JSON marker to the substrate-health journal.

    Best-effort: on IO error, swallow — the marker is operator-observability,
    not load-bearing for circuit-breaker correctness.
    """
    try:
        os.makedirs(run_dir, exist_ok=True)
        path = _journal_path(run_dir)
        entry = {
            "ts": time.time(),
            "marker": marker,
            **detail,
        }
        with open(path, "a", encoding="utf-8") as fh:
            fh.write(json.dumps(entry) + "\n")
    except OSError as exc:
        logger.warning("journal write failed: %s", exc)


def _acquire_migration_lock(
    lock_path: str,
    timeout_seconds: float = MIGRATION_LOCK_TIMEOUT_SECONDS,
) -> int:
    """Acquire the migration lock with a timeout.

    Returns the lock file descriptor. Caller is responsible for closing.

    Raises:
        CircuitBreakerMigrationTimeout: if the lock cannot be acquired within
            `timeout_seconds`. The exception carries the holder's pid if it
            was written into the lock file.
    """
    os.makedirs(os.path.dirname(lock_path) or ".", exist_ok=True)
    fd = os.open(lock_path, os.O_RDWR | os.O_CREAT, 0o600)
    deadline = time.monotonic() + timeout_seconds
    while True:
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            break
        except OSError as exc:
            if exc.errno not in (errno.EAGAIN, errno.EWOULDBLOCK):
                os.close(fd)
                raise
            if time.monotonic() >= deadline:
                holder_pid = 0
                try:
                    with open(lock_path, "r") as fh:
                        text = fh.read().strip()
                    if text.isdigit():
                        holder_pid = int(text)
                except OSError:
                    pass
                os.close(fd)
                raise CircuitBreakerMigrationTimeout(holder_pid, timeout_seconds)
            time.sleep(0.05)
    # Stamp PID into the lock file (informational; survives flock release).
    try:
        os.ftruncate(fd, 0)
        os.lseek(fd, 0, os.SEEK_SET)
        os.write(fd, str(os.getpid()).encode("ascii"))
    except OSError:
        pass
    return fd


def _release_migration_lock(fd: int) -> None:
    try:
        fcntl.flock(fd, fcntl.LOCK_UN)
    except OSError:
        pass
    try:
        os.close(fd)
    except OSError:
        pass


def _seed_default_bucket(
    provider: str,
    auth_type: str,
    run_dir: str,
) -> bool:
    """Create a CLOSED-default state file if it does not already exist.

    Returns True if a new file was created, False if it already existed.
    """
    path = _state_file_path(provider, auth_type, run_dir)
    if os.path.lexists(path):
        return False
    _atomic_write_json(path, _default_state(provider, auth_type))
    return True


def _create_transitional_symlink(
    provider: str,
    run_dir: str,
) -> None:
    """Create `.run/circuit-breaker-{provider}.json -> *-http_api.json`.

    Idempotent. Skips creation if the path already exists as a regular file
    (the caller's migration has not yet unlinked the legacy file) — the
    symlink is materialized only after the legacy file is removed.

    BB iter-2 F12 closure: uses `os.symlink` to a temp name + `os.rename`
    to atomically replace the legacy path. POSIX rename(2) is the only
    primitive that replaces-and-links in a single syscall, so SIGKILL/OOM
    between steps cannot leave a permanent gap (which would have violated
    FR-0.6). The temp-name + rename pattern matches Postgres WAL and
    Git's index.lock → index discipline.
    """
    legacy_path = _legacy_state_file_path(provider, run_dir)
    http_api_target = f"circuit-breaker-{provider}-http_api.json"

    # If a regular file lives there, do NOT clobber it (concurrent migrator
    # could be mid-flight). On idempotent re-run, the legacy regular file
    # has been unlinked first, so this path is either absent or a symlink.
    if os.path.lexists(legacy_path):
        if _state_file_is_symlink(legacy_path):
            try:
                if os.readlink(legacy_path) == http_api_target:
                    return
            except OSError:
                return
            # Mismatched target — fall through to atomic-rename replacement.
        else:
            # A regular file (not yet unlinked by migration) — leave it.
            return

    # Atomic two-step: create symlink under temp name, then rename onto
    # legacy_path. The rename is atomic — no SIGKILL window.
    tmp_path = f"{legacy_path}.tmp.symlink.{os.getpid()}.{int(time.time() * 1e6)}"
    try:
        os.symlink(http_api_target, tmp_path)
    except FileExistsError:
        # Astronomically unlikely temp-name collision; bail.
        return
    try:
        # os.replace works on symlinks (it operates on the path, not what it
        # points to). On Linux it's a single rename(2) syscall.
        os.replace(tmp_path, legacy_path)
    except OSError:
        # Cleanup tmp on failure.
        try:
            os.unlink(tmp_path)
        except OSError:
            pass


def _migrate_legacy_state_if_present(
    provider: str,
    run_dir: str = ".run",
) -> None:
    """Idempotent legacy-state migration ([PRD:FR-0.2], SDD §3.3).

    Steps:
      1. Acquire advisory flock on `.run/circuit-breaker-migration.lock`.
      2. Skip if the legacy path is a symlink (C13 closure — the transitional
         symlink would otherwise be re-migrated into itself).
      3. If the legacy file exists and the `(provider, http_api)` bucket
         already exists with non-default state, DROP the legacy file (C3
         closure — newer state wins; do not overwrite).
      4. Otherwise, preserve legacy state into the `http_api` bucket.
      5. Seed CLOSED-default buckets for the other auth_types.
      6. Unlink legacy ONLY after new files are durably written.
      7. Create the transitional symlink ([PRD:FR-0.6]).
      8. On corrupted legacy: cold-start fail-open + `[L4-MIGRATION-CORRUPT]`
         journal marker (per SDD §1.9 + cycle-099 cache-check precedent).

    Concurrent invocation: first acquirer performs migration; subsequent
    acquirers observe post-state and become no-ops. FileNotFoundError on
    concurrent unlink is swallowed.
    """
    legacy_path = _legacy_state_file_path(provider, run_dir)

    # Fast-path: nothing to migrate (most common case after first invocation).
    if not os.path.lexists(legacy_path):
        return

    # C13: transitional symlink is NOT a legacy file — leave it alone.
    if _state_file_is_symlink(legacy_path):
        return

    lock_path = _migration_lock_path(run_dir)
    lock_fd = _acquire_migration_lock(lock_path)
    try:
        # Re-check under lock: another migrator may have completed the work.
        if not os.path.lexists(legacy_path):
            return
        if _state_file_is_symlink(legacy_path):
            return

        # Try to read legacy content; on corruption, fail-open.
        legacy_data: Optional[Dict[str, Any]] = None
        corrupted = False
        try:
            with open(legacy_path, "r", encoding="utf-8") as fh:
                legacy_data = json.load(fh)
            if not isinstance(legacy_data, dict) or "state" not in legacy_data:
                corrupted = True
                legacy_data = None
        except (OSError, json.JSONDecodeError):
            corrupted = True

        http_api_path = _state_file_path(provider, AUTH_TYPE_HTTP_API, run_dir)

        if corrupted:
            _emit_journal_marker(
                run_dir,
                "L4-MIGRATION-CORRUPT",
                {
                    "provider": provider,
                    "legacy_path": legacy_path,
                    "action": "cold-start-fail-open",
                },
            )
            # Cold-start fail-open: seed default CLOSED bucket if absent.
            if not os.path.lexists(http_api_path):
                _atomic_write_json(
                    http_api_path,
                    _default_state(provider, AUTH_TYPE_HTTP_API),
                )
        else:
            assert legacy_data is not None
            # C3: if an http_api bucket already exists with non-default
            # state, prefer the newer state — drop legacy.
            existing_http_api: Optional[Dict[str, Any]] = None
            if os.path.lexists(http_api_path) and not _state_file_is_symlink(http_api_path):
                try:
                    with open(http_api_path, "r", encoding="utf-8") as fh:
                        existing_http_api = json.load(fh)
                except (OSError, json.JSONDecodeError):
                    existing_http_api = None
            if _bucket_has_state(existing_http_api):
                logger.info(
                    "circuit-breaker migration: dropping legacy %s "
                    "(http_api bucket already has state)",
                    legacy_path,
                )
            else:
                # Preserve legacy state into the http_api bucket.
                preserved = dict(legacy_data)
                preserved["provider"] = provider
                preserved["auth_type"] = AUTH_TYPE_HTTP_API
                _atomic_write_json(http_api_path, preserved)

        # Seed CLOSED-default buckets for the other auth_types per SDD §3.3
        # step 2c: headless always; aws_iam ONLY for bedrock (else lazy-seeded
        # on first dispatch). Matching the spec narrows the at-rest surface
        # — substrate-health operators don't see empty aws_iam buckets for
        # providers that will never use them.
        _seed_default_bucket(provider, AUTH_TYPE_HEADLESS, run_dir)
        if provider == "bedrock":
            _seed_default_bucket(provider, AUTH_TYPE_AWS_IAM, run_dir)

        # Only AFTER new files exist, unlink legacy.
        try:
            os.unlink(legacy_path)
        except FileNotFoundError:
            # Concurrent migrator beat us; harmless.
            pass

        # Materialize transitional symlink ([PRD:FR-0.6]).
        _create_transitional_symlink(provider, run_dir)
    finally:
        _release_migration_lock(lock_fd)


def _bucket_has_state(data: Optional[Dict[str, Any]]) -> bool:
    """Detect whether a state file carries non-default state worth preserving.

    Used by C3 (idempotency overwrite-check) to decide whether legacy state
    should be dropped (newer http_api state wins) or preserved.
    """
    if not isinstance(data, dict):
        return False
    if data.get("state") and data.get("state") != CLOSED:
        return True
    if data.get("failure_count", 0):
        return True
    if data.get("last_failure_ts") is not None:
        return True
    if data.get("opened_at") is not None:
        return True
    if data.get("half_open_probes", 0):
        return True
    return False


# ---------------------------------------------------------------------------
# Public API — auth_type-aware (cycle-110 FR-0)
# ---------------------------------------------------------------------------


def check_state(
    provider: str,
    auth_type: str,
    config: Dict[str, Any],
    run_dir: str = ".run",
) -> str:
    """Check circuit breaker state for a (provider, auth_type) bucket.

    Handles state transitions:
    - OPEN → HALF_OPEN when reset_timeout expires.

    Returns: CLOSED, OPEN, or HALF_OPEN.
    """
    cb_config = config.get("routing", {}).get("circuit_breaker", {})
    reset_timeout = cb_config.get("reset_timeout_seconds", DEFAULT_RESET_TIMEOUT)

    state = _read_state(provider, auth_type, run_dir)
    current = state.get("state", CLOSED)

    if current == OPEN:
        opened_at = state.get("opened_at")
        if opened_at and (time.time() - opened_at) >= reset_timeout:
            state["state"] = HALF_OPEN
            state["half_open_probes"] = 0
            _write_state(state, run_dir)
            logger.info(
                "Circuit breaker %s/%s: OPEN → HALF_OPEN (reset_timeout expired)",
                provider, auth_type,
            )
            return HALF_OPEN
        return OPEN

    if current == HALF_OPEN:
        max_probes = cb_config.get(
            "half_open_max_probes", DEFAULT_HALF_OPEN_MAX_PROBES
        )
        if state.get("half_open_probes", 0) >= max_probes:
            return OPEN  # Too many concurrent probes
        return HALF_OPEN

    return CLOSED


def record_failure(
    provider: str,
    auth_type: str,
    config: Dict[str, Any],
    run_dir: str = ".run",
) -> str:
    """Record a failure for a (provider, auth_type) bucket.

    Handles state transitions:
    - CLOSED → OPEN when failure_count >= threshold within count_window.
    - HALF_OPEN → OPEN on probe failure (timer restarts).

    Returns new state after recording.
    """
    cb_config = config.get("routing", {}).get("circuit_breaker", {})
    threshold = cb_config.get("failure_threshold", DEFAULT_FAILURE_THRESHOLD)
    count_window = cb_config.get("count_window_seconds", DEFAULT_COUNT_WINDOW)

    state = _read_state(provider, auth_type, run_dir)
    current = state.get("state", CLOSED)
    now = time.time()

    if current == HALF_OPEN:
        state["state"] = OPEN
        state["opened_at"] = now
        state["half_open_probes"] = 0
        _write_state(state, run_dir)
        logger.warning(
            "Circuit breaker %s/%s: HALF_OPEN → OPEN (probe failed)",
            provider, auth_type,
        )
        return OPEN

    if current == CLOSED:
        last_ts = state.get("last_failure_ts")
        if last_ts and (now - last_ts) > count_window:
            state["failure_count"] = 0

        state["failure_count"] = state.get("failure_count", 0) + 1
        state["last_failure_ts"] = now

        if state["failure_count"] >= threshold:
            state["state"] = OPEN
            state["opened_at"] = now
            _write_state(state, run_dir)
            logger.warning(
                "Circuit breaker %s/%s: CLOSED → OPEN "
                "(failures=%d >= threshold=%d)",
                provider, auth_type,
                state["failure_count"], threshold,
            )
            return OPEN

        _write_state(state, run_dir)
        return CLOSED

    # Already OPEN — just record.
    state["last_failure_ts"] = now
    _write_state(state, run_dir)
    return OPEN


def record_success(
    provider: str,
    auth_type: str,
    config: Dict[str, Any],
    run_dir: str = ".run",
) -> str:
    """Record a success for a (provider, auth_type) bucket.

    Handles state transitions:
    - HALF_OPEN → CLOSED on successful probe.

    Returns new state after recording.
    """
    state = _read_state(provider, auth_type, run_dir)
    current = state.get("state", CLOSED)

    if current == HALF_OPEN:
        state = _default_state(provider, auth_type)
        _write_state(state, run_dir)
        logger.info(
            "Circuit breaker %s/%s: HALF_OPEN → CLOSED (probe succeeded)",
            provider, auth_type,
        )
        return CLOSED

    if current == CLOSED:
        if state.get("failure_count", 0) > 0:
            state["failure_count"] = 0
            _write_state(state, run_dir)

    return state.get("state", CLOSED)


def increment_probe(
    provider: str,
    auth_type: str,
    run_dir: str = ".run",
) -> None:
    """Increment half-open probe counter before attempting a probe."""
    state = _read_state(provider, auth_type, run_dir)
    if state.get("state") == HALF_OPEN:
        state["half_open_probes"] = state.get("half_open_probes", 0) + 1
        _write_state(state, run_dir)


# ---------------------------------------------------------------------------
# Operator surface — used by substrate-health CLI (T1.9, FR-0.3)
# ---------------------------------------------------------------------------


def list_buckets(run_dir: str = ".run") -> Dict[str, Dict[str, Dict[str, Any]]]:
    """Enumerate all `(provider, auth_type)` buckets present in run_dir.

    Excludes the transitional symlink (C13) and the migration lock.

    Returns:
        {
            "<provider>": {
                "<auth_type>": {
                    "state": "CLOSED" | "OPEN" | "HALF_OPEN",
                    "failure_count": int,
                    "opened_at": float | None,
                    "path": str,
                },
                ...
            },
            ...
        }
    """
    out: Dict[str, Dict[str, Dict[str, Any]]] = {}
    if not os.path.isdir(run_dir):
        return out

    # BB iter-1 F2 closure: sort listdir BEFORE iterating so operator-visible
    # output is deterministic (POSIX makes no order guarantee). Files that
    # don't match the canonical `circuit-breaker-{provider}-{auth_type}.json`
    # shape are skipped with a one-time WARN — they indicate either a stale
    # legacy file the migration should have handled OR an operator-planted
    # file outside the cycle-110 schema.
    for fname in sorted(os.listdir(run_dir)):
        if not fname.startswith("circuit-breaker-") or not fname.endswith(".json"):
            continue
        if fname == MIGRATION_LOCK_NAME:
            continue
        full = os.path.join(run_dir, fname)
        if _state_file_is_symlink(full):
            # Transitional symlink — skip; the http_api bucket it points to
            # will be enumerated separately.
            continue
        # Parse `circuit-breaker-{provider}-{auth_type}.json` — require the
        # canonical shape. Files matching the prefix but lacking the auth_type
        # suffix are post-migration residue (the migration should have
        # unlinked them); WARN once and skip rather than misclassifying as
        # http_api (which would collide silently with the real http_api
        # bucket and produce listdir-order-dependent behavior).
        stem = fname[len("circuit-breaker-"):-len(".json")]
        parts = stem.rsplit("-", 1)
        if len(parts) != 2 or parts[1] not in AUTH_TYPES:
            logger.warning(
                "[CB-NON-CANONICAL-BUCKET] skipping %s in %s — does not match "
                "circuit-breaker-{provider}-{auth_type}.json shape (auth_type "
                "suffix missing or unknown). Run substrate cleanup to remove.",
                fname, run_dir,
            )
            continue
        provider, auth_type = parts
        try:
            with open(full, "r", encoding="utf-8") as fh:
                data = json.load(fh)
        except (OSError, json.JSONDecodeError):
            data = _default_state(provider, auth_type)
        out.setdefault(provider, {})[auth_type] = {
            "state": data.get("state", CLOSED),
            "failure_count": data.get("failure_count", 0),
            "opened_at": data.get("opened_at"),
            "half_open_probes": data.get("half_open_probes", 0),
            "path": full,
        }
    return out


# ---------------------------------------------------------------------------
# Cleanup utilities
# ---------------------------------------------------------------------------


def cleanup_stale_files(run_dir: str = ".run", max_age_hours: int = 24) -> int:
    """Clean up stale circuit breaker files.

    Removes files (not symlinks) older than max_age_hours. The transitional
    symlink is preserved unconditionally — it has zero on-disk state.

    Returns count of files removed.
    """
    if not os.path.exists(run_dir):
        return 0

    removed = 0
    now = time.time()
    max_age_seconds = max_age_hours * 3600

    for fname in os.listdir(run_dir):
        if not fname.startswith("circuit-breaker-"):
            continue
        if fname == MIGRATION_LOCK_NAME:
            continue
        path = os.path.join(run_dir, fname)
        if _state_file_is_symlink(path):
            continue
        try:
            mtime = os.path.getmtime(path)
            if (now - mtime) > max_age_seconds:
                os.remove(path)
                removed += 1
        except OSError:
            pass

    return removed


def cleanup_stale_tempfiles(
    run_dir: str = ".run",
    max_age_seconds: int = TEMPFILE_MAX_AGE_SECONDS,
    prefix: str = TEMPFILE_PREFIX,
) -> int:
    """Startup tempfile janitor (cycle-110 C8 closure).

    Scans `.run/{prefix}*` files older than `max_age_seconds` and unlinks
    them. Idempotent and safe to invoke on substrate init.

    Returns count of files removed.
    """
    if not os.path.isdir(run_dir):
        return 0
    now = time.time()
    removed = 0
    for fname in os.listdir(run_dir):
        if not fname.startswith(prefix):
            continue
        path = os.path.join(run_dir, fname)
        try:
            mtime = os.path.getmtime(path)
        except OSError:
            continue
        if (now - mtime) <= max_age_seconds:
            continue
        try:
            if os.path.isdir(path) and not os.path.islink(path):
                # Defensive: never recurse — only unlink top-level files.
                continue
            os.unlink(path)
            removed += 1
        except OSError:
            pass
    return removed


__all__ = [
    "AUTH_TYPES",
    "AUTH_TYPE_HEADLESS",
    "AUTH_TYPE_HTTP_API",
    "AUTH_TYPE_AWS_IAM",
    "CLOSED",
    "HALF_OPEN",
    "OPEN",
    "CircuitBreakerMigrationTimeout",
    "check_state",
    "cleanup_stale_files",
    "cleanup_stale_tempfiles",
    "increment_probe",
    "list_buckets",
    "record_failure",
    "record_success",
]
