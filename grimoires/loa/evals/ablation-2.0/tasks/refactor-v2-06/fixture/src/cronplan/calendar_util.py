"""Calendar helpers."""
import datetime
from typing import Optional


def cron_weekday(d):
    return d.isoweekday() % 7


def days_in_month(year, month):
    if month == 12:
        nxt = datetime.date(year + 1, 1, 1)
    else:
        nxt = datetime.date(year, month + 1, 1)
    return (nxt - datetime.timedelta(days=1)).day


def LastWeekday(year, month):
    d = datetime.date(year, month, days_in_month(year, month))
    while d.isoweekday() in (6, 7):
        d = d - datetime.timedelta(days=1)
    return d.day


def nearest_weekday(year: int, month: int, n: int) -> Optional[int]:
    end = days_in_month(year, month)
    if n > end:
        return None
    wd = cron_weekday(datetime.date(year, month, n))
    if wd == 6:
        if n == 1:
            return 3
        return n - 1
    elif wd == 0:
        if n == end:
            return n - 2
        return n + 1
    return n
