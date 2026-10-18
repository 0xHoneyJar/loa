"""The run log.

One line per entry::

    2026-03-29T03:00:00Z backup fires=2

``fires`` counts the fire instants the entry covers; the time is the latest
of them.
"""
import re

from .errors import CronqError
from .timeutil import format_utc, parse_instant

_LINE = re.compile(r"^(\S+) ([a-z][a-z0-9_-]*) fires=([1-9][0-9]*)$")


class Entry:
    def __init__(self, time, job, fires):
        self.time = time
        self.job = job
        self.fires = fires

    def __eq__(self, other):
        return isinstance(other, Entry) and (self.time, self.job, self.fires) == (other.time, other.job, other.fires)

    def __repr__(self):
        return f"Entry({format_utc(self.time)}, {self.job!r}, {self.fires})"

    def format(self):
        return f"{format_utc(self.time)} {self.job} fires={self.fires}"


class RunLog:
    def __init__(self, entries=()):
        self.entries = list(entries)

    def extend(self, entries):
        self.entries.extend(entries)

    def for_job(self, name):
        return [entry for entry in self.entries if entry.job == name]

    def to_text(self):
        return "".join(entry.format() + "\n" for entry in self.entries)


def parse_log(text):
    entries = []
    for number, raw in enumerate(text.splitlines(), 1):
        if not raw.strip():
            continue
        match = _LINE.match(raw.strip())
        if not match:
            raise CronqError(f"log:{number}: bad entry")
        entries.append(Entry(parse_instant(match.group(1)), match.group(2), int(match.group(3))))
    return RunLog(entries)
