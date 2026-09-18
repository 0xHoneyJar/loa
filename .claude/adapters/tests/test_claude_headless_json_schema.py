"""cycle-124 Sprint 2 Task 2.2 (FR-7): claude-headless forwards `--json-schema`
when the CLI knows the flag (probed once from `claude --help`), prefers the
enforced `structured_output` over the `result` string, and reports
`schema_enforced` truthfully. Fixture = the real CLI JSON captured on this host
(`claude -p --output-format json --json-schema …`, Claude Code 2.1.275).
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

import loa_cheval.providers.claude_headless_adapter as mod  # noqa: E402
from loa_cheval.providers.claude_headless_adapter import ClaudeHeadlessAdapter  # noqa: E402
from loa_cheval.types import CompletionRequest, ModelConfig, ProviderConfig  # noqa: E402

SCHEMA = {"type": "object", "properties": {"answer": {"type": "string"}, "n": {"type": "integer"}},
          "required": ["answer", "n"], "additionalProperties": False}
COMPACT = json.dumps(SCHEMA, separators=(",", ":"))

CLI_JSON_ENFORCED = {
    "type": "result", "subtype": "success", "is_error": False, "duration_ms": 1800, "num_turns": 1,
    "result": "{\"answer\":\"PONG\",\"n\":42}",
    "structured_output": {"answer": "PONG", "n": 42},
    "stop_reason": "tool_use", "session_id": "7d6f3a2e-0000-4000-8000-000000000042",
    "usage": {"input_tokens": 3, "output_tokens": 9},
    "modelUsage": {"claude-opus-4-7": {"inputTokens": 3, "outputTokens": 9}},
}
CLI_JSON_PLAIN = {k: v for k, v in CLI_JSON_ENFORCED.items() if k != "structured_output"}
CLI_JSON_PLAIN["result"] = "PONG"
CLI_JSON_PLAIN["stop_reason"] = "end_turn"


def _config() -> ProviderConfig:
    return ProviderConfig(name="claude-headless", type="claude-headless", endpoint="", auth="",
                          connect_timeout=10.0, read_timeout=600.0,
                          models={"claude-opus-4-7": ModelConfig(context_window=200000)})


def _req(schema=SCHEMA) -> CompletionRequest:
    return CompletionRequest(messages=[{"role": "user", "content": "ping"}], model="claude-opus-4-7",
                             max_tokens=64, output_schema=schema)


def _proc(payload: dict):
    return SimpleNamespace(returncode=0, stdout=json.dumps(payload), stderr="")


@pytest.fixture(autouse=True)
def _reset_probe(monkeypatch):
    monkeypatch.setattr(mod, "_JSON_SCHEMA_FLAG", None)


def test_argv_carries_the_compact_schema_when_the_cli_supports_it(monkeypatch):
    monkeypatch.setattr(mod, "_JSON_SCHEMA_FLAG", True)
    adapter = ClaudeHeadlessAdapter(_config())
    cmd = adapter._build_command(_req(), adapter.config.models["claude-opus-4-7"], "ping")
    assert cmd[cmd.index("--json-schema") + 1] == COMPACT


def test_argv_omits_the_flag_on_an_older_cli(monkeypatch):
    monkeypatch.setattr(mod, "_JSON_SCHEMA_FLAG", False)
    adapter = ClaudeHeadlessAdapter(_config())
    cmd = adapter._build_command(_req(), adapter.config.models["claude-opus-4-7"], "ping")
    assert "--json-schema" not in cmd


def test_argv_omits_the_flag_without_a_schema(monkeypatch):
    monkeypatch.setattr(mod, "_JSON_SCHEMA_FLAG", True)
    adapter = ClaudeHeadlessAdapter(_config())
    cmd = adapter._build_command(_req(schema=None), adapter.config.models["claude-opus-4-7"], "ping")
    assert "--json-schema" not in cmd


@pytest.mark.parametrize("help_text, expected", [
    ("  --json-schema <schema>                JSON Schema for structured output\n", True),
    ("  --output-format <format>\n", False),
])
def test_probe_reads_help_once_and_caches(monkeypatch, help_text, expected):
    calls = []

    def _fake_run(argv, **kw):
        calls.append(argv)
        return SimpleNamespace(returncode=0, stdout=help_text, stderr="")

    monkeypatch.setattr(mod.subprocess, "run", _fake_run)
    assert mod._cli_supports_json_schema("claude") is expected
    assert mod._cli_supports_json_schema("claude") is expected
    assert len(calls) == 1 and calls[0][-1] == "--help"


def test_probe_failure_means_unsupported(monkeypatch):
    def _boom(*a, **k):
        raise FileNotFoundError("claude")
    monkeypatch.setattr(mod.subprocess, "run", _boom)
    assert mod._cli_supports_json_schema("claude") is False


def test_structured_output_wins_and_is_reported_enforced(monkeypatch):
    monkeypatch.setattr(mod, "_JSON_SCHEMA_FLAG", True)
    adapter = ClaudeHeadlessAdapter(_config())
    with patch("loa_cheval.providers.claude_headless_adapter.run_subprocess_pgkill", return_value=_proc(CLI_JSON_ENFORCED)) as run:
        result = adapter.complete(_req())
    argv = run.call_args.args[0]
    assert argv[argv.index("--json-schema") + 1] == COMPACT
    assert result.content == '{"answer":"PONG","n":42}'
    assert json.loads(result.content) == {"answer": "PONG", "n": 42}
    assert result.metadata["schema_enforced"] is True
    assert result.metadata.get("stop_reason") == "tool_use"


def test_plain_result_is_reported_unenforced(monkeypatch):
    monkeypatch.setattr(mod, "_JSON_SCHEMA_FLAG", False)
    adapter = ClaudeHeadlessAdapter(_config())
    with patch("loa_cheval.providers.claude_headless_adapter.run_subprocess_pgkill", return_value=_proc(CLI_JSON_PLAIN)):
        result = adapter.complete(_req())
    assert result.content == "PONG"
    assert result.metadata["schema_enforced"] is False
