"""cycle-125 Sprint 4 (PRD FR-5 AC 2, SDD §1.6) — headless adapters record the
hop (`transport`) and the id the CLI was asked to run (`resolved_model` =
catalog `extra.cli_model`) on the CompletionResult metadata, so the ledger row
is priced through the ladder and attributable. `model` keeps its pre-cycle
meaning (actual when reported, else requested).
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from loa_cheval.providers.claude_headless_adapter import ClaudeHeadlessAdapter  # noqa: E402
from loa_cheval.providers.codex_headless_adapter import CodexHeadlessAdapter  # noqa: E402
from loa_cheval.types import ModelConfig, ProviderConfig  # noqa: E402


def _cfg(name: str, ptype: str, model_id: str, extra: dict) -> ProviderConfig:
    return ProviderConfig(
        name=name, type=ptype, endpoint="", auth="", connect_timeout=10.0, read_timeout=60.0,
        models={model_id: ModelConfig(context_window=200000, extra=extra)},
    )


def test_claude_headless_records_transport_and_resolved_model_when_cli_reports_no_model():
    adapter = ClaudeHeadlessAdapter(_cfg("anthropic", "claude-headless", "claude-headless", {"cli_model": "fable"}))
    parsed = {"type": "result", "subtype": "success", "is_error": False, "result": "hi",
              "stop_reason": "end_turn", "session_id": "s1",
              "usage": {"input_tokens": 10, "output_tokens": 2}}
    r = adapter._parse_json_output(parsed=parsed, requested_model="claude-headless", latency_ms=5, cli_model="fable")
    assert r.model == "claude-headless"                    # unchanged meaning: no modelUsage → requested
    assert r.metadata["transport"] == "cli:claude"
    assert r.metadata["requested_model"] == "claude-headless"
    assert r.metadata["resolved_model"] == "fable"


def test_claude_headless_prefers_the_reported_model_and_still_records_the_hop():
    adapter = ClaudeHeadlessAdapter(_cfg("anthropic", "claude-headless", "claude-headless", {"cli_model": "fable"}))
    parsed = {"type": "result", "subtype": "success", "is_error": False, "result": "hi",
              "stop_reason": "end_turn", "session_id": "s1",
              "usage": {"input_tokens": 10, "output_tokens": 2},
              "modelUsage": {"claude-fable-5-1": {"inputTokens": 10, "outputTokens": 2}}}
    r = adapter._parse_json_output(parsed=parsed, requested_model="claude-headless", latency_ms=5, cli_model="fable")
    assert r.model == "claude-fable-5-1"
    assert r.metadata["transport"] == "cli:claude" and r.metadata["resolved_model"] == "fable"


def test_codex_headless_records_transport_and_resolved_model():
    adapter = CodexHeadlessAdapter(_cfg("openai", "codex-headless", "codex-headless", {"cli_model": "gpt-5.5"}))
    stdout = '\n'.join([
        '{"type":"thread.started","thread_id":"t1"}',
        '{"type":"item.completed","item":{"id":"i1","type":"agent_message","text":"hello"}}',
        '{"type":"turn.completed","usage":{"input_tokens":12,"output_tokens":3}}',
    ]) + "\n"
    r = adapter._parse_jsonl_output(stdout=stdout, stderr="", requested_model="codex-headless", latency_ms=7, cli_model="gpt-5.5")
    assert r.content == "hello" and r.model == "codex-headless"
    assert r.metadata == {"transport": "cli:codex", "requested_model": "codex-headless", "resolved_model": "gpt-5.5"}


def test_no_resolved_model_when_cli_model_equals_the_requested_id():
    adapter = CodexHeadlessAdapter(_cfg("openai", "codex-headless", "gpt-5.5", {"cli_model": "gpt-5.5"}))
    r = adapter._parse_jsonl_output(stdout='{"type":"turn.completed","usage":{}}\n', stderr="", requested_model="gpt-5.5", latency_ms=1, cli_model="gpt-5.5")
    assert "resolved_model" not in r.metadata and r.metadata["transport"] == "cli:codex"
