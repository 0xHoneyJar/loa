"""One log line is `<timestamp> <LEVEL> <message>`.

The timestamp is ISO-8601 (`2026-10-15T09:30:00Z`, `2026-10-15T11:30:00+02:00`,
fractional seconds allowed); a timestamp without an offset is UTC.
"""
from dataclasses import dataclass
from datetime import datetime, timezone

LEVELS = ("DEBUG", "INFO", "WARN", "ERROR")


@dataclass(frozen=True)
class Record:
    when: datetime  # always timezone-aware
    level: str
    message: str
    raw: str


def parse_timestamp(text: str) -> datetime:
    """Parse a record timestamp; raises ValueError when it is not ISO-8601."""
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    when = datetime.fromisoformat(text)
    if when.tzinfo is None:
        when = when.replace(tzinfo=timezone.utc)
    return when


def parse_line(line: str):
    """Return a Record, or None when the line is not a well-formed log line."""
    raw = line.rstrip("\n")
    parts = raw.split(" ", 2)
    if len(parts) < 2 or parts[1] not in LEVELS:
        return None
    try:
        when = parse_timestamp(parts[0])
    except ValueError:
        return None
    return Record(when=when, level=parts[1], message=parts[2] if len(parts) == 3 else "", raw=raw)
