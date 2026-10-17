"""Exceptions raised by semrange.

Every error is a ``VersionError`` (itself a ``ValueError``).  The message of
``InvalidVersion`` and ``InvalidRange`` quotes the offending argument with
``repr()`` so that whitespace and quotes in the input stay visible.
"""


class VersionError(ValueError):
    """Base class of every semrange error."""


class InvalidVersion(VersionError):
    """A string is not a valid semantic version."""

    def __init__(self, text):
        super().__init__(f"invalid version: {text!r}")
        self.text = text


class InvalidRange(VersionError):
    """A string is not a valid range expression."""

    def __init__(self, text):
        super().__init__(f"invalid range: {text!r}")
        self.text = text


class InvalidIncrement(VersionError):
    """An increment kind or a prerelease id is not acceptable."""
