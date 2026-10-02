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
        # (nineteenth run, c2e C-001: a bool taken as 1.0 or a NaN swallowed by max() would leave the bound at 720 too — the
        # shared predicate itself is asserted, and the NaN bound is asserted finite whatever max()'s argument order)
        import math
        from loa_cheval.types import usable_headless_timeout as _usable
        assert _usable(True) is None and _usable(float("nan")) is None and _usable(10 ** 400) is None and _usable("900") == 900.0
        assert math.isfinite(adapter._compute_timeout(ModelConfig(headless_timeout_seconds=float("nan"))))
        assert adapter._compute_timeout(ModelConfig(headless_timeout_seconds=10 ** 400)) == 720.0   # (d C-001: no OverflowError)
        assert adapter._compute_timeout(ModelConfig(headless_timeout_seconds="900")) == 920.0   # (fourteenth run, d C-001: the loader's predicate — a quoted number is a number)
        assert adapter._compute_timeout(ModelConfig(headless_timeout_seconds=100)) == 720.0
        assert adapter._compute_timeout(ModelConfig(headless_timeout_seconds=90000)) == 3620.0
        assert adapter._compute_timeout(ModelConfig(headless_timeout_seconds=900)) == 920.0
        assert caplog.text == ""
    # the catalog loader coerces once (d C-002): typed float or None, one warning each; the ceiling is applied
    # THERE, so the stored field is the effective bound (tenth run, d C-001)
    from loa_cheval.types import HEADLESS_TIMEOUT_CEILING_SECONDS, coerce_headless_timeout_seconds, reset_headless_timeout_reports
    assert HEADLESS_TIMEOUT_CEILING_SECONDS == 3600.0 == adapter._HEADLESS_TIMEOUT_CEILING
    reset_headless_timeout_reports()   # (the reports are once per process — this test runs once per adapter)
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
        assert coerce_headless_timeout_seconds(10 ** 400, where="p/m: ") is None   # (d C-001: OverflowError is "not a number of seconds")
        assert caplog.text.count("p/m: headless_timeout_seconds") == 6
        assert caplog.text.count("ignored") == 6
        # once per process per (where, value): the same defect on a rebuilt provider config is not repeated (d C-002)
        caplog.clear()
        assert coerce_headless_timeout_seconds(True, where="p/m: ") is None
        assert coerce_headless_timeout_seconds(True, where="p/other: ") is None
        assert caplog.text.count("headless_timeout_seconds") == 1
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


def test_complete_bounds_the_hop_by_its_model(adapter_case, tmp_path, monkeypatch):
    """Every adapter's complete() hands the hop's ModelConfig to _compute_timeout — a subclass with its own complete()
    (agy, grok) that called it with no argument ran a catalog `headless_timeout_seconds` on the 600 s floor, though the
    loader accepted the key for its *-headless provider (twenty-first run, d C-001)."""
    adapter, name, output = adapter_case
    adapter.config.models["entry"].headless_timeout_seconds = 900.0
    binary = tmp_path / "fake-cli"
    binary.write_text(f"#!/usr/bin/env python3\nimport sys\nsys.stdin.read()\nprint('local-version' if '--version' in sys.argv else {output!r})\n")
    binary.chmod(0o755)
    monkeypatch.chdir(tmp_path)
    monkeypatch.setenv(f"{name.upper()}_HEADLESS_BIN", str(binary))
    seen = []
    real = type(adapter)._compute_timeout
    monkeypatch.setattr(adapter, "_compute_timeout", lambda *a, **k: seen.append(real(adapter, *a, **k)) or seen[-1])
    result = adapter.complete(CompletionRequest(messages=[{"role": "user", "content": "ping"}], model="entry"))
    assert result.content == "pong"
    assert seen == [910.0]


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
    from loa_cheval.types import reset_headless_timeout_reports
    reset_headless_timeout_reports()
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
    assert caplog.text.count("applies to CLI models only") == 2
    assert "p/x: headless_timeout_seconds 900 applies to CLI models only (kind: cli, or a *-headless provider) — ignored on this model (kind: none, provider type: anthropic)" in caplog.text
    assert "p/y: headless_timeout_seconds 900 applies to CLI models only (kind: cli, or a *-headless provider) — ignored on this model (kind: http_api, provider type: anthropic)" in caplog.text
    # a model of a *-headless provider is a CLI model without a model-level kind (fourteenth run, d C-002)
    cfg2 = {"providers": {"g": {"type": "grok-headless", "endpoint": "", "auth": "none", "models": {"grok-headless": {"context_window": 1000, "headless_timeout_seconds": 800}}}}}
    caplog.clear()
    pg = cheval._build_provider_config("g", cfg2)
    assert pg.models["grok-headless"].headless_timeout_seconds == 800.0
    assert caplog.text == ""
    # a provider with no `type:` is the openai adapter — never a headless one — so the gate's empty default and the
    # loader's "openai" default agree: the key is dropped, and no headless hop runs without it (twenty-first run, d C-002)
    cfg3 = {"providers": {"n": {"endpoint": "", "auth": "none", "models": {"m": {"context_window": 1000, "headless_timeout_seconds": 800}}}}}
    pn = cheval._build_provider_config("n", cfg3)
    assert pn.type == "openai" and not pn.type.endswith("-headless")
    assert pn.models["m"].headless_timeout_seconds is None
    assert "n/m: headless_timeout_seconds 800 applies to CLI models only" in caplog.text
    caplog.clear()
    # a chain walk rebuilds the provider config per hop: the same two defects are not reported again (d C-002)
    with caplog.at_level(logging.WARNING, logger="loa_cheval.config"):
        pc2 = cheval._build_provider_config("p", cfg)
        pc3 = cheval._build_provider_config("p", cfg)
    assert pc2.models["x"].headless_timeout_seconds is None and pc3.models["x"].headless_timeout_seconds is None
    assert caplog.text.count("applies to CLI models only") == 0   # (the log was cleared above: two rebuilds added nothing)


def test_headless_timeout_report_gate_keys(caplog):
    """The once-per-process report gate keys on repr(raw): a repeated NaN is reported once, while False and 0 —
    equal and equal-hashing in Python — are distinct defects and each reported (twentieth run, c2e C-002)."""
    from loa_cheval.types import coerce_headless_timeout_seconds, reset_headless_timeout_reports
    reset_headless_timeout_reports()
    with caplog.at_level(logging.WARNING, logger="loa_cheval.config"):
        caplog.clear()
        assert coerce_headless_timeout_seconds(float("nan"), where="p/m: ") is None
        assert coerce_headless_timeout_seconds(float("nan"), where="p/m: ") is None
        assert len(caplog.records) == 1
        assert coerce_headless_timeout_seconds(False, where="p/m: ") is None
        assert coerce_headless_timeout_seconds(0, where="p/m: ") is None
        assert len(caplog.records) == 3
    assert "headless_timeout_seconds False ignored: a boolean" in caplog.records[1].getMessage()
    assert "headless_timeout_seconds 0 ignored: not a positive finite number" in caplog.records[2].getMessage()


def test_headless_timeout_note_is_durable(caplog, tmp_path, monkeypatch):
    """A catalog `headless_timeout_seconds` that was not applied as written leaves more than a one-shot WARNING on
    stderr (which the dissent path discards): the loader's verdict travels on the ModelConfig and the adapter appends
    it to its timeout error, so the MODELINV row says why the hop ran on the floor (sixteenth run, d C-001)."""
    import subprocess
    import cheval
    from loa_cheval.types import headless_timeout_note, reset_headless_timeout_reports
    # the helper's four verdicts
    assert headless_timeout_note(None, None, None) is None
    assert headless_timeout_note(900, 900, 900.0) is None                       # applied as written
    assert headless_timeout_note("900", "900", 900.0) is None                   # a quoted number applies as written
    assert headless_timeout_note(900, None, None) == "catalog headless_timeout_seconds 900 not applied: CLI models only"
    assert headless_timeout_note("15m", "15m", None) == "catalog headless_timeout_seconds '15m' ignored: not a positive finite number of seconds"
    assert headless_timeout_note(True, True, None) == "catalog headless_timeout_seconds True ignored: not a positive finite number of seconds"
    assert headless_timeout_note(7200, 7200, 3600.0) == "catalog headless_timeout_seconds 7200 clamped to 3600s"
    # …set by the loader, per model
    reset_headless_timeout_reports()
    cfg = {"providers": {"p": {"type": "anthropic", "endpoint": "https://example.invalid", "auth": "none", "models": {
        "ok": {"kind": "cli", "context_window": 1000, "headless_timeout_seconds": 900},
        "bad": {"kind": "cli", "context_window": 1000, "headless_timeout_seconds": "15m"},
        "big": {"kind": "cli", "context_window": 1000, "headless_timeout_seconds": 7200},
        "http": {"context_window": 1000, "headless_timeout_seconds": 900},
        "none": {"kind": "cli", "context_window": 1000},
        "low": {"kind": "cli", "context_window": 1000, "headless_timeout_seconds": 300},
    }}}}
    with caplog.at_level(logging.WARNING, logger="loa_cheval.config"):
        pc = cheval._build_provider_config("p", cfg)
    assert pc.models["ok"].headless_timeout_note is None and pc.models["ok"].headless_timeout_seconds == 900.0
    assert pc.models["none"].headless_timeout_note is None
    assert pc.models["bad"].headless_timeout_note == "catalog headless_timeout_seconds '15m' ignored: not a positive finite number of seconds"
    assert pc.models["bad"].headless_timeout_seconds is None
    assert pc.models["big"].headless_timeout_note == "catalog headless_timeout_seconds 7200 clamped to 3600s"
    assert pc.models["big"].headless_timeout_seconds == 3600.0
    assert pc.models["http"].headless_timeout_note == "catalog headless_timeout_seconds 900 not applied: CLI models only"
    # a positive value the read floor overrides is not applied either — it says so (nineteenth run, d C-001)
    assert pc.models["low"].headless_timeout_note == "catalog headless_timeout_seconds 300 at or below the 600s read floor: the floor applies"
    assert pc.models["low"].headless_timeout_seconds == 300.0
    assert headless_timeout_note(300, 300, 300.0, floor=600.0) == "catalog headless_timeout_seconds 300 at or below the 600s read floor: the floor applies"
    assert headless_timeout_note(900, 900, 900.0, floor=600.0) is None
    assert headless_timeout_note(900, 900, 900.0, floor=4000.0) == "catalog headless_timeout_seconds 900 at or below the 4000s read floor: the floor applies"
    # a clamped value the read floor still overrides names both: the floor is what the hop ran on (twentieth run, d C-002)
    assert headless_timeout_note(4500, 4500, 3600.0, floor=4000.0) == "catalog headless_timeout_seconds 4500 clamped to 3600s, at or below the 4000s read floor: the floor applies"
    assert headless_timeout_note(7200, 7200, 3600.0, floor=600.0) == "catalog headless_timeout_seconds 7200 clamped to 3600s"
    # …and the loader computes the floor from the provider's own read_timeout (twentieth run, c2e C-001)
    cfg_hi = {"providers": {"q": {"type": "anthropic", "endpoint": "https://example.invalid", "auth": "none", "read_timeout": 4000, "models": {
        "mid": {"kind": "cli", "context_window": 1000, "headless_timeout_seconds": 900},
        "huge": {"kind": "cli", "context_window": 1000, "headless_timeout_seconds": 4500},
    }}}}
    pq = cheval._build_provider_config("q", cfg_hi)
    assert pq.models["mid"].headless_timeout_note == "catalog headless_timeout_seconds 900 at or below the 4000s read floor: the floor applies"
    assert pq.models["huge"].headless_timeout_note == "catalog headless_timeout_seconds 4500 clamped to 3600s, at or below the 4000s read floor: the floor applies"
    assert pq.models["huge"].headless_timeout_seconds == 3600.0
    # a chain walk rebuilds the provider config per hop: the note and the effective bound are computed from values on every
    # build, never from the once-per-process report gate (nineteenth run, c2e C-002)
    pc2 = cheval._build_provider_config("p", cfg)
    pc3 = cheval._build_provider_config("p", cfg)
    for later in (pc2, pc3):
        for m in ("ok", "bad", "big", "http", "none", "low"):
            assert later.models[m].headless_timeout_note == pc.models[m].headless_timeout_note, m
            assert later.models[m].headless_timeout_seconds == pc.models[m].headless_timeout_seconds, m
    assert pc3.models["big"].headless_timeout_seconds == 3600.0
    # complete() runs in an isolated cwd with the binary pinned to a stub that is never executed (c2e C-003), as its siblings do
    monkeypatch.chdir(tmp_path)
    fake = tmp_path / "fake-claude"
    fake.write_text("#!/bin/sh\nexit 1\n")
    fake.chmod(0o755)
    monkeypatch.setenv("CLAUDE_HEADLESS_BIN", str(fake))
    # …and appended to the adapter's timeout error, where the MODELINV row reads it; absent when there is nothing to say
    for note, expect in ((pc.models["bad"].headless_timeout_note, " (catalog headless_timeout_seconds '15m' ignored: not a positive finite number of seconds)"), (None, "")):
        config = ProviderConfig(
            name="claude-headless", type="claude-headless", endpoint="", auth="", connect_timeout=1, read_timeout=1,
            models={"entry": ModelConfig(context_window=200000, extra={"cli_model": "m"}, headless_timeout_note=note)},
        )
        adapter = ClaudeHeadlessAdapter(config)

        def _timeout(*_a, **_k):
            raise subprocess.TimeoutExpired(cmd=["claude"], timeout=1)

        adapter._run_subprocess = _timeout
        with pytest.raises(ProviderUnavailableError) as exc_info:
            adapter.complete(CompletionRequest(model="entry", messages=[{"role": "user", "content": "ping"}]))
        assert ("timed out after 610s" + expect) in str(exc_info.value)
        if note is None:
            assert not str(exc_info.value).rstrip().endswith(")")   # nothing to say → nothing appended


# run 23, c2e DISS-C-001: the once-per-process report gate is module state — conftest resets it around every
# test, so a key one test seeds never silences a warning another test asserts (pytest runs these two in file order)
def test_report_gate_seeded_here_without_a_reset():
    from loa_cheval import types as _types
    _types.report_headless_timeout_once(("gate-leak/x: ", 900), "seeded %s", "here")
    assert ("gate-leak/x: ", 900) in _types._HEADLESS_TIMEOUT_REPORTED


def test_report_gate_is_empty_when_the_next_test_starts():
    from loa_cheval import types as _types
    assert not _types._HEADLESS_TIMEOUT_REPORTED
