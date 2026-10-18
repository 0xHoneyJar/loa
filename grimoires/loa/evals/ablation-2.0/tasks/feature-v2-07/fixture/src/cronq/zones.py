"""The zone table.

A zone is an initial offset plus an increasing list of transitions, each an
instant at which a new offset takes effect.  The file format::

    # comment
    zone Lakeland
      initial +01:00
      2026-03-29T01:00Z +02:00
      2026-10-25T01:00Z +01:00

The zone ``UTC`` (offset 0, no transitions) always exists and may not be
redefined.
"""
import re

from .errors import TimeFormatError, ZoneError
from .timeutil import format_offset, parse_instant, parse_offset, wall_time

_NAME = re.compile(r"^[A-Za-z][A-Za-z0-9_/+-]*$")


class Zone:
    def __init__(self, name, initial, changes=()):
        self.name = name
        self.initial = initial
        self.changes = tuple(changes)  # ((instant, offset), ...), strictly increasing instants

    def offset_at(self, instant):
        """The offset in effect at ``instant``: that of the last transition at or before it."""
        offset = self.initial
        for when, value in self.changes:
            if when <= instant:
                offset = value
            else:
                break
        return offset

    def offsets(self):
        """Every offset the zone ever uses, sorted."""
        return sorted({self.initial, *(value for _, value in self.changes)})

    def wall(self, instant):
        """The naive local datetime of ``instant`` in this zone."""
        return wall_time(instant, self.offset_at(instant))

    def describe(self):
        parts = [f"{self.name} {format_offset(self.initial)}"]
        parts += [f"{when}:{format_offset(value)}" for when, value in self.changes]
        return " ".join(parts)

    def __repr__(self):
        return f"Zone({self.name!r})"


UTC = Zone("UTC", 0)


def parse_zones(text):
    """Parse a zone table file into ``{name: Zone}`` (always including ``UTC``)."""
    zones = {"UTC": UTC}
    current = None  # [name, initial, changes, line]

    def finish():
        if current is not None:
            zones[current[0]] = Zone(current[0], current[1], current[2])

    for number, raw in enumerate(text.splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        words = line.split()
        if words[0] == "zone":
            if len(words) != 2 or not _NAME.match(words[1]):
                raise ZoneError(f"zones:{number}: expected 'zone NAME'")
            if words[1] in zones or (current is not None and current[0] == words[1]):
                raise ZoneError(f"zones:{number}: duplicate zone {words[1]!r}")
            finish()
            current = [words[1], None, [], number]
            continue
        if current is None:
            raise ZoneError(f"zones:{number}: entry outside a zone")
        if len(words) != 2:
            raise ZoneError(f"zones:{number}: expected 2 fields, got {len(words)}")
        try:
            offset = parse_offset(words[1])
            if words[0] == "initial":
                if current[1] is not None:
                    raise ZoneError(f"zones:{number}: second initial offset")
                current[1] = offset
                continue
            when = parse_instant(words[0])
        except TimeFormatError as exc:
            raise ZoneError(f"zones:{number}: {exc}") from None
        if current[1] is None:
            raise ZoneError(f"zones:{number}: zone {current[0]!r} has no initial offset")
        if current[2] and when <= current[2][-1][0]:
            raise ZoneError(f"zones:{number}: transitions must increase")
        current[2].append((when, offset))
    if current is not None and current[1] is None:
        raise ZoneError(f"zones:{current[3]}: zone {current[0]!r} has no initial offset")
    finish()
    return zones


def lookup(zones, name):
    try:
        return zones[name]
    except KeyError:
        raise ZoneError(f"unknown zone {name!r}") from None
