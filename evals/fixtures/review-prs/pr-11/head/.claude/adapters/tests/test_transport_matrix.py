"""cycle-126 Sprint 1 Task 1.1 (PRD FR-1.8, SDD D-1.8) — one table over
(provider) × (transport) and, through the real code paths with mocked
transports, what each row applies: the effective input ceiling, the output
default, the read timeout, the `anthropic-beta` header and the token-count
method. The Bridgebuilder generated table and the Flatline cap resolver are
asserted against the same catalog rows.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

import pytest
import yaml

ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parents[1]
sys.path.insert(0, str(ROOT))

import cheval  # noqa: E402
from loa_cheval.providers import anthropic_adapter as aa  # noqa: E402
from loa_cheval.providers.base import default_max_tokens  # noqa: E402
from loa_cheval.routing.ceiling import COUNT_NEAR_BOUND, GateEstimate, gate, input_bound  # noqa: E402

CATALOG = REPO / ".claude" / "defaults" / "model-config.yaml"
BB_TRUNCATION = REPO / ".claude" / "skills" / "bridgebuilder-review" / "resources" / "core" / "truncation.generated.ts"
MODEL_MAPS = REPO / ".claude" / "scripts" / "generated-model-maps.sh"
FLATLINE = REPO / ".claude" / "scripts" / "flatline-orchestrator.sh"

BB_OUTPUT_CAP = 32_000
FLATLINE_CAP = 64_000
ANTHROPIC_STREAM_CAP, ANTHROPIC_LEGACY_CAP, OTHER_CAP = 64_000, 16_000, 16_000

# (provider, model) per transport class. CLI hops carry no HTTP ceiling.
ROWS = [
    ("anthropic", "claude-fable-5-1", "http-stream"),
    ("anthropic", "claude-fable-5-1", "http-legacy"),
    ("anthropic", "claude-headless", "cli-hop"),
    ("openai", "gpt-5.5", "http-stream"),
    ("openai", "gpt-5.5", "http-legacy"),
    ("openai", "codex-headless", "cli-hop"),
    ("google", "gemini-3.1-pro-preview", "http-stream"),
    ("google", "gemini-3.1-pro-preview", "http-legacy"),
    ("google", "gemini-headless", "cli-hop"),
]


@pytest.fixture(scope="module")
def catalog():
    with CATALOG.open() as fh:
        return yaml.safe_load(fh)


@pytest.fixture(autouse=True)
def _clean(monkeypatch):
    for var in ("LOA_CHEVAL_DISABLE_STREAMING", "LOA_CHEVAL_LEGACY_WIRE", "LOA_CHEVAL_LEGACY_CEILING",
                "LOA_CHEVAL_UNCALIBRATED_CEILING", "LOA_CHEVAL_MAX_INPUT_TOKENS"):
        monkeypatch.delenv(var, raising=False)


def _entry(catalog, provider, model):
    return catalog["providers"][provider]["models"][model]


def _expected_output(provider, entry, transport):
    declared = entry.get("max_output_tokens")
    if not isinstance(declared, int):
        return 4096
    cap = (ANTHROPIC_LEGACY_CAP if transport == "http-legacy" else ANTHROPIC_STREAM_CAP) if provider == "anthropic" else OTHER_CAP
    return min(cap, declared)


@pytest.mark.parametrize("provider,model,transport", ROWS)
def test_row(catalog, monkeypatch, provider, model, transport):
    entry = _entry(catalog, provider, model)
    if transport == "http-legacy":
        monkeypatch.setenv("LOA_CHEVAL_DISABLE_STREAMING", "1")
    if transport == "cli-hop":
        assert entry.get("auth_type") == "headless"

    # output default follows the resolved entry (D-1.3)
    out = default_max_tokens(provider=provider, model_max_output=entry.get("max_output_tokens"))
    assert out == _expected_output(provider, entry, transport), (provider, model, transport, out)

    # effective input ceiling (D-1.1): policy bound; 36K wall on the Anthropic legacy transport; none for CLI hops
    threshold = cheval._lookup_max_input_tokens(provider, model, catalog, max_tokens=out)
    if transport == "cli-hop":
        assert input_bound(entry, max_tokens=out) is None
        if provider == "anthropic":
            assert threshold is None
    elif provider == "anthropic":
        bound = input_bound(entry, max_tokens=out)
        assert bound is not None and bound.value + out <= entry["context_window"]
        assert threshold == (min(bound.value, cheval._LEGACY_TRANSPORT_INPUT_WALL) if transport == "http-legacy" else bound.value)
    else:
        # the other providers carry no v3 ceiling (no bound from the policy module); openai keeps its v2
        # split fields as the walk-gate threshold, google has none (the adapter's window check is the line)
        assert input_bound(entry, max_tokens=out) is None
        assert threshold is None or (isinstance(threshold, int) and threshold > 0)
        if provider == "openai":
            assert threshold == (entry.get("legacy_max_input_tokens") if transport == "http-legacy" else entry.get("streaming_max_input_tokens"))

    # read timeout: the legacy (non-streaming) transport lengthens the read with the resolved budget
    # (25 tok/s, capped at 600 s); the streaming path never consults this helper
    if provider == "anthropic" and transport == "http-legacy":
        assert aa._nonstreaming_read_timeout(120.0, out) == min(600.0, max(120.0, out / 25.0))

    # anthropic-beta: only what the catalog declares, joined; never derived from a request
    if provider == "anthropic" and transport != "cli-hop":
        params = entry.get("params") or {}
        beta = aa._beta_header_value(params, model)
        declared = params.get("beta_headers") or []
        assert beta == (",".join(declared) if declared else None)

    # token-count method: an Anthropic HTTP row counts near the bound; everything else keeps the heuristic
    if provider == "anthropic" and transport != "cli-hop":
        bound = input_bound(entry, max_tokens=out).value
        calls = []
        near = gate(entry, estimate=GateEstimate(tokens=int(bound * COUNT_NEAR_BOUND) + 1), requested_max_tokens=out,
                    counter=lambda: calls.append(1) or bound - 1)
        assert calls == [1] and near.estimate.method == "count_tokens"
        far = gate(entry, estimate=GateEstimate(tokens=int(bound * 0.5)), requested_max_tokens=out, counter=lambda: calls.append(1) or 1)
        assert far.estimate.method != "count_tokens"
    elif transport == "cli-hop":
        assert gate(entry, estimate=GateEstimate(tokens=10), requested_max_tokens=out, counter=lambda: 1).estimate.method != "count_tokens"


def _bb_budgets():
    text = BB_TRUNCATION.read_text()
    return {m.group(1): (int(m.group(2)), int(m.group(3)))
            for m in re.finditer(r'"([^"]+)": \{ maxInput: (\d+), maxOutput: (\d+),', text)}


def _flatline_map():
    text = MODEL_MAPS.read_text()
    block = text.split("declare -A MODEL_MAX_OUTPUT=(", 1)[1].split(")", 1)[0]
    return {m.group(1): int(m.group(2)) for m in re.finditer(r'\["([^"]+)"\]="(\d+)"', block)}


def test_bridgebuilder_and_flatline_agree_with_the_same_rows(catalog):
    bb, fl = _bb_budgets(), _flatline_map()
    assert re.search(r"^FLATLINE_VOICE_MAX_TOKENS_CAP=64000$", FLATLINE.read_text(), re.M)
    for provider, model, transport in ROWS:
        entry = _entry(catalog, provider, model)
        declared = entry.get("max_output_tokens")
        # BB: the declared output capped at 32K; the provider default when undeclared
        assert model in bb, model
        if isinstance(declared, int):
            assert bb[model][1] == min(declared, BB_OUTPUT_CAP), (model, bb[model])
            assert fl.get(model) == declared, (model, fl.get(model))
            assert min(FLATLINE_CAP, fl[model]) == min(FLATLINE_CAP, declared)
        else:
            assert model not in fl, model
            assert bb[model][1] <= 8192
        # BB maxInput sits under cheval's bound with the 20K headroom for ceiling-bearing rows
        if isinstance(entry.get("effective_input_ceiling"), int):
            assert bb[model][0] == entry["effective_input_ceiling"] - 20_000, (model, bb[model])
