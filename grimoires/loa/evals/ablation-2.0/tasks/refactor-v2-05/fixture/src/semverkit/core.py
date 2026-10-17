"""Versions: parsing, ordering and bumping."""
import re
from typing import Optional

from . import config
from .utils import _strip, _sign, _is_num, _fmt, isWord

_version_re = re.compile(
    r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)"
    r"(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$"
)

_parse_count = 0


class InvalidVersion(ValueError):
    pass


class Version:
    """A parsed semantic version."""

    def __init__(self, major, minor, patch, prerelease=(), build=()):
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = tuple(prerelease)
        self.build = tuple(build)

    def __eq__(self, other):
        if not isinstance(other, Version):
            return NotImplemented
        return (self.major, self.minor, self.patch, self.prerelease, self.build) == (
            other.major, other.minor, other.patch, other.prerelease, other.build)

    def __hash__(self):
        return hash((self.major, self.minor, self.patch, self.prerelease, self.build))

    def __repr__(self):
        return "Version(major=%r, minor=%r, patch=%r, prerelease=%r, build=%r)" % (
            self.major, self.minor, self.patch, self.prerelease, self.build)


def parse(text):
    """Parse one version string, accepting a leading = and v."""
    global _parse_count
    _parse_count += 1
    if not isinstance(text, str):
        raise InvalidVersion("not a string: %r" % (text,))
    if len(text) > config.get("max_length"):
        raise InvalidVersion("version too long")
    m = _version_re.match(_strip(text))
    if m is None:
        raise InvalidVersion("invalid version: %r" % (text,))
    pre = []
    if m.group(4):
        for ident in m.group(4).split("."):
            if _is_num(ident):
                if len(ident) > 1 and ident[0] == "0":
                    raise InvalidVersion("invalid version: %r" % (text,))
                pre.append(int(ident))
            else:
                pre.append(ident)
    build = m.group(5).split(".") if m.group(5) else []
    return Version(int(m.group(1)), int(m.group(2)), int(m.group(3)), pre, build)


def _fmt(v):
    return "%d.%d.%d" % (v.major, v.minor, v.patch) + (
        ("-" + ".".join(str(x) for x in v.prerelease)) if v.prerelease else "") + (
        ("+" + ".".join(v.build)) if v.build else "")


def toStr(v):
    return _fmt(v)


def compare_versions(a, b):
    """Return -1, 0 or 1 by precedence; build metadata is ignored."""
    if a.major != b.major:
        return _sign(a.major, b.major)
    if a.minor != b.minor:
        return _sign(a.minor, b.minor)
    if a.patch != b.patch:
        return _sign(a.patch, b.patch)
    pa, pb = a.prerelease, b.prerelease
    if not pa and not pb:
        return 0
    if not pa:
        return 1
    if not pb:
        return -1
    i = 0
    while i < len(pa) and i < len(pb):
        x, y = pa[i], pb[i]
        if isinstance(x, int) and isinstance(y, int):
            if x != y:
                return _sign(x, y)
        elif isinstance(x, int):
            return -1
        elif isinstance(y, int):
            return 1
        else:
            if x != y:
                return _sign(x, y)
        i += 1
    return _sign(len(pa), len(pb))


def _sort_cmp(a, b):
    c = compare_versions(a[0], b[0])
    if c:
        return c
    return _sign(_fmt(a[0]), _fmt(b[0]))


def bump(text, part, ident: Optional[str] = None):
    """Bump one part of a version string."""
    if part not in ("major", "minor", "patch", "prerelease", "release"):
        raise ValueError("unknown part: %r" % (part,))
    v = parse(text)
    if ident is not None:
        if part != "prerelease":
            raise ValueError("identifier only applies to prerelease")
        if not isWord(ident):
            raise ValueError("invalid identifier: %r" % (ident,))
    if part == "major":
        if v.prerelease and v.minor == 0 and v.patch == 0:
            n = Version(v.major, 0, 0)
        else:
            n = Version(v.major + 1, 0, 0)
    elif part == "minor":
        if v.prerelease and v.patch == 0:
            n = Version(v.major, v.minor, 0)
        else:
            n = Version(v.major, v.minor + 1, 0)
    elif part == "patch":
        if v.prerelease:
            n = Version(v.major, v.minor, v.patch)
        else:
            n = Version(v.major, v.minor, v.patch + 1)
    elif part == "prerelease":
        if not v.prerelease:
            if ident is not None:
                n = Version(v.major, v.minor, v.patch + 1, (ident, 0))
            else:
                n = Version(v.major, v.minor, v.patch + 1, (0,))
        else:
            pre = v.prerelease
            if ident is not None and pre[0] != ident:
                pre = (ident, 0)
            elif isinstance(pre[-1], int):
                pre = pre[:-1] + (pre[-1] + 1,)
            else:
                pre = pre + (0,)
            n = Version(v.major, v.minor, v.patch, pre)
    else:
        if not v.prerelease:
            raise ValueError("already a release: %r" % (_fmt(v),))
        n = Version(v.major, v.minor, v.patch)
    return toStr(n)


def satisfies_version(v, sets, include_prerelease=None):
    """Check a parsed version against parsed comparator sets."""
    from .ranges import test_set
    if include_prerelease is None:
        include_prerelease = config.get("include_prerelease")
    for group in sets:
        if test_set(v, group, include_prerelease):
            return True
    return False
