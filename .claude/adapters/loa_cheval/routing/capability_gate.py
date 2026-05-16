"""Per-entry feature-vs-adapter compatibility check (SDD §1.4.2, §5.2).

Cycle-104 Sprint 2. Skips adapters that lack a request-required capability
WITHOUT failing the call — the router walks to the next chain entry and
records `models_failed[].reason = "capability_mismatch"` with the missing
capability list. The capability matrix lives in `model-config.yaml`
(`providers.{name}.models.{id}.capabilities`); this module is pure (no I/O).
"""

from __future__ import annotations

import logging
from typing import Any, Dict, FrozenSet, Iterable, Tuple

from loa_cheval.routing.types import CapabilityCheckResult, ResolvedEntry
from loa_cheval.types import CompletionRequest

logger = logging.getLogger("loa_cheval.routing.capability_gate")


# Reserved capability key used by request metadata to override the
# default inferred capability set. Tests and integration sites can attach
# `metadata["requires_capabilities"] = ["large_context", "tools"]` to
# express explicit demands without depending on inference.
METADATA_REQUIRES_KEY = "requires_capabilities"


def check(
    request: CompletionRequest,
    entry: ResolvedEntry,
) -> CapabilityCheckResult:
    """Return CapabilityCheckResult comparing request demands vs entry caps.

    The contract is "skip and continue" (SDD §1.4.2): callers that get
    `ok=False` should NOT raise — they should record the missing list and
    advance to the next chain entry. This is distinct from the existing
    `chains.walk_fallback_chain` capability check, which raises mid-walk.

    Args:
        request: caller's CompletionRequest.
        entry: candidate chain entry (provider, model, kind, capabilities).

    Returns:
        CapabilityCheckResult. `ok=True` ⇒ entry can handle the request.
        `ok=False` ⇒ `missing` enumerates the capabilities the entry lacks.

    Notes:
        Inference order: explicit metadata override > derived requirements.
        `_derive_required_capabilities` is conservative — it asks for `tools`
        only when the request actually carries tools, so a plain `chat` call
        is not blocked from a headless CLI that lacks tool_use.
    """
    required = _resolve_required(request)
    declared: FrozenSet[str] = entry.capabilities
    missing = tuple(sorted(c for c in required if c not in declared))
    if missing:
        logger.debug(
            "capability_gate: %s missing %s (declared=%s, required=%s)",
            entry.canonical,
            list(missing),
            sorted(declared),
            sorted(required),
        )
        return CapabilityCheckResult(ok=False, missing=missing)
    return CapabilityCheckResult(ok=True, missing=())


# --- Internals ---


def _resolve_required(request: CompletionRequest) -> FrozenSet[str]:
    """Compute the capability set the request needs.

    Explicit `metadata.requires_capabilities` (list[str] | tuple[str] | set)
    overrides inference entirely — useful when a caller knows it needs
    `structured_json` or `thinking` even if the request shape doesn't
    obviously show it.
    """
    metadata: Dict[str, Any] = request.metadata or {}
    explicit = metadata.get(METADATA_REQUIRES_KEY)
    if explicit is not None:
        return _coerce_caps(explicit)
    return _derive_required_capabilities(request)


def _coerce_caps(value: Any) -> FrozenSet[str]:
    """Validate + normalize an iterable of capability strings."""
    if isinstance(value, (str, bytes)):
        raise TypeError(
            f"metadata.{METADATA_REQUIRES_KEY} must be a list/tuple/set of "
            f"strings, got bare string {value!r}"
        )
    if not isinstance(value, Iterable):
        raise TypeError(
            f"metadata.{METADATA_REQUIRES_KEY} must be iterable, got "
            f"{type(value).__name__}"
        )
    out = []
    for item in value:
        if not isinstance(item, str) or not item:
            raise TypeError(
                f"metadata.{METADATA_REQUIRES_KEY} entries must be non-empty "
                f"strings, got {item!r}"
            )
        out.append(item)
    return frozenset(out)


def _derive_required_capabilities(request: CompletionRequest) -> FrozenSet[str]:
    """Infer the minimum capability set from request shape.

    Conservative: only declare capabilities the request actually exercises.
    `chat` is always required; `tools` only when `request.tools` is non-empty
    (presence of the request field alone is not enough — many adapters pass
    `[]` to disable tools).
    """
    required = {"chat"}
    if request.tools:
        required.add("tools")
    return frozenset(required)
