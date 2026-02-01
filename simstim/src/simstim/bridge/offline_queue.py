"""Offline queue for handling network disconnections.

Queues events during Telegram disconnection and flushes
when connection is restored.
"""

from __future__ import annotations

import asyncio
import logging
from dataclasses import dataclass, field
from datetime import datetime, timezone
from enum import Enum
from typing import Any, Callable, Coroutine


logger = logging.getLogger(__name__)


class QueuedEventType(Enum):
    """Types of events that can be queued."""

    PERMISSION_REQUEST = "permission_request"
    PHASE_NOTIFICATION = "phase_notification"
    STATUS_MESSAGE = "status_message"
    GENERIC_MESSAGE = "generic_message"


@dataclass
class QueuedEvent:
    """An event queued during disconnection."""

    event_type: QueuedEventType
    timestamp: datetime = field(default_factory=lambda: datetime.now(timezone.utc))
    data: dict[str, Any] = field(default_factory=dict)
    priority: int = 0  # Higher = more important


class OfflineQueue:
    """Manages events during Telegram disconnection.

    Events are queued when offline and flushed in order
    when connection is restored.
    """

    def __init__(
        self,
        max_size: int = 100,
        max_age_seconds: int = 3600,
    ) -> None:
        """Initialize offline queue.

        Args:
            max_size: Maximum number of events to queue
            max_age_seconds: Maximum age of events before discard
        """
        self._queue: list[QueuedEvent] = []
        self._max_size = max_size
        self._max_age = max_age_seconds
        self._is_offline = False
        self._offline_since: datetime | None = None
        self._lock = asyncio.Lock()

    async def enqueue(self, event: QueuedEvent) -> bool:
        """Add event to offline queue.

        Args:
            event: Event to queue

        Returns:
            True if event was queued, False if queue full
        """
        async with self._lock:
            # Prune old events first
            self._prune_old_events()

            if len(self._queue) >= self._max_size:
                logger.warning("Offline queue full, dropping oldest event")
                self._queue.pop(0)

            self._queue.append(event)
            return True

    async def flush(
        self,
        handler: Callable[[QueuedEvent], Coroutine[Any, Any, bool]],
    ) -> int:
        """Flush all queued events through handler.

        Args:
            handler: Async function to process each event

        Returns:
            Number of events successfully processed
        """
        async with self._lock:
            # Prune old events first
            self._prune_old_events()

            if not self._queue:
                return 0

            # Sort by priority (highest first)
            sorted_events = sorted(
                self._queue,
                key=lambda e: (-e.priority, e.timestamp),
            )

            processed = 0
            remaining = []

            for event in sorted_events:
                try:
                    success = await handler(event)
                    if success:
                        processed += 1
                    else:
                        remaining.append(event)
                except Exception as e:
                    logger.error(f"Failed to process queued event: {e}")
                    remaining.append(event)

            self._queue = remaining
            logger.info(f"Flushed {processed} events from offline queue")
            return processed

    def _prune_old_events(self) -> int:
        """Remove events older than max age.

        Returns:
            Number of events pruned
        """
        if not self._queue:
            return 0

        now = datetime.now(timezone.utc)
        original_count = len(self._queue)

        self._queue = [
            e for e in self._queue
            if (now - e.timestamp).total_seconds() < self._max_age
        ]

        pruned = original_count - len(self._queue)
        if pruned > 0:
            logger.info(f"Pruned {pruned} expired events from offline queue")
        return pruned

    def set_offline(self) -> None:
        """Mark as offline."""
        if not self._is_offline:
            self._is_offline = True
            self._offline_since = datetime.now(timezone.utc)
            logger.info("Marked as offline")

    def set_online(self) -> None:
        """Mark as online."""
        if self._is_offline:
            self._is_offline = False
            duration = None
            if self._offline_since:
                duration = (datetime.now(timezone.utc) - self._offline_since).total_seconds()
            self._offline_since = None
            logger.info(
                "Marked as online",
                extra={"offline_duration_seconds": duration},
            )

    @property
    def is_offline(self) -> bool:
        """Check if currently offline."""
        return self._is_offline

    @property
    def queue_size(self) -> int:
        """Get current queue size."""
        return len(self._queue)

    @property
    def offline_duration(self) -> float | None:
        """Get duration of current offline period in seconds."""
        if not self._is_offline or not self._offline_since:
            return None
        return (datetime.now(timezone.utc) - self._offline_since).total_seconds()


class ReconnectionManager:
    """Manages reconnection with exponential backoff.

    Handles automatic reconnection attempts with increasing
    delays between retries.
    """

    def __init__(
        self,
        initial_delay: float = 1.0,
        max_delay: float = 300.0,
        backoff_factor: float = 2.0,
        max_attempts: int = 0,  # 0 = unlimited
        jitter: float = 0.1,
    ) -> None:
        """Initialize reconnection manager.

        Args:
            initial_delay: Initial delay between attempts (seconds)
            max_delay: Maximum delay between attempts (seconds)
            backoff_factor: Multiplier for exponential backoff
            max_attempts: Maximum reconnection attempts (0 = unlimited)
            jitter: Random jitter factor (0-1)
        """
        self._initial_delay = initial_delay
        self._max_delay = max_delay
        self._backoff_factor = backoff_factor
        self._max_attempts = max_attempts
        self._jitter = jitter

        self._current_delay = initial_delay
        self._attempt_count = 0
        self._is_reconnecting = False
        self._last_attempt: datetime | None = None
        self._successful_connections = 0

    async def attempt_reconnect(
        self,
        connect_fn: Callable[[], Coroutine[Any, Any, bool]],
        on_success: Callable[[], Coroutine[Any, Any, None]] | None = None,
        on_failure: Callable[[Exception | None], Coroutine[Any, Any, None]] | None = None,
    ) -> bool:
        """Attempt reconnection with backoff.

        Args:
            connect_fn: Async function that attempts connection
            on_success: Callback on successful connection
            on_failure: Callback on failed connection

        Returns:
            True if connection successful
        """
        if self._is_reconnecting:
            return False

        self._is_reconnecting = True

        try:
            while True:
                self._attempt_count += 1
                self._last_attempt = datetime.now(timezone.utc)

                if self._max_attempts > 0 and self._attempt_count > self._max_attempts:
                    logger.error(f"Max reconnection attempts ({self._max_attempts}) exceeded")
                    if on_failure:
                        await on_failure(None)
                    return False

                logger.info(
                    f"Reconnection attempt {self._attempt_count}",
                    extra={"delay": self._current_delay},
                )

                try:
                    success = await connect_fn()
                    if success:
                        self._successful_connections += 1
                        self._reset()
                        if on_success:
                            await on_success()
                        return True
                except Exception as e:
                    logger.warning(f"Reconnection attempt failed: {e}")

                # Calculate next delay with jitter
                import random
                jitter_range = self._current_delay * self._jitter
                jitter = random.uniform(-jitter_range, jitter_range)
                delay = min(self._current_delay + jitter, self._max_delay)

                logger.info(f"Waiting {delay:.1f}s before next attempt")
                await asyncio.sleep(delay)

                # Increase delay for next attempt
                self._current_delay = min(
                    self._current_delay * self._backoff_factor,
                    self._max_delay,
                )

        finally:
            self._is_reconnecting = False

    def _reset(self) -> None:
        """Reset reconnection state after successful connection."""
        self._current_delay = self._initial_delay
        self._attempt_count = 0

    def cancel(self) -> None:
        """Cancel ongoing reconnection attempts."""
        self._is_reconnecting = False
        logger.info("Reconnection cancelled")

    @property
    def is_reconnecting(self) -> bool:
        """Check if currently reconnecting."""
        return self._is_reconnecting

    @property
    def attempt_count(self) -> int:
        """Get current attempt count."""
        return self._attempt_count

    @property
    def current_delay(self) -> float:
        """Get current delay between attempts."""
        return self._current_delay

    @property
    def successful_connections(self) -> int:
        """Get total successful connections."""
        return self._successful_connections
