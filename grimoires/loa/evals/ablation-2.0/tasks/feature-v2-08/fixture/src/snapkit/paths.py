"""Relative path handling.

Every path snapkit works with is relative to the snapshot root, uses ``/`` as
the separator, is never empty and never starts or ends with ``/``.
"""
from .errors import PathError


def normalize(path):
    """Return the canonical form of a user-supplied relative path.

    Repeated slashes and ``.`` segments are dropped, as are leading ``./`` and
    trailing slashes.  An absolute path, a ``..`` segment or a path that is
    empty after normalising raises ``PathError``.
    """
    if not isinstance(path, str):
        raise PathError(f"not a path: {path!r}")
    if path.startswith("/"):
        raise PathError(f"absolute path not allowed: {path!r}")
    parts = []
    for seg in path.split("/"):
        if seg in ("", "."):
            continue
        if seg == "..":
            raise PathError(f"'..' not allowed: {path!r}")
        parts.append(seg)
    if not parts:
        raise PathError(f"empty path: {path!r}")
    return "/".join(parts)


def join(parent, name):
    """Join a directory path (``""`` for the root) and an entry name."""
    return name if parent == "" else f"{parent}/{name}"


def parent_of(path):
    """Return the directory part of ``path`` (``""`` for a top-level entry)."""
    head, _, _ = path.rpartition("/")
    return head


def depth(path):
    """Number of segments in ``path``; the root ``""`` has depth 0."""
    return 0 if path == "" else path.count("/") + 1


def ancestors(path):
    """Proper ancestor directories of ``path``, shallowest first."""
    parts = path.split("/")
    return ["/".join(parts[:k]) for k in range(1, len(parts))]


def sort_key(path):
    """Snapshot order: plain string order of the relative path."""
    return path
