"""Command line.

    python -m cronzone next EXPRESSION ZONE START [COUNT]

``START`` and ``END`` are ISO 8601 date-times with an offset (or ``Z``).
Each fire time is printed on its own line as ``<UTC> <wall time><offset>``,
for example ``2026-03-29T01:00Z 2026-03-29T03:00+02:00``.
"""
import sys
from datetime import datetime

from .errors import CronError
from .schedule import Schedule

USAGE = "usage: cronzone next EXPRESSION ZONE START [COUNT]"


def format_fire(schedule, instant):
    """``<UTC> <wall><offset>`` for one fire time."""
    offset = schedule.zone.offset(instant)
    wall = schedule.zone.wall(instant)
    sign = "+" if offset >= 0 else "-"
    hours, minutes = divmod(abs(offset), 60)
    return f"{instant:%Y-%m-%dT%H:%M}Z {wall:%Y-%m-%dT%H:%M}{sign}{hours:02d}:{minutes:02d}"


def _instant(text):
    value = datetime.fromisoformat(text)
    if value.tzinfo is None:
        raise ValueError(f"expected a timezone-aware datetime, got {text!r}")
    return value


def main(argv=None, stdout=None, stderr=None):
    argv = sys.argv[1:] if argv is None else argv
    stdout = sys.stdout if stdout is None else stdout
    stderr = sys.stderr if stderr is None else stderr
    try:
        if len(argv) in (4, 5) and argv[0] == "next":
            count = int(argv[4]) if len(argv) == 5 else 1
            schedule = Schedule(argv[1], argv[2])
            fires = schedule.next_fires(_instant(argv[3]), count)
        else:
            print(USAGE, file=stderr)
            return 2
    except (CronError, ValueError) as exc:
        print(f"error: {exc}", file=stderr)
        return 1
    for instant in fires:
        print(format_fire(schedule, instant), file=stdout)
    return 0
