"""Tests for loa_cheval.types.parse_provider_model_id (cycle-096 Sprint 1 Task 1.1).

Closes Flatline v1.1 SKP-006 — single canonical parser shared with the bash
helper at .claude/scripts/lib-provider-parse.sh. Cross-language equivalence
enforced by tests/integration/parser-cross-language.bats.

SDD reference: §5.4 Centralized Parser Contract.
"""

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from loa_cheval.types import InvalidInputError, parse_provider_model_id


# --- Happy path ---


def test_parses_simple_provider_model_id():
    assert parse_provider_model_id("anthropic:claude-opus-4-7") == ("anthropic", "claude-opus-4-7")


def test_parses_bedrock_inference_profile_no_suffix():
    assert parse_provider_model_id("bedrock:us.anthropic.claude-opus-4-7") == (
        "bedrock",
        "us.anthropic.claude-opus-4-7",
    )


def test_parses_bedrock_with_colon_bearing_suffix():
    """Haiku 4.5 case: trailing :0 is part of the model_id, not a separator."""
    assert parse_provider_model_id("bedrock:us.anthropic.claude-haiku-4-5-20251001-v1:0") == (
        "bedrock",
        "us.anthropic.claude-haiku-4-5-20251001-v1:0",
    )


def test_parses_openai_with_dots_and_dashes():
    assert parse_provider_model_id("openai:gpt-5.5-pro") == ("openai", "gpt-5.5-pro")


def test_parses_google_preview_model():
    assert parse_provider_model_id("google:gemini-3.1-pro-preview") == (
        "google",
        "gemini-3.1-pro-preview",
    )


def test_split_on_first_colon_only_preserves_subsequent_colons():
    assert parse_provider_model_id("provider:multi:colon:value") == (
        "provider",
        "multi:colon:value",
    )


# --- Day-1 Bedrock model IDs (from Sprint 0 G-S0-2 probe captures) ---


def test_day1_bedrock_opus_4_7():
    p, m = parse_provider_model_id("bedrock:us.anthropic.claude-opus-4-7")
    assert (p, m) == ("bedrock", "us.anthropic.claude-opus-4-7")


def test_day1_bedrock_sonnet_4_6():
    p, m = parse_provider_model_id("bedrock:us.anthropic.claude-sonnet-4-6")
    assert (p, m) == ("bedrock", "us.anthropic.claude-sonnet-4-6")


def test_day1_bedrock_haiku_4_5_with_v1_zero_suffix():
    p, m = parse_provider_model_id("bedrock:us.anthropic.claude-haiku-4-5-20251001-v1:0")
    assert (p, m) == ("bedrock", "us.anthropic.claude-haiku-4-5-20251001-v1:0")


def test_day1_bedrock_global_namespace():
    """global.* inference profile namespace alongside us.*."""
    p, m = parse_provider_model_id("bedrock:global.anthropic.claude-opus-4-7")
    assert (p, m) == ("bedrock", "global.anthropic.claude-opus-4-7")


# --- Error paths (must raise InvalidInputError per SDD §5.4) ---


def test_empty_input_raises():
    with pytest.raises(InvalidInputError, match="empty input"):
        parse_provider_model_id("")


def test_missing_colon_raises():
    with pytest.raises(InvalidInputError, match="missing colon"):
        parse_provider_model_id("no-colon-at-all")


def test_empty_provider_half_raises():
    with pytest.raises(InvalidInputError, match="empty provider"):
        parse_provider_model_id(":claude-opus-4-7")


def test_empty_model_id_half_raises():
    with pytest.raises(InvalidInputError, match="empty model_id"):
        parse_provider_model_id("anthropic:")


def test_only_colon_raises_for_empty_provider():
    """Edge: ':' alone — provider is empty, model_id is empty; provider check fires first."""
    with pytest.raises(InvalidInputError, match="empty provider"):
        parse_provider_model_id(":")


# --- Type stability ---


def test_returns_tuple_of_two_strings():
    result = parse_provider_model_id("anthropic:claude-opus-4-7")
    assert isinstance(result, tuple)
    assert len(result) == 2
    assert all(isinstance(x, str) for x in result)


def test_idempotent_for_same_input():
    """Calling twice yields equal results (no hidden state)."""
    a = parse_provider_model_id("anthropic:claude-opus-4-7")
    b = parse_provider_model_id("anthropic:claude-opus-4-7")
    assert a == b


# --- InvalidInputError surface ---


def test_invalid_input_error_message_includes_offending_value():
    """Caller debugging needs the bad input echoed (caller-supplied data, safe to surface)."""
    try:
        parse_provider_model_id("no-colon-at-all")
    except InvalidInputError as e:
        assert "no-colon-at-all" in str(e)
    else:
        pytest.fail("InvalidInputError not raised")


def test_invalid_input_error_is_chevalerror_subclass():
    """Existing exception handlers catching ChevalError will catch this too."""
    from loa_cheval.types import ChevalError

    with pytest.raises(ChevalError):
        parse_provider_model_id("")
