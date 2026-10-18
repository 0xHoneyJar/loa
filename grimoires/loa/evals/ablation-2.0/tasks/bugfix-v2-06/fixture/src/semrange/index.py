"""``VersionIndex``: a version list prepared once for many range queries.

The valid entries are sorted once by precedence, input position breaking
ties, so every comparator set of a range is answered by bisecting over the
interval its comparators bound instead of testing every entry.  Releases
and prereleases are kept apart: a set admits a prerelease only through a
comparator of the same set naming a prerelease of the same release, so the
prereleases are grouped by their ``(major, minor, patch)`` and only the
groups a set names are searched.

A query plan (the intervals and the prerelease groups of each set) is
cached per range text; whitespace does not change a plan, so the cache key
is the text with its whitespace removed.
"""
from bisect import bisect_left, bisect_right
from functools import cmp_to_key

from .errors import InvalidVersion
from .range import Range
from .version import compare_versions, coerce_version

KEY = cmp_to_key(compare_versions)


class _Line:
    """Entries ``(position, item, version)`` sorted by precedence, then position."""

    __slots__ = ("entries", "keys")

    def __init__(self, entries):
        self.entries = sorted(entries, key=lambda e: (KEY(e[2]), e[0]))
        self.keys = [KEY(e[2]) for e in self.entries]

    def span(self, interval):
        """``(start, stop)`` of the entries inside ``interval``."""
        lo, lo_incl, hi, hi_incl = interval
        keys = self.keys
        start = 0 if lo is None else bisect_left(keys, KEY(lo))
        if lo is not None and not lo_incl:
            start += 1  # step over the bound itself
        stop = len(keys) if hi is None else bisect_right(keys, KEY(hi))
        return start, max(start, stop)

    def highest(self, interval):
        """The earliest entry of the highest precedence inside, or None."""
        start, stop = self.span(interval)
        return self.entries[stop - 1] if start < stop else None

    def lowest(self, interval):
        start, stop = self.span(interval)
        return self.entries[start] if start < stop else None

    def inside(self, interval):
        start, stop = self.span(interval)
        return self.entries[start:stop]


def _interval(comparators):
    """``(lo, lo_inclusive, hi, hi_inclusive)`` bounded by a set's comparators.

    Of two bounds on the same side the stricter wins.
    """
    lo, lo_incl, hi, hi_incl = None, True, None, True
    for c in comparators:
        v = c.version
        if c.op in (">", ">=", "="):
            if lo is None or compare_versions(v, lo) > 0:
                lo, lo_incl = v, c.op != ">"
        if c.op in ("<", "<=", "="):
            if hi is None or compare_versions(v, hi) < 0:
                hi, hi_incl = v, c.op != "<"
    return lo, lo_incl, hi, hi_incl


def _plan(range_):
    """Per set: its interval and the release lines whose prereleases it admits."""
    lines = sorted({c.version.core for comparators in range_.sets
                    for c in comparators if c.version.prerelease})
    return [(_interval(comparators), lines) for comparators in range_.sets]


def _better(a, b, sign):
    """The entry that wins between ``a`` and ``b``: precedence, then position."""
    if a is None:
        return b
    if b is None:
        return a
    d = compare_versions(a[2], b[2]) * sign
    if d > 0 or (d == 0 and a[0] < b[0]):
        return a
    return b


class VersionIndex:
    """Answers ``max_satisfying``, ``min_satisfying`` and ``filter_satisfying``
    over the list given at construction; items that are not valid versions are
    skipped.  ``len(index)`` is the number of valid entries."""

    def __init__(self, versions):
        releases, pre = [], {}
        count = 0
        for position, item in enumerate(list(versions)):
            try:
                v = coerce_version(item)
            except InvalidVersion:
                continue
            count += 1
            if v.prerelease:
                pre.setdefault(v.core, []).append((position, item, v))
            else:
                releases.append((position, item, v))
        self._count = count
        self._releases = _Line(releases)
        self._pre = {core: _Line(entries) for core, entries in pre.items()}
        self._plans = {}

    def __len__(self):
        return self._count

    def _plan_for(self, range_):
        if isinstance(range_, Range):
            return _plan(range_)
        key = "".join(range_.split()) if isinstance(range_, str) else range_
        plan = self._plans.get(key)
        if plan is None:
            plan = self._plans[key] = _plan(Range(range_))
        return plan

    def _lines(self, lines):
        yield self._releases
        for core in lines:
            line = self._pre.get(core)
            if line is not None:
                yield line

    def max_satisfying(self, range_):
        best = None
        for interval, lines in self._plan_for(range_):
            for line in self._lines(lines):
                best = _better(best, line.highest(interval), 1)
        return None if best is None else best[1]

    def min_satisfying(self, range_):
        best = None
        for interval, lines in self._plan_for(range_):
            for line in self._lines(lines):
                best = _better(best, line.lowest(interval), -1)
        return None if best is None else best[1]

    def filter_satisfying(self, range_):
        out, seen = [], set()
        for interval, lines in self._plan_for(range_):
            hits = []
            for line in self._lines(lines):
                hits.extend(line.inside(interval))
            for position, item, _ in sorted(hits, key=lambda e: e[0]):
                if position not in seen:
                    seen.add(position)
                    out.append(item)
        return out
