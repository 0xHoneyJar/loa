"""Turning range terms into primitive comparators.

Every upper bound that excludes a whole release line is written with the
lowest possible prerelease ``-0`` (``<2.0.0-0`` rather than ``<2.0.0``), so
that no prerelease of the excluded line slips through.
"""
from .comparator import Comparator
from .rangeparse import HyphenTerm
from .version import Version

LOWEST = ("0",)


def _v(major, minor, patch, prerelease=()):
    return Version(major, minor, patch, prerelease)


def _any():
    return [Comparator(">=", _v(0, 0, 0))]


def primitive(op, p):
    """``op`` in ``< <= > >= =`` applied to the partial version ``p``."""
    if p.major is None:
        return _any()
    if p.patch is not None:
        return [Comparator(op, _v(p.major, p.minor, p.patch, p.prerelease))]
    # fill the missing components with zeros
    low = _v(p.major, p.minor or 0, 0)
    if op == "=":
        if p.minor is None:
            high = _v(p.major + 1, 0, 0, LOWEST)
        else:
            high = _v(p.major, p.minor + 1, 0, LOWEST)
        return [Comparator(">=", low), Comparator("<", high)]
    if op == "<":
        return [Comparator("<", _v(low.major, low.minor, 0, LOWEST))]
    return [Comparator(op, low)]


def tilde(p):
    """``~``: patch-level changes, or minor-level ones when only X is given."""
    if p.major is None:
        return _any()
    minor = p.minor or 0
    patch = p.patch or 0
    return [Comparator(">=", _v(p.major, minor, patch, p.prerelease)),
            Comparator("<", _v(p.major, minor + 1, 0, LOWEST))]


def caret(p):
    """``^``: changes that keep the left-most non-zero component."""
    if p.major is None:
        return _any()
    if p.minor is None:
        return [Comparator(">=", _v(p.major, 0, 0)),
                Comparator("<", _v(p.major + 1, 0, 0, LOWEST))]
    if p.patch is None:
        low = _v(p.major, p.minor, 0)
        if p.major > 0:
            high = _v(p.major + 1, 0, 0, LOWEST)
        else:
            high = _v(0, p.minor + 1, 0, LOWEST)
        return [Comparator(">=", low), Comparator("<", high)]
    low = _v(p.major, p.minor, p.patch, p.prerelease)
    if p.major > 0:
        high = _v(p.major + 1, 0, 0, LOWEST)
    else:
        high = _v(0, p.minor + 1, 0, LOWEST)
    return [Comparator(">=", low), Comparator("<", high)]


def hyphen(low, high):
    """``A - B``: ``>=`` the low end, up to and including the high end."""
    if low.major is None:
        out = _any()
    else:
        out = [Comparator(">=", _v(low.major, low.minor or 0, low.patch or 0,
                                   low.prerelease))]
    if high.major is None:
        return out
    out.append(Comparator("<=", _v(high.major, high.minor or 0, high.patch or 0,
                                   high.prerelease)))
    return out


def desugar_term(term):
    """The comparators of one parsed term, in order."""
    if isinstance(term, HyphenTerm):
        return hyphen(term.low, term.high)
    if term.op == "~":
        return tilde(term.partial)
    if term.op == "^":
        return caret(term.partial)
    return primitive(term.op, term.partial)


def desugar_set(terms):
    out = []
    for term in terms:
        out.extend(desugar_term(term))
    return out
