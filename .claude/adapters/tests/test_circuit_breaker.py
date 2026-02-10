"""Tests for circuit breaker state management (Sprint 3, SDD §4.2.6)."""

import json
import os
import sys
import time
from pathlib import Path
from unittest.mock import patch

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from loa_cheval.routing.circuit_breaker import (
    CLOSED,
    HALF_OPEN,
    OPEN,
    check_state,
    cleanup_stale_files,
    increment_probe,
    record_failure,
    record_success,
)


# Default config for tests
CB_CONFIG = {
    "routing": {
        "circuit_breaker": {
            "failure_threshold": 3,
            "reset_timeout_seconds": 5,
            "half_open_max_probes": 1,
            "count_window_seconds": 60,
        }
    }
}


class TestCheckState:
    """Circuit breaker state checking."""

    def test_default_closed(self, tmp_path):
        """No state file → CLOSED."""
        state = check_state("openai", CB_CONFIG, str(tmp_path))
        assert state == CLOSED

    def test_reads_existing_state(self, tmp_path):
        """Reads state from file."""
        state_file = tmp_path / "circuit-breaker-openai.json"
        state_file.write_text(json.dumps({
            "provider": "openai",
            "state": OPEN,
            "failure_count": 5,
            "opened_at": time.time() + 100,  # Far future — won't expire
        }))
        state = check_state("openai", CB_CONFIG, str(tmp_path))
        assert state == OPEN

    def test_open_transitions_to_half_open(self, tmp_path):
        """OPEN → HALF_OPEN when reset_timeout expires."""
        state_file = tmp_path / "circuit-breaker-openai.json"
        state_file.write_text(json.dumps({
            "provider": "openai",
            "state": OPEN,
            "failure_count": 5,
            "opened_at": time.time() - 10,  # 10s ago (> 5s timeout)
        }))
        state = check_state("openai", CB_CONFIG, str(tmp_path))
        assert state == HALF_OPEN

    def test_corrupted_file_returns_closed(self, tmp_path):
        """Corrupted state file → default CLOSED."""
        state_file = tmp_path / "circuit-breaker-openai.json"
        state_file.write_text("not json")
        state = check_state("openai", CB_CONFIG, str(tmp_path))
        assert state == CLOSED


class TestRecordFailure:
    """Failure recording and state transitions."""

    def test_accumulates_failures(self, tmp_path):
        """Failures accumulate toward threshold."""
        run_dir = str(tmp_path)
        record_failure("openai", CB_CONFIG, run_dir)
        record_failure("openai", CB_CONFIG, run_dir)

        # Still CLOSED (threshold=3, only 2 failures)
        state = check_state("openai", CB_CONFIG, run_dir)
        assert state == CLOSED

    def test_trips_at_threshold(self, tmp_path):
        """CLOSED → OPEN at failure_threshold."""
        run_dir = str(tmp_path)
        for _ in range(3):
            record_failure("openai", CB_CONFIG, run_dir)

        state = check_state("openai", CB_CONFIG, run_dir)
        assert state == OPEN

    def test_half_open_failure_reopens(self, tmp_path):
        """HALF_OPEN → OPEN on probe failure."""
        run_dir = str(tmp_path)
        state_file = tmp_path / "circuit-breaker-openai.json"
        state_file.write_text(json.dumps({
            "provider": "openai",
            "state": HALF_OPEN,
            "failure_count": 3,
            "opened_at": time.time() - 10,
            "half_open_probes": 0,
        }))

        new_state = record_failure("openai", CB_CONFIG, run_dir)
        assert new_state == OPEN

    def test_count_window_resets(self, tmp_path):
        """Failures outside count_window are reset."""
        run_dir = str(tmp_path)
        config = {
            "routing": {
                "circuit_breaker": {
                    "failure_threshold": 3,
                    "reset_timeout_seconds": 5,
                    "count_window_seconds": 1,  # Very short window
                }
            }
        }

        record_failure("openai", config, run_dir)
        record_failure("openai", config, run_dir)

        # Simulate time passing beyond count_window
        state_file = tmp_path / "circuit-breaker-openai.json"
        data = json.loads(state_file.read_text())
        data["last_failure_ts"] = time.time() - 5  # 5s ago (> 1s window)
        state_file.write_text(json.dumps(data))

        # This failure should reset counter to 1 (within new window)
        new_state = record_failure("openai", config, run_dir)
        assert new_state == CLOSED  # Not tripped — only 1 failure in window


class TestRecordSuccess:
    """Success recording and state transitions."""

    def test_half_open_success_closes(self, tmp_path):
        """HALF_OPEN → CLOSED on successful probe."""
        run_dir = str(tmp_path)
        state_file = tmp_path / "circuit-breaker-openai.json"
        state_file.write_text(json.dumps({
            "provider": "openai",
            "state": HALF_OPEN,
            "failure_count": 3,
            "opened_at": time.time() - 10,
            "half_open_probes": 1,
        }))

        new_state = record_success("openai", CB_CONFIG, run_dir)
        assert new_state == CLOSED

    def test_closed_success_resets_count(self, tmp_path):
        """Success in CLOSED resets failure count."""
        run_dir = str(tmp_path)
        state_file = tmp_path / "circuit-breaker-openai.json"
        state_file.write_text(json.dumps({
            "provider": "openai",
            "state": CLOSED,
            "failure_count": 2,
            "last_failure_ts": time.time(),
        }))

        record_success("openai", CB_CONFIG, run_dir)

        data = json.loads(state_file.read_text())
        assert data["failure_count"] == 0

    def test_success_on_no_state(self, tmp_path):
        """Success with no state file → CLOSED (no-op)."""
        new_state = record_success("openai", CB_CONFIG, str(tmp_path))
        assert new_state == CLOSED


class TestFullLifecycle:
    """Complete state machine lifecycle tests."""

    def test_closed_open_halfopen_closed(self, tmp_path):
        """Full cycle: CLOSED → OPEN → HALF_OPEN → CLOSED."""
        run_dir = str(tmp_path)
        config = {
            "routing": {
                "circuit_breaker": {
                    "failure_threshold": 2,
                    "reset_timeout_seconds": 1,
                    "half_open_max_probes": 1,
                    "count_window_seconds": 60,
                }
            }
        }

        # Start CLOSED
        assert check_state("openai", config, run_dir) == CLOSED

        # 2 failures → OPEN
        record_failure("openai", config, run_dir)
        new_state = record_failure("openai", config, run_dir)
        assert new_state == OPEN

        # Verify state file says OPEN
        state_file = tmp_path / "circuit-breaker-openai.json"
        data = json.loads(state_file.read_text())
        assert data["state"] == OPEN

        # Manually set opened_at to past to simulate timeout
        data["opened_at"] = time.time() - 5
        state_file.write_text(json.dumps(data))

        # Now check_state should transition OPEN → HALF_OPEN
        state = check_state("openai", config, run_dir)
        assert state == HALF_OPEN

        # Probe succeeds → CLOSED
        record_success("openai", config, run_dir)
        assert check_state("openai", config, run_dir) == CLOSED

    def test_halfopen_probe_fail_reopens(self, tmp_path):
        """HALF_OPEN probe fails → back to OPEN."""
        run_dir = str(tmp_path)
        config = {
            "routing": {
                "circuit_breaker": {
                    "failure_threshold": 1,
                    "reset_timeout_seconds": 1,
                    "half_open_max_probes": 1,
                    "count_window_seconds": 60,
                }
            }
        }

        # Trip to OPEN
        new_state = record_failure("openai", config, run_dir)
        assert new_state == OPEN

        # Manually set opened_at to past to enable HALF_OPEN transition
        state_file = tmp_path / "circuit-breaker-openai.json"
        data = json.loads(state_file.read_text())
        data["opened_at"] = time.time() - 5
        state_file.write_text(json.dumps(data))

        # Check transitions to HALF_OPEN
        assert check_state("openai", config, run_dir) == HALF_OPEN

        # Probe fails → back to OPEN
        record_failure("openai", config, run_dir)

        # Read state file directly (check_state might auto-transition again)
        data = json.loads(state_file.read_text())
        assert data["state"] == OPEN


class TestCleanupStaleFiles:
    """Stale file cleanup tests."""

    def test_removes_old_files(self, tmp_path):
        """Files older than max_age are removed."""
        run_dir = str(tmp_path)

        # Create an old file
        old_file = tmp_path / "circuit-breaker-old-provider.json"
        old_file.write_text("{}")
        # Set mtime to 48 hours ago
        old_time = time.time() - (48 * 3600)
        os.utime(old_file, (old_time, old_time))

        # Create a recent file
        new_file = tmp_path / "circuit-breaker-new-provider.json"
        new_file.write_text("{}")

        removed = cleanup_stale_files(run_dir, max_age_hours=24)
        assert removed == 1
        assert not old_file.exists()
        assert new_file.exists()

    def test_ignores_non_cb_files(self, tmp_path):
        """Only removes circuit-breaker-* files."""
        run_dir = str(tmp_path)

        other_file = tmp_path / "something-else.json"
        other_file.write_text("{}")
        old_time = time.time() - (48 * 3600)
        os.utime(other_file, (old_time, old_time))

        removed = cleanup_stale_files(run_dir, max_age_hours=24)
        assert removed == 0
        assert other_file.exists()

    def test_empty_directory(self, tmp_path):
        removed = cleanup_stale_files(str(tmp_path))
        assert removed == 0

    def test_nonexistent_directory(self):
        removed = cleanup_stale_files("/nonexistent/path")
        assert removed == 0
