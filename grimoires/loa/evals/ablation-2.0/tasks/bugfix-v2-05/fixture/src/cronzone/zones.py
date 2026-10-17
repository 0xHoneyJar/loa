"""The zone table: fixed offsets and yearly daylight-saving rules in UTC.

A rule ``(month, nth, weekday, hour, minute)`` names the instant at
``hour:minute`` UTC on the ``nth`` (1-4, or -1 for the last) ``weekday``
(0 = Sunday) of ``month`` (by UTC date).  A zone with daylight saving uses
``dst`` from its start rule (inclusive) to its end rule (exclusive) every
year.
"""
import calendar
from dataclasses import dataclass
from datetime import datetime
from typing import Optional, Tuple

from .errors import CronError
from .timeutil import ceil_minutes, floor_minutes, to_instant, to_wall, wall_minutes

Rule = Tuple[int, int, int, int, int]


@dataclass(frozen=True)
class Zone:
    name: str
    std: int
    dst: Optional[int] = None
    start: Optional[Rule] = None
    end: Optional[Rule] = None

    # -- transitions ------------------------------------------------------
    def _rule_minutes(self, year, rule):
        month, nth, weekday, hour, minute = rule
        first_py, length = calendar.monthrange(year, month)
        days = [d for d in range(1, length + 1) if (first_py + d) % 7 == weekday]
        day = days[-1] if nth == -1 else days[nth - 1]
        return wall_minutes(datetime(year, month, day, hour, minute))

    def transitions_minutes(self, year):
        """[(minute, offset after), ...] of ``year``, in time order."""
        if self.dst is None:
            return []
        return [(self._rule_minutes(year, self.start), self.dst),
                (self._rule_minutes(year, self.end), self.std)]

    def offset_minutes(self, u):
        """The offset in effect at whole minute ``u``."""
        if self.dst is None:
            return self.std
        year = to_instant(u).year
        start = self._rule_minutes(year, self.start)
        end = self._rule_minutes(year, self.end)
        return self.dst if start <= u < end else self.std

    # -- public, on datetimes ---------------------------------------------
    def offset(self, instant):
        """Offset (minutes east of UTC) in effect at an aware instant."""
        return self.offset_minutes(floor_minutes(instant))

    def wall(self, instant):
        """The naive wall-clock time of an aware instant (to the minute)."""
        u = ceil_minutes(instant)
        return to_wall(u + self.offset_minutes(u))

    def instants_minutes(self, w):
        """The whole minutes whose wall time is wall minute ``w``."""
        offsets = [self.std] if self.dst is None else [self.std, self.dst]
        return [w - off for off in offsets if self.offset_minutes(w - off) == off]

    def instants(self, wall):
        """The UTC instants (0, 1 or 2) whose wall time is ``wall``."""
        return [to_instant(u) for u in self.instants_minutes(wall_minutes(wall))]

    def transitions(self, year):
        """[(aware UTC instant, offset after), ...] of ``year``."""
        return [(to_instant(m), off) for m, off in self.transitions_minutes(year)]


ZONES = {
    "utc": Zone("utc", 0),
    "plus0530": Zone("plus0530", 330),
    "north": Zone("north", 60, 120, (3, -1, 0, 1, 0), (10, -1, 0, 1, 0)),
    "west": Zone("west", -300, -240, (3, 2, 0, 7, 0), (11, 1, 0, 6, 0)),
    "south": Zone("south", 630, 660, (10, 1, 0, 15, 30), (4, 1, 0, 15, 0)),
    "midnight": Zone("midnight", -180, -120, (11, 1, 0, 3, 0), (2, 3, 0, 2, 0)),
}


def get_zone(name):
    """The zone called ``name``; ``CronError`` for an unknown name."""
    if isinstance(name, Zone):
        return name
    if name not in ZONES:
        raise CronError(f"unknown zone: {name!r}")
    return ZONES[name]
