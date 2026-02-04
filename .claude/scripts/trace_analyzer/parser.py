"""
Trajectory Parser - JSONL streaming parser with session detection.

Primary path: Line-by-line JSONL parsing with json.loads()
Optional path: ijson for JSON array format files
"""

from __future__ import annotations

import json
import logging
from datetime import datetime, timedelta
from pathlib import Path
from typing import Generator, Any

from .models import TrajectoryEntry, ParseResult, SessionInfo

logger = logging.getLogger(__name__)

# Safety guards
MAX_ENTRIES = 10000
MAX_FILE_SIZE_MB = 50
DEFAULT_SESSION_GAP_MINUTES = 30


class TrajectoryParser:
    """
    Streaming JSONL trajectory parser with session boundary detection.

    Primary implementation uses line-by-line json.loads() for JSONL files.
    Optional ijson support for JSON array format files.
    """

    def __init__(
        self,
        session_gap_minutes: int = DEFAULT_SESSION_GAP_MINUTES,
        max_entries: int = MAX_ENTRIES,
        max_file_size_mb: int = MAX_FILE_SIZE_MB,
    ):
        self.session_gap_minutes = session_gap_minutes
        self.max_entries = max_entries
        self.max_file_size_bytes = max_file_size_mb * 1024 * 1024
        self._ijson_available = self._check_ijson()

    def _check_ijson(self) -> bool:
        """Check if ijson is available for JSON array streaming."""
        try:
            import ijson
            return True
        except ImportError:
            logger.info("ijson not available, using JSONL parser only")
            return False

    def parse(
        self,
        path: str | Path,
        session_id: str | None = None,
        time_window_hours: int = 24,
        timeout_seconds: float | None = None,
    ) -> ParseResult:
        """
        Parse trajectory file with optional session and time filtering.

        Args:
            path: Path to trajectory JSONL file
            session_id: Optional session ID filter (primary correlation signal)
            time_window_hours: Hours of history to include
            timeout_seconds: Maximum time for parsing

        Returns:
            ParseResult with entries and session info
        """
        import time
        start_time = time.time()

        path = Path(path)
        if not path.exists():
            return ParseResult(
                entries=[],
                session_info=SessionInfo(confidence="low", reason="file_not_found"),
                corrupt_lines=0,
                total_lines=0,
                parser_used="none",
            )

        # Check file size
        file_size = path.stat().st_size
        if file_size > self.max_file_size_bytes:
            logger.warning(f"File too large: {file_size} bytes > {self.max_file_size_bytes}")
            return ParseResult(
                entries=[],
                session_info=SessionInfo(confidence="low", reason="file_too_large"),
                corrupt_lines=0,
                total_lines=0,
                parser_used="none",
            )

        # Calculate time cutoff (timezone-aware)
        from datetime import timezone
        cutoff_time = datetime.now(timezone.utc) - timedelta(hours=time_window_hours)

        entries: list[TrajectoryEntry] = []
        corrupt_lines = 0
        total_lines = 0
        parser_used = "jsonl"

        try:
            for entry in self._stream_jsonl(path, timeout_seconds, start_time):
                total_lines += 1

                if entry is None:
                    corrupt_lines += 1
                    continue

                # Apply session filter (primary signal)
                if session_id and entry.session_id != session_id:
                    continue

                # Apply time filter (handle both aware and naive timestamps)
                if entry.timestamp:
                    entry_ts = entry.timestamp
                    # Make timestamp timezone-aware if it isn't
                    if entry_ts.tzinfo is None:
                        from datetime import timezone
                        entry_ts = entry_ts.replace(tzinfo=timezone.utc)
                    if entry_ts < cutoff_time:
                        continue

                entries.append(entry)

                # Safety guard
                if len(entries) >= self.max_entries:
                    logger.warning(f"Max entries reached: {self.max_entries}")
                    break

                # Timeout check
                if timeout_seconds and (time.time() - start_time) > timeout_seconds:
                    raise TimeoutError("parser")

        except TimeoutError:
            raise
        except Exception as e:
            logger.error(f"Parse error: {e}")

        # Detect session boundaries and confidence
        session_info = self._analyze_sessions(entries, session_id)

        return ParseResult(
            entries=entries,
            session_info=session_info,
            corrupt_lines=corrupt_lines,
            total_lines=total_lines,
            parser_used=parser_used,
        )

    def _stream_jsonl(
        self,
        path: Path,
        timeout_seconds: float | None,
        start_time: float,
    ) -> Generator[TrajectoryEntry | None, None, None]:
        """Stream entries from JSONL file line by line."""
        import time

        with open(path, "r", encoding="utf-8") as f:
            for line_num, line in enumerate(f, 1):
                # Timeout check
                if timeout_seconds and (time.time() - start_time) > timeout_seconds:
                    raise TimeoutError("parser")

                line = line.strip()
                if not line:
                    continue

                try:
                    data = json.loads(line)
                    yield TrajectoryEntry.model_validate(data)
                except json.JSONDecodeError as e:
                    logger.debug(f"Line {line_num}: JSON decode error: {e}")
                    yield None
                except Exception as e:
                    logger.debug(f"Line {line_num}: Validation error: {e}")
                    yield None

    def _analyze_sessions(
        self,
        entries: list[TrajectoryEntry],
        filter_session_id: str | None,
    ) -> SessionInfo:
        """Analyze session boundaries and determine confidence."""
        if not entries:
            return SessionInfo(confidence="low", reason="no_entries")

        # If filtering by session_id, high confidence
        if filter_session_id:
            return SessionInfo(
                confidence="high",
                reason="session_id_filter",
                session_ids=[filter_session_id],
            )

        # Collect unique session IDs
        session_ids = list(set(e.session_id for e in entries if e.session_id))

        if len(session_ids) == 1:
            return SessionInfo(
                confidence="high",
                reason="single_session",
                session_ids=session_ids,
            )

        if len(session_ids) > 1:
            logger.warning(f"Multiple sessions detected: {session_ids}")
            return SessionInfo(
                confidence="medium",
                reason="multiple_sessions",
                session_ids=session_ids,
            )

        # No session IDs - use timestamp gap heuristic
        return self._detect_sessions_by_timestamp(entries)

    def _detect_sessions_by_timestamp(
        self,
        entries: list[TrajectoryEntry],
    ) -> SessionInfo:
        """Detect session boundaries using timestamp gaps."""
        if not entries:
            return SessionInfo(confidence="low", reason="no_entries")

        # Sort by timestamp
        sorted_entries = sorted(
            [e for e in entries if e.timestamp],
            key=lambda e: e.timestamp,
        )

        if len(sorted_entries) < 2:
            return SessionInfo(
                confidence="medium",
                reason="single_entry_heuristic",
            )

        # Count gaps larger than threshold
        gap_threshold = timedelta(minutes=self.session_gap_minutes)
        session_boundaries = 0

        for i in range(1, len(sorted_entries)):
            gap = sorted_entries[i].timestamp - sorted_entries[i - 1].timestamp
            if gap > gap_threshold:
                session_boundaries += 1

        if session_boundaries == 0:
            return SessionInfo(
                confidence="medium",
                reason="no_gaps_heuristic",
            )

        return SessionInfo(
            confidence="low",
            reason=f"gap_heuristic_{session_boundaries + 1}_sessions",
        )


def discover_trajectory_path() -> Path | None:
    """Auto-discover the most recent trajectory file."""
    trajectory_dir = Path("grimoires/loa/a2a/trajectory")
    if not trajectory_dir.exists():
        return None

    # Find most recent JSONL file
    jsonl_files = list(trajectory_dir.glob("*.jsonl"))
    if not jsonl_files:
        return None

    # Sort by modification time, most recent first
    jsonl_files.sort(key=lambda p: p.stat().st_mtime, reverse=True)
    return jsonl_files[0]
