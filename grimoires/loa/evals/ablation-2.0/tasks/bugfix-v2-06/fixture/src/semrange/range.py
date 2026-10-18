"""The ``Range`` value: comparator sets and the satisfaction test."""
from .desugar import desugar_set
from .rangeparse import parse_range_text
from .version import coerce_version


class Range:
    """A parsed range expression.

    ``sets`` is a list of comparator lists.  A version satisfies the range
    when it satisfies at least one set.
    """

    __slots__ = ("text", "sets")

    def __init__(self, text):
        self.text = text
        self.sets = [desugar_set(terms) for terms in parse_range_text(text)]

    def test(self, version):
        """True when ``version`` (string or ``Version``) is in the range."""
        v = coerce_version(version)
        if v.prerelease and not self._names_prerelease_of(v):
            return False
        return any(all(c.test(v) for c in comparators)
                   for comparators in self.sets)

    def _names_prerelease_of(self, version):
        """True when some comparator names a prerelease of the same release."""
        return any(c.version.prerelease and c.version.core == version.core
                   for comparators in self.sets for c in comparators)

    def __contains__(self, version):
        return self.test(version)

    def __str__(self):
        return " || ".join(" ".join(str(c) for c in comparators)
                           for comparators in self.sets)

    def __repr__(self):
        return f"Range({str(self)!r})"


def coerce_range(value):
    """A ``Range`` is returned as is; anything else is parsed."""
    if isinstance(value, Range):
        return value
    return Range(value)
