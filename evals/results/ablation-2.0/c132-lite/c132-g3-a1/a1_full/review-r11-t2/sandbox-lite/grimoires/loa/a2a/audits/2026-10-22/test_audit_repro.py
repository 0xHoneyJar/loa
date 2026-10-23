"""Audit repro checks (sprint-1 audit, 2026-10-22). NOT part of the PR — runs against the overlay at /tmp/aroot.
Each test states the EXPECTED behaviour; a failure demonstrates the defect."""
from __future__ import annotations
import sys
from pathlib import Path
import pytest
ADAPTERS = Path("/tmp/aroot/.claude/adapters")
sys.path.insert(0, str(ADAPTERS))
sys.path.insert(0, str(ADAPTERS / "tests"))
import cheval  # noqa: E402
import test_ceiling_e2e as H  # the PR's own harness  # noqa: E402
from loa_cheval.providers import retry as retry_mod  # noqa: E402
from loa_cheval.metering.pricing import PricingEntry, calculate_total_cost, _long_context_fields  # noqa: E402
from loa_cheval.routing.ceiling import observed_for  # noqa: E402
from loa_cheval.types import (CompletionRequest, ProviderContextLimitError, ProviderUnavailableError,  # noqa: E402
                              RateLimitError, RetriesExhaustedError)

_quiet = H._quiet  # reuse the PR's autouse fixture (persona stubs, env scrub)


@pytest.fixture(autouse=True)
def _state_paths(monkeypatch, tmp_path):
    monkeypatch.setenv("LOA_CHEVAL_CEILING_OBSERVED_PATH", str(tmp_path / "ceiling-observed.json"))
    monkeypatch.setenv("LOA_COST_LEDGER_PATH", str(tmp_path / "cost-ledger.jsonl"))
    monkeypatch.setenv("LOA_MODELINV_LOG_PATH", str(tmp_path / "model-invoke.jsonl"))


# R1 — review Change 1: count <= bound < heuristic must dispatch on the HEAD hop (D-1.4)
def test_r1_walk_gate_honours_the_provider_count():
    class _Adapter:
        def count_tokens(self, request):
            return 172_000
    prompt = H._prompt_of_tokens(185_000)          # heuristic 185K > probed 180K
    code, dispatched, cap = H._run(prompt, adapter=_Adapter())
    assert code == cheval.EXIT_CODES["SUCCESS"] and [d.model for d in dispatched] == ["claude-opus-5"], (
        f"exit={code} preflight={H._cap(cap).get('preflight_decision')} estimator={H._cap(cap).get('estimator')} "
        f"dispatched={[d.model for d in dispatched]} failed={H._classes(cap)} "
        f"msgs={[f.get('message_redacted') for f in cap.get('models_failed', [])]}")


# R2 — review Change 4: a shrinkable provider verdict on the FINAL attempt must stay typed
def test_r2_shrink_on_final_attempt_keeps_the_typed_error(monkeypatch):
    monkeypatch.setattr("loa_cheval.routing.circuit_breaker.check_state", lambda *a, **k: "CLOSED")
    monkeypatch.setattr(retry_mod, "_record_failure", lambda *a, **k: None)
    monkeypatch.setattr(retry_mod, "_record_success", lambda *a, **k: None)

    class _A:
        provider = "anthropic"; auth_type = "http_api"
        def __init__(self): self.seen = []
        def complete(self, request):
            self.seen.append(request.max_tokens)
            raise ProviderContextLimitError("anthropic", "HTTP 400 context-limit: input length and max_tokens exceed "
                                            "context limit: 190000 + 64000 > 200000", status=400,
                                            input_tokens=190_000, max_tokens=64_000, limit=200_000)
    a = _A()
    with pytest.raises(ProviderContextLimitError):
        try:
            retry_mod.invoke_with_retry(a, CompletionRequest(messages=[{"role": "user", "content": "x"}], model="m",
                                                             max_tokens=64_000),
                                        {"retry": {"max_retries": 0, "base_delay_seconds": 0}})
        except RetriesExhaustedError as e:
            pytest.fail(f"degraded to RetriesExhaustedError({e}); attempts seen={a.seen}")


# R3 — review Change 3: the unverified flag must be per hop, not inherited from the head
def test_r3_unverified_is_per_hop(monkeypatch):
    monkeypatch.setenv("LOA_CHEVAL_UNCALIBRATED_CEILING", "derived")
    head = H._entry(chain=["anthropic:claude-opus-4-8"])
    cal = {"source": "empirical_probe", "calibrated_at": "2026-10-01T00:00:00Z", "stale_after_days": 90}
    cfg = H._config(head=head)
    cfg["providers"]["anthropic"]["models"]["claude-opus-4-8"] = H._entry(ceiling=700_000, cal=cal)  # calibrated fallback
    code, dispatched, cap = H._run(H.SIX, config=cfg, errors=[ProviderUnavailableError("anthropic", "503"),
                                                             RateLimitError("anthropic")])
    classes = H._classes(cap)
    assert "RATE_LIMIT_UNVERIFIED" not in classes, (
        f"calibrated fallback hop classed as unverified: classes={classes} exit={code} "
        f"store={[(r['model'], r['error_class']) for r in H.load_observed(H.observed_store_path())['entries']]}")


# R4 — review Change 5: the long-context threshold must count cache tokens (provider rule: prompt length)
def test_r4_premium_threshold_counts_cache_tokens():
    p = PricingEntry(provider="anthropic", model="claude-opus-5", input_per_mtok=5_000_000, output_per_mtok=25_000_000,
                     **_long_context_fields({"threshold_tokens": 200_000, "input_multiplier": 2.0, "output_multiplier": 1.5}))
    b = calculate_total_cost(100_000, 1_000, 0, p, cache_read_tokens=150_000)
    assert b.long_context_applied, f"250K prompt billed at base rates: {b}"


# R5 — audit SEC: one provider/proxy error body becomes a persistent (tiny) bound → every later call preempted
def test_r5_observed_store_has_no_plausibility_floor():
    poison = ProviderContextLimitError("anthropic", "HTTP 400 context-limit: prompt is too long: 5 tokens > 1 maximum",
                                       status=400, input_tokens=5, limit=1)
    code, dispatched, cap = H._run(H._prompt_of_tokens(1_000), errors=[poison])
    assert code == cheval.EXIT_CODES["CONTEXT_TOO_LARGE"]
    obs = observed_for("anthropic", "claude-opus-5")
    code2, dispatched2, cap2 = H._run(H._prompt_of_tokens(1_000))
    assert dispatched2, f"self-DoS: observed={obs} bound={H._cap(cap2).get('input_ceiling')} exit={code2}"


# R6 — audit: `verified: false` is not consulted; inf multiplier accepted
def test_r6_long_context_block_validation():
    f = _long_context_fields({"threshold_tokens": 200_000, "input_multiplier": 2.0, "output_multiplier": 1.5, "verified": False})
    assert f == {}, f"unverified reference tier is billed: {f}"


def test_r6b_inf_multiplier_rejected():
    f = _long_context_fields({"threshold_tokens": 200_000, "input_multiplier": float("inf")})
    p = PricingEntry(provider="anthropic", model="m", input_per_mtok=5_000_000, output_per_mtok=25_000_000, **f)
    try:
        calculate_total_cost(300_000, 10, 0, p)
    except OverflowError as e:
        pytest.fail(f"ledger would crash after the billed call: {e}")
