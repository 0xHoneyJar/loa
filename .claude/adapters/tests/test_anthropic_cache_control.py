"""cycle-124 Sprint 1 Task 1.6 (FR-4 / SDD §3.3) — prompt caching + telemetry.

- cheval splits persona (cache breakpoint) and context into two system
  messages for Anthropic-company chains; the joined text is byte-identical to
  the merged `_load_persona()` string on every transport.
- anthropic_adapter._transform_messages: joined string when no marker,
  `[{type:text, cache_control}, {type:text}]` when marked — exactly one
  breakpoint per body; LOA_CHEVAL_LEGACY_WIRE ⇒ string.
- OpenAI / Google / headless golden bodies do not move (AC-4.4).
- Usage.cache_* reaches the MODELINV payload and the CLI JSON.
"""

from __future__ import annotations

import json
import sys
import types
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

import cheval  # type: ignore[import-not-found]  # noqa: E402
import loa_cheval.providers.headless_cli as headless_cli  # noqa: E402
from loa_cheval.providers.anthropic_adapter import AnthropicAdapter, _transform_messages  # noqa: E402
from loa_cheval.providers.google_adapter import _translate_messages as google_translate  # noqa: E402
from loa_cheval.providers.openai_adapter import OpenAIAdapter  # noqa: E402
from loa_cheval.types import CompletionRequest, CompletionResult, ModelConfig, ProviderConfig, Usage  # noqa: E402

PERSONA = "You are the reviewer.\n\n---\n\nRules:\n- be terse"   # contains a markdown hr on purpose
CONTEXT = "Sprint 7 diff context."
MARK = {"type": "ephemeral"}


@pytest.fixture(autouse=True)
def _clean_env(monkeypatch):
    monkeypatch.delenv("LOA_CHEVAL_LEGACY_WIRE", raising=False)
    monkeypatch.delenv("LOA_CHEVAL_DISABLE_STREAMING", raising=False)


@pytest.fixture
def persona_tree(tmp_path, monkeypatch):
    """A scratch repo root with persona.md for agent `agentx` and a --system file."""
    (tmp_path / ".claude" / "skills" / "agentx").mkdir(parents=True)
    (tmp_path / ".claude" / "skills" / "agentx" / "persona.md").write_text(PERSONA + "\n")
    system_file = tmp_path / "context.md"
    system_file.write_text(CONTEXT + "\n")
    monkeypatch.chdir(tmp_path)
    return str(system_file)


# --- cheval._persona_messages --------------------------------------------------

def test_persona_plus_context_splits_with_one_marker_and_identical_join(persona_tree):
    msgs = cheval._persona_messages("agentx", persona_tree)
    assert [m["role"] for m in msgs] == ["system", "system"]
    assert msgs[0]["content"] == PERSONA
    assert msgs[0]["cache_control"] == MARK
    assert "cache_control" not in msgs[1]
    assert msgs[1]["content"].startswith("---\n\n")
    merged = cheval._load_persona("agentx", persona_tree)
    assert "\n\n".join(m["content"] for m in msgs) == merged


def test_persona_only_is_a_single_marked_message(persona_tree):
    msgs = cheval._persona_messages("agentx", None)
    assert len(msgs) == 1 and msgs[0]["cache_control"] == MARK
    assert msgs[0]["content"] == cheval._load_persona("agentx", None) == PERSONA


def test_context_without_persona_is_the_marked_stable_prefix(persona_tree):
    """PRD FR-4: with no persona the WHOLE --system payload is the stable block
    and carries the breakpoint — Bridgebuilder dispatches `--agent reviewing-code`
    (no persona.md) with a 9 KB stable system file and must cache too
    (review round-1 high #1 flipped the earlier 'unmarked' pin)."""
    msgs = cheval._persona_messages("no-such-agent", persona_tree)
    assert msgs == [{"role": "system", "content": CONTEXT, "cache_control": dict(MARK)}]
    assert cheval._load_persona("no-such-agent", persona_tree) == CONTEXT


def test_bridgebuilder_shape_no_persona_gets_exactly_one_breakpoint(tmp_path, monkeypatch):
    """The real BB prefix (INJECTION_HARDENING + .claude/data/bridgebuilder-persona.md)
    through the production path: _persona_messages → _transform_messages."""
    repo_root = Path(__file__).resolve().parents[3]
    bb = (repo_root / ".claude" / "data" / "bridgebuilder-persona.md").read_text()
    assert not (repo_root / ".claude" / "skills" / "reviewing-code" / "persona.md").exists()
    system_file = tmp_path / "bb-system.md"
    system_file.write_text("SYSTEM SECURITY NOTICE\n\n" + bb)
    monkeypatch.chdir(repo_root)
    msgs = cheval._persona_messages("reviewing-code", str(system_file))
    system, _ = _transform_messages(msgs + [{"role": "user", "content": "review"}])
    assert isinstance(system, list) and len(system) == 1
    assert system[0]["cache_control"] == MARK
    assert system[0]["text"] == cheval._load_persona("reviewing-code", str(system_file))


def test_nothing_loaded_yields_no_system_messages(persona_tree):
    assert cheval._persona_messages("no-such-agent", None) == []
    assert cheval._load_persona("no-such-agent", None) is None


# --- anthropic_adapter._transform_messages -------------------------------------

def _split_messages():
    return [
        {"role": "system", "content": PERSONA, "cache_control": dict(MARK)},
        {"role": "system", "content": "---\n\n" + CONTEXT},
        {"role": "user", "content": "review"},
    ]


def test_transform_without_marker_is_the_joined_string():
    system, msgs = _transform_messages([
        {"role": "system", "content": "Part 1"}, {"role": "system", "content": "Part 2"},
        {"role": "user", "content": "x"},
    ])
    assert system == "Part 1\n\nPart 2"
    assert msgs == [{"role": "user", "content": "x"}]


def test_transform_with_marker_emits_blocks_with_exactly_one_breakpoint():
    system, _ = _transform_messages(_split_messages())
    assert isinstance(system, list)
    assert system[0] == {"type": "text", "text": PERSONA, "cache_control": MARK}
    assert system[1] == {"type": "text", "text": "\n\n---\n\n" + CONTEXT}
    assert sum(1 for b in system if "cache_control" in b) == 1
    # The characters the model sees are the same as the string path.
    assert "".join(b["text"] for b in system) == PERSONA + "\n\n" + "---\n\n" + CONTEXT


def test_transform_legacy_wire_ignores_markers(monkeypatch):
    monkeypatch.setenv("LOA_CHEVAL_LEGACY_WIRE", "1")
    system, _ = _transform_messages(_split_messages())
    assert system == PERSONA + "\n\n---\n\n" + CONTEXT


def test_transform_non_dict_marker_is_ignored():
    system, _ = _transform_messages([{"role": "system", "content": "p", "cache_control": "ephemeral"},
                                     {"role": "user", "content": "x"}])
    assert system == "p"


def _anthropic_config() -> ProviderConfig:
    return ProviderConfig(
        name="anthropic", type="anthropic", endpoint="https://api.anthropic.com/v1", auth="sk-ant-test",
        connect_timeout=10.0, read_timeout=30.0,
        models={"claude-opus-5": ModelConfig(capabilities=["chat"], context_window=1_000_000,
                                             params={"temperature_supported": False, "thinking_adaptive": True})},
    )


def test_complete_sends_system_blocks_verbatim(monkeypatch):
    monkeypatch.setenv("LOA_CHEVAL_DISABLE_STREAMING", "1")
    adapter = AnthropicAdapter(_anthropic_config())
    captured: dict = {}
    monkeypatch.setattr(adapter, "_complete_nonstreaming", lambda url, headers, body: captured.setdefault("body", body))
    adapter.complete(CompletionRequest(messages=_split_messages(), model="claude-opus-5", max_tokens=64))
    system = captured["body"]["system"]
    assert isinstance(system, list) and system[0]["cache_control"] == MARK
    assert captured["body"]["thinking"] == {"type": "adaptive"}


# --- AC-4.4: other transports do not move ---------------------------------------

def _merged_messages():
    return [{"role": "system", "content": PERSONA + "\n\n---\n\n" + CONTEXT}, {"role": "user", "content": "review"}]


def test_openai_responses_body_identical_for_split_and_merged():
    cfg = ProviderConfig(name="openai", type="openai", endpoint="https://api.openai.com/v1", auth="sk-test",
                         models={"gpt-5.5": ModelConfig(capabilities=["chat"], context_window=200_000,
                                                        endpoint_family="responses")})
    adapter = OpenAIAdapter(cfg)
    mc = cfg.models["gpt-5.5"]
    split = adapter._build_responses_body(CompletionRequest(messages=_split_messages(), model="gpt-5.5", max_tokens=64), mc)
    merged = adapter._build_responses_body(CompletionRequest(messages=_merged_messages(), model="gpt-5.5", max_tokens=64), mc)
    assert split == merged
    assert "cache_control" not in json.dumps(split)


def test_google_translate_identical_for_split_and_merged():
    mc = ModelConfig(capabilities=["chat"], context_window=1_000_000)
    assert google_translate(_split_messages(), mc) == google_translate(_merged_messages(), mc)


def test_headless_prompt_identical_for_split_and_merged():
    cls = next(v for v in vars(headless_cli).values() if isinstance(v, type) and hasattr(v, "_build_prompt"))
    build = cls._build_prompt
    assert build(None, _split_messages()) == build(None, _merged_messages())
    assert build(None, _split_messages()).count("## System") == 1
    # Non-consecutive system messages are still separate sections (unchanged behaviour).
    mixed = [{"role": "system", "content": "a"}, {"role": "user", "content": "u"}, {"role": "system", "content": "b"}]
    assert build(None, mixed).count("## System") == 2


# --- cheval assembly + telemetry through cmd_invoke ------------------------------

def _args(agent: str, system_file: str, output_format: str = "text"):
    a = types.SimpleNamespace()
    a.agent = agent; a.role = None; a.skill = None; a.sprint_kind = None
    a.input = None; a.prompt = "review"; a.system = system_file; a.model = None
    a.max_tokens = None; a.effort = None; a.output_format = output_format
    a.json_errors = True; a.timeout = 30; a.include_thinking = False; a.async_mode = False
    a.poll_id = None; a.cancel_id = None; a.dry_run = False; a.print_config = False
    a.validate_bindings = False; a.mock_fixture_dir = None; a.max_input_tokens = None
    return a


def _cfg(provider: str, model: str):
    return {
        "aliases": {model: f"{provider}:{model}"},
        "providers": {provider: {"type": provider, "endpoint": "https://x", "auth": "dummy",
                                 "models": {model: {"capabilities": ["chat"], "context_window": 1_000_000,
                                                    "max_output_tokens": 128_000,
                                                    "pricing": {"input_per_mtok": 5_000_000, "output_per_mtok": 25_000_000,
                                                                "cache_read_per_mtok": 500_000}}}}},
        "feature_flags": {"metering": False},
    }


def _invoke(provider: str, model: str, system_file: str, monkeypatch, output_format: str = "text", usage: Usage | None = None):
    monkeypatch.setattr(cheval, "_check_feature_flags", lambda *_a, **_kw: None)
    seen = []

    def _retry_side(_adapter, req, _cfg, budget_hook=None):
        seen.append(req)
        return CompletionResult(content="ok", model=model, provider=provider,
                                usage=usage or Usage(input_tokens=10, output_tokens=5),
                                latency_ms=1, tool_calls=None, thinking=None, metadata={"streaming": True})

    captured: dict = {}

    def _emit(level, event, payload, *_a, **_kw):
        captured.update(payload)

    with patch.object(cheval, "load_config", return_value=(_cfg(provider, model), {})), \
         patch.object(cheval, "resolve_execution", return_value=(MagicMock(temperature=0.7, capability_class=None),
                                                                  MagicMock(provider=provider, model_id=model))), \
         patch.object(cheval, "_build_provider_config", return_value=MagicMock()), \
         patch.object(cheval, "get_adapter", return_value=MagicMock()), \
         patch("loa_cheval.providers.retry.invoke_with_retry", side_effect=_retry_side), \
         patch("loa_cheval.audit_envelope.audit_emit", _emit), \
         patch("loa_cheval.audit.modelinv.redact_payload_strings", side_effect=lambda x: x), \
         patch("loa_cheval.audit.modelinv.assert_no_secret_shapes_remain"):
        code = cheval.cmd_invoke(_args("agentx", system_file, output_format))
    return code, seen, captured


def test_anthropic_chain_gets_split_system_messages(persona_tree, monkeypatch):
    code, seen, _ = _invoke("anthropic", "claude-opus-5", persona_tree, monkeypatch)
    assert code == 0
    sys_msgs = [m for m in seen[0].messages if m["role"] == "system"]
    assert len(sys_msgs) == 2 and sys_msgs[0]["cache_control"] == MARK
    assert "\n\n".join(m["content"] for m in sys_msgs) == cheval._load_persona("agentx", persona_tree)


def test_non_anthropic_chain_keeps_the_merged_string(persona_tree, monkeypatch):
    code, seen, _ = _invoke("openai", "gpt-5.5", persona_tree, monkeypatch)
    assert code == 0
    sys_msgs = [m for m in seen[0].messages if m["role"] == "system"]
    assert len(sys_msgs) == 1 and "cache_control" not in sys_msgs[0]
    assert sys_msgs[0]["content"] == cheval._load_persona("agentx", persona_tree)


def test_legacy_wire_keeps_the_merged_string_on_anthropic(persona_tree, monkeypatch):
    monkeypatch.setenv("LOA_CHEVAL_LEGACY_WIRE", "1")
    _, seen, _ = _invoke("anthropic", "claude-opus-5", persona_tree, monkeypatch)
    sys_msgs = [m for m in seen[0].messages if m["role"] == "system"]
    assert len(sys_msgs) == 1 and "cache_control" not in sys_msgs[0]


def test_cache_usage_reaches_modelinv_and_cli_json(persona_tree, monkeypatch, capsys):
    usage = Usage(input_tokens=10, output_tokens=5, cache_read_input_tokens=1234, cache_creation_input_tokens=56)
    code, _, captured = _invoke("anthropic", "claude-opus-5", persona_tree, monkeypatch, output_format="json", usage=usage)
    assert code == 0
    assert captured["tokens_cache_read"] == 1234
    assert captured["tokens_cache_creation"] == 56
    assert captured["pricing_snapshot"]["cache_read_per_mtok"] == 500_000
    assert captured["pricing_snapshot"]["cache_write_per_mtok"] == 6_250_000
    out = json.loads(capsys.readouterr().out)
    assert out["usage"]["cache_read_input_tokens"] == 1234
    assert out["usage"]["cache_creation_input_tokens"] == 56


def test_absent_cache_usage_is_zero_in_cli_and_absent_in_modelinv(persona_tree, monkeypatch, capsys):
    code, _, captured = _invoke("anthropic", "claude-opus-5", persona_tree, monkeypatch, output_format="json")
    assert code == 0
    out = json.loads(capsys.readouterr().out)
    assert out["usage"]["cache_read_input_tokens"] == 0
    # Usage defaults are 0 (ints), so the payload carries explicit zeros — a
    # writer that saw no telemetry at all (None) would omit them.
    assert captured.get("tokens_cache_read") == 0


@pytest.mark.parametrize("model, params, thinking_text", [
    ("claude-opus-5", {"temperature_supported": False, "thinking_adaptive": True}, "…"),
    # Fable: thinking is always on and the param is OMITTED — the catalog carries
    # only temperature_supported:false, so the flag alone would never fire
    # (review round-1 high #2).
    ("claude-fable-5-1", {"temperature_supported": False}, None),
    # A response that visibly carried thinking is flagged whatever the catalog says.
    ("claude-opus-4-8", {}, "reasoning trace"),
])
def test_thinking_truncation_sets_operator_visible_warn(persona_tree, monkeypatch, capsys, model, params, thinking_text):
    cfg = _cfg("anthropic", model)
    cfg["providers"]["anthropic"]["models"][model]["params"] = params
    monkeypatch.setattr(cheval, "_check_feature_flags", lambda *_a, **_kw: None)
    captured: dict = {}

    def _retry_side(_adapter, req, _cfg, budget_hook=None):
        return CompletionResult(content="partial", model=model, provider="anthropic",
                                usage=Usage(input_tokens=10, output_tokens=64), latency_ms=1, tool_calls=None,
                                thinking=thinking_text, metadata={"streaming": True, "stop_reason": "max_tokens"})

    with patch.object(cheval, "load_config", return_value=(cfg, {})), \
         patch.object(cheval, "resolve_execution", return_value=(MagicMock(temperature=0.7, capability_class=None),
                                                                  MagicMock(provider="anthropic", model_id=model))), \
         patch.object(cheval, "_build_provider_config", return_value=MagicMock()), \
         patch.object(cheval, "get_adapter", return_value=MagicMock()), \
         patch("loa_cheval.providers.retry.invoke_with_retry", side_effect=_retry_side), \
         patch("loa_cheval.audit_envelope.audit_emit", lambda level, event, payload, *a, **k: captured.update(payload)), \
         patch("loa_cheval.audit.modelinv.redact_payload_strings", side_effect=lambda x: x), \
         patch("loa_cheval.audit.modelinv.assert_no_secret_shapes_remain"):
        assert cheval.cmd_invoke(_args("agentx", persona_tree)) == 0
    assert captured["operator_visible_warn"] is True
    assert "stopped at max_tokens=64000 with thinking on" in capsys.readouterr().err


def test_non_thinking_max_tokens_stop_is_not_flagged(persona_tree, monkeypatch, capsys):
    """A plain (no thinking) max_tokens stop is the caller's budget choice, not a hidden truncation."""
    cfg = _cfg("anthropic", "claude-haiku-4-5-20251001")
    cfg["providers"]["anthropic"]["models"]["claude-haiku-4-5-20251001"]["params"] = {}
    monkeypatch.setattr(cheval, "_check_feature_flags", lambda *_a, **_kw: None)
    captured: dict = {}

    def _retry_side(_adapter, req, _cfg, budget_hook=None):
        return CompletionResult(content="partial", model="claude-haiku-4-5-20251001", provider="anthropic",
                                usage=Usage(input_tokens=10, output_tokens=64), latency_ms=1, tool_calls=None,
                                thinking=None, metadata={"streaming": True, "stop_reason": "max_tokens"})

    with patch.object(cheval, "load_config", return_value=(cfg, {})), \
         patch.object(cheval, "resolve_execution", return_value=(MagicMock(temperature=0.7, capability_class=None),
                                                                  MagicMock(provider="anthropic", model_id="claude-haiku-4-5-20251001"))), \
         patch.object(cheval, "_build_provider_config", return_value=MagicMock()), \
         patch.object(cheval, "get_adapter", return_value=MagicMock()), \
         patch("loa_cheval.providers.retry.invoke_with_retry", side_effect=_retry_side), \
         patch("loa_cheval.audit_envelope.audit_emit", lambda level, event, payload, *a, **k: captured.update(payload)), \
         patch("loa_cheval.audit.modelinv.redact_payload_strings", side_effect=lambda x: x), \
         patch("loa_cheval.audit.modelinv.assert_no_secret_shapes_remain"):
        assert cheval.cmd_invoke(_args("agentx", persona_tree)) == 0
    assert captured.get("operator_visible_warn") is not True
    assert "with thinking on" not in capsys.readouterr().err
