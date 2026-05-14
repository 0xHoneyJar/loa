"""cycle-109 followup #883 Bug 3 — billing-class error classification.

When the Anthropic API returns HTTP 400 with a billing-class signal
(credit balance depleted, quota exceeded, invoice overdue), the
adapter previously raised InvalidInputError — which is TERMINAL and
prevents the chain-walk from advancing to the next entry. The cycle-104
within-company chain (e.g. claude-opus-4-7 → claude-opus-4-6 →
claude-sonnet-4-6 → claude-headless) is specifically designed for this
scenario: if the API path is unavailable due to billing, claude-headless
(CLI OAuth subscription) should take over.

Fix: classify billing-class 400s as ProviderUnavailableError so the
chain walks. Other 400s (parameter errors, malformed requests) remain
InvalidInputError.

Symptom: with depleted ANTHROPIC_API_KEY, every Flatline voice fails
with `[cheval] PROVIDER_UNAVAILABLE: Anthropic API error (HTTP 400):
Your credit balance is too low` and the entire orchestration aborts
even though claude-headless (the chain terminal) would succeed.
"""

from __future__ import annotations

import sys
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

# Adapter import path (mirrors test_claude_headless_adapter.py pattern).
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from loa_cheval.providers.anthropic_adapter import AnthropicAdapter  # noqa: E402
from loa_cheval.types import (  # noqa: E402
    CompletionRequest,
    InvalidInputError,
    ModelConfig,
    ProviderConfig,
    ProviderUnavailableError,
)


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


def _make_config() -> ProviderConfig:
    return ProviderConfig(
        name="anthropic",
        type="anthropic",
        endpoint="https://api.anthropic.com/v1",
        auth="sk-ant-test",
        connect_timeout=10.0,
        read_timeout=30.0,
        models={
            "claude-opus-4-7": ModelConfig(
                capabilities=["chat"],
                context_window=200000,
            ),
        },
    )


def _make_request() -> CompletionRequest:
    return CompletionRequest(
        messages=[{"role": "user", "content": "hi"}],
        model="claude-opus-4-7",
        temperature=0.3,
        max_tokens=1024,
    )


# ---------------------------------------------------------------------------
# Billing-class error classification (closes #883 Bug 3)
#
# These tests exercise the non-streaming path because it's the simpler
# error site to mock. The streaming path uses the same _is_billing_class_error
# helper so coverage transfers.
# ---------------------------------------------------------------------------


def _force_nonstreaming(monkeypatch):
    """The streaming kill switch routes through the non-streaming path
    (which is the simpler one to mock)."""
    monkeypatch.setenv("LOA_CHEVAL_DISABLE_STREAMING", "1")


class TestBillingClassErrors:
    """Each billing-class HTTP 400 should raise ProviderUnavailableError
    so the within-company chain walks instead of terminating."""

    def test_credit_balance_too_low_lowercase(self, monkeypatch):
        _force_nonstreaming(monkeypatch)
        adapter = AnthropicAdapter(_make_config())
        err_resp = {"error": {"message": "your credit balance is too low"}}
        with patch(
            "loa_cheval.providers.anthropic_adapter.http_post",
            return_value=(400, err_resp),
        ):
            with pytest.raises(ProviderUnavailableError):
                adapter.complete(_make_request())

    def test_credit_balance_too_low_capitalized(self, monkeypatch):
        _force_nonstreaming(monkeypatch)
        adapter = AnthropicAdapter(_make_config())
        err_resp = {"error": {"message": "Your credit balance is too low"}}
        with patch(
            "loa_cheval.providers.anthropic_adapter.http_post",
            return_value=(400, err_resp),
        ):
            with pytest.raises(ProviderUnavailableError):
                adapter.complete(_make_request())

    def test_quota_exceeded(self, monkeypatch):
        _force_nonstreaming(monkeypatch)
        adapter = AnthropicAdapter(_make_config())
        err_resp = {"error": {"message": "quota_exceeded for this account"}}
        with patch(
            "loa_cheval.providers.anthropic_adapter.http_post",
            return_value=(400, err_resp),
        ):
            with pytest.raises(ProviderUnavailableError):
                adapter.complete(_make_request())

    def test_invoice_overdue(self, monkeypatch):
        _force_nonstreaming(monkeypatch)
        adapter = AnthropicAdapter(_make_config())
        err_resp = {"error": {"message": "invoice_overdue; please update payment"}}
        with patch(
            "loa_cheval.providers.anthropic_adapter.http_post",
            return_value=(400, err_resp),
        ):
            with pytest.raises(ProviderUnavailableError):
                adapter.complete(_make_request())

    def test_billing_disabled(self, monkeypatch):
        _force_nonstreaming(monkeypatch)
        adapter = AnthropicAdapter(_make_config())
        err_resp = {"error": {"message": "billing_disabled on workspace"}}
        with patch(
            "loa_cheval.providers.anthropic_adapter.http_post",
            return_value=(400, err_resp),
        ):
            with pytest.raises(ProviderUnavailableError):
                adapter.complete(_make_request())

    def test_payment_required_signal(self, monkeypatch):
        """Generic payment_required token (Anthropic surfaces this on some 400s)."""
        _force_nonstreaming(monkeypatch)
        adapter = AnthropicAdapter(_make_config())
        err_resp = {"error": {"message": "payment_required to continue"}}
        with patch(
            "loa_cheval.providers.anthropic_adapter.http_post",
            return_value=(400, err_resp),
        ):
            with pytest.raises(ProviderUnavailableError):
                adapter.complete(_make_request())


class TestNonBillingErrorsStillTerminal:
    """Positive control — non-billing 400s remain InvalidInputError so the
    classifier doesn't over-broaden (e.g. param errors should NOT chain-walk)."""

    def test_temperature_deprecated_stays_terminal(self, monkeypatch):
        _force_nonstreaming(monkeypatch)
        adapter = AnthropicAdapter(_make_config())
        err_resp = {"error": {"message": "temperature is deprecated for this model"}}
        with patch(
            "loa_cheval.providers.anthropic_adapter.http_post",
            return_value=(400, err_resp),
        ):
            with pytest.raises(InvalidInputError):
                adapter.complete(_make_request())

    def test_malformed_messages_stays_terminal(self, monkeypatch):
        _force_nonstreaming(monkeypatch)
        adapter = AnthropicAdapter(_make_config())
        err_resp = {"error": {"message": "messages: at least one message is required"}}
        with patch(
            "loa_cheval.providers.anthropic_adapter.http_post",
            return_value=(400, err_resp),
        ):
            with pytest.raises(InvalidInputError):
                adapter.complete(_make_request())

    def test_invalid_model_stays_terminal(self, monkeypatch):
        _force_nonstreaming(monkeypatch)
        adapter = AnthropicAdapter(_make_config())
        err_resp = {"error": {"message": "model: 'fake-model' is not a valid model"}}
        with patch(
            "loa_cheval.providers.anthropic_adapter.http_post",
            return_value=(400, err_resp),
        ):
            with pytest.raises(InvalidInputError):
                adapter.complete(_make_request())


class TestHelperPureFunction:
    """Direct test of _is_billing_class_error — operators can extend
    the keyword list by editing the module-level constant."""

    def test_returns_true_for_each_canonical_token(self):
        from loa_cheval.providers.anthropic_adapter import _is_billing_class_error
        assert _is_billing_class_error("Your credit balance is too low") is True
        assert _is_billing_class_error("quota_exceeded") is True
        assert _is_billing_class_error("invoice_overdue") is True
        assert _is_billing_class_error("billing_disabled") is True
        assert _is_billing_class_error("payment_required") is True

    def test_returns_false_for_param_errors(self):
        from loa_cheval.providers.anthropic_adapter import _is_billing_class_error
        assert _is_billing_class_error("temperature is deprecated") is False
        assert _is_billing_class_error("model not found") is False
        assert _is_billing_class_error("") is False

    def test_case_insensitive(self):
        from loa_cheval.providers.anthropic_adapter import _is_billing_class_error
        assert _is_billing_class_error("CREDIT BALANCE TOO LOW") is True
        assert _is_billing_class_error("Quota Exceeded") is True
