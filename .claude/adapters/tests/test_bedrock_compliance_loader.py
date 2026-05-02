"""Tests for Bedrock compliance_profile defaulting in loader (Task 1.5 / SDD §5.6).

Covers the 4-step deterministic rule:

1. Explicit user value → kept (validated)
2. AWS_BEARER_TOKEN_BEDROCK set, ANTHROPIC_API_KEY unset → bedrock_only
3. Both env vars set → prefer_bedrock
4. AWS_BEARER_TOKEN_BEDROCK unset → None (Bedrock unused)

Plus the SKP-003 fallback_to invariant:
- prefer_bedrock with any model lacking fallback_to → ConfigError at load time

Plus the auth_modes invariant:
- auth_modes without 'api_key' → ConfigError (sigv4 is v2 path)

Plus the one-shot migration-notice sentinel behavior.
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from loa_cheval.config.loader import (  # noqa: E402
    _enforce_prefer_bedrock_fallback_to,
    _reject_unsupported_bedrock_auth_modes,
    _resolve_bedrock_compliance_profile,
)
from loa_cheval.types import ConfigError  # noqa: E402


# Reset module-level latch between tests (one-shot notice latch).
@pytest.fixture(autouse=True)
def _reset_notice_latch():
    import loa_cheval.config.loader as ldr

    ldr._bedrock_migration_notice_emitted = False
    yield
    ldr._bedrock_migration_notice_emitted = False


def _bedrock_block(*, compliance_profile=None, models=None, auth_modes=None):
    block = {
        "type": "bedrock",
        "endpoint": "https://bedrock-runtime.{region}.amazonaws.com",
        "auth": "{env:AWS_BEARER_TOKEN_BEDROCK}",
        "compliance_profile": compliance_profile,
        "models": models or {
            "us.anthropic.claude-opus-4-7": {
                "capabilities": ["chat"],
                "fallback_to": "anthropic:claude-opus-4-7",
                "fallback_mapping_version": 1,
            }
        },
    }
    if auth_modes is not None:
        block["auth_modes"] = auth_modes
    return block


# ---------------------------------------------------------------------------
# Rule 1: explicit value wins
# ---------------------------------------------------------------------------


def test_rule1_explicit_bedrock_only_kept(monkeypatch):
    monkeypatch.setenv("AWS_BEARER_TOKEN_BEDROCK", "token")
    monkeypatch.setenv("ANTHROPIC_API_KEY", "anth-key")
    monkeypatch.setenv("LOA_CACHE_DIR", str(Path("/tmp/loa-test-cache")))

    merged = {"providers": {"bedrock": _bedrock_block(compliance_profile="bedrock_only")}}
    _resolve_bedrock_compliance_profile(merged)
    assert merged["providers"]["bedrock"]["compliance_profile"] == "bedrock_only"


def test_rule1_explicit_prefer_bedrock_validates_fallback_to(monkeypatch):
    monkeypatch.setenv("AWS_BEARER_TOKEN_BEDROCK", "token")
    merged = {
        "providers": {
            "bedrock": _bedrock_block(
                compliance_profile="prefer_bedrock",
                models={
                    "us.anthropic.claude-opus-4-7": {
                        "capabilities": ["chat"],
                        # MISSING fallback_to — should raise
                    }
                },
            )
        }
    }
    with pytest.raises(ConfigError, match="fallback_to"):
        _resolve_bedrock_compliance_profile(merged)


def test_rule1_explicit_invalid_value_raises():
    merged = {"providers": {"bedrock": _bedrock_block(compliance_profile="invalid_value")}}
    with pytest.raises(ConfigError, match="must be one of"):
        _resolve_bedrock_compliance_profile(merged)


def test_rule1_explicit_none_kept():
    """Explicit 'none' is allowed (operator opt-in to silent fallback)."""
    merged = {"providers": {"bedrock": _bedrock_block(compliance_profile="none")}}
    _resolve_bedrock_compliance_profile(merged)
    assert merged["providers"]["bedrock"]["compliance_profile"] == "none"


# ---------------------------------------------------------------------------
# Rule 2: bedrock_only when only Bedrock token set
# ---------------------------------------------------------------------------


def test_rule2_bedrock_token_only_defaults_to_bedrock_only(monkeypatch, tmp_path):
    monkeypatch.setenv("AWS_BEARER_TOKEN_BEDROCK", "token")
    monkeypatch.delenv("ANTHROPIC_API_KEY", raising=False)
    monkeypatch.setenv("LOA_CACHE_DIR", str(tmp_path))

    merged = {"providers": {"bedrock": _bedrock_block(compliance_profile=None)}}
    _resolve_bedrock_compliance_profile(merged)
    assert merged["providers"]["bedrock"]["compliance_profile"] == "bedrock_only"


# ---------------------------------------------------------------------------
# Rule 3: prefer_bedrock when both env vars set
# ---------------------------------------------------------------------------


def test_rule3_both_tokens_default_to_prefer_bedrock(monkeypatch, tmp_path):
    monkeypatch.setenv("AWS_BEARER_TOKEN_BEDROCK", "token")
    monkeypatch.setenv("ANTHROPIC_API_KEY", "anth-key")
    monkeypatch.setenv("LOA_CACHE_DIR", str(tmp_path))

    merged = {"providers": {"bedrock": _bedrock_block(compliance_profile=None)}}
    _resolve_bedrock_compliance_profile(merged)
    assert merged["providers"]["bedrock"]["compliance_profile"] == "prefer_bedrock"


def test_rule3_prefer_bedrock_default_validates_fallback_to(monkeypatch, tmp_path):
    """When auto-defaulting to prefer_bedrock, the fallback_to invariant still applies."""
    monkeypatch.setenv("AWS_BEARER_TOKEN_BEDROCK", "token")
    monkeypatch.setenv("ANTHROPIC_API_KEY", "anth-key")
    monkeypatch.setenv("LOA_CACHE_DIR", str(tmp_path))

    merged = {
        "providers": {
            "bedrock": _bedrock_block(
                compliance_profile=None,
                models={"us.anthropic.claude-opus-4-7": {"capabilities": ["chat"]}},
            )
        }
    }
    with pytest.raises(ConfigError, match="fallback_to"):
        _resolve_bedrock_compliance_profile(merged)


# ---------------------------------------------------------------------------
# Rule 4: no Bedrock token → None
# ---------------------------------------------------------------------------


def test_rule4_no_bedrock_token_leaves_none(monkeypatch):
    monkeypatch.delenv("AWS_BEARER_TOKEN_BEDROCK", raising=False)
    monkeypatch.setenv("ANTHROPIC_API_KEY", "anth-key")

    merged = {"providers": {"bedrock": _bedrock_block(compliance_profile=None)}}
    _resolve_bedrock_compliance_profile(merged)
    assert merged["providers"]["bedrock"]["compliance_profile"] is None


# ---------------------------------------------------------------------------
# Migration notice — one-shot, sentinel-gated
# ---------------------------------------------------------------------------


def test_migration_notice_emitted_on_first_default(monkeypatch, tmp_path, capsys):
    monkeypatch.setenv("AWS_BEARER_TOKEN_BEDROCK", "token")
    monkeypatch.delenv("ANTHROPIC_API_KEY", raising=False)
    monkeypatch.setenv("LOA_CACHE_DIR", str(tmp_path))

    merged = {"providers": {"bedrock": _bedrock_block(compliance_profile=None)}}
    _resolve_bedrock_compliance_profile(merged)

    captured = capsys.readouterr()
    assert "compliance_profile" in captured.err
    assert "bedrock_only" in captured.err
    # Sentinel was created so subsequent process won't notice.
    assert (tmp_path / "bedrock-migration-acked.sentinel").exists()


def test_migration_notice_suppressed_when_sentinel_exists(monkeypatch, tmp_path, capsys):
    monkeypatch.setenv("AWS_BEARER_TOKEN_BEDROCK", "token")
    monkeypatch.delenv("ANTHROPIC_API_KEY", raising=False)
    monkeypatch.setenv("LOA_CACHE_DIR", str(tmp_path))

    sentinel = tmp_path / "bedrock-migration-acked.sentinel"
    sentinel.touch()

    merged = {"providers": {"bedrock": _bedrock_block(compliance_profile=None)}}
    _resolve_bedrock_compliance_profile(merged)

    captured = capsys.readouterr()
    assert captured.err == ""  # silent


def test_migration_notice_one_shot_per_process(monkeypatch, tmp_path, capsys):
    """Multiple defaultings in the same process emit at most once."""
    monkeypatch.setenv("AWS_BEARER_TOKEN_BEDROCK", "token")
    monkeypatch.delenv("ANTHROPIC_API_KEY", raising=False)
    monkeypatch.setenv("LOA_CACHE_DIR", str(tmp_path))

    # First call emits the notice and creates the sentinel.
    merged_a = {"providers": {"bedrock": _bedrock_block(compliance_profile=None)}}
    _resolve_bedrock_compliance_profile(merged_a)
    capsys.readouterr()  # discard

    # Second call within the same process — no notice.
    merged_b = {"providers": {"bedrock": _bedrock_block(compliance_profile=None)}}
    _resolve_bedrock_compliance_profile(merged_b)
    captured = capsys.readouterr()
    assert captured.err == ""


# ---------------------------------------------------------------------------
# auth_modes invariant
# ---------------------------------------------------------------------------


def test_auth_modes_must_include_api_key():
    merged = {"providers": {"bedrock": _bedrock_block(auth_modes=["sigv4"])}}
    with pytest.raises(ConfigError, match="api_key"):
        _reject_unsupported_bedrock_auth_modes(merged)


def test_auth_modes_with_api_key_passes():
    merged = {"providers": {"bedrock": _bedrock_block(auth_modes=["api_key", "sigv4"])}}
    _reject_unsupported_bedrock_auth_modes(merged)  # no raise


def test_auth_modes_must_be_a_list():
    merged = {"providers": {"bedrock": _bedrock_block(auth_modes="api_key")}}
    with pytest.raises(ConfigError, match="must be a list"):
        _reject_unsupported_bedrock_auth_modes(merged)


def test_auth_modes_optional_when_omitted():
    """Schema allows the field to be absent; default is api_key v1."""
    merged = {"providers": {"bedrock": _bedrock_block(auth_modes=None)}}
    # Strip the auth_modes key entirely.
    merged["providers"]["bedrock"].pop("auth_modes", None)
    _reject_unsupported_bedrock_auth_modes(merged)  # no raise


# ---------------------------------------------------------------------------
# fallback_to enforcement helper (also exercised via Rule 1/3 above)
# ---------------------------------------------------------------------------


def test_enforce_fallback_to_lists_all_missing():
    bedrock = {
        "models": {
            "us.anthropic.claude-opus-4-7": {"capabilities": ["chat"]},  # missing
            "us.anthropic.claude-sonnet-4-6": {"fallback_to": "anthropic:claude-sonnet-4-6"},
            "us.anthropic.claude-haiku-4-5-20251001-v1:0": {"capabilities": ["chat"]},  # missing
        }
    }
    with pytest.raises(ConfigError, match="us.anthropic.claude-opus-4-7") as exc_info:
        _enforce_prefer_bedrock_fallback_to(bedrock)
    # All missing models named in the error.
    assert "us.anthropic.claude-haiku-4-5-20251001-v1:0" in str(exc_info.value)
    assert "us.anthropic.claude-sonnet-4-6" not in str(exc_info.value)


def test_enforce_fallback_to_silent_when_all_declared():
    bedrock = {
        "models": {
            "us.anthropic.claude-opus-4-7": {"fallback_to": "anthropic:claude-opus-4-7"},
        }
    }
    _enforce_prefer_bedrock_fallback_to(bedrock)  # no raise


# ---------------------------------------------------------------------------
# Edge: bedrock provider absent — defaulting must no-op
# ---------------------------------------------------------------------------


def test_no_bedrock_provider_is_no_op():
    merged = {"providers": {"openai": {"type": "openai"}}}
    _resolve_bedrock_compliance_profile(merged)  # no raise
    _reject_unsupported_bedrock_auth_modes(merged)  # no raise
    assert "bedrock" not in merged["providers"]
