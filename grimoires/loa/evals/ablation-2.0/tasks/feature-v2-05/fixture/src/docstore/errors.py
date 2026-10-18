"""Exception hierarchy. Every error the store raises derives from DocstoreError."""


class DocstoreError(Exception):
    """Base class of every docstore error."""


class ConfigError(DocstoreError):
    """The configuration file is malformed."""


class InvalidId(DocstoreError):
    """A document id does not follow the id rules."""


class NotFound(DocstoreError):
    """No document has the requested id."""


class Conflict(DocstoreError):
    """A document already exists, or an expected revision does not match."""


class ValidationError(DocstoreError):
    """A document is not storable (types, depth, size, root)."""


class ExportError(DocstoreError):
    """A bundle cannot be read or written."""
