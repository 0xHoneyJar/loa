"""Users and their groups, read from ``user: group, group`` lines."""
import re

from .errors import DirectoryError

NAME = re.compile(r"[A-Za-z0-9_.-]+")


class Directory:
    def __init__(self, members=None):
        self._groups = {user: frozenset(groups) for user, groups in (members or {}).items()}

    def groups_of(self, user):
        """The user's groups; an unknown user has none."""
        return self._groups.get(user, frozenset())

    def users(self):
        return sorted(self._groups)


def parse_directory(text):
    members = {}
    for number, raw in enumerate(text.splitlines(), start=1):
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        user, sep, rest = line.partition(":")
        user = user.strip()
        groups = [g.strip() for g in rest.split(",") if g.strip()]
        if not sep or not NAME.fullmatch(user) or not all(NAME.fullmatch(g) for g in groups):
            raise DirectoryError(f"users:{number}: expected 'user: group, group'")
        if user in members:
            raise DirectoryError(f"users:{number}: {user} listed twice")
        members[user] = groups
    return Directory(members)
