"""cycle-129 FR-7 (SDD D-7.3, §6; sprint-257 Task 3.2, AC-3.2) — structured output on
the OpenAI chat-completions path.

* `_build_chat_body` carries `response_format: {type: json_schema, json_schema: {name,
  schema, strict: true}}` when the request has an output schema AND the model entry
  declares `structured_json`; absent otherwise.
* `schema_enforced` in the result metadata is True only when the body sent carried it.
* An HTTP 400 whose body names `response_format`/`json_schema` is retried once without
  the schema and recorded (`schema_enforced: False`, `schema_rejected_by_server: True`);
  any other 400 is not retried. Streaming and non-streaming transports both.
"""

from __future__ import annotations

import sys
from contextlib import contextmanager
from pathlib import Path
from typing import Any, Dict, List

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from loa_cheval.providers import openai_adapter as oa  # noqa: E402
from loa_cheval.providers.openai_adapter import OpenAIAdapter  # noqa: E402
from loa_cheval.types import CompletionRequest, InvalidInputError, ModelConfig, ProviderConfig  # noqa: E402

SCHEMA = {"type": "object", "properties": {"findings": {"type": "array"}}, "required": ["findings"],
          "additionalProperties": False}


def _cfg(caps: List[str]) -> ProviderConfig:
    return ProviderConfig(
        name="local", type="openai_compat", endpoint="http://127.0.0.1:8000/v1", auth="", keyless=True,
        allow_insecure_endpoint="127.0.0.1",
        models={"m": ModelConfig(capabilities=caps, context_window=32768, endpoint_family="chat",
                                 dispatch_group="local")},
    )


def _req(schema: Any = SCHEMA) -> CompletionRequest:
    meta = {"output_schema_name": "adversarial-finding.wire.json"} if schema is not None else {}
    return CompletionRequest(messages=[{"role": "user", "content": "review"}], model="m", max_tokens=64,
                             output_schema=schema, metadata=meta)


# --- body ---------------------------------------------------------------------------------------------------


def test_chat_body_carries_response_format_for_a_structured_json_entry():
    adapter = OpenAIAdapter(_cfg(["chat", "structured_json"]))
    body = adapter._build_chat_body(_req(), adapter._get_model_config("m"))
    assert body["response_format"] == {
        "type": "json_schema",
        "json_schema": {"name": "adversarial-finding", "schema": SCHEMA, "strict": True},
    }
    assert oa._schema_enforced(body) is True


@pytest.mark.parametrize("caps, schema", [(["chat"], SCHEMA), (["chat", "structured_json"], None)],
                         ids=["no-structured_json-capability", "no-schema-requested"])
def test_chat_body_has_no_response_format_otherwise(caps, schema):
    adapter = OpenAIAdapter(_cfg(caps))
    body = adapter._build_chat_body(_req(schema), adapter._get_model_config("m"))
    assert "response_format" not in body
    assert oa._schema_enforced(body) is False


# --- schema_enforced truth through complete() -----------------------------------------------------------


def _ok_chat() -> Dict[str, Any]:
    return {"choices": [{"message": {"content": '{"findings": []}'}}], "model": "m",
            "usage": {"prompt_tokens": 3, "completion_tokens": 4}}


@pytest.mark.parametrize("caps, expected", [(["chat", "structured_json"], True), (["chat"], False)])
def test_schema_enforced_is_true_only_when_the_body_carried_it(monkeypatch, caps, expected):
    monkeypatch.setenv("LOA_CHEVAL_DISABLE_STREAMING", "1")
    sent: List[Dict[str, Any]] = []

    def fake_post(url, headers, body, connect_timeout=10.0, read_timeout=120.0, policy=None):
        sent.append(body)
        return 200, _ok_chat()

    monkeypatch.setattr(oa, "http_post", fake_post)
    result = OpenAIAdapter(_cfg(caps)).complete(_req())
    assert ("response_format" in sent[0]) is expected
    assert result.metadata["schema_enforced"] is expected
    assert "schema_rejected_by_server" not in result.metadata


# --- the 400 retry ----------------------------------------------------------------------------------------

_REJECTIONS = [
    {"error": {"message": "response_format json_schema is not supported by this server", "type": "BadRequestError"}},
    {"object": "error", "message": "Unknown field: json_schema", "code": 400},
    {"detail": [{"loc": ["body", "response_format"], "msg": "extra fields not permitted"}]},
]


@pytest.mark.parametrize("rejection", _REJECTIONS, ids=["openai-shape", "vllm-shape", "fastapi-shape"])
def test_non_streaming_400_naming_response_format_retries_once_without_it(monkeypatch, rejection):
    monkeypatch.setenv("LOA_CHEVAL_DISABLE_STREAMING", "1")
    sent: List[Dict[str, Any]] = []
    replies = [(400, rejection), (200, _ok_chat())]

    def fake_post(url, headers, body, connect_timeout=10.0, read_timeout=120.0, policy=None):
        sent.append(dict(body))
        return replies.pop(0)

    monkeypatch.setattr(oa, "http_post", fake_post)
    result = OpenAIAdapter(_cfg(["chat", "structured_json"])).complete(_req())
    assert len(sent) == 2
    assert "response_format" in sent[0] and "response_format" not in sent[1]
    assert result.metadata["schema_enforced"] is False
    assert result.metadata["schema_rejected_by_server"] is True
    assert result.content == '{"findings": []}'


def test_a_400_not_naming_response_format_is_not_retried(monkeypatch):
    monkeypatch.setenv("LOA_CHEVAL_DISABLE_STREAMING", "1")
    sent: List[Dict[str, Any]] = []

    def fake_post(url, headers, body, connect_timeout=10.0, read_timeout=120.0, policy=None):
        sent.append(body)
        return 400, {"error": {"message": "max_tokens is too large"}}

    monkeypatch.setattr(oa, "http_post", fake_post)
    with pytest.raises(InvalidInputError, match="max_tokens is too large"):
        OpenAIAdapter(_cfg(["chat", "structured_json"])).complete(_req())
    assert len(sent) == 1


def test_a_second_rejection_is_not_retried_again(monkeypatch):
    monkeypatch.setenv("LOA_CHEVAL_DISABLE_STREAMING", "1")
    sent: List[Dict[str, Any]] = []

    def fake_post(url, headers, body, connect_timeout=10.0, read_timeout=120.0, policy=None):
        sent.append(body)
        return 400, {"error": {"message": "response_format unsupported"}}

    monkeypatch.setattr(oa, "http_post", fake_post)
    with pytest.raises(InvalidInputError):
        OpenAIAdapter(_cfg(["chat", "structured_json"])).complete(_req())
    assert len(sent) == 2   # the original and exactly one retry without the schema


class _FakeStream:
    def __init__(self, status: int, chunks: List[bytes]):
        self.status_code = status
        self._chunks = chunks

    def iter_bytes(self):
        return iter(self._chunks)


def test_streaming_400_naming_response_format_retries_once_without_it(monkeypatch):
    monkeypatch.delenv("LOA_CHEVAL_DISABLE_STREAMING", raising=False)
    sent: List[Dict[str, Any]] = []
    ok_sse = [
        b'data: {"choices":[{"delta":{"content":"{\\"findings\\": []}"},"finish_reason":null}],"model":"m"}\n\n',
        b'data: {"choices":[{"delta":{},"finish_reason":"stop"}],"model":"m"}\n\n',
        b"data: [DONE]\n\n",
    ]
    replies = [_FakeStream(400, [b'{"error":{"message":"response_format is not supported"}}']),
               _FakeStream(200, ok_sse)]

    @contextmanager
    def fake_stream(url, headers, body, connect_timeout=10.0, read_timeout=120.0, policy=None):
        sent.append(dict(body))
        yield replies.pop(0)

    monkeypatch.setattr(oa, "http_post_stream", fake_stream)
    result = OpenAIAdapter(_cfg(["chat", "structured_json"])).complete(_req())
    assert len(sent) == 2
    assert "response_format" in sent[0] and "response_format" not in sent[1]
    assert result.metadata["schema_enforced"] is False
    assert result.metadata["schema_rejected_by_server"] is True
    assert result.content == '{"findings": []}'


def test_the_heuristic():
    assert oa._names_response_format(400, {"error": {"message": "bad RESPONSE_FORMAT"}})
    assert oa._names_response_format(400, "json_schema: unsupported")
    assert not oa._names_response_format(422, {"error": {"message": "response_format"}})
    assert not oa._names_response_format(400, {"error": {"message": "context length exceeded"}})
