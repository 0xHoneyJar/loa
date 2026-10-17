"""The built-in steps; each takes a list of strings and returns JSON data."""
from .errors import PipelineError


def _strings(items, step):
    if not isinstance(items, list) or not all(isinstance(s, str) for s in items):
        raise PipelineError(f"{step}: expected a list of strings")
    return items


def strip(items):
    return [s.strip() for s in _strings(items, "strip")]


def lower(items):
    return [s.lower() for s in _strings(items, "lower")]


def nonempty(items):
    return [s for s in _strings(items, "nonempty") if s]


def dedupe(items):
    """Drop repeats, keeping the first occurrence."""
    seen = set()
    out = []
    for s in _strings(items, "dedupe"):
        if s not in seen:
            seen.add(s)
            out.append(s)
    return out


def sort(items):
    return sorted(_strings(items, "sort"))


def count(items):
    """``{item: occurrences}`` with the keys in sorted order."""
    counts = {}
    for s in _strings(items, "count"):
        counts[s] = counts.get(s, 0) + 1
    return dict(sorted(counts.items()))


REGISTRY = {"strip": strip, "lower": lower, "nonempty": nonempty, "dedupe": dedupe, "sort": sort, "count": count}
