"""Tests for BedrockAdapter (cycle-096 Sprint 1 Task 1.3 / FR-2 + FR-11/12/13).

Coverage targets:

* Successful Converse path (response shape normalization, camelCase→snake_case)
* Error taxonomy classifier — 9 categories per SDD §6.1
* Empty content[] retry semantics (NFR-R4)
* Daily-quota circuit breaker (process-scoped, threading.Event)
* Tool schema wrapping ({json: <schema>})
* Thinking-trace translation (caller `enabled` → Bedrock `adaptive`)
* URL encoding for colon-bearing model IDs
* Region resolution chain (request → env → config → fallback)
* Region-prefix mismatch guard (FR-12)
* Streaming non-support assertion (HIGH-CONSENSUS IMP-007)
* validate_config — including prefer_bedrock + missing fallback_to (SKP-003)
* No boto3 / botocore imports (FR-3 AC)

All tests use mocked `http_post` — no live API calls.
"""

from __future__ import annotations

import sys
import threading
from pathlib import Path
from typing import Any, Dict
from unittest.mock import patch

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from loa_cheval.providers.bedrock_adapter import (  # noqa: E402
    BedrockAdapter,
    EmptyResponseError,
    ModelEndOfLifeError,
    OnDemandNotSupportedError,
    QuotaExceededError,
    RegionMismatchError,
    _DAILY_QUOTA_EXCEEDED,
    _extract_thinking_directive,
    _is_daily_quota_body,
    _transform_messages,
    _transform_tools_to_converse,
)
from loa_cheval.types import (  # noqa: E402
    ChevalError,
    CompletionRequest,
    ConfigError,
    InvalidInputError,
    ModelConfig,
    ProviderConfig,
    ProviderUnavailableError,
    RateLimitError,
)


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


@pytest.fixture(autouse=True)
def _reset_circuit_breaker():
    """Daily-quota circuit breaker is process-scoped; clear before each test."""
    _DAILY_QUOTA_EXCEEDED.clear()
    yield
    _DAILY_QUOTA_EXCEEDED.clear()


def _make_provider_config(
    *,
    region_default: str = "us-east-1",
    auth_modes=None,
    compliance_profile=None,
    models=None,
) -> ProviderConfig:
    return ProviderConfig(
        name="bedrock",
        type="bedrock",
        endpoint="https://bedrock-runtime.{region}.amazonaws.com",
        auth="ABSKR-test-token-not-real",
        models=models or {},
        region_default=region_default,
        auth_modes=auth_modes if auth_modes is not None else ["api_key", "sigv4"],
        compliance_profile=compliance_profile,
    )


def _make_model_config(**overrides) -> ModelConfig:
    defaults: Dict[str, Any] = {
        "capabilities": ["chat"],
        "context_window": 200000,
        "token_param": "max_tokens",
        "api_format": {"chat": "converse"},
        "fallback_to": "anthropic:claude-opus-4-7",
        "fallback_mapping_version": 1,
    }
    defaults.update(overrides)
    return ModelConfig(**defaults)


def _make_request(
    *,
    model: str = "us.anthropic.claude-opus-4-7",
    messages=None,
    metadata=None,
    tools=None,
    tool_choice=None,
    max_tokens: int = 16,
) -> CompletionRequest:
    return CompletionRequest(
        messages=messages or [{"role": "user", "content": "hi"}],
        model=model,
        temperature=0.0,
        max_tokens=max_tokens,
        tools=tools,
        tool_choice=tool_choice,
        metadata=metadata,
    )


def _success_response() -> Dict[str, Any]:
    """Bedrock Converse 200 OK shape (camelCase usage + cache fields)."""
    return {
        "output": {
            "message": {
                "role": "assistant",
                "content": [{"text": "ok"}],
            }
        },
        "stopReason": "end_turn",
        "usage": {
            "inputTokens": 10,
            "outputTokens": 4,
            "totalTokens": 14,
            "cacheReadInputTokens": 0,
            "cacheWriteInputTokens": 0,
        },
        "metrics": {"latencyMs": 123},
    }


# ---------------------------------------------------------------------------
# Successful path (Probe 2 captures)
# ---------------------------------------------------------------------------


def test_complete_returns_normalized_result_for_200_ok():
    config = _make_provider_config(
        models={"us.anthropic.claude-opus-4-7": _make_model_config()}
    )
    adapter = BedrockAdapter(config)

    with patch(
        "loa_cheval.providers.bedrock_adapter.http_post",
        return_value=(200, _success_response()),
    ) as m:
        result = adapter.complete(_make_request())

    assert result.content == "ok"
    assert result.usage.input_tokens == 10
    assert result.usage.output_tokens == 4
    assert result.provider == "bedrock"
    assert result.model == "us.anthropic.claude-opus-4-7"
    # The URL must contain the unencoded model ID (no colons in this Day-1 ID).
    called_url = m.call_args.kwargs["url"]
    assert "us.anthropic.claude-opus-4-7" in called_url
    assert called_url.startswith("https://bedrock-runtime.us-east-1.amazonaws.com/model/")
    # Bearer auth header (NEVER SigV4 in v1).
    assert m.call_args.kwargs["headers"]["Authorization"].startswith("Bearer ")


def test_complete_url_encodes_colon_bearing_model_id():
    """Haiku 4.5 case — `:0` must become `%3A0` in the URL path."""
    haiku_id = "us.anthropic.claude-haiku-4-5-20251001-v1:0"
    config = _make_provider_config(
        models={haiku_id: _make_model_config(fallback_to="anthropic:claude-haiku-4-5-20251001")}
    )
    adapter = BedrockAdapter(config)

    with patch(
        "loa_cheval.providers.bedrock_adapter.http_post",
        return_value=(200, _success_response()),
    ) as m:
        adapter.complete(_make_request(model=haiku_id))

    url = m.call_args.kwargs["url"]
    assert "%3A0" in url
    assert ":0" not in url.split("?")[0]  # raw colon must NOT appear in path


def test_complete_normalizes_camelcase_usage_to_snake_case():
    config = _make_provider_config(models={"us.anthropic.claude-opus-4-7": _make_model_config()})
    adapter = BedrockAdapter(config)

    resp = _success_response()
    resp["usage"]["inputTokens"] = 42
    resp["usage"]["outputTokens"] = 7

    with patch("loa_cheval.providers.bedrock_adapter.http_post", return_value=(200, resp)):
        result = adapter.complete(_make_request())

    assert result.usage.input_tokens == 42
    assert result.usage.output_tokens == 7


# ---------------------------------------------------------------------------
# Error taxonomy classifier (FR-11 / SDD §6.1)
# ---------------------------------------------------------------------------


def test_classifier_400_on_demand_not_supported_raises_typed_error():
    config = _make_provider_config(
        models={"anthropic.claude-opus-4-7": _make_model_config()}
    )
    adapter = BedrockAdapter(config)

    err_body = {
        "message": (
            "Invocation of model ID anthropic.claude-opus-4-7 with on-demand "
            "throughput isn't supported. Retry your request with the ID or "
            "ARN of an inference profile that contains this model."
        )
    }
    with patch("loa_cheval.providers.bedrock_adapter.http_post", return_value=(400, err_body)):
        with pytest.raises(OnDemandNotSupportedError) as exc_info:
            adapter.complete(_make_request(model="anthropic.claude-opus-4-7"))

    msg = str(exc_info.value)
    assert "inference profile" in msg.lower()
    assert "us.anthropic" in msg or "global.anthropic" in msg


def test_classifier_400_invalid_model_identifier_raises_invalid_input():
    config = _make_provider_config(
        models={"us.anthropic.nonexistent": _make_model_config()}
    )
    adapter = BedrockAdapter(config)

    err_body = {"message": "The provided model identifier is invalid."}
    with patch("loa_cheval.providers.bedrock_adapter.http_post", return_value=(400, err_body)):
        with pytest.raises(InvalidInputError) as exc_info:
            adapter.complete(_make_request(model="us.anthropic.nonexistent"))

    assert "invalid" in str(exc_info.value).lower()


def test_classifier_404_end_of_life_raises_model_end_of_life_error():
    config = _make_provider_config(
        models={"us.anthropic.claude-2-old": _make_model_config()}
    )
    adapter = BedrockAdapter(config)

    err_body = {
        "message": (
            "This model version has reached the end of its life. "
            "Please refer to the AWS documentation for more details."
        )
    }
    with patch("loa_cheval.providers.bedrock_adapter.http_post", return_value=(404, err_body)):
        with pytest.raises(ModelEndOfLifeError):
            adapter.complete(_make_request(model="us.anthropic.claude-2-old"))


def test_classifier_400_blank_text_field_raises_invalid_input():
    config = _make_provider_config(models={"us.anthropic.claude-opus-4-7": _make_model_config()})
    adapter = BedrockAdapter(config)

    err_body = {"message": "The text field in the ContentBlock object at messages.0.content.0 is blank."}
    with patch("loa_cheval.providers.bedrock_adapter.http_post", return_value=(400, err_body)):
        with pytest.raises(InvalidInputError):
            adapter.complete(_make_request())


def test_classifier_403_raises_config_error_with_token_remediation():
    config = _make_provider_config(models={"us.anthropic.claude-opus-4-7": _make_model_config()})
    adapter = BedrockAdapter(config)

    err_body = {"message": "AccessDenied: not authorized to invoke this model"}
    with patch("loa_cheval.providers.bedrock_adapter.http_post", return_value=(403, err_body)):
        with pytest.raises(ConfigError) as exc_info:
            adapter.complete(_make_request())

    assert "AWS_BEARER_TOKEN_BEDROCK" in str(exc_info.value)


def test_classifier_429_raises_rate_limit_error():
    config = _make_provider_config(models={"us.anthropic.claude-opus-4-7": _make_model_config()})
    adapter = BedrockAdapter(config)

    err_body = {"message": "ThrottlingException"}
    with patch("loa_cheval.providers.bedrock_adapter.http_post", return_value=(429, err_body)):
        with pytest.raises(RateLimitError):
            adapter.complete(_make_request())


def test_classifier_5xx_raises_provider_unavailable_error():
    config = _make_provider_config(models={"us.anthropic.claude-opus-4-7": _make_model_config()})
    adapter = BedrockAdapter(config)

    err_body = {"message": "ServiceUnavailableException"}
    with patch("loa_cheval.providers.bedrock_adapter.http_post", return_value=(503, err_body)):
        with pytest.raises(ProviderUnavailableError):
            adapter.complete(_make_request())


# ---------------------------------------------------------------------------
# Empty content[] retry semantics (NFR-R4)
# ---------------------------------------------------------------------------


def test_empty_content_first_call_retries_and_succeeds_on_second():
    config = _make_provider_config(models={"us.anthropic.claude-opus-4-7": _make_model_config()})
    adapter = BedrockAdapter(config)

    empty = {
        "output": {"message": {"role": "assistant", "content": []}},
        "stopReason": "end_turn",
        "usage": {"inputTokens": 5, "outputTokens": 0, "totalTokens": 5},
    }
    with patch(
        "loa_cheval.providers.bedrock_adapter.http_post",
        side_effect=[(200, empty), (200, _success_response())],
    ) as m:
        result = adapter.complete(_make_request())

    assert m.call_count == 2
    assert result.content == "ok"


def test_empty_content_two_consecutive_raises_empty_response_error():
    config = _make_provider_config(models={"us.anthropic.claude-opus-4-7": _make_model_config()})
    adapter = BedrockAdapter(config)

    empty = {
        "output": {"message": {"role": "assistant", "content": []}},
        "stopReason": "end_turn",
        "usage": {"inputTokens": 5, "outputTokens": 0, "totalTokens": 5},
    }
    with patch(
        "loa_cheval.providers.bedrock_adapter.http_post",
        side_effect=[(200, empty), (200, empty)],
    ):
        with pytest.raises(EmptyResponseError):
            adapter.complete(_make_request())


# ---------------------------------------------------------------------------
# Daily-quota circuit breaker (SDD §6.6 / FR-11)
# ---------------------------------------------------------------------------


def test_daily_quota_pattern_in_200_body_trips_circuit_breaker():
    config = _make_provider_config(models={"us.anthropic.claude-opus-4-7": _make_model_config()})
    adapter = BedrockAdapter(config)

    quota_body = {"message": "Too many tokens per day for this account"}
    with patch("loa_cheval.providers.bedrock_adapter.http_post", return_value=(200, quota_body)):
        with pytest.raises(QuotaExceededError):
            adapter.complete(_make_request())

    assert _DAILY_QUOTA_EXCEEDED.is_set()


def test_circuit_breaker_fast_fails_subsequent_calls():
    config = _make_provider_config(models={"us.anthropic.claude-opus-4-7": _make_model_config()})
    adapter = BedrockAdapter(config)

    _DAILY_QUOTA_EXCEEDED.set()

    with patch("loa_cheval.providers.bedrock_adapter.http_post") as m:
        with pytest.raises(QuotaExceededError):
            adapter.complete(_make_request())
    assert m.call_count == 0  # fast-fail without any API call


def test_circuit_breaker_uses_threading_event_for_concurrency():
    """SDD §6.6: process-scoped, atomic across threads."""
    assert isinstance(_DAILY_QUOTA_EXCEEDED, threading.Event)


def test_quota_error_default_message_includes_reset_guidance():
    """NC-5 (cycle-097): default error message must point operator at the
    AWS quota reset cadence and the fallback path so the surface is
    actionable, not just a circuit-breaker notice.
    """
    err = QuotaExceededError()
    msg = str(err)
    assert "00:00 UTC" in msg
    assert "restart" in msg.lower()
    assert "fallback" in msg.lower() or "prefer_bedrock" in msg


# ---------------------------------------------------------------------------
# Tool schema wrapping (FR-1 / Sprint 0 G-S0-2 probe #3)
# ---------------------------------------------------------------------------


def test_tools_wrap_schema_with_input_schema_json_envelope():
    cheval_tools = [
        {
            "name": "get_weather",
            "description": "Get weather for a city",
            "parameters": {
                "type": "object",
                "properties": {"city": {"type": "string"}},
                "required": ["city"],
            },
        }
    ]
    converted = _transform_tools_to_converse(cheval_tools, tool_choice=None)
    spec = converted["tools"][0]["toolSpec"]
    assert spec["name"] == "get_weather"
    # Bedrock-specific envelope.
    assert "inputSchema" in spec
    assert "json" in spec["inputSchema"]
    assert spec["inputSchema"]["json"]["properties"]["city"]["type"] == "string"


def test_tools_handle_openai_shape_via_function_key():
    openai_shape = [
        {
            "type": "function",
            "function": {
                "name": "lookup",
                "description": "Lookup",
                "parameters": {"type": "object", "properties": {}},
            },
        }
    ]
    converted = _transform_tools_to_converse(openai_shape, tool_choice=None)
    assert converted["tools"][0]["toolSpec"]["name"] == "lookup"


def test_tool_choice_required_maps_to_any():
    converted = _transform_tools_to_converse(
        [{"name": "x", "description": "", "parameters": {}}],
        tool_choice="required",
    )
    assert "any" in converted["toolChoice"]


# ---------------------------------------------------------------------------
# Thinking-trace translation (FR-13)
# ---------------------------------------------------------------------------


def test_thinking_directive_translates_enabled_to_adaptive():
    """Caller passes direct-Anthropic 'enabled' shape; adapter emits 'adaptive'."""
    req = _make_request(metadata={"thinking": {"type": "enabled", "budget_tokens": 1024}})
    out = _extract_thinking_directive(req)
    assert out["thinking"]["type"] == "adaptive"
    assert "output_config" in out
    assert "effort" in out["output_config"]


def test_thinking_directive_handles_cheval_canonical_enabled_flag():
    req = _make_request(metadata={"thinking": {"enabled": True}})
    out = _extract_thinking_directive(req)
    assert out["thinking"]["type"] == "adaptive"


def test_thinking_directive_returns_none_when_no_metadata():
    req = _make_request(metadata=None)
    assert _extract_thinking_directive(req) is None


def test_thinking_directive_returns_none_when_disabled():
    req = _make_request(metadata={"thinking": {"enabled": False}})
    assert _extract_thinking_directive(req) is None


# ---------------------------------------------------------------------------
# Streaming non-support (HIGH-CONSENSUS IMP-007 / Task 1.B)
# ---------------------------------------------------------------------------


def test_streaming_request_raises_not_implemented_immediately():
    config = _make_provider_config(models={"us.anthropic.claude-opus-4-7": _make_model_config()})
    adapter = BedrockAdapter(config)

    req = _make_request(metadata={"stream": True})
    with patch("loa_cheval.providers.bedrock_adapter.http_post") as m:
        with pytest.raises(NotImplementedError) as exc_info:
            adapter.complete(req)
    assert m.call_count == 0  # fail-fast; no API call attempted
    assert "Streaming not supported" in str(exc_info.value)


# ---------------------------------------------------------------------------
# Region resolution + mismatch guard (FR-12)
# ---------------------------------------------------------------------------


def test_region_resolution_prefers_request_metadata_override():
    config = _make_provider_config(
        region_default="us-east-1",
        models={"us.anthropic.claude-opus-4-7": _make_model_config()},
    )
    adapter = BedrockAdapter(config)
    req = _make_request(metadata={"region": "us-west-2"})

    with patch(
        "loa_cheval.providers.bedrock_adapter.http_post",
        return_value=(200, _success_response()),
    ) as m:
        adapter.complete(req)

    assert "us-west-2" in m.call_args.kwargs["url"]


def test_region_resolution_uses_env_var_when_no_request_override(monkeypatch):
    config = _make_provider_config(
        region_default="us-east-1",
        models={"us.anthropic.claude-opus-4-7": _make_model_config()},
    )
    adapter = BedrockAdapter(config)
    monkeypatch.setenv("AWS_BEDROCK_REGION", "us-east-2")

    with patch(
        "loa_cheval.providers.bedrock_adapter.http_post",
        return_value=(200, _success_response()),
    ) as m:
        adapter.complete(_make_request())

    assert "us-east-2" in m.call_args.kwargs["url"]


def test_region_prefix_mismatch_raises_region_mismatch_error():
    """User configures eu-west-1 but requests a us.* profile → RegionMismatchError."""
    config = _make_provider_config(
        region_default="eu-west-1",
        models={"us.anthropic.claude-opus-4-7": _make_model_config()},
    )
    adapter = BedrockAdapter(config)

    with patch("loa_cheval.providers.bedrock_adapter.http_post") as m:
        with pytest.raises(RegionMismatchError) as exc_info:
            adapter.complete(_make_request())

    assert m.call_count == 0  # caught pre-flight
    assert "us-east-1" in str(exc_info.value) or "us-east-2" in str(exc_info.value)
    assert "AWS_BEDROCK_REGION" in str(exc_info.value)


def test_region_prefix_global_accepts_any_region():
    """global.* profiles work in any region (cross-region inference)."""
    config = _make_provider_config(
        region_default="ap-northeast-1",  # not in us.* set
        models={"global.anthropic.claude-opus-4-7": _make_model_config()},
    )
    adapter = BedrockAdapter(config)

    with patch(
        "loa_cheval.providers.bedrock_adapter.http_post",
        return_value=(200, _success_response()),
    ):
        result = adapter.complete(_make_request(model="global.anthropic.claude-opus-4-7"))
    assert result.content == "ok"


# ---------------------------------------------------------------------------
# validate_config — including SKP-003 prefer_bedrock guard
# ---------------------------------------------------------------------------


def test_validate_config_passes_for_well_formed_config():
    config = _make_provider_config(models={"us.anthropic.claude-opus-4-7": _make_model_config()})
    adapter = BedrockAdapter(config)
    assert adapter.validate_config() == []


def test_validate_config_rejects_missing_endpoint():
    config = _make_provider_config(models={"us.anthropic.claude-opus-4-7": _make_model_config()})
    config.endpoint = ""
    adapter = BedrockAdapter(config)
    errors = adapter.validate_config()
    assert any("endpoint is required" in e for e in errors)


def test_validate_config_rejects_wrong_type():
    config = _make_provider_config(models={"us.anthropic.claude-opus-4-7": _make_model_config()})
    config.type = "not_bedrock"
    adapter = BedrockAdapter(config)
    errors = adapter.validate_config()
    assert any("must be 'bedrock'" in e for e in errors)


def test_validate_config_rejects_prefer_bedrock_with_missing_fallback_to():
    """Flatline BLOCKER SKP-003 — no heuristic name matching."""
    model = _make_model_config(fallback_to=None)
    config = _make_provider_config(
        compliance_profile="prefer_bedrock",
        models={"us.anthropic.claude-opus-4-7": model},
    )
    adapter = BedrockAdapter(config)
    errors = adapter.validate_config()
    assert any("missing fallback_to" in e for e in errors)
    assert any("SKP-003" in e for e in errors)


def test_validate_config_rejects_invalid_compliance_profile_value():
    config = _make_provider_config(
        compliance_profile="not_a_real_value",
        models={"us.anthropic.claude-opus-4-7": _make_model_config()},
    )
    adapter = BedrockAdapter(config)
    errors = adapter.validate_config()
    assert any("compliance_profile" in e for e in errors)


# ---------------------------------------------------------------------------
# Daily-quota body sentinel (helper)
# ---------------------------------------------------------------------------


def test_daily_quota_body_sentinel_matches_too_many_tokens():
    body = {"message": "Too many tokens per day for this account"}
    assert _is_daily_quota_body(body) is True


def test_daily_quota_body_sentinel_matches_via_output_message_text():
    body = {
        "output": {
            "message": {"content": [{"text": "Daily quota exceeded for this model"}]}
        }
    }
    assert _is_daily_quota_body(body) is True


def test_daily_quota_body_sentinel_does_not_false_positive_on_normal_response():
    assert _is_daily_quota_body(_success_response()) is False


# ---------------------------------------------------------------------------
# Message transformation (Converse uses system as separate top-level)
# ---------------------------------------------------------------------------


def test_transform_messages_separates_system_block():
    sys_blocks, msgs = _transform_messages(
        [
            {"role": "system", "content": "be helpful"},
            {"role": "user", "content": "hi"},
        ]
    )
    assert sys_blocks == [{"text": "be helpful"}]
    assert msgs == [{"role": "user", "content": [{"text": "hi"}]}]


def test_transform_messages_handles_string_user_content():
    _, msgs = _transform_messages([{"role": "user", "content": "hello"}])
    assert msgs[0]["content"] == [{"text": "hello"}]


# ---------------------------------------------------------------------------
# Implementation guard: no boto3 / botocore (FR-3 AC)
# ---------------------------------------------------------------------------


def test_adapter_module_does_not_import_boto3():
    """v1 must not pull in boto3/botocore — Bearer-only path.

    Reads the source file directly rather than importlib.reload to avoid
    refreshing the exception class identity (which would cause downstream
    tests' `pytest.raises(OnDemandNotSupportedError)` to fail to match).
    """
    import loa_cheval.providers.bedrock_adapter as mod

    src = Path(mod.__file__).read_text()
    assert "import boto3" not in src
    assert "import botocore" not in src
    assert "from boto3" not in src
    assert "from botocore" not in src


# ---------------------------------------------------------------------------
# Compliance-aware fallback dispatch (NFR-R1, Task 1.5 runtime)
# ---------------------------------------------------------------------------


def _mock_anthropic_complete_success():
    """Helper: create a CompletionResult that AnthropicAdapter.complete would return."""
    from loa_cheval.types import CompletionResult, Usage
    return CompletionResult(
        content="ok-from-anthropic",
        tool_calls=None,
        thinking=None,
        usage=Usage(input_tokens=10, output_tokens=4, reasoning_tokens=0, source="actual"),
        model="claude-opus-4-7",
        latency_ms=200,
        provider="anthropic",
    )


def test_compliance_bedrock_only_re_raises_on_outage(monkeypatch):
    """Default mode: ProviderUnavailableError propagates to caller (fail-closed)."""
    monkeypatch.setenv("ANTHROPIC_API_KEY", "anth-test-key")
    config = _make_provider_config(
        compliance_profile="bedrock_only",
        models={"us.anthropic.claude-opus-4-7": _make_model_config()},
    )
    adapter = BedrockAdapter(config)

    with patch(
        "loa_cheval.providers.bedrock_adapter.http_post",
        return_value=(503, {"message": "ServiceUnavailableException"}),
    ):
        with pytest.raises(ProviderUnavailableError):
            adapter.complete(_make_request())


def test_compliance_prefer_bedrock_falls_back_to_anthropic(monkeypatch, capsys):
    """`prefer_bedrock` mode: Bedrock 503 → AnthropicAdapter.complete is invoked."""
    monkeypatch.setenv("ANTHROPIC_API_KEY", "anth-test-key")
    config = _make_provider_config(
        compliance_profile="prefer_bedrock",
        models={"us.anthropic.claude-opus-4-7": _make_model_config()},
    )
    adapter = BedrockAdapter(config)

    fake_anth_result = _mock_anthropic_complete_success()
    # Make Bedrock fail; mock AnthropicAdapter.complete on the class.
    with patch(
        "loa_cheval.providers.bedrock_adapter.http_post",
        return_value=(503, {"message": "ServiceUnavailableException"}),
    ):
        with patch(
            "loa_cheval.providers.anthropic_adapter.AnthropicAdapter.complete",
            return_value=fake_anth_result,
        ) as anth_mock:
            result = adapter.complete(_make_request())

    # Anthropic adapter was actually called.
    assert anth_mock.call_count == 1
    # Caller-visible result is the Anthropic one.
    assert result.content == "ok-from-anthropic"
    assert result.provider == "anthropic"
    # Result is tagged so caller can see the fallback happened.
    assert result.metadata["fallback"] == "cross_provider"
    assert result.metadata["original_provider"] == "bedrock"
    assert result.metadata["original_error_type"] == "ProviderUnavailableError"
    # Stderr warning was emitted (warned-fallback per NFR-R1).
    captured = capsys.readouterr()
    assert "falling back to direct" in captured.err
    assert "prefer_bedrock" in captured.err


def test_compliance_none_falls_back_silently(monkeypatch, capsys):
    """`none` mode: fallback dispatches but emits NO stderr warning."""
    monkeypatch.setenv("ANTHROPIC_API_KEY", "anth-test-key")
    config = _make_provider_config(
        compliance_profile="none",
        models={"us.anthropic.claude-opus-4-7": _make_model_config()},
    )
    adapter = BedrockAdapter(config)

    fake_anth_result = _mock_anthropic_complete_success()
    with patch(
        "loa_cheval.providers.bedrock_adapter.http_post",
        return_value=(503, {"message": "ServiceUnavailableException"}),
    ):
        with patch(
            "loa_cheval.providers.anthropic_adapter.AnthropicAdapter.complete",
            return_value=fake_anth_result,
        ) as anth_mock:
            result = adapter.complete(_make_request())

    assert anth_mock.call_count == 1
    assert result.provider == "anthropic"
    captured = capsys.readouterr()
    assert "falling back" not in captured.err  # silent


def test_compliance_fallback_skips_for_config_errors(monkeypatch):
    """OnDemandNotSupportedError / RegionMismatchError are config errors —
    NEVER trigger fallback (would mask user error)."""
    monkeypatch.setenv("ANTHROPIC_API_KEY", "anth-test-key")
    config = _make_provider_config(
        compliance_profile="prefer_bedrock",
        models={"anthropic.claude-opus-4-7": _make_model_config()},
    )
    adapter = BedrockAdapter(config)

    err_body = {
        "message": (
            "Invocation of model ID anthropic.claude-opus-4-7 with on-demand "
            "throughput isn't supported."
        )
    }
    with patch(
        "loa_cheval.providers.bedrock_adapter.http_post",
        return_value=(400, err_body),
    ):
        # OnDemandNotSupportedError MUST propagate even though prefer_bedrock is set.
        with pytest.raises(OnDemandNotSupportedError):
            adapter.complete(_make_request(model="anthropic.claude-opus-4-7"))


def test_compliance_fallback_skips_when_fallback_to_missing(monkeypatch):
    """If fallback_to is missing, re-raise the original error rather than guess."""
    monkeypatch.setenv("ANTHROPIC_API_KEY", "anth-test-key")
    config = _make_provider_config(
        compliance_profile="none",  # avoid loader rejecting prefer_bedrock without fallback_to
        models={
            "us.anthropic.claude-opus-4-7": _make_model_config(fallback_to=None),
        },
    )
    adapter = BedrockAdapter(config)

    with patch(
        "loa_cheval.providers.bedrock_adapter.http_post",
        return_value=(503, {"message": "ServiceUnavailableException"}),
    ):
        with pytest.raises(ProviderUnavailableError):
            adapter.complete(_make_request())


def test_compliance_fallback_skips_when_fallback_target_not_anthropic(monkeypatch):
    """v1 only supports anthropic fallback. Non-anthropic targets re-raise."""
    monkeypatch.setenv("ANTHROPIC_API_KEY", "anth-test-key")
    config = _make_provider_config(
        compliance_profile="none",
        models={
            "us.anthropic.claude-opus-4-7": _make_model_config(
                fallback_to="openai:gpt-5.5",  # not anthropic
            ),
        },
    )
    adapter = BedrockAdapter(config)

    with patch(
        "loa_cheval.providers.bedrock_adapter.http_post",
        return_value=(503, {"message": "ServiceUnavailableException"}),
    ):
        with pytest.raises(ProviderUnavailableError):
            adapter.complete(_make_request())


# ---------------------------------------------------------------------------
# Errors are ChevalError subclasses (downstream handlers catch base class)
# ---------------------------------------------------------------------------


@pytest.mark.parametrize(
    "exc_cls",
    [OnDemandNotSupportedError, ModelEndOfLifeError, RegionMismatchError, EmptyResponseError, QuotaExceededError],
)
def test_all_bedrock_errors_subclass_chevalerror(exc_cls):
    """Existing handlers catching ChevalError will catch the new types too."""
    assert issubclass(exc_cls, ChevalError)
