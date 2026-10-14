"""cycle-126 Sprint 1 Task 1.1 / 1.3 (PRD FR-1.2, FR-1.3, FR-1.7; SDD D-1.2,
D-1.3, D-1.7) — adapter defaults follow the resolved catalog entry:

- `default_max_tokens`: any provider with a declared `max_output_tokens` gets
  `min(cap, declared)`; 4,096 only without a declaration or under the legacy
  wire kill switch.
- the request's temperature is unset by default and omitted on the wire; the
  legacy wire restores 0.7.
- `params.beta_headers` is validated against the allowlist regex, joined into
  one `anthropic-beta` header, never derived from a request.
- the health probe carries no retired snapshot id: models endpoint first, then
  a one-token message on the `tiny` alias.
"""
from __future__ import annotations

import sys
from pathlib import Path
from unittest.mock import patch

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from loa_cheval.providers import anthropic_adapter as aa  # noqa: E402
from loa_cheval.providers.base import (  # noqa: E402
    _LEGACY_DEFAULT_MAX_TOKENS,
    _NON_ANTHROPIC_DEFAULT_OUTPUT_CAP,
    default_max_tokens,
)
from loa_cheval.types import CompletionRequest, ModelConfig, ProviderConfig  # noqa: E402


@pytest.fixture(autouse=True)
def _env(monkeypatch):
    monkeypatch.delenv("LOA_CHEVAL_LEGACY_WIRE", raising=False)
    monkeypatch.delenv("LOA_CHEVAL_DISABLE_STREAMING", raising=False)


# --- D-1.3 output defaults ---------------------------------------------------

@pytest.mark.parametrize("provider", ["openai", "google", "xai", "bedrock"])
def test_non_anthropic_declared_output_is_honoured_up_to_the_cap(provider):
    assert default_max_tokens(provider=provider, model_max_output=128_000) == _NON_ANTHROPIC_DEFAULT_OUTPUT_CAP
    assert default_max_tokens(provider=provider, model_max_output=8_000) == 8_000
    assert default_max_tokens(provider=provider, model_max_output=None) == _LEGACY_DEFAULT_MAX_TOKENS


def test_anthropic_defaults_are_unchanged():
    assert default_max_tokens(provider="anthropic", model_max_output=128_000) == 64_000
    assert default_max_tokens(provider="anthropic", model_max_output=None) == _LEGACY_DEFAULT_MAX_TOKENS


def test_legacy_wire_restores_4096_everywhere(monkeypatch):
    monkeypatch.setenv("LOA_CHEVAL_LEGACY_WIRE", "1")
    assert default_max_tokens(provider="openai", model_max_output=128_000) == _LEGACY_DEFAULT_MAX_TOKENS
    assert default_max_tokens(provider="anthropic", model_max_output=128_000) == _LEGACY_DEFAULT_MAX_TOKENS


def test_non_anthropic_cap_is_a_named_constant():
    assert _NON_ANTHROPIC_DEFAULT_OUTPUT_CAP == 16_000


# --- D-1.3 temperature ------------------------------------------------------

def _adapter(params=None, capabilities=None):
    cfg = ProviderConfig(
        name="anthropic", type="anthropic", endpoint="https://api.example.invalid/v1", auth="sk-ant-test",
        models={"m": ModelConfig(capabilities=capabilities or ["chat"], context_window=200_000,
                                 params=params or {})},
    )
    return aa.AnthropicAdapter(cfg)


def _body(adapter, request):
    captured = {}

    def fake_post(url, headers, body, **kw):
        captured["headers"] = headers
        captured["body"] = body
        return 200, {"content": [{"type": "text", "text": "ok"}], "usage": {"input_tokens": 1, "output_tokens": 1}, "stop_reason": "end_turn", "model": "m"}

    with patch.object(aa, "http_post", fake_post), patch.object(aa, "_streaming_disabled", lambda: True):
        adapter.complete(request)
    return captured


def test_temperature_is_unset_by_default_and_omitted_on_the_wire():
    req = CompletionRequest(messages=[{"role": "user", "content": "hi"}], model="m")
    assert req.temperature is None
    captured = _body(_adapter(params={"temperature_supported": True}), req)
    assert "temperature" not in captured["body"]


def test_explicit_temperature_is_sent_where_supported_and_dropped_where_not(caplog):
    req = CompletionRequest(messages=[{"role": "user", "content": "hi"}], model="m", temperature=0.2)
    assert _body(_adapter(params={"temperature_supported": True}), req)["body"]["temperature"] == 0.2
    assert "temperature" not in _body(_adapter(params={"temperature_supported": False}), req)["body"]


def test_legacy_wire_restores_the_pre_cycle_default_temperature(monkeypatch):
    monkeypatch.setenv("LOA_CHEVAL_LEGACY_WIRE", "1")
    req = CompletionRequest(messages=[{"role": "user", "content": "hi"}], model="m")
    assert _body(_adapter(params={"temperature_supported": True}), req)["body"]["temperature"] == 0.7


# --- D-1.2 beta headers -----------------------------------------------------

def test_beta_headers_are_joined_when_declared_and_absent_otherwise():
    req = CompletionRequest(messages=[{"role": "user", "content": "hi"}], model="m")
    plain = _body(_adapter(), req)["headers"]
    assert "anthropic-beta" not in plain
    with_beta = _body(_adapter(params={"beta_headers": ["context-1m-2025-08-07", "output-128k-2025-02-19"]}), req)["headers"]
    assert with_beta["anthropic-beta"] == "context-1m-2025-08-07,output-128k-2025-02-19"


@pytest.mark.parametrize("bad", ["Context-1M", "context-1m-2025-08-07; rm", "x y", "", "context_1m_2025_08_07"])
def test_beta_headers_outside_the_allowlist_are_a_config_error(bad):
    from loa_cheval.types import ConfigError
    req = CompletionRequest(messages=[{"role": "user", "content": "hi"}], model="m")
    with pytest.raises(ConfigError):
        _body(_adapter(params={"beta_headers": [bad]}), req)


def test_beta_header_allowlist_regex_is_the_documented_one():
    assert aa._BETA_HEADER_RE.pattern == r"^[a-z0-9]+(-[a-z0-9]+)*-\d{4}-\d{2}-\d{2}$"


# --- D-1.7 health probe -----------------------------------------------------

def test_health_probe_uses_the_models_endpoint_then_the_tiny_alias_and_no_retired_id():
    adapter = _adapter()
    calls = []

    def fake_get(url, headers, **kw):
        calls.append(("GET", url))
        return 404, {}

    def fake_post(url, headers, body, **kw):
        calls.append(("POST", url, body.get("model")))
        return 200, {}

    with patch.object(aa, "http_get", fake_get), patch.object(aa, "http_post", fake_post), \
         patch.object(aa.AnthropicAdapter, "_tiny_model_id", lambda self: "claude-haiku-4-5-20251001"):
        assert adapter.health_check() is True
    assert calls[0][0] == "GET" and calls[0][1].endswith("/models?limit=1")
    assert calls[1] == ("POST", "https://api.example.invalid/v1/messages", "claude-haiku-4-5-20251001")
    src = Path(aa.__file__).read_text()
    assert "claude-3-haiku-20240307" not in src, "no retired snapshot id may remain in the adapter"


def test_health_probe_is_true_on_a_models_endpoint_200_without_a_message_call():
    adapter = _adapter()
    posted = []
    with patch.object(aa, "http_get", lambda url, headers, **kw: (200, {"data": []})), \
         patch.object(aa, "http_post", lambda *a, **k: posted.append(a) or (200, {})):
        assert adapter.health_check() is True
    assert posted == []
