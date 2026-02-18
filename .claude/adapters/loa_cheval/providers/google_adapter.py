"""Google Gemini provider adapter — handles generateContent + Interactions API (SDD 4.1).

Supports:
  - Standard Gemini 2.5/3 models via generateContent endpoint
  - Deep Research via Interactions API (blocking-poll and non-blocking modes)
"""

from __future__ import annotations

import json as _json
import logging
import os
import random
import re
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
            # models.list is GET — use urllib/httpx directly
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
        from loa_cheval.providers.concurrency import FLockSemaphore

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

        # Call with retry + concurrency control (Flatline IMP-001, Task 2.4)
        with FLockSemaphore("google-standard", max_concurrent=5):
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
        # Pass input text length for token estimation when usageMetadata is absent
        input_text_len = sum(
            len(m.get("content", "")) for m in request.messages
            if isinstance(m.get("content"), str)
        )
        return _parse_response(
            resp, request.model, latency_ms, self.provider, model_config,
            input_text_length=input_text_len,
        )

    def _complete_deep_research(self, request, model_config):
        # type: (CompletionRequest, Any) -> CompletionResult
        """Deep Research via Interactions API — blocking-poll (SDD 4.2.1)."""
        from loa_cheval.providers.concurrency import FLockSemaphore

        extra = getattr(model_config, "extra", None) or {}
        poll_interval = extra.get("polling_interval_s", 5)
        max_poll_time = extra.get("max_poll_time_s", 600)
        store = extra.get("store", False)

        # Context window enforcement (Review CONCERN-2)
        enforce_context_window(request, model_config)

        # Concurrency control (Task 2.4) — extended timeout for DR queue depth
        with FLockSemaphore("google-deep-research", max_concurrent=3, timeout=max_poll_time):
            # Create interaction
            interaction = self.create_interaction(
                request, model_config, store=store,
            )
            interaction_id = interaction.get("name", "")

            if not interaction_id:
                raise InvalidInputError(
                    "Deep Research createInteraction returned no interaction ID"
                )

            # Persist metadata for recovery (Flatline SKP-009)
            _persist_interaction(interaction_id, request.model)

            # Poll until complete
            start = time.monotonic()
            result = self.poll_interaction(
                interaction_id, model_config,
                poll_interval=poll_interval,
                timeout=max_poll_time,
            )

            latency_ms = int((time.monotonic() - start) * 1000)

            # Normalize output
            normalized = _normalize_citations(result.get("output", ""))
            content = _json.dumps(normalized)

            # Parse usage
            usage_meta = result.get("usageMetadata", {})
            usage = Usage(
                input_tokens=usage_meta.get("promptTokenCount", 0),
                output_tokens=usage_meta.get("candidatesTokenCount", 0),
                reasoning_tokens=0,
                source="actual" if usage_meta else "estimated",
            )

            return CompletionResult(
                content=content,
                tool_calls=None,
                thinking=None,
                usage=usage,
                model=request.model,
                latency_ms=latency_ms,
                provider=self.provider,
                interaction_id=interaction_id,
            )

    def create_interaction(self, request, model_config, store=False):
        # type: (CompletionRequest, Any, bool) -> Dict[str, Any]
        """Create a Deep Research interaction (non-blocking start)."""
        auth = self._get_auth_header()
        headers = {
            "Content-Type": "application/json",
            "x-goog-api-key": auth,
        }

        # Extract user prompt from messages
        user_content = ""
        for msg in request.messages:
            if msg.get("role") == "user":
                content = msg.get("content", "")
                if isinstance(content, str):
                    user_content = content
                    break

        body = {
            "query": user_content,
            "background": True,
            "store": store,
        }

        url = self._build_url(
            "models/%s:createInteraction" % request.model
        )

        status, resp = _call_with_retry(
            url, headers, body,
            connect_timeout=self.config.connect_timeout,
            read_timeout=self.config.read_timeout,
        )

        if status >= 400:
            _raise_for_status(status, resp, self.provider)

        return resp

    def poll_interaction(self, interaction_id, model_config,
                         poll_interval=5, timeout=600):
        # type: (str, Any, int, int) -> Dict[str, Any]
        """Poll a Deep Research interaction until completion."""
        auth = self._get_auth_header()
        headers = {
            "x-goog-api-key": auth,
        }

        start = time.monotonic()
        last_log = start
        attempt = 0

        # Completed state names (case-insensitive, schema-tolerant)
        completed_states = {"completed", "done", "succeeded"}
        failed_states = {"failed", "error", "cancelled"}

        while True:
            elapsed = time.monotonic() - start
            if elapsed >= timeout:
                raise TimeoutError(
                    "Deep Research poll timed out after %ds for %s"
                    % (timeout, interaction_id)
                )

            # GET poll request
            url = self._build_url(interaction_id)
            try:
                poll_status, poll_resp = _poll_get(
                    url, headers,
                    connect_timeout=5.0,
                    read_timeout=30.0,
                )
            except Exception as exc:
                attempt += 1
                if attempt > _MAX_RETRIES:
                    raise ProviderUnavailableError(
                        self.provider,
                        "Poll failed after %d attempts: %s" % (attempt, exc),
                    )
                time.sleep(min(poll_interval * (2 ** attempt), 30))
                continue

            # Retry on transient errors (Flatline SKP-009)
            if poll_status in _RETRYABLE_STATUS_CODES:
                attempt += 1
                if attempt > _MAX_RETRIES:
                    _raise_for_status(poll_status, poll_resp, self.provider)
                delay = min(poll_interval * (2 ** attempt), 30)
                logger.warning(
                    "dr_poll_retry attempt=%d status=%d delay=%.1fs",
                    attempt, poll_status, delay,
                )
                time.sleep(delay)
                continue

            if poll_status >= 400:
                _raise_for_status(poll_status, poll_resp, self.provider)

            attempt = 0  # Reset on success

            # Schema-tolerant status check (accepts "status" or "state")
            state = (
                poll_resp.get("status", "")
                or poll_resp.get("state", "")
            ).lower()

            if state in completed_states:
                return poll_resp

            if state in failed_states:
                err_msg = _extract_error_message(poll_resp)
                raise ProviderUnavailableError(
                    self.provider,
                    "Deep Research failed: %s" % err_msg,
                )

            # Unknown status — log warning, continue (Flatline SKP-009)
            if state and state not in {"processing", "pending", "running", "queued"}:
                logger.warning(
                    "dr_unknown_status interaction=%s status=%s",
                    interaction_id, state,
                )

            # Progress log every 30s (no prompt content — IMP-009)
            now = time.monotonic()
            if now - last_log >= 30:
                logger.info(
                    "dr_polling interaction=%s elapsed=%.0fs status=%s",
                    interaction_id, elapsed, state,
                )
                last_log = now

            time.sleep(poll_interval)

    def cancel_interaction(self, interaction_id):
        # type: (str) -> bool
        """Best-effort cancellation of a Deep Research interaction.

        Idempotent — cancelling already-cancelled is a no-op (Flatline SKP-009).
        Returns True if cancellation accepted, False otherwise.
        """
        auth = self._get_auth_header()
        headers = {
            "Content-Type": "application/json",
            "x-goog-api-key": auth,
        }

        url = self._build_url("%s:cancel" % interaction_id)

        try:
            status, resp = http_post(
                url, headers, {},
                connect_timeout=5.0,
                read_timeout=10.0,
            )
            # 200 = cancelled, 400 = already done (idempotent)
            return status < 500
        except Exception:
            return False


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


def _parse_response(resp, model_id, latency_ms, provider, model_config,
                    input_text_length=0):
    # type: (Dict[str, Any], str, int, str, Any, int) -> CompletionResult
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
        # Conservative estimate (Flatline SKP-007, BB-404)
        # Input estimated from input messages, output from response content
        logger.warning(
            "google_missing_usage model=%s using_estimate=true",
            model_id,
        )
        est_input = int(input_text_length / 3.5) if input_text_length else 0
        est_output = int(len(content) / 3.5) if content else 0
        usage = Usage(
            input_tokens=est_input,
            output_tokens=est_output,
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


# --- Citation Normalization (Task 2.2) ---


def _normalize_citations(raw_output):
    # type: (str) -> Dict[str, Any]
    """Extract structured citations from Deep Research output (SDD 4.2.3).

    Never fails — returns raw_output with empty citations on extraction failure.
    """
    if not raw_output:
        return {"summary": "", "claims": [], "citations": [], "raw_output": ""}

    citations = []  # type: List[Dict[str, str]]

    try:
        # Extract markdown citation references [N]
        ref_pattern = re.compile(r"\[(\d+)\]")
        ref_numbers = set(ref_pattern.findall(raw_output))

        # Extract DOI patterns
        doi_pattern = re.compile(r"10\.\d{4,}/[^\s,)]+")
        dois = doi_pattern.findall(raw_output)

        # Extract URLs
        url_pattern = re.compile(
            r"https?://[^\s<>\"'\]),]+[^\s<>\"'\]),.]"
        )
        urls = url_pattern.findall(raw_output)

        for ref in sorted(ref_numbers, key=int):
            citations.append({"type": "reference", "id": ref})

        for doi in dois:
            citations.append({"type": "doi", "value": doi})

        for url in urls:
            citations.append({"type": "url", "value": url})

    except Exception:
        logger.warning("dr_citation_extraction_failed")

    if not citations:
        logger.warning("dr_no_citations_extracted")

    return {
        "summary": raw_output[:500] if len(raw_output) > 500 else raw_output,
        "claims": [],
        "citations": citations,
        "raw_output": raw_output,
    }


# --- Interaction Persistence (Flatline SKP-009) ---


_INTERACTIONS_FILE = ".run/.dr-interactions.json"


def _persist_interaction(interaction_id, model):
    # type: (str, str) -> None
    """Save interaction metadata for crash recovery (flock-protected)."""
    import fcntl

    try:
        os.makedirs(os.path.dirname(_INTERACTIONS_FILE) or ".", exist_ok=True)
        lock_path = _INTERACTIONS_FILE + ".lock"

        with open(lock_path, "w") as lock_f:
            fcntl.flock(lock_f, fcntl.LOCK_EX)
            try:
                data = {}  # type: Dict[str, Any]
                if os.path.exists(_INTERACTIONS_FILE):
                    with open(_INTERACTIONS_FILE, "r") as f:
                        data = _json.load(f)

                data[interaction_id] = {
                    "model": model,
                    "start_time": time.time(),
                    "pid": os.getpid(),
                }

                with open(_INTERACTIONS_FILE, "w") as f:
                    _json.dump(data, f, indent=2)
            finally:
                fcntl.flock(lock_f, fcntl.LOCK_UN)
    except Exception:
        logger.warning("dr_persist_failed interaction=%s", interaction_id)


def _load_persisted_interactions():
    # type: () -> Dict[str, Any]
    """Load persisted interaction metadata for recovery."""
    try:
        if os.path.exists(_INTERACTIONS_FILE):
            with open(_INTERACTIONS_FILE, "r") as f:
                return _json.load(f)
    except (ValueError, FileNotFoundError, OSError):
        pass
    return {}


# --- Poll GET Helper ---


def _poll_get(url, headers, connect_timeout=5.0, read_timeout=30.0):
    # type: (str, Dict[str, str], float, float) -> Tuple[int, Dict[str, Any]]
    """HTTP GET that returns (status_code, response_json)."""
    try:
        import httpx

        timeout = httpx.Timeout(
            connect=connect_timeout,
            read=read_timeout,
            write=10.0,
            pool=5.0,
        )
        try:
            resp = httpx.get(url, headers=headers, timeout=timeout)
            return resp.status_code, resp.json()
        except httpx.HTTPError as e:
            logger.warning("poll_get_httpx_error url=%s error=%s", url, e)
            return 503, {"error": {"message": str(e)}}
        except (ValueError, _json.JSONDecodeError) as e:
            logger.warning("poll_get_json_error url=%s error=%s", url, e)
            return 503, {"error": {"message": "JSON decode error: %s" % e}}
    except ImportError:
        pass

    import urllib.request
    import urllib.error

    req = urllib.request.Request(url, headers=headers, method="GET")
    total_timeout = connect_timeout + read_timeout
    try:
        with urllib.request.urlopen(req, timeout=total_timeout) as resp:
            body = resp.read().decode("utf-8")
            return resp.status, _json.loads(body)
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8") if e.fp else "{}"
        try:
            return e.code, _json.loads(body)
        except _json.JSONDecodeError:
            return e.code, {"error": {"message": body}}
    except urllib.error.URLError as e:
        logger.warning("poll_get_url_error url=%s reason=%s", url, e.reason)
        return 503, {"error": {"message": "URLError: %s" % e.reason}}
    except (OSError, _json.JSONDecodeError) as e:
        logger.warning("poll_get_error url=%s error=%s", url, e)
        return 503, {"error": {"message": str(e)}}


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
