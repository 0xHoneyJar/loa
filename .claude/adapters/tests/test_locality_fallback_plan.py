"""cycle-129 audit a257-1 MEDIUM-A1 (a)(b) — under `hounfour.locality: local_voices` cheval itself, the process that
sends the prompt, keeps the walk on hops that pass the local-hop rule (SDD D-8.1).

(a) `cheval._plan_around_locality`, applied where `_plan_around_agy` is applied:
  * a chain `[local-a, hosted]` plans only `local-a`; stderr names the dropped hop
    (`locality: local_voices refuses hosted hop <provider>:<model> (fallback of <alias>)`), MODELINV records it in
    `models_not_planned` with `reason: locality_refused`, and the stub local server answers;
  * a hosted primary in front of a local fallback is dropped with `(primary)` and the local hop answers;
  * a chain with no local hop (`[hosted]`) refuses the call before any dispatch: a typed `LocalityRefusedError`
    (`locality: local_voices refuses every hop of <alias> …`), exit INVALID_CONFIG and a MODELINV row whose
    `models_failed` carry `failure_class: locality_refused`;
  * under `hosted` (or unset) the chain is unchanged.
(b) the loader, only under `local_voices`, refuses a `dispatch_group: local` model whose `fallback_chain` names a hop
    that fails the rule — a `provider:model` pin, an alias resolved through `hounfour.aliases`, or an entry that does
    not resolve — and admits the same config under `hosted`.

The local server is a stub bound to 127.0.0.1 that the test starts and stops; every MODELINV payload captured is
validated against the shipped payload schema.
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
from loa_cheval.routing.chain_resolver import resolve as resolve_chain  # noqa: E402
from loa_cheval.types import ConfigError, LocalityRefusedError  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parents[3]
DEFAULTS = REPO_ROOT / ".claude" / "defaults" / "model-config.yaml"
PAYLOAD_SCHEMA = (REPO_ROOT / ".claude" / "data" / "trajectory-schemas" / "model-events"
                  / "model-invoke-complete.payload.schema.json")


def _validator() -> jsonschema.Draft202012Validator:
    schema = json.loads(PAYLOAD_SCHEMA.read_text())
    schema["properties"]["models_failed"]["items"]["properties"]["error_class"] = {"type": "string"}
    return jsonschema.Draft202012Validator(schema)


VALIDATOR = _validator()


class _Stub:
    """A non-streaming-tolerant OpenAI-compatible stub: answers every POST with one SSE completion."""

    def __init__(self) -> None:
        stub = self
        self.requests: List[Dict[str, Any]] = []

        class H(BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def do_POST(self) -> None:  # noqa: N802
                length = int(self.headers.get("Content-Length") or 0)
                body = json.loads(self.rfile.read(length) or b"{}")
                stub.requests.append({"path": self.path, "body": body})
                events = [
                    {"choices": [{"delta": {"role": "assistant", "content": "local answer"}}]},
                    {"choices": [{"delta": {}, "finish_reason": "stop"}]},
                    {"choices": [], "usage": {"prompt_tokens": 9, "completion_tokens": 2}},
                ]
                raw = b"".join(f"data: {json.dumps(dict(e, model=body.get('model')))}\n\n".encode() for e in events)
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


def _model(group: str, fallback: Optional[List[str]] = None) -> Dict[str, Any]:
    m: Dict[str, Any] = {"endpoint_family": "chat", "auth_type": "http_api", "dispatch_group": group,
                         "capabilities": ["chat"], "context_window": 32768, "max_output_tokens": 256,
                         "pricing": {"input_per_mtok": 0, "output_per_mtok": 0}}
    if fallback is not None:
        m["fallback_chain"] = fallback
    return m


def _hounfour(port: int, models: Dict[str, Any], *, locality: Optional[str] = None,
              aliases: Optional[Dict[str, str]] = None) -> Dict[str, Any]:
    h: Dict[str, Any] = {
        "providers": {
            "local": {
                "type": "openai_compat", "endpoint": f"http://127.0.0.1:{port}/v1", "keyless": True,
                "allow_insecure_endpoint": "127.0.0.1", "models": models,
            }
        },
        "aliases": dict({"la": "local:qwen-a", "lp": "local:qwen-plain"}, **(aliases or {})),
        "feature_flags": {"metering": False},
    }
    if locality:
        h["locality"] = locality
    return h


def _load(tmp_path: Path, hounfour: Dict[str, Any]) -> Dict[str, Any]:
    root = tmp_path / "proj"
    (root / ".claude" / "defaults").mkdir(parents=True, exist_ok=True)
    shutil.copy(DEFAULTS, root / ".claude" / "defaults" / "model-config.yaml")
    (root / ".loa.config.yaml").write_text(yaml.safe_dump({"hounfour": hounfour}, sort_keys=False))
    clear_config_cache()
    merged, _ = load_config(project_root=str(root))
    return merged


def _args(model: str) -> Any:
    return types.SimpleNamespace(
        agent="flatline-reviewer", role=None, skill=None, sprint_kind=None, input=None, prompt="review this",
        system=None, model=model, max_tokens=128, output_format="text", json_errors=True, timeout=30,
        include_thinking=False, async_mode=False, poll_id=None, cancel_id=None, dry_run=False, print_config=False,
        validate_bindings=False, mock_fixture_dir=None, max_input_tokens=None, json_schema=None, effort=None,
    )


@pytest.fixture(autouse=True)
def _quiet(monkeypatch):
    monkeypatch.setattr(cheval, "_load_persona", lambda *_a, **_kw: None)
    monkeypatch.setattr(cheval, "_load_persona_parts", lambda *_a, **_kw: (None, None))
    monkeypatch.setattr(cheval, "_check_feature_flags", lambda *_a, **_kw: None)
    monkeypatch.delenv("LOA_HEADLESS_MODE", raising=False)
    for var in ("HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "http_proxy", "https_proxy", "all_proxy"):
        monkeypatch.delenv(var, raising=False)
    from loa_cheval.providers import base
    base._reset_http_client_detection_for_tests()


def _invoke(merged: Dict[str, Any], model: str) -> Dict[str, Any]:
    captured: Dict[str, Any] = {}

    def fake_emit(level, event, payload, *_a, **_kw):
        captured.update(copy.deepcopy(payload))

    with patch.object(cheval, "load_config", return_value=(merged, {})), \
         patch("loa_cheval.audit_envelope.audit_emit", fake_emit), \
         patch("loa_cheval.audit.modelinv.redact_payload_strings", side_effect=lambda x: x), \
         patch("loa_cheval.audit.modelinv.assert_no_secret_shapes_remain"):
        captured["__exit__"] = cheval.cmd_invoke(_args(model))
    return captured


def _assert_schema_valid(row: Dict[str, Any]) -> None:
    body = {k: v for k, v in row.items() if k != "__exit__"}
    errors = sorted(VALIDATOR.iter_errors(body), key=lambda e: list(e.path))
    assert not errors, [f"{list(e.path)}: {e.message}" for e in errors]


# --- (a) the planner --------------------------------------------------------------------------------------


def test_local_then_hosted_plans_only_the_local_hop_and_names_the_drop(tmp_path, stub, capsys):
    """[local-a, hosted] under local_voices: only local-a is planned and dispatched; the drop is named. The loader
    would refuse this config under local_voices (part (b)), so it is loaded under hosted and the posture is switched
    on the merged view — the planner is the defence that holds whatever view cheval is handed."""
    models = {"qwen-a": _model("local", ["local:qwen-plain"]), "qwen-plain": _model("lan")}
    merged = _load(tmp_path, _hounfour(stub.port, models))
    merged["locality"] = "local_voices"
    row = _invoke(merged, "la")
    out = capsys.readouterr()
    assert row["__exit__"] == 0, out.err
    assert out.out.strip() == "local answer"
    assert "locality: local_voices refuses hosted hop local:qwen-plain (fallback of la)" in out.err.splitlines()
    assert [r["body"]["model"] for r in stub.requests] == ["qwen-a"]
    assert row["models_requested"] == ["local:qwen-a"]
    assert row["models_not_planned"] == [{"model": "local:qwen-plain", "provider": "local", "reason": "locality_refused"}]
    assert row["models_succeeded"] == ["local:qwen-a"]
    assert row["locality_mode"] == "local_voices" and row["hop_locality"] == "local"
    _assert_schema_valid(row)


def test_a_hosted_primary_is_dropped_as_primary_and_the_local_fallback_answers(tmp_path, stub, capsys):
    models = {"qwen-plain": _model("lan", ["local:qwen-a"]), "qwen-a": _model("local")}
    merged = _load(tmp_path, _hounfour(stub.port, models, locality="local_voices"))   # (b) admits it: primary not local
    row = _invoke(merged, "lp")
    out = capsys.readouterr()
    assert row["__exit__"] == 0, out.err
    assert "locality: local_voices refuses hosted hop local:qwen-plain (primary)" in out.err.splitlines()
    assert [r["body"]["model"] for r in stub.requests] == ["qwen-a"]
    assert row["models_requested"] == ["local:qwen-a"]
    _assert_schema_valid(row)


def test_a_chain_with_no_local_hop_is_refused_with_a_modelinv_row(tmp_path, stub, capsys):
    models = {"qwen-plain": _model("lan"), "qwen-a": _model("local")}
    merged = _load(tmp_path, _hounfour(stub.port, models, locality="local_voices"))
    row = _invoke(merged, "lp")
    err = capsys.readouterr().err
    assert row["__exit__"] == cheval.EXIT_CODES["INVALID_CONFIG"], err
    assert stub.requests == []                                   # nothing sent
    assert "locality: local_voices refuses hosted hop local:qwen-plain (primary)" in err.splitlines()
    envelope = json.loads([ln for ln in err.splitlines() if ln.startswith("{")][-1])
    assert envelope["code"] == "INVALID_CONFIG" and envelope["failure_class"] == "locality_refused"
    assert envelope["message"].startswith("locality: local_voices refuses every hop of lp")
    assert row["models_requested"] == ["local:qwen-plain"]
    assert row["models_succeeded"] == []
    assert [(f["model"], f["error_class"], f["failure_class"]) for f in row["models_failed"]] == [
        ("local:qwen-plain", "INVALID_CONFIG", "locality_refused")]
    assert row["models_failed"][0]["message_redacted"].startswith("locality: local_voices refuses every hop of lp")
    assert row["locality_mode"] == "local_voices" and row["hop_locality"] == "hosted"
    _assert_schema_valid(row)


def test_the_planner_raises_the_typed_error_directly(tmp_path):
    models = {"qwen-plain": _model("lan"), "qwen-a": _model("local")}
    merged = _load(tmp_path, _hounfour(1, models, locality="local_voices"))
    chain = resolve_chain("lp", model_config=merged)
    with pytest.raises(LocalityRefusedError) as exc:
        cheval._plan_around_locality(chain, merged)
    assert exc.value.detail.startswith("locality: local_voices refuses every hop of lp")
    assert exc.value.failure_class == "locality_refused" and exc.value.code == "INVALID_CONFIG"


@pytest.mark.parametrize("posture", [None, "hosted"])
def test_under_hosted_the_chain_is_unchanged(tmp_path, stub, capsys, posture):
    models = {"qwen-a": _model("local", ["local:qwen-plain"]), "qwen-plain": _model("lan")}
    merged = _load(tmp_path, _hounfour(stub.port, models, locality=posture))   # (b) is silent under hosted
    chain = resolve_chain("la", model_config=merged)
    planned, skipped = cheval._plan_around_locality(chain, merged)
    assert planned is chain and skipped == []
    row = _invoke(merged, "la")
    err = capsys.readouterr().err
    assert row["__exit__"] == 0, err
    assert "locality:" not in err
    assert row["models_requested"] == ["local:qwen-a", "local:qwen-plain"]
    assert "models_not_planned" not in row


def test_a_cli_hop_is_hosted_whatever_its_label(tmp_path):
    from loa_cheval.routing.types import ResolvedChain, ResolvedEntry
    merged = {"locality": "local_voices", "providers": {"local": {
        "type": "openai_compat", "endpoint": "http://127.0.0.1:9/v1",
        "models": {"qwen-a": {"dispatch_group": "local"}, "qwen-cli": {"dispatch_group": "local", "kind": "cli"}}}}}
    chain = ResolvedChain(primary_alias="la", headless_mode="prefer-api", headless_mode_source="default", entries=(
        ResolvedEntry(provider="local", model_id="qwen-a", adapter_kind="http", capabilities=frozenset({"chat"})),
        ResolvedEntry(provider="local", model_id="qwen-cli", adapter_kind="cli", capabilities=frozenset({"chat"}))))
    planned, skipped = cheval._plan_around_locality(chain, merged)
    assert [e.model_id for e in planned.entries] == ["qwen-a"]
    assert skipped == [{"model": "local:qwen-cli", "provider": "local", "reason": "locality_refused"}]


# --- (b) the loader ---------------------------------------------------------------------------------------


@pytest.mark.parametrize("fallback", ["local:qwen-plain", "lp", "no-such-alias"])
def test_the_loader_refuses_a_local_model_that_falls_back_to_a_hosted_hop(tmp_path, fallback):
    models = {"qwen-a": _model("local", [fallback]), "qwen-plain": _model("lan")}
    with pytest.raises(ConfigError) as exc:
        _load(tmp_path, _hounfour(1, models, locality="local_voices"))
    assert str(exc.value).endswith(f"[CONFIG-INVALID] providers.local.models.qwen-a: under hounfour.locality "
                                   f"local_voices the fallback_chain reaches a hosted hop {fallback}"), str(exc.value)


@pytest.mark.parametrize("fallback", ["local:qwen-b", "lb"])
def test_the_loader_admits_a_local_model_whose_fallbacks_are_local(tmp_path, fallback):
    models = {"qwen-a": _model("local", [fallback]), "qwen-b": _model("local")}
    merged = _load(tmp_path, _hounfour(1, models, locality="local_voices", aliases={"lb": "local:qwen-b"}))
    assert merged["providers"]["local"]["models"]["qwen-a"]["fallback_chain"] == [fallback]


def test_the_loader_admits_a_hosted_fallback_under_hosted(tmp_path):
    models = {"qwen-a": _model("local", ["local:qwen-plain"]), "qwen-plain": _model("lan")}
    merged = _load(tmp_path, _hounfour(1, models, locality="hosted"))
    assert merged["locality"] == "hosted"
