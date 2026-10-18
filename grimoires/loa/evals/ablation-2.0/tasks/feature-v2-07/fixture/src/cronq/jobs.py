"""The jobs file.

One job per line, four fields separated by ``|``::

    NAME | ZONE | SCHEDULE | COMMAND

``NAME`` is a lower-case word (``[a-z][a-z0-9_-]*``), unique in the file.
``ZONE`` names a zone of the zone table, or is ``-`` for the config's
default zone.  ``SCHEDULE`` is a schedule text.  Blank lines and lines
starting with ``#`` are skipped; whitespace around fields is ignored.
"""
import re

from .config import Config
from .errors import JobsError, ScheduleError, ZoneError
from .schedule import parse_schedule
from .zones import lookup

_NAME = re.compile(r"^[a-z][a-z0-9_-]*$")


class Job:
    def __init__(self, name, zone, schedule, command, line):
        self.name = name
        self.zone = zone
        self.schedule = schedule
        self.command = command
        self.line = line

    def next_after(self, instant):
        return self.schedule.next_after(instant, self.zone)

    def __repr__(self):
        return f"Job({self.name!r})"


def parse_jobs(text, zones, config=None):
    """Parse a jobs file into a list of Job in file order."""
    config = config or Config()
    jobs, names = [], set()
    for number, raw in enumerate(text.splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        fields = [part.strip() for part in line.split("|")]
        if len(fields) != 4:
            raise JobsError(f"jobs:{number}: expected 4 fields separated by '|', got {len(fields)}")
        name, zone_name, schedule_text, command = fields
        if not _NAME.match(name):
            raise JobsError(f"jobs:{number}: bad job name {name!r}")
        if name in names:
            raise JobsError(f"jobs:{number}: duplicate job {name!r}")
        try:
            zone = lookup(zones, config.default_zone if zone_name == "-" else zone_name)
        except ZoneError as exc:
            raise JobsError(f"jobs:{number}: {exc}") from None
        try:
            schedule = parse_schedule(schedule_text, config.horizon_days)
        except ScheduleError as exc:
            raise JobsError(f"jobs:{number}: bad schedule: {exc}") from None
        if not command:
            raise JobsError(f"jobs:{number}: empty command")
        names.add(name)
        jobs.append(Job(name, zone, schedule, command, number))
    return jobs
