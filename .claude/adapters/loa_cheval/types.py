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
    type: str  # "openai" | "anthropic" | "openai_compat"
    endpoint: str
    auth: Any  # str or LazyValue — resolved to str via str() when accessed
    models: Dict[str, ModelConfig] = field(default_factory=dict)
    connect_timeout: float = 10.0  # seconds
    read_timeout: float = 120.0
    write_timeout: float = 30.0


@dataclass
class ModelConfig:
    """Per-model configuration within a provider."""

    capabilities: List[str] = field(default_factory=list)
    context_window: int = 128000
    token_param: str = "max_tokens"  # Wire name for max output tokens param (e.g., "max_completion_tokens" for GPT-5.2+)
    pricing: Optional[Dict[str, int]] = None  # {input_per_mtok, output_per_mtok} in micro-USD
    api_mode: Optional[str] = None  # "standard" (default) | "interactions" (Deep Research)
    extra: Optional[Dict[str, Any]] = None  # Provider-specific config (thinking_level, api_version, etc.)


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
