"""
loa_cheval.jcs — RFC 8785 JCS canonicalization wrapper.

cycle-098 Sprint 1 (IMP-001 HIGH_CONSENSUS 736). Wraps the `rfc8785` reference
implementation behind a stable Loa-namespaced API. Used by Python audit-log
writers (audit_envelope.py) and any other Loa Python tooling that needs
deterministic JSON serialization.

Install requirement (not yet pinned in pyproject.toml — see Sprint 1B):
    pip install rfc8785

Public API:
    canonicalize(obj: Any) -> bytes
        Canonical JSON bytes per RFC 8785.

    available() -> bool
        Returns True if the underlying `rfc8785` package is importable.
"""

from __future__ import annotations

from typing import Any


def available() -> bool:
    """Return True if rfc8785 is importable in the current environment."""
    try:
        import rfc8785  # noqa: F401
    except ImportError:
        return False
    return True


def canonicalize(obj: Any) -> bytes:
    """
    Canonicalize a Python value to RFC 8785 JCS bytes.

    Args:
        obj: any JSON-serializable Python value (dict, list, str, int, float,
             bool, None).

    Returns:
        Canonical-JSON encoded as UTF-8 bytes. No trailing newline.

    Raises:
        ImportError: if `rfc8785` is not installed. Install with
            `pip install rfc8785`.
        Exception: propagates rfc8785's own errors for unsupported inputs
            (e.g., NaN, Infinity — RFC 8785 forbids these).
    """
    import rfc8785  # local import keeps module importable when dep missing

    return rfc8785.dumps(obj)
