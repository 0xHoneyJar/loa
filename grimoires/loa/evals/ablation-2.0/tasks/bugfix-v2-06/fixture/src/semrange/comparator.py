"""A primitive comparator: an operator and a full version."""
from .version import compare_versions

OPERATORS = ("<", "<=", ">", ">=", "=")

_TESTS = {
    "<": lambda c: c < 0,
    "<=": lambda c: c <= 0,
    ">": lambda c: c > 0,
    ">=": lambda c: c >= 0,
    "=": lambda c: c == 0,
}


class Comparator:
    """``op`` is one of ``OPERATORS``; ``version`` is a ``Version``."""

    __slots__ = ("op", "version")

    def __init__(self, op, version):
        if op not in _TESTS:
            raise ValueError(f"unknown operator: {op!r}")
        self.op = op
        self.version = version

    def test(self, version):
        """True when ``version`` stands in this relation to the bound."""
        return _TESTS[self.op](compare_versions(version, self.version))

    def __str__(self):
        prefix = "" if self.op == "=" else self.op
        return prefix + str(self.version)

    def __repr__(self):
        return f"Comparator({str(self)!r})"

    def __eq__(self, other):
        if not isinstance(other, Comparator):
            return NotImplemented
        return self.op == other.op and str(self.version) == str(other.version)

    def __hash__(self):
        return hash((self.op, str(self.version)))
