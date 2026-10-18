"""Brute-force model of the cronzone specification (grader side only).

Independent of the package: its own parser, its own zone arithmetic, and
fire times found by checking whole UTC minutes one by one (skipping a
30-minute UTC block at once when its local date is not selected; every
offset in the table is a multiple of 30 minutes and every transition falls
on a :00 or :30 UTC minute, so the local date is constant inside such a
block).
"""
import calendar
from datetime import datetime, timedelta, timezone

UTC = timezone.utc
EPOCH = datetime(1970, 1, 1, tzinfo=UTC)
NAIVE = datetime(1970, 1, 1)
HORIZON = 2922 * 1440
NEVER = "no fire time within 8 years"


class Err(Exception):
    pass


# -- zones ----------------------------------------------------------------
ZONES = {
    "utc": (0, None),
    "plus0530": (330, None),
    "north": (60, (120, (3, "last", 0, 1, 0), (10, "last", 0, 1, 0))),
    "west": (-300, (-240, (3, 2, 0, 7, 0), (11, 1, 0, 6, 0))),
    "south": (630, (660, (10, 1, 0, 15, 30), (4, 1, 0, 15, 0))),
    "midnight": (-180, (-120, (11, 1, 0, 3, 0), (2, 3, 0, 2, 0))),
}
_cache = {}


def _rule_minute(year, rule):
    month, nth, weekday, hh, mm = rule
    n_days = calendar.monthrange(year, month)[1]
    hits = [d for d in range(1, n_days + 1)
            if (datetime(year, month, d).isoweekday() % 7) == weekday]
    d = hits[-1] if nth == "last" else hits[nth - 1]
    return int((datetime(year, month, d, hh, mm, tzinfo=UTC) - EPOCH).total_seconds()) // 60


def _year_rules(zone, year):
    key = (zone, year)
    if key not in _cache:
        std, dst = ZONES[zone]
        if dst is None:
            _cache[key] = None
        else:
            _cache[key] = (_rule_minute(year, dst[1]), _rule_minute(year, dst[2]))
    return _cache[key]


def year_of(u):
    return (EPOCH + timedelta(minutes=u)).year


def offset(zone, u):
    std, dst = ZONES[zone]
    rules = _year_rules(zone, year_of(u))
    if rules is None:
        return std
    a, b = rules
    if a < b:
        inside = a <= u < b
    else:
        inside = u >= a or u < b
    return dst[0] if inside else std


def wall_of(zone, u):
    return NAIVE + timedelta(minutes=u + offset(zone, u))


def instants_of(zone, wall):
    w = int((wall.replace(second=0, microsecond=0) - NAIVE).total_seconds()) // 60
    std, dst = ZONES[zone]
    offs = {std} if dst is None else {std, dst[0]}
    return sorted(w - o for o in offs if offset(zone, w - o) == o)


def minutes_of(dt):
    """(floor, ceil) whole minutes of an aware datetime."""
    delta = dt - EPOCH
    total_us = (delta.days * 86400 + delta.seconds) * 10 ** 6 + delta.microseconds
    floor = total_us // (60 * 10 ** 6)
    ceil = floor if total_us % (60 * 10 ** 6) == 0 else floor + 1
    return floor, ceil


def instant(u):
    return EPOCH + timedelta(minutes=u)


# -- parsing --------------------------------------------------------------
MACROS = {"@yearly": "0 0 1 1 *", "@annually": "0 0 1 1 *", "@monthly": "0 0 1 * *",
          "@weekly": "0 0 * * 0", "@daily": "0 0 * * *", "@midnight": "0 0 * * *",
          "@hourly": "0 * * * *"}
MON = "JAN FEB MAR APR MAY JUN JUL AUG SEP OCT NOV DEC".split()
DOWN = "SUN MON TUE WED THU FRI SAT".split()
SPECS = [("minute", 0, 59, {}), ("hour", 0, 23, {}), ("day-of-month", 1, 31, {}),
         ("month", 1, 12, {n: i + 1 for i, n in enumerate(MON)}),
         ("day-of-week", 0, 7, {n: i for i, n in enumerate(DOWN)})]


def _num(tok, spec, raw):
    name, lo, hi, names = spec
    if tok.upper() in names:
        return names[tok.upper()]
    if tok == "" or any(c not in "0123456789" for c in tok):
        raise Err(f"invalid {name} value: {raw!r}")
    v = int(tok)
    if v < lo or v > hi:
        raise Err(f"{name} value out of range: {raw!r}")
    return v


def _digits(s):
    return s != "" and all(c in "0123456789" for c in s)


def _field(text, idx):
    spec = SPECS[idx]
    name, lo, hi, _ = spec
    if text == "":
        raise Err(f"invalid {name} value: ''")
    vals, specials = set(), []
    for raw in text.split(","):
        up = raw.upper()
        if idx == 2:
            if up == "L":
                specials.append(("L", 0)); continue
            if up == "LW":
                specials.append(("LW",)); continue
            if up.startswith("L-") and _digits(up[2:]):
                n = int(up[2:])
                if not 1 <= n <= 30:
                    raise Err(f"{name} value out of range: {raw!r}")
                specials.append(("L", n)); continue
            if up.endswith("W") and _digits(up[:-1]):
                n = int(up[:-1])
                if not 1 <= n <= 31:
                    raise Err(f"{name} value out of range: {raw!r}")
                specials.append(("W", n)); continue
        if idx == 4:
            if "#" in up:
                left, _, right = up.partition("#")
                if left != "" and "#" not in right and _digits(right) and left.isalnum() and left.isascii():
                    d = _num(left, spec, raw) % 7
                    k = int(right)
                    if not 1 <= k <= 5:
                        raise Err(f"{name} value out of range: {raw!r}")
                    specials.append(("#", d, k)); continue
            if len(up) >= 2 and up.endswith("L") and up[:-1].isalnum() and up[:-1].isascii():
                specials.append(("DL", _num(up[:-1], spec, raw) % 7)); continue
        base, slash, step = raw.partition("/")
        st = 1
        if slash:
            if not _digits(step) or int(step) == 0:
                raise Err(f"invalid {name} step: {raw!r}")
            st = int(step)
        if base == "*" or (base == "?" and idx in (2, 4)):
            a, b = lo, hi
        elif "-" in base:
            x, _, y = base.partition("-")
            a, b = _num(x, spec, raw), _num(y, spec, raw)
            if a > b:
                raise Err(f"invalid {name} range: {raw!r}")
        else:
            a = _num(base, spec, raw)
            b = hi if slash else a
        vals.update(range(a, b + 1, st))
    if idx == 4:
        vals = {v % 7 for v in vals}
    restricted = text not in ("*", "?") if idx in (2, 4) else True
    return vals, specials, restricted


def parse(text):
    s = text.strip()
    if s.startswith("@"):
        if s.lower() not in MACROS:
            raise Err(f"unknown macro: {s!r}")
        s = MACROS[s.lower()]
    parts = s.split()
    if len(parts) != 5:
        raise Err(f"expected 5 fields, got {len(parts)}")
    return [_field(p, i) for i, p in enumerate(parts)]


# -- matching -------------------------------------------------------------
def _dow(y, m, d):
    return datetime(y, m, d).isoweekday() % 7


def _special_hit(sp, y, m, d):
    n_days = calendar.monthrange(y, m)[1]
    kind = sp[0]
    if kind == "L":
        return d == n_days - sp[1]
    if kind == "LW":
        t = n_days
        while _dow(y, m, t) in (0, 6):
            t -= 1
        return d == t
    if kind == "W":
        n = sp[1]
        if n > n_days:
            return False
        wd = _dow(y, m, n)
        if wd == 6:
            t = n - 1 if n > 1 else n + 2
        elif wd == 0:
            t = n + 1 if n < n_days else n - 2
        else:
            t = n
        return d == t
    if kind == "#":
        return _dow(y, m, d) == sp[1] and (d - 1) // 7 + 1 == sp[2]
    if kind == "DL":
        return _dow(y, m, d) == sp[1] and d + 7 > n_days
    raise AssertionError(kind)


def day_ok(f, y, m, d):
    if m not in f[3][0]:
        return False
    dom_v, dom_s, dom_r = f[2]
    dow_v, dow_s, dow_r = f[4]
    dom_hit = d in dom_v or any(_special_hit(s, y, m, d) for s in dom_s)
    dow_hit = _dow(y, m, d) in dow_v or any(_special_hit(s, y, m, d) for s in dow_s)
    if dom_r and dow_r:
        return dom_hit or dow_hit
    if dom_r:
        return dom_hit
    if dow_r:
        return dow_hit
    return True


def fires_at(f, zone, u):
    w = wall_of(zone, u)
    return w.minute in f[0][0] and w.hour in f[1][0] and day_ok(f, w.year, w.month, w.day)


def _block_day_ok(f, zone, u):
    w = wall_of(zone, u)
    return day_ok(f, w.year, w.month, w.day)


def first_in(f, zone, u, last):
    while u <= last:
        if not _block_day_ok(f, zone, u):
            u = (u // 30 + 1) * 30
            continue
        if fires_at(f, zone, u):
            return u
        u += 1
    return None


def last_in(f, zone, u, first):
    while u >= first:
        if not _block_day_ok(f, zone, u):
            u = (u // 30) * 30 - 1
            continue
        if fires_at(f, zone, u):
            return u
        u -= 1
    return None


# -- the public operations ------------------------------------------------
def _wrap(fn):
    try:
        return ("ok", fn())
    except Err as e:
        return ("err", "CronError", str(e))


def next_fire(text, zone, after):
    def run():
        f = parse(text)
        base = minutes_of(after)[0]
        u = first_in(f, zone, base + 1, base + HORIZON)
        if u is None:
            raise Err(NEVER)
        return instant(u)
    return _wrap(run)


def prev_fire(text, zone, before):
    def run():
        f = parse(text)
        top = minutes_of(before)[1]
        u = last_in(f, zone, top - 1, top - HORIZON)
        if u is None:
            raise Err(NEVER)
        return instant(u)
    return _wrap(run)


def fires_between(text, zone, start, end):
    def run():
        f = parse(text)
        u, last = minutes_of(start)[1], minutes_of(end)[1] - 1
        out = []
        while True:
            u = first_in(f, zone, u, last)
            if u is None:
                return out
            out.append(instant(u))
            u += 1
    return _wrap(run)


def next_fires(text, zone, after, n):
    def run():
        out, t = [], after
        for _ in range(n):
            r = next_fire(text, zone, t)
            if r[0] == "err":
                raise Err(r[2])
            t = r[1]
            out.append(t)
        return out
    return _wrap(run)


def upcoming(jobs, after, n):
    """jobs: [(name, text, zone)]"""
    events = []
    for pos, (name, text, zone) in enumerate(jobs):
        t = after
        for _ in range(n):
            r = next_fire(text, zone, t)
            if r[0] == "err":
                break
            t = r[1]
            events.append((t, pos, name))
    events.sort()
    return [(t, name) for t, _, name in events[:n]]


def catch_up(text, zone, last_run, now, policy):
    if policy not in ("all", "latest", "skip"):
        return ("err", "CronError", f"unknown policy: {policy!r}")
    if policy == "skip":
        return ("ok", [])
    f = parse(text)
    u, last = minutes_of(last_run)[0] + 1, minutes_of(now)[0]
    out = []
    while True:
        u = first_in(f, zone, u, last)
        if u is None:
            break
        out.append(instant(u))
        u += 1
    return ("ok", out if policy == "all" else out[-1:])
