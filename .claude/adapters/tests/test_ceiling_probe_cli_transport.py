"""cycle-127 Sprint 1 Task 1.4 (FR-3.1/3.2, SDD D-3.1/D-3.2, D-3.5…D-3.9):
`tools/ceiling-probe-live.py --transport claude-headless`.

The probe bisects the accepted input size through `${CLAUDE_HEADLESS_BIN:-claude}`
with the headless adapter's own argv (`build_headless_argv`) plus
`--effort low --max-turns 1`. An attempt is accepted only when the completed JSON
`result` echoes the prompt's trailing needle; the accepted size is the CLI's
measured usage. Size rejections (provider or CLI-local) bracket the bound;
throttling / 429 / 5xx retry up to 3 attempts; anything else is `other`. Only a
`clean` outcome writes the catalog (`operator_set`, `method: probed_headless`).

No real CLI is ever spawned: CLAUDE_HEADLESS_BIN (or PATH) points at a recording
fake, and the module asserts zero live spend (no `.run/model-invoke.jsonl` write).
"""
from __future__ import annotations

import importlib.util
import json
import os
import stat
import subprocess
import sys
import textwrap
from pathlib import Path

import pytest
import yaml

ROOT = Path(__file__).resolve().parents[3]
TOOL = ROOT / "tools" / "ceiling-probe-live.py"
CATALOG = ROOT / ".claude" / "defaults" / "model-config.yaml"
SCHEMA_V3 = ROOT / ".claude" / "data" / "schemas" / "model-config-v3.schema.json"
MODELINV_LOG = ROOT / ".run" / "model-invoke.jsonl"

# The filler is ≈10 tokens per 45 characters; the fake compares stdin characters.
CHARS_PER_TOKEN = 4.5
OVERHEAD = 3000          # the fake's "system prompt" share of the measured usage

FAKE = textwrap.dedent('''\
    #!{python}
    import json, os, re, sys
    if sys.argv[1:] == ["--version"]:
        print("9.9.9 (Fake Claude)")
        sys.exit(0)
    data = sys.stdin.read()
    log = os.environ["FAKE_LOG"]
    with open(log, "a") as fh:
        fh.write(json.dumps({{"argv": sys.argv, "stdin_chars": len(data), "tail": data[-80:],
                             "cwd": os.getcwd(), "auto_memory": os.environ.get("CLAUDE_CODE_DISABLE_AUTO_MEMORY")}}) + "\\n")
    calls = sum(1 for _ in open(log))
    m = re.search(r"code and nothing else: ([0-9a-f]{{12}})$", data)
    needle = m.group(1) if m else "NO-NEEDLE"
    mode = os.environ.get("FAKE_MODE", "limit")
    limit = int(os.environ.get("FAKE_LIMIT_CHARS", "1000000000"))
    measured = int(len(data) / 4.5) + {overhead}

    def err(msg, status=None):
        body = {{"type": "result", "is_error": True, "result": msg}}
        if status:
            body["api_error_status"] = status
        print(json.dumps(body))
        sys.exit(1)

    if mode == "other":
        err("Not logged in · Please run /login")
    if mode == "garbage":
        print("not json at all")
        sys.exit(0)
    if mode == "throttle":
        err("API Error: ThrottlingException: Too many requests, please wait before trying again.")
    if mode == "5xx":
        err("API Error: 500 internal server error")
    if mode == "flaky" and calls <= 2:
        err("API Error: 529 overloaded")
    if len(data) > limit:
        if mode == "tpm":
            err("API Error: 429 This request would exceed your organization's rate limit of 300,000 input tokens per minute")
        if os.environ.get("FAKE_ORIGIN") == "cli":
            err("Prompt is too long")
        err("API Error: 400 prompt is too long: 912345 tokens > 800000 maximum", status=400)
    result = "ok" if mode == "noneedle" else needle
    body = {{"type": "result", "subtype": "success", "is_error": False, "result": result, "stop_reason": "end_turn",
             "usage": {{"input_tokens": 5, "cache_creation_input_tokens": measured - 5,
                       "cache_read_input_tokens": 0, "output_tokens": 3}}}}
    if os.environ.get("FAKE_COST"):
        body["total_cost_usd"] = float(os.environ["FAKE_COST"])
    print(json.dumps(body))
''')


def _stat(p: Path):
    return (p.stat().st_size, p.stat().st_mtime_ns) if p.exists() else None


@pytest.fixture(scope="module", autouse=True)
def _zero_live_spend():
    """No test in this module may reach a model: the ledger cheval appends on
    every invoke is byte-for-byte where it was."""
    before = _stat(MODELINV_LOG)
    yield
    assert _stat(MODELINV_LOG) == before, ".run/model-invoke.jsonl changed — a live call escaped the fake"


@pytest.fixture(scope="module")
def tool():
    spec = importlib.util.spec_from_file_location("ceiling_probe_live_cli", TOOL)
    mod = importlib.util.module_from_spec(spec)
    sys.modules["ceiling_probe_live_cli"] = mod
    spec.loader.exec_module(mod)
    return mod


def _write_fake(path: Path) -> Path:
    path.write_text(FAKE.format(python=sys.executable, overhead=OVERHEAD))
    path.chmod(path.stat().st_mode | stat.S_IXUSR)
    return path


@pytest.fixture
def fake(tmp_path, monkeypatch, tool):
    bin_path = _write_fake(tmp_path / "fake-claude")
    log = tmp_path / "calls.jsonl"
    monkeypatch.setenv("CLAUDE_HEADLESS_BIN", str(bin_path))
    monkeypatch.setenv("FAKE_LOG", str(log))
    for var in ("ANTHROPIC_API_KEY", "ANTHROPIC_DEFAULT_OPUS_MODEL", "FAKE_MODE", "FAKE_LIMIT_CHARS",
                "FAKE_ORIGIN", "FAKE_COST", "AWS_REGION", "ANTHROPIC_BEDROCK_REGION_PREFIX",
                "CLAUDE_CODE_USE_BEDROCK"):
        monkeypatch.delenv(var, raising=False)
    sleeps: list = []
    monkeypatch.setattr(tool, "_SLEEP", sleeps.append)

    def calls():
        if not log.exists():
            return []
        return [json.loads(l) for l in log.read_text().splitlines() if l.strip()]

    return {"bin": str(bin_path), "calls": calls, "dir": tmp_path, "sleeps": sleeps}


def _limit(monkeypatch, tokens: int):
    monkeypatch.setenv("FAKE_LIMIT_CHARS", str(int(tokens * CHARS_PER_TOKEN)))


def _run(tool, monkeypatch, tmp_path, *extra):
    out = tmp_path / "record.json"
    argv = ["ceiling-probe-live.py", "--model", "claude-opus-5-5", "--transport", "claude-headless",
            "--min-tokens-probe", "100000", "--max-tokens-probe", "400000", "--budget-usd", "20",
            "--output", str(out), *extra]
    monkeypatch.setattr(sys, "argv", argv)
    code = tool.main()
    record = json.loads(out.read_text()) if out.exists() else None
    return code, record


PINNED = ["-p", "--output-format", "json", "--permission-mode", "plan", "--no-session-persistence",
          "--tools", "", "--model", "claude-opus-5-5", "--effort", "low", "--max-turns", "1"]


# --- command shape ----------------------------------------------------------

def test_cli_command_is_the_adapter_argv_plus_the_probe_pins(tool, fake, monkeypatch, tmp_path):
    _limit(monkeypatch, 250_000)
    code, record = _run(tool, monkeypatch, tmp_path)
    assert code == 0, record
    first = fake["calls"]()[0]
    assert first["argv"][1:] == PINNED
    assert record["argv"] == [fake["bin"], *PINNED]
    # prompt on stdin (never argv), ≈ N tokens of filler ending in the needle line
    assert "code and nothing else: " in first["tail"] and len(first["tail"].rsplit(" ", 1)[1]) == 12
    assert 400_000 * 4 <= first["stdin_chars"] <= 400_000 * 5
    assert all(len(a) < 1000 for a in first["argv"])
    # private cwd outside the tree, auto memory off — as the adapter
    assert not str(Path(first["cwd"]).resolve()).startswith(str(ROOT.resolve()))
    assert first["auto_memory"] == "1"


def test_the_probe_builds_its_argv_with_the_adapter_builder(tool):
    sys.path.insert(0, str(ROOT / ".claude" / "adapters"))
    from loa_cheval.providers.claude_headless_adapter import ClaudeHeadlessAdapter, build_headless_argv
    from loa_cheval.types import CompletionRequest, ModelConfig, ProviderConfig
    adapter = ClaudeHeadlessAdapter(ProviderConfig(name="claude-headless", type="claude-headless", endpoint="",
                                                   auth="", connect_timeout=1.0, read_timeout=600.0,
                                                   models={"m": ModelConfig(context_window=1)}))
    req = CompletionRequest(messages=[{"role": "user", "content": "x"}], model="opus", max_tokens=16, effort="low")
    adapter_argv = adapter._build_command(req, ModelConfig(context_window=1), None)
    assert adapter_argv == build_headless_argv(adapter_argv[0], "opus", effort="low")
    assert tool._cli_command(adapter_argv[0], "opus") == adapter_argv + ["--max-turns", "1"]


def test_runs_from_another_cwd_under_python_isolated_mode(tmp_path, monkeypatch):
    bin_path = _write_fake(tmp_path / "fake-claude")
    out = tmp_path / "r.json"
    env = {k: v for k, v in os.environ.items() if k not in ("ANTHROPIC_API_KEY", "PYTHONPATH")}
    env.update(CLAUDE_HEADLESS_BIN=str(bin_path), FAKE_LOG=str(tmp_path / "c.jsonl"),
               FAKE_LIMIT_CHARS=str(int(250_000 * CHARS_PER_TOKEN)))
    proc = subprocess.run([sys.executable, "-I", str(TOOL), "--model", "claude-opus-5-5", "--transport",
                           "claude-headless", "--min-tokens-probe", "100000", "--max-tokens-probe", "400000",
                           "--budget-usd", "20", "--output", str(out)],
                          cwd=str(tmp_path), env=env, capture_output=True, text=True, timeout=300)
    assert proc.returncode == 0, proc.stderr
    assert json.loads(out.read_text())["outcome"] == "clean"


def test_default_binary_is_claude_on_path(tool, fake, monkeypatch, tmp_path):
    bindir = tmp_path / "bin"
    bindir.mkdir()
    _write_fake(bindir / "claude")
    monkeypatch.delenv("CLAUDE_HEADLESS_BIN", raising=False)
    monkeypatch.setenv("PATH", f"{bindir}{os.pathsep}{os.environ['PATH']}")
    _limit(monkeypatch, 250_000)
    code, record = _run(tool, monkeypatch, tmp_path)
    assert code == 0 and record["cli_bin"] == "claude"
    assert fake["calls"]() and record["cli_version"] == "9.9.9 (Fake Claude)"


# --- classification, measurement, outcome -----------------------------------

def test_clean_bisection_measures_and_brackets_the_bound(tool, fake, monkeypatch, tmp_path, capsys):
    _limit(monkeypatch, 250_000)
    code, record = _run(tool, monkeypatch, tmp_path)
    assert code == 0
    assert record["outcome"] == "clean" and record["reasons"] == [] and record["partial"] is False
    ok, fail = record["largest_ok_input_tokens"], record["smallest_failed_input_tokens"]
    assert ok < 250_000 <= fail and fail - ok <= 16_000
    # measured, not estimated: the CLI's usage (filler + the fake's overhead), recorded per step
    assert record["measured_input_tokens"] > ok
    assert record["measured_input_tokens"] == next(s["measured_input_tokens"] for s in record["samples"]
                                                    if s["tokens"] == ok)
    assert all("tokens" in s and "measured_input_tokens" in s for s in record["samples"])
    failed = [s for s in record["samples"] if s["kind"] == "size"]
    assert failed and all(s["failure_class"] == "context_limit" and s["size_origin"] == "provider" for s in failed)
    assert all(s["verified"] for s in record["samples"] if s["kind"] == "ok")
    # record provenance
    assert record["transport"] == "claude-headless" and record["method"] == "probed_headless"
    assert record["source"] == "operator_set" and record["pricing_basis"] == "catalog_estimate"
    assert record["bounds_tested"] == {"min": 100_000, "max": 400_000} and record["budget_usd"] == 20
    assert record["tolerance_tokens"] == 16_000 and record["started_at"] and record["calibrated_at"]
    assert record["cli_version"] == "9.9.9 (Fake Claude)" and record["cli_model"] == "claude-opus-5-5"
    assert record["route_env"] == {"AWS_REGION": None, "ANTHROPIC_BEDROCK_REGION_PREFIX": None,
                                   "CLAUDE_CODE_USE_BEDROCK": False}
    assert len(fake["calls"]()) == record["sample_size"]
    # worst-case step cost and how many fit, printed before the first live call
    err = capsys.readouterr().err
    assert "worst-case step ≈ $1.60" in err and "12 such steps fit in $20" in err
    assert err.index("worst-case step") < err.index("tokens (attempt 1)")


def test_cli_local_preflight_rejection_counts_as_size(tool, fake, monkeypatch, tmp_path):
    _limit(monkeypatch, 250_000)
    monkeypatch.setenv("FAKE_ORIGIN", "cli")
    code, record = _run(tool, monkeypatch, tmp_path)
    assert code == 0 and record["outcome"] == "clean"
    assert {s["size_origin"] for s in record["samples"] if s["kind"] == "size"} == {"cli_local"}


def test_tolerance_tokens_sets_the_stop(tool, fake, monkeypatch, tmp_path):
    _limit(monkeypatch, 250_000)
    code, record = _run(tool, monkeypatch, tmp_path, "--tolerance-tokens", "2000")
    assert code == 0
    assert record["smallest_failed_input_tokens"] - record["largest_ok_input_tokens"] <= 2000
    code2, wide = _run(tool, monkeypatch, tmp_path, "--tolerance-tokens", "60000")
    assert wide["sample_size"] < record["sample_size"]


def test_a_completion_without_the_needle_is_unverified_and_partial(tool, fake, monkeypatch, tmp_path):
    monkeypatch.setenv("FAKE_MODE", "noneedle")
    catalog = tmp_path / "model-config.yaml"
    catalog.write_text(CATALOG.read_text())
    code, record = _run(tool, monkeypatch, tmp_path, "--write-catalog", str(catalog))
    assert code == 3
    assert record["outcome"] == "partial" and record["unverified"] is True
    assert record["largest_ok_input_tokens"] == 0, "an unverified completion is never counted as OK"
    assert any("unverified" in r for r in record["reasons"])
    assert catalog.read_text() == CATALOG.read_text()


def test_top_accepted_without_a_rejection_is_not_clean(tool, fake, monkeypatch, tmp_path):
    code, record = _run(tool, monkeypatch, tmp_path)
    assert code == 3 and record["outcome"] == "partial"
    assert any("not bracketed" in r for r in record["reasons"])


def test_transient_classes_retry_with_backoff_and_count_every_attempt(tool, fake, monkeypatch, tmp_path):
    _limit(monkeypatch, 250_000)
    monkeypatch.setenv("FAKE_MODE", "flaky")       # the first two calls answer 529 overloaded
    code, record = _run(tool, monkeypatch, tmp_path)
    assert code == 0 and record["outcome"] == "clean"
    top = record["samples"][0]
    assert top["tokens"] == 400_000 and top["attempts"] == 3
    assert fake["sleeps"] == [5, 15]
    # three attempts at 400K are all paid for (two rejected at the requested size, one measured)
    assert top["cost_usd"] >= 3 * 1.6 - 0.01
    assert record["spent_usd"] == pytest.approx(sum(s["cost_usd"] for s in record["samples"]), abs=1e-3)


@pytest.mark.parametrize("mode", ["throttle", "5xx"])
def test_a_transient_class_that_persists_is_other_after_three_attempts(tool, fake, monkeypatch, tmp_path, mode):
    monkeypatch.setenv("FAKE_MODE", mode)
    catalog = tmp_path / "model-config.yaml"
    catalog.write_text(CATALOG.read_text())
    code, record = _run(tool, monkeypatch, tmp_path, "--write-catalog", str(catalog))
    assert code == 1 and record["outcome"] == "partial" and record["error"]
    assert len(fake["calls"]()) == 3 and record["samples"][0]["attempts"] == 3
    assert catalog.read_text() == CATALOG.read_text()


def test_a_token_budget_429_that_persists_at_a_size_is_a_size_rejection(tool, fake, monkeypatch, tmp_path):
    _limit(monkeypatch, 300_000)
    monkeypatch.setenv("FAKE_MODE", "tpm")
    code, record = _run(tool, monkeypatch, tmp_path)
    assert code == 0, record["reasons"]
    failed = [s for s in record["samples"] if s["kind"] == "size"]
    assert failed and all(s["failure_class"] == "token_limit" and s["attempts"] == 3 for s in failed)
    assert record["largest_ok_input_tokens"] < 300_000 <= record["smallest_failed_input_tokens"]


@pytest.mark.parametrize("mode", ["other", "garbage"])
def test_any_other_failure_exits_1_with_the_error_recorded_and_writes_nothing(tool, fake, monkeypatch, tmp_path, mode):
    monkeypatch.setenv("FAKE_MODE", mode)
    catalog = tmp_path / "model-config.yaml"
    catalog.write_text(CATALOG.read_text())
    code, record = _run(tool, monkeypatch, tmp_path, "--write-catalog", str(catalog))
    assert code == 1
    assert record["error"] and record["outcome"] == "partial"
    assert catalog.read_text() == CATALOG.read_text()
    assert len(fake["calls"]()) == 1   # not retried: neither size nor transient


def test_missing_binary_is_other(tool, fake, monkeypatch, tmp_path):
    monkeypatch.setenv("CLAUDE_HEADLESS_BIN", str(tmp_path / "no-such-claude"))
    code, record = _run(tool, monkeypatch, tmp_path)
    assert code == 1 and record["error"] and record["cli_version"] is None


def test_inconsistent_classifications_are_partial(tool):
    samples = [{"tokens": 300_000, "kind": "ok"}, {"tokens": 250_000, "kind": "size"}]
    reasons = tool._outcome_reasons(samples, stop=None, largest_ok=300_000, measured=303_000,
                                    smallest_fail=250_000, hi=400_000, tol=16_000)
    assert any("inconsistent" in r for r in reasons)
    clean = [{"tokens": 240_000, "kind": "ok"}, {"tokens": 250_000, "kind": "size"}]
    assert tool._outcome_reasons(clean, stop=None, largest_ok=240_000, measured=243_000,
                                 smallest_fail=250_000, hi=400_000, tol=16_000) == []
    assert tool._outcome_reasons(clean, stop=None, largest_ok=240_000, measured=None,
                                 smallest_fail=250_000, hi=400_000, tol=16_000)


# --- budget -----------------------------------------------------------------

def test_budget_cap_stops_with_partial_and_writes_nothing(tool, fake, monkeypatch, tmp_path):
    _limit(monkeypatch, 150_000)
    catalog = tmp_path / "model-config.yaml"
    catalog.write_text(CATALOG.read_text())
    # 400K top ($1.60) fits; the first mid (250K, $1.00) does not fit in $2
    code, record = _run(tool, monkeypatch, tmp_path, "--budget-usd", "2", "--write-catalog", str(catalog),
                        "--allow-partial")
    assert code == 3
    assert record["outcome"] == "partial" and any("budget" in r for r in record["reasons"])
    assert record["spent_usd"] <= 2
    assert catalog.read_text() == CATALOG.read_text(), "a partial CLI-transport record is never written"


def test_budget_below_the_first_call_makes_no_call(tool, fake, monkeypatch, tmp_path):
    code, record = _run(tool, monkeypatch, tmp_path, "--budget-usd", "0.5")
    assert code == 3 and record["partial"] is True and record["sample_size"] == 0
    assert fake["calls"]() == []


def test_spend_is_the_larger_of_the_cli_cost_and_the_catalog_estimate(tool, fake, monkeypatch, tmp_path):
    _limit(monkeypatch, 250_000)
    monkeypatch.setenv("FAKE_COST", "9.0")          # an implausibly high CLI-reported cost wins
    code, record = _run(tool, monkeypatch, tmp_path, "--budget-usd", "40")
    ok_steps = [s for s in record["samples"] if s["kind"] == "ok"]
    assert ok_steps and all(s["cost_usd"] >= 9.0 for s in ok_steps)


# --- cli_model / host_route / env -------------------------------------------

def test_cli_model_alias_resolves_through_the_wrapper_env_when_visible(tool, fake, monkeypatch, tmp_path):
    _limit(monkeypatch, 250_000)
    monkeypatch.setenv("ANTHROPIC_DEFAULT_OPUS_MODEL", "global.anthropic.claude-opus-5-5")
    monkeypatch.setenv("AWS_REGION", "us-east-1")
    monkeypatch.setenv("ANTHROPIC_BEDROCK_REGION_PREFIX", "global")
    monkeypatch.setenv("CLAUDE_CODE_USE_BEDROCK", "1")
    code, record = _run(tool, monkeypatch, tmp_path, "--cli-model", "opus")
    assert code == 0
    assert record["cli_model"] == "global.anthropic.claude-opus-5-5"
    argv0 = fake["calls"]()[0]["argv"]
    assert argv0[argv0.index("--model") + 1] == "opus"   # the CLI resolves the alias itself
    assert record["model"] == "claude-opus-5-5"
    assert record["route_env"] == {"AWS_REGION": "us-east-1", "ANTHROPIC_BEDROCK_REGION_PREFIX": "global",
                                   "CLAUDE_CODE_USE_BEDROCK": True}
    assert record["host_route"].startswith("bedrock")


def test_cli_model_alias_without_env_is_recorded_as_passed(tool, fake, monkeypatch, tmp_path):
    _limit(monkeypatch, 250_000)
    code, record = _run(tool, monkeypatch, tmp_path, "--cli-model", "opus", "--host-route", "bedrock us-east-1 global")
    assert code == 0
    assert record["cli_model"] == "opus" and record["host_route"] == "bedrock us-east-1 global"


# --- helpers ----------------------------------------------------------------

def test_attempt_timeout_scales_with_size_and_is_capped(tool):
    assert tool._attempt_timeout(0) == 120
    assert tool._attempt_timeout(400_000) == 320
    assert tool._attempt_timeout(10_000_000) == 1800


def test_captured_output_is_capped_at_1mb(tool):
    rc, out, err = tool._run_capped([sys.executable, "-c",
                                     "import sys; sys.stdout.write('x' * 3000000); sys.stderr.write('y' * 2000000)"],
                                    "", 60)
    assert rc == 0 and len(out) == 1 << 20 and len(err) == 1 << 20


# --- the operator_set write -------------------------------------------------

def _w(tool, text, ceiling, **kw):
    args = dict(calibrated_at="2026-10-07T12:00:00Z", cli_model="global.anthropic.claude-opus-5-5",
                host_route="bedrock (claude-bedrock)", cli_version="2.1.292 (Claude Code)")
    args.update(kw)
    return tool.write_catalog_operator_set(text, "claude-opus-5-5", ceiling=ceiling, **args)


def test_write_operator_set_changes_only_the_entry_and_replaces_the_shortcut(tool):
    before = CATALOG.read_text()
    if "# loa:shortcut: Opus 5's measured bound, not probed on 5.5" not in before:
        pytest.skip("the catalog is already calibrated (the lead's probe write landed)")
    after = _w(tool, before, 640_000)
    b, a = yaml.safe_load(before), yaml.safe_load(after)
    entry = a["providers"]["anthropic"]["models"]["claude-opus-5-5"]
    assert entry["probed_ceiling"] == 640_000
    # a calibrated entry is bounded by effective_input_ceiling (routing/ceiling.input_bound),
    # so the measured value lands there too — otherwise the write would be inert
    assert entry["effective_input_ceiling"] == 640_000
    cal = entry["ceiling_calibration"]
    assert cal["source"] == "operator_set" and cal["method"] == "probed_headless"
    assert cal["transport"] == "claude-headless" and cal["cli_version"] == "2.1.292 (Claude Code)"
    assert cal["cli_model"] == "global.anthropic.claude-opus-5-5" and cal["measured_input_tokens"] == 640_000
    assert cal["calibrated_at"] == "2026-10-07T12:00:00Z"
    assert cal["sample_size"] is None and cal["stale_after_days"] == 90
    assert cal["reprobe_trigger"].startswith("API-transport probe (tools/ceiling-probe-live.py --transport api) "
                                             "from a host with ANTHROPIC_API_KEY;")
    assert "through claude-headless on Bedrock (global.anthropic.claude-opus-5-5) on 2026-10-07" in cal["reprobe_trigger"]
    for prov, pv in b["providers"].items():
        for mid, me in (pv.get("models") or {}).items():
            if (prov, mid) != ("anthropic", "claude-opus-5-5"):
                assert a["providers"][prov]["models"][mid] == me, (prov, mid)
    be = b["providers"]["anthropic"]["models"]["claude-opus-5-5"]
    for k in set(be) | set(entry):
        if k not in ("probed_ceiling", "effective_input_ceiling", "ceiling_calibration"):
            assert entry.get(k) == be.get(k), k
    assert a["aliases"] == b["aliases"]
    assert "loa:shortcut: Opus 5's measured bound" not in after
    assert sum(1 for l in after.splitlines() if l.strip().startswith("#")) == \
        sum(1 for l in before.splitlines() if l.strip().startswith("#")) - 1
    prov_lines = [l for l in after.splitlines() if "cycle-127 FR-3" in l and "claude-headless" in l]
    assert len(prov_lines) == 1 and prov_lines[0].startswith("        # ")
    bl, al = before.splitlines(), after.splitlines()
    start = bl.index("      claude-opus-5-5:")
    assert bl[:start] == al[:start]
    assert bl[bl.index("      claude-opus-5:"):] == al[al.index("      claude-opus-5:"):]
    sys.path.insert(0, str(ROOT / ".claude" / "adapters"))
    from loa_cheval.routing.ceiling import input_bound
    d = input_bound(entry, max_tokens=64_000)
    assert d.basis == "calibrated" and d.value == 640_000
    import jsonschema
    schema = json.loads(SCHEMA_V3.read_text())
    jsonschema.validate(cal, {**schema["$defs"]["ceilingCalibration"], "$defs": schema["$defs"]})


def test_a_measured_bound_below_the_old_one_is_written_as_measured(tool):
    after = _w(tool, CATALOG.read_text(), 120_000)
    entry = yaml.safe_load(after)["providers"]["anthropic"]["models"]["claude-opus-5-5"]
    assert entry["probed_ceiling"] == entry["effective_input_ceiling"] == 120_000
    assert entry["ceiling_calibration"]["measured_input_tokens"] == 120_000


def test_write_operator_set_keeps_stale_after_days_is_idempotent_and_refuses_bad_input(tool):
    text = CATALOG.read_text()
    start = text.index("      claude-opus-5-5:")
    nxt = text.index("      claude-opus-5:", start)
    text = text[:start] + text[start:nxt].replace("stale_after_days: 90", "stale_after_days: 45", 1) + text[nxt:]
    once = _w(tool, text, 500_000, cli_model="opus", host_route="claude CLI", cli_version=None)
    entry = yaml.safe_load(once)["providers"]["anthropic"]["models"]["claude-opus-5-5"]
    assert entry["ceiling_calibration"]["stale_after_days"] == 45
    assert entry["ceiling_calibration"]["cli_version"] is None
    assert "through claude-headless on claude CLI (opus) on 2026-10-07" in entry["ceiling_calibration"]["reprobe_trigger"]
    assert _w(tool, once, 500_000, cli_model="opus", host_route="claude CLI", cli_version=None) == once
    rewritten = _w(tool, once, 450_000, cli_model="opus", host_route="claude CLI", cli_version=None)
    assert sum(1 for l in rewritten.splitlines() if "cycle-127 FR-3: bound measured" in l) == 1
    for bad in (0, -1, True, "500000"):
        with pytest.raises(ValueError):
            _w(tool, text, bad)
    with pytest.raises(ValueError):
        tool.write_catalog_operator_set(text, "claude-nope-9", ceiling=1, calibrated_at="2026-10-07T00:00:00Z",
                                        cli_model="x", host_route="y")


def test_cli_write_catalog_end_to_end_on_a_temp_copy(tool, fake, monkeypatch, tmp_path):
    _limit(monkeypatch, 250_000)
    catalog = tmp_path / "model-config.yaml"
    catalog.write_text(CATALOG.read_text())
    code, record = _run(tool, monkeypatch, tmp_path, "--write-catalog", str(catalog), "--host-route", "bedrock")
    assert code == 0 and record["outcome"] == "clean"
    entry = yaml.safe_load(catalog.read_text())["providers"]["anthropic"]["models"]["claude-opus-5-5"]
    assert entry["probed_ceiling"] == record["measured_input_tokens"] == entry["effective_input_ceiling"]
    cal = entry["ceiling_calibration"]
    assert cal["source"] == "operator_set" and cal["calibrated_at"] == record["calibrated_at"]
    assert cal["cli_version"] == "9.9.9 (Fake Claude)" and cal["measured_input_tokens"] == record["measured_input_tokens"]
    # account_limits are the API path's (tier/itpm) — the CLI transport leaves them alone
    assert entry["account_limits"] == {"tier": "unverified", "itpm": None}
    assert not [p for p in tmp_path.iterdir() if p.name.startswith(".model-config.")]


# --- the API path is unchanged ----------------------------------------------

def test_default_transport_is_api_and_still_needs_the_key(tool, fake, monkeypatch, tmp_path, capsys):
    monkeypatch.setattr(sys, "argv", ["ceiling-probe-live.py", "--model", "claude-opus-5-5"])
    assert tool.main() == 2
    assert "ANTHROPIC_API_KEY is required" in capsys.readouterr().err
    assert fake["calls"]() == []


def test_unknown_transport_is_a_usage_error(tool, monkeypatch):
    monkeypatch.setattr(sys, "argv", ["ceiling-probe-live.py", "--model", "m", "--transport", "carrier-pigeon"])
    with pytest.raises(SystemExit) as e:
        tool.main()
    assert e.value.code == 2


def test_opus_5_5_has_its_catalog_input_price(tool):
    assert tool._PRICE_IN["claude-opus-5-5"] == 4_000_000
    cat = yaml.safe_load(CATALOG.read_text())
    assert cat["providers"]["anthropic"]["models"]["claude-opus-5-5"]["pricing"]["input_per_mtok"] == \
        tool._PRICE_IN["claude-opus-5-5"]
