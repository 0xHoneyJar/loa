"""Append-only history.

Each change appends one line ``<seq>\t<id>\t<action>\t<rev>\t<digest>\t<detail>``.
``seq`` counts from 1 over the whole log, ``digest`` is the digest of the document
after the change (``-`` for a delete) and ``detail`` is ``-`` when an action has
none. A History either appends to a file or, with no path, keeps lines in memory.
"""
from collections import namedtuple

HistoryEntry = namedtuple("HistoryEntry", "seq doc_id action rev digest detail")

ACTIONS = ("create", "put", "delete", "import")


def format_entry(entry):
    return "\t".join(
        [str(entry.seq), entry.doc_id, entry.action, str(entry.rev), entry.digest, entry.detail]
    )


def parse_entry(line):
    parts = line.rstrip("\n").split("\t")
    if len(parts) != 6:
        raise ValueError(f"malformed history line: {line!r}")
    seq, doc_id, action, rev, dig, detail = parts
    return HistoryEntry(int(seq), doc_id, action, int(rev), dig, detail)


class History:
    def __init__(self, path=None):
        self.path = path
        self._lines = []

    def _read_lines(self):
        if self.path is None:
            return list(self._lines)
        try:
            with open(self.path, encoding="utf-8") as fh:
                return [line.rstrip("\n") for line in fh if line.strip()]
        except FileNotFoundError:
            return []

    def entries(self, doc_id=None):
        result = [parse_entry(line) for line in self._read_lines()]
        if doc_id is not None:
            result = [e for e in result if e.doc_id == doc_id]
        return result

    def lines(self):
        return self._read_lines()

    def append(self, doc_id, action, rev, digest, detail="-"):
        if action not in ACTIONS:
            raise ValueError(f"unknown history action {action!r}")
        seq = len(self._read_lines()) + 1
        entry = HistoryEntry(seq, doc_id, action, rev, digest, detail)
        line = format_entry(entry)
        if self.path is None:
            self._lines.append(line)
        else:
            with open(self.path, "a", encoding="utf-8") as fh:
                fh.write(line + "\n")
        return entry
