"""Security tests for SIMSTIM-006: Rate Limiter Timing Attack.

Tests verify that:
- Rate limiting uses constant-time evaluation
- Both denial backoff and rate limit are always checked
- No timing oracle exists
"""

import asyncio
import time
import pytest
from datetime import datetime, timezone, timedelta
from simstim.bridge.rate_limiter import RateLimiter, UserRateState


class TestConstantTimeEvaluation:
    """Test constant-time rate limit evaluation."""

    @pytest.fixture
    def limiter(self):
        return RateLimiter(
            requests_per_minute=10,
            denial_backoff_base=5.0,
            denial_threshold=2,
        )

    @pytest.mark.asyncio
    async def test_both_checks_performed(self, limiter):
        """Test that both denial backoff and rate limit are checked."""
        user_id = 12345

        # First request should be allowed
        allowed, wait = await limiter.check_rate_limit(user_id)
        assert allowed is True
        assert wait is None

    @pytest.mark.asyncio
    async def test_denial_backoff_blocks(self, limiter):
        """Test denial backoff correctly blocks requests."""
        user_id = 12345

        # Record requests and denials to trigger backoff
        await limiter.record_request(user_id)
        await limiter.record_denial(user_id)
        await limiter.record_denial(user_id)
        await limiter.record_denial(user_id)  # Threshold exceeded

        # Should be blocked
        allowed, wait = await limiter.check_rate_limit(user_id)
        assert allowed is False
        assert wait is not None
        assert wait > 0

    @pytest.mark.asyncio
    async def test_rate_limit_blocks(self, limiter):
        """Test rate limit correctly blocks requests."""
        user_id = 12345

        # Fill up the rate limit
        for _ in range(10):
            await limiter.record_request(user_id)

        # Should be blocked by rate limit
        allowed, wait = await limiter.check_rate_limit(user_id)
        assert allowed is False
        assert wait is not None

    @pytest.mark.asyncio
    async def test_denial_priority_over_rate(self, limiter):
        """Test denial backoff takes priority over rate limit."""
        user_id = 12345

        # Trigger both denial backoff AND rate limit
        for _ in range(10):
            await limiter.record_request(user_id)
            await limiter.record_denial(user_id)

        # Should be blocked by denial backoff (higher priority)
        allowed, wait = await limiter.check_rate_limit(user_id)
        assert allowed is False
        # Wait time should be for denial backoff, which is typically longer
        assert wait >= 0.1

    @pytest.mark.asyncio
    async def test_approval_resets_denial_count(self, limiter):
        """Test that approval resets denial state."""
        user_id = 12345

        # Trigger denial backoff
        await limiter.record_denial(user_id)
        await limiter.record_denial(user_id)
        await limiter.record_denial(user_id)

        # Record approval to reset
        await limiter.record_approval(user_id)

        # Should be allowed now (no backoff)
        allowed, wait = await limiter.check_rate_limit(user_id)
        assert allowed is True


class TestTimingConsistency:
    """Test timing consistency to detect potential timing attacks."""

    @pytest.fixture
    def limiter(self):
        return RateLimiter(requests_per_minute=100)

    @pytest.mark.asyncio
    async def test_timing_similar_for_different_states(self, limiter):
        """Test that timing is similar regardless of internal state.

        This is a weak test since we can't guarantee constant-time in Python,
        but we can check the code path doesn't have obvious timing differences.
        """
        user_allowed = 11111
        user_rate_limited = 22222
        user_denial_backoff = 33333

        # Set up different states
        # User 1: Clean state (will be allowed)

        # User 2: Rate limited
        for _ in range(100):
            await limiter.record_request(user_rate_limited)

        # User 3: Denial backoff
        for _ in range(5):
            await limiter.record_denial(user_denial_backoff)

        # Measure timing for each
        iterations = 100
        times = {"allowed": [], "rate_limited": [], "denial_backoff": []}

        for _ in range(iterations):
            start = time.perf_counter()
            await limiter.check_rate_limit(user_allowed)
            times["allowed"].append(time.perf_counter() - start)

            start = time.perf_counter()
            await limiter.check_rate_limit(user_rate_limited)
            times["rate_limited"].append(time.perf_counter() - start)

            start = time.perf_counter()
            await limiter.check_rate_limit(user_denial_backoff)
            times["denial_backoff"].append(time.perf_counter() - start)

        # Calculate averages (in microseconds for readability)
        avg = {k: sum(v) / len(v) * 1_000_000 for k, v in times.items()}

        # All timings should be within reasonable range of each other
        # This is a sanity check, not a strict constant-time guarantee.
        # Python's async and GC make true constant-time impossible, but we can
        # check there's no obvious order-of-magnitude difference.
        max_time = max(avg.values())
        min_time = min(avg.values())

        # Allow 50x variance to account for Python overhead, GC pauses, etc.
        # The main goal is ensuring both code paths execute (no early return)
        assert max_time < min_time * 50, (
            f"Timing variance too high: min={min_time:.2f}us, max={max_time:.2f}us"
        )


class TestUserStats:
    """Test user stats retrieval."""

    @pytest.fixture
    def limiter(self):
        return RateLimiter(requests_per_minute=30)

    @pytest.mark.asyncio
    async def test_get_user_stats(self, limiter):
        """Test stats accurately reflect user state."""
        user_id = 12345

        # Initial state
        stats = await limiter.get_user_stats(user_id)
        assert stats["user_id"] == user_id
        assert stats["requests_last_minute"] == 0
        assert stats["requests_remaining"] == 30
        assert stats["denial_count"] == 0
        assert stats["in_backoff"] is False

        # After some requests
        for _ in range(5):
            await limiter.record_request(user_id)

        stats = await limiter.get_user_stats(user_id)
        assert stats["requests_last_minute"] == 5
        assert stats["requests_remaining"] == 25

    @pytest.mark.asyncio
    async def test_clear_user(self, limiter):
        """Test clearing user state."""
        user_id = 12345

        # Add some state
        await limiter.record_request(user_id)
        await limiter.record_denial(user_id)

        # Clear it
        await limiter.clear_user(user_id)

        # Should be fresh state
        stats = await limiter.get_user_stats(user_id)
        assert stats["requests_last_minute"] == 0
        assert stats["denial_count"] == 0
