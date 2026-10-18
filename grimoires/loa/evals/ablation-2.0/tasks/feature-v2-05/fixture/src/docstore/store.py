"""The document store.

``Store(storage, history, config)`` keeps documents by id. Every stored document
has a revision that starts at 1 and grows by one per change, and every change
appends one history entry. Values handed in and out are deep copies, so callers
never share structure with the store.
"""
import copy

from .canon import digest
from .config import Config
from .errors import Conflict, NotFound
from .history import History
from .ids import check_id
from .storage import MemoryStorage
from .validate import validate_document


class Store:
    def __init__(self, storage=None, history=None, config=None):
        self.storage = storage if storage is not None else MemoryStorage()
        self.history = history if history is not None else History()
        self.config = config if config is not None else Config()

    # -- helpers -----------------------------------------------------------
    def _validate(self, doc):
        validate_document(doc, self.config.max_depth, self.config.max_bytes)

    def _record(self, doc_id):
        record = self.storage.read(doc_id)
        if record is None:
            raise NotFound(f"no document {doc_id!r}")
        return record

    @staticmethod
    def _check_rev(doc_id, record, expected_rev):
        if expected_rev is not None and record["rev"] != expected_rev:
            raise Conflict(
                f"revision mismatch for {doc_id!r}: expected {expected_rev}, found {record['rev']}"
            )

    # -- reading -----------------------------------------------------------
    def exists(self, doc_id):
        check_id(doc_id)
        return self.storage.read(doc_id) is not None

    def get(self, doc_id):
        """Return a deep copy of the document; NotFound when absent."""
        check_id(doc_id)
        return copy.deepcopy(self._record(doc_id)["doc"])

    def revision(self, doc_id):
        check_id(doc_id)
        return self._record(doc_id)["rev"]

    def ids(self):
        return self.storage.ids()

    # -- writing -----------------------------------------------------------
    def create(self, doc_id, doc):
        """Store a new document at revision 1; Conflict when the id is taken."""
        check_id(doc_id)
        if self.storage.read(doc_id) is not None:
            raise Conflict(f"document {doc_id!r} already exists")
        self._validate(doc)
        self.storage.write(doc_id, {"rev": 1, "doc": copy.deepcopy(doc)})
        self.history.append(doc_id, "create", 1, digest(doc))
        return 1

    def put(self, doc_id, doc, expected_rev=None):
        """Replace a document; returns the new revision."""
        check_id(doc_id)
        record = self._record(doc_id)
        self._check_rev(doc_id, record, expected_rev)
        self._validate(doc)
        rev = record["rev"] + 1
        self.storage.write(doc_id, {"rev": rev, "doc": copy.deepcopy(doc)})
        self.history.append(doc_id, "put", rev, digest(doc))
        return rev

    def delete(self, doc_id, expected_rev=None):
        check_id(doc_id)
        record = self._record(doc_id)
        self._check_rev(doc_id, record, expected_rev)
        self.storage.remove(doc_id)
        self.history.append(doc_id, "delete", record["rev"], "-")

    def load(self, doc_id, rev, doc, detail):
        """Store a document at a given revision (used by bundle import)."""
        check_id(doc_id)
        self._validate(doc)
        self.storage.write(doc_id, {"rev": rev, "doc": copy.deepcopy(doc)})
        self.history.append(doc_id, "import", rev, digest(doc), detail)
