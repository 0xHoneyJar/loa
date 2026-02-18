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
    ContextTooLargeError,
    InvalidInputError,
    ModelConfig,
    ProviderConfig,
    RateLimitError,
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
        assert result.model == "claude-opus-4-6"

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
            models={"gpt-legacy": ModelConfig()},
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
