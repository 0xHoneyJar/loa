"""Anthropic provider adapter — handles Anthropic Messages API (SDD §4.2.5)."""

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

logger = logging.getLogger("loa_cheval.providers.anthropic")


class AnthropicAdapter(ProviderAdapter):
    """Adapter for Anthropic Messages API (SDD §4.2.3, §4.2.5)."""

    def complete(self, request: CompletionRequest) -> CompletionResult:
        """Send completion request to Anthropic API, return normalized result."""
        model_config = self._get_model_config(request.model)

        # Context window enforcement (SDD §4.2.4)
        enforce_context_window(request, model_config)

        # Transform request from canonical to Anthropic format
        system_prompt, messages = _transform_messages(request.messages)

        body: Dict[str, Any] = {
            "model": request.model,
            "messages": messages,
            "max_tokens": request.max_tokens,
            "temperature": request.temperature,
        }

        if system_prompt:
            body["system"] = system_prompt

        if request.tools:
            body["tools"] = _transform_tools_to_anthropic(request.tools)
        if request.tool_choice:
            body["tool_choice"] = _transform_tool_choice(request.tool_choice)

        # Build headers — Anthropic uses x-api-key, not Bearer token
        auth = self._get_auth_header()
        headers = {
            "Content-Type": "application/json",
            "x-api-key": auth,
            "anthropic-version": "2023-06-01",
        }

        url = f"{self.config.endpoint}/messages"
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
            raise RateLimitError(self.provider)

        if status >= 500:
            msg = _extract_error_message(resp)
            raise ProviderUnavailableError(self.provider, f"HTTP {status}: {msg}")

        if status >= 400:
            msg = _extract_error_message(resp)
            raise InvalidInputError(f"Anthropic API error (HTTP {status}): {msg}")

        # Parse response
        return self._parse_response(resp, latency_ms)

    def _parse_response(self, resp: Dict[str, Any], latency_ms: int) -> CompletionResult:
        """Extract CompletionResult from Anthropic response (SDD §4.2.5)."""
        content_blocks = resp.get("content", [])

        text_parts: List[str] = []
        thinking_parts: List[str] = []
        tool_calls: List[Dict[str, Any]] = []

        for block in content_blocks:
            block_type = block.get("type", "")

            if block_type == "text":
                text_parts.append(block.get("text", ""))
            elif block_type == "thinking":
                # Extract thinking traces (Anthropic-specific)
                thinking_parts.append(block.get("thinking", ""))
            elif block_type == "tool_use":
                # Normalize to canonical tool call format (SDD §4.2.5)
                tool_calls.append({
                    "id": block.get("id", ""),
                    "function": {
                        "name": block.get("name", ""),
                        "arguments": _serialize_arguments(block.get("input", {})),
                    },
                    "type": "function",
                })

        content = "\n".join(text_parts)
        thinking = "\n".join(thinking_parts) if thinking_parts else None

        # Usage
        usage_data = resp.get("usage", {})
        usage = Usage(
            input_tokens=usage_data.get("input_tokens", 0),
            output_tokens=usage_data.get("output_tokens", 0),
            reasoning_tokens=0,  # Anthropic reports thinking tokens differently
            source="actual" if usage_data else "estimated",
        )

        return CompletionResult(
            content=content,
            tool_calls=tool_calls if tool_calls else None,
            thinking=thinking,
            usage=usage,
            model=resp.get("model", "unknown"),
            latency_ms=latency_ms,
            provider=self.provider,
        )

    def validate_config(self) -> List[str]:
        """Validate Anthropic-specific configuration."""
        errors = []
        if not self.config.endpoint:
            errors.append(f"Provider '{self.provider}': endpoint is required")
        if not self.config.auth:
            errors.append(f"Provider '{self.provider}': auth is required")
        if self.config.type != "anthropic":
            errors.append(f"Provider '{self.provider}': type must be 'anthropic'")
        return errors

    def health_check(self) -> bool:
        """Quick health probe. Anthropic doesn't have a models endpoint,
        so we send a minimal messages request."""
        try:
            auth = self._get_auth_header()
            headers = {
                "Content-Type": "application/json",
                "x-api-key": auth,
                "anthropic-version": "2023-06-01",
            }
            body = {
                "model": "claude-3-haiku-20240307",
                "max_tokens": 1,
                "messages": [{"role": "user", "content": "ping"}],
            }
            url = f"{self.config.endpoint}/messages"
            status, _ = http_post(url, headers, body, connect_timeout=5.0, read_timeout=10.0)
            return status == 200
        except Exception:
            return False


def _transform_messages(
    messages: List[Dict[str, Any]],
) -> tuple:
    """Transform canonical messages to Anthropic format.

    Anthropic requires system prompt as a separate parameter, not in messages.
    Returns (system_prompt, anthropic_messages).
    """
    system_prompt = None
    anthropic_messages = []

    for msg in messages:
        role = msg.get("role", "user")
        content = msg.get("content", "")

        if role == "system":
            # Collect system messages — Anthropic only supports one
            if system_prompt is None:
                system_prompt = content
            else:
                system_prompt += "\n\n" + content
        elif role == "tool":
            # Anthropic represents tool results differently
            anthropic_messages.append({
                "role": "user",
                "content": [{
                    "type": "tool_result",
                    "tool_use_id": msg.get("tool_call_id", ""),
                    "content": content,
                }],
            })
        else:
            anthropic_messages.append({
                "role": role,
                "content": content,
            })

    return system_prompt, anthropic_messages


def _transform_tools_to_anthropic(tools: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """Transform OpenAI-format tools to Anthropic tool format."""
    anthropic_tools = []
    for tool in tools:
        if tool.get("type") == "function":
            func = tool.get("function", {})
            anthropic_tools.append({
                "name": func.get("name", ""),
                "description": func.get("description", ""),
                "input_schema": func.get("parameters", {"type": "object", "properties": {}}),
            })
    return anthropic_tools


def _transform_tool_choice(choice: str) -> Dict[str, Any]:
    """Transform canonical tool_choice to Anthropic format."""
    if choice == "auto":
        return {"type": "auto"}
    elif choice == "required":
        return {"type": "any"}
    elif choice == "none":
        return {"type": "none"}
    return {"type": "auto"}


def _serialize_arguments(input_data: Any) -> str:
    """Serialize tool input to JSON string (canonical format expects string arguments)."""
    import json

    if isinstance(input_data, str):
        return input_data
    return json.dumps(input_data)


def _extract_error_message(resp: Dict[str, Any]) -> str:
    """Extract error message from Anthropic error response."""
    if isinstance(resp, dict):
        error = resp.get("error", {})
        if isinstance(error, dict):
            return error.get("message", str(resp))
        return str(error)
    return str(resp)
