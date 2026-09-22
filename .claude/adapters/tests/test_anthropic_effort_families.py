"""cycle-124 Sprint 1 Task 1.4 (FR-2 / SDD §3.2) — per-family effort emission.

`output_config.effort` exists on Opus 4.5+ / Sonnet 4.6+ / Fable; the 4.6
generation rejects `xhigh` (downgraded to `high`); the Sonnet 4.5 snapshot and
Haiku 4.5 predate the control, so the field is omitted rather than 400ing.
Same body-capture seam as test_anthropic_effort.py (non-streaming forced).
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from loa_cheval.providers.anthropic_adapter import (  # noqa: E402
    AnthropicAdapter,
    _effort_for_model,
)
from loa_cheval.types import CompletionRequest, ModelConfig, ProviderConfig  # noqa: E402

MODELS = [
    "claude-fable-5-1",
    "claude-fable-5",
    "claude-opus-5",
    "claude-opus-4-8",
    "claude-opus-4-7",
    "claude-opus-4-6",
    "claude-sonnet-5",
    "claude-sonnet-4-6",
    "claude-sonnet-4-5-20250929",
    "claude-haiku-4-5-20251001",
]


def _make_config() -> ProviderConfig:
    return ProviderConfig(
        name="anthropic",
        type="anthropic",
        endpoint="https://api.anthropic.com/v1",
        auth="sk-ant-test",
        connect_timeout=10.0,
        read_timeout=30.0,
        models={
            m: ModelConfig(capabilities=["chat"], context_window=1_000_000,
                           params={"temperature_supported": False})
            for m in MODELS
        },
    )


def _capture_body(monkeypatch, request: CompletionRequest) -> dict:
    monkeypatch.setenv("LOA_CHEVAL_DISABLE_STREAMING", "1")
    adapter = AnthropicAdapter(_make_config())
    captured: dict = {}

    def _fake_ns(url, headers, body):
        captured["body"] = body
        return "sentinel-result"

    monkeypatch.setattr(adapter, "_complete_nonstreaming", _fake_ns)
    adapter.complete(request)
    return captured["body"]


def _req(model: str, effort: str | None) -> CompletionRequest:
    return CompletionRequest(
        messages=[{"role": "user", "content": "hi"}],
        model=model,
        max_tokens=1024,
        effort=effort,
    )


@pytest.mark.parametrize("model", [
    "claude-fable-5-1", "claude-fable-5", "claude-opus-5", "claude-opus-4-8",
    "claude-opus-4-7", "claude-sonnet-5",
])
@pytest.mark.parametrize("effort", ["low", "medium", "high", "xhigh", "max"])
def test_current_generation_passes_effort_through(monkeypatch, model, effort):
    body = _capture_body(monkeypatch, _req(model, effort))
    assert body["output_config"] == {"effort": effort}


@pytest.mark.parametrize("model", ["claude-opus-4-6", "claude-sonnet-4-6"])
def test_4_6_generation_downgrades_xhigh_to_high(monkeypatch, model, caplog):
    body = _capture_body(monkeypatch, _req(model, "xhigh"))
    assert body["output_config"] == {"effort": "high"}
    assert any("downgraded to high" in r.getMessage() for r in caplog.records)


@pytest.mark.parametrize("model", ["claude-opus-4-6", "claude-sonnet-4-6"])
@pytest.mark.parametrize("effort", ["low", "medium", "high", "max"])
def test_4_6_generation_passes_other_levels(monkeypatch, model, effort):
    body = _capture_body(monkeypatch, _req(model, effort))
    assert body["output_config"] == {"effort": effort}


@pytest.mark.parametrize("model", ["claude-sonnet-4-5-20250929", "claude-haiku-4-5-20251001"])
@pytest.mark.parametrize("effort", ["low", "xhigh", "max"])
def test_pre_effort_models_omit_the_field(monkeypatch, model, effort):
    body = _capture_body(monkeypatch, _req(model, effort))
    assert "output_config" not in body


@pytest.mark.parametrize("model", MODELS)
def test_unset_effort_keeps_body_shape(monkeypatch, model):
    body = _capture_body(monkeypatch, _req(model, None))
    assert "output_config" not in body


def test_every_catalog_http_id_is_classified_by_exactly_one_effort_tuple():
    """Falsifiable totality (review round-1 low 3): a new Anthropic id must be
    placed in exactly one of the three prefix tuples — the pass-through default
    in `_effort_for_model` no longer counts as classification."""
    import yaml
    from loa_cheval.providers.anthropic_adapter import (
        _EFFORT_FULL_PREFIXES, _EFFORT_NO_XHIGH_PREFIXES, _EFFORT_UNSUPPORTED_PREFIXES,
    )
    catalog = ROOT.parents[1] / ".claude" / "defaults" / "model-config.yaml"
    with catalog.open() as fh:
        models = yaml.safe_load(fh)["providers"]["anthropic"]["models"]
    tables = (_EFFORT_UNSUPPORTED_PREFIXES, _EFFORT_NO_XHIGH_PREFIXES, _EFFORT_FULL_PREFIXES)
    for model_id, entry in models.items():
        if entry.get("auth_type") != "http_api":
            continue
        hits = [p for table in tables for p in table if model_id.startswith(p)]
        assert len(hits) == 1, (model_id, hits)
    # The FULL tuple is behaviour, not decoration: each member passes xhigh through.
    for prefix in _EFFORT_FULL_PREFIXES:
        assert _effort_for_model(prefix, "xhigh") == "xhigh", prefix


def test_effort_for_model_expected_table_over_the_catalog():
    """Every Anthropic HTTP id in the live catalog resolves to the EXPECTED
    per-family value (audit slice D: the previous form accepted any level and
    could not fail)."""
    import yaml
    from loa_cheval.providers.anthropic_adapter import _EFFORT_NO_XHIGH_PREFIXES, _EFFORT_UNSUPPORTED_PREFIXES
    catalog = ROOT.parents[1] / ".claude" / "defaults" / "model-config.yaml"
    with catalog.open() as fh:
        models = yaml.safe_load(fh)["providers"]["anthropic"]["models"]
    for model_id, entry in models.items():
        if entry.get("auth_type") != "http_api":
            continue
        for effort in ("low", "medium", "high", "xhigh", "max"):
            out = _effort_for_model(model_id, effort)
            if model_id.startswith(_EFFORT_UNSUPPORTED_PREFIXES):
                expected = None
            elif model_id.startswith(_EFFORT_NO_XHIGH_PREFIXES):
                expected = "high" if effort == "xhigh" else effort
            else:
                expected = effort
            assert out == expected, (model_id, effort, out, expected)
