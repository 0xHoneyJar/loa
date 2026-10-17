"""Parsing cron expressions."""
import re

from . import settings
from .names import MONTHS, DAYS, MACROS, _lookup

_plain_re = re.compile(r"^(\*|\?|[0-9A-Za-z]+(?:-[0-9A-Za-z]+)?)(?:/([0-9]+))?$")
_offset_re = re.compile(r"^L-([0-9]+)$")
_nearest_re = re.compile(r"^([0-9]+)W$")
_last_re = re.compile(r"^([0-9A-Za-z]+)L$")
_nth_re = re.compile(r"^([0-9A-Za-z]+)#([0-9]+)$")

SPECIAL_ORDER = ["L", "LW", "L-", "W", "dL", "#"]


class CronError(ValueError):
    pass


class ParseError(CronError):
    pass


class RangeError(CronError):
    pass


class fieldSpec:
    def __init__(self, name, values, specials, starred):
        self.name = name
        self.values = frozenset(values)
        self.specials = specials
        self.starred = starred

    def __repr__(self):
        return "fieldSpec(%r, %r, %r, %r)" % (self.name, sorted(self.values), self.specials, self.starred)


class Schedule:
    """A parsed five-field expression."""

    def __init__(self, fields):
        self.minute, self.hour, self.day, self.month, self.weekday = fields

    def fields(self):
        return [self.minute, self.hour, self.day, self.month, self.weekday]


def _value(text, name):
    lo, hi = settings.BOUNDS[name]
    if text.isascii() and text.isdigit():
        v = int(text)
        if v < lo or v > hi:
            raise RangeError("field %r: value %d out of range %d-%d" % (name, v, lo, hi))
        return v
    v = None
    if name == "month":
        v = _lookup(MONTHS, text)
    if name == "day-of-week":
        v = _lookup(DAYS, text)
    if v is None:
        raise ParseError("field %r: bad value %r" % (name, text))
    return v


def parse_field(text, name):
    """Parse one comma-separated field."""
    lo, hi = settings.BOUNDS[name]
    values = set()
    specials = set()
    for item in text.split(","):
        if name == "day-of-month":
            if item == "L":
                specials.add(("L", 0, 0))
                continue
            if item == "LW":
                specials.add(("LW", 0, 0))
                continue
            m = _offset_re.match(item)
            if m:
                n = int(m.group(1))
                if n > 30:
                    raise RangeError("field 'day-of-month': offset %d out of range 0-30" % n)
                specials.add(("L-", n, 0))
                continue
            m = _nearest_re.match(item)
            if m:
                n = int(m.group(1))
                if n < lo or n > hi:
                    raise RangeError("field %r: value %d out of range %d-%d" % (name, n, lo, hi))
                specials.add(("W", n, 0))
                continue
        if name == "day-of-week":
            m = _last_re.match(item)
            if m:
                specials.add(("dL", _value(m.group(1), name) % 7, 0))
                continue
            m = _nth_re.match(item)
            if m:
                k = int(m.group(2))
                if k < 1 or k > 5:
                    raise RangeError("field 'day-of-week': nth %d out of range 1-5" % k)
                specials.add(("#", _value(m.group(1), name) % 7, k))
                continue
        m = _plain_re.match(item)
        if m is None or (item.startswith("?") and name not in ("day-of-month", "day-of-week")):
            raise ParseError("field %r: bad item %r" % (name, item))
        step = 1
        if m.group(2) is not None:
            step = int(m.group(2))
            if step == 0:
                raise ParseError("field %r: step 0 is not allowed" % (name,))
        base = m.group(1)
        if base == "*" or base == "?":
            a, b = lo, hi
        else:
            if "-" in base:
                left, right = base.split("-")
                a = _value(left, name)
                b = _value(right, name)
            else:
                a = _value(base, name)
                b = hi if m.group(2) is not None else a
            if a > b:
                raise ParseError("field %r: range %d-%d is reversed" % (name, a, b))
        for v in range(a, b + 1, step):
            if name == "day-of-week":
                v = v % 7
            values.add(v)
    ordered = sorted(specials, key=lambda s: (SPECIAL_ORDER.index(s[0]), s[1], s[2]))
    return fieldSpec(name, values, tuple(ordered), text[:1] in ("*", "?"))


def parse(text):
    """Parse a five-field expression or a macro."""
    if not isinstance(text, str):
        raise ParseError("not a string: %r" % (text,))
    body = text.strip()
    if body.startswith("@"):
        if body.lower() not in MACROS:
            raise ParseError("unknown macro: %r" % (body,))
        body = MACROS[body.lower()]
    parts = body.split()
    if len(parts) != 5:
        raise ParseError("expected 5 fields, got %d" % len(parts))
    return Schedule([parse_field(p, n) for p, n in zip(parts, settings.FIELD_NAMES)])
