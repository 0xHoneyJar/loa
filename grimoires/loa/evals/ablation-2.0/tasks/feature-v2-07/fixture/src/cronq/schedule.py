"""Schedules.

A schedule answers ``next_after(instant, zone)``: the first fire instant
strictly after ``instant``.  The one kind today is the interval::

    every 15m      every 2h      every 1d

An interval fires at every instant that is a whole multiple of its length
counted from 1970-01-01T00:00Z; the zone does not affect it.
"""
import re

from .errors import ScheduleError

DEFAULT_HORIZON_DAYS = 1830
_INTERVAL = re.compile(r"^([0-9]+)([mhd])$")
_UNIT_MINUTES = {"m": 1, "h": 60, "d": 1440}


class IntervalSchedule:
    def __init__(self, minutes, text):
        self.minutes = minutes
        self.text = text

    def next_after(self, instant, zone):
        step = self.minutes * 60
        return (instant // step + 1) * step

    def describe(self):
        return self.text

    def __repr__(self):
        return f"IntervalSchedule({self.minutes})"


def _parse_interval(words, text):
    if len(words) != 2:
        raise ScheduleError(f"expected 'every <n><m|h|d>', got {text!r}")
    match = _INTERVAL.match(words[1])
    if not match:
        raise ScheduleError(f"bad interval {words[1]!r}")
    count = int(match.group(1))
    if count < 1:
        raise ScheduleError(f"bad interval {words[1]!r}")
    return IntervalSchedule(count * _UNIT_MINUTES[match.group(2)], "every " + words[1])


def parse_schedule(text, horizon_days=DEFAULT_HORIZON_DAYS):
    """Parse a schedule text (``every ...``)."""
    words = text.split()
    if not words:
        raise ScheduleError("empty schedule")
    if words[0] == "every":
        return _parse_interval(words, text.strip())
    raise ScheduleError(f"unknown schedule kind {words[0]!r}")
