"""#1027: shared contracts across every headless CLI, using local executables."""

import json
import os
import subprocess
import sys
from pathlib import Path
from unittest.mock import Mock

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from loa_cheval.providers.agy_headless_adapter import AgyHeadlessAdapter
from loa_cheval.providers.claude_headless_adapter import ClaudeHeadlessAdapter
from loa_cheval.providers.codex_headless_adapter import CodexHeadlessAdapter
from loa_cheval.providers.cursor_headless_adapter import CursorHeadlessAdapter
from loa_cheval.providers.gemini_headless_adapter import GeminiHeadlessAdapter
from loa_cheval.providers.grok_headless_adapter import GrokHeadlessAdapter
from loa_cheval.providers import headless_cli
from loa_cheval.providers.base import SubprocessOutputCapExceeded
from loa_cheval.types import (
    CompletionRequest, ConfigError, ModelConfig, ProviderConfig, ProviderUnavailableError,
)

ADAPTERS = [
    (ClaudeHeadlessAdapter, "claude", "claude-headless", '{"result":"pong"}'),
    (CodexHeadlessAdapter, "codex", "codex-headless",
     '{"type":"item.completed","item":{"type":"agent_message","text":"pong"}}\n'
     '{"type":"turn.completed","usage":{"input_tokens":1,"output_tokens":1}}'),
    (GeminiHeadlessAdapter, "gemini", "gemini-headless", '{"response":"pong"}'),
    (AgyHeadlessAdapter, "agy", "gemini-headless", "pong"),
    (CursorHeadlessAdapter, "cursor", "cursor-headless",
     '{"type":"result","subtype":"success","result":"pong"}'),
    (GrokHeadlessAdapter, "grok", "grok-headless", '{"text":"pong","stopReason":"EndTurn"}'),
]


@pytest.fixture(params=ADAPTERS, ids=lambda row: row[1])
def adapter_case(request):
    cls, name, ptype, output = request.param
    config = ProviderConfig(
        name=ptype, type=ptype, endpoint="", auth="",
        connect_timeout=1, read_timeout=1,
        models={"entry": ModelConfig(
            context_window=200000, extra={"cli_model": "requested-model"},
        )},
    )
    return cls(config), name, output


@pytest.fixture
def mock_cli(adapter_case, tmp_path, monkeypatch):
    """Mock only the provider's process seam; exercise real completion handling."""
    adapter, _, output = adapter_case
    run = Mock(return_value=subprocess.CompletedProcess(["fake-cli"], 0, output, ""))
    monkeypatch.chdir(tmp_path)
    monkeypatch.setattr(sys.modules[type(adapter).__module__], "run_subprocess_pgkill", run)
    return run


@pytest.mark.parametrize("messages, expected", [
    pytest.param(
        [{"role": "user", "content": "ping"}],
        "## User\n\nping\n", id="single-user",
    ),
    pytest.param(
        [
            {"role": "system", "content": "be terse"},
            {"role": "user", "content": "hi"},
            {"role": "assistant", "content": "hello"},
            {"role": "user", "content": "again"},
        ],
        "## System\n\nbe terse\n\n## User\n\nhi\n\n## Assistant\n\nhello\n\n## User\n\nagain\n",
        id="conversation-order",
    ),
    pytest.param(
        [{"role": "user", "content": [
            {"type": "text", "text": "block A"}, {"type": "text", "text": "block B"},
        ]}],
        "## User\n\nblock A\nblock B\n", id="list-content",
    ),
    pytest.param(
        [
            {"role": "user", "content": "call tool"},
            {"role": "tool", "content": '{"result":42}', "tool_call_id": "x"},
        ],
        '## User\n\ncall tool\n\n## Tool result\n\n{"result":42}\n',
        id="tool-result",
    ),
])
def test_prompt_formatting(adapter_case, messages, expected):
    """Full output equality retains the old role, content and ordering checks."""
    adapter, _, _ = adapter_case
    assert adapter._build_prompt(messages) == expected


def test_prompt_and_timeout_contract(adapter_case):
    adapter, _, _ = adapter_case
    assert adapter._build_prompt([
        {"role": "system", "content": "rules"},
        {"role": "user", "content": [{"text": "one"}, {"text": "two"}]},
        {"role": "tool", "content": {"status": "ok"}},
    ]) == '## System\n\nrules\n\n## User\n\none\ntwo\n\n## Tool result\n\n{"status": "ok"}\n'
    assert adapter._compute_timeout() == 610.0
    adapter.config.connect_timeout = 20
    adapter.config.read_timeout = 700
    assert adapter._compute_timeout() == 720.0


def test_local_cli_health_and_complete(adapter_case, tmp_path, monkeypatch):
    """Do not mock complete(), health_check(), semaphore, or process execution."""
    adapter, name, output = adapter_case
    evidence = tmp_path / "calls.jsonl"
    binary = tmp_path / "fake-cli"
    binary.write_text(
        "#!/usr/bin/env python3\nimport json, os, sys\n"
        "stdin = sys.stdin.read()\n"
        "prompt_file = None\n"
        "if '--prompt-file' in sys.argv:\n"
        " with open(sys.argv[sys.argv.index('--prompt-file') + 1]) as f: prompt_file = f.read()\n"
        f"with open({str(evidence)!r}, 'a') as f:\n"
        " f.write(json.dumps({'argv': sys.argv[1:], 'cwd': os.getcwd(),"
        " 'auth': 'ANTHROPIC_API_KEY' in os.environ,"
        " 'stdin': stdin, 'prompt_file': prompt_file}) + '\\n')\n"
        f"print('local-version' if '--version' in sys.argv else {output!r})\n"
    )
    binary.chmod(0o755)
    monkeypatch.chdir(tmp_path)
    monkeypatch.setenv(f"{name.upper()}_HEADLESS_BIN", str(binary))
    monkeypatch.setenv("ANTHROPIC_API_KEY", "test-only")
    monkeypatch.delenv("LOA_HEADLESS_KEEP_API_KEY", raising=False)
    assert adapter.health_check()
    result = adapter.complete(CompletionRequest(
        messages=[{"role": "user", "content": "ping"}], model="entry",
    ))
    assert result.content == "pong"
    calls = [json.loads(line) for line in evidence.read_text().splitlines()]
    assert calls[0]["argv"] == ["--version"]
    assert len(calls) == 2
    args = calls[1]["argv"]
    model_flag = "--model" if "--model" in args else "-m"
    assert args[args.index(model_flag) + 1] == "requested-model"
    assert not calls[1]["auth"]
    prompt = "## User\n\nping\n"
    if name in ("codex", "cursor"):
        assert calls[1]["stdin"] == prompt
        assert prompt not in args
    elif name == "grok":
        assert calls[1]["prompt_file"] == prompt
        assert prompt not in args
    else:
        assert prompt in args
        assert calls[1]["stdin"] == ""
    if name in ("codex", "cursor", "grok"):
        assert calls[1]["cwd"] != str(tmp_path)
        assert not Path(calls[1]["cwd"]).exists()


def test_missing_binary_health_is_false(adapter_case, monkeypatch):
    adapter, name, _ = adapter_case
    monkeypatch.setenv(f"{name.upper()}_HEADLESS_BIN", "/nonexistent/local-cli")
    run = Mock()
    monkeypatch.setattr(headless_cli.subprocess, "run", run)
    assert not adapter.health_check()
    run.assert_not_called()


@pytest.mark.parametrize("returncode, error", [
    pytest.param(0, None, id="success"),
    pytest.param(1, None, id="nonzero"),
    pytest.param(None, subprocess.TimeoutExpired(["fake-cli"], 5), id="timeout"),
    pytest.param(None, OSError("fixture exec failure"), id="oserror"),
])
def test_health_check_version_contract(adapter_case, monkeypatch, returncode, error):
    adapter, name, _ = adapter_case
    binary = f"/fixture/{name}"
    monkeypatch.setenv(f"{name.upper()}_HEADLESS_BIN", binary)
    monkeypatch.setattr(headless_cli.shutil, "which", Mock(return_value=binary))
    run = Mock(
        return_value=subprocess.CompletedProcess([binary], returncode),
        side_effect=error,
    )
    monkeypatch.setattr(headless_cli.subprocess, "run", run)
    assert adapter.health_check() is (error is None and returncode == 0)
    run.assert_called_once_with(
        [binary, "--version"], capture_output=True, text=True, timeout=5.0, check=False,
    )


@pytest.mark.parametrize("present, wrong_type", [
    pytest.param(True, False, id="valid"),
    pytest.param(False, False, id="missing-binary"),
    pytest.param(True, True, id="wrong-type"),
])
def test_validation_contract(adapter_case, monkeypatch, present, wrong_type):
    adapter, name, _ = adapter_case
    original_type = adapter.config.type
    if wrong_type:
        adapter.config.type = "unsupported"
    binary = f"/fixture/{name}"
    monkeypatch.setenv(f"{name.upper()}_HEADLESS_BIN", binary)
    which = Mock(return_value=binary if present else None)
    monkeypatch.setattr(headless_cli.shutil, "which", which)
    errors = adapter.validate_config()
    which.assert_called_once_with(binary)
    if wrong_type:
        assert len(errors) == 1
        assert f"type must be '{original_type}'" in errors[0]
        assert "unsupported" in errors[0]
    elif not present:
        assert len(errors) == 1
        assert "not found on PATH" in errors[0] and binary in errors[0]
    else:
        assert errors == []


def test_validation_reports_type_then_missing_binary(adapter_case, monkeypatch):
    adapter, name, _ = adapter_case
    original_type = adapter.config.type
    adapter.config.type = "unsupported"
    monkeypatch.setenv(f"{name.upper()}_HEADLESS_BIN", "/nonexistent/local-cli")
    errors = adapter.validate_config()
    assert len(errors) == 2
    assert original_type in errors[0] and "unsupported" in errors[0]
    assert "/nonexistent/local-cli" in errors[1]


@pytest.mark.parametrize("failure, expected_error, message", [
    pytest.param(
        subprocess.TimeoutExpired(["fake-cli"], 5),
        ProviderUnavailableError, "timed out", id="timeout",
    ),
    pytest.param(
        FileNotFoundError("fixture CLI missing"),
        ConfigError, "not found on PATH", id="missing-binary",
    ),
    pytest.param(
        SubprocessOutputCapExceeded("stdout exceeded the 10485760-byte cap"),
        ProviderUnavailableError, "cap", id="output-cap",
    ),
])
def test_completion_subprocess_errors(adapter_case, mock_cli, failure, expected_error, message):
    adapter, _, _ = adapter_case
    adapter.config.read_timeout = 5
    mock_cli.side_effect = failure
    with pytest.raises(expected_error, match=message):
        adapter.complete(CompletionRequest(
            messages=[{"role": "user", "content": "ping"}], model="entry",
        ))
    mock_cli.assert_called_once()


@pytest.mark.parametrize("mode", ["absent", "strip", "keep"])
def test_subprocess_environment_contract(adapter_case, mock_cli, monkeypatch, mode):
    """Use synthetic keys and mocked processes; keep the runner's HOME intact."""
    adapter, _, _ = adapter_case
    preserved = {key: os.environ[key] for key in ("PATH", "HOME")}
    credentials = {
        key: f"test-only-{key.lower()}"
        for key in ("ANTHROPIC_API_KEY", "OPENAI_API_KEY", "GOOGLE_API_KEY", "GEMINI_API_KEY")
    }
    monkeypatch.delenv("LOA_HEADLESS_KEEP_API_KEY", raising=False)
    for key, value in credentials.items():
        if mode == "absent":
            monkeypatch.delenv(key, raising=False)
        else:
            monkeypatch.setenv(key, value)
    if mode == "keep":
        monkeypatch.setenv("LOA_HEADLESS_KEEP_API_KEY", "1")
    adapter.complete(CompletionRequest(
        messages=[{"role": "user", "content": "ping"}], model="entry",
    ))
    mock_cli.assert_called_once()
    env = mock_cli.call_args.kwargs["env"]
    assert env is not None
    for key, value in credentials.items():
        if mode == "keep":
            assert env[key] == value
        else:
            assert key not in env
    for key, value in preserved.items():
        assert env[key] == value
        assert os.environ[key] == value


@pytest.mark.parametrize("limit, expected_slots", [
    pytest.param(None, 50, id="default-limit"),
    pytest.param(3, 3, id="configured-limit"),
])
def test_semaphore_failure_never_spawns(adapter_case, mock_cli, monkeypatch, limit, expected_slots):
    from loa_cheval.adapters import headless_concurrency
    adapter, name, _ = adapter_case
    calls = []

    def exhausted(cli, n_slots):
        calls.append((cli, n_slots))
        raise headless_concurrency.SemaphoreExhausted(cli, n_slots, 0.1)

    monkeypatch.setenv(f"{name.upper()}_HEADLESS_BIN", "/nonexistent/local-cli")
    monkeypatch.setattr(headless_concurrency, "acquire_slot", exhausted)
    adapter.config.models["entry"].headless_concurrency_limit = limit
    with pytest.raises(ProviderUnavailableError, match="CHAIN-EXHAUSTED-CONCURRENCY"):
        adapter.complete(CompletionRequest(
            messages=[{"role": "user", "content": "ping"}], model="entry",
        ))
    assert len(calls) == 1
    assert calls[0] == (adapter.config.type, expected_slots)
    mock_cli.assert_not_called()
