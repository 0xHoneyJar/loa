"""sprint-bug-197 iter-2 (#979): _get_adapter_for_entry kind:cli dispatch shapes.

Two ways a ResolvedEntry can be kind:cli:
1. Family provider (anthropic/openai/google) with a kind:cli model — the
   _CLI_ADAPTER_BY_PROVIDER map reroutes to the sibling CLI adapter type.
2. Custom typed-headless provider (the documented example shape: a provider
   literally named `claude-headless` with `type: claude-headless`) — the
   provider's own type already selects the CLI adapter; the family map
   misses and must NOT raise.

Pre-iter-2, shape 2 raised ConfigError at invocation (the kind:cli inference
from iter-1 moved these providers onto the cli dispatch path where only the
family map was consulted).
"""

from __future__ import annotations

import sys
from pathlib import Path
from types import SimpleNamespace

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import cheval
from loa_cheval.providers.claude_headless_adapter import ClaudeHeadlessAdapter
from loa_cheval.providers.codex_headless_adapter import CodexHeadlessAdapter
from loa_cheval.providers.gemini_headless_adapter import GeminiHeadlessAdapter
from loa_cheval.types import ConfigError


def _hounfour(provider_id: str, ptype: str, model: str) -> dict:
    return {
        "providers": {
            provider_id: {
                "type": ptype,
                "endpoint": "",
                "auth": "",
                "models": {
                    model: {
                        "capabilities": ["chat"],
                        "context_window": 200000,
                        "auth_type": "headless",
                        "dispatch_group": "test-group",
                        "kind": "cli",
                    }
                },
            }
        }
    }


def _entry(provider_id: str) -> SimpleNamespace:
    return SimpleNamespace(provider=provider_id, adapter_kind="cli")


class TestTypedHeadlessProviders:
    @pytest.mark.parametrize(
        "provider_id, ptype, model, adapter_cls",
        [
            ("claude-headless", "claude-headless", "claude-opus-4-7", ClaudeHeadlessAdapter),
            ("my-codex", "codex-headless", "gpt-5.5", CodexHeadlessAdapter),
            ("gemini-headless", "gemini-headless", "gemini-3.1-pro-preview", GeminiHeadlessAdapter),
        ],
    )
    def test_custom_typed_headless_dispatches_by_type(
        self, provider_id, ptype, model, adapter_cls
    ):
        adapter = cheval._get_adapter_for_entry(
            _entry(provider_id), _hounfour(provider_id, ptype, model)
        )
        assert isinstance(adapter, adapter_cls)


class TestFamilyProviders:
    def test_family_provider_reroutes_via_map(self):
        # providers.anthropic with a kind:cli model → ClaudeHeadlessAdapter
        # via _CLI_ADAPTER_BY_PROVIDER (the original cycle-110 shape).
        adapter = cheval._get_adapter_for_entry(
            _entry("anthropic"), _hounfour("anthropic", "anthropic", "claude-opus-4-7")
        )
        assert isinstance(adapter, ClaudeHeadlessAdapter)


class TestUnbindableStillRejected:
    def test_non_headless_type_with_explicit_kind_cli_raises(self):
        with pytest.raises(ConfigError, match="no\\s+CLI adapter is registered"):
            cheval._get_adapter_for_entry(
                _entry("my-proxy"), _hounfour("my-proxy", "openai_compat", "some-model")
            )
