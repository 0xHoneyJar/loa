"""Google Gemini provider adapter — handles generateContent API (SDD 4.1).

Supports standard Gemini 2.5/3 models via generateContent endpoint.
Deep Research (Interactions API) is handled via _complete_deep_research() (Sprint 2).
"""

from __future__ import annotations

import logging
import random
import time
from typing import Any, Dict, List, Optional, Tuple

from loa_cheval.providers.base import (
    ProviderAdapter,
    enforce_context_window,
    http_post,
)
from loa_cheval.types import (
    CompletionRequest,
    CompletionResult,
    ConfigError,
    InvalidInputError,
    ProviderUnavailableError,
    RateLimitError,
    Usage,
)

logger = logging.getLogger("loa_cheval.providers.google")

# Retryable HTTP status codes (Flatline IMP-001)
_RETRYABLE_STATUS_CODES = {429, 500, 503}

# Retry config (Flatline IMP-001)
_MAX_RETRIES = 3
_INITIAL_BACKOFF_S = 1.0
_MAX_BACKOFF_S = 8.0
_JITTER_MAX_MS = 500


class GoogleAdapter(ProviderAdapter):
    """Adapter for Google Gemini API (SDD 4.1).

    Supports:
    - Standard generateContent (Gemini 2.5/3)
    - Deep Research via Interactions API (Sprint 2 stub)
    """

    def __init__(self, config):
        # type: (Any) -> None
        super().__init__(config)
        # API version pinned, configurable via model extra (Flatline SKP-003)
        self._api_version = "v1beta"

    def complete(self, request):
        # type: (CompletionRequest) -> CompletionResult
        """Route to standard or Deep Research based on api_mode."""
        model_config = self._get_model_config(request.model)

        # Check api_mode: "interactions" routes to Deep Research (Sprint 2)
        api_mode = model_config.api_mode or "standard"
        if api_mode == "interactions":
            return self._complete_deep_research(request, model_config)

        return self._complete_standard(request, model_config)

    def validate_config(self):
        # type: () -> List[str]
        """Validate Google-specific configuration."""
        errors = []
        if not self.config.endpoint:
            errors.append("Provider '%s': endpoint is required" % self.provider)
        if not self.config.auth:
            errors.append("Provider '%s': auth (GOOGLE_API_KEY) is required" % self.provider)
        if self.config.type != "google":
            errors.append("Provider '%s': type must be 'google'" % self.provider)
        return errors

    def health_check(self):
        # type: () -> bool
        """Lightweight models.list probe (Flatline SKP-003: startup self-test)."""
        try:
            auth = self._get_auth_header()
            url = self._build_url("models")
            headers = {
                "x-goog-api-key": auth,
            }
            # Use http_post for GET-like request (minimal body)
            # Actually, models.list is GET — use urllib/httpx directly
            import json as _json
            client = _detect_http_client_for_get()
            status = client(url, headers, connect_timeout=5.0, read_timeout=10.0)
            return status < 400
        except Exception:
            return False

    def _build_url(self, path):
        # type: (str) -> str
        """Centralized URL construction (Flatline SKP-003).

        Base URL + API version in one place. Override api_version via
        model_config.extra.api_version if needed.
        """
        base = self.config.endpoint.rstrip("/")
        # If endpoint already contains version (e.g., /v1beta), strip it
        # so we don't double up
        for ver in ("v1beta", "v1alpha", "v1"):
            if base.endswith("/" + ver):
                base = base[: -(len(ver) + 1)]
                break
        return "%s/%s/%s" % (base, self._api_version, path)

    # --- Standard generateContent (Tasks 1.2-1.5) ---

    def _complete_standard(self, request, model_config):
        # type: (CompletionRequest, Any) -> CompletionResult
        """Standard generateContent flow (SDD 4.1.4)."""
        enforce_context_window(request, model_config)

        # Translate messages (Task 1.2)
        system_instruction, contents = _translate_messages(
            request.messages, model_config
        )

        # Build request body
        body = {
            "contents": contents,
            "generationConfig": {
                "temperature": request.temperature,
                "maxOutputTokens": request.max_tokens,
            },
        }  # type: Dict[str, Any]

        if system_instruction:
            body["systemInstruction"] = {
                "parts": [{"text": system_instruction}]
            }

        # Thinking config (Task 1.3)
        thinking = _build_thinking_config(request.model, model_config)
        if thinking:
            body["generationConfig"].update(thinking)

        # Auth and URL (Task 1.4)
        auth = self._get_auth_header()
        headers = {
            "Content-Type": "application/json",
            "x-goog-api-key": auth,
        }
        url = self._build_url(
            "models/%s:generateContent" % request.model
        )

        # Call with retry (Flatline IMP-001)
        start = time.monotonic()
        status, resp = _call_with_retry(
            url, headers, body,
            connect_timeout=self.config.connect_timeout,
            read_timeout=self.config.read_timeout,
        )
        latency_ms = int((time.monotonic() - start) * 1000)

        # Error mapping (Task 1.5)
        if status >= 400:
            _raise_for_status(status, resp, self.provider)

        # Parse response (Task 1.4)
        return _parse_response(
            resp, request.model, latency_ms, self.provider, model_config
        )

    def _complete_deep_research(self, request, model_config):
        # type: (CompletionRequest, Any) -> CompletionResult
        """Deep Research via Interactions API (Sprint 2 — stub)."""
        raise InvalidInputError(
            "Deep Research (api_mode=interactions) is not yet implemented. "
            "Use a standard Gemini model instead."
        )


# --- Message Translation (Task 1.2) ---


def _translate_messages(messages, model_config):
    # type: (List[Dict[str, Any]], Any) -> Tuple[Optional[str], List[Dict[str, Any]]]
    """Translate OpenAI canonical messages to Gemini format (SDD 4.1.2).

    Returns (system_instruction, contents).
    """
    system_parts = []  # type: List[str]
    contents = []  # type: List[Dict[str, Any]]

    capabilities = getattr(model_config, "capabilities", [])

    for msg in messages:
        role = msg.get("role", "user")
        content = msg.get("content", "")

        if role == "system":
            if isinstance(content, str) and content.strip():
                system_parts.append(content)
            continue

        # Array content blocks are unsupported (Flatline SKP-002)
        if isinstance(content, list):
            unsupported_types = []
            for block in content:
                if isinstance(block, dict):
                    unsupported_types.append(block.get("type", "unknown"))
            msg_parts = [
                "Google Gemini adapter does not support array content blocks "
                "(found types: %s)." % ", ".join(unsupported_types),
            ]
            # Suggest fallback if capabilities indicate limitation
            if "images" not in capabilities and "vision" not in capabilities:
                msg_parts.append(
                    "This model lacks multimodal capabilities. "
                    "Consider using an OpenAI or Anthropic model for "
                    "image/multi-part content."
                )
            raise InvalidInputError(" ".join(msg_parts))

        if not isinstance(content, str) or not content.strip():
            continue

        # Map roles: assistant → model, user stays user
        gemini_role = "model" if role == "assistant" else "user"
        contents.append({
            "role": gemini_role,
            "parts": [{"text": content}],
        })

    system_instruction = "\n\n".join(system_parts) if system_parts else None
    return system_instruction, contents


# --- Thinking Config (Task 1.3) ---


def _build_thinking_config(model_id, model_config):
    # type: (str, Any) -> Optional[Dict[str, Any]]
    """Build model-aware thinking configuration (SDD 4.1.3).

    Gemini 3: thinkingLevel (string)
    Gemini 2.5: thinkingBudget (int, -1 for dynamic)
    Other: None
    """
    extra = getattr(model_config, "extra", None) or {}

    if model_id.startswith("gemini-3"):
        level = extra.get("thinking_level", "high")
        return {"thinkingConfig": {"thinkingLevel": level}}

    if model_id.startswith("gemini-2.5"):
        budget = extra.get("thinking_budget", -1)
        if budget == 0:
            return None  # Disable thinking
        return {"thinkingConfig": {"thinkingBudget": budget}}

    return None


# --- Response Parsing (Task 1.4) ---


def _parse_response(resp, model_id, latency_ms, provider, model_config):
    # type: (Dict[str, Any], str, int, str, Any) -> CompletionResult
    """Parse Gemini generateContent response (SDD 4.1.5).

    Receives explicit model_id — no closure over request state.
    """
    candidates = resp.get("candidates", [])
    if not candidates:
        raise InvalidInputError(
            "Gemini API returned empty candidates list — "
            "check model availability and request validity."
        )

    candidate = candidates[0]
    finish_reason = candidate.get("finishReason", "")

    # Safety block (SDD 4.1.6)
    if finish_reason == "SAFETY":
        ratings = candidate.get("safetyRatings", [])
        ratings_str = ", ".join(
            "%s=%s" % (r.get("category", "?"), r.get("probability", "?"))
            for r in ratings
        )
        raise InvalidInputError(
            "Response blocked by safety filters: %s" % ratings_str
        )

    if finish_reason == "RECITATION":
        raise InvalidInputError(
            "Response blocked due to recitation (potential copyright content)."
        )

    if finish_reason == "MAX_TOKENS":
        logger.warning(
            "google_response_truncated model=%s reason=MAX_TOKENS",
            model_id,
        )

    # Handle unknown finish reasons gracefully (Flatline SKP-001)
    known_reasons = {"STOP", "MAX_TOKENS", "SAFETY", "RECITATION", "OTHER", ""}
    if finish_reason and finish_reason not in known_reasons:
        logger.warning(
            "google_unknown_finish_reason model=%s reason=%s",
            model_id,
            finish_reason,
        )

    # Extract content and thinking parts
    parts = candidate.get("content", {}).get("parts", [])
    text_parts = []  # type: List[str]
    thinking_parts = []  # type: List[str]

    for part in parts:
        text = part.get("text", "")
        if not text:
            continue
        if part.get("thought", False):
            thinking_parts.append(text)
        else:
            text_parts.append(text)

    content = "\n".join(text_parts)
    thinking = "\n".join(thinking_parts) if thinking_parts else None

    # Parse usage (Flatline SKP-001, SKP-007)
    usage_meta = resp.get("usageMetadata")
    if usage_meta:
        input_tokens = usage_meta.get("promptTokenCount", 0)
        output_tokens = usage_meta.get("candidatesTokenCount", 0)
        reasoning_tokens = usage_meta.get("thoughtsTokenCount", 0)

        # Warn on partial metadata (Flatline SKP-007)
        if "thoughtsTokenCount" not in usage_meta and thinking_parts:
            logger.warning(
                "google_partial_usage model=%s missing=thoughtsTokenCount",
                model_id,
            )

        usage = Usage(
            input_tokens=input_tokens,
            output_tokens=output_tokens,
            reasoning_tokens=reasoning_tokens,
            source="actual",
        )
    else:
        # Conservative estimate (Flatline SKP-007)
        logger.warning(
            "google_missing_usage model=%s using_estimate=true",
            model_id,
        )
        est_input = int(len(content) / 3.5) if content else 0
        usage = Usage(
            input_tokens=est_input,
            output_tokens=int(len(content) / 3.5) if content else 0,
            reasoning_tokens=0,
            source="estimated",
        )

    logger.debug(
        "google_complete model=%s latency_ms=%d input_tokens=%d output_tokens=%d",
        model_id,
        latency_ms,
        usage.input_tokens,
        usage.output_tokens,
    )

    return CompletionResult(
        content=content,
        tool_calls=None,  # Tool calls not supported in standard path yet
        thinking=thinking,
        usage=usage,
        model=model_id,
        latency_ms=latency_ms,
        provider=provider,
    )


# --- Error Mapping (Task 1.5) ---


def _raise_for_status(status, resp, provider):
    # type: (int, Dict[str, Any], str) -> None
    """Map Google API HTTP status to Hounfour error types (SDD 4.1.6)."""
    msg = _extract_error_message(resp)

    if status == 400:
        raise InvalidInputError("Google API error (400): %s" % msg)
    if status == 401:
        raise ConfigError("Google API authentication failed (401): %s" % msg)
    if status == 403:
        raise ProviderUnavailableError(provider, "Permission denied (403): %s" % msg)
    if status == 404:
        raise InvalidInputError("Google API model not found (404): %s" % msg)
    if status == 429:
        raise RateLimitError(provider)
    if status >= 500:
        raise ProviderUnavailableError(provider, "HTTP %d: %s" % (status, msg))

    # Unknown status — treat as provider unavailable
    raise ProviderUnavailableError(provider, "HTTP %d: %s" % (status, msg))


def _extract_error_message(resp):
    # type: (Dict[str, Any]) -> str
    """Extract error message from Google API error response."""
    if isinstance(resp, dict):
        error = resp.get("error", {})
        if isinstance(error, dict):
            return error.get("message", str(resp))
        return str(error)
    return str(resp)


# --- Retry Logic (Flatline IMP-001) ---


def _call_with_retry(url, headers, body, connect_timeout=10.0, read_timeout=120.0):
    # type: (str, Dict[str, str], Dict[str, Any], float, float) -> Tuple[int, Dict[str, Any]]
    """HTTP POST with exponential backoff + jitter for retryable status codes."""
    last_status = 0
    last_resp = {}  # type: Dict[str, Any]

    for attempt in range(_MAX_RETRIES + 1):
        status, resp = http_post(
            url, headers, body,
            connect_timeout=connect_timeout,
            read_timeout=read_timeout,
        )

        if status not in _RETRYABLE_STATUS_CODES:
            return status, resp

        last_status = status
        last_resp = resp

        if attempt < _MAX_RETRIES:
            backoff = min(
                _INITIAL_BACKOFF_S * (2 ** attempt),
                _MAX_BACKOFF_S,
            )
            jitter = random.uniform(0, _JITTER_MAX_MS / 1000.0)
            delay = backoff + jitter
            logger.warning(
                "google_retry attempt=%d/%d status=%d backoff=%.2fs",
                attempt + 1,
                _MAX_RETRIES,
                status,
                delay,
            )
            time.sleep(delay)

    return last_status, last_resp


# --- Health Check Helper ---


def _detect_http_client_for_get():
    # type: () -> Any
    """Return a callable that performs HTTP GET and returns status code."""
    try:
        import httpx

        def _get_httpx(url, headers, connect_timeout=5.0, read_timeout=10.0):
            # type: (str, Dict[str, str], float, float) -> int
            timeout = httpx.Timeout(
                connect=connect_timeout,
                read=read_timeout,
                write=10.0,
                pool=5.0,
            )
            resp = httpx.get(url, headers=headers, timeout=timeout)
            return resp.status_code

        return _get_httpx
    except ImportError:
        pass

    def _get_urllib(url, headers, connect_timeout=5.0, read_timeout=10.0):
        # type: (str, Dict[str, str], float, float) -> int
        import urllib.request
        import urllib.error

        req = urllib.request.Request(url, headers=headers, method="GET")
        total_timeout = connect_timeout + read_timeout
        try:
            with urllib.request.urlopen(req, timeout=total_timeout) as resp:
                return resp.status
        except urllib.error.HTTPError as e:
            return e.code

    return _get_urllib
