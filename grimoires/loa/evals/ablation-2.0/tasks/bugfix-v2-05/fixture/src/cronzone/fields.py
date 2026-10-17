"""Parsing one field of an expression into a set of values and specials."""
import re
from dataclasses import dataclass, field
from typing import FrozenSet, Tuple

from .errors import CronError
from .names import DOM, DOW

_NUMBER = re.compile(r"[0-9]+")


@dataclass(frozen=True)
class FieldSet:
    """The values a field allows, its day specials and whether it restricts."""

    values: FrozenSet[int]
    specials: Tuple[tuple, ...] = ()
    restricted: bool = True
    text: str = field(default="", compare=False)


def _value(token, spec, raw):
    """One number or name of ``spec``; range-checked."""
    upper = token.upper()
    if upper in spec.names:
        return spec.names[upper]
    if _NUMBER.fullmatch(token) is None:
        raise CronError(f"invalid {spec.name} value: {raw!r}")
    number = int(token)
    if not spec.lo <= number <= spec.hi:
        raise CronError(f"{spec.name} value out of range: {raw!r}")
    return number


def _special(token, spec, raw):
    """A day special (``L``, ``L-n``, ``nW``, ``LW``, ``d#k``, ``dL``) or None."""
    upper = token.upper()
    if spec is DOM:
        if upper == "L":
            return ("last", 0)
        if upper == "LW":
            return ("last-weekday",)
        m = re.fullmatch(r"L-([0-9]+)", upper)
        if m:
            n = int(m.group(1))
            if not 1 <= n <= 30:
                raise CronError(f"{spec.name} value out of range: {raw!r}")
            return ("last", n)
        m = re.fullmatch(r"([0-9]+)W", upper)
        if m:
            n = int(m.group(1))
            if not 1 <= n <= 31:
                raise CronError(f"{spec.name} value out of range: {raw!r}")
            return ("nearest-weekday", n)
    if spec is DOW:
        m = re.fullmatch(r"([0-9A-Z]+)#([0-9]+)", upper)
        if m:
            day = _value(m.group(1), spec, raw) % 7
            k = int(m.group(2))
            if not 1 <= k <= 5:
                raise CronError(f"{spec.name} value out of range: {raw!r}")
            return ("nth", day, k)
        m = re.fullmatch(r"([0-9A-Z]+)L", upper)
        if m and upper != "L":
            return ("last-dow", _value(m.group(1), spec, raw) % 7)
    return None


def _element(token, spec):
    """Values of one comma-separated element (no specials)."""
    raw = token
    base, slash, step_text = token.partition("/")
    if base in ("*", "?") and (base == "*" or spec in (DOM, DOW)):
        lo, hi = 0, spec.hi
    elif "-" in base:
        first, _, last = base.partition("-")
        lo, hi = _value(first, spec, raw), _value(last, spec, raw)
        if lo > hi:
            raise CronError(f"invalid {spec.name} range: {raw!r}")
    else:
        lo = _value(base, spec, raw)
        hi = spec.hi if slash else lo
    step = 1
    if slash:
        if _NUMBER.fullmatch(step_text) is None or int(step_text) == 0:
            raise CronError(f"invalid {spec.name} step: {raw!r}")
        step = int(step_text)
    return set(range(lo, hi + 1, step))


def parse_field(text, spec):
    """Parse the text of one field."""
    if text == "":
        raise CronError(f"invalid {spec.name} value: {text!r}")
    values, specials = set(), []
    for token in text.split(","):
        special = _special(token, spec, token) if spec in (DOM, DOW) else None
        if special is not None:
            specials.append(special)
        else:
            values |= _element(token, spec)
    if spec is DOW:
        values = {v % 7 for v in values}
    restricted = not (spec in (DOM, DOW) and text == "*")
    return FieldSet(frozenset(values), tuple(specials), restricted, text)
