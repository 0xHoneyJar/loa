"""Dot-separated identifiers of the prerelease and build parts.

An identifier is a non-empty run of ASCII letters, digits and hyphens.  A
*numeric* identifier consists of digits only.  In a prerelease a numeric
identifier must not carry a leading zero; build identifiers may.
"""
import re

_IDENT = re.compile(r"[0-9A-Za-z-]+")
_NUMERIC = re.compile(r"[0-9]+")


def is_identifier(text):
    """True when ``text`` is a non-empty run of ``[0-9A-Za-z-]``."""
    return bool(_IDENT.fullmatch(text))


def is_numeric(text):
    """True when ``text`` consists of ASCII digits only."""
    return bool(_NUMERIC.fullmatch(text))


def valid_prerelease_identifier(text):
    """A prerelease identifier: a non-empty run of the allowed characters."""
    return is_identifier(text)


def valid_build_identifier(text):
    """A build identifier: any non-empty run of the allowed characters."""
    return is_identifier(text)


def split_identifiers(text, validator):
    """Split ``text`` on dots; return the tuple, or None if any part fails."""
    parts = text.split(".")
    for part in parts:
        if not validator(part):
            return None
    return tuple(parts)


def compare_identifier(a, b):
    """Order two prerelease identifiers (-1, 0 or 1).

    Numeric identifiers sort before alphanumeric ones; otherwise the
    identifiers compare as text.
    """
    a_num, b_num = is_numeric(a), is_numeric(b)
    if a_num != b_num:
        return -1 if a_num else 1
    return (a > b) - (a < b)


def compare_prerelease(a, b):
    """Order two prerelease tuples; the empty tuple (a release) is highest."""
    if not a and not b:
        return 0
    if not a:
        return 1
    if not b:
        return -1
    for x, y in zip(a, b):
        c = compare_identifier(x, y)
        if c:
            return c
    return 0
