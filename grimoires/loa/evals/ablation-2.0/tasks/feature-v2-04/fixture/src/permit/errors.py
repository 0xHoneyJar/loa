"""Error types."""


class PermitError(Exception):
    """Base class of every permit error."""


class PathError(PermitError):
    """A resource path that is not absolute or not clean."""


class RuleError(PermitError):
    """A malformed rule; the message starts with ``<source>:<line>:``."""


class DirectoryError(PermitError):
    """A malformed users file."""
