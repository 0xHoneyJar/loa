"""cycle-103 sprint-3 T3.1 — tests for ProviderStreamError + dispatch table.

Pins the AC-3.1 contract: every documented `category` value dispatches
to the right typed exception. Tests the foundational layer that T3.2-T3.7
all build on, so a regression here would cascade.

Spec: sprint.md T3.1 + AC-3.1 + sdd.md §1.4.4 + §6.1.
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

# Add the adapters/ directory to sys.path so we can import loa_cheval.
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from loa_cheval.types import (  # noqa: E402
    ChevalError,
    ConnectionLostError,
    InvalidInputError,
    ProviderStreamError,
    ProviderUnavailableError,
    RateLimitError,
    dispatch_provider_stream_error,
)


# ----------------------------------------------------------------------------
# ProviderStreamError construction
# ----------------------------------------------------------------------------


class TestProviderStreamErrorConstruction:
    def test_subclasses_cheval_error(self) -> None:
        e = ProviderStreamError("malformed", "test")
        assert isinstance(e, ChevalError)

    def test_carries_category(self) -> None:
        e = ProviderStreamError("rate_limit", "test")
        assert e.category == "rate_limit"

    def test_carries_message_detail(self) -> None:
        e = ProviderStreamError("malformed", "JSON parse failure at byte 1234")
        assert e.message_detail == "JSON parse failure at byte 1234"

    def test_carries_raw_payload(self) -> None:
        payload = b'{"error": "..."}'
        e = ProviderStreamError("malformed", "x", raw_payload=payload)
        assert e.raw_payload == payload

    def test_raw_payload_defaults_to_none(self) -> None:
        e = ProviderStreamError("malformed", "x")
        assert e.raw_payload is None

    def test_code_is_provider_stream_error(self) -> None:
        e = ProviderStreamError("malformed", "x")
        assert e.code == "PROVIDER_STREAM_ERROR"

    def test_str_includes_category_tag(self) -> None:
        e = ProviderStreamError("malformed", "broken JSON")
        # The format is `[category] message` per the constructor.
        assert "[malformed]" in str(e)
        assert "broken JSON" in str(e)

    @pytest.mark.parametrize(
        "category,expected_retryable",
        [
            ("rate_limit", True),
            ("overloaded", True),
            ("transient", True),
            ("malformed", False),
            ("policy", False),
            ("unknown", False),
        ],
    )
    def test_retryable_mirrors_dispatched_semantics(
        self, category: str, expected_retryable: bool
    ) -> None:
        e = ProviderStreamError(category, "test")  # type: ignore[arg-type]
        assert e.retryable is expected_retryable

    def test_context_carries_category(self) -> None:
        e = ProviderStreamError("rate_limit", "x")
        assert e.context["category"] == "rate_limit"


# ----------------------------------------------------------------------------
# dispatch_provider_stream_error — AC-3.1 lookup table
# ----------------------------------------------------------------------------


class TestDispatchProviderStreamError:
    def test_rate_limit_dispatches_to_RateLimitError(self) -> None:
        e = ProviderStreamError("rate_limit", "429 received")
        dispatched = dispatch_provider_stream_error(e, provider="anthropic")
        assert isinstance(dispatched, RateLimitError)
        assert dispatched.context.get("provider") == "anthropic"

    def test_overloaded_dispatches_to_ProviderUnavailableError(self) -> None:
        e = ProviderStreamError("overloaded", "503 received")
        dispatched = dispatch_provider_stream_error(e, provider="openai")
        assert isinstance(dispatched, ProviderUnavailableError)
        # The reason should propagate the detail message.
        assert "overloaded" in str(dispatched)
        assert "503 received" in str(dispatched)

    def test_malformed_dispatches_to_InvalidInputError(self) -> None:
        e = ProviderStreamError("malformed", "JSON parse failure at byte 1234")
        dispatched = dispatch_provider_stream_error(e, provider="google")
        assert isinstance(dispatched, InvalidInputError)
        # Caller-facing message includes provider + the parser detail.
        assert "google" in str(dispatched)
        assert "JSON parse failure" in str(dispatched)

    def test_policy_dispatches_to_InvalidInputError(self) -> None:
        e = ProviderStreamError("policy", "content blocked by safety filter")
        dispatched = dispatch_provider_stream_error(e, provider="anthropic")
        assert isinstance(dispatched, InvalidInputError)
        assert "policy" in str(dispatched)

    def test_transient_dispatches_to_ConnectionLostError(self) -> None:
        e = ProviderStreamError("transient", "stream ended prematurely after 1200 bytes")
        dispatched = dispatch_provider_stream_error(e, provider="anthropic")
        assert isinstance(dispatched, ConnectionLostError)
        # The provider + transport context should be carried.
        assert dispatched.provider == "anthropic"

    def test_unknown_dispatches_to_ProviderUnavailableError(self) -> None:
        e = ProviderStreamError("unknown", "weird event type seen")
        dispatched = dispatch_provider_stream_error(e, provider="anthropic")
        # `unknown` is the conservative fallback — move on to next provider.
        assert isinstance(dispatched, ProviderUnavailableError)

    def test_empty_provider_defaults_to_unknown_in_context(self) -> None:
        # Calling without provider= still produces a valid exception
        # (with provider="unknown" in the context) — for callers that
        # don't know which provider raised.
        e = ProviderStreamError("rate_limit", "test")
        dispatched = dispatch_provider_stream_error(e)
        assert isinstance(dispatched, RateLimitError)
        assert dispatched.context.get("provider") == "unknown"

    def test_dispatch_preserves_retry_semantics_per_AC_3_1(self) -> None:
        # AC-3.1: "Restores retry classification cycle-3 flattened."
        # Each category must dispatch to an exception whose retryable
        # flag matches retry.py's behavioral expectation.
        retry_categories = [("rate_limit", True), ("overloaded", True), ("transient", True)]
        non_retry_categories = [("malformed", False), ("policy", False)]
        for category, want_retryable in retry_categories + non_retry_categories:
            e = ProviderStreamError(category, "test")  # type: ignore[arg-type]
            dispatched = dispatch_provider_stream_error(e, provider="anthropic")
            assert dispatched.retryable is want_retryable, (
                f"category={category} dispatched to {type(dispatched).__name__} "
                f"with retryable={dispatched.retryable}, expected {want_retryable}"
            )


# ----------------------------------------------------------------------------
# Round-trip — raise → catch → dispatch → re-raise pattern
# ----------------------------------------------------------------------------


class TestRoundTripIntegration:
    """Pin the documented usage pattern from the docstring."""

    def test_round_trip_from_streaming_layer_to_caller(self) -> None:
        # Simulated streaming layer raises ProviderStreamError.
        def fake_sse_parser() -> None:
            raise ProviderStreamError(
                category="rate_limit",
                message="Anthropic streaming returned rate_limit_exceeded",
                raw_payload=b'{"type":"error","error":{"type":"rate_limit_exceeded"}}',
            )

        # Adapter dispatch layer catches + re-raises typed.
        with pytest.raises(RateLimitError) as exc_info:
            try:
                fake_sse_parser()
            except ProviderStreamError as e:
                raise dispatch_provider_stream_error(e, provider="anthropic")

        assert exc_info.value.context.get("provider") == "anthropic"
        assert exc_info.value.retryable is True


# ----------------------------------------------------------------------------
# Retry semantics — pin that retry.py-compatible flag is set
# ----------------------------------------------------------------------------


class TestRetrySemantics:
    """retry.py reads the `retryable` flag on the dispatched exception.
    Pin that the dispatch preserves the right retry behavior per
    category."""

    @pytest.mark.parametrize(
        "category,exception_class,retryable",
        [
            ("rate_limit", RateLimitError, True),
            ("overloaded", ProviderUnavailableError, True),
            ("transient", ConnectionLostError, True),
            ("malformed", InvalidInputError, False),
            ("policy", InvalidInputError, False),
            ("unknown", ProviderUnavailableError, True),  # PU is retryable
        ],
    )
    def test_category_to_class_and_retryable(
        self, category: str, exception_class: type, retryable: bool
    ) -> None:
        e = ProviderStreamError(category, "test")  # type: ignore[arg-type]
        dispatched = dispatch_provider_stream_error(e, provider="anthropic")
        assert isinstance(dispatched, exception_class)
        assert dispatched.retryable is retryable
