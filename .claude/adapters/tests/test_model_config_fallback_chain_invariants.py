"""Cycle-104 Sprint 2 T2.3: lint every primary's fallback_chain in
`.claude/defaults/model-config.yaml` against the within-company invariant.

This is the load-time gate: if any primary has a cross-company chain entry,
or references an unknown alias, this test fails before cheval ever boots.
The intent (AC-2.1) is "NO chain entry references a different company
prefix". Headless aliases (`*-headless`, `kind: cli`) are exercised through
chain_resolver.resolve() so the kind propagates to ResolvedEntry.
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import yaml

from loa_cheval.routing.chain_resolver import resolve
from loa_cheval.routing.types import ResolvedChain
from loa_cheval.types import ConfigError


REPO_ROOT = Path(__file__).resolve().parents[3]
DEFAULT_CONFIG = REPO_ROOT / ".claude" / "defaults" / "model-config.yaml"

# Sprint 2 explicitly scopes within-company chains to the 3 BB-consensus
# companies. Bedrock is a separate dispatch path; the cycle-104 invariant
# is documented but not enforced for `bedrock:` provider in this sprint.
TARGET_COMPANIES = frozenset({"openai", "anthropic", "google"})

# Models intentionally exempt — they ARE the chain terminals.
HEADLESS_MODELS = frozenset(
    {
        "openai:codex-headless",
        "anthropic:claude-headless",
        "google:gemini-headless",
    }
)


def _load_config() -> dict:
    assert DEFAULT_CONFIG.exists(), f"missing {DEFAULT_CONFIG}"
    with DEFAULT_CONFIG.open() as fh:
        return yaml.safe_load(fh)


def _iter_primary_models(config: dict):
    """Yield `(provider, model_id)` for every non-headless model in the 3 target companies."""
    for provider in TARGET_COMPANIES:
        prov_block = config.get("providers", {}).get(provider) or {}
        for model_id in (prov_block.get("models") or {}).keys():
            canonical = f"{provider}:{model_id}"
            if canonical in HEADLESS_MODELS:
                continue
            yield provider, model_id


def test_default_config_is_readable():
    cfg = _load_config()
    assert "providers" in cfg
    assert "aliases" in cfg


def test_every_target_company_primary_declares_fallback_chain():
    """AC-2.1: every primary in OpenAI/Anthropic/Google has a chain."""
    cfg = _load_config()
    missing = []
    for provider, model_id in _iter_primary_models(cfg):
        chain = (
            cfg["providers"][provider]["models"][model_id].get("fallback_chain")
            or []
        )
        if not chain:
            missing.append(f"{provider}:{model_id}")
    assert not missing, (
        f"primary models without fallback_chain: {missing}. "
        "Cycle-104 AC-2.1 requires every primary to declare a within-company chain."
    )


def test_every_primary_chain_resolves_without_cross_company_entries():
    """The load-bearing invariant. Cross-company entries raise ConfigError.

    We pass `provider:model_id` form to resolve() rather than the bare
    model_id — many model_ids (e.g. `claude-opus-4-7`) are not also alias
    keys; the alias layer is Sprint-2-orthogonal.
    """
    cfg = _load_config()
    errors = []
    for provider, model_id in _iter_primary_models(cfg):
        primary = f"{provider}:{model_id}"
        try:
            chain = resolve(primary, model_config=cfg)
        except ConfigError as exc:
            errors.append(f"{primary}: {exc}")
            continue
        assert isinstance(chain, ResolvedChain)
        if chain.company != provider:
            errors.append(
                f"{primary} resolved into company={chain.company!r} "
                "(should equal primary's provider)"
            )
        for entry in chain.entries:
            if entry.provider != provider:
                errors.append(
                    f"{primary} chain entry {entry.canonical} "
                    f"crosses company boundary (primary={provider})"
                )
    assert not errors, "cross-company / unresolvable chain entries:\n" + "\n".join(errors)


@pytest.mark.parametrize(
    "headless_alias,expected_canonical,expected_kind",
    [
        ("codex-headless", "openai:codex-headless", "cli"),
        ("claude-headless", "anthropic:claude-headless", "cli"),
        ("gemini-headless", "google:gemini-headless", "cli"),
    ],
)
def test_headless_aliases_declare_kind_cli(headless_alias, expected_canonical, expected_kind):
    """FR-S2.2: headless aliases declared in alias map + kind: cli on model."""
    cfg = _load_config()
    aliases = cfg.get("aliases") or {}
    target = aliases.get(headless_alias)
    assert target == expected_canonical, (
        f"alias '{headless_alias}' must resolve to '{expected_canonical}'; "
        f"got {target!r}"
    )
    provider, model_id = expected_canonical.split(":", 1)
    model = cfg["providers"][provider]["models"][model_id]
    assert model.get("kind") == expected_kind
    caps = model.get("capabilities") or []
    assert "chat" in caps, (
        f"headless alias {headless_alias} must declare capability 'chat'"
    )


def test_each_company_terminates_in_its_own_headless_when_available():
    """Per SDD §1.4.6: chain ends in within-company headless OR smallest within-company model."""
    cfg = _load_config()
    expectations = {
        "openai": "openai:codex-headless",
        "anthropic": "anthropic:claude-headless",
        "google": "google:gemini-headless",
    }
    misses = []
    for provider, model_id in _iter_primary_models(cfg):
        primary = f"{provider}:{model_id}"
        chain = resolve(primary, model_config=cfg)
        terminal = chain.entries[-1].canonical
        if terminal != expectations[provider]:
            # Allow non-headless terminals only if the model has a documented
            # reason (e.g., a single-entry chain to the smallest model). For
            # now we surface mismatches as a soft check; primary models can
            # still be valid without ending in headless if the operator
            # opted out per documented exception.
            misses.append(f"{provider}:{model_id} terminal={terminal!r} (expected {expectations[provider]!r})")
    # Hard assertion: every target-company primary that has a multi-entry
    # chain MUST terminate in the company's headless. Single-entry chains
    # (primary alone) are caught by the prior test (`fallback_chain` empty).
    assert not misses, (
        "Sprint 2 D2.3 requires every primary chain to terminate in its "
        "within-company headless alias:\n  " + "\n  ".join(misses)
    )


def test_headless_aliases_have_no_fallback_chain():
    """Headless entries are chain terminals — they MUST NOT have their own fallback_chain."""
    cfg = _load_config()
    bad = []
    for canonical in HEADLESS_MODELS:
        provider, model_id = canonical.split(":", 1)
        model = cfg["providers"][provider]["models"][model_id]
        if model.get("fallback_chain"):
            bad.append(canonical)
    assert not bad, (
        "headless aliases must not declare fallback_chain (they're terminals): "
        f"{bad}"
    )
