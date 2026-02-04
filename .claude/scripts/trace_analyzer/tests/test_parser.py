"""Tests for the TrajectoryParser."""

import json
import tempfile
from datetime import datetime, timezone, timedelta
from pathlib import Path

import pytest

from trace_analyzer.parser import TrajectoryParser, DEFAULT_SESSION_GAP_MINUTES
from trace_analyzer.models import TrajectoryEntry, SessionConfidence


@pytest.fixture
def parser():
    """Create a parser instance."""
    return TrajectoryParser()


@pytest.fixture
def temp_trajectory(tmp_path):
    """Create a temporary trajectory file."""
    def _create(entries: list[dict]) -> Path:
        path = tmp_path / "trajectory.jsonl"
        with open(path, "w") as f:
            for entry in entries:
                f.write(json.dumps(entry) + "\n")
        return path
    return _create


class TestTrajectoryParser:
    """Test TrajectoryParser basic functionality."""

    def test_parse_empty_file(self, parser, tmp_path):
        """Test parsing an empty file."""
        path = tmp_path / "empty.jsonl"
        path.write_text("")

        result = parser.parse(path)

        assert len(result.entries) == 0
        assert result.corrupt_lines == 0
        assert result.total_lines == 0

    def test_parse_single_entry(self, parser, temp_trajectory):
        """Test parsing a single valid entry."""
        now = datetime.now(timezone.utc).isoformat()
        entries = [
            {"timestamp": now, "session_id": "test-123", "entry_type": "skill"}
        ]
        path = temp_trajectory(entries)

        result = parser.parse(path)

        assert len(result.entries) == 1
        assert result.entries[0].session_id == "test-123"
        assert result.corrupt_lines == 0

    def test_parse_multiple_entries(self, parser, temp_trajectory):
        """Test parsing multiple entries."""
        now = datetime.now(timezone.utc)
        entries = [
            {"timestamp": (now - timedelta(minutes=i)).isoformat(), "session_id": "test", "entry_type": "skill"}
            for i in range(10)
        ]
        path = temp_trajectory(entries)

        result = parser.parse(path)

        assert len(result.entries) == 10
        assert result.corrupt_lines == 0
        assert result.total_lines == 10


class TestCorruptLineHandling:
    """Test handling of corrupt JSONL lines."""

    def test_skip_corrupt_lines(self, parser, temp_trajectory):
        """Test that corrupt lines are skipped and counted."""
        now = datetime.now(timezone.utc).isoformat()
        path = temp_trajectory([])

        # Write mixed content
        with open(path, "w") as f:
            f.write(json.dumps({"timestamp": now, "session_id": "test", "entry_type": "skill"}) + "\n")
            f.write("not valid json\n")
            f.write(json.dumps({"timestamp": now, "session_id": "test", "entry_type": "tool"}) + "\n")
            f.write("{incomplete\n")

        result = parser.parse(path)

        assert len(result.entries) == 2
        assert result.corrupt_lines == 2
        assert result.total_lines == 4

    def test_empty_lines_ignored(self, parser, temp_trajectory):
        """Test that empty lines are ignored."""
        now = datetime.now(timezone.utc).isoformat()
        path = temp_trajectory([])

        with open(path, "w") as f:
            f.write(json.dumps({"timestamp": now, "session_id": "test", "entry_type": "skill"}) + "\n")
            f.write("\n")
            f.write("   \n")
            f.write(json.dumps({"timestamp": now, "session_id": "test", "entry_type": "tool"}) + "\n")

        result = parser.parse(path)

        assert len(result.entries) == 2
        # Empty lines are skipped, not counted as corrupt
        assert result.corrupt_lines == 0


class TestSessionBoundaryDetection:
    """Test session boundary detection."""

    def test_single_session_high_confidence(self, parser, temp_trajectory):
        """Test that single session has high confidence."""
        now = datetime.now(timezone.utc)
        entries = [
            {"timestamp": (now - timedelta(minutes=i)).isoformat(), "session_id": "single-session", "entry_type": "skill"}
            for i in range(5)
        ]
        path = temp_trajectory(entries)

        result = parser.parse(path)

        assert result.session_info.confidence == "high"
        assert "single_session" in result.session_info.reason

    def test_multiple_sessions_medium_confidence(self, parser, temp_trajectory):
        """Test that multiple sessions have medium confidence."""
        now = datetime.now(timezone.utc)
        entries = [
            {"timestamp": (now - timedelta(minutes=0)).isoformat(), "session_id": "session-1", "entry_type": "skill"},
            {"timestamp": (now - timedelta(minutes=1)).isoformat(), "session_id": "session-2", "entry_type": "skill"},
            {"timestamp": (now - timedelta(minutes=2)).isoformat(), "session_id": "session-1", "entry_type": "skill"},
        ]
        path = temp_trajectory(entries)

        result = parser.parse(path)

        assert result.session_info.confidence == "medium"
        assert "multiple_sessions" in result.session_info.reason

    def test_session_id_filter(self, parser, temp_trajectory):
        """Test filtering by session ID."""
        now = datetime.now(timezone.utc)
        entries = [
            {"timestamp": (now - timedelta(minutes=0)).isoformat(), "session_id": "target", "entry_type": "skill"},
            {"timestamp": (now - timedelta(minutes=1)).isoformat(), "session_id": "other", "entry_type": "skill"},
            {"timestamp": (now - timedelta(minutes=2)).isoformat(), "session_id": "target", "entry_type": "skill"},
        ]
        path = temp_trajectory(entries)

        result = parser.parse(path, session_id="target")

        assert len(result.entries) == 2
        assert all(e.session_id == "target" for e in result.entries)
        assert result.session_info.confidence == "high"

    def test_timestamp_gap_heuristic(self, parser, temp_trajectory):
        """Test session detection by timestamp gaps when no session_id."""
        now = datetime.now(timezone.utc)
        entries = [
            # First session
            {"timestamp": (now - timedelta(hours=2)).isoformat(), "entry_type": "skill"},
            {"timestamp": (now - timedelta(hours=2, minutes=5)).isoformat(), "entry_type": "skill"},
            # Gap > 30 min
            # Second session
            {"timestamp": (now - timedelta(minutes=5)).isoformat(), "entry_type": "skill"},
            {"timestamp": now.isoformat(), "entry_type": "skill"},
        ]
        path = temp_trajectory(entries)

        result = parser.parse(path)

        assert result.session_info.confidence == "low"
        assert "gap_heuristic" in result.session_info.reason


class TestTimeWindowFiltering:
    """Test time window filtering."""

    def test_filter_old_entries(self, parser, temp_trajectory):
        """Test that entries outside time window are filtered."""
        now = datetime.now(timezone.utc)
        entries = [
            {"timestamp": now.isoformat(), "session_id": "test", "entry_type": "skill"},
            {"timestamp": (now - timedelta(hours=12)).isoformat(), "session_id": "test", "entry_type": "skill"},
            {"timestamp": (now - timedelta(hours=48)).isoformat(), "session_id": "test", "entry_type": "skill"},
        ]
        path = temp_trajectory(entries)

        result = parser.parse(path, time_window_hours=24)

        assert len(result.entries) == 2  # Only entries within 24 hours

    def test_larger_time_window(self, parser, temp_trajectory):
        """Test with larger time window includes more entries."""
        now = datetime.now(timezone.utc)
        entries = [
            {"timestamp": now.isoformat(), "session_id": "test", "entry_type": "skill"},
            {"timestamp": (now - timedelta(hours=48)).isoformat(), "session_id": "test", "entry_type": "skill"},
            {"timestamp": (now - timedelta(hours=72)).isoformat(), "session_id": "test", "entry_type": "skill"},
        ]
        path = temp_trajectory(entries)

        # Default 24h window
        result_24h = parser.parse(path, time_window_hours=24)
        # Larger 96h window (72 hours + buffer)
        result_96h = parser.parse(path, time_window_hours=96)

        # Larger window should include more entries
        assert len(result_96h.entries) >= len(result_24h.entries)


class TestSafetyGuards:
    """Test safety guards like max entries and file size."""

    def test_max_entries_guard(self, parser, temp_trajectory):
        """Test that max entries limit is enforced."""
        parser = TrajectoryParser(max_entries=5)
        now = datetime.now(timezone.utc)
        entries = [
            {"timestamp": (now - timedelta(seconds=i)).isoformat(), "session_id": "test", "entry_type": "skill"}
            for i in range(10)
        ]
        path = temp_trajectory(entries)

        result = parser.parse(path)

        assert len(result.entries) == 5

    def test_file_too_large(self, parser, tmp_path):
        """Test handling of files exceeding size limit."""
        parser = TrajectoryParser(max_file_size_mb=0)  # 0 MB limit
        path = tmp_path / "large.jsonl"
        path.write_text('{"test": true}\n')

        result = parser.parse(path)

        assert len(result.entries) == 0
        assert result.session_info.reason == "file_too_large"


class TestTimezoneHandling:
    """Test handling of various timestamp formats."""

    def test_utc_timestamps(self, parser, temp_trajectory):
        """Test UTC timestamps with Z suffix."""
        entries = [
            {"timestamp": "2026-02-04T12:00:00Z", "session_id": "test", "entry_type": "skill"},
        ]
        path = temp_trajectory(entries)

        result = parser.parse(path, time_window_hours=24*365)  # Large window

        assert len(result.entries) == 1

    def test_offset_timestamps(self, parser, temp_trajectory):
        """Test timestamps with offset."""
        entries = [
            {"timestamp": "2026-02-04T12:00:00+00:00", "session_id": "test", "entry_type": "skill"},
            {"timestamp": "2026-02-04T14:00:00+02:00", "session_id": "test", "entry_type": "skill"},
        ]
        path = temp_trajectory(entries)

        result = parser.parse(path, time_window_hours=24*365)

        assert len(result.entries) == 2

    def test_naive_timestamps(self, parser, temp_trajectory):
        """Test naive timestamps (no timezone)."""
        entries = [
            {"timestamp": "2026-02-04T12:00:00", "session_id": "test", "entry_type": "skill"},
        ]
        path = temp_trajectory(entries)

        result = parser.parse(path, time_window_hours=24*365)

        assert len(result.entries) == 1
