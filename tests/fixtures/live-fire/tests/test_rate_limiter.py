"""Baseline tests for the live-fire rate_limiter fixture.

These pass on the fixture AS SHIPPED (bugs included) — they exercise the
happy path only, deliberately avoiding the two boundary conditions the
seeded bugs live in. Task T1 in grimoires/loa/sprint.md asks the model
under test to find those boundaries itself, prove them with a new
failing-then-passing test, and fix them.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from rate_limiter import RateLimiter  # noqa: E402


def test_allow_within_limit():
    rl = RateLimiter(max_requests=2, window_seconds=10.0)
    assert rl.allow("alice", now=0.0) is True
    assert rl.allow("alice", now=1.0) is True


def test_remaining_decrements_as_hits_accrue():
    rl = RateLimiter(max_requests=3, window_seconds=10.0)
    assert rl.remaining("bob", now=0.0) == 3
    rl.allow("bob", now=0.0)
    assert rl.remaining("bob", now=0.5) == 2


def test_window_frees_up_after_it_fully_elapses():
    rl = RateLimiter(max_requests=1, window_seconds=5.0)
    assert rl.allow("carol", now=0.0) is True
    # Well past the window (10s > 5s window) — should have a free slot.
    assert rl.remaining("carol", now=10.0) == 1


def test_separate_keys_are_independent():
    rl = RateLimiter(max_requests=1, window_seconds=10.0)
    assert rl.allow("dave", now=0.0) is True
    assert rl.allow("erin", now=0.0) is True
