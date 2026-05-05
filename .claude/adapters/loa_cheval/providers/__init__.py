"""Provider adapter registry."""

from __future__ import annotations

from typing import Dict, Type

from loa_cheval.providers.base import ProviderAdapter
from loa_cheval.providers.openai_adapter import OpenAIAdapter
from loa_cheval.providers.anthropic_adapter import AnthropicAdapter
from loa_cheval.providers.google_adapter import GoogleAdapter
from loa_cheval.providers.bedrock_adapter import BedrockAdapter
from loa_cheval.providers.codex_headless_adapter import CodexHeadlessAdapter
from loa_cheval.providers.gemini_headless_adapter import GeminiHeadlessAdapter
from loa_cheval.types import ConfigError, ProviderConfig

# Provider type → adapter class mapping.
# - cycle-096 Sprint 1 added 'bedrock'.
# - codex-headless: routes through `codex exec` subprocess for ChatGPT
#   subscription auth (no OPENAI_API_KEY consumed). See codex_headless_adapter.py.
# - gemini-headless: routes through `gemini -p` subprocess for Google AI
#   subscription auth (no GOOGLE_API_KEY consumed). Sibling pattern to
#   codex-headless. See gemini_headless_adapter.py.
_ADAPTER_REGISTRY: Dict[str, Type[ProviderAdapter]] = {
    "openai": OpenAIAdapter,
    "anthropic": AnthropicAdapter,
    "openai_compat": OpenAIAdapter,  # OpenAI-compatible uses the same adapter
    "google": GoogleAdapter,
    "bedrock": BedrockAdapter,
    "codex-headless": CodexHeadlessAdapter,
    "gemini-headless": GeminiHeadlessAdapter,
}


def get_adapter(config: ProviderConfig) -> ProviderAdapter:
    """Get a provider adapter instance for the given config."""
    adapter_cls = _ADAPTER_REGISTRY.get(config.type)
    if adapter_cls is None:
        raise ConfigError(f"Unknown provider type: '{config.type}'. Supported: {list(_ADAPTER_REGISTRY.keys())}")
    return adapter_cls(config)


__all__ = [
    "ProviderAdapter",
    "OpenAIAdapter",
    "AnthropicAdapter",
    "GoogleAdapter",
    "BedrockAdapter",
    "CodexHeadlessAdapter",
    "GeminiHeadlessAdapter",
    "get_adapter",
]
