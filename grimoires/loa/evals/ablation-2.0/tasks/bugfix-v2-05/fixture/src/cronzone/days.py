"""Which days of a month an expression's day fields select."""
import calendar


def month_shape(year, month):
    """(number of days, cron weekday of the 1st) — 0 is Sunday."""
    first_py, length = calendar.monthrange(year, month)
    return length, (first_py + 1) % 7


def _weekday(first, day):
    return (first + day - 1) % 7


def _special_days(special, length, first):
    kind = special[0]
    if kind == "last":
        day = length - special[1]
        return {day} if day >= 1 else set()
    if kind == "last-weekday":
        day = length
        while _weekday(first, day) in (0, 6):
            day -= 1
        return {day}
    if kind == "nearest-weekday":
        day = special[1]
        if day > length:
            return set()
        wd = _weekday(first, day)
        if wd == 6:
            return {day - 1}
        if wd == 0:
            return {day + 1}
        return {day}
    if kind == "nth":
        _, dow, k = special
        days = [d for d in range(1, length + 1) if _weekday(first, d) == dow]
        return {days[k - 1]} if k <= len(days) else set()
    if kind == "last-dow":
        days = [d for d in range(1, length + 1) if _weekday(first, d) == special[1]]
        return {days[-1]}
    raise AssertionError(kind)


def _dom_days(dom, length, first):
    days = {d for d in dom.values if d <= length}
    for special in dom.specials:
        days |= _special_days(special, length, first)
    return days


def _dow_days(dow, length, first):
    days = {d for d in range(1, length + 1) if _weekday(first, d) in dow.values}
    for special in dow.specials:
        days |= _special_days(special, length, first)
    return days


def matching_days(dom, dow, length, first):
    """The sorted days of a month of ``length`` days starting on ``first``."""
    if dom.restricted and dow.restricted:
        days = _dom_days(dom, length, first) | _dow_days(dow, length, first)
    elif dom.restricted:
        days = _dom_days(dom, length, first)
    elif dow.restricted:
        days = _dow_days(dow, length, first)
    else:
        days = set(range(1, length + 1))
    return tuple(sorted(days))
