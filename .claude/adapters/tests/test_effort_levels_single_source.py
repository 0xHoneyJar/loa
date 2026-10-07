"""cycle-127 sprint-251 review r251-1 C5 (findings 24, 26).

* The effort levels are defined ONCE (``loa_cheval.types.EFFORT_LEVELS``):
  cheval's resolver, the argparse ``--effort`` choices, the v3 catalog schema
  (``params.default_effort``) and the MODELINV payload schema (``effort`` /
  ``effort_effective``) all agree with it.
* ``_effort_on_wire`` keys on the provider's TYPE, not its key string: an
  anthropic-type HTTP provider under any key gets the Anthropic per-family
  mapping; a headless/CLI type passes the value through; other types send
  nothing (None).
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parents[1]
sys.path.insert(0, str(ROOT))

import cheval  # type: ignore[import-not-found]  # noqa: E402
from loa_cheval.types import EFFORT_LEVELS  # noqa: E402


def _schema(rel: str) -> dict:
    return json.loads((REPO / rel).read_text())


def test_effort_levels_are_one_tuple_used_by_cheval():
    assert EFFORT_LEVELS == ("low", "medium", "high", "xhigh", "max")
    assert cheval._EFFORT_LEVELS is EFFORT_LEVELS


def test_argparse_effort_choices_are_the_constant(monkeypatch):
    """cheval builds its parser inside main(): capture it at parse_args and stop."""
    import argparse

    captured = {}

    class _Stop(Exception):
        pass

    def _grab(self, *a, **k):
        captured["parser"] = self
        raise _Stop

    monkeypatch.setattr(argparse.ArgumentParser, "parse_args", _grab)
    try:
        cheval.main()
    except _Stop:
        pass
    action = next(a for a in captured["parser"]._actions if "--effort" in a.option_strings)
    assert tuple(action.choices) == EFFORT_LEVELS


def test_schemas_enumerate_the_same_levels():
    v3 = _schema(".claude/data/schemas/model-config-v3.schema.json")

    def _find(node):
        if isinstance(node, dict):
            if "default_effort" in node and isinstance(node["default_effort"], dict) and "enum" in node["default_effort"]:
                return node["default_effort"]["enum"]
            for v in node.values():
                hit = _find(v)
                if hit is not None:
                    return hit
        elif isinstance(node, list):
            for v in node:
                hit = _find(v)
                if hit is not None:
                    return hit
        return None

    assert tuple(_find(v3)) == EFFORT_LEVELS
    payload = _schema(".claude/data/trajectory-schemas/model-events/model-invoke-complete.payload.schema.json")
    props = payload.get("properties", payload)
    assert tuple(props["effort_effective"]["enum"]) == EFFORT_LEVELS
    assert tuple(props["effort"]["enum"]) == EFFORT_LEVELS


def _hounfour(provider_key: str, ptype: str, model_id: str, entry: dict) -> dict:
    return {"providers": {provider_key: {"type": ptype, "models": {model_id: entry}}}}


def test_effort_on_wire_keys_on_the_provider_type_not_its_key():
    # an anthropic-type HTTP provider under another key: the Anthropic mapping (xhigh → high on 4.6; omitted on Haiku 4.5)
    h = _hounfour("anthropic-eu", "anthropic", "claude-opus-4-6", {"auth_type": "http_api"})
    assert cheval._effort_on_wire("anthropic-eu", "claude-opus-4-6", "xhigh", h) == "high"
    h = _hounfour("anthropic-eu", "anthropic", "claude-haiku-4-5-20251001", {"auth_type": "http_api"})
    assert cheval._effort_on_wire("anthropic-eu", "claude-haiku-4-5-20251001", "high", h) is None
    # a key named "anthropic" whose type is not anthropic gets no Anthropic rule
    h = _hounfour("anthropic", "openai_compat", "claude-opus-4-6", {"auth_type": "http_api"})
    assert cheval._effort_on_wire("anthropic", "claude-opus-4-6", "xhigh", h) is None
    # a headless provider type passes through even without a per-model kind marker
    h = _hounfour("claude-cli", "claude-headless", "opus", {})
    assert cheval._effort_on_wire("claude-cli", "opus", "xhigh", h) == "xhigh"
    # other HTTP types send nothing
    h = _hounfour("bedrock", "bedrock", "us.anthropic.claude-opus-4-8", {"auth_type": "http_api"})
    assert cheval._effort_on_wire("bedrock", "us.anthropic.claude-opus-4-8", "high", h) is None
    # a provider block without `type` falls back to its key (pre-type configs keep today's behaviour)
    h = {"providers": {"anthropic": {"models": {"claude-opus-4-6": {}}}}}
    assert cheval._effort_on_wire("anthropic", "claude-opus-4-6", "xhigh", h) == "high"
