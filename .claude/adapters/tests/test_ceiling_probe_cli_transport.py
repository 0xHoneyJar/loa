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
    limit = int(os.environ.get("FAKE_LIMIT_TOKENS", "1000000000"))     # in MEASURED tokens
    ratio = float(os.environ.get("FAKE_RATIO", "1.0"))                 # tokenizer: measured per filler token
    measured = int(len(data) / 4.5 * ratio) + {overhead}

    def err(msg, status=None):
        body = {{"type": "result", "is_error": True, "result": msg}}
        if status:
            body["api_error_status"] = status
        if os.environ.get("FAKE_ERR_COST"):
            body["total_cost_usd"] = float(os.environ["FAKE_ERR_COST"])
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
    BEDROCK_THROTTLE = "Too many tokens, please wait before trying again."
    if mode == "bedrock_flaky" and calls <= 1:
        err(BEDROCK_THROTTLE)
    if mode == "huge":
        sys.stdout.write("x" * (2 << 20))
        sys.exit(0)
    if measured > limit:
        if mode == "bedrock_tpm":
            err(BEDROCK_THROTTLE)
        if mode == "tpm":
            hint = os.environ.get("FAKE_RETRY_AFTER")
            err("API Error: 429 This request would exceed your organization's rate limit of 300,000 input tokens "
                "per minute" + (f" (retry-after: {{hint}})" if hint else ""))
        if os.environ.get("FAKE_ORIGIN") == "cli":
            err(f"Prompt is too long: {{measured:,}} tokens > {{limit:,}} maximum")
        if os.environ.get("FAKE_BARE"):
            err("API Error: 400 prompt is too long", status=400)
        err(f"API Error: 400 prompt is too long: {{measured}} tokens > {{limit}} maximum", status=400)
    result = "ok" if mode == "noneedle" else needle
    body = {{"type": "result", "subtype": "success", "is_error": False, "result": result, "stop_reason": "end_turn",
             "usage": {{"input_tokens": 5, "cache_creation_input_tokens": measured - 5,
                       "cache_read_input_tokens": 0, "output_tokens": 3}}}}
    if os.environ.get("FAKE_COST"):
        body["total_cost_usd"] = float(os.environ["FAKE_COST"])
    print(json.dumps(body))
''')


@pytest.fixture(autouse=True)
def _zero_live_spend(_isolate_ledgers):
    """No test in this module may reach a model through cheval: the test's OWN MODELINV ledger (conftest
    _isolate_ledgers points LOA_MODELINV_LOG_PATH at the test's tmp_path) stays unwritten. r251-3 R5: scoped per test —
    the host-global .run/model-invoke.jsonl grows under any concurrent cheval run on the host."""
    yield
    log = Path(os.environ["LOA_MODELINV_LOG_PATH"])
    assert not log.exists() or log.stat().st_size == 0, f"{log} written — a live call escaped the fake"


@pytest.fixture(scope="module", autouse=True)
def _no_real_cli(tmp_path_factory):
    """r251-1 P11 — fail-closed: this transport spawns ${CLAUDE_HEADLESS_BIN:-claude}
    directly, so a real `claude -p` would never show in cheval's MODELINV ledger
    (the per-test guard above). Every test starts with CLAUDE_HEADLESS_BIN at a path that
    does not exist; only the `fake` fixture points it at the recording fake."""
    sentinel = tmp_path_factory.mktemp("loa-probe-no-real-cli") / "claude-must-not-run"
    with pytest.MonkeyPatch.context() as mp:
        mp.setenv("CLAUDE_HEADLESS_BIN", str(sentinel))
        yield sentinel
    assert not sentinel.exists()


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
    for var in ("ANTHROPIC_API_KEY", "ANTHROPIC_DEFAULT_OPUS_MODEL", "FAKE_MODE", "FAKE_LIMIT_TOKENS",
                "FAKE_RATIO", "FAKE_BARE", "FAKE_ORIGIN", "FAKE_COST", "FAKE_ERR_COST", "FAKE_RETRY_AFTER", "AWS_REGION", "ANTHROPIC_BEDROCK_REGION_PREFIX",
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
    """The fake's provider limit, in MEASURED tokens (what the CLI's usage reports)."""
    monkeypatch.setenv("FAKE_LIMIT_TOKENS", str(tokens))


def _run(tool, monkeypatch, tmp_path, *extra, expect_calls: bool = True):
    """Run the probe in-process. r251-1 P11: a probe-running test proves the
    recording fake was called (at least once) — or, with expect_calls=False,
    that no CLI ran at all."""
    out = tmp_path / "record.json"
    argv = ["ceiling-probe-live.py", "--model", "claude-opus-5-5", "--transport", "claude-headless",
            "--min-tokens-probe", "100000", "--max-tokens-probe", "400000", "--budget-usd", "20",
            "--output", str(out), *extra]
    monkeypatch.setattr(sys, "argv", argv)
    code = tool.main()
    record = json.loads(out.read_text()) if out.exists() else None
    log = Path(os.environ.get("FAKE_LOG", "/nonexistent"))
    ran = log.exists() and log.read_text().strip() != ""
    assert ran is expect_calls, f"fake called: {ran}, expected {expect_calls} (CLAUDE_HEADLESS_BIN=" \
                                f"{os.environ.get('CLAUDE_HEADLESS_BIN')})"
    return code, record


# A two-entry catalog shaped like the pre-probe claude-opus-5-5 block: the writer
# tests must hold in a tree whose live catalog is already calibrated.
SYNTH = textwrap.dedent("""\
    providers:
      anthropic:
        models:
          claude-opus-5-5:
            context_window: 1000000
            max_output_tokens: 128000
            effective_input_ceiling: 180000   # cycle-124 FR-3 (SDD §2.1): see claude-fable-5-1
            # loa:shortcut: Opus 5's measured bound, not probed on 5.5; 180000 — rerun
            # tools/ceiling-probe-live.py --write-catalog on the operator's account.
            probed_ceiling: 180000
            ceiling_calibration:
              source: conservative_default
              calibrated_at: null
              stale_after_days: 90
            account_limits:
              tier: unverified
              itpm: null
          claude-opus-5:
            context_window: 1000000
            effective_input_ceiling: 180000
    """)

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


def test_runs_from_another_cwd_under_python_isolated_mode(fake, tmp_path, monkeypatch):
    # r251-1 P11: the same recording fake as every other test (CLAUDE_HEADLESS_BIN and
    # FAKE_LOG come from the `fake` fixture), and a PATH with no `claude` on it
    out = tmp_path / "r.json"
    empty = tmp_path / "empty-path"
    empty.mkdir()
    env = {k: v for k, v in os.environ.items() if k not in ("ANTHROPIC_API_KEY", "PYTHONPATH")}
    env.update(FAKE_LIMIT_TOKENS="250000", PATH=str(empty))
    assert env["CLAUDE_HEADLESS_BIN"] == fake["bin"]
    proc = subprocess.run([sys.executable, "-I", str(TOOL), "--model", "claude-opus-5-5", "--transport",
                           "claude-headless", "--min-tokens-probe", "100000", "--max-tokens-probe", "400000",
                           "--budget-usd", "20", "--output", str(out)],
                          cwd=str(tmp_path), env=env, capture_output=True, text=True, timeout=300)
    assert proc.returncode == 0, proc.stderr
    assert json.loads(out.read_text())["outcome"] == "clean"
    assert fake["calls"](), "the isolated-mode run did not go through the recording fake"


def test_default_binary_is_claude_on_path(tool, fake, monkeypatch, tmp_path):
    bindir = tmp_path / "bin"
    bindir.mkdir()
    _write_fake(bindir / "claude")
    monkeypatch.delenv("CLAUDE_HEADLESS_BIN", raising=False)
    monkeypatch.setenv("PATH", str(bindir))     # r251-1 P11: no real `claude` is reachable
    _limit(monkeypatch, 250_000)
    code, record = _run(tool, monkeypatch, tmp_path)
    # r251-4 T4 (n43): the record names the binary that ran, resolved on PATH
    assert code == 0 and record["cli_bin"] == str(bindir / "claude")
    assert fake["calls"]() and record["cli_version"] == "9.9.9 (Fake Claude)"


# --- classification, measurement, outcome -----------------------------------

def test_clean_bisection_measures_and_brackets_the_bound(tool, fake, monkeypatch, tmp_path, capsys):
    _limit(monkeypatch, 250_000)
    code, record = _run(tool, monkeypatch, tmp_path)
    assert code == 0
    assert record["outcome"] == "clean" and record["reasons"] == [] and record["partial"] is False
    ok, fail = record["largest_ok_input_tokens"], record["smallest_failed_input_tokens"]
    assert ok < 250_000 <= fail and fail - ok <= 16_000
    # sizes are MEASURED tokens (the CLI's usage); the filler sent is recorded beside them
    assert record["measured_input_tokens"] == ok
    best = next(s for s in record["samples"] if s["kind"] == "ok" and s["measured_input_tokens"] == ok)
    assert record["largest_ok_filler_tokens"] == best["tokens"] < ok      # the fake's 3000-token overhead
    assert all({"tokens", "target_measured", "measured_input_tokens"} <= set(s) for s in record["samples"])
    assert record["smallest_failed_basis"] == "parsed"
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
    # r251-4 T3 (n58): until a step measures, the estimate assumes the 1.8 tokenizer ratio
    # (400K filler tokens ≈ 720K measured × $5/MTok)
    assert "worst-case step ≈ $3.60" in err and "5 such steps fit in $20" in err
    assert "estimate assumes the Opus 4.7+ tokenizer ratio 1.8 until the first measured accept" in err
    assert "$4.00/MTok input × 1.25 cache-write rate = $5.00/MTok" in err and "Bedrock bills separately" in err
    assert record["estimate_rate"] == "input × 1.25 (cache-write rate)"
    # accepted steps without a CLI cost are charged at the measured size × the cache-write rate
    for s in record["samples"]:
        if s["kind"] == "ok":
            assert s["charged_usd"] == pytest.approx(s["measured_input_tokens"] * 5e-6, abs=1e-5)
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
    catalog.write_text(SYNTH)
    code, record = _run(tool, monkeypatch, tmp_path, "--write-catalog", str(catalog))
    assert code == 3
    assert record["outcome"] == "partial" and record["unverified"] is True
    assert record["largest_ok_input_tokens"] == 0, "an unverified completion is never counted as OK"
    assert any("unverified" in r for r in record["reasons"])
    assert catalog.read_text() == SYNTH


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
    # r251-1 P1: the two 529s and the third attempt's size rejection (400K > the 250K limit)
    # are provider-side rejections the CLI reported no cost for — none is billed
    assert [a["kind"] for a in top["attempt_log"]] == ["transient", "transient", "size"]
    assert [a["charge_basis"] for a in top["attempt_log"]] == ["provider_rejection_unbilled"] * 3
    assert top["charged_usd"] == 0
    ok = [s for s in record["samples"] if s["kind"] == "ok"]
    assert ok and all(s["charge_basis"] == "completion" and s["charged_usd"] > 0 for s in ok)
    assert record["spent_usd"] == pytest.approx(sum(s["charged_usd"] for s in record["samples"]), abs=1e-3)


@pytest.mark.parametrize("mode", ["throttle", "5xx"])
def test_a_transient_class_that_persists_is_other_after_three_attempts(tool, fake, monkeypatch, tmp_path, mode):
    monkeypatch.setenv("FAKE_MODE", mode)
    catalog = tmp_path / "model-config.yaml"
    catalog.write_text(SYNTH)
    code, record = _run(tool, monkeypatch, tmp_path, "--write-catalog", str(catalog))
    assert code == 1 and record["outcome"] == "partial" and record["error"]
    assert len(fake["calls"]()) == 3 and record["samples"][0]["attempts"] == 3
    assert fake["sleeps"] == [5, 15]          # the short schedule: not a token-budget 429
    assert catalog.read_text() == SYNTH


def test_a_token_budget_429_that_persists_at_a_size_is_a_size_rejection(tool, fake, monkeypatch, tmp_path):
    _limit(monkeypatch, 300_000)
    monkeypatch.setenv("FAKE_MODE", "tpm")
    code, record = _run(tool, monkeypatch, tmp_path)
    # verifier r251-1: a bound bracketed by a token-budget rejection is not a context limit — partial
    assert code == 3 and record["outcome"] == "partial"
    assert any("token_limit" in r and "context_limit" in r for r in record["reasons"])
    failed = [s for s in record["samples"] if s["kind"] == "size"]
    assert failed and all(s["failure_class"] == "token_limit" and s["attempts"] == 4 for s in failed)
    assert all(s["retry_wait_s"] >= tool._TPM_WINDOW_S for s in failed)
    assert record["largest_ok_input_tokens"] < 300_000 <= record["smallest_failed_input_tokens"]
    # r251-1 P2: each failed step waited out the tokens-per-minute window, 5 s / 15 s never could
    assert fake["sleeps"] == [20, 45, 75] * len(failed)


@pytest.mark.parametrize("mode", ["other", "garbage"])
def test_any_other_failure_exits_1_with_the_error_recorded_and_writes_nothing(tool, fake, monkeypatch, tmp_path, mode):
    monkeypatch.setenv("FAKE_MODE", mode)
    catalog = tmp_path / "model-config.yaml"
    catalog.write_text(SYNTH)
    code, record = _run(tool, monkeypatch, tmp_path, "--write-catalog", str(catalog))
    assert code == 1
    assert record["error"] and record["outcome"] == "partial"
    assert catalog.read_text() == SYNTH
    assert len(fake["calls"]()) == 1   # not retried: neither size nor transient


def test_missing_binary_is_other(tool, fake, monkeypatch, tmp_path):
    monkeypatch.setenv("CLAUDE_HEADLESS_BIN", str(tmp_path / "no-such-claude"))
    code, record = _run(tool, monkeypatch, tmp_path, expect_calls=False)
    assert code == 1 and record["error"] and record["cli_version"] is None


def test_inconsistent_classifications_are_partial(tool):
    samples = [{"tokens": 300_000, "kind": "ok"}, {"tokens": 250_000, "kind": "size"}]
    reasons = tool._outcome_reasons(samples, stop=None, largest_ok=300_000, measured=303_000,
                                    smallest_fail=250_000, hi=400_000, tol=16_000)
    assert any("inconsistent" in r for r in reasons)
    clean = [{"tokens": 240_000, "kind": "ok"}, {"tokens": 250_000, "kind": "size", "failure_class": "context_limit"}]
    assert tool._outcome_reasons(clean, stop=None, largest_ok=240_000, measured=243_000,
                                 smallest_fail=250_000, hi=400_000, tol=16_000) == []
    assert tool._outcome_reasons(clean, stop=None, largest_ok=240_000, measured=None,
                                 smallest_fail=250_000, hi=400_000, tol=16_000)


# --- budget -----------------------------------------------------------------

def test_budget_cap_stops_with_partial_and_writes_nothing(tool, fake, monkeypatch, tmp_path, capsys):
    _limit(monkeypatch, 350_000)
    catalog = tmp_path / "model-config.yaml"
    catalog.write_text(SYNTH)
    # the 400K top (est $3.60: the 1.8 prior × the cache-write rate, r251-4 T3) is rejected (free);
    # ≈251K is accepted (≈$1.26), ≈327K accepted (≈$1.64); the next mid (≈365K, est ≈$1.83) no
    # longer fits in $3.60 — the pre-check uses the estimate
    code, record = _run(tool, monkeypatch, tmp_path, "--budget-usd", "3.6", "--write-catalog", str(catalog))
    assert code == 3
    assert record["outcome"] == "partial" and any("budget" in r for r in record["reasons"])
    assert 0 < record["spent_usd"] <= 3.6
    assert catalog.read_text() == SYNTH, "a partial CLI-transport record is never written"
    assert (tmp_path / "record.json").exists()


def test_budget_below_the_first_call_makes_no_call(tool, fake, monkeypatch, tmp_path):
    code, record = _run(tool, monkeypatch, tmp_path, "--budget-usd", "0.5", expect_calls=False)
    assert code == 3 and record["partial"] is True and record["sample_size"] == 0
    assert fake["calls"]() == []


def test_spend_is_the_larger_of_the_cli_cost_and_the_catalog_estimate(tool, fake, monkeypatch, tmp_path):
    _limit(monkeypatch, 250_000)
    monkeypatch.setenv("FAKE_COST", "9.0")          # an implausibly high CLI-reported cost wins
    code, record = _run(tool, monkeypatch, tmp_path, "--budget-usd", "40")
    ok_steps = [s for s in record["samples"] if s["kind"] == "ok"]
    assert ok_steps and all(s["charged_usd"] >= 9.0 for s in ok_steps)
    assert all(s["charge_basis"] == "completion" for s in ok_steps)


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


def test_output_past_the_1mb_cap_raises_and_kills_the_group(tool):
    # verifier r251-1 (P7): the probe runs through loa_cheval's run_subprocess_pgkill, which
    # raises past its byte cap instead of truncating — a truncated answer never classifies
    tool._adapters()                       # the tool's own import seam (verifier n46)
    from loa_cheval.providers.base import SubprocessOutputCapExceeded
    with pytest.raises(SubprocessOutputCapExceeded):
        tool._run_capped([sys.executable, "-c", "import sys; sys.stdout.write('x' * 3000000)"], "", 60)
    rc, out, err = tool._run_capped([sys.executable, "-c", "import sys; sys.stdout.write('x' * 1000)"], "", 60)
    assert rc == 0 and len(out) == 1000


def test_an_oversized_cli_answer_is_other(tool, fake, monkeypatch, tmp_path):
    monkeypatch.setenv("FAKE_MODE", "huge")
    code, record = _run(tool, monkeypatch, tmp_path)
    assert code == 1 and record["samples"][0]["kind"] == "other"
    assert "1 MB" in record["samples"][0]["detail"] and record["samples"][0]["attempts"] == 1


# --- the operator_set write -------------------------------------------------

def _w(tool, text, ceiling, **kw):
    args = dict(calibrated_at="2026-10-07T12:00:00Z", cli_model="global.anthropic.claude-opus-5-5",
                host_route="bedrock (claude-bedrock)", cli_version="2.1.292 (Claude Code)",
                probe_outcome="clean", sample_size=5)
    args.update(kw)
    return tool.write_catalog_operator_set(text, "claude-opus-5-5", ceiling=ceiling, **args)


def test_write_operator_set_changes_only_the_entry_and_replaces_the_shortcut(tool):
    # r251-1 P9: on the synthetic pre-probe catalog — the live entry is calibrated, and a
    # skip here would leave the shortcut-replacement path untested
    before = SYNTH
    assert "# loa:shortcut: Opus 5's measured bound, not probed on 5.5" in before
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
    assert cal["sample_size"] == 5 and cal["probe_outcome"] == "clean" and cal["stale_after_days"] == 90
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
    assert a.get("aliases") == b.get("aliases")
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
    after = _w(tool, SYNTH, 120_000)
    entry = yaml.safe_load(after)["providers"]["anthropic"]["models"]["claude-opus-5-5"]
    assert entry["probed_ceiling"] == entry["effective_input_ceiling"] == 120_000
    assert entry["ceiling_calibration"]["measured_input_tokens"] == 120_000


def test_write_operator_set_keeps_stale_after_days_is_idempotent_and_refuses_bad_input(tool):
    text = SYNTH.replace("stale_after_days: 90", "stale_after_days: 45", 1)
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
                                        cli_model="x", host_route="y", probe_outcome="clean", sample_size=1)


def test_cli_write_catalog_end_to_end_on_a_temp_copy(tool, fake, monkeypatch, tmp_path):
    _limit(monkeypatch, 250_000)
    catalog = tmp_path / "model-config.yaml"
    catalog.write_text(SYNTH)
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


# --- cycle-127 fr23b: the I2 clamp and measured-token bisection ------------

def test_the_write_clamps_to_the_i2_invariant_and_keeps_the_raw_measurement(tool):
    """The live probe accepted 972,887 measured tokens; written raw, effective +
    the 64K default output would exceed the 1M window (I2). The written bound is
    min(measured, context_window − default_max_tokens(entry)); the raw accept is
    kept in ceiling_calibration.measured_input_tokens and the comment says so."""
    after = _w(tool, SYNTH, 972_887)
    entry = yaml.safe_load(after)["providers"]["anthropic"]["models"]["claude-opus-5-5"]
    sys.path.insert(0, str(ROOT / ".claude" / "adapters"))
    from loa_cheval.providers.base import default_max_tokens
    default_out = default_max_tokens(provider="anthropic", model_max_output=entry["max_output_tokens"])
    assert default_out == 64_000
    assert entry["probed_ceiling"] == entry["effective_input_ceiling"] == 1_000_000 - 64_000
    assert entry["effective_input_ceiling"] + default_out <= entry["context_window"]
    assert entry["ceiling_calibration"]["measured_input_tokens"] == 972_887
    prov = [l for l in after.splitlines() if "cycle-127 FR-3: bound measured" in l]
    assert len(prov) == 1 and "clamped to 936000" in prov[0] and "972887" in prov[0]
    from loa_cheval.routing.ceiling import input_bound
    d = input_bound(entry, max_tokens=default_out)
    assert d.basis == "calibrated" and d.value == 936_000


def test_the_clamp_ignores_the_operator_streaming_switches(tool, monkeypatch):
    """The catalog invariant is checked against the streaming default; an
    operator running the probe with streaming disabled must not loosen it."""
    monkeypatch.setenv("LOA_CHEVAL_DISABLE_STREAMING", "1")
    monkeypatch.setenv("LOA_CHEVAL_LEGACY_WIRE", "1")
    entry = yaml.safe_load(_w(tool, SYNTH, 972_887))["providers"]["anthropic"]["models"]["claude-opus-5-5"]
    assert entry["effective_input_ceiling"] == 936_000
    assert os.environ["LOA_CHEVAL_DISABLE_STREAMING"] == "1" and os.environ["LOA_CHEVAL_LEGACY_WIRE"] == "1"


def test_a_measurement_under_the_clamp_is_written_unclamped_and_says_so(tool):
    after = _w(tool, SYNTH, 640_000)
    entry = yaml.safe_load(after)["providers"]["anthropic"]["models"]["claude-opus-5-5"]
    assert entry["effective_input_ceiling"] == entry["ceiling_calibration"]["measured_input_tokens"] == 640_000
    assert "clamped" not in next(l for l in after.splitlines() if "cycle-127 FR-3: bound measured" in l)


def test_an_entry_without_max_output_tokens_clamps_with_the_4096_default(tool):
    text = SYNTH.replace("        max_output_tokens: 128000\n", "", 1)
    entry = yaml.safe_load(_w(tool, text, 999_000))["providers"]["anthropic"]["models"]["claude-opus-5-5"]
    assert entry["effective_input_ceiling"] == 1_000_000 - 4096


def test_an_entry_without_context_window_is_refused(tool):
    with pytest.raises(ValueError, match="context_window"):
        _w(tool, SYNTH.replace("        context_window: 1000000\n", "", 1), 500_000)


def test_clean_end_to_end_write_above_the_clamp(tool, fake, monkeypatch, tmp_path):
    _limit(monkeypatch, 990_000)
    catalog = tmp_path / "model-config.yaml"
    catalog.write_text(SYNTH)
    code, record = _run(tool, monkeypatch, tmp_path, "--max-tokens-probe", "1000000", "--budget-usd", "100",
                        "--write-catalog", str(catalog))
    assert code == 0 and record["outcome"] == "clean", record["reasons"]
    assert record["measured_input_tokens"] > 936_000
    entry = yaml.safe_load(catalog.read_text())["providers"]["anthropic"]["models"]["claude-opus-5-5"]
    assert entry["effective_input_ceiling"] == entry["probed_ceiling"] == 936_000
    assert entry["ceiling_calibration"]["measured_input_tokens"] == record["measured_input_tokens"]
    assert record["written_ceiling"] == 936_000


def test_bisection_rescales_the_filler_to_measured_tokens(tool, fake, monkeypatch, tmp_path):
    """The Opus 4.7+ tokenizer counts the filler ≈1.8× heavier than the probe
    assumes: once a step has a measured size, later steps scale the filler by
    measured/requested so each lands on its measured target."""
    monkeypatch.setenv("FAKE_RATIO", "1.8")
    _limit(monkeypatch, 700_000)
    code, record = _run(tool, monkeypatch, tmp_path, "--max-tokens-probe", "1000000", "--budget-usd", "100")
    assert code == 0 and record["outcome"] == "clean", record["reasons"]
    ok, fail = record["measured_input_tokens"], record["smallest_failed_input_tokens"]
    assert ok <= 700_000 < fail and fail - ok <= 16_000          # the tolerance is in measured tokens
    samples = record["samples"]
    first_measured = next(i for i, s in enumerate(samples) if s.get("measured_input_tokens"))
    for s in samples[first_measured + 1:]:
        got = s["size_measured"] if s["size_basis"] in ("usage", "parsed") else None   # usage, or the count a rejection states
        assert got is not None and abs(got - s["target_measured"]) / s["target_measured"] < 0.02, s
    assert samples[0]["tokens"] == 1_000_000 and samples[0]["target_measured"] == 1_000_000
    # the filler actually sent shrank by ≈1/1.8 against the measured target
    later = samples[-1]
    assert later["tokens"] == pytest.approx(later["target_measured"] / 1.8, rel=0.03)
    assert record["tokenizer_ratio"] == pytest.approx(1.8, rel=0.02)
    assert len(samples) <= 10


def test_max_tokens_probe_is_measured_the_top_is_reanchored_after_an_overshoot(tool, fake, monkeypatch, tmp_path):
    """No limit below the top: the first step (ratio unknown) overshoots to
    ≈1.8× the top; the probe re-anchors the top in measured tokens before it
    concludes there is no rejection, and never reports an accept above it as the bound."""
    monkeypatch.setenv("FAKE_RATIO", "1.8")
    _limit(monkeypatch, 1_200_000)
    code, record = _run(tool, monkeypatch, tmp_path, "--max-tokens-probe", "1000000", "--budget-usd", "100")
    reanchor = [s for s in record["samples"] if s["target_measured"] == 1_000_000]
    assert len(reanchor) == 2 and reanchor[1]["tokens"] < reanchor[0]["tokens"]
    assert reanchor[1]["kind"] == "ok" and abs(reanchor[1]["measured_input_tokens"] - 1_000_000) < 20_000
    assert code == 3 and any("not bracketed" in r for r in record["reasons"])


def test_an_unparsed_rejection_is_scaled_by_the_measured_ratio(tool, fake, monkeypatch, tmp_path):
    monkeypatch.setenv("FAKE_RATIO", "1.8")
    monkeypatch.setenv("FAKE_BARE", "1")      # rejections carry no token count
    _limit(monkeypatch, 700_000)
    code, record = _run(tool, monkeypatch, tmp_path, "--max-tokens-probe", "1000000", "--budget-usd", "100")
    assert record["smallest_failed_basis"] == "scaled"
    assert record["measured_input_tokens"] <= 700_000 < record["smallest_failed_input_tokens"] * 1.02
    assert code in (0, 3)


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


# --- r251-1 (cross-model review of 8ad37c55) --------------------------------

def test_p1_a_cli_local_rejection_is_never_charged(tool, fake, monkeypatch, tmp_path):
    _limit(monkeypatch, 250_000)
    monkeypatch.setenv("FAKE_ORIGIN", "cli")
    code, record = _run(tool, monkeypatch, tmp_path)
    assert code == 0
    rejected = [s for s in record["samples"] if s["kind"] == "size"]
    assert rejected and all(s["charged_usd"] == 0 and s["charge_basis"] == "cli_local_rejection" for s in rejected)
    ok = [s for s in record["samples"] if s["kind"] == "ok"]
    assert record["spent_usd"] == pytest.approx(sum(s["charged_usd"] for s in ok), abs=1e-4)


def test_p1_a_cli_local_rejection_alone_spends_nothing(tool, fake, monkeypatch, tmp_path):
    _limit(monkeypatch, 1)                       # every size rejected, by the CLI's own pre-flight
    monkeypatch.setenv("FAKE_ORIGIN", "cli")
    code, record = _run(tool, monkeypatch, tmp_path)
    assert record["samples"] and record["spent_usd"] == 0


def test_p1_a_provider_rejection_is_free_unless_the_cli_reports_a_cost(tool, fake, monkeypatch, tmp_path):
    _limit(monkeypatch, 250_000)
    code, record = _run(tool, monkeypatch, tmp_path)
    rejected = [s for s in record["samples"] if s["kind"] == "size"]
    assert rejected and all(s["size_origin"] == "provider" for s in rejected)
    assert all(s["charged_usd"] == 0 and s["charge_basis"] == "provider_rejection_unbilled" for s in rejected)
    monkeypatch.setenv("FAKE_ERR_COST", "0.25")
    code, record = _run(tool, monkeypatch, tmp_path)
    rejected = [s for s in record["samples"] if s["kind"] == "size"]
    assert all(s["charged_usd"] == 0.25 and s["charge_basis"] == "cli_reported" for s in rejected)
    assert record["spent_usd"] == pytest.approx(sum(s["charged_usd"] for s in record["samples"]), abs=1e-4)


def test_p1_the_budget_precheck_still_uses_the_estimate(tool, fake, monkeypatch, tmp_path):
    """A free rejection does not make the next attempt free in advance: the cap
    is checked against the estimate before any attempt."""
    _limit(monkeypatch, 1)
    monkeypatch.setenv("FAKE_ORIGIN", "cli")
    code, record = _run(tool, monkeypatch, tmp_path, "--budget-usd", "1.0", expect_calls=False)
    # 400K filler ≈ 720K measured (the 1.8 prior, r251-4 T3) ≈ $3.60 estimated > $1.00: never
    # attempted although it would have cost nothing
    assert code == 3 and record["sample_size"] == 0 and fake["calls"]() == []
    # the estimate is the cache-write rate: $3.00 would have fit at the plain input price ($2.88)
    code, record = _run(tool, monkeypatch, tmp_path, "--budget-usd", "3.0", expect_calls=False)
    assert code == 3 and record["sample_size"] == 0
    # and the 1.8 prior: $2.50 would have fit at the filler count ($2.00)
    code, record = _run(tool, monkeypatch, tmp_path, "--budget-usd", "2.5", expect_calls=False)
    assert code == 3 and record["sample_size"] == 0


def test_p2_a_retry_after_hint_is_honoured_and_the_total_wait_capped(tool, fake, monkeypatch, tmp_path):
    _limit(monkeypatch, 300_000)
    monkeypatch.setenv("FAKE_MODE", "tpm")
    monkeypatch.setenv("FAKE_RETRY_AFTER", "100")
    code, record = _run(tool, monkeypatch, tmp_path)
    failed = [s for s in record["samples"] if s["kind"] == "size"]
    assert failed
    for s in failed:
        assert s["retry_wait_s"] <= tool._RETRY_WAIT_CAP_S
    # the hint (100 s) beats the 20 s schedule; the cap (180 s) truncates the second wait
    assert fake["sleeps"][:2] == [100, 80]


def test_p2_the_short_backoff_is_kept_for_5xx(tool, fake, monkeypatch, tmp_path):
    _limit(monkeypatch, 250_000)
    monkeypatch.setenv("FAKE_MODE", "flaky")
    _run(tool, monkeypatch, tmp_path)
    assert fake["sleeps"] == [5, 15]


def test_p3_a_token_limit_that_persists_without_the_window_cleared_is_other(tool, fake, monkeypatch, tmp_path):
    _limit(monkeypatch, 300_000)
    monkeypatch.setenv("FAKE_MODE", "tpm")
    monkeypatch.setattr(tool, "_RETRY_WAIT_CAP_S", 30)       # the window (60 s) can never be waited out
    code, record = _run(tool, monkeypatch, tmp_path)
    assert code == 1 and record["samples"][0]["kind"] == "other"
    assert "window" in record["samples"][0]["detail"]


def test_p3_classification_unit(tool):
    s = tool._persisted_transient({"kind": "transient", "token_limit": True, "detail": "429 tpm"},
                                  attempt_kinds=["token_limit"] * 4, waited=140.0)
    assert s["kind"] == "size" and s["failure_class"] == "token_limit" and s["size_origin"] == "provider"
    s = tool._persisted_transient({"kind": "transient", "token_limit": True, "detail": "429 tpm"},
                                  attempt_kinds=["transient", "token_limit", "token_limit"], waited=140.0)
    assert s["kind"] == "other"                                # not every attempt was the token-limit class
    s = tool._persisted_transient({"kind": "transient", "detail": "503"}, attempt_kinds=["transient"] * 3, waited=20)
    assert s["kind"] == "other" and "persisted" in s["detail"]


def test_p4_classification_reads_the_full_diagnostic(tool):
    stderr = "x" * 400 + " Prompt is too long: 500,000 tokens > 400,000 maximum"
    res = tool._classify(1, "", stderr, "abcdefabcdef")
    assert res["kind"] == "size" and res["rejected_input_tokens"] == 500_000
    assert len(res["detail"]) <= 300                       # truncated for the record only
    tpm = "y" * 400 + " API Error: 429 rate limit of 300,000 input tokens per minute"
    res = tool._classify(1, json.dumps({"type": "result", "is_error": True, "result": tpm}), "", "abcdefabcdef")
    assert res["kind"] == "transient" and res["token_limit"] is True


def test_p4_the_full_text_is_capped_at_the_capture_size(tool):
    huge = "z" * (3 << 20) + " Prompt is too long"
    # beyond the 1 MB capture the marker is never seen — the classifier never reads more than was captured
    res = tool._classify(1, "", huge, "abcdefabcdef")
    assert res["kind"] != "size"


def test_p5_a_classifier_exception_is_other_and_the_record_survives(tool, fake, monkeypatch, tmp_path):
    _limit(monkeypatch, 250_000)
    _, ceiling, _ = tool._adapters()

    def boom(_msg):
        raise RuntimeError("parse exploded")
    monkeypatch.setattr(ceiling, "parse_context_limit", boom)
    code, record = _run(tool, monkeypatch, tmp_path)
    assert code == 1 and record is not None and record["outcome"] == "partial"
    bad = [s for s in record["samples"] if s["kind"] == "other"]
    assert bad and "parse exploded" in bad[0]["detail"] and "RuntimeError" in bad[0]["detail"]
    assert "parse exploded" in record["error"]


@pytest.mark.parametrize("mutate,why", [
    (lambda t: t.replace("      claude-opus-5-5:\n", "      claude-opus-5-4:\n", 1), "no `      claude-opus-5-5:` block"),
    (lambda t: t.replace("        context_window: 1000000\n", "", 1), "context_window"),
    (lambda t: t.replace("        context_window: 1000000\n", "        context_window: 0\n", 1), "context_window"),
    (lambda t: t.replace("        probed_ceiling: 180000\n", "", 1), "probed_ceiling"),
])
def test_p6_write_prerequisites_fail_fast_with_no_spend(tool, fake, monkeypatch, tmp_path, capsys, mutate, why):
    _limit(monkeypatch, 250_000)
    catalog = tmp_path / "model-config.yaml"
    bad = mutate(SYNTH)
    catalog.write_text(bad)
    code, record = _run(tool, monkeypatch, tmp_path, "--write-catalog", str(catalog), expect_calls=False)
    assert code == 2 and record is None
    # no model call; `--version` (no spend) now runs first so the dry run sees the real
    # cli_version (r251-4 T1) — the fake does not log it
    assert fake["calls"]() == []
    assert why in capsys.readouterr().err
    assert catalog.read_text() == bad


def test_p6_a_missing_catalog_file_fails_fast(tool, fake, monkeypatch, tmp_path):
    code, record = _run(tool, monkeypatch, tmp_path, "--write-catalog", str(tmp_path / "nope.yaml"), expect_calls=False)
    assert code == 2 and fake["calls"]() == []


GRANDCHILD = textwrap.dedent("""\
    import os, subprocess, sys, time
    child = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(300)"])
    open(sys.argv[1], "w").write(f"{os.getpid()} {child.pid}")
    time.sleep(300)
    """)


def _alive(pid: int) -> bool:
    try:
        with open(f"/proc/{pid}/stat") as fh:
            return fh.read().split(")")[-1].split()[0] != "Z"
    except FileNotFoundError:
        return False


def _cmdline_has(pid: int, marker: str) -> bool:
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as fh:
            return marker in fh.read().replace(b"\0", b" ").decode(errors="replace")
    except OSError:
        return False


@pytest.mark.skipif(not os.path.isdir("/proc"), reason="needs /proc to observe the grandchild")
def test_p7_a_timeout_kills_the_whole_process_group(tool, tmp_path):
    import time
    script = tmp_path / "wrapper.py"
    script.write_text(GRANDCHILD)
    pidfile = tmp_path / "gc.pid"
    # verifier n49: a 5 s cap leaves the wrapper ample time to write the pidfile, and a
    # missing pidfile fails with a message rather than a FileNotFoundError
    with pytest.raises(subprocess.TimeoutExpired):
        tool._run_capped([sys.executable, str(script), str(pidfile)], "prompt on stdin", 5)
    deadline = time.time() + 10
    while not pidfile.exists() and time.time() < deadline:
        time.sleep(0.05)
    assert pidfile.exists(), "the wrapper never wrote its pidfile within the 5 s cap — the test proved nothing"
    wrapper, gc = (int(x) for x in pidfile.read_text().split())
    while (_alive(gc) or _alive(wrapper)) and time.time() < deadline:
        time.sleep(0.1)
    survivors = [p for p in (wrapper, gc) if _alive(p)]
    # r251-4 T7 (n46): kill only a PID whose cmdline is still ours (a reused PID is left alone)
    for p, marker in ((wrapper, str(script)), (gc, "time.sleep(300)")):
        if p in survivors and _cmdline_has(p, marker):
            os.kill(p, 9)
    assert not survivors, f"the timeout left {survivors} alive (wrapper {wrapper}, grandchild {gc})"


def test_p7_stdin_is_delivered_and_the_child_leads_its_own_group(tool):
    rc, out, err = tool._run_capped([sys.executable, "-c",
                                     "import os, sys; d = sys.stdin.read(); "
                                     "print(len(d), os.getpgid(0) == os.getpid())"], "x" * 3_000_000, 60)
    assert rc == 0 and out.split() == ["3000000", "True"]


@pytest.mark.parametrize("text,transient", [
    ("Request took 503 ms and then failed: something odd", False),
    ("retrying 3 of 500 items", False),
    ("API Error: 503", True),
    ("HTTP 502 from upstream", True),
    ("status 504", True),
])
def test_p8_the_5xx_heuristic_needs_a_status_context(tool, text, transient):
    res = tool._classify(1, json.dumps({"type": "result", "is_error": True, "result": text}), "", "abcdefabcdef")
    assert (res["kind"] == "transient") is transient, res


def test_p8_api_status_field_counts(tool):
    body = {"type": "result", "is_error": True, "result": "upstream trouble", "api_error_status": 503}
    assert tool._classify(1, json.dumps(body), "", "abcdefabcdef")["kind"] == "transient"


@pytest.mark.parametrize("flags", [["--allow-partial"], ["--tier", "3"], ["--itpm", "100000"]])
def test_p9_api_only_flags_are_a_usage_error_on_the_headless_transport(tool, fake, monkeypatch, tmp_path, capsys, flags):
    catalog = tmp_path / "model-config.yaml"
    catalog.write_text(SYNTH)
    code, record = _run(tool, monkeypatch, tmp_path, "--write-catalog", str(catalog), *flags, expect_calls=False)
    assert code == 2 and record is None and catalog.read_text() == SYNTH
    assert f"{flags[0]} is an api-transport flag" in capsys.readouterr().err


def test_p9_the_headless_only_flag_is_a_usage_error_on_the_api_transport(tool, fake, monkeypatch, capsys):
    monkeypatch.setenv("ANTHROPIC_API_KEY", "sk-never-used")
    monkeypatch.setattr(sys, "argv", ["ceiling-probe-live.py", "--model", "claude-opus-5-5", "--write-catalog",
                                      "/nonexistent", "--write-partial-as-operator-set"])
    assert tool.main() == 2
    assert "--write-partial-as-operator-set applies to --transport claude-headless only" in capsys.readouterr().err


def test_p10_the_docstring_describes_the_i2_clamp(tool):
    doc = tool.__doc__
    assert "raw — the api transport applies no safety margin either" not in doc
    assert "min(measured, context_window − default_max_tokens)" in doc
    assert "size_unit" in doc and "written_ceiling" in doc


# --- r251-1 P11: the zero-spend guard is fail-closed for this transport -----

def test_p11_the_module_default_binary_is_a_sentinel_that_does_not_exist():
    """Without the `fake` fixture, CLAUDE_HEADLESS_BIN points at a path under a
    tmp dir that does not exist: a probe test that forgets the fake fails on
    spawn instead of reaching a real `claude -p`."""
    sentinel = os.environ.get("CLAUDE_HEADLESS_BIN", "")
    assert sentinel and "loa-probe-no-real-cli" in sentinel and not os.path.exists(sentinel)


def test_p11_a_probe_without_the_fake_fails_on_spawn(tool, monkeypatch, tmp_path):
    out = tmp_path / "r.json"
    monkeypatch.setattr(sys, "argv", ["ceiling-probe-live.py", "--model", "claude-opus-5-5", "--transport",
                                      "claude-headless", "--min-tokens-probe", "100000", "--max-tokens-probe",
                                      "400000", "--budget-usd", "20", "--output", str(out)])
    assert tool.main() == 1
    record = json.loads(out.read_text())
    assert "loa-probe-no-real-cli" in record["error"] and record["samples"][0]["charge_basis"] == "not_sent"


# --- r251-1 P12: probe_outcome / sample_size provenance --------------------

def _validate_cal(cal):
    import jsonschema
    schema = json.loads(SCHEMA_V3.read_text())
    jsonschema.validate(cal, {**schema["$defs"]["ceilingCalibration"], "$defs": schema["$defs"]})


def test_p12_a_clean_write_carries_probe_outcome_and_the_sample_count(tool):
    after = _w(tool, SYNTH, 640_000, sample_size=7)
    cal = yaml.safe_load(after)["providers"]["anthropic"]["models"]["claude-opus-5-5"]["ceiling_calibration"]
    assert cal["probe_outcome"] == "clean" and cal["sample_size"] == 7
    _validate_cal(cal)


def test_p12_a_partial_record_is_refused_without_force(tool):
    with pytest.raises(ValueError, match="partial"):
        _w(tool, SYNTH, 640_000, probe_outcome="partial")
    for bad in ("maybe", None, ""):
        with pytest.raises(ValueError):
            _w(tool, SYNTH, 640_000, probe_outcome=bad)
    for bad in (-1, True, "5", None):
        with pytest.raises(ValueError):
            _w(tool, SYNTH, 640_000, sample_size=bad)


def test_p12_a_forced_partial_write_says_partial(tool):
    after = _w(tool, SYNTH, 972_887, probe_outcome="partial", sample_size=5, force_partial=True)
    entry = yaml.safe_load(after)["providers"]["anthropic"]["models"]["claude-opus-5-5"]
    cal = entry["ceiling_calibration"]
    assert cal["probe_outcome"] == "partial" and cal["sample_size"] == 5
    assert cal["measured_input_tokens"] == 972_887 and entry["effective_input_ceiling"] == 936_000
    assert "partial" in next(l for l in after.splitlines() if "cycle-127 FR-3: bound measured" in l)
    _validate_cal(cal)
    # forcing a clean record is a no-op flag
    assert _w(tool, SYNTH, 640_000, force_partial=True) == _w(tool, SYNTH, 640_000)


def test_p12_the_schema_probe_outcome_is_optional_and_closed(tool):
    import jsonschema
    base = {"source": "operator_set", "calibrated_at": "2026-10-07T00:00:00Z", "sample_size": 5,
            "stale_after_days": 90}
    _validate_cal(base)                                          # optional: absent is valid
    _validate_cal({**base, "probe_outcome": "partial"})
    with pytest.raises(jsonschema.ValidationError):
        _validate_cal({**base, "probe_outcome": "maybe"})
    schema = json.loads(SCHEMA_V3.read_text())
    cc = schema["$defs"]["ceilingCalibration"]
    assert "probe_outcome" not in cc.get("required", [])     # required only under probed_headless (r251-4 T5)
    assert "number of probe samples taken (accepted + rejected)" in cc["properties"]["sample_size"]["description"]


def test_p12_the_clean_cli_path_writes_probe_outcome_clean(tool, fake, monkeypatch, tmp_path):
    _limit(monkeypatch, 250_000)
    catalog = tmp_path / "model-config.yaml"
    catalog.write_text(SYNTH)
    code, record = _run(tool, monkeypatch, tmp_path, "--write-catalog", str(catalog))
    assert code == 0 and record["outcome"] == "clean"
    cal = yaml.safe_load(catalog.read_text())["providers"]["anthropic"]["models"]["claude-opus-5-5"]["ceiling_calibration"]
    assert cal["probe_outcome"] == "clean" and cal["sample_size"] == record["sample_size"] == len(record["samples"])
    _validate_cal(cal)


def test_p12_write_partial_as_operator_set_writes_a_budget_capped_record(tool, fake, monkeypatch, tmp_path, capsys):
    _limit(monkeypatch, 350_000)
    catalog = tmp_path / "model-config.yaml"
    catalog.write_text(SYNTH)
    # $3.60 fits the first step's 1.8-prior estimate and two accepts, then caps (r251-4 T3)
    code, record = _run(tool, monkeypatch, tmp_path, "--budget-usd", "3.6", "--write-catalog", str(catalog),
                        "--write-partial-as-operator-set")
    assert code == 3 and record["outcome"] == "partial"     # the exit code still reports the partial probe
    entry = yaml.safe_load(catalog.read_text())["providers"]["anthropic"]["models"]["claude-opus-5-5"]
    cal = entry["ceiling_calibration"]
    assert cal["probe_outcome"] == "partial" and cal["sample_size"] == record["sample_size"]
    assert cal["measured_input_tokens"] == record["measured_input_tokens"] == entry["effective_input_ceiling"]
    assert record["written_ceiling"] == entry["effective_input_ceiling"]
    _validate_cal(cal)
    assert "operator vouches" in capsys.readouterr().err


def test_p12_write_partial_needs_a_verified_accept(tool, fake, monkeypatch, tmp_path):
    monkeypatch.setenv("FAKE_MODE", "noneedle")
    catalog = tmp_path / "model-config.yaml"
    catalog.write_text(SYNTH)
    code, record = _run(tool, monkeypatch, tmp_path, "--write-catalog", str(catalog), "--write-partial-as-operator-set")
    assert code == 3 and catalog.read_text() == SYNTH and "no verified accept" in record["error"]


def test_p12_write_partial_without_write_catalog_is_a_usage_error(tool, fake, monkeypatch, tmp_path):
    code, record = _run(tool, monkeypatch, tmp_path, "--write-partial-as-operator-set", expect_calls=False)
    assert code == 2 and record is None


# --- verifier additions (r251-1) -------------------------------------------

BEDROCK_THROTTLE = "Too many tokens, please wait before trying again."


@pytest.mark.parametrize("text", [
    BEDROCK_THROTTLE,
    "ThrottlingException: Too many tokens, please wait before trying again.",
    "API Error: 429 prompt is too long for your rate limit",
    "too many tokens per minute",
])
def test_a_throttle_marker_beats_a_context_marker(tool, text):
    res = tool._classify(1, json.dumps({"type": "result", "is_error": True, "result": text}), "", "abcdefabcdef")
    assert res["kind"] == "transient" and res.get("token_limit") is True, res


def test_a_token_count_of_429_thousand_is_not_a_429(tool):
    msg = "Prompt is too long: 429,000 tokens > 400,000 maximum"
    res = tool._classify(1, json.dumps({"type": "result", "is_error": True, "result": msg}), "", "abcdefabcdef")
    assert res["kind"] == "size" and res["rejected_input_tokens"] == 429_000


def test_bedrock_throttle_is_retried_on_the_tpm_schedule(tool, fake, monkeypatch, tmp_path):
    _limit(monkeypatch, 250_000)
    monkeypatch.setenv("FAKE_MODE", "bedrock_flaky")      # the first call answers Bedrock's throttle
    code, record = _run(tool, monkeypatch, tmp_path)
    assert code == 0 and record["outcome"] == "clean", record["reasons"]
    top = record["samples"][0]
    assert top["attempts"] == 2 and top["attempt_log"][0]["kind"] == "token_limit"
    assert top["failure_class"] == "context_limit"          # the real bracket, after the retry
    assert fake["sleeps"] == [20]


def test_a_persisting_bedrock_throttle_never_writes_a_clean_bound(tool, fake, monkeypatch, tmp_path):
    _limit(monkeypatch, 250_000)
    monkeypatch.setenv("FAKE_MODE", "bedrock_tpm")
    catalog = tmp_path / "model-config.yaml"
    catalog.write_text(SYNTH)
    code, record = _run(tool, monkeypatch, tmp_path, "--write-catalog", str(catalog))
    assert code == 3 and record["outcome"] == "partial"
    assert any("token_limit" in r for r in record["reasons"])
    assert all(s["failure_class"] == "token_limit" and s["attempts"] == 4
               for s in record["samples"] if s["kind"] == "size")
    assert catalog.read_text() == SYNTH


def test_outcome_reasons_flag_a_non_context_bracket(tool):
    samples = [{"tokens": 240_000, "kind": "ok"}, {"tokens": 250_000, "kind": "size", "failure_class": "token_limit"}]
    reasons = tool._outcome_reasons(samples, stop=None, largest_ok=240_000, measured=243_000,
                                    smallest_fail=250_000, hi=400_000, tol=16_000)
    assert any("token_limit" in r for r in reasons)


@pytest.mark.parametrize("exc,code", [(KeyboardInterrupt, 130), (RuntimeError, 1)])
def test_an_interrupt_after_paid_steps_still_writes_the_record(tool, fake, monkeypatch, tmp_path, capsys, exc, code):
    _limit(monkeypatch, 250_000)
    real = tool._run_capped
    n = {"calls": 0}

    def flaky(*a, **kw):
        n["calls"] += 1
        if n["calls"] == 2:
            raise exc("operator pressed ^C" if exc is KeyboardInterrupt else "unexpected boom")
        return real(*a, **kw)
    monkeypatch.setattr(tool, "_run_capped", flaky)
    got, record = _run(tool, monkeypatch, tmp_path)
    assert got == code and record is not None
    assert record["outcome"] == "partial" and record["stop"] == "interrupted"
    assert exc.__name__ in record["interrupted"] and exc.__name__ in " ".join(record["reasons"])
    first, second = record["samples"][:2]
    assert first["kind"] in ("ok", "size") and second["kind"] == "interrupted"
    assert second["charge_basis"] == "interrupted_estimate" and second["charged_usd"] > 0
    assert record["spent_usd"] == pytest.approx(sum(s["charged_usd"] for s in record["samples"]), abs=1e-4)
    # r251-2 Q5 (verifier n62): a defect keeps its traceback on stderr; ^C stays quiet
    err = capsys.readouterr().err
    if exc is KeyboardInterrupt:
        assert "Traceback" not in err
    else:
        assert "Traceback" in err and "unexpected boom" in err and "flaky" in err


# --- review dissent run 2 (r251-2) -----------------------------------------

def _cls(tool, result, stderr=""):
    return tool._classify(1, json.dumps({"type": "result", "is_error": True, "result": result}), stderr,
                          "abcdefabcdef")


@pytest.mark.parametrize("text", ["API Error: 429. Too many tokens", "API Error: 429, too many tokens",
                                  "API Error: 429 Too many tokens"])
def test_q1_a_429_followed_by_punctuation_is_a_throttle(tool, text):
    res = _cls(tool, text)
    assert res["kind"] == "transient" and res.get("token_limit") is True, res


@pytest.mark.parametrize("text", ["Prompt is too long: 429,000 tokens > 400,000 maximum",
                                  "Prompt is too long: 1,429.5k tokens > 1,000,000 maximum"])
def test_q1_a_429_inside_a_number_is_still_not_a_status(tool, text):
    assert _cls(tool, text)["kind"] == "size"


def test_q1_a_stale_stderr_throttle_does_not_turn_a_context_result_transient(tool):
    res = _cls(tool, "Prompt is too long: 1,065,182 tokens > 1,000,000 maximum",
               stderr="warning: earlier rate limit hit, please wait before retrying")
    assert res["kind"] == "size" and res["failure_class"] == "context_limit", res
    assert res["rejected_input_tokens"] == 1_065_182


def test_q1_stderr_decides_the_throttle_when_the_result_is_empty(tool):
    res = tool._classify(1, "", "Too many tokens, please wait before trying again.", "abcdefabcdef")
    assert res["kind"] == "transient" and res.get("token_limit") is True, res


@pytest.mark.skipif(hasattr(os, "geteuid") and os.geteuid() == 0, reason="root ignores the permission bits")
@pytest.mark.parametrize("lock", ["dir", "file"])
def test_q2_an_unwritable_catalog_fails_before_any_spend(tool, fake, monkeypatch, tmp_path, capsys, lock):
    _limit(monkeypatch, 250_000)
    d = tmp_path / "cat"
    d.mkdir()
    catalog = d / "model-config.yaml"
    catalog.write_text(SYNTH)
    target = d if lock == "dir" else catalog
    mode = target.stat().st_mode
    target.chmod(0o555 if lock == "dir" else 0o444)
    try:
        code, record = _run(tool, monkeypatch, tmp_path, "--write-catalog", str(catalog), expect_calls=False)
    finally:
        target.chmod(mode)
    assert code == 2 and record is None and fake["calls"]() == []
    err = capsys.readouterr().err
    assert "not writable" in err and "nothing spent" in err
    assert catalog.read_text() == SYNTH


@pytest.mark.parametrize("partial", [False, True])
def test_q3_a_failed_catalog_write_leaves_no_written_claim(tool, fake, monkeypatch, tmp_path, capsys, partial):
    _limit(monkeypatch, 350_000 if partial else 250_000)
    catalog = tmp_path / "model-config.yaml"
    catalog.write_text(SYNTH)

    def boom(path, new):
        raise OSError(28, "No space left on device")
    monkeypatch.setattr(tool, "_write_text_atomic", boom)
    extra = ("--budget-usd", "3.6", "--write-partial-as-operator-set") if partial else ()
    code, record = _run(tool, monkeypatch, tmp_path, "--write-catalog", str(catalog), *extra)
    assert code == 1
    assert record["outcome"] == ("partial" if partial else "clean")
    assert "written_ceiling" not in record and "written_probe_outcome" not in record, record
    assert "catalog not written" in record["error"] and "No space left" in record["error"]
    assert catalog.read_text() == SYNTH
    assert "No space left" in capsys.readouterr().err


def test_q3_a_landed_write_is_claimed_in_the_record(tool, fake, monkeypatch, tmp_path):
    _limit(monkeypatch, 250_000)
    catalog = tmp_path / "model-config.yaml"
    catalog.write_text(SYNTH)
    code, record = _run(tool, monkeypatch, tmp_path, "--write-catalog", str(catalog))
    entry = yaml.safe_load(catalog.read_text())["providers"]["anthropic"]["models"]["claude-opus-5-5"]
    assert code == 0 and record["written_ceiling"] == entry["effective_input_ceiling"]
    assert record["written_probe_outcome"] == "clean" and "error" not in record


def test_q4_a_skipped_forced_write_keeps_the_first_probe_error(tool, fake, monkeypatch, tmp_path, capsys):
    monkeypatch.setenv("FAKE_MODE", "other")
    catalog = tmp_path / "model-config.yaml"
    catalog.write_text(SYNTH)
    code, record = _run(tool, monkeypatch, tmp_path, "--write-catalog", str(catalog), "--write-partial-as-operator-set")
    assert code == 1 and catalog.read_text() == SYNTH
    assert "Not logged in" in record["error"]                    # errors[0], not overwritten
    assert "no verified accept" in record["write_skipped"]
    assert "no verified accept" in capsys.readouterr().err


def test_q7_the_tpm_schedule_clears_the_window_by_construction(tool):
    assert sum(tool._TPM_BACKOFF_S) >= tool._TPM_WINDOW_S
    src = TOOL.read_text()
    assert "sum(_TPM_BACKOFF_S) < _TPM_WINDOW_S" in src            # the import-time guard exists


# --- r251-4 (audit dissent run 1, verifier F) -----------------------------------

_INJECT = "x\n        effective_input_ceiling: 1"


@pytest.mark.parametrize("route", [_INJECT, "a\rb", "a\x00b", "a\x1bb", "a\x7fb", "a\x85b", "a b",
                                   "x" * 201])
@pytest.mark.parametrize("write", [True, False])
def test_t1_an_unsafe_host_route_is_a_usage_error_before_any_spend(tool, fake, monkeypatch, tmp_path, capsys,
                                                                   route, write):
    """n52: --host-route reaches the catalog's provenance comment; a line break there
    overrides `effective_input_ceiling` in the loaded YAML. Refused (exit 2) before
    the dry run and before any model call, with or without --write-catalog."""
    _limit(monkeypatch, 250_000)
    catalog = tmp_path / "model-config.yaml"
    catalog.write_text(SYNTH)
    extra = ("--write-catalog", str(catalog)) if write else ()
    code, record = _run(tool, monkeypatch, tmp_path, "--host-route", route, *extra, expect_calls=False)
    assert code == 2 and record is None and fake["calls"]() == []
    assert "--host-route" in capsys.readouterr().err
    assert catalog.read_text() == SYNTH


def test_t1_an_unsafe_resolved_cli_model_from_the_env_is_refused(tool, fake, monkeypatch, tmp_path, capsys):
    """n52/n57: the RESOLVED cli_model (ANTHROPIC_DEFAULT_OPUS_MODEL feeds `opus`) is validated."""
    catalog = tmp_path / "model-config.yaml"
    catalog.write_text(SYNTH)
    monkeypatch.setenv("ANTHROPIC_DEFAULT_OPUS_MODEL", "opus\n        effective_input_ceiling: 1")
    code, record = _run(tool, monkeypatch, tmp_path, "--cli-model", "opus", "--write-catalog", str(catalog),
                        expect_calls=False)
    assert code == 2 and record is None and fake["calls"]() == []
    err = capsys.readouterr().err
    assert "cli_model" in err and "ANTHROPIC_DEFAULT_OPUS_MODEL" in err
    assert catalog.read_text() == SYNTH


def test_t1_an_unsafe_cli_version_is_refused(tool, fake, monkeypatch, tmp_path, capsys):
    monkeypatch.setattr(tool, "_cli_version", lambda _bin: "2.1\x1b[31m (Claude Code)")
    code, record = _run(tool, monkeypatch, tmp_path, expect_calls=False)
    assert code == 2 and record is None and "cli_version" in capsys.readouterr().err


def test_t1_the_dry_run_uses_the_real_writes_resolved_kwargs(tool, fake, monkeypatch, tmp_path):
    """n57: the pre-spend dry run passes the resolved cli_model, the host route and the
    cli_version the real write will pass."""
    _limit(monkeypatch, 250_000)
    monkeypatch.setenv("ANTHROPIC_DEFAULT_OPUS_MODEL", "global.anthropic.claude-opus-5-5")
    catalog = tmp_path / "model-config.yaml"
    catalog.write_text(SYNTH)
    seen: list = []
    real = tool.write_catalog_operator_set

    def spy(text, model, **kw):
        seen.append(kw)
        return real(text, model, **kw)

    monkeypatch.setattr(tool, "write_catalog_operator_set", spy)
    code, record = _run(tool, monkeypatch, tmp_path, "--cli-model", "opus", "--host-route", "bedrock",
                        "--write-catalog", str(catalog))
    assert code == 0 and len(seen) == 2
    dry, real_kw = seen
    for k in ("cli_model", "host_route", "cli_version"):
        assert dry[k] == real_kw[k], k
    assert dry["cli_model"] == "global.anthropic.claude-opus-5-5" and dry["cli_version"] == "9.9.9 (Fake Claude)"


@pytest.mark.parametrize("field", ["host_route", "cli_model", "cli_version"])
def test_t1_the_writer_refuses_control_characters_itself(tool, field):
    with pytest.raises(ValueError, match=field):
        _w(tool, SYNTH, 640_000, **{field: _INJECT})


def test_t1_the_writer_reparses_its_output_before_returning(tool, monkeypatch):
    """n52 (c): a template defect that would corrupt the entry raises instead of writing."""
    monkeypatch.setattr(tool, "_PROVENANCE", tool._PROVENANCE + "\n        effective_input_ceiling: 1")
    with pytest.raises(ValueError, match="re-parse"):
        _w(tool, SYNTH, 640_000)


def test_t1_the_reparse_catches_a_change_outside_the_entry(tool, monkeypatch):
    monkeypatch.setattr(tool, "_PROVENANCE", tool._PROVENANCE + "\n        context_window: 5")
    with pytest.raises(ValueError, match="re-parse"):
        _w(tool, SYNTH, 640_000)


def test_t1_a_reparse_failure_on_the_real_write_leaves_the_catalog(tool, fake, monkeypatch, tmp_path):
    """The dry run passes (ceiling 1) but the real write's text is corrupt: nothing lands."""
    _limit(monkeypatch, 250_000)
    catalog = tmp_path / "model-config.yaml"
    catalog.write_text(SYNTH)
    real = tool.write_catalog_operator_set
    calls = {"n": 0}

    def corrupt_second(text, model, **kw):
        calls["n"] += 1
        if calls["n"] == 2:
            monkeypatch.setattr(tool, "_PROVENANCE", tool._PROVENANCE + "\n        effective_input_ceiling: 1")
        return real(text, model, **kw)

    monkeypatch.setattr(tool, "write_catalog_operator_set", corrupt_second)
    code, record = _run(tool, monkeypatch, tmp_path, "--write-catalog", str(catalog))
    assert code == 1 and record["write_failed"] is True and "re-parse" in record["error"]
    assert "written_ceiling" not in record
    assert catalog.read_text() == SYNTH


@pytest.mark.parametrize("value", ["Infinity", "NaN", "-Infinity", "1e9"])
def test_t2_a_non_finite_or_absurd_cli_cost_is_dropped(tool, fake, monkeypatch, tmp_path, value):
    """n56: json.loads accepts Infinity / NaN; int(inf * 1e6) raised OverflowError outside
    the attempt's try, losing the charge and the run. The value is dropped and noted."""
    _limit(monkeypatch, 250_000)
    monkeypatch.setenv("FAKE_COST", value)
    code, record = _run(tool, monkeypatch, tmp_path)
    assert code == 0 and record["outcome"] == "clean"
    for s in record["samples"]:
        if s["kind"] == "ok":
            assert s["cli_reported_cost_usd"] is None
            assert any("cli_reported_cost_usd" in n for n in s["dropped_values"])
            assert s["charged_usd"] == pytest.approx(s["measured_input_tokens"] * 5e-6, abs=1e-5)
    assert json.loads(json.dumps(record["spent_usd"])) == record["spent_usd"]


def test_t2_absurd_token_counts_and_retry_hints_are_dropped(tool):
    out = json.dumps({"type": "result", "is_error": False, "result": "abcdef012345", "total_cost_usd": 0.5,
                      "usage": {"input_tokens": 10 ** 12}})
    res = tool._classify(0, out, "", "abcdef012345")
    assert res["kind"] == "ok" and res["measured_input_tokens"] is None and res["cli_reported_cost_usd"] == 0.5
    assert any("measured_input_tokens" in n for n in res["dropped_values"])
    err = json.dumps({"type": "result", "is_error": True, "result": "API Error: 429 rate limit, retry-after: 99999"})
    res = tool._classify(1, err, "", "abcdef012345")
    assert res["kind"] == "transient" and "retry_after_s" not in res
    assert any("retry_after_s" in n for n in res["dropped_values"])
    ok = tool._classify(1, json.dumps({"type": "result", "is_error": True,
                                       "result": "API Error: 429 rate limit, retry-after: 30"}), "", "x")
    assert ok["retry_after_s"] == 30.0 and "dropped_values" not in ok


def test_t2_charge_never_overflows(tool):
    for bad in (float("inf"), float("nan"), 10 ** 400):
        assert tool._charge({"kind": "ok", "measured_input_tokens": 1000, "cli_reported_cost_usd": bad},
                            est_micro=7, price_in=5_000_000)[0] == 5_000     # 1000 tokens × $5/MTok, in micro-USD


def test_t4_the_record_names_paths_under_home_tilde_relative(tool, fake, monkeypatch, tmp_path):
    """n40/n43: the committed record must not carry the operator's home directory."""
    _limit(monkeypatch, 250_000)
    monkeypatch.setenv("HOME", str(fake["dir"]))
    code, record = _run(tool, monkeypatch, tmp_path)
    assert code == 0
    assert record["cli_bin"] == "~/fake-claude" and record["argv"][0] == "~/fake-claude"
    assert record["argv"][1:] == PINNED
    assert str(fake["dir"]) not in json.dumps(record["cli_bin"]) + json.dumps(record["argv"])


def test_t4_home_rendering_is_prefix_exact(tool, monkeypatch):
    monkeypatch.setenv("HOME", "/home/op")
    assert tool._home_rel("/home/op/.local/bin/claude-bedrock") == "~/.local/bin/claude-bedrock"
    assert tool._home_rel("/home/operator/bin/claude") == "/home/operator/bin/claude"
    assert tool._home_rel("claude") == "claude"
    monkeypatch.setenv("HOME", "/")
    assert tool._home_rel("/usr/bin/claude") == "/usr/bin/claude"


def test_t4_the_committed_probe_record_carries_no_home_path():
    rec = ROOT / "grimoires" / "loa" / "reports" / "2026-10-07-opus-5-5-ceiling-probe-cli.json"
    data = json.loads(rec.read_text())
    assert data["cli_bin"] == "~/.local/bin/claude-bedrock" and data["argv"][0] == "~/.local/bin/claude-bedrock"
    assert "/home/" not in rec.read_text()


_HEADLESS_CAL = {"source": "operator_set", "calibrated_at": "2026-10-07T00:00:00Z", "sample_size": 5,
                 "stale_after_days": 90, "method": "probed_headless", "transport": "claude-headless",
                 "probe_outcome": "partial", "cli_model": "global.anthropic.claude-opus-5-5",
                 "cli_version": "2.1.292 (Claude Code)", "measured_input_tokens": 972_887}


@pytest.mark.parametrize("mutate", [
    lambda c: {k: v for k, v in c.items() if k != "probe_outcome"},
    lambda c: {k: v for k, v in c.items() if k != "transport"},
    lambda c: {**c, "transport": "api"},
    lambda c: {**c, "cli_model": "m" * 201},
    lambda c: {**c, "cli_version": "v" * 201},
])
def test_t5_the_schema_ties_probed_headless_to_its_transport_and_outcome(tool, mutate):
    import jsonschema
    _validate_cal(_HEADLESS_CAL)
    with pytest.raises(jsonschema.ValidationError):
        _validate_cal(mutate(_HEADLESS_CAL))


def test_t5_the_schema_still_accepts_an_api_probe_without_probe_outcome(tool):
    _validate_cal({"source": "empirical_probe", "calibrated_at": "2026-10-07T00:00:00Z", "sample_size": 5,
                   "stale_after_days": 90, "method": "probed_api", "transport": "api"})


def test_t5_the_live_catalog_entries_satisfy_the_hardened_calibration_schema():
    cat = yaml.safe_load(CATALOG.read_text())
    seen = 0
    for prov in cat["providers"].values():
        for mid, entry in (prov.get("models") or {}).items():
            if isinstance(entry, dict) and isinstance(entry.get("ceiling_calibration"), dict):
                _validate_cal(entry["ceiling_calibration"])
                seen += entry["ceiling_calibration"].get("method") == "probed_headless"
    assert seen >= 1
