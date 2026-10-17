"""Canonical JSON text and document digests.

The canonical form sorts object keys, uses no insignificant whitespace, keeps
non-ASCII characters as they are and refuses NaN and infinities.
"""
import hashlib
import json


def canonical(value):
    """Return the canonical JSON text of ``value``."""
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False, allow_nan=False)


def digest(value):
    """Return the first 12 hex digits of the SHA-256 of the canonical text."""
    return hashlib.sha256(canonical(value).encode("utf-8")).hexdigest()[:12]


def parse_json(text, where):
    """Parse JSON text; ``where`` names the input in the error message."""
    from .errors import ValidationError

    try:
        return json.loads(text, parse_constant=_refuse_constant)
    except ValueError as exc:
        raise ValidationError(f"{where}: invalid JSON: {exc}") from None


def _refuse_constant(name):
    raise ValueError(f"{name} is not allowed")
