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


def _build_openai_config():
    from loa_cheval.types import ProviderConfig, ModelConfig

    return ProviderConfig(
        name="openai",
        type="openai",
        endpoint="https://api.example.test/v1",
        auth="test-key",
        models={
            "gpt-test": ModelConfig(
                capabilities=["chat"],
                context_window=128_000,
                token_param="max_tokens",
                endpoint_family="chat",
            ),
        },
    )


def _build_google_config():
    from loa_cheval.types import ProviderConfig, ModelConfig

    return ProviderConfig(
        name="google",
        type="google",
        endpoint="https://api.example.test/v1beta",
        auth="test-key",
        models={
            "gemini-test": ModelConfig(
                capabilities=["chat"],
                context_window=1_000_000,
                token_param="max_tokens",
            ),
        },
    )


# Adapter routing matrix — closes Sprint 4A cycle-2 DISS-003 (the cycle-1 pin
# only exercised Anthropic; a future refactor could regress openai or google
# back to `== "1"` without failing any test).
_ADAPTER_ROUTING_CASES = [
    pytest.param(
        "anthropic",
        "loa_cheval.providers.anthropic_adapter",
        "AnthropicAdapter",
        _build_anthropic_config,
        {
            "id": "msg_x",
            "type": "message",
            "role": "assistant",
            "model": "claude-test",
            "content": [{"type": "text", "text": "ok"}],
            "stop_reason": "end_turn",
            "usage": {"input_tokens": 5, "output_tokens": 2},
        },
        "claude-test",
        id="anthropic",
    ),
    pytest.param(
        "openai",
        "loa_cheval.providers.openai_adapter",
        "OpenAIAdapter",
        _build_openai_config,
        {
            "id": "chatcmpl_x",
            "model": "gpt-test",
            "choices": [
                {
                    "index": 0,
                    "message": {"role": "assistant", "content": "ok"},
                    "finish_reason": "stop",
                }
            ],
            "usage": {"prompt_tokens": 5, "completion_tokens": 2},
        },
        "gpt-test",
        id="openai",
    ),
]


@pytest.mark.parametrize("kill_value", ["true", "TRUE", "yes", "on"])
@pytest.mark.parametrize(
    "provider,module_path,adapter_cls_name,config_factory,mock_response,model_id",
    _ADAPTER_ROUTING_CASES,
)
def test_disss_001_pin_adapter_routes_legacy_across_all_providers(
    monkeypatch,
    kill_value,
    provider,
    module_path,
    adapter_cls_name,
    config_factory,
    mock_response,
    model_id,
):
    """End-to-end DISS-001 + cycle-2 DISS-003 pin: with non-strict truthy
    kill-switch value, the adapter routes through the legacy `http_post`
    path, NOT `http_post_stream`. Parametrized across Anthropic + OpenAI
    so a future refactor that regresses a single adapter back to `== "1"`
    fails immediately.

    Google adapter uses `_call_with_retry` (not direct `http_post`) on
    the legacy path, so its mock pattern differs slightly — covered by
    `test_google_adapter_routes_legacy_under_non_strict_kill_switch` below.
    """
    import importlib

    module = importlib.import_module(module_path)
    AdapterCls = getattr(module, adapter_cls_name)

    from loa_cheval.types import CompletionRequest

    monkeypatch.setenv("LOA_CHEVAL_DISABLE_STREAMING", kill_value)

    adapter = AdapterCls(config_factory())
    request = CompletionRequest(
        messages=[{"role": "user", "content": "hi"}],
        model=model_id,
        max_tokens=64,
        temperature=0.0,
    )

    with patch.object(
        module, "http_post", return_value=(200, mock_response)
    ) as nonstream_mock, patch.object(
        module, "http_post_stream"
    ) as stream_mock:
        result = adapter.complete(request)

    assert nonstream_mock.called, (
        f"DISS-001 regression for {provider}: with "
        f"LOA_CHEVAL_DISABLE_STREAMING={kill_value!r}, adapter must use "
        "the legacy non-streaming http_post path"
    )
    assert not stream_mock.called, (
        f"DISS-001 regression for {provider}: with "
        f"LOA_CHEVAL_DISABLE_STREAMING={kill_value!r}, adapter must NOT "
        "call http_post_stream"
    )
    assert result.content == "ok"


@pytest.mark.parametrize("kill_value", ["true", "TRUE", "yes", "on"])
def test_google_adapter_routes_legacy_under_non_strict_kill_switch(
    monkeypatch, kill_value
):
    """Google's legacy path goes through `_call_with_retry` (not direct
    `http_post`). DISS-001 + cycle-2 DISS-003 pin for the Google adapter
    routes through `_call_with_retry` when the kill switch is set; the
    streaming `http_post_stream` is NOT called.
    """
    from loa_cheval.providers import google_adapter
    from loa_cheval.providers.google_adapter import GoogleAdapter
    from loa_cheval.types import CompletionRequest

    monkeypatch.setenv("LOA_CHEVAL_DISABLE_STREAMING", kill_value)

    adapter = GoogleAdapter(_build_google_config())
    request = CompletionRequest(
        messages=[{"role": "user", "content": "hi"}],
        model="gemini-test",
        max_tokens=64,
        temperature=0.0,
    )

    mock_response = {
        "candidates": [
            {
                "content": {"parts": [{"text": "ok"}], "role": "model"},
                "index": 0,
                "finishReason": "STOP",
            }
        ],
        "usageMetadata": {
            "promptTokenCount": 5,
            "candidatesTokenCount": 2,
            "totalTokenCount": 7,
        },
        "modelVersion": "gemini-test",
    }

    with patch.object(
        google_adapter, "_call_with_retry", return_value=(200, mock_response)
    ) as nonstream_mock, patch.object(
        google_adapter, "http_post_stream"
    ) as stream_mock:
        result = adapter.complete(request)

    assert nonstream_mock.called, (
        f"DISS-001 regression for google: with "
        f"LOA_CHEVAL_DISABLE_STREAMING={kill_value!r}, adapter must use "
        "the legacy _call_with_retry path"
    )
    assert not stream_mock.called, (
        f"DISS-001 regression for google: with "
        f"LOA_CHEVAL_DISABLE_STREAMING={kill_value!r}, adapter must NOT "
        "call http_post_stream"
    )
    assert result.content == "ok"
