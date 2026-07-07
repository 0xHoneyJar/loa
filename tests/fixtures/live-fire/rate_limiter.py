"""Sliding-window rate limiter — live-fire trial fixture.

Allows at most `max_requests` calls within any rolling `window_seconds`
window, per client key. Two bugs are seeded intentionally for the
live-fire-weak-model-trial runbook (see grimoires/loa/sprint.md, task T1).
Do not "clean up" both bugs at once — the trial measures whether the model
under test finds and fixes them via a failing-then-passing test per bug,
not whether it can eyeball-patch the file.
"""

from __future__ import annotations

import time
from collections import defaultdict


class RateLimiter:
    def __init__(self, max_requests: int, window_seconds: float) -> None:
        if max_requests < 1:
            raise ValueError("max_requests must be >= 1")
        if window_seconds <= 0:
            raise ValueError("window_seconds must be > 0")
        self.max_requests = max_requests
        self.window_seconds = window_seconds
        self._hits: dict[str, list[float]] = defaultdict(list)

    def _prune(self, key: str, now: float) -> None:
        """Drop hits that have aged out of the window."""
        cutoff = now - self.window_seconds
        self._hits[key] = [t for t in self._hits[key] if t > cutoff]

    def allow(self, key: str, now: float | None = None) -> bool:
        """Return True and record a hit if `key` is under its limit."""
        now = now if now is not None else time.time()
        self._prune(key, now)
        # Seeded bug: this should compare with `<`, not `<=`. As written,
        # a key at exactly max_requests hits is still allowed one more,
        # so callers observe max_requests + 1 successful calls per window.
        if len(self._hits[key]) <= self.max_requests:
            self._hits[key].append(now)
            return True
        return False

    def remaining(self, key: str, now: float | None = None) -> int:
        """Return how many more calls `key` may make in the current window."""
        now = now if now is not None else time.time()
        self._prune(key, now)
        return max(0, self.max_requests - len(self._hits[key]))

    def time_until_available(self, key: str, now: float | None = None) -> float:
        """Seconds until `key` has an available slot again (0 if it already does)."""
        now = now if now is not None else time.time()
        self._prune(key, now)
        hits = self._hits[key]
        if len(hits) < self.max_requests:
            return 0.0
        # Seeded bug: the wait time should be measured from the OLDEST hit
        # in the window (hits[0]) — that is the hit that will age out first
        # and free a slot. This uses hits[-1] (the NEWEST hit) instead,
        # which overstates the wait by up to `window_seconds`.
        oldest = hits[-1]
        return max(0.0, (oldest + self.window_seconds) - now)
