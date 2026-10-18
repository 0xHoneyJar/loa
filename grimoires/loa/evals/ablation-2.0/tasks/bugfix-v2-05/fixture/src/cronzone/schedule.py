"""A cron expression evaluated in a zone."""
from .errors import CronError
from .expr import CronExpr
from .search import HORIZON, first_at_or_after, last_at_or_before
from .timeutil import ceil_minutes, floor_minutes, to_instant
from .zones import get_zone

NEVER = "no fire time within 8 years"


class Schedule:
    """``Schedule(expression, zone="utc")``."""

    def __init__(self, expression, zone="utc"):
        self.expr = expression if isinstance(expression, CronExpr) else CronExpr(expression)
        self.zone = get_zone(zone)

    def next_fire(self, after):
        """The earliest firing instant strictly after ``after``."""
        base = floor_minutes(after)
        found = first_at_or_after(self.expr, self.zone, base + 1, base + HORIZON)
        if found is None:
            raise CronError(NEVER)
        return to_instant(found)

    def prev_fire(self, before):
        """The latest firing instant strictly before ``before``."""
        top = floor_minutes(before)
        found = last_at_or_before(self.expr, self.zone, top - 1, top - HORIZON)
        if found is None:
            raise CronError(NEVER)
        return to_instant(found)

    def next_fires(self, after, count):
        """The ``count`` successive firing instants after ``after``."""
        out = []
        for _ in range(count):
            after = self.next_fire(after)
            out.append(after)
        return out

    def fires_between(self, start, end):
        """Every firing instant ``t`` with ``start <= t < end``, ascending."""
        u, last = floor_minutes(start) + 1, ceil_minutes(end) - 1
        out = []
        while True:
            found = first_at_or_after(self.expr, self.zone, u, last)
            if found is None:
                return out
            out.append(to_instant(found))
            u = found + 1

    def matches(self, instant):
        """True when the whole minute containing ``instant`` fires."""
        return self.expr.matches(self.zone.wall(instant))
