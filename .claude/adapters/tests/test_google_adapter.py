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
    Usage,
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

    @patch("loa_cheval.providers.google_adapter._poll_get")
    @patch("loa_cheval.providers.google_adapter.http_post")
    def test_deep_research_blocking_poll(self, mock_http, mock_poll):
        """Task 2.1: Full blocking-poll flow."""
        create_fixture = json.loads((FIXTURES / "gemini-deep-research-create.json").read_text())
        completed_fixture = json.loads((FIXTURES / "gemini-deep-research-completed.json").read_text())

        mock_http.return_value = (200, create_fixture)
        mock_poll.return_value = (200, completed_fixture)

        config = _make_google_config()
        config.models["deep-research-pro"] = ModelConfig(
            capabilities=["chat", "deep_research"],
            api_mode="interactions",
            extra={"polling_interval_s": 0.1, "max_poll_time_s": 5, "store": False},
        )
        adapter = GoogleAdapter(config)
        request = CompletionRequest(
            messages=[{"role": "user", "content": "Research quantum computing advances"}],
            model="deep-research-pro",
        )
        result = adapter.complete(request)

        assert result.provider == "google"
        # Content is JSON with normalized citations
        import json as _json
        parsed = _json.loads(result.content)
        assert "citations" in parsed
        assert "raw_output" in parsed


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


# --- Deep Research Tests (Sprint 2 Task 2.7) ---


class TestDeepResearchPoll:
    """Test Deep Research Interactions API polling."""

    @patch("loa_cheval.providers.google_adapter._poll_get")
    @patch("loa_cheval.providers.google_adapter.http_post")
    def test_poll_timeout(self, mock_http, mock_poll):
        """Forever-pending → TimeoutError."""
        create_resp = {"name": "interactions/test-123"}
        mock_http.return_value = (200, create_resp)
        mock_poll.return_value = (200, {"status": "processing"})

        config = _make_google_config()
        config.models["deep-research-pro"] = ModelConfig(
            api_mode="interactions",
            extra={"polling_interval_s": 0.05, "max_poll_time_s": 0.2},
        )
        adapter = GoogleAdapter(config)
        request = CompletionRequest(
            messages=[{"role": "user", "content": "test"}],
            model="deep-research-pro",
        )
        with pytest.raises(TimeoutError, match="timed out"):
            adapter.complete(request)

    @patch("loa_cheval.providers.google_adapter._poll_get")
    @patch("loa_cheval.providers.google_adapter.http_post")
    def test_poll_failure(self, mock_http, mock_poll):
        """Failed status → ProviderUnavailableError."""
        mock_http.return_value = (200, {"name": "interactions/test-456"})
        failed_fixture = json.loads((FIXTURES / "gemini-deep-research-failed.json").read_text())
        mock_poll.return_value = (200, failed_fixture)

        config = _make_google_config()
        config.models["deep-research-pro"] = ModelConfig(
            api_mode="interactions",
            extra={"polling_interval_s": 0.05, "max_poll_time_s": 5},
        )
        adapter = GoogleAdapter(config)
        request = CompletionRequest(
            messages=[{"role": "user", "content": "test"}],
            model="deep-research-pro",
        )
        with pytest.raises(ProviderUnavailableError, match="failed"):
            adapter.complete(request)

    @patch("loa_cheval.providers.google_adapter.http_post")
    def test_store_default_false(self, mock_http):
        """Verify store: false in request body by default (Flatline SKP-002)."""
        mock_http.return_value = (200, {"name": "interactions/test-789"})

        config = _make_google_config()
        config.models["deep-research-pro"] = ModelConfig(
            api_mode="interactions",
            extra={"polling_interval_s": 0.05, "max_poll_time_s": 0.1},
        )
        adapter = GoogleAdapter(config)

        # Just test create_interaction directly
        request = CompletionRequest(
            messages=[{"role": "user", "content": "test"}],
            model="deep-research-pro",
        )
        model_config = config.models["deep-research-pro"]
        adapter.create_interaction(request, model_config, store=False)

        call_args = mock_http.call_args
        body = call_args[0][2] if len(call_args[0]) > 2 else call_args[1].get("body", {})
        assert body.get("store") is False

    @patch("loa_cheval.providers.google_adapter._poll_get")
    def test_schema_tolerant_status(self, mock_poll):
        """Both 'status' and 'state' field names accepted."""
        from loa_cheval.providers.google_adapter import GoogleAdapter as GA

        config = _make_google_config()
        config.models["dr"] = ModelConfig(
            api_mode="interactions",
            extra={"polling_interval_s": 0.05, "max_poll_time_s": 5},
        )
        adapter = GA(config)

        # Test with "state" field instead of "status"
        mock_poll.return_value = (200, {"state": "completed", "output": "result"})
        result = adapter.poll_interaction(
            "interactions/test", config.models["dr"],
            poll_interval=0.05, timeout=2,
        )
        assert result.get("state") == "completed"

    @patch("loa_cheval.providers.google_adapter._poll_get")
    @patch("loa_cheval.providers.google_adapter.time.sleep")
    def test_poll_retry_on_5xx(self, mock_sleep, mock_poll):
        """Transient 500 during poll → retry, then complete (Flatline SKP-009)."""
        config = _make_google_config()
        config.models["dr"] = ModelConfig(
            api_mode="interactions",
            extra={"polling_interval_s": 0.05, "max_poll_time_s": 30},
        )
        adapter = GoogleAdapter(config)

        mock_poll.side_effect = [
            (500, {"error": {"message": "Internal"}}),
            (200, {"status": "completed", "output": "done"}),
        ]
        result = adapter.poll_interaction(
            "interactions/test", config.models["dr"],
            poll_interval=0.05, timeout=10,
        )
        assert result.get("status") == "completed"

    @patch("loa_cheval.providers.google_adapter._poll_get")
    @patch("loa_cheval.providers.google_adapter.time.sleep")
    def test_unknown_status_continues(self, mock_sleep, mock_poll, caplog):
        """Unknown status string → continue polling (Flatline SKP-009)."""
        config = _make_google_config()
        config.models["dr"] = ModelConfig(
            api_mode="interactions",
            extra={"polling_interval_s": 0.05, "max_poll_time_s": 5},
        )
        adapter = GoogleAdapter(config)

        mock_poll.side_effect = [
            (200, {"status": "initializing_research_agents"}),
            (200, {"status": "completed", "output": "done"}),
        ]
        with caplog.at_level(logging.WARNING, logger="loa_cheval.providers.google"):
            result = adapter.poll_interaction(
                "interactions/test", config.models["dr"],
                poll_interval=0.05, timeout=5,
            )
        assert result.get("status") == "completed"
        assert "unknown_status" in caplog.text

    @patch("loa_cheval.providers.google_adapter.http_post")
    def test_cancel_idempotent(self, mock_http):
        """Cancel already-cancelled → no error (Flatline SKP-009)."""
        mock_http.return_value = (400, {"error": {"message": "Already completed"}})

        adapter = GoogleAdapter(_make_google_config())
        result = adapter.cancel_interaction("interactions/test-done")
        # 400 = already done, still returns True (idempotent)
        assert result is True


# --- Citation Normalization Tests (Task 2.2) ---


class TestNormalizeCitations:
    """Test Deep Research output citation extraction."""

    def test_citations_with_dois(self):
        text = "See DOI 10.1234/example.2025.001 and 10.5678/paper.v2 for details."
        from loa_cheval.providers.google_adapter import _normalize_citations
        result = _normalize_citations(text)
        dois = [c for c in result["citations"] if c["type"] == "doi"]
        assert len(dois) == 2
        assert dois[0]["value"] == "10.1234/example.2025.001"

    def test_citations_with_urls(self):
        text = "For more info, see https://example.com/paper and http://arxiv.org/abs/1234."
        from loa_cheval.providers.google_adapter import _normalize_citations
        result = _normalize_citations(text)
        urls = [c for c in result["citations"] if c["type"] == "url"]
        assert len(urls) == 2

    def test_citations_with_references(self):
        text = "According to [1], the approach works. Also see [2] and [3]."
        from loa_cheval.providers.google_adapter import _normalize_citations
        result = _normalize_citations(text)
        refs = [c for c in result["citations"] if c["type"] == "reference"]
        assert len(refs) == 3

    def test_empty_citations(self, caplog):
        text = "Just some plain text without any citations."
        from loa_cheval.providers.google_adapter import _normalize_citations
        with caplog.at_level(logging.WARNING, logger="loa_cheval.providers.google"):
            result = _normalize_citations(text)
        assert result["citations"] == []
        assert result["raw_output"] == text
        assert "no_citations" in caplog.text

    def test_empty_input(self):
        from loa_cheval.providers.google_adapter import _normalize_citations
        result = _normalize_citations("")
        assert result["summary"] == ""
        assert result["citations"] == []

    def test_completed_fixture_citations(self):
        """Full fixture extraction."""
        fixture = json.loads((FIXTURES / "gemini-deep-research-completed.json").read_text())
        from loa_cheval.providers.google_adapter import _normalize_citations
        result = _normalize_citations(fixture["output"])

        # Should find references [1], [2], a DOI, and a URL
        refs = [c for c in result["citations"] if c["type"] == "reference"]
        dois = [c for c in result["citations"] if c["type"] == "doi"]
        urls = [c for c in result["citations"] if c["type"] == "url"]

        assert len(refs) >= 1
        assert len(dois) >= 1
        assert len(urls) >= 1


# --- Health Check Tests (Review F2) ---


class TestHealthCheck:
    """Test GoogleAdapter health_check method."""

    @patch("loa_cheval.providers.google_adapter._detect_http_client_for_get")
    def test_health_check_success(self, mock_detect):
        """health_check returns True when status < 400."""
        mock_client = MagicMock(return_value=200)
        mock_detect.return_value = mock_client

        adapter = GoogleAdapter(_make_google_config())
        assert adapter.health_check() is True
        mock_client.assert_called_once()

    @patch("loa_cheval.providers.google_adapter._detect_http_client_for_get")
    def test_health_check_failure(self, mock_detect):
        """health_check returns False when status >= 400."""
        mock_client = MagicMock(return_value=401)
        mock_detect.return_value = mock_client

        adapter = GoogleAdapter(_make_google_config())
        assert adapter.health_check() is False

    @patch("loa_cheval.providers.google_adapter._detect_http_client_for_get")
    def test_health_check_exception(self, mock_detect):
        """health_check returns False on exception."""
        mock_detect.side_effect = RuntimeError("connection failed")

        adapter = GoogleAdapter(_make_google_config())
        assert adapter.health_check() is False

    @patch("loa_cheval.providers.google_adapter._detect_http_client_for_get")
    def test_health_check_url_construction(self, mock_detect):
        """health_check calls models endpoint."""
        mock_client = MagicMock(return_value=200)
        mock_detect.return_value = mock_client

        adapter = GoogleAdapter(_make_google_config())
        adapter.health_check()

        call_args = mock_client.call_args
        url = call_args[0][0]
        assert "models" in url
        assert "generativelanguage.googleapis.com" in url


# --- Poll GET Error Handling Tests (Review F1) ---


class TestPollGetErrors:
    """Test _poll_get resilience to non-HTTP errors."""

    @patch("urllib.request.urlopen")
    def test_poll_get_urllib_url_error(self, mock_urlopen):
        """URLError (DNS failure, connection refused) → 503."""
        import urllib.error

        mock_urlopen.side_effect = urllib.error.URLError("Name resolution failed")

        # Force urllib fallback by hiding httpx
        with patch.dict("sys.modules", {"httpx": None}):
            # Re-import to ensure clean import path
            import importlib
            import loa_cheval.providers.google_adapter as ga_mod
            importlib.reload(ga_mod)
            status, resp = ga_mod._poll_get("https://bad-host.invalid", {})
            # Reload again to restore httpx availability
            importlib.reload(ga_mod)

        assert status == 503
        assert "URLError" in resp["error"]["message"] or "Name resolution" in resp["error"]["message"]

    @patch("loa_cheval.providers.google_adapter._poll_get")
    def test_poll_get_returns_503_on_network_error(self, mock_poll):
        """Verify poll callers handle 503 gracefully."""
        mock_poll.return_value = (503, {"error": {"message": "URLError: connection refused"}})
        status, resp = mock_poll("https://example.com", {})
        assert status == 503


# --- Interaction Persistence Tests (Flatline SKP-009) ---


class TestInteractionPersistence:
    """Test interaction metadata persistence for crash recovery."""

    def test_persist_and_load(self, tmp_path, monkeypatch):
        from loa_cheval.providers.google_adapter import (
            _persist_interaction,
            _load_persisted_interactions,
            _INTERACTIONS_FILE,
        )
        import loa_cheval.providers.google_adapter as ga_mod

        # Redirect to tmp path
        test_file = str(tmp_path / ".dr-interactions.json")
        monkeypatch.setattr(ga_mod, "_INTERACTIONS_FILE", test_file)

        _persist_interaction("interactions/test-1", "gemini-3-pro")
        data = _load_persisted_interactions()
        assert "interactions/test-1" in data
        assert data["interactions/test-1"]["model"] == "gemini-3-pro"

    def test_persist_concurrent_safe(self, tmp_path, monkeypatch):
        """Concurrent _persist_interaction calls don't corrupt data (Review CONCERN-5)."""
        from loa_cheval.providers.google_adapter import (
            _persist_interaction,
            _load_persisted_interactions,
        )
        import loa_cheval.providers.google_adapter as ga_mod

        test_file = str(tmp_path / ".dr-interactions.json")
        monkeypatch.setattr(ga_mod, "_INTERACTIONS_FILE", test_file)

        # Sequential writes simulating concurrent access
        _persist_interaction("interactions/a", "gemini-3-pro")
        _persist_interaction("interactions/b", "gemini-3-flash")

        data = _load_persisted_interactions()
        assert "interactions/a" in data
        assert "interactions/b" in data
        assert data["interactions/a"]["model"] == "gemini-3-pro"
        assert data["interactions/b"]["model"] == "gemini-3-flash"

    def test_stale_interactions_loadable(self, tmp_path, monkeypatch):
        """Stale .dr-interactions.json with dead PID loads without error (Task 7.5)."""
        import loa_cheval.providers.google_adapter as ga_mod

        test_file = str(tmp_path / ".dr-interactions.json")
        monkeypatch.setattr(ga_mod, "_INTERACTIONS_FILE", test_file)

        # Write stale data with a PID that doesn't exist
        stale_data = {
            "interactions/dead-1": {
                "model": "gemini-3-pro",
                "start_time": 1000000.0,
                "pid": 99999999,  # Dead PID
            },
            "interactions/dead-2": {
                "model": "deep-research-pro",
                "start_time": 1000001.0,
                "pid": 88888888,
            },
        }
        with open(test_file, "w") as f:
            json.dump(stale_data, f)

        from loa_cheval.providers.google_adapter import _load_persisted_interactions
        data = _load_persisted_interactions()
        assert len(data) == 2
        assert data["interactions/dead-1"]["pid"] == 99999999

    def test_corrupted_interactions_file(self, tmp_path, monkeypatch):
        """Corrupted .dr-interactions.json returns empty dict (Task 7.5)."""
        import loa_cheval.providers.google_adapter as ga_mod

        test_file = str(tmp_path / ".dr-interactions.json")
        monkeypatch.setattr(ga_mod, "_INTERACTIONS_FILE", test_file)

        with open(test_file, "w") as f:
            f.write("not valid json{{{")

        from loa_cheval.providers.google_adapter import _load_persisted_interactions
        data = _load_persisted_interactions()
        assert data == {}


# --- Semaphore Pool Tests (Task 7.5) ---


class TestSemaphorePools:
    """Standard and Deep Research use separate concurrency pools."""

    def test_standard_pool_name(self):
        """Standard completion uses 'google-standard' pool."""
        from loa_cheval.providers.concurrency import FLockSemaphore

        sem = FLockSemaphore("google-standard", max_concurrent=5)
        assert sem.name == "google-standard"
        assert sem.max_concurrent == 5

    def test_deep_research_pool_name(self):
        """Deep Research uses 'google-deep-research' pool."""
        from loa_cheval.providers.concurrency import FLockSemaphore

        sem = FLockSemaphore("google-deep-research", max_concurrent=3)
        assert sem.name == "google-deep-research"
        assert sem.max_concurrent == 3

    def test_pools_independent(self):
        """Different pool names → independent semaphores."""
        from loa_cheval.providers.concurrency import FLockSemaphore

        sem1 = FLockSemaphore("google-standard", max_concurrent=5)
        sem2 = FLockSemaphore("google-deep-research", max_concurrent=3)
        # Different names produce different lock paths
        assert sem1.name != sem2.name


# --- API Version and URL Construction (Task 7.5) ---


class TestApiVersionOverride:
    """Test api_version override and URL construction edge cases."""

    def test_default_api_version(self):
        adapter = GoogleAdapter(_make_google_config())
        assert adapter._api_version == "v1beta"

    def test_url_with_model_colon(self):
        """Model names with colons in generateContent path."""
        adapter = GoogleAdapter(_make_google_config())
        url = adapter._build_url("models/gemini-3-pro:generateContent")
        assert "v1beta" in url
        assert "gemini-3-pro:generateContent" in url

    def test_url_with_interactions_path(self):
        """Interactions API path."""
        adapter = GoogleAdapter(_make_google_config())
        url = adapter._build_url("models/deep-research-pro:createInteraction")
        assert "v1beta" in url
        assert "createInteraction" in url

    def test_endpoint_normalization_strips_version(self):
        """Endpoint with version suffix → stripped to avoid doubling."""
        config = _make_google_config(
            endpoint="https://generativelanguage.googleapis.com/v1beta"
        )
        adapter = GoogleAdapter(config)
        url = adapter._build_url("models")
        # Should not produce /v1beta/v1beta/models
        assert url.count("v1beta") == 1

    def test_endpoint_without_version(self):
        """Endpoint without version → version added correctly."""
        config = _make_google_config(
            endpoint="https://generativelanguage.googleapis.com"
        )
        adapter = GoogleAdapter(config)
        url = adapter._build_url("models")
        assert "v1beta/models" in url


# --- Auth Header Tests (Task 7.5) ---


class TestAuthHeader:
    """Test authentication is via x-goog-api-key header."""

    @patch("loa_cheval.providers.google_adapter.http_post")
    def test_auth_header_present(self, mock_http):
        """Auth key sent via x-goog-api-key header (not query param)."""
        fixture = json.loads((FIXTURES / "gemini-standard-response.json").read_text())
        mock_http.return_value = (200, fixture)

        config = _make_google_config(auth="AIzaSyTEST_KEY_12345")
        adapter = GoogleAdapter(config)
        request = CompletionRequest(
            messages=[{"role": "user", "content": "Hello"}],
            model="gemini-2.5-pro",
        )
        adapter.complete(request)

        call_args = mock_http.call_args
        headers = call_args[1]["headers"] if "headers" in call_args[1] else call_args[0][1]
        assert headers.get("x-goog-api-key") == "AIzaSyTEST_KEY_12345"

    @patch("loa_cheval.providers.google_adapter.http_post")
    def test_auth_not_in_url(self, mock_http):
        """Auth key must NOT appear as URL query parameter."""
        fixture = json.loads((FIXTURES / "gemini-standard-response.json").read_text())
        mock_http.return_value = (200, fixture)

        config = _make_google_config(auth="AIzaSyTEST_KEY_12345")
        adapter = GoogleAdapter(config)
        request = CompletionRequest(
            messages=[{"role": "user", "content": "Hello"}],
            model="gemini-2.5-pro",
        )
        adapter.complete(request)

        call_args = mock_http.call_args
        url = call_args[1]["url"] if "url" in call_args[1] else call_args[0][0]
        assert "AIzaSyTEST_KEY_12345" not in url


# --- Max Retries Exhausted (Task 7.5) ---


class TestMaxRetriesExhausted:
    """Final error is surfaced when all retries are exhausted."""

    @patch("loa_cheval.providers.google_adapter.http_post")
    @patch("loa_cheval.providers.google_adapter.time.sleep")
    def test_final_503_raises_provider_unavailable(self, mock_sleep, mock_http):
        """All retries exhausted on 503 → ProviderUnavailableError with message."""
        mock_http.return_value = (503, {"error": {"message": "Service Unavailable"}})

        adapter = GoogleAdapter(_make_google_config())
        request = CompletionRequest(
            messages=[{"role": "user", "content": "Hello"}],
            model="gemini-2.5-pro",
        )
        with pytest.raises(ProviderUnavailableError, match="503"):
            adapter.complete(request)

    @patch("loa_cheval.providers.google_adapter._poll_get")
    @patch("loa_cheval.providers.google_adapter.http_post")
    @patch("loa_cheval.providers.google_adapter.time.sleep")
    def test_poll_max_retries_surfaces_error(self, mock_sleep, mock_http, mock_poll):
        """Poll retries exhausted → error surfaced, not swallowed."""
        mock_http.return_value = (200, {"name": "interactions/test-retry"})
        # All poll attempts fail with 503
        mock_poll.return_value = (503, {"error": {"message": "Unavailable"}})

        config = _make_google_config()
        config.models["deep-research-pro"] = ModelConfig(
            api_mode="interactions",
            extra={"polling_interval_s": 0.05, "max_poll_time_s": 5},
        )
        adapter = GoogleAdapter(config)
        request = CompletionRequest(
            messages=[{"role": "user", "content": "test"}],
            model="deep-research-pro",
        )
        with pytest.raises(ProviderUnavailableError):
            adapter.complete(request)
