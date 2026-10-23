"""cycle-129 Sprint 3 Task 3.3 (PRD FR-7 AC-7.5, SDD D-7.6, DEC-0131) — catalog price provenance.

Invariant over the LIVE `.claude/defaults/model-config.yaml`: a model entry marked `open_weight: true` with a non-zero
price carries `price_source` (an `https://` URL, or a path under `docs/` that exists) and `price_date` (`YYYY-MM-DD`,
a real date, not in the future). No price is invented: this cycle adds no open-weight row, so today the invariant holds
vacuously and the fixture cases below prove the check itself fails when it should.

Also: the pricing module reads the provenance fields, marks a price whose `price_date` is older than 90 days as
`stale_catalog` (WARN, and the ledger row says so), and the `python3 -m loa_cheval.metering.pricing --alias` CLI the
dissent budget gate asks prints the catalog rates or `unknown`.
"""
from __future__ import annotations

import datetime as dt
import json
import logging
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Any, Dict, List

import pytest
import yaml

ADAPTERS = Path(__file__).resolve().parents[1]
REPO_ROOT = ADAPTERS.parents[1]
sys.path.insert(0, str(ADAPTERS))

from loa_cheval.metering import pricing as pricing_mod  # noqa: E402
from loa_cheval.metering.ledger import create_ledger_entry  # noqa: E402
from loa_cheval.metering.pricing import (  # noqa: E402
    STALE_PRICE_DAYS,
    find_pricing,
    lookup_alias,
    price_is_stale,
    pricing_source_for,
)

CATALOG = REPO_ROOT / ".claude" / "defaults" / "model-config.yaml"
_DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")


def provenance_violations(catalog: Dict[str, Any], repo_root: Path = REPO_ROOT,
                          today: dt.date | None = None) -> List[str]:
    """Every `providers.<p>.models.<m>` entry with `open_weight: true` and a non-zero price that lacks valid provenance."""
    today = today or dt.date.today()
    out: List[str] = []
    for prov, block in ((catalog.get("providers") or {}).items()):
        if not isinstance(block, dict):
            continue
        for mid, entry in ((block.get("models") or {}).items()):
            if not isinstance(entry, dict) or entry.get("open_weight") is not True:
                continue
            price = entry.get("pricing") or {}
            nonzero = any(isinstance(price.get(k), (int, float)) and not isinstance(price.get(k), bool) and price.get(k) > 0
                          for k in ("input_per_mtok", "output_per_mtok", "reasoning_per_mtok", "per_task_micro_usd"))
            if not nonzero:
                continue
            where = f"{prov}:{mid}"
            src = entry.get("price_source")
            if not isinstance(src, str) or not src.strip():
                out.append(f"{where}: open_weight with a non-zero price and no price_source")
            else:
                s = src.strip()
                if s.startswith("https://"):
                    if len(s) <= len("https://") or any(c.isspace() for c in s):
                        out.append(f"{where}: price_source is not a usable https URL")
                elif s.startswith("docs/") and ".." not in Path(s).parts:
                    if not (repo_root / s).is_file():
                        out.append(f"{where}: price_source {s} does not exist under docs/")
                else:
                    out.append(f"{where}: price_source must be an https:// URL or a path under docs/")
            date = entry.get("price_date")
            if isinstance(date, dt.date):
                date = date.isoformat()
            if not isinstance(date, str) or not _DATE_RE.match(date):
                out.append(f"{where}: open_weight with a non-zero price and no price_date (YYYY-MM-DD)")
            else:
                try:
                    d = dt.date.fromisoformat(date)
                except ValueError:
                    out.append(f"{where}: price_date {date} is not a real date")
                else:
                    if d > today:
                        out.append(f"{where}: price_date {date} is in the future")
    return out


@pytest.fixture(scope="module")
def live_catalog() -> Dict[str, Any]:
    with CATALOG.open() as fh:
        return yaml.safe_load(fh)


def _fixture_catalog(entry: Dict[str, Any]) -> Dict[str, Any]:
    return {"providers": {"local": {"type": "openai_compat", "models": {"qwen-x": entry}}},
            "aliases": {"qwen": "local:qwen-x"}}


# --- the invariant over the live catalog ------------------------------------------------------------------------------

def test_live_catalog_open_weight_prices_carry_provenance(live_catalog):
    assert provenance_violations(live_catalog) == []


def test_live_catalog_provenance_fields_are_well_typed(live_catalog):
    """Any entry that does carry the fields (open-weight or not) carries them in the documented shape."""
    bad = []
    for prov, block in (live_catalog.get("providers") or {}).items():
        for mid, entry in ((block or {}).get("models") or {}).items():
            if not isinstance(entry, dict):
                continue
            if "open_weight" in entry and not isinstance(entry["open_weight"], bool):
                bad.append(f"{prov}:{mid} open_weight")
            d = entry.get("price_date")
            if d is not None and not (isinstance(d, dt.date) or (isinstance(d, str) and _DATE_RE.match(d))):
                bad.append(f"{prov}:{mid} price_date")
    assert bad == []


# --- the check itself fails when it should ----------------------------------------------------------------------------

PRICED = {"pricing": {"input_per_mtok": 200000, "output_per_mtok": 600000}}


def test_open_weight_nonzero_price_without_provenance_fails():
    v = provenance_violations(_fixture_catalog({"open_weight": True, **PRICED}))
    assert any("no price_source" in x for x in v)
    assert any("no price_date" in x for x in v)


def test_open_weight_nonzero_price_with_url_and_date_passes():
    entry = {"open_weight": True, "price_source": "https://example.com/pricing", "price_date": "2026-10-01", **PRICED}
    assert provenance_violations(_fixture_catalog(entry), today=dt.date(2026, 10, 14)) == []


def test_docs_path_must_exist_and_stay_under_docs(tmp_path):
    (tmp_path / "docs").mkdir()
    (tmp_path / "docs" / "prices.md").write_text("x\n")
    ok = {"open_weight": True, "price_source": "docs/prices.md", "price_date": "2026-10-01", **PRICED}
    assert provenance_violations(_fixture_catalog(ok), repo_root=tmp_path, today=dt.date(2026, 10, 14)) == []
    missing = dict(ok, price_source="docs/none.md")
    assert any("does not exist" in x for x in provenance_violations(_fixture_catalog(missing), repo_root=tmp_path))
    escape = dict(ok, price_source="docs/../secrets.md")
    assert any("https:// URL or a path under docs/" in x
               for x in provenance_violations(_fixture_catalog(escape), repo_root=tmp_path))
    http = dict(ok, price_source="http://example.com/p")
    assert any("https:// URL or a path under docs/" in x for x in provenance_violations(_fixture_catalog(http)))


def test_bad_or_future_price_date_fails():
    base = {"open_weight": True, "price_source": "https://example.com/p", **PRICED}
    assert any("no price_date" in x for x in provenance_violations(_fixture_catalog(dict(base, price_date="14/10/2026"))))
    assert any("not a real date" in x for x in provenance_violations(_fixture_catalog(dict(base, price_date="2026-02-30"))))
    assert any("in the future" in x for x in provenance_violations(
        _fixture_catalog(dict(base, price_date="2026-11-01")), today=dt.date(2026, 10, 14)))


def test_zero_priced_open_weight_entry_needs_no_provenance():
    entry = {"open_weight": True, "pricing": {"input_per_mtok": 0, "output_per_mtok": 0}}
    assert provenance_violations(_fixture_catalog(entry)) == []


def test_non_open_weight_entry_is_not_checked():
    assert provenance_violations(_fixture_catalog(dict(PRICED))) == []


# --- the pricing module: provenance read, freshness WARN, ledger source -----------------------------------------------

def test_find_pricing_reads_the_provenance_fields():
    cfg = _fixture_catalog({"open_weight": True, "price_source": "https://example.com/p", "price_date": "2026-10-01",
                            **PRICED})
    entry = find_pricing("local", "qwen-x", cfg)
    assert entry is not None
    assert entry.open_weight is True
    assert entry.price_source == "https://example.com/p"
    assert entry.price_date == "2026-10-01"


def test_yaml_date_is_read_as_iso_string():
    cfg = yaml.safe_load("providers:\n  local:\n    models:\n      qwen-x:\n        price_date: 2026-10-01\n"
                         "        pricing: {input_per_mtok: 1, output_per_mtok: 1}\n")
    assert find_pricing("local", "qwen-x", cfg).price_date == "2026-10-01"


def test_stale_price_is_marked_and_warned(caplog):
    today = dt.date(2026, 10, 14)
    fresh = find_pricing("local", "qwen-x", _fixture_catalog(dict(PRICED, price_date=(
        today - dt.timedelta(days=STALE_PRICE_DAYS)).isoformat())))
    stale = find_pricing("local", "qwen-x", _fixture_catalog(dict(PRICED, price_date=(
        today - dt.timedelta(days=STALE_PRICE_DAYS + 1)).isoformat())))
    assert not price_is_stale(fresh, today)
    assert pricing_source_for(fresh, today) == "config"
    pricing_mod._STALE_WARNED.clear()
    with caplog.at_level(logging.WARNING, logger="loa_cheval.metering.pricing"):
        assert pricing_source_for(stale, today) == "stale_catalog"
        assert pricing_source_for(stale, today) == "stale_catalog"
    warns = [r for r in caplog.records if "stale_catalog" in r.getMessage()]
    assert len(warns) == 1   # once per entry per process
    assert pricing_source_for(None) == "unknown"


def test_entry_without_price_date_is_never_stale():
    entry = find_pricing("local", "qwen-x", _fixture_catalog(dict(PRICED)))
    assert not price_is_stale(entry, dt.date(2099, 1, 1))
    assert pricing_source_for(entry) == "config"


def test_ledger_row_records_stale_catalog():
    cfg = _fixture_catalog(dict(PRICED, price_date="2000-01-01"))
    row = create_ledger_entry(trace_id="t", agent="a", provider="local", model="qwen-x", input_tokens=1000,
                              output_tokens=10, reasoning_tokens=0, latency_ms=1, config=cfg)
    assert row["pricing_source"] == "stale_catalog"
    assert row["cost_micro_usd"] > 0
    assert row["pricing_resolution"] == "exact"


def test_ledger_row_without_provenance_is_config():
    row = create_ledger_entry(trace_id="t", agent="a", provider="local", model="qwen-x", input_tokens=1000,
                              output_tokens=10, reasoning_tokens=0, latency_ms=1, config=_fixture_catalog(dict(PRICED)))
    assert row["pricing_source"] == "config"


# --- the price lookup CLI ---------------------------------------------------------------------------------------------

def _cli(tmp_path: Path, *args: str, catalog: Dict[str, Any] | None = None, project: str | None = None):
    cat = tmp_path / "model-config.yaml"
    cat.write_text(yaml.safe_dump(catalog if catalog is not None else {
        "providers": {
            "openai": {"models": {"gpt-x": {"pricing": {"input_per_mtok": 5000000, "output_per_mtok": 30000000}}}},
            "local": {"models": {"free-x": {"pricing": {"input_per_mtok": 0, "output_per_mtok": 0}}}},
        },
        "aliases": {"gx": "openai:gpt-x", "free": "local:free-x"},
    }))
    conf = tmp_path / "loa.config.yaml"
    conf.write_text(project or "{}\n")
    env = dict(os.environ, PYTHONPATH=str(ADAPTERS), PYTHONSAFEPATH="1")
    return subprocess.run([sys.executable, "-W", "ignore::RuntimeWarning", "-m", "loa_cheval.metering.pricing",
                           "--catalog", str(cat), "--config", str(conf), *args],
                          capture_output=True, text=True, env=env, cwd=str(tmp_path), timeout=60)


def test_cli_prints_catalog_rates(tmp_path):
    r = _cli(tmp_path, "--alias", "gx")
    assert r.returncode == 0, r.stderr
    assert r.stdout.strip() == "alias=gx input_per_mtok=5000000 output_per_mtok=30000000 pricing_source=config"


def test_cli_json_unknown_and_zero(tmp_path):
    r = _cli(tmp_path, "--alias", "nope", "--alias", "free", "--alias", "openai:gpt-x", "--json")
    assert r.returncode == 0, r.stderr
    rows = [json.loads(line) for line in r.stdout.splitlines()]
    assert rows[0]["pricing_source"] == "unknown" and rows[0]["input_per_mtok"] is None
    assert rows[1]["pricing_source"] == "config" and rows[1]["input_per_mtok"] == 0 and rows[1]["output_per_mtok"] == 0
    assert rows[2]["input_per_mtok"] == 5000000 and rows[2]["provider"] == "openai"


def test_cli_project_config_overlays_the_catalog(tmp_path):
    project = ("hounfour:\n  providers:\n    local:\n      models:\n        lm:\n"
               "          pricing: {input_per_mtok: 100, output_per_mtok: 200}\n  aliases:\n    mine: local:lm\n")
    r = _cli(tmp_path, "--alias", "mine", project=project)
    assert r.returncode == 0, r.stderr
    assert "input_per_mtok=100 output_per_mtok=200 pricing_source=config" in r.stdout


def test_cli_unreadable_catalog_is_a_usage_error(tmp_path):
    env = dict(os.environ, PYTHONPATH=str(ADAPTERS), PYTHONSAFEPATH="1")
    r = subprocess.run([sys.executable, "-W", "ignore::RuntimeWarning", "-m", "loa_cheval.metering.pricing",
                        "--catalog", str(tmp_path / "missing.yaml"), "--alias", "x"],
                       capture_output=True, text=True, env=env, cwd=str(tmp_path), timeout=60)
    assert r.returncode == 2
    assert "cannot read the catalog" in r.stderr


def test_lookup_alias_against_the_live_catalog():
    """The budget gate's default primary resolves to a real catalog price (no fallback on a stock config)."""
    from loa_cheval.metering.pricing import load_pricing_config
    cfg = load_pricing_config(str(CATALOG), None)
    row = lookup_alias("gpt-5.3-codex", cfg)
    assert row["pricing_source"] == "config"
    assert row["input_per_mtok"] and row["output_per_mtok"]
