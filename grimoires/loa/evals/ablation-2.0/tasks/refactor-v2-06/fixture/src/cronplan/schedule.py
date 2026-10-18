"""Fire-time search."""
import datetime

from . import settings
from .parser import CronError
from .calendar_util import cron_weekday, days_in_month, LastWeekday, nearest_weekday
from .cache import get


class SearchError(CronError):
    pass


class ArgumentError(CronError):
    pass


def _check(when):
    if not isinstance(when, datetime.datetime):
        raise ArgumentError("not a datetime: %r" % (when,))
    if when.tzinfo is not None:
        raise ArgumentError("datetime must be naive")


def _special(s, d):
    kind, n, k = s
    end = days_in_month(d.year, d.month)
    if kind == "L":
        return d.day == end
    elif kind == "LW":
        return d.day == LastWeekday(d.year, d.month)
    elif kind == "L-":
        return d.day == end - n
    elif kind == "W":
        return d.day == nearest_weekday(d.year, d.month, n)
    elif kind == "dL":
        return cron_weekday(d) == n and d.day + 7 > end
    else:
        return cron_weekday(d) == n and (d.day - 1) // 7 + 1 == k


def day_ok(sched, d):
    if d.month not in sched.month.values:
        return False
    dom = d.day in sched.day.values
    if not dom:
        for s in sched.day.specials:
            if _special(s, d):
                dom = True
                break
    dow = cron_weekday(d) in sched.weekday.values
    if not dow:
        for s in sched.weekday.specials:
            if _special(s, d):
                dow = True
                break
    if sched.day.starred or sched.weekday.starred:
        return dom and dow
    return dom or dow


def _next(sched, after):
    _check(after)
    t = after.replace(second=0, microsecond=0) + datetime.timedelta(minutes=1)
    while t.year <= after.year + settings.horizon_years:
        if t.month not in sched.month.values:
            if t.month == 12:
                t = datetime.datetime(t.year + 1, 1, 1)
            else:
                t = datetime.datetime(t.year, t.month + 1, 1)
            continue
        if not day_ok(sched, t.date()):
            t = datetime.datetime(t.year, t.month, t.day) + datetime.timedelta(days=1)
            continue
        if t.hour not in sched.hour.values:
            t = t.replace(minute=0) + datetime.timedelta(hours=1)
            continue
        if t.minute not in sched.minute.values:
            t = t + datetime.timedelta(minutes=1)
            continue
        if settings.debug:
            print("fire", t)
        return t
    raise SearchError("no fire time within %d years" % settings.horizon_years)


def next_fire(expression, after):
    """Return the first fire time of an expression after a moment."""
    return _next(get(expression), after)


def fires(expression, after, count=5):
    """Return the next fire times of an expression after a moment."""
    sched = get(expression)
    if not isinstance(count, int) or count < 1 or count > settings.max_count:
        raise ArgumentError("count must be 1-%d, got %r" % (settings.max_count, count))
    out = []
    for i in range(count):
        after = _next(sched, after)
        out.append(after)
    return out


def matches(expression, when):
    """Tell whether an expression fires at exactly this moment."""
    sched = get(expression)
    _check(when)
    if when.second != 0 or when.microsecond != 0:
        return False
    if when.minute not in sched.minute.values:
        return False
    if when.hour not in sched.hour.values:
        return False
    return day_ok(sched, when.date())
