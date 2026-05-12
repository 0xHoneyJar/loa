"""Routing-layer types for chain resolution and capability gating.

Cycle-104 Sprint 2 (SDD §3.1, §5.1, §5.2). These types are scoped to the
routing layer; provider-level types live in `loa_cheval.types`.

Why a separate types module: ResolvedChain / ResolvedEntry are immutable
value objects that flow through cheval.invoke() before any adapter dispatch.
Keeping them next to chain_resolver.py / capability_gate.py makes the
within-company invariant easier to enforce — every consumer goes through
chain_resolver.resolve(), which is the single chokepoint for both validation
and mode-transform application.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Dict, FrozenSet, Literal, Optional, Tuple

from loa_cheval.types import ChevalError


# --- Adapter kind + headless mode literals (SDD §3.1, §3.3) ---

AdapterKind = Literal["http", "cli"]
HeadlessMode = Literal["prefer-api", "prefer-cli", "api-only", "cli-only"]
HeadlessModeSource = Literal["env", "config", "default"]

HEADLESS_MODES: Tuple[HeadlessMode, ...] = (
    "prefer-api",
    "prefer-cli",
    "api-only",
    "cli-only",
)
ADAPTER_KINDS: Tuple[AdapterKind, ...] = ("http", "cli")
HEADLESS_MODE_SOURCES: Tuple[HeadlessModeSource, ...] = ("env", "config", "default")


# --- Resolved chain dataclasses (SDD §3.1) ---


@dataclass(frozen=True)
class ResolvedEntry:
    """One concrete (provider, model, kind) tuple in a resolved chain.

    Immutable. Constructed only via chain_resolver.resolve() so that the
    within-company invariant and capability frozenset are enforced uniformly.
    """

    provider: str  # e.g. "openai" / "anthropic" / "google"
    model_id: str  # e.g. "gpt-5.5-pro" or "codex-headless"
    adapter_kind: AdapterKind  # "http" or "cli"
    capabilities: FrozenSet[str]  # e.g. frozenset({"chat", "tools"})

    def __post_init__(self) -> None:
        if self.adapter_kind not in ADAPTER_KINDS:
            raise ValueError(
                f"ResolvedEntry.adapter_kind must be one of {ADAPTER_KINDS}, "
                f"got {self.adapter_kind!r}"
            )
        if not isinstance(self.capabilities, frozenset):
            raise TypeError(
                "ResolvedEntry.capabilities must be a frozenset (got "
                f"{type(self.capabilities).__name__})"
            )

    @property
    def canonical(self) -> str:
        """`provider:model_id` form for logs and audit."""
        return f"{self.provider}:{self.model_id}"


@dataclass(frozen=True)
class ResolvedChain:
    """Ordered list of (entries) that cheval.invoke() walks for one call.

    `entries[0]` is the primary; `entries[1:]` are within-company fallbacks
    transformed per `headless_mode`. The within-company invariant
    (`every entry.provider == entries[0].provider`) is asserted at
    construction by chain_resolver.resolve() — there is no other legitimate
    construction path.
    """

    primary_alias: str
    entries: Tuple[ResolvedEntry, ...]
    headless_mode: HeadlessMode
    headless_mode_source: HeadlessModeSource

    def __post_init__(self) -> None:
        if not self.entries:
            raise ValueError("ResolvedChain.entries must not be empty")
        if self.headless_mode not in HEADLESS_MODES:
            raise ValueError(
                f"ResolvedChain.headless_mode must be one of {HEADLESS_MODES}, "
                f"got {self.headless_mode!r}"
            )
        if self.headless_mode_source not in HEADLESS_MODE_SOURCES:
            raise ValueError(
                "ResolvedChain.headless_mode_source must be one of "
                f"{HEADLESS_MODE_SOURCES}, got {self.headless_mode_source!r}"
            )

    @property
    def primary(self) -> ResolvedEntry:
        return self.entries[0]

    @property
    def company(self) -> str:
        """The company prefix shared by every entry (within-company invariant)."""
        return self.entries[0].provider


# --- Capability gate result (SDD §5.2) ---


@dataclass(frozen=True)
class CapabilityCheckResult:
    """Result of `capability_gate.check(request, entry)`.

    `ok=True` ⇒ `missing` is empty.
    `ok=False` ⇒ `missing` enumerates the capabilities the request required
    that the entry does not declare. The router records the missing list in
    MODELINV `models_failed[].missing_capabilities` so audit consumers can
    explain why a chain entry was skipped without reading provider logs.
    """

    ok: bool
    missing: Tuple[str, ...] = ()

    def __post_init__(self) -> None:
        if self.ok and self.missing:
            raise ValueError(
                "CapabilityCheckResult.missing must be empty when ok=True; "
                f"got missing={self.missing!r}"
            )


# --- Routing-layer errors (SDD §6.2, §6.3) ---


class NoEligibleAdapterError(ChevalError):
    """No adapter in the resolved chain is eligible to dispatch this request.

    Raised by `chain_resolver.resolve()` when the mode-transformed chain ends
    up empty — e.g., `cli-only` mode for a primary that has no CLI fallback
    declared, or `prefer-cli` with all CLI binaries uninstalled (SDD §10 Q7).

    Fail-loud (`retryable=False`) so cheval surfaces the misconfiguration to
    the operator instead of silently substituting another company.
    """

    def __init__(
        self,
        primary_alias: str,
        headless_mode: str,
        reason: str,
    ):
        super().__init__(
            "NO_ELIGIBLE_ADAPTER",
            (
                f"No eligible adapter for primary='{primary_alias}' under "
                f"headless_mode='{headless_mode}': {reason}"
            ),
            retryable=False,
            context={
                "primary_alias": primary_alias,
                "headless_mode": headless_mode,
                "reason": reason,
            },
        )


class ChainExhaustedError(ChevalError):
    """All entries in a ResolvedChain have failed.

    Raised by cheval.invoke() after walking the full chain — each entry
    either raised a retryable error or was skipped by capability_gate. Carries
    the populated `models_failed[]` list so MODELINV envelope writers can
    record the walk order. Distinct from `RetriesExhaustedError` (which is
    per-provider retry budget): ChainExhaustedError is per-chain.
    """

    def __init__(
        self,
        primary_alias: str,
        models_failed: Tuple[Dict[str, Any], ...],
    ):
        super().__init__(
            "CHAIN_EXHAUSTED",
            (
                f"All {len(models_failed)} entries in chain for "
                f"'{primary_alias}' failed."
            ),
            retryable=False,
            context={
                "primary_alias": primary_alias,
                "models_failed": list(models_failed),
            },
        )


class EmptyContentError(ChevalError):
    """Provider returned a 200 with empty `content` (KF-003 class).

    Distinct from `ProviderStreamError` (mid-flight stream failure) and from
    `RetriesExhaustedError` (retry budget). Classified as retryable so the
    router moves to the next chain entry per SDD §5.3 + §10 Q6 — mirrors
    cycle-103 ProviderStreamError dispatch pattern.

    Sanitization: `reason` flows through MODELINV as-is; callers must
    pre-sanitize via cycle-103 `sanitize_provider_error_message` before
    raising.
    """

    def __init__(
        self,
        provider: str,
        model_id: str,
        reason: str = "",
        input_tokens: Optional[int] = None,
    ):
        ctx: Dict[str, Any] = {
            "provider": provider,
            "model_id": model_id,
        }
        if input_tokens is not None:
            ctx["input_tokens"] = input_tokens
        msg = (
            f"Provider '{provider}' returned empty content from "
            f"'{model_id}'"
        )
        if reason:
            msg = f"{msg}: {reason}"
        super().__init__(
            "EMPTY_CONTENT",
            msg,
            retryable=True,
            context=ctx,
        )
