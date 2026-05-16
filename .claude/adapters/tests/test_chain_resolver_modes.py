"""Headless-mode transform tests for chain_resolver (cycle-104 Sprint 2).

AC-2.3: `LOA_HEADLESS_MODE` × {prefer-api, prefer-cli, api-only, cli-only}
produces 4 distinct resolved chain orderings/filterings.

Also covers `resolve_headless_mode` precedence (env wins over config wins
over default).
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from loa_cheval.routing.chain_resolver import (
    DEFAULT_HEADLESS_MODE,
    resolve,
    resolve_headless_mode,
)
from loa_cheval.routing.types import NoEligibleAdapterError


def _config():
    return {
        "aliases": {
            "gpt-5.5-pro": "openai:gpt-5.5-pro",
            "gpt-5.3-codex": "openai:gpt-5.3-codex",
            "claude-opus-4-7": "anthropic:claude-opus-4-7",
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
                        "capabilities": ["chat", "code"],
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
                        "capabilities": ["chat", "tools"],
                        "fallback_chain": ["anthropic:claude-sonnet-4-7"],
                    },
                    "claude-sonnet-4-7": {
                        "capabilities": ["chat"],
                    },
                },
            },
        },
    }


# --- Mode transform: 4 distinct shapes ---


def test_prefer_api_keeps_http_first_cli_last():
    chain = resolve(
        "gpt-5.5-pro", model_config=_config(), headless_mode="prefer-api"
    )
    kinds = [e.adapter_kind for e in chain.entries]
    assert kinds == ["http", "http", "cli"]


def test_prefer_cli_moves_cli_first():
    chain = resolve(
        "gpt-5.5-pro", model_config=_config(), headless_mode="prefer-cli"
    )
    kinds = [e.adapter_kind for e in chain.entries]
    assert kinds == ["cli", "http", "http"]


def test_api_only_drops_cli_entries():
    chain = resolve(
        "gpt-5.5-pro", model_config=_config(), headless_mode="api-only"
    )
    assert all(e.adapter_kind == "http" for e in chain.entries)
    assert len(chain.entries) == 2  # primary + first fallback


def test_cli_only_drops_http_entries():
    chain = resolve(
        "gpt-5.5-pro", model_config=_config(), headless_mode="cli-only"
    )
    assert all(e.adapter_kind == "cli" for e in chain.entries)
    assert [e.canonical for e in chain.entries] == ["openai:codex-headless"]


# --- 4-mode shape distinctness (the AC-2.3 spec wording) ---


def test_four_modes_produce_distinct_chain_signatures():
    cfg = _config()
    sig = lambda m: tuple(  # noqa: E731
        e.canonical for e in resolve("gpt-5.5-pro", model_config=cfg, headless_mode=m).entries
    )
    sigs = {m: sig(m) for m in ("prefer-api", "prefer-cli", "api-only", "cli-only")}
    # All 4 distinct.
    assert len(set(sigs.values())) == 4, sigs


# --- Fail-loud cases ---


def test_cli_only_with_no_cli_entry_raises_no_eligible_adapter():
    """SDD §1.4.1 fail-loud: cli-only on a primary with no headless raises."""
    cfg = _config()
    # Drop the CLI fallback from the chain.
    cfg["providers"]["openai"]["models"]["gpt-5.5-pro"]["fallback_chain"] = [
        "openai:gpt-5.3-codex",
    ]
    with pytest.raises(NoEligibleAdapterError) as exc_info:
        resolve(
            "gpt-5.5-pro",
            model_config=cfg,
            headless_mode="cli-only",
        )
    assert exc_info.value.code == "NO_ELIGIBLE_ADAPTER"
    assert exc_info.value.retryable is False
    assert "cli-only" in str(exc_info.value)


def test_api_only_with_only_cli_entry_raises():
    """A chain that is CLI-only under api-only mode also fails fast."""
    cfg = _config()
    # Tweak gpt-5.5-pro itself to be CLI (synthetic — not how YAML would
    # really declare it, but exercises the symmetric fail-loud branch).
    cfg["providers"]["openai"]["models"]["gpt-5.5-pro"]["kind"] = "cli"
    cfg["providers"]["openai"]["models"]["gpt-5.5-pro"]["fallback_chain"] = []
    with pytest.raises(NoEligibleAdapterError):
        resolve("gpt-5.5-pro", model_config=cfg, headless_mode="api-only")


def test_invalid_mode_raises_value_error():
    with pytest.raises(ValueError):
        resolve(
            "gpt-5.5-pro",
            model_config=_config(),
            headless_mode="wat",  # type: ignore[arg-type]
        )


# --- resolve_headless_mode precedence (SDD §3.3) ---


def test_resolve_headless_mode_default_when_no_env_no_config():
    mode, source = resolve_headless_mode(config=None, env={})
    assert mode == DEFAULT_HEADLESS_MODE
    assert source == "default"


def test_resolve_headless_mode_picks_config_when_env_unset():
    cfg = {"hounfour": {"headless": {"mode": "prefer-cli"}}}
    mode, source = resolve_headless_mode(config=cfg, env={})
    assert mode == "prefer-cli"
    assert source == "config"


def test_resolve_headless_mode_env_wins_over_config():
    cfg = {"hounfour": {"headless": {"mode": "prefer-cli"}}}
    env = {"LOA_HEADLESS_MODE": "cli-only"}
    mode, source = resolve_headless_mode(config=cfg, env=env)
    assert mode == "cli-only"
    assert source == "env"


def test_resolve_headless_mode_empty_env_falls_through():
    """Empty string env value behaves as unset (operator convenience)."""
    cfg = {"hounfour": {"headless": {"mode": "api-only"}}}
    env = {"LOA_HEADLESS_MODE": ""}
    mode, source = resolve_headless_mode(config=cfg, env=env)
    assert mode == "api-only"
    assert source == "config"


def test_resolve_headless_mode_invalid_env_value_raises():
    env = {"LOA_HEADLESS_MODE": "definitely-not-a-mode"}
    with pytest.raises(ValueError):
        resolve_headless_mode(config=None, env=env)


def test_resolve_headless_mode_invalid_config_value_raises():
    cfg = {"hounfour": {"headless": {"mode": "totally-wrong"}}}
    with pytest.raises(ValueError):
        resolve_headless_mode(config=cfg, env={})


def test_resolve_records_source_provenance_in_chain():
    chain = resolve(
        "gpt-5.5-pro",
        model_config=_config(),
        headless_mode="prefer-cli",
        headless_mode_source="env",
    )
    assert chain.headless_mode == "prefer-cli"
    assert chain.headless_mode_source == "env"


# --- Stable order property ---


def test_transforms_preserve_relative_order_within_kind():
    """`prefer-api` keeps original HTTP order; `prefer-cli` keeps CLI order."""
    cfg = _config()
    # Build a chain with two HTTP and two CLI entries to make stability
    # observable (otherwise trivially satisfied with one of each).
    cfg["providers"]["openai"]["models"]["second-headless"] = {
        "kind": "cli",
        "capabilities": ["chat"],
    }
    cfg["aliases"]["second-headless"] = "openai:second-headless"
    cfg["providers"]["openai"]["models"]["gpt-5.5-pro"]["fallback_chain"] = [
        "openai:gpt-5.3-codex",
        "openai:codex-headless",
        "openai:second-headless",
    ]

    pref_api = resolve("gpt-5.5-pro", model_config=cfg, headless_mode="prefer-api")
    assert [e.canonical for e in pref_api.entries] == [
        "openai:gpt-5.5-pro",
        "openai:gpt-5.3-codex",
        "openai:codex-headless",
        "openai:second-headless",
    ]

    pref_cli = resolve("gpt-5.5-pro", model_config=cfg, headless_mode="prefer-cli")
    assert [e.canonical for e in pref_cli.entries] == [
        "openai:codex-headless",
        "openai:second-headless",
        "openai:gpt-5.5-pro",
        "openai:gpt-5.3-codex",
    ]
