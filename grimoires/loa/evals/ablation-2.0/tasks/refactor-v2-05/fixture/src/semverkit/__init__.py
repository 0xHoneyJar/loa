"""Semantic versions and npm-style ranges."""
import functools

from .core import Version, InvalidVersion, parse, bump, compare_versions, _sort_cmp, _fmt
from .ranges import InvalidRange, satisfies, max_satisfying, min_satisfying, normalize_range


def valid(text):
    """Return the canonical form of a version string, or None."""
    try:
        return _fmt(parse(text))
    except Exception:
        return None


def compare(a, b):
    """Compare two version strings by precedence."""
    return compare_versions(parse(a), parse(b))


def sort(texts):
    """Sort version strings by precedence, keeping their spelling."""
    pairs = [(parse(t), t) for t in texts]
    pairs.sort(key=functools.cmp_to_key(_sort_cmp))
    return [t for _, t in pairs]


from .report import render_table  # noqa: E402  (report needs sort)
