"""Tests for Google Gemini provider adapter (SDD 4.1, Sprint 1 Task 1.8)."""

import json
import logging
import sys
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from loa_cheval.providers.google_adapter import (
    GoogleAdapter,
    _build_thinking_config,
    _call_with_retry,
    _extract_error_message,
    _parse_response,
    _raise_for_status,
    _translate_messages,
)
from loa_cheval.types import (
    CompletionRequest,
    ConfigError,
    InvalidInputError,
    ModelConfig,
    ProviderConfig,
    ProviderUnavailableError,
    RateLimitError,
)

FIXTURES = Path(__file__).parent / "fixtures"


def _make_google_config(**overrides):
    """Create a ProviderConfig for Google adapter tests."""
    defaults = dict(
        name="google",
        type="google",
        endpoint="https://generativelanguage.googleapis.com/v1beta",
        auth="test-google-api-key",
        models={
            "gemini-2.5-pro": ModelConfig(
                capabilities=["chat", "thinking_traces"],
                context_window=1048576,
                pricing={"input_per_mtok": 1250000, "output_per_mtok": 10000000},
                extra={"thinking_budget": -1},
            ),
            "gemini-3-pro": ModelConfig(
                capabilities=["chat", "thinking_traces"],
                context_window=2097152,
                pricing={"input_per_mtok": 2500000, "output_per_mtok": 15000000},
                extra={"thinking_level": "high"},
            ),
            "gemini-3-flash": ModelConfig(
                capabilities=["chat", "thinking_traces"],
                context_window=2097152,
                extra={"thinking_level": "medium"},
            ),
        },
    )
    defaults.update(overrides)
    return ProviderConfig(**defaults)


def _default_model_config(**overrides):
    """Create a ModelConfig with sensible defaults for tests."""
    defaults = dict(
        capabilities=["chat", "thinking_traces"],
        context_window=1048576,
    )
    defaults.update(overrides)
    return ModelConfig(**defaults)


# --- Message Translation Tests (Task 1.2) ---


class TestTranslateMessages:
    """Test canonical → Gemini message format translation."""

    def test_basic_user_message(self):
        messages = [{"role": "user", "content": "Hello world"}]
        system, contents = _translate_messages(messages, _default_model_config())
        assert system is None
        assert len(contents) == 1
        assert contents[0]["role"] == "user"
        assert contents[0]["parts"] == [{"text": "Hello world"}]

    def test_assistant_mapped_to_model(self):
        messages = [
            {"role": "user", "content": "Hi"},
            {"role": "assistant", "content": "Hello!"},
        ]
        _, contents = _translate_messages(messages, _default_model_config())
        assert len(contents) == 2
        assert contents[1]["role"] == "model"
        assert contents[1]["parts"] == [{"text": "Hello!"}]

    def test_system_extracted(self):
        messages = [
            {"role": "system", "content": "You are a helpful assistant."},
            {"role": "user", "content": "Help me."},
        ]
        system, contents = _translate_messages(messages, _default_model_config())
        assert system == "You are a helpful assistant."
        assert len(contents) == 1
        assert contents[0]["role"] == "user"

    def test_multiple_system_concatenated(self):
        messages = [
            {"role": "system", "content": "Part 1"},
            {"role": "system", "content": "Part 2"},
            {"role": "user", "content": "Hello"},
        ]
        system, contents = _translate_messages(messages, _default_model_config())
        assert system == "Part 1\n\nPart 2"
        assert len(contents) == 1

    def test_unsupported_array_content(self):
        messages = [
            {
                "role": "user",
                "content": [
                    {"type": "text", "text": "Look at this"},
                    {"type": "image_url", "image_url": {"url": "data:image/png;base64,..."}},
                ],
            }
        ]
        with pytest.raises(InvalidInputError, match="array content blocks"):
            _translate_messages(messages, _default_model_config())

    def test_unsupported_array_suggests_fallback(self):
        """Flatline SKP-002: suggest fallback provider when capabilities missing."""
        config = _default_model_config(capabilities=["chat"])
        messages = [
            {"role": "user", "content": [{"type": "image_url"}]},
        ]
        with pytest.raises(InvalidInputError, match="OpenAI or Anthropic"):
            _translate_messages(messages, config)

    def test_empty_content_skipped(self):
        messages = [
            {"role": "user", "content": "Hello"},
            {"role": "assistant", "content": ""},
            {"role": "user", "content": "More"},
        ]
        _, contents = _translate_messages(messages, _default_model_config())
        assert len(contents) == 2
        assert contents[0]["parts"] == [{"text": "Hello"}]
        assert contents[1]["parts"] == [{"text": "More"}]


# --- Thinking Config Tests (Task 1.3) ---


class TestBuildThinkingConfig:
    """Test model-aware thinking configuration."""

    def test_gemini3_thinking_level(self):
        config = _default_model_config(extra={"thinking_level": "high"})
        result = _build_thinking_config("gemini-3-pro", config)
        assert result == {"thinkingConfig": {"thinkingLevel": "high"}}

    def test_gemini3_default_level(self):
        config = _default_model_config(extra={})
        result = _build_thinking_config("gemini-3-flash", config)
        assert result == {"thinkingConfig": {"thinkingLevel": "high"}}

    def test_gemini25_thinking_budget(self):
        config = _default_model_config(extra={"thinking_budget": -1})
        result = _build_thinking_config("gemini-2.5-pro", config)
        assert result == {"thinkingConfig": {"thinkingBudget": -1}}

    def test_gemini25_thinking_disabled(self):
        config = _default_model_config(extra={"thinking_budget": 0})
        result = _build_thinking_config("gemini-2.5-flash", config)
        assert result is None

    def test_other_model_returns_none(self):
        config = _default_model_config()
        result = _build_thinking_config("gpt-5.2", config)
        assert result is None

    def test_no_extra_dict(self):
        config = _default_model_config(extra=None)
        result = _build_thinking_config("gemini-3-pro", config)
        assert result == {"thinkingConfig": {"thinkingLevel": "high"}}


# --- Response Parsing Tests (Task 1.4) ---


class TestParseResponse:
    """Test Gemini generateContent response parsing."""

    def test_standard_response(self):
        fixture = json.loads((FIXTURES / "gemini-standard-response.json").read_text())
        config = _default_model_config()
        result = _parse_response(fixture, "gemini-2.5-pro", 100, "google", config)

        assert result.content == "This is a test response from the Gemini API."
        assert result.thinking is None
        assert result.tool_calls is None
        assert result.usage.input_tokens == 42
        assert result.usage.output_tokens == 15
        assert result.usage.source == "actual"
        assert result.model == "gemini-2.5-pro"
        assert result.provider == "google"
        assert result.latency_ms == 100

    def test_thinking_response(self):
        fixture = json.loads((FIXTURES / "gemini-thinking-response.json").read_text())
        config = _default_model_config()
        result = _parse_response(fixture, "gemini-3-pro", 150, "google", config)

        assert result.thinking is not None
        assert "analyze this step by step" in result.thinking
        assert "hash map" in result.content
        assert result.usage.reasoning_tokens == 120
        assert result.usage.source == "actual"

    def test_safety_block(self):
        fixture = json.loads((FIXTURES / "gemini-safety-block.json").read_text())
        config = _default_model_config()
        with pytest.raises(InvalidInputError, match="safety filters"):
            _parse_response(fixture, "gemini-2.5-pro", 50, "google", config)

    def test_recitation_block(self):
        resp = {
            "candidates": [
                {
                    "content": {"parts": [{"text": "copied text"}]},
                    "finishReason": "RECITATION",
                }
            ],
        }
        config = _default_model_config()
        with pytest.raises(InvalidInputError, match="recitation"):
            _parse_response(resp, "gemini-2.5-pro", 50, "google", config)

    def test_max_tokens_truncated(self, caplog):
        resp = {
            "candidates": [
                {
                    "content": {"parts": [{"text": "truncated output"}]},
                    "finishReason": "MAX_TOKENS",
                }
            ],
            "usageMetadata": {
                "promptTokenCount": 100,
                "candidatesTokenCount": 4096,
            },
        }
        config = _default_model_config()
        with caplog.at_level(logging.WARNING, logger="loa_cheval.providers.google"):
            result = _parse_response(resp, "gemini-2.5-pro", 100, "google", config)
        assert result.content == "truncated output"
        assert "MAX_TOKENS" in caplog.text

    def test_empty_candidates_raises(self):
        resp = {"candidates": []}
        config = _default_model_config()
        with pytest.raises(InvalidInputError, match="empty candidates"):
            _parse_response(resp, "gemini-2.5-pro", 50, "google", config)

    def test_no_candidates_key_raises(self):
        resp = {}
        config = _default_model_config()
        with pytest.raises(InvalidInputError, match="empty candidates"):
            _parse_response(resp, "gemini-2.5-pro", 50, "google", config)

    def test_missing_usage_metadata(self, caplog):
        """Flatline SKP-007: missing usageMetadata → conservative estimate."""
        resp = {
            "candidates": [
                {
                    "content": {"parts": [{"text": "response text"}]},
                    "finishReason": "STOP",
                }
            ],
        }
        config = _default_model_config()
        with caplog.at_level(logging.WARNING, logger="loa_cheval.providers.google"):
            result = _parse_response(resp, "gemini-2.5-pro", 100, "google", config)
        assert result.usage.source == "estimated"
        assert "missing_usage" in caplog.text

    def test_partial_usage_metadata(self, caplog):
        """Flatline SKP-007: missing thoughtsTokenCount → default 0."""
        resp = {
            "candidates": [
                {
                    "content": {
                        "parts": [
                            {"text": "thinking here", "thought": True},
                            {"text": "answer"},
                        ]
                    },
                    "finishReason": "STOP",
                }
            ],
            "usageMetadata": {
                "promptTokenCount": 50,
                "candidatesTokenCount": 20,
                # No thoughtsTokenCount
            },
        }
        config = _default_model_config()
        with caplog.at_level(logging.WARNING, logger="loa_cheval.providers.google"):
            result = _parse_response(resp, "gemini-3-pro", 100, "google", config)
        assert result.usage.reasoning_tokens == 0
        assert result.thinking == "thinking here"
        assert "partial_usage" in caplog.text

    def test_unknown_finish_reason(self, caplog):
        """Flatline SKP-001: unknown finishReason → log warning, return content."""
        resp = {
            "candidates": [
                {
                    "content": {"parts": [{"text": "some content"}]},
                    "finishReason": "UNKNOWN_NEW_REASON",
                }
            ],
            "usageMetadata": {
                "promptTokenCount": 10,
                "candidatesTokenCount": 5,
            },
        }
        config = _default_model_config()
        with caplog.at_level(logging.WARNING, logger="loa_cheval.providers.google"):
            result = _parse_response(resp, "gemini-2.5-pro", 50, "google", config)
        assert result.content == "some content"
        assert "unknown_finish_reason" in caplog.text


# --- Error Mapping Tests (Task 1.5) ---


class TestErrorMapping:
    """Test Google API HTTP status → Hounfour error type mapping."""

    def test_400_invalid_input(self):
        with pytest.raises(InvalidInputError, match="400"):
            _raise_for_status(400, {"error": {"message": "Bad request"}}, "google")

    def test_401_config_error(self):
        with pytest.raises(ConfigError, match="401"):
            _raise_for_status(401, {"error": {"message": "Unauthorized"}}, "google")

    def test_403_provider_unavailable(self):
        with pytest.raises(ProviderUnavailableError, match="403"):
            _raise_for_status(403, {"error": {"message": "Forbidden"}}, "google")

    def test_404_invalid_input(self):
        with pytest.raises(InvalidInputError, match="404"):
            _raise_for_status(404, {"error": {"message": "Not found"}}, "google")

    def test_429_rate_limit(self):
        with pytest.raises(RateLimitError):
            _raise_for_status(429, {"error": {"message": "Rate limited"}}, "google")

    def test_500_provider_unavailable(self):
        with pytest.raises(ProviderUnavailableError, match="500"):
            _raise_for_status(500, {"error": {"message": "Internal error"}}, "google")

    def test_503_provider_unavailable(self):
        with pytest.raises(ProviderUnavailableError, match="503"):
            _raise_for_status(503, {"error": {"message": "Unavailable"}}, "google")

    def test_unknown_status(self):
        with pytest.raises(ProviderUnavailableError, match="502"):
            _raise_for_status(502, {"error": {"message": "Bad gateway"}}, "google")


# --- Retry Tests (Flatline IMP-001) ---


class TestRetry:
    """Test retry with exponential backoff for retryable status codes."""

    @patch("loa_cheval.providers.google_adapter.http_post")
    @patch("loa_cheval.providers.google_adapter.time.sleep")
    def test_retry_on_429(self, mock_sleep, mock_http):
        """Retries with backoff on 429."""
        mock_http.side_effect = [
            (429, {"error": {"message": "Rate limited"}}),
            (429, {"error": {"message": "Rate limited"}}),
            (200, {"candidates": [{"content": {"parts": [{"text": "ok"}]}}]}),
        ]
        status, resp = _call_with_retry(
            "https://example.com", {}, {},
            connect_timeout=5.0, read_timeout=10.0,
        )
        assert status == 200
        assert mock_sleep.call_count == 2
        assert mock_http.call_count == 3

    @patch("loa_cheval.providers.google_adapter.http_post")
    @patch("loa_cheval.providers.google_adapter.time.sleep")
    def test_retry_on_500(self, mock_sleep, mock_http):
        """Retries with backoff on 500."""
        mock_http.side_effect = [
            (500, {"error": {"message": "Internal error"}}),
            (200, {"candidates": []}),
        ]
        status, resp = _call_with_retry(
            "https://example.com", {}, {},
        )
        assert status == 200
        assert mock_sleep.call_count == 1

    @patch("loa_cheval.providers.google_adapter.http_post")
    def test_no_retry_on_400(self, mock_http):
        """No retry on non-retryable 400."""
        mock_http.return_value = (400, {"error": {"message": "Bad request"}})
        status, resp = _call_with_retry(
            "https://example.com", {}, {},
        )
        assert status == 400
        assert mock_http.call_count == 1

    @patch("loa_cheval.providers.google_adapter.http_post")
    @patch("loa_cheval.providers.google_adapter.time.sleep")
    def test_retries_exhausted(self, mock_sleep, mock_http):
        """Returns last error after all retries exhausted."""
        mock_http.return_value = (503, {"error": {"message": "Unavailable"}})
        status, resp = _call_with_retry(
            "https://example.com", {}, {},
        )
        assert status == 503
        # 1 initial + 3 retries = 4 calls, 3 sleeps
        assert mock_http.call_count == 4
        assert mock_sleep.call_count == 3


# --- Validate Config Tests ---


class TestValidateConfig:
    """Test GoogleAdapter config validation."""

    def test_valid_config(self):
        adapter = GoogleAdapter(_make_google_config())
        errors = adapter.validate_config()
        assert errors == []

    def test_missing_endpoint(self):
        adapter = GoogleAdapter(_make_google_config(endpoint=""))
        errors = adapter.validate_config()
        assert any("endpoint" in e for e in errors)

    def test_missing_auth(self):
        adapter = GoogleAdapter(_make_google_config(auth=""))
        errors = adapter.validate_config()
        assert any("auth" in e for e in errors)

    def test_wrong_type(self):
        adapter = GoogleAdapter(_make_google_config(type="openai"))
        errors = adapter.validate_config()
        assert any("type" in e for e in errors)


# --- URL Construction Tests (Flatline SKP-003) ---


class TestBuildUrl:
    """Test centralized URL construction."""

    def test_standard_url(self):
        adapter = GoogleAdapter(_make_google_config())
        url = adapter._build_url("models/gemini-2.5-pro:generateContent")
        assert url == "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-pro:generateContent"

    def test_models_list_url(self):
        adapter = GoogleAdapter(_make_google_config())
        url = adapter._build_url("models")
        assert url == "https://generativelanguage.googleapis.com/v1beta/models"

    def test_endpoint_without_version(self):
        adapter = GoogleAdapter(_make_google_config(
            endpoint="https://generativelanguage.googleapis.com"
        ))
        url = adapter._build_url("models")
        assert url == "https://generativelanguage.googleapis.com/v1beta/models"


# --- Integration-Style Tests ---


class TestGoogleAdapterComplete:
    """Test the full complete() flow with mocked HTTP."""

    @patch("loa_cheval.providers.google_adapter.http_post")
    def test_standard_complete(self, mock_http):
        fixture = json.loads((FIXTURES / "gemini-standard-response.json").read_text())
        mock_http.return_value = (200, fixture)

        adapter = GoogleAdapter(_make_google_config())
        request = CompletionRequest(
            messages=[
                {"role": "system", "content": "You are helpful."},
                {"role": "user", "content": "Hello"},
            ],
            model="gemini-2.5-pro",
            temperature=0.7,
            max_tokens=4096,
        )
        result = adapter.complete(request)

        assert result.content == "This is a test response from the Gemini API."
        assert result.provider == "google"
        assert result.usage.input_tokens == 42

        # Verify the request sent to http_post
        call_args = mock_http.call_args
        url = call_args[1]["url"] if "url" in call_args[1] else call_args[0][0]
        assert "generateContent" in url

        body = call_args[1]["body"] if "body" in call_args[1] else call_args[0][2]
        assert "systemInstruction" in body
        assert body["generationConfig"]["temperature"] == 0.7

    @patch("loa_cheval.providers.google_adapter.http_post")
    def test_thinking_complete(self, mock_http):
        fixture = json.loads((FIXTURES / "gemini-thinking-response.json").read_text())
        mock_http.return_value = (200, fixture)

        adapter = GoogleAdapter(_make_google_config())
        request = CompletionRequest(
            messages=[{"role": "user", "content": "Solve this"}],
            model="gemini-3-pro",
        )
        result = adapter.complete(request)

        assert result.thinking is not None
        assert "step by step" in result.thinking
        assert result.usage.reasoning_tokens == 120

    @patch("loa_cheval.providers.google_adapter.http_post")
    def test_api_error_raises(self, mock_http):
        mock_http.return_value = (429, {"error": {"message": "Rate limited"}})

        adapter = GoogleAdapter(_make_google_config())
        request = CompletionRequest(
            messages=[{"role": "user", "content": "Hello"}],
            model="gemini-2.5-pro",
        )
        with pytest.raises(RateLimitError):
            adapter.complete(request)

    def test_deep_research_stub(self):
        config = _make_google_config()
        config.models["deep-research-pro"] = ModelConfig(
            capabilities=["chat", "deep_research"],
            api_mode="interactions",
        )
        adapter = GoogleAdapter(config)
        request = CompletionRequest(
            messages=[{"role": "user", "content": "Research this"}],
            model="deep-research-pro",
        )
        with pytest.raises(InvalidInputError, match="not yet implemented"):
            adapter.complete(request)


# --- Log Redaction Tests (Flatline IMP-009) ---


class TestLogRedaction:
    """Verify API keys and prompt content never appear in log output."""

    @patch("loa_cheval.providers.google_adapter.http_post")
    def test_api_key_not_in_logs(self, mock_http, caplog):
        fixture = json.loads((FIXTURES / "gemini-standard-response.json").read_text())
        mock_http.return_value = (200, fixture)

        config = _make_google_config(auth="AIzaSyDEADBEEF1234567890")
        adapter = GoogleAdapter(config)
        request = CompletionRequest(
            messages=[{"role": "user", "content": "secret prompt content"}],
            model="gemini-2.5-pro",
        )

        with caplog.at_level(logging.DEBUG, logger="loa_cheval.providers.google"):
            adapter.complete(request)

        # API key must not appear in any log records
        for record in caplog.records:
            assert "AIzaSyDEADBEEF1234567890" not in record.getMessage()
            assert "secret prompt content" not in record.getMessage()


# --- Registry Tests ---


class TestRegistration:
    """Test GoogleAdapter registration in provider registry."""

    def test_google_in_registry(self):
        from loa_cheval.providers import _ADAPTER_REGISTRY
        assert "google" in _ADAPTER_REGISTRY

    def test_get_adapter_returns_google(self):
        from loa_cheval.providers import get_adapter
        config = _make_google_config()
        adapter = get_adapter(config)
        assert isinstance(adapter, GoogleAdapter)
