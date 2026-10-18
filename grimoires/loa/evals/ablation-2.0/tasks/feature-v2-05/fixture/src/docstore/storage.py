"""Persistence back ends.

A back end stores records ``{"rev": int, "doc": dict}`` by id. FileStorage keeps
one ``<id>.json`` file per document under ``<root>/docs`` and replaces files
atomically; MemoryStorage keeps them in a dict. Both hand out deep copies.
"""
import copy
import json
import os
import tempfile

from .canon import canonical


class MemoryStorage:
    def __init__(self):
        self._records = {}

    def read(self, doc_id):
        record = self._records.get(doc_id)
        return copy.deepcopy(record)

    def write(self, doc_id, record):
        self._records[doc_id] = copy.deepcopy(record)

    def remove(self, doc_id):
        self._records.pop(doc_id, None)

    def ids(self):
        return sorted(self._records)


class FileStorage:
    def __init__(self, root):
        self.root = root
        self.docs = os.path.join(root, "docs")
        os.makedirs(self.docs, exist_ok=True)

    def _path(self, doc_id):
        return os.path.join(self.docs, doc_id + ".json")

    def read(self, doc_id):
        try:
            with open(self._path(doc_id), encoding="utf-8") as fh:
                return json.load(fh)
        except FileNotFoundError:
            return None

    def write(self, doc_id, record):
        fd, tmp = tempfile.mkstemp(dir=self.docs, prefix=".tmp-", suffix=".json")
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as fh:
                fh.write(canonical(record) + "\n")
            os.replace(tmp, self._path(doc_id))
        except BaseException:
            if os.path.exists(tmp):
                os.unlink(tmp)
            raise

    def remove(self, doc_id):
        try:
            os.unlink(self._path(doc_id))
        except FileNotFoundError:
            pass

    def ids(self):
        names = [n[:-5] for n in os.listdir(self.docs) if n.endswith(".json") and not n.startswith(".")]
        return sorted(names)
