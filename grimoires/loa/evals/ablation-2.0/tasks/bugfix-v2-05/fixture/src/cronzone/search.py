"""Finding fire times.

The search runs over the wall-clock calendar: it finds the next (or
previous) matching wall time and converts it to UTC with the zone.  A wall
time that does not exist in the zone is passed over.
"""
from datetime import date, datetime, timedelta

from .timeutil import to_wall, wall_minutes

HORIZON_DAYS = 2922
HORIZON = HORIZON_DAYS * 1440
MAX_OFFSET = 24 * 60
ONE_DAY = timedelta(days=1)


def _first_of_next_month(day):
    return date(day.year + (day.month == 12), day.month % 12 + 1, 1)


def _last_of_previous_month(day):
    return day.replace(day=1) - ONE_DAY


def next_wall(expr, w, limit):
    """The smallest matching wall minute ``m`` with ``w <= m < limit``, or None."""
    if w >= limit:
        return None
    start = to_wall(w)
    last_day = to_wall(limit - 1).date()
    day, low_h, low_m = start.date(), start.hour, start.minute
    while day <= last_day:
        if day.month not in expr.month.values:
            day = _first_of_next_month(day)
            continue
        if day.day in expr.days(day.year, day.month):
            for h in expr.hours:
                if h < low_h:
                    continue
                for m in expr.minutes:
                    if h == low_h and m < low_m:
                        continue
                    found = wall_minutes(datetime(day.year, day.month, day.day, h, m))
                    return found if found < limit else None
        day, low_h, low_m = day + ONE_DAY, 0, 0
    return None


def prev_wall(expr, w, floor):
    """The largest matching wall minute ``m`` with ``floor <= m <= w``, or None."""
    if w < floor:
        return None
    start = to_wall(w)
    first_day = to_wall(floor).date()
    day, high_h, high_m = start.date(), start.hour, start.minute
    while day >= first_day:
        if day.month not in expr.month.values:
            day = _last_of_previous_month(day)
            continue
        if day.day in expr.days(day.year, day.month):
            for h in reversed(expr.hours):
                if h > high_h:
                    continue
                for m in reversed(expr.minutes):
                    if h == high_h and m > high_m:
                        continue
                    found = wall_minutes(datetime(day.year, day.month, day.day, h, m))
                    return found if found >= floor else None
        day, high_h, high_m = day - ONE_DAY, 23, 59
    return None


def first_at_or_after(expr, zone, u, last):
    """The first firing minute in ``[u, last]``, or None."""
    w = u + zone.offset_minutes(u)
    while True:
        found = next_wall(expr, w, last + 1 + MAX_OFFSET)
        if found is None:
            return None
        candidates = [i for i in zone.instants_minutes(found) if i >= u]
        if candidates:
            first = min(candidates)
            return first if first <= last else None
        w = found + 1


def last_at_or_before(expr, zone, u, first):
    """The last firing minute in ``[first, u]``, or None."""
    w = u + zone.offset_minutes(u)
    while True:
        found = prev_wall(expr, w, first - MAX_OFFSET)
        if found is None:
            return None
        candidates = [i for i in zone.instants_minutes(found) if i <= u]
        if candidates:
            last = max(candidates)
            return last if last >= first else None
        w = found - 1
