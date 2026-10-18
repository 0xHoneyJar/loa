"""The ``Version`` value and the version parser."""
import re
from functools import total_ordering

from .errors import InvalidVersion
from .identifiers import (compare_prerelease, split_identifiers,
                          valid_build_identifier, valid_prerelease_identifier)

NUMBER = r"[0-9]+"
_VERSION = re.compile(
    rf"(?P<major>{NUMBER})\.(?P<minor>{NUMBER})\.(?P<patch>{NUMBER})"
    r"(?:-(?P<pre>[^+]*))?(?:\+(?P<build>.*))?",
    re.DOTALL,
)


@total_ordering
class Version:
    """A semantic version: three numbers, a prerelease and a build tuple.

    ``prerelease`` and ``build`` are tuples of identifier strings.  Versions
    compare by precedence; build metadata takes no part in it, so two
    versions that differ only in their build compare equal.
    """

    __slots__ = ("major", "minor", "patch", "prerelease", "build")

    def __init__(self, major, minor, patch, prerelease=(), build=()):
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = tuple(prerelease)
        self.build = tuple(build)

    @property
    def core(self):
        """The ``(major, minor, patch)`` triple."""
        return (self.major, self.minor, self.patch)

    @property
    def is_prerelease(self):
        return bool(self.prerelease)

    def __str__(self):
        text = f"{self.major}.{self.minor}.{self.patch}"
        if self.prerelease:
            text += "-" + ".".join(self.prerelease)
        if self.build:
            text += "+" + ".".join(self.build)
        return text

    def __repr__(self):
        return f"Version({str(self)!r})"

    def __eq__(self, other):
        if not isinstance(other, Version):
            return NotImplemented
        return compare_versions(self, other) == 0

    def __lt__(self, other):
        if not isinstance(other, Version):
            return NotImplemented
        return compare_versions(self, other) < 0

    def __hash__(self):
        return hash((self.core, self.prerelease))


def compare_versions(a, b):
    """Precedence of two ``Version`` objects: -1, 0 or 1."""
    if a.core != b.core:
        return (a.core > b.core) - (a.core < b.core)
    return compare_prerelease(a.prerelease, b.prerelease)


def parse(text):
    """Parse a version string into a ``Version`` or raise ``InvalidVersion``."""
    if not isinstance(text, str):
        raise InvalidVersion(text)
    body = text.strip()
    if body.startswith("v"):
        body = body[1:]
    m = _VERSION.fullmatch(body)
    if not m:
        raise InvalidVersion(text)
    pre, build = (), ()
    if m.group("pre") is not None:
        pre = split_identifiers(m.group("pre"), valid_prerelease_identifier)
        if pre is None:
            raise InvalidVersion(text)
    if m.group("build") is not None:
        build = split_identifiers(m.group("build"), valid_build_identifier)
        if build is None:
            raise InvalidVersion(text)
    return Version(int(m.group("major")), int(m.group("minor")),
                   int(m.group("patch")), pre, build)


def valid(text):
    """The canonical form of ``text`` if it is a valid version, else None."""
    try:
        return str(parse(text))
    except InvalidVersion:
        return None


def coerce_version(value):
    """A ``Version`` is returned as is; anything else goes through ``parse``."""
    if isinstance(value, Version):
        return value
    return parse(value)
