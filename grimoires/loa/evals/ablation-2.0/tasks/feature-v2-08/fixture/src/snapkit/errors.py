"""Exceptions raised by snapkit.  The command line prints ``snapkit: <str(exc)>``."""


class SnapError(Exception):
    """Base class of every error snapkit reports to the user."""


class PathError(SnapError):
    """A relative path given by the user or a config file is not acceptable."""


class ConfigError(SnapError):
    """A config file line is malformed; the message starts with ``<source>:<line>: ``."""


class SnapshotError(SnapError):
    """A snapshot file cannot be parsed."""
