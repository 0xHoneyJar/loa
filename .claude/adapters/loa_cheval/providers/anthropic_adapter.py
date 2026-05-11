"""Anthropic provider adapter — handles Anthropic Messages API (SDD §4.2.5).

Sprint 4A (cycle-102, AC-4.5e): `complete()` defaults to the streaming
transport (`http_post_stream` + `parse_anthropic_stream`). The
non-streaming path is preserved behind the `LOA_CHEVAL_DISABLE_STREAMING=1`
env-var kill switch for operator one-shot backstop. Streaming eliminates
KF-002 layer 3 (`httpx.RemoteProtocolError` at 60s wall-clock) by
construction — see `grimoires/loa/known-failures.md` and
`grimoires/loa/cycles/cycle-102-model-stability/sprint.md` Sprint 4A.
"""

from __future__ import annotations

import logging
import os
import time
from typing import Any, Dict, List, Optional

from loa_cheval.providers.anthropic_streaming import parse_anthropic_stream
from loa_cheval.providers.base import (
    ProviderAdapter,
    _streaming_disabled,
    enforce_context_window,
    http_post,
    http_post_stream,
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
        """Send completion request to Anthropic API, return normalized result.

        Sprint 4A: streaming is the default path (KF-002 layer 3 mitigation).
        Set `LOA_CHEVAL_DISABLE_STREAMING=1` to force the legacy non-streaming
        path as a one-shot operator backstop.
        """
        model_config = self._get_model_config(request.model)

        # Context window enforcement (SDD §4.2.4)
        enforce_context_window(request, model_config)

        # Transform request from canonical to Anthropic format
        system_prompt, messages = _transform_messages(request.messages)

        body: Dict[str, Any] = {
            "model": request.model,
            "messages": messages,
            "max_tokens": request.max_tokens,
        }
        # #641: Opus 4 deprecated `temperature` and rejects requests that include
        # it with HTTP 400 ("temperature is deprecated for this model"). Gate the
        # field on a per-model wire-protocol flag. Default True preserves
        # back-compat for Claude 3, 3.5, and pre-4 Opus models.
        # `isinstance` guard handles malformed configs (e.g. `params: "false"` or
        # `params: [foo]` in YAML pass dataclass construction since Python type
        # hints aren't enforced at runtime, but would raise AttributeError on
        # `.get()`). Lenient default → treat malformed as missing → include
        # temperature; dataclass schema validation upstream is the strict path.
        params = model_config.params if isinstance(model_config.params, dict) else {}
        if params.get("temperature_supported", True):
            body["temperature"] = request.temperature

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

        # Sprint 4A: streaming default with operator kill switch.
        # Detection centralized in `base._streaming_disabled()` so adapters
        # + audit-emit share identical semantics (Sprint 4A DISS-001 closure).
        if _streaming_disabled():
            return self._complete_nonstreaming(url, headers, body)
        return self._complete_streaming(url, headers, body)

    def _complete_streaming(
        self,
        url: str,
        headers: Dict[str, str],
        body: Dict[str, Any],
    ) -> CompletionResult:
        """Sprint 4A default path: streaming Messages API."""
        # Anthropic Messages API expects `stream: true` in the request body
        # to switch to SSE response format.
        body = dict(body)
        body["stream"] = True

        start = time.monotonic()
        with http_post_stream(
            url=url,
            headers=headers,
            body=body,
            connect_timeout=self.config.connect_timeout,
            read_timeout=self.config.read_timeout,
        ) as resp:
            status = resp.status_code

            if status >= 400:
                # On error, the body is regular JSON (not SSE). Drain + parse.
                err_bytes = b"".join(resp.iter_bytes())
                try:
                    import json
                    err_json = json.loads(err_bytes.decode("utf-8", errors="replace"))
                except Exception:
                    err_json = {"error": {"message": err_bytes.decode("utf-8", errors="replace")[:500]}}
                if status == 429:
                    raise RateLimitError(self.provider)
                if status >= 500:
                    raise ProviderUnavailableError(
                        self.provider,
                        f"HTTP {status}: {_extract_error_message(err_json)}",
                    )
                raise InvalidInputError(
                    f"Anthropic API error (HTTP {status}): {_extract_error_message(err_json)}"
                )

            # Parse the SSE event stream into a CompletionResult.
            # Sprint 4A cycle-3 (BF-001): map parser-raised ValueError to
            # typed adapter exception so the retry layer routes it via the
            # same arms as non-streaming HTTP error paths. Mid-stream
            # provider errors (Anthropic `error` SSE events, malformed data
            # frames, OpenAI `response.failed`, Google SAFETY/RECITATION
            # blocks) all surface as ValueError from the parser; without
            # this wrapper, they would bypass RateLimitError /
            # ProviderUnavailableError / InvalidInputError classification
            # and the retry layer's typed-transient handling.
            try:
                result = parse_anthropic_stream(
                    resp.iter_bytes(),
                    provider=self.provider,
                )
            except ValueError as parse_err:
                raise InvalidInputError(
                    f"Anthropic streaming error: {parse_err}"
                ) from parse_err

        latency_ms = int((time.monotonic() - start) * 1000)
        # Re-attach latency (the parser fills 0 when not passed).
        # cycle-103 T3.2 / AC-3.2: set observed-transport flag for audit.
        _meta = dict(result.metadata or {})
        _meta["streaming"] = True
        return CompletionResult(
            content=result.content,
            tool_calls=result.tool_calls,
            thinking=result.thinking,
            usage=result.usage,
            model=result.model,
            latency_ms=latency_ms,
            provider=result.provider,
            metadata=_meta,
        )

    def _complete_nonstreaming(
        self,
        url: str,
        headers: Dict[str, str],
        body: Dict[str, Any],
    ) -> CompletionResult:
        """Legacy non-streaming path retained behind LOA_CHEVAL_DISABLE_STREAMING=1
        kill switch (Sprint 4A operator backstop)."""
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

        # cycle-103 T3.2 / AC-3.2: non-streaming path → metadata['streaming']=False.
        return CompletionResult(
            content=content,
            tool_calls=tool_calls if tool_calls else None,
            thinking=thinking,
            usage=usage,
            model=resp.get("model", "unknown"),
            latency_ms=latency_ms,
            provider=self.provider,
            metadata={"streaming": False},
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
