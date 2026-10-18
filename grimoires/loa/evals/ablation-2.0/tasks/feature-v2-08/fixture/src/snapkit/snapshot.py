"""Snapshots: a manifest of every kept file with its digest and size.

Text form::

    snapkit-snapshot 1
    <digest> <size> <path>
    ...
    total <files> files <bytes> bytes

The file lines are sorted by path in plain string order.  A path may contain
spaces; it is everything after the second space of its line.
"""
from . import digest, walker
from .errors import SnapshotError
from .paths import sort_key

HEADER = "snapkit-snapshot 1"


class Record:
    __slots__ = ("path", "size", "digest")

    def __init__(self, path, size, digest_hex):
        self.path = path
        self.size = size
        self.digest = digest_hex

    def __eq__(self, other):
        return isinstance(other, Record) and (self.path, self.size, self.digest) == (
            other.path, other.size, other.digest)

    def __repr__(self):
        return f"Record({self.path!r}, {self.size!r}, {self.digest!r})"


class Snapshot:
    def __init__(self, records=()):
        self.records = sorted(records, key=lambda r: sort_key(r.path))

    @property
    def total_bytes(self):
        return sum(r.size for r in self.records)

    def paths(self):
        return [r.path for r in self.records]

    def by_path(self):
        return {r.path: r for r in self.records}


def build_snapshot(root, config, exclusions=None):
    records = []
    for entry in walker.files(root, config, exclusions):
        records.append(Record(entry.path, entry.size,
                              digest.digest_file(root, entry.path, config.digest_length)))
    return Snapshot(records)


def format_snapshot(snapshot):
    lines = [HEADER]
    for r in snapshot.records:
        lines.append(f"{r.digest} {r.size} {r.path}")
    lines.append(f"total {len(snapshot.records)} files {snapshot.total_bytes} bytes")
    return "\n".join(lines) + "\n"


def parse_snapshot(text, source="snapshot"):
    lines = text.splitlines()
    if not lines or lines[0] != HEADER:
        raise SnapshotError(f"{source}: not a snapkit snapshot")
    records = []
    footer_seen = False
    for lineno, line in enumerate(lines[1:], 2):
        if footer_seen:
            raise SnapshotError(f"{source}:{lineno}: text after the total line")
        if line.startswith("total "):
            footer_seen = True
            continue
        fields = line.split(" ", 2)
        if len(fields) != 3 or not fields[1].isdigit() or not fields[2]:
            raise SnapshotError(f"{source}:{lineno}: malformed record")
        records.append(Record(fields[2], int(fields[1]), fields[0]))
    if not footer_seen:
        raise SnapshotError(f"{source}: missing total line")
    snap = Snapshot(records)
    paths = snap.paths()
    if len(set(paths)) != len(paths):
        raise SnapshotError(f"{source}: duplicate path")
    return snap
