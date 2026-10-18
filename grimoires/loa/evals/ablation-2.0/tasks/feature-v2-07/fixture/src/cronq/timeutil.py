"""Instants, offsets and their text forms.

An *instant* is an integer number of seconds since 1970-01-01T00:00:00 UTC.
An *offset* is a signed integer number of minutes east of UTC.
"""
import calendar
import datetime
import re

from .errors import TimeFormatError

_INSTANT = re.compile(r"^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2}))?Z$")
_OFFSET = re.compile(r"^([+-])(\d{2}):(\d{2})$")
MAX_OFFSET = 14 * 60
EPOCH = datetime.datetime(1970, 1, 1)


def parse_instant(text):
    """Parse ``YYYY-MM-DDTHH:MM[:SS]Z`` into an instant."""
    match = _INSTANT.match(text)
    if not match:
        raise TimeFormatError(f"bad instant {text!r}")
    year, month, day, hour, minute = (int(match.group(i)) for i in range(1, 6))
    second = int(match.group(6) or 0)
    try:
        value = datetime.datetime(year, month, day, hour, minute, second)
    except ValueError:
        raise TimeFormatError(f"bad instant {text!r}") from None
    return calendar.timegm(value.timetuple())


def to_datetime(instant):
    """The naive UTC datetime of an instant."""
    return EPOCH + datetime.timedelta(seconds=instant)


def from_datetime(value):
    """The instant of a naive datetime read as UTC."""
    return calendar.timegm(value.timetuple())


def format_utc(instant):
    """``YYYY-MM-DDTHH:MM:SSZ``."""
    return to_datetime(instant).strftime("%Y-%m-%dT%H:%M:%SZ")


def parse_offset(text):
    """Parse ``+HH:MM`` / ``-HH:MM`` into minutes; at most 14 hours either way."""
    match = _OFFSET.match(text)
    if not match:
        raise TimeFormatError(f"bad offset {text!r}")
    sign = -1 if match.group(1) == "-" else 1
    hours, minutes = int(match.group(2)), int(match.group(3))
    if minutes >= 60 or hours * 60 + minutes > MAX_OFFSET:
        raise TimeFormatError(f"bad offset {text!r}")
    return sign * (hours * 60 + minutes)


def format_offset(minutes):
    sign = "-" if minutes < 0 else "+"
    hours, rest = divmod(abs(minutes), 60)
    return f"{sign}{hours:02d}:{rest:02d}"


def wall_time(instant, offset):
    """The naive local datetime of an instant at a fixed offset."""
    return to_datetime(instant + offset * 60)


def format_local(instant, offset):
    """``YYYY-MM-DDTHH:MM+HH:MM``: the local wall time to the minute and its offset."""
    return wall_time(instant, offset).strftime("%Y-%m-%dT%H:%M") + format_offset(offset)


def floor_minute(instant):
    return instant - instant % 60
