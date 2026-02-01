"""Permission queue for managing pending permission requests.

Provides async queue with timeout support and response futures.
"""

from __future__ import annotations

import asyncio
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import TYPE_CHECKING
from uuid import uuid4

if TYPE_CHECKING:
    from simstim.bridge.stdout_parser import ActionType, RiskLevel


@dataclass
class PermissionRequest:
    """A pending permission request."""

    action: ActionType
    target: str
    context: str
    risk_level: RiskLevel
    id: str = field(default_factory=lambda: str(uuid4())[:8])
    created_at: datetime = field(default_factory=lambda: datetime.now(timezone.utc))
    telegram_message_id: int | None = None
    timeout_task: asyncio.Task[None] | None = None


@dataclass
class PermissionResponse:
    """Response to a permission request."""

    request_id: str
    approved: bool
    responded_by: int  # Telegram user ID (0 for system/timeout)
    response_time: datetime = field(default_factory=lambda: datetime.now(timezone.utc))
    auto_approved: bool = False
    policy_name: str | None = None


class PermissionQueue:
    """Manages pending permission requests with timeout support."""

    def __init__(self, timeout_seconds: int, default_action: str) -> None:
        """Initialize permission queue.

        Args:
            timeout_seconds: Timeout duration for requests
            default_action: Action to take on timeout ("approve" or "deny")
        """
        self._pending: dict[str, PermissionRequest] = {}
        self._response_futures: dict[str, asyncio.Future[PermissionResponse]] = {}
        self._timeout_seconds = timeout_seconds
        self._default_action = default_action

    async def add(self, request: PermissionRequest) -> PermissionResponse:
        """Add request to queue and wait for response.

        Args:
            request: Permission request to add

        Returns:
            Response when available (from user or timeout)
        """
        self._pending[request.id] = request

        loop = asyncio.get_event_loop()
        future: asyncio.Future[PermissionResponse] = loop.create_future()
        self._response_futures[request.id] = future

        # Start timeout handler
        request.timeout_task = asyncio.create_task(
            self._timeout_handler(request.id),
            name=f"timeout-{request.id}",
        )

        try:
            return await future
        finally:
            self._cleanup(request.id)

    async def respond(self, response: PermissionResponse) -> bool:
        """Submit response for a pending request.

        Args:
            response: Response to submit

        Returns:
            True if response was accepted, False if request not found or already handled
        """
        if response.request_id not in self._pending:
            return False

        future = self._response_futures.get(response.request_id)
        if future and not future.done():
            future.set_result(response)
            return True
        return False

    async def _timeout_handler(self, request_id: str) -> None:
        """Handle timeout for a request.

        Args:
            request_id: ID of request to timeout
        """
        await asyncio.sleep(self._timeout_seconds)

        if request_id in self._pending:
            future = self._response_futures.get(request_id)
            if future and not future.done():
                response = PermissionResponse(
                    request_id=request_id,
                    approved=(self._default_action == "approve"),
                    responded_by=0,  # System
                    auto_approved=True,
                    policy_name="timeout",
                )
                future.set_result(response)

    def _cleanup(self, request_id: str) -> None:
        """Clean up request state.

        Args:
            request_id: ID of request to clean up
        """
        request = self._pending.pop(request_id, None)
        if request and request.timeout_task:
            request.timeout_task.cancel()
        self._response_futures.pop(request_id, None)

    @property
    def pending_count(self) -> int:
        """Number of pending requests."""
        return len(self._pending)

    def get_pending(self, request_id: str) -> PermissionRequest | None:
        """Get a pending request by ID.

        Args:
            request_id: ID of request to retrieve

        Returns:
            Request if found, None otherwise
        """
        return self._pending.get(request_id)

    def get_all_pending(self) -> list[PermissionRequest]:
        """Get all pending requests.

        Returns:
            List of all pending requests
        """
        return list(self._pending.values())

    async def cancel_all(self) -> int:
        """Cancel all pending requests.

        Returns:
            Number of requests cancelled
        """
        count = len(self._pending)
        request_ids = list(self._pending.keys())

        for request_id in request_ids:
            future = self._response_futures.get(request_id)
            if future and not future.done():
                response = PermissionResponse(
                    request_id=request_id,
                    approved=False,
                    responded_by=0,
                    auto_approved=True,
                    policy_name="cancelled",
                )
                future.set_result(response)

        return count
