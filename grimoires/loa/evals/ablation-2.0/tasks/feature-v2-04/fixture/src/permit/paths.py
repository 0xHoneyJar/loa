"""Resource paths: absolute, slash-separated, without ``.`` or ``..`` segments."""
from .errors import PathError


def normalize(path):
    """``"/docs//a/"`` -> ``"/docs/a"``; PathError for a relative or unclean path."""
    if not isinstance(path, str) or not path.startswith("/"):
        raise PathError(f"bad path: {path!r}")
    parts = [p for p in path.split("/") if p]
    if any(p in (".", "..") for p in parts):
        raise PathError(f"bad path: {path!r}")
    return "/" + "/".join(parts)


def segments(path):
    """The segments of a normalised path; the root has none."""
    return [p for p in normalize(path).split("/") if p]
