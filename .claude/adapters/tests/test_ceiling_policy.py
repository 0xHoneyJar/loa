"""cycle-126 Sprint 1 Task 1.1 (PRD FR-1.1, SDD D-1.1 / D-1.1b) — the input
bound is a policy over the catalog entry, not a literal:

  I1  estimate + max_tokens_on_wire ≤ context_window  (auto-shrink max_tokens
      to a 4,096 floor before refusing)
  I2  calibrated entry → calibrated value; uncalibrated entry → probed bound by
      default; the catalog-derived bound (context_window − max_tokens) only
      after calibration or under LOA_CHEVAL_UNCALIBRATED_CEILING=derived;
      an observed provider limit (self-correction) caps the bound until
      calibration; LOA_CHEVAL_MAX_INPUT_TOKENS lowers any bound;
      LOA_CHEVAL_LEGACY_CEILING=1 is today's single literal.
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from loa_cheval.routing.ceiling import (  # noqa: E402
    FLOOR_MAX_TOKENS,
    CeilingDecision,
    fit_max_tokens,
    input_bound,
    policy_from_env,
)

FIVE = {  # a 5-family entry as the catalog carries it after this sprint
    "context_window": 1_000_000,
    "max_output_tokens": 128_000,
    "effective_input_ceiling": 180_000,
    "probed_ceiling": 180_000,
    "ceiling_calibration": {"source": "kf_derived", "calibrated_at": None, "stale_after_days": 90},
}
TWO_HUNDRED = {  # a 200K entry
    "context_window": 200_000,
    "max_output_tokens": 128_000,
    "effective_input_ceiling": 180_000,
    "probed_ceiling": 180_000,
    "ceiling_calibration": {"source": "kf_derived", "calibrated_at": None, "stale_after_days": 90},
}
V2 = {"context_window": 200_000}  # no ceiling fields at all → no gate


@pytest.fixture(autouse=True)
def _clean_env(monkeypatch):
    for k in ("LOA_CHEVAL_LEGACY_CEILING", "LOA_CHEVAL_UNCALIBRATED_CEILING", "LOA_CHEVAL_MAX_INPUT_TOKENS"):
        monkeypatch.delenv(k, raising=False)


def test_policy_from_env_defaults_to_probed(monkeypatch):
    assert policy_from_env() == "probed"
    monkeypatch.setenv("LOA_CHEVAL_UNCALIBRATED_CEILING", "derived")
    assert policy_from_env() == "derived"
    monkeypatch.setenv("LOA_CHEVAL_LEGACY_CEILING", "1")
    assert policy_from_env() == "legacy", "the kill switch wins over the opt-in"


def test_uncalibrated_entry_uses_the_probed_bound_by_default():
    d = input_bound(FIVE, max_tokens=64_000)
    assert isinstance(d, CeilingDecision)
    assert d.value == 180_000 and d.basis == "probed" and d.calibrated is False
    assert d.derived == 1_000_000 - 64_000 and d.probed == 180_000


def test_derived_bound_needs_the_opt_in_and_never_exceeds_i1(monkeypatch):
    monkeypatch.setenv("LOA_CHEVAL_UNCALIBRATED_CEILING", "derived")
    d = input_bound(FIVE, max_tokens=64_000)
    assert d.value == 936_000 and d.basis == "derived"
    # I1: the derived bound shrinks with a larger output budget
    assert input_bound(FIVE, max_tokens=128_000).value == 872_000
    # a 200K entry under the opt-in: derived (72K) is BELOW the probed value — I1 wins, never max()
    d2 = input_bound(TWO_HUNDRED, max_tokens=128_000)
    assert d2.value == 72_000 and d2.basis == "derived"


def test_probed_bound_is_also_capped_by_i1_for_200k_entries():
    # default policy on a 200K entry with the new 64K streaming default: 200K − 64K = 136K < probed 180K
    d = input_bound(TWO_HUNDRED, max_tokens=64_000)
    assert d.value == 136_000 and d.basis == "i1"
    # with a small output budget the probed value stands
    assert input_bound(TWO_HUNDRED, max_tokens=4_096).value == 180_000


def test_calibrated_entry_uses_its_calibrated_value_regardless_of_policy(monkeypatch):
    cal = dict(FIVE, effective_input_ceiling=640_000,
               ceiling_calibration={"source": "empirical_probe", "calibrated_at": "2026-09-25T00:00:00Z", "stale_after_days": 90})
    d = input_bound(cal, max_tokens=64_000)
    assert d.value == 640_000 and d.basis == "calibrated" and d.calibrated is True
    monkeypatch.setenv("LOA_CHEVAL_UNCALIBRATED_CEILING", "derived")
    assert input_bound(cal, max_tokens=64_000).value == 640_000, "the opt-in never overrides a measurement"
    # I1 still applies to a calibrated value
    assert input_bound(cal, max_tokens=400_000).value == 600_000


def test_observed_provider_limit_caps_the_bound_until_calibration(monkeypatch):
    monkeypatch.setenv("LOA_CHEVAL_UNCALIBRATED_CEILING", "derived")
    d = input_bound(FIVE, max_tokens=64_000, observed=412_000)
    assert d.value == 411_999 and d.basis == "observed" and d.observed == 412_000
    # an observed limit above the current bound changes nothing
    assert input_bound(FIVE, max_tokens=64_000, observed=999_000).basis == "derived"
    # a calibrated entry ignores stale observations
    cal = dict(FIVE, effective_input_ceiling=640_000,
               ceiling_calibration={"source": "empirical_probe", "calibrated_at": "2026-09-25T00:00:00Z", "stale_after_days": 90})
    assert input_bound(cal, max_tokens=64_000, observed=412_000).basis == "calibrated"


def test_max_input_guard_lowers_any_bound(monkeypatch):
    monkeypatch.setenv("LOA_CHEVAL_MAX_INPUT_TOKENS", "100000")
    d = input_bound(FIVE, max_tokens=64_000)
    assert d.value == 100_000 and d.basis == "guard"
    monkeypatch.setenv("LOA_CHEVAL_MAX_INPUT_TOKENS", "not-a-number")
    assert input_bound(FIVE, max_tokens=64_000).value == 180_000, "a malformed guard is ignored, never a zero bound"


def test_legacy_kill_switch_is_todays_literal(monkeypatch):
    monkeypatch.setenv("LOA_CHEVAL_LEGACY_CEILING", "1")
    monkeypatch.setenv("LOA_CHEVAL_UNCALIBRATED_CEILING", "derived")
    d = input_bound(FIVE, max_tokens=64_000, observed=100_000)
    assert d.value == 180_000 and d.basis == "legacy"
    assert input_bound(TWO_HUNDRED, max_tokens=64_000).value == 180_000, "legacy = the literal, even where I1 would say less (today's behaviour)"


def test_v2_entry_has_no_bound():
    assert input_bound(V2, max_tokens=4_096) is None


def test_fit_max_tokens_shrinks_to_the_floor_then_refuses():
    # 170K input on a 200K entry with the 64K default: shrink to 30K, record it
    fit = fit_max_tokens(context_window=200_000, estimate=170_000, requested=64_000)
    assert fit.max_tokens == 30_000 and fit.shrunk_from == 64_000
    # fits already: untouched
    fit2 = fit_max_tokens(context_window=200_000, estimate=100_000, requested=64_000)
    assert fit2.max_tokens == 64_000 and fit2.shrunk_from is None
    # cannot fit even the floor: refused
    fit3 = fit_max_tokens(context_window=200_000, estimate=199_000, requested=64_000)
    assert fit3.max_tokens is None and fit3.shrunk_from == 64_000
    assert FLOOR_MAX_TOKENS == 4_096
    # a requested budget below the floor is respected as-is when it fits
    assert fit_max_tokens(context_window=200_000, estimate=198_000, requested=1_000).max_tokens == 1_000


# --- D-1.1b message parsing + observed store --------------------------------

from loa_cheval.routing.ceiling import (  # noqa: E402
    BOUND_LOWERING_CLASSES,
    OBSERVED_PATH_ENV,
    GateEstimate,
    gate,
    is_context_limit_message,
    load_observed,
    observed_for,
    observed_store_path,
    parse_context_limit,
    record_observed,
)


def test_context_limit_messages_are_classified_and_parsed():
    assert is_context_limit_message("prompt is too long: 213456 tokens > 200000 maximum")
    assert is_context_limit_message("input length and max_tokens exceed context limit: 190000 + 64000 > 200000")
    assert is_context_limit_message("Request too large for this model") and not is_context_limit_message("invalid effort 'turbo'")
    assert parse_context_limit("prompt is too long: 213,456 tokens > 200,000 maximum") == {
        "input_tokens": 213_456, "limit": 200_000, "max_tokens": None}
    assert parse_context_limit("input length and `max_tokens` exceed context limit: 190000 + 64000 > 200000") == {
        "input_tokens": 190_000, "max_tokens": 64_000, "limit": 200_000}
    assert parse_context_limit("request_too_large") == {"input_tokens": None, "limit": None, "max_tokens": None}


def test_token_limit_429_messages_are_told_apart_from_request_rate_ones():
    """BB-003: a 429 is the token-limit class only when the provider's message says so."""
    from loa_cheval.routing.ceiling import is_token_limit_message
    for msg in ("This request would exceed the rate limit for your organization of 30,000 input tokens per minute.",
                "Rate limit reached for gpt-5.5-pro on tokens per min (TPM): Limit 30000, Requested 612000.",
                "Request too large for gpt-5.5-pro on tokens per min (TPM)",
                "context_length_exceeded",
                "prompt is too long: 612000 tokens > 400000 maximum"):
        assert is_token_limit_message(msg), msg
    for msg in ("Rate limit reached for gpt-5.5-pro on requests per min (RPM): Limit 500",
                "This request would exceed the rate limit for your organization of 50 requests per minute.",
                "", None):
        assert not is_token_limit_message(msg), msg


def test_adapters_mark_a_token_limit_429(monkeypatch):
    """The Anthropic and OpenAI adapters set RateLimitError.token_limited from the 429 body."""
    from loa_cheval.providers import anthropic_adapter, openai_adapter
    from loa_cheval.types import RateLimitError, dispatch_provider_stream_error, ProviderStreamError
    assert RateLimitError("anthropic").token_limited is False
    assert RateLimitError("anthropic", token_limited=True).token_limited is True
    assert anthropic_adapter._rate_limit_error("anthropic", {"error": {"message": "30,000 input tokens per minute"}}).token_limited
    assert not anthropic_adapter._rate_limit_error("anthropic", {"error": {"message": "50 requests per minute"}}).token_limited
    assert openai_adapter._rate_limit_error("openai", {"error": {"message": "on tokens per min (TPM): Limit 30000"}}).token_limited
    assert not openai_adapter._rate_limit_error("openai", {"error": {"message": "on requests per min (RPM)"}}).token_limited
    assert not openai_adapter._rate_limit_error("openai", "not a dict").token_limited
    assert dispatch_provider_stream_error(ProviderStreamError("rate_limit", "input tokens per minute"), provider="anthropic").token_limited
    assert not dispatch_provider_stream_error(ProviderStreamError("rate_limit", "429 received"), provider="anthropic").token_limited


def test_observed_store_records_atomically_and_reduces_to_the_tightest_bound(tmp_path, monkeypatch):
    path = tmp_path / "run" / "ceiling-observed.json"  # parent missing on a fresh mount → created
    monkeypatch.setenv(OBSERVED_PATH_ENV, str(path))
    assert observed_store_path() == str(path)
    assert observed_for("anthropic", "claude-fable-5-1") is None
    row = record_observed(provider="anthropic", model="claude-fable-5-1", observed_input_tokens=412_000,
                          error_class="CEILING_UNVERIFIED_LIMIT", estimated_input_tokens=400_000)
    assert row["calibrate"].endswith("--model claude-fable-5-1 --write-catalog") and row["ts"].endswith("Z")
    assert observed_for("anthropic", "claude-fable-5-1") == 412_000
    record_observed(provider="anthropic", model="claude-fable-5-1", observed_input_tokens=450_000,
                    error_class="PROVIDER_CONTEXT_LIMIT", provider_limit=380_000)
    assert observed_for("anthropic", "claude-fable-5-1") == 380_001, "the provider's stated limit + 1 is the tightest"
    record_observed(provider="anthropic", model="claude-fable-5-1", observed_input_tokens=10, error_class="RATE_LIMIT_UNVERIFIED")
    assert observed_for("anthropic", "claude-fable-5-1") == 380_001, "a 429 is recorded but never lowers the bound"
    assert observed_for("anthropic", "claude-opus-5") is None
    data = load_observed(str(path))
    assert data["version"] == 1 and len(data["entries"]) == 3
    assert not [p for p in path.parent.iterdir() if p.name.startswith(".ceiling-observed.")], "no temp file left behind"
    path.write_text("{not json")
    assert load_observed(str(path)) == {"version": 1, "entries": []}, "a malformed store never fails the gate closed"
    assert BOUND_LOWERING_CLASSES == {"CEILING_UNVERIFIED_LIMIT", "PROVIDER_CONTEXT_LIMIT"}


def test_observed_store_default_path_is_the_repo_run_dir(monkeypatch):
    monkeypatch.delenv(OBSERVED_PATH_ENV, raising=False)
    p = Path(observed_store_path())
    assert p.name == "ceiling-observed.json" and p.parent.name == ".run"
    assert (p.parent.parent / ".claude" / "adapters").is_dir(), "the repo root, not the working directory"


# --- the gate decision (D-1.1 / D-1.4) ----------------------------------------

def test_gate_default_policy_preempts_at_the_probed_bound():
    out = gate(FIVE, estimate=GateEstimate(tokens=600_000), requested_max_tokens=64_000)
    assert out.action == "preempt" and out.bound == 180_000 and out.basis == "probed"
    env = out.as_envelope()
    assert env["preflight_decision"] == "preempt" and env["input_ceiling"]["value"] == 180_000
    assert env["estimator"]["tokens"] == 600_000 and env["ceiling_policy"] == "probed" and env["ceiling_unverified"] is False


def test_gate_opt_in_warns_on_low_uncertainty_and_preempts_on_high(monkeypatch):
    monkeypatch.setenv("LOA_CHEVAL_UNCALIBRATED_CEILING", "derived")
    entry = dict(FIVE, model_id="claude-fable-5-1")
    low = gate(entry, estimate=GateEstimate(tokens=600_000, uncertainty="low"), requested_max_tokens=64_000)
    assert low.action == "warn" and low.unverified is True and low.bound == 936_000 and low.basis == "derived"
    assert "ceiling-probe-live.py --model claude-fable-5-1" in low.reason
    high = gate(entry, estimate=GateEstimate(tokens=600_000, uncertainty="high"), requested_max_tokens=64_000)
    assert high.action == "preempt" and "calibrate first" in high.reason
    # I1 auto-shrink: 950K + 64K > 1M, so the budget shrinks to 50K and the request fits under the derived bound
    big = gate(entry, estimate=GateEstimate(tokens=950_000, uncertainty="low"), requested_max_tokens=64_000)
    assert big.action == "warn" and big.max_tokens == 50_000 and big.shrunk_from == 64_000 and big.bound == 950_000
    # but never past the window minus the output floor
    top = gate(entry, estimate=GateEstimate(tokens=997_000, uncertainty="low"), requested_max_tokens=64_000)
    assert top.action == "preempt" and top.basis == "i1"
    # and never past the operator's guard
    monkeypatch.setenv("LOA_CHEVAL_MAX_INPUT_TOKENS", "500000")
    guarded = gate(entry, estimate=GateEstimate(tokens=600_000, uncertainty="low"), requested_max_tokens=64_000)
    assert guarded.action == "preempt" and guarded.basis == "guard" and guarded.bound == 500_000
    monkeypatch.delenv("LOA_CHEVAL_MAX_INPUT_TOKENS")
    # under the probed bound the opt-in changes nothing
    assert gate(entry, estimate=GateEstimate(tokens=100_000), requested_max_tokens=64_000).action == "dispatch"


def test_gate_count_endpoint_is_authoritative(monkeypatch):
    monkeypatch.setenv("LOA_CHEVAL_UNCALIBRATED_CEILING", "derived")
    out = gate(FIVE, estimate=GateEstimate(tokens=600_000, uncertainty="high"), requested_max_tokens=64_000, counter=lambda: 610_000)
    assert out.action == "warn" and out.estimate.method == "count_tokens" and out.estimate.tokens == 610_000
    assert out.estimate.uncertainty == "none", "a high heuristic is settled by the count"
    assert gate(FIVE, estimate=GateEstimate(tokens=600_000), requested_max_tokens=64_000, counter=lambda: 940_000).action == "preempt"
    calls = []
    gate(FIVE, estimate=GateEstimate(tokens=100_000), requested_max_tokens=64_000, counter=lambda: calls.append(1) or 1)
    assert calls == [], "far below the bound no count is spent"
    monkeypatch.delenv("LOA_CHEVAL_UNCALIBRATED_CEILING")
    calls.clear()
    out = gate(FIVE, estimate=GateEstimate(tokens=170_000), requested_max_tokens=64_000, counter=lambda: calls.append(1) or 179_000)
    assert calls == [1] and out.action == "dispatch" and out.estimate.method == "count_tokens", "within 90 % of the bound the count runs"
    out = gate(FIVE, estimate=GateEstimate(tokens=170_000), requested_max_tokens=64_000, counter=lambda: None)
    assert out.estimate.method == "heuristic" and out.action == "dispatch", "a failed count keeps the heuristic"


def test_gate_i1_shrinks_the_output_budget_before_the_bound():
    out = gate(TWO_HUNDRED, estimate=GateEstimate(tokens=170_000), requested_max_tokens=64_000)
    assert out.action == "dispatch" and out.max_tokens == 30_000 and out.shrunk_from == 64_000
    assert out.as_envelope()["max_tokens_shrunk"] == {"from": 64_000, "to": 30_000}
    out = gate(TWO_HUNDRED, estimate=GateEstimate(tokens=199_000), requested_max_tokens=64_000)
    assert out.action == "preempt" and out.basis == "i1" and "output floor" in out.reason


def test_gate_cli_override_observed_and_legacy(monkeypatch):
    assert gate(FIVE, estimate=GateEstimate(tokens=150_000), requested_max_tokens=64_000, cli_override=100_000).basis == "cli_override"
    v2 = gate(V2, estimate=GateEstimate(tokens=150_000), requested_max_tokens=4_096, cli_override=100_000)
    assert v2.action == "preempt" and v2.basis == "cli_override", "--max-input-tokens binds an entry without a catalog ceiling too"
    assert gate(V2, estimate=GateEstimate(tokens=150_000), requested_max_tokens=4_096).action == "dispatch"
    monkeypatch.setenv("LOA_CHEVAL_UNCALIBRATED_CEILING", "derived")
    out = gate(FIVE, estimate=GateEstimate(tokens=500_000, uncertainty="low"), requested_max_tokens=64_000, observed=412_000)
    assert out.action == "preempt" and out.basis == "observed" and out.bound == 411_999
    monkeypatch.setenv("LOA_CHEVAL_LEGACY_CEILING", "1")
    out = gate(TWO_HUNDRED, estimate=GateEstimate(tokens=170_000), requested_max_tokens=64_000, counter=lambda: 1)
    assert out.action == "dispatch" and out.shrunk_from is None and out.policy == "legacy" and out.estimate.method == "heuristic", \
        "legacy: no I1, no count, the literal"


def test_record_observed_is_serialised_across_processes(tmp_path, monkeypatch):
    """Review sprint-247 DISS-001 (chunk a): concurrent writers must not lose rows —
    the read/append/replace cycle is held under an interprocess lock."""
    import multiprocessing as mp
    path = tmp_path / "ceiling-observed.json"
    monkeypatch.setenv(OBSERVED_PATH_ENV, str(path))

    ctx = mp.get_context("fork")
    procs = [ctx.Process(target=_append_many, args=(str(path), w, 25)) for w in range(4)]
    for pr in procs:
        pr.start()
    for pr in procs:
        pr.join(60)
    assert all(pr.exitcode == 0 for pr in procs), [pr.exitcode for pr in procs]
    data = load_observed(str(path))
    assert len(data["entries"]) == 100, len(data["entries"])
    assert sorted(row["observed_input_tokens"] for row in data["entries"]) == sorted(1000 * w + i for w in range(4) for i in range(25))
    assert not [p for p in tmp_path.iterdir() if p.suffix == ".tmp"], "no temp file left behind"


def _append_many(path, worker, n):
    for i in range(n):
        record_observed(provider="anthropic", model="claude-opus-5", observed_input_tokens=1000 * worker + i,
                        error_class="PROVIDER_CONTEXT_LIMIT", path=path)


def test_record_observed_never_follows_a_planted_symlink_at_the_lock_path(tmp_path, monkeypatch):
    """Audit hardening (atomic-write symlink defenses): the lock file is opened O_NOFOLLOW, so a
    symlink planted at `<store>.lock` is refused (OSError) instead of being followed."""
    path = tmp_path / "ceiling-observed.json"
    target = tmp_path / "elsewhere.txt"
    target.write_text("keep")
    (tmp_path / "ceiling-observed.json.lock").symlink_to(target)
    with pytest.raises(OSError):
        record_observed(provider="anthropic", model="m", observed_input_tokens=1, error_class="PROVIDER_CONTEXT_LIMIT", path=str(path))
    assert target.read_text() == "keep" and not path.exists()


def test_record_observed_refuses_a_lock_symlink_without_o_nofollow(tmp_path, monkeypatch):
    """Bridgebuilder F3: on a platform without O_NOFOLLOW the open would follow a planted symlink;
    the lstat before the open and the fstat/lstat identity check after it refuse it anyway, and the
    target (or a dangling target's path) is never touched."""
    monkeypatch.delattr(os, "O_NOFOLLOW", raising=False)
    path = tmp_path / "ceiling-observed.json"
    target = tmp_path / "elsewhere.txt"
    target.write_text("keep")
    lock = tmp_path / "ceiling-observed.json.lock"
    lock.symlink_to(target)
    with pytest.raises(OSError):
        record_observed(provider="anthropic", model="m", observed_input_tokens=1, error_class="PROVIDER_CONTEXT_LIMIT", path=str(path))
    assert target.read_text() == "keep" and not path.exists()
    lock.unlink()
    dangling = tmp_path / "never-created.txt"
    lock.symlink_to(dangling)
    with pytest.raises(OSError):
        record_observed(provider="anthropic", model="m", observed_input_tokens=1, error_class="PROVIDER_CONTEXT_LIMIT", path=str(path))
    assert not dangling.exists() and not path.exists()
    # the normal path still records
    lock.unlink()
    row = record_observed(provider="anthropic", model="m", observed_input_tokens=7, error_class="PROVIDER_CONTEXT_LIMIT", path=str(path))
    assert row["observed_input_tokens"] == 7 and observed_for("anthropic", "m", load_observed(str(path))) == 7
    assert lock.is_file() and not lock.is_symlink()


def test_record_observed_refuses_a_lock_that_is_not_a_regular_file(tmp_path):
    path = tmp_path / "ceiling-observed.json"
    os.mkfifo(tmp_path / "ceiling-observed.json.lock")
    with pytest.raises(OSError):
        record_observed(provider="anthropic", model="m", observed_input_tokens=1, error_class="PROVIDER_CONTEXT_LIMIT", path=str(path))
    assert not path.exists()
