"""Choosing versions from a list by a range.

The list functions build a ``VersionIndex`` and ask it; a caller with many
queries over one list builds the index once itself.
"""
from .index import VersionIndex
from .range import coerce_range
from .version import coerce_version


def satisfies(version, range_):
    """True when ``version`` is in ``range_``.

    An invalid version raises ``InvalidVersion``; an invalid range raises
    ``InvalidRange``.
    """
    return coerce_range(range_).test(coerce_version(version))


def filter_satisfying(versions, range_):
    """The items of ``versions`` in the range, in input order."""
    return VersionIndex(versions).filter_satisfying(range_)


def max_satisfying(versions, range_):
    """The item of highest precedence in the range, or None.

    Among items of equal precedence the first in input order wins.
    """
    return VersionIndex(versions).max_satisfying(range_)


def min_satisfying(versions, range_):
    """The item of lowest precedence in the range, or None (first wins ties)."""
    return VersionIndex(versions).min_satisfying(range_)
