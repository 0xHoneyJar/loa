"""Hounfour canonical types — extracted from loa-finn types.ts (SDD §4.2.3)."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Dict, List, Literal, Optional


# --- Completion Request/Result ---


@dataclass
class CompletionRequest:
    """Canonical request sent to any provider adapter."""

    messages: List[Dict[str, Any]]  # [{"role": "system"|"user"|"assistant"|"tool", "content": str}]
    model: str  # Provider-specific model ID (e.g., "gpt-5.2")
    temperature: float = 0.7
    max_tokens: int = 4096
    tools: Optional[List[Dict[str, Any]]] = None
    tool_choice: Optional[str] = None  # "auto" | "required" | "none"
    metadata: Optional[Dict[str, Any]] = None  # agent, trace_id, sprint_id (not sent to provider)


@dataclass
class CompletionResult:
    """Canonical result returned from any provider adapter."""

    content: str  # Model response text
    tool_calls: Optional[List[Dict[str, Any]]]  # Normalized tool call format
    thinking: Optional[str]  # Reasoning/thinking trace (None if unsupported)
    usage: Usage  # Token counts
    model: str  # Actual model used (may differ from requested)
    latency_ms: int
    provider: str
    interaction_id: Optional[str] = None  # Deep Research interaction ID for deduplication
    # cycle-095 Sprint 1 (SDD §5.6): adapter-emitted out-of-band signals.
    # Documented keys: refused (bool), truncated (bool), truncation_reason (str),
    # unknown_shapes_present (bool), unknown_shapes (list[str]).
    metadata: Dict[str, Any] = field(default_factory=dict)


@dataclass
class Usage:
    """Token usage information."""

    input_tokens: int
    output_tokens: int
    reasoning_tokens: int = 0
    source: str = "actual"  # "actual" | "estimated"


# --- Agent Binding ---


@dataclass
class AgentBinding:
    """Per-agent model binding with requirements."""

    agent: str
    model: str  # Alias or "provider:model-id"
    temperature: Optional[float] = None
    persona: Optional[str] = None  # Path to persona.md
    requires: Optional[Dict[str, Any]] = field(default_factory=dict)


# --- Resolved Model ---


@dataclass
class ResolvedModel:
    """Fully resolved provider + model ID pair."""

    provider: str  # e.g., "openai"
    model_id: str  # e.g., "gpt-5.2"


# --- Provider Config ---


@dataclass
class ProviderConfig:
    """Per-provider configuration."""

    name: str
    type: str  # "openai" | "anthropic" | "openai_compat" | "google" | "bedrock"
    endpoint: str
    auth: Any  # str or LazyValue — resolved to str via str() when accessed
    models: Dict[str, ModelConfig] = field(default_factory=dict)
    connect_timeout: float = 10.0  # seconds
    read_timeout: float = 120.0
    write_timeout: float = 30.0
    # cycle-096 Sprint 1 (SDD §3.1, FR-1) — Bedrock-specific provider fields.
    # Optional on all entries; non-Bedrock providers leave them None.
    region_default: Optional[str] = None  # e.g., "us-east-1"; per-request override via extras.region
    auth_modes: Optional[List[str]] = None  # ["api_key"] in v1; ["api_key", "sigv4"] when SigV4 lands
    # compliance_profile: resolved by 4-step loader rule (SDD §5.6) when YAML
    # value is null. Allowed at runtime: "bedrock_only" | "prefer_bedrock" | "none".
    compliance_profile: Optional[str] = None


@dataclass
class ModelConfig:
    """Per-model configuration within a provider."""

    capabilities: List[str] = field(default_factory=list)
    context_window: int = 128000
    # cycle-103 Sprint 3 T3.4: streaming-vs-legacy split for the
    # cheval HTTP-asymmetry safe-input gate (KF-002 layer 3). When both
    # are set, _lookup_max_input_tokens in cheval.py branches on the
    # streaming kill switch. `max_input_tokens` remains as a backward-
    # compat single-value fallback when the split fields are absent.
    streaming_max_input_tokens: Optional[int] = None
    legacy_max_input_tokens: Optional[int] = None
    token_param: str = "max_tokens"  # Wire name for max output tokens param (e.g., "max_completion_tokens" for GPT-5.2+)
    pricing: Optional[Dict[str, int]] = None  # {input_per_mtok, output_per_mtok} in micro-USD
    api_mode: Optional[str] = None  # "standard" (default) | "interactions" (Deep Research)
    extra: Optional[Dict[str, Any]] = None  # Provider-specific config (thinking_level, api_version, etc.)
    # Wire-protocol parameter gates (#641): controls which optional fields the
    # adapter serializes into the request body. Distinct from `extra` (provider-
    # specific feature config) — `params` flips wire-level inclusion. Currently:
    #   temperature_supported: bool (default True). Set False for Opus 4 family
    #   which rejects requests carrying `temperature` with HTTP 400.
    params: Optional[Dict[str, Any]] = None
    # cycle-095 Sprint 1 (SDD §3.4, §5.2): OpenAI endpoint routing metadata.
    # REQUIRED on every providers.openai.models.* entry (validated in loader);
    # ignored for non-OpenAI providers. Allowed values: "chat" | "responses".
    endpoint_family: Optional[str] = None
    # cycle-095 Sprint 2 (SDD §3.5): probe-driven fallback chain.
    # Each entry is "provider:model_id". Optional; absence = no fallback.
    fallback_chain: Optional[List[str]] = None
    # Latency-formalization of an existing YAML field. Probe-gated entries are
    # treated as UNAVAILABLE until model-health-probe.sh confirms reachability.
    probe_required: bool = False
    # cycle-096 Sprint 1 (SDD §3.1, FR-1) — Bedrock-specific fields. Optional
    # on all entries; non-Bedrock providers leave them None.
    #
    # api_format: per-capability dispatch table. Currently consumed only by the
    # Bedrock adapter (Converse vs InvokeModel decision per capability per
    # SDD §6.6). Example: {"chat": "converse", "tools": "converse",
    # "thinking_traces": "converse"}. Adapter falls back to "converse" when key
    # absent. Direct-Anthropic / OpenAI / Google entries leave this None.
    api_format: Optional[Dict[str, str]] = None
    # fallback_to: explicit direct-provider equivalent for compliance-aware
    # fallback when compliance_profile=prefer_bedrock. Required on every
    # bedrock model entry per Flatline BLOCKER SKP-003 — loader rejects
    # prefer_bedrock when fallback_to absent. Format: "provider:model_id".
    fallback_to: Optional[str] = None
    # fallback_mapping_version: bumps when AWS or vendor ships a behavior
    # delta that breaks fallback equivalence. Operator acknowledges via
    # sentinel file (NFR-Sec9 IR runbook).
    fallback_mapping_version: Optional[int] = None
    # cycle-110 sprint-2b2b1 BB iter-2 F-001 closure: per-model concurrency
    # cap for the cross-process N-slot semaphore (SDD §5.6 v1.1). Seeded
    # from FR-8.6 stress test results; defaults to 50 if absent. Operator
    # tunes per model in `.claude/defaults/model-config.yaml`.
    headless_concurrency_limit: Optional[int] = None


# --- Error Types ---


class ChevalError(Exception):
    """Base error for all cheval operations."""

    def __init__(self, code: str, message: str, retryable: bool = False, context: Optional[Dict[str, Any]] = None):
        super().__init__(f"[cheval] {code}: {message}")
        self.code = code
        self.retryable = retryable
        self.context = context or {}

    def to_json(self) -> Dict[str, Any]:
        return {
            "error": True,
            "code": self.code,
            "message": str(self),
            "retryable": self.retryable,
        }


class NativeRuntimeRequired(ChevalError):
    """Agent requires native_runtime — cannot be routed to remote model."""

    def __init__(self, agent: str):
        super().__init__("NATIVE_RUNTIME_REQUIRED", f"Agent '{agent}' requires native_runtime", retryable=False, context={"agent": agent})


class ProviderUnavailableError(ChevalError):
    """Provider is not reachable or circuit breaker is open."""

    def __init__(self, provider: str, reason: str = ""):
        super().__init__("PROVIDER_UNAVAILABLE", f"Provider '{provider}' unavailable: {reason}", retryable=True, context={"provider": provider})


class RateLimitError(ChevalError):
    """Provider returned 429 Too Many Requests."""

    def __init__(self, provider: str, retry_after: Optional[float] = None):
        super().__init__("RATE_LIMITED", f"Rate limited by {provider}", retryable=True, context={"provider": provider, "retry_after": retry_after})


class BudgetExceededError(ChevalError):
    """Daily budget exceeded."""

    def __init__(self, spent: int, limit: int):
        super().__init__("BUDGET_EXCEEDED", f"Budget exceeded: {spent} >= {limit} micro-USD", retryable=False, context={"spent": spent, "limit": limit})


class ContextTooLargeError(ChevalError):
    """Input exceeds model context window."""

    def __init__(self, estimated_tokens: int, available: int, context_window: int):
        super().__init__(
            "CONTEXT_TOO_LARGE",
            f"Input ~{estimated_tokens} tokens exceeds available {available} tokens (context_window={context_window})",
            retryable=False,
            context={"estimated_tokens": estimated_tokens, "available": available, "context_window": context_window},
        )


class RetriesExhaustedError(ChevalError):
    """All retry/fallback attempts exhausted.

    Carries optional typed metadata on `context.last_error_class` and
    `context.last_error_context` so downstream error formatters (cheval.py
    JSON-error output) can surface a typed `failure_class` (e.g.
    PROVIDER_DISCONNECT for ConnectionLostError per issue #774) without
    parsing the message string.
    """

    def __init__(
        self,
        total_attempts: int,
        last_error: Optional[str] = None,
        last_error_class: Optional[str] = None,
        last_error_context: Optional[Dict[str, Any]] = None,
    ):
        ctx: Dict[str, Any] = {"total_attempts": total_attempts}
        if last_error_class:
            ctx["last_error_class"] = last_error_class
        if last_error_context:
            ctx["last_error_context"] = last_error_context
        super().__init__(
            "RETRIES_EXHAUSTED",
            f"Failed after {total_attempts} attempts: {last_error or 'unknown'}",
            retryable=False,
            context=ctx,
        )


class ConnectionLostError(ChevalError):
    """Transport-layer connection lost mid-flight (issue #774).

    Catches the family of httpx exceptions
    (RemoteProtocolError / ReadError / WriteError / ConnectError /
    PoolTimeout / ProtocolError) and the urllib equivalents
    (http.client.RemoteDisconnected, urllib.error.URLError,
    socket.timeout) that share the operator-facing failure shape:
    "Server disconnected without sending a response."

    Sibling of `ProviderUnavailableError` — NOT a subclass — because the
    retry semantics differ. ProviderUnavailableError moves on to the next
    provider in the chain; ConnectionLostError counts against the
    per-provider retry budget (transient on long prompts; the real
    workaround is upstream — streaming or HTTP/1.1 — and is deferred per
    /bug scope to /plan).

    Carries typed context (provider, transport_class, request_size_bytes)
    so cheval.py can surface `failure_class: PROVIDER_DISCONNECT` in
    JSON-error stderr without parsing the message string. Sanitization:
    transport class and size are safe to log; raw body / headers / auth
    are NEVER attached.
    """

    def __init__(
        self,
        provider: str = "",
        transport_class: str = "",
        request_size_bytes: Optional[int] = None,
        message: Optional[str] = None,
    ):
        msg = message or (
            f"Connection lost from {provider or 'provider'} "
            f"(transport={transport_class or 'unknown'}, "
            f"request_size_bytes={request_size_bytes if request_size_bytes is not None else 'unknown'})"
        )
        super().__init__(
            "CONNECTION_LOST",
            msg,
            retryable=True,
            context={
                "provider": provider,
                "transport_class": transport_class,
                "request_size_bytes": request_size_bytes,
            },
        )
        self.provider = provider
        self.transport_class = transport_class
        self.request_size_bytes = request_size_bytes


class ConfigError(ChevalError):
    """Invalid configuration."""

    def __init__(self, message: str):
        super().__init__("INVALID_CONFIG", message, retryable=False)


class InvalidInputError(ChevalError):
    """Invalid input to model-invoke."""

    def __init__(self, message: str):
        super().__init__("INVALID_INPUT", message, retryable=False)


# cycle-095 Sprint 1 (SDD §5.6): adapter-runtime defense-in-depth for missing
# endpoint_family. Config-load validation (loader.py) is the primary gate;
# this exception fires only if a request reaches the adapter without it.
class InvalidConfigError(ChevalError):
    """Registry / config-shape error caught at adapter request-time."""

    def __init__(self, message: str):
        super().__init__("INVALID_CONFIG", message, retryable=False)


# cycle-095 Sprint 1 (SDD §5.4, §5.4.1): the strict-default raise for
# /v1/responses output[].type values not in the §5.4 normalization matrix.
# Operators who need a one-shot escape hatch can set
# hounfour.experimental.responses_unknown_shape_policy: degrade.
class UnsupportedResponseShapeError(ChevalError):
    """Adapter encountered a response shape not in §5.4 normalization matrix."""

    def __init__(self, message: str):
        super().__init__("UNSUPPORTED_RESPONSE_SHAPE", message, retryable=False)


# cycle-095 Sprint 2 (SDD §5.6): forward-compat alias for PRD wording (FR-5/FR-5a).
# The pre-call cost-cap guard raises this name; existing per-day budget code
# keeps using BudgetExceededError directly.
CostBudgetExceeded = BudgetExceededError


# ----------------------------------------------------------------------------
# ProviderStreamError — cycle-103 Sprint 3 T3.1 / AC-3.1
# ----------------------------------------------------------------------------
#
# Structured parser exception that preserves provider-side failure
# classification through retry routing. Per cycle-102 Sprint 4A reviewer
# carry-forward F-002: streaming parsers were raising bare ValueError /
# RuntimeError, which flattened the retry classification at the adapter
# layer. retry.py couldn't tell "this is a 429 rate-limit, back off" from
# "this is malformed, surface to caller".
#
# Spec: sdd.md §1.4.4 (component spec) + §6.1 (error taxonomy) + sprint.md
# T3.1.
#
# Usage:
#
#   from loa_cheval.types import ProviderStreamError, dispatch_provider_stream_error
#
#   # In an SSE parser:
#   if event.type == "error" and event.data.get("type") == "rate_limit_exceeded":
#       raise ProviderStreamError(
#           category="rate_limit",
#           message="Anthropic streaming returned rate_limit_exceeded",
#           raw_payload=event.raw_bytes,
#       )
#
#   # In the adapter dispatch layer:
#   try:
#       ... parse stream ...
#   except ProviderStreamError as e:
#       raise dispatch_provider_stream_error(e, provider="anthropic")
#
# The dispatch table maps `category` → typed exception (RateLimitError,
# ProviderUnavailableError, InvalidInputError, ConnectionLostError) via a
# SINGLE lookup table at the adapter boundary. retry.py reads the typed
# exception (unchanged) — no cascading rewrite. Mitigates PRD R4.
#
# raw_payload is Optional[bytes]; sanitization via sanitize_provider_error_message
# (T3.3) is the caller's responsibility before any exception arg interpolation.


ProviderStreamCategory = Literal[
    "rate_limit",   # provider 429 / explicit rate-limit signal
    "overloaded",   # provider 5xx / "server overloaded" signal
    "malformed",    # response shape doesn't parse (bad JSON, missing fields)
    "policy",       # provider refused on content policy / safety
    "transient",    # connection lost / partial stream / retryable transport
    "unknown",      # unclassified (fallback)
]


class ProviderStreamError(ChevalError):
    """Structured parser exception raised by streaming adapters.

    Sibling of `RateLimitError` etc. — NOT a subclass — because the
    dispatch happens at the adapter layer. The category-to-typed-exception
    map lives in `dispatch_provider_stream_error` so retry.py (unchanged)
    reads only the dispatched typed exception, not this raw form.

    Args:
        category: classification per `ProviderStreamCategory`.
        message: human-readable detail. Should NOT contain raw upstream
            bytes — wrap any provider payload in
            `sanitize_provider_error_message` (T3.3) first.
        raw_payload: optional original bytes for debugging / audit. Caller
            is responsible for redaction before persisting or surfacing.
    """

    def __init__(
        self,
        category: ProviderStreamCategory,
        message: str,
        raw_payload: Optional[bytes] = None,
    ):
        # AC-3.1: retryable flag mirrors the dispatched typed exception's
        # retry semantics so callers that inspect ChevalError.retryable
        # without dispatching see the right behavior.
        retryable = category in ("rate_limit", "overloaded", "transient")
        super().__init__(
            "PROVIDER_STREAM_ERROR",
            f"[{category}] {message}",
            retryable=retryable,
            context={"category": category},
        )
        self.category: ProviderStreamCategory = category
        self.message_detail: str = message
        self.raw_payload: Optional[bytes] = raw_payload


def dispatch_provider_stream_error(
    error: ProviderStreamError,
    *,
    provider: str = "",
) -> ChevalError:
    """AC-3.1 dispatch table: map `ProviderStreamError.category` to the
    typed exception that retry.py + the adapter callers already
    understand. Single lookup; no cascade.

    Args:
        error: the structured parser exception raised by the streaming layer.
        provider: provider name (e.g., "anthropic") for the constructed
            exception's context. May be empty for callers that don't
            know.

    Returns:
        A ChevalError-subclass instance ready to raise. retry.py treats:
          - RateLimitError → retry with backoff
          - ProviderUnavailableError → move to next provider in chain
          - InvalidInputError → surface to caller (don't retry)
          - ConnectionLostError → count against per-provider retry budget
    """
    category = error.category
    detail = error.message_detail

    if category == "rate_limit":
        return RateLimitError(provider=provider or "unknown")
    if category == "overloaded":
        return ProviderUnavailableError(
            provider=provider or "unknown",
            reason=f"overloaded — {detail}",
        )
    if category == "malformed":
        return InvalidInputError(
            f"Provider {provider or 'unknown'} returned malformed stream: {detail}"
        )
    if category == "policy":
        # Policy refusals are non-retryable input-side problems — the
        # request shape itself was rejected. Surface to caller.
        return InvalidInputError(
            f"Provider {provider or 'unknown'} refused on policy: {detail}"
        )
    if category == "transient":
        # Connection-lost-class: count against per-provider retry budget.
        # ConnectionLostError is the existing sibling for this semantic
        # (issue #774 cycle-102).
        return ConnectionLostError(
            provider=provider or "unknown",
            transport_class="stream",
            message=f"Transient stream failure: {detail}",
        )
    # `unknown` and any unexpected category fall to the "treat as
    # provider-unavailable" disposition. This is the conservative choice:
    # retry.py moves to the next provider rather than surfacing an
    # unclassified error to the caller.
    return ProviderUnavailableError(
        provider=provider or "unknown",
        reason=f"unclassified stream error (category={category!r}): {detail}",
    )


# --- Centralized provider:model_id parser (cycle-096 Sprint 1 Task 1.1) ---
#
# Single source of truth for parsing "provider:model-id" strings. Closes Flatline
# v1.1 SKP-006 by ensuring every Python callsite uses this function rather than
# scattered .split(":", 1) calls. Companion bash helper at
# .claude/scripts/lib-provider-parse.sh enforces identical semantics.
#
# SDD reference: §5.4 Centralized Parser Contract.


def parse_provider_model_id(s: str) -> tuple[str, str]:
    """Split a "provider:model_id" string on the FIRST colon only.

    Everything after the first colon is the literal model_id, including any
    further colons. This is required for Bedrock inference profile IDs of the
    form ``us.anthropic.claude-haiku-4-5-20251001-v1:0`` where the trailing
    ``:0`` is part of the model_id, not a second separator.

    Args:
        s: Input string of the form ``provider:model_id``.

    Returns:
        ``(provider, model_id)`` as a 2-tuple of strings.

    Raises:
        InvalidInputError: ``s`` is empty, lacks a colon, has an empty provider
            half (``":model-id"``), or has an empty model_id half (``"provider:"``).

    Examples:
        >>> parse_provider_model_id("anthropic:claude-opus-4-7")
        ('anthropic', 'claude-opus-4-7')
        >>> parse_provider_model_id("bedrock:us.anthropic.claude-haiku-4-5-20251001-v1:0")
        ('bedrock', 'us.anthropic.claude-haiku-4-5-20251001-v1:0')
        >>> parse_provider_model_id("provider:multi:colon:value")
        ('provider', 'multi:colon:value')
    """
    if not s:
        raise InvalidInputError("parse_provider_model_id: empty input")

    if ":" not in s:
        raise InvalidInputError(f"parse_provider_model_id: missing colon separator in {s!r}")

    provider, model_id = s.split(":", 1)

    if not provider:
        raise InvalidInputError(f"parse_provider_model_id: empty provider in {s!r}")

    if not model_id:
        raise InvalidInputError(f"parse_provider_model_id: empty model_id in {s!r}")

    return provider, model_id
