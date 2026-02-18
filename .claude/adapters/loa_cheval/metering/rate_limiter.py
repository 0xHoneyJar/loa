"""Per-provider rate limiting via token bucket (SDD §4.3.5, Flatline IMP-006).

Provides RPM (requests per minute) and TPM (tokens per minute) enforcement.
State persisted to .run/.ratelimit-{provider}.json with flock protection.

NOTE: This rate limiter is ADVISORY, not enforcing. The check() method uses a
non-locking read — multiple concurrent processes may simultaneously pass the
check and exceed the limit. For hard enforcement, use BudgetEnforcer which
provides atomic check+reserve semantics via pre_call_atomic().

Clock semantics: Persisted state uses time.time() (wall clock) for cross-process
compatibility. In-process interval measurement uses time.monotonic().
"""

from __future__ import annotations

import fcntl
import json
import logging
import os
import time
from typing import Any, Dict, Optional

logger = logging.getLogger("loa_cheval.metering.rate_limiter")

# Default limits per provider
DEFAULT_LIMITS: Dict[str, Dict[str, int]] = {
    "google": {"rpm": 60, "tpm": 1_000_000},
    "openai": {"rpm": 500, "tpm": 2_000_000},
    "anthropic": {"rpm": 100, "tpm": 1_000_000},
}


class TokenBucketLimiter:
    """Per-provider RPM/TPM rate limiter using token bucket algorithm.

    State file: .run/.ratelimit-{provider}.json (flock-protected, mode 0o600).
    Bucket refills based on elapsed time since last check.
    """

    def __init__(
        self,
        rpm: int = 60,
        tpm: int = 1_000_000,
        state_dir: str = ".run",
    ) -> None:
        self._rpm = rpm
        self._tpm = tpm
        self._state_dir = state_dir

    def check(self, provider: str, estimated_tokens: int = 0) -> bool:
        """Check if a request is within rate limits (advisory, non-atomic).

        Returns True if the request can proceed, False if rate limited.
        Does NOT consume tokens — use record() after completion.

        NOTE: This is a non-locking read. Multiple concurrent processes may
        simultaneously see capacity and proceed, potentially exceeding the
        limit. For hard enforcement, use BudgetEnforcer.pre_call_atomic().
        """
        state = self._read_state(provider)
        now = time.time()
        state = self._refill(state, now)

        if state["requests_remaining"] <= 0:
            logger.info("Rate limited: %s RPM exhausted", provider)
            return False

        if estimated_tokens > 0 and state["tokens_remaining"] < estimated_tokens:
            logger.info(
                "Rate limited: %s TPM insufficient (%d < %d)",
                provider, state["tokens_remaining"], estimated_tokens,
            )
            return False

        return True

    def record(self, provider: str, tokens_used: int) -> None:
        """Record usage after a completed request.

        Atomically updates state file with flock protection.
        Uses time.time() (wall clock) for cross-process state persistence.
        """
        state_path = self._state_path(provider)
        os.makedirs(self._state_dir, exist_ok=True)

        fd = os.open(state_path, os.O_RDWR | os.O_CREAT, 0o600)
        try:
            fcntl.flock(fd, fcntl.LOCK_EX)

            raw = os.read(fd, 4096)
            if raw:
                try:
                    state = json.loads(raw.decode("utf-8"))
                except json.JSONDecodeError:
                    state = self._default_state()
            else:
                state = self._default_state()

            now = time.time()
            state = self._refill(state, now)

            state["requests_remaining"] = max(0, state["requests_remaining"] - 1)
            state["tokens_remaining"] = max(0, state["tokens_remaining"] - tokens_used)
            state["last_update"] = now

            os.lseek(fd, 0, os.SEEK_SET)
            os.ftruncate(fd, 0)
            os.write(fd, json.dumps(state).encode("utf-8"))
        finally:
            fcntl.flock(fd, fcntl.LOCK_UN)
            os.close(fd)

    def _refill(self, state: Dict[str, Any], now: float) -> Dict[str, Any]:
        """Refill buckets based on elapsed time."""
        elapsed = now - state.get("last_update", now)
        if elapsed <= 0:
            return state

        # Refill proportional to elapsed time (per minute)
        minutes_elapsed = elapsed / 60.0
        rpm_refill = int(self._rpm * minutes_elapsed)
        tpm_refill = int(self._tpm * minutes_elapsed)

        state["requests_remaining"] = min(
            self._rpm, state.get("requests_remaining", self._rpm) + rpm_refill
        )
        state["tokens_remaining"] = min(
            self._tpm, state.get("tokens_remaining", self._tpm) + tpm_refill
        )
        state["last_update"] = now

        return state

    def _default_state(self) -> Dict[str, Any]:
        """Fresh state with full buckets.

        Uses time.time() for cross-process compatibility.
        """
        return {
            "requests_remaining": self._rpm,
            "tokens_remaining": self._tpm,
            "last_update": time.time(),
        }

    def _state_path(self, provider: str) -> str:
        return os.path.join(self._state_dir, f".ratelimit-{provider}.json")

    def _read_state(self, provider: str) -> Dict[str, Any]:
        """Read state file (non-locking, for check only)."""
        path = self._state_path(provider)
        if not os.path.exists(path):
            return self._default_state()
        try:
            with open(path, "r") as f:
                return json.load(f)
        except (json.JSONDecodeError, OSError):
            return self._default_state()


def create_limiter(
    provider: str,
    config: Dict[str, Any],
    state_dir: str = ".run",
) -> TokenBucketLimiter:
    """Create a rate limiter from config or defaults.

    Config path: routing.rate_limits.{provider}.{rpm,tpm}
    """
    rate_limits = config.get("routing", {}).get("rate_limits", {})
    provider_limits = rate_limits.get(provider, {})

    defaults = DEFAULT_LIMITS.get(provider, {"rpm": 60, "tpm": 1_000_000})
    rpm = provider_limits.get("rpm", defaults["rpm"])
    tpm = provider_limits.get("tpm", defaults["tpm"])

    return TokenBucketLimiter(rpm=rpm, tpm=tpm, state_dir=state_dir)
