"""cycle-124 Sprint 2 Task 2.2 (FR-7 / SDD §2.2) — schema-enforced output on the wire.

`request.output_schema` becomes `output_config.format = {type: json_schema,
schema}` ONLY on entries whose catalog capabilities include `structured_json`;
other entries run unenforced; LOA_CHEVAL_LEGACY_WIRE omits it; `output_schema
None` leaves the body byte-identical. `metadata.schema_enforced` is derived from
the body actually sent, on both transports.
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

SCHEMA = {"type": "object", "properties": {"ok": {"type": "boolean"}}, "required": ["ok"], "additionalProperties": False}
MODEL = "claude-opus-5"


@pytest.fixture(autouse=True)
def _clean_env(monkeypatch):
    monkeypatch.delenv("LOA_CHEVAL_LEGACY_WIRE", raising=False)


def _config(caps) -> ProviderConfig:
    return ProviderConfig(
        name="anthropic", type="anthropic", endpoint="https://api.anthropic.com/v1",
        auth="sk-ant-test", connect_timeout=10.0, read_timeout=30.0,
        models={MODEL: ModelConfig(capabilities=list(caps), context_window=1_000_000,
                                   params={"temperature_supported": False, "thinking_adaptive": True})},
    )


def _req(schema=SCHEMA, **kw) -> CompletionRequest:
    base = dict(messages=[{"role": "user", "content": "hi"}], model=MODEL, max_tokens=64, output_schema=schema)
    base.update(kw)
    return CompletionRequest(**base)


def _capture(monkeypatch, config, request, streaming: bool) -> dict:
    if streaming:
        monkeypatch.delenv("LOA_CHEVAL_DISABLE_STREAMING", raising=False)
        name = "_complete_streaming"
    else:
        monkeypatch.setenv("LOA_CHEVAL_DISABLE_STREAMING", "1")
        name = "_complete_nonstreaming"
    adapter = AnthropicAdapter(config)
    seen: dict = {}

    def _fake(url, headers, body):
        seen["body"] = body
        return "sentinel"

    monkeypatch.setattr(adapter, name, _fake)
    adapter.complete(request)
    return seen["body"]


@pytest.mark.parametrize("streaming", [False, True])
def test_structured_json_entry_emits_output_config_format(monkeypatch, streaming):
    body = _capture(monkeypatch, _config(["chat", "structured_json"]), _req(), streaming)
    assert body["output_config"]["format"] == {"type": "json_schema", "schema": SCHEMA}
    assert "tool_choice" not in body


@pytest.mark.parametrize("streaming", [False, True])
def test_entry_without_the_capability_runs_unenforced(monkeypatch, streaming):
    body = _capture(monkeypatch, _config(["chat"]), _req(), streaming)
    assert "output_config" not in body


def test_legacy_wire_omits_the_format(monkeypatch):
    monkeypatch.setenv("LOA_CHEVAL_LEGACY_WIRE", "1")
    body = _capture(monkeypatch, _config(["chat", "structured_json"]), _req(), streaming=False)
    assert "output_config" not in body


def test_no_schema_leaves_the_body_unchanged(monkeypatch):
    with_schema_absent = _capture(monkeypatch, _config(["chat", "structured_json"]), _req(schema=None), streaming=False)
    assert "output_config" not in with_schema_absent


def test_effort_and_format_share_output_config(monkeypatch):
    body = _capture(monkeypatch, _config(["chat", "structured_json"]), _req(effort="high"), streaming=False)
    assert body["output_config"] == {"effort": "high", "format": {"type": "json_schema", "schema": SCHEMA}}


def _ok_response() -> dict:
    return {"id": "m", "model": MODEL, "content": [{"type": "text", "text": "{\"ok\": true}"}],
            "stop_reason": "end_turn", "usage": {"input_tokens": 1, "output_tokens": 1}}


@pytest.mark.parametrize("caps, expected", [(["chat", "structured_json"], True), (["chat"], False)])
def test_nonstreaming_metadata_schema_enforced_is_derived_from_the_body(monkeypatch, caps, expected):
    monkeypatch.setenv("LOA_CHEVAL_DISABLE_STREAMING", "1")
    adapter = AnthropicAdapter(_config(caps))
    with patch("loa_cheval.providers.anthropic_adapter.http_post", return_value=(200, _ok_response())):
        result = adapter.complete(_req())
    assert result.metadata["schema_enforced"] is expected
    assert result.metadata["streaming"] is False


def test_nonstreaming_metadata_flag_false_when_no_schema_requested(monkeypatch):
    monkeypatch.setenv("LOA_CHEVAL_DISABLE_STREAMING", "1")
    adapter = AnthropicAdapter(_config(["chat", "structured_json"]))
    with patch("loa_cheval.providers.anthropic_adapter.http_post", return_value=(200, _ok_response())):
        result = adapter.complete(_req(schema=None))
    assert result.metadata["schema_enforced"] is False


# --- streaming transport: the flag is derived from the same body -------------

def _sse(event: str, data: dict) -> bytes:
    return f"event: {event}\ndata: {json.dumps(data)}\n\n".encode("utf-8")


def _ok_stream_blob() -> bytes:
    return (
        _sse("message_start", {"type": "message_start", "message": {"id": "m", "role": "assistant", "model": MODEL,
                                                                   "content": [], "usage": {"input_tokens": 4, "output_tokens": 1}}})
        + _sse("content_block_start", {"type": "content_block_start", "index": 0, "content_block": {"type": "text", "text": ""}})
        + _sse("content_block_delta", {"type": "content_block_delta", "index": 0, "delta": {"type": "text_delta", "text": "{\"ok\": true}"}})
        + _sse("content_block_stop", {"type": "content_block_stop", "index": 0})
        + _sse("message_delta", {"type": "message_delta", "delta": {"stop_reason": "end_turn"}, "usage": {"output_tokens": 6}})
        + _sse("message_stop", {"type": "message_stop"})
    )


def _mock_ok_stream():
    resp = MagicMock()
    resp.status_code = 200
    resp.http_version = "HTTP/2"
    resp.iter_bytes = MagicMock(return_value=iter([_ok_stream_blob()]))

    @contextmanager
    def fake_http_post_stream(*args, **kwargs):
        yield resp

    return fake_http_post_stream


@pytest.mark.parametrize("caps, expected", [(["chat", "structured_json"], True), (["chat"], False)])
def test_streaming_metadata_schema_enforced_is_derived_from_the_body(monkeypatch, caps, expected):
    monkeypatch.delenv("LOA_CHEVAL_DISABLE_STREAMING", raising=False)
    adapter = AnthropicAdapter(_config(caps))
    with patch("loa_cheval.providers.anthropic_adapter.http_post_stream", _mock_ok_stream()):
        result = adapter.complete(_req())
    assert result.content == '{"ok": true}'
    assert result.metadata["schema_enforced"] is expected
    assert result.metadata["streaming"] is True


# --- late Sprint 2 review (slice C, MEDIUM): the AC-7.1 ids on the LIVE catalog --

def _live_config(model_id: str) -> ProviderConfig:
    import yaml
    catalog = yaml.safe_load((ROOT.parents[1] / ".claude" / "defaults" / "model-config.yaml").read_text())
    entry = catalog["providers"]["anthropic"]["models"][model_id]
    return ProviderConfig(
        name="anthropic", type="anthropic", endpoint="https://api.anthropic.com/v1",
        auth="sk-ant-test", connect_timeout=10.0, read_timeout=30.0,
        models={model_id: ModelConfig(capabilities=list(entry.get("capabilities") or []),
                                      context_window=int(entry.get("context_window") or 200_000),
                                      params=dict(entry.get("params") or {}))},
    )


@pytest.mark.parametrize("streaming", [False, True])
def test_live_catalog_opus_4_8_emits_format_and_opus_4_7_does_not(monkeypatch, streaming):
    body = _capture(monkeypatch, _live_config("claude-opus-4-8"), _req(model="claude-opus-4-8"), streaming)
    assert body["output_config"]["format"] == {"type": "json_schema", "schema": SCHEMA}
    body = _capture(monkeypatch, _live_config("claude-opus-4-7"), _req(model="claude-opus-4-7"), streaming)
    assert "output_config" not in body
