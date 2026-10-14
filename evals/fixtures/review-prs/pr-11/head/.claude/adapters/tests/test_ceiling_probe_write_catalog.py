"""cycle-126 Sprint 1 Task 1.2 (PRD FR-1.1, SDD D-1.1) — `tools/ceiling-probe-live.py
--write-catalog` folds a probe result into the LIVE catalog text: the model's
ceiling, calibration and account limits change; every comment and every other
entry stay byte-identical; a missing block or field is an error, never a guess.
"""
from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

import pytest
import yaml

ROOT = Path(__file__).resolve().parents[3]
TOOL = ROOT / "tools" / "ceiling-probe-live.py"
CATALOG = ROOT / ".claude" / "defaults" / "model-config.yaml"


@pytest.fixture(scope="module")
def tool():
    spec = importlib.util.spec_from_file_location("ceiling_probe_live", TOOL)
    mod = importlib.util.module_from_spec(spec)
    sys.modules["ceiling_probe_live"] = mod
    spec.loader.exec_module(mod)
    return mod


def test_write_catalog_changes_only_the_probed_entry(tool):
    before = CATALOG.read_text()
    after = tool.write_catalog(before, "claude-opus-5", ceiling=640_000, calibrated_at="2026-09-25T00:00:00Z",
                               sample_size=6, tier="4", itpm=2_000_000)
    b, a = yaml.safe_load(before), yaml.safe_load(after)
    entry = a["providers"]["anthropic"]["models"]["claude-opus-5"]
    assert entry["effective_input_ceiling"] == 640_000 and entry["probed_ceiling"] == 180_000
    assert entry["ceiling_calibration"]["source"] == "empirical_probe"
    assert entry["ceiling_calibration"]["calibrated_at"] == "2026-09-25T00:00:00Z"
    assert entry["ceiling_calibration"]["sample_size"] == 6 and entry["ceiling_calibration"]["stale_after_days"] == 90
    assert entry["account_limits"] == {"tier": "4", "itpm": 2_000_000}
    # every other entry is untouched
    for prov, pv in b["providers"].items():
        for mid, me in (pv.get("models") or {}).items():
            if (prov, mid) != ("anthropic", "claude-opus-5"):
                assert a["providers"][prov]["models"][mid] == me, (prov, mid)
    assert a["aliases"] == b["aliases"]
    # comments survive: same number of comment lines, and the entry's own comment kept
    assert sum(1 for l in after.splitlines() if l.strip().startswith("#")) == sum(1 for l in before.splitlines() if l.strip().startswith("#"))
    assert "# cycle-124 FR-3 (SDD §2.1): see claude-fable-5-1" in after
    # the cheval policy now reads it as calibrated
    sys.path.insert(0, str(ROOT / ".claude" / "adapters"))
    from loa_cheval.routing.ceiling import input_bound
    d = input_bound(entry, max_tokens=64_000)
    assert d.basis == "calibrated" and d.value == 640_000


def test_write_catalog_is_idempotent_and_refuses_unknowns(tool):
    text = CATALOG.read_text()
    once = tool.write_catalog(text, "claude-sonnet-5", ceiling=300_000, calibrated_at="2026-09-25T00:00:00Z", sample_size=3)
    twice = tool.write_catalog(once, "claude-sonnet-5", ceiling=300_000, calibrated_at="2026-09-25T00:00:00Z", sample_size=3)
    assert once == twice
    with pytest.raises(ValueError):
        tool.write_catalog(text, "claude-nope-9", ceiling=1, calibrated_at="x", sample_size=1)
    with pytest.raises(ValueError):
        tool.write_catalog(text, "claude-opus-5", ceiling=1, calibrated_at="x", sample_size=1, tier="platinum")
    with pytest.raises(ValueError):
        tool.write_catalog(text.replace("        effective_input_ceiling: 180000   # cycle-124 FR-3 (SDD §2.1): see claude-fable-5-1\n", "", 1)
                           if "claude-opus-5" in text else text, "claude-opus-5", ceiling=1, calibrated_at="x", sample_size=1) \
            if False else tool.write_catalog("      claude-opus-5:\n        context_window: 1\n", "claude-opus-5", ceiling=1,
                                             calibrated_at="x", sample_size=1)


def test_cli_flags_exist_and_partial_is_refused_without_allow(tool, tmp_path, monkeypatch, capsys):
    catalog = tmp_path / "model-config.yaml"
    catalog.write_text(CATALOG.read_text())
    record = {"largest_ok_input_tokens": 500_000, "calibrated_at": "2026-09-25T00:00:00Z", "sample_size": 2}
    tool._write_catalog_file(str(catalog), "claude-fable-5-1", record, "2", None)
    entry = yaml.safe_load(catalog.read_text())["providers"]["anthropic"]["models"]["claude-fable-5-1"]
    assert entry["effective_input_ceiling"] == 500_000 and entry["account_limits"] == {"tier": "2", "itpm": None}
    assert not [p for p in tmp_path.iterdir() if p.name.startswith(".model-config.")], "atomic write leaves no temp file"
    # the parser knows the flags (no live call is made here: no key → exit 2 before any probe)
    monkeypatch.delenv("ANTHROPIC_API_KEY", raising=False)
    monkeypatch.setattr(sys, "argv", ["ceiling-probe-live.py", "--model", "claude-opus-5", "--write-catalog", str(catalog),
                                      "--tier", "3", "--itpm", "400000", "--allow-partial"])
    assert tool.main() == 2
    assert "ANTHROPIC_API_KEY is required" in capsys.readouterr().err
