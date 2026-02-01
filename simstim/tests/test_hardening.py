"""Unit tests for hardening components (Sprint 4)."""

from __future__ import annotations

import asyncio
import pytest
from datetime import datetime, timezone, timedelta
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import AsyncMock, MagicMock

from simstim.audit.logger import AuditLogger, AuditEvent, EventType
from simstim.bridge.offline_queue import (
    OfflineQueue,
    QueuedEvent,
    QueuedEventType,
    ReconnectionManager,
)
from simstim.bridge.rate_limiter import RateLimiter


class TestAuditLogger:
    """Tests for AuditLogger."""

    def test_init_creates_directory(self, tmp_path):
        """Should create log directory if it doesn't exist."""
        log_path = tmp_path / "subdir" / "audit.jsonl"
        logger = AuditLogger(log_path)
        assert log_path.parent.exists()

    def test_generates_session_id(self, tmp_path):
        """Should generate unique session IDs."""
        log_path = tmp_path / "audit.jsonl"
        logger1 = AuditLogger(log_path)
        logger2 = AuditLogger(log_path)
        assert logger1.session_id.startswith("sim-")
        assert logger1.session_id != logger2.session_id

    def test_log_writes_jsonl(self, tmp_path):
        """Should write events as JSONL."""
        log_path = tmp_path / "audit.jsonl"
        logger = AuditLogger(log_path)

        event = AuditEvent(
            event_type=EventType.PERMISSION_REQUESTED,
            request_id="test-123",
            action="bash_execute",
            target="test.sh",
        )
        logger.log(event)

        assert log_path.exists()
        content = log_path.read_text()
        assert "permission_requested" in content
        assert "test-123" in content

    def test_log_increments_count(self, tmp_path):
        """Should track event count."""
        log_path = tmp_path / "audit.jsonl"
        logger = AuditLogger(log_path)

        assert logger.event_count == 0
        logger.log(AuditEvent(event_type=EventType.SIMSTIM_STARTED))
        assert logger.event_count == 1
        logger.log(AuditEvent(event_type=EventType.SIMSTIM_STOPPED))
        assert logger.event_count == 2

    def test_log_permission_request(self, tmp_path):
        """Should log permission request events."""
        log_path = tmp_path / "audit.jsonl"
        logger = AuditLogger(log_path)

        logger.log_permission_request(
            request_id="req-1",
            action="file_edit",
            target="src/main.ts",
            risk_level="low",
            context="Some context",
        )

        content = log_path.read_text()
        assert "permission_requested" in content
        assert "file_edit" in content
        assert "src/main.ts" in content

    def test_log_permission_response_approved(self, tmp_path):
        """Should log approved permission response."""
        log_path = tmp_path / "audit.jsonl"
        logger = AuditLogger(log_path)

        logger.log_permission_response(
            request_id="req-1",
            approved=True,
            user_id=12345,
        )

        content = log_path.read_text()
        assert "permission_approved" in content
        assert "12345" in content

    def test_log_permission_response_auto_approved(self, tmp_path):
        """Should log auto-approved permission response."""
        log_path = tmp_path / "audit.jsonl"
        logger = AuditLogger(log_path)

        logger.log_permission_response(
            request_id="req-1",
            approved=True,
            user_id=0,
            auto_approved=True,
            policy_name="test-policy",
        )

        content = log_path.read_text()
        assert "permission_auto_approved" in content
        assert "test-policy" in content

    def test_log_permission_response_timeout(self, tmp_path):
        """Should log timeout events."""
        log_path = tmp_path / "audit.jsonl"
        logger = AuditLogger(log_path)

        logger.log_permission_response(
            request_id="req-1",
            approved=False,
            user_id=0,
            auto_approved=True,
            policy_name="timeout",
        )

        content = log_path.read_text()
        assert "permission_timeout" in content

    def test_log_error(self, tmp_path):
        """Should log error events."""
        log_path = tmp_path / "audit.jsonl"
        logger = AuditLogger(log_path)

        logger.log_error("Test error", {"detail": "more info"})

        content = log_path.read_text()
        assert "error" in content
        assert "Test error" in content


class TestAuditEvent:
    """Tests for AuditEvent dataclass."""

    def test_to_dict_required_fields(self):
        """Should include required fields in dict."""
        event = AuditEvent(
            event_type=EventType.SIMSTIM_STARTED,
        )
        d = event.to_dict()

        assert "timestamp" in d
        assert d["event_type"] == "simstim_started"
        assert "session_id" in d

    def test_to_dict_optional_fields_omitted(self):
        """Should omit None optional fields."""
        event = AuditEvent(
            event_type=EventType.SIMSTIM_STARTED,
        )
        d = event.to_dict()

        assert "request_id" not in d
        assert "user_id" not in d
        assert "action" not in d

    def test_to_dict_optional_fields_included(self):
        """Should include set optional fields."""
        event = AuditEvent(
            event_type=EventType.PERMISSION_REQUESTED,
            request_id="test-123",
            action="bash_execute",
        )
        d = event.to_dict()

        assert d["request_id"] == "test-123"
        assert d["action"] == "bash_execute"


class TestOfflineQueue:
    """Tests for OfflineQueue."""

    @pytest.mark.asyncio
    async def test_enqueue_event(self):
        """Should enqueue events."""
        queue = OfflineQueue()

        event = QueuedEvent(
            event_type=QueuedEventType.PERMISSION_REQUEST,
            data={"test": "data"},
        )
        result = await queue.enqueue(event)

        assert result is True
        assert queue.queue_size == 1

    @pytest.mark.asyncio
    async def test_enqueue_respects_max_size(self):
        """Should drop oldest when full."""
        queue = OfflineQueue(max_size=2)

        for i in range(3):
            event = QueuedEvent(
                event_type=QueuedEventType.GENERIC_MESSAGE,
                data={"index": i},
            )
            await queue.enqueue(event)

        assert queue.queue_size == 2

    @pytest.mark.asyncio
    async def test_flush_processes_events(self):
        """Should flush events through handler."""
        queue = OfflineQueue()

        for i in range(3):
            event = QueuedEvent(
                event_type=QueuedEventType.GENERIC_MESSAGE,
                data={"index": i},
            )
            await queue.enqueue(event)

        processed = []

        async def handler(event):
            processed.append(event.data["index"])
            return True

        count = await queue.flush(handler)

        assert count == 3
        assert len(processed) == 3
        assert queue.queue_size == 0

    @pytest.mark.asyncio
    async def test_flush_handles_failures(self):
        """Should keep failed events in queue."""
        queue = OfflineQueue()

        for i in range(3):
            event = QueuedEvent(
                event_type=QueuedEventType.GENERIC_MESSAGE,
                data={"index": i},
            )
            await queue.enqueue(event)

        async def handler(event):
            # Fail on middle event
            return event.data["index"] != 1

        count = await queue.flush(handler)

        assert count == 2
        assert queue.queue_size == 1

    def test_offline_state_tracking(self):
        """Should track offline state."""
        queue = OfflineQueue()

        assert not queue.is_offline
        assert queue.offline_duration is None

        queue.set_offline()
        assert queue.is_offline
        assert queue.offline_duration is not None

        queue.set_online()
        assert not queue.is_offline


class TestReconnectionManager:
    """Tests for ReconnectionManager."""

    @pytest.mark.asyncio
    async def test_successful_reconnection(self):
        """Should succeed on first attempt if connect succeeds."""
        manager = ReconnectionManager()
        success_called = False

        async def connect():
            return True

        async def on_success():
            nonlocal success_called
            success_called = True

        result = await manager.attempt_reconnect(connect, on_success=on_success)

        assert result is True
        assert success_called
        assert manager.successful_connections == 1

    @pytest.mark.asyncio
    async def test_retries_on_failure(self):
        """Should retry with backoff on failure."""
        manager = ReconnectionManager(
            initial_delay=0.01,  # Fast for testing
            max_delay=0.05,
        )

        attempts = 0

        async def connect():
            nonlocal attempts
            attempts += 1
            return attempts >= 3  # Succeed on 3rd attempt

        result = await manager.attempt_reconnect(connect)

        assert result is True
        assert attempts == 3

    @pytest.mark.asyncio
    async def test_max_attempts_exceeded(self):
        """Should stop after max attempts."""
        manager = ReconnectionManager(
            initial_delay=0.01,
            max_attempts=2,
        )

        async def connect():
            return False

        failure_called = False

        async def on_failure(e):
            nonlocal failure_called
            failure_called = True

        result = await manager.attempt_reconnect(connect, on_failure=on_failure)

        assert result is False
        assert failure_called

    def test_reset_on_success(self):
        """Should reset delay after success."""
        manager = ReconnectionManager(initial_delay=1.0)

        # Simulate some attempts
        manager._current_delay = 10.0
        manager._attempt_count = 5
        manager._reset()

        assert manager.current_delay == 1.0
        assert manager.attempt_count == 0


class TestRateLimiter:
    """Tests for RateLimiter."""

    @pytest.mark.asyncio
    async def test_allows_under_limit(self):
        """Should allow requests under limit."""
        limiter = RateLimiter(requests_per_minute=10)

        allowed, wait = await limiter.check_rate_limit(123)

        assert allowed is True
        assert wait is None

    @pytest.mark.asyncio
    async def test_blocks_over_limit(self):
        """Should block requests over limit."""
        limiter = RateLimiter(requests_per_minute=2)

        # Record 2 requests
        await limiter.record_request(123)
        await limiter.record_request(123)

        allowed, wait = await limiter.check_rate_limit(123)

        assert allowed is False
        assert wait is not None
        assert wait > 0

    @pytest.mark.asyncio
    async def test_denial_backoff(self):
        """Should apply backoff after repeated denials."""
        limiter = RateLimiter(
            denial_threshold=2,
            denial_backoff_base=1.0,
        )

        # Record denials
        await limiter.record_denial(123)
        await limiter.record_denial(123)

        allowed, wait = await limiter.check_rate_limit(123)

        assert allowed is False
        assert wait is not None
        assert wait > 0

    @pytest.mark.asyncio
    async def test_approval_resets_denial_count(self):
        """Should reset denial count on approval."""
        limiter = RateLimiter(denial_threshold=2)

        await limiter.record_denial(123)
        await limiter.record_denial(123)
        await limiter.record_approval(123)

        stats = await limiter.get_user_stats(123)

        assert stats["denial_count"] == 0
        assert stats["in_backoff"] is False

    @pytest.mark.asyncio
    async def test_user_stats(self):
        """Should return accurate user stats."""
        limiter = RateLimiter(requests_per_minute=10)

        await limiter.record_request(123)
        await limiter.record_request(123)
        await limiter.record_denial(123)

        stats = await limiter.get_user_stats(123)

        assert stats["user_id"] == 123
        assert stats["requests_last_minute"] == 2
        assert stats["requests_remaining"] == 8
        assert stats["denial_count"] == 1

    @pytest.mark.asyncio
    async def test_per_user_isolation(self):
        """Should track users separately."""
        limiter = RateLimiter(requests_per_minute=2)

        await limiter.record_request(111)
        await limiter.record_request(111)
        await limiter.record_request(222)

        allowed_111, _ = await limiter.check_rate_limit(111)
        allowed_222, _ = await limiter.check_rate_limit(222)

        assert allowed_111 is False  # At limit
        assert allowed_222 is True  # Under limit
