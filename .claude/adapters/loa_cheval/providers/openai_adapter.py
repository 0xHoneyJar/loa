"""OpenAI provider adapter — handles OpenAI and OpenAI-compatible APIs (SDD §4.2.5)."""

from __future__ import annotations

import logging
import time
from typing import Any, Dict, List, Optional

from loa_cheval.providers.base import (
    ProviderAdapter,
    enforce_context_window,
    http_post,
)
from loa_cheval.types import (
    CompletionRequest,
    CompletionResult,
    InvalidInputError,
    ProviderUnavailableError,
    RateLimitError,
    Usage,
)

logger = logging.getLogger("loa_cheval.providers.openai")

# Supported API surface (SDD §4.2.5) — NO streaming, NO JSON mode in MVP
_SUPPORTED_PARAMS = {"messages", "model", "temperature", "max_tokens", "max_completion_tokens", "tools", "tool_choice"}


class OpenAIAdapter(ProviderAdapter):
    """Adapter for OpenAI and OpenAI-compatible APIs (SDD §4.2.3, §4.2.5)."""

    def complete(self, request: CompletionRequest) -> CompletionResult:
        """Send completion request to OpenAI API, return normalized result."""
        model_config = self._get_model_config(request.model)

        # Context window enforcement (SDD §4.2.4)
        enforce_context_window(request, model_config)

        # Build request body — OpenAI is the canonical format (pass-through)
        token_key = model_config.token_param  # "max_completion_tokens" for GPT-5.2+
        body: Dict[str, Any] = {
            "model": request.model,
            "messages": request.messages,
            "temperature": request.temperature,
            token_key: request.max_tokens,
        }

        if request.tools:
            body["tools"] = request.tools
        if request.tool_choice:
            body["tool_choice"] = request.tool_choice

        # Build headers
        auth = self._get_auth_header()
        headers = {
            "Content-Type": "application/json",
            "Authorization": f"Bearer {auth}",
        }

        url = f"{self.config.endpoint}/chat/completions"
        start = time.monotonic()

        status, resp = http_post(
            url=url,
            headers=headers,
            body=body,
            connect_timeout=self.config.connect_timeout,
            read_timeout=self.config.read_timeout,
        )

        latency_ms = int((time.monotonic() - start) * 1000)

        # Handle errors
        if status == 429:
            retry_after = None
            if isinstance(resp, dict) and "error" in resp:
                # Some providers include retry-after hint in error body
                pass
            raise RateLimitError(self.provider, retry_after)

        if status >= 500:
            msg = _extract_error_message(resp)
            raise ProviderUnavailableError(self.provider, f"HTTP {status}: {msg}")

        if status >= 400:
            msg = _extract_error_message(resp)
            raise InvalidInputError(f"OpenAI API error (HTTP {status}): {msg}")

        # Parse response
        return self._parse_response(resp, latency_ms)

    def _parse_response(self, resp: Dict[str, Any], latency_ms: int) -> CompletionResult:
        """Extract CompletionResult from OpenAI response (SDD §4.2.5)."""
        choices = resp.get("choices", [])
        if not choices:
            raise InvalidInputError("OpenAI response contains no choices")

        message = choices[0].get("message", {})
        content = message.get("content", "") or ""

        # Normalize tool calls to canonical format (SDD §4.2.5)
        raw_tool_calls = message.get("tool_calls")
        tool_calls = _normalize_tool_calls(raw_tool_calls) if raw_tool_calls else None

        # Usage
        usage_data = resp.get("usage", {})
        usage = Usage(
            input_tokens=usage_data.get("prompt_tokens", 0),
            output_tokens=usage_data.get("completion_tokens", 0),
            reasoning_tokens=usage_data.get("completion_tokens_details", {}).get("reasoning_tokens", 0),
            source="actual" if usage_data else "estimated",
        )

        return CompletionResult(
            content=content,
            tool_calls=tool_calls,
            thinking=None,  # OpenAI does not support thinking traces (degrade silently)
            usage=usage,
            model=resp.get("model", "unknown"),
            latency_ms=latency_ms,
            provider=self.provider,
        )

    def validate_config(self) -> List[str]:
        """Validate OpenAI-specific configuration."""
        errors = []
        if not self.config.endpoint:
            errors.append(f"Provider '{self.provider}': endpoint is required")
        if not self.config.auth:
            errors.append(f"Provider '{self.provider}': auth is required")
        if self.config.type not in ("openai", "openai_compat"):
            errors.append(f"Provider '{self.provider}': type must be 'openai' or 'openai_compat'")
        return errors

    def health_check(self) -> bool:
        """Quick health probe via models list endpoint."""
        auth = self._get_auth_header()
        headers = {
            "Authorization": f"Bearer {auth}",
        }
        try:
            from loa_cheval.providers.base import _detect_http_client

            client = _detect_http_client()
            url = f"{self.config.endpoint}/models"

            if client == "httpx":
                import httpx

                resp = httpx.get(url, headers=headers, timeout=5.0)
                return resp.status_code == 200
            else:
                import urllib.request

                req = urllib.request.Request(url, headers=headers)
                with urllib.request.urlopen(req, timeout=5) as resp:
                    return resp.status == 200
        except Exception:
            return False


def _normalize_tool_calls(raw_calls: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """Normalize OpenAI tool calls to canonical format (SDD §4.2.5).

    Canonical format:
    {
        "id": "call_abc123",
        "function": { "name": "search", "arguments": "{\"query\": \"...\"}" },
        "type": "function"
    }
    """
    normalized = []
    for call in raw_calls:
        normalized.append({
            "id": call.get("id", ""),
            "function": {
                "name": call.get("function", {}).get("name", ""),
                "arguments": call.get("function", {}).get("arguments", "{}"),
            },
            "type": "function",
        })
    return normalized


def _extract_error_message(resp: Dict[str, Any]) -> str:
    """Extract error message from OpenAI error response."""
    if isinstance(resp, dict):
        error = resp.get("error", {})
        if isinstance(error, dict):
            return error.get("message", str(resp))
        return str(error)
    return str(resp)
