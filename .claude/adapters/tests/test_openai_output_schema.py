"""cycle-124 Sprint 2 Task 2.6 (FR-7 / SDD §2.4, flagged exception, isolated
commit) — OpenAI /v1/responses pass-through: `request.output_schema` becomes
`text.format = {type: json_schema, name, strict: true, schema}`; without a
schema the body keeps the cycle-102 `{type: text}` format byte-for-byte;
`metadata.schema_enforced` is derived from the body on both transports; the
format name is the schema file's basename, sanitized.
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from loa_cheval.providers.openai_adapter import OpenAIAdapter, _output_schema_name  # noqa: E402
from loa_cheval.types import CompletionRequest, CompletionResult, ModelConfig, ProviderConfig, Usage  # noqa: E402

SCHEMA = {"type": "object", "properties": {"ok": {"type": "boolean"}}, "required": ["ok"], "additionalProperties": False}


def _cfg() -> ProviderConfig:
    return ProviderConfig(
        name="openai", type="openai", endpoint="https://api.openai.com/v1", auth="sk-test",
        connect_timeout=10.0, read_timeout=30.0,
        models={"gpt-5.5": ModelConfig(capabilities=["chat"], context_window=400_000, endpoint_family="responses")},
    )


def _req(schema=SCHEMA, name=None) -> CompletionRequest:
    meta = {"agent": "x"}
    if name is not None:
        meta["output_schema_name"] = name
    return CompletionRequest(messages=[{"role": "user", "content": "hi"}], model="gpt-5.5", max_tokens=64,
                             output_schema=schema, metadata=meta)


def test_responses_body_carries_strict_json_schema_format():
    adapter = OpenAIAdapter(_cfg())
    body = adapter._build_responses_body(_req(name="dissent-review.wire.json"), _cfg().models["gpt-5.5"])
    assert body["text"] == {"format": {"type": "json_schema", "name": "dissent-review", "strict": True, "schema": SCHEMA}}


def test_no_schema_keeps_the_text_format_unchanged():
    adapter = OpenAIAdapter(_cfg())
    body = adapter._build_responses_body(_req(schema=None), _cfg().models["gpt-5.5"])
    assert body["text"] == {"format": {"type": "text"}}


@pytest.mark.parametrize("raw, expected", [
    ("dissent-review.wire.json", "dissent-review"),
    ("/abs/path/flatline scorer!.json", "flatline_scorer"),
    ("", "loa_output_schema"),
    ("x" * 100, "x" * 64),
])
def test_format_name_is_sanitized_basename(raw, expected):
    assert _output_schema_name(_req(name=raw)) == expected


def test_format_name_defaults_without_metadata():
    req = CompletionRequest(messages=[{"role": "user", "content": "hi"}], model="gpt-5.5", max_tokens=64, output_schema=SCHEMA)
    assert _output_schema_name(req) == "loa_output_schema"


def _result() -> CompletionResult:
    return CompletionResult(content='{"ok": true}', tool_calls=None, thinking=None,
                            usage=Usage(input_tokens=1, output_tokens=1), model="gpt-5.5",
                            latency_ms=1, provider="openai", metadata={"streaming": True})


@pytest.mark.parametrize("streaming", [True, False])
@pytest.mark.parametrize("schema, expected", [(SCHEMA, True), (None, False)])
def test_metadata_schema_enforced_is_derived_from_the_body(monkeypatch, streaming, schema, expected):
    if streaming:
        monkeypatch.delenv("LOA_CHEVAL_DISABLE_STREAMING", raising=False)
        name = "_complete_streaming"
    else:
        monkeypatch.setenv("LOA_CHEVAL_DISABLE_STREAMING", "1")
        name = "_complete_nonstreaming"
    adapter = OpenAIAdapter(_cfg())
    seen = {}

    def _fake(url, headers, body, family):
        seen["body"] = body
        return _result()

    monkeypatch.setattr(adapter, name, _fake)
    result = adapter.complete(_req(schema=schema))
    assert (seen["body"]["text"]["format"]["type"] == "json_schema") is expected
    assert result.metadata["schema_enforced"] is expected
