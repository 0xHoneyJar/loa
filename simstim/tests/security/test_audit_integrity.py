"""Security tests for SIMSTIM-008: Audit Log Tampering.

Tests verify that:
- Audit logs are HMAC-signed
- Hash chain links entries together
- Tampered entries are detected
- Missing entries break the chain
- Log verification correctly validates integrity
"""

import json
import os
import tempfile
import pytest
from pathlib import Path
from simstim.audit.logger import (
    AuditLogger,
    AuditEvent,
    EventType,
    verify_audit_log,
)


@pytest.fixture
def temp_log_path():
    """Create a temporary log file path."""
    with tempfile.NamedTemporaryFile(suffix=".jsonl", delete=False) as f:
        yield Path(f.name)
    # Cleanup
    Path(f.name).unlink(missing_ok=True)


@pytest.fixture
def hmac_key():
    """Generate a test HMAC key."""
    return os.urandom(32)


class TestHMACSignedEntries:
    """Test HMAC signature generation."""

    def test_entries_have_hmac_signature(self, temp_log_path, hmac_key):
        """Test that log entries include HMAC signatures."""
        logger = AuditLogger(temp_log_path, hmac_key=hmac_key)

        logger.log(AuditEvent(event_type=EventType.SIMSTIM_STARTED))

        with open(temp_log_path, "r") as f:
            entry = json.loads(f.readline())

        assert "hmac" in entry
        assert len(entry["hmac"]) == 64  # SHA256 hex digest

    def test_entries_have_prev_hash(self, temp_log_path, hmac_key):
        """Test that log entries include previous hash for chaining."""
        logger = AuditLogger(temp_log_path, hmac_key=hmac_key)

        logger.log(AuditEvent(event_type=EventType.SIMSTIM_STARTED))
        logger.log(AuditEvent(event_type=EventType.LOA_STARTED))

        with open(temp_log_path, "r") as f:
            entry1 = json.loads(f.readline())
            entry2 = json.loads(f.readline())

        # First entry has empty prev_hash
        assert entry1["prev_hash"] == ""

        # Second entry references first entry's signature
        assert entry2["prev_hash"] == entry1["hmac"]

    def test_different_keys_produce_different_signatures(self, temp_log_path):
        """Test that different HMAC keys produce different signatures."""
        key1 = os.urandom(32)
        key2 = os.urandom(32)

        logger1 = AuditLogger(temp_log_path, hmac_key=key1, session_id="test")
        logger1.log(AuditEvent(event_type=EventType.SIMSTIM_STARTED))

        with open(temp_log_path, "r") as f:
            sig1 = json.loads(f.readline())["hmac"]

        # Clear and write with different key
        temp_log_path.unlink()

        logger2 = AuditLogger(temp_log_path, hmac_key=key2, session_id="test")
        logger2.log(AuditEvent(event_type=EventType.SIMSTIM_STARTED))

        with open(temp_log_path, "r") as f:
            sig2 = json.loads(f.readline())["hmac"]

        assert sig1 != sig2


class TestHashChain:
    """Test hash chain integrity."""

    def test_chain_links_all_entries(self, temp_log_path, hmac_key):
        """Test that each entry links to the previous one."""
        logger = AuditLogger(temp_log_path, hmac_key=hmac_key)

        # Log multiple events
        for i in range(5):
            logger.log(AuditEvent(
                event_type=EventType.PERMISSION_REQUESTED,
                request_id=f"req-{i}",
            ))

        entries = []
        with open(temp_log_path, "r") as f:
            for line in f:
                entries.append(json.loads(line))

        # Verify chain
        for i in range(1, len(entries)):
            assert entries[i]["prev_hash"] == entries[i-1]["hmac"], (
                f"Chain broken at entry {i}"
            )


class TestLogVerification:
    """Test log verification function."""

    def test_verify_valid_log(self, temp_log_path, hmac_key):
        """Test verification passes for valid log."""
        logger = AuditLogger(temp_log_path, hmac_key=hmac_key)

        logger.log(AuditEvent(event_type=EventType.SIMSTIM_STARTED))
        logger.log(AuditEvent(event_type=EventType.LOA_STARTED))
        logger.log(AuditEvent(event_type=EventType.PERMISSION_REQUESTED))

        valid, errors = verify_audit_log(temp_log_path, hmac_key)

        assert valid is True
        assert len(errors) == 0

    def test_verify_empty_log(self, temp_log_path, hmac_key):
        """Test verification passes for empty/missing log."""
        # File doesn't exist yet
        valid, errors = verify_audit_log(temp_log_path, hmac_key)
        assert valid is True
        assert len(errors) == 0

    def test_verify_detects_tampered_event(self, temp_log_path, hmac_key):
        """Test verification detects tampered event data."""
        logger = AuditLogger(temp_log_path, hmac_key=hmac_key)
        logger.log(AuditEvent(event_type=EventType.SIMSTIM_STARTED))
        logger.log(AuditEvent(event_type=EventType.PERMISSION_APPROVED))

        # Tamper with the log
        with open(temp_log_path, "r") as f:
            lines = f.readlines()

        entry = json.loads(lines[1])
        entry["event"]["event_type"] = "permission_denied"  # Change the event type

        with open(temp_log_path, "w") as f:
            f.write(lines[0])  # Keep first line
            f.write(json.dumps(entry) + "\n")  # Write tampered second line

        valid, errors = verify_audit_log(temp_log_path, hmac_key)

        assert valid is False
        assert len(errors) > 0
        assert any("Invalid HMAC" in e for e in errors)

    def test_verify_detects_deleted_entry(self, temp_log_path, hmac_key):
        """Test verification detects deleted entries (chain break)."""
        logger = AuditLogger(temp_log_path, hmac_key=hmac_key)
        logger.log(AuditEvent(event_type=EventType.SIMSTIM_STARTED))
        logger.log(AuditEvent(event_type=EventType.PERMISSION_REQUESTED))
        logger.log(AuditEvent(event_type=EventType.PERMISSION_APPROVED))

        # Delete the middle entry
        with open(temp_log_path, "r") as f:
            lines = f.readlines()

        with open(temp_log_path, "w") as f:
            f.write(lines[0])  # First entry
            f.write(lines[2])  # Third entry (skip second)

        valid, errors = verify_audit_log(temp_log_path, hmac_key)

        assert valid is False
        assert any("chain broken" in e.lower() for e in errors)

    def test_verify_detects_wrong_key(self, temp_log_path, hmac_key):
        """Test verification fails with wrong key."""
        logger = AuditLogger(temp_log_path, hmac_key=hmac_key)
        logger.log(AuditEvent(event_type=EventType.SIMSTIM_STARTED))

        wrong_key = os.urandom(32)
        valid, errors = verify_audit_log(temp_log_path, wrong_key)

        assert valid is False
        assert any("Invalid HMAC" in e for e in errors)

    def test_verify_detects_reordered_entries(self, temp_log_path, hmac_key):
        """Test verification detects reordered entries."""
        logger = AuditLogger(temp_log_path, hmac_key=hmac_key)
        logger.log(AuditEvent(event_type=EventType.SIMSTIM_STARTED))
        logger.log(AuditEvent(event_type=EventType.PERMISSION_REQUESTED))
        logger.log(AuditEvent(event_type=EventType.PERMISSION_APPROVED))

        # Swap entries 1 and 2
        with open(temp_log_path, "r") as f:
            lines = f.readlines()

        with open(temp_log_path, "w") as f:
            f.write(lines[0])  # Entry 0
            f.write(lines[2])  # Entry 2 (moved up)
            f.write(lines[1])  # Entry 1 (moved down)

        valid, errors = verify_audit_log(temp_log_path, hmac_key)

        assert valid is False

    def test_verify_detects_malformed_json(self, temp_log_path, hmac_key):
        """Test verification detects malformed JSON."""
        logger = AuditLogger(temp_log_path, hmac_key=hmac_key)
        logger.log(AuditEvent(event_type=EventType.SIMSTIM_STARTED))

        # Append malformed JSON
        with open(temp_log_path, "a") as f:
            f.write("{not valid json\n")

        valid, errors = verify_audit_log(temp_log_path, hmac_key)

        assert valid is False
        assert any("Malformed JSON" in e for e in errors)


class TestKeyManagement:
    """Test HMAC key management."""

    def test_key_from_hex_string(self, temp_log_path):
        """Test key can be provided as hex string."""
        key_bytes = os.urandom(32)
        key_hex = key_bytes.hex()

        logger = AuditLogger(temp_log_path, hmac_key=key_hex)
        logger.log(AuditEvent(event_type=EventType.SIMSTIM_STARTED))

        valid, errors = verify_audit_log(temp_log_path, key_hex)
        assert valid is True

    def test_key_from_env_var(self, temp_log_path, monkeypatch):
        """Test key loaded from environment variable."""
        key_hex = os.urandom(32).hex()
        monkeypatch.setenv("SIMSTIM_AUDIT_KEY", key_hex)

        logger = AuditLogger(temp_log_path)
        logger.log(AuditEvent(event_type=EventType.SIMSTIM_STARTED))

        valid, errors = verify_audit_log(temp_log_path, key_hex)
        assert valid is True

    def test_ephemeral_key_generated(self, temp_log_path, monkeypatch):
        """Test ephemeral key is generated when not provided."""
        monkeypatch.delenv("SIMSTIM_AUDIT_KEY", raising=False)

        # Should not raise, but will log a warning
        logger = AuditLogger(temp_log_path)
        logger.log(AuditEvent(event_type=EventType.SIMSTIM_STARTED))

        # Log file should exist with signed entry
        with open(temp_log_path, "r") as f:
            entry = json.loads(f.readline())
        assert "hmac" in entry


class TestConvenienceMethods:
    """Test audit logger convenience methods still work."""

    def test_log_permission_request(self, temp_log_path, hmac_key):
        """Test log_permission_request produces signed entry."""
        logger = AuditLogger(temp_log_path, hmac_key=hmac_key)
        logger.log_permission_request(
            request_id="req-123",
            action="file_create",
            target="src/main.py",
            risk_level="low",
        )

        valid, errors = verify_audit_log(temp_log_path, hmac_key)
        assert valid is True

    def test_log_error(self, temp_log_path, hmac_key):
        """Test log_error produces signed entry."""
        logger = AuditLogger(temp_log_path, hmac_key=hmac_key)
        logger.log_error("Test error", context={"code": 500})

        valid, errors = verify_audit_log(temp_log_path, hmac_key)
        assert valid is True
