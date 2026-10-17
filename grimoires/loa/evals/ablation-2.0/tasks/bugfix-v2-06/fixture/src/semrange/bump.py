"""Computing the next version: ``inc(version, kind, preid=None)``."""
from .errors import InvalidIncrement
from .identifiers import is_identifier, is_numeric
from .version import Version, coerce_version

KINDS = ("major", "minor", "patch", "premajor", "preminor", "prepatch",
         "prerelease")


def _check_preid(preid):
    if preid is None:
        return
    if not isinstance(preid, str) or not is_identifier(preid) or is_numeric(preid):
        raise InvalidIncrement(f"invalid preid: {preid!r}")


def inc(version, kind, preid=None):
    """Return the incremented version as a canonical string.

    The version is parsed first (``InvalidVersion``), then the kind and the
    prerelease id are checked (``InvalidIncrement``).  Build metadata is
    always dropped.
    """
    v = coerce_version(version)
    if kind not in KINDS:
        raise InvalidIncrement(f"unknown increment: {kind!r}")
    _check_preid(preid)
    start = (preid, "0") if preid is not None else ("0",)
    major, minor, patch, pre = v.major, v.minor, v.patch, v.prerelease
    if kind == "major":
        out = (major, 0, 0, ()) if pre and minor == 0 and patch == 0 \
            else (major + 1, 0, 0, ())
    elif kind == "minor":
        out = (major, minor, 0, ()) if pre and patch == 0 \
            else (major, minor + 1, 0, ())
    elif kind == "patch":
        out = (major, minor, patch + 1, ())
    elif kind == "premajor":
        out = (major + 1, 0, 0, start)
    elif kind == "preminor":
        out = (major, minor + 1, 0, start)
    elif kind == "prepatch":
        out = (major, minor, patch + 1, start)
    else:
        out = _next_prerelease(major, minor, patch, pre, start)
    return str(Version(*out))


def _next_prerelease(major, minor, patch, pre, start):
    if not pre:
        return (major, minor, patch + 1, start)
    ids = list(pre)
    for i in range(len(ids) - 1, -1, -1):
        if is_numeric(ids[i]):
            ids[i] = str(int(ids[i]) + 1)
            break
    else:
        ids.append("0")
    return (major, minor, patch, tuple(ids))
