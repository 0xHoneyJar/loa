"""Provider adapter registry."""

from __future__ import annotations

import importlib
from typing import TYPE_CHECKING, Any, Dict, Optional, Type

from loa_cheval.providers.base import ProviderAdapter
from loa_cheval.types import ConfigError, ProviderConfig

if TYPE_CHECKING:  # names resolved lazily at runtime via module __getattr__ below
    from loa_cheval.providers.openai_adapter import OpenAIAdapter
    from loa_cheval.providers.anthropic_adapter import AnthropicAdapter
    from loa_cheval.providers.google_adapter import GoogleAdapter
    from loa_cheval.providers.bedrock_adapter import BedrockAdapter
    from loa_cheval.providers.codex_headless_adapter import CodexHeadlessAdapter
    from loa_cheval.providers.gemini_headless_adapter import GeminiHeadlessAdapter
    from loa_cheval.providers.claude_headless_adapter import ClaudeHeadlessAdapter
    from loa_cheval.providers.cursor_headless_adapter import CursorHeadlessAdapter
    from loa_cheval.providers.grok_headless_adapter import GrokHeadlessAdapter
    from loa_cheval.providers.agy_headless_adapter import AgyHeadlessAdapter

# Adapter class name -> defining module. Each adapter module is imported on first use
# (registry lookup or ``from loa_cheval.providers import <Name>``), not at package
# import: a cheval spawn needs one adapter, not all ten (eso pass 17).
_ADAPTER_MODULES: Dict[str, str] = {
    "OpenAIAdapter": "loa_cheval.providers.openai_adapter",
    "AnthropicAdapter": "loa_cheval.providers.anthropic_adapter",
    "GoogleAdapter": "loa_cheval.providers.google_adapter",
    "BedrockAdapter": "loa_cheval.providers.bedrock_adapter",
    "CodexHeadlessAdapter": "loa_cheval.providers.codex_headless_adapter",
    "GeminiHeadlessAdapter": "loa_cheval.providers.gemini_headless_adapter",
    "ClaudeHeadlessAdapter": "loa_cheval.providers.claude_headless_adapter",
    "CursorHeadlessAdapter": "loa_cheval.providers.cursor_headless_adapter",
    "GrokHeadlessAdapter": "loa_cheval.providers.grok_headless_adapter",
    "AgyHeadlessAdapter": "loa_cheval.providers.agy_headless_adapter",
}


def _adapter_class(name: str) -> Any:
    """Adapter class by name, preferring the copy cached in module globals so every
    path (registry, get_adapter, ``from loa_cheval.providers import X``) yields the
    SAME class object even if a test later evicts the adapter module from sys.modules
    (the eager imports this replaces bound the class once, at package import)."""
    return globals().get(name) or __getattr__(name)


def __getattr__(name: str) -> Any:
    if name == "_ADAPTER_REGISTRY":
        # Full plain dict (type -> class), same contents and key order as the former eager
        # table. Built on first touch (tests, cli_adapter_types) and cached in globals();
        # cheval's normal path resolves one type via _ADAPTER_TYPES instead.
        registry: Dict[str, Type[ProviderAdapter]] = {t: _adapter_class(c) for t, c in _ADAPTER_TYPES.items()}
        globals()["_ADAPTER_REGISTRY"] = registry
        return registry
    module = _ADAPTER_MODULES.get(name)
    if module is None:
        raise AttributeError(f"module {__name__!r} has no attribute {name!r}")
    cls = getattr(importlib.import_module(module), name)
    globals()[name] = cls  # cache: later lookups bypass __getattr__
    return cls


# Provider type → adapter class mapping.
# - cycle-096 Sprint 1 added 'bedrock'.
# - codex-headless: routes through `codex exec` for ChatGPT subscription auth
#   (no OPENAI_API_KEY consumed). See codex_headless_adapter.py.
# - gemini-headless: routes through `agy -p` (Antigravity CLI) — the FR-5 repoint
#   (loa#1096, #1089) after Google retired the gemini-cli's individual Code Assist
#   tier (IneligibleTierError, "migrate to Antigravity"). agy's Gemini models restore
#   the Google-lineage voice. See agy_headless_adapter.py. The GeminiHeadlessAdapter
#   class is kept for reference; `gemini-api` (#1091, HTTP) stays the fallback.
# - claude-headless: routes through `claude -p` (Claude Code CLI) for Claude
#   Max/Pro subscription auth (no ANTHROPIC_API_KEY consumed). Different
#   from `claude-code:session` (NATIVE_PROVIDER) — that's the in-process
#   native runtime; this is a subprocess CLI invocation. See
#   claude_headless_adapter.py.
# - cursor-headless: routes through `cursor-agent -p` (Cursor Agent CLI) for
#   Cursor subscription auth (no API key consumed). Brings the Composer model
#   line (Moonshot-Kimi base + agentic RL) in as a distinct-corpus voice for
#   consensus panels. Read-only + sandboxed (the prompt is untrusted). See
#   cursor_headless_adapter.py.
# - grok-headless: routes through `grok --prompt-file ... --output-format json`
#   (xAI Grok Build CLI) for xAI subscription auth (OIDC; no API key consumed).
#   A headless CLI is a multi-model client (`grok models` → grok-build +
#   grok-composer-2.5-fast; `cursor-agent models` spans Claude/GPT/Gemini/Grok/
#   Kimi/Composer — CLIs cross-serve). Cheval pins this `xai` entry to grok's
#   served models via cli_model; it adds direct-subscription access to grok-build
#   (an xAI agentic model not pinned elsewhere). Pure inference, isolated cwd,
#   prompt-via-file (the prompt is untrusted). See
#   grok_headless_adapter.py.
_ADAPTER_TYPES: Dict[str, str] = {
    "openai": "OpenAIAdapter",
    "anthropic": "AnthropicAdapter",
    "openai_compat": "OpenAIAdapter",  # OpenAI-compatible uses the same adapter
    "google": "GoogleAdapter",
    "bedrock": "BedrockAdapter",
    "codex-headless": "CodexHeadlessAdapter",
    "gemini-headless": "AgyHeadlessAdapter",  # FR-5 repoint: gemini-cli (dead, IneligibleTier) → agy
    "claude-headless": "ClaudeHeadlessAdapter",
    "cursor-headless": "CursorHeadlessAdapter",
    "grok-headless": "GrokHeadlessAdapter",
}


def get_adapter(config: ProviderConfig) -> ProviderAdapter:
    """Get a provider adapter instance for the given config."""
    adapter_cls = adapter_class_for_type(config.type)
    if adapter_cls is None:
        raise ConfigError(f"Unknown provider type: '{config.type}'. Supported: {list(_ADAPTER_TYPES)}")
    return adapter_cls(config)


def adapter_class_for_type(adapter_type: str) -> Optional[Type[ProviderAdapter]]:
    """The registered adapter class for a provider ``type`` (None when unknown) —
    cycle-127 r251-1 C5: cheval asks it what reaches the wire (``wire_effort``)."""
    name = _ADAPTER_TYPES.get(adapter_type)
    return None if name is None else _adapter_class(name)


def cli_adapter_types() -> frozenset:
    """Adapter types that dispatch via a subscription-CLI subprocess (kind: cli).

    Derived from the registry so a NEW headless adapter is admitted by the
    kind:cli dispatch path automatically — review #966 closed the gap where
    cursor-headless was registered here but rejected by cheval's closed
    escape-hatch list. Keyed on the adapter class's own auth_type contract,
    not the name convention (BB #966 round-2): the attribute IS the semantic;
    a rename cannot silently drop an adapter from CLI admission.
    """
    return frozenset(
        t
        for t, cls in (globals().get("_ADAPTER_REGISTRY") or __getattr__("_ADAPTER_REGISTRY")).items()
        if getattr(cls, "auth_type", None) == "headless"
    )


__all__ = [
    "ProviderAdapter",
    "OpenAIAdapter",
    "AnthropicAdapter",
    "GoogleAdapter",
    "BedrockAdapter",
    "CodexHeadlessAdapter",
    "GeminiHeadlessAdapter",
    "AgyHeadlessAdapter",
    "ClaudeHeadlessAdapter",
    "CursorHeadlessAdapter",
    "GrokHeadlessAdapter",
    "get_adapter",
    "adapter_class_for_type",
    "cli_adapter_types",
]
