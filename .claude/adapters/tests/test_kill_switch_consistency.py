"""Sprint 4A DISS-001 regression pin — kill-switch consistency.

Pins the invariant that adapter routing and MODELINV audit emit MUST
agree on the boolean derived from `LOA_CHEVAL_DISABLE_STREAMING` across
the full truthy-value set. Before centralization in
`base._streaming_disabled()`, the adapters used strict `== "1"` while
`modelinv._streaming_active` used case-insensitive `.lower() in (...)` —
that mismatch was caught by the Sprint 4A adversarial review pass on
2026-05-11 (DISS-001 BLOCKING).

The invariant: for every value V the kill-switch interprets as truthy,
the adapter MUST take the legacy non-streaming path AND the audit MUST
record `streaming: false`. For every value V the kill-switch interprets
as falsy, the adapter MUST take the streaming path AND the audit MUST
record `streaming: true`. The two booleans MUST be exact inverses.
"""
from __future__ import annotations

import os
import sys
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

HERE = Path(__file__).resolve().parent
ADAPTERS_ROOT = HERE.parent
if str(ADAPTERS_ROOT) not in sys.path:
    sys.path.insert(0, str(ADAPTERS_ROOT))

from loa_cheval.providers.base import _streaming_disabled  # noqa: E402
from loa_cheval.audit.modelinv import _streaming_active  # noqa: E402


# Full truthy-value matrix the centralized helper recognizes (case-insensitive).
TRUTHY_VALUES = [
    "1",
    "true",
    "True",
    "TRUE",
    "yes",
    "Yes",
    "YES",
    "on",
    "On",
    "ON",
    "  true  ",  # whitespace stripped per centralized helper contract
]

FALSY_VALUES = [
    "",
    "0",
    "false",
    "False",
    "no",
    "off",
    "anything-else",
    "2",
    "tru",
    "yess",
]


# --- Direct helper consistency ---


@pytest.mark.parametrize("kill_value", TRUTHY_VALUES)
def test_truthy_values_agree_across_adapter_and_audit(monkeypatch, kill_value):
    """For every kill-switch truthy value: adapter sees disabled=True
    AND audit sees streaming=False (they must be exact inverses).
    """
    monkeypatch.setenv("LOA_CHEVAL_DISABLE_STREAMING", kill_value)
    adapter_disabled = _streaming_disabled()
    audit_streaming = _streaming_active()
    assert adapter_disabled is True, (
        f"Expected _streaming_disabled()=True for kill-switch value {kill_value!r}; got False"
    )
    assert audit_streaming is False, (
        f"Expected _streaming_active()=False for kill-switch value {kill_value!r}; got True"
    )
    # Invariant: the two MUST be exact inverses (DISS-001).
    assert adapter_disabled is (not audit_streaming), (
        f"DISS-001 unfixed: adapter_disabled={adapter_disabled} "
        f"audit_streaming={audit_streaming} for kill-switch={kill_value!r}"
    )


@pytest.mark.parametrize("non_kill_value", FALSY_VALUES)
def test_falsy_values_agree_across_adapter_and_audit(monkeypatch, non_kill_value):
    """For every kill-switch falsy value: adapter sees disabled=False
    AND audit sees streaming=True.
    """
    monkeypatch.setenv("LOA_CHEVAL_DISABLE_STREAMING", non_kill_value)
    adapter_disabled = _streaming_disabled()
    audit_streaming = _streaming_active()
    assert adapter_disabled is False, (
        f"Expected _streaming_disabled()=False for value {non_kill_value!r}; got True"
    )
    assert audit_streaming is True, (
        f"Expected _streaming_active()=True for value {non_kill_value!r}; got False"
    )
    assert adapter_disabled is (not audit_streaming), (
        f"DISS-001 unfixed: adapter_disabled={adapter_disabled} "
        f"audit_streaming={audit_streaming} for value={non_kill_value!r}"
    )


def test_env_unset_treats_streaming_as_active(monkeypatch):
    """No env var set → adapter takes streaming, audit records streaming."""
    monkeypatch.delenv("LOA_CHEVAL_DISABLE_STREAMING", raising=False)
    assert _streaming_disabled() is False
    assert _streaming_active() is True


# --- End-to-end consistency: adapter routing + audit emit in same call ---


def _build_anthropic_config():
    from loa_cheval.types import ProviderConfig, ModelConfig

    return ProviderConfig(
        name="anthropic",
        type="anthropic",
        endpoint="https://api.example.test/v1",
        auth="test-key",
        models={
            "claude-test": ModelConfig(
                capabilities=["chat"],
                context_window=200_000,
                token_param="max_tokens",
                params={"temperature_supported": True},
            ),
        },
    )


@pytest.mark.parametrize("kill_value", ["true", "TRUE", "yes", "on"])
def test_disss_001_pin_adapter_routes_legacy_when_kill_switch_is_non_strict_truthy(
    monkeypatch, kill_value
):
    """End-to-end DISS-001 pin: with `LOA_CHEVAL_DISABLE_STREAMING=true`
    (not the strict `"1"`), the AnthropicAdapter routes through the
    legacy `http_post` path, NOT the streaming path. Before DISS-001
    closure, the adapter used `== "1"` strict and would have taken the
    streaming path here while the audit recorded the wrong boolean.
    """
    from loa_cheval.providers.anthropic_adapter import AnthropicAdapter
    from loa_cheval.types import CompletionRequest

    monkeypatch.setenv("LOA_CHEVAL_DISABLE_STREAMING", kill_value)

    adapter = AnthropicAdapter(_build_anthropic_config())
    request = CompletionRequest(
        messages=[{"role": "user", "content": "hi"}],
        model="claude-test",
        max_tokens=64,
        temperature=0.0,
    )

    mock_response = {
        "id": "msg_x",
        "type": "message",
        "role": "assistant",
        "model": "claude-test",
        "content": [{"type": "text", "text": "ok"}],
        "stop_reason": "end_turn",
        "usage": {"input_tokens": 5, "output_tokens": 2},
    }

    # If the adapter routed to streaming, http_post would NOT be called
    # and this mock would never fire. If it routed to legacy, http_post
    # IS called and the mock intercepts.
    with patch(
        "loa_cheval.providers.anthropic_adapter.http_post",
        return_value=(200, mock_response),
    ) as nonstream_mock, patch(
        "loa_cheval.providers.anthropic_adapter.http_post_stream"
    ) as stream_mock:
        result = adapter.complete(request)

    assert nonstream_mock.called, (
        f"DISS-001 regression: with LOA_CHEVAL_DISABLE_STREAMING={kill_value!r}, "
        "adapter should have used the legacy non-streaming http_post path"
    )
    assert not stream_mock.called, (
        f"DISS-001 regression: with LOA_CHEVAL_DISABLE_STREAMING={kill_value!r}, "
        "adapter should NOT have called http_post_stream"
    )
    assert result.content == "ok"
