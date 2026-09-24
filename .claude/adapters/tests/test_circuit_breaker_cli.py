"""cycle-125 Sprint 4 (PRD FR-4 AC 1, SDD §1.5) — operator surface for provider
circuit breakers: `bucket_snapshot` arithmetic, `reset_bucket` (journal BEFORE
write), the `--list` / `--reset` CLI shapes, and OPEN → HALF_OPEN after the
cooldown. Everything runs against a temp run_dir; no network, no credentials.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import time
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from loa_cheval.routing.circuit_breaker import (  # noqa: E402
    CLOSED,
    HALF_OPEN,
    OPEN,
    bucket_snapshot,
    check_state,
    reset_bucket,
)


def _seed(run_dir: Path, provider: str, auth: str, state: str, opened_ago: float | None = None, failures: int = 0) -> Path:
    p = run_dir / f"circuit-breaker-{provider}-{auth}.json"
    payload = {"provider": provider, "auth_type": auth, "state": state, "failure_count": failures,
               "last_failure_ts": None, "opened_at": (time.time() - opened_ago) if opened_ago is not None else None,
               "half_open_probes": 0}
    p.write_text(json.dumps(payload))
    return p


def _cli(*argv: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, "-m", "loa_cheval.routing.breaker_cli", *argv],
        cwd=str(ROOT), capture_output=True, text=True,
        env={**os.environ, "PYTHONPATH": str(ROOT)},
    )


# --- snapshot -----------------------------------------------------------------

def test_snapshot_adds_age_and_probe_timing(tmp_path):
    _seed(tmp_path, "google", "http_api", OPEN, opened_ago=120, failures=5)
    _seed(tmp_path, "google", "headless", CLOSED)
    snap = bucket_snapshot(str(tmp_path), reset_timeout=300)
    g = snap["buckets"]["google"]
    assert snap["reset_timeout_seconds"] == 300
    assert g["http_api"]["state"] == OPEN and 119 <= g["http_api"]["age_s"] <= 125
    assert 175 <= g["http_api"]["probe_due_in_s"] <= 181
    assert g["headless"]["age_s"] is None and g["headless"]["probe_due_in_s"] is None


def test_snapshot_probe_due_is_zero_once_the_cooldown_elapsed(tmp_path):
    _seed(tmp_path, "openai", "http_api", OPEN, opened_ago=600, failures=3)
    snap = bucket_snapshot(str(tmp_path), reset_timeout=60)
    assert snap["buckets"]["openai"]["http_api"]["probe_due_in_s"] == 0


def test_snapshot_never_mutates_state_and_ignores_symlinks(tmp_path):
    p = _seed(tmp_path, "openai", "http_api", OPEN, opened_ago=600)
    before = p.read_text()
    os.symlink(p.name, tmp_path / "circuit-breaker-openai.json")
    snap = bucket_snapshot(str(tmp_path), reset_timeout=60)
    assert list(snap["buckets"]["openai"].keys()) == ["http_api"]
    assert p.read_text() == before


# --- OPEN → HALF_OPEN after cooldown (expiry surfaced) --------------------------

def test_check_state_moves_open_to_half_open_after_reset_timeout(tmp_path):
    _seed(tmp_path, "anthropic", "http_api", OPEN, opened_ago=120, failures=5)
    cfg = {"routing": {"circuit_breaker": {"reset_timeout_seconds": 60}}}
    assert bucket_snapshot(str(tmp_path), 60)["buckets"]["anthropic"]["http_api"]["probe_due_in_s"] == 0
    assert check_state("anthropic", "http_api", cfg, str(tmp_path)) == HALF_OPEN
    on_disk = json.loads((tmp_path / "circuit-breaker-anthropic-http_api.json").read_text())
    assert on_disk["state"] == HALF_OPEN and on_disk["half_open_probes"] == 0


def test_check_state_keeps_open_before_reset_timeout(tmp_path):
    _seed(tmp_path, "anthropic", "http_api", OPEN, opened_ago=10, failures=5)
    cfg = {"routing": {"circuit_breaker": {"reset_timeout_seconds": 3600}}}
    assert check_state("anthropic", "http_api", cfg, str(tmp_path)) == OPEN


# --- reset ----------------------------------------------------------------------

def test_reset_bucket_journals_before_writing_default_state(tmp_path):
    p = _seed(tmp_path, "google", "http_api", OPEN, opened_ago=120, failures=5)
    done = reset_bucket("google", "http_api", str(tmp_path), reason="test reset")
    assert done == ["google/http_api"]
    state = json.loads(p.read_text())
    assert state["state"] == CLOSED and state["failure_count"] == 0 and state["opened_at"] is None
    journal = (tmp_path / "substrate-health-journal.jsonl").read_text().splitlines()
    marker = json.loads(journal[-1])
    assert marker["marker"] == "operator_reset"
    assert marker["provider"] == "google" and marker["auth_type"] == "http_api"
    assert marker["previous_state"] == OPEN and marker["previous_failure_count"] == 5
    assert marker["reason"] == "test reset"
    # journal entry precedes the state write
    assert marker["ts"] <= os.stat(p).st_mtime + 0.001


def test_reset_bucket_without_auth_type_resets_every_bucket_of_the_provider(tmp_path):
    _seed(tmp_path, "google", "http_api", OPEN, opened_ago=120, failures=5)
    _seed(tmp_path, "google", "headless", OPEN, opened_ago=60, failures=2)
    _seed(tmp_path, "openai", "http_api", OPEN, opened_ago=60, failures=2)
    done = reset_bucket("google", None, str(tmp_path))
    assert sorted(done) == ["google/headless", "google/http_api"]
    assert json.loads((tmp_path / "circuit-breaker-openai-http_api.json").read_text())["state"] == OPEN


def test_reset_bucket_never_fabricates_a_bucket_that_does_not_exist(tmp_path):
    """Dissent DISS-001: an explicit auth_type with no state file must not create one."""
    _seed(tmp_path, "google", "headless", OPEN, opened_ago=60, failures=2)
    assert reset_bucket("google", "http_api", str(tmp_path)) == []
    assert not (tmp_path / "circuit-breaker-google-http_api.json").exists()
    assert not (tmp_path / "substrate-health-journal.jsonl").exists()
    r = _cli("--reset", "google:http_api", "--run-dir", str(tmp_path))
    assert r.returncode == 1 and "nothing matched" in r.stdout
    # the existing bucket still resets
    assert reset_bucket("google", "headless", str(tmp_path)) == ["google/headless"]


def test_reset_bucket_rejects_bad_names(tmp_path):
    with pytest.raises(ValueError):
        reset_bucket("Goo gle", "http_api", str(tmp_path))
    with pytest.raises(ValueError):
        reset_bucket("google", "ssh", str(tmp_path))
    assert reset_bucket("nobody", None, str(tmp_path)) == []


# --- CLI ------------------------------------------------------------------------

def test_cli_list_text_and_json(tmp_path):
    _seed(tmp_path, "google", "http_api", OPEN, opened_ago=7200, failures=5)
    _seed(tmp_path, "openai", "headless", CLOSED)
    r = _cli("--list", "--run-dir", str(tmp_path), "--reset-timeout", "60")
    assert r.returncode == 0, r.stderr
    assert "RuntimeWarning" not in r.stderr
    lines = r.stdout.splitlines()
    assert any(l.startswith("google/http_api") and "OPEN" in l and "open 2h" in l and "probe overdue" in l for l in lines)
    assert any(l.startswith("openai/headless") and "CLOSED" in l for l in lines)
    r = _cli("--list", "--json", "--run-dir", str(tmp_path), "--reset-timeout", "60")
    data = json.loads(r.stdout)
    assert data["reset_timeout_seconds"] == 60
    assert data["buckets"]["google"]["http_api"]["state"] == OPEN
    assert data["buckets"]["google"]["http_api"]["probe_due_in_s"] == 0
    assert set(data["buckets"]["google"]["http_api"]) >= {"state", "failure_count", "opened_at", "age_s", "probe_due_in_s"}


def test_cli_list_empty_dir_and_usage(tmp_path):
    r = _cli("--list", "--run-dir", str(tmp_path))
    assert r.returncode == 0 and "no circuit-breaker buckets" in r.stdout
    r = _cli("--run-dir", str(tmp_path))
    assert r.returncode == 2
    r = _cli("--list", "--reset", "google", "--run-dir", str(tmp_path))
    assert r.returncode == 2


def test_cli_reset_json_and_exit_codes(tmp_path):
    _seed(tmp_path, "google", "http_api", OPEN, opened_ago=120, failures=5)
    r = _cli("--reset", "google:http_api", "--json", "--reason", "cli test", "--run-dir", str(tmp_path))
    assert r.returncode == 0, r.stderr
    assert json.loads(r.stdout) == {"reset": ["google/http_api"], "reason": "cli test"}
    r = _cli("--reset", "google:http_api", "--run-dir", str(tmp_path))
    assert r.returncode == 0  # resetting a CLOSED bucket is a no-op reset, still journaled
    r = _cli("--reset", "nobody", "--run-dir", str(tmp_path))
    assert r.returncode == 1 and "nothing matched" in r.stdout
    r = _cli("--reset", "bad name", "--run-dir", str(tmp_path))
    assert r.returncode == 2


def test_cli_output_carries_no_credential_values(tmp_path, monkeypatch):
    monkeypatch.setenv("OPENAI_API_KEY", "sk-test-should-never-appear")
    _seed(tmp_path, "openai", "http_api", OPEN, opened_ago=5)
    r = subprocess.run([sys.executable, "-m", "loa_cheval.routing.breaker_cli", "--list", "--json", "--run-dir", str(tmp_path)],
                       cwd=str(ROOT), capture_output=True, text=True, env={**os.environ, "PYTHONPATH": str(ROOT)})
    assert "sk-test-should-never-appear" not in r.stdout + r.stderr
