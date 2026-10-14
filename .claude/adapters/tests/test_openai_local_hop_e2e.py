"""cycle-129 FR-7 / FR-8 (SDD D-7.2, D-7.3, D-8.0; sprint-257 Task 3.2, AC-3.2) — a local
OpenAI-compatible hop end to end through `cheval.cmd_invoke`, the real loader and the real
OpenAI adapter, against a stub server the test binds to 127.0.0.1 and stops.

* The stub streams `reasoning_content` deltas, then a `<think>`-prefixed answer: the
  answer printed is the JSON alone, and the MODELINV row records `thinking_stripped`,
  `schema_enforced` (response_format carried for a `structured_json` entry),
  `destination: {host, scheme, provider}`, `locality_mode` and `hop_locality: local`.
* A stub that rejects `response_format` with HTTP 400: one retry without it,
  `schema_enforced: false`, `schema_rejected_by_server: true`.
* A prompt over the declared `context_window` refuses the hop with
  `context_window exceeded (<n> > <limit>) for <alias>`, writes a MODELINV row with
  `failure_class: context_window_refused`, and sends nothing to the server.
* A hosted hop records `hop_locality: hosted` and its https destination.

Every MODELINV payload captured here is validated against the shipped payload schema.
"""

from __future__ import annotations

import copy
import json
import shutil
import sys
import threading
import types
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from typing import Any, Dict, List, Optional
from unittest.mock import patch

import jsonschema
import pytest
import yaml

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import cheval  # type: ignore[import-not-found]  # noqa: E402
from loa_cheval.config.loader import clear_config_cache, load_config  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parents[3]
DEFAULTS = REPO_ROOT / ".claude" / "defaults" / "model-config.yaml"
PAYLOAD_SCHEMA = (REPO_ROOT / ".claude" / "data" / "trajectory-schemas" / "model-events"
                  / "model-invoke-complete.payload.schema.json")
WIRE_SCHEMA = {"type": "object", "properties": {"findings": {"type": "array"}}, "required": ["findings"]}


def _payload_validator() -> jsonschema.Draft202012Validator:
    schema = json.loads(PAYLOAD_SCHEMA.read_text())
    # the error_class enum lives in a sibling schema behind a loa:// $ref; a string suffices here
    schema["properties"]["models_failed"]["items"]["properties"]["error_class"] = {"type": "string"}
    return jsonschema.Draft202012Validator(schema)


VALIDATOR = _payload_validator()


# --- the stub server -----------------------------------------------------------------------------------------


class _Stub:
    def __init__(self, mode: str = "stream-think") -> None:
        stub = self
        self.mode = mode
        self.requests: List[Dict[str, Any]] = []

        class H(BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def do_POST(self) -> None:  # noqa: N802
                length = int(self.headers.get("Content-Length") or 0)
                body = json.loads(self.rfile.read(length) or b"{}")
                stub.requests.append({"path": self.path, "headers": dict(self.headers), "body": body})
                if stub.mode == "reject-schema" and "response_format" in body:
                    payload = json.dumps({"object": "error", "message": "response_format json_schema unsupported",
                                          "code": 400}).encode()
                    self.send_response(400)
                    self.send_header("Content-Type", "application/json")
                    self.send_header("Content-Length", str(len(payload)))
                    self.end_headers()
                    self.wfile.write(payload)
                    return
                events = [
                    {"choices": [{"delta": {"role": "assistant", "reasoning_content": "Reading the diff. "}}]},
                    {"choices": [{"delta": {"reasoning_content": "Nothing is wrong."}}]},
                    {"choices": [{"delta": {"content": "<think>double-check</think>"}}]},
                    {"choices": [{"delta": {"content": '{"findings": []}'}}]},
                    {"choices": [{"delta": {}, "finish_reason": "stop"}]},
                    {"choices": [], "usage": {"prompt_tokens": 12, "completion_tokens": 7}},
                ]
                raw = b"".join(f"data: {json.dumps(dict(e, model='qwen3-coder-30b'))}\n\n".encode() for e in events)
                raw += b"data: [DONE]\n\n"
                self.send_response(200)
                self.send_header("Content-Type", "text/event-stream")
                self.send_header("Content-Length", str(len(raw)))
                self.end_headers()
                self.wfile.write(raw)

            def log_message(self, *args: Any) -> None:
                pass

        self.server = HTTPServer(("127.0.0.1", 0), H)
        self.port = self.server.server_port
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def stop(self) -> None:
        self.server.shutdown()
        self.server.server_close()


@pytest.fixture
def stub():
    s = _Stub()
    yield s
    s.stop()


# --- harness -----------------------------------------------------------------------------------------------


def _local_hounfour(port: int, *, context_window: int = 32768, caps: Optional[List[str]] = None,
                    locality: Optional[str] = None) -> Dict[str, Any]:
    h: Dict[str, Any] = {
        "providers": {
            "local": {
                "type": "openai_compat",
                "endpoint": f"http://127.0.0.1:{port}/v1",
                "keyless": True,
                "allow_insecure_endpoint": "127.0.0.1",
                "models": {
                    "qwen3-coder-30b": {
                        "endpoint_family": "chat", "auth_type": "http_api", "dispatch_group": "local",
                        "capabilities": caps or ["chat", "structured_json"],
                        "context_window": context_window, "max_output_tokens": 512,
                        "streaming_recovery": {"first_token_deadline_s": 120},
                        "pricing": {"input_per_mtok": 0, "output_per_mtok": 0},
                    }
                },
            }
        },
        "aliases": {"local-reviewer": "local:qwen3-coder-30b"},
        "feature_flags": {"metering": False},
    }
    if locality:
        h["locality"] = locality
    return h


def _merged(tmp_path: Path, hounfour: Dict[str, Any]) -> Dict[str, Any]:
    root = tmp_path / "proj"
    (root / ".claude" / "defaults").mkdir(parents=True, exist_ok=True)
    shutil.copy(DEFAULTS, root / ".claude" / "defaults" / "model-config.yaml")
    (root / ".loa.config.yaml").write_text(yaml.safe_dump({"hounfour": hounfour}, sort_keys=False))
    clear_config_cache()
    merged, _ = load_config(project_root=str(root))
    return merged


def _args(prompt: str, *, model: str = "local-reviewer", json_schema: Optional[str] = None) -> Any:
    a = types.SimpleNamespace()
    a.agent = "flatline-reviewer"
    a.role = None
    a.skill = None
    a.sprint_kind = None
    a.input = None
    a.prompt = prompt
    a.system = None
    a.model = model
    a.max_tokens = 256
    a.output_format = "text"
    a.json_errors = True
    a.timeout = 30
    a.include_thinking = False
    a.async_mode = False
    a.poll_id = None
    a.cancel_id = None
    a.dry_run = False
    a.print_config = False
    a.validate_bindings = False
    a.mock_fixture_dir = None
    a.max_input_tokens = None
    a.json_schema = json_schema
    a.effort = None
    return a


@pytest.fixture(autouse=True)
def _quiet(monkeypatch):
    monkeypatch.setattr(cheval, "_load_persona", lambda *_a, **_kw: None)
    monkeypatch.setattr(cheval, "_load_persona_parts", lambda *_a, **_kw: (None, None))
    monkeypatch.setattr(cheval, "_check_feature_flags", lambda *_a, **_kw: None)
    for var in ("HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "http_proxy", "https_proxy", "all_proxy"):
        monkeypatch.setenv(var, "http://127.0.0.1:1")   # a dead proxy: the local hop must ignore it
    monkeypatch.delenv("LOA_CHEVAL_DISABLE_STREAMING", raising=False)
    from loa_cheval.providers import base
    base._reset_http_client_detection_for_tests()


def _invoke(merged: Dict[str, Any], args: Any) -> Dict[str, Any]:
    captured: Dict[str, Any] = {}

    def fake_emit(level, event, payload, *_a, **_kw):
        captured.update(copy.deepcopy(payload))

    with patch.object(cheval, "load_config", return_value=(merged, {})), \
         patch("loa_cheval.audit_envelope.audit_emit", fake_emit), \
         patch("loa_cheval.audit.modelinv.redact_payload_strings", side_effect=lambda x: x), \
         patch("loa_cheval.audit.modelinv.assert_no_secret_shapes_remain"):
        captured["__exit__"] = cheval.cmd_invoke(args)
    return captured


def _assert_schema_valid(payload: Dict[str, Any]) -> None:
    body = {k: v for k, v in payload.items() if k != "__exit__"}
    errors = sorted(VALIDATOR.iter_errors(body), key=lambda e: list(e.path))
    assert not errors, [f"{list(e.path)}: {e.message}" for e in errors]


# --- tests -------------------------------------------------------------------------------------------------


def test_local_hop_streams_reasoning_strips_think_and_records_destination(tmp_path, stub, capsys):
    schema_file = tmp_path / "adversarial-finding.wire.json"
    schema_file.write_text(json.dumps(WIRE_SCHEMA))
    merged = _merged(tmp_path, _local_hounfour(stub.port))
    row = _invoke(merged, _args("Review this diff: x = 1", json_schema=str(schema_file)))
    out = capsys.readouterr()
    assert row["__exit__"] == 0, out.err
    assert out.out.strip() == '{"findings": []}'          # no reasoning, no <think>
    req = stub.requests[0]
    assert req["path"] == "/v1/chat/completions"
    assert "Authorization" not in req["headers"]
    assert req["body"]["response_format"]["type"] == "json_schema"
    assert req["body"]["response_format"]["json_schema"]["strict"] is True
    assert row["models_succeeded"] == ["local:qwen3-coder-30b"]
    assert row["schema_enforced"] is True
    assert row["thinking_stripped"] is True
    assert row["destination"] == {"host": f"127.0.0.1:{stub.port}", "scheme": "http", "provider": "local"}
    assert row["locality_mode"] == "hosted"
    assert row["hop_locality"] == "local"
    assert "schema_rejected_by_server" not in row
    _assert_schema_valid(row)


def test_server_rejecting_response_format_is_retried_once_and_recorded(tmp_path, capsys):
    s = _Stub(mode="reject-schema")
    try:
        schema_file = tmp_path / "adversarial-finding.wire.json"
        schema_file.write_text(json.dumps(WIRE_SCHEMA))
        merged = _merged(tmp_path, _local_hounfour(s.port, locality="local_voices"))
        row = _invoke(merged, _args("Review this diff", json_schema=str(schema_file)))
    finally:
        s.stop()
    out = capsys.readouterr()
    assert row["__exit__"] == 0, out.err
    assert [("response_format" in r["body"]) for r in s.requests] == [True, False]
    assert row["schema_enforced"] is False
    assert row["schema_rejected_by_server"] is True
    assert row["locality_mode"] == "local_voices"
    _assert_schema_valid(row)


def test_prompt_over_the_declared_context_window_refuses_the_hop(tmp_path, stub, capsys):
    merged = _merged(tmp_path, _local_hounfour(stub.port, context_window=600))
    row = _invoke(merged, _args("word " * 4000))
    err = capsys.readouterr().err
    assert row["__exit__"] == cheval.EXIT_CODES["CONTEXT_TOO_LARGE"], err
    assert stub.requests == []                               # nothing sent, nothing truncated
    failed = row["models_failed"]
    assert len(failed) == 1
    assert failed[0]["failure_class"] == "context_window_refused"
    assert failed[0]["error_class"] == "ROUTING_MISS"
    assert failed[0]["message_redacted"].startswith("context_window exceeded (")
    assert "> 344) for local-reviewer" in failed[0]["message_redacted"]   # 600 − 256 reserved output
    assert "context_window exceeded" in err
    assert row["destination"]["provider"] == "local" and row["hop_locality"] == "local"
    _assert_schema_valid(row)


def test_hosted_hop_records_hosted_locality_and_https_destination(tmp_path):
    merged = _merged(tmp_path, {})
    from loa_cheval.audit.modelinv import hop_telemetry
    t = hop_telemetry("openai:gpt-5.5", merged)
    assert t == {"locality_mode": "hosted", "hop_locality": "hosted",
                 "destination": {"host": "api.openai.com", "scheme": "https", "provider": "openai"}}
    cli = hop_telemetry("openai:codex-headless", merged)
    assert cli["destination"] == {"host": "cli-subprocess", "scheme": "cli", "provider": "openai"}
    assert hop_telemetry(None, merged) == {"locality_mode": "hosted"}
    assert hop_telemetry("openai:gpt-5.5", dict(merged, locality="bogus")).get("locality_mode") is None
