"""Tests for provider adapters — golden fixture validation (SDD §4.2.5)."""

import json
import sys
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from loa_cheval.providers.openai_adapter import OpenAIAdapter, _normalize_tool_calls
from loa_cheval.providers.anthropic_adapter import (
    AnthropicAdapter,
    _transform_messages,
    _transform_tools_to_anthropic,
    _transform_tool_choice,
    _serialize_arguments,
)
from loa_cheval.providers.base import estimate_tokens, enforce_context_window
from loa_cheval.types import (
    CompletionRequest,
    CompletionResult,
    ContextTooLargeError,
    InvalidConfigError,
    InvalidInputError,
    ModelConfig,
    ProviderConfig,
    RateLimitError,
    UnsupportedResponseShapeError,
)

FIXTURES = Path(__file__).parent / "fixtures"


def _make_provider_config(name="openai", ptype="openai") -> ProviderConfig:
    return ProviderConfig(
        name=name,
        type=ptype,
        endpoint="https://api.example.com/v1",
        auth="test-key",
        models={
            "gpt-5.2": ModelConfig(
                capabilities=["chat", "tools"],
                context_window=128000,
                pricing={"input_per_mtok": 10000, "output_per_mtok": 30000},
            ),
            "claude-opus-4-6": ModelConfig(
                capabilities=["chat", "tools", "thinking_traces"],
                context_window=200000,
                pricing={"input_per_mtok": 5000, "output_per_mtok": 25000},
            ),
        },
    )


class TestOpenAIResponseParsing:
    """Golden fixture tests for OpenAI response deserialization."""

    def test_basic_response(self):
        fixture = json.loads((FIXTURES / "openai_response.json").read_text())
        adapter = OpenAIAdapter(_make_provider_config())
        result = adapter._parse_response(fixture, latency_ms=100)

        assert result.content == "This is a test response from the OpenAI API."
        assert result.tool_calls is None
        assert result.thinking is None  # OpenAI does not support thinking
        assert result.usage.input_tokens == 50
        assert result.usage.output_tokens == 12
        assert result.usage.source == "actual"
        assert result.model == "gpt-5.2"
        assert result.provider == "openai"

    def test_tool_call_response(self):
        fixture = json.loads((FIXTURES / "openai_tool_call_response.json").read_text())
        adapter = OpenAIAdapter(_make_provider_config())
        result = adapter._parse_response(fixture, latency_ms=200)

        assert result.content == ""  # null content in fixture
        assert result.tool_calls is not None
        assert len(result.tool_calls) == 2

        # Verify canonical format (SDD §4.2.5)
        call = result.tool_calls[0]
        assert call["id"] == "call_abc123"
        assert call["function"]["name"] == "search"
        assert call["function"]["arguments"] == '{"query": "test query"}'
        assert call["type"] == "function"

    def test_empty_choices_raises(self):
        adapter = OpenAIAdapter(_make_provider_config())
        with pytest.raises(InvalidInputError, match="no choices"):
            adapter._parse_response({"choices": []}, latency_ms=0)


class TestAnthropicResponseParsing:
    """Golden fixture tests for Anthropic response deserialization."""

    def test_basic_response(self):
        fixture = json.loads((FIXTURES / "anthropic_response.json").read_text())
        adapter = AnthropicAdapter(_make_provider_config("anthropic", "anthropic"))
        result = adapter._parse_response(fixture, latency_ms=100)

        assert result.content == "This is a test response from the Anthropic API."
        assert result.tool_calls is None
        assert result.thinking is None  # No thinking block in this fixture
        assert result.usage.input_tokens == 50
        assert result.usage.output_tokens == 12
        assert result.model == "claude-opus-4-7"

    def test_thinking_trace_extraction(self):
        fixture = json.loads((FIXTURES / "anthropic_thinking_response.json").read_text())
        adapter = AnthropicAdapter(_make_provider_config("anthropic", "anthropic"))
        result = adapter._parse_response(fixture, latency_ms=150)

        assert result.thinking is not None
        assert "analyze this step by step" in result.thinking
        assert result.content == "After careful analysis, the implementation looks secure."

    def test_tool_use_normalization(self):
        fixture = json.loads((FIXTURES / "anthropic_tool_use_response.json").read_text())
        adapter = AnthropicAdapter(_make_provider_config("anthropic", "anthropic"))
        result = adapter._parse_response(fixture, latency_ms=200)

        assert result.tool_calls is not None
        assert len(result.tool_calls) == 1

        # Verify canonical format (same as OpenAI — SDD §4.2.5)
        call = result.tool_calls[0]
        assert call["id"] == "toolu_abc123"
        assert call["function"]["name"] == "search"
        assert call["type"] == "function"
        # Anthropic tool input is dict, must be serialized to string
        args = json.loads(call["function"]["arguments"])
        assert args["query"] == "test query"


class TestMessageTransformation:
    """Test canonical → Anthropic message format translation."""

    def test_system_extracted(self):
        messages = [
            {"role": "system", "content": "You are a reviewer."},
            {"role": "user", "content": "Review this code."},
        ]
        system, anthropic_msgs = _transform_messages(messages)
        assert system == "You are a reviewer."
        assert len(anthropic_msgs) == 1
        assert anthropic_msgs[0]["role"] == "user"

    def test_multiple_system_messages_concatenated(self):
        messages = [
            {"role": "system", "content": "Part 1"},
            {"role": "system", "content": "Part 2"},
            {"role": "user", "content": "Hello"},
        ]
        system, _ = _transform_messages(messages)
        assert "Part 1" in system
        assert "Part 2" in system

    def test_tool_result_transformed(self):
        messages = [
            {"role": "user", "content": "Search for X"},
            {"role": "tool", "content": "Results: ...", "tool_call_id": "call_abc"},
        ]
        _, anthropic_msgs = _transform_messages(messages)
        assert len(anthropic_msgs) == 2
        tool_msg = anthropic_msgs[1]
        assert tool_msg["role"] == "user"
        assert tool_msg["content"][0]["type"] == "tool_result"


class TestToolTransformation:
    def test_openai_to_anthropic_tools(self):
        tools = [
            {
                "type": "function",
                "function": {
                    "name": "search",
                    "description": "Search for information",
                    "parameters": {"type": "object", "properties": {"query": {"type": "string"}}},
                },
            }
        ]
        result = _transform_tools_to_anthropic(tools)
        assert len(result) == 1
        assert result[0]["name"] == "search"
        assert result[0]["description"] == "Search for information"
        assert "properties" in result[0]["input_schema"]

    def test_tool_choice_auto(self):
        assert _transform_tool_choice("auto") == {"type": "auto"}

    def test_tool_choice_required(self):
        assert _transform_tool_choice("required") == {"type": "any"}

    def test_tool_choice_none(self):
        assert _transform_tool_choice("none") == {"type": "none"}


class TestToolCallNormalization:
    def test_openai_normalization(self):
        raw = [
            {
                "id": "call_123",
                "type": "function",
                "function": {"name": "test", "arguments": '{"x": 1}'},
            }
        ]
        result = _normalize_tool_calls(raw)
        assert result[0]["id"] == "call_123"
        assert result[0]["function"]["name"] == "test"
        assert result[0]["type"] == "function"

    def test_serialize_dict_arguments(self):
        result = _serialize_arguments({"key": "value"})
        assert json.loads(result) == {"key": "value"}

    def test_serialize_string_arguments(self):
        result = _serialize_arguments('{"key": "value"}')
        assert result == '{"key": "value"}'


class TestOpenAIRequestBodyConstruction:
    """Test that token_param from config flows to the wire request body (#346)."""

    def _capture_body(self, token_param="max_completion_tokens"):
        """Build an adapter with given token_param, mock http_post, return captured body."""
        config = ProviderConfig(
            name="openai",
            type="openai",
            endpoint="https://api.example.com/v1",
            auth="test-key",
            models={
                "gpt-5.2": ModelConfig(
                    capabilities=["chat", "tools"],
                    context_window=128000,
                    token_param=token_param,
                    # cycle-095 Sprint 1: endpoint_family required on every
                    # OpenAI entry that can flow through complete().
                    endpoint_family="chat",
                ),
            },
        )
        adapter = OpenAIAdapter(config)
        request = CompletionRequest(
            messages=[{"role": "user", "content": "Hello"}],
            model="gpt-5.2",
            max_tokens=4096,
        )

        # Mock http_post to capture the body without making a real API call
        mock_response = {
            "choices": [{"message": {"content": "ok"}}],
            "usage": {"prompt_tokens": 5, "completion_tokens": 2},
            "model": "gpt-5.2",
        }
        with patch("loa_cheval.providers.openai_adapter.http_post", return_value=(200, mock_response)) as mock:
            adapter.complete(request)
            return mock.call_args[1]["body"]

    def test_gpt52_sends_max_completion_tokens(self):
        body = self._capture_body("max_completion_tokens")
        assert "max_completion_tokens" in body
        assert body["max_completion_tokens"] == 4096
        assert "max_tokens" not in body

    def test_legacy_model_sends_max_tokens(self):
        body = self._capture_body("max_tokens")
        assert "max_tokens" in body
        assert body["max_tokens"] == 4096
        assert "max_completion_tokens" not in body

    def test_default_model_config_sends_max_tokens(self):
        """ModelConfig() without explicit token_param defaults to max_tokens."""
        config = ProviderConfig(
            name="openai",
            type="openai",
            endpoint="https://api.example.com/v1",
            auth="test-key",
            # cycle-095 Sprint 1: endpoint_family required on every OpenAI entry.
            models={"gpt-legacy": ModelConfig(endpoint_family="chat")},
        )
        adapter = OpenAIAdapter(config)
        request = CompletionRequest(
            messages=[{"role": "user", "content": "Hello"}],
            model="gpt-legacy",
            max_tokens=2048,
        )
        mock_response = {
            "choices": [{"message": {"content": "ok"}}],
            "usage": {"prompt_tokens": 5, "completion_tokens": 2},
            "model": "gpt-legacy",
        }
        with patch("loa_cheval.providers.openai_adapter.http_post", return_value=(200, mock_response)) as mock:
            adapter.complete(request)
            body = mock.call_args[1]["body"]
        assert "max_tokens" in body
        assert body["max_tokens"] == 2048


class TestAnthropicRequestBodyConstruction:
    """Issue #641 (A): Opus 4 rejects requests with `temperature` (HTTP 400, 'temperature
    is deprecated for this model'). Adapter must gate the temperature serialization on a
    new `model_config.params.temperature_supported` flag (default True for back-compat
    with Claude 3 / 3.5 / pre-4 Opus models)."""

    def _capture_body(self, params=None, model_id="claude-opus-4-7"):
        """Build an Anthropic adapter, mock http_post, return the captured request body.

        params: dict passed to ModelConfig.params, or None to test the default-back-compat path.
        """
        config = ProviderConfig(
            name="anthropic",
            type="anthropic",
            endpoint="https://api.example.com/v1",
            auth="test-key",
            models={
                model_id: ModelConfig(
                    capabilities=["chat", "tools"],
                    context_window=200000,
                    token_param="max_tokens",
                    params=params,
                ),
            },
        )
        adapter = AnthropicAdapter(config)
        request = CompletionRequest(
            messages=[{"role": "user", "content": "Hello"}],
            model=model_id,
            max_tokens=4096,
            temperature=0.7,
        )
        mock_response = {
            "id": "msg_test",
            "type": "message",
            "role": "assistant",
            "model": model_id,
            "content": [{"type": "text", "text": "ok"}],
            "stop_reason": "end_turn",
            "usage": {"input_tokens": 5, "output_tokens": 2},
        }
        with patch("loa_cheval.providers.anthropic_adapter.http_post", return_value=(200, mock_response)) as mock:
            adapter.complete(request)
            return mock.call_args[1]["body"]

    def test_temperature_omitted_when_unsupported(self):
        """Opus 4 family: params.temperature_supported=False → no temperature in body."""
        body = self._capture_body(params={"temperature_supported": False})
        assert "temperature" not in body, (
            "Anthropic body must NOT include 'temperature' when "
            "model_config.params.temperature_supported is False (Opus 4 deprecation)"
        )

    def test_temperature_included_when_supported(self):
        """Older Anthropic models: params.temperature_supported=True → temperature in body."""
        body = self._capture_body(params={"temperature_supported": True})
        assert "temperature" in body
        assert body["temperature"] == 0.7

    def test_temperature_default_is_supported_for_back_compat(self):
        """params=None: default behavior keeps temperature in body — protects Claude 3 / 3.5."""
        body = self._capture_body(params=None)
        assert "temperature" in body, (
            "Default ModelConfig (params=None) must keep temperature in body — "
            "back-compat invariant for older Anthropic models"
        )
        assert body["temperature"] == 0.7

    def test_temperature_safe_when_params_is_malformed(self):
        """Adversarial-finding fix: dataclass type hints aren't enforced at runtime,
        so YAML like `params: "false"` or `params: [x]` constructs ModelConfig but
        would raise AttributeError on `.get()`. Adapter must guard with isinstance
        and gracefully degrade to the back-compat default (include temperature),
        not crash the request."""
        # Non-dict truthy value — pre-fix would raise AttributeError
        body = self._capture_body(params="some-malformed-string")
        assert "temperature" in body, (
            "Malformed params (non-dict) must gracefully default to "
            "temperature_supported=True — not crash with AttributeError"
        )
        # List value — same hazard class
        body = self._capture_body(params=["temperature_supported"])
        assert "temperature" in body


class TestContextWindowEnforcement:
    def test_within_limits(self):
        request = CompletionRequest(
            messages=[{"role": "user", "content": "Hello"}],
            model="gpt-5.2",
            max_tokens=4096,
        )
        model_config = ModelConfig(context_window=128000)
        # Should not raise
        result = enforce_context_window(request, model_config)
        assert result is request

    def test_exceeds_limits(self):
        # Create a message that exceeds the available window
        long_text = "x" * 500000  # ~142K tokens at 3.5 chars/token
        request = CompletionRequest(
            messages=[{"role": "user", "content": long_text}],
            model="gpt-5.2",
            max_tokens=4096,
        )
        model_config = ModelConfig(context_window=128000)
        with pytest.raises(ContextTooLargeError):
            enforce_context_window(request, model_config)


class TestTokenEstimation:
    def test_heuristic_estimation(self):
        tokens = estimate_tokens([{"role": "user", "content": "Hello world, this is a test."}])
        # ~27 chars / 3.5 ≈ 7-8 tokens
        assert 5 <= tokens <= 15

    def test_empty_messages(self):
        tokens = estimate_tokens([])
        assert tokens == 0

    def test_content_blocks(self):
        tokens = estimate_tokens([
            {"role": "user", "content": [{"text": "Block one"}, {"text": "Block two"}]},
        ])
        assert tokens > 0


class TestAdapterValidation:
    def test_openai_valid_config(self):
        adapter = OpenAIAdapter(_make_provider_config())
        errors = adapter.validate_config()
        assert errors == []

    def test_openai_missing_endpoint(self):
        config = _make_provider_config()
        config.endpoint = ""
        adapter = OpenAIAdapter(config)
        errors = adapter.validate_config()
        assert any("endpoint" in e for e in errors)

    def test_anthropic_valid_config(self):
        config = _make_provider_config("anthropic", "anthropic")
        adapter = AnthropicAdapter(config)
        errors = adapter.validate_config()
        assert errors == []

    def test_anthropic_wrong_type(self):
        config = _make_provider_config("anthropic", "openai")
        adapter = AnthropicAdapter(config)
        errors = adapter.validate_config()
        assert any("type" in e for e in errors)


# ─────────────────────────────────────────────────────────────────────────────
# cycle-095 Sprint 1 — Routing infrastructure + response normalization
# ─────────────────────────────────────────────────────────────────────────────

OPENAI_FIXTURES = FIXTURES / "openai"


def _make_openai_provider_with_families() -> ProviderConfig:
    """ProviderConfig mirroring the cycle-095 .claude/defaults/model-config.yaml
    OpenAI block — every entry carries explicit endpoint_family.
    """
    return ProviderConfig(
        name="openai",
        type="openai",
        endpoint="https://api.example.com/v1",
        auth="test-key",
        models={
            "gpt-5.2": ModelConfig(
                capabilities=["chat", "tools"],
                context_window=128000,
                token_param="max_completion_tokens",
                endpoint_family="chat",
                pricing={"input_per_mtok": 10000000, "output_per_mtok": 30000000},
            ),
            "gpt-5.3-codex": ModelConfig(
                capabilities=["chat", "tools", "code"],
                context_window=400000,
                token_param="max_completion_tokens",
                endpoint_family="responses",
                pricing={"input_per_mtok": 1750000, "output_per_mtok": 14000000},
            ),
            "gpt-5.5": ModelConfig(
                capabilities=["chat", "tools", "code"],
                context_window=400000,
                token_param="max_completion_tokens",
                endpoint_family="responses",
                pricing={"input_per_mtok": 5000000, "output_per_mtok": 30000000},
            ),
            "gpt-5.5-pro": ModelConfig(
                capabilities=["chat", "tools", "code"],
                context_window=400000,
                token_param="max_completion_tokens",
                endpoint_family="responses",
                pricing={"input_per_mtok": 30000000, "output_per_mtok": 180000000},
            ),
            "gpt-broken-no-family": ModelConfig(
                # Deliberately missing endpoint_family — used to assert the
                # adapter-runtime defense-in-depth raise.
                capabilities=["chat"],
                context_window=128000,
            ),
            "gpt-broken-bad-family": ModelConfig(
                capabilities=["chat"],
                context_window=128000,
                endpoint_family="bogus",
            ),
        },
    )


class TestOpenAIResponsesEndpointRouting:
    """SDD §7.3 Sprint 1 — TestOpenAIResponsesEndpointRouting (cases a-f).

    These are unit tests of complete()'s URL routing decision.  They mock
    http_post so no network call fires.  The assertion is on which URL the
    adapter chose — proving cycle-095's metadata-driven routing.
    """

    def _request(self, model: str) -> CompletionRequest:
        return CompletionRequest(
            messages=[{"role": "user", "content": "hello"}],
            model=model,
            temperature=0.0,
            max_tokens=64,
        )

    def _capturing_http_post(self, fixture_name: str):
        """Return (mock_fn, captured_calls). The mock returns a fixture body."""
        captured = []
        body = json.loads((OPENAI_FIXTURES / fixture_name).read_text())

        def fake_http_post(url, headers, body, **_kwargs):
            captured.append({"url": url, "body": body})
            return 200, json.loads((OPENAI_FIXTURES / fixture_name).read_text())

        # Need to also patch where it's bound inside the adapter module.
        return fake_http_post, captured

    def test_a_gpt55_routes_to_responses_endpoint(self):
        adapter = OpenAIAdapter(_make_openai_provider_with_families())
        fake, captured = self._capturing_http_post("responses_multiblock_text.json")
        with patch("loa_cheval.providers.openai_adapter.http_post", side_effect=fake):
            adapter.complete(self._request("gpt-5.5"))
        assert captured, "http_post was not called"
        assert captured[0]["url"].endswith("/responses")
        # Body must use the /v1/responses shape — 'input' key, not 'messages'.
        assert "input" in captured[0]["body"]
        assert "messages" not in captured[0]["body"]
        assert captured[0]["body"]["max_output_tokens"] == 64

    def test_b_gpt53_codex_still_routes_to_responses(self):
        adapter = OpenAIAdapter(_make_openai_provider_with_families())
        fake, captured = self._capturing_http_post("responses_multiblock_text.json")
        with patch("loa_cheval.providers.openai_adapter.http_post", side_effect=fake):
            adapter.complete(self._request("gpt-5.3-codex"))
        assert captured[0]["url"].endswith("/responses")

    def test_c_gpt52_routes_to_chat_completions(self):
        adapter = OpenAIAdapter(_make_openai_provider_with_families())
        # Fixture for chat completions reuses existing openai_response.json
        body = json.loads((FIXTURES / "openai_response.json").read_text())
        captured = []

        def fake(url, headers, body, **_kwargs):
            captured.append({"url": url, "body": body})
            return 200, json.loads((FIXTURES / "openai_response.json").read_text())

        with patch("loa_cheval.providers.openai_adapter.http_post", side_effect=fake):
            adapter.complete(self._request("gpt-5.2"))
        assert captured[0]["url"].endswith("/chat/completions")
        assert "messages" in captured[0]["body"]

    def test_d_missing_endpoint_family_raises(self):
        adapter = OpenAIAdapter(_make_openai_provider_with_families())
        with pytest.raises(InvalidConfigError, match="endpoint_family"):
            adapter.complete(self._request("gpt-broken-no-family"))

    def test_e_unknown_endpoint_family_raises(self):
        adapter = OpenAIAdapter(_make_openai_provider_with_families())
        with pytest.raises(InvalidConfigError, match="invalid endpoint_family"):
            adapter.complete(self._request("gpt-broken-bad-family"))

    def test_f_legacy_aliases_kill_switch_does_not_force_endpoint(self):
        """Regression: LOA_FORCE_LEGACY_ALIASES restores ALIAS targets only.

        Each restored alias still routes per its OWN model entry's
        endpoint_family.  E.g., when the kill-switch makes `reviewer` resolve
        to gpt-5.3-codex, the adapter still calls /v1/responses (gpt-5.3-codex's
        own family), NOT /v1/chat/completions.  This test proves there is NO
        endpoint-force layer — only an alias-substitution layer.
        """
        adapter = OpenAIAdapter(_make_openai_provider_with_families())
        body = json.loads((OPENAI_FIXTURES / "responses_multiblock_text.json").read_text())
        captured = []

        def fake(url, headers, body, **_kwargs):
            captured.append({"url": url})
            return 200, json.loads(
                (OPENAI_FIXTURES / "responses_multiblock_text.json").read_text()
            )

        # The alias resolution happens in the loader/resolver, not the adapter.
        # We simulate the kill-switch result here — `reviewer` resolved to
        # gpt-5.3-codex — and assert routing uses gpt-5.3-codex's metadata.
        with patch("loa_cheval.providers.openai_adapter.http_post", side_effect=fake):
            adapter.complete(self._request("gpt-5.3-codex"))
        assert captured[0]["url"].endswith("/responses")


class TestOpenAIResponsesNormalization:
    """SDD §7.3 Sprint 1 — one assertion per §5.4 shape (7 fixtures)."""

    def _adapter(self) -> OpenAIAdapter:
        return OpenAIAdapter(_make_openai_provider_with_families())

    def test_shape1_multiblock_text(self):
        fixture = json.loads((OPENAI_FIXTURES / "responses_multiblock_text.json").read_text())
        result = self._adapter()._parse_responses_response(fixture, latency_ms=10)
        # \n\n join across two output_text parts
        assert result.content == "First paragraph of the response.\n\nSecond paragraph follows."
        assert result.tool_calls is None
        assert result.thinking is None
        assert result.metadata.get("refused") is not True
        assert result.usage.output_tokens == 24
        assert result.usage.reasoning_tokens == 0

    def test_shape2_tool_call_normalization(self):
        fixture = json.loads((OPENAI_FIXTURES / "responses_tool_call.json").read_text())
        result = self._adapter()._parse_responses_response(fixture, latency_ms=10)
        assert result.content == ""
        assert result.tool_calls is not None and len(result.tool_calls) == 1
        tc = result.tool_calls[0]
        # call_id from /v1/responses maps to canonical id field.
        assert tc["id"] == "call_abc123"
        assert tc["type"] == "function"
        assert tc["function"]["name"] == "search"
        # Arguments preserved as the source-string JSON (not eagerly parsed).
        assert "loa cycle-095" in tc["function"]["arguments"]

    def test_shape3_reasoning_summary_extracted_into_thinking(self):
        fixture = json.loads(
            (OPENAI_FIXTURES / "responses_reasoning_summary.json").read_text()
        )
        result = self._adapter()._parse_responses_response(fixture, latency_ms=10)
        assert result.content == "The answer is forty-two."
        assert result.thinking is not None
        assert "Analyzed the question" in result.thinking
        # reasoning_tokens > 0 but billing only on output_tokens (SDD §5.5)
        assert result.usage.reasoning_tokens == 250
        assert result.usage.output_tokens == 264

    def test_shape4_refusal_sets_metadata_flag(self):
        fixture = json.loads((OPENAI_FIXTURES / "responses_refusal.json").read_text())
        result = self._adapter()._parse_responses_response(fixture, latency_ms=10)
        assert result.metadata.get("refused") is True
        assert "can't help" in result.content

    def test_shape5_empty_output_warns_does_not_raise(self, caplog):
        fixture = json.loads((OPENAI_FIXTURES / "responses_empty.json").read_text())
        with caplog.at_level("WARNING", logger="loa_cheval.providers.openai"):
            result = self._adapter()._parse_responses_response(fixture, latency_ms=10)
        assert result.content == ""
        assert result.tool_calls is None
        assert any("empty output" in rec.message for rec in caplog.records)

    def test_shape6_truncated_sets_metadata_flag(self):
        fixture = json.loads((OPENAI_FIXTURES / "responses_truncated.json").read_text())
        result = self._adapter()._parse_responses_response(fixture, latency_ms=10)
        assert result.metadata.get("truncated") is True
        assert result.metadata.get("truncation_reason") == "max_output_tokens"
        assert result.content.startswith("This response was truncated")

    def test_pro_fixture_reasoning_tokens_carried(self):
        """The load-bearing pro fixture: reasoning_tokens populated on Usage."""
        fixture = json.loads(
            (OPENAI_FIXTURES / "responses_pro_reasoning_tokens.json").read_text()
        )
        result = self._adapter()._parse_responses_response(fixture, latency_ms=10)
        assert result.usage.reasoning_tokens == 1800
        assert result.usage.output_tokens == 2400  # INCLUSIVE of reasoning
        assert result.content == "QED."
        # reasoning summary surfaced as thinking trace
        assert result.thinking and "step by step" in result.thinking


class TestUnsupportedResponseShape:
    """SDD §7.3 Sprint 1 — TestUnsupportedResponseShape: forward-compat fail-loud."""

    def _adapter(self) -> OpenAIAdapter:
        return OpenAIAdapter(_make_openai_provider_with_families())

    def _unknown_fixture(self) -> dict:
        return {
            "id": "resp_unknown_001",
            "object": "response",
            "model": "gpt-5.5",
            "status": "completed",
            "output": [
                {"type": "audio_segment", "data": "base64-XXXX"}  # not in §5.4 matrix
            ],
            "usage": {
                "input_tokens": 5,
                "output_tokens": 10,
                "output_tokens_details": {"reasoning_tokens": 0},
            },
        }

    def test_strict_default_raises(self, monkeypatch):
        monkeypatch.delenv("LOA_RESPONSES_UNKNOWN_SHAPE_POLICY", raising=False)
        # Reset the warned-set so prior tests don't leak.
        OpenAIAdapter._unknown_shape_warned.clear()
        with pytest.raises(UnsupportedResponseShapeError, match="audio_segment"):
            self._adapter()._parse_responses_response(self._unknown_fixture(), latency_ms=10)

    def test_degrade_policy_skips_unknown_block_and_warns_once(self, monkeypatch, caplog):
        monkeypatch.setenv("LOA_RESPONSES_UNKNOWN_SHAPE_POLICY", "degrade")
        OpenAIAdapter._unknown_shape_warned.clear()
        adapter = self._adapter()
        # Add a sibling text block so the result has *some* content.
        fixture = self._unknown_fixture()
        fixture["output"].append({
            "type": "message",
            "id": "m1",
            "role": "assistant",
            "content": [{"type": "output_text", "text": "fallback text", "annotations": []}],
        })
        with caplog.at_level("WARNING", logger="loa_cheval.providers.openai"):
            result = adapter._parse_responses_response(fixture, latency_ms=10)
        assert result.content == "fallback text"
        assert result.metadata["unknown_shapes_present"] is True
        assert "audio_segment" in result.metadata["unknown_shapes"]
        warned = [r for r in caplog.records if "audio_segment" in r.message]
        assert len(warned) == 1


class TestForceLegacyAliasesRouting:
    """SDD §7.3 Sprint 1 — TestForceLegacyAliases case f.

    The kill-switch substitutes alias targets at config-load time; routing
    happens later per the substituted target's own endpoint_family.  This
    test asserts that gpt-5.3-codex (the legacy reviewer target) routes to
    /v1/responses post-substitution, NOT /v1/chat/completions.
    """

    def test_legacy_target_routes_per_own_metadata(self):
        adapter = OpenAIAdapter(_make_openai_provider_with_families())
        captured = []

        def fake(url, headers, body, **_kwargs):
            captured.append(url)
            return 200, json.loads(
                (OPENAI_FIXTURES / "responses_multiblock_text.json").read_text()
            )

        request = CompletionRequest(
            messages=[{"role": "user", "content": "x"}],
            model="gpt-5.3-codex",
            max_tokens=32,
        )
        with patch("loa_cheval.providers.openai_adapter.http_post", side_effect=fake):
            adapter.complete(request)
        assert captured[0].endswith("/responses")


# ─────────────────────────────────────────────────────────────────────────────
# cycle-095 Sprint 2 — Google fallback chain (SDD §3.5, §5.8)
# ─────────────────────────────────────────────────────────────────────────────


def _make_google_provider_with_chain() -> ProviderConfig:
    """ProviderConfig with gemini-3-flash-preview → fallback → gemini-2.5-flash."""
    return ProviderConfig(
        name="google",
        type="google",
        endpoint="https://generativelanguage.googleapis.com/v1beta",
        auth="test-key",
        models={
            "gemini-3-flash-preview": ModelConfig(
                capabilities=["chat"],
                context_window=1048576,
                fallback_chain=["google:gemini-2.5-flash"],
                pricing={"input_per_mtok": 150000, "output_per_mtok": 600000},
            ),
            "gemini-2.5-flash": ModelConfig(
                capabilities=["chat"],
                context_window=1048576,
                pricing={"input_per_mtok": 150000, "output_per_mtok": 600000},
            ),
        },
    )


class TestFallbackChain:
    """SDD §5.8 — probe-driven demotion + cooldown hysteresis."""

    def _make_request(self, model: str = "gemini-3-flash-preview") -> CompletionRequest:
        return CompletionRequest(
            messages=[{"role": "user", "content": "ping"}],
            model=model,
            max_tokens=16,
        )

    def test_primary_available_returns_primary(self, monkeypatch):
        from loa_cheval.providers.google_adapter import GoogleAdapter
        adapter = GoogleAdapter(_make_google_provider_with_chain())
        # Mock _is_available to always return True (primary AVAILABLE).
        monkeypatch.setattr(adapter, "_is_available", lambda *a: True)
        active = adapter._resolve_active_model(
            self._make_request(), adapter._get_model_config("gemini-3-flash-preview")
        )
        assert active == "gemini-3-flash-preview"

    def test_primary_unavailable_falls_back_and_warns_once(self, monkeypatch, caplog):
        from loa_cheval.providers.google_adapter import GoogleAdapter
        adapter = GoogleAdapter(_make_google_provider_with_chain())

        def _avail(provider, model_id):
            # Primary UNAVAILABLE; fallback AVAILABLE.
            return model_id != "gemini-3-flash-preview"

        monkeypatch.setattr(adapter, "_is_available", _avail)
        with caplog.at_level("WARNING", logger="loa_cheval.providers.google"):
            active = adapter._resolve_active_model(
                self._make_request(),
                adapter._get_model_config("gemini-3-flash-preview"),
            )
        assert active == "gemini-2.5-flash"
        warns = [r for r in caplog.records if "Demoting" in r.message]
        assert len(warns) == 1

        # Second call — same demotion, no second WARN.
        caplog.clear()
        with caplog.at_level("WARNING", logger="loa_cheval.providers.google"):
            adapter._resolve_active_model(
                self._make_request(),
                adapter._get_model_config("gemini-3-flash-preview"),
            )
        warns_2 = [r for r in caplog.records if "Demoting" in r.message]
        assert len(warns_2) == 0

    def test_recovery_after_cooldown_promotes_back(self, monkeypatch):
        import time as _time
        from loa_cheval.providers.google_adapter import GoogleAdapter
        adapter = GoogleAdapter(_make_google_provider_with_chain())

        # Stage 1: primary UNAVAILABLE → demote.
        avail_state = {"primary_available": False}

        def _avail(provider, model_id):
            if model_id == "gemini-3-flash-preview":
                return avail_state["primary_available"]
            return True

        monkeypatch.setattr(adapter, "_is_available", _avail)
        adapter._cooldown_seconds = 0.01  # tiny cooldown for test
        active1 = adapter._resolve_active_model(
            self._make_request(),
            adapter._get_model_config("gemini-3-flash-preview"),
        )
        assert active1 == "gemini-2.5-flash"

        # Stage 2: primary AVAILABLE again, but still inside cooldown.
        avail_state["primary_available"] = True
        adapter._cooldown_seconds = 999  # high cooldown — stay demoted
        active2 = adapter._resolve_active_model(
            self._make_request(),
            adapter._get_model_config("gemini-3-flash-preview"),
        )
        assert active2 == "gemini-2.5-flash"

        # Stage 3: cooldown expired → promote back.
        adapter._cooldown_seconds = 0.0
        # Wait one tick of monotonic time to ensure (now - unavailable_since) > 0
        _time.sleep(0.01)
        active3 = adapter._resolve_active_model(
            self._make_request(),
            adapter._get_model_config("gemini-3-flash-preview"),
        )
        assert active3 == "gemini-3-flash-preview"

    def test_all_unavailable_raises_provider_unavailable(self, monkeypatch):
        from loa_cheval.providers.google_adapter import GoogleAdapter
        from loa_cheval.types import ProviderUnavailableError
        adapter = GoogleAdapter(_make_google_provider_with_chain())
        monkeypatch.setattr(adapter, "_is_available", lambda *a: False)
        with pytest.raises(ProviderUnavailableError, match="all fallback chain UNAVAILABLE"):
            adapter._resolve_active_model(
                self._make_request(),
                adapter._get_model_config("gemini-3-flash-preview"),
            )


class TestProbeCacheTrustBoundary:
    """SDD §3.5 SKP-003: probe cache trust check (file owner UID + mode 0600)."""

    def test_loose_mode_treated_as_unknown(self, tmp_path, monkeypatch, caplog):
        from loa_cheval.providers.google_adapter import GoogleAdapter
        import os as _os, json as _json_mod, stat as _stat
        adapter = GoogleAdapter(_make_google_provider_with_chain())

        cache = tmp_path / "model-health-cache.json"
        cache.write_text(_json_mod.dumps({"models": {"google:gemini-3-flash-preview": "UNAVAILABLE"}}))
        # Loose mode (group-readable) → trust check fails → UNKNOWN → AVAILABLE.
        _os.chmod(str(cache), 0o644)

        # Patch the hardcoded path so our adapter looks at our temp cache.
        original_is_available = adapter._is_available

        def _patched_is_available(provider, model_id):
            # Manually replicate the probe path with our temp cache.
            if not adapter._probe_cache_trust_check(str(cache)):
                return True  # Trust fail → UNKNOWN → assume AVAILABLE
            return original_is_available(provider, model_id)

        with caplog.at_level("ERROR", logger="loa_cheval.providers.google"):
            ok = _patched_is_available("google", "gemini-3-flash-preview")
        assert ok is True
        # Trust-check error log surfaced
        errs = [r for r in caplog.records if "loose mode" in r.message]
        assert errs

    def test_strict_mode_passes_trust_check(self, tmp_path):
        from loa_cheval.providers.google_adapter import GoogleAdapter
        import os as _os
        adapter = GoogleAdapter(_make_google_provider_with_chain())
        cache = tmp_path / "model-health-cache.json"
        cache.write_text("{}")
        _os.chmod(str(cache), 0o600)
        assert adapter._probe_cache_trust_check(str(cache)) is True


# ─────────────────────────────────────────────────────────────────────────────
# cycle-095 Sprint 2 — tier_groups schema + cost cap (FR-5a)
# ─────────────────────────────────────────────────────────────────────────────


class TestTierGroupsCostCap:
    """SDD §1.4.4 — pre-call session cap raises CostBudgetExceeded BEFORE API call."""

    def test_under_cap_passes(self, tmp_path):
        from loa_cheval.metering.budget import check_session_cap_pre

        ledger = tmp_path / "ledger.jsonl"
        # Empty ledger — no spend yet.
        check_session_cap_pre(
            trace_id="tr-1",
            ledger_path=str(ledger),
            cap_micro=100_000_000,    # $100 cap
            request_estimate_micro=10_000_000,  # $10 estimate
        )

    def test_over_cap_raises_pre_call(self, tmp_path):
        from loa_cheval.metering.budget import check_session_cap_pre
        from loa_cheval.types import CostBudgetExceeded

        ledger = tmp_path / "ledger.jsonl"
        # Pre-load a $90 spend on tr-1.
        ledger.write_text(
            json.dumps({"trace_id": "tr-1", "cost_micro_usd": 90_000_000}) + "\n"
        )
        # $90 + $20 estimate would exceed $100 cap.
        with pytest.raises(CostBudgetExceeded, match="BUDGET_EXCEEDED"):
            check_session_cap_pre(
                trace_id="tr-1",
                ledger_path=str(ledger),
                cap_micro=100_000_000,
                request_estimate_micro=20_000_000,
            )

    def test_null_cap_no_enforcement(self, tmp_path):
        from loa_cheval.metering.budget import check_session_cap_pre
        ledger = tmp_path / "ledger.jsonl"
        ledger.write_text(json.dumps({"trace_id": "tr-1", "cost_micro_usd": 999_999_000_000}) + "\n")
        # cap_micro=None → no enforcement
        check_session_cap_pre("tr-1", str(ledger), None, 100_000_000)

    def test_other_trace_id_does_not_count(self, tmp_path):
        from loa_cheval.metering.budget import check_session_cap_pre, _reset_session_reservations_for_tests
        _reset_session_reservations_for_tests()
        ledger = tmp_path / "ledger.jsonl"
        # Pre-load a $90 spend on a DIFFERENT trace_id.
        ledger.write_text(json.dumps({"trace_id": "tr-other", "cost_micro_usd": 90_000_000}) + "\n")
        # Per-trace_id session cap — tr-1 has $0 spend, $20 estimate fits in $100.
        check_session_cap_pre("tr-1", str(ledger), 100_000_000, 20_000_000)

    def test_reservation_blocks_concurrent_pre_call(self, tmp_path):
        """Adversarial review DISS-001 (Sprint 2): two parallel pre_call
        invocations must NOT both pass when their combined estimate would
        exceed the cap. The in-process reservation tracker prevents this race.
        """
        from loa_cheval.metering.budget import (
            check_session_cap_pre,
            release_session_reservation,
            _reset_session_reservations_for_tests,
        )
        from loa_cheval.types import CostBudgetExceeded

        _reset_session_reservations_for_tests()
        ledger = tmp_path / "ledger.jsonl"
        # Cap = $100. Two requests at $60 each. Sequentially-modeled.
        # Request A: passes, reserves $60.
        check_session_cap_pre("tr-race", str(ledger), 100_000_000, 60_000_000)
        # Request B: would push total to $120 (0 ledger + 60 pending + 60 estimate);
        # MUST raise even though ledger shows $0 spent.
        with pytest.raises(CostBudgetExceeded):
            check_session_cap_pre("tr-race", str(ledger), 100_000_000, 60_000_000)
        # Release request A's reservation.
        release_session_reservation("tr-race", 60_000_000)
        # Now a fresh $60 request fits.
        check_session_cap_pre("tr-race", str(ledger), 100_000_000, 60_000_000)
        release_session_reservation("tr-race", 60_000_000)

    def test_release_idempotent_when_no_reservation(self, tmp_path):
        """release_session_reservation must be safe to call without prior pre_call."""
        from loa_cheval.metering.budget import release_session_reservation, _reset_session_reservations_for_tests
        _reset_session_reservations_for_tests()
        # Should not raise.
        release_session_reservation("never-reserved", 1000)
        release_session_reservation("never-reserved", -1)
        release_session_reservation("never-reserved", 0)


class TestPreferProDryrun:
    """SDD §5.9 — dryrun_preview surfaces what apply_tier_groups WOULD do."""

    def test_flag_off_emits_off_preview(self):
        from loa_cheval.routing.tier_groups import dryrun_preview
        config = {"hounfour": {"prefer_pro_models": False}, "tier_groups": {"mappings": {"reviewer": "gpt-5.5-pro"}}}
        lines = dryrun_preview(config)
        assert any("off" in line for line in lines)

    def test_flag_on_empty_mappings(self):
        from loa_cheval.routing.tier_groups import dryrun_preview
        config = {"hounfour": {"prefer_pro_models": True}, "tier_groups": {"mappings": {}}}
        lines = dryrun_preview(config)
        assert any("empty" in line.lower() or "no remaps" in line for line in lines)

    def test_flag_on_with_mappings(self):
        from loa_cheval.routing.tier_groups import dryrun_preview
        config = {
            "hounfour": {"prefer_pro_models": True},
            "tier_groups": {"mappings": {"reviewer": "openai:gpt-5.5-pro"}},
            "aliases": {"reviewer": "openai:gpt-5.5"},
        }
        lines = dryrun_preview(config)
        # Should show reviewer: openai:gpt-5.5 -> openai:gpt-5.5-pro
        assert any("reviewer" in line and "gpt-5.5-pro" in line for line in lines)

    def test_denylist_skips(self):
        from loa_cheval.routing.tier_groups import dryrun_preview
        config = {
            "hounfour": {"prefer_pro_models": True},
            "tier_groups": {"mappings": {"reviewer": "openai:gpt-5.5-pro"}, "denylist": ["reviewer"]},
            "aliases": {"reviewer": "openai:gpt-5.5"},
        }
        lines = dryrun_preview(config)
        assert any("reviewer" in line and "denylist" in line for line in lines)

    def test_validate_tier_groups_clean(self):
        from loa_cheval.routing.tier_groups import validate_tier_groups
        config = {
            "tier_groups": {"mappings": {"reviewer": "openai:gpt-5.5-pro"}, "denylist": [], "max_cost_per_session_micro_usd": None},
            "aliases": {"reviewer": "openai:gpt-5.5"},
        }
        warnings = validate_tier_groups(config)
        assert warnings == []

    def test_validate_tier_groups_unknown_denylist_warns(self):
        from loa_cheval.routing.tier_groups import validate_tier_groups
        config = {
            "tier_groups": {"mappings": {}, "denylist": ["nonexistent-alias"]},
            "aliases": {"reviewer": "openai:gpt-5.5"},
        }
        warnings = validate_tier_groups(config)
        assert any("nonexistent-alias" in w for w in warnings)

    def test_validate_tier_groups_invalid_cap_raises(self):
        from loa_cheval.routing.tier_groups import validate_tier_groups
        from loa_cheval.types import ConfigError
        config = {
            "tier_groups": {"max_cost_per_session_micro_usd": -1},
        }
        with pytest.raises(ConfigError, match="max_cost_per_session_micro_usd"):
            validate_tier_groups(config)

    def test_dryrun_env_var(self, monkeypatch):
        from loa_cheval.routing.tier_groups import is_dryrun_active
        monkeypatch.delenv("LOA_PREFER_PRO_DRYRUN", raising=False)
        assert is_dryrun_active() is False
        monkeypatch.setenv("LOA_PREFER_PRO_DRYRUN", "1")
        assert is_dryrun_active() is True
        monkeypatch.setenv("LOA_PREFER_PRO_DRYRUN", "true")
        assert is_dryrun_active() is True
        monkeypatch.setenv("LOA_PREFER_PRO_DRYRUN", "0")
        assert is_dryrun_active() is False

