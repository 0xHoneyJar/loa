"""Comparison helpers over versions given as strings or ``Version`` objects."""
from functools import cmp_to_key

from .version import compare_versions, coerce_version


def compare(a, b):
    """-1, 0 or 1 as ``a`` has lower, equal or higher precedence than ``b``."""
    return compare_versions(coerce_version(a), coerce_version(b))


def gt(a, b):
    return compare(a, b) > 0


def lt(a, b):
    return compare(a, b) < 0


def eq(a, b):
    return compare(a, b) == 0


def sort_versions(versions, reverse=False):
    """Return the versions as ``Version`` objects in precedence order.

    ``reverse=True`` gives the newest version first.
    """
    items = [coerce_version(v) for v in versions]
    ordered = sorted(items, key=cmp_to_key(compare_versions))
    if reverse:
        ordered.reverse()
    return ordered
