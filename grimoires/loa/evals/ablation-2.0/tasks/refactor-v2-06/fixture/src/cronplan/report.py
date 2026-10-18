import datetime

from .cache import get
from .schedule import day_ok, ArgumentError
from .calendar_util import days_in_month


def month_report(expression, year, month):
    """Render the per-day fire counts of an expression for one month."""
    sched = get(expression)
    if not isinstance(month, int) or month < 1 or month > 12:
        raise ArgumentError("month must be 1-12, got %r" % (month,))
    if not isinstance(year, int) or year < 1 or year > 9998:
        raise ArgumentError("year must be 1-9998, got %r" % (year,))
    per_day = len(sched.hour.values) * len(sched.minute.values)
    lines = []
    n = 0
    for day in range(1, days_in_month(year, month) + 1):
        d = datetime.date(year, month, day)
        if day_ok(sched, d):
            lines.append("%s  %d" % (d.isoformat(), per_day))
            n += 1
    lines.append("total  %d" % (per_day * n))
    return "\n".join(lines)
