"""OpenAI provider adapter — handles OpenAI and OpenAI-compatible APIs (SDD §4.2.5).

cycle-095 Sprint 1 (SDD §5.2-5.4) replaces the name-regex routing decision with
a registry-metadata read (`endpoint_family`), expands `_build_responses_body`
to handle full multi-message conversations + tools, and rewrites
`_parse_responses_response` as a six-shape normalizer matching PRD §3.1 and
SDD §5.4 — multi-block text, tool/function call, reasoning summary, refusal,
empty output, and partial/truncated.
"""

from __future__ import annotations

import json
import logging
import os
import time
from typing import Any, Dict, List, Optional

from loa_cheval.providers.base import (
    ProviderAdapter,
    _streaming_disabled,
    enforce_context_window,
    http_post,
    http_post_stream,
)
from loa_cheval.providers.openai_streaming import (
    parse_openai_chat_stream,
    parse_openai_responses_stream,
)
from loa_cheval.types import (
    CompletionRequest,
    CompletionResult,
    InvalidConfigError,
    InvalidInputError,
    ModelConfig,
    ProviderUnavailableError,
    RateLimitError,
    UnsupportedResponseShapeError,
    Usage,
)

logger = logging.getLogger("loa_cheval.providers.openai")

# Supported API surface (SDD §4.2.5) — NO streaming, NO JSON mode in MVP.
# `max_output_tokens` was added in Sprint 1 for the /v1/responses path.
_SUPPORTED_PARAMS = {
    "messages",
    "model",
    "temperature",
    "max_tokens",
    "max_completion_tokens",
    "max_output_tokens",
    "tools",
    "tool_choice",
}

_ALLOWED_ENDPOINT_FAMILIES = ("chat", "responses")


class OpenAIAdapter(ProviderAdapter):
    """Adapter for OpenAI and OpenAI-compatible APIs (SDD §4.2.3, §4.2.5)."""

    # cycle-095 Sprint 1: once-per-process WARN deduplication for unknown
    # /v1/responses output[].type values seen under degrade policy. Stored
    # at class-level so all OpenAIAdapter instances in one process share the
    # dedup set — that's the documented intent ("once per unique unknown
    # type per process"). Tests must call OpenAIAdapter._unknown_shape_warned
    # .clear() in fixtures to avoid cross-test bleed. Production cheval is
    # single-threaded CLI-driven (loader docstring); under multi-threaded
    # use, the worst case is a duplicate WARN, not data loss.
    _unknown_shape_warned: set[str] = set()

    def _route_decision(self, model_config: ModelConfig, model_id: str) -> str:
        """Return 'chat' or 'responses' from the model_config metadata.

        cycle-095 Sprint 1 (SDD §5.2): defense-in-depth at request time. The
        primary gate is config-load validation in loader.py, which rejects
        configs that lack `endpoint_family`. This raise should be unreachable
        in practice — but if it fires, it tells the operator exactly which
        model is malformed instead of producing an opaque HTTP 400.
        """
        family = getattr(model_config, "endpoint_family", None)
        if family is None:
            raise InvalidConfigError(
                f"OpenAI model '{model_id}' lacks required 'endpoint_family' field. "
                f"Add 'endpoint_family: chat' or 'endpoint_family: responses' to "
                f".claude/defaults/model-config.yaml (or your override). "
                f"For one-shot operator backstop, set "
                f"LOA_LEGACY_ENDPOINT_FAMILY_DEFAULT=chat."
            )
        if family not in _ALLOWED_ENDPOINT_FAMILIES:
            raise InvalidConfigError(
                f"OpenAI model '{model_id}' has invalid endpoint_family={family!r}. "
                f"Allowed values: {', '.join(_ALLOWED_ENDPOINT_FAMILIES)}."
            )
        return family

    def complete(self, request: CompletionRequest) -> CompletionResult:
        """Send completion request to OpenAI API, return normalized result.

        Sprint 4A (cycle-102, AC-4.5e): streaming is the default path for both
        /chat/completions and /v1/responses endpoint families. The
        non-streaming path is preserved behind LOA_CHEVAL_DISABLE_STREAMING=1
        as a one-shot operator backstop. Streaming eliminates KF-002 layer 3
        (>60s-wait-for-first-byte → RemoteProtocolError) by construction.
        """
        model_config = self._get_model_config(request.model)

        # Context window enforcement (SDD §4.2.4)
        enforce_context_window(request, model_config)

        # cycle-095 Sprint 1: registry-metadata-driven endpoint routing.
        family = self._route_decision(model_config, request.model)

        # Build headers
        auth = self._get_auth_header()
        headers = {
            "Content-Type": "application/json",
            "Authorization": f"Bearer {auth}",
        }

        if family == "responses":
            url = f"{self.config.endpoint}/responses"
            body = self._build_responses_body(request, model_config)
        else:
            url = f"{self.config.endpoint}/chat/completions"
            body = self._build_chat_body(request, model_config)

        # Sprint 4A DISS-001 closure: centralized kill-switch detection so
        # the adapter routing and the MODELINV audit field stay consistent.
        if _streaming_disabled():
            return self._complete_nonstreaming(url, headers, body, family)
        return self._complete_streaming(url, headers, body, family)

    def _complete_streaming(
        self,
        url: str,
        headers: Dict[str, str],
        body: Dict[str, Any],
        family: str,
    ) -> CompletionResult:
        """Sprint 4A streaming default path for both endpoint families."""
        body = dict(body)
        body["stream"] = True
        # Request usage in the final chunk for /chat/completions (the
        # `stream_options.include_usage` flag). The /v1/responses path
        # carries usage on `response.completed` by default — no flag.
        if family != "responses":
            body["stream_options"] = {"include_usage": True}

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
                err_bytes = b"".join(resp.iter_bytes())
                try:
                    err_json = json.loads(err_bytes.decode("utf-8", errors="replace"))
                except Exception:
                    err_json = {
                        "error": {
                            "message": err_bytes.decode("utf-8", errors="replace")[:500]
                        }
                    }
                if status == 429:
                    raise RateLimitError(self.provider)
                if status >= 500:
                    raise ProviderUnavailableError(
                        self.provider,
                        f"HTTP {status}: {_extract_error_message(err_json)}",
                    )
                raise InvalidInputError(
                    f"OpenAI API error (HTTP {status}): {_extract_error_message(err_json)}"
                )

            # Sprint 4A cycle-3 (BF-001): map parser-raised ValueError to
            # typed adapter exception so the retry layer routes correctly.
            # Covers OpenAI `response.failed` events, top-level `{"error":...}`
            # frames (BF-002), and malformed data frames (BF-006).
            try:
                if family == "responses":
                    result = parse_openai_responses_stream(
                        resp.iter_bytes(), provider=self.provider
                    )
                else:
                    result = parse_openai_chat_stream(
                        resp.iter_bytes(), provider=self.provider
                    )
            except ValueError as parse_err:
                raise InvalidInputError(
                    f"OpenAI streaming error: {parse_err}"
                ) from parse_err

        latency_ms = int((time.monotonic() - start) * 1000)
        return CompletionResult(
            content=result.content,
            tool_calls=result.tool_calls,
            thinking=result.thinking,
            usage=result.usage,
            model=result.model,
            latency_ms=latency_ms,
            provider=result.provider,
            metadata=result.metadata,
        )

    def _complete_nonstreaming(
        self,
        url: str,
        headers: Dict[str, str],
        body: Dict[str, Any],
        family: str,
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
        if family == "responses":
            return self._parse_responses_response(resp, latency_ms)
        return self._parse_response(resp, latency_ms)

    def _build_chat_body(self, request: CompletionRequest, model_config: ModelConfig) -> Dict[str, Any]:
        """Build request body for Chat Completions API."""
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

        return body

    def _build_responses_body(
        self,
        request: CompletionRequest,
        model_config: ModelConfig,
    ) -> Dict[str, Any]:
        """Build request body for /v1/responses (cycle-095 Sprint 1, SDD §5.3).

        Transformations relative to /v1/chat/completions:
          - system → top-level `instructions` (joined with \\n\\n if multiple)
          - max_tokens → max_output_tokens
          - tool messages → typed function_call_output input blocks (call_id)
          - simple-string optimization: single user message + no tool results
            collapses to `input: <string>` (matches probe evidence shape)
        """
        instructions: Optional[str] = None
        input_blocks: List[Dict[str, Any]] = []
        has_tool_results = any(m.get("role") == "tool" for m in request.messages)

        for msg in request.messages:
            role = msg.get("role", "")
            content = msg.get("content", "")

            if role == "system":
                instructions = (
                    f"{instructions}\n\n{content}" if instructions else content
                )
            elif role == "tool":
                if isinstance(content, str):
                    output_str = content
                else:
                    try:
                        output_str = json.dumps(content)
                    except (TypeError, ValueError):
                        output_str = str(content)
                input_blocks.append(
                    {
                        "type": "function_call_output",
                        "call_id": msg.get("tool_call_id", ""),
                        "output": output_str,
                    }
                )
            else:
                # user / assistant
                input_blocks.append(
                    {
                        "type": "message",
                        "role": role,
                        "content": content,
                    }
                )

        body: Dict[str, Any] = {"model": request.model}

        # Optimization: single user message + no tool results → simple-string input.
        # Matches the shape from the live probe evidence (preflight.md:9-25).
        if (
            len(input_blocks) == 1
            and not has_tool_results
            and input_blocks[0]["type"] == "message"
            and isinstance(input_blocks[0]["content"], str)
        ):
            body["input"] = input_blocks[0]["content"]
        else:
            body["input"] = input_blocks

        if instructions:
            body["instructions"] = instructions

        body["max_output_tokens"] = request.max_tokens

        # cycle-102 sprint-1F (KF-002 mitigation, openai/openai-python#2546):
        # force /v1/responses to emit a text message item even when reasoning
        # consumes the visible-output budget. Per upstream characterization
        # ("normal behavior" per #2546 closing comment), /v1/responses returns
        # ONLY a ResponseReasoningItem when reasoning exhausts max_output_tokens;
        # the SDK's `output_text` aggregator then concatenates an empty string
        # because there's no message item to aggregate from. The `text.format`
        # parameter forces the model to also emit a text message, eliminating
        # the empty-output-text failure mode at any scale.
        #
        # This is HARMLESS when not in the empty-content scenario — the model
        # returns the same text content it would have returned anyway, just
        # also bound to a typed ResponseOutputMessage (which is what the
        # /v1/responses parser already expects). No semantic change for
        # successful calls; only adds a safety net for the empty-content edge.
        #
        # Operator opt-out: set hounfour.openai_no_text_format=true in
        # .loa.config.yaml (or omit; this default-on fix only adds bytes to
        # the request, never removes capability).
        body["text"] = {"format": {"type": "text"}}

        # Wire-protocol parameter gates: respect params.temperature_supported.
        # Defaults to True if absent (preserves existing behavior). Mirrors the
        # anthropic_adapter pattern from #641.
        params = model_config.params if isinstance(model_config.params, dict) else {}
        if request.temperature is not None and params.get("temperature_supported", True):
            body["temperature"] = request.temperature

        if request.tools:
            body["tools"] = request.tools  # Same shape as /v1/chat/completions
        if request.tool_choice:
            body["tool_choice"] = request.tool_choice

        return body

    def _parse_responses_response(
        self,
        resp: Dict[str, Any],
        latency_ms: int,
    ) -> CompletionResult:
        """Six-shape /v1/responses normalizer (PRD §3.1, SDD §5.4).

        Shapes handled:
          1. Multi-block text (output[].type == 'message' with output_text parts)
          2. Tool/function call (output[].type in {'tool_call','function_call'})
          3. Reasoning summary (output[].type == 'reasoning')
          4. Refusal (top-level type='refusal' OR refusal part inside message)
          5. Empty output (no content + no tool calls — WARN, do not raise)
          6. Truncated (incomplete_details.reason set — metadata flag)

        Unknown shapes follow the policy in SDD §5.4.1: strict (default) raises
        UnsupportedResponseShapeError; `degrade` skips the unknown block,
        emits a once-per-unique-type WARN, and surfaces metadata flags so
        callers can detect partial results.
        """
        output = resp.get("output", []) or []
        incomplete = resp.get("incomplete_details") or {}
        incomplete_reason = (
            incomplete.get("reason") if isinstance(incomplete, dict) else None
        )

        text_parts: List[str] = []
        thinking_parts: List[str] = []
        tool_calls: List[Dict[str, Any]] = []
        refusal_text: Optional[str] = None
        metadata: Dict[str, Any] = {}

        unknown_policy = self._unknown_shape_policy()

        for item in output:
            if not isinstance(item, dict):
                continue
            item_type = item.get("type", "")

            if item_type == "message":
                # Shape 1: multi-block text. Shape 4 may also live here as a
                # `refusal` part inside a message item.
                for part in item.get("content", []) or []:
                    if not isinstance(part, dict):
                        continue
                    ptype = part.get("type", "")
                    if ptype == "output_text":
                        text_parts.append(part.get("text", "") or "")
                    elif ptype == "refusal":
                        # The refusal text typically lives in either `refusal`
                        # or `text` depending on minor API revision; check both.
                        refusal_text = part.get("refusal") or part.get("text") or ""

            elif item_type in ("tool_call", "function_call"):
                # Shape 2: tool-use. Normalize to canonical CompletionResult.tool_calls.
                # /v1/responses splits identifiers: `id` is the item ID
                # (e.g., "fc_001"); `call_id` is the threading ID (e.g.,
                # "call_abc123") that the next request references via
                # tool_call_id → call_id mapping in _build_responses_body.
                # /v1/chat/completions has only one `id` (which is the call_id).
                # Canonical CompletionResult.tool_calls[].id MUST be the
                # threading ID, so prefer call_id when both are present.
                tool_calls.append(
                    {
                        "id": item.get("call_id") or item.get("id", ""),
                        "type": "function",
                        "function": {
                            "name": item.get("name", ""),
                            "arguments": item.get("arguments", "{}"),
                        },
                    }
                )

            elif item_type == "reasoning":
                # Shape 3: visible reasoning summary. Distinct from the
                # invisible reasoning_tokens count — that's billing-only.
                for sblock in item.get("summary", []) or []:
                    if isinstance(sblock, dict):
                        text = sblock.get("text") or ""
                        if text:
                            thinking_parts.append(text)

            elif item_type == "refusal":
                # Shape 4 — top-level variant. The refusal payload key has
                # varied across minor API revisions; accept either.
                refusal_text = item.get("refusal") or item.get("text") or ""

            else:
                # Forward-compat: unknown shape policy (SDD §5.4.1).
                if unknown_policy == "degrade":
                    if item_type not in self._unknown_shape_warned:
                        logger.warning(
                            "OpenAI /v1/responses returned unknown output[].type=%r "
                            "(degrading per policy)",
                            item_type,
                        )
                        self._unknown_shape_warned.add(item_type)
                    metadata.setdefault("unknown_shapes", []).append(item_type)
                    metadata["unknown_shapes_present"] = True
                    continue
                raise UnsupportedResponseShapeError(
                    f"Unknown /v1/responses output[].type: {item_type!r}. "
                    f"Adapter does not support this shape; file a Loa bug. "
                    f"For one-shot graceful degradation, set "
                    f"hounfour.experimental.responses_unknown_shape_policy: degrade."
                )

        # Shape 4 handling — refusal sets content + metadata flag, does NOT raise.
        if refusal_text is not None:
            content = refusal_text
            metadata["refused"] = True
        else:
            content = "\n\n".join(text_parts)

        # Shape 5 — empty output. Warn, do not raise; caller may inspect.
        if not content and not tool_calls:
            logger.warning(
                "OpenAI /v1/responses returned empty output (model=%s)",
                resp.get("model"),
            )

        # Shape 6 — partial / truncated.
        if incomplete_reason:
            metadata["truncated"] = True
            metadata["truncation_reason"] = incomplete_reason

        # Token accounting. SDD §5.5: output_tokens is INCLUSIVE total
        # (visible + reasoning). Cost-ledger bills on output_tokens ONLY —
        # never sum with reasoning_tokens.
        usage_data = resp.get("usage", {}) or {}
        output_tokens = usage_data.get("output_tokens", 0) or 0
        reasoning_tokens = (
            (usage_data.get("output_tokens_details") or {}).get("reasoning_tokens", 0)
            or 0
        )
        usage = Usage(
            input_tokens=usage_data.get("input_tokens", 0) or 0,
            output_tokens=output_tokens,
            reasoning_tokens=reasoning_tokens,
            source="actual" if usage_data else "estimated",
        )

        # PRD §3.1 edge-case: visible-token estimate vs reported output_tokens.
        # If the divergence exceeds 5%, log WARN — likely a parser miss or a
        # new API revision adding hidden output channels.
        if output_tokens > 0:
            visible_estimate = self._estimate_visible_tokens(
                content, tool_calls, thinking_parts
            )
            visible_reported = output_tokens - reasoning_tokens
            denom = max(output_tokens, 1)
            divergence = abs(visible_estimate - visible_reported) / denom
            if divergence > 0.05:
                logger.warning(
                    "Token accounting divergence: visible≈%d, reported=%d "
                    "(reasoning=%d) for model=%s — divergence=%.1f%%",
                    visible_estimate,
                    output_tokens,
                    reasoning_tokens,
                    resp.get("model"),
                    divergence * 100,
                )

        return CompletionResult(
            content=content,
            tool_calls=tool_calls if tool_calls else None,
            thinking="\n".join(thinking_parts) if thinking_parts else None,
            usage=usage,
            model=resp.get("model", "unknown"),
            latency_ms=latency_ms,
            provider=self.provider,
            metadata=metadata,
        )

    def _unknown_shape_policy(self) -> str:
        """Read the unknown-shape policy from env var or hounfour config.

        Precedence:
          1. LOA_RESPONSES_UNKNOWN_SHAPE_POLICY env var (operator escape hatch
             usable in tests + interactive debugging without rebuilding config)
          2. hounfour.experimental.responses_unknown_shape_policy
          3. Default: 'strict' (PRD locked default)
        """
        env = os.environ.get("LOA_RESPONSES_UNKNOWN_SHAPE_POLICY", "").strip().lower()
        if env in ("strict", "degrade"):
            return env

        # Lazy-import to avoid a config↔providers import cycle. The loader
        # imports nothing from providers; providers may safely import loader
        # when needed.
        try:
            from loa_cheval.config.loader import get_config

            cfg = get_config()
            policy = (
                (cfg.get("experimental") or {}).get("responses_unknown_shape_policy")
                or "strict"
            )
            policy = str(policy).strip().lower()
            if policy in ("strict", "degrade"):
                return policy
        except Exception:
            # If config cannot be loaded for any reason, fail safe to strict.
            pass
        return "strict"

    def _estimate_visible_tokens(
        self,
        content: str,
        tool_calls: Optional[List[Dict[str, Any]]],
        thinking_parts: List[str],
    ) -> int:
        """Approximate visible-token count for divergence sanity check.

        Uses the same chars/3.5 heuristic as base.estimate_tokens — we don't
        need exact counts here, only a "much-too-low / much-too-high" signal.
        """
        text = content or ""
        if tool_calls:
            for tc in tool_calls:
                fn = (tc or {}).get("function") or {}
                text += fn.get("name", "") or ""
                text += fn.get("arguments", "") or ""
        if thinking_parts:
            text += "\n".join(thinking_parts)
        if not text:
            return 0
        return int(len(text) / 3.5)

    def _parse_response(self, resp: Dict[str, Any], latency_ms: int) -> CompletionResult:
        """Extract CompletionResult from OpenAI /v1/chat/completions response."""
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
