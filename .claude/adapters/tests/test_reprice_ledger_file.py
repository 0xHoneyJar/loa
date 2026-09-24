"""sprint-bug-245 audit round 1 (F-1, F-2, F-3) — the file half of the
re-pricing pass: the writer's lock and an in-place rewrite (no orphaned
inode), exclusive no-follow creation of the backup and the receipt, refusal
of a symlinked ledger, and no row-supplied pricing authority.
"""
from __future__ import annotations

import fcntl
import json
import os
import sys
import threading
import time
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from loa_cheval.metering.ledger import append_ledger  # noqa: E402
from loa_cheval.metering.reprice import RepriceRefused, reprice_ledger_file, reprice_rows  # noqa: E402

CONFIG = {
    "providers": {
        "openai": {
            "models": {
                "gpt-5.5": {"pricing": {"input_per_mtok": 2_000_000, "output_per_mtok": 8_000_000}},
                "codex-headless": {"kind": "cli", "extra": {"cli_model": "gpt-5.5"}},
            }
        }
    },
    "aliases": {},
}
NOW = "2026-09-24T02:00:00Z"
STAMP = "20260924T020000Z"

UNKNOWN = '{"ts":"2026-09-22T09:00:00.000Z","request_id":"u1","provider":"openai","model":"codex-headless","tokens_in":1000,"tokens_out":100,"cost_micro_usd":0,"pricing_source":"unknown"}\n'
PRICED = '{"ts":"2026-09-22T09:03:00.000Z","request_id":"p1","provider":"openai","model":"gpt-5.5","tokens_in":10,"tokens_out":1,"cost_micro_usd":900,"pricing_source":"config","pricing_resolution":"exact"}\n'
CORRUPT = "not json at all\n"


def write_ledger(path: Path, text: str = UNKNOWN + PRICED + CORRUPT) -> None:
    path.write_bytes(text.encode("utf-8"))


def test_rewrites_the_same_inode_in_place_and_keeps_untouched_lines_verbatim(tmp_path):
    ledger = tmp_path / "ledger.jsonl"
    write_ledger(ledger)
    inode_before = ledger.stat().st_ino
    receipt = reprice_ledger_file(str(ledger), str(tmp_path / "run"), CONFIG, NOW, stamp=STAMP)
    assert ledger.stat().st_ino == inode_before, "the pass must not replace the inode"
    lines = ledger.read_bytes().split(b"\n")
    assert json.loads(lines[0])["pricing_source"] == "config" and json.loads(lines[0])["repriced_at"] == NOW
    assert lines[1] + b"\n" == PRICED.encode() and lines[2] + b"\n" == CORRUPT.encode()
    assert receipt["rows_repriced"] == 1 and receipt["corrupt_lines_preserved"] == 1
    assert receipt["backup"] == str(ledger) + f".pre-reprice-{STAMP}"
    assert Path(receipt["backup"]).read_text() == UNKNOWN + PRICED + CORRUPT
    assert receipt["sha256_before"] != receipt["sha256_after"]
    assert Path(receipt["receipt_path"]).name == f"cost-ledger-reprice-{STAMP}.json"
    on_disk = json.loads(Path(receipt["receipt_path"]).read_text())
    assert on_disk["writer"].endswith("reprice_rows") and "tokens_in" not in json.dumps(on_disk)


def test_holds_the_writers_lock_and_a_later_append_survives(tmp_path):
    ledger = tmp_path / "ledger.jsonl"
    write_ledger(ledger)
    # a writer holds the ledger's flock: the pass must block until it is released
    holder = os.open(str(ledger), os.O_RDWR)
    fcntl.flock(holder, fcntl.LOCK_EX)
    result = {}

    def run():
        result["receipt"] = reprice_ledger_file(str(ledger), str(tmp_path / "run"), CONFIG, NOW, stamp=STAMP)

    t = threading.Thread(target=run)
    t.start()
    t.join(timeout=0.5)
    assert t.is_alive(), "the pass ran without the writer's lock"
    fcntl.flock(holder, fcntl.LOCK_UN)
    os.close(holder)
    t.join(timeout=10)
    assert not t.is_alive() and result["receipt"]["rows_repriced"] == 1
    # a row appended through the real writer after the pass lands after the new content
    append_ledger({"request_id": "after", "provider": "openai", "model": "gpt-5.5", "tokens_in": 1, "tokens_out": 1, "cost_micro_usd": 5, "pricing_source": "config"}, str(ledger))
    rows = [json.loads(l) for l in ledger.read_text().splitlines() if l.startswith("{")]
    assert [r["request_id"] for r in rows] == ["u1", "p1", "after"]


def test_dry_run_locks_shared_and_writes_nothing(tmp_path):
    ledger = tmp_path / "ledger.jsonl"
    write_ledger(ledger)
    before = ledger.read_bytes()
    receipt = reprice_ledger_file(str(ledger), str(tmp_path / "run"), CONFIG, NOW, dry_run=True, stamp=STAMP)
    assert receipt["dry_run"] is True and receipt["rows_repriced"] == 1 and "receipt_path" not in receipt
    assert ledger.read_bytes() == before
    assert not (tmp_path / "run").exists()
    assert not list(tmp_path.glob("*.pre-reprice-*"))


def test_backup_and_receipt_never_follow_a_planted_symlink(tmp_path):
    ledger = tmp_path / "ledger.jsonl"
    write_ledger(ledger)
    victim = tmp_path / "victim.txt"
    run_dir = tmp_path / "run"
    run_dir.mkdir()
    # dangling symlinks planted at the computed backup name and the computed receipt name
    os.symlink(str(victim), str(ledger) + f".pre-reprice-{STAMP}")
    receipt_victim = tmp_path / "receipt-victim.json"
    os.symlink(str(receipt_victim), str(run_dir / f"cost-ledger-reprice-{STAMP}.json"))
    receipt = reprice_ledger_file(str(ledger), str(run_dir), CONFIG, NOW, stamp=STAMP)
    assert not victim.exists() and not receipt_victim.exists(), "a planted symlink was followed"
    assert receipt["backup"] == str(ledger) + f".pre-reprice-{STAMP}-2"
    assert Path(receipt["backup"]).read_text() == UNKNOWN + PRICED + CORRUPT
    assert Path(receipt["receipt_path"]).name == f"cost-ledger-reprice-{STAMP}-2.json"
    assert os.path.islink(str(ledger) + f".pre-reprice-{STAMP}")  # the plant is left alone


def test_symlinked_ledger_is_refused_before_any_write(tmp_path):
    real = tmp_path / "real.jsonl"
    write_ledger(real)
    link = tmp_path / "link.jsonl"
    os.symlink(str(real), str(link))
    before = real.read_bytes()
    with pytest.raises(RepriceRefused):
        reprice_ledger_file(str(link), str(tmp_path / "run"), CONFIG, NOW, stamp=STAMP)
    assert real.read_bytes() == before and not (tmp_path / "run").exists()
    with pytest.raises(FileNotFoundError):
        reprice_ledger_file(str(tmp_path / "missing.jsonl"), str(tmp_path / "run"), CONFIG, NOW)


def test_second_pass_reprices_nothing_and_makes_no_backup(tmp_path):
    ledger = tmp_path / "ledger.jsonl"
    write_ledger(ledger)
    first = reprice_ledger_file(str(ledger), str(tmp_path / "run"), CONFIG, NOW, stamp=STAMP)
    after = ledger.read_bytes()
    second = reprice_ledger_file(str(ledger), str(tmp_path / "run"), CONFIG, "2026-09-25T00:00:00Z", stamp=STAMP)
    assert second["rows_repriced"] == 0 and second["backup"] is None and second["sha256_before"] == second["sha256_after"]
    assert ledger.read_bytes() == after
    assert len(list(tmp_path.glob("ledger.jsonl.pre-reprice-*"))) == 1
    assert Path(second["receipt_path"]).name == f"cost-ledger-reprice-{STAMP}-2.json" and first["receipt_path"] != second["receipt_path"]


def test_row_supplied_resolved_model_is_not_a_pricing_authority():
    row = {"provider": "openai", "model": "not-in-catalog", "resolved_model": "gpt-5.5", "tokens_in": 5, "tokens_out": 5, "cost_micro_usd": 0, "pricing_source": "unknown"}
    out, stats = reprice_rows([row], CONFIG, NOW)
    assert out[0] is row and stats["rows_still_unpriced"] == 1
