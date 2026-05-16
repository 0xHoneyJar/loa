"""Within-company invariant tests for chain_resolver (cycle-104 Sprint 2).

Pinned behavior:
- Every fallback_chain entry shares the primary's provider.
- A cross-company entry raises ConfigError at resolve() time, NOT silently.
- Duplicate entries (same provider:model_id twice) are rejected.
- A primary with no fallback_chain still resolves to a chain of length 1.
- Headless `kind: cli` is propagated to the ResolvedEntry.
- The `aliases:` indirection layer is honored (alias → provider:model).
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from loa_cheval.routing.chain_resolver import resolve
from loa_cheval.routing.types import ResolvedChain
from loa_cheval.types import ConfigError


def _config():
    """Minimal model-config.yaml shape for routing tests."""
    return {
        "aliases": {
            "gpt-5.5-pro": "openai:gpt-5.5-pro",
            "gpt-5.3-codex": "openai:gpt-5.3-codex",
            "claude-opus-4-7": "anthropic:claude-opus-4-7",
            "claude-sonnet-4-7": "anthropic:claude-sonnet-4-7",
        },
        "providers": {
            "openai": {
                "type": "openai",
                "endpoint": "https://api.openai.com/v1",
                "models": {
                    "gpt-5.5-pro": {
                        "capabilities": ["chat", "tools", "large_context"],
                        "fallback_chain": [
                            "openai:gpt-5.3-codex",
                            "openai:codex-headless",
                        ],
                    },
                    "gpt-5.3-codex": {
                        "capabilities": ["chat", "tools", "code"],
                        "fallback_chain": ["openai:codex-headless"],
                    },
                    "codex-headless": {
                        "kind": "cli",
                        "capabilities": ["chat", "code"],
                    },
                },
            },
            "anthropic": {
                "type": "anthropic",
                "endpoint": "https://api.anthropic.com/v1",
                "models": {
                    "claude-opus-4-7": {
                        "capabilities": [
                            "chat",
                            "tools",
                            "large_context",
                            "thinking",
                        ],
                        "fallback_chain": [
                            "anthropic:claude-sonnet-4-7",
                            "anthropic:claude-headless",
                        ],
                    },
                    "claude-sonnet-4-7": {
                        "capabilities": ["chat", "tools"],
                    },
                    "claude-headless": {
                        "kind": "cli",
                        "capabilities": ["chat"],
                    },
                },
            },
        },
    }


def test_resolve_returns_chain_for_primary_with_fallback():
    chain = resolve("gpt-5.5-pro", model_config=_config())
    assert isinstance(chain, ResolvedChain)
    assert chain.primary_alias == "gpt-5.5-pro"
    assert [e.canonical for e in chain.entries] == [
        "openai:gpt-5.5-pro",
        "openai:gpt-5.3-codex",
        "openai:codex-headless",
    ]
    assert chain.company == "openai"


def test_within_company_invariant_holds_for_every_entry():
    chain = resolve("claude-opus-4-7", model_config=_config())
    assert all(e.provider == "anthropic" for e in chain.entries)


def test_primary_without_fallback_chain_returns_length_one():
    chain = resolve("claude-sonnet-4-7", model_config=_config())
    assert len(chain.entries) == 1
    assert chain.entries[0].canonical == "anthropic:claude-sonnet-4-7"


def test_cross_company_entry_raises_config_error():
    cfg = _config()
    cfg["providers"]["openai"]["models"]["gpt-5.5-pro"]["fallback_chain"] = [
        "openai:gpt-5.3-codex",
        "anthropic:claude-opus-4-7",  # cross-company — forbidden
    ]
    with pytest.raises(ConfigError) as exc_info:
        resolve("gpt-5.5-pro", model_config=cfg)
    msg = str(exc_info.value)
    assert "crosses company boundary" in msg
    assert "anthropic:claude-opus-4-7" in msg
    assert "openai" in msg


def test_duplicate_entry_raises_config_error():
    cfg = _config()
    cfg["providers"]["openai"]["models"]["gpt-5.5-pro"]["fallback_chain"] = [
        "openai:gpt-5.3-codex",
        "openai:gpt-5.3-codex",  # duplicate
    ]
    with pytest.raises(ConfigError) as exc_info:
        resolve("gpt-5.5-pro", model_config=cfg)
    assert "duplicate entry" in str(exc_info.value)


def test_headless_kind_propagates_to_entry():
    chain = resolve("gpt-5.5-pro", model_config=_config())
    # entries[2] is codex-headless
    assert chain.entries[2].adapter_kind == "cli"
    assert chain.entries[0].adapter_kind == "http"
    assert chain.entries[1].adapter_kind == "http"


def test_capabilities_are_frozenset_on_every_entry():
    chain = resolve("gpt-5.5-pro", model_config=_config())
    for entry in chain.entries:
        assert isinstance(entry.capabilities, frozenset)


def test_primary_alias_unresolvable_raises_config_error():
    with pytest.raises(ConfigError):
        resolve("nonexistent-model", model_config=_config())


def test_chain_entry_references_unknown_model_raises():
    cfg = _config()
    cfg["providers"]["openai"]["models"]["gpt-5.5-pro"]["fallback_chain"] = [
        "openai:does-not-exist"
    ]
    with pytest.raises(ConfigError) as exc_info:
        resolve("gpt-5.5-pro", model_config=cfg)
    assert "does-not-exist" in str(exc_info.value) or "Model" in str(exc_info.value)


def test_resolve_is_idempotent():
    cfg = _config()
    a = resolve("gpt-5.5-pro", model_config=cfg)
    b = resolve("gpt-5.5-pro", model_config=cfg)
    assert [e.canonical for e in a.entries] == [e.canonical for e in b.entries]


def test_provider_model_id_form_accepted_as_primary():
    """Caller may pass the explicit provider:model form too."""
    chain = resolve("openai:gpt-5.5-pro", model_config=_config())
    assert chain.entries[0].canonical == "openai:gpt-5.5-pro"


def test_unknown_kind_raises_config_error():
    cfg = _config()
    cfg["providers"]["openai"]["models"]["gpt-5.5-pro"]["kind"] = "wat"
    with pytest.raises(ConfigError) as exc_info:
        resolve("gpt-5.5-pro", model_config=cfg)
    assert "unknown kind" in str(exc_info.value)


def test_empty_chain_entry_string_rejected():
    cfg = _config()
    cfg["providers"]["openai"]["models"]["gpt-5.5-pro"]["fallback_chain"] = [
        "openai:gpt-5.3-codex",
        "  ",  # whitespace-only spec
    ]
    with pytest.raises(ConfigError):
        resolve("gpt-5.5-pro", model_config=cfg)


def test_chain_is_immutable_tuple():
    chain = resolve("gpt-5.5-pro", model_config=_config())
    assert isinstance(chain.entries, tuple)
    with pytest.raises(AttributeError):
        chain.entries = ()  # type: ignore[misc]


def test_default_mode_is_prefer_api():
    chain = resolve("gpt-5.5-pro", model_config=_config())
    assert chain.headless_mode == "prefer-api"
    assert chain.headless_mode_source == "default"
