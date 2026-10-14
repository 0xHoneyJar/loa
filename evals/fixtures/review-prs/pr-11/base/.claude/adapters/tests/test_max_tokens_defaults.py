"""cycle-124 Sprint 1 Task 1.4 (FR-2 / SDD §2.2, §3.2) — per-hop output budgets.

- `default_max_tokens()` : Anthropic min(64K streaming | 16K non-streaming,
  catalog max_output_tokens); 4096 when the entry declares no max_output,
  for every other provider, and under LOA_CHEVAL_LEGACY_WIRE.
- `_lookup_max_output_tokens()` / `_hop_max_tokens()` over the LIVE catalog:
  explicit values are clamped, 0 is refused at the CLI as INVALID_INPUT,
  `--effort` is validated by argparse and surfaces in `--dry-run`.
- Cost exposure of the new default at the new pricing is pinned as a table
  (the "per-call cost-ceiling" test): a 64K worst case on the priciest entry
  stays under $3.20, and the bounded dispatchers' 16K under $0.80.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

import pytest
import yaml

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from cheval import _hop_max_tokens, _lookup_max_output_tokens  # noqa: E402
from loa_cheval.metering.pricing import calculate_cost_micro  # noqa: E402
from loa_cheval.providers.base import (  # noqa: E402
    _LEGACY_DEFAULT_MAX_TOKENS,
    _legacy_wire,
    default_max_tokens,
)

REPO_ROOT = ROOT.parents[1]
CATALOG = REPO_ROOT / ".claude" / "defaults" / "model-config.yaml"
CHEVAL = ROOT / "cheval.py"


@pytest.fixture(scope="module")
def catalog() -> dict:
    with CATALOG.open() as fh:
        return yaml.safe_load(fh)


@pytest.fixture(autouse=True)
def _clean_switches(monkeypatch):
    monkeypatch.delenv("LOA_CHEVAL_DISABLE_STREAMING", raising=False)
    monkeypatch.delenv("LOA_CHEVAL_LEGACY_WIRE", raising=False)


# --- default_max_tokens ------------------------------------------------------

def test_anthropic_streaming_default_is_64k_clamped_to_catalog():
    assert default_max_tokens(provider="anthropic", model_max_output=128_000) == 64_000
    assert default_max_tokens(provider="anthropic", model_max_output=32_000) == 32_000
    assert default_max_tokens(provider="anthropic", model_max_output=64_000) == 64_000


def test_anthropic_non_streaming_default_is_16k(monkeypatch):
    monkeypatch.setenv("LOA_CHEVAL_DISABLE_STREAMING", "1")
    assert default_max_tokens(provider="anthropic", model_max_output=128_000) == 16_000
    assert default_max_tokens(provider="anthropic", model_max_output=8_000) == 8_000


@pytest.mark.parametrize("bad", [None, 0, -1, True, "128000"])
def test_anthropic_without_usable_max_output_keeps_4096(bad):
    assert default_max_tokens(provider="anthropic", model_max_output=bad) == _LEGACY_DEFAULT_MAX_TOKENS


@pytest.mark.parametrize("provider", ["openai", "google", "bedrock", "xai", "cursor", ""])
def test_other_providers_keep_4096_regardless_of_catalog(provider):
    assert default_max_tokens(provider=provider, model_max_output=128_000) == 4096


@pytest.mark.parametrize("value", ["1", "true", "YES", " on "])
def test_legacy_wire_restores_4096_on_anthropic(monkeypatch, value):
    monkeypatch.setenv("LOA_CHEVAL_LEGACY_WIRE", value)
    assert _legacy_wire() is True
    assert default_max_tokens(provider="anthropic", model_max_output=128_000) == 4096


@pytest.mark.parametrize("value", ["", "0", "false", "off", "no"])
def test_legacy_wire_off_values(monkeypatch, value):
    monkeypatch.setenv("LOA_CHEVAL_LEGACY_WIRE", value)
    assert _legacy_wire() is False


# --- catalog lookups + per-hop resolution -----------------------------------

def test_lookup_max_output_over_live_catalog(catalog):
    assert _lookup_max_output_tokens("anthropic", "claude-opus-5", catalog) == 128_000
    assert _lookup_max_output_tokens("anthropic", "claude-fable-5-1", catalog) == 128_000
    assert _lookup_max_output_tokens("anthropic", "claude-haiku-4-5-20251001", catalog) is None
    assert _lookup_max_output_tokens("anthropic", "claude-headless", catalog) is None
    assert _lookup_max_output_tokens("openai", "gpt-5.5", catalog) == 32_000
    assert _lookup_max_output_tokens("ghost", "nope", catalog) is None
    assert _lookup_max_output_tokens("anthropic", "nope", catalog) is None


def test_hop_defaults_follow_each_hop_not_the_primary(catalog, monkeypatch):
    assert _hop_max_tokens(None, "anthropic", "claude-opus-5", catalog) == 64_000
    assert _hop_max_tokens(None, "anthropic", "claude-haiku-4-5-20251001", catalog) == 4096
    assert _hop_max_tokens(None, "anthropic", "claude-headless", catalog) == 4096
    assert _hop_max_tokens(None, "openai", "gpt-5.5", catalog) == 4096
    monkeypatch.setenv("LOA_CHEVAL_DISABLE_STREAMING", "1")
    assert _hop_max_tokens(None, "anthropic", "claude-opus-5", catalog) == 16_000


def test_explicit_value_is_clamped_to_catalog_max_output(catalog, caplog):
    assert _hop_max_tokens(200_000, "anthropic", "claude-opus-5", catalog) == 128_000
    assert any("clamped" in r.getMessage() for r in caplog.records)
    assert _hop_max_tokens(8_000, "anthropic", "claude-opus-5", catalog) == 8_000
    # No catalog max_output ⇒ the explicit value passes through untouched.
    assert _hop_max_tokens(200_000, "anthropic", "claude-headless", catalog) == 200_000


def test_every_anthropic_http_default_fits_under_the_ceiling(catalog):
    """SDD §2.1: effective_input_ceiling + default_max_tokens(entry) ≤ context_window."""
    for model_id, entry in catalog["providers"]["anthropic"]["models"].items():
        if entry.get("auth_type") != "http_api":
            continue
        default = _hop_max_tokens(None, "anthropic", model_id, catalog)
        assert entry["effective_input_ceiling"] + default <= entry["context_window"], model_id


# --- CLI surface (argparse + dry-run) ----------------------------------------

def _cheval(*argv: str, env_extra: dict | None = None) -> subprocess.CompletedProcess:
    env = {k: v for k, v in os.environ.items() if k != "ANTHROPIC_API_KEY"}
    env.update(env_extra or {})
    return subprocess.run(
        [sys.executable, str(CHEVAL), *argv],
        capture_output=True, text=True, env=env, cwd=str(REPO_ROOT), timeout=120,
    )


def test_dry_run_reports_default_budget_and_effort():
    proc = _cheval("--agent", "reviewing-code", "--model", "opus", "--effort", "xhigh",
                   "--prompt", "x", "--dry-run", "--json-errors")
    assert proc.returncode == 0, proc.stderr
    out = json.loads(proc.stdout)
    assert out["resolved_model"] == "claude-opus-5"
    assert out["max_tokens"] == 64_000
    assert out["effort"] == "xhigh"


def test_dry_run_non_anthropic_stays_4096():
    proc = _cheval("--agent", "reviewing-code", "--model", "gpt-5.5", "--prompt", "x", "--dry-run")
    assert proc.returncode == 0, proc.stderr
    assert json.loads(proc.stdout)["max_tokens"] == 4096


def test_dry_run_explicit_value_is_clamped():
    proc = _cheval("--agent", "reviewing-code", "--model", "opus", "--max-tokens", "200000",
                   "--prompt", "x", "--dry-run")
    assert proc.returncode == 0, proc.stderr
    assert json.loads(proc.stdout)["max_tokens"] == 128_000


@pytest.mark.parametrize("value", ["0", "-5"])
def test_zero_or_negative_max_tokens_is_invalid_input(value):
    proc = _cheval("--agent", "reviewing-code", "--model", "opus", "--max-tokens", value,
                   "--prompt", "x", "--dry-run", "--json-errors")
    assert proc.returncode != 0
    assert '"INVALID_INPUT"' in proc.stderr, proc.stderr


def test_invalid_effort_is_rejected_by_argparse():
    proc = _cheval("--agent", "reviewing-code", "--model", "opus", "--effort", "ultra",
                   "--prompt", "x", "--dry-run")
    assert proc.returncode == 2
    assert "invalid choice" in proc.stderr


# --- cost exposure of the new default ("per-call cost-ceiling" table) -------

_WORST_CASE_DEFAULT_CEILING_MICRO = 3_200_000    # $3.20 — Fable at 64K × $50/MTok
_WORST_CASE_BOUNDED_CEILING_MICRO = 800_000      # $0.80 — Fable at 16K (dissent / flatline / BB)


def test_worst_case_output_cost_per_call_is_bounded(catalog):
    rows = []
    for model_id, entry in catalog["providers"]["anthropic"]["models"].items():
        if entry.get("auth_type") != "http_api":
            continue
        out_price = entry["pricing"]["output_per_mtok"]
        default = _hop_max_tokens(None, "anthropic", model_id, catalog)
        worst_default, _ = calculate_cost_micro(default, out_price)
        worst_bounded, _ = calculate_cost_micro(16_000, out_price)
        rows.append((model_id, default, worst_default, worst_bounded))
        assert worst_default <= _WORST_CASE_DEFAULT_CEILING_MICRO, (model_id, worst_default)
        assert worst_bounded <= _WORST_CASE_BOUNDED_CEILING_MICRO, (model_id, worst_bounded)
    # The table is printed so the sprint report can cite it verbatim.
    print("\n" + "\n".join(f"{m:32s} default={d:6d} worst_default_micro={wd:8d} worst_16k_micro={wb:7d}"
                           for m, d, wd, wb in rows))
    assert rows
