"""Differences between two snapshots.

Each line is ``A <path>`` (only in the new snapshot), ``D <path>`` (only in
the old one) or ``M <path>`` (in both, digest or size differs), sorted by
path; a summary line ``<a> added, <d> deleted, <m> modified`` ends the output.
"""
from .paths import sort_key


def diff_snapshots(old, new):
    """Return a list of ``(code, path)`` tuples sorted by path."""
    before, after = old.by_path(), new.by_path()
    changes = []
    for path in set(before) | set(after):
        if path not in before:
            changes.append(("A", path))
        elif path not in after:
            changes.append(("D", path))
        elif (before[path].digest, before[path].size) != (after[path].digest, after[path].size):
            changes.append(("M", path))
    changes.sort(key=lambda c: sort_key(c[1]))
    return changes


def format_diff(changes):
    counts = {"A": 0, "D": 0, "M": 0}
    lines = []
    for code, path in changes:
        counts[code] += 1
        lines.append(f"{code} {path}")
    lines.append(f"{counts['A']} added, {counts['D']} deleted, {counts['M']} modified")
    return "\n".join(lines) + "\n"
