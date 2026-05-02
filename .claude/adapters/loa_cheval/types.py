"""Hounfour canonical types — extracted from loa-finn types.ts (SDD §4.2.3)."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional


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
    """All retry/fallback attempts exhausted."""

    def __init__(self, total_attempts: int, last_error: Optional[str] = None):
        super().__init__("RETRIES_EXHAUSTED", f"Failed after {total_attempts} attempts: {last_error or 'unknown'}", retryable=False, context={"total_attempts": total_attempts})


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
