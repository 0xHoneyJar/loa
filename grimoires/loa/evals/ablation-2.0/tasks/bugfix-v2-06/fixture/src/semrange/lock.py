"""A small lock-file format: ``name = version`` lines, ``#`` comments.

``parse_lock(text)`` returns an ordered dict of name to version string and
raises ``LockError`` (a ``VersionError``) with ``line <n>: <reason>`` for a
malformed line.  ``check_lock(requirements, lock)`` lists the problems of a
lock against the requirements, in requirement-name order.
"""
from .errors import InvalidVersion, VersionError
from .select import satisfies
from .version import parse


class LockError(VersionError):
    """A lock file line is malformed."""


def parse_lock(text):
    entries = {}
    for number, raw in enumerate(text.splitlines(), start=1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            raise LockError(f"line {number}: expected name = version")
        name, _, version = (part.strip() for part in line.partition("="))
        if not name:
            raise LockError(f"line {number}: missing name")
        if name in entries:
            raise LockError(f"line {number}: duplicate name {name}")
        try:
            parse(version)
        except InvalidVersion:
            raise LockError(f"line {number}: bad version {version}") from None
        entries[name] = version
    return entries


def dump_lock(entries):
    return "".join(f"{name} = {version}\n" for name, version in entries.items())


def check_lock(requirements, lock):
    problems = []
    for name in sorted(requirements):
        if name not in lock:
            problems.append(f"{name}: not locked")
        elif not satisfies(lock[name], requirements[name]):
            problems.append(f"{name}: {lock[name]} is outside {requirements[name]}")
    for name in sorted(set(lock) - set(requirements)):
        problems.append(f"{name}: not required")
    return problems
