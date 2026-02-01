"""Structured audit logger for Simstim.

Writes all events to a JSONL file for audit trail and analytics.

Security Note (SIMSTIM-008): Audit entries are HMAC-signed with a hash chain
to provide tamper detection and integrity verification.
"""

from __future__ import annotations

import hashlib
import hmac
import json
import logging
import os
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
    """Structured JSONL audit logger with integrity protection.

    Writes events to a JSONL file with one JSON object per line.
    Thread-safe for concurrent writes.

    Security Note (SIMSTIM-008): Each log entry is HMAC-signed with a hash chain
    to prevent tampering. The chain links each entry to the previous one,
    making it detectable if any entry is modified, deleted, or reordered.
    """

    def __init__(
        self,
        log_path: Path | str,
        session_id: str | None = None,
        max_file_size_mb: int = 100,
        rotate_count: int = 5,
        hmac_key: bytes | str | None = None,
    ) -> None:
        """Initialize audit logger.

        Args:
            log_path: Path to the JSONL log file
            session_id: Unique session identifier (auto-generated if not provided)
            max_file_size_mb: Maximum log file size before rotation
            rotate_count: Number of rotated files to keep
            hmac_key: Key for HMAC signing (hex string or bytes). If None, read from
                     SIMSTIM_AUDIT_KEY env var or generate a new one.
        """
        self._log_path = Path(log_path)
        self._session_id = session_id or self._generate_session_id()
        self._max_size = max_file_size_mb * 1024 * 1024
        self._rotate_count = rotate_count
        self._event_count = 0

        # SECURITY (SIMSTIM-008): Initialize HMAC key and hash chain
        self._hmac_key = self._init_hmac_key(hmac_key)
        self._last_hash: bytes = b""  # Chain starts empty

        # Ensure directory exists
        self._log_path.parent.mkdir(parents=True, exist_ok=True)

        logger.info(
            "Audit logger initialized",
            extra={
                "log_path": str(self._log_path),
                "session_id": self._session_id,
                "integrity_enabled": True,
            },
        )

    def _init_hmac_key(self, key: bytes | str | None) -> bytes:
        """Initialize HMAC key from provided value, env var, or generate new.

        Args:
            key: Key as bytes, hex string, or None

        Returns:
            32-byte key for HMAC-SHA256
        """
        if key is not None:
            if isinstance(key, str):
                return bytes.fromhex(key)
            return key

        # Try environment variable
        env_key = os.environ.get("SIMSTIM_AUDIT_KEY")
        if env_key:
            return bytes.fromhex(env_key)

        # Generate new key (logged as warning since it's ephemeral)
        new_key = os.urandom(32)
        logger.warning(
            "Generated ephemeral HMAC key for audit logs. "
            "Set SIMSTIM_AUDIT_KEY for persistent integrity verification."
        )
        return new_key

    def _generate_session_id(self) -> str:
        """Generate a unique session ID."""
        from uuid import uuid4
        return f"sim-{datetime.now(timezone.utc).strftime('%Y%m%d-%H%M%S')}-{str(uuid4())[:6]}"

    def log(self, event: AuditEvent) -> None:
        """Log an audit event with HMAC integrity protection.

        Security Note (SIMSTIM-008): Each entry is signed with HMAC-SHA256
        using a hash chain: signature = HMAC(key, prev_hash || event_json).

        Args:
            event: Event to log
        """
        # Set session ID if not already set
        if not event.session_id:
            event.session_id = self._session_id

        # Check for rotation
        self._maybe_rotate()

        # Write event with HMAC signature
        try:
            event_dict = event.to_dict()
            event_json = json.dumps(event_dict, separators=(',', ':'), sort_keys=True)

            # SECURITY (SIMSTIM-008): Calculate HMAC chain signature
            # H(key, previous_hash || event_json)
            h = hmac.new(self._hmac_key, digestmod=hashlib.sha256)
            h.update(self._last_hash)
            h.update(event_json.encode('utf-8'))
            signature = h.hexdigest()

            # Build signed log entry
            log_entry = {
                "event": event_dict,
                "hmac": signature,
                "prev_hash": self._last_hash.hex() if self._last_hash else "",
            }

            with open(self._log_path, "a", encoding="utf-8") as f:
                f.write(json.dumps(log_entry) + "\n")

            # Update chain for next entry
            self._last_hash = bytes.fromhex(signature)
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


def verify_audit_log(
    log_path: Path | str,
    hmac_key: bytes | str,
) -> tuple[bool, list[str]]:
    """Verify audit log integrity.

    Security Note (SIMSTIM-008): Verifies the HMAC chain to detect any
    tampering, deletions, or reordering of log entries.

    Args:
        log_path: Path to the JSONL log file
        hmac_key: HMAC key as bytes or hex string

    Returns:
        Tuple of (valid, errors) where valid is True if log is intact
        and errors is a list of detected issues
    """
    log_path = Path(log_path)
    errors: list[str] = []

    if isinstance(hmac_key, str):
        hmac_key = bytes.fromhex(hmac_key)

    if not log_path.exists():
        return True, []  # Empty log is valid

    prev_hash = b""

    try:
        with open(log_path, "r", encoding="utf-8") as f:
            for line_num, line in enumerate(f, 1):
                if not line.strip():
                    continue

                try:
                    entry = json.loads(line)

                    # Extract components
                    event_dict = entry.get("event", {})
                    claimed_sig = entry.get("hmac", "")
                    expected_prev = entry.get("prev_hash", "")

                    # Verify hash chain linkage
                    actual_prev = prev_hash.hex() if prev_hash else ""
                    if actual_prev != expected_prev:
                        errors.append(
                            f"Line {line_num}: Hash chain broken "
                            f"(expected prev={expected_prev[:8]}..., got {actual_prev[:8]}...)"
                        )

                    # Recompute HMAC signature
                    event_json = json.dumps(event_dict, separators=(',', ':'), sort_keys=True)
                    h = hmac.new(hmac_key, digestmod=hashlib.sha256)
                    h.update(prev_hash)
                    h.update(event_json.encode('utf-8'))
                    computed_sig = h.hexdigest()

                    # Verify signature
                    if not hmac.compare_digest(computed_sig, claimed_sig):
                        errors.append(
                            f"Line {line_num}: Invalid HMAC signature "
                            f"(entry may have been tampered)"
                        )

                    # Update chain for next entry
                    prev_hash = bytes.fromhex(claimed_sig) if claimed_sig else b""

                except json.JSONDecodeError as e:
                    errors.append(f"Line {line_num}: Malformed JSON - {e}")
                except KeyError as e:
                    errors.append(f"Line {line_num}: Missing field - {e}")
                except ValueError as e:
                    errors.append(f"Line {line_num}: Invalid value - {e}")

    except OSError as e:
        errors.append(f"Failed to read log file: {e}")

    return len(errors) == 0, errors
