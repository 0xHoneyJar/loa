"""cycle-127 sprint-251 review r251-1 C5 extension (finding 24) — the MODELINV
``effort_effective`` field equals what the answering adapter actually puts on
the wire, for EVERY model in the live catalog.

For each (provider, model) the adapter is selected through cheval's own
``_get_adapter_for_entry`` (the dispatch path), a request carrying the
resolved effort is built into the adapter's real body / argv (the HTTP
transport is stubbed to capture the body; nothing is sent), the emitted
effort is read back, and it must equal ``cheval._effort_on_wire``.
"""
from __future__ import annotations

import copy
import sys
import types
from pathlib import Path

import pytest
import yaml

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

import cheval  # type: ignore[import-not-found]  # noqa: E402
from loa_cheval.providers import (  # noqa: E402
    anthropic_adapter as anth_mod,
    bedrock_adapter as bedrock_mod,
    google_adapter as google_mod,
    openai_adapter as openai_mod,
)
from loa_cheval.types import CompletionRequest  # noqa: E402

CATALOG = ROOT.parent / "defaults" / "model-config.yaml"
CATALOG_DATA = yaml.safe_load(CATALOG.read_text())


def _is_cli(entry: dict) -> bool:
    return entry.get("kind") == "cli" or entry.get("auth_type") == "headless"


def _pairs():
    for provider, block in CATALOG_DATA["providers"].items():
        for model_id, entry in (block.get("models") or {}).items():
            yield provider, model_id


class _Captured(Exception):
    def __init__(self, body):
        super().__init__("captured")
        self.body = body


def _capture_post(*args, **kwargs):
    body = kwargs.get("body")
    if body is None:
        # chat bodies carry messages / contents / input; Google's interactions API (api_mode: interactions, Deep
        # Research) carries `query` (review r251-2 K9 / n41)
        body = next((a for a in args if isinstance(a, dict)
                     and ("messages" in a or "contents" in a or "input" in a or "query" in a)), None)
    raise _Captured(body)


@pytest.fixture(autouse=True)
def _offline(monkeypatch):
    for k, v in {"ANTHROPIC_API_KEY": "sk-ant-test", "OPENAI_API_KEY": "sk-test", "GOOGLE_API_KEY": "g-test",
                 "GEMINI_API_KEY": "g-test", "AWS_BEARER_TOKEN_BEDROCK": "bedrock-test", "AWS_REGION": "us-east-1",
                 "LOA_CHEVAL_DISABLE_STREAMING": "1"}.items():
        monkeypatch.setenv(k, v)
    for mod in (openai_mod, google_mod, bedrock_mod):
        for name in ("http_post", "http_post_stream"):
            if hasattr(mod, name):
                monkeypatch.setattr(mod, name, _capture_post)
    monkeypatch.setattr(anth_mod.AnthropicAdapter, "_complete_nonstreaming",
                        lambda self, url, headers, body: (_ for _ in ()).throw(_Captured(body)))


def _http_body(adapter, request) -> dict:
    try:
        adapter.complete(request)
    except _Captured as cap:
        # (review r251-2 K9 / n41: an uncaptured body would make every "carries no effort" assertion pass on {})
        if not isinstance(cap.body, dict) or not cap.body:
            pytest.fail(f"{type(adapter).__name__}: the transport was reached but its body was not captured "
                        f"({cap.body!r}) — teach _capture_post this body shape")
        return cap.body
    pytest.fail(f"{type(adapter).__name__}.complete() returned without reaching the transport")


def _emitted(adapter, request, model_config) -> object:
    """The reasoning-effort control in the adapter's real body / argv (None = none sent)."""
    name = type(adapter).__name__
    if name == "AnthropicAdapter" or name == "BedrockAdapter":
        return (_http_body(adapter, request).get("output_config") or {}).get("effort")
    if name == "OpenAIAdapter":
        body = _http_body(adapter, request)
        return (body.get("reasoning") or {}).get("effort") or body.get("reasoning_effort")
    if name == "GoogleAdapter":
        body = _http_body(adapter, request)
        text = repr(body).lower()
        assert "effort" not in text, f"google body carries an effort control: {body}"
        return None
    if name == "ClaudeHeadlessAdapter":
        cmd = adapter._build_command(request, model_config, None)
        return cmd[cmd.index("--effort") + 1] if "--effort" in cmd else None
    if name == "CodexHeadlessAdapter":
        cmd = adapter._build_command(request, model_config)
        hits = [c.split("=", 1)[1] for c in cmd if c.startswith("model_reasoning_effort=")]
        return hits[0] if hits else None
    if name == "GrokHeadlessAdapter":
        cmd = adapter._build_command(request, model_config, "/nonexistent/prompt.txt")
        return cmd[cmd.index("--reasoning-effort") + 1] if "--reasoning-effort" in cmd else None
    if name == "CursorHeadlessAdapter":
        cmd = adapter._build_command(request, model_config)
    elif name == "AgyHeadlessAdapter":
        cmd = adapter._build_command(request, model_config, "prompt")
    else:
        pytest.fail(f"no emission reader for {name} — add one so its effort_effective is checked")
    assert not any("effort" in str(c).lower() for c in cmd), (name, cmd)
    return None


def _check(provider, model_id, hounfour, effort):
    entry = hounfour["providers"][provider]["models"][model_id]
    ent = types.SimpleNamespace(provider=provider, model_id=model_id, adapter_kind="cli" if _is_cli(entry) else "http")
    adapter = cheval._get_adapter_for_entry(ent, hounfour)
    model_config = adapter.config.models[model_id]
    request = CompletionRequest(messages=[{"role": "user", "content": "hi"}], model=model_id, max_tokens=64,
                                effort=effort)
    emitted = _emitted(adapter, request, model_config)
    recorded = cheval._effort_on_wire(provider, model_id, effort, hounfour)
    assert recorded == emitted, (f"{provider}:{model_id} ({type(adapter).__name__}) effort={effort!r}: "
                                 f"effort_effective {recorded!r} but the wire carries {emitted!r}")


@pytest.mark.parametrize("effort", ["high", "xhigh"])
@pytest.mark.parametrize("provider,model_id", list(_pairs()), ids=lambda v: str(v))
def test_effort_effective_is_what_the_adapter_emits(provider, model_id, effort):
    _check(provider, model_id, copy.deepcopy(CATALOG_DATA), effort)


@pytest.mark.parametrize("provider,model_id", [("openai", "codex-headless"), ("xai", "grok-build")])
def test_codex_and_grok_record_their_own_extra_reasoning_effort_not_the_caller_value(provider, model_id):
    hounfour = copy.deepcopy(CATALOG_DATA)
    hounfour["providers"][provider]["models"][model_id].setdefault("extra", {})["reasoning_effort"] = "low"
    _check(provider, model_id, hounfour, "high")
    assert cheval._effort_on_wire(provider, model_id, "high", hounfour) == "low"


def test_adapter_class_for_type_is_part_of_the_public_api():
    """review r251-2 K9 (n40): cheval imports it by name; it is exported with the rest of the registry API."""
    import loa_cheval.providers as providers
    assert "adapter_class_for_type" in providers.__all__
