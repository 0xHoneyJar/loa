"""cycle-127 sprint-251 audit round r251-4 — routing/ceiling.py.

S6 (audit run-2 n5): a 429 / 529 counts as a throttle status only as a whole token — never inside a request id
(`req_a529fz…`) — while "API Error: 429. Too many tokens" stays a throttle.
S6 (audit run-2 n6): a bare "N tokens (limit M)" with no marker word is not a context limit; the CLI's own sentence shape
("the request is ~N tokens (limit M)") still is.
S7 (audit run-2 n38): an observation below a plausibility floor (< 0.1 × context_window) or above the window is ignored —
a stray `observed_input_tokens: 1` row must not wedge the route — and said once.
"""

from __future__ import annotations

import logging
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from loa_cheval.routing import ceiling  # noqa: E402
from loa_cheval.routing.ceiling import (  # noqa: E402
    input_bound, is_context_limit_message, is_throttle_message, observed_for, parse_context_limit,
)


# --- S6 n5: the throttle status is a whole token -----------------------------------------------------------------

@pytest.mark.parametrize("msg,want", [
    ("request req_a529fz01 failed: prompt is too long", False),
    ("request id req_011CX429ab: the request is ~1065182 tokens (limit 1000000)", False),
    ("trace 0x529f: Prompt is too long", False),
    ("error_529x: something", False),
    ("API Error: 429. Too many tokens, please wait before trying again", True),
    ("API Error: 429 Too Many Requests", True),
    ('{"status":529,"type":"overloaded"}', True),
    ("HTTP 529", True),
    ("status=429", True),
    ("(429)", True),
    ("1,429,000 tokens > 1,000,000 maximum", False),
    ("the request is ~429 tokens (limit 400)", False),
])
def test_s6_the_throttle_status_is_a_whole_token(msg, want):
    assert is_throttle_message(msg) is want, msg


# --- S6 n6: a context limit needs a marker word or the CLI's own sentence -----------------------------------------

@pytest.mark.parametrize("msg,want", [
    ("processed 12 tokens (limit 100) of the batch", False),
    ("batch 3: ~500 tokens (limit: 1000) remaining", False),
    ("the request is ~1065182 tokens (limit 1000000)", True),
    ("API Error: the request is ~1052900 tokens (limit 1000000) but the model's context window is exceeded", True),
    ("request is 1,065,182 tokens (limit 1,000,000)", True),
    ("Prompt is too long · the request is ~1065182 tokens (limit 1000000) but …", True),
    ("prompt is too long: 1065182 tokens > 1000000 maximum", True),
    ("input length and `max_tokens` exceed context limit: 950000 + 64000 > 1000000", True),
])
def test_s6_a_context_limit_needs_a_marker_or_the_cli_sentence(msg, want):
    assert is_context_limit_message(msg) is want, msg


def test_s6_the_numbers_still_parse_from_the_cli_shape():
    assert parse_context_limit("~990000 tokens (limit: 1000000)")["limit"] == 1_000_000


# --- S7 n38: an implausible observation never wedges the route ------------------------------------------------------

_ENTRY = {"context_window": 1_000_000, "effective_input_ceiling": 900_000, "probed_ceiling": 900_000}


@pytest.fixture(autouse=True)
def _fresh(monkeypatch):
    monkeypatch.setattr(ceiling, "_IMPLAUSIBLE_OBSERVED_WARNED", False, raising=False)


def _rows(*obs):
    return {"version": 1, "entries": [
        {"provider": "anthropic", "model": "m", "error_class": "PROVIDER_CONTEXT_LIMIT", "observed_input_tokens": o}
        for o in obs]}


def test_s7_a_stray_tiny_observation_is_ignored_by_input_bound_and_warned_once(caplog):
    with caplog.at_level(logging.WARNING):
        for _ in range(3):
            d = input_bound(_ENTRY, max_tokens=64_000, observed=1, policy="probed")
            assert d.value == 900_000 and d.basis == "probed", d
    warns = [r.getMessage() for r in caplog.records if "implausible" in r.getMessage()]
    assert len(warns) == 1, [r.getMessage() for r in caplog.records]


def test_s7_an_observation_above_the_window_is_ignored():
    d = input_bound(_ENTRY, max_tokens=64_000, observed=2_000_000, policy="probed")
    assert d.value == 900_000 and d.basis == "probed", d


def test_s7_a_plausible_observation_still_tightens():
    d = input_bound(_ENTRY, max_tokens=64_000, observed=500_000, policy="probed")
    assert d.value == 499_999 and d.basis == "observed", d


def test_s7_observed_for_skips_implausible_rows_so_they_never_mask_a_real_one():
    data = _rows(1, 500_000, 5_000_000)
    assert observed_for("anthropic", "m", data, context_window=1_000_000) == 500_000
    assert observed_for("anthropic", "m", _rows(1), context_window=1_000_000) is None
    # without a window there is nothing to judge plausibility against: unchanged
    assert observed_for("anthropic", "m", data) == 1


def test_s7_cheval_passes_the_window_to_every_observed_for_call():
    src = (Path(__file__).resolve().parent.parent / "cheval.py").read_text()
    import re
    calls = re.findall(r"_observed_for\(([^)]*)\)", src)
    assert calls, "no _observed_for call found"
    for c in calls:
        assert "context_window" in c, c


# --- S6 n4 (verifier E run 2): the printed probe command quotes the model id -----------------------------------------

def test_s6_the_calibrate_hint_quotes_a_hostile_model_id():
    import shlex
    from types import SimpleNamespace
    import cheval
    hostile = "x; touch /tmp/pwned $(id)"
    http = SimpleNamespace(model_id=hostile, provider="anthropic", adapter_kind="http")
    hint = cheval._calibrate_hint(http, [http])
    argv = shlex.split(hint)
    assert argv[argv.index("--model") + 1] == hostile, hint
    cli = SimpleNamespace(model_id="claude-headless", provider="anthropic", adapter_kind="cli")
    argv = shlex.split(cheval._calibrate_hint(cli, [http, cli]))
    assert argv[argv.index("--model") + 1] == hostile and argv[-2:] == ["--transport", "claude-headless"], argv
    # a plain id prints as before (no quotes)
    plain = SimpleNamespace(model_id="claude-opus-5-5", provider="anthropic", adapter_kind="http")
    assert "'" not in cheval._calibrate_hint(plain, [plain])
