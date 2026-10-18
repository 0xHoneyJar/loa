"""Instants as whole UTC minutes since 1970-01-01T00:00Z."""
from datetime import datetime, timedelta, timezone

EPOCH = datetime(1970, 1, 1, tzinfo=timezone.utc)
NAIVE_EPOCH = datetime(1970, 1, 1)
MINUTE = timedelta(minutes=1)


def require_aware(value):
    if not isinstance(value, datetime) or value.tzinfo is None or value.utcoffset() is None:
        raise ValueError(f"expected a timezone-aware datetime, got {value!r}")
    return value


def floor_minutes(instant):
    """The whole minute at or before ``instant`` (an aware datetime)."""
    return (require_aware(instant) - EPOCH) // MINUTE


def ceil_minutes(instant):
    """The whole minute at or after ``instant``."""
    delta = require_aware(instant) - EPOCH
    whole = delta // MINUTE
    return whole if delta == whole * MINUTE else whole + 1


def to_instant(minutes):
    return EPOCH + minutes * MINUTE


def wall_minutes(wall):
    """A naive wall-clock datetime as minutes since 1970-01-01T00:00 (seconds dropped)."""
    return (wall.replace(second=0, microsecond=0) - NAIVE_EPOCH) // MINUTE


def to_wall(minutes):
    return NAIVE_EPOCH + minutes * MINUTE
