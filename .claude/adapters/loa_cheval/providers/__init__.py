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
from loa_cheval.providers.claude_headless_adapter import ClaudeHeadlessAdapter
from loa_cheval.providers.cursor_headless_adapter import CursorHeadlessAdapter
from loa_cheval.providers.grok_headless_adapter import GrokHeadlessAdapter
from loa_cheval.providers.agy_headless_adapter import AgyHeadlessAdapter
from loa_cheval.types import ConfigError, ProviderConfig

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
_ADAPTER_REGISTRY: Dict[str, Type[ProviderAdapter]] = {
    "openai": OpenAIAdapter,
    "anthropic": AnthropicAdapter,
    "openai_compat": OpenAIAdapter,  # OpenAI-compatible uses the same adapter
    "google": GoogleAdapter,
    "bedrock": BedrockAdapter,
    "codex-headless": CodexHeadlessAdapter,
    "gemini-headless": AgyHeadlessAdapter,  # FR-5 repoint: gemini-cli (dead, IneligibleTier) → agy
    "claude-headless": ClaudeHeadlessAdapter,
    "cursor-headless": CursorHeadlessAdapter,
    "grok-headless": GrokHeadlessAdapter,
}


def get_adapter(config: ProviderConfig) -> ProviderAdapter:
    """Get a provider adapter instance for the given config."""
    adapter_cls = _ADAPTER_REGISTRY.get(config.type)
    if adapter_cls is None:
        raise ConfigError(f"Unknown provider type: '{config.type}'. Supported: {list(_ADAPTER_REGISTRY.keys())}")
    return adapter_cls(config)


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
        for t, cls in _ADAPTER_REGISTRY.items()
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
    "cli_adapter_types",
]
