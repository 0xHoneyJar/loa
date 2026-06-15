"""Tests for Bedrock forward-routing (this PR).

Covers:
- ``_build_anthropic_to_bedrock_map`` inverts each Bedrock model's ``fallback_to``.
- ``_apply_bedrock_forward_routing`` rewrites Anthropic-targeted aliases to their
  Bedrock equivalent under bedrock_only / prefer_bedrock, and is a no-op otherwise.
- non-Anthropic aliases (openai/google) are left untouched.
- aliases already at ``bedrock:`` are left untouched (idempotent).
- ``_warn_misnested_compliance_profile`` warns on a stray top-level flag.
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from loa_cheval.config.loader import (  # noqa: E402
    _apply_bedrock_forward_routing,
    _build_anthropic_to_bedrock_map,
    _warn_misnested_compliance_profile,
)


def _bedrock(profile):
    return {
        "type": "bedrock",
        "compliance_profile": profile,
        "models": {
            "us.anthropic.claude-opus-4-8": {"fallback_to": "anthropic:claude-opus-4-8"},
            "us.anthropic.claude-sonnet-4-6": {"fallback_to": "anthropic:claude-sonnet-4-6"},
        },
    }


def _merged(profile):
    return {
        "providers": {"bedrock": _bedrock(profile)},
        "aliases": {
            "opus": "anthropic:claude-opus-4-8",
            "cheap": "anthropic:claude-sonnet-4-6",
            "gpt": "openai:gpt-5.5",
            "flash": "google:gemini-headless",
            "already": "bedrock:us.anthropic.claude-opus-4-8",
        },
    }


def test_build_inverse_map_from_fallback_to():
    table = _build_anthropic_to_bedrock_map(_bedrock("prefer_bedrock"))
    assert table == {
        "anthropic:claude-opus-4-8": "bedrock:us.anthropic.claude-opus-4-8",
        "anthropic:claude-sonnet-4-6": "bedrock:us.anthropic.claude-sonnet-4-6",
    }


def test_build_inverse_map_skips_models_without_fallback():
    bedrock = {"models": {"us.anthropic.x": {}, "us.anthropic.y": {"fallback_to": "anthropic:y"}}}
    assert _build_anthropic_to_bedrock_map(bedrock) == {"anthropic:y": "bedrock:us.anthropic.y"}


@pytest.mark.parametrize("profile", ["prefer_bedrock", "bedrock_only"])
def test_forward_routing_active_rewrites_anthropic_aliases(profile):
    merged = _merged(profile)
    _apply_bedrock_forward_routing(merged)
    a = merged["aliases"]
    assert a["opus"] == "bedrock:us.anthropic.claude-opus-4-8"
    assert a["cheap"] == "bedrock:us.anthropic.claude-sonnet-4-6"
    # other providers untouched
    assert a["gpt"] == "openai:gpt-5.5"
    assert a["flash"] == "google:gemini-headless"
    # already-bedrock untouched (idempotent)
    assert a["already"] == "bedrock:us.anthropic.claude-opus-4-8"


@pytest.mark.parametrize("profile", [None, "none"])
def test_forward_routing_noop_when_not_bedrock_posture(profile):
    merged = _merged(profile)
    before = dict(merged["aliases"])
    _apply_bedrock_forward_routing(merged)
    assert merged["aliases"] == before


def test_forward_routing_idempotent_second_pass():
    merged = _merged("prefer_bedrock")
    _apply_bedrock_forward_routing(merged)
    once = dict(merged["aliases"])
    _apply_bedrock_forward_routing(merged)
    assert merged["aliases"] == once


def test_forward_routing_no_bedrock_provider_is_safe():
    merged = {"providers": {}, "aliases": {"opus": "anthropic:claude-opus-4-8"}}
    _apply_bedrock_forward_routing(merged)
    assert merged["aliases"]["opus"] == "anthropic:claude-opus-4-8"


def test_misnested_compliance_profile_warns(capsys):
    merged = {"compliance_profile": "prefer_bedrock", "providers": {"bedrock": {}}}
    _warn_misnested_compliance_profile(merged)
    err = capsys.readouterr().err
    assert "WRONG level" in err
    assert "providers.bedrock.compliance_profile" in err


def test_misnested_silent_when_correctly_nested(capsys):
    merged = {
        "compliance_profile": "prefer_bedrock",
        "providers": {"bedrock": {"compliance_profile": "prefer_bedrock"}},
    }
    _warn_misnested_compliance_profile(merged)
    assert capsys.readouterr().err == ""


def test_misnested_silent_when_no_stray_key(capsys):
    merged = {"providers": {"bedrock": {"compliance_profile": "prefer_bedrock"}}}
    _warn_misnested_compliance_profile(merged)
    assert capsys.readouterr().err == ""
