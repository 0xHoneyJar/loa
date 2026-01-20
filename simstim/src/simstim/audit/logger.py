"""Structured audit logger for Simstim.

Writes all events to a JSONL file for audit trail and analytics.
"""

from __future__ import annotations

import json
import logging
from dataclasses import dataclass, field, asdict
from datetime import datetime, timezone
from enum import Enum
from pathlib import Path
from typing import Any


logger = logging.getLogger(__name__)


class EventType(Enum):
    """Types of audit events."""

    # Permission events
    PERMISSION_REQUESTED = "permission_requested"
    PERMISSION_APPROVED = "permission_approved"
    PERMISSION_DENIED = "permission_denied"
    PERMISSION_AUTO_APPROVED = "permission_auto_approved"
    PERMISSION_TIMEOUT = "permission_timeout"

    # Policy events
    POLICY_EVALUATED = "policy_evaluated"
    POLICY_MATCHED = "policy_matched"

    # Phase events
    PHASE_STARTED = "phase_started"
    PHASE_COMPLETED = "phase_completed"
    PHASE_TRANSITION = "phase_transition"

    # System events
    SIMSTIM_STARTED = "simstim_started"
    SIMSTIM_STOPPED = "simstim_stopped"
    LOA_STARTED = "loa_started"
    LOA_STOPPED = "loa_stopped"
    LOA_EXIT = "loa_exit"

    # Telegram events
    TELEGRAM_CONNECTED = "telegram_connected"
    TELEGRAM_DISCONNECTED = "telegram_disconnected"
    TELEGRAM_RECONNECTED = "telegram_reconnected"
    TELEGRAM_MESSAGE_SENT = "telegram_message_sent"
    TELEGRAM_CALLBACK = "telegram_callback"

    # Error events
    ERROR = "error"
    WARNING = "warning"


@dataclass
class AuditEvent:
    """A single audit log entry."""

    event_type: EventType
    timestamp: datetime = field(default_factory=lambda: datetime.now(timezone.utc))
    session_id: str = ""
    request_id: str | None = None
    user_id: int | None = None
    action: str | None = None
    target: str | None = None
    risk_level: str | None = None
    policy_name: str | None = None
    phase: str | None = None
    metadata: dict[str, Any] = field(default_factory=dict)
    error: str | None = None

    def to_dict(self) -> dict[str, Any]:
        """Convert to dictionary for JSON serialization."""
        result = {
            "timestamp": self.timestamp.isoformat(),
            "event_type": self.event_type.value,
            "session_id": self.session_id,
        }

        # Add optional fields only if set
        if self.request_id:
            result["request_id"] = self.request_id
        if self.user_id is not None:
            result["user_id"] = self.user_id
        if self.action:
            result["action"] = self.action
        if self.target:
            result["target"] = self.target
        if self.risk_level:
            result["risk_level"] = self.risk_level
        if self.policy_name:
            result["policy_name"] = self.policy_name
        if self.phase:
            result["phase"] = self.phase
        if self.metadata:
            result["metadata"] = self.metadata
        if self.error:
            result["error"] = self.error

        return result


class AuditLogger:
    """Structured JSONL audit logger.

    Writes events to a JSONL file with one JSON object per line.
    Thread-safe for concurrent writes.
    """

    def __init__(
        self,
        log_path: Path | str,
        session_id: str | None = None,
        max_file_size_mb: int = 100,
        rotate_count: int = 5,
    ) -> None:
        """Initialize audit logger.

        Args:
            log_path: Path to the JSONL log file
            session_id: Unique session identifier (auto-generated if not provided)
            max_file_size_mb: Maximum log file size before rotation
            rotate_count: Number of rotated files to keep
        """
        self._log_path = Path(log_path)
        self._session_id = session_id or self._generate_session_id()
        self._max_size = max_file_size_mb * 1024 * 1024
        self._rotate_count = rotate_count
        self._event_count = 0

        # Ensure directory exists
        self._log_path.parent.mkdir(parents=True, exist_ok=True)

        logger.info(
            "Audit logger initialized",
            extra={
                "log_path": str(self._log_path),
                "session_id": self._session_id,
            },
        )

    def _generate_session_id(self) -> str:
        """Generate a unique session ID."""
        from uuid import uuid4
        return f"sim-{datetime.now(timezone.utc).strftime('%Y%m%d-%H%M%S')}-{str(uuid4())[:6]}"

    def log(self, event: AuditEvent) -> None:
        """Log an audit event.

        Args:
            event: Event to log
        """
        # Set session ID if not already set
        if not event.session_id:
            event.session_id = self._session_id

        # Check for rotation
        self._maybe_rotate()

        # Write event
        try:
            with open(self._log_path, "a", encoding="utf-8") as f:
                f.write(json.dumps(event.to_dict()) + "\n")
            self._event_count += 1
        except OSError as e:
            logger.error(f"Failed to write audit log: {e}")

    def log_permission_request(
        self,
        request_id: str,
        action: str,
        target: str,
        risk_level: str,
        context: str | None = None,
    ) -> None:
        """Log a permission request event."""
        self.log(AuditEvent(
            event_type=EventType.PERMISSION_REQUESTED,
            request_id=request_id,
            action=action,
            target=target,
            risk_level=risk_level,
            metadata={"context": context} if context else {},
        ))

    def log_permission_response(
        self,
        request_id: str,
        approved: bool,
        user_id: int,
        auto_approved: bool = False,
        policy_name: str | None = None,
        response_time_ms: int | None = None,
    ) -> None:
        """Log a permission response event."""
        if auto_approved:
            if policy_name == "timeout":
                event_type = EventType.PERMISSION_TIMEOUT
            else:
                event_type = EventType.PERMISSION_AUTO_APPROVED
        else:
            event_type = EventType.PERMISSION_APPROVED if approved else EventType.PERMISSION_DENIED

        metadata = {}
        if response_time_ms is not None:
            metadata["response_time_ms"] = response_time_ms

        self.log(AuditEvent(
            event_type=event_type,
            request_id=request_id,
            user_id=user_id,
            policy_name=policy_name,
            metadata=metadata,
        ))

    def log_policy_evaluation(
        self,
        request_id: str,
        action: str,
        target: str,
        risk_level: str,
        matched: bool,
        policy_name: str | None = None,
        reason: str | None = None,
    ) -> None:
        """Log a policy evaluation event."""
        self.log(AuditEvent(
            event_type=EventType.POLICY_MATCHED if matched else EventType.POLICY_EVALUATED,
            request_id=request_id,
            action=action,
            target=target,
            risk_level=risk_level,
            policy_name=policy_name,
            metadata={"reason": reason} if reason else {},
        ))

    def log_phase_transition(
        self,
        phase: str,
        metadata: dict[str, Any] | None = None,
    ) -> None:
        """Log a phase transition event."""
        self.log(AuditEvent(
            event_type=EventType.PHASE_TRANSITION,
            phase=phase,
            metadata=metadata or {},
        ))

    def log_system_event(
        self,
        event_type: EventType,
        metadata: dict[str, Any] | None = None,
    ) -> None:
        """Log a system event."""
        self.log(AuditEvent(
            event_type=event_type,
            metadata=metadata or {},
        ))

    def log_error(
        self,
        error: str,
        context: dict[str, Any] | None = None,
    ) -> None:
        """Log an error event."""
        self.log(AuditEvent(
            event_type=EventType.ERROR,
            error=error,
            metadata=context or {},
        ))

    def log_warning(
        self,
        warning: str,
        context: dict[str, Any] | None = None,
    ) -> None:
        """Log a warning event."""
        self.log(AuditEvent(
            event_type=EventType.WARNING,
            error=warning,
            metadata=context or {},
        ))

    def _maybe_rotate(self) -> None:
        """Rotate log file if it exceeds max size."""
        if not self._log_path.exists():
            return

        try:
            if self._log_path.stat().st_size >= self._max_size:
                self._rotate()
        except OSError:
            pass

    def _rotate(self) -> None:
        """Rotate log files."""
        # Remove oldest if at limit
        oldest = self._log_path.with_suffix(f".jsonl.{self._rotate_count}")
        if oldest.exists():
            oldest.unlink()

        # Shift existing rotated files
        for i in range(self._rotate_count - 1, 0, -1):
            current = self._log_path.with_suffix(f".jsonl.{i}")
            next_file = self._log_path.with_suffix(f".jsonl.{i + 1}")
            if current.exists():
                current.rename(next_file)

        # Rotate current file
        if self._log_path.exists():
            self._log_path.rename(self._log_path.with_suffix(".jsonl.1"))

        logger.info("Audit log rotated")

    @property
    def session_id(self) -> str:
        """Get current session ID."""
        return self._session_id

    @property
    def event_count(self) -> int:
        """Get number of events logged in this session."""
        return self._event_count

    @property
    def log_path(self) -> Path:
        """Get log file path."""
        return self._log_path
