"""Reference model of the rules of the task brief, written for clarity, not speed.

parse(text) -> Spec, or raises OracleError(message)
next_after / prev_before / count_between / nth_after over (initial, changes)
parse_tz(text) and tz_timeline(text) -> (initial, changes) for rule strings
"""
import bisect
import calendar
import datetime
import functools


class OracleError(Exception):
    pass


NAMES = ["minute", "hour", "dom", "month", "dow"]
LOW = [0, 0, 1, 1, 0]
HIGH = [59, 23, 31, 12, 7]
MONTHS = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
DAYS = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]
MACRO = {
    "@yearly": "0 0 1 1 *", "@annually": "0 0 1 1 *", "@monthly": "0 0 1 * *",
    "@weekly": "0 0 * * 0", "@daily": "0 0 * * *", "@midnight": "0 0 * * *", "@hourly": "0 * * * *",
}


class Problem(Exception):
    pass


def is_digits(s):
    return s != "" and all(c in "0123456789" for c in s)


def number(s, f):
    if is_digits(s):
        v = int(s)
    elif f == 3 and s.upper() in MONTHS:
        v = MONTHS.index(s.upper()) + 1
    elif f == 4 and s.upper() in DAYS:
        v = DAYS.index(s.upper())
    else:
        raise Problem("bad value %r" % (s,))
    if v < LOW[f] or v > HIGH[f]:
        raise Problem("value %d out of range %d-%d" % (v, LOW[f], HIGH[f]))
    return v


def is_dow_base(s):
    return is_digits(s) or (len(s) == 3 and all(c.isascii() and c.isalpha() for c in s))


class Field:
    def __init__(self, text):
        self.text = text
        self.plain = set()
        self.specials = []  # ("L",), ("LW",), ("W", n), ("lastof", d), ("nth", d, k)


def parse_field(text, f):
    fld = Field(text)
    for item in text.split(","):
        if item == "":
            raise Problem("empty item")
        up = item.upper()
        if f == 2 and up == "L":
            fld.specials.append(("L",))
            continue
        if f == 2 and up == "LW":
            fld.specials.append(("LW",))
            continue
        if f == 2 and len(item) >= 2 and up.endswith("W") and is_digits(item[:-1]):
            fld.specials.append(("W", number(item[:-1], f)))
            continue
        if f == 4 and len(item) >= 2 and up.endswith("L") and is_dow_base(item[:-1]):
            fld.specials.append(("lastof", number(item[:-1], f) % 7))
            continue
        if f == 4 and "#" in item:
            head, _, tail = item.partition("#")
            if is_dow_base(head) and is_digits(tail):
                d = number(head, f) % 7
                k = int(tail)
                if k < 1 or k > 5:
                    raise Problem("occurrence %d out of range 1-5" % k)
                fld.specials.append(("nth", d, k))
                continue
        if "/" in item:
            base, step_s = item.split("/", 1)
            has_step = True
        else:
            base, step_s, has_step = item, None, False
        if base == "*":
            a, b = LOW[f], HIGH[f]
        elif "-" in base:
            left, right = base.split("-", 1)
            a = number(left, f)
            b = number(right, f)
            if a > b:
                raise Problem("reversed range %r" % (base,))
        else:
            a = number(base, f)
            b = HIGH[f] if has_step else a
        step = 1
        if has_step:
            if not is_digits(step_s):
                raise Problem("bad step %r" % (step_s,))
            step = int(step_s)
            if step == 0:
                raise Problem("step must be at least 1")
        v = a
        while v <= b:
            fld.plain.add(v % 7 if f == 4 else v)
            v += step
    return fld


class Spec:
    def __init__(self, fields):
        self.fields = fields


def parse(text):
    s = text.strip()
    if s == "":
        raise OracleError("empty expression")
    if s[0] == "@":
        if s.lower() not in MACRO:
            raise OracleError("unknown macro %r" % (s,))
        parts = MACRO[s.lower()].split()
    else:
        parts = s.split()
        if len(parts) != 5:
            raise OracleError("expected 5 fields, got %d" % len(parts))
    fields = []
    for f in range(5):
        try:
            fields.append(parse_field(parts[f], f))
        except Problem as p:
            raise OracleError("field %d (%s): %s" % (f + 1, NAMES[f], p)) from None
    return Spec(fields)


def cron_weekday(y, m, d):
    return (datetime.date(y, m, d).weekday() + 1) % 7


def dom_ok(fld, y, m, d):
    last = calendar.monthrange(y, m)[1]
    if d in fld.plain:
        return True
    for sp in fld.specials:
        if sp[0] == "L" and d == last:
            return True
        if sp[0] == "LW":
            x = last
            while cron_weekday(y, m, x) in (0, 6):
                x -= 1
            if d == x:
                return True
        if sp[0] == "W":
            n = sp[1]
            if n > last:
                continue
            wd = cron_weekday(y, m, n)
            if wd == 6:
                target = n - 1 if n > 1 else 3
            elif wd == 0:
                target = n + 1 if n < last else n - 2
            else:
                target = n
            if d == target:
                return True
    return False


def dow_ok(fld, y, m, d):
    wd = cron_weekday(y, m, d)
    last = calendar.monthrange(y, m)[1]
    if wd in fld.plain:
        return True
    for sp in fld.specials:
        if sp[0] == "lastof" and wd == sp[1] and d + 7 > last:
            return True
        if sp[0] == "nth" and wd == sp[1] and (d - 1) // 7 + 1 == sp[2]:
            return True
    return False


def day_ok(spec, y, m, d):
    dom, month, dow = spec.fields[2], spec.fields[3], spec.fields[4]
    if m not in month.plain:
        return False
    dom_r = dom.text != "*"
    dow_r = dow.text != "*"
    if dom_r and dow_r:
        return dom_ok(dom, y, m, d) or dow_ok(dow, y, m, d)
    if dom_r:
        return dom_ok(dom, y, m, d)
    if dow_r:
        return dow_ok(dow, y, m, d)
    return True


EPOCH = datetime.datetime(1970, 1, 1)
SPAN = 1096


class Timeline:
    """Offsets of a zone as (initial, changes) with the occurred-before test."""

    def __init__(self, initial, changes):
        self.initial = initial
        self.changes = list(changes)
        self.times = [w for w, _ in self.changes]
        self.offsets = sorted({initial} | {v for _, v in self.changes})
        self.marks = sorted({-(-w // 60) for w in self.times})

    def off(self, mi):
        i = bisect.bisect_right(self.times, mi * 60)
        return self.changes[i - 1][1] if i else self.initial

    def seen_before(self, mi, w):
        for o in self.offsets:
            other = w - o
            if other < mi and self.off(other) == o:
                return True
        return False

    def next_mark(self, mi):
        i = bisect.bisect_right(self.marks, mi)
        return self.marks[i] if i < len(self.marks) else None

    def prev_mark(self, mi):  # largest mark <= mi
        i = bisect.bisect_right(self.marks, mi)
        return self.marks[i - 1] if i else None


def fires_forward(spec, tl, first, last):
    """Fire minute indexes in [first, last], ascending (walk with day/hour skipping)."""
    minute_set, hour_set = spec.fields[0].plain, spec.fields[1].plain
    mi = first
    while mi <= last:
        w = mi + tl.off(mi)
        local = EPOCH + datetime.timedelta(minutes=w)
        jump = None
        if not day_ok(spec, local.year, local.month, local.day):
            jump = mi + (1440 - w % 1440)
        elif local.hour not in hour_set:
            jump = mi + (60 - w % 60)
        if jump is not None:
            nc = tl.next_mark(mi)
            mi = jump if nc is None else min(jump, nc)
            continue
        if local.minute in minute_set and not tl.seen_before(mi, w):
            yield mi
        mi += 1


def fires_backward(spec, tl, last, first):
    """Fire minute indexes in [first, last], descending."""
    minute_set, hour_set = spec.fields[0].plain, spec.fields[1].plain
    mi = last
    while mi >= first:
        w = mi + tl.off(mi)
        local = EPOCH + datetime.timedelta(minutes=w)
        jump = None
        if not day_ok(spec, local.year, local.month, local.day):
            jump = mi - (w % 1440) - 1
        elif local.hour not in hour_set:
            jump = mi - (w % 60) - 1
        if jump is not None:
            pm = tl.prev_mark(mi)
            mi = jump if pm is None else max(jump, pm - 1)
            continue
        if local.minute in minute_set and not tl.seen_before(mi, w):
            yield mi
        mi -= 1


def next_after(spec, instant, initial, changes, horizon_days):
    tl = Timeline(initial, changes)
    for mi in fires_forward(spec, tl, instant // 60 + 1, (instant + horizon_days * 86400) // 60):
        return mi * 60
    raise OracleError("no fire time within %d days" % horizon_days)


def prev_before(spec, instant, initial, changes, horizon_days):
    tl = Timeline(initial, changes)
    first = -(-(instant - horizon_days * 86400) // 60)
    for mi in fires_backward(spec, tl, -(-instant // 60) - 1, first):
        return mi * 60
    raise OracleError("no fire time within %d days before" % horizon_days)


def count_between(spec, a, b, initial, changes):
    if b < a:
        raise OracleError("end before start")
    if b - a > SPAN * 86400:
        raise OracleError("span longer than %d days" % SPAN)
    tl = Timeline(initial, changes)
    return sum(1 for _ in fires_forward(spec, tl, a // 60 + 1, b // 60))


def nth_after(spec, instant, n, initial, changes):
    if n < 1:
        raise OracleError("n must be at least 1")
    tl = Timeline(initial, changes)
    k = 0
    for mi in fires_forward(spec, tl, instant // 60 + 1, (instant + SPAN * 86400) // 60):
        k += 1
        if k == n:
            return mi * 60
    raise OracleError("fewer than %d fire times within %d days" % (n, SPAN))


def run(fn, *args):
    try:
        return ("ok", fn(*args))
    except OracleError as exc:
        return ("error", str(exc))


def outcome(text, instant, initial, changes, horizon_days, count, backward=False):
    """("ok", None, [instants]) or ("error", message, [instants found before it])."""
    try:
        spec = parse(text)
    except OracleError as exc:
        return ("error", str(exc), [])
    step = prev_before if backward else next_after
    found = []
    t = instant
    for _ in range(count):
        try:
            t = step(spec, t, initial, changes, horizon_days)
        except OracleError as exc:
            return ("error", str(exc), found)
        found.append(t)
    return ("ok", None, found)


# ---------------------------------------------------------------- POSIX-TZ-style rules

ASCII_LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
DIGITS = "0123456789"


def take_digits(s, i):
    j = i
    while j < len(s) and s[j] in DIGITS:
        j += 1
    return s[i:j], j


def read_name(s, i, which):
    if i < len(s) and s[i] == "<":
        j = s.find(">", i + 1)
        if j < 0:
            raise OracleError("bad %s name" % which)
        inner = s[i + 1:j]
        if len(inner) < 3 or not all(c in ASCII_LETTERS + DIGITS + "+-" for c in inner):
            raise OracleError("bad %s name" % which)
        return j + 1
    j = i
    while j < len(s) and s[j] in ASCII_LETTERS:
        j += 1
    if j - i < 3:
        raise OracleError("bad %s name" % which)
    return j


def read_clock(s, i, max_digits, max_hour):
    """(signed minutes, next index) or (None, index)."""
    sign = 1
    if i < len(s) and s[i] in "+-":
        if s[i] == "-":
            sign = -1
        i += 1
    h, i = take_digits(s, i)
    if len(h) < 1 or len(h) > max_digits or int(h) > max_hour:
        return None, i
    total = int(h) * 60
    if i < len(s) and s[i] == ":":
        m, i = take_digits(s, i + 1)
        if len(m) != 2 or int(m) > 59:
            return None, i
        total += int(m)
        if i < len(s) and s[i] == ":":
            sec, i = take_digits(s, i + 1)
            if sec != "00":
                return None, i
    return sign * total, i


def read_date(s, i):
    if i < len(s) and s[i] == "J":
        n, i = take_digits(s, i + 1)
        ok = 1 <= len(n) <= 3 and 1 <= int(n) <= 365
        return (("J", int(n)) if ok else None), i
    if i < len(s) and s[i] == "M":
        parts = []
        i += 1
        for k, (lo, hi, maxlen) in enumerate([(1, 12, 2), (1, 5, 1), (0, 6, 1)]):
            d, i = take_digits(s, i)
            if not 1 <= len(d) <= maxlen or not lo <= int(d) <= hi:
                return None, i
            parts.append(int(d))
            if k < 2:
                if i >= len(s) or s[i] != ".":
                    return None, i
                i += 1
        return ("M", parts[0], parts[1], parts[2]), i
    n, i = take_digits(s, i)
    ok = 1 <= len(n) <= 3 and int(n) <= 365
    return (("N", int(n)) if ok else None), i


def parse_tz(text):
    """(std_east, dst_east or None, (start_date, start_time) or None, (end_date, end_time) or None)."""
    s = text.strip()
    if not s:
        raise OracleError("empty rule")
    i = read_name(s, 0, "std")
    v, i = read_clock(s, i, 2, 24)
    if v is None or not (i == len(s) or s[i] == "<" or s[i] in ASCII_LETTERS):
        raise OracleError("bad std offset")
    std = -v
    if i == len(s):
        return std, None, None, None
    i = read_name(s, i, "dst")
    dst = std + 60
    if i < len(s) and s[i] in "+-" + DIGITS:
        v, i = read_clock(s, i, 2, 24)
        if v is None or (i < len(s) and s[i] != ","):
            raise OracleError("bad dst offset")
        dst = -v
    if i == len(s):
        raise OracleError("dst rules required")
    if s[i] != ",":
        raise OracleError("bad dst offset")
    i += 1
    rules = []
    for which, last in (("start", False), ("end", True)):
        if which == "end" and i >= len(s):
            raise OracleError("bad end rule")
        date, i = read_date(s, i)
        follow = s[i] if i < len(s) else "END"
        if date is None or follow not in (("/", "END") if last else ("/", ",")):
            raise OracleError("bad %s rule" % which)
        time = 120
        if follow == "/":
            time, i = read_clock(s, i + 1, 3, 167)
            follow = s[i] if i < len(s) else "END"
            if time is None or follow != ("END" if last else ","):
                raise OracleError("bad %s time" % which)
        rules.append((date, time))
        if not last:
            i += 1
    return std, dst, rules[0], rules[1]


def rule_day(year, date):
    if date[0] == "J":
        common = datetime.date(2001, 1, 1) + datetime.timedelta(days=date[1] - 1)  # 2001 has no Feb 29
        return datetime.date(year, common.month, common.day)
    if date[0] == "N":
        return datetime.date(year, 1, 1) + datetime.timedelta(days=date[1])
    _, month, week, weekday = date
    hits = []
    for day in range(1, 32):
        try:
            d = datetime.date(year, month, day)
        except ValueError:
            break
        if (d.weekday() + 1) % 7 == weekday:
            hits.append(d)
    return hits[min(week, len(hits)) - 1]


@functools.lru_cache(maxsize=512)
def tz_timeline(text):
    """(initial, changes) for a rule string, years 1970-2199; raises OracleError."""
    std, dst, start, end = parse_tz(text)
    if dst is None:
        return std, ()
    items = []
    for year in range(1970, 2200):
        for order, (date, time), before, after in ((0, start, std, dst), (1, end, dst, std)):
            local = datetime.datetime.combine(rule_day(year, date), datetime.time()) + datetime.timedelta(minutes=time)
            utc = local - datetime.timedelta(minutes=before)
            items.append((int((utc - EPOCH).total_seconds()), order, after))
    items.sort()
    return std, tuple((w, o) for w, _, o in items)
