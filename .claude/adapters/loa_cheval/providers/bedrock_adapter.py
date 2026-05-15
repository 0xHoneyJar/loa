"""AWS Bedrock provider adapter (cycle-096 Sprint 1 / SDD §5.1).

Bearer-token auth via direct HTTP to the Bedrock Converse API. No boto3,
no SigV4 signing in v1 — those are the v2 (FR-4) path, designed-not-built.

Key behaviors driven by Sprint 0 G-S0-2 probe findings (2026-05-02):

* Inference profile IDs are REQUIRED. Bare ``anthropic.*`` foundation-model
  IDs return HTTP 400 with the explicit "on-demand throughput isn't supported"
  message; the adapter classifies this as :class:`OnDemandNotSupportedError`
  with actionable remediation pointing at ``us.*`` or ``global.*`` profile IDs.
* Model IDs containing colons (e.g., the trailing ``:0`` on Bedrock-Haiku-4.5)
  must be URL-encoded in the path component.
* Request body uses Bedrock Converse format. Tool schemas require the
  ``inputSchema.json: <schema>`` wrapping (distinct from direct Anthropic).
* Thinking traces use ``thinking.type: "adaptive"`` + ``output_config.effort``
  on Bedrock; the direct-Anthropic ``"enabled"`` + ``budget_tokens`` form is
  rejected with HTTP 400. Adapter translates per-provider.
* Response usage is camelCase (``inputTokens`` etc.) plus prompt-cache fields.
  Adapter normalizes to cheval ``Usage`` (snake_case).
* Daily-quota responses can arrive as HTTP 200 with a body pattern; we
  detect the pattern and trip a process-scoped circuit breaker
  (``threading.Event``) until process restart.
* Streaming is OUT OF SCOPE for v1 — :class:`NotImplementedError` is raised
  immediately rather than a silent fallback.
"""

from __future__ import annotations

import logging
import os
import sys
import threading
import time
from typing import Any, Dict, List, Optional, Tuple
from urllib.parse import quote

from loa_cheval.providers.base import (
    ProviderAdapter,
    enforce_context_window,
    http_post,
)
from loa_cheval.providers.bedrock_token_age import record_token_use
from loa_cheval.config.redaction import register_value_redaction
from loa_cheval.types import parse_provider_model_id  # noqa: F401  # used in _fallback_to_direct
from loa_cheval.types import (
    ChevalError,
    CompletionRequest,
    CompletionResult,
    ConfigError,
    InvalidInputError,
    ProviderUnavailableError,
    RateLimitError,
    Usage,
)

logger = logging.getLogger("loa_cheval.providers.bedrock")


# Daily-quota body sentinel patterns. Matched after lib-security.sh redaction
# (no risk of token leakage via the sentinel itself) — cf. SDD §6.1.
_DAILY_QUOTA_PATTERNS: Tuple[str, ...] = (
    "too many tokens per day",
    "daily quota",
    "daily limit",
)


# Process-scoped circuit breaker for daily-quota state. threading.Event is
# atomic across threads; once .set(), subsequent calls fast-fail. Reset
# requires process restart per SDD §6.6 (cross-process coordination is a v2
# concern; daily quotas are billing-account-scoped which makes the
# per-process granularity acceptable in v1).
_DAILY_QUOTA_EXCEEDED: threading.Event = threading.Event()


class BedrockError(ChevalError):
    """Base error for Bedrock-specific adapter conditions."""


class OnDemandNotSupportedError(ConfigError):
    """Bare model ID used; inference profile required.

    Surfaced when the operator passes ``anthropic.claude-opus-4-7`` instead
    of ``us.anthropic.claude-opus-4-7``. The error message names the actual
    inference profile namespaces (``us.*``, ``global.*``) so the operator
    can act without consulting docs. Caller must NOT retry.
    """


class ModelEndOfLifeError(ConfigError):
    """Model has been retired by AWS.

    Surfaced on HTTP 404 with the explicit retirement body message. The
    caller must update to a non-retired model — a retry will keep failing
    against the same retired ID. Distinct from "not found" (which Bedrock
    returns as HTTP 400 ``ValidationException``).
    """


class EmptyResponseError(BedrockError):
    """Two consecutive Converse calls returned ``output.message.content = []``.

    A subset of Bedrock-Anthropic prompt patterns elicit empty-content
    responses on 200 OK rather than an error. NFR-R4 specifies single retry;
    if the second call also yields empty, we surface this rather than
    silently returning empty text.
    """

    def __init__(self, message: str = "Bedrock returned empty content[] on two consecutive attempts"):
        super().__init__("BEDROCK_EMPTY_RESPONSE", message, retryable=False)


class QuotaExceededError(BedrockError):
    """Daily quota exhausted; circuit breaker tripped for process lifetime.

    Subsequent calls within this process fail-fast without hitting the API.
    Operator restarts the process to clear (or waits until quota resets and
    initiates a new process).
    """

    DEFAULT_MESSAGE = (
        "Bedrock daily quota exceeded — circuit breaker tripped. "
        "AWS Bedrock per-account daily quotas reset at 00:00 UTC; restart "
        "the process after reset, or fail over to a different provider via "
        "compliance_profile: prefer_bedrock + fallback_to mapping."
    )

    def __init__(self, message: str = DEFAULT_MESSAGE):
        super().__init__("BEDROCK_DAILY_QUOTA", message, retryable=False)


class RegionMismatchError(ConfigError):
    """Configured region cannot serve the requested inference profile.

    For example: ``hounfour.bedrock.region: eu-west-1`` paired with
    ``us.anthropic.claude-opus-4-7``. The error names the supported region
    set so the operator can correct ``.loa.config.yaml`` or
    ``AWS_BEDROCK_REGION``.
    """


class BedrockAdapter(ProviderAdapter):
    """Adapter for AWS Bedrock Converse API (SDD §5.1)."""

    PROVIDER_TYPE = "bedrock"
    # Cycle-110 FR-2.3 — Bedrock dispatches via AWS IAM SigV4 / Bearer-token.
    auth_type: str = "aws_iam"

    # Class-level circuit breaker reference (re-exported for tests).
    _DAILY_QUOTA_EXCEEDED = _DAILY_QUOTA_EXCEEDED

    def complete(self, request: CompletionRequest) -> CompletionResult:
        """Send a Converse request; fallback to direct provider per compliance_profile.

        On transient Bedrock failure (RateLimitError, ProviderUnavailableError),
        and only when ``self.config.compliance_profile`` is ``prefer_bedrock`` or
        ``none``, look up the per-model ``fallback_to`` mapping and re-issue
        the request via the direct-provider adapter.

        Raises:
            QuotaExceededError: circuit breaker tripped from a prior call.
            NotImplementedError: streaming requested (v1 explicit non-support).
            OnDemandNotSupportedError: bare model ID used (NEVER triggers fallback —
                a config error, not a transient outage).
            ModelEndOfLifeError: model retired by AWS (NEVER triggers fallback).
            RegionMismatchError: region/profile mismatch (NEVER triggers fallback).
            EmptyResponseError: two consecutive empty-content responses.
            RateLimitError, ProviderUnavailableError: surface to caller when
                ``compliance_profile=bedrock_only`` (default; fail-closed).
                Trigger fallback when ``compliance_profile in (prefer_bedrock, none)``.
            InvalidInputError: standard adapter error surface (SDD §5.1).
        """
        try:
            return self._complete_bedrock(request)
        except (ProviderUnavailableError, RateLimitError) as exc:
            cp = self.config.compliance_profile
            if cp in ("prefer_bedrock", "none"):
                return self._fallback_to_direct(request, exc, cp)
            # bedrock_only (or unknown / missing) → re-raise for fail-closed behavior.
            raise

    def _complete_bedrock(self, request: CompletionRequest) -> CompletionResult:
        """Inner Bedrock-only path. Wrapped by complete() for fallback handling."""
        # Streaming explicit non-support (HIGH-CONSENSUS IMP-007).
        if request.metadata and request.metadata.get("stream"):
            raise NotImplementedError(
                "Streaming not supported in Bedrock v1 (track at OQ-S1). "
                "Use non-streaming completion or a different provider."
            )

        # Circuit-breaker fast-fail.
        if self._DAILY_QUOTA_EXCEEDED.is_set():
            raise QuotaExceededError()

        model_config = self._get_model_config(request.model)
        enforce_context_window(request, model_config)

        # Region resolution chain (SDD §5.1 + FR-6).
        region = self._resolve_region(request)

        # Region-prefix sanity (FR-12). If model_id starts with a regional
        # prefix that doesn't match the resolved region's family, surface
        # RegionMismatchError before spending an API call. Profile IDs of the
        # form "us.*" require region in the US set; "eu.*" for EU; "global.*"
        # accepts any region.
        self._verify_region_for_model(request.model, region)

        # Build the request URL — model_id MUST be URL-encoded because
        # colon-bearing IDs (Haiku 4.5 case) would break path parsing.
        url = (
            f"https://bedrock-runtime.{region}.amazonaws.com"
            f"/model/{quote(request.model, safe='')}/converse"
        )

        # Translate caller-canonical messages → Bedrock Converse format.
        system_blocks, converse_messages = _transform_messages(request.messages)

        body: Dict[str, Any] = {
            "messages": converse_messages,
            "inferenceConfig": {"maxTokens": request.max_tokens},
        }

        # Temperature gate per ModelConfig.params (mirrors anthropic_adapter).
        params = model_config.params if isinstance(model_config.params, dict) else {}
        if params.get("temperature_supported", True):
            body["inferenceConfig"]["temperature"] = request.temperature

        if system_blocks:
            body["system"] = system_blocks

        if request.tools:
            body["toolConfig"] = _transform_tools_to_converse(request.tools, request.tool_choice)

        # Thinking-trace translation (FR-13 + Sprint 0 probe finding).
        thinking_directive = _extract_thinking_directive(request)
        if thinking_directive is not None:
            body["additionalModelRequestFields"] = thinking_directive

        # Headers — Bearer auth, NEVER SigV4 in v1.
        auth = self._get_auth_header()
        headers = {
            "Content-Type": "application/json",
            "Authorization": f"Bearer {auth}",
        }

        # Two-layer redaction registration (NFR-Sec10) + token age tracking
        # (NFR-Sec11). Both are best-effort; failures do not gate the request.
        # Idempotent: register_value_redaction dedupes via set membership;
        # record_token_use writes the sentinel at most once per call.
        register_value_redaction(auth)
        # max_age_days: read from provider extras if present, else default 90.
        # Schema lives at hounfour.bedrock.token_max_age_days; for now we read
        # via os.environ since there's no plumbing for arbitrary provider-level
        # config in ProviderConfig today. Cycle-097 can promote to first-class.
        try:
            max_age = int(os.environ.get("LOA_BEDROCK_TOKEN_MAX_AGE_DAYS", "90"))
        except (TypeError, ValueError):
            max_age = 90
        record_token_use(auth, max_age_days=max_age)

        # Issue the request with empty-content single-retry semantics.
        return self._post_with_empty_retry(
            url=url,
            headers=headers,
            body=body,
            request_model=request.model,
        )

    # ------------------------------------------------------------------
    # Compliance-aware fallback (NFR-R1, FR-1.5)
    # ------------------------------------------------------------------

    def _fallback_to_direct(
        self,
        request: CompletionRequest,
        original_error: Exception,
        compliance_profile: str,
    ) -> CompletionResult:
        """Dispatch to the direct-provider equivalent per ``fallback_to`` mapping.

        Only invoked when ``compliance_profile`` is ``prefer_bedrock`` or
        ``none``. Loader pre-validates ``fallback_to`` is set on every model
        when ``prefer_bedrock`` is active (Flatline BLOCKER SKP-003).

        Audit log + cost-ledger entries follow the NFR-Sec8 schema:
        - ``event_type: fallback_cross_provider`` (cost ledger)
        - ``category: compliance, subcategory: fallback_cross_provider_warned``
          (audit log) for ``prefer_bedrock``; silent for ``none``.
        """
        model_config = self._get_model_config(request.model)
        fallback_target = model_config.fallback_to
        if not fallback_target:
            # No declared mapping; re-raise the original error.
            logger.warning(
                "Bedrock %s failed; no fallback_to declared for %s. Re-raising.",
                type(original_error).__name__, request.model,
            )
            raise original_error

        # Parse the canonical "provider:model_id" string.
        try:
            fallback_provider, fallback_model_id = parse_provider_model_id(fallback_target)
        except Exception as exc:
            logger.warning(
                "Bedrock fallback_to %r is malformed (%s); re-raising original error.",
                fallback_target, exc,
            )
            raise original_error

        # v1 only supports Anthropic as a fallback target. Other providers can be
        # added in cycle-097 by extending this branch.
        if fallback_provider != "anthropic":
            logger.warning(
                "Bedrock fallback_to provider %r not yet supported (v1: anthropic only); "
                "re-raising original error.",
                fallback_provider,
            )
            raise original_error

        # Emit operator-visible warning + audit log per compliance posture.
        self._emit_fallback_audit(
            request_model=request.model,
            fallback_target=fallback_target,
            original_error=original_error,
            compliance_profile=compliance_profile,
        )

        # Construct minimal AnthropicAdapter via the public factory; reads
        # ANTHROPIC_API_KEY from env at request time. Imported lazily to avoid
        # circular import at module load.
        from loa_cheval.providers.anthropic_adapter import AnthropicAdapter
        from loa_cheval.types import ProviderConfig as _ProviderConfig

        fallback_provider_config = _ProviderConfig(
            name="anthropic",
            type="anthropic",
            endpoint="https://api.anthropic.com/v1",
            auth=os.environ.get("ANTHROPIC_API_KEY", ""),
            models={},  # AnthropicAdapter falls back to default ModelConfig
        )
        fallback_adapter = AnthropicAdapter(fallback_provider_config)

        # Re-issue the request with the fallback model. Preserve everything
        # else (messages, tools, tool_choice, max_tokens, etc.) so behavior is
        # equivalent from the caller's perspective.
        from dataclasses import replace
        fallback_request = replace(request, model=fallback_model_id)

        result = fallback_adapter.complete(fallback_request)

        # Tag the result so downstream consumers can detect the fallback
        # (cost-ledger entry tagging keys off this).
        if not isinstance(result.metadata, dict):
            result.metadata = {}
        result.metadata.setdefault("fallback", "cross_provider")
        result.metadata.setdefault("original_provider", "bedrock")
        result.metadata.setdefault("original_error_type", type(original_error).__name__)
        return result

    @staticmethod
    def _emit_fallback_audit(
        *,
        request_model: str,
        fallback_target: str,
        original_error: Exception,
        compliance_profile: str,
    ) -> None:
        """Stderr warning + audit logger entry per compliance posture.

        ``prefer_bedrock`` emits a stderr warning and an audit-category log
        line. ``none`` is silent (operator opted into silent fallback).
        """
        if compliance_profile == "prefer_bedrock":
            sys.stderr.write(
                f"[loa-cheval] Bedrock unavailable; falling back to direct "
                f"{fallback_target} per compliance_profile=prefer_bedrock. "
                f"Original error: {type(original_error).__name__}: {original_error}\n"
            )
            logger.warning(
                "compliance_fallback_cross_provider_warned: bedrock %s -> %s (reason=%s)",
                request_model, fallback_target, type(original_error).__name__,
            )
        # `none`: silent fallback; only the structured logger entry, no stderr.
        else:
            logger.info(
                "compliance_fallback_cross_provider_silent: bedrock %s -> %s (reason=%s)",
                request_model, fallback_target, type(original_error).__name__,
            )

    # ------------------------------------------------------------------
    # Region resolution + verification
    # ------------------------------------------------------------------

    def _resolve_region(self, request: CompletionRequest) -> str:
        """Resolve region per SDD §5.1 chain: request → env → config → fallback."""
        # 1. per-request override via metadata.region (advanced; documented but not promoted)
        if request.metadata:
            override = request.metadata.get("region")
            if override:
                return str(override)
        # 2. env var
        env_region = os.environ.get("AWS_BEDROCK_REGION") or os.environ.get("AWS_REGION")
        if env_region:
            return env_region
        # 3. provider config default
        if self.config.region_default:
            return self.config.region_default
        # 4. final fallback (matches model-config.yaml default)
        return "us-east-1"

    @staticmethod
    def _verify_region_for_model(model_id: str, region: str) -> None:
        """Region-prefix mismatch guard (FR-12).

        Profile ID prefixes (``us.``, ``eu.``, ``apac.``, ``global.``) constrain
        which AWS region can serve the request. We reject obvious mismatches
        early with an actionable message rather than letting AWS return a
        generic error.
        """
        prefix_to_regions: Dict[str, List[str]] = {
            "us.": ["us-east-1", "us-east-2", "us-west-2"],
            "eu.": ["eu-central-1", "eu-west-1", "eu-west-3", "eu-north-1"],
            "apac.": ["ap-northeast-1", "ap-northeast-2", "ap-southeast-1", "ap-southeast-2"],
        }
        for prefix, allowed in prefix_to_regions.items():
            if model_id.startswith(prefix):
                if region not in allowed:
                    raise RegionMismatchError(
                        f"Model {model_id!r} requires region in {allowed}; "
                        f"have {region!r}. Set hounfour.bedrock.region or "
                        f"AWS_BEDROCK_REGION to a supported region."
                    )
                return
        # global.* accepts any region; bare model IDs (no prefix) will fail at
        # the API level with OnDemandNotSupportedError — handled in
        # _classify_error rather than here (we don't want to second-guess the
        # operator's intent at this layer).

    # ------------------------------------------------------------------
    # HTTP + retry
    # ------------------------------------------------------------------

    def _post_with_empty_retry(
        self,
        url: str,
        headers: Dict[str, str],
        body: Dict[str, Any],
        request_model: str,
    ) -> CompletionResult:
        """POST to Converse with the empty-content single-retry policy (NFR-R4).

        Empty content[] on 200 OK gets exactly one retry with the same body.
        If the second call also returns empty, raise :class:`EmptyResponseError`.
        """
        for attempt in range(2):
            start = time.monotonic()
            status, resp = http_post(
                url=url,
                headers=headers,
                body=body,
                connect_timeout=self.config.connect_timeout,
                read_timeout=self.config.read_timeout,
            )
            latency_ms = int((time.monotonic() - start) * 1000)

            # Daily-quota detection on 200 OK (SDD §6.1).
            if status == 200 and _is_daily_quota_body(resp):
                self._DAILY_QUOTA_EXCEEDED.set()
                logger.warning(
                    "Bedrock daily quota detected; circuit breaker tripped for process lifetime"
                )
                raise QuotaExceededError()

            # Error path — classify via _classify_error.
            if status != 200:
                self._classify_error(status, resp, request_model)

            content_blocks = (
                resp.get("output", {}).get("message", {}).get("content") or []
            )
            if content_blocks:
                return self._parse_response(resp, request_model, latency_ms)

            # Empty content branch — retry exactly once.
            if attempt == 0:
                logger.info("Bedrock returned empty content[]; retrying once (NFR-R4)")
                continue

        raise EmptyResponseError()

    # ------------------------------------------------------------------
    # Error classification
    # ------------------------------------------------------------------

    def _classify_error(self, status: int, resp: Dict[str, Any], model_id: str) -> None:
        """Map (status, body) to a typed Cheval error (SDD §6.1 / FR-11).

        Always raises; never returns. The branching reflects empirical Bedrock
        behavior captured in the Sprint 0 G-S0-2 probe set:

        * HTTP 400 with "on-demand throughput isn't supported" body →
          :class:`OnDemandNotSupportedError` (operator used a bare model ID).
        * HTTP 400 with "provided model identifier is invalid" body →
          :class:`InvalidInputError` (operator typo in the profile ID).
        * HTTP 404 with "end of its life" body →
          :class:`ModelEndOfLifeError` (model retired; pick a replacement).
        * HTTP 429 → :class:`RateLimitError` (caller can back off).
        * HTTP >= 500 → :class:`ProviderUnavailableError` (transient).
        * Other 4xx → :class:`InvalidInputError`.
        """
        message = _extract_error_message(resp)

        if status == 400:
            if "on-demand throughput isn't supported" in message.lower() or \
               "on-demand throughput isn’t supported" in message.lower():
                raise OnDemandNotSupportedError(
                    f"Bedrock model {model_id!r} requires an inference profile ID. "
                    f"Replace bare 'anthropic.*' with 'us.anthropic.*' (US-region) "
                    f"or 'global.anthropic.*' (cross-region). Original: {message}"
                )
            if "provided model identifier is invalid" in message.lower():
                raise InvalidInputError(
                    f"Bedrock model identifier invalid: {model_id!r}. {message}"
                )
            raise InvalidInputError(f"Bedrock 400: {message}")

        if status == 404:
            if "end of its life" in message.lower() or "reached the end of its life" in message.lower():
                raise ModelEndOfLifeError(
                    f"Bedrock model {model_id!r} has been retired by AWS: {message}"
                )
            raise InvalidInputError(f"Bedrock 404: {message}")

        if status == 403:
            raise ConfigError(
                f"Bedrock 403 AccessDenied for {model_id!r}: {message}. "
                f"Check AWS_BEARER_TOKEN_BEDROCK and IAM model-invocation permissions."
            )

        if status == 429:
            raise RateLimitError(self.provider)

        if status >= 500:
            raise ProviderUnavailableError(self.provider, f"HTTP {status}: {message}")

        raise InvalidInputError(f"Bedrock HTTP {status}: {message}")

    # ------------------------------------------------------------------
    # Response normalization (camelCase → snake_case Usage)
    # ------------------------------------------------------------------

    def _parse_response(
        self,
        resp: Dict[str, Any],
        request_model: str,
        latency_ms: int,
    ) -> CompletionResult:
        """Translate Bedrock response shape → cheval CompletionResult."""
        message = resp.get("output", {}).get("message", {}) or {}
        content_blocks = message.get("content") or []

        text_parts: List[str] = []
        thinking_parts: List[str] = []
        tool_calls: List[Dict[str, Any]] = []

        for block in content_blocks:
            if "text" in block:
                text_parts.append(block.get("text", ""))
            elif "reasoningContent" in block:
                # Bedrock thinking traces under "reasoningContent" rather than
                # Anthropic's "thinking" type. Probe-confirmed shape may evolve.
                rc = block.get("reasoningContent", {})
                rt = rc.get("reasoningText", {})
                thinking_parts.append(rt.get("text", ""))
            elif "toolUse" in block:
                tu = block["toolUse"]
                # Cheval canonical tool call shape (SDD §4.2.5) — match the
                # AnthropicAdapter normalization so downstream handlers don't
                # branch on provider.
                tool_calls.append({
                    "id": tu.get("toolUseId", ""),
                    "type": "function",
                    "function": {
                        "name": tu.get("name", ""),
                        "arguments": _serialize_arguments(tu.get("input", {})),
                    },
                })

        text = "\n".join(p for p in text_parts if p)
        thinking = "\n".join(p for p in thinking_parts if p) if thinking_parts else None

        # Usage normalization: Bedrock camelCase + cache fields → cheval snake_case.
        usage_data = resp.get("usage", {}) or {}
        # Bedrock emits BOTH cacheReadInputTokens (newer) and cacheReadInputTokenCount
        # (alias from earlier schema versions). Prefer the *Tokens form;
        # fall back to *TokenCount for forward/backward compat.
        usage = Usage(
            input_tokens=int(usage_data.get("inputTokens", 0) or 0),
            output_tokens=int(usage_data.get("outputTokens", 0) or 0),
            reasoning_tokens=0,
            source="actual" if usage_data else "estimated",
        )

        return CompletionResult(
            content=text,
            tool_calls=tool_calls or None,
            thinking=thinking,
            usage=usage,
            model=request_model,
            latency_ms=latency_ms,
            provider=self.provider,
        )

    # ------------------------------------------------------------------
    # Config validation + health probe
    # ------------------------------------------------------------------

    def validate_config(self) -> List[str]:
        """Validate Bedrock-specific provider config."""
        errors: List[str] = []

        if not self.config.endpoint:
            errors.append(f"Provider '{self.provider}': endpoint is required")
        if not self.config.auth:
            errors.append(f"Provider '{self.provider}': auth is required (AWS_BEARER_TOKEN_BEDROCK)")
        if self.config.type != "bedrock":
            errors.append(f"Provider '{self.provider}': type must be 'bedrock'")

        # auth_modes: v1 only honors api_key. sigv4 declared in YAML schema
        # is the v2 path; loader rejects sigv4 with a clear error.
        modes = self.config.auth_modes or ["api_key"]
        if not isinstance(modes, list):
            errors.append(f"Provider '{self.provider}': auth_modes must be a list")
        elif "api_key" not in modes:
            errors.append(
                f"Provider '{self.provider}': auth_modes must include 'api_key' "
                f"(v1 only supports Bearer tokens; sigv4 is designed-not-built)"
            )

        # compliance_profile validation (post-loader resolution).
        cp = self.config.compliance_profile
        if cp is not None and cp not in ("bedrock_only", "prefer_bedrock", "none"):
            errors.append(
                f"Provider '{self.provider}': compliance_profile must be one of "
                f"'bedrock_only' | 'prefer_bedrock' | 'none', got {cp!r}"
            )

        # Per-model fallback_to validation when prefer_bedrock is active.
        if cp == "prefer_bedrock":
            for model_id, mc in self.config.models.items():
                if not mc.fallback_to:
                    errors.append(
                        f"Provider '{self.provider}': model {model_id!r} missing "
                        f"fallback_to; required when compliance_profile=prefer_bedrock "
                        f"(closes Flatline BLOCKER SKP-003 — no heuristic name matching)"
                    )

        return errors

    def health_check(self) -> bool:
        """Hit ListFoundationModels with Bearer auth — cheap, no token usage."""
        try:
            auth = self._get_auth_header()
            headers = {
                "Content-Type": "application/json",
                "Authorization": f"Bearer {auth}",
            }
            region = self.config.region_default or "us-east-1"
            url = f"https://bedrock.{region}.amazonaws.com/foundation-models"
            # http_post supports POST only; for GET, fall back to a lightweight
            # urllib call. Keeping it minimal — health_check should be fast.
            import urllib.request  # local import: only used here

            req = urllib.request.Request(url, headers=headers, method="GET")
            with urllib.request.urlopen(req, timeout=10) as resp:
                return resp.status == 200
        except Exception:  # noqa: BLE001
            return False


# ----------------------------------------------------------------------
# Module-level helpers
# ----------------------------------------------------------------------


def _transform_messages(
    messages: List[Dict[str, Any]],
) -> Tuple[Optional[List[Dict[str, str]]], List[Dict[str, Any]]]:
    """Cheval canonical messages → (system_blocks, converse_messages).

    Bedrock Converse takes ``system`` as a top-level array of ``{text}`` blocks,
    not a role inside ``messages``. We strip ``system`` messages out and emit
    them separately. ``user``/``assistant`` content becomes
    ``[{text: ...}]`` blocks per Converse schema.
    """
    system_blocks: List[Dict[str, str]] = []
    converse_messages: List[Dict[str, Any]] = []

    for msg in messages:
        role = msg.get("role")
        content = msg.get("content", "")

        if role == "system":
            if isinstance(content, str) and content:
                system_blocks.append({"text": content})
            continue

        if role not in ("user", "assistant"):
            # Unsupported role — skip (caller-side validation should catch).
            continue

        if isinstance(content, str):
            content_blocks = [{"text": content}]
        elif isinstance(content, list):
            # Caller passed pre-shaped content blocks; pass through.
            content_blocks = content
        else:
            content_blocks = [{"text": str(content)}]

        converse_messages.append({"role": role, "content": content_blocks})

    return (system_blocks or None), converse_messages


def _transform_tools_to_converse(
    tools: List[Dict[str, Any]],
    tool_choice: Optional[str],
) -> Dict[str, Any]:
    """Wrap caller tools with Bedrock-specific ``inputSchema.json`` envelope."""
    converse_tools: List[Dict[str, Any]] = []
    for tool in tools:
        # Caller may pass either OpenAI shape ({type: function, function: {...}})
        # or canonical cheval shape. Normalize to the inner spec.
        if "function" in tool:
            spec = tool["function"]
        else:
            spec = tool

        name = spec.get("name", "")
        description = spec.get("description", "")
        # Cheval canonical: spec.parameters is JSON Schema. Bedrock requires
        # double-wrapping under inputSchema.json — without this wrapper, the
        # tool call silently fails (Sprint 0 G-S0-2 probe #3 confirmed).
        parameters = spec.get("parameters", {"type": "object", "properties": {}})

        converse_tools.append({
            "toolSpec": {
                "name": name,
                "description": description,
                "inputSchema": {"json": parameters},
            }
        })

    cfg: Dict[str, Any] = {"tools": converse_tools}

    if tool_choice == "required":
        cfg["toolChoice"] = {"any": {}}
    elif tool_choice == "none":
        # Bedrock Converse doesn't support 'none' explicitly; omit toolConfig
        # entirely in caller code if 'none' is set. Here we default to 'auto'.
        cfg["toolChoice"] = {"auto": {}}
    else:
        cfg["toolChoice"] = {"auto": {}}

    return cfg


def _extract_thinking_directive(request: CompletionRequest) -> Optional[Dict[str, Any]]:
    """Translate caller-canonical thinking flags into Bedrock format.

    Caller may pass ``request.metadata = {"thinking": {"enabled": True}}`` or a
    direct-Anthropic-style ``thinking.type: enabled``; we translate either
    into Bedrock's ``adaptive`` format. Returns ``None`` if no directive.

    Probe-confirmed (Sprint 0 G-S0-2 #4): Bedrock REJECTS the direct-Anthropic
    ``thinking.type: enabled`` form with HTTP 400. Adapter ALWAYS emits the
    ``adaptive`` form on Bedrock.
    """
    if not request.metadata:
        return None

    thinking = request.metadata.get("thinking")
    if not thinking:
        return None

    # Accept either the cheval-shape {"enabled": True} or the direct-Anthropic
    # shape {"type": "enabled", "budget_tokens": N} and translate to Bedrock.
    if isinstance(thinking, dict):
        wants_thinking = (
            thinking.get("enabled") is True
            or thinking.get("type") == "enabled"
            or thinking.get("type") == "adaptive"
        )
        if not wants_thinking:
            return None

    return {
        "thinking": {"type": "adaptive"},
        "output_config": {"effort": "medium"},  # operator can override per-request later
    }


def _is_daily_quota_body(resp: Dict[str, Any]) -> bool:
    """Detect the daily-quota text pattern in a 200 OK body."""
    # Flatten plausible carrier fields into one search string. Conservative —
    # we'd rather miss the trip and let the next call hit the same response
    # than false-positive on a benign string.
    candidates: List[str] = []
    for key in ("message", "error", "errorMessage"):
        v = resp.get(key)
        if isinstance(v, str):
            candidates.append(v)

    # Sometimes the message is nested under output.message.content[].text —
    # check the first text block for the pattern.
    msg = resp.get("output", {}).get("message", {})
    for block in msg.get("content", []) or []:
        text = block.get("text", "")
        if isinstance(text, str):
            candidates.append(text)

    haystack = " ".join(candidates).lower()
    return any(pat in haystack for pat in _DAILY_QUOTA_PATTERNS)


def _extract_error_message(resp: Dict[str, Any]) -> str:
    """Pull a human-readable error message from Bedrock's varied error shapes."""
    if not isinstance(resp, dict):
        return str(resp)
    for key in ("message", "Message", "errorMessage", "error"):
        v = resp.get(key)
        if isinstance(v, str):
            return v
        if isinstance(v, dict):
            inner = v.get("message")
            if isinstance(inner, str):
                return inner
    return "(no error message in response body)"


def _serialize_arguments(args: Any) -> str:
    """Match the AnthropicAdapter convention: tool call arguments as JSON string."""
    import json as _json  # local import: only used here

    if isinstance(args, str):
        return args
    return _json.dumps(args, separators=(",", ":"))
