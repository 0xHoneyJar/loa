"""File-based circuit breaker per provider (SDD §4.2.6).

State machine: CLOSED → OPEN → HALF_OPEN → CLOSED.
State persisted in .run/circuit-breaker-{provider}.json.
"""

from __future__ import annotations

import fcntl
import json
import logging
import os
import time
from typing import Any, Dict, Optional

logger = logging.getLogger("loa_cheval.routing.circuit_breaker")

# States
CLOSED = "CLOSED"
OPEN = "OPEN"
HALF_OPEN = "HALF_OPEN"

# Default config values (match model-config.yaml)
DEFAULT_FAILURE_THRESHOLD = 5
DEFAULT_RESET_TIMEOUT = 60  # seconds
DEFAULT_HALF_OPEN_MAX_PROBES = 1
DEFAULT_COUNT_WINDOW = 300  # seconds


def _state_file_path(provider: str, run_dir: str = ".run") -> str:
    """Compute state file path for a provider."""
    return os.path.join(run_dir, f"circuit-breaker-{provider}.json")


def _read_state(provider: str, run_dir: str = ".run") -> Dict[str, Any]:
    """Read circuit breaker state from file.

    Returns default CLOSED state if file doesn't exist or is corrupted.

    NOTE: _read_state() and _write_state() acquire locks independently.
    This means read-modify-write sequences (e.g. in record_failure) are
    NOT fully atomic across processes — two concurrent callers may both
    read the same state, both increment, and one write overwrites the other.
    This is intentional: best-effort counting is acceptable for circuit
    breakers because missed counts are self-correcting on the next failure.
    Compare with ledger.py:update_daily_spend() which holds the lock across
    the full read-modify-write because cost accounting requires atomicity.
    """
    path = _state_file_path(provider, run_dir)
    if not os.path.exists(path):
        return _default_state(provider)

    try:
        with open(path, "r") as f:
            data = json.load(f)
        # Validate required fields
        if data.get("provider") != provider or "state" not in data:
            return _default_state(provider)
        return data
    except (json.JSONDecodeError, OSError):
        return _default_state(provider)


def _write_state(state: Dict[str, Any], run_dir: str = ".run") -> None:
    """Atomically write circuit breaker state to file."""
    provider = state["provider"]
    path = _state_file_path(provider, run_dir)
    os.makedirs(run_dir, exist_ok=True)

    fd = os.open(path, os.O_RDWR | os.O_CREAT, 0o644)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        os.lseek(fd, 0, os.SEEK_SET)
        os.ftruncate(fd, 0)
        os.write(fd, json.dumps(state, indent=2).encode("utf-8"))
    finally:
        fcntl.flock(fd, fcntl.LOCK_UN)
        os.close(fd)


def _default_state(provider: str) -> Dict[str, Any]:
    """Return default CLOSED state for a provider."""
    return {
        "provider": provider,
        "state": CLOSED,
        "failure_count": 0,
        "last_failure_ts": None,
        "opened_at": None,
        "half_open_probes": 0,
    }


def check_state(
    provider: str,
    config: Dict[str, Any],
    run_dir: str = ".run",
) -> str:
    """Check circuit breaker state for a provider.

    Handles state transitions:
    - OPEN → HALF_OPEN when reset_timeout expires

    Returns: CLOSED, OPEN, or HALF_OPEN.
    """
    cb_config = config.get("routing", {}).get("circuit_breaker", {})
    reset_timeout = cb_config.get("reset_timeout_seconds", DEFAULT_RESET_TIMEOUT)

    state = _read_state(provider, run_dir)
    current = state.get("state", CLOSED)

    if current == OPEN:
        opened_at = state.get("opened_at")
        if opened_at and (time.time() - opened_at) >= reset_timeout:
            # Transition: OPEN → HALF_OPEN
            state["state"] = HALF_OPEN
            state["half_open_probes"] = 0
            _write_state(state, run_dir)
            logger.info(
                "Circuit breaker %s: OPEN → HALF_OPEN (reset_timeout expired)",
                provider,
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
    config: Dict[str, Any],
    run_dir: str = ".run",
) -> str:
    """Record a failure for circuit breaker tracking.

    Handles state transitions:
    - CLOSED → OPEN when failure_count >= threshold within count_window
    - HALF_OPEN → OPEN on probe failure (timer restarts)

    Returns new state after recording.
    """
    cb_config = config.get("routing", {}).get("circuit_breaker", {})
    threshold = cb_config.get("failure_threshold", DEFAULT_FAILURE_THRESHOLD)
    count_window = cb_config.get("count_window_seconds", DEFAULT_COUNT_WINDOW)

    state = _read_state(provider, run_dir)
    current = state.get("state", CLOSED)
    now = time.time()

    if current == HALF_OPEN:
        # Probe failed → back to OPEN (timer restarts)
        state["state"] = OPEN
        state["opened_at"] = now
        state["half_open_probes"] = 0
        _write_state(state, run_dir)
        logger.warning(
            "Circuit breaker %s: HALF_OPEN → OPEN (probe failed)", provider
        )
        return OPEN

    if current == CLOSED:
        # Check if last failure was within the count window
        last_ts = state.get("last_failure_ts")
        if last_ts and (now - last_ts) > count_window:
            # Outside window — reset counter
            state["failure_count"] = 0

        state["failure_count"] = state.get("failure_count", 0) + 1
        state["last_failure_ts"] = now

        if state["failure_count"] >= threshold:
            # Trip: CLOSED → OPEN
            state["state"] = OPEN
            state["opened_at"] = now
            _write_state(state, run_dir)
            logger.warning(
                "Circuit breaker %s: CLOSED → OPEN (failures=%d >= threshold=%d)",
                provider,
                state["failure_count"],
                threshold,
            )
            return OPEN

        _write_state(state, run_dir)
        return CLOSED

    # Already OPEN — just record
    state["last_failure_ts"] = now
    _write_state(state, run_dir)
    return OPEN


def record_success(
    provider: str,
    config: Dict[str, Any],
    run_dir: str = ".run",
) -> str:
    """Record a success for circuit breaker tracking.

    Handles state transitions:
    - HALF_OPEN → CLOSED on successful probe

    Returns new state after recording.
    """
    state = _read_state(provider, run_dir)
    current = state.get("state", CLOSED)

    if current == HALF_OPEN:
        # Probe succeeded → reset to CLOSED
        state = _default_state(provider)
        _write_state(state, run_dir)
        logger.info(
            "Circuit breaker %s: HALF_OPEN → CLOSED (probe succeeded)", provider
        )
        return CLOSED

    if current == CLOSED:
        # Reset failure count on success
        if state.get("failure_count", 0) > 0:
            state["failure_count"] = 0
            _write_state(state, run_dir)

    return state.get("state", CLOSED)


def increment_probe(
    provider: str,
    run_dir: str = ".run",
) -> None:
    """Increment half-open probe counter before attempting a probe."""
    state = _read_state(provider, run_dir)
    if state.get("state") == HALF_OPEN:
        state["half_open_probes"] = state.get("half_open_probes", 0) + 1
        _write_state(state, run_dir)


def cleanup_stale_files(run_dir: str = ".run", max_age_hours: int = 24) -> int:
    """Clean up stale circuit breaker files.

    Removes files older than max_age_hours.
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
        path = os.path.join(run_dir, fname)
        try:
            mtime = os.path.getmtime(path)
            if (now - mtime) > max_age_seconds:
                os.remove(path)
                removed += 1
        except OSError:
            pass

    return removed
