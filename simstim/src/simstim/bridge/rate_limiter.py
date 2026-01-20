"""Rate limiter for Telegram interactions.

Provides per-user rate limiting with backoff for repeated denials.
"""

from __future__ import annotations

import asyncio
from collections import defaultdict
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Dict


@dataclass
class UserRateState:
    """Rate limiting state for a single user."""

    request_times: list[datetime] = field(default_factory=list)
    denial_count: int = 0
    last_denial: datetime | None = None
    backoff_until: datetime | None = None


class RateLimiter:
    """Per-user rate limiter with denial backoff.

    Limits requests per minute and adds additional backoff
    for users who repeatedly deny requests.
    """

    def __init__(
        self,
        requests_per_minute: int = 30,
        denial_backoff_base: float = 5.0,
        denial_backoff_max: float = 300.0,
        denial_threshold: int = 3,
    ) -> None:
        """Initialize rate limiter.

        Args:
            requests_per_minute: Maximum requests per minute per user
            denial_backoff_base: Base backoff seconds after denials
            denial_backoff_max: Maximum backoff seconds
            denial_threshold: Number of denials to trigger backoff
        """
        self._requests_per_minute = requests_per_minute
        self._denial_backoff_base = denial_backoff_base
        self._denial_backoff_max = denial_backoff_max
        self._denial_threshold = denial_threshold

        self._user_states: Dict[int, UserRateState] = defaultdict(UserRateState)
        self._lock = asyncio.Lock()

    async def check_rate_limit(self, user_id: int) -> tuple[bool, float | None]:
        """Check if user is within rate limits.

        Args:
            user_id: Telegram user ID

        Returns:
            Tuple of (allowed, wait_seconds)
            - allowed: True if request is allowed
            - wait_seconds: Seconds to wait if not allowed (None if allowed)
        """
        async with self._lock:
            state = self._user_states[user_id]
            now = datetime.now(timezone.utc)

            # Check denial backoff first
            if state.backoff_until and state.backoff_until > now:
                wait = (state.backoff_until - now).total_seconds()
                return False, wait

            # Prune old request times
            cutoff = now.timestamp() - 60  # 1 minute window
            state.request_times = [
                t for t in state.request_times
                if t.timestamp() > cutoff
            ]

            # Check rate limit
            if len(state.request_times) >= self._requests_per_minute:
                oldest = state.request_times[0]
                wait = 60 - (now.timestamp() - oldest.timestamp())
                return False, max(0.1, wait)

            return True, None

    async def record_request(self, user_id: int) -> None:
        """Record a request for rate limiting.

        Args:
            user_id: Telegram user ID
        """
        async with self._lock:
            state = self._user_states[user_id]
            state.request_times.append(datetime.now(timezone.utc))

    async def record_denial(self, user_id: int) -> None:
        """Record a denial for backoff calculation.

        Args:
            user_id: Telegram user ID
        """
        async with self._lock:
            state = self._user_states[user_id]
            state.denial_count += 1
            state.last_denial = datetime.now(timezone.utc)

            # Apply backoff if threshold exceeded
            if state.denial_count >= self._denial_threshold:
                backoff = min(
                    self._denial_backoff_base * (2 ** (state.denial_count - self._denial_threshold)),
                    self._denial_backoff_max,
                )
                state.backoff_until = datetime.now(timezone.utc)
                # Add backoff seconds manually since timedelta not imported
                from datetime import timedelta
                state.backoff_until = state.backoff_until + timedelta(seconds=backoff)

    async def record_approval(self, user_id: int) -> None:
        """Record an approval to reset denial count.

        Args:
            user_id: Telegram user ID
        """
        async with self._lock:
            state = self._user_states[user_id]
            # Reset denial state on approval
            state.denial_count = 0
            state.backoff_until = None

    async def clear_user(self, user_id: int) -> None:
        """Clear all rate limiting state for a user.

        Args:
            user_id: Telegram user ID
        """
        async with self._lock:
            if user_id in self._user_states:
                del self._user_states[user_id]

    async def get_user_stats(self, user_id: int) -> dict:
        """Get rate limiting stats for a user.

        Args:
            user_id: Telegram user ID

        Returns:
            Dict with rate limit stats
        """
        async with self._lock:
            state = self._user_states[user_id]
            now = datetime.now(timezone.utc)

            # Count recent requests
            cutoff = now.timestamp() - 60
            recent_requests = len([
                t for t in state.request_times
                if t.timestamp() > cutoff
            ])

            return {
                "user_id": user_id,
                "requests_last_minute": recent_requests,
                "requests_remaining": max(0, self._requests_per_minute - recent_requests),
                "denial_count": state.denial_count,
                "in_backoff": state.backoff_until is not None and state.backoff_until > now,
                "backoff_remaining": (
                    (state.backoff_until - now).total_seconds()
                    if state.backoff_until and state.backoff_until > now
                    else 0
                ),
            }
