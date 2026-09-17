"""cycle-124 FR-6 — cost-ledger path resolution + test isolation (AC-6.1).

Pins ``resolve_cost_ledger_path`` precedence and path safety (sprint Flatline
SKP-003: canonicalized, symlink target rejected, parent must exist, traversal
collapsed) and proves the ``conftest.py`` autouse fixture keeps the repo's two
production ledgers byte-identical across a real ``--mock-fixture-dir`` cheval
run — the exact invocation that used to append ``mock-review`` rows to
``.run/cost-ledger.jsonl``.
"""

from __future__ import annotations

import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from loa_cheval.metering.ledger import (  # noqa: E402
    COST_LEDGER_ENV,
    DEFAULT_COST_LEDGER_PATH,
    append_ledger,
    resolve_cost_ledger_path,
)
from loa_cheval.metering.rollup import default_ledger_path  # noqa: E402
from loa_cheval.types import ConfigError  # noqa: E402

PROJECT_ROOT = Path(__file__).resolve().parents[3]
CHEVAL = PROJECT_ROOT / ".claude" / "adapters" / "cheval.py"
MOCK_FIXTURE_DIR = PROJECT_ROOT / "tests" / "fixtures" / "cycle-109" / "mock-mode" / "review"
PRODUCTION_LEDGERS = (
    PROJECT_ROOT / ".run" / "cost-ledger.jsonl",
    PROJECT_ROOT / ".run" / "model-invoke.jsonl",
)
MODELINV_ENV = "LOA_MODELINV_LOG_PATH"


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest() if path.exists() else "<absent>"


def _real(path: Path) -> str:
    return os.path.realpath(str(path))


# ---------------------------------------------------------------------------
# Precedence: env > metering.ledger_path > default
# ---------------------------------------------------------------------------


class TestPrecedence:
    def test_env_override_wins(self, monkeypatch, tmp_path):
        env_path = tmp_path / "env-ledger.jsonl"
        monkeypatch.setenv(COST_LEDGER_ENV, str(env_path))
        resolved = resolve_cost_ledger_path({"ledger_path": str(tmp_path / "cfg.jsonl")})
        assert resolved == _real(env_path)
        # Readers consult the same precedence (rollup default, cost-report.sh
        # is pinned by tests/unit/cheval-cost-rollup.bats).
        assert default_ledger_path() == str(env_path)

    def test_falls_back_to_config_when_env_unset(self, monkeypatch, tmp_path):
        monkeypatch.delenv(COST_LEDGER_ENV, raising=False)
        cfg_path = tmp_path / "cfg-ledger.jsonl"
        assert resolve_cost_ledger_path({"ledger_path": str(cfg_path)}) == _real(cfg_path)
        # Empty config value is "unset", not "the empty path".
        monkeypatch.chdir(tmp_path)
        assert resolve_cost_ledger_path({"ledger_path": ""}) == _real(tmp_path / DEFAULT_COST_LEDGER_PATH)

    def test_default_when_neither(self, monkeypatch, tmp_path):
        monkeypatch.delenv(COST_LEDGER_ENV, raising=False)
        monkeypatch.chdir(tmp_path)
        expected = _real(tmp_path / ".run" / "cost-ledger.jsonl")
        assert DEFAULT_COST_LEDGER_PATH == ".run/cost-ledger.jsonl"
        assert resolve_cost_ledger_path({}) == expected
        assert resolve_cost_ledger_path(None) == expected
        # Today's contract is kept for the default: no parent required at
        # resolve time (append_ledger creates .run/ on first write).
        assert not (tmp_path / ".run").exists()
        append_ledger({"probe": 1}, resolve_cost_ledger_path({}))
        assert (tmp_path / ".run" / "cost-ledger.jsonl").read_text().strip() == '{"probe":1}'


# ---------------------------------------------------------------------------
# Path safety (sprint Flatline SKP-003)
# ---------------------------------------------------------------------------


class TestPathSafety:
    def test_symlink_target_rejected(self, monkeypatch, tmp_path):
        real = tmp_path / "real.jsonl"
        real.write_text("")
        link = tmp_path / "link.jsonl"
        link.symlink_to(real)

        monkeypatch.setenv(COST_LEDGER_ENV, str(link))
        with pytest.raises(ConfigError) as excinfo:
            resolve_cost_ledger_path({})
        assert excinfo.value.code == "INVALID_CONFIG"
        assert "symlink" in str(excinfo.value)

        monkeypatch.delenv(COST_LEDGER_ENV)
        with pytest.raises(ConfigError):
            resolve_cost_ledger_path({"ledger_path": str(link)})

        # The writer refuses a symlink swapped in after validation (O_NOFOLLOW):
        # the open fails and the link target stays untouched.
        with pytest.raises(OSError):
            append_ledger({"probe": 1}, str(link))
        assert real.read_text() == ""

    def test_missing_parent_rejected(self, monkeypatch, tmp_path):
        missing = tmp_path / "nope" / "ledger.jsonl"

        monkeypatch.setenv(COST_LEDGER_ENV, str(missing))
        with pytest.raises(ConfigError) as excinfo:
            resolve_cost_ledger_path({})
        assert "parent directory" in str(excinfo.value)
        assert not (tmp_path / "nope").exists(), "validation must never mkdir"

        monkeypatch.delenv(COST_LEDGER_ENV)
        with pytest.raises(ConfigError):
            resolve_cost_ledger_path({"ledger_path": str(missing)})

    def test_traversal_is_canonicalized(self, monkeypatch, tmp_path):
        (tmp_path / "a" / "b").mkdir(parents=True)

        # Absolute with `..` collapses to the canonical parent.
        monkeypatch.setenv(COST_LEDGER_ENV, str(tmp_path / "a" / "b" / ".." / "ledger.jsonl"))
        resolved = resolve_cost_ledger_path({})
        assert resolved == _real(tmp_path / "a" / "ledger.jsonl")
        assert ".." not in resolved

        # Relative resolves against the working directory.
        monkeypatch.chdir(tmp_path)
        monkeypatch.setenv(COST_LEDGER_ENV, "a/./ledger.jsonl")
        assert resolve_cost_ledger_path({}) == _real(tmp_path / "a" / "ledger.jsonl")

        # Traversal out to a parent that does not exist is still rejected.
        monkeypatch.setenv(COST_LEDGER_ENV, "a/b/../../missing/ledger.jsonl")
        with pytest.raises(ConfigError):
            resolve_cost_ledger_path({})


# ---------------------------------------------------------------------------
# Isolation (AC-6.1)
# ---------------------------------------------------------------------------


class TestIsolation:
    def test_conftest_isolates_both_ledgers(self, tmp_path):
        for var in (COST_LEDGER_ENV, MODELINV_ENV):
            value = os.environ.get(var)
            assert value, f"{var} must be set by tests/conftest.py"
            assert value.startswith(str(tmp_path) + os.sep), (
                f"{var}={value!r} is not under this test's tmp_path — unset any "
                "shell-level export before running the adapter suite"
            )

    @pytest.mark.skipif(not MOCK_FIXTURE_DIR.is_dir(), reason="mock fixture dir absent")
    def test_mock_run_leaves_repo_ledgers_byte_identical(self):
        before = {str(p): _sha256(p) for p in PRODUCTION_LEDGERS}

        env = dict(os.environ, PROJECT_ROOT=str(PROJECT_ROOT), LOA_ADVISOR_STRATEGY_DISABLE="1")
        proc = subprocess.run(
            [
                sys.executable, str(CHEVAL),
                "--agent", "flatline-reviewer",
                "--prompt", "FR-6 ledger isolation probe",
                "--mock-fixture-dir", str(MOCK_FIXTURE_DIR),
                "--output-format", "json",
                "--json-errors",
            ],
            cwd=str(PROJECT_ROOT), env=env, capture_output=True, text=True, timeout=120,
        )
        assert proc.returncode == 0, proc.stderr

        after = {str(p): _sha256(p) for p in PRODUCTION_LEDGERS}
        assert after == before, f"production ledgers changed:\nbefore={before}\nafter={after}"

        # The run DID reach dispatch and DID write — to the isolated paths.
        cost_rows = [
            json.loads(line)
            for line in Path(os.environ[COST_LEDGER_ENV]).read_text().splitlines()
            if line.strip()
        ]
        assert cost_rows and cost_rows[-1]["model"] == "mock-review", cost_rows
        modelinv = Path(os.environ[MODELINV_ENV])
        assert modelinv.exists() and modelinv.stat().st_size > 0
