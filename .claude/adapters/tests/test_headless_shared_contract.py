"""#1027: shared contracts across every headless CLI, using local executables."""

import logging
import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from loa_cheval.providers.agy_headless_adapter import AgyHeadlessAdapter
from loa_cheval.providers.claude_headless_adapter import ClaudeHeadlessAdapter
from loa_cheval.providers.codex_headless_adapter import CodexHeadlessAdapter
from loa_cheval.providers.cursor_headless_adapter import CursorHeadlessAdapter
from loa_cheval.providers.gemini_headless_adapter import GeminiHeadlessAdapter
from loa_cheval.providers.grok_headless_adapter import GrokHeadlessAdapter
from loa_cheval.types import CompletionRequest, ModelConfig, ProviderConfig, ProviderUnavailableError

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


def test_prompt_and_timeout_contract(adapter_case, caplog):
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
    # cycle-126 sprint-248: a per-model headless_timeout_seconds raises the read bound, never lowers it
    from loa_cheval.types import ModelConfig
    assert adapter._compute_timeout(ModelConfig(headless_timeout_seconds=900)) == 920.0
    assert adapter._compute_timeout(ModelConfig(headless_timeout_seconds=100)) == 720.0
    assert adapter._compute_timeout(ModelConfig()) == 720.0
    assert adapter._compute_timeout(ModelConfig(headless_timeout_seconds="not-a-number")) == 720.0
    # the catalog value is clamped to an hour (seventh run, c2 C-008 / d C-001)
    assert adapter._compute_timeout(ModelConfig(headless_timeout_seconds=90000)) == 3620.0
    # …and never lowers a provider read_timeout already above the ceiling (eighth run, d DISS-001 / C-001)
    adapter.config.read_timeout = 4000
    assert adapter._compute_timeout(ModelConfig(headless_timeout_seconds=90000)) == 4020.0
    assert adapter._compute_timeout(ModelConfig(headless_timeout_seconds=900)) == 4020.0
    adapter.config.read_timeout = 700
    # the adapter is silent at WARNING whatever it is handed: validation and its one warning happen at load
    # (eighth run, c2 C-001 pinned the warnings; tenth run, d C-001 moved them to the loader — a per-hop
    # 'ignored' for a value the bound already meets misled the operator); NaN is unusable too (c2 C-004)
    with caplog.at_level(logging.WARNING, logger="loa_cheval.providers.headless"):
        caplog.clear()
        assert adapter._compute_timeout(ModelConfig(headless_timeout_seconds=True)) == 720.0
        assert adapter._compute_timeout(ModelConfig(headless_timeout_seconds="not-a-number")) == 720.0
        assert adapter._compute_timeout(ModelConfig(headless_timeout_seconds=float("nan"))) == 720.0
        assert adapter._compute_timeout(ModelConfig(headless_timeout_seconds=100)) == 720.0
        assert adapter._compute_timeout(ModelConfig(headless_timeout_seconds=90000)) == 3620.0
        assert adapter._compute_timeout(ModelConfig(headless_timeout_seconds=900)) == 920.0
        assert caplog.text == ""
    # the catalog loader coerces once (d C-002): typed float or None, one warning each; the ceiling is applied
    # THERE, so the stored field is the effective bound (tenth run, d C-001)
    from loa_cheval.types import HEADLESS_TIMEOUT_CEILING_SECONDS, coerce_headless_timeout_seconds
    assert HEADLESS_TIMEOUT_CEILING_SECONDS == 3600.0 == adapter._HEADLESS_TIMEOUT_CEILING
    with caplog.at_level(logging.WARNING, logger="loa_cheval.config"):
        caplog.clear()
        assert coerce_headless_timeout_seconds(900) == 900.0
        assert coerce_headless_timeout_seconds("900") == 900.0
        assert coerce_headless_timeout_seconds(3600) == 3600.0
        assert coerce_headless_timeout_seconds(None) is None
        assert caplog.text == ""
        assert coerce_headless_timeout_seconds(True, where="p/m: ") is None
        assert coerce_headless_timeout_seconds("15m", where="p/m: ") is None
        assert coerce_headless_timeout_seconds(-5, where="p/m: ") is None
        assert coerce_headless_timeout_seconds(float("inf"), where="p/m: ") is None
        assert coerce_headless_timeout_seconds(float("nan"), where="p/m: ") is None
        assert caplog.text.count("p/m: headless_timeout_seconds") == 5
        assert caplog.text.count("ignored") == 5
        caplog.clear()
        assert coerce_headless_timeout_seconds(7200, where="p/m: ") == 3600.0
        assert "p/m: headless_timeout_seconds 7200 clamped to 3600s" in caplog.text
        assert caplog.text.count("headless_timeout_seconds") == 1
    # no headless subclass overrides the base timeout (d C-004)
    assert "_compute_timeout" not in type(adapter).__dict__


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
    assert not adapter.health_check()


def test_validation_reports_type_then_missing_binary(adapter_case, monkeypatch):
    adapter, name, _ = adapter_case
    original_type = adapter.config.type
    adapter.config.type = "unsupported"
    monkeypatch.setenv(f"{name.upper()}_HEADLESS_BIN", "/nonexistent/local-cli")
    errors = adapter.validate_config()
    assert len(errors) == 2
    assert original_type in errors[0] and "unsupported" in errors[0]
    assert "/nonexistent/local-cli" in errors[1]


def test_semaphore_failure_never_spawns(adapter_case, tmp_path, monkeypatch):
    from loa_cheval.adapters import headless_concurrency
    adapter, name, _ = adapter_case
    calls = []

    def exhausted(cli, n_slots):
        calls.append((cli, n_slots))
        raise headless_concurrency.SemaphoreExhausted(cli, n_slots, 0.1)

    monkeypatch.chdir(tmp_path)
    monkeypatch.setenv(f"{name.upper()}_HEADLESS_BIN", "/nonexistent/local-cli")
    monkeypatch.setattr(headless_concurrency, "acquire_slot", exhausted)
    adapter.config.models["entry"].headless_concurrency_limit = 3
    with pytest.raises(ProviderUnavailableError, match="CHAIN-EXHAUSTED-CONCURRENCY"):
        adapter.complete(CompletionRequest(
            messages=[{"role": "user", "content": "ping"}], model="entry",
        ))
    assert len(calls) == 1
    assert calls[0][1] == 3


def test_headless_timeout_seconds_is_cli_only(caplog):
    """The key applies to `kind: cli` models only; anywhere else the loader reports it once and drops it, so
    the typed field never claims a bound no hop will honour (tenth run, d C-002)."""
    import cheval
    cfg = {"providers": {"p": {"type": "anthropic", "endpoint": "https://example.invalid", "auth": "none", "models": {
        "h": {"kind": "cli", "context_window": 1000, "headless_timeout_seconds": 900},
        "x": {"context_window": 1000, "headless_timeout_seconds": 900},
        "y": {"kind": "http_api", "context_window": 1000, "headless_timeout_seconds": 900},
        "z": {"context_window": 1000},
    }}}}
    with caplog.at_level(logging.WARNING, logger="loa_cheval.config"):
        caplog.clear()
        pc = cheval._build_provider_config("p", cfg)
    assert pc.models["h"].headless_timeout_seconds == 900.0
    assert pc.models["x"].headless_timeout_seconds is None
    assert pc.models["y"].headless_timeout_seconds is None
    assert pc.models["z"].headless_timeout_seconds is None
    assert caplog.text.count("applies to kind: cli models only") == 2
    assert "p/x: headless_timeout_seconds 900 applies to kind: cli models only — ignored on this http_api model" in caplog.text
    assert "p/y: headless_timeout_seconds 900 applies to kind: cli models only — ignored on this http_api model" in caplog.text
