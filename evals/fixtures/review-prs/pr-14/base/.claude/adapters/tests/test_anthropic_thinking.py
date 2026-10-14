"""cycle-124 Sprint 1 Task 1.5 (FR-1 / SDD §3.3) — adaptive thinking on the wire.

`params.thinking_adaptive: true` (catalog) ⇒ `thinking: {type: adaptive}` in
the Anthropic request body; never `budget_tokens`, never `type: disabled`.
Byte-identical body when the flag is absent or LOA_CHEVAL_LEGACY_WIRE is set;
the streaming path inherits the same body; a thinking block that PRECEDES the
text block (the common shape once thinking is on) parses on both transports;
a caller-supplied temperature is dropped with a visible warning.
"""

from __future__ import annotations

import json
import sys
from contextlib import contextmanager
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from loa_cheval.providers.anthropic_adapter import AnthropicAdapter  # noqa: E402
from loa_cheval.types import CompletionRequest, ModelConfig, ProviderConfig  # noqa: E402

ADAPTIVE = ["claude-opus-5", "claude-opus-4-8", "claude-opus-4-7", "claude-opus-4-6",
            "claude-sonnet-5", "claude-sonnet-4-6"]
NOT_ADAPTIVE = ["claude-fable-5-1", "claude-fable-5", "claude-sonnet-4-5-20250929", "claude-haiku-4-5-20251001"]


def _params(model: str) -> dict:
    if model in ADAPTIVE:
        return {"temperature_supported": False, "thinking_adaptive": True}
    if model.startswith("claude-fable"):
        return {"temperature_supported": False}
    return {}


def _make_config(params_override: dict | None = None) -> ProviderConfig:
    return ProviderConfig(
        name="anthropic", type="anthropic", endpoint="https://api.anthropic.com/v1",
        auth="sk-ant-test", connect_timeout=10.0, read_timeout=30.0,
        models={m: ModelConfig(capabilities=["chat"], context_window=1_000_000,
                               params=(params_override if params_override is not None else _params(m)))
                for m in ADAPTIVE + NOT_ADAPTIVE},
    )


def _req(model: str, **kw) -> CompletionRequest:
    base = dict(messages=[{"role": "user", "content": "hi"}], model=model, max_tokens=1024)
    base.update(kw)
    return CompletionRequest(**base)


def _capture_nonstreaming(monkeypatch, config, request) -> dict:
    monkeypatch.setenv("LOA_CHEVAL_DISABLE_STREAMING", "1")
    adapter = AnthropicAdapter(config)
    captured: dict = {}

    def _fake_ns(url, headers, body):
        captured["body"] = body
        return "sentinel"

    monkeypatch.setattr(adapter, "_complete_nonstreaming", _fake_ns)
    adapter.complete(request)
    return captured["body"]


def _capture_streaming(monkeypatch, config, request) -> dict:
    monkeypatch.delenv("LOA_CHEVAL_DISABLE_STREAMING", raising=False)
    adapter = AnthropicAdapter(config)
    captured: dict = {}

    def _fake_stream(url, headers, body):
        captured["body"] = body
        return "sentinel"

    monkeypatch.setattr(adapter, "_complete_streaming", _fake_stream)
    adapter.complete(request)
    return captured["body"]


@pytest.fixture(autouse=True)
def _no_legacy_wire(monkeypatch):
    monkeypatch.delenv("LOA_CHEVAL_LEGACY_WIRE", raising=False)
    # The temperature-drop warning is once-per-model-per-process; start each
    # test with a clean memory so ordering cannot change what it observes.
    import loa_cheval.providers.anthropic_adapter as _aa
    monkeypatch.setattr(_aa, "_TEMPERATURE_DROP_WARNED", set(), raising=False)


# --- emission per family --------------------------------------------------------

@pytest.mark.parametrize("model", ADAPTIVE)
def test_adaptive_entries_emit_thinking_adaptive_and_no_sampling(monkeypatch, model):
    body = _capture_nonstreaming(monkeypatch, _make_config(), _req(model))
    assert body["thinking"] == {"type": "adaptive"}
    assert "budget_tokens" not in json.dumps(body)
    assert "disabled" not in json.dumps(body["thinking"])
    for key in ("temperature", "top_p", "top_k"):
        assert key not in body


@pytest.mark.parametrize("model", NOT_ADAPTIVE)
def test_non_adaptive_entries_omit_thinking(monkeypatch, model):
    body = _capture_nonstreaming(monkeypatch, _make_config(), _req(model))
    assert "thinking" not in body


@pytest.mark.parametrize("model", ADAPTIVE)
def test_streaming_inherits_the_same_body(monkeypatch, model):
    ns = _capture_nonstreaming(monkeypatch, _make_config(), _req(model))
    st = _capture_streaming(monkeypatch, _make_config(), _req(model))
    assert ns == st
    assert st["thinking"] == {"type": "adaptive"}


def test_body_byte_identical_when_flag_absent(monkeypatch):
    cfg_flag_absent = _make_config(params_override={"temperature_supported": False})
    body = _capture_nonstreaming(monkeypatch, cfg_flag_absent, _req("claude-opus-4-8"))
    assert body == {"model": "claude-opus-4-8", "messages": [{"role": "user", "content": "hi"}], "max_tokens": 1024}


@pytest.mark.parametrize("value", ["1", "true", "on"])
def test_legacy_wire_restores_the_pre_cycle_body(monkeypatch, value):
    monkeypatch.setenv("LOA_CHEVAL_LEGACY_WIRE", value)
    body = _capture_nonstreaming(monkeypatch, _make_config(), _req("claude-opus-5"))
    assert body == {"model": "claude-opus-5", "messages": [{"role": "user", "content": "hi"}], "max_tokens": 1024}


def test_legacy_wire_body_per_live_catalog_family(monkeypatch):
    """Scoped claim (review round-1 low 2): under LOA_CHEVAL_LEGACY_WIRE every
    Anthropic HTTP family in the LIVE catalog sends only model/messages/
    max_tokens (+ temperature where the catalog still allows it). The flag
    removes what this cycle ADDED (thinking, cache blocks, format); the
    temperature omission is catalog-driven (`temperature_supported: false`)
    and is NOT restored by the flag — entries that gained that flag this
    cycle drop temperature on the legacy wire too."""
    import yaml
    catalog = yaml.safe_load((ROOT.parents[1] / ".claude" / "defaults" / "model-config.yaml").read_text())
    entries = {m: e for m, e in catalog["providers"]["anthropic"]["models"].items() if e.get("auth_type") == "http_api"}
    assert len(entries) >= 8
    cfg = ProviderConfig(
        name="anthropic", type="anthropic", endpoint="https://api.anthropic.com/v1",
        auth="sk-ant-test", connect_timeout=10.0, read_timeout=30.0,
        models={m: ModelConfig(capabilities=["chat"], context_window=int(e.get("context_window") or 200_000),
                               params=dict(e.get("params") or {})) for m, e in entries.items()},
    )
    monkeypatch.setenv("LOA_CHEVAL_LEGACY_WIRE", "1")
    for model, entry in entries.items():
        body = _capture_nonstreaming(monkeypatch, cfg, _req(model, temperature=0.3))
        expected = {"model": model, "messages": [{"role": "user", "content": "hi"}], "max_tokens": 1024}
        if (entry.get("params") or {}).get("temperature_supported", True):
            expected["temperature"] = 0.3
        assert body == expected, model


def test_flag_value_must_be_literal_true(monkeypatch):
    for bad in ("true", 1, "yes"):
        cfg = _make_config(params_override={"temperature_supported": False, "thinking_adaptive": bad})
        body = _capture_nonstreaming(monkeypatch, cfg, _req("claude-opus-5"))
        assert "thinking" not in body, bad


# --- temperature drop is visible -------------------------------------------------

def test_non_default_temperature_dropped_with_warning(monkeypatch, caplog):
    body = _capture_nonstreaming(monkeypatch, _make_config(), _req("claude-opus-5", temperature=0.3))
    assert "temperature" not in body
    assert any("temperature 0.3 dropped for claude-opus-5" in r.getMessage() for r in caplog.records)


def test_temperature_drop_warns_once_per_model_then_logs_info(monkeypatch, caplog):
    """review round-1 low 1: the framework's bindings run at 0.2–0.6, so a
    per-call WARNING would fire on essentially every dispatch. First drop per
    model is WARNING; later drops for the same model are INFO; a different
    model warns again."""
    import logging
    caplog.set_level(logging.INFO, logger="loa_cheval.providers.anthropic")
    _capture_nonstreaming(monkeypatch, _make_config(), _req("claude-opus-5", temperature=0.3))
    _capture_nonstreaming(monkeypatch, _make_config(), _req("claude-opus-5", temperature=0.4))
    _capture_nonstreaming(monkeypatch, _make_config(), _req("claude-sonnet-5", temperature=0.3))
    drops = [(r.levelno, r.getMessage()) for r in caplog.records if "dropped for" in r.getMessage()]
    assert [lvl for lvl, _ in drops] == [logging.WARNING, logging.INFO, logging.WARNING], drops
    assert "temperature 0.4 dropped for claude-opus-5" in drops[1][1]


def test_default_temperature_drops_silently(monkeypatch, caplog):
    _capture_nonstreaming(monkeypatch, _make_config(), _req("claude-opus-5"))
    assert not any("dropped" in r.getMessage() for r in caplog.records)


# --- thinking-block-first responses parse on both transports ---------------------

def _nonstreaming_thinking_first() -> dict:
    return {
        "id": "msg_1", "model": "claude-opus-5", "role": "assistant",
        "content": [
            {"type": "thinking", "thinking": "Let me weigh the evidence.", "signature": "sig"},
            {"type": "text", "text": "Final answer."},
        ],
        "stop_reason": "end_turn",
        "usage": {"input_tokens": 50, "output_tokens": 20, "cache_read_input_tokens": 40, "cache_creation_input_tokens": 0},
    }


def test_nonstreaming_thinking_block_first_parses(monkeypatch):
    monkeypatch.setenv("LOA_CHEVAL_DISABLE_STREAMING", "1")
    adapter = AnthropicAdapter(_make_config())
    with patch("loa_cheval.providers.anthropic_adapter.http_post", return_value=(200, _nonstreaming_thinking_first())):
        result = adapter.complete(_req("claude-opus-5"))
    assert result.content == "Final answer."
    assert result.thinking == "Let me weigh the evidence."
    assert result.metadata["stop_reason"] == "end_turn"
    assert result.usage.cache_read_input_tokens == 40


def _ev(name: str, data: dict) -> bytes:
    return f"event: {name}\ndata: {json.dumps(data)}\n\n".encode("utf-8")


def _sse_thinking_first() -> bytes:
    return (
        _ev("message_start", {"type": "message_start", "message": {"id": "msg_1", "model": "claude-opus-5", "role": "assistant",
                                                                   "content": [], "usage": {"input_tokens": 50, "output_tokens": 0,
                                                                                            "cache_read_input_tokens": 40,
                                                                                            "cache_creation_input_tokens": 0}}})
        + _ev("content_block_start", {"type": "content_block_start", "index": 0, "content_block": {"type": "thinking", "thinking": ""}})
        + _ev("content_block_delta", {"type": "content_block_delta", "index": 0, "delta": {"type": "thinking_delta", "thinking": "Let me weigh"}})
        + _ev("content_block_delta", {"type": "content_block_delta", "index": 0, "delta": {"type": "signature_delta", "signature": "sig"}})
        + _ev("content_block_stop", {"type": "content_block_stop", "index": 0})
        + _ev("content_block_start", {"type": "content_block_start", "index": 1, "content_block": {"type": "text", "text": ""}})
        + _ev("content_block_delta", {"type": "content_block_delta", "index": 1, "delta": {"type": "text_delta", "text": "Final answer."}})
        + _ev("content_block_stop", {"type": "content_block_stop", "index": 1})
        + _ev("message_delta", {"type": "message_delta", "delta": {"stop_reason": "end_turn"}, "usage": {"output_tokens": 20}})
        + _ev("message_stop", {"type": "message_stop"})
    )


def test_streaming_thinking_block_first_parses(monkeypatch):
    monkeypatch.delenv("LOA_CHEVAL_DISABLE_STREAMING", raising=False)
    adapter = AnthropicAdapter(_make_config())
    resp = MagicMock()
    resp.status_code = 200
    resp.http_version = "HTTP/2"
    resp.iter_bytes = MagicMock(return_value=iter([_sse_thinking_first()]))

    @contextmanager
    def _fake_stream(*_a, **_kw):
        yield resp

    with patch("loa_cheval.providers.anthropic_adapter.http_post_stream", _fake_stream):
        result = adapter.complete(_req("claude-opus-5"))
    assert result.content == "Final answer."
    assert "Let me weigh" in (result.thinking or "")
    assert result.usage.cache_read_input_tokens == 40
    assert result.metadata.get("stop_reason") == "end_turn"


def test_live_catalog_flags_match_the_adaptive_set():
    """Catalog and adapter agree on which ids emit thinking (SDD §2.1 invariant)."""
    import yaml
    catalog = ROOT.parents[1] / ".claude" / "defaults" / "model-config.yaml"
    with catalog.open() as fh:
        models = yaml.safe_load(fh)["providers"]["anthropic"]["models"]
    flagged = sorted(m for m, e in models.items() if (e.get("params") or {}).get("thinking_adaptive") is True)
    assert flagged == sorted(ADAPTIVE)


# --- Bedrock is untouched by the catalog flag (golden body) -----------------------

def test_bedrock_body_identical_with_and_without_thinking_flag(monkeypatch):
    from loa_cheval.providers.bedrock_adapter import BedrockAdapter

    monkeypatch.delenv("AWS_BEDROCK_REGION", raising=False)
    monkeypatch.delenv("AWS_REGION", raising=False)

    def _cfg(params):
        return ProviderConfig(
            name="bedrock", type="bedrock", endpoint="https://bedrock-runtime.{region}.amazonaws.com",
            auth="ABSKR-test-token-not-real", region_default="us-east-1", auth_modes=["api_key", "sigv4"],
            models={"us.anthropic.claude-opus-4-8": ModelConfig(
                capabilities=["chat"], context_window=200_000, token_param="max_tokens",
                api_format={"chat": "converse"}, fallback_to="anthropic:claude-opus-4-8",
                fallback_mapping_version=1, params=params)},
        )

    class _Stop(Exception):
        pass

    def _capture(params) -> dict:
        seen: dict = {}

        def _post(url, headers, body, **kw):
            seen["body"] = body
            raise _Stop()

        with patch("loa_cheval.providers.bedrock_adapter.http_post", side_effect=_post):
            with pytest.raises(_Stop):
                BedrockAdapter(_cfg(params)).complete(
                    CompletionRequest(messages=[{"role": "user", "content": "hi"}],
                                      model="us.anthropic.claude-opus-4-8", max_tokens=64))
        return seen["body"]

    without = _capture({"temperature_supported": False})
    with_flag = _capture({"temperature_supported": False, "thinking_adaptive": True})
    assert without == with_flag
    assert "thinking" not in json.dumps(with_flag)
