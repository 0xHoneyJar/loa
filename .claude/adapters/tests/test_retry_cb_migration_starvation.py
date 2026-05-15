"""CRIT-1 closure: SDD §5.3 starvation guard around CB migration timeout.

Tests the retry envelope wrapped around `check_state` inside retry.py:
- Migration timeout retried per `_CB_MIGRATION_RETRY_DELAYS` (1s / 2s / 4s).
- After exhausting retries, the helper degrades to "OPEN" rather than
  re-raising CircuitBreakerMigrationTimeout.
- A transient timeout that succeeds on retry returns the underlying state.
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from loa_cheval.providers import retry as retry_mod  # noqa: E402
from loa_cheval.routing.circuit_breaker import (  # noqa: E402
    CLOSED,
    CircuitBreakerMigrationTimeout,
)


CB_CONFIG = {
    "routing": {"circuit_breaker": {"failure_threshold": 3, "count_window_seconds": 60}}
}


class _SequencedCheckState:
    """Callable that yields a queue of side-effects on each call.

    Used to simulate the migration-timeout retry envelope: first N calls
    raise CircuitBreakerMigrationTimeout, subsequent calls return a value.
    """

    def __init__(self, sequence):
        self._seq = list(sequence)
        self.calls = 0

    def __call__(self, provider, auth_type, config, run_dir=".run"):
        self.calls += 1
        if not self._seq:
            raise AssertionError("check_state called more times than expected")
        nxt = self._seq.pop(0)
        if isinstance(nxt, Exception):
            raise nxt
        return nxt


def _patch_check_state_and_sleep(monkeypatch, seq):
    fake = _SequencedCheckState(seq)
    # Patch the symbol the retry envelope binds via local import.
    monkeypatch.setattr(
        "loa_cheval.routing.circuit_breaker.check_state", fake
    )
    sleep_calls = []
    monkeypatch.setattr(retry_mod.time, "sleep", lambda d: sleep_calls.append(d))
    return fake, sleep_calls


class TestMigrationStarvationGuard:
    def test_transient_timeout_then_success(self, monkeypatch):
        """One timeout retry → second attempt succeeds → state returned."""
        fake, sleeps = _patch_check_state_and_sleep(
            monkeypatch,
            [CircuitBreakerMigrationTimeout(holder_pid=1234, timeout_seconds=10), CLOSED],
        )
        state = retry_mod._check_circuit_breaker("openai", "http_api", CB_CONFIG)
        assert state == CLOSED
        assert fake.calls == 2
        # First-retry delay is the canonical 1.0s per SDD.
        assert sleeps == [1.0]

    def test_all_retries_exhausted_degrades_to_open(self, monkeypatch):
        """4 consecutive timeouts (initial + 3 retries) → helper returns OPEN."""
        timeout = CircuitBreakerMigrationTimeout(holder_pid=99, timeout_seconds=10)
        fake, sleeps = _patch_check_state_and_sleep(
            monkeypatch, [timeout, timeout, timeout, timeout]
        )
        state = retry_mod._check_circuit_breaker("openai", "http_api", CB_CONFIG)
        assert state == "OPEN"
        assert fake.calls == 4
        # Backoff sequence is canonical 1 / 2 / 4 per SDD §5.3.
        assert sleeps == [1.0, 2.0, 4.0]

    def test_immediate_success_no_sleep(self, monkeypatch):
        """Migration succeeds on first attempt — no retry-envelope overhead."""
        fake, sleeps = _patch_check_state_and_sleep(monkeypatch, [CLOSED])
        state = retry_mod._check_circuit_breaker("openai", "http_api", CB_CONFIG)
        assert state == CLOSED
        assert fake.calls == 1
        assert sleeps == []

    def test_typed_exception_never_escapes(self, monkeypatch):
        """The whole point: callers must not see CircuitBreakerMigrationTimeout."""
        timeout = CircuitBreakerMigrationTimeout(holder_pid=42, timeout_seconds=10)
        _patch_check_state_and_sleep(
            monkeypatch, [timeout, timeout, timeout, timeout]
        )
        # Must NOT raise.
        try:
            retry_mod._check_circuit_breaker("openai", "http_api", CB_CONFIG)
        except CircuitBreakerMigrationTimeout:  # pragma: no cover
            pytest.fail(
                "retry envelope must absorb CircuitBreakerMigrationTimeout; "
                "starvation guard regression"
            )

    def test_retry_delays_are_canonical_sdd_sequence(self, monkeypatch):
        """SDD §5.3 mandates 1s / 2s / 4s exactly. Pin against re-tune drift."""
        assert retry_mod._CB_MIGRATION_RETRY_DELAYS == (1.0, 2.0, 4.0)
